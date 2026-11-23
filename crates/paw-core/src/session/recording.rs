//! The record of takes: start a take, collect what the engine captures,
//! close it, and make clips of it.
//!
//! A take goes through three states, and no state waits for the engine:
//!
//! 1. It records while [`Recorder::take`] holds it. The engine captures
//!    into its rings, and [`Session::flush`] collects the notes.
//! 2. A stop, a seek or a punch out closes it ([`Session::close_take`]):
//!    the kernel sends `SetTake(None)`, moves the take to
//!    [`Recorder::closing`] and returns at once.
//! 3. The engine lets go of the take at its next block and marks it
//!    closed, and each writer thread then finishes its file.
//!    [`Session::poll_takes`], called from `idle`, makes the clips of each
//!    take that is [done](Take::is_done), as one undo step, and emits
//!    `transport.recorded`.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::thread::JoinHandle;

use paw_engine::record::{self, AudioCapture, MidiCapture, TakeShared};
use paw_engine::{Msg, TrackSlot};
use paw_types::{EventKind, TempoMap};
use rtrb::{Consumer, RingBuffer};

use super::*;
use crate::events::{KernelEvent as E, Record, Recorded};

/// What records takes: the take under way, the takes that close, how many
/// takes were begun, and how much earlier recordings are moved.
#[derive(Default)]
pub(super) struct Recorder {
    /// The take that records now. A stop moves it to `closing`.
    pub take: Option<Take>,
    /// Takes that the engine was told to let go of, in the order they
    /// stopped. [`Session::poll_takes`] removes each one when it is done.
    pub closing: Vec<Take>,
    /// Takes begun so far: the next take's number is one more.
    pub takes: u32,
    /// Milliseconds to move recordings earlier by, on top of what the audio
    /// system reports: found by recording the metronome through a loop-back.
    pub offset: f64,
}

/// A take: the writer threads that fill its files, and the notes played
/// into armed tracks so far.
pub(super) struct Take {
    pub number: u32,
    pub shared: Arc<TakeShared>,
    pub audio: Vec<TakeFile>,
    midi: Consumer<MidiCapture>,
    /// Notes still held, by track and key.
    held: HashMap<(Id, u8), Held>,
    /// Finished notes by track and time round the loop, with `start` in
    /// project beats.
    notes: BTreeMap<(Id, u32), Vec<Note>>,
    /// Controller moves by track and time round, with `start` in project beats.
    controls: BTreeMap<(Id, u32), Vec<Control>>,
    /// The loop the take goes round, if the loop was on when it began.
    looped: Option<(f64, f64)>,
    /// The range it was punched into, in beats of the song, if punching was
    /// on when it began: only what was played there is captured.
    punch: Option<(f64, f64)>,
    /// The frames captured each time the loop jumped back, as the engine
    /// sends them, and as collected so far.
    wraps: Consumer<u64>,
    wrapped: Vec<u64>,
}

/// A note still held: the beat it began on, its velocity, which time round
/// the loop it began in, and its attribute.
struct Held {
    start: f64,
    velocity: u8,
    pass: u32,
    attr: Option<NoteAttr>,
}

/// The file of one armed track with an input, and the thread that writes it.
pub(super) struct TakeFile {
    pub track: Id,
    pub path: PathBuf,
    writer: JoinHandle<record::Written>,
}

/// One time round the loop of a take, or the whole of a take that never
/// went round: where it lies on the timeline and where its sound begins in
/// the take's files.
#[derive(Debug, PartialEq)]
pub(super) struct Pass {
    /// Its number among the take's passes, from 0.
    pub index: u32,
    pub start: f64,
    pub end: f64,
    /// Seconds into the files, before the latency is taken off.
    pub seconds: f64,
}

impl Take {
    /// Whether the take can become clips: the engine has let go of it, and
    /// each writer thread has finished its file.
    pub(super) fn is_done(&self) -> bool {
        self.shared.closed() && self.audio.iter().all(|file| file.writer.is_finished())
    }

