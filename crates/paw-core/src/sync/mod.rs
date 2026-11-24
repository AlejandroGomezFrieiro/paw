//! Turns the difference between two project snapshots into engine messages and
//! change events.
//!
//! This is the only place that tells the engine what the project looks like.
//! Edits, undo, loading a project and offline rendering all end up here, so
//! none of them can leave the engine out of step with the model.
//!
//! [`sync`] takes its steps in a fixed order, which the engine relies on: a
//! part is there before its devices and clips, the schedule comes after the
//! parts and devices it names, and what is removed goes last.
//!
//! - `mapper.rs`: the slots and what the engine was last sent;
//! - `audio.rs`: decoded files, shared between clips;
//! - `devices.rs`: devices made, updated and given their files;
//! - `clips.rs`: clips compiled and sent whole or in parts;
//! - `stacks.rs`: what a clip with a modifier stack plays, kept by key;
//! - `automation.rs`: lanes, VCA faders, and what a lane gives back;
//! - `routing.rs`: outputs, sends, side-chains, solo and the schedule;
//! - `items.rs`: the events of clips and lanes added, changed or removed.

mod audio;
mod automation;
mod chains;
mod clips;
mod devices;
mod items;
mod mapper;
mod nests;
pub(crate) use nests::passes;
mod routing;
mod stacks;
#[cfg(test)]
mod tests;

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use paw_engine::launch::Slots;
use paw_engine::{ClipSet, Controller, Msg, ParamInfo, Registry, PartRt, PartSlot, db_to_gain};
use paw_types::midi_form::Form;

pub use self::audio::AudioCache;
pub(crate) use self::automation::is_active;
pub(crate) use self::devices::{TakesClips, deliver_clips, install, is_host};
pub use self::mapper::Mapper;
pub(crate) use self::mapper::Follow;
pub(crate) use self::clips::repeats;
pub use crate::events::ModelEvent;

use self::automation::{build_automation, release_targets, vca_volume_lane, vcas_of};
use self::clips::{build_clips, build_cues, cue_rows, edit_pieces, frozen_clips};
use self::devices::{add_device, update_device};
use self::items::{PartIndex, item_events};
use self::mapper::{InputSent, MidiInSent, MidiOutSent, MixSent};
use self::routing::{build_schedule, routing_of, solo_paths, soloed_parts};
use crate::events::{Cue, Item, KernelEvent as E, Nothing, Order, PartChange, PartId};
use crate::freeze::Played;
use crate::model::{DeviceInst, Id, MASTER_ID, Project, Part};

/// What is kept on the main thread for a device the engine is running.
pub struct LiveDevice {
    /// The parameters of this instance, in the order the device numbers them.
    pub params: Arc<Vec<ParamInfo>>,
    /// The main-thread side of the device, for hosted plugins.
    pub controller: Option<Box<dyn Controller>>,
    /// Frames by which the device's output is behind its input.
    pub latency: u32,
    /// Why the device has stopped working, once it has (see
    /// [`Controller::health`]).
    pub stopped: Option<String>,
    /// It keeps files beside its state (an attachment took the plugin): it
    /// answered [`paw_engine::device::FILE_LOAD`] when it was made.
    pub attached: bool,
    /// Whether it takes its part's clips, and what it was given.
    pub(crate) clips: TakesClips,
    /// The states given to it since it was made ([`load_state`](Self::load_state)),
    /// and the number of the last that the session told it took on
    /// (`device.state_applied`). `states_told` is never more than
    /// `states_given`.
    pub(crate) states_given: u64,
    pub(crate) states_told: u64,
}

impl LiveDevice {
    /// Give the running device a whole state, as its controller saved it.
    /// The session tells when it took it on (`device.state_applied`).
    pub(crate) fn load_state(&mut self, state: &[u8]) -> anyhow::Result<()> {
        let controller = self
            .controller
            .as_mut()
            .ok_or_else(|| anyhow::anyhow!("the device takes no saved state"))?;
        controller.load_state(state)?;
        self.states_given += 1;
        Ok(())
    }

