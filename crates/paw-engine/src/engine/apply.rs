//! Carrying out the messages of the main thread, between blocks.
//!
//! [`Engine::apply`] is the one place that tells the messages apart. Each
//! message that does more than set a field has a method of its own, kept
//! here by what it acts on: tracks, devices, what tracks play, the
//! transport, and MIDI and the other ways in and out.

use std::sync::atomic::Ordering::Relaxed;

use rtrb::Producer;

use crate::automation::{self, Automation};
use crate::clip::{ClipSet, PartEdit};
use crate::device::Device;
use crate::event::EventKind;
use crate::host::HostPath;
use crate::launch::{Launch, Slots};
use crate::midi_form::Form;
use crate::midi_out::MidiOut;
use crate::preview::Preview;
use crate::record::Take;
use crate::slot::{DeviceSlot, TrackSlot};
use crate::tempo::TempoMap;

use super::Engine;
use super::click::Count;
use super::device_rt::{DeviceRt, KeyBuf, OutBufs};
use super::msg::{Garbage, Msg};
use super::schedule::Schedule;
use super::track::{TrackRt, release_held};

impl Engine {
    pub(super) fn apply(&mut self, msg: Msg) {
        match msg {
            Msg::InsertTrack { slot, track } => self.insert_track(slot, track),
            Msg::RemoveTrack { slot } => self.remove_track(slot),
            Msg::SetSchedule(schedule) => self.set_schedule(schedule),
            Msg::SetMix {
                slot,
                gain,
                pan,
                mute,
                quiet,
            } => self.set_mix(slot, gain, pan, mute, quiet),
            Msg::SetChain { track, chain } => self.set_chain(track, chain),
            Msg::SetLocalTime { track, time } => self.set_local_time(track, time),
            Msg::InsertDevice { slot, device } => self.insert_device(slot, device),
            Msg::RemoveDevice { slot } => self.remove_device(slot),
            Msg::SetKey { device, key } => self.set_key(device, key),
            Msg::SetOutputs { device, outs } => self.set_outputs(device, outs),
            Msg::SetHost { device, path } => self.set_host(device, path),
            Msg::SetDeviceLatency { device, frames } => self.set_device_latency(device, frames),
            Msg::SetParam {
                device,
                param,
                value,
            } => self.set_param(device, param, value),
            Msg::SetBypass { device, bypass } => self.set_bypass(device, bypass),
            Msg::SetClips { track, clips } => self.set_clips(track, clips),
            Msg::EditClips { track, edit } => self.edit_clips(track, edit),
            Msg::SetAutomation { track, automation } => self.set_automation(track, automation),
            Msg::StatesHeld => self.states_held(),
            Msg::SetSlots { track, slots } => self.set_slots(track, slots),
            Msg::Launch(launches) => self.launch(launches),
            Msg::SetTempoMap(map) => self.set_tempo_map(map),
            Msg::SetTempo(tempo) => self.set_tempo(tempo),
            Msg::SetTimeSig { num, den } => self.set_time_sig(num, den),
            Msg::SetLoop {
                enabled,
                start,
                end,
            } => self.set_loop(enabled, start, end),
            Msg::SetMetronome(on) => self.metronome = on,
            Msg::SetClick {
                gain,
                accent,
                output,
            } => self.set_click(gain, accent, output),
            Msg::Play => self.play(),
            Msg::CountIn {
                frames,
                every,
                clicks,
                per_bar,
            } => self.count_in(frames, every, clicks, per_bar),
            Msg::Stop => self.stop(),
            Msg::Seek(position) => self.seek(position),
            Msg::Live { track, event } => self.play_live(track, event),
            Msg::SetInput {
                track,
                first,
                channels,
                monitor,
                armed,
            } => self.set_input(track, first, channels, monitor, armed),
            Msg::SetTake(take) => self.set_take(take),
            Msg::SetMidiInput {
                track,
                port,
                channel,
            } => self.set_midi_input(track, port, channel),
            Msg::MidiIn { port, kind } => self.midi_in(port, kind),
            Msg::SetMidiOutput {
                track,
                port,
                channel,
                form,
            } => self.set_midi_output(track, port, channel, form),
            Msg::SetMidiOut(out) => self.set_midi_out(out),
            Msg::SetMidiFilter(filter) => {
                let old = std::mem::replace(&mut self.midi_filter, filter);
                self.discard(Garbage::MidiFilter(old));
            }
            Msg::SetMonitor(monitor) => self.set_monitor(monitor),
            Msg::SetPreview(preview) => self.set_preview(preview),
            Msg::SetPreviewGain(gain) => self.set_preview_gain(gain),
            Msg::SetSleep(sleep) => self.sleep = sleep,
            // A message at all wakes the engine (`take_messages`).
            Msg::Wake => {}
            Msg::SetPool(pool) => {
                if let Some(old) = self.set_pool(pool) {
                    self.discard(Garbage::Pool(old));
                }
            }
        }
    }
}

