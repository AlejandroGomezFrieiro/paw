//! Turns the difference between two project snapshots into engine messages and
//! change events.
//!
//! This is the only place that tells the engine what the project looks like.
//! Edits, undo, loading a project and offline rendering all end up here, so
//! none of them can leave the engine out of step with the model.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use base64::Engine as _;
use paw_engine::midi_form::Form;
use base64::engine::general_purpose::STANDARD as BASE64;
use paw_engine::launch::{SlotClip, Slots};
use paw_engine::{
    AudioData, AudioRegion, AutoLane, AutoTarget, Automation, ClipSet, Controller, Delay, Part, PartEdit,
    DiskStore, MASTER,
    KeyRt, MAX_BLOCK, MAX_DELAY, MAX_DEVICES, MAX_TRACKS, MidiEv, Msg, NO_SLOT, OutRt, ParamInfo,
    Registry, SchedEntry, Schedule, SendRt, Slot, StateChange, StateLane, TrackRt, db_to_gain,
};
use serde_json::{Value, json};

use crate::freeze::Played;
use crate::model::{
    Clip, ClipContent, Control, DeviceInst, Id, Lane, MASTER_ID, Note, Notes, Project, Target, Track,
};
use crate::peaks::{self, Summary};

/// A change notification for Lua: event name and payload.
pub type ModelEvent = (String, Value);

/// Where a track's signal goes, and how late it is when it leaves.
#[derive(Clone, Debug, PartialEq)]
struct Route {
    track: Id,
    output: Id,
    /// Target, gain, and whether it is taken before the fader.
    sends: Vec<(Id, f32, bool)>,
    /// Devices on other tracks that listen to this one: see [`Key`].
    keys: Vec<Key>,
    /// Further output pairs of this track's devices: see [`Out`].
    outs: Vec<Out>,
    /// Frames of latency of the track's own devices.
    latency: u32,
}

/// A side-chain, as the track it is taken from sees it.
#[derive(Clone, Debug, PartialEq)]
struct Key {
    /// The track the listening device is on, and the device.
    track: Id,
    device: Id,
    /// Taken before the fader.
    pre: bool,
    /// Frames of latency of the devices before it on its track, which the
    /// key waits for so that it lines up with what the device hears.
    before: u32,
}

/// One of a device's further output pairs, played into another track.
#[derive(Clone, Debug, PartialEq)]
struct Out {
    device: Id,
    /// 0 for the device's second pair.
    pair: usize,
    target: Id,
    /// Frames of latency of the track's devices up to this one, included:
    /// how late after the track's input the pair leaves.
    late: u32,
}

type Routing = Vec<Route>;

/// Which engine slot each track and device lives in.
pub struct Mapper {
    pub tracks: HashMap<Id, Slot>,
    pub devices: HashMap<Id, Slot>,
    free_tracks: Vec<Slot>,
    free_devices: Vec<Slot>,
    next_track: Slot,
    next_device: Slot,
    mix: HashMap<Id, (f32, f32, bool, bool)>,
    /// The fader lane each track has because of the VCAs it is in, as last
    /// sent: see [`vca_volume_lane`].
    vca_lanes: HashMap<Id, Vec<(f64, f64)>>,
    /// First input channel, channel count, monitoring and armed, as last sent.
    inputs: HashMap<Id, (usize, usize, bool, bool)>,
    /// The MIDI port's key and channel each track takes, as last sent.
    midi_inputs: HashMap<Id, (u32, u8)>,
    /// The same for the port each track sends to.
    midi_outputs: HashMap<Id, (u32, u8, Form)>,
    routing: Routing,
    /// Devices given a buffer for a side-chain.
    keyed: HashSet<Id>,
    /// Devices given buffers for further output pairs, and which.
    outs: HashMap<Id, Vec<usize>>,
    /// Frames by which the output is behind the transport, as last scheduled.
    pub latency: u32,
    /// What the engine was sent of each track's clips, one part for each
    /// (see [`Parts`]), so that an edit compiles and sends only the clips
    /// it changed. Tracks whose clips are sent as one list have none.
    parts: HashMap<Id, Parts>,
    /// Each device's latency as last told to the host's dry signal.
    host_latency: HashMap<Id, u32>,
    /// Make devices whose factories can ([`DeviceFactory::starts_apart`])
    /// without waiting for them: each gets a stand-in, and its id is put
    /// in [`deferred`](Self::deferred) for the session to make it.
    ///
    /// [`DeviceFactory::starts_apart`]: paw_engine::DeviceFactory::starts_apart
    pub defer: bool,
    /// Devices given a stand-in since the session last looked.
    pub deferred: Vec<Id>,
    /// Tracks the session plays from a file for now, as if they were
    /// frozen, without the project saying so (see [`crate::freeze`]).
    pub held_files: HashMap<Id, PathBuf>,
    /// When set, only these tracks are heard, with what they pass through,
    /// as if they were soloed; the project is not changed.
    pub audible: Option<HashSet<Id>>,
    /// The track that plays MIDI input as if it were monitored, without
    /// the project saying so: the selected track, while no track is armed
    /// (`paw.opt.midi_follows_selection`).
    pub follow: Option<Id>,
    /// What the engine was last told to play of each track that is not live.
    played: HashMap<Id, Played>,
    /// The clip in each of a track's cue rows in the engine, so that a
    /// clip keeps its row (and goes on playing) while others come and go.
    pub cue_rows: HashMap<Id, Vec<Option<Id>>>,
    /// Each track's MIDI clips off the timeline as engine events, so that
    /// a change of one compiles only that one.
    cue_events: HashMap<Id, HashMap<Id, (Arc<Clip>, Arc<[MidiEv]>)>>,
    /// For each state lane the engine has, by the lane's id: which of its
    /// states need the main thread (a whole saved state, or a request the
    /// device could not prepare for its audio side). The session loads
    /// those as the song plays, and a render stops on their points.
    pub state_main: HashMap<Id, Vec<bool>>,
}

impl Default for Mapper {
    fn default() -> Self {
        Self::new()
    }
}

impl Mapper {
    pub fn new() -> Self {
        Self {
            tracks: HashMap::from([(MASTER_ID, MASTER)]),
            devices: HashMap::new(),
            free_tracks: Vec::new(),
            free_devices: Vec::new(),
            next_track: MASTER + 1,
            next_device: 0,
            mix: HashMap::new(),
            vca_lanes: HashMap::new(),
            inputs: HashMap::new(),
            midi_inputs: HashMap::new(),
            midi_outputs: HashMap::new(),
            routing: Vec::new(),
            keyed: HashSet::new(),
            outs: HashMap::new(),
            latency: 0,
            parts: HashMap::new(),
            host_latency: HashMap::new(),
            defer: false,
            deferred: Vec::new(),
            held_files: HashMap::new(),
            audible: None,
            follow: None,
            played: HashMap::new(),
            cue_rows: HashMap::new(),
            cue_events: HashMap::new(),
            state_main: HashMap::new(),
        }
    }

    /// The engine's row of a clip off the timeline, if the engine has it.
    pub fn cue_row(&self, track: Id, clip: Id) -> Option<u32> {
        let rows = self.cue_rows.get(&track)?;
        rows.iter().position(|c| *c == Some(clip)).map(|r| r as u32)
    }

    /// The clip in a track's cue row in the engine.
    pub fn cue_clip(&self, track: Id, row: u32) -> Option<Id> {
        *self.cue_rows.get(&track)?.get(row as usize)?
    }

    fn alloc_track(&mut self) -> Option<Slot> {
        self.free_tracks.pop().or_else(|| {
            let slot = self.next_track;
            ((slot as usize) < MAX_TRACKS).then(|| {
                self.next_track += 1;
                slot
            })
        })
    }

    fn alloc_device(&mut self) -> Option<Slot> {
        self.free_devices.pop().or_else(|| {
            let slot = self.next_device;
            ((slot as usize) < MAX_DEVICES).then(|| {
                self.next_device += 1;
                slot
            })
        })
    }
}

/// Decoded audio files, loaded once and shared between clips.
#[derive(Default)]
pub struct AudioCache {
    files: HashMap<PathBuf, Option<Arc<AudioData>>>,
    summaries: HashMap<PathBuf, Arc<Summary>>,
    /// Recent answers to [`peaks`](Self::peaks), since views ask every frame.
    peaks: HashMap<PeaksKey, Arc<Vec<[f32; 3]>>>,
    /// Files at another rate than the engine's, converted, by file and rate.
    converted: HashMap<(PathBuf, u32), Arc<AudioData>>,
    /// Where waveform overviews are kept between runs (`peaks::Summary`),
    /// so that drawing a file need not decode it; nowhere when `None`.
    pub peak_dir: Option<PathBuf>,
    /// Where the decoded sound of long files is kept and played from,
    /// instead of memory; nowhere when `None`.
    pub store: Option<DiskStore>,
    /// Stretched and shifted versions of files, made apart: `stretched.rs`.
    pub renders: crate::stretched::Renders,
}

/// File, offset and length in seconds (as bits, to hash them), and points.
type PeaksKey = (PathBuf, u64, u64, usize);

impl AudioCache {
    /// A cache that keeps waveform overviews in `dir` between runs.
    pub fn with_peak_dir(dir: PathBuf) -> Self {
        Self {
            peak_dir: Some(dir),
            ..Self::default()
        }
    }

    /// Load a file, reporting why it could not be read.
    pub fn load(&mut self, path: &Path) -> anyhow::Result<Arc<AudioData>> {
        if let Some(Some(data)) = self.files.get(path) {
            return Ok(data.clone());
        }
        let loaded = AudioData::load_with(path, self.store.as_ref());
        self.files
            .insert(path.to_path_buf(), loaded.as_ref().ok().cloned());
        loaded
    }

    /// `n` (min, max) pairs covering `seconds` of a file from `offset`.
    pub fn peaks(
        &mut self,
        path: &Path,
        offset: f64,
        seconds: f64,
        n: usize,
    ) -> anyhow::Result<Arc<Vec<[f32; 3]>>> {
        let key = (path.to_path_buf(), offset.to_bits(), seconds.to_bits(), n);
        if let Some(peaks) = self.peaks.get(&key) {
            return Ok(peaks.clone());
        }
        let summary = self.summary(path)?;
        let rate = summary.sample_rate as f64;
        let from = offset * rate;
        let to = from + seconds * rate;
        let decoded = self.files.get(path).cloned().flatten();
        let peaks = match decoded {
            // Decoded already: exact to the sample.
            Some(data) => peaks::peaks(&data, &summary, from, to, n),
            None => match peaks::coarse(&summary, from, to, n) {
                // Zoomed out: the overview alone, without decoding the file.
                Some(peaks) => peaks,
                None => {
                    let data = self.load(path)?;
                    peaks::peaks(&data, &summary, from, to, n)
                }
            },
        };
        let peaks = Arc::new(peaks);
        // Zooming and editing leave old answers behind; a bound keeps them
        // from piling up without tracking which are still wanted.
        if self.peaks.len() >= 256 {
            self.peaks.clear();
        }
        self.peaks.insert(key, peaks.clone());
        Ok(peaks)
    }

    /// True when no file, nor anything worked out from one, is kept.
    pub fn holds_nothing(&self) -> bool {
        self.files.is_empty()
            && self.summaries.is_empty()
            && self.peaks.is_empty()
            && self.converted.is_empty()
            && self.renders.is_empty()
    }

    /// Forget every file but those in `keep`, and what was worked out from
    /// them (converted copies, overviews, peaks). Files a clip in the engine
    /// or a running render still plays stay in memory until they let go.
    pub fn retain(&mut self, keep: &std::collections::HashSet<PathBuf>) {
        self.files.retain(|path, _| keep.contains(path));
        self.summaries.retain(|path, _| keep.contains(path));
        self.peaks.retain(|key, _| keep.contains(&key.0));
        self.converted.retain(|key, _| keep.contains(&key.0));
        self.renders.retain(Some(keep));
    }

