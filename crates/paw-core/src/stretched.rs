//! Stretched and pitch-shifted sound, made on worker threads and kept.
//!
//! A clip with a stretch, warp markers or a pitch shift plays a version of
//! its file made for it (`stretch.rs`), at the engine's rate. Sync asks
//! for it when it builds the clip; the first time it is not there yet, so
//! it is queued, and the clip is silent until it is started, when the
//! session builds the clip's track again (`Session::poll_stretches`). From
//! then on the clip plays the version as far as it has been made: it is
//! made from its start, into room laid out for all of it, many times
//! faster than it plays. A version is known by its file and what was made
//! of it (its warp, shift, mode and formants, and the rate), kept in
//! memory, and in the disk store when it is large, so that it is made once
//! for every clip that plays it and found again in later runs.
//!
//! A version asked for is made only once it has been wanted for a moment,
//! so that a ratio typed or dragged through several values makes only the
//! last, and one that stops being wanted (the clip changed again, or went)
//! is dropped, its worker told to stop.

use std::collections::{HashMap, HashSet, VecDeque};
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use anyhow::Result;
use paw_engine::{AudioData, DiskStore, Sink, TempoMap};

use crate::model::{Clip, ClipContent};
use crate::peaks::Summary;
use crate::stretch::{self, Mode, Params};
use crate::warp::{self, Warp};

/// How long a version must be wanted before it is made.
pub const SETTLE: Duration = Duration::from_millis(150);

/// How many are made at the same time.
const AT_ONCE: usize = 2;

/// Versions no clip plays any more that are kept anyway, for undo.
const SPARE: usize = 8;

/// What a version is made of.
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
        let ClipContent::Audio { file, edits, .. } = &clip.content else {
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

    /// The name it is kept under in the disk store.
    fn store_name(&self) -> Option<String> {
        // FNV-1a over the warp and the edits.
        let mut hash = 0xcbf2_9ce4_8422_2325u64;
        for word in &self.warp {
            for b in word.to_le_bytes() {
                hash = (hash ^ b as u64).wrapping_mul(0x100_0000_01b3);
            }
        }
        let mut edits = 0xcbf2_9ce4_8422_2325u64;
        for b in self.edits.bytes() {
            edits = (edits ^ b as u64).wrapping_mul(0x100_0000_01b3);
        }
        let what = format!(
            "x{}-{hash:016x}-{:016x}-{}{}{}",
            self.rate,
            self.pitch,
            if self.plain { "plain" } else { self.mode.name() },
            if self.formants { "-formants" } else { "" },
            if self.edits.is_empty() { String::new() } else { format!("-edits{edits:016x}") }
        );
        paw_engine::store_name(&self.file, &what)
    }
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

/// A version made, with its waveform overview once one was asked for.
pub struct Ready {
    pub data: Arc<AudioData>,
    summary: Option<Arc<Summary>>,
}

impl Ready {
    pub fn summary(&mut self) -> Arc<Summary> {
        self.summary
            .get_or_insert_with(|| Arc::new(Summary::new(&self.data)))
            .clone()
    }
}

enum Job {
    /// Wanted since then, made from this.
    Waiting(Instant, Arc<AudioData>),
    /// Being made, into the version as far as it is made.
    Running(
        JoinHandle<Result<AudioData>>,
        Arc<AtomicBool>,
        Arc<AudioData>,
    ),
    Done(Ready),
    /// It could not be made; why was told once, as a warning.
    Failed,
}

/// Where a clip's version is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Status {
    /// Not stretched at all (it plays its file), or not asked for yet.
    Plain,
    Ready,
    /// Waiting or being made.
    Making,
    Failed,
}

#[derive(Default)]
pub struct Renders {
    jobs: HashMap<Key, Job>,
    /// Versions made, oldest first, for dropping the oldest unwanted ones.
    made: VecDeque<Key>,
    /// Why versions could not be made, not yet told.
    pub failures: Vec<String>,
    /// Versions started, made or failed since the session last looked,
    /// whose clips are to be built again.
    pub finished: Vec<Key>,
}

