//! Turns the difference between two project snapshots into engine messages and
//! change events.
//!
//! This is the only place that tells the engine what the project looks like.
//! Edits, undo, loading a project and offline rendering all end up here, so
//! none of them can leave the engine out of step with the model.
//!
//! [`sync`] takes its steps in a fixed order, which the engine relies on: a
//! track is there before its devices and clips, the schedule comes after the
//! tracks and devices it names, and what is removed goes last.
//!
//! - `mapper.rs`: the slots and what the engine was last sent;
//! - `audio.rs`: decoded files, shared between clips;
//! - `devices.rs`: devices made, updated and given their files;
//! - `clips.rs`: clips compiled and sent whole or in parts;
//! - `automation.rs`: lanes, VCA faders, and what a lane gives back;
//! - `routing.rs`: outputs, sends, side-chains, solo and the schedule;
//! - `items.rs`: the events of clips and lanes added, changed or removed.

mod audio;
mod automation;
mod clips;
mod devices;
mod items;
mod mapper;
mod routing;
#[cfg(test)]
mod tests;

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use paw_engine::launch::Slots;
use paw_engine::midi_form::Form;
use paw_engine::{ClipSet, Controller, DeviceSlot, Msg, ParamInfo, Registry, TrackRt, TrackSlot, db_to_gain};

pub use self::audio::AudioCache;
pub use self::automation::is_active;
pub use self::devices::{TakesClips, clips_json, deliver_clips, install, is_host, rekey};
pub use self::mapper::{Follow, Mapper};
pub use self::clips::repeats;
pub use crate::events::ModelEvent;

use self::automation::{build_automation, release_targets, vca_volume_lane, vcas_of};
use self::clips::{build_clips, build_cues, cue_rows, edit_parts, frozen_clips};
use self::devices::{add_device, update_device};
use self::items::{TrackIndex, item_events};
use self::mapper::{InputSent, MidiInSent, MidiOutSent, MixSent};
use self::routing::{build_schedule, routing_of, solo_paths, soloed_tracks};
use crate::events::{Cue, Item, KernelEvent as E, Nothing, Order, TrackId};
use crate::freeze::Played;
use crate::model::{DeviceInst, Id, MASTER_ID, Project, Track};

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
    /// Whether it takes its track's clips, and what it was given.
    pub clips: TakesClips,
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
    let mut pass = Pass {
        old_tracks: old.all_tracks().map(|t| (t.id, t)).collect(),
        old_devices: old
            .all_tracks()
            .flat_map(|t| &t.devices)
            .map(|d| (d.id, d))
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
    pass.tracks(retimed);
    pass.removed_devices();
    pass.item_events();
    pass.vca_lanes();
    pass.mix();
    pass.inputs();
    pass.device_latency();
    pass.routing();
    pass.removed_tracks();
    let Pass { new, ctx, send, removals, .. } = pass;
    // Removals go last, once nothing in the schedule or a chain refers to them.
    removals.into_iter().for_each(&mut *send);

    deliver_clips(new, ctx);

    if events.len() > before {
        events.push(E::changed().into());
    }
}

/// One [`sync`]: the two snapshots, where the messages and events go, and
/// what the steps tell each other.
struct Pass<'p, 'm, 'c> {
    old: &'p Project,
    new: &'p Project,
    old_tracks: TrackIndex<'p>,
    old_devices: HashMap<Id, &'p Arc<DeviceInst>>,
    map: &'m mut Mapper,
    ctx: &'m mut SyncCtx<'c>,
    send: &'m mut dyn FnMut(Msg),
    events: &'m mut Vec<ModelEvent>,
    /// Sent last, once nothing in the schedule or a chain refers to them.
    removals: Vec<Msg>,
    clips_changed: bool,
    lanes_changed: bool,
    /// The schedule lists slots, so a track that gets one needs a new schedule.
    new_slots: bool,
    /// Side-chains name device slots, so a device that gets one does too.
    device_slots: bool,
}