/// Tracks, their mix and the order they are processed in.
impl Engine {
    fn insert_track(&mut self, slot: TrackSlot, track: Box<TrackRt>) {
        if let Some(entry) = self.tracks.get_mut(slot.index()) {
            if let Some(old) = entry.get_mut().replace(track) {
                self.discard(Garbage::Track(old));
            }
        } else {
            self.discard(Garbage::Track(track));
        }
        // A new track hears no input: the one it replaced may have.
        if self.listening {
            self.note_listening();
        }
    }

    fn remove_track(&mut self, slot: TrackSlot) {
        if let Some(old) = self
            .tracks
            .get_mut(slot.index())
            .and_then(|t| t.get_mut().take())
        {
            self.discard(Garbage::Track(old));
        }
        self.note_states();
        if self.listening {
            self.note_listening();
        }
    }

    fn set_schedule(&mut self, schedule: Box<Schedule>) {
        self.shared.latency.store(schedule.latency, Relaxed);
        if let Some(old) = self.schedule.replace(schedule) {
            self.discard(Garbage::Schedule(old));
        }
    }

    fn set_mix(&mut self, slot: TrackSlot, gain: f32, pan: f32, mute: bool, quiet: bool) {
        if let Some(track) = self.track_mut(slot) {
            track.gain = gain;
            track.pan = pan;
            track.mute = mute;
            track.quiet = quiet;
            if !track.started {
                track.applied = track.target_gains();
                track.applied_heard = if quiet { 0.0 } else { 1.0 };
            }
        }
    }

    fn set_local_time(&mut self, track: TrackSlot, time: Option<Box<crate::tempo::LocalTime>>) {
        let old = match self.track_mut(track) {
            Some(t) => std::mem::replace(&mut t.local, time),
            None => time,
        };
        if let Some(old) = old {
            self.discard(Garbage::LocalTime(old));
        }
    }

    fn set_chain(&mut self, track: TrackSlot, chain: Box<[DeviceSlot]>) {
        match self.track_mut(track) {
            Some(t) => {
                let old = std::mem::replace(&mut t.chain, chain);
                self.discard(Garbage::Chain(old));
            }
            None => self.discard(Garbage::Chain(chain)),
        }
    }
}

/// Devices, and what the host puts around them.
impl Engine {
    fn insert_device(&mut self, slot: DeviceSlot, device: Box<dyn Device>) {
        if let Some(entry) = self.devices.get_mut(slot.index()) {
            self.shared.faults[slot.index()].store(0, Relaxed);
            // A device put in place of another (one that was being
            // made, or restarted) listens where that one did.
            let key = entry.get_mut().as_mut().and_then(|old| old.key.take());
            let outs = entry.get_mut().as_mut().and_then(|old| old.outs.take());
            if let Some(old) = entry.get_mut().replace(DeviceRt {
                device,
                bypass: false,
                host: None,
                key,
                outs,
                failed: false,
                flagged: false,
            }) {
                self.discard(Garbage::Device(old.device));
                if let Some(host) = old.host {
                    self.discard(Garbage::Host(host));
                }
            }
        } else {
            self.discard(Garbage::Device(device));
        }
    }

    fn remove_device(&mut self, slot: DeviceSlot) {
        if let Some(old) = self
            .devices
            .get_mut(slot.index())
            .and_then(|d| d.get_mut().take())
        {
            self.discard(Garbage::Device(old.device));
            if let Some(host) = old.host {
                self.discard(Garbage::Host(host));
            }
            if let Some(key) = old.key {
                self.discard(Garbage::Key(key));
            }
            if let Some(outs) = old.outs {
                self.discard(Garbage::Outs(outs));
            }
        }
    }

    fn set_key(&mut self, device: DeviceSlot, key: Option<Box<KeyBuf>>) {
        let old = match self.device_mut(device) {
            Some(slot) => std::mem::replace(&mut slot.key, key),
            None => key,
        };
        if let Some(old) = old {
            self.discard(Garbage::Key(old));
        }
    }

    fn set_outputs(&mut self, device: DeviceSlot, outs: Option<Box<OutBufs>>) {
        let old = match self.device_mut(device) {
            Some(slot) => std::mem::replace(&mut slot.outs, outs),
            None => outs,
        };
        if let Some(old) = old {
            self.discard(Garbage::Outs(old));
        }
    }