    /// Take in what the engine captured since the last call: the times it
    /// went round the loop, and the notes and controller moves. `track_of`
    /// gives the track of an engine slot; a capture of a slot with no track
    /// is left out.
    fn collect(&mut self, track_of: impl Fn(TrackSlot) -> Option<Id>) {
        while let Ok(frames) = self.wraps.pop() {
            self.wrapped.push(frames);
        }
        while let Ok(capture) = self.midi.pop() {
            let Some(track) = track_of(capture.slot) else {
                continue;
            };
            let (beat, pass) = (capture.beat, capture.pass);
            match capture.kind {
                EventKind::NoteOn { key, vel, attr, .. } => {
                    // A key struck again ends the note it held.
                    self.end_note(track, key, beat, pass);
                    let velocity = (vel * 127.0).round().clamp(1.0, 127.0) as u8;
                    let held = Held { start: beat, velocity, pass, attr: NoteAttr::of(attr) };
                    self.held.insert((track, key), held);
                }
                EventKind::NoteOff { key, .. } => self.end_note(track, key, beat, pass),
                EventKind::Control { .. } | EventKind::NoteControl { .. } | EventKind::Program { .. } => {
                    if let Some(control) = Control::from_event(beat, capture.kind) {
                        self.controls.entry((track, pass)).or_default().push(control);
                    }
                }
                EventKind::AllNotesOff => {
                    let keys: Vec<u8> =
                        self.held.keys().filter(|(t, _)| *t == track).map(|(_, k)| *k).collect();
                    for key in keys {
                        self.end_note(track, key, beat, pass);
                    }
                }
            }
        }
    }

    /// End a held note at `at`, played in pass `pass`. A note still held
    /// when the loop jumps back ends at the loop's end.
    fn end_note(&mut self, track: Id, key: u8, at: f64, pass: u32) {
        if let Some(held) = self.held.remove(&(track, key)) {
            let at = match self.looped {
                Some((_, end)) if pass > held.pass => end,
                _ => at,
            };
            self.notes.entry((track, held.pass)).or_default().push(Note {
                start: held.start,
                length: (at - held.start).max(1.0 / 128.0),
                pitch: key,
                velocity: held.velocity,
                meta: Default::default(),
                id: 0,
                attr: held.attr,
            });
        }
    }

    /// End every note still held at `end`, where the engine let go of the
    /// take, in its last time round.
    fn end_held(&mut self, end: f64) {
        let rounds = self.wrapped.len() as u32;
        let held: Vec<(Id, u8)> = self.held.keys().copied().collect();
        for (track, key) in held {
            self.end_note(track, key, end, rounds);
        }
    }

    /// The passes of a take that captured from `start` and was let go of at
    /// `end`, and the range of the clip that holds them as takes when there
    /// are several: the loop, or the punch range.
    fn passes(&self, start: f64, end: f64, map: &TempoMap, rate: f64) -> (Vec<Pass>, Option<(f64, f64)>) {
        if let Some(punch) = self.punch {
            let passes = self.punched_passes(punch, start, end, map, rate);
            // Several times round the punch range are takes of one clip
            // over it, as several times round the loop are over the loop.
            let over = (passes.len() > 1).then(|| {
                let stop = self.looped.map_or(punch.1, |(_, loop_end)| punch.1.min(loop_end));
                (punch.0, stop)
            });
            return (passes, over);
        }
        let Some((loop_start, loop_end)) = self.looped.filter(|_| !self.wrapped.is_empty()) else {
            return (vec![Pass { index: 0, start, end, seconds: 0.0 }], None);
        };
        // The first time round runs from where the take began to the loop's
        // end; each later one from the loop's start, the last to the end.
        let mut passes = vec![Pass { index: 0, start, end: loop_end, seconds: 0.0 }];
        for (i, frames) in self.wrapped.iter().enumerate() {
            let last = i + 1 == self.wrapped.len();
            passes.push(Pass {
                index: i as u32 + 1,
                start: loop_start,
                end: if last { end.min(loop_end) } else { loop_end },
                seconds: *frames as f64 / rate,
            });
        }
        (passes, Some((loop_start, loop_end)))
    }