    /// What a stretched or shifted clip plays, if it has been made; if not,
    /// it is queued to be made (see `stretched.rs`).
    pub fn stretched(
        &mut self,
        key: &crate::stretched::Key,
        warnings: &mut Vec<String>,
    ) -> Option<Arc<AudioData>> {
        let store = self.store.clone();
        if self.renders.known(key) {
            return self.renders.get(key, store.as_ref(), || None);
        }
        let source = self.get(&key.file, key.rate, warnings);
        self.renders.get(key, store.as_ref(), || source)
    }

    /// What the engine plays of a file at `rate`, if it has been loaded:
    /// the file's own samples or their conversion.
    pub fn playing(&self, path: &Path, rate: u32) -> Option<&Arc<AudioData>> {
        let data = self.files.get(path)?.as_ref()?;
        if data.sample_rate == rate {
            return Some(data);
        }
        self.converted
            .get(&(path.to_path_buf(), rate))
            .or(Some(data))
    }

    /// Whether a file that has been loaded is played from the disk.
    pub fn on_disk(&self, path: &Path) -> Option<bool> {
        Some(self.files.get(path)?.as_ref()?.on_disk())
    }

    /// Forget the decoded files, so that each is loaded again when it is
    /// next asked for. Whatever plays one keeps what it has.
    pub fn forget_loaded(&mut self) {
        self.files.clear();
        self.converted.clear();
        self.renders.retain(None);
    }

    /// How many files are held, decoded or known to be unreadable.
    pub fn len(&self) -> usize {
        self.files.len()
    }

    pub fn is_empty(&self) -> bool {
        self.files.is_empty()
    }

    /// A file's waveform overview: kept in memory, read from the peak
    /// directory when it was made before for the file as it is now, or made
    /// from the samples and kept there.
    fn summary(&mut self, path: &Path) -> anyhow::Result<Arc<Summary>> {
        if let Some(summary) = self.summaries.get(path) {
            return Ok(summary.clone());
        }
        let stored = self
            .peak_dir
            .as_deref()
            .and_then(|dir| peaks::stored(dir, path));
        let summary = match stored
            .as_ref()
            .and_then(|(cached, _)| Summary::read(cached))
        {
            Some(summary) => summary,
            None => {
                let summary = Summary::new(&*self.load(path)?);
                if let Some((cached, _)) = &stored {
                    // A cache that cannot be written only costs time.
                    let _ = summary.write(cached);
                }
                summary
            }
        };
        let summary = Arc::new(summary);
        self.summaries.insert(path.to_path_buf(), summary.clone());
        Ok(summary)
    }

    /// A file for playing at `rate`: converted when it is at another.
    fn get(
        &mut self,
        path: &Path,
        rate: u32,
        warnings: &mut Vec<String>,
    ) -> Option<Arc<AudioData>> {
        let data = self.get_native(path, warnings)?;
        if data.sample_rate == rate {
            return Some(data);
        }
        let key = (path.to_path_buf(), rate);
        if let Some(converted) = self.converted.get(&key) {
            return Some(converted.clone());
        }
        // A long file converted is as long: it goes where the file went.
        let kept = self.store.as_ref().and_then(|store| {
            Some((store, paw_engine::store_name(path, &rate.to_string())?))
        });
        if let Some((store, name)) = &kept
            && let Some(converted) = store.open(name)
        {
            let converted = Arc::new(converted);
            self.converted.insert(key, converted.clone());
            return Some(converted);
        }
        match crate::resample::convert_into(&data, rate, paw_engine::Sink::new(kept)) {
            Ok(converted) => {
                let converted = Arc::new(converted);
                self.converted.insert(key, converted.clone());
                Some(converted)
            }
            Err(err) => {
                warnings.push(format!("{}: {err:#}", path.display()));
                Some(data)
            }
        }
    }