impl Renders {
    /// The version `key` names, if it is made or being made (as far as it
    /// is); otherwise it is queued, to be made from `source`, which is
    /// asked for only then.
    pub fn get(
        &mut self,
        key: &Key,
        store: Option<&DiskStore>,
        source: impl FnOnce() -> Option<Arc<AudioData>>,
    ) -> Option<Arc<AudioData>> {
        match self.jobs.get(key) {
            Some(Job::Done(ready)) => return Some(ready.data.clone()),
            Some(Job::Running(_, _, made)) => return Some(made.clone()),
            Some(_) => return None,
            None => {}
        }
        if let Some(store) = store
            && let Some(name) = key.store_name()
            && let Some(data) = store.open(&name)
        {
            let data = Arc::new(data);
            self.done(key.clone(), data.clone());
            return Some(data);
        }
        let source = source()?;
        self.jobs
            .insert(key.clone(), Job::Waiting(Instant::now(), source));
        None
    }

    fn done(&mut self, key: Key, data: Arc<AudioData>) {
        self.jobs.insert(
            key.clone(),
            Job::Done(Ready {
                data,
                summary: None,
            }),
        );
        self.made.push_back(key);
    }

    /// Whether `key` has been asked for (and not dropped since).
    pub fn known(&self, key: &Key) -> bool {
        self.jobs.contains_key(key)
    }

    /// The version made for `key`, with its overview for drawing.
    pub fn ready(&mut self, key: &Key) -> Option<&mut Ready> {
        match self.jobs.get_mut(key) {
            Some(Job::Done(ready)) => Some(ready),
            _ => None,
        }
    }

    pub fn status(&self, key: Option<&Key>) -> Status {
        match key.and_then(|k| self.jobs.get(k)) {
            None => Status::Plain,
            Some(Job::Done(_)) => Status::Ready,
            Some(Job::Failed) => Status::Failed,
            Some(_) => Status::Making,
        }
    }

    /// How much of the version `key` names is made, from 0 to 1.
    pub fn made(&self, key: &Key) -> f64 {
        match self.jobs.get(key) {
            Some(Job::Done(_)) => 1.0,
            Some(Job::Running(_, _, made)) => made.seconds() / made.whole_seconds().max(1e-9),
            _ => 0.0,
        }
    }

    /// Whether anything is waiting or being made.
    pub fn busy(&self) -> bool {
        self.jobs
            .values()
            .any(|job| matches!(job, Job::Waiting(..) | Job::Running(..)))
    }

    /// Whether any of `keys` is still waiting or being made.
    pub fn making(&self, keys: &HashSet<Key>) -> bool {
        keys.iter()
            .any(|k| matches!(self.jobs.get(k), Some(Job::Waiting(..) | Job::Running(..))))
    }

    /// Drop what is not in `wanted`, start what has waited `settle`, and
    /// take in what has been made, noting it in `finished`. `store` keeps
    /// what is large.
    pub fn poll(&mut self, wanted: &HashSet<Key>, settle: Duration, store: Option<&DiskStore>) {
        self.drop_unwanted(wanted);
        self.take_ended(wanted);
        self.start_due(settle, store);
        self.drop_spare(wanted);
    }

    /// Drop the waiting versions no clip wants, and tell the running ones
    /// to stop.
    fn drop_unwanted(&mut self, wanted: &HashSet<Key>) {
        self.jobs.retain(|key, job| match job {
            Job::Waiting(..) => wanted.contains(key),
            Job::Running(_, cancel, _) => {
                if !wanted.contains(key) {
                    // It stops at its next look; its result is dropped then.
                    cancel.store(true, Ordering::Relaxed);
                }
                true
            }
            Job::Done(_) | Job::Failed => true,
        });
    }

    /// Take in the versions whose thread has ended, noting each in
    /// `finished`.
    fn take_ended(&mut self, wanted: &HashSet<Key>) {
        let ended: Vec<Key> = self
            .jobs
            .iter()
            .filter(|(_, job)| matches!(job, Job::Running(thread, ..) if thread.is_finished()))
            .map(|(key, _)| key.clone())
            .collect();
        for key in ended {
            let Some(Job::Running(thread, cancel, _)) = self.jobs.remove(&key) else {
                continue;
            };
            let result = thread
                .join()
                .unwrap_or_else(|_| Err(anyhow::anyhow!("the stretch stopped unexpectedly")));
            if cancel.load(Ordering::Relaxed) {
                // Wanted again since it was told to stop: its clips are
                // built again, which asks for it anew.
                if wanted.contains(&key) {
                    self.finished.push(key);
                }
                continue;
            }
            match result {
                Ok(data) => {
                    self.finished.push(key.clone());
                    self.jobs.insert(
                        key.clone(),
                        Job::Done(Ready {
                            data: Arc::new(data),
                            summary: None,
                        }),
                    );
                    self.made.push_back(key);
                }
                Err(err) => {
                    let why = format!("stretching {}: {err:#}", key.file.display());
                    self.failures.push(why);
                    self.jobs.insert(key.clone(), Job::Failed);
                    self.finished.push(key);
                }
            }
        }
    }