    fn set_host(&mut self, device: DeviceSlot, path: Box<HostPath>) {
        match self.device_mut(device) {
            Some(slot) => {
                if let Some(old) = slot.host.replace(path) {
                    self.discard(Garbage::Host(old));
                }
            }
            None => self.discard(Garbage::Host(path)),
        }
    }

    fn set_device_latency(&mut self, device: DeviceSlot, frames: u32) {
        if let Some(host) = self.device_mut(device).and_then(|s| s.host.as_mut()) {
            host.set_latency(frames);
        }
    }

    fn set_param(&mut self, device: DeviceSlot, param: u32, value: f32) {
        if let Some(slot) = self.device_mut(device) {
            slot.set_param(param, value);
        }
        self.reapply = true;
    }

    fn set_bypass(&mut self, device: DeviceSlot, bypass: bool) {
        if let Some(slot) = self.device_mut(device) {
            slot.bypass = bypass;
        }
    }
}

/// What tracks play: their clips, lanes and launcher slots.
impl Engine {
    fn set_clips(&mut self, track: TrackSlot, clips: Box<ClipSet>) {
        match self.track_mut(track) {
            Some(t) => {
                let old = std::mem::replace(&mut t.clips, clips);
                // Notes that were sounding may no longer have a note-off.
                t.flush = true;
                t.chase = true;
                self.discard(Garbage::Clips(old));
            }
            None => self.discard(Garbage::Clips(clips)),
        }
    }

    fn edit_clips(&mut self, track: TrackSlot, mut edit: Box<PartEdit>) {
        if let Some(t) = self.track_mut(track) {
            // The main thread keeps count of the room there is, so
            // an edit always fits.
            if t.clips.edit(&mut edit) {
                // Notes that were sounding may no longer have a note-off.
                t.flush = true;
                t.chase = true;
            }
        }
        self.discard(Garbage::PartEdit(edit));
    }

    fn set_automation(&mut self, track: TrackSlot, automation: Box<Automation>) {
        match self.track_mut(track) {
            Some(t) => {
                let old = std::mem::replace(&mut t.automation, automation);
                self.discard(Garbage::Automation(old));
            }
            None => self.discard(Garbage::Automation(automation)),
        }
        self.note_states();
    }

    /// See [`Msg::StatesHeld`].
    fn states_held(&mut self) {
        let beat = self.head.beat();
        for t in self.tracks.iter_mut() {
            if let Some(t) = t.get_mut().as_deref_mut() {
                for lane in t.automation.states.iter_mut() {
                    let at = automation::state_at(&lane.points, beat + 1e-9);
                    // A program change goes with the events of a
                    // block: that one is given when the song plays.
                    let program = at
                        .and_then(|i| lane.changes.get(i as usize))
                        .is_some_and(|c| c.program.is_some());
                    lane.last = if program { None } else { at };
                    lane.sent_early = None;
                }
            }
        }
        self.states_held = true;
    }

    fn set_slots(&mut self, track: TrackSlot, slots: Box<Slots>) {
        match self.track_mut(track) {
            Some(t) => {
                let old = t.launcher.set_slots(slots);
                if !t.launcher.follows_arrangement() {
                    t.flush = true;
                    t.chase = true;
                }
                self.discard(Garbage::Slots(old));
            }
            None => self.discard(Garbage::Slots(slots)),
        }
    }

    // The box is the message's: it goes back to be freed whole, not here.
    #[allow(clippy::box_collection)]
    fn launch(&mut self, launches: Box<Vec<Launch>>) {
        let (position, playing) = (self.head.beat(), self.playing);
        if let Some(map) = self.map.take() {
            for launch in launches.iter() {
                // Stopped, there is no beat to wait for.
                let at = if playing {
                    launch.quantize.next(&map, position)
                } else {
                    position
                };
                if let Some(t) = self.track_mut(launch.track) {
                    t.launcher.queue(launch, at);
                    self.launching = true;
                }
            }
            self.map = Some(map);
        }
        self.discard(Garbage::Launches(launches));
    }
}

/// The transport, the tempo, the loop and the click.
impl Engine {
    fn set_tempo_map(&mut self, map: Box<TempoMap>) {
        // The frames played so far count in the old map's time: the new
        // one counts from the beat the song is on.
        self.head.put(self.head.beat());
        if let Some(old) = self.map.replace(map) {
            self.discard(Garbage::TempoMap(old));
        }
    }

    fn set_tempo(&mut self, tempo: f64) {
        if let Some(map) = self.map.as_deref_mut() {
            map.set_first_tempo(tempo);
        }
    }

    fn set_time_sig(&mut self, num: u32, den: u32) {
        if let Some(map) = self.map.as_deref_mut() {
            map.set_first_signature(num, den);
        }
    }

