//! Stretched, warped, shifted and looped clips: the fields that set them,
//! warp markers, the versions of files made for them (`stretched.rs`) put
//! in place as they are started, and their waveforms.
//!
//! A clip's `stretch` is the ratio it plays its file at, whatever its
//! timebase: a clip in [`Timebase::Stretch`] has it set again whenever the
//! tempo changes (`Project::retime`), and its `source_tempo` says what its
//! sound's own tempo is, so that `stretch = source_tempo / tempo` at its
//! start (where the tempo changes inside it, it is bent along the tempo
//! instead: `warp.rs`). Until a version's bake starts its clip plays a
//! rough preview; then it plays the version as far as it is made. The
//! bakes are wanted in the order they are heard: what the playhead is
//! about to play first, a render's next, the rest after.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use serde_json::Value;

use super::{ClipKind, MAX_PEAKS, Session, de};
use crate::model::{Clip, ClipContent, Id, Project, Timebase, WarpMarker};
use crate::peaks;
use crate::stretch::{PITCH_RANGE, RATIO_RANGE};
use crate::bake::scheduler::{Busy, Priority, Status};
use crate::events::{BakeProgress, KernelEvent as E};
use crate::stretched::{Key, SETTLE, ViewRange};
use crate::media::Sources;
use crate::warp;

/// The clip fields set here rather than in `Session::clip_set`.
const FIELDS: [&str; 10] = [
    "stretch",
    "pitch",
    "stretch_mode",
    "source_tempo",
    "timebase",
    "loop",
    "loop_length",
    "loop_start",
    "warp",
    "formants",
];

/// The refusal of an audio-only field (`what` is `have ...`) on a clip that
/// has no audio sound: for a custom clip, it says what the clip has.
pub(super) fn not_audio(clip: &Clip, what: &str) -> anyhow::Error {
    match &clip.content {
        ClipContent::Custom(custom) => anyhow::anyhow!(
            "clip {} is a clip of the kind `{}` with no audio sound: only clips that play audio {what}",
            clip.id,
            custom.kind
        ),
        _ => anyhow::anyhow!("only audio clips {what}"),
    }
}

/// Check how a new clip of `kind` is to play.
pub(super) fn check_playing(
    kind: ClipKind,
    stretch: f64,
    pitch: f64,
    source_tempo: Option<f64>,
) -> Result<()> {
    if kind != ClipKind::Audio && (stretch != 1.0 || pitch != 0.0) {
        bail!("only audio clips are stretched or shifted");
    }
    check_ratio(stretch)?;
    check_pitch(pitch)?;
    if let Some(bpm) = source_tempo {
        check_tempo(bpm)?;
    }
    Ok(())
}

fn check_ratio(ratio: f64) -> Result<f64> {
    let (lo, hi) = RATIO_RANGE;
    if !(lo..=hi).contains(&ratio) {
        bail!("a clip is stretched to between {lo} and {hi} times its length, not {ratio}");
    }
    Ok(ratio)
}

fn check_pitch(semitones: f64) -> Result<f64> {
    if !semitones.is_finite() || semitones.abs() > PITCH_RANGE {
        bail!("a clip is shifted by at most {PITCH_RANGE} semitones either way, not {semitones}");
    }
    Ok(semitones)
}

fn check_tempo(bpm: f64) -> Result<f64> {
    if !(1.0..=999.0).contains(&bpm) {
        bail!("a tempo is between 1 and 999, not {bpm}");
    }
    Ok(bpm)
}

/// Check an audio clip's warp markers: in order of their moments of the
/// file, and of where they play them.
pub(super) fn check_warp(kind: ClipKind, warp: &[WarpMarker]) -> Result<()> {
    if kind != ClipKind::Audio && !warp.is_empty() {
        bail!("only audio clips have warp markers");
    }
    for m in warp {
        if !m.source.is_finite() || !m.target.is_finite() || m.source < 0.0 {
            bail!("a warp marker is a moment of the file from 0 on, and where it plays");
        }
    }
    if warp
        .windows(2)
        .any(|w| w[1].source <= w[0].source || w[1].target <= w[0].target)
    {
        bail!("warp markers follow each other in the file and where they play it");
    }
    Ok(())
}

/// The seconds after the playhead whose bakes are made first.
const AHEAD: f64 = 10.0;

/// How often `bake.progress` is sent at most.
const REPORT: Duration = Duration::from_millis(250);

/// The undo states whose bakes stay in the cache, as the versions do in
/// memory (`bake::scheduler`).
const UNDO_PINS: usize = 8;

