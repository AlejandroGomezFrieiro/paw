//! The transport: play, stop, seek, loop, count-in and recording.

use crate::events::{KernelEvent as E, Nothing, Play, Position, Record};
use super::*;

impl Session {
    pub(super) fn send_transport(&mut self) {
        let t = &self.transport;
        self.handle.send(Msg::SetLoop {
            enabled: t.loop_enabled,
            start: t.loop_start,
            end: t.loop_end,
        });
        self.handle.send(Msg::SetMetronome(t.metronome));
        self.handle.send(Msg::SetClick {
            gain: paw_engine::db_to_gain(t.click_level),
            accent: t.click_accent,
            output: t.click_output as u16,
        });
    }

    /// Where a take punched in from a stop starts playing: the pre-roll
    /// before the punch in, but never later than the playhead (a playhead
    /// further back is left alone), and not at all when the playhead is
    /// inside the range or past it.
    pub(super) fn pre_roll_start(&self) -> Option<f64> {
        let t = &self.transport;
        if !t.recording || self.playing || !t.punch_enabled || t.punch_end <= t.punch_start {
            return None;
        }
        if t.pre_roll == 0 && t.pre_roll_seconds <= 0.0 {
            return None;
        }
        let at = self.position();
        if at > t.punch_start + 1e-9 {
            return None;
        }
        let map = self.project.tempo_map();
        let bar = (map.bar_of(t.punch_start) - t.pre_roll as i64).max(0);
        let from = map.bar_start(bar);
        let from = map.beat((map.seconds(from) - t.pre_roll_seconds).max(0.0));
        Some(from.min(at))
    }

    pub fn play(&mut self) {
        if let Some(from) = self.pre_roll_start() {
            self.seek(from);
        }
        self.flush();
        if self.transport.recording {
            self.start_take();
        }
        self.read_ahead_from(self.position());
        // A take begun with the song stopped is counted in first.
        let count = (self.transport.recording && !self.playing && self.transport.count_in > 0)
            .then(|| self.count_in())
            .flatten();
        let beats = match count {
            Some((msg, beats)) => {
                self.handle.send(msg);
                beats
            }
            None => {
                self.handle.send(Msg::Play);
                0
            }
        };
        self.count_sent = beats;
        self.playing = true;
        let position = self.position();
        self.emit(E::TransportPlay(Play { position, count_in: beats as f64 }));
    }

    /// The count-in before playing from where the playhead is: as many bars
    /// as `count_in` says, at the tempo and in the signature there, a click
    /// for every beat of the signature. The message for the engine, and how
    /// many beats it counts.
    pub(super) fn count_in(&self) -> Option<(Msg, u32)> {
        let map = self.project.tempo_map();
        let at = self.position();
        let (num, den) = map.signature(at);
        let every = 60.0 / map.tempo(at) * 4.0 / den as f64 * self.handle.sample_rate;
        let clicks = self.transport.count_in.min(16) * num;
        let frames = (clicks as f64 * every).round() as u64;
        (frames > 0).then_some((
            Msg::CountIn {
                frames,
                every,
                clicks,
                per_bar: num,
            },
            clicks,
        ))
    }

    /// Beats of a count-in still to be counted before the song starts; 0
    /// when none is under way.
    pub fn counting(&self) -> u32 {
        let shared = &self.handle.shared;
        if !self.playing || shared.playing() {
            return 0;
        }
        // Until the engine has taken the count up, it is all still to come.
        match shared.counting() {
            0 => self.count_sent,
            left => left,
        }
    }

    pub fn stop(&mut self) {
        if self.playing {
            self.handle.send(Msg::Stop);
            self.playing = false;
            // The engine stops at its next block. Wait for that, so that the
            // position read from here on is where it stopped.
            let deadline = Instant::now() + Duration::from_millis(200);
            while self.handle.shared.playing() && Instant::now() < deadline {
                std::thread::sleep(Duration::from_micros(200));
            }
            let position = self.position();
            self.emit(E::TransportStop(Position { position }));
            // Stopping ends the take and, with it, record mode: the next
            // play is a play, not another take over the one just made.
            if self.rec.take.is_some() {
                self.transport.recording = false;
                self.emit(E::TransportChanged(Nothing {}));
            }
            self.finish_take();
        }
    }

