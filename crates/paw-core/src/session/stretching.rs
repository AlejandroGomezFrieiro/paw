//! Stretched, warped, shifted and looped clips: the fields that set them,
//! warp markers, the versions of files made for them (`stretched.rs`) put
//! in place as they are started, and their waveforms.
//!
//! A clip's `stretch` is the ratio it plays its file at, whatever its
//! timebase: a clip in [`Timebase::Stretch`] has it set again whenever the
//! tempo changes (`Project::retime`), and its `source_tempo` says what its
//! sound's own tempo is, so that `stretch = source_tempo / tempo` at its
//! start (where the tempo changes inside it, it is bent along the tempo
//! instead: `warp.rs`). Until a version is started its clip is silent;
//! then it plays as far as it is made.

use std::collections::HashSet;
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use serde_json::{Value, json};

use super::{ClipKind, MAX_PEAKS, Session, de};
use crate::model::{Clip, ClipContent, Id, Project, Timebase, WarpMarker};
use crate::peaks;
use crate::stretch::{PITCH_RANGE, RATIO_RANGE};
use crate::stretched::{Key, SETTLE, Status};
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

/// The versions every stretched clip of `project` plays at `rate`.
fn wanted(project: &Project, rate: u32) -> HashSet<Key> {
    let map = project.tempo_map();
    project
        .all_tracks()
        .flat_map(|t| t.clips.iter().chain(&t.cues))
        .filter_map(|c| Key::of(c, rate, map))
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
            .project
            .clip(id)
            .with_context(|| format!("no clip {id}"))?
            .clone();
        let audio = matches!(clip.playable(), Some(ClipContent::Audio { .. }));
        if !audio && !key.starts_with("loop") {
            return Err(not_audio(&clip, &format!("have `{key}`")));
        }
        let tempo = self.project.tempo_map().tempo(clip.start);
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
        self.edit(|p| {
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

    /// Note on a clip's description that its version is still being made,
    /// and where its warp markers are, as beats of the song.
    pub(super) fn note_stretching(&self, clip: &Clip, view: &mut Value) {
        let map = self.project.tempo_map();
        let key = Key::of(clip, self.engine.handle.sample_rate as u32, map);
        if let Some(key) = key.as_ref()
            && self.audio.renders.status(Some(key)) == Status::Making
        {
            // Played as far as it is made: how far that is.
            view["stretching"] = json!(true);
            view["made"] = json!(self.audio.renders.made(key));
        }
        if warp::is_bent(clip, map) {
            view["bent"] = json!(true);
        }
        if clip.formants {
            view["formants"] = json!(true);
        }
        if !clip.warp.is_empty() {
            let markers: Vec<Value> = clip
                .warp
                .iter()
                .map(|m| {
                    json!({
                        "source": m.source,
                        "target": m.target,
                        "beat": warp::beat_of(clip, map, m.source),
                    })
                })
                .collect();
            view["warp"] = json!(markers);
        }
    }

    /// Put a warp marker on audio clip `id` at `beat`, pinning the moment of
    /// its file that plays there; nothing moves. Returns its index among
    /// the clip's markers (one already there is found again).
    pub fn warp_add(&mut self, id: Id, beat: f64) -> Result<usize> {
        let clip = self.audio_clip_ref(id)?;
        if !beat.is_finite() || beat < clip.start - 1e-9 || beat > clip.start + clip.length + 1e-9 {
            bail!("a warp marker goes inside its clip");
        }
        let map = self.project.tempo_map().clone();
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
        self.edit(|p| {
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
    pub fn warp_move(&mut self, id: Id, index: usize, beat: f64) -> Result<usize> {
        let clip = self.audio_clip_ref(id)?;
        let Some(&marker) = clip.warp.get(index) else {
            bail!("clip {id} has no warp marker {}", index + 1);
        };
        if !beat.is_finite() {
            bail!("a beat is a number");
        }
        let map = self.project.tempo_map().clone();
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
        self.edit(|p| {
            p.clip_mut(id).expect("the clip was found").warp = markers;
            Ok(())
        })?;
        Ok(index)
    }

    /// Take warp marker `index` off clip `id`: the sound between its
    /// neighbours is stretched evenly again.
    pub fn warp_remove(&mut self, id: Id, index: usize) -> Result<()> {
        let clip = self.audio_clip_ref(id)?;
        if index >= clip.warp.len() {
            bail!("clip {id} has no warp marker {}", index + 1);
        }
        self.edit(|p| {
            p.clip_mut(id).expect("the clip was found").warp.remove(index);
            Ok(())
        })
    }

    fn audio_clip_ref(&self, id: Id) -> Result<Arc<Clip>> {
        let clip = self
            .project
            .clip(id)
            .with_context(|| format!("no clip {id}"))?;
        if !matches!(clip.playable(), Some(ClipContent::Audio { .. })) {
            return Err(not_audio(clip, "have warp markers"));
        }
        Ok(clip.clone())
    }

    /// Start versions that have waited long enough, drop those no clip
    /// wants any more, and build again the tracks whose clips play one
    /// that has been made. Called regularly, from [`idle`](Self::idle).
    pub(super) fn poll_stretches(&mut self) {
        let renders = &self.audio.renders;
        if !renders.busy() && renders.finished.is_empty() {
            return;
        }
        let rate = self.engine.handle.sample_rate as u32;
        let store = self.audio.store.clone();
        self.audio
            .renders
            .poll(&wanted(&self.project, rate), SETTLE, store.as_ref());
        self.warnings.append(&mut self.audio.renders.failures);
        let finished: HashSet<Key> = self.audio.renders.finished.drain(..).collect();
        if finished.is_empty() {
            return;
        }
        // The engine builds a clip again when its copy differs from the
        // one it last saw: those clips are made to differ.
        let map = self.project.tempo_map().clone();
        let touched =
            |c: &Arc<Clip>| Key::of(c, rate, &map).is_some_and(|k| finished.contains(&k));
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
            if track.cues.iter().any(|c| touched(c)) {
                for clip in Arc::make_mut(track).cues.iter_mut() {
                    if touched(clip) {
                        *clip = Arc::new((**clip).clone());
                    }
                }
            }
        }
        self.dirty = true;
        self.flush();
    }

    /// Wait up to `limit` for every version `project`'s clips play at
    /// `rate`: for rendering, which needs them all.
    pub(super) fn await_stretches(
        &mut self,
        project: &Project,
        rate: u32,
        limit: Duration,
    ) -> Result<()> {
        let keys = wanted(project, rate);
        if keys.is_empty() {
            return Ok(());
        }
        for key in &keys {
            self.audio.stretched(key, &mut self.warnings);
        }
        let mut all = keys.clone();
        all.extend(wanted(&self.project, self.engine.handle.sample_rate as u32));
        let store = self.audio.store.clone();
        let deadline = Instant::now() + limit;
        while self.audio.renders.making(&keys) {
            if Instant::now() > deadline {
                bail!("the stretched clips are still being made");
            }
            self.audio
                .renders
                .poll(&all, Duration::ZERO, store.as_ref());
            std::thread::sleep(Duration::from_millis(5));
        }
        self.warnings.append(&mut self.audio.renders.failures);
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
        let map = self.project.tempo_map().clone();
        let seconds = map.seconds_between(clip.start, clip.start + clip.length);
        let key = Key::of(clip, self.engine.handle.sample_rate as u32, &map);
        let warp = warp::of(clip, &map).unwrap_or_else(|| warp::Warp::even(1.0));
        let audio = &mut self.audio;
        // `seconds` of what plays from `from`, in seconds of what plays.
        let mut part = |from: f64, seconds: f64, n: usize| -> Result<Vec<[f32; 3]>> {
            if let Some(ready) = key.as_ref().and_then(|k| audio.renders.ready(k)) {
                let summary = ready.summary();
                let rate = ready.data.sample_rate as f64;
                return Ok(peaks::peaks(
                    &ready.data,
                    &summary,
                    from * rate,
                    (from + seconds) * rate,
                    n,
                ));
            }
            let start = warp.inverse(from).max(0.0);
            let end = warp.inverse(from + seconds).max(start);
            Ok(audio.peaks(file, start, end - start, n)?.to_vec())
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