    fn get_native(&mut self, path: &Path, warnings: &mut Vec<String>) -> Option<Arc<AudioData>> {
        if let Some(known) = self.files.get(path) {
            return known.clone();
        }
        // A file that is not there is reported once, with the others
        // missing, when the project is opened (session/media.rs).
        let missing = !path.exists();
        self.load(path)
            .map_err(|err| {
                if !missing {
                    warnings.push(format!("{err:#}"))
                }
            })
            .ok()
    }
}

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
    let mut emit = |name: &str, payload: Value| events.push((name.to_string(), payload));

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
        send(Msg::SetTempoMap(Box::new(map)));
    }
    if retimed || old.name != new.name || old.meta != new.meta {
        emit("project.changed", json!({}));
    }
    // The same tracks in another order: nothing the engine needs to hear of,
    // but whoever draws the track list does.
    if old.tracks.len() == new.tracks.len()
        && old
            .tracks
            .iter()
            .zip(&new.tracks)
            .any(|(a, b)| a.id != b.id)
    {
        let order: Vec<Id> = new.tracks.iter().map(|t| t.id).collect();
        emit("track.moved", json!({ "order": order }));
    }

    let old_tracks: HashMap<Id, &Arc<Track>> = old.all_tracks().map(|t| (t.id, t)).collect();
    let old_devices: HashMap<Id, &Arc<DeviceInst>> = old
        .all_tracks()
        .flat_map(|t| &t.devices)
        .map(|d| (d.id, d))
        .collect();
    let mut clips_changed = false;
    let mut lanes_changed = false;
    // The schedule lists slots, so a track that gets one needs a new schedule.
    let mut new_slots = false;
    // Side-chains name device slots, so a device that gets one does too.
    let mut device_slots = false;
    let mut removals = Vec::new();
    // Frozen tracks play a file, and what feeds them is held.
    let mut played = crate::freeze::played(new, &map.held_files);

    for track in new.all_tracks() {
        let prev = old_tracks.get(&track.id).copied();
        // A track the engine had no room for is built whole once there is room.
        let fresh = !map.tracks.contains_key(&track.id);
        // Notes an attribute map moves by seconds land by the tempo map.
        let retimed_notes = retimed && track.attr_map.as_ref().is_some_and(|m| m.has_delay());
        let plays = played.get(&track.id).cloned().unwrap_or(Played::Live);
        let replayed = map.played.get(&track.id).unwrap_or(&Played::Live) != &plays;
        if !fresh && !replayed && !retimed_notes && prev.is_some_and(|p| Arc::ptr_eq(p, track)) {
            continue;
        }
        if fresh {
            let Some(slot) = map.alloc_track() else {
                if prev.is_none() {
                    ctx.warnings
                        .push(format!("too many tracks: `{}` will be silent", track.name));
                }
                continue;
            };
            map.tracks.insert(track.id, slot);
            new_slots = true;
            send(Msg::InsertTrack {
                slot,
                track: TrackRt::new(),
            });
        }
        match prev {
            None => emit("track.added", json!({ "id": track.id })),
            Some(p) if !Arc::ptr_eq(p, track) => emit("track.changed", json!({ "id": track.id })),
            Some(_) => {}
        }
        // From here on, a track that has only now got a slot counts as new.
        let prev = prev.filter(|_| !fresh);
        let Some(&slot) = map.tracks.get(&track.id) else {
            continue;
        };

        // Devices set offline or back online since: gone from the engine,
        // or made, and the chain sent again.
        let mut toggled = false;
        for device in &track.devices {
            match old_devices.get(&device.id).filter(|_| prev.is_some()) {
                Some(before) if before.offline != device.offline => {
                    toggled = true;
                    device_slots = true;
                    map.keyed.remove(&device.id);
                    map.outs.remove(&device.id);
                    if device.offline {
                        ctx.live.remove(&device.id);
                        if let Some(slot) = map.devices.remove(&device.id) {
                            removals.push(Msg::RemoveDevice { slot });
                            map.free_devices.push(slot);
                        }
                    } else {
                        add_device(device, map, ctx, send);
                    }
                    emit(
                        "device.changed",
                        json!({ "id": device.id, "track": track.id }),
                    );
                }
                None => {
                    add_device(device, map, ctx, send);
                    device_slots = true;
                    if !old_devices.contains_key(&device.id) {
                        emit(
                            "device.added",
                            json!({ "id": device.id, "track": track.id }),
                        );
                    }
                }
                Some(before) if !Arc::ptr_eq(before, device) => {
                    update_device(before, device, map, ctx, send);
                    emit(
                        "device.changed",
                        json!({ "id": device.id, "track": track.id }),
                    );
                }
                Some(_) => {}
            }
        }
        let same_chain = !toggled
            && prev.is_some_and(|p| {
                p.devices
                    .iter()
                    .map(|d| d.id)
                    .eq(track.devices.iter().map(|d| d.id))
            });
        if !same_chain {
            let chain: Box<[Slot]> = track
                .devices
                .iter()
                .filter_map(|d| map.devices.get(&d.id).copied())
                .collect();
            send(Msg::SetChain { track: slot, chain });
        }
        // A frozen or held track's devices are held in the engine only: the
        // model keeps its own bypass, which comes back when it thaws.
        let held = plays != Played::Live;
        if held || replayed {
            for device in &track.devices {
                if let Some(&device_slot) = map.devices.get(&device.id) {
                    send(Msg::SetBypass {
                        device: device_slot,
                        bypass: device.bypass || held,
                    });
                }
            }
        }

        let same_clips = !retimed_notes
            && prev.is_some_and(|p| {
            p.attr_map == track.attr_map && p.clips.same(&track.clips)
        });
        if !same_clips {
            clips_changed = true;
        }
        if !same_clips || replayed {
            // A few clips changed: the engine is sent only theirs.
            let edit = match (&plays, prev) {
                (Played::Live, Some(p)) if !replayed && !retimed_notes && p.attr_map == track.attr_map => {
                    edit_parts(p, track, new.tempo_map(), map, ctx)
                }
                _ => None,
            };
            match edit {
                Some(edit) => send(Msg::EditClips {
                    track: slot,
                    edit: Box::new(edit),
                }),
                None => {
                    let clips = match &plays {
                        Played::Live => build_clips(track, new.tempo_map(), map, ctx),
                        Played::Frozen(file) => {
                            map.parts.remove(&track.id);
                            frozen_clips(file, new.tempo_map(), ctx)
                        }
                        Played::Held => {
                            map.parts.remove(&track.id);
                            ClipSet::default()
                        }
                    };
                    send(Msg::SetClips {
                        track: slot,
                        clips: Box::new(clips),
                    });
                }
            }
        }

        let same_cues = !(retimed_notes && !track.cues.is_empty())
            && prev.map_or(track.cues.is_empty(), |p| {
            p.attr_map == track.attr_map && p.cues.same(&track.cues)
        });
        if !same_cues || (replayed && !track.cues.is_empty()) {
            let rows = cue_rows(map.cue_rows.remove(&track.id).unwrap_or_default(), track);
            let slots = if held {
                Slots::default()
            } else {
                build_cues(track, &rows, new.tempo_map(), map, ctx)
            };
            if !rows.is_empty() {
                map.cue_rows.insert(track.id, rows);
            }
            send(Msg::SetSlots {
                track: slot,
                slots: Box::new(slots),
            });
            if !same_cues {
                emit("cue.changed", json!({ "track": track.id }));
            }
        }
        match played.remove(&track.id) {
            Some(plays) => map.played.insert(track.id, plays),
            None => map.played.remove(&track.id),
        };

        let same_lanes = prev.map_or(track.lanes.is_empty(), |p| {
            p.lanes.len() == track.lanes.len()
                && p.lanes
                    .iter()
                    .zip(&track.lanes)
                    .all(|(a, b)| Arc::ptr_eq(a, b))
        });
        // A lane's compiled form names device slots, so a new chain needs it rebuilt.
        if !same_lanes || (!same_chain && !track.lanes.is_empty()) {
            lanes_changed |= !same_lanes;
            send(Msg::SetAutomation {
                track: slot,
                automation: Box::new(build_automation(track, new, map, ctx)),
            });
        }
        if let Some(prev) = prev.filter(|_| !same_lanes) {
            release_targets(prev, track, map, ctx, send);
        }
    }

    let new_devices: HashSet<Id> = new
        .all_tracks()
        .flat_map(|t| &t.devices)
        .map(|d| d.id)
        .collect();
    for id in old_devices.keys().filter(|id| !new_devices.contains(id)) {
        ctx.live.remove(id);
        map.host_latency.remove(id);
        map.keyed.remove(id);
        map.outs.remove(id);
        if let Some(slot) = map.devices.remove(id) {
            removals.push(Msg::RemoveDevice { slot });
            map.free_devices.push(slot);
        }
        emit("device.removed", json!({ "id": id }));
    }

    // Only tracks that are not the very same in both snapshots can have
    // gained, lost or changed a clip or a lane.
    let new_tracks: HashMap<Id, &Arc<Track>> = new.all_tracks().map(|t| (t.id, t)).collect();
    let touched = |id: Id| match (old_tracks.get(&id), new_tracks.get(&id)) {
        (Some(a), Some(b)) => !Arc::ptr_eq(a, b),
        _ => true,
    };
    if clips_changed {
        item_events(
            "clip",
            (&old_tracks, &new_tracks),
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
    if lanes_changed {
        item_events(
            "lane",
            (&old_tracks, &new_tracks),
            &touched,
            |was, t| (was.map_or(Vec::new(), |w| w.lanes.iter().collect()), t.lanes.iter().collect()),
            |l| l.id,
            &mut emit,
        );
    }

    // A track the VCAs it is in have changed the fader lane of is told so,
    // and takes its own fader value back when it no longer has one.
    for track in new.all_tracks() {
        let Some(&slot) = map.tracks.get(&track.id) else {
            continue;
        };
        let lane = vca_volume_lane(track, new);
        if lane.as_ref() != map.vca_lanes.get(&track.id) {
            match lane {
                Some(points) => map.vca_lanes.insert(track.id, points),
                None => map.vca_lanes.remove(&track.id),
            };
            map.mix.remove(&track.id);
            send(Msg::SetAutomation {
                track: slot,
                automation: Box::new(build_automation(track, new, map, ctx)),
            });
        }
    }

    let soloed = soloed_tracks(new);
    let sounding = if soloed.is_empty() {
        HashSet::new()
    } else {
        solo_paths(new, &soloed)
    };
    // What the session lets be heard for now: as a solo, but not the model's.
    let audible = map
        .audible
        .as_ref()
        .map(|ids| solo_paths(new, &ids.iter().copied().filter(|id| new.track(*id).is_some()).collect()));
    map.played.retain(|id, _| new.track(*id).is_some());
    for track in new.all_tracks() {
        let Some(&slot) = map.tracks.get(&track.id) else {
            continue;
        };
        let silenced = track.id != MASTER_ID
            && ((!soloed.is_empty() && !sounding.contains(&track.id))
                || audible.as_ref().is_some_and(|a| !a.contains(&track.id))
                || map.played.get(&track.id) == Some(&Played::Held));
        let vcas = vcas_of(track, new);
        let mix = (
            db_to_gain(track.volume + vcas.iter().map(|v| v.volume).sum::<f64>()),
            track.pan as f32,
            track.mute || vcas.iter().any(|v| v.mute),
            silenced,
        );
        if map.mix.get(&track.id) != Some(&mix) {
            map.mix.insert(track.id, mix);
            send(Msg::SetMix {
                slot,
                gain: mix.0,
                pan: mix.1,
                mute: mix.2,
                quiet: mix.3,
            });
        }
    }

    // The selected track plays the MIDI keyboard while no track is armed.
    let follow = map
        .follow
        .filter(|_| !new.tracks.iter().any(|t| t.armed));
    for track in new.all_tracks() {
        let Some(&slot) = map.tracks.get(&track.id) else {
            continue;
        };
        let (first, channels) = track.input_channels().unwrap_or((0, 0));
        // An armed track is always heard, so that what is recorded is what
        // the player hears; the monitor switch is for hearing it otherwise.
        let followed = follow == Some(track.id) && channels == 0 && track.id != MASTER_ID;
        let input = (first, channels, track.armed || track.monitor || followed, track.armed);
        if map.inputs.get(&track.id) != Some(&input) {
            map.inputs.insert(track.id, input);
            send(Msg::SetInput {
                track: slot,
                first,
                channels,
                monitor: input.2,
                armed: track.armed,
            });
        }
        let midi = track.midi_input.as_ref().map_or((0, 0), |m| {
            (
                m.port.as_deref().map_or(0, paw_engine::midi::port_key),
                m.channel.unwrap_or(0),
            )
        });
        if map.midi_inputs.get(&track.id).copied().unwrap_or((0, 0)) != midi {
            map.midi_inputs.insert(track.id, midi);
            send(Msg::SetMidiInput {
                track: slot,
                port: midi.0,
                channel: midi.1,
            });
        }
        let out = track.midi_output.as_ref().map_or((0, 0, Form::Auto), |m| {
            (
                paw_engine::midi::port_key(&m.port),
                m.channel.unwrap_or(0),
                m.engine_form(),
            )
        });
        if map.midi_outputs.get(&track.id).copied().unwrap_or((0, 0, Form::Auto)) != out {
            map.midi_outputs.insert(track.id, out);
            send(Msg::SetMidiOutput {
                track: slot,
                port: out.0,
                channel: out.1,
                form: out.2,
            });
        }
    }

    // A device whose latency changed: its dry signal is held back to match.
    for (id, live) in ctx.live.iter() {
        if let Some(&slot) = map.devices.get(id)
            && map.host_latency.get(id) != Some(&live.latency)
        {
            map.host_latency.insert(*id, live.latency);
            send(Msg::SetDeviceLatency {
                device: slot,
                frames: live.latency,
            });
        }
    }
    let routing = routing_of(new, ctx.live, &map.played);
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
    let routes_moved = device_slots
        && routing
            .iter()
            .any(|r| !r.keys.is_empty() || !r.outs.is_empty());
    if routing != map.routing || new_slots || routes_moved {
        let schedule = build_schedule(&routing, map);
        map.latency = schedule.latency;
        send(Msg::SetSchedule(Box::new(schedule)));
        map.routing = routing;
    }

    for id in old_tracks.keys().filter(|id| new.track(**id).is_none()) {
        map.parts.remove(id);
        map.cue_rows.remove(id);
        map.cue_events.remove(id);
        if let Some(slot) = map.tracks.remove(id) {
            // Notes it left sounding on its MIDI output port end there.
            if map.midi_outputs.get(id).is_some_and(|(port, ..)| *port != 0) {
                removals.push(Msg::SetMidiOutput {
                    track: slot,
                    port: 0,
                    channel: 0,
                    form: Form::Auto,
                });
            }
            removals.push(Msg::RemoveTrack { slot });
            map.free_tracks.push(slot);
        }
        map.mix.remove(id);
        map.inputs.remove(id);
        map.midi_inputs.remove(id);
        map.midi_outputs.remove(id);
        emit("track.removed", json!({ "id": id }));
    }
    // Removals go last, once nothing in the schedule or a chain refers to them.
    removals.into_iter().for_each(&mut *send);

    deliver_clips(new, ctx);

    if events.len() > before {
        events.push(("changed".to_string(), json!({})));
    }
}

/// Whether a device takes its track's clips ([`paw_engine::device::CLIPS`]).
#[derive(Clone, Debug, Default, PartialEq)]
pub enum TakesClips {
    /// Not asked yet.
    #[default]
    Unasked,
    /// It does not know the call: not asked again.
    No,
    /// It took them; this is what it was given last.
    Given(String),
}

/// Give each device that keeps files (a plugin an attachment took) the
/// audio clips of its track and the tempo, when they changed since it was
/// given them last; the first time, to find out whether it takes them.
pub fn deliver_clips(project: &Project, ctx: &mut SyncCtx) {
    for (id, live) in ctx.live.iter_mut() {
        if !live.attached || live.clips == TakesClips::No || live.stopped.is_some() {
            continue;
        }
        let Some(controller) = live.controller.as_mut() else {
            continue;
        };
        let Some(track) = project
            .find_device(*id)
            .and_then(|(track, _)| project.all_tracks().find(|t| t.id == track))
        else {
            continue;
        };
        let text = clips_json(project, track).to_string();
        if live.clips == TakesClips::Given(text.clone()) {
            continue;
        }
        match controller.call(paw_engine::device::CLIPS, text.as_bytes()) {
            Ok(_) => live.clips = TakesClips::Given(text),
            Err(err) => {
                if matches!(live.clips, TakesClips::Given(_)) {
                    ctx.warnings.push(format!("a device did not take the clips: {err:#}"));
                }
                live.clips = TakesClips::No;
            }
        }
    }
}

/// A track's audio clips and the song's tempo, as a device that reads
/// whole clips (an ARA plugin) is given them: times in seconds from the
/// start of the song, and the tempo as points of seconds and beats.
pub fn clips_json(project: &Project, track: &Track) -> Value {
    let map = project.tempo_map();
    let clips: Vec<Value> = track
        .clips
        .iter()
        .filter_map(|clip| {
            let ClipContent::Audio { file, offset, gain, .. } = &clip.content else {
                return None;
            };
            let start = map.seconds(clip.start);
            let end = map.seconds(clip.start + clip.length);
            Some(json!({
                "id": clip.id,
                "name": clip.name,
                "file": file,
                "offset": offset,
                "start": start,
                "length": end - start,
                "stretch": clip.stretch,
                "gain": gain,
                "muted": clip.muted,
            }))
        })
        .collect();
    // A point at each tempo change and at its end, enough for a plugin to
    // place every beat: the tempo between two points is constant, or a ramp
    // given by more points.
    let mut tempo = Vec::new();
    let end = track
        .clips
        .iter()
        .map(|c| c.start + c.length)
        .fold(0.0f64, f64::max);
    let points = project.tempo_points();
    let mut beats = Vec::new();
    for (i, p) in points.iter().enumerate() {
        beats.push(p.beat);
        // A ramp is given as a point on each beat up to the next change.
        if p.ramp {
            let next = points.get(i + 1).map_or(end, |n| n.beat);
            let mut beat = p.beat + 1.0;
            while beat < next && beats.len() < 4096 {
                beats.push(beat);
                beat += 1.0;
            }
        }
    }
    beats.push(end.max(beats.last().copied().unwrap_or(0.0)) + 1.0);
    beats.sort_by(f64::total_cmp);
    beats.dedup();
    for beat in beats {
        tempo.push(json!({ "seconds": map.seconds(beat), "beat": beat }));
    }
    let signatures: Vec<Value> = project
        .sig_points()
        .iter()
        .map(|s| json!({ "beat": s.beat, "num": s.num, "den": s.den }))
        .collect();
    json!({
        "track": { "id": track.id, "name": track.name },
        "clips": clips,
        "tempo": tempo,
        "signatures": signatures,
    })
}

fn add_device(device: &DeviceInst, map: &mut Mapper, ctx: &mut SyncCtx, send: &mut dyn FnMut(Msg)) {
    // Set offline: not made, and passed over in the chain.
    if device.offline {
        return;
    }
    let Some(factory) = ctx.registry.get(&device.kind) else {
        ctx.warnings.push(format!(
            "`{}` is not installed: it is passed over, and kept with its saved state",
            device.name.as_deref().unwrap_or(&device.kind)
        ));
        return;
    };
    if map.defer && !ctx.offline && factory.starts_apart() {
        let Some(slot) = map.alloc_device() else {
            ctx.warnings.push(format!(
                "too many devices: `{}` will be skipped",
                device.kind
            ));
            return;
        };
        // Until it is made: an instrument is silent, an effect passes
        // the sound through.
        let instrument = factory.info().category == "instrument";
        map.devices.insert(device.id, slot);
        map.deferred.push(device.id);
        send(Msg::InsertDevice {
            slot,
            device: Box::new(Standin { instrument }),
        });
        return;
    }
    let instance = match factory.create(ctx.sample_rate, MAX_BLOCK) {
        Ok(instance) => instance,
        Err(err) => {
            ctx.warnings
                .push(format!("could not load `{}`: {err:#}", device.kind));
            return;
        }
    };
    let Some(slot) = map.alloc_device() else {
        ctx.warnings.push(format!(
            "too many devices: `{}` will be skipped",
            device.kind
        ));
        return;
    };
    let mut controller = instance.controller;
    if let (Some(controller), true) = (controller.as_mut(), ctx.offline) {
        controller.set_offline(true);
    }
    if let (Some(controller), Some(state)) = (controller.as_mut(), &device.state) {
        let loaded = BASE64
            .decode(state)
            .map_err(anyhow::Error::from)
            .and_then(|bytes| controller.load_state(&bytes));
        if let Err(err) = loaded {
            ctx.warnings.push(format!(
                "could not restore the state of `{}`: {err:#}",
                device.kind
            ));
        }
    }
    if let Some(controller) = controller.as_mut() {
        deliver_posts(&device.kind, controller.as_mut(), ctx);
    }
    let attached = controller
        .as_mut()
        .is_some_and(|c| give_files(device, c.as_mut(), ctx));
    let mut params = match &controller {
        Some(controller) => controller.params(),
        None => factory.info().params.clone(),
    };
    rekey(&mut params, &device.param_ids);
    // The host's wet/dry mix and gain come after the device's own.
    let own = params.len();
    params.extend(paw_engine::host::params());
    let params = Arc::new(params);
    let latency = match &controller {
        Some(controller) => controller.latency(),
        None => factory.latency(ctx.sample_rate),
    };
    map.devices.insert(device.id, slot);
    send(Msg::InsertDevice {
        slot,
        device: instance.device,
    });
    send(Msg::SetHost {
        device: slot,
        path: Box::new(paw_engine::host::HostPath::new(
            own as u32, latency, MAX_BLOCK,
        )),
    });
    for (index, param) in params.iter().enumerate() {
        if let Some(&value) = device.params.get(&param.key) {
            let value = param_value(param, value);
            send(Msg::SetParam {
                device: slot,
                param: index as u32,
                value: value as f32,
            });
            if let Some(controller) = controller.as_mut().filter(|_| index < own) {
                controller.set_value(index, value);
            }
        }
    }
    if device.bypass {
        send(Msg::SetBypass {
            device: slot,
            bypass: true,
        });
    }
    // A parameter can change how late the device is (a look-ahead): ask
    // again now that they are set, and hold the dry signal back to match.
    let latency = match &controller {
        Some(controller) => controller.latency(),
        None => latency,
    };
    send(Msg::SetDeviceLatency {
        device: slot,
        frames: latency,
    });
    ctx.live.insert(
        device.id,
        LiveDevice {
            params,
            controller,
            latency,
            stopped: None,
            attached,
            clips: TakesClips::Unasked,
        },
    );
}

/// Give a device that was just made the files it keeps beside its state
/// ([`paw_engine::device::FILE_LOAD`]), none the first time. Whether it
/// keeps such files: a device that does not know the call keeps none.
fn give_files(device: &DeviceInst, controller: &mut dyn paw_engine::Controller, ctx: &mut SyncCtx) -> bool {
    let mut files = Vec::new();
    for (name, text) in &device.files {
        match BASE64.decode(text) {
            Ok(bytes) => files.push((name.clone(), bytes)),
            Err(err) => ctx.warnings.push(format!("the {name} file of `{}`: {err}", device.kind)),
        }
    }
    match controller.call(paw_engine::device::FILE_LOAD, &paw_engine::device::pack_files(&files)) {
        Ok(_) => true,
        Err(err) => {
            if !files.is_empty() {
                ctx.warnings
                    .push(format!("`{}` did not take its files: {err:#}", device.kind));
            }
            false
        }
    }
}

/// Give a device that was just made what scripts posted to its kind
/// ([`Registry::post`](paw_engine::Registry::post)), before its first block.
fn deliver_posts(kind: &str, controller: &mut dyn paw_engine::Controller, ctx: &mut SyncCtx) {
    for (topic, data) in ctx.registry.posts(kind) {
        if let Err(err) = controller.call(topic, data) {
            ctx.warnings
                .push(format!("`{kind}` did not take `{topic}`: {err:#}"));
        }
    }
}

/// Give each parameter the key the project knows it by, found by the
/// device's own id for it (`ids`, key to id): a plugin whose new version
/// orders or names its parameters otherwise keeps the project's values and
/// lanes. A parameter that had the key before takes the other's.
pub fn rekey(params: &mut [ParamInfo], ids: &BTreeMap<String, String>) {
    for (key, id) in ids {
        let Some(at) = params.iter().position(|p| !p.id.is_empty() && &p.id == id) else {
            continue;
        };
        if &params[at].key == key {
            continue;
        }
        let old = std::mem::replace(&mut params[at].key, key.clone());
        if let Some(other) = params
            .iter()
            .enumerate()
            .position(|(i, p)| i != at && &p.key == key)
        {
            params[other].key = old;
        }
    }
}

/// Whether a device's parameter is one of the host's (see `paw_engine::host`):
/// the last two, by those keys.
pub fn is_host(params: &[ParamInfo], index: usize) -> bool {
    index + 2 >= params.len()
        && params
            .get(index)
            .is_some_and(|p| p.key == paw_engine::host::WET || p.key == paw_engine::host::GAIN)
}

/// What stands in the engine for a device that is still being made.
struct Standin {
    instrument: bool,
}

impl paw_engine::Device for Standin {
    fn process(&mut self, _ctx: &paw_engine::ProcessCtx, io: &mut paw_engine::Io) {
        if self.instrument {
            io.left.fill(0.0);
            io.right.fill(0.0);
        }
    }

    fn set_param(&mut self, _index: u32, _value: f32) {}
}

/// Put a device that was made apart (see [`Mapper::defer`]) in place of its
/// stand-in, its state already loaded, with the project's parameters and
/// bypass applied.
pub fn install(
    device: &DeviceInst,
    instance: paw_engine::Instance,
    map: &Mapper,
    ctx: &mut SyncCtx,
    send: &mut dyn FnMut(Msg),
) {
    let Some(&slot) = map.devices.get(&device.id) else {
        return;
    };
    let mut controller = instance.controller;
    if let Some(controller) = controller.as_mut() {
        deliver_posts(&device.kind, controller.as_mut(), ctx);
    }
    let attached = controller
        .as_mut()
        .is_some_and(|c| give_files(device, c.as_mut(), ctx));
    let mut params = match &controller {
        Some(controller) => controller.params(),
        None => ctx
            .registry
            .get(&device.kind)
            .map(|f| f.info().params.clone())
            .unwrap_or_default(),
    };
    rekey(&mut params, &device.param_ids);
    // The host's wet/dry mix and gain come after the device's own.
    let own = params.len();
    params.extend(paw_engine::host::params());
    let params = Arc::new(params);
    let latency = controller.as_ref().map_or(0, |c| c.latency());
    send(Msg::InsertDevice {
        slot,
        device: instance.device,
    });
    send(Msg::SetHost {
        device: slot,
        path: Box::new(paw_engine::host::HostPath::new(
            own as u32, latency, MAX_BLOCK,
        )),
    });
    for (index, param) in params.iter().enumerate() {
        if let Some(&value) = device.params.get(&param.key) {
            let value = param_value(param, value);
            send(Msg::SetParam {
                device: slot,
                param: index as u32,
                value: value as f32,
            });
            if let Some(controller) = controller.as_mut().filter(|_| index < own) {
                controller.set_value(index, value);
            }
        }
    }
    if device.bypass {
        send(Msg::SetBypass {
            device: slot,
            bypass: true,
        });
    }
    // A parameter can change how late the device is (a look-ahead): ask
    // again now that they are set, and hold the dry signal back to match.
    let latency = match &controller {
        Some(controller) => controller.latency(),
        None => latency,
    };
    send(Msg::SetDeviceLatency {
        device: slot,
        frames: latency,
    });
    ctx.live.insert(
        device.id,
        LiveDevice {
            params,
            controller,
            latency,
            stopped: None,
            attached,
            clips: TakesClips::Unasked,
        },
    );
}

fn update_device(
    before: &DeviceInst,
    device: &DeviceInst,
    map: &Mapper,
    ctx: &mut SyncCtx,
    send: &mut dyn FnMut(Msg),
) {
    let (Some(&slot), Some(live)) = (map.devices.get(&device.id), ctx.live.get_mut(&device.id))
    else {
        return;
    };
    // A preset was loaded, or that was undone: the state goes in first, and
    // the preset's parameters on top of it. What the preset leaves out is
    // what the state says, not the default.
    let preset = device.loaded != before.loaded;
    let with_state = preset && device.state.is_some() && live.controller.is_some();
    if with_state && let Some(controller) = live.controller.as_mut() {
        let loaded = BASE64
            .decode(device.state.as_deref().unwrap_or(""))
            .map_err(anyhow::Error::from)
            .and_then(|bytes| controller.load_state(&bytes));
        if let Err(err) = loaded {
            ctx.warnings.push(format!(
                "could not load the preset into `{}`: {err:#}",
                device.kind
            ));
        }
    }
    for (index, param) in live.params.iter().enumerate() {
        let value = device.params.get(&param.key).copied();
        if with_state && value.is_none() {
            continue;
        }
        if value != before.params.get(&param.key).copied() || (with_state && value.is_some()) {
            let value = param_value(param, value.unwrap_or(param.default as f64));
            send(Msg::SetParam {
                device: slot,
                param: index as u32,
                value: value as f32,
            });
            if let Some(controller) = live
                .controller
                .as_mut()
                .filter(|_| !is_host(&live.params, index))
            {
                controller.set_value(index, value);
            }
        }
    }
    if device.state != before.state
        && !with_state
        && let Some(controller) = live.controller.as_mut().filter(|c| c.follows_state())
    {
        let loaded = BASE64
            .decode(device.state.as_deref().unwrap_or(""))
            .map_err(anyhow::Error::from)
            .and_then(|bytes| controller.load_state(&bytes));
        if let Err(err) = loaded {
            ctx.warnings.push(format!(
                "could not load the state of `{}`: {err:#}",
                device.kind
            ));
        }
    }
    if device.bypass != before.bypass {
        send(Msg::SetBypass {
            device: slot,
            bypass: device.bypass,
        });
    }
}

/// One MIDI clip's notes and controller moves as engine events, sorted. A
/// looped clip plays what lies in its repeated stretch over and over, each
/// note cut at the end of its repeat.
fn compile_clip(clip: &Clip, notes: &Notes, controls: &[Control]) -> Arc<[MidiEv]> {
    let mut set = ClipSet::default();
    let Some((from, beats)) = clip.repeat() else {
        return compile_part(clip, notes, controls);
    };
    let inside = |at: f64| at >= from && at < from + beats;
    for (base, end) in repeats(from, beats, clip.length) {
        let place = |at: f64| base + (at - from);
        for control in controls.iter().filter(|c| inside(c.start)) {
            let at = place(control.start);
            if at >= 0.0 && at < clip.length {
                set.push_event(clip.start + at, control.event(0));
            }
        }
        for note in notes.iter().filter(|n| inside(n.start)) {
            let at = place(note.start);
            if at >= 0.0 && at < clip.length {
                let stop = (at + note.length).min(end);
                let vel = note.velocity.clamp(1, 127) as f32 / 127.0;
                let (start, stop) = (clip.start + at, clip.start + stop);
                set.push_note_attr(start, stop, note.pitch, vel, attr_of(note));
            }
        }
    }
    set.finish();
    set.midi.into()
}

/// Some of the notes and controllers of a clip that does not loop, as
/// engine events: what [`compile_clip`] makes of them all.
fn compile_part<'a>(
    clip: &Clip,
    notes: impl IntoIterator<Item = &'a Note>,
    controls: &[Control],
) -> Arc<[MidiEv]> {
    let mut set = ClipSet::default();
    for control in controls
        .iter()
        .filter(|c| c.start >= 0.0 && c.start < clip.length)
    {
        set.push_event(clip.start + control.start, control.event(0));
    }
    for note in notes
        .into_iter()
        .filter(|n| n.start >= 0.0 && n.start < clip.length)
    {
        let end = (note.start + note.length).min(clip.length);
        let vel = note.velocity.clamp(1, 127) as f32 / 127.0;
        let (start, end) = (clip.start + note.start, clip.start + end);
        set.push_note_attr(start, end, note.pitch, vel, attr_of(note));
    }
    set.finish();
    set.midi.into()
}