    pub fn seek(&mut self, beats: f64) {
        let beats = beats.max(0.0);
        // A take is continuous, so jumping ends it and starts another.
        let recording = self.rec.take.is_some();
        self.finish_take();
        self.handle.send(Msg::Seek(beats));
        self.seeks = self.seeks.wrapping_add(1);
        self.seek_target = beats;
        self.read_ahead_from(beats);
        self.emit(E::TransportSeek(Position { position: beats }));
        if recording && self.playing {
            self.start_take();
        }
    }

    /// Turn on recording and play.
    pub fn record(&mut self) -> Result<()> {
        self.transport_set("recording", Value::Bool(true))?;
        if !self.playing {
            self.play();
        }
        Ok(())
    }

    /// Where new recordings go: `media` beside the project file, or the user's
    /// data directory for a project that has never been saved.
    pub fn media_dir(&self) -> PathBuf {
        match &self.path {
            Some(path) => std::path::absolute(path)
                .unwrap_or_else(|_| path.clone())
                .with_file_name("media"),
            None => scratch_media_dir(),
        }
    }

    /// Start capturing every armed track: audio from those with an input,
    /// notes from the others.
    pub(super) fn start_take(&mut self) {
        if self.rec.take.is_some() {
            return;
        }
        // The engine has to know the tracks before it can capture them.
        self.flush();
        self.rec.takes += 1;
        let number = self.rec.takes;
        let shared = Arc::new(TakeShared::default());
        let sample_rate = self.handle.sample_rate as u32;
        let inputs = self.stream.info.input_channels as usize;
        let dir = self.media_dir();
        let mut audio = Vec::new();
        let mut captures = Vec::new();
        for track in self.project.tracks.iter().filter(|t| t.armed) {
            let Some((first, channels)) = track.input_channels() else {
                continue;
            };
            if first + channels > inputs {
                self.warnings.push(format!(
                    "{} records input {} but the audio device has {inputs} input channels",
                    track.name,
                    track.input.as_deref().unwrap_or("")
                ));
            }
            let started = std::fs::create_dir_all(&dir)
                .with_context(|| format!("creating {}", dir.display()))
                .and_then(|()| {
                    let path =
                        unique_path(&dir, &format!("{}-take{number}", file_safe(&track.name)));
                    // Two seconds of room for the writer to fall behind by.
                    let (tx, rx) = RingBuffer::new(sample_rate as usize * channels * 2);
                    let thread = record::spawn_writer(
                        &path,
                        sample_rate,
                        channels as u16,
                        rx,
                        shared.clone(),
                    )?;
                    Ok((path, thread, tx))
                });
            match started {
                Ok((path, thread, ring)) => {
                    audio.push((track.id, path, thread));
                    captures.push(AudioCapture {
                        first,
                        channels,
                        ring,
                    });
                }
                Err(err) => self
                    .warnings
                    .push(format!("cannot record {}: {err:#}", track.name)),
            }
        }
        let channels: usize = captures.iter().map(|c| c.channels).sum();
        let (midi_tx, midi_rx) = RingBuffer::new(16384);
        let (wraps_tx, wraps_rx) = RingBuffer::new(4096);
        let t = &self.transport;
        let looped = (t.loop_enabled && t.loop_end > t.loop_start)
            .then_some((t.loop_start, t.loop_end));
        let punch = (t.punch_enabled && t.punch_end > t.punch_start)
            .then_some((t.punch_start, t.punch_end));
        let mut take = Take::new(captures, midi_tx, shared.clone(), wraps_tx);
        if let Some((from, to)) = punch {
            // What is played at the punch out arrives as late as the
            // recording is behind the song: capture that much past it.
            let map = self.project.tempo_map();
            take.punch = Some((from, map.beat(map.seconds(to) + self.record_latency(true))));
            let at = self.position();
            let comes_round = looped.is_some_and(|(start, end)| at < end && start < to);
            if at >= to - 1e-9 && !comes_round {
                self.warnings.push(format!(
                    "the playhead is past the punch out (bar {}): nothing will be recorded",
                    map.bar_of(to) + 1
                ));
            }
        }
        self.handle.send(Msg::SetTake(Some(Box::new(take))));
        self.rec.take = Some(Recording {
            number,
            shared,
            audio,
            midi: midi_rx,
            held: HashMap::new(),
            notes: BTreeMap::new(),
            controls: BTreeMap::new(),
            looped,
            punch,
            wraps: wraps_rx,
            wrapped: Vec::new(),
        });
        // Where the files go and how fast they grow, for a warning when
        // the disk is nearly full; and the files, for a safety copy.
        let files: Vec<PathBuf> = self
            .rec
            .take
            .iter()
            .flat_map(|t| t.audio.iter().map(|a| a.1.clone()))
            .collect();
        let record = Record {
            position: self.position(), take: number, free: crate::safe::free_space(&dir), dir,
            bytes_per_second: channels * 4 * sample_rate as usize, files,
        };
        self.emit(E::TransportRecord(record));
    }