    fn set_loop(&mut self, enabled: bool, start: f64, end: f64) {
        self.loop_enabled = enabled && end > start;
        self.loop_start = start;
        self.loop_end = end;
    }

    fn set_click(&mut self, gain: f32, accent: bool, output: u16) {
        self.click_gain = gain;
        self.click_accent = accent;
        self.click_output = output;
    }

    fn play(&mut self) {
        self.playing = true;
        self.chase = true;
        self.reapply = true;
        self.restate = !std::mem::take(&mut self.states_held);
        self.count = None;
    }

    fn count_in(&mut self, frames: u64, every: f64, clicks: u32, per_bar: u32) {
        self.playing = false;
        self.count = Some(Count {
            frames,
            every,
            clicks,
            per_bar: per_bar.max(1),
            delay: self.schedule.as_ref().map_or(0, |s| s.latency as u64),
            elapsed: 0,
            next: 0,
            started: false,
        });
    }

    fn stop(&mut self) {
        self.playing = false;
        self.flush_notes = true;
        self.count = None;
        // A performance ends with the song: every track plays its
        // clips on the timeline again.
        for t in self.tracks.iter_mut() {
            if let Some(t) = t.get_mut().as_deref_mut() {
                t.launcher.reset();
            }
        }
        self.launching = false;
    }

    fn seek(&mut self, position: f64) {
        self.head.put(position.max(0.0));
        self.flush_notes = true;
        self.chase = true;
        self.reapply = true;
        self.seeks = self.seeks.wrapping_add(1);
        self.requantize(self.head.beat());
    }
}

/// MIDI and the other ways in and out: inputs, takes, the monitor and the
/// preview.
impl Engine {
    fn set_input(
        &mut self,
        track: TrackSlot,
        first: usize,
        channels: usize,
        monitor: bool,
        armed: bool,
    ) {
        if let Some(t) = self.track_mut(track) {
            t.input_first = first;
            t.input_channels = channels;
            t.monitor = monitor;
            t.armed = armed;
            if !t.takes_midi() {
                release_held(t);
            }
        }
        if channels > 0 && (monitor || armed) && self.track_mut(track).is_some() {
            self.listening = true;
        } else if self.listening {
            self.note_listening();
        }
    }

    fn set_take(&mut self, take: Option<Box<Take>>) {
        if let Some(old) = std::mem::replace(&mut self.take, take) {
            old.shared.close(self.head.beat());
            self.discard(Garbage::Take(old));
        }
    }

    fn set_midi_input(&mut self, track: TrackSlot, port: u32, channel: u8) {
        if let Some(t) = self.track_mut(track) {
            if (t.midi_port, t.midi_channel) != (port, channel) {
                release_held(t);
            }
            t.midi_port = port;
            t.midi_channel = channel;
        }
    }

    fn set_midi_output(&mut self, track: TrackSlot, port: u32, channel: u8, form: Form) {
        let Some(t) = self.track_mut(track) else {
            return;
        };
        let old = std::mem::replace(&mut t.midi_out, port);
        let old_form = std::mem::replace(&mut t.midi_out_form, form);
        t.midi_out_channel = channel;
        t.sent.clear();
        // The notes it left sounding where it played before, or in
        // the form it played in before, end there.
        if old != 0
            && (old != port || old_form != form)
            && let Some(out) = self.midi_out.as_deref_mut()
        {
            let _ = out.push(MidiOut {
                at: 0,
                port: old,
                form: old_form,
                kind: EventKind::AllNotesOff,
            });
        }
    }

    fn set_midi_out(&mut self, out: Option<Box<Producer<MidiOut>>>) {
        if let Some(old) = std::mem::replace(&mut self.midi_out, out) {
            self.discard(Garbage::MidiOut(old));
        }
    }

    fn set_monitor(&mut self, monitor: Option<Box<Producer<f32>>>) {
        if let Some(old) = std::mem::replace(&mut self.monitor, monitor) {
            self.discard(Garbage::Monitor(old));
        }
    }

    fn set_preview(&mut self, preview: Option<Box<Preview>>) {
        let old = std::mem::replace(&mut self.preview, preview);
        if let Some(gone) = std::mem::replace(&mut self.preview_leaving, old) {
            self.discard(Garbage::Preview(gone));
        }
    }

    fn set_preview_gain(&mut self, gain: f32) {
        if let Some(preview) = self.preview.as_deref_mut() {
            preview.set_gain(gain);
        }
    }

    /// What was played live goes into the track's next block, as far as
    /// there is room.
    fn play_live(&mut self, track: TrackSlot, event: EventKind) {
        if let Some(t) = self.track_mut(track)
            && t.live.len() < t.live.capacity()
        {
            t.live.push(event);
        }
    }
}
