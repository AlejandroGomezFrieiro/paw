//! The engine and the audio device: starting, options and statistics.

use crate::events::{KernelEvent as E};
use super::*;

/// The running engine: the handle that talks to it, the ids it knows the
/// project's things by, the audio stream it plays on, and what it was
/// started with.
pub(super) struct EngineLink {
    pub handle: EngineHandle,
    pub map: Mapper,
    pub stream: Stream,
    /// Threads to process tracks on, or 0 for as many as the machine has cores.
    pub threads: usize,
    /// Devices at rest sleep through silent blocks (`paw.opt.device_sleep`).
    pub sleep: bool,
    /// What the engine was last started with, to start it again with a
    /// device changed.
    pub backend: BackendOptions,
}

impl Session {
    pub fn engine_info(&self) -> Value {
        let info: &StreamInfo = &self.engine.stream.info;
        json!({
            "backend": info.backend, "device": info.device, "sample_rate": info.sample_rate,
            "device_id": info.device_id, "input_device_id": info.input_device_id,
            "buffer_size": info.buffer_size, "cpu": self.engine.handle.shared.cpu(),
            // Frames per callback as the device runs it, 0 until it has.
            "block": self.engine.handle.shared.period(),
            "xruns": self.engine.handle.shared.xruns(), "input_device": info.input_device,
            "input_channels": info.input_channels,
            "input_latency": self.engine.handle.shared.input_latency() as f64 * 1000.0,
            "output_latency": self.engine.handle.shared.output_latency() as f64 * 1000.0,
            // How far the output is behind the transport because of devices
            // that look ahead, in milliseconds.
            "latency": self.engine.map.latency as f64 * 1000.0 / info.sample_rate as f64,
            "midi": self.midi.inputs.is_some(),
            "blocks": block_json(&self.engine.handle.shared.blocks.summary(), info.sample_rate),
            "leaked": self.engine.handle.shared.leaked(),
            // Threads tracks are processed on, counting the audio thread, and
            // what was asked for (0 leaves it to the machine).
            "threads": self.engine.handle.shared.threads(),
            "threads_wanted": self.engine.threads,
            // Whether devices at rest sleep through silence, and the blocks
            // of devices run and slept through since the engine started.
            "device_sleep": self.engine.sleep,
            "device_runs": self.engine.handle.shared.device_blocks().0,
            "device_sleeps": self.engine.handle.shared.device_blocks().1,
            // Blocks in which the whole engine rested: stopped and silent.
            "engine_rests": self.engine.handle.shared.engine_rests(),
            // Groups of tracks shared out between threads since the engine
            // started: one with little work runs on the audio thread alone.
            "shared_groups": self.engine.handle.shared.shared_groups(),
            // What went wrong while playing, for the status line: blocks
            // plugins did not deliver in time, MIDI events dropped, frames
            // of the take being recorded lost to a slow disk, devices that
            // have stopped, and decoded audio files held in memory.
            "late_blocks": self.live.values().filter_map(|l| l.controller.as_ref()).map(|c| c.late_blocks()).sum::<u64>(),
            "midi_dropped": paw_engine::event::dropped(),
            "record_dropped": self.rec.take.as_ref().map_or(0, |t| t.shared.dropped()),
            "devices_stopped": self.live.values().filter(|l| l.stopped.is_some()).count(),
            "audio_files": self.audio.len(),
            // The device that went away and is waited for, or nil.
            "lost": self.audio_lost(),
        })
    }

    /// Process tracks on this many threads, counting the audio thread, or
    /// with 0 on as many as the machine has cores. Tracks that do not feed
    /// each other are then processed side by side; the sound is the same.
    pub fn set_threads(&mut self, threads: usize) -> Result<()> {
        if threads > MAX_THREADS {
            bail!(
                "{threads} threads are too many: use up to {MAX_THREADS}, or 0 to leave it to the machine"
            );
        }
        self.engine.threads = threads;
        self.send_pool();
        Ok(())
    }

    /// Worker threads for an engine: for the live one, or with `threads`
    /// for a render that asks for a number of its own.
    pub(crate) fn pool(&self, threads: Option<usize>) -> Option<Box<Pool>> {
        let threads = match threads.unwrap_or(self.engine.threads) {
            0 => default_threads(),
            threads => threads.min(MAX_THREADS),
        };
        (threads > 1).then(|| Box::new(Pool::new(threads)))
    }

    pub(super) fn send_pool(&mut self) {
        let pool = self.pool(None);
        self.engine.handle.send(Msg::SetPool(pool));
        self.engine.handle.send(Msg::SetSleep(self.engine.sleep));
    }