    /// The take being recorded, as a safety copy keeps it: its files, which
    /// track each is for and where it starts, so that the take can be put
    /// back as clips if the program never gets to finish it.
    pub(super) fn take_in_progress(&self) -> Value {
        let Some(take) = &self.rec.take else {
            return Value::Null;
        };
        let start = take.shared.start().unwrap_or_else(|| self.position());
        let files: Vec<Value> = take
            .audio
            .iter()
            .map(|(track, path, _)| json!({ "track": track, "file": path }))
            .collect();
        json!({
            "name": format!("take {}", take.number), "start": start,
            "offset": self.record_latency(true), "files": files,
        })
    }

    /// A take that was being recorded when a safety copy was made, put back
    /// as clips from whatever its files hold.
    pub(super) fn restore_take(&mut self, take: &Value) {
        let Some(files) = take["files"].as_array() else {
            return;
        };
        let start = take["start"].as_f64().unwrap_or(0.0);
        for entry in files {
            let (Some(track), Some(file)) = (entry["track"].as_u64(), entry["file"].as_str())
            else {
                continue;
            };
            // The project's folder may have moved since: look in its `media`.
            let mut path = PathBuf::from(file);
            if !path.exists()
                && let Some(name) = path.file_name()
                && self.media_dir().join(name).exists()
            {
                path = self.media_dir().join(name);
            }
            let opts = ClipOpts {
                name: take["name"].as_str().map(String::from),
                start,
                file: Some(path),
                offset: take["offset"].as_f64().unwrap_or(0.0),
                source_tempo: Some(self.project.tempo_map().tempo(start)),
                ..ClipOpts::default()
            };
            if let Err(err) = self.clip_add(track as Id, opts) {
                self.warnings
                    .push(format!("the take in {file} could not be put back: {err:#}"));
            }
        }
    }

    /// Collect the notes the engine has captured for the take so far.
    pub(super) fn drain_take(&mut self) {
        let Some(take) = self.rec.take.as_mut() else {
            return;
        };
        while let Ok(frames) = take.wraps.pop() {
            take.wrapped.push(frames);
        }
        while let Ok(capture) = take.midi.pop() {
            let Some(track) = self
                .map
                .tracks
                .iter()
                .find(|(_, slot)| **slot == capture.slot)
                .map(|(id, _)| *id)
            else {
                continue;
            };
            match capture.kind {
                EventKind::NoteOn { key, vel, attr, .. } => {
                    take.end_note(track, key, capture.beat, capture.pass);
                    let velocity = (vel * 127.0).round().clamp(1.0, 127.0) as u8;
                    let note = (capture.beat, velocity, capture.pass, NoteAttr::of(attr));
                    take.held.insert((track, key), note);
                }
                EventKind::NoteOff { key, .. } => {
                    take.end_note(track, key, capture.beat, capture.pass)
                }
                EventKind::Control { .. }
                | EventKind::NoteControl { .. }
                | EventKind::Program { .. } => {
                    if let Some(control) = Control::from_event(capture.beat, capture.kind) {
                        take.controls
                            .entry((track, capture.pass))
                            .or_default()
                            .push(control);
                    }
                }
                EventKind::AllNotesOff => {
                    let keys: Vec<u8> = take
                        .held
                        .keys()
                        .filter(|(t, _)| *t == track)
                        .map(|(_, k)| *k)
                        .collect();
                    for key in keys {
                        take.end_note(track, key, capture.beat, capture.pass);
                    }
                }
            }
        }
    }