/// How a track plays now and what it was before, worked out once for its
/// steps.
struct TrackPass<'p> {
    /// The same track in the old snapshot, unless it only now got a slot.
    prev: Option<&'p Arc<Track>>,
    slot: TrackSlot,
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
                paw_engine::TempoMap::new(&new.tempo_points(), &new.sig_points())
            };
            (self.send)(Msg::SetTempoMap(Box::new(map)));
        }
        if retimed || old.name != new.name || old.meta != new.meta {
            self.emit(E::ProjectChanged(Nothing {}));
        }
        // The same tracks in another order: nothing the engine needs to hear of,
        // but whoever draws the track list does.
        if old.tracks.len() == new.tracks.len()
            && old.tracks.iter().zip(&new.tracks).any(|(a, b)| a.id != b.id)
        {
            let order: Vec<Id> = new.tracks.iter().map(|t| t.id).collect();
            self.emit(E::TrackMoved(Order { order }));
        }
        retimed
    }

    /// Each track that changed, whole: its slot, devices, clips, cues and
    /// lanes.
    fn tracks(&mut self, retimed: bool) {
        // Frozen tracks play a file, and what feeds them is held.
        let new = self.new;
        let mut played = crate::freeze::played(new, &self.map.held_files);
        for track in new.all_tracks() {
            let plays = played.remove(&track.id);
            let Some(pass) = self.track_slot(track, plays.clone().unwrap_or(Played::Live), retimed)
            else {
                continue;
            };
            let same_chain = self.track_devices(track, &pass);
            // A frozen or held track's devices are held in the engine only: the
            // model keeps its own bypass, which comes back when it thaws.
            let held = pass.plays != Played::Live;
            if held || pass.replayed {
                for device in &track.devices {
                    if let Some(&device_slot) = self.map.devices.get(&device.id) {
                        (self.send)(Msg::SetBypass {
                            device: device_slot,
                            bypass: device.bypass || held,
                        });
                    }
                }
            }
            self.track_clips(track, &pass);
            self.track_cues(track, &pass, held);
            match plays {
                Some(plays) => self.map.played.insert(track.id, plays),
                None => self.map.played.remove(&track.id),
            };
            self.track_lanes(track, &pass, same_chain);
        }
    }

    /// Whether a track needs looking at, its slot (made now for a new
    /// track) and its events. `None` for a track that did not change, or
    /// that the engine has no room for.
    fn track_slot(&mut self, track: &'p Arc<Track>, plays: Played, retimed: bool) -> Option<TrackPass<'p>> {
        let prev = self.old_tracks.get(&track.id).copied();
        // A track the engine had no room for is built whole once there is room.
        let fresh = !self.map.tracks.contains_key(&track.id);
        let retimed_notes = retimed && track.attr_map.as_ref().is_some_and(|m| m.has_delay());
        let replayed = self.map.played.get(&track.id).unwrap_or(&Played::Live) != &plays;
        if !fresh && !replayed && !retimed_notes && prev.is_some_and(|p| Arc::ptr_eq(p, track)) {
            return None;
        }
        if fresh {
            let Some(slot) = self.map.alloc_track() else {
                if prev.is_none() {
                    self.ctx
                        .warnings
                        .push(format!("too many tracks: `{}` will be silent", track.name));
                }
                return None;
            };
            self.map.tracks.insert(track.id, slot);
            self.new_slots = true;
            (self.send)(Msg::InsertTrack {
                slot,
                track: TrackRt::new(),
            });
        }
        match prev {
            None => self.emit(E::TrackAdded(TrackId { id: track.id })),
            Some(p) if !Arc::ptr_eq(p, track) => self.emit(E::TrackChanged(TrackId { id: track.id })),
            Some(_) => {}
        }
        Some(TrackPass {
            // From here on, a track that has only now got a slot counts as new.
            prev: prev.filter(|_| !fresh),
            slot: *self.map.tracks.get(&track.id)?,
            plays,
            replayed,
            retimed_notes,
        })
    }

    /// A track's devices added, set offline or back, or changed, and its
    /// chain sent again when it changed. Whether the chain is the same.
    fn track_devices(&mut self, track: &Track, pass: &TrackPass) -> bool {
        // Devices set offline or back online since: gone from the engine,
        // or made, and the chain sent again.
        let mut toggled = false;
        for device in &track.devices {
            let item = Item { id: device.id, track: Some(track.id) };
            match self.old_devices.get(&device.id).copied().filter(|_| pass.prev.is_some()) {
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
                    .eq(track.devices.iter().map(|d| d.id))
            });
        if !same_chain {
            let chain: Box<[DeviceSlot]> = track
                .devices
                .iter()
                .filter_map(|d| self.map.devices.get(&d.id).copied())
                .collect();
            (self.send)(Msg::SetChain { track: pass.slot, chain });
        }
        same_chain
    }

    /// A track's clips on the timeline: the parts an edit changed, or all
    /// of them.
    fn track_clips(&mut self, track: &Track, pass: &TrackPass) {
        let same_clips = !pass.retimed_notes
            && pass
                .prev
                .is_some_and(|p| p.attr_map == track.attr_map && p.clips.same(&track.clips));
        if !same_clips {
            self.clips_changed = true;
        }
        if same_clips && !pass.replayed {
            return;
        }
        let tempo = self.new.tempo_map();
        // A few clips changed: the engine is sent only theirs.
        let edit = match (&pass.plays, pass.prev) {
            (Played::Live, Some(p))
                if !pass.replayed && !pass.retimed_notes && p.attr_map == track.attr_map =>
            {
                edit_parts(p, track, tempo, self.map, self.ctx)
            }
            _ => None,
        };
        let msg = match edit {
            Some(edit) => Msg::EditClips {
                track: pass.slot,
                edit: Box::new(edit),
            },
            None => {
                let clips = match &pass.plays {
                    Played::Live => build_clips(track, tempo, self.map, self.ctx),
                    Played::Frozen(file) => {
                        self.map.parts.remove(&track.id);
                        frozen_clips(file, tempo, self.ctx)
                    }
                    Played::Held => {
                        self.map.parts.remove(&track.id);
                        ClipSet::default()
                    }
                };
                Msg::SetClips {
                    track: pass.slot,
                    clips: Box::new(clips),
                }
            }
        };
        (self.send)(msg);
    }

    /// A track's clips off the timeline, each in its row.
    fn track_cues(&mut self, track: &Track, pass: &TrackPass, held: bool) {
        let same_cues = (!pass.retimed_notes || track.cues.is_empty())
            && pass.prev.map_or(track.cues.is_empty(), |p| {
                p.attr_map == track.attr_map && p.cues.same(&track.cues)
            });
        if same_cues && (!pass.replayed || track.cues.is_empty()) {
            return;
        }
        let rows = cue_rows(self.map.cue_rows.remove(&track.id).unwrap_or_default(), track);
        let slots = if held {
            Slots::default()
        } else {
            build_cues(track, &rows, self.new.tempo_map(), self.map, self.ctx)
        };
        if !rows.is_empty() {
            self.map.cue_rows.insert(track.id, rows);
        }
        (self.send)(Msg::SetSlots {
            track: pass.slot,
            slots: Box::new(slots),
        });
        if !same_cues {
            self.emit(E::CueChanged(Cue { track: track.id }));
        }
    }

    /// A track's automation lanes, and what the lanes it lost give back.
    fn track_lanes(&mut self, track: &Track, pass: &TrackPass, same_chain: bool) {
        let same_lanes = pass.prev.map_or(track.lanes.is_empty(), |p| {
            p.lanes.len() == track.lanes.len()
                && p.lanes.iter().zip(&track.lanes).all(|(a, b)| Arc::ptr_eq(a, b))
        });
        // A lane's compiled form names device slots, so a new chain needs it rebuilt.
        if !same_lanes || (!same_chain && !track.lanes.is_empty()) {
            self.lanes_changed |= !same_lanes;
            let automation = build_automation(track, self.new, self.map, self.ctx);
            (self.send)(Msg::SetAutomation {
                track: pass.slot,
                automation: Box::new(automation),
            });
        }
        if let Some(prev) = pass.prev.filter(|_| !same_lanes) {
            release_targets(prev, track, self.map, self.ctx, self.send);
        }
    }

    /// Devices that are in no track any more.
    fn removed_devices(&mut self) {
        let new_devices: HashSet<Id> = self
            .new
            .all_tracks()
            .flat_map(|t| &t.devices)
            .map(|d| d.id)
            .collect();
        let gone: Vec<Id> = self
            .old_devices
            .keys()
            .copied()
            .filter(|id| !new_devices.contains(id))
            .collect();
        for id in gone {
            self.ctx.live.remove(&id);
            self.map.host_latency.remove(&id);
            self.map.keyed.remove(&id);
            self.map.outs.remove(&id);
            self.map.free_device(id, &mut self.removals);
            self.emit(E::DeviceRemoved(Item { id, track: None }));
        }
    }

    /// The events of the clips and lanes that tracks gained, lost or changed.
    fn item_events(&mut self) {
        if !self.clips_changed && !self.lanes_changed {
            return;
        }
        // Only tracks that are not the very same in both snapshots can have
        // gained, lost or changed a clip or a lane.
        let new_tracks: TrackIndex = self.new.all_tracks().map(|t| (t.id, t)).collect();
        let old_tracks = &self.old_tracks;
        let touched = |id: Id| match (old_tracks.get(&id), new_tracks.get(&id)) {
            (Some(a), Some(b)) => !Arc::ptr_eq(a, b),
            _ => true,
        };
        let events = &mut *self.events;
        let mut emit = |event: E| events.push(event.into());
        if self.clips_changed {
            item_events(
                [E::ClipAdded, E::ClipChanged, E::ClipRemoved],
                (old_tracks, &new_tracks),
                &touched,
                |was, t| match was {
                    Some(w) => {
                        let (old, new) = t.clips.changed(&w.clips);
                        (w.clips.range(old).collect(), t.clips.range(new).collect())
                    }
                    None => (Vec::new(), t.clips.iter().collect()),
                },
                |c| c.id,
                &mut emit,
            );
        }
        if self.lanes_changed {
            item_events(
                [E::LaneAdded, E::LaneChanged, E::LaneRemoved],
                (old_tracks, &new_tracks),
                &touched,
                |was, t| (was.map_or(Vec::new(), |w| w.lanes.iter().collect()), t.lanes.iter().collect()),
                |l| l.id,
                &mut emit,
            );
        }
    }

    /// A track the VCAs it is in have changed the fader lane of is told so,
    /// and takes its own fader value back when it no longer has one.
    fn vca_lanes(&mut self) {
        let new = self.new;
        for track in new.all_tracks() {
            let Some(&slot) = self.map.tracks.get(&track.id) else {
                continue;
            };
            let lane = vca_volume_lane(track, new);
            if lane.as_ref() == self.map.vca_lanes.get(&track.id) {
                continue;
            }
            match lane {
                Some(points) => self.map.vca_lanes.insert(track.id, points),
                None => self.map.vca_lanes.remove(&track.id),
            };
            self.map.mix.remove(&track.id);
            let automation = build_automation(track, new, self.map, self.ctx);
            (self.send)(Msg::SetAutomation {
                track: slot,
                automation: Box::new(automation),
            });
        }
    }

    /// Each track's fader, pan, mute and whether a solo silences it.
    fn mix(&mut self) {
        let new = self.new;
        let soloed = soloed_tracks(new);
        let sounding = if soloed.is_empty() {
            HashSet::new()
        } else {
            solo_paths(new, &soloed)
        };
        // What the session lets be heard for now: as a solo, but not the model's.
        let audible = self.map.audible.as_ref().map(|ids| {
            let ids = ids.iter().copied().filter(|id| new.track(*id).is_some()).collect();
            solo_paths(new, &ids)
        });
        self.map.played.retain(|id, _| new.track(*id).is_some());
        for track in new.all_tracks() {
            let Some(&slot) = self.map.tracks.get(&track.id) else {
                continue;
            };
            let quiet = track.id != MASTER_ID
                && ((!soloed.is_empty() && !sounding.contains(&track.id))
                    || audible.as_ref().is_some_and(|a| !a.contains(&track.id))
                    || self.map.played.get(&track.id) == Some(&Played::Held));
            let vcas = vcas_of(track, new);
            let mix = MixSent {
                gain: db_to_gain(track.volume + vcas.iter().map(|v| v.volume).sum::<f64>()),
                pan: track.pan as f32,
                mute: track.mute || vcas.iter().any(|v| v.mute),
                quiet,
            };
            if self.map.mix.get(&track.id) != Some(&mix) {
                self.map.mix.insert(track.id, mix);
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

    /// Each track's audio input, MIDI input and MIDI output.
    fn inputs(&mut self) {
        let new = self.new;
        // The selected track plays the MIDI keyboard while no track is
        // armed; step input's track plays it always.
        let follow = self.map.follow.track(new.tracks.iter().any(|t| t.armed));
        for track in new.all_tracks() {
            let Some(&slot) = self.map.tracks.get(&track.id) else {
                continue;
            };
            let (first, channels) =
                track.input.map_or((0, 0), |i| (usize::from(i.first), usize::from(i.count)));
            // An armed track is always heard, so that what is recorded is what
            // the player hears; the monitor switch is for hearing it otherwise.
            let followed = follow == Some(track.id) && channels == 0 && track.id != MASTER_ID;
            let input = InputSent {
                first,
                channels,
                monitor: track.armed || track.monitor || followed,
                armed: track.armed,
            };
            if self.map.inputs.get(&track.id) != Some(&input) {
                self.map.inputs.insert(track.id, input);
                (self.send)(Msg::SetInput {
                    track: slot,
                    first,
                    channels,
                    monitor: input.monitor,
                    armed: input.armed,
                });
            }
            let midi = track.midi_input.as_ref().map_or(MidiInSent::default(), |m| MidiInSent {
                port: m.port.as_deref().map_or(0, paw_engine::midi::port_key),
                channel: m.channel.unwrap_or(0),
            });
            if self.map.midi_inputs.get(&track.id).copied().unwrap_or_default() != midi {
                self.map.midi_inputs.insert(track.id, midi);
                (self.send)(Msg::SetMidiInput {
                    track: slot,
                    port: midi.port,
                    channel: midi.channel,
                });
            }
            let out = track.midi_output.as_ref().map_or(MidiOutSent::default(), |m| MidiOutSent {
                port: paw_engine::midi::port_key(&m.port),
                channel: m.channel.unwrap_or(0),
                form: m.engine_form(),
            });
            if self.map.midi_outputs.get(&track.id).copied().unwrap_or_default() != out {
                self.map.midi_outputs.insert(track.id, out);
                (self.send)(Msg::SetMidiOutput {
                    track: slot,
                    port: out.port,
                    channel: out.channel,
                    form: out.form,
                });
            }
        }
    }

    /// A device whose latency changed: its dry signal is held back to match.
    fn device_latency(&mut self) {
        for (id, live) in self.ctx.live.iter() {
            if let Some(&slot) = self.map.devices.get(id)
                && self.map.host_latency.get(id) != Some(&live.latency)
            {
                self.map.host_latency.insert(*id, live.latency);
                (self.send)(Msg::SetDeviceLatency {
                    device: slot,
                    frames: live.latency,
                });
            }
        }
    }

    /// Side-chain and output buffers for the devices that are routed, and
    /// the schedule when the routing changed.
    fn routing(&mut self) {
        let map = &mut *self.map;
        let send = &mut *self.send;
        let routing = routing_of(self.new, self.ctx.live, &map.played);
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

    /// Tracks that are gone: their slots are freed after the removals.
    fn removed_tracks(&mut self) {
        let new = self.new;
        let gone: Vec<Id> = self
            .old_tracks
            .keys()
            .copied()
            .filter(|id| new.track(*id).is_none())
            .collect();
        for id in gone {
            let map = &mut *self.map;
            map.parts.remove(&id);
            map.cue_rows.remove(&id);
            map.cue_events.remove(&id);
            if let Some(slot) = map.tracks.remove(&id) {
                // Notes it left sounding on its MIDI output port end there.
                if map.midi_outputs.get(&id).is_some_and(|out| out.port != 0) {
                    self.removals.push(Msg::SetMidiOutput {
                        track: slot,
                        port: 0,
                        channel: 0,
                        form: Form::Auto,
                    });
                }
                self.removals.push(Msg::RemoveTrack { slot });
                map.free_tracks.push(slot);
            }
            map.mix.remove(&id);
            map.inputs.remove(&id);
            map.midi_inputs.remove(&id);
            map.midi_outputs.remove(&id);
            self.emit(E::TrackRemoved(TrackId { id }));
        }
    }
}