    /// Start the versions that have waited `settle`, the oldest first, as
    /// many as `AT_ONCE` allows.
    fn start_due(&mut self, settle: Duration, store: Option<&DiskStore>) {
        let running = self
            .jobs
            .values()
            .filter(|job| matches!(job, Job::Running(..)))
            .count();
        let now = Instant::now();
        let mut due: Vec<(Instant, Key)> = self
            .jobs
            .iter()
            .filter_map(|(key, job)| match job {
                Job::Waiting(since, _) if now.duration_since(*since) >= settle => {
                    Some((*since, key.clone()))
                }
                _ => None,
            })
            .collect();
        due.sort_by_key(|(since, _)| *since);
        for (_, key) in due.into_iter().take(AT_ONCE.saturating_sub(running)) {
            let Some(Job::Waiting(_, source)) = self.jobs.remove(&key) else {
                continue;
            };
            let cancel = Arc::new(AtomicBool::new(false));
            let kept = store.and_then(|s| Some((s, key.store_name()?)));
            let params = key.params();
            let frames = stretch::length(source.frames(), source.sample_rate, &params.warp);
            let stop = cancel.clone();
            let edits: Vec<crate::edits::AudioEdit> = serde_json::from_str(&key.edits).unwrap_or_default();
            let plain = key.plain;
            let thread = Sink::growing(frames, source.sample_rate, kept).and_then(|sink| {
                let made = Arc::new(sink.playing().expect("a growing sink"));
                let thread = std::thread::Builder::new()
                    .name("stretch".into())
                    .spawn(move || {
                        // The edits first, then the stretch, if any.
                        let edited;
                        let sound = if edits.is_empty() {
                            &*source
                        } else {
                            edited = crate::edits::apply(&source, &edits);
                            &edited
                        };
                        if plain {
                            copy(sound, sink, &stop)
                        } else {
                            stretch::render(sound, &params, sink, &stop)
                        }
                    })?;
                Ok((thread, made))
            });
            match thread {
                Ok((thread, made)) => {
                    // Its clips play it from now, as far as it is made.
                    self.finished.push(key.clone());
                    self.jobs.insert(key, Job::Running(thread, cancel, made));
                }
                Err(err) => {
                    let why = format!("starting a stretch: {err}");
                    self.failures.push(why);
                    self.jobs.insert(key, Job::Failed);
                }
            }
        }
    }

    /// Versions no clip plays any more, past a few kept for undo.
    fn drop_spare(&mut self, wanted: &HashSet<Key>) {
        let unwanted: Vec<Key> = self
            .made
            .iter()
            .filter(|k| !wanted.contains(k))
            .cloned()
            .collect();
        if unwanted.len() > SPARE {
            for key in &unwanted[..unwanted.len() - SPARE] {
                self.jobs.remove(key);
            }
            let jobs = &self.jobs;
            self.made.retain(|k| jobs.contains_key(k));
        }
    }

    /// True when nothing is made or being made.
    pub fn is_empty(&self) -> bool {
        self.jobs.is_empty() && self.made.is_empty()
    }

    /// Forget what was made from files not in `keep`, and everything when
    /// `keep` is `None`.
    pub fn retain(&mut self, keep: Option<&HashSet<PathBuf>>) {
        // One being made stops at its next look, and is dropped once it has.
        for (key, job) in &self.jobs {
            if let Job::Running(_, cancel, _) = job
                && !keep.is_some_and(|k| k.contains(&key.file))
            {
                cancel.store(true, Ordering::Relaxed);
            }
        }
        self.jobs.retain(|key, job| {
            matches!(job, Job::Running(..)) || keep.is_some_and(|k| k.contains(&key.file))
        });
        let jobs = &self.jobs;
        self.made.retain(|k| jobs.contains_key(k));
    }
}