    /// Stop capturing and turn what was captured into clips where the take
    /// began, as one undo step.
    pub(super) fn finish_take(&mut self) {
        let Some(shared) = self.rec.take.as_ref().map(|t| t.shared.clone()) else {
            return;
        };
        self.handle.send(Msg::SetTake(None));
        let deadline = Instant::now() + Duration::from_secs(2);
        while !shared.closed() && Instant::now() < deadline {
            self.handle.collect_garbage();
            std::thread::sleep(Duration::from_millis(1));
        }
        // No engine is running to let go of the take, so let go of it here.
        shared.close(self.position());
        self.drain_take();
        let mut take = self.rec.take.take().unwrap();
        let (start, end) = (shared.start(), shared.end());
        let rounds = take.wrapped.len() as u32;
        let held: Vec<(Id, u8)> = take.held.keys().copied().collect();
        for (track, key) in held {
            take.end_note(track, key, end, rounds);
        }
        // The take as the times it went round the loop, or as the one
        // stretch it is.
        let rate = self.handle.sample_rate;
        let mut looped = take.looped.filter(|_| rounds > 0);
        let mut passes: Vec<Pass> = Vec::new();
        if let (Some(start), Some(punch)) = (start, take.punch) {
            passes = self.punched_passes(&take, punch, start, end);
            // Several times round the punch range are takes of one clip
            // over it, as several times round the loop are over the loop.
            looped = (passes.len() > 1).then(|| {
                let stop = take.looped.map_or(punch.1, |(_, end)| punch.1.min(end));
                (punch.0, stop)
            });
        } else if let Some(start) = start {
            match looped {
                Some((loop_start, loop_end)) => {
                    passes.push(Pass {
                        index: 0,
                        start,
                        end: loop_end,
                        seconds: 0.0,
                    });
                    for (i, frames) in take.wrapped.iter().enumerate() {
                        let last = i + 1 == take.wrapped.len();
                        passes.push(Pass {
                            index: i as u32 + 1,
                            start: loop_start,
                            end: if last { end.min(loop_end) } else { loop_end },
                            seconds: *frames as f64 / rate,
                        });
                    }
                }
                None => passes.push(Pass {
                    index: 0,
                    start,
                    end,
                    seconds: 0.0,
                }),
            }
        }

        self.checkpoint();
        let name = format!("take {}", take.number);
        let audio = std::mem::take(&mut take.audio);
        for (track, path, thread) in audio {
            // A writer that stopped on an error has kept what it wrote, as a
            // whole WAV file: that becomes the clip like any other.
            let frames = match thread.join() {
                Ok(written) => {
                    if let Some(err) = written.error {
                        self.warnings.push(format!(
                            "recording stopped: writing {} failed ({err}); the {:.1} s before that are kept",
                            path.display(),
                            written.frames as f64 / self.handle.sample_rate
                        ));
                    }
                    written.frames
                }
                Err(_) => 0,
            };
            if frames == 0 || passes.is_empty() {
                let _ = std::fs::remove_file(&path);
                continue;
            }
            if let Err(err) =
                self.add_recorded_audio(track, &path, &name, &passes, looped, take.punch.is_some())
            {
                self.warnings.push(format!(
                    "recorded {} but could not add it: {err:#}",
                    path.display()
                ));
            }
        }
        if let Some(start) = start {
            // Notes are only late by what the player heard late.
            let map = self.project.tempo_map();
            let late = start - map.beat(map.seconds(start) - self.record_latency(false));
            let tracks: BTreeSet<Id> = take
                .notes
                .keys()
                .chain(take.controls.keys())
                .map(|(track, _)| *track)
                .collect();
            for track in tracks {
                if passes.is_empty() {
                    break;
                }
                if let Err(err) =
                    self.add_recorded_notes(track, &mut take, &name, &passes, looped, late)
                {
                    self.warnings
                        .push(format!("could not add the recorded notes: {err:#}"));
                }
            }
        }
        if shared.dropped() > 0 {
            self.warnings.push(format!(
                "the disk fell behind: {} frames of {name} were lost",
                shared.dropped()
            ));
        }
        self.checkpoint();
    }