    /// The number of the last state given that the device took on, once,
    /// when it is newer than the last told: a device takes a state on when
    /// no state is pending in its controller.
    pub(crate) fn take_state_applied(&mut self) -> Option<u64> {
        let pending = self.controller.as_ref().is_some_and(|c| c.state_pending());
        if self.states_told == self.states_given || pending {
            return None;
        }
        self.states_told = self.states_given;
        Some(self.states_told)
    }
}

pub type LiveDevices = HashMap<Id, LiveDevice>;

pub struct SyncCtx<'a> {
    pub registry: &'a Registry,
    /// The hashes of the files, which name stretched versions.
    pub sources: &'a crate::media::Sources,
    pub audio: &'a mut AudioCache,
    pub live: &'a mut LiveDevices,
    pub sample_rate: f32,
    pub warnings: &'a mut Vec<String>,
    /// The engine being built renders to a file, not to be heard as it plays.
    pub offline: bool,
    /// Wakes the engine from rest: each new device keeps it
    /// ([`Controller::set_waker`](paw_engine::Controller::set_waker)), and
    /// a state given to a device wakes it.
    pub waker: paw_engine::Waker,
    /// Tells the kernel's loop that a plugin asked for a call on the main
    /// thread: each new controller keeps it
    /// ([`Controller::set_bell`](paw_engine::Controller::set_bell)).
    pub bell: paw_engine::Bell,
    /// The schedule time of the turn: a bake asked for waits its settle
    /// from it.
    pub now: crate::clock::ScheduleTime,
    /// The kinds of split, which tell how each split of a chain plays.
    pub kinds: &'a crate::model::chain::SplitKinds,
    /// The kinds of modifier, which run the stack of each clip.
    pub modifiers: &'a crate::model::modifiers::ModKinds,
}

/// Bring the engine from `old` to `new`.
pub fn sync(
    old: &Project,
    new: &Project,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
    send: &mut dyn FnMut(Msg),
    events: &mut Vec<ModelEvent>,
) {
    let before = events.len();
    // Nest parts play their clips placed in the song (`nests.rs`).
    let placed = nests::Placed::of(new);
    let old_shown: HashMap<Id, Arc<Part>> =
        map.expanded.iter().map(|(id, e)| (*id, e.part.clone())).collect();
    let shown = nests::expand(new, &placed, std::mem::take(&mut map.expanded));
    let mut pass = Pass {
        shown: &shown,
        old_shown: &old_shown,
        placed: &placed,
        old_parts: old.all_parts().map(|t| (t.id, t)).collect(),
        old_devices: old
            .all_parts()
            .flat_map(|t| t.devices.iter().map(move |d| (d.id, (t.id, d))))
            .collect(),
        old,
        new,
        map,
        ctx,
        send,
        events,
        removals: Vec::new(),
        clips_changed: false,
        lanes_changed: false,
        new_slots: false,
        device_slots: false,
    };
    let retimed = pass.project();
    pass.parts(retimed);
    pass.removed_devices();
    pass.item_events();
    pass.vca_lanes();
    pass.mix();
    pass.inputs();
    pass.device_latency();
    pass.routing();
    pass.local_times();
    pass.removed_parts();
    let Pass { ctx, send, removals, map, .. } = pass;
    // Removals go last, once nothing in the schedule or a chain refers to them.
    removals.into_iter().for_each(&mut *send);

    deliver_clips(new, ctx);
    map.expanded = shown;

    if events.len() > before {
        events.push(E::changed().into());
    }
}

/// One [`sync`]: the two snapshots, where the messages and events go, and
/// what the steps tell each other.
struct Pass<'p, 'm, 'c> {
    /// The nest parts as the engine plays them, now and at the last sync.
    shown: &'p nests::ExpandedParts,
    old_shown: &'p HashMap<Id, Arc<Part>>,
    /// Where each nest plays, and the part its master plays into.
    placed: &'p nests::Placed,
    old: &'p Project,
    new: &'p Project,
    old_parts: PartIndex<'p>,
    /// Each device of the old snapshot, with the part it was on.
    old_devices: HashMap<Id, (Id, &'p Arc<DeviceInst>)>,
    map: &'m mut Mapper,
    ctx: &'m mut SyncCtx<'c>,
    send: &'m mut dyn FnMut(Msg),
    events: &'m mut Vec<ModelEvent>,
    /// Sent last, once nothing in the schedule or a chain refers to them.
    removals: Vec<Msg>,
    clips_changed: bool,
    lanes_changed: bool,
    /// The schedule lists slots, so a part that gets one needs a new schedule.
    new_slots: bool,
    /// Side-chains name device slots, so a device that gets one does too.
    device_slots: bool,
}