/// A note's attribute as the engine has it.
fn attr_of(note: &Note) -> paw_engine::Attr {
    note.attr.map_or(paw_engine::Attr::NONE, Into::into)
}

/// Where each repeat of a looped clip begins and ends, from the clip's
/// start, for a repeated stretch beginning at `from` and `period` long, in
/// a clip `length` long: the first begins at or before 0, the last ends
/// at `length` or later. In beats for MIDI, in seconds for sound.
pub fn repeats(from: f64, period: f64, length: f64) -> impl Iterator<Item = (f64, f64)> {
    // The repeat the clip's start falls in.
    let first = from - period * (from / period).ceil();
    let count = if period > 0.0 {
        ((length - first) / period).ceil().max(0.0) as usize
    } else {
        0
    };
    (0..count).map(move |k| {
        let a = first + k as f64 * period;
        (a, first + (k + 1) as f64 * period)
    })
}

/// Whether sound repeated from `from` for `seconds` runs on from its end
/// into its start without a jump: the frame after its end is about the
/// frame at its start, as near as one frame is to the next around there.
fn joins_itself(data: &AudioData, from: f64, seconds: f64) -> bool {
    let rate = data.sample_rate as f64;
    let (a, b) = (
        (from * rate).round() as i64,
        ((from + seconds) * rate).round() as i64,
    );
    let at = |c: &[f32], i: i64| {
        usize::try_from(i)
            .ok()
            .and_then(|i| c.get(i))
            .copied()
            .unwrap_or(0.0)
    };
    data.channels.iter().all(|c| {
        let jump = (at(c, b) - at(c, a)).abs();
        let step = [a, b]
            .iter()
            .flat_map(|&i| {
                [
                    (at(c, i) - at(c, i - 1)).abs(),
                    (at(c, i + 1) - at(c, i)).abs(),
                ]
            })
            .fold(0.0, f32::max);
        jump <= 2.0 * step + 1e-4
    })
}