    /// The times a punched take went through its range (`from` to `to`):
    /// one pass for each time round the loop that captured anything, each
    /// with where its sound begins in the take's files. Capturing began at
    /// `start` and the take was let go of at `end`.
    pub(super) fn punched_passes(&self, take: &Recording, (from, to): (f64, f64), start: f64, end: f64) -> Vec<Pass> {
        let map = self.project.tempo_map();
        let rate = self.handle.sample_rate;
        // Capturing stops at the loop's end if that comes first, and after
        // a jump back starts again where the loop does if that is later.
        let (stop, again) = match take.looped {
            Some((loop_start, loop_end)) => (to.min(loop_end), from.max(loop_start)),
            None => (to, from),
        };
        // A block cut at the punch in may start a hair after it.
        let first = if map.seconds_between(from, start).abs() * rate < 1.5 {
            from
        } else {
            start.max(from)
        };
        let mut out = Vec::new();
        let mut before = 0u64;
        for round in 0..=take.wrapped.len() {
            let last = round == take.wrapped.len();
            let seconds = before as f64 / rate;
            let captured = if last {
                end > from + 1e-9
            } else {
                take.wrapped[round] > before
            };
            if !last {
                before = take.wrapped[round];
            }
            if !captured {
                continue;
            }
            let begin = if out.is_empty() { first } else { again };
            let finish = if last { end.min(stop) } else { stop };
            if finish - begin > 1e-9 {
                out.push(Pass {
                    index: round as u32,
                    start: begin,
                    end: finish,
                    seconds,
                });
            }
        }
        out
    }

    /// Turn a track's recorded file into clips. A take that never went
    /// round the loop is one clip where it began. One that did becomes a
    /// clip over the loop whose takes are the times round, the last of them
    /// the one that plays (`clip.meta.takes`, see `paw.takes`), and a clip
    /// before the loop for what was played on the way in.
    pub(super) fn add_recorded_audio(
        &mut self,
        track: Id,
        path: &Path,
        name: &str,
        passes: &[Pass],
        looped: Option<(f64, f64)>,
        punched: bool,
    ) -> Result<()> {
        // What was played along with the song was heard late and arrived
        // late: leave that much off the front of the file.
        let latency = self.record_latency(true);
        let Some((loop_start, loop_end)) = looped else {
            let pass = &passes[0];
            let opts = ClipOpts {
                name: Some(name.to_string()),
                start: pass.start,
                // A punched take covers its punch range exactly; its file
                // holds a little more, for the latency.
                length: punched.then_some(pass.end - pass.start),
                file: Some(path.to_path_buf()),
                offset: latency + pass.seconds,
                source_tempo: Some(self.project.tempo_map().tempo(pass.start)),
                ..ClipOpts::default()
            };
            return self.clip_add(track, opts).map(|_| ());
        };
        let map = self.project.tempo_map().clone();
        let first = &passes[0];
        let last = &passes[passes.len() - 1];
        let whole = loop_end - loop_start;
        // The first time round counts from the loop's start if it began
        // there or before; the last if it got at least half way.
        let from_start = first.start <= loop_start + 1e-6;
        let lead = map.seconds_between(first.start.min(loop_start), loop_start);
        let mut kept: Vec<(&Pass, f64)> = Vec::new();
        if from_start {
            kept.push((first, latency + lead));
        }
        for pass in &passes[1..passes.len() - 1] {
            kept.push((pass, latency + pass.seconds));
        }
        let complete = !kept.is_empty();
        if last.end - loop_start >= whole / 2.0 || !complete {
            kept.push((last, latency + last.seconds));
        }
        let length = if complete {
            whole
        } else {
            last.end - loop_start
        };
        if from_start && first.start < loop_start - 1e-6 {
            // What was played on the way into the loop.
            let opts = ClipOpts {
                name: Some(format!("{name} lead-in")),
                start: first.start,
                length: Some(loop_start - first.start),
                file: Some(path.to_path_buf()),
                offset: latency,
                source_tempo: Some(map.tempo(first.start)),
                ..ClipOpts::default()
            };
            self.clip_add(track, opts)?;
        } else if !from_start {
            if first.start >= loop_start + length - 1e-6 {
                // It began after everything else ends: a clip of its own.
                let opts = ClipOpts {
                    name: Some(name.to_string()),
                    start: first.start,
                    length: Some(loop_end - first.start),
                    file: Some(path.to_path_buf()),
                    offset: latency,
                    source_tempo: Some(map.tempo(first.start)),
                    ..ClipOpts::default()
                };
                self.clip_add(track, opts)?;
            } else {
                self.warnings.push(format!(
                    "{name}: the first time round began in the middle of the loop and is left out; its sound is the first {:.1} s of {}",
                    map.seconds_between(first.start, loop_end),
                    path.display()
                ));
            }
        }
        if length <= 1e-6 {
            return Ok(());
        }
        let mut meta = Map::new();
        if kept.len() > 1 {
            let list: Vec<Value> = kept
                .iter()
                .enumerate()
                .map(|(i, (_, offset))| {
                    let label = format!("{name}.{}", i + 1);
                    if i + 1 == kept.len() {
                        json!({ "name": label })
                    } else {
                        json!({ "name": label, "file": path, "offset": offset, "gain": 0.0 })
                    }
                })
                .collect();
            // `origin`: the offset of the clip itself while the others'
            // offsets are as written here (see `paw.takes`).
            meta.insert(
                "takes".into(),
                json!({
                    "active": kept.len(), "origin": kept[kept.len() - 1].1, "list": list,
                }),
            );
        }
        let opts = ClipOpts {
            name: Some(name.to_string()),
            start: loop_start,
            length: Some(length),
            file: Some(path.to_path_buf()),
            offset: kept[kept.len() - 1].1,
            meta,
            source_tempo: Some(map.tempo(loop_start)),
            ..ClipOpts::default()
        };
        self.clip_add(track, opts).map(|_| ())
    }

