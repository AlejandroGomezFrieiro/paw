//! Stretched and pitch-shifted sound: the stretch bake and its preview.
//!
//! A clip with a stretch, warp markers, a pitch shift or an edit list plays
//! a version of its file made for it (`stretch.rs`) at the engine's rate.
//! Sync asks the bake scheduler (`bake::scheduler`) for it by its [`Key`].
//! Until the bake starts, the clip plays a rough [`preview`]: its file in
//! short grains laid where the warp puts them, so the rhythm is heard. Once
//! the bake starts, the clip plays the version as far as it is made: it is
//! made from its start, into room laid out for all of it, many times faster
//! than it plays. Each swap is a new build of the clip's regions on the
//! kernel thread, sent to the engine as every edit is.
//!
//! In the bake cache, a version is known by its [`BakeJob`]: the hash of
//! its file's bytes and what is made of it, so that it is found again in
//! later runs and by other projects. Large versions are kept there.

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use anyhow::{Context, Result};
use paw_engine::{AudioData, AudioRegion, DiskStore, Sink, TempoMap};
use serde_json::json;

use crate::bake::scheduler::{Bake, Made, Scheduler, Task};
use crate::bake::{BakeJob, Digest, EntryKey, Hasher, Input, Output, Store, Stream, Write};
use crate::model::{Clip, ClipContent};
use crate::stretch::{self, Mode, Params};
use crate::warp::{self, Warp};

pub use crate::bake::scheduler::SETTLE;

/// The bakes of stretched clips, by what they are made of.
pub type Renders = Scheduler<Key>;

/// What the session keeps beside the bakes: the keys a running export
/// waits for, the last `bake.progress` told, and the cache's tidying.
#[derive(Default)]
pub struct Upkeep {
    /// The keys of a running render, pinned in the cache while it runs.
    pub exporting: std::collections::HashSet<Key>,
    /// When `bake.progress` was last sent, and what it said.
    pub reported: Option<(std::time::Instant, crate::bake::scheduler::Busy)>,
    /// A tidy of the cache running on a thread of its own.
    pub tidying: Option<std::sync::mpsc::Receiver<crate::bake::Tidied>>,
    /// A bake ended while the cache was being tidied: tidy again after.
    pub tidy_again: bool,
    /// The pinned bakes alone were over the cache's limit, and that was told.
    pub told_over: bool,
}

/// Who makes a stretch: a new version of the stretch is a new entry.
const TOOL: &str = "paw.stretch/1";

/// The name of the sound in its cache entry (`DiskStore` files).
const SOUND: &str = "sound";

/// What a version is made of: cheap to work out in each sync, and the
/// identity of a bake while paw runs. Its cache entry also names the
/// file's bytes ([`Key::job`]).
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct Key {
    pub file: PathBuf,
    /// The engine's rate, which the version is at.
    pub rate: u32,
    /// The warp ([`Warp::bits`]) and the shift in semitones, as bits.
    warp: Vec<u64>,
    pitch: u64,
    pub mode: Mode,
    pub formants: bool,
    /// The clip's edit list (`edits.rs`), as text; empty for none.
    edits: String,
    /// Not stretched or shifted: the edits alone.
    plain: bool,
}

impl Key {
    /// What `clip` plays at `rate` with the song's tempo `map`, if it is an
    /// audio clip stretched, warped or shifted, or with an edit list.
    pub fn of(clip: &Clip, rate: u32, map: &TempoMap) -> Option<Self> {
        let Some(ClipContent::Audio { file, edits, .. }) = clip.playable() else {
            return None;
        };
        let warp = warp::of(clip, map);
        if warp.is_none() && edits.is_empty() {
            return None;
        }
        let plain = warp.is_none();
        let warp = warp.unwrap_or_else(|| Warp::even(1.0));
        Some(Self {
            file: file.clone(),
            rate,
            warp: warp.bits(),
            pitch: if plain { 0 } else { clip.pitch.to_bits() },
            mode: clip.stretch_mode,
            formants: !plain && clip.formants && clip.pitch != 0.0,
            edits: if edits.is_empty() { String::new() } else { crate::edits::text(edits) },
            plain,
        })
    }

    pub fn warp(&self) -> Warp {
        Warp::from_bits(&self.warp)
    }

    pub fn params(&self) -> Params {
        Params {
            warp: self.warp(),
            semitones: f64::from_bits(self.pitch),
            mode: self.mode,
            formants: self.formants,
        }
    }

    /// The bake of this version of the file whose bytes hash to `source`.
    pub fn job(&self, source: Digest) -> BakeJob {
        let edits: serde_json::Value = serde_json::from_str(&self.edits).unwrap_or_default();
        BakeJob {
            op: if self.plain { "edit".into() } else { "stretch".into() },
            version: 1,
            // Floats as their bits: exact, and never NaN in the JSON.
            params: json!({
                "warp": self.warp,
                "pitch": self.pitch,
                "mode": self.mode.name(),
                "formants": self.formants,
                "edits": edits,
            }),
            inputs: vec![Input::File { source }],
            output: Output { stream: Stream::Sound, rate: Some(self.rate), format: None },
        }
    }
}

/// The bake of `key` from `source` (the file at the engine's rate), kept in
/// `bakes` when it is larger than `disk`'s limit.
pub fn bake(key: Key, source: Arc<AudioData>, bakes: Option<Store>, disk: Option<DiskStore>) -> Arc<dyn Bake> {
    crate::bake::native::Native::of(crate::bake::native::Op::Stretch(Stretch { key, source, bakes, disk }))
}

/// A stretch to make: the native op of `bake::native`.
pub struct Stretch {
    key: Key,
    source: Arc<AudioData>,
    bakes: Option<Store>,
    disk: Option<DiskStore>,
}