/// The regions an audio clip plays: the part of `data` from `offset`
/// seconds, or, looped, its repeated stretch again and again. A fade in
/// belongs to the first repeat and a fade out to the last, each as long
/// as that repeat at most.
fn audio_regions(
    clip: &Clip,
    data: Arc<AudioData>,
    offset: f64,
    gain: f32,
    tempo: &paw_engine::TempoMap,
    out: &mut Vec<AudioRegion>,
) {
    let seconds = tempo.seconds_between(clip.start, clip.start + clip.length);
    let end = clip.start + clip.length;
    let Some((from, beats)) = clip.repeat() else {
        out.push(AudioRegion {
            start: clip.start,
            end,
            // An edge inside the recording is a cut.
            declick_in: offset > 1e-6,
            declick_out: offset + seconds < data.whole_seconds() - 1e-6,
            data,
            offset,
            gain,
            fade_in: clip.fade_in,
            fade_out: clip.fade_out,
            hold: Default::default(),
        });
        return;
    };
    // A repeat lasts as long in seconds as its beats do from the clip's start.
    let period = tempo.seconds_between(clip.start, clip.start + beats);
    if period <= 1e-9 {
        return;
    }
    let lead = from * period / beats;
    let begins = offset + lead;
    let joins = joins_itself(&data, begins, period);
    let t0 = tempo.seconds(clip.start);
    let first = out.len();
    for (a, b) in repeats(lead, period, seconds) {
        let (ra, rb) = (a.max(0.0), b.min(seconds));
        if rb - ra <= 1e-9 {
            continue;
        }
        let into = begins + (ra - a);
        let start = if ra <= 0.0 {
            clip.start
        } else {
            tempo.beat(t0 + ra)
        };
        let stop = if rb >= seconds {
            end
        } else {
            tempo.beat(t0 + rb)
        };
        out.push(AudioRegion {
            start,
            end: stop,
            declick_in: if ra <= 0.0 { into > 1e-6 } else { !joins },
            declick_out: if rb >= seconds {
                into + (rb - ra) < data.whole_seconds() - 1e-6
            } else {
                !joins
            },
            data: data.clone(),
            offset: into,
            gain,
            fade_in: 0.0,
            fade_out: 0.0,
            hold: Default::default(),
        });
    }
    if let Some(r) = out.get_mut(first) {
        r.fade_in = clip.fade_in.min(r.end - r.start);
    }
    if out.len() > first
        && let Some(r) = out.last_mut()
    {
        r.fade_out = clip.fade_out.min(r.end - r.start);
    }
}

/// Everything a track plays. A MIDI clip that is the very same as at the
/// last sync reuses its events; the track's events are those of its clips in
/// order, sorted again (stably, so the result is what sorting all the notes at
/// once gives, and nearly free when the clips follow each other in time).
/// What the engine has of a track's clips, sent as parts: one for each
/// clip, or for a long MIDI clip one for its controllers and one for each
/// few runs of its notes (see [`Notes`]), so that a note edited compiles
/// again only the notes beside it.
#[derive(Default)]
struct Parts {
    /// Each clip by id, as compiled and sent.
    clips: HashMap<Id, Sent>,
    /// How many parts the engine has, and room for.
    len: usize,
    room: usize,
    /// The clips were sent as one list, through the track's attribute map:
    /// only their events are kept, to compile only what changed.
    flat: bool,
}

/// One clip as the engine was sent it.
struct Sent {
    clip: Arc<Clip>,
    /// Its order (see [`paw_engine::Part::order`]); its parts have this
    /// order and those after it, one each.
    order: u64,
    /// Its events in pieces (see [`pieces_of`]); none for an audio clip.
    pieces: Vec<Piece>,
    /// The orders of the parts the engine has of it: those not empty.
    parts: Vec<u64>,
}

// The pointers only name runs to compare with: never read through.
unsafe impl Send for Sent {}

/// The space between the orders of two clips side by side when a track's
/// parts are sent whole: clips put in between later take orders between.
const ORDER_GAP: u64 = 1 << 32;
/// An edit of more clips than this sends the track's clips whole.
const MAX_EDIT: usize = 512;

/// The runs of notes a piece is compiled from (none for the controllers,
/// or for a clip in one piece), and its events.
type Piece = (Vec<*const Vec<Note>>, Arc<[MidiEv]>);

/// Notes in a piece of a clip's events: runs side by side go in one piece
/// until it has this many.
const PIECE: usize = 256;

/// The pieces of a clip's events: its controllers and its notes in pieces
/// of a few runs (in that order, which is the order a clip's events are
/// compiled in); a short or looped clip in one piece. A piece of the very
/// same runs as one of the clip `before` is not compiled again.
fn pieces_of(clip: &Clip, before: Option<&Sent>) -> Vec<Piece> {
    let ClipContent::Midi { notes, controls } = &clip.content else {
        return Vec::new();
    };
    // The very same clip: nothing to compile.
    if let Some(b) = before.filter(|b| std::ptr::eq(&*b.clip, clip)) {
        return b.pieces.clone();
    }
    if notes.len() <= PIECE || clip.repeat().is_some() {
        return vec![(Vec::new(), compile_clip(clip, notes, controls))];
    }
    // Compiled pieces of the clip before, by their first run.
    let mut known: HashMap<*const Vec<Note>, &Piece> = HashMap::new();
    if let Some(b) = before.filter(|b| b.clip.start == clip.start && b.clip.length == clip.length) {
        for piece in &b.pieces {
            if let Some(&first) = piece.0.first() {
                known.insert(first, piece);
            }
        }
    }
    let mut out = Vec::new();
    // The controllers are compiled again with any change of the clip.
    out.push((Vec::new(), compile_part(clip, &[], controls)));
    let runs = notes.runs();
    let mut at = 0;
    while at < runs.len() {
        let (mut end, mut count) = (at, 0);
        while end < runs.len() && count < PIECE {
            count += runs[end].len();
            end += 1;
        }
        let ptrs: Vec<*const Vec<Note>> = runs[at..end].iter().map(Arc::as_ptr).collect();
        let events = match known.get(&ptrs[0]) {
            Some((was, events)) if *was == ptrs => events.clone(),
            _ => compile_part(clip, runs[at..end].iter().flat_map(|r| r.iter()), &[]),
        };
        out.push((ptrs, events));
        at = end;
    }
    out
}

/// A clip's parts from `order` on, compiling only what changed since
/// `before`, and the clip as sent.
fn parts_of(
    clip: &Arc<Clip>,
    order: u64,
    before: Option<&Sent>,
    tempo: &paw_engine::TempoMap,
    ctx: &mut SyncCtx,
) -> (Vec<Part>, Sent) {
    let mut audio = Vec::new();
    let mut pieces = Vec::new();
    if !clip.muted {
        match &clip.content {
            ClipContent::Midi { .. } => pieces = pieces_of(clip, before),
            ClipContent::Audio { file, offset, gain, .. } => {
                clip_audio(clip, (file, *offset, *gain), tempo, ctx, &mut audio)
            }
        }
    }
    let mut parts = Vec::with_capacity(pieces.len().max(1));
    if !audio.is_empty() {
        parts.push(Part::new(clip.id, order, Arc::from([]), audio));
    }
    for (k, (_, events)) in pieces.iter().enumerate() {
        parts.push(Part::new(clip.id, order + k as u64, events.clone(), Vec::new()));
    }
    parts.retain(|p| !p.is_empty());
    let sent = Sent {
        clip: clip.clone(),
        order,
        pieces,
        parts: parts.iter().map(|p| p.order).collect(),
    };
    (parts, sent)
}

/// How many orders a clip's parts take.
fn orders_taken(clip: &Clip) -> u64 {
    match &clip.content {
        ClipContent::Midi { notes, .. } => notes.runs().len() as u64 + 1,
        ClipContent::Audio { .. } => 1,
    }
}

/// Whether a track's events go through its attribute map: then its clips
/// are sent as one list, which the map changes as a whole.
fn mapped(track: &Track) -> bool {
    track.attr_map.as_ref().is_some_and(|m| m.plan().is_ok())
}

fn build_clips(
    track: &Track,
    tempo: &paw_engine::TempoMap,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
) -> ClipSet {
    let cached = map.parts.remove(&track.id).unwrap_or_default();
    let mut kept = Parts {
        clips: HashMap::with_capacity(track.clips.len()),
        flat: mapped(track),
        ..Parts::default()
    };
    if kept.flat {
        // In the order a clip's events are compiled in, which the sort keeps
        // on the same beat.
        let mut set = ClipSet::default();
        for clip in track.clips.iter() {
            let (parts, sent) = parts_of(clip, 0, cached.clips.get(&clip.id), tempo, ctx);
            for part in parts {
                set.midi.extend_from_slice(&part.midi);
                set.audio.extend(part.audio);
            }
            kept.clips.insert(clip.id, sent);
        }
        set.finish();
        downgrade(track, &mut set, tempo);
        map.parts.insert(track.id, kept);
        return set;
    }
    let mut parts = Vec::with_capacity(track.clips.len());
    for (i, clip) in track.clips.iter().enumerate() {
        let order = (i as u64 + 1) * ORDER_GAP;
        let (mut more, sent) = parts_of(clip, order, cached.clips.get(&clip.id), tempo, ctx);
        parts.append(&mut more);
        kept.clips.insert(clip.id, sent);
    }
    kept.len = parts.len();
    kept.room = 2 * parts.len() + 64;
    let set = ClipSet::default().with_parts(parts, kept.room);
    map.parts.insert(track.id, kept);
    set
}