    /// Turn the notes and controller moves recorded for a track into clips,
    /// as [`add_recorded_audio`](Self::add_recorded_audio) does for sound:
    /// every time round the loop that something was played in is a take.
    pub(super) fn add_recorded_notes(
        &mut self,
        track: Id,
        take: &mut Recording,
        name: &str,
        passes: &[Pass],
        looped: Option<(f64, f64)>,
        late: f64,
    ) -> Result<()> {
        let mut played: Vec<(u32, Vec<Note>, Vec<Control>)> = Vec::new();
        for pass in passes {
            let notes = take.notes.remove(&(track, pass.index)).unwrap_or_default();
            let controls = take
                .controls
                .remove(&(track, pass.index))
                .unwrap_or_default();
            if !notes.is_empty() || !controls.is_empty() {
                played.push((pass.index, notes, controls));
            }
        }
        // Count from where a clip starts, moved earlier by the latency. A
        // punched take keeps what falls inside its range, and notes held
        // across the punch out end there.
        let punch = take.punch.map(|_| {
            looped.map_or(passes[0].end - passes[0].start, |(start, end)| end - start)
        });
        let place = |notes: &mut Vec<Note>, controls: &mut Vec<Control>, origin: f64| {
            for note in notes.iter_mut() {
                note.start = (note.start - origin - late).max(0.0);
            }
            for control in controls.iter_mut() {
                control.start = (control.start - origin - late).max(0.0);
            }
            if let Some(length) = punch {
                notes.retain(|n| n.start < length - 1e-9);
                for note in notes.iter_mut() {
                    note.length = note.length.min(length - note.start);
                }
                controls.retain(|c| c.start < length - 1e-9);
            }
        };
        let Some((loop_start, loop_end)) = looped else {
            let Some((_, mut notes, mut controls)) = played.pop() else {
                return Ok(());
            };
            let (start, end) = (passes[0].start, passes[0].end);
            place(&mut notes, &mut controls, start);
            let last = notes.iter().map(|n| n.start + n.length).fold(0.0, f64::max);
            let opts = ClipOpts {
                kind: Some("midi".into()),
                name: Some(name.to_string()),
                start,
                length: Some(punch.unwrap_or((end - start).max(last))),
                notes,
                controls,
                ..ClipOpts::default()
            };
            return self.clip_add(track, opts).map(|_| ());
        };
        // What was played on the way into the loop is a clip before it.
        let start = passes[0].start;
        if start < loop_start - 1e-6
            && let Some((0, notes, controls)) = played.first_mut()
        {
            let (mut before, inside): (Vec<Note>, Vec<Note>) = std::mem::take(notes)
                .into_iter()
                .partition(|n| n.start - late < loop_start);
            let (mut moves, later): (Vec<Control>, Vec<Control>) = std::mem::take(controls)
                .into_iter()
                .partition(|c| c.start - late < loop_start);
            *notes = inside;
            *controls = later;
            if !before.is_empty() || !moves.is_empty() {
                place(&mut before, &mut moves, start);
                for note in &mut before {
                    note.length = note.length.min(loop_start - start - note.start).max(1.0 / 128.0);
                }
                let opts = ClipOpts {
                    kind: Some("midi".into()),
                    name: Some(format!("{name} lead-in")),
                    start,
                    length: Some(loop_start - start),
                    notes: before,
                    controls: moves,
                    ..ClipOpts::default()
                };
                self.clip_add(track, opts)?;
            }
        }
        played.retain(|(_, notes, controls)| !notes.is_empty() || !controls.is_empty());
        let Some((_, mut notes, mut controls)) = played.pop() else {
            return Ok(());
        };
        place(&mut notes, &mut controls, loop_start);
        let mut meta = Map::new();
        if !played.is_empty() {
            let mut list: Vec<Value> = Vec::new();
            for (i, (_, mut notes, mut controls)) in played.into_iter().enumerate() {
                place(&mut notes, &mut controls, loop_start);
                list.push(json!({
                    "name": format!("{name}.{}", i + 1),
                    "notes": sorted(notes), "controls": controls,
                }));
            }
            list.push(json!({ "name": format!("{name}.{}", list.len() + 1) }));
            meta.insert(
                "takes".into(),
                json!({ "active": list.len(), "list": list }),
            );
        }
        let opts = ClipOpts {
            kind: Some("midi".into()),
            name: Some(name.to_string()),
            start: loop_start,
            length: Some(loop_end - loop_start),
            notes,
            controls,
            meta,
            ..ClipOpts::default()
        };
        self.clip_add(track, opts).map(|_| ())
    }