    /// The times a punched take went through its range (`from` to `to`):
    /// one pass for each time round the loop that captured anything, each
    /// with where its sound begins in the take's files. Capturing began at
    /// `start` and the take was let go of at `end`.
    fn punched_passes(&self, (from, to): (f64, f64), start: f64, end: f64, map: &TempoMap, rate: f64) -> Vec<Pass> {
        // Capturing stops at the loop's end if that comes first, and after
        // a jump back starts again where the loop does if that is later.
        let (stop, again) = match self.looped {
            Some((loop_start, loop_end)) => (to.min(loop_end), from.max(loop_start)),
            None => (to, from),
        };
        // A block cut at the punch in may start a hair after it.
        let first = if map.seconds_between(from, start).abs() * rate < 1.5 { from } else { start.max(from) };
        let mut out = Vec::new();
        let mut before = 0u64;
        for round in 0..=self.wrapped.len() {
            let last = round == self.wrapped.len();
            let seconds = before as f64 / rate;
            let captured = if last { end > from + 1e-9 } else { self.wrapped[round] > before };
            if !last {
                before = self.wrapped[round];
            }
            if !captured {
                continue;
            }
            let begin = if out.is_empty() { first } else { again };
            let finish = if last { end.min(stop) } else { stop };
            if finish - begin > 1e-9 {
                out.push(Pass { index: round as u32, start: begin, end: finish, seconds });
            }
        }
        out
    }
}

