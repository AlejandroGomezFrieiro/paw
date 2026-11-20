//! Carrying out the messages of the main thread, between blocks.

use std::sync::atomic::Ordering::Relaxed;

use crate::automation;
use crate::event::EventKind;
use crate::midi_out::MidiOut;

use super::Engine;
use super::click::Count;
use super::device_rt::DeviceRt;
use super::msg::{Garbage, Msg};
use super::track::release_held;

impl Engine {
    pub(super) fn apply(&mut self, msg: Msg) {
        match msg {
            Msg::InsertTrack { slot, track } => {
                if let Some(entry) = self.tracks.get_mut(slot.index()) {
                    if let Some(old) = entry.get_mut().replace(track) {
                        self.discard(Garbage::Track(old));
                    }
                } else {
                    self.discard(Garbage::Track(track));
                }
            }
            Msg::RemoveTrack { slot } => {
                if let Some(old) = self
                    .tracks
                    .get_mut(slot.index())
                    .and_then(|t| t.get_mut().take())
                {
                    self.discard(Garbage::Track(old));
                }
                self.note_states();
            }
            Msg::SetSchedule(schedule) => {
                self.shared.latency.store(schedule.latency, Relaxed);
                if let Some(old) = self.schedule.replace(schedule) {
                    self.discard(Garbage::Schedule(old));
                }
            }
            Msg::SetMix {
                slot,
                gain,
                pan,
                mute,
                quiet,
            } => {
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
            Msg::InsertDevice { slot, device } => {
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
            Msg::RemoveDevice { slot } => {
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
            Msg::SetKey { device, key } => {
                let old = match self.device_mut(device) {
                    Some(slot) => std::mem::replace(&mut slot.key, key),
                    None => key,
                };
                if let Some(old) = old {
                    self.discard(Garbage::Key(old));
                }
            }
            Msg::SetOutputs { device, outs } => {
                let old = match self.device_mut(device) {
                    Some(slot) => std::mem::replace(&mut slot.outs, outs),
                    None => outs,
                };
                if let Some(old) = old {
                    self.discard(Garbage::Outs(old));
                }
            }
            Msg::SetHost { device, path } => match self.device_mut(device) {
                Some(slot) => {
                    if let Some(old) = slot.host.replace(path) {
                        self.discard(Garbage::Host(old));
                    }
                }
                None => self.discard(Garbage::Host(path)),
            },
            Msg::SetDeviceLatency { device, frames } => {
                if let Some(host) = self.device_mut(device).and_then(|s| s.host.as_mut()) {
                    host.set_latency(frames);
                }
            }
            Msg::SetChain { track, chain } => match self.track_mut(track) {
                Some(t) => {
                    let old = std::mem::replace(&mut t.chain, chain);
                    self.discard(Garbage::Chain(old));
                }
                None => self.discard(Garbage::Chain(chain)),
            },
            Msg::SetParam {
                device,
                param,
                value,
            } => {
                if let Some(slot) = self.device_mut(device) {
                    slot.set_param(param, value);
                }
                self.reapply = true;
            }
            Msg::SetBypass { device, bypass } => {
                if let Some(slot) = self.device_mut(device) {
                    slot.bypass = bypass;
                }
            }
            Msg::SetClips { track, clips } => match self.track_mut(track) {
                Some(t) => {
                    let old = std::mem::replace(&mut t.clips, clips);
                    // Notes that were sounding may no longer have a note-off.
                    t.flush = true;
                    t.chase = true;
                    self.discard(Garbage::Clips(old));
                }
                None => self.discard(Garbage::Clips(clips)),
            },
            Msg::EditClips { track, mut edit } => {
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
            Msg::SetAutomation { track, automation } => {
                match self.track_mut(track) {
                    Some(t) => {
                        let old = std::mem::replace(&mut t.automation, automation);
                        self.discard(Garbage::Automation(old));
                    }
                    None => self.discard(Garbage::Automation(automation)),
                }
                self.note_states();
            }
            Msg::SetTempoMap(map) => {
                if let Some(old) = self.map.replace(map) {
                    self.discard(Garbage::TempoMap(old));
                }
            }
            Msg::SetTempo(tempo) => {
                if let Some(map) = self.map.as_deref_mut() {
                    map.set_first_tempo(tempo);
                }
            }
            Msg::SetTimeSig { num, den } => {
                if let Some(map) = self.map.as_deref_mut() {
                    map.set_first_signature(num, den);
                }
            }
            Msg::SetLoop {
                enabled,
                start,
                end,
            } => {
                self.loop_enabled = enabled && end > start;
                self.loop_start = start;
                self.loop_end = end;
            }
            Msg::SetMetronome(on) => self.metronome = on,
            Msg::SetClick {
                gain,
                accent,
                output,
            } => {
                self.click_gain = gain;
                self.click_accent = accent;
                self.click_output = output;
            }
            Msg::StatesHeld => {
                let beat = self.position;
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
            Msg::Play => {
                self.playing = true;
                self.chase = true;
                self.reapply = true;
                self.restate = !std::mem::take(&mut self.states_held);
                self.count = None;
            }
            Msg::CountIn {
                frames,
                every,
                clicks,
                per_bar,
            } => {
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
            Msg::Stop => {
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
            Msg::Seek(position) => {
                self.position = position.max(0.0);
                self.flush_notes = true;
                self.chase = true;
                self.reapply = true;
                self.seeks = self.seeks.wrapping_add(1);
                self.requantize(self.position);
            }
            Msg::Live { track, event } => {
                if let Some(t) = self.track_mut(track)
                    && t.live.len() < t.live.capacity()
                {
                    t.live.push(event);
                }
            }
            Msg::SetInput {
                track,
                first,
                channels,
                monitor,
                armed,
            } => {
                if let Some(t) = self.track_mut(track) {
                    t.input_first = first;
                    t.input_channels = channels;
                    t.monitor = monitor;
                    t.armed = armed;
                    if !t.takes_midi() {
                        release_held(t);
                    }
                }
            }
            Msg::SetTake(take) => {
                if let Some(old) = std::mem::replace(&mut self.take, take) {
                    old.shared.close(self.position);
                    self.discard(Garbage::Take(old));
                }
            }
            Msg::SetMidiInput {
                track,
                port,
                channel,
            } => {
                if let Some(t) = self.track_mut(track) {
                    if (t.midi_port, t.midi_channel) != (port, channel) {
                        release_held(t);
                    }
                    t.midi_port = port;
                    t.midi_channel = channel;
                }
            }
            Msg::MidiIn { port, kind } => self.midi_in(port, kind),
            Msg::SetMidiOutput {
                track,
                port,
                channel,
                form,
            } => {
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
            Msg::SetMidiOut(out) => {
                if let Some(old) = std::mem::replace(&mut self.midi_out, out) {
                    self.discard(Garbage::MidiOut(old));
                }
            }
            Msg::SetMonitor(monitor) => {
                if let Some(old) = std::mem::replace(&mut self.monitor, monitor) {
                    self.discard(Garbage::Monitor(old));
                }
            }
            Msg::SetPreview(preview) => {
                let old = std::mem::replace(&mut self.preview, preview);
                if let Some(gone) = std::mem::replace(&mut self.preview_leaving, old) {
                    self.discard(Garbage::Preview(gone));
                }
            }
            Msg::SetPreviewGain(gain) => {
                if let Some(preview) = self.preview.as_deref_mut() {
                    preview.set_gain(gain);
                }
            }
            Msg::SetSleep(sleep) => self.sleep = sleep,
            Msg::SetPool(pool) => {
                if let Some(old) = self.set_pool(pool) {
                    self.discard(Garbage::Pool(old));
                }
            }
            Msg::SetSlots { track, slots } => match self.track_mut(track) {
                Some(t) => {
                    let old = t.launcher.set_slots(slots);
                    if !t.launcher.follows_arrangement() {
                        t.flush = true;
                        t.chase = true;
                    }
                    self.discard(Garbage::Slots(old));
                }
                None => self.discard(Garbage::Slots(slots)),
            },
            Msg::Launch(launches) => {
                let (position, playing) = (self.position, self.playing);
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
    }
}