/// The versions every stretched clip of `project` plays at `rate`.
fn wanted(project: &Project, rate: u32, sources: &Sources) -> HashSet<Key> {
    let map = project.tempo_map();
    project
        .all_tracks()
        .flat_map(|t| t.clips.iter().chain(&t.cues))
        .filter_map(|c| Key::of(c, rate, map, sources))
        .collect()
}

impl Session {
    /// Set one of the [`FIELDS`] of a clip; `None` for any other field.
    pub(super) fn clip_set_playing(
        &mut self,
        id: Id,
        key: &str,
        value: &Value,
    ) -> Option<Result<()>> {
        FIELDS
            .contains(&key)
            .then(|| self.set_playing(id, key, value.clone()))
    }

    fn set_playing(&mut self, id: Id, key: &str, value: Value) -> Result<()> {
        let clip = self
            .doc.project
            .clip(id)
            .with_context(|| format!("no clip {id}"))?
            .clone();
        let audio = matches!(clip.playable(), Some(ClipContent::Audio { .. }));
        if !audio && !key.starts_with("loop") {
            return Err(not_audio(&clip, &format!("have `{key}`")));
        }
        let tempo = self.doc.project.tempo_map().tempo(clip.start);
        // What a loop turned on repeats unless it was given a length: a
        // MIDI clip what it holds now, an audio clip its file from where
        // it starts playing it.
        let natural = match (key, &value) {
            ("loop", Value::Bool(true)) if clip.loop_length.is_none() => Some(if audio {
                self.clip_source_length(id)?
            } else {
                clip.length
            }),
            _ => None,
        };
        let number = |value: &Value| -> Result<Option<f64>> {
            match value {
                Value::Null => Ok(None),
                value => {
                    let n: f64 = de(key, value.clone())?;
                    if !n.is_finite() {
                        bail!("`{key}` is a number, not {n}");
                    }
                    Ok(Some(n))
                }
            }
        };
        self.doc.edit(|p| {
            let c = p.clip_mut(id).expect("the clip was found");
            match key {
                "stretch" => {
                    c.stretch = check_ratio(number(&value)?.unwrap_or(1.0))?;
                    // Its sound's own tempo is as much faster as it is slowed.
                    if c.timebase == Some(Timebase::Stretch) {
                        c.source_tempo = Some(tempo * c.stretch);
                    }
                }
                "pitch" => c.pitch = check_pitch(number(&value)?.unwrap_or(0.0))?,
                "stretch_mode" => c.stretch_mode = de(key, value)?,
                "source_tempo" => match number(&value)? {
                    None => c.source_tempo = None,
                    Some(bpm) => {
                        let bpm = check_tempo(bpm)?;
                        if c.timebase == Some(Timebase::Stretch) {
                            c.stretch = check_ratio(bpm / tempo).context(
                                "the clip would be stretched too far to follow the tempo",
                            )?;
                        }
                        c.source_tempo = Some(bpm);
                    }
                },
                "timebase" => {
                    let timebase: Timebase = de(key, value)?;
                    if timebase == Timebase::Stretch && c.source_tempo.is_none() {
                        c.source_tempo = Some(tempo * c.stretch);
                    }
                    c.timebase = Some(timebase);
                }
                "loop" => {
                    let on: bool = de(key, value)?;
                    if on && c.loop_length.is_none() {
                        let Some(beats) = natural.filter(|l| *l > 1e-9) else {
                            bail!("the clip has nothing to repeat");
                        };
                        c.loop_length = Some(beats);
                    }
                    c.looped = on;
                }
                "loop_length" => match number(&value)? {
                    Some(beats) if beats <= 0.0 => bail!("a loop is longer than 0 beats"),
                    beats => c.loop_length = beats,
                },
                "loop_start" => c.loop_start = number(&value)?.unwrap_or(0.0),
                "warp" => {
                    let markers: Vec<WarpMarker> = match value {
                        // An empty Lua table is an empty object.
                        Value::Null => Vec::new(),
                        Value::Object(map) if map.is_empty() => Vec::new(),
                        value => de(key, value)?,
                    };
                    check_warp(ClipKind::Audio, &markers)?;
                    c.warp = markers;
                }
                "formants" => c.formants = de(key, value)?,
                _ => unreachable!("one of FIELDS"),
            }
            Ok(())
        })
    }