impl Session {
    /// Where new recordings go: `media` beside the project file, or the user's
    /// data directory for a project that has never been saved.
    pub(crate) fn media_dir(&self) -> PathBuf {
        match &self.path {
            Some(path) => std::path::absolute(path)
                .unwrap_or_else(|_| path.clone())
                .with_file_name("media"),
            None => scratch_media_dir(&self.dirs),
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
        let sample_rate = self.engine.handle.sample_rate as u32;
        let inputs = self.engine.stream.info.input_channels as usize;
        let dir = self.media_dir();
        let mut audio = Vec::new();
        let mut captures = Vec::new();
        for track in self.doc.project.tracks.iter().filter(|t| t.armed) {
            let Some(input) = track.input else {
                continue;
            };
            let (first, channels) = (usize::from(input.first), usize::from(input.count));
            if first + channels > inputs {
                self.doc.warnings.push(format!(
                    "{} records input {input} but the audio device has {inputs} input channels",
                    track.name
                ));
            }
            let started = std::fs::create_dir_all(&dir)
                .with_context(|| format!("creating {}", dir.display()))
                .and_then(|()| {
                    let path = unique_path(&dir, &format!("{}-take{number}", file_safe(&track.name)));
                    // Two seconds of room for the writer to fall behind by.
                    let (tx, rx) = RingBuffer::new(sample_rate as usize * channels * 2);
                    let writer = record::spawn_writer(&path, sample_rate, channels as u16, rx, shared.clone())?;
                    Ok((path, writer, tx))
                });
            match started {
                Ok((path, writer, ring)) => {
                    audio.push(TakeFile { track: track.id, path, writer });
                    captures.push(AudioCapture { first, channels, ring });
                }
                Err(err) => self.doc.warnings.push(format!("cannot record {}: {err:#}", track.name)),
            }
        }
        let channels: usize = captures.iter().map(|c| c.channels).sum();
        let (midi_tx, midi_rx) = RingBuffer::new(16384);
        let (wraps_tx, wraps_rx) = RingBuffer::new(4096);
        let t = &self.transport;
        let looped = (t.loop_enabled && t.loop_end > t.loop_start).then_some((t.loop_start, t.loop_end));
        let punch = (t.punch_enabled && t.punch_end > t.punch_start).then_some((t.punch_start, t.punch_end));
        let mut capture = record::Take::new(captures, midi_tx, shared.clone(), wraps_tx);
        if let Some((from, to)) = punch {
            // What is played at the punch out arrives as late as the
            // recording is behind the song: capture that much past it.
            let map = self.doc.project.tempo_map();
            capture.punch = Some((from, map.beat(map.seconds(to) + self.record_latency(true))));
            let at = self.position();
            let comes_round = looped.is_some_and(|(start, end)| at < end && start < to);
            if at >= to - 1e-9 && !comes_round {
                self.doc.warnings.push(format!(
                    "the playhead is past the punch out (bar {}): nothing will be recorded",
                    map.bar_of(to) + 1
                ));
            }
        }
        self.engine.handle.send(Msg::SetTake(Some(Box::new(capture))));
        // Where the files go and how fast they grow, for a warning when
        // the disk is nearly full; and the files, for a safety copy.
        let files: Vec<PathBuf> = audio.iter().map(|file| file.path.clone()).collect();
        self.rec.take = Some(Take {
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
        let record = Record {
            position: self.position(),
            take: number,
            free: crate::safe::free_space(&dir),
            dir,
            bytes_per_second: channels * 4 * sample_rate as usize,
            files,
        };
        self.doc.emit(E::TransportRecord(record));
    }

    /// Collect the notes the engine has captured for the take so far.
    pub(super) fn collect_take(&mut self) {
        let tracks = &self.engine.map.tracks;
        if let Some(take) = self.rec.take.as_mut() {
            take.collect(|slot| slot_track(tracks, slot));
        }
    }

    /// End the take being recorded, if one is: the engine lets go of it at
    /// its next block, and [`poll_takes`](Self::poll_takes) makes its clips
    /// after that. This returns at once.
    pub(super) fn close_take(&mut self) {
        let Some(take) = self.rec.take.take() else {
            return;
        };
        self.engine.handle.send(Msg::SetTake(None));
        self.rec.closing.push(take);
    }

    /// How many closing takes the engine has let go of, whose writer
    /// threads still write their files: work on the wall clock that ends
    /// on its own.
    pub(crate) fn takes_writing(&self) -> usize {
        self.rec.closing.iter().filter(|take| take.shared.closed() && !take.is_done()).count()
    }

    /// Make the clips of each closing take that is done, in the order the
    /// takes stopped. Called regularly, from [`idle`](Self::idle).
    pub(super) fn poll_takes(&mut self) {
        if !self.rec.closing.iter().any(Take::is_done) {
            return;
        }
        let (done, waiting): (Vec<Take>, Vec<Take>) =
            std::mem::take(&mut self.rec.closing).into_iter().partition(Take::is_done);
        self.rec.closing = waiting;
        for take in done {
            self.finish_take(take);
        }
    }

    /// The engine that held the closing takes is gone (it was restarted):
    /// nothing will let go of them but this. They end at `position`.
    pub(super) fn takes_let_go(&mut self, position: f64) {
        for take in &self.rec.closing {
            take.shared.close(position);
        }
    }

    /// Make the clips of every closing take now, for when the project they
    /// belong to goes away: another project opens, or the program ends.
    /// A take that the engine has not let go of yet ends here, and what the
    /// engine captures in its last block is lost. This waits for the writer
    /// threads to finish their files.
    pub(super) fn finish_takes_now(&mut self) {
        let position = self.position();
        self.takes_let_go(position);
        for take in std::mem::take(&mut self.rec.closing) {
            self.finish_take(take);
        }
    }

    /// Turn what a closed take captured into clips where it began, as one
    /// undo step, and say that it is done.
    fn finish_take(&mut self, mut take: Take) {
        let tracks = &self.engine.map.tracks;
        take.collect(|slot| slot_track(tracks, slot));
        let shared = take.shared.clone();
        let (start, end) = (shared.start(), shared.end());
        take.end_held(end);
        let rate = self.engine.handle.sample_rate;
        let map = self.doc.project.tempo_map().clone();
        // A take that never played captured nothing.
        let (passes, looped) = start.map_or((Vec::new(), None), |start| take.passes(start, end, &map, rate));

        self.checkpoint();
        let name = format!("take {}", take.number);
        for TakeFile { track, path, writer } in std::mem::take(&mut take.audio) {
            // A writer that stopped on an error has kept what it wrote, as a
            // whole WAV file: that becomes the clip like any other.
            let frames = match writer.join() {
                Ok(written) => {
                    if let Some(err) = written.error {
                        self.doc.warnings.push(format!(
                            "recording stopped: writing {} failed ({err}); the {:.1} s before that are kept",
                            path.display(),
                            written.frames as f64 / rate
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
            if let Err(err) = self.add_recorded_audio(track, &path, &name, &passes, looped, take.punch.is_some()) {
                self.doc.warnings
                    .push(format!("recorded {} but could not add it: {err:#}", path.display()));
            }
        }
        if let Some(start) = start.filter(|_| !passes.is_empty()) {
            // Notes are only late by what the player heard late.
            let late = start - map.beat(map.seconds(start) - self.record_latency(false));
            let tracks: BTreeSet<Id> =
                take.notes.keys().chain(take.controls.keys()).map(|(track, _)| *track).collect();
            for track in tracks {
                if let Err(err) = self.add_recorded_notes(track, &mut take, &name, &passes, looped, late) {
                    self.doc.warnings.push(format!("could not add the recorded notes: {err:#}"));
                }
            }
        }
        if shared.dropped() > 0 {
            self.doc.warnings.push(format!(
                "the disk fell behind: {} frames of {name} were lost",
                shared.dropped()
            ));
        }
        self.doc.emit(E::TransportRecorded(Recorded { take: take.number }));
        self.checkpoint();
    }

    /// The take being recorded, or else one that closes, as a safety copy
    /// keeps it: its files, which track each is for and where it starts, so
    /// that the take can be put back as clips if the program never gets to
    /// finish it.
    pub(super) fn take_in_progress(&self) -> Value {
        let Some(take) = self.rec.take.iter().chain(&self.rec.closing).next() else {
            return Value::Null;
        };
        let start = take.shared.start().unwrap_or_else(|| self.position());
        let files: Vec<Value> = take
            .audio
            .iter()
            .map(|file| json!({ "track": file.track, "file": file.path }))
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
            let (Some(track), Some(file)) = (entry["track"].as_u64(), entry["file"].as_str()) else {
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
                source_tempo: Some(self.doc.project.tempo_map().tempo(start)),
                ..ClipOpts::default()
            };
            if let Err(err) = self.clip_add(track as Id, opts) {
                self.doc.warnings
                    .push(format!("the take in {file} could not be put back: {err:#}"));
            }
        }
    }

    /// Turn a track's recorded file into clips. A take that never went
    /// round the loop is one clip where it began. One that did becomes a
    /// clip over the loop whose takes are the times round, the last of them
    /// the one that plays (`clip.meta.takes`, see `paw.takes`), and a clip
    /// before the loop for what was played on the way in.
    fn add_recorded_audio(
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
                source_tempo: Some(self.doc.project.tempo_map().tempo(pass.start)),
                ..ClipOpts::default()
            };
            return self.clip_add(track, opts).map(|_| ());
        };
        let map = self.doc.project.tempo_map().clone();
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
        let length = if complete { whole } else { last.end - loop_start };
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
                self.doc.warnings.push(format!(
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
    fn add_recorded_notes(
        &mut self,
        track: Id,
        take: &mut Take,
        name: &str,
        passes: &[Pass],
        looped: Option<(f64, f64)>,
        late: f64,
    ) -> Result<()> {
        let mut played: Vec<(u32, Vec<Note>, Vec<Control>)> = Vec::new();
        for pass in passes {
            let notes = take.notes.remove(&(track, pass.index)).unwrap_or_default();
            let controls = take.controls.remove(&(track, pass.index)).unwrap_or_default();
            if !notes.is_empty() || !controls.is_empty() {
                played.push((pass.index, notes, controls));
            }
        }
        // Count from where a clip starts, moved earlier by the latency. A
        // punched take keeps what falls inside its range, and notes held
        // across the punch out end there.
        let punch = take
            .punch
            .map(|_| looped.map_or(passes[0].end - passes[0].start, |(start, end)| end - start));
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
                kind: Some(ClipKind::Midi),
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
            let (mut before, inside): (Vec<Note>, Vec<Note>) =
                std::mem::take(notes).into_iter().partition(|n| n.start - late < loop_start);
            let (mut moves, later): (Vec<Control>, Vec<Control>) =
                std::mem::take(controls).into_iter().partition(|c| c.start - late < loop_start);
            *notes = inside;
            *controls = later;
            if !before.is_empty() || !moves.is_empty() {
                place(&mut before, &mut moves, start);
                for note in &mut before {
                    note.length = note.length.min(loop_start - start - note.start).max(1.0 / 128.0);
                }
                let opts = ClipOpts {
                    kind: Some(ClipKind::Midi),
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
            meta.insert("takes".into(), json!({ "active": list.len(), "list": list }));
        }
        let opts = ClipOpts {
            kind: Some(ClipKind::Midi),
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
        let info = &self.engine.stream.info;
        let mut seconds = self.rec.offset / 1000.0;
        if !info.backend.is_null() {
            seconds += info.buffer_size as f64 / info.sample_rate as f64;
            if audio {
                seconds += self.engine.handle.shared.input_latency() as f64;
            }
        }
        seconds.max(0.0)
    }

    /// Recordings made before the project had a file live in the user's data
    /// directory. Saving links or copies them into the `media` directory
    /// beside the project and points the clips there. The originals stay,
    /// because earlier undo steps still refer to them.
    pub(super) fn adopt_recordings(&mut self, path: &Path) -> Result<()> {
        let scratch = scratch_media_dir(&self.dirs);
        let media = std::path::absolute(path)?.with_file_name("media");
        let mut moved: HashMap<PathBuf, PathBuf> = HashMap::new();
        for file in media::files(&self.doc.project) {
            if !file.starts_with(&scratch) || moved.contains_key(&file) {
                continue;
            }
            std::fs::create_dir_all(&media).with_context(|| format!("creating {}", media.display()))?;
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
        for project in [&mut self.doc.project, &mut self.doc.undo.checkpoint] {
            media::map_files(project, |file| moved.get(file).cloned());
        }
        self.doc.dirty = true;
        Ok(())
    }
}

/// Where recordings go while the project has no file.
fn scratch_media_dir(dirs: &Dirs) -> PathBuf {
    dirs.paw_data().join("recordings")
}

/// The track that plays in engine slot `slot`.
fn slot_track(tracks: &HashMap<Id, TrackSlot>, slot: TrackSlot) -> Option<Id> {
    tracks.iter().find(|(_, s)| **s == slot).map(|(id, _)| *id)
}

#[cfg(test)]
mod tests {
    use paw_types::Attr;

    use super::*;

    const RATE: f64 = 48000.0;
    const TRACK: Id = 7;
    const SLOT: TrackSlot = TrackSlot(3);

    /// A take with no audio, and the producer ends that the engine fills.
    struct Captured {
        take: Take,
        midi: rtrb::Producer<MidiCapture>,
        wraps: rtrb::Producer<u64>,
    }

    fn take(looped: Option<(f64, f64)>, punch: Option<(f64, f64)>) -> Captured {
        let (midi, midi_rx) = RingBuffer::new(64);
        let (wraps, wraps_rx) = RingBuffer::new(16);
        let take = Take {
            number: 1,
            shared: Arc::new(TakeShared::default()),
            audio: Vec::new(),
            midi: midi_rx,
            held: HashMap::new(),
            notes: BTreeMap::new(),
            controls: BTreeMap::new(),
            looped,
            punch,
            wraps: wraps_rx,
            wrapped: Vec::new(),
        };
        Captured { take, midi, wraps }
    }

    impl Captured {
        fn play(&mut self, beat: f64, pass: u32, kind: EventKind) {
            self.midi.push(MidiCapture { slot: SLOT, beat, kind, pass }).unwrap();
        }

        fn press(&mut self, key: u8, beat: f64, pass: u32) {
            self.play(beat, pass, EventKind::NoteOn { key, vel: 0.5, ch: 0, attr: Attr::NONE });
        }

        fn release(&mut self, key: u8, beat: f64, pass: u32) {
            self.play(beat, pass, EventKind::NoteOff { key, ch: 0 });
        }

        fn collect(&mut self) {
            self.take.collect(|slot| (slot == SLOT).then_some(TRACK));
        }

        /// (pass, start, length) of each note collected, by pass.
        fn notes(&self) -> Vec<(u32, f64, f64)> {
            let mut out = Vec::new();
            for ((_, pass), notes) in &self.take.notes {
                out.extend(notes.iter().map(|n| (*pass, n.start, n.length)));
            }
            out
        }
    }

    fn pass(index: u32, start: f64, end: f64, seconds: f64) -> Pass {
        Pass { index, start, end, seconds }
    }

    #[test]
    fn a_take_is_done_only_when_the_engine_has_let_go_of_it() {
        let captured = take(None, None);
        assert!(!captured.take.is_done(), "a take the engine still holds");
        captured.take.shared.close(4.0);
        assert!(captured.take.is_done(), "a take the engine let go of, with no files");
    }

    #[test]
    fn a_take_that_never_went_round_is_one_pass() {
        let captured = take(Some((0.0, 8.0)), None);
        let (passes, over) = captured.take.passes(1.0, 5.0, &TempoMap::default(), RATE);
        assert_eq!(passes, [pass(0, 1.0, 5.0, 0.0)]);
        assert_eq!(over, None, "a loop it never went round holds no takes");
    }

    #[test]
    fn each_time_round_the_loop_is_a_pass_from_its_start() {
        let mut captured = take(Some((4.0, 8.0)), None);
        // At 120 beats a minute, 4 beats are 2 s: 96000 frames.
        captured.wraps.push(96000 + 48000).unwrap();
        captured.wraps.push(2 * 96000 + 48000).unwrap();
        captured.collect();
        let (passes, over) = captured.take.passes(2.0, 6.0, &TempoMap::default(), RATE);
        assert_eq!(passes, [pass(0, 2.0, 8.0, 0.0), pass(1, 4.0, 8.0, 3.0), pass(2, 4.0, 6.0, 5.0)]);
        assert_eq!(over, Some((4.0, 8.0)));
    }

    #[test]
    fn a_punched_take_keeps_only_the_rounds_that_captured() {
        let mut captured = take(Some((0.0, 8.0)), Some((2.0, 4.0)));
        // Round 0 captured 48000 frames, round 1 nothing, round 2 is the last.
        captured.wraps.push(48000).unwrap();
        captured.wraps.push(48000).unwrap();
        captured.collect();
        let (passes, over) = captured.take.passes(2.0, 3.0, &TempoMap::default(), RATE);
        assert_eq!(passes, [pass(0, 2.0, 4.0, 0.0), pass(2, 2.0, 3.0, 1.0)]);
        assert_eq!(over, Some((2.0, 4.0)), "two rounds are takes of one clip over the range");
    }

    #[test]
    fn notes_are_collected_by_the_round_they_began_in() {
        let mut captured = take(Some((0.0, 4.0)), None);
        captured.press(60, 1.0, 0);
        captured.release(60, 2.0, 0);
        // Held across the jump back: it ends at the loop's end.
        captured.press(62, 3.0, 0);
        captured.wraps.push(96000).unwrap();
        captured.release(62, 0.5, 1);
        captured.press(99, 0.25, 1);
        // An all-notes-off of a slot with no track ends none of them.
        captured.midi.push(MidiCapture { slot: TrackSlot(9), beat: 0.5, kind: EventKind::AllNotesOff, pass: 1 }).unwrap();
        captured.collect();
        captured.release(99, 1.25, 1);
        // Still held when the engine lets go of the take, at beat 1.5.
        captured.press(64, 1.0, 1);
        captured.collect();
        captured.take.end_held(1.5);
        assert_eq!(captured.notes(), [(0, 1.0, 1.0), (0, 3.0, 1.0), (1, 0.25, 1.0), (1, 1.0, 0.5)]);
    }
}