    /// Seconds by which what is recorded is behind the song it was played
    /// to: how late the output is heard, how late the input arrives (for
    /// audio), and the offset set by hand for what the system does not report.
    pub(super) fn record_latency(&self, audio: bool) -> f64 {
        let info = &self.stream.info;
        let mut seconds = self.rec.offset / 1000.0;
        if info.backend != BackendChoice::Null {
            seconds += info.buffer_size as f64 / info.sample_rate as f64;
            if audio {
                seconds += self.handle.shared.input_latency() as f64;
            }
        }
        seconds.max(0.0)
    }

    /// Recordings made before the project had a file live in the user's data
    /// directory. Saving links or copies them into the `media` directory
    /// beside the project and points the clips there. The originals stay,
    /// because earlier undo steps still refer to them.
    pub(super) fn adopt_recordings(&mut self, path: &Path) -> Result<()> {
        let scratch = scratch_media_dir();
        let media = std::path::absolute(path)?.with_file_name("media");
        let mut moved: HashMap<PathBuf, PathBuf> = HashMap::new();
        for file in media::files(&self.project) {
            if !file.starts_with(&scratch) || moved.contains_key(&file) {
                continue;
            }
            std::fs::create_dir_all(&media)
                .with_context(|| format!("creating {}", media.display()))?;
            let stem = file.file_stem().unwrap_or_default().to_string_lossy();
            let target = unique_path(&media, &stem);
            std::fs::hard_link(&file, &target)
                .or_else(|_| std::fs::copy(&file, &target).map(|_| ()))
                .with_context(|| format!("copying {} to {}", file.display(), target.display()))?;
            moved.insert(file, target);
        }
        if moved.is_empty() {
            return Ok(());
        }
        for project in [&mut self.project, &mut self.checkpoint] {
            media::map_files(project, |file| moved.get(file).cloned());
        }
        self.dirty = true;
        Ok(())
    }
}