/// The parts of the clips an edit changed, to take out of the engine and
/// put in again, from the clips of `track` that differ from those of
/// `prev` (the same track as the engine has it). `None` when the track's
/// clips are to be sent whole: they are sent as one list, or the edit
/// changed many, or the parts would not fit in the room the engine has.
fn edit_parts(
    prev: &Track,
    track: &Track,
    tempo: &paw_engine::TempoMap,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
) -> Option<PartEdit> {
    let kept = map.parts.get_mut(&track.id)?;
    if kept.flat || mapped(track) {
        return None;
    }
    let (old, new) = track.clips.changed(&prev.clips);
    if old.len() + new.len() > MAX_EDIT {
        return None;
    }
    // The orders on each side of the stretch, which the clips put in again
    // take orders between, each as many as it has parts.
    let low = match new.start {
        0 => 0,
        at => {
            let c = track.clips.get(at - 1)?;
            kept.clips.get(&c.id)?.order + orders_taken(c)
        }
    };
    let count = new.len() as u64;
    let step = match track.clips.get(new.end) {
        Some(c) => (kept.clips.get(&c.id)?.order.checked_sub(low)?) / (count + 1),
        None => ORDER_GAP,
    };
    if track.clips.range(new.clone()).any(|c| orders_taken(c) >= step) {
        return None;
    }
    let mut edit = PartEdit::default();
    let mut gone = HashMap::new();
    for clip in prev.clips.range(old) {
        if let Some(was) = kept.clips.remove(&clip.id) {
            edit.remove.extend(was.parts.iter().map(|&order| (clip.id, order)));
            gone.insert(clip.id, was);
        }
    }
    let mut sent = Vec::with_capacity(new.len());
    for (k, clip) in track.clips.range(new).enumerate() {
        let order = low + (k as u64 + 1) * step;
        let (mut parts, now) = parts_of(clip, order, gone.get(&clip.id), tempo, ctx);
        edit.add.append(&mut parts);
        sent.push(now);
    }
    let len = kept.len - edit.remove.len() + edit.add.len();
    if len > kept.room {
        // Sent whole, with more room.
        map.parts.remove(&track.id);
        return None;
    }
    kept.len = len;
    for now in sent {
        kept.clips.insert(now.clip.id, now);
    }
    edit.removed = Vec::with_capacity(edit.remove.len());
    Some(edit)
}

/// What the track's attribute map sends, put among its events.
fn downgrade(track: &Track, set: &mut ClipSet, tempo: &paw_engine::TempoMap) {
    // A map is checked when it is set; one that no longer reads (from a
    // file edited by hand) plays as if there were none.
    if let Some(plan) = track.attr_map.as_ref().and_then(|m| m.plan().ok()) {
        crate::attr_map::downgrade(set, &plan, tempo);
    }
}

/// The regions an audio clip plays, once its sound is at hand.
fn clip_audio(
    clip: &Clip,
    (file, offset, gain): (&Path, f64, f64),
    tempo: &paw_engine::TempoMap,
    ctx: &mut SyncCtx,
    out: &mut Vec<AudioRegion>,
) {
    let rate = ctx.sample_rate as u32;
    // A stretched, warped or shifted clip plays a version made for it, in
    // which its file's moments are where its warp puts them (`warp.rs`); it
    // is silent until that is started, and then plays it as far as it is made.
    let warp = crate::warp::of(clip, tempo);
    let data = match crate::stretched::Key::of(clip, rate, tempo) {
        Some(key) => ctx.audio.stretched(&key, ctx.warnings),
        None => ctx.audio.get(file, rate, ctx.warnings),
    };
    if let Some(data) = data {
        let offset = warp.map_or(offset, |w| w.forward(offset));
        audio_regions(clip, data, offset, db_to_gain(gain), tempo, out);
    }
}

/// What a frozen track plays: its file from the start of the song, as it
/// was rendered, at unity gain and without fades.
fn frozen_clips(file: &Path, tempo: &paw_engine::TempoMap, ctx: &mut SyncCtx) -> ClipSet {
    let mut set = ClipSet::default();
    if let Some(data) = ctx.audio.get(file, ctx.sample_rate as u32, ctx.warnings) {
        let end = tempo.beat(tempo.seconds(0.0) + data.whole_seconds());
        set.audio.push(AudioRegion {
            start: 0.0,
            end,
            declick_in: false,
            declick_out: false,
            data,
            offset: 0.0,
            gain: 1.0,
            fade_in: 0.0,
            fade_out: 0.0,
            hold: Default::default(),
        });
    }
    set.finish();
    set
}

/// The engine's rows for a track's clips off the timeline: a clip keeps
/// the row it had, a clip gone frees its row, and a new clip takes the
/// first free row.
fn cue_rows(mut rows: Vec<Option<Id>>, track: &Track) -> Vec<Option<Id>> {
    for row in rows.iter_mut() {
        if row.is_some_and(|id| !track.cues.iter().any(|c| c.id == id)) {
            *row = None;
        }
    }
    for clip in &track.cues {
        if rows.contains(&Some(clip.id)) {
            continue;
        }
        match rows.iter().position(Option::is_none) {
            Some(free) => rows[free] = Some(clip.id),
            None => rows.push(Some(clip.id)),
        }
    }
    while rows.last() == Some(&None) {
        rows.pop();
    }
    rows
}

/// What a track's clips off the timeline play, each laid out from its own
/// start, in its row (`rows`).
fn build_cues(
    track: &Track,
    rows: &[Option<Id>],
    tempo: &paw_engine::TempoMap,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
) -> Slots {
    // A clip that did not change is not compiled again.
    let cached = map.cue_events.remove(&track.id).unwrap_or_default();
    let mut kept = HashMap::with_capacity(cached.len() + 1);
    let mut out: Vec<Option<SlotClip>> = Vec::new();
    out.resize_with(rows.len(), || None);
    for (row, id) in rows.iter().enumerate() {
        let Some(clip) = id.and_then(|id| track.cues.iter().find(|c| c.id == id)) else {
            continue;
        };
        if clip.muted {
            continue;
        }
        let mut clips = ClipSet::default();
        match &clip.content {
            ClipContent::Midi { notes, controls } => {
                let events = match cached.get(&clip.id) {
                    Some((was, events)) if Arc::ptr_eq(was, clip) => events.clone(),
                    _ => compile_clip(clip, notes, controls),
                };
                clips.midi = events.to_vec();
                kept.insert(clip.id, (clip.clone(), events));
                downgrade(track, &mut clips, tempo);
            }
            ClipContent::Audio { file, offset, gain, .. } => {
                clip_audio(clip, (file, *offset, *gain), tempo, ctx, &mut clips.audio)
            }
        }
        out[row] = Some(SlotClip {
            clips,
            length: clip.length,
        });
    }
    if !kept.is_empty() {
        map.cue_events.insert(track.id, kept);
    }
    Slots { rows: out }
}

type TrackIndex<'a> = HashMap<Id, &'a Arc<Track>>;

/// Where two states of a track's list of clips or lanes may differ: the
/// items of the state before and of the state after in that stretch.
type Span<'a, T> = (Vec<&'a Arc<T>>, Vec<&'a Arc<T>>);

/// Report the clips or lanes (`kind`) that the touched tracks gained, lost or
/// changed, as `<kind>.added`, `<kind>.removed` and `<kind>.changed`.
fn item_events<T>(
    kind: &str,
    (old, new): (&TrackIndex, &TrackIndex),
    touched: &dyn Fn(Id) -> bool,
    span: for<'a> fn(Option<&'a Track>, &'a Track) -> Span<'a, T>,
    id_of: fn(&T) -> Id,
    emit: &mut dyn FnMut(&str, Value),
) {
    let changed: Vec<(&Arc<Track>, Option<&&Arc<Track>>)> = new
        .values()
        .filter(|t| touched(t.id))
        .map(|t| (*t, old.get(&t.id)))
        .collect();
    // Each changed track against itself as it was: items in the same place
    // are found at once, and only what is left over (added, removed, or
    // moved from one track to another) is looked up by id.
    let mut added: Vec<(Id, Id)> = Vec::new();
    let mut removed: Vec<(Id, Id)> = Vec::new();
    for (t, was) in &changed {
        let (before, after) = span(was.map(|w| &***w), t);
        let mut by_id = crate::model::ByKey::new(&before[..], |x: &&Arc<T>| id_of(x));
        let mut matched = vec![false; before.len()];
        for item in after {
            match by_id.position(id_of(item)) {
                Some(k) => {
                    matched[k] = true;
                    if !Arc::ptr_eq(before[k], item) {
                        emit(
                            &format!("{kind}.changed"),
                            json!({ "id": id_of(item), "track": t.id }),
                        );
                    }
                }
                None => added.push((id_of(item), t.id)),
            }
        }
        for (k, _) in matched.iter().enumerate().filter(|(_, m)| !**m) {
            removed.push((id_of(&before[k]), t.id));
        }
    }
    // Tracks that are gone take their items with them.
    for (id, t) in old.iter().filter(|(id, _)| !new.contains_key(id)) {
        removed.extend(span(None, t).1.into_iter().map(|item| (id_of(item), *id)));
    }
    let mut removed: HashMap<Id, Id> = removed.into_iter().collect();
    for (id, track) in added {
        let event = if removed.remove(&id).is_some() { "changed" } else { "added" };
        emit(&format!("{kind}.{event}"), json!({ "id": id, "track": track }));
    }
    for (id, track) in removed {
        emit(
            &format!("{kind}.removed"),
            json!({ "id": id, "track": track }),
        );
    }
}

/// A parameter value as the device may be given it: within the parameter's
/// range, whatever a project file says. Devices are not asked to cope with
/// values they never declared (a gain of 1e300 dB is an infinite gain).
fn param_value(param: &ParamInfo, value: f64) -> f64 {
    let (min, max) = (param.min as f64, param.max as f64);
    if value.is_nan() {
        param.default as f64
    } else if min <= max {
        value.clamp(min, max)
    } else {
        value
    }
}

/// Whether a lane moves its target: it is on and has somewhere to take it.
pub fn is_active(lane: &Lane) -> bool {
    lane.enabled && !lane.points.is_empty()
}

fn build_automation(
    track: &Track,
    project: &Project,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
) -> Automation {
    let mut set = Automation::default();
    // A track whose automation is off keeps its lanes and plays none.
    let on = track.automation != crate::model::AutoMode::Off;
    let vca = vca_volume_lane(track, project);
    if let Some(points) = &vca {
        set.lanes.push(AutoLane::new(AutoTarget::Volume, points.clone()));
    }
    for lane in &track.lanes {
        map.state_main.remove(&lane.id);
    }
    for lane in track.lanes.iter().filter(|l| on && is_active(l)) {
        let mut range = None;
        let target = match &lane.target {
            Target::State { device } => {
                if let Some(state) = state_lane(lane, *device, map, ctx) {
                    set.states.push(state);
                }
                continue;
            }
            // The fader's lane is already there when VCAs are involved.
            Target::Volume if vca.is_some() => continue,
            Target::Volume => AutoTarget::Volume,
            Target::Pan => AutoTarget::Pan,
            Target::Param { device, param } => {
                let (Some(&slot), Some(live)) = (map.devices.get(device), ctx.live.get(device))
                else {
                    continue;
                };
                let Some(index) = live.params.iter().position(|p| &p.key == param) else {
                    continue;
                };
                range = Some(&live.params[index]);
                AutoTarget::Param {
                    device: slot,
                    index: index as u32,
                }
            }
        };
        // Shaped stretches go to the engine as the straight pieces they are played as.
        let played = lane.played();
        let points: Vec<(f64, f64)> = match range {
            Some(param) => played
                .iter()
                .map(|&(beat, v)| (beat, param_value(param, v)))
                .collect(),
            None => played.into_owned(),
        };
        set.lanes.push(AutoLane::new(target, points));
    }
    set
}

/// A state lane as the engine plays it: what each state does on the audio
/// thread (parameters, a program change, a request the device's controller
/// prepares as a message), and in `map.state_main` which states also need
/// the main thread.
fn state_lane(lane: &Lane, device: Id, map: &mut Mapper, ctx: &mut SyncCtx) -> Option<StateLane> {
    let &slot = map.devices.get(&device)?;
    let live = ctx.live.get_mut(&device);
    let (params, mut controller) = match live {
        Some(live) => (live.params.clone(), live.controller.as_mut()),
        None => (Arc::new(Vec::new()), None),
    };
    let mut main = Vec::with_capacity(lane.states.len());
    let mut changes = Vec::with_capacity(lane.states.len());
    for state in &lane.states {
        let mut change = StateChange {
            params: state
                .params
                .iter()
                .filter_map(|(key, value)| {
                    let index = params.iter().position(|p| &p.key == key)?;
                    Some((index as u32, param_value(&params[index], *value) as f32))
                })
                .collect(),
            program: state.program.map(|p| (p, state.bank)),
            message: None,
        };
        let mut needs_main = state.state.is_some();
        if let Some(call) = &state.call {
            match controller
                .as_mut()
                .map(|c| c.prepare(&call.method, call.data.as_bytes()))
            {
                Some(Ok(Some(message))) => change.message = Some(message.into()),
                Some(Err(err)) => {
                    ctx.warnings
                        .push(format!("state `{}` of a lane: {err:#}", state.name));
                    needs_main = true;
                }
                _ => needs_main = true,
            }
        }
        main.push(needs_main);
        changes.push(change);
    }
    let points: Vec<(f64, u32)> = lane
        .points
        .iter()
        .filter(|(_, v)| (*v as usize) < lane.states.len())
        .map(|&(beat, v)| (beat, v as u32))
        .collect();
    if main.iter().any(|m| *m) {
        map.state_main.insert(lane.id, main);
    }
    Some(StateLane::new(slot, points, changes))
}