/// How a part plays now and what it was before, worked out once for its
/// steps.
struct PartPass<'p> {
    /// The same part in the old snapshot, unless it only now got a slot.
    prev: Option<&'p Arc<Part>>,
    slot: PartSlot,
    plays: Played,
    /// It plays otherwise than the engine was last told (frozen, held, live).
    replayed: bool,
    /// Notes an attribute map moves by seconds land by the tempo map.
    retimed_notes: bool,
}

impl<'p> Pass<'p, '_, '_> {
    fn emit(&mut self, event: E) {
        self.events.push(event.into());
    }

    /// The tempo map and the project's own events. Whether the song was
    /// retimed.
    fn project(&mut self) -> bool {
        let (old, new) = (self.old, self.new);
        // A project's map is shared by its copies, so an unchanged map is the
        // very same one. One out of step with its fields (set directly rather
        // than through `set_tempo_map`) is built again from them.
        let current = new.tempo_is_current();
        let retimed = !Arc::ptr_eq(old.tempo_map(), new.tempo_map()) || !current;
        if retimed {
            let map = if current {
                (**new.tempo_map()).clone()
            } else {
                paw_types::TempoMap::new(&new.tempo_points(), &new.sig_points())
            };
            (self.send)(Msg::SetTempoMap(Box::new(map)));
        }
        if retimed || old.name != new.name || old.meta != new.meta {
            self.emit(E::ProjectChanged(Nothing {}));
        }
        // The same parts in another order: nothing the engine needs to hear of,
        // but whoever draws the part list does.
        if old.parts.len() == new.parts.len()
            && old.parts.iter().zip(&new.parts).any(|(a, b)| a.id != b.id)
        {
            let order: Vec<Id> = new.parts.iter().map(|t| t.id).collect();
            self.emit(E::PartMoved(Order { order }));
        }
        retimed
    }

    /// Each part that changed, whole: its slot, devices, clips, cues and
    /// lanes.
    fn parts(&mut self, retimed: bool) {
        // Frozen parts play a file, and what feeds them is held.
        let new = self.new;
        let mut played = crate::freeze::played(new, &self.map.held_files);
        // A nest that only frozen blocks place rests, as what feeds a
        // frozen part does.
        for nest in self.placed.resting() {
            for t in new.nest_parts(nest) {
                played.entry(t.id).or_insert(Played::Held);
            }
        }
        let (shown, old_shown) = (self.shown, self.old_shown);
        for part in new.all_parts() {
            let plays = played.remove(&part.id);
            // A nest part plays a copy of its clips for each place of its
            // nest; a row also the clips of the parts in pass mode it holds.
            let now = shown.get(&part.id).map(|e| &e.part);
            let was = old_shown.get(&part.id);
            let moved = match (now, was) {
                (Some(a), Some(b)) => !Arc::ptr_eq(a, b),
                (None, None) => false,
                _ => true,
            };
            let Some(pass) = self.part_slot(part, plays.clone().unwrap_or(Played::Live), retimed, moved)
            else {
                continue;
            };
            let same_chain = self.part_devices(part, &pass);
            // A frozen or held part's devices are held in the engine only: the
            // model keeps its own bypass, which comes back when it thaws.
            let held = pass.plays != Played::Live;
            if held || pass.replayed {
                for device in &part.devices {
                    if let Some(&device_slot) = self.map.devices.get(&device.id) {
                        (self.send)(Msg::SetBypass {
                            device: device_slot,
                            bypass: device.bypass || held,
                        });
                    }
                }
            }
            // What the engine has: the part as it was played, when it was
            // expanded then or is now.
            let prev = match (now, was) {
                (None, None) => pass.prev.map(|t| &**t),
                _ => pass.prev.and(was).map(|t| &**t),
            };
            self.part_clips(now.unwrap_or(part), prev, &pass);
            self.part_cues(part, &pass, held);
            match plays {
                Some(plays) => self.map.played.insert(part.id, plays),
                None => self.map.played.remove(&part.id),
            };
            // A nest part's lanes play at the places of its nest, as its clips do.
            self.part_lanes(now.map_or(part, |t| &**t), prev, &pass, same_chain);
        }
    }

