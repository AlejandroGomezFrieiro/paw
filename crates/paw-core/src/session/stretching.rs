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
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]
#![expect(clippy::float_cmp, reason = "debt: pay down")]

use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};

use super::document::{ClipChange, check_pitch, check_ratio, check_tempo, check_warp};
use super::{Change as _, ClipKind, MAX_PEAKS, Session};
use crate::model::{Clip, ClipContent, Id, Project, Timebase, WarpMarker};
use crate::peaks;
use crate::bake::scheduler::{Busy, Priority, Status};
use crate::clock::Agenda;
use crate::doorbell::Woken;
use crate::events::{BakeProgress, KernelEvent as E};
use crate::stretched::{Key, SETTLE, ViewRange};
use crate::media::Sources;
use crate::warp;

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
        .all_parts()
        .flat_map(|t| t.clips.iter().chain(&t.cues))
        .filter_map(|c| Key::of(c, rate, map, sources))
        .collect()
}

impl Session {
    /// Make a change of how clip `id` plays ([`ClipChange::is_playing`]).
    pub(super) fn set_playing(&mut self, id: Id, change: ClipChange) -> Result<()> {
        let clip = self
            .doc.project
            .clip(id)
            .with_context(|| format!("no clip {id}"))?
            .clone();
        let audio = matches!(clip.playable(), Some(ClipContent::Audio { .. }));
        let key = change.key();
        if !audio && !key.starts_with("loop") {
            return Err(not_audio(&clip, &format!("have `{key}`")));
        }
        let tempo = self.doc.project.tempo_map().tempo(clip.start);
        // What a loop turned on repeats unless it was given a length: a
        // MIDI clip what it holds now, an audio clip its file from where
        // it starts playing it.
        let natural = match change {
            ClipChange::Loop(true) if clip.loop_length.is_none() => Some(if audio {
                self.clip_source_length(id)?
            } else {
                clip.length
            }),
            _ => None,
        };
        let finite = |value: Option<f64>| -> Result<Option<f64>> {
            match value {
                Some(n) if !n.is_finite() => bail!("`{key}` is a number, not {n}"),
                value => Ok(value),
            }
        };
        self.doc.edit(|p| {
            let c = p.clip_in(id)?;
            match change {
                ClipChange::Stretch(ratio) => {
                    c.stretch = crate::model::Factor(check_ratio(finite(ratio)?.unwrap_or(1.0))?);
                    // Its sound's own tempo is as much faster as it is slowed.
                    if c.timebase == Some(Timebase::Stretch) {
                        c.source_tempo = Some(tempo * c.stretch.0);
                    }
                }
                ClipChange::Pitch(semitones) => c.pitch = check_pitch(finite(semitones)?.unwrap_or(0.0))?,
                ClipChange::StretchMode(mode) => c.stretch_mode = mode,
                ClipChange::SourceTempo(bpm) => match finite(bpm)? {
                    None => c.source_tempo = None,
                    Some(bpm) => {
                        let bpm = check_tempo(bpm)?;
                        if c.timebase == Some(Timebase::Stretch) {
                            c.stretch = crate::model::Factor(check_ratio(bpm / tempo).context(
                                "the clip would be stretched too far to follow the tempo",
                            )?);
                        }
                        c.source_tempo = Some(bpm);
                    }
                },
                ClipChange::Timebase(timebase) => {
                    if timebase == Timebase::Stretch && c.source_tempo.is_none() {
                        c.source_tempo = Some(tempo * c.stretch.0);
                    }
                    c.timebase = Some(timebase);
                }
                ClipChange::Loop(on) => {
                    if on && c.loop_length.is_none() {
                        let Some(beats) = natural.filter(|l| *l > 1e-9) else {
                            bail!("the clip has nothing to repeat");
                        };
                        c.loop_length = Some(beats);
                    }
                    c.looped = on;
                }
                ClipChange::LoopLength(beats) => match finite(beats)? {
                    Some(beats) if beats <= 0.0 => bail!("a loop is longer than 0 beats"),
                    beats => c.loop_length = beats,
                },
                ClipChange::LoopStart(beats) => c.loop_start = finite(beats)?.unwrap_or(0.0),
                ClipChange::Warp(markers) => {
                    check_warp(ClipKind::Audio, &markers)?;
                    c.warp = markers;
                }
                ClipChange::Formants(on) => c.formants = on,
                other => unreachable!("`{}` is not a change of how a clip plays", other.key()),
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
            let c = p.clip_in(id)?;
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
        let (lo, hi) = warp::target_range(&markers, index, clip.stretch.0);
        let target = warp::target_for(&pinned, &map, beat).clamp(lo, hi);
        markers[index].target = target;
        self.doc.edit(|p| {
            p.clip_in(id)?.warp = markers;
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
            p.clip_in(id)?.warp.remove(index);
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
        for part in self.doc.project.all_parts() {
            for clip in &part.clips {
                if let Some(key) = Key::of(clip, rate, map, &self.sources) {
                    let end = clip.start + clip.length;
                    let priority = if clip.start < to && end > from {
                        Priority::Playing
                    } else if views.iter().any(|view| view.shows(part.id, clip.start, end)) {
                        Priority::Visible
                    } else {
                        Priority::Background
                    };
                    want(key, priority);
                }
            }
            // Clips off the timeline play when they are launched: any time.
            for key in part.cues.iter().filter_map(|c| Key::of(c, rate, map, &self.sources)) {
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
        let bell = self.bell.bell(Woken::BAKES);
        let thread = std::thread::Builder::new().name("tidy".into()).spawn(move || {
            let _ = tell.send(store.tidy(&pins));
            bell.ring();
        });
        if thread.is_ok() {
            self.audio.upkeep.tidying = Some(told);
        }
    }

    /// Take in a tidy that ended: when the pinned bakes alone are over
    /// the cache's limit, say so, once. Gives true when one ended.
    fn poll_tidy(&mut self) -> bool {
        let Some(told) = &self.audio.upkeep.tidying else {
            return false;
        };
        let tidied = match told.try_recv() {
            Ok(tidied) => tidied,
            Err(std::sync::mpsc::TryRecvError::Empty) => return false,
            Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                self.audio.upkeep.tidying = None;
                return true;
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
        true
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
    /// again the parts whose clips play one that changed. Called
    /// regularly, from [`idle`](Self::idle). Gives true when a bake or a
    /// tidy ended, or a bake has sound to play: the news that they ring
    /// for.
    pub(super) fn poll_bakes(&mut self) -> bool {
        let tidied = self.poll_tidy();
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
            return tidied;
        }
        let rate = self.engine.handle.sample_rate as u32;
        let wants = self.bake_wants();
        let news = self.audio.renders.poll(&wants, SETTLE, self.now) || tidied;
        self.doc.warnings.append(&mut self.audio.renders.failures);
        self.report_bakes();
        let finished: HashSet<Key> = self.audio.renders.finished.drain(..).collect();
        if finished.is_empty() && hashed.is_empty() {
            return news;
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
        for part in std::iter::once(&mut synced.master).chain(synced.parts.iter_mut()) {
            if part.clips.iter().any(touched) {
                for clip in Arc::make_mut(part).clips.iter_mut() {
                    if touched(clip) {
                        *clip = Arc::new((**clip).clone());
                    }
                }
            }
            // So do clips off the timeline (`session/cues.rs`).
            if part.cues.iter().any(&touched) {
                for clip in Arc::make_mut(part).cues.iter_mut() {
                    if touched(clip) {
                        *clip = Arc::new((**clip).clone());
                    }
                }
            }
        }
        self.doc.dirty = true;
        self.flush();
        news
    }

    /// What the bakes leave for the loop: those on threads and in helpers
    /// are in flight, with a tidy of the cache; those that wait for their
    /// settle are due then.
    pub(super) fn bakes_agenda(&self) -> Agenda {
        let running = self.audio.renders.summary().running + usize::from(self.audio.upkeep.tidying.is_some());
        Agenda {
            in_flight: u32::try_from(running).unwrap_or(u32::MAX),
            next_due: self.audio.renders.next_due(SETTLE),
            ..Agenda::default()
        }
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
            .all_parts()
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