    /// Whether devices at rest (a reverb whose tail has died away, a synth
    /// with no note sounding) sleep through silent blocks, which saves the
    /// processor their work. The sound is the same either way.
    pub fn set_sleep(&mut self, sleep: bool) {
        self.engine.sleep = sleep;
        self.engine.handle.send(Msg::SetSleep(sleep));
    }

    /// Whether devices at rest sleep, for a render that does not say.
    pub(crate) fn sleep(&self) -> bool {
        self.engine.sleep
    }

    /// The devices the system offers, and which are open.
    pub fn audio_devices(&self) -> Result<Value> {
        let list = backend::list_devices(&self.engine.backend)?;
        let rows = |devices: &[backend::AudioDevice]| -> Vec<Value> {
            devices
                .iter()
                .map(|d| {
                    json!({
                        "name": d.name, "id": d.id, "channels": d.channels,
                        "sample_rate": d.sample_rate, "min_block": d.min_block,
                        "max_block": d.max_block,
                    })
                })
                .collect()
        };
        let info = &self.engine.stream.info;
        Ok(json!({
            "backend": list.backend, "outputs": rows(&list.outputs), "inputs": rows(&list.inputs),
            "output": info.device, "input": info.input_device,
            // Empty when the system's default is open.
            "output_id": info.device_id, "input_id": info.input_device_id,
            "buffer_size": info.buffer_size,
            // The sound systems there are, and the rate that runs.
            "backends": backend::backends(), "sample_rate": info.sample_rate,
            "rates": backend::RATES,
        }))
    }

    /// Open other devices: `output` and `input` by name, id or part of a
    /// name, `"default"` for the system's; `buffer` in frames, 0 to leave
    /// it to the device. What is not given stays as it is. A name that
    /// matches nothing is an error and changes nothing. The choice is
    /// remembered in [`device_file`](Self::device_file) for the next run.
    pub fn audio_use(
        &mut self,
        output: Option<String>,
        input: Option<String>,
        buffer: Option<u32>,
        choice: AudioChoice,
    ) -> Result<()> {
        let mut opts = self.engine.backend.clone();
        if opts.backend == BackendChoice::Auto && self.engine.stream.info.backend != BackendChoice::Null {
            // Keep to the backend that opened, rather than trying them all again.
            opts.backend = self.engine.stream.info.backend.clone();
        }
        if let Some(word) = choice.backend.filter(|b| !b.is_empty()) {
            if !backend::backends().contains(&word) {
                bail!(
                    "no sound system `{word}`; there are: {}",
                    backend::backends().join(", ")
                );
            }
            let backend = BackendChoice::from(word.as_str());
            // Another system names its devices otherwise: start from its defaults.
            if backend != opts.backend {
                opts.output_device = None;
                opts.input_device = None;
            }
            opts.backend = backend;
        }
        if let Some(rate) = choice.rate {
            opts.sample_rate = (rate > 0).then_some(rate);
        }
        let list = backend::list_devices(&opts)?;
        let pick = |wanted: String,
                    devices: &[backend::AudioDevice],
                    what: &str|
         -> Result<Option<String>> {
            if wanted.is_empty() || wanted == "default" {
                return Ok(None);
            }
            match backend::find_device(devices, &wanted) {
                Some(device) => Ok(Some(device.name.clone())),
                None => {
                    let names: Vec<&str> = devices.iter().map(|d| d.name.as_str()).collect();
                    bail!(
                        "no {what} device matches `{wanted}`; there {}",
                        if names.is_empty() {
                            "are none".to_string()
                        } else {
                            format!("are: {}", names.join(", "))
                        }
                    )
                }
            }
        };
        if let Some(wanted) = output {
            opts.output_device = pick(wanted, &list.outputs, "output")?;
        }
        if let Some(wanted) = input {
            opts.input_device = pick(wanted, &list.inputs, "input")?;
            opts.input = true;
        }
        if let Some(frames) = buffer {
            opts.buffer_size = (frames > 0).then_some(frames);
        }
        self.engine_restart(&opts)?;
        if let Some(path) = &self.device_file
            && self.engine.stream.info.backend != BackendChoice::Null
        {
            let remembered = crate::audio::Remembered {
                output: opts.output_device.clone(),
                input: opts.input_device.clone(),
                buffer: opts.buffer_size,
                backend: (opts.backend != BackendChoice::Auto).then(|| opts.backend.to_string()),
                rate: opts.sample_rate,
            };
            if let Err(err) = crate::audio::save(path, &remembered) {
                self.warnings
                    .push(format!("the devices could not be remembered: {err:#}"));
            }
        }
        Ok(())
    }