    /// Whether a part needs looking at, its slot (made now for a new
    /// part) and its events. `None` for a part that did not change, or
    /// that the engine has no room for.
    fn part_slot(
        &mut self,
        part: &'p Arc<Part>,
        plays: Played,
        retimed: bool,
        moved: bool,
    ) -> Option<PartPass<'p>> {
        let prev = self.old_parts.get(&part.id).copied();
        // A part the engine had no room for is built whole once there is room.
        let fresh = !self.map.parts.contains_key(&part.id);
        let retimed_notes = retimed && part.attr_map.as_ref().is_some_and(|m| m.has_delay());
        let replayed = self.map.played.get(&part.id).unwrap_or(&Played::Live) != &plays;
        if !fresh && !replayed && !retimed_notes && !moved && prev.is_some_and(|p| Arc::ptr_eq(p, part)) {
            return None;
        }
        if fresh {
            let Some(slot) = self.map.alloc_part() else {
                if prev.is_none() {
                    self.ctx
                        .warnings
                        .push(format!("too many parts: `{}` will be silent", part.name));
                }
                return None;
            };
            self.map.parts.insert(part.id, slot);
            self.new_slots = true;
            (self.send)(Msg::InsertPart {
                slot,
                part: PartRt::new(),
            });
        }
        match prev {
            None => self.emit(E::PartAdded(PartId { id: part.id })),
            Some(p) if !Arc::ptr_eq(p, part) => self.emit(E::PartChanged(PartChange {
                id: part.id,
                fields: part.changed_fields(p),
            })),
            Some(_) => {}
        }
        Some(PartPass {
            // From here on, a part that has only now got a slot counts as new.
            prev: prev.filter(|_| !fresh),
            slot: *self.map.parts.get(&part.id)?,
            plays,
            replayed,
            retimed_notes,
        })
    }

    /// A part's devices added, set offline or back, or changed, and the
    /// plan of its chain sent again when it changed. Whether the devices
    /// are the same, in the same order.
    fn part_devices(&mut self, part: &Part, pass: &PartPass) -> bool {
        // Devices set offline or back online since: gone from the engine,
        // or made, and the chain sent again.
        let mut toggled = false;
        for device in &part.devices {
            let item = Item::on(device.id, Some(part.id));
            match self.old_devices.get(&device.id).map(|&(_, d)| d).filter(|_| pass.prev.is_some()) {
                Some(before) if before.offline != device.offline => {
                    toggled = true;
                    self.device_slots = true;
                    self.map.keyed.remove(&device.id);
                    self.map.outs.remove(&device.id);
                    if device.offline {
                        self.ctx.live.remove(&device.id);
                        self.map.free_device(device.id, &mut self.removals);
                    } else {
                        add_device(device, self.map, self.ctx, self.send);
                    }
                    self.emit(E::DeviceChanged(item));
                }
                None => {
                    add_device(device, self.map, self.ctx, self.send);
                    self.device_slots = true;
                    if !self.old_devices.contains_key(&device.id) {
                        self.emit(E::DeviceAdded(item));
                    }
                }
                Some(before) if !Arc::ptr_eq(before, device) => {
                    update_device(before, device, self.map, self.ctx, self.send);
                    self.emit(E::DeviceChanged(item));
                }
                Some(_) => {}
            }
        }
        let same_chain = !toggled
            && pass.prev.is_some_and(|p| {
                p.devices
                    .iter()
                    .map(|d| d.id)
                    .eq(part.devices.iter().map(|d| d.id))
            });
        self.send_plan(part, pass.slot, pass.plays != Played::Live, pass.prev.is_none());
        same_chain
    }

    /// A part's clips on the timeline: the parts an edit changed, or all
    /// of them. `prev` is what the engine has of them (for a nest part,
    /// its clips as they were placed).
    fn part_clips(&mut self, part: &Part, prev: Option<&Part>, pass: &PartPass) {
        let same_clips = !pass.retimed_notes
            && prev.is_some_and(|p| p.attr_map == part.attr_map && p.clips.same(&part.clips));
        if !same_clips {
            self.clips_changed = true;
        }
        if same_clips && !pass.replayed {
            return;
        }
        let tempo = self.new.tempo_map();
        // A few clips changed: the engine is sent only theirs.
        let edit = match (&pass.plays, prev) {
            (Played::Live, Some(p))
                if !pass.replayed && !pass.retimed_notes && p.attr_map == part.attr_map =>
            {
                edit_pieces(p, part, tempo, self.map, self.ctx)
            }
            _ => None,
        };
        let msg = match edit {
            Some(edit) => Msg::EditClips {
                part: pass.slot,
                edit: Box::new(edit),
            },
            None => {
                let clips = match &pass.plays {
                    Played::Live => build_clips(part, tempo, self.map, self.ctx),
                    Played::Frozen(file) => {
                        self.map.pieces.remove(&part.id);
                        frozen_clips(file, tempo, self.ctx)
                    }
                    Played::Held => {
                        self.map.pieces.remove(&part.id);
                        ClipSet::default()
                    }
                };
                Msg::SetClips {
                    part: pass.slot,
                    clips: Box::new(clips),
                }
            }
        };
        (self.send)(msg);
    }

    /// A part's clips off the timeline, each in its row.
    fn part_cues(&mut self, part: &Part, pass: &PartPass, held: bool) {
        let same_cues = (!pass.retimed_notes || part.cues.is_empty())
            && pass.prev.map_or(part.cues.is_empty(), |p| {
                p.attr_map == part.attr_map && p.cues.same(&part.cues)
            });
        if same_cues && (!pass.replayed || part.cues.is_empty()) {
            return;
        }
        let rows = cue_rows(self.map.cue_rows.remove(&part.id).unwrap_or_default(), part);
        let slots = if held {
            Slots::default()
        } else {
            build_cues(part, &rows, self.new.tempo_map(), self.map, self.ctx)
        };
        if !rows.is_empty() {
            self.map.cue_rows.insert(part.id, rows);
        }
        (self.send)(Msg::SetSlots {
            part: pass.slot,
            slots: Box::new(slots),
        });
        if !same_cues {
            self.emit(E::CueChanged(Cue { part: part.id }));
        }
    }

    /// A part's automation lanes, and what the lanes it lost give back.
    /// `prev` is the part as the engine last had it.
    fn part_lanes(&mut self, part: &Part, prev: Option<&Part>, pass: &PartPass, same_chain: bool) {
        let same_lanes = prev.map_or(part.lanes.is_empty(), |p| {
            p.lanes.len() == part.lanes.len()
                && p.lanes.iter().zip(&part.lanes).all(|(a, b)| Arc::ptr_eq(a, b))
        });
        // A lane's compiled form names device slots, so a new chain needs it rebuilt.
        if !same_lanes || (!same_chain && !part.lanes.is_empty()) {
            self.lanes_changed |= !same_lanes;
            let automation = build_automation(part, self.new, self.map, self.ctx);
            (self.send)(Msg::SetAutomation {
                part: pass.slot,
                automation: Box::new(automation),
            });
        }
        if let Some(prev) = prev.filter(|_| !same_lanes) {
            release_targets(prev, part, self.map, self.ctx, self.send);
        }
    }

    /// Devices that are in no part any more.
    fn removed_devices(&mut self) {
        let new_devices: HashSet<Id> = self
            .new
            .all_parts()
            .flat_map(|t| &t.devices)
            .map(|d| d.id)
            .collect();
        // The part it was on, so that whoever listens looks at that part
        // alone (it may be gone too).
        let gone: Vec<(Id, Id)> = self
            .old_devices
            .iter()
            .filter(|(id, _)| !new_devices.contains(id))
            .map(|(&id, &(part, _))| (id, part))
            .collect();
        for (id, part) in gone {
            self.ctx.live.remove(&id);
            self.map.host_latency.remove(&id);
            self.map.keyed.remove(&id);
            self.map.outs.remove(&id);
            self.map.free_device(id, &mut self.removals);
            self.emit(E::DeviceRemoved(Item::on(id, Some(part))));
        }
    }

    /// The events of the clips and lanes that parts gained, lost or changed.
    fn item_events(&mut self) {
        if !self.clips_changed && !self.lanes_changed {
            return;
        }
        // Only parts that are not the very same in both snapshots can have
        // gained, lost or changed a clip or a lane.
        let new_parts: PartIndex = self.new.all_parts().map(|t| (t.id, t)).collect();
        let old_parts = &self.old_parts;
        let touched = |id: Id| match (old_parts.get(&id), new_parts.get(&id)) {
            (Some(a), Some(b)) => !Arc::ptr_eq(a, b),
            _ => true,
        };
        let events = &mut *self.events;
        let mut emit = |event: E| events.push(event.into());
        if self.clips_changed {
            item_events(
                [E::ClipAdded, E::ClipChanged, E::ClipRemoved],
                (old_parts, &new_parts),
                &touched,
                |was, t| match was {
                    Some(w) => {
                        let (old, new) = t.clips.changed(&w.clips);
                        (w.clips.range(old).collect(), t.clips.range(new).collect())
                    }
                    None => (Vec::new(), t.clips.iter().collect()),
                },
                |c| (c.id, c.stamp()),
                &mut emit,
            );
        }
        if self.lanes_changed {
            item_events(
                [E::LaneAdded, E::LaneChanged, E::LaneRemoved],
                (old_parts, &new_parts),
                &touched,
                |was, t| (was.map_or(Vec::new(), |w| w.lanes.iter().collect()), t.lanes.iter().collect()),
                |l| (l.id, None),
                &mut emit,
            );
        }
    }

    /// A part the VCAs it is in have changed the fader lane of is told so,
    /// and takes its own fader value back when it no longer has one.
    fn vca_lanes(&mut self) {
        let new = self.new;
        for part in new.all_parts() {
            let Some(&slot) = self.map.parts.get(&part.id) else {
                continue;
            };
            let lane = vca_volume_lane(part, new);
            if lane.as_ref() == self.map.vca_lanes.get(&part.id) {
                continue;
            }
            match lane {
                Some(points) => self.map.vca_lanes.insert(part.id, points),
                None => self.map.vca_lanes.remove(&part.id),
            };
            self.map.mix.remove(&part.id);
            let automation = build_automation(part, new, self.map, self.ctx);
            (self.send)(Msg::SetAutomation {
                part: slot,
                automation: Box::new(automation),
            });
        }
    }

    /// Each part's fader, pan, mute and whether a solo silences it.
    fn mix(&mut self) {
        let new = self.new;
        let soloed = soloed_parts(new);
        let sounding = if soloed.is_empty() {
            HashSet::new()
        } else {
            solo_paths(new, &soloed)
        };
        // What the session lets be heard for now: as a solo, but not the model's.
        let audible = self.map.audible.as_ref().map(|ids| {
            let ids = ids.iter().copied().filter(|id| new.part(*id).is_some()).collect();
            solo_paths(new, &ids)
        });
        self.map.played.retain(|id, _| new.part(*id).is_some());
        for part in new.all_parts() {
            let Some(&slot) = self.map.parts.get(&part.id) else {
                continue;
            };
            let quiet = part.id != MASTER_ID
                && ((!soloed.is_empty() && !sounding.contains(&part.id))
                    || audible.as_ref().is_some_and(|a| !a.contains(&part.id))
                    || self.map.played.get(&part.id) == Some(&Played::Held));
            let vcas = vcas_of(part, new);
            let mix = MixSent {
                gain: db_to_gain(part.volume + vcas.iter().map(|v| v.volume).sum::<f64>()),
                pan: part.pan as f32,
                mute: part.mute || vcas.iter().any(|v| v.mute),
                quiet,
            };
            if self.map.mix.get(&part.id) != Some(&mix) {
                self.map.mix.insert(part.id, mix);
                (self.send)(Msg::SetMix {
                    slot,
                    gain: mix.gain,
                    pan: mix.pan,
                    mute: mix.mute,
                    quiet: mix.quiet,
                });
            }
        }
    }

    /// Each part's audio input, MIDI input and MIDI output.
    fn inputs(&mut self) {
        let new = self.new;
        // The selected part plays the MIDI keyboard while no part is
        // armed; step input's part plays it always.
        let follow = self.map.follow.part(new.parts.iter().any(|t| t.armed));
        for part in new.all_parts() {
            let Some(&slot) = self.map.parts.get(&part.id) else {
                continue;
            };
            let (first, channels) =
                part.input.map_or((0, 0), |i| (usize::from(i.first), usize::from(i.count)));
            // An armed part is always heard, so that what is recorded is what
            // the player hears; the monitor switch is for hearing it otherwise.
            let followed = follow == Some(part.id) && channels == 0 && part.id != MASTER_ID;
            let input = InputSent {
                first,
                channels,
                monitor: part.armed || part.monitor || followed,
                armed: part.armed,
            };
            if self.map.inputs.get(&part.id) != Some(&input) {
                self.map.inputs.insert(part.id, input);
                (self.send)(Msg::SetInput {
                    part: slot,
                    first,
                    channels,
                    monitor: input.monitor,
                    armed: input.armed,
                });
            }
            let midi = part.midi_input.as_ref().map_or(MidiInSent::default(), |m| MidiInSent {
                port: m.port.as_deref().map_or(0, paw_engine::midi::port_key),
                channel: m.channel.unwrap_or(0),
            });
            if self.map.midi_inputs.get(&part.id).copied().unwrap_or_default() != midi {
                self.map.midi_inputs.insert(part.id, midi);
                (self.send)(Msg::SetMidiInput {
                    part: slot,
                    port: midi.port,
                    channel: midi.channel,
                });
            }
            let out = part.midi_output.as_ref().map_or(MidiOutSent::default(), |m| MidiOutSent {
                port: paw_engine::midi::port_key(&m.port),
                channel: m.channel.unwrap_or(0),
                form: m.engine_form(),
            });
            if self.map.midi_outputs.get(&part.id).copied().unwrap_or_default() != out {
                self.map.midi_outputs.insert(part.id, out);
                (self.send)(Msg::SetMidiOutput {
                    part: slot,
                    port: out.port,
                    channel: out.channel,
                    form: out.form,
                });
            }
        }
    }

    /// A device whose latency changed: its dry signal is held back to
    /// match, and the branches of its chain wait for it.
    fn device_latency(&mut self) {
        let mut changed = HashSet::new();
        for (id, live) in self.ctx.live.iter() {
            if let Some(&slot) = self.map.devices.get(id)
                && self.map.host_latency.get(id) != Some(&live.latency)
            {
                self.map.host_latency.insert(*id, live.latency);
                changed.insert(*id);
                (self.send)(Msg::SetDeviceLatency {
                    device: slot,
                    frames: live.latency,
                });
            }
        }
        if changed.is_empty() {
            return;
        }
        for part in self.new.all_parts() {
            if part.devices.iter().any(|d| changed.contains(&d.id))
                && let Some(&slot) = self.map.parts.get(&part.id)
            {
                let held = self.map.played.contains_key(&part.id);
                self.send_plan(part, slot, held, false);
            }
        }
    }

    /// Compile the chain of `part` and send the plan to its processor,
    /// when it is not what the engine has (or always, when `fresh`: the
    /// processor is new). The devices of a frozen or held part hold
    /// nothing back.
    fn send_plan(&mut self, part: &Part, slot: PartSlot, held: bool, fresh: bool) {
        let live = &*self.ctx.live;
        let latency = |d: &DeviceInst| -> u32 {
            if held || d.bypass {
                return 0;
            }
            live.get(&d.id).map_or(0, |l| l.latency.min(paw_engine::MAX_DELAY as u32))
        };
        let slots = chains::Slots { devices: &self.map.devices, latency: &latency, kinds: self.ctx.kinds };
        let (tree, notes) = chains::tree_of(part, &slots);
        if !fresh && self.map.trees.get(&part.id) == Some(&tree) {
            return;
        }
        let plan = paw_engine::plan::compile(&tree, self.ctx.sample_rate);
        self.map.meters.insert(part.id, plan.meters().clone());
        self.map.trees.insert(part.id, tree);
        self.ctx.warnings.extend(notes);
        (self.send)(Msg::SetGraph { slot: slot.into(), plan });
    }

    /// Side-chain and output buffers for the devices that are routed, and
    /// the schedule when the routing changed.
    fn routing(&mut self) {
        let map = &mut *self.map;
        let send = &mut *self.send;
        let routing = routing_of(self.new, self.ctx.live, map, self.placed);
        // Devices that listen to a side-chain get a buffer for it, before the
        // schedule that fills it; those that no longer do give theirs back.
        let keyed: HashSet<Id> = routing
            .iter()
            .flat_map(|r| &r.keys)
            .map(|k| k.device)
            .filter(|id| map.devices.contains_key(id))
            .collect();
        for id in keyed.difference(&map.keyed) {
            send(Msg::SetKey {
                device: map.devices[id],
                key: Some(paw_engine::key_buf()),
            });
        }
        for id in map.keyed.difference(&keyed) {
            if let Some(&device) = map.devices.get(id) {
                send(Msg::SetKey { device, key: None });
            }
        }
        map.keyed = keyed;
        // Likewise buffers for as many further output pairs as are routed.
        let mut outs: HashMap<Id, Vec<usize>> = HashMap::new();
        for out in routing.iter().flat_map(|r| &r.outs) {
            if map.devices.contains_key(&out.device) {
                let pairs = outs.entry(out.device).or_default();
                if !pairs.contains(&out.pair) {
                    pairs.push(out.pair);
                    pairs.sort_unstable();
                }
            }
        }
        for (id, pairs) in &outs {
            if map.outs.get(id) != Some(pairs) {
                send(Msg::SetOutputs {
                    device: map.devices[id],
                    outs: Some(paw_engine::out_bufs(pairs)),
                });
            }
        }
        for id in map.outs.keys().filter(|id| !outs.contains_key(id)) {
            if let Some(&device) = map.devices.get(id) {
                send(Msg::SetOutputs { device, outs: None });
            }
        }
        map.outs = outs;
        let routes_moved = self.device_slots
            && routing
                .iter()
                .any(|r| !r.keys.is_empty() || !r.outs.is_empty());
        if routing != map.routing || self.new_slots || routes_moved {
            let schedule = build_schedule(&routing, map);
            map.latency = schedule.latency;
            send(Msg::SetSchedule(Box::new(schedule)));
            map.routing = routing;
        }
    }

    /// The time the devices of each nest part see: the nest's bars, from
    /// beat 0 of the block that plays (`nests.rs`). Sent when it changes.
    fn local_times(&mut self) {
        let mut now: HashMap<Id, nests::Local> = HashMap::new();
        for t in self.new.parts.iter() {
            if let Some(local) = t.nest.and_then(|n| nests::Local::of(self.new, n, t.id, self.placed)) {
                now.insert(t.id, local);
            }
        }
        if now.is_empty() && self.map.local.is_empty() {
            return;
        }
        for (id, local) in &now {
            if self.map.local.get(id) == Some(local) {
                continue;
            }
            if let Some(&part) = self.map.parts.get(id) {
                (self.send)(Msg::SetLocalTime { part, time: Some(Box::new(local.time())) });
            }
        }
        for id in self.map.local.keys().filter(|id| !now.contains_key(id)) {
            if let Some(&part) = self.map.parts.get(id) {
                (self.send)(Msg::SetLocalTime { part, time: None });
            }
        }
        self.map.local = now;
    }

    /// Parts that are gone: their slots are freed after the removals.
    fn removed_parts(&mut self) {
        let new = self.new;
        let gone: Vec<Id> = self
            .old_parts
            .keys()
            .copied()
            .filter(|id| new.part(*id).is_none())
            .collect();
        for id in gone {
            let map = &mut *self.map;
            map.pieces.remove(&id);
            map.trees.remove(&id);
            map.meters.remove(&id);
            map.cue_rows.remove(&id);
            map.cue_events.remove(&id);
            if let Some(slot) = map.parts.remove(&id) {
                // Notes it left sounding on its MIDI output port end there.
                if map.midi_outputs.get(&id).is_some_and(|out| out.port != 0) {
                    self.removals.push(Msg::SetMidiOutput {
                        part: slot,
                        port: 0,
                        channel: 0,
                        form: Form::Auto,
                    });
                }
                self.removals.push(Msg::RemovePart { slot });
                map.free_parts.push(slot);
            }
            map.mix.remove(&id);
            map.inputs.remove(&id);
            map.midi_inputs.remove(&id);
            map.midi_outputs.remove(&id);
            self.emit(E::PartRemoved(PartId { id }));
        }
    }
}