impl Stretch {
    pub fn what(&self) -> String {
        format!("stretching {}", self.key.file.display())
    }

    /// Find the version in the cache, or make it: its sound plays from its
    /// start as it is made ([`Task::partial`]).
    pub fn run(&self, task: &Task) -> Result<Made> {
        let key = &self.key;
        let cache = self.bakes.as_ref().zip(self.disk.as_ref());
        let entry = match cache {
            Some(_) => {
                let source = Hasher::file(&key.file).with_context(|| format!("reading {}", key.file.display()))?;
                let job = key.job(source);
                let entry = EntryKey::new(&job, TOOL);
                task.entry(entry.id());
                Some((job, entry))
            }
            None => None,
        };
        let mut writer = None;
        if let (Some((store, disk)), Some((job, entry))) = (cache, &entry) {
            let found = match store.open(entry) {
                Some(found) => Some(found),
                None => match store.writer(job, entry) {
                    Ok(Write::Make(made)) => {
                        writer = Some(made);
                        None
                    }
                    Ok(Write::Done(found)) => Some(found),
                    // Made by another paw now, or a cache that cannot be
                    // written: made here, in memory.
                    Ok(Write::Busy) | Err(_) => None,
                },
            };
            let kept = found.and_then(|found| sound_store(found.file(""), disk).open(SOUND));
            if let Some(data) = kept {
                return Ok(Made::Sound(Arc::new(data)));
            }
        }
        let params = key.params();
        let source = &*self.source;
        let frames = stretch::length(source.frames(), source.sample_rate, &params.warp);
        let store = writer.as_ref().zip(self.disk.as_ref()).map(|(w, disk)| sound_store(w.file(""), disk));
        let sink = Sink::growing(frames, source.sample_rate, store.as_ref().map(|s| (s, SOUND.to_string())))?;
        task.partial(Arc::new(sink.playing().expect("a growing sink")));
        let edits: Vec<crate::edits::AudioEdit> = serde_json::from_str(&key.edits).unwrap_or_default();
        // The edits first, then the stretch, if any.
        let edited;
        let sound = if edits.is_empty() {
            source
        } else {
            edited = crate::edits::apply(source, &edits);
            &edited
        };
        let stop = task.stop_flag();
        let data = if key.plain { copy(sound, sink, stop)? } else { stretch::render(sound, &params, sink, stop)? };
        // Large: its files are in the entry, which goes in place whole. Small,
        // it stays in memory and the entry is dropped.
        if let Some(writer) = writer
            && writer.file(&format!("{SOUND}.meta")).is_file()
        {
            // A cache that cannot be written only costs time next run.
            let _ = writer.commit();
        }
        Ok(Made::Sound(Arc::new(data)))
    }
}

/// The sound files of an entry's folder `dir`, written as `disk` writes.
fn sound_store(dir: PathBuf, disk: &DiskStore) -> DiskStore {
    DiskStore { dir, limit: disk.limit }
}

/// A sound into a sink as it is, a part at a time, until `stop` is set.
fn copy(data: &AudioData, mut sink: Sink, stop: &AtomicBool) -> Result<AudioData> {
    const PART: usize = 1 << 15;
    let frames = data.frames();
    let mut at = 0;
    while at < frames {
        if stop.load(Ordering::Relaxed) {
            anyhow::bail!("stopped");
        }
        let to = (at + PART).min(frames);
        sink.push(&data.channels[0][at..to], Some(&data.channels[1][at..to]))?;
        at = to;
    }
    sink.finish(data.sample_rate)
}

/// The shortest grain of a preview, in seconds.
const GRAIN: f64 = 0.1;
/// The most grains a clip's preview has, so that a long clip costs the
/// engine as little as a short one.
const GRAINS: f64 = 256.0;

/// The regions of a rough preview of a clip whose version is not made yet:
/// its file `source` in short grains, each played as it is (its pitch, its
/// speed) from where the warp puts its start, so that the rhythm is heard.
/// `offset` is in seconds of the version, as the clip's regions take it.
pub fn preview(
    clip: &Clip,
    source: Arc<AudioData>,
    (offset, gain): (f64, f32),
    warp: &Warp,
    tempo: &TempoMap,
    out: &mut Vec<AudioRegion>,
) {
    let seconds = tempo.seconds_between(clip.start, clip.start + clip.length);
    // The clip's time in seconds, from `a` to `b`, plays the version from `at`.
    let spans: Vec<(f64, f64, f64)> = match clip.repeat() {
        None => vec![(0.0, seconds, offset)],
        Some((from, beats)) => {
            let period = tempo.seconds_between(clip.start, clip.start + beats);
            if period <= 1e-9 {
                return;
            }
            let lead = from * period / beats;
            crate::sync::repeats(lead, period, seconds)
                .filter_map(|(a, b)| {
                    let (ra, rb) = (a.max(0.0), b.min(seconds));
                    (rb - ra > 1e-9).then_some((ra, rb, offset + lead + (ra - a)))
                })
                .collect()
        }
    };
    let grain = (seconds / GRAINS).max(GRAIN);
    let t0 = tempo.seconds(clip.start);
    let whole = source.whole_seconds();
    let first = out.len();
    for (a, b, at) in spans {
        let mut t = a;
        while t < b - 1e-9 {
            let e = (t + grain).min(b);
            let from = warp.inverse(at + (t - a)).max(0.0);
            if from < whole {
                out.push(AudioRegion {
                    start: tempo.beat(t0 + t),
                    end: tempo.beat(t0 + e),
                    data: source.clone(),
                    offset: from,
                    gain,
                    fade_in: 0.0,
                    fade_out: 0.0,
                    declick_in: from > 1e-6,
                    declick_out: true,
                    hold: Default::default(),
                });
            }
            t = e;
        }
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