/// Whether a track is a VCA: a fader, mute and solo that belong to other
/// tracks and carry no audio of their own. The runtime marks it in its meta.
fn is_vca(track: &Track) -> bool {
    track.meta.get("vca").and_then(|v| v.as_bool()) == Some(true)
}

/// The VCAs a track is assigned to (named in its meta) that exist.
fn vcas_of<'a>(track: &Track, project: &'a Project) -> Vec<&'a Track> {
    let Some(ids) = track.meta.get("vcas").and_then(|v| v.as_array()) else {
        return Vec::new();
    };
    if is_vca(track) {
        return Vec::new();
    }
    project
        .tracks
        .iter()
        .filter(|t| is_vca(t) && ids.iter().any(|id| id.as_u64() == Some(t.id)))
        .map(|t| &**t)
        .collect()
}

/// A fader's lane on its own: its points in dB, or `None` where the fader
/// is still (or its automation is off).
fn fader_points(track: &Track) -> Option<&[(f64, f64)]> {
    if track.automation == crate::model::AutoMode::Off {
        return None;
    }
    track
        .lanes
        .iter()
        .find(|l| l.target == Target::Volume && is_active(l))
        .map(|l| l.points.as_slice())
}

/// The fader lane of a track that is in VCAs, when any lane is in play: the
/// sum in dB of its own fader and its VCAs' faders, each a lane or a fixed
/// value. Lanes are straight lines between points, so the sum is too, with
/// a point wherever one of them has one: the engine plays it as any lane,
/// sample by sample, and a render hears the same.
fn vca_volume_lane(track: &Track, project: &Project) -> Option<Vec<(f64, f64)>> {
    let vcas = vcas_of(track, project);
    if vcas.is_empty() {
        return None;
    }
    let all: Vec<&Track> = std::iter::once(track).chain(vcas).collect();
    let lanes: Vec<Option<&[(f64, f64)]>> = all.iter().map(|t| fader_points(t)).collect();
    if lanes.iter().all(|l| l.is_none()) {
        return None;
    }
    let mut beats: Vec<f64> = lanes
        .iter()
        .flatten()
        .flat_map(|l| l.iter().map(|p| p.0))
        .collect();
    beats.sort_by(f64::total_cmp);
    beats.dedup();
    let sum = |at: &dyn Fn(&[(f64, f64)]) -> f64| -> f64 {
        all.iter()
            .zip(&lanes)
            .map(|(t, l)| l.map_or(t.volume, at))
            .sum()
    };
    let mut out = Vec::new();
    for b in beats {
        // The value as a beat is reached, and as it is left (they differ at a jump).
        let before = sum(&|p| value_before(p, b));
        let after = sum(&|p| paw_engine::automation::value_at(p, b).unwrap_or(0.0));
        if before != after {
            out.push((b, before));
        }
        out.push((b, after));
    }
    Some(out)
}

/// A lane's value as `beat` is approached from before it.
fn value_before(points: &[(f64, f64)], beat: f64) -> f64 {
    let next = points.partition_point(|p| p.0 < beat);
    match (next.checked_sub(1).map(|i| points[i]), points.get(next)) {
        (None, Some(b)) => b.1,
        (Some(a), None) => a.1,
        (Some(a), Some(b)) => a.1 + (b.1 - a.1) * (beat - a.0) / (b.0 - a.0),
        (None, None) => 0.0,
    }
}

/// The tracks that count as soloed: those that are, and the members of a
/// soloed VCA.
fn soloed_tracks(project: &Project) -> HashSet<Id> {
    let mut out = HashSet::new();
    for t in project.all_tracks() {
        if (t.solo && !is_vca(t)) || vcas_of(t, project).iter().any(|v| v.solo) {
            out.insert(t.id);
        }
    }
    out
}

/// Put back the project's own value of anything a lane stopped automating,
/// since the engine otherwise keeps the last automated value.
fn release_targets(
    old: &Track,
    new: &Track,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
    send: &mut dyn FnMut(Msg),
) {
    let active =
        |t: &Track, target: &Target| t.lanes.iter().any(|l| &l.target == target && is_active(l));
    for lane in old
        .lanes
        .iter()
        .filter(|l| is_active(l) && !active(new, &l.target))
    {
        match &lane.target {
            // Forget what the engine was last told, so that the mix is sent again.
            Target::Volume | Target::Pan => {
                map.mix.remove(&new.id);
            }
            Target::Param { device, param } => {
                let Some(inst) = new.devices.iter().find(|d| d.id == *device) else {
                    continue;
                };
                let (Some(&slot), Some(live)) = (map.devices.get(device), ctx.live.get_mut(device))
                else {
                    continue;
                };
                let Some(index) = live.params.iter().position(|p| &p.key == param) else {
                    continue;
                };
                let value = inst
                    .params
                    .get(param)
                    .copied()
                    .unwrap_or(live.params[index].default as f64);
                let value = param_value(&live.params[index], value);
                send(Msg::SetParam {
                    device: slot,
                    param: index as u32,
                    value: value as f32,
                });
                if let Some(controller) = live
                    .controller
                    .as_mut()
                    .filter(|_| !is_host(&live.params, index))
                {
                    controller.set_value(index, value);
                }
            }
            // The device takes back the state the project gives it, and
            // the parameters set in the project.
            Target::State { device } => {
                let Some(inst) = new.devices.iter().find(|d| d.id == *device) else {
                    continue;
                };
                let (Some(&slot), Some(live)) = (map.devices.get(device), ctx.live.get_mut(device))
                else {
                    continue;
                };
                if let Some(controller) = live.controller.as_mut()
                    && let Some(state) = &inst.state
                    && let Ok(bytes) = BASE64.decode(state)
                    && let Err(err) = controller.load_state(&bytes)
                {
                    ctx.warnings
                        .push(format!("could not give a device its state back: {err:#}"));
                }
                for (index, param) in live.params.iter().enumerate() {
                    let Some(&value) = inst.params.get(&param.key) else {
                        continue;
                    };
                    let value = param_value(param, value);
                    send(Msg::SetParam {
                        device: slot,
                        param: index as u32,
                        value: value as f32,
                    });
                    if let Some(controller) = live
                        .controller
                        .as_mut()
                        .filter(|_| !is_host(&live.params, index))
                    {
                        controller.set_value(index, value);
                    }
                }
            }
        }
    }
}

/// With some track soloed, a track still sounds if it is soloed itself, feeds a
/// soloed track, or carries a soloed track's signal on to the master: through
/// its output or a send (the reverb a soloed track sends to is heard with
/// it, and the stems of a song add up to its mix). The tracks that still
/// sound, found in one pass over the outputs.
fn solo_paths(project: &Project, soloed: &HashSet<Id>) -> HashSet<Id> {
    let by_id: HashMap<Id, &Track> = project.tracks.iter().map(|t| (t.id, &**t)).collect();
    let mut sounding = HashSet::new();
    // Soloed tracks, and every track their sound passes through.
    let mut ahead: Vec<Id> = project.tracks.iter().map(|t| t.id).filter(|id| soloed.contains(id)).collect();
    while let Some(id) = ahead.pop() {
        if !sounding.insert(id) {
            continue;
        }
        if let Some(t) = by_id.get(&id) {
            ahead.extend(t.output.iter().chain(t.sends.iter().map(|s| &s.target)).filter(|id| by_id.contains_key(id)));
        }
    }
    // Tracks whose output reaches a soloed track. `feeds` remembers the
    // answer for every track walked through, so each is walked once.
    let mut feeds: HashMap<Id, bool> = HashMap::new();
    for t in &project.tracks {
        let mut path: Vec<&Track> = Vec::new();
        let mut beyond = false;
        let mut at = t.output;
        while let Some(&next) = at.and_then(|id| by_id.get(&id)) {
            if let Some(&known) = feeds.get(&next.id) {
                beyond = known || soloed.contains(&next.id);
                break;
            }
            if path.len() > by_id.len() {
                break;
            }
            path.push(next);
            at = next.output;
        }
        for n in path.iter().rev() {
            feeds.insert(n.id, beyond);
            beyond |= soloed.contains(&n.id);
        }
        feeds.insert(t.id, beyond);
        if beyond {
            sounding.insert(t.id);
        }
    }
    sounding
}

fn routing_of(project: &Project, live: &LiveDevices, played: &HashMap<Id, Played>) -> Routing {
    let ids: HashSet<Id> = project.all_tracks().map(|t| t.id).collect();
    let exists = |id: Id| ids.contains(&id);
    // A device that is bypassed is not run, so it holds nothing back.
    let device_latency = |d: &DeviceInst| -> u32 {
        if d.bypass {
            return 0;
        }
        live.get(&d.id)
            .map_or(0, |l| l.latency.min(MAX_DELAY as u32))
    };
    // Nor are the devices of a frozen or held track.
    let latency = |t: &Track| -> u32 {
        if played.contains_key(&t.id) {
            return 0;
        }
        t.devices.iter().map(|d| device_latency(d)).sum()
    };
    // Side-chains, by the track they are taken from. The master feeds
    // nothing, so it keys nothing.
    let mut keys: HashMap<Id, Vec<Key>> = HashMap::new();
    for t in project.all_tracks() {
        let mut before = 0;
        for d in &t.devices {
            if let Some(source) = d
                .sidechain
                .filter(|s| exists(*s) && *s != t.id && *s != MASTER_ID)
            {
                keys.entry(source).or_default().push(Key {
                    track: t.id,
                    device: d.id,
                    pre: d.sidechain_pre,
                    before,
                });
            }
            before += device_latency(d);
        }
    }
    // Further output pairs, by the track whose devices they come from. The
    // master feeds nothing, so its devices' pairs go nowhere.
    let outs_of = |t: &Track| -> Vec<Out> {
        let mut late = 0;
        let mut outs = Vec::new();
        for d in &t.devices {
            late += device_latency(d);
            for (&pair, &target) in &d.outputs {
                if t.id != MASTER_ID && pair >= 2 && exists(target) && target != t.id {
                    outs.push(Out {
                        device: d.id,
                        pair: pair as usize - 2,
                        target,
                        late,
                    });
                }
            }
        }
        outs
    };
    project
        .all_tracks()
        .map(|t| Route {
            keys: keys.remove(&t.id).unwrap_or_default(),
            outs: outs_of(t),
            track: t.id,
            output: t
                .output
                .filter(|id| exists(*id) && *id != t.id)
                .unwrap_or(MASTER_ID),
            sends: t
                .sends
                .iter()
                .filter(|s| exists(s.target) && s.target != t.id)
                .map(|s| (s.target, db_to_gain(s.level), s.pre))
                .collect(),
            latency: latency(t),
        })
        .collect()
}