    /// Note on a clip's description that its version is still being made
    /// (and plays a rough `preview` until its bake starts), and where its
    /// warp markers are, as beats of the song.
    pub(super) fn note_stretching(&self, clip: &Clip, view: &mut super::ClipView<'_>) {
        let map = self.doc.project.tempo_map();
        let key = Key::of(clip, self.engine.handle.sample_rate as u32, map, &self.sources);
        if let Some(key) = key.as_ref() {
            // A file with no hash in the bakes yet waits for it, as a bake
            // waits to start: also when the hash came this turn, and the
            // next poll of the bakes asks for the bake.
            let status = match self.audio.renders.status(key) {
                Status::Unknown if self.audio.upkeep.unhashed.contains(&key.file) => Status::Waiting,
                status => status,
            };
            if matches!(status, Status::Waiting | Status::Running) {
                // Played as far as it is made: how far that is.
                view.stretching = Some(true);
                view.made = Some(self.audio.renders.progress(key));
            }
            if status == Status::Waiting {
                view.preview = Some(true);
            }
        }
        if warp::is_bent(clip, map) {
            view.bent = Some(true);
        }
        if clip.formants {
            view.formants = Some(true);
        }
        if !clip.warp.is_empty() {
            view.warp = Some(
                clip.warp
                    .iter()
                    .map(|m| super::WarpView {
                        source: m.source,
                        target: m.target,
                        beat: warp::beat_of(clip, map, m.source),
                    })
                    .collect(),
            );
        }
    }

    /// Put a warp marker on audio clip `id` at `beat`, pinning the moment of
    /// its file that plays there; nothing moves. Returns its index among
    /// the clip's markers (one already there is found again).
    pub(crate) fn warp_add(&mut self, id: Id, beat: f64) -> Result<usize> {
        let clip = self.audio_clip_ref(id)?;
        if !beat.is_finite() || beat < clip.start - 1e-9 || beat > clip.start + clip.length + 1e-9 {
            bail!("a warp marker goes inside its clip");
        }
        let map = self.doc.project.tempo_map().clone();
        let source = warp::source_at(&clip, &map, beat);
        if source < 0.0 {
            bail!("the clip plays nothing of its file there");
        }
        if let Some(i) = clip.warp.iter().position(|m| (m.source - source).abs() < 1e-6) {
            return Ok(i);
        }
        let target = warp::Warp::new(
            clip.warp.iter().map(|m| (m.source, m.target)).collect(),
            1.0,
            1.0,
        )
        .forward(source);
        let index = clip.warp.partition_point(|m| m.source < source);
        self.doc.edit(|p| {
            let c = p.clip_mut(id).expect("the clip was found");
            c.warp.insert(index, WarpMarker { source, target });
            Ok(())
        })?;
        Ok(index)
    }

    /// Move warp marker `index` of clip `id` to play at `beat`, stretching
    /// the sound between it and its neighbours and nowhere else: the clip's
    /// start and end are pinned with markers of their own when no marker is
    /// between them and it. It goes no further than a stretch of a quarter
    /// to four times on either side allows. Returns its index, which
    /// pinning may have changed.
    pub(crate) fn warp_move(&mut self, id: Id, index: usize, beat: f64) -> Result<usize> {
        let clip = self.audio_clip_ref(id)?;
        let Some(&marker) = clip.warp.get(index) else {
            bail!("clip {id} has no warp marker {}", index + 1);
        };
        if !beat.is_finite() {
            bail!("a beat is a number");
        }
        let map = self.doc.project.tempo_map().clone();
        let Some(&ClipContent::Audio { offset, .. }) = clip.playable() else {
            unreachable!("an audio clip")
        };
        let end = warp::source_at(&clip, &map, clip.start + clip.length);
        let mut markers = clip.warp.clone();
        let unstretched = warp::Warp::new(markers.iter().map(|m| (m.source, m.target)).collect(), 1.0, 1.0);
        let pin = |markers: &mut Vec<WarpMarker>, source: f64| {
            let at = markers.partition_point(|m| m.source < source);
            markers.insert(
                at,
                WarpMarker {
                    source,
                    target: unstretched.forward(source),
                },
            );
        };
        if offset < marker.source - 1e-6 && !markers.iter().any(|m| m.source >= offset - 1e-9 && m.source < marker.source) {
            pin(&mut markers, offset);
        }
        if end > marker.source + 1e-6 && !markers.iter().any(|m| m.source > marker.source && m.source <= end + 1e-9) {
            pin(&mut markers, end);
        }
        let index = markers
            .iter()
            .position(|m| m.source == marker.source)
            .expect("the marker moved is there");
        let pinned = Clip {
            warp: markers.clone(),
            ..(*clip).clone()
        };
        let (lo, hi) = warp::target_range(&markers, index, clip.stretch);
        let target = warp::target_for(&pinned, &map, beat).clamp(lo, hi);
        markers[index].target = target;
        self.doc.edit(|p| {
            p.clip_mut(id).expect("the clip was found").warp = markers;
            Ok(())
        })?;
        Ok(index)
    }