    /// Peak level of each input channel of the device, as linear gain.
    pub fn input_levels(&self) -> Vec<f32> {
        (0..self.engine.stream.info.input_channels as usize)
            .map(|ch| self.engine.handle.shared.input_meter(ch))
            .collect()
    }

    /// Audio blocks the engine has finished since it started, or, with a
    /// device, the blocks that device has run (not slept through). `None`
    /// for a device the engine does not have.
    pub fn blocks(&self, device: Option<Id>) -> Option<u64> {
        let shared = &self.engine.handle.shared;
        match device {
            None => Some(shared.processed()),
            Some(id) => self.engine.map.devices.get(&id).map(|&slot| shared.device_processed(slot)),
        }
    }

    /// Forget the processing times recorded so far.
    pub fn engine_reset_stats(&self) {
        self.engine.handle.shared.blocks.reset();
    }

    /// Play a track from a sound file for now, as if it were frozen (see
    /// [`crate::freeze`]), or live again with `None`. The project is not
    /// changed: nothing is saved or undone, and renders play it live.
    pub fn hold(&mut self, track: Id, file: Option<PathBuf>) -> Result<()> {
        if track == MASTER_ID || self.project.track(track).is_none() {
            bail!("no track {track} to hold");
        }
        match file {
            Some(file) => self.engine.map.held_files.insert(track, file),
            None => self.engine.map.held_files.remove(&track),
        };
        self.dirty = true;
        self.flush();
        Ok(())
    }

    /// The tracks held by [`hold`](Self::hold).
    pub fn held(&self) -> Vec<Id> {
        let mut out: Vec<Id> = self.engine.map.held_files.keys().copied().collect();
        out.sort_unstable();
        out
    }

    /// The track that plays MIDI input while no track is armed, as if it
    /// were monitored, or none. The project does not change.
    pub fn set_follow(&mut self, track: Option<Id>) {
        self.set_follows(Follow { selected: track, ..self.engine.map.follow });
    }

    /// The track that plays MIDI input as if it were monitored, also while
    /// another track is armed, in place of [`set_follow`](Self::set_follow)'s
    /// track; or none. The project does not change.
    pub fn set_follow_always(&mut self, track: Option<Id>) {
        self.set_follows(Follow { always: track, ..self.engine.map.follow });
    }

    fn set_follows(&mut self, follow: Follow) {
        if self.engine.map.follow == follow {
            return;
        }
        self.engine.map.follow = follow;
        self.dirty = true;
        self.flush();
    }

    /// Let only these tracks be heard for now, with what they pass through
    /// (as a solo would, without the project's solos changing), or every
    /// track again with `None`.
    pub fn set_audible(&mut self, tracks: Option<Vec<Id>>) {
        self.engine.map.audible = tracks.map(|ids| ids.into_iter().collect());
        self.dirty = true;
        self.flush();
    }

    /// Stop the audio backend and start another one, rebuilding the engine
    /// from the project.
    pub fn engine_restart(&mut self, opts: &BackendOptions) -> Result<()> {
        self.capture_states();
        let position = self.position();
        let was_playing = self.play.playing;
        self.stop();
        let (handle, stream) = start_engine(opts)?;
        self.engine.backend = opts.clone();
        // Assigning drops the old stream, which stops the old engine.
        self.engine.stream = stream;
        self.engine.handle = handle;
        self.send_pool();
        self.live.clear();
        self.play.seeks = 0;
        let held = std::mem::take(&mut self.engine.map.held_files);
        let audible = self.engine.map.audible.take();
        let follow = self.engine.map.follow;
        self.engine.map = Mapper::new();
        self.engine.map.follow = follow;
        self.engine.map.defer = self.loads.on;
        (self.engine.map.held_files, self.engine.map.audible) = (held, audible);
        self.loads.devices.clear();
        self.synced = Project::default();
        self.dirty = true;
        self.warnings.extend(self.engine.stream.info.warning.clone());
        self.connect_midi();
        self.engine.handle.send(Msg::SetTempo(self.project.tempo));
        self.send_transport();
        let events = std::mem::take(&mut self.events);
        self.flush();
        self.events = events;
        self.seek(position);
        if was_playing {
            self.play();
        }
        let info = self.engine_info();
        self.emit(E::EngineStarted(info));
        Ok(())
    }
}