/// Order tracks so that each one runs after everything that feeds it, and
/// hold each connection back until the slowest signal reaching the same
/// place has arrived.
fn build_schedule(routing: &Routing, map: &Mapper) -> Schedule {
    // The master is in the routing for its latency, not as a source.
    let sources: Vec<&Route> = routing.iter().filter(|r| r.track != MASTER_ID).collect();
    // What feeds each track: the source, and how many frames earlier than
    // its output the place it arrives at is (a side-chain arrives at a
    // device, after the devices before it).
    let mut feeders: HashMap<Id, Vec<(usize, u32)>> = HashMap::new();
    for (index, route) in sources.iter().enumerate() {
        feeders.entry(route.output).or_default().push((index, 0));
        for (target, ..) in &route.sends {
            feeders.entry(*target).or_default().push((index, 0));
        }
        for key in &route.keys {
            feeders
                .entry(key.track)
                .or_default()
                .push((index, key.before));
        }
        for out in &route.outs {
            feeders
                .entry(out.target)
                .or_default()
                .push((index, route.latency.saturating_sub(out.late)));
        }
    }
    fn visit(
        index: usize,
        sources: &[&Route],
        feeders: &HashMap<Id, Vec<(usize, u32)>>,
        state: &mut [u8],
        order: &mut Vec<usize>,
    ) {
        if state[index] != 0 {
            return;
        }
        state[index] = 1;
        for &(feeder, _) in feeders
            .get(&sources[index].track)
            .map(Vec::as_slice)
            .unwrap_or(&[])
        {
            visit(feeder, sources, feeders, state, order);
        }
        order.push(index);
    }
    let mut state = vec![0u8; sources.len()];
    let mut order = Vec::with_capacity(sources.len());
    for index in 0..sources.len() {
        visit(index, &sources, &feeders, &mut state, &mut order);
    }

    // How late each track's output is, and how late the latest signal fed
    // into it is. Feeders come first in the order, so one pass does it. A
    // side-chain that would arrive late at its device holds back the
    // track the device is on instead.
    let mut arrives: HashMap<Id, u32> = HashMap::new();
    let mut leaves: HashMap<Id, u32> = HashMap::new();
    let latest = |id: Id, leaves: &HashMap<Id, u32>| -> u32 {
        feeders
            .get(&id)
            .into_iter()
            .flatten()
            .filter_map(|&(f, early)| {
                leaves
                    .get(&sources[f].track)
                    .map(|l| l.saturating_sub(early))
            })
            .max()
            .unwrap_or(0)
    };
    for &index in &order {
        let route = sources[index];
        let arrive = latest(route.track, &leaves);
        arrives.insert(route.track, arrive);
        leaves.insert(route.track, arrive + route.latency);
    }
    let master_arrive = latest(MASTER_ID, &leaves);
    arrives.insert(MASTER_ID, master_arrive);
    let master_latency = routing
        .iter()
        .find(|r| r.track == MASTER_ID)
        .map_or(0, |r| r.latency);

    let slot = |id: &Id| map.tracks.get(id).copied();
    // What a connection into `target` waits: until the latest one gets there.
    let wait_for = |from: Id, target: Id, early: u32| -> Delay {
        let frames = (arrives.get(&target).copied().unwrap_or(0) + early)
            .saturating_sub(leaves[&from]);
        match frames {
            0 => Delay::default(),
            frames => Delay::new(frames as usize),
        }
    };
    let wait = |from: Id, target: Id| wait_for(from, target, 0);
    let mut entries: Vec<SchedEntry> = order
        .into_iter()
        .filter_map(|index| {
            let route = sources[index];
            let output = if slot(&route.output).is_some() {
                route.output
            } else {
                MASTER_ID
            };
            Some(SchedEntry {
                slot: slot(&route.track)?,
                output: slot(&output).unwrap_or(MASTER),
                delay: wait(route.track, output),
                sends: route
                    .sends
                    .iter()
                    .filter_map(|(target, gain, pre)| {
                        Some(SendRt {
                            target: slot(target)?,
                            gain: *gain,
                            pre: *pre,
                            delay: wait(route.track, *target),
                        })
                    })
                    .collect(),
                keys: route
                    .keys
                    .iter()
                    .filter_map(|key| {
                        Some(KeyRt {
                            device: *map.devices.get(&key.device)?,
                            track: slot(&key.track)?,
                            pre: key.pre,
                            delay: wait_for(route.track, key.track, key.before),
                        })
                    })
                    .collect(),
                outs: route
                    .outs
                    .iter()
                    .filter_map(|out| {
                        Some(OutRt {
                            device: *map.devices.get(&out.device)?,
                            pair: out.pair,
                            target: slot(&out.target)?,
                            delay: wait_for(
                                route.track,
                                out.target,
                                route.latency.saturating_sub(out.late),
                            ),
                        })
                    })
                    .collect(),
            })
        })
        .collect();
    entries.push(SchedEntry::new(MASTER, NO_SLOT));
    Schedule::new(entries, master_arrive + master_latency)
}

#[cfg(test)]
mod tests {
    use super::*;
    use paw_engine::{Engine, EngineHandle};

    /// A track with a synth and `clips` short clips that overlap, the same
    /// keys in each, and one long clip of 1000 notes and some controllers.
    fn project(clips: usize) -> Project {
        let note = |start: f64, pitch: u64| {
            json!({ "start": start, "length": 0.75, "pitch": pitch, "velocity": 90 })
        };
        let mut list: Vec<Value> = (0..clips)
            .map(|i| {
                let notes: Vec<Value> = (0..6).map(|k| note(k as f64 * 0.5, 48 + (k % 3))).collect();
                json!({
                    "id": 100 + i, "name": "", "start": (i % 9) as f64 * 1.25, "length": 3.0,
                    "muted": false, "content": { "kind": "midi", "notes": notes },
                })
            })
            .collect();
        let notes: Vec<Value> = (0..1000).map(|k| note(k as f64 * 0.125, 60 + (k % 7))).collect();
        let controls: Vec<Value> = (0..20)
            .map(|k| json!({ "start": k as f64, "type": "cc", "number": 1, "value": k as f64 / 20.0 }))
            .collect();
        list.push(json!({
            "id": 99, "name": "long", "start": 0.5, "length": 130.0, "muted": false,
            "content": { "kind": "midi", "notes": notes, "controls": controls },
        }));
        let track = |id: u64, name: &str, devices: Value, clips: Value| {
            json!({ "id": id, "name": name, "volume": 0.0, "pan": 0.0, "mute": false, "solo": false,
                "armed": false, "output": null, "sends": [], "color": null,
                "devices": devices, "clips": clips })
        };
        let synth = json!([{ "id": 2, "kind": "synth", "bypass": false, "params": {} }]);
        let project = json!({
            "name": "t", "tempo": 120.0, "sig_num": 4, "sig_den": 4,
            "master": track(0, "Master", json!([]), json!([])),
            "tracks": [track(1, "T", synth, Value::Array(list))],
        });
        serde_json::from_value(project).unwrap()
    }

    /// The events compiled for track 1, by where they are kept.
    fn compiled(map: &Mapper) -> HashMap<*const MidiEv, usize> {
        let Some(parts) = map.parts.get(&1) else { return HashMap::new() };
        let pieces = parts.clips.values().flat_map(|s| &s.pieces);
        pieces.map(|(_, e)| (e.as_ptr(), e.len())).collect()
    }

    /// An engine brought through each of `states` in turn, as a session
    /// syncs it; what it was sent for the last, and how many events were
    /// compiled for it.
    fn engine(states: &[&Project]) -> (Engine, EngineHandle, (Vec<&'static str>, usize)) {
        let (mut engine, mut handle) = Engine::new(48000.0);
        let registry = Registry::with_builtins();
        let (mut audio, mut live, mut warnings) = (AudioCache::default(), LiveDevices::new(), Vec::new());
        let mut map = Mapper::new();
        let empty = Project::default();
        let mut last = Vec::new();
        let mut fresh = 0;
        let mut old = &empty;
        for state in states {
            let mut ctx = SyncCtx {
                registry: &registry,
                audio: &mut audio,
                live: &mut live,
                sample_rate: 48000.0,
                warnings: &mut warnings,
                offline: true,
            };
            let mut sent = Vec::new();
            let before = compiled(&map);
            sync(old, state, &mut map, &mut ctx, &mut |msg| sent.push(msg), &mut Vec::new());
            let after = compiled(&map);
            fresh = after.iter().filter(|(p, _)| !before.contains_key(p)).map(|(_, n)| n).sum();
            last = sent
                .iter()
                .map(|m| match m {
                    Msg::SetClips { .. } => "clips",
                    Msg::EditClips { .. } => "edit",
                    _ => "other",
                })
                .collect();
            for msg in sent {
                handle.send_while(msg, &mut engine);
            }
            old = state;
        }
        (engine, handle, (last, fresh))
    }

    fn play(engine: &mut Engine, handle: &mut EngineHandle, from: f64) -> Vec<f32> {
        handle.send_while(Msg::Seek(from), engine);
        handle.send_while(Msg::Play, engine);
        let (mut l, mut r) = (vec![0.0; 512], vec![0.0; 512]);
        let mut out = Vec::new();
        for _ in 0..150 {
            engine.process(&mut l, &mut r);
            out.extend_from_slice(&l);
            out.extend_from_slice(&r);
        }
        handle.collect_garbage();
        out
    }

    type Edit = Box<dyn Fn(&mut Project)>;

    fn long(p: &mut Project) -> &mut Clip {
        let clips = &mut p.track_mut(1).unwrap().clips;
        let last = clips.len() - 1;
        Arc::make_mut(&mut clips[last])
    }

    /// Edits of a few clips are sent as the parts they changed; what the
    /// engine plays then is what it plays when sent every clip whole.
    #[test]
    fn edits_sent_as_parts_play_as_the_project_sent_whole() {
        let edits: Vec<Edit> = vec![
            Box::new(|p| Arc::make_mut(&mut p.track_mut(1).unwrap().clips[150]).start = 2.0),
            Box::new(|p| {
                p.track_mut(1).unwrap().clips.remove(10);
            }),
            Box::new(|p| {
                let mut clip = (*p.track(1).unwrap().clips[20]).clone();
                clip.id = 9000;
                clip.start = 1.0;
                p.track_mut(1).unwrap().clips.insert(30, Arc::new(clip));
            }),
            Box::new(|p| Arc::make_mut(&mut p.track_mut(1).unwrap().clips[70]).muted = true),
            // Two notes of the long clip: one run of its notes changes.
            Box::new(|p| {
                if let ClipContent::Midi { notes, .. } = &mut long(p).content {
                    notes[500].pitch = 40;
                    notes[501].start += 0.0625;
                }
            }),
            Box::new(|p| long(p).start = 1.0),
            Box::new(|p| {
                if let ClipContent::Midi { notes, .. } = &mut long(p).content {
                    notes.remove(3);
                }
            }),
        ];
        let mut states = vec![project(300)];
        for edit in &edits {
            let mut next = states.last().unwrap().clone();
            edit(&mut next);
            states.push(next);
        }
        for k in 1..states.len() {
            let path: Vec<&Project> = states[..=k].iter().collect();
            let (mut a, mut ha, (sent, fresh)) = engine(&path);
            assert!(sent.contains(&"edit") && !sent.contains(&"clips"), "edit {k} sent {sent:?}");
            if k == 5 || k == 7 {
                // Notes of the long clip: only their piece is compiled again
                // (two events a note, at most 511 notes a piece, and the
                // controllers), not the clip's 2000 events.
                assert!(fresh <= 2 * 511 + 20, "edit {k}: {fresh} events compiled");
            }
            let (mut b, mut hb, _) = engine(&[&states[k]]);
            for from in [0.0, 3.4, 60.0] {
                let (x, y) = (play(&mut a, &mut ha, from), play(&mut b, &mut hb, from));
                assert!(x.iter().any(|s| *s != 0.0));
                assert!(x == y, "edit {k}: what plays from {from} differs");
            }
        }
    }
}

#[cfg(test)]
mod rekey_tests {
    use super::*;

    fn param(key: &str, id: &str) -> ParamInfo {
        ParamInfo {
            id: id.into(),
            ..ParamInfo::new(key, 0.0, 1.0, 0.0, "")
        }
    }

    #[test]
    fn parameters_keep_the_keys_the_project_knows_them_by() {
        // A new version of the plugin swapped two parameters of one name:
        // "gain" is now the one the project knew as "gain_2".
        let mut params = vec![param("gain", "20"), param("gain_2", "10"), param("mix", "30")];
        let ids = BTreeMap::from([("gain".to_string(), "10".to_string())]);
        rekey(&mut params, &ids);
        let keys: Vec<&str> = params.iter().map(|p| p.key.as_str()).collect();
        assert_eq!(keys, ["gain_2", "gain", "mix"]);
        // Renamed: the project's key wins, and an id it does not know changes nothing.
        let mut params = vec![param("drive", "7")];
        let ids = BTreeMap::from([
            ("distortion".to_string(), "7".to_string()),
            ("gone".to_string(), "99".to_string()),
        ]);
        rekey(&mut params, &ids);
        assert_eq!(params[0].key, "distortion");
    }
}