    /// Take warp marker `index` off clip `id`: the sound between its
    /// neighbours is stretched evenly again.
    pub(crate) fn warp_remove(&mut self, id: Id, index: usize) -> Result<()> {
        let clip = self.audio_clip_ref(id)?;
        if index >= clip.warp.len() {
            bail!("clip {id} has no warp marker {}", index + 1);
        }
        self.doc.edit(|p| {
            p.clip_mut(id).expect("the clip was found").warp.remove(index);
            Ok(())
        })
    }

    fn audio_clip_ref(&self, id: Id) -> Result<Arc<Clip>> {
        let clip = self
            .doc.project
            .clip(id)
            .with_context(|| format!("no clip {id}"))?;
        if !matches!(clip.playable(), Some(ClipContent::Audio { .. })) {
            return Err(not_audio(clip, "have warp markers"));
        }
        Ok(clip.clone())
    }

    /// What the windows on screen show now: the bakes of the clips there
    /// start before the rest (`bake_wants`), at the next poll.
    pub(crate) fn view_ranges_set(&mut self, ranges: Vec<ViewRange>) {
        self.audio.upkeep.views = ranges;
    }

    /// What the windows on screen show, as they told it last.
    pub(crate) fn view_ranges(&self) -> &[ViewRange] {
        &self.audio.upkeep.views
    }

    /// What the bakes of stretched clips are wanted for: those the
    /// playhead (or, stopped, the cursor) reaches in the next seconds
    /// first, then those a window shows, then those a running render
    /// waits for, then the rest.
    fn bake_wants(&self) -> HashMap<Key, Priority> {
        let rate = self.engine.handle.sample_rate as u32;
        let map = self.doc.project.tempo_map();
        let from = self.position();
        let to = map.beat(map.seconds(from) + AHEAD);
        let mut wants: HashMap<Key, Priority> = HashMap::new();
        let mut want = |key: Key, priority: Priority| {
            let was = wants.entry(key).or_default();
            *was = (*was).max(priority);
        };
        let views = &self.audio.upkeep.views;
        for track in self.doc.project.all_tracks() {
            for clip in &track.clips {
                if let Some(key) = Key::of(clip, rate, map, &self.sources) {
                    let end = clip.start + clip.length;
                    let priority = if clip.start < to && end > from {
                        Priority::Playing
                    } else if views.iter().any(|view| view.shows(track.id, clip.start, end)) {
                        Priority::Visible
                    } else {
                        Priority::Background
                    };
                    want(key, priority);
                }
            }
            // Clips off the timeline play when they are launched: any time.
            for key in track.cues.iter().filter_map(|c| Key::of(c, rate, map, &self.sources)) {
                want(key, Priority::Background);
            }
        }
        for key in &self.audio.upkeep.exporting {
            want(key.clone(), Priority::Export);
        }
        wants
    }

    /// The cache entries kept whatever the cache's size: those of the
    /// project as it is, of the last undo states, and of a running render.
    pub(crate) fn bake_pins(&self) -> HashSet<String> {
        let rate = self.engine.handle.sample_rate as u32;
        let mut keys = wanted(&self.doc.project, rate, &self.sources);
        let mut states: Vec<_> = self.doc.undo.history.states().collect();
        states.sort_by_key(|s| std::cmp::Reverse(s.id));
        for state in states.into_iter().take(UNDO_PINS) {
            keys.extend(wanted(&state.snapshot, rate, &self.sources));
        }
        keys.extend(self.audio.upkeep.exporting.iter().cloned());
        self.audio.renders.entries(keys.iter()).cloned().collect()
    }

    /// Tidy the bake cache on a thread of its own, with its pins.
    fn tidy_bakes(&mut self) {
        let Some(store) = self.audio.bakes.clone() else {
            return;
        };
        if self.audio.upkeep.tidying.is_some() {
            self.audio.upkeep.tidy_again = true;
            return;
        }
        let pins = self.bake_pins();
        let (tell, told) = std::sync::mpsc::channel();
        let thread = std::thread::Builder::new().name("tidy".into()).spawn(move || {
            let _ = tell.send(store.tidy(&pins));
        });
        if thread.is_ok() {
            self.audio.upkeep.tidying = Some(told);
        }
    }

    /// Take in a tidy that ended: when the pinned bakes alone are over
    /// the cache's limit, say so, once.
    fn poll_tidy(&mut self) {
        let Some(told) = &self.audio.upkeep.tidying else {
            return;
        };
        let tidied = match told.try_recv() {
            Ok(tidied) => tidied,
            Err(std::sync::mpsc::TryRecvError::Empty) => return,
            Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                self.audio.upkeep.tidying = None;
                return;
            }
        };
        self.audio.upkeep.tidying = None;
        let limit = self.audio.bakes.as_ref().map_or(u64::MAX, |s| s.limit);
        if tidied.over(limit) && !self.audio.upkeep.told_over {
            self.audio.upkeep.told_over = true;
            let gb = |bytes: u64| bytes as f64 / 1_073_741_824.0;
            self.doc.warnings.push(format!(
                "the bakes this project needs now take {:.1} GB, more than the cache's limit of {:.1} GB: \
                 none of them is removed. Raise paw.opt.media_cache to make room",
                gb(tidied.pinned),
                gb(limit)
            ));
        }
        if std::mem::take(&mut self.audio.upkeep.tidy_again) {
            self.tidy_bakes();
        }
    }

    /// Send `bake.progress` when it changed: at most 4 times a second of
    /// schedule time, and at once when the bakes start or all end.
    fn report_bakes(&mut self) {
        let busy = self.audio.renders.summary();
        let idle = |b: &Busy| b.running + b.waiting == 0;
        let upkeep = &mut self.audio.upkeep;
        let due = match &upkeep.reported {
            None => !idle(&busy),
            Some((at, was)) => *was != busy && (idle(was) != idle(&busy) || self.now - *at >= REPORT),
        };
        if !due {
            return;
        }
        upkeep.reported = Some((self.now, busy));
        let Busy { running, waiting, fraction } = busy;
        self.doc.emit(E::BakeProgress(BakeProgress { running, waiting, fraction }));
    }

    /// Take in the bakes that ended or started, start those that have
    /// waited long enough, drop those no clip wants any more, and build
    /// again the tracks whose clips play one that changed. Called
    /// regularly, from [`idle`](Self::idle).
    pub(super) fn poll_bakes(&mut self) {
        self.poll_tidy();
        if self.render_job.is_none() {
            self.audio.upkeep.exporting.clear();
        }
        let hashed: HashSet<std::path::PathBuf> = self
            .audio
            .upkeep
            .unhashed
            .extract_if(|file| self.sources.record(file).is_some())
            .collect();
        let renders = &self.audio.renders;
        if !renders.busy() && renders.finished.is_empty() && hashed.is_empty() {
            return;
        }
        let rate = self.engine.handle.sample_rate as u32;
        let wants = self.bake_wants();
        self.audio.renders.poll(&wants, SETTLE, self.now);
        self.doc.warnings.append(&mut self.audio.renders.failures);
        self.report_bakes();
        let finished: HashSet<Key> = self.audio.renders.finished.drain(..).collect();
        if finished.is_empty() && hashed.is_empty() {
            return;
        }
        if finished.iter().any(|k| self.audio.renders.status(k) == Status::Ready) {
            self.tidy_bakes();
        }
        // The engine builds a clip again when its copy differs from the
        // one it last saw: those clips are made to differ. Built again on
        // this thread and sent as any edit is, the clip's new regions take
        // the place of its old ones (the preview's, say) at a block boundary.
        let map = self.doc.project.tempo_map().clone();
        let sources = &self.sources;
        let touched = |c: &Arc<Clip>| {
            Key::of(c, rate, &map, sources).is_some_and(|k| finished.contains(&k) || hashed.contains(&k.file))
        };
        let synced = &mut self.synced;
        for track in std::iter::once(&mut synced.master).chain(synced.tracks.iter_mut()) {
            if track.clips.iter().any(touched) {
                for clip in Arc::make_mut(track).clips.iter_mut() {
                    if touched(clip) {
                        *clip = Arc::new((**clip).clone());
                    }
                }
            }
            // So do clips off the timeline (`session/cues.rs`).
            if track.cues.iter().any(&touched) {
                for clip in Arc::make_mut(track).cues.iter_mut() {
                    if touched(clip) {
                        *clip = Arc::new((**clip).clone());
                    }
                }
            }
        }
        self.doc.dirty = true;
        self.flush();
    }

    /// Wait up to `limit` for every version `project`'s clips play at
    /// `rate`: for rendering, which needs them all. They are made before
    /// the rest, and pinned in the cache while the render runs.
    pub(super) fn await_stretches(
        &mut self,
        project: &Project,
        rate: u32,
        limit: Duration,
    ) -> Result<()> {
        // A render cannot wait for the background hashing: its files are
        // hashed now, so that each stretched clip has a key.
        let files: Vec<std::path::PathBuf> = project
            .all_tracks()
            .flat_map(|t| t.clips.iter().chain(&t.cues))
            .filter_map(|c| match c.playable() {
                Some(ClipContent::Audio { file, .. }) => Some(file.clone()),
                _ => None,
            })
            .collect();
        let changed = self.sources.complete(files.iter().map(std::path::PathBuf::as_path));
        if !changed.is_empty() {
            self.tell_changed(changed);
        }
        let keys = wanted(project, rate, &self.sources);
        if keys.is_empty() {
            return Ok(());
        }
        for key in &keys {
            self.audio.stretched(key, self.now, &mut self.doc.warnings);
        }
        self.audio.upkeep.exporting.extend(keys.iter().cloned());
        // A wait for other threads and processes: a budget of wall time.
        #[expect(clippy::disallowed_methods, reason = "a budget of wall time for the bakes of an export")]
        let deadline = Instant::now() + limit;
        while self.audio.renders.making(keys.iter()) {
            #[expect(clippy::disallowed_methods, reason = "a budget of wall time for the bakes of an export")]
            let late = Instant::now() > deadline;
            if late {
                bail!("the stretched clips are still being made");
            }
            let wants = self.bake_wants();
            self.audio.renders.poll(&wants, Duration::ZERO, self.now);
            std::thread::sleep(Duration::from_millis(5));
        }
        self.doc.warnings.append(&mut self.audio.renders.failures);
        Ok(())
    }

    /// An audio clip's waveform as [`clip_peaks`](Self::clip_peaks) gives
    /// it, before its gain: of the version it plays once that is made (of
    /// its file squeezed or spread in time until then), and repeated as a
    /// looped clip repeats.
    pub(super) fn playing_peaks(&mut self, clip: &Clip, n: usize) -> Result<Vec<[f32; 3]>> {
        let Some(ClipContent::Audio { file, offset, .. }) = clip.playable() else {
            return Err(not_audio(clip, "have a waveform"));
        };
        let map = self.doc.project.tempo_map().clone();
        let seconds = map.seconds_between(clip.start, clip.start + clip.length);
        let key = Key::of(clip, self.engine.handle.sample_rate as u32, &map, &self.sources);
        let warp = warp::of(clip, &map).unwrap_or_else(|| warp::Warp::even(1.0));
        let source = self.sources.record(file).map(|r| r.hash);
        let audio = &mut self.audio;
        // `seconds` of what plays from `from`, in seconds of what plays.
        let mut part = |from: f64, seconds: f64, n: usize| -> Result<Vec<[f32; 3]>> {
            if let Some(ready) = key.as_ref().and_then(|k| audio.renders.ready(k))
                && let Some(summary) = ready.summary()
                && let Some(data) = ready.sound()
            {
                let rate = data.sample_rate as f64;
                return Ok(peaks::peaks(
                    data,
                    &summary,
                    from * rate,
                    (from + seconds) * rate,
                    n,
                ));
            }
            let start = warp.inverse(from).max(0.0);
            let end = warp.inverse(from + seconds).max(start);
            Ok(audio.peaks(file, source, start, end - start, n)?.to_vec())
        };
        let begin = warp.forward(*offset);

        let Some((from, beats)) = clip.repeat() else {
            return part(begin, seconds, n);
        };
        let period = map.seconds_between(clip.start, clip.start + beats);
        if period <= 1e-9 || seconds <= 0.0 || n == 0 {
            return Ok(Vec::new());
        }
        let lead = from * period / beats;
        let per = ((n as f64 * period / seconds).ceil() as usize).clamp(1, MAX_PEAKS);
        let one = part(begin + lead, period, per)?;
        if one.is_empty() {
            return Ok(Vec::new());
        }
        Ok((0..n)
            .map(|i| {
                let at = (i as f64 + 0.5) * seconds / n as f64;
                let phase = (at - lead).rem_euclid(period) / period;
                one[((phase * one.len() as f64) as usize).min(one.len() - 1)]
            })
            .collect())
    }
}
