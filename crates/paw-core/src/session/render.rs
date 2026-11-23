//! Rendering the project to a file.
//!
//! A render takes a snapshot of the project and builds a private engine from
//! it on the main thread (plugins included), then hands that engine to a
//! thread of its own, which plays it as fast as it can and encodes what comes
//! out. The session goes on meanwhile: edits made during a render change the
//! project, not the render. The file is written under a temporary name in the
//! same directory and renamed when it is complete, so that a cancelled or
//! failed render leaves nothing under the name asked for.
//!
//! Normalizing (to a peak level or a loudness) needs the whole song before
//! the first sample can be written: the engine's output goes to a raw
//! temporary file first, is measured, and is then encoded from there with
//! the gain applied, which gives the same samples as playing the song twice.

use crate::events::{KernelEvent as E, RenderEnd, RenderProgress};
use std::fs::File;
use std::io::{BufReader, BufWriter, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow, bail};
use paw_engine::backend;
use paw_engine::{Engine, Msg, wav};
use paw_measure::Analyzer;
use serde_json::{Value, json};

use super::encode::{self, Lossy, Quality};
use super::tags::{self, Cover, Tags};
use super::statelanes::{self, Settle, Stop};
use super::{Dither, RenderOpts, Session, block_json, check_sample_rate, settle_plugins};
use crate::model::{Id, MASTER_ID, Project};
use crate::sync::{LiveDevices, Mapper, SyncCtx, sync};

/// Seconds a render goes on after its end at most: ten minutes is more
/// than any reverb or delay rings for.
const MAX_TAIL: f64 = 600.0;

/// An engine built for a render, with what the render needs from the sync.
struct BuiltEngine {
    engine: Engine,
    handle: paw_engine::EngineHandle,
    live: LiveDevices,
    latency: usize,
    mapper_states: std::collections::HashMap<Id, Vec<bool>>,
    mapper_devices: std::collections::HashMap<Id, paw_engine::DeviceSlot>,
}

/// Only these tracks of a render, with what they pass through on the way
/// to the master: as when they are soloed. A frozen track alone, or none.
fn select_render_tracks(project: &mut Project, opts: &RenderOpts) -> Result<()> {
    if let Some(id) = opts.freeze {
        if !opts.tracks.is_empty() {
            bail!("a render is of a frozen track or of a list of tracks, not both");
        }
        crate::freeze::alone(project, id)?;
    }
    if !opts.tracks.is_empty() {
        if let Some(id) = opts.tracks.iter().find(|id| project.track(**id).is_none()) {
            bail!("no track {id} to render");
        }
        for track in project.tracks.iter_mut() {
            let wanted = opts.tracks.contains(&track.id);
            if track.solo != wanted {
                Arc::make_mut(track).solo = wanted;
            }
        }
    }
    if !opts.master {
        bypass_master(project);
    }
    Ok(())
}

/// The checks of the levels and of the folder of a render.
fn check_render_target(opts: &RenderOpts, path: &Path) -> Result<()> {
    if let Some(level) = opts.normalize
        && (!level.is_finite() || level > 0.0)
    {
        bail!("normalize to a level in dB at or below 0, such as -1");
    }
    if let Some(level) = opts.loudness
        && (!level.is_finite() || !(-70.0..=0.0).contains(&level))
    {
        bail!("loudness is a level in LUFS between -70 and 0, such as -14");
    }
    if let Some(dir) = path.parent().filter(|d| !d.as_os_str().is_empty())
        && !dir.is_dir()
    {
        bail!(
            "cannot render {}: there is no directory {}",
            path.display(),
            dir.display()
        );
    }
    Ok(())
}

/// A kind of file a render can write.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Format {
    Wav,
    Flac,
    /// The lossy formats are made by ffmpeg from a WAV: see [`encode`].
    Mp3,
    Vorbis,
    Opus,
}

impl Format {
    /// Every format that can be written, with its extensions.
    pub const ALL: &'static [(Format, &'static str, &'static [&'static str])] = &[
        (Format::Wav, "WAV", &["wav", "wave"]),
        (Format::Flac, "FLAC", &["flac"]),
        (Format::Mp3, "MP3", &["mp3"]),
        (Format::Vorbis, "Ogg Vorbis", &["ogg", "oga"]),
        (Format::Opus, "Opus", &["opus"]),
    ];

    pub fn name(self) -> &'static str {
        Self::ALL.iter().find(|f| f.0 == self).map_or("?", |f| f.1)
    }

    /// The sample sizes the format holds.
    fn bits(self) -> &'static [u16] {
        match self {
            Format::Wav => &[16, 24, 32],
            Format::Flac => &[16, 24],
            _ => &[],
        }
    }

    /// The lossy format this is, when it is one.
    fn lossy(self) -> Option<Lossy> {
        match self {
            Format::Mp3 => Some(Lossy::Mp3),
            Format::Vorbis => Some(Lossy::Vorbis),
            Format::Opus => Some(Lossy::Opus),
            _ => None,
        }
    }
}

/// Formats people ask for that cannot be written, and why.
const UNWRITABLE: &[(&str, &str)] = &[
    ("m4a", "AAC"),
    ("aac", "AAC"),
    ("aif", "AIFF"),
    ("aiff", "AIFF"),
    ("wma", "WMA"),
];

/// "WAV (.wav) or FLAC (.flac)": what can be written with nothing else
/// installed, for messages.
pub fn writable() -> String {
    let names: Vec<String> = Format::ALL
        .iter()
        .filter(|(format, ..)| format.lossy().is_none())
        .map(|(_, name, ext)| format!("{name} (.{})", ext[0]))
        .collect();
    match names.split_last() {
        Some((last, [])) => last.clone(),
        Some((last, rest)) => format!("{} or {last}", rest.join(", ")),
        None => String::new(),
    }
}

/// The format a file name asks for, or why it cannot be written. The lossy
/// formats need ffmpeg: `ffmpeg` is where it is, when not on the PATH.
pub fn format_of(path: &Path, ffmpeg: Option<&str>) -> Result<Format> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(str::to_ascii_lowercase);
    let Some(ext) = ext else {
        bail!(
            "{} has no extension to say what to write: render to {}",
            path.display(),
            writable()
        );
    };
    if let Some((format, ..)) = Format::ALL
        .iter()
        .find(|(_, _, exts)| exts.contains(&ext.as_str()))
    {
        if let Some(why) = format.lossy().and_then(|l| encode::unavailable(l, ffmpeg)) {
            bail!(
                "cannot render {}: {} {why}; render to {}, which need nothing",
                path.display(),
                format.name(),
                writable()
            );
        }
        return Ok(*format);
    }
    match UNWRITABLE.iter().find(|(e, _)| *e == ext) {
        Some((_, name)) => bail!(
            "cannot render {}: {name} needs an encoder this program does not have; render to {}",
            path.display(),
            writable()
        ),
        None => bail!(
            "cannot render {}: .{ext} is not a format this program writes; render to {}",
            path.display(),
            writable()
        ),
    }
}

/// The formats, for `paw.api.render_formats()`: `{ { name, extensions, bits,
/// lossy, available, why } }`; `why` says what a format that is not
/// available needs.
pub fn formats_json(ffmpeg: Option<&str>) -> Value {
    Value::Array(
        Format::ALL
            .iter()
            .map(|(format, name, exts)| {
                let why = format.lossy().and_then(|l| encode::unavailable(l, ffmpeg));
                json!({ "name": name, "extensions": exts, "bits": format.bits(),
                    "lossy": format.lossy().is_some(), "available": why.is_none(), "why": why })
            })
            .collect(),
    )
}

/// Where a render is up to, shared with its thread.
#[derive(Default)]
struct Progress {
    /// Fraction done, as the bits of an `f64`.
    fraction: AtomicU64,
    cancel: AtomicBool,
    /// The file is being encoded by ffmpeg: `fraction` is now the encode's.
    encoding: AtomicBool,
}

impl Progress {
    fn set(&self, fraction: f64) {
        self.fraction.store(fraction.to_bits(), Ordering::Relaxed);
    }

    fn get(&self) -> f64 {
        f64::from_bits(self.fraction.load(Ordering::Relaxed))
    }

    fn cancelled(&self) -> bool {
        self.cancel.load(Ordering::Relaxed)
    }

    fn stage(&self) -> &'static str {
        if self.encoding.load(Ordering::Relaxed) {
            "encoding"
        } else {
            "rendering"
        }
    }
}

/// A render that is running.
pub struct Job {
    path: PathBuf,
    started: Instant,
    progress: Arc<Progress>,
    thread: Option<JoinHandle<Result<Value>>>,
    /// The main-thread side of the render's devices: kept here until its
    /// engine, on the render's thread, is gone.
    live: Option<LiveDevices>,
    /// The fraction last reported in a `render.progress` event, and when.
    reported: (f64, Instant),
    /// Where the render stops for a state lane's state that the main
    /// thread gives (see `statelanes.rs`): the render's thread asks by the
    /// stop's number, and is answered once the plugin is ready.
    stops: Vec<Stop>,
    asks: std::sync::mpsc::Receiver<usize>,
    answers: std::sync::mpsc::Sender<()>,
    /// The stop being given, while the plugin gets ready.
    settling: Option<(Id, Settle)>,
    settle: Duration,
}

/// What a render's thread needs besides its engine.
struct Plan {
    format: Format,
    path: PathBuf,
    sample_rate: u32,
    bits: u16,
    channels: u16,
    frames: usize,
    /// Frames the engine's output is late by, played and thrown away.
    latency: usize,
    dither: bool,
    /// Bring the loudest sample to this level in dB.
    peak: Option<f64>,
    /// Bring the integrated loudness to this level in LUFS.
    loudness: Option<f64>,
    progress: Arc<Progress>,
    /// For a lossy format: how ffmpeg is to make the file from the WAV
    /// that is rendered first.
    encode: Option<Encode>,
    /// What the file is tagged with: in a WAV or FLAC as it is written, in
    /// the lossy formats by ffmpeg.
    tags: Tags,
    cover: Option<Cover>,
    /// The engine's frames (from the start, before the latency is played
    /// away) where the render stops for the main thread to give a state;
    /// the main thread is asked by a stop's number, and answers when the
    /// plugin is ready.
    stops: Vec<u64>,
    ask: std::sync::mpsc::Sender<usize>,
    answered: std::sync::mpsc::Receiver<()>,
}

struct Encode {
    format: Lossy,
    program: String,
    quality: Quality,
    bitrate: Option<u32>,
}

/// The temporary name a file is written under until it is complete.
fn partial(path: &Path, what: &str) -> PathBuf {
    let name = path.file_name().unwrap_or_default().to_string_lossy();
    path.with_file_name(format!(".{name}.{what}"))
}

impl Session {
    /// Render the project to a file and wait for it. Returns what
    /// [`render_start`](Self::render_start) does when it is done.
    pub fn render(&mut self, path: &Path, opts: &RenderOpts) -> Result<Value> {
        self.render_start(path, opts)?;
        self.render_wait()
    }

    /// Wait for the running render to end, and give what it gives.
    pub(super) fn render_wait(&mut self) -> Result<Value> {
        let mut job = self.render_job.take().context("the render did not start")?;
        // The render's thread may stop on a state lane's point and wait
        // for the main thread, which is here.
        while !job.thread.as_ref().is_none_or(|t| t.is_finished()) {
            serve_stops(&mut job);
            std::thread::sleep(Duration::from_millis(2));
        }
        let result = job
            .thread
            .take()
            .expect("a render's thread is joined once")
            .join()
            .unwrap_or_else(|_| Err(anyhow!("the render stopped unexpectedly")));
        let left_out = self.render_left_out(job.live.take());
        result.map(|info| with_left_out(info, left_out))
    }

    /// Plugins of a render that stopped answering and were left out of the
    /// rest of it (see the sandbox), as messages; the render's devices are
    /// let go of here, once its engine is gone.
    fn render_left_out(&mut self, live: Option<LiveDevices>) -> Vec<String> {
        let mut out = Vec::new();
        for (id, mut device) in live.into_iter().flatten() {
            if let Some(why) = device.controller.as_mut().and_then(|c| c.health()) {
                let name = self
                    .project
                    .device(id)
                    .map_or("a device", |d| d.kind.as_str());
                out.push(format!(
                    "{name} stopped during the render ({why}); the rest was rendered without it"
                ));
            }
        }
        out
    }

    /// Start rendering the project to a file, on a thread of its own, from a
    /// snapshot of the project as it is now. [`render_poll`](Self::render_poll)
    /// reports progress and the end as events.
    pub fn render_start(&mut self, path: &Path, opts: &RenderOpts) -> Result<()> {
        format_of(path, opts.ffmpeg.as_deref())?;
        // Every plugin is needed: wait for those still being made, and
        // refuse, naming it, one that did not load.
        self.await_loads(Duration::from_secs(60))?;
        self.capture_states();
        let project = self.project.clone();
        // The file's tags are the project's, over which the render's own
        // go. A lossy file's title is the project's name unless one is
        // given; a WAV or FLAC is only tagged with what was asked for, so
        // that a plain render stays a plain file.
        let mut opts = opts.clone();
        opts.tags = Tags::of_project(&project)?.over(&opts.tags);
        let lossy = format_of(path, opts.ffmpeg.as_deref())?.lossy().is_some();
        if lossy && opts.tags.title.is_empty() {
            opts.tags.title.clone_from(&project.name);
        }
        self.render_snapshot(project, path, &opts)
    }

    /// Start rendering `project`, which need not be the session's: a glue
    /// renders a few clips of it.
    pub(super) fn render_snapshot(
        &mut self,
        mut project: Project,
        path: &Path,
        opts: &RenderOpts,
    ) -> Result<()> {
        let (format, quality, bits) = self.check_render_opts(path, opts)?;
        select_render_tracks(&mut project, opts)?;
        let project = &project;
        let (sample_rate, frames) = self.render_extent(project, opts, format, bits)?;
        // Stretched clips play versions made apart: wait for those too.
        self.await_stretches(project, sample_rate, Duration::from_secs(120))?;
        check_render_target(opts, path)?;

        let cover = opts
            .tags
            .load_cover(self.path.as_deref().and_then(Path::parent))?;

        let mut built = self.build_render_engine(project, sample_rate, opts);
        let stops = self.start_render_engine(&mut built, project, opts, sample_rate);
        let BuiltEngine { engine, handle, live, latency, .. } = built;
        // A plugin that loads in the background (a model) is given time
        // to be ready before the first frame.
        let settle = Duration::from_secs_f64(opts.settle.clamp(0.0, 600.0));
        // The handle stays with the engine: dropping it would leave the
        // engine's side of the channel without its other end.
        let progress = Arc::new(Progress::default());
        let (ask, asks) = std::sync::mpsc::channel();
        let (answers, answered) = std::sync::mpsc::channel();
        let plan = Plan {
            stops: stops.iter().map(|s| s.frame).collect(),
            ask,
            answered,
            format,
            path: path.to_path_buf(),
            sample_rate,
            bits,
            channels: opts.channels,
            frames,
            latency,
            dither: opts.dither && format.lossy().is_none(),
            peak: opts.normalize,
            loudness: opts.loudness,
            progress: progress.clone(),
            encode: format.lossy().map(|lossy| Encode {
                format: lossy,
                program: encode::program(opts.ffmpeg.as_deref()).to_owned(),
                quality,
                bitrate: opts.bitrate,
            }),
            tags: opts.tags.clone(),
            cover,
        };
        let thread = std::thread::Builder::new()
            .name("render".into())
            .spawn(move || {
                let _handle = handle;
                run(engine, plan)
            })
            .context("starting the render's thread")?;
        let now = Instant::now();
        self.render_job = Some(Job {
            path: path.to_path_buf(),
            started: now,
            progress,
            thread: Some(thread),
            live: Some(live),
            reported: (0.0, now),
            stops,
            asks,
            answers,
            settling: None,
            settle,
        });
        Ok(())
    }

    /// The format, quality and bit depth of a render, after the checks
    /// that need only its options and whether another render runs.
    fn check_render_opts(&mut self, path: &Path, opts: &RenderOpts) -> Result<(Format, Quality, u16)> {
        let format = format_of(path, opts.ffmpeg.as_deref())?;
        let quality = opts
            .quality
            .as_deref()
            .map_or(Ok(Quality::High), Quality::parse)?;
        if opts.bitrate.is_some_and(|k| !(8..=512).contains(&k)) {
            bail!("bitrate is in kbit/s, from 8 to 512");
        }
        // What is rendered: a lossy format is encoded from 32-bit float.
        let bits = if format.lossy().is_some() { 32 } else { opts.bits };
        // One that has finished but not been reported yet is reported now.
        self.render_poll();
        if let Some(job) = &self.render_job {
            bail!(
                "{} is being rendered: wait for it or cancel it first",
                job.path.display()
            );
        }
        if format.lossy().is_none() && !format.bits().contains(&opts.bits) {
            let bits: Vec<String> = format.bits().iter().map(u16::to_string).collect();
            bail!(
                "cannot render {} at {} bits: use {}",
                format.name(),
                opts.bits,
                bits.join(", ")
            );
        }
        if !matches!(opts.channels, 1 | 2) {
            bail!(
                "a render has 1 channel (mono) or 2 (stereo), not {}",
                opts.channels
            );
        }
        Ok((format, quality, bits))
    }

    /// The sample rate and the number of frames of a render, after the
    /// checks of its range and of the size of the file.
    fn render_extent(
        &self,
        project: &Project,
        opts: &RenderOpts,
        format: Format,
        bits: u16,
    ) -> Result<(u32, usize)> {
        let sample_rate = opts.sample_rate.unwrap_or(self.engine.stream.info.sample_rate);
        check_sample_rate(sample_rate)?;
        let end = opts.end.unwrap_or_else(|| project.end());
        if !opts.start.is_finite() || !end.is_finite() || !opts.tail.is_finite() {
            bail!("a render needs a finite start, end and tail");
        }
        if opts.tail > MAX_TAIL {
            bail!("a render's tail is at most {MAX_TAIL} seconds, not {}", opts.tail);
        }
        if end <= opts.start {
            bail!(
                "nothing to render between beat {} and beat {end}",
                opts.start
            );
        }
        let seconds = project.tempo_map().seconds_between(opts.start, end) + opts.tail.max(0.0);
        let frames = (seconds * sample_rate as f64).ceil();
        // A WAV file holds at most 4 GiB of samples.
        let bytes = frames * opts.channels as f64 * (bits / 8) as f64;
        if (format == Format::Wav || format.lossy().is_some()) && bytes >= u32::MAX as f64 - 64.0 {
            bail!(
                "{seconds:.0} s at {sample_rate} Hz and {bits} bits is more than a WAV file can hold"
            );
        }
        Ok((sample_rate, frames as usize))
    }

    /// A private engine with its own instances of every device, plugins
    /// included, and the project synced into it.
    fn build_render_engine(
        &mut self,
        project: &Project,
        sample_rate: u32,
        opts: &RenderOpts,
    ) -> BuiltEngine {
        let (mut engine, mut handle) = Engine::new(sample_rate as f64);
        engine.set_pool(self.pool(opts.threads));
        engine.set_sleep(opts.sleep.unwrap_or(self.sleep()));
        engine.set_offline(true);
        let mut live = LiveDevices::new();
        // Nothing else is driving this engine, so make room by pumping it.
        let mut send = |msg| {
            let mut msg = msg;
            while let Err(back) = handle.try_send(msg) {
                msg = back;
                engine.pump();
            }
        };
        send(Msg::SetTempo(project.tempo));
        send(Msg::SetTimeSig {
            num: project.sig_num,
            den: project.sig_den,
        });
        let mut ctx = SyncCtx {
            registry: &self.registry,
            sources: &self.sources,
            audio: &mut self.audio,
            live: &mut live,
            sample_rate: sample_rate as f32,
            warnings: &mut self.warnings,
            offline: true,
        };
        let mut mapper = Mapper::new();
        sync(
            &Project::default(),
            project,
            &mut mapper,
            &mut ctx,
            &mut send,
            &mut Vec::new(),
        );
        BuiltEngine {
            latency: mapper.latency as usize,
            mapper_states: mapper.state_main.clone(),
            mapper_devices: mapper.devices.clone(),
            engine,
            handle,
            live,
        }
    }

    /// Bring the built engine to the first frame: the state lanes' states
    /// in force at the start, the plugins settled, the song at the start
    /// and playing. Returns the stops where the render waits for states.
    fn start_render_engine(
        &mut self,
        built: &mut BuiltEngine,
        project: &Project,
        opts: &RenderOpts,
        sample_rate: u32,
    ) -> Vec<Stop> {
        let BuiltEngine { engine, handle, live, mapper_states, mapper_devices, .. } = built;
        // A state lane's saved states: the one in force at the start is
        // given now, the others where the render stops for them.
        let (first, stops) = {
            let mut mapper = Mapper::new();
            mapper.state_main = mapper_states.clone();
            let map = project.tempo_map().clone();
            let t0 = map.seconds(opts.start);
            let sr = sample_rate as f64;
            statelanes::render_stops(project, &mapper, opts.start, |beat| {
                let x = (map.seconds(beat) - t0) * sr;
                if (x - x.round()).abs() < 1e-6 { x.round() as u64 } else { x.ceil() as u64 }
            })
        };
        // Each state lane's state at the start is given now, whole, so
        // that the plugin holds it from the first frame.
        let starting = statelanes::states_at(project, opts.start);
        for (id, state) in &starting {
            let Some(device) = live.get_mut(id) else { continue };
            match statelanes::give_all(device, state) {
                Ok(params) => {
                    if let Some(&slot) = mapper_devices.get(id) {
                        for (param, value) in params {
                            handle.send_while(Msg::SetParam { device: slot, param, value }, engine);
                        }
                    }
                }
                Err(err) => self
                    .warnings
                    .push(format!("state `{}` of a lane: {err:#}", state.name)),
            }
        }
        drop(first);
        settle_plugins(engine, live);
        let settle = Duration::from_secs_f64(opts.settle.clamp(0.0, 600.0));
        if starting.is_empty() {
            Settle::start(settle).wait(live, None);
        } else {
            Settle::new(settle).wait(live, None);
        }
        // A plugin that has loaded a model can fade over to it as it plays
        // (TONE3000 takes about a third of a second): half a second of
        // silence, with the song stopped, lets it finish before the first
        // frame, so that each render starts the same.
        if live.values().any(|d| d.controller.is_some()) {
            let mut scratch = vec![0.0f32; 2 * paw_engine::MAX_BLOCK];
            let (left, right) = scratch.split_at_mut(paw_engine::MAX_BLOCK);
            for _ in 0..(sample_rate as usize / 2).div_ceil(paw_engine::MAX_BLOCK) {
                engine.process(left, right);
            }
        }
        handle.send_while(Msg::Seek(opts.start), engine);
        handle.send_while(Msg::StatesHeld, engine);
        handle.send_while(Msg::Play, engine);
        stops
    }

    /// Ask the running render to stop. It leaves no file behind. Returns
    /// whether there was one.
    pub fn render_cancel(&mut self) -> bool {
        match &self.render_job {
            Some(job) => {
                job.progress.cancel.store(true, Ordering::Relaxed);
                true
            }
            None => false,
        }
    }

    /// The running render: `{ path, fraction, seconds }`, or null.
    pub fn render_status(&self) -> Value {
        match &self.render_job {
            Some(job) => json!({
                "path": job.path,
                "fraction": job.progress.get(),
                "seconds": job.started.elapsed().as_secs_f64(),
                "cancelling": job.progress.cancelled(),
                "stage": job.progress.stage(),
            }),
            None => Value::Null,
        }
    }

    /// Whether a render is running.
    pub fn rendering(&self) -> bool {
        self.render_job.is_some()
    }

    /// Report how the running render is getting on: `render.progress` now
    /// and then, and `render.done`, `render.failed` or `render.cancelled`
    /// when it ends. Called from [`idle`](Self::idle).
    pub fn render_poll(&mut self) {
        let Some(job) = &mut self.render_job else {
            return;
        };
        serve_stops(job);
        let finished = job.thread.as_ref().is_none_or(|t| t.is_finished());
        if !finished {
            let fraction = job.progress.get();
            if fraction != job.reported.0 && job.reported.1.elapsed() >= Duration::from_millis(100) {
                job.reported = (fraction, Instant::now());
                let progress = RenderProgress { path: job.path.clone(), fraction,
                    stage: job.progress.stage().to_string(), seconds: job.started.elapsed().as_secs_f64() };
                self.emit(E::RenderProgress(progress));
            }
            return;
        }
        let mut job = self.render_job.take().expect("checked above");
        let result = match job.thread.take() {
            Some(thread) => thread
                .join()
                .unwrap_or_else(|_| Err(anyhow!("the render stopped unexpectedly"))),
            None => Err(anyhow!("the render stopped unexpectedly")),
        };
        let left_out = self.render_left_out(job.live.take());
        let event = match result {
            Ok(info) => E::RenderDone(with_left_out(info, left_out)),
            Err(_) if job.progress.cancelled() => E::RenderCancelled(RenderEnd { path: job.path, error: None }),
            Err(err) => E::RenderFailed(RenderEnd { path: job.path, error: Some(format!("{err:#}")) }),
        };
        self.emit(event);
    }
}

/// Give the states the render's thread stopped for, and answer it once the
/// plugin is ready. Never waits.
fn serve_stops(job: &mut Job) {
    let Some(live) = job.live.as_mut() else {
        return;
    };
    if job.settling.is_none()
        && let Ok(at) = job.asks.try_recv()
    {
        if let Some(stop) = job.stops.get(at)
            && let Some(device) = live.get_mut(&stop.device)
        {
            // A state that cannot be given is left out; the render goes on.
            let _ = statelanes::give(device, &stop.state);
            job.settling = Some((stop.device, Settle::new(job.settle)));
        } else {
            let _ = job.answers.send(());
        }
    }
    if let Some((device, settle)) = &mut job.settling
        && settle.ready(live, Some(&[*device]))
    {
        job.settling = None;
        let _ = job.answers.send(());
    }
}

/// A render's answer with what it had to leave out, if anything.
fn with_left_out(mut info: Value, left_out: Vec<String>) -> Value {
    if !left_out.is_empty()
        && let Value::Object(map) = &mut info
    {
        map.insert("left_out".into(), json!(left_out));
    }
    info
}

/// Take the master track's own processing out: its devices, fader, pan and
/// automation, so that what reaches it is what is written.
fn bypass_master(project: &mut Project) {
    let master = Arc::make_mut(&mut project.master);
    debug_assert_eq!(master.id, MASTER_ID);
    master.devices.clear();
    master.lanes.clear();
    master.volume = 0.0;
    master.pan = 0.0;
    master.mute = false;
}

/// What the render's thread does: play the engine through, write the file
/// under a temporary name, and give it its name when it is complete.
fn run(engine: Engine, plan: Plan) -> Result<Value> {
    let part = partial(&plan.path, "part");
    let raw = partial(&plan.path, "raw");
    let result = match &plan.encode {
        None => write(engine, &plan, &part, &raw).and_then(|info| {
            if plan.format == Format::Wav {
                tags::write_wav(&part, &plan.tags).context("tagging the file")?;
            }
            Ok(info)
        }),
        Some(encode) => {
            // The mix goes to a WAV beside the file, which ffmpeg then
            // encodes into the part; the WAV goes either way.
            let wav = partial(&plan.path, "wav.part");
            let metadata = partial(&plan.path, "meta");
            let cover_file = partial(
                &plan.path,
                &format!("cover.{}", plan.cover.as_ref().map_or("png", Cover::extension)),
            );
            let result = write(engine, &plan, &wav, &raw).and_then(|info| {
                plan.progress.encoding.store(true, Ordering::Relaxed);
                plan.progress.set(0.0);
                let seconds = plan.frames as f64 / plan.sample_rate as f64;
                encode::run(
                    &encode::Job {
                        format: encode.format,
                        program: &encode.program,
                        input: &wav,
                        output: &part,
                        rate: plan.sample_rate,
                        seconds,
                        tags: &plan.tags,
                        cover: plan.cover.as_ref(),
                        metadata: &metadata,
                        cover_file: &cover_file,
                        quality: encode.quality,
                        bitrate: encode.bitrate,
                    },
                    &|f| plan.progress.set(f),
                    &|| plan.progress.cancelled(),
                )?;
                plan.progress.set(1.0);
                Ok(info)
            });
            let _ = std::fs::remove_file(&wav);
            let _ = std::fs::remove_file(&metadata);
            let _ = std::fs::remove_file(&cover_file);
            result.map(|mut info| {
                info["bits"] = Value::Null;
                info["quality"] = json!(format!("{:?}", encode.quality).to_lowercase());
                info["bitrate"] = json!(encode.bitrate);
                info
            })
        }
    };
    let _ = std::fs::remove_file(&raw);
    match result {
        Ok(info) => {
            std::fs::rename(&part, &plan.path)
                .with_context(|| format!("writing {}", plan.path.display()))?;
            Ok(info)
        }
        Err(err) => {
            let _ = std::fs::remove_file(&part);
            Err(err)
        }
    }
}

/// What playing the engine through found.
struct Pass {
    peak: f32,
    nonfinite: u64,
    elapsed: f64,
    processing: f64,
    blocks: Value,
    threads: u32,
    /// Blocks of devices run, and slept through.
    device_blocks: (u64, u64),
    /// Integrated loudness of what was played, when it was measured.
    loudness: Option<f64>,
}

/// Play the engine through, handing every frame of output (mono or stereo
/// as the plan says) to `sink`. Progress goes from `from` to `to`.
fn play(
    mut engine: Engine,
    plan: &Plan,
    measure: bool,
    span: (f64, f64),
    sink: &mut dyn FnMut(f32, f32) -> Result<()>,
) -> Result<Pass> {
    let frames = plan.frames;
    let mut left = vec![0.0f32; 512];
    let mut right = vec![0.0f32; 512];
    let mut peak = 0f32;
    let mut nonfinite = 0u64;
    let mut done = 0;
    let began = Instant::now();
    let mut processing = Duration::ZERO;
    let mut analyzer = measure.then(|| Analyzer::new(plan.sample_rate as f64));
    // As on the audio thread: decaying tails must not slow the render down.
    let denormals = backend::NoDenormals::new();
    let mut skip = plan.latency;
    // Frames the engine has played, and the next stop for a state.
    let mut played = 0u64;
    let mut stop = 0;
    while done < frames {
        if plan.progress.cancelled() {
            bail!("the render was cancelled");
        }
        while plan.stops.get(stop).is_some_and(|&at| at <= played) {
            if plan.stops[stop] == played && played > 0 {
                wait_for_state(plan, stop)?;
            }
            stop += 1;
        }
        let mut n = (frames - done + skip).min(left.len());
        if let Some(&at) = plan.stops.get(stop) {
            n = n.min((at - played) as usize);
        }
        played += n as u64;
        let block = Instant::now();
        engine.process(&mut left[..n], &mut right[..n]);
        processing += block.elapsed();
        let skipped = skip.min(n);
        skip -= skipped;
        if plan.channels == 1 {
            for i in skipped..n {
                let mono = (left[i] + right[i]) * 0.5;
                left[i] = mono;
                right[i] = mono;
            }
        }
        for (l, r) in left[skipped..n].iter().zip(&right[skipped..n]) {
            peak = peak.max(l.abs()).max(r.abs());
            nonfinite += (!l.is_finite()) as u64 + (!r.is_finite()) as u64;
            sink(*l, *r)?;
        }
        if let Some(analyzer) = &mut analyzer {
            analyzer.push(&left[skipped..n], &right[skipped..n]);
        }
        done += n - skipped;
        plan.progress
            .set(span.0 + (span.1 - span.0) * done as f64 / frames.max(1) as f64);
    }
    drop(denormals);
    let sample_rate = plan.sample_rate;
    Ok(Pass {
        peak,
        nonfinite,
        elapsed: began.elapsed().as_secs_f64() * 1000.0,
        processing: processing.as_secs_f64() * 1000.0,
        blocks: block_json(&engine.shared().blocks.summary(), sample_rate),
        threads: engine.shared().threads(),
        device_blocks: engine.shared().device_blocks(),
        loudness: analyzer.and_then(|a| a.finish().integrated),
    })
}

/// Ask the main thread to give the state of stop `at`, and wait until the
/// plugin is ready.
fn wait_for_state(plan: &Plan, at: usize) -> Result<()> {
    if plan.ask.send(at).is_err() {
        return Ok(());
    }
    loop {
        match plan.answered.recv_timeout(Duration::from_millis(50)) {
            Ok(()) => return Ok(()),
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => return Ok(()),
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                if plan.progress.cancelled() {
                    bail!("the render was cancelled");
                }
            }
        }
    }
}

fn write(engine: Engine, plan: &Plan, part: &Path, raw: &Path) -> Result<Value> {
    let normalizing = plan.peak.is_some() || plan.loudness.is_some();
    let (pass, gain) = if normalizing {
        // Play it all into a raw file, measuring, then encode from there.
        let mut out = BufWriter::new(
            File::create(raw).with_context(|| format!("creating {}", raw.display()))?,
        );
        let pass = play(
            engine,
            plan,
            plan.loudness.is_some(),
            (0.0, 0.8),
            &mut |l, r| {
                out.write_all(&l.to_le_bytes())?;
                out.write_all(&r.to_le_bytes())?;
                Ok(())
            },
        )?;
        out.flush()?;
        drop(out);
        let mut gain = 1.0f32;
        if let Some(level) = plan.peak
            && pass.peak > 0.0
            && pass.peak.is_finite()
        {
            gain = paw_engine::db_to_gain(level) / pass.peak;
        }
        if let (Some(target), Some(measured)) = (plan.loudness, pass.loudness) {
            let to_loudness = paw_engine::db_to_gain(target - measured);
            // With a peak level too, the peak is a ceiling the loudness gives way to.
            gain = if plan.peak.is_some() {
                gain.min(to_loudness)
            } else {
                to_loudness
            };
        }
        let mut encoder = Encoder::create(plan, part)?;
        let mut input =
            BufReader::new(File::open(raw).with_context(|| format!("reading {}", raw.display()))?);
        input.seek(SeekFrom::Start(0))?;
        let mut bytes = [0u8; 8];
        for i in 0..plan.frames {
            if plan.progress.cancelled() {
                bail!("the render was cancelled");
            }
            input.read_exact(&mut bytes)?;
            let l = f32::from_le_bytes(bytes[..4].try_into().expect("4 bytes"));
            let r = f32::from_le_bytes(bytes[4..].try_into().expect("4 bytes"));
            encoder.frame(l * gain, r * gain)?;
            if i % 65536 == 0 {
                plan.progress
                    .set(0.8 + 0.2 * i as f64 / plan.frames.max(1) as f64);
            }
        }
        encoder.finish()?;
        (pass, gain)
    } else {
        let mut encoder = Encoder::create(plan, part)?;
        let pass = play(engine, plan, false, (0.0, 1.0), &mut |l, r| {
            encoder.frame(l, r)
        })?;
        encoder.finish()?;
        (pass, 1.0)
    };
    plan.progress.set(1.0);
    let seconds = plan.frames as f64 / plan.sample_rate as f64;
    Ok(json!({
        "path": plan.path, "frames": plan.frames, "seconds": seconds,
        "sample_rate": plan.sample_rate, "peak": pass.peak * gain,
        "format": plan.format.name(), "bits": plan.bits, "channels": plan.channels,
        // What normalizing raised or lowered the level by, in dB.
        "gain": paw_engine::gain_to_db(gain),
        // Integrated loudness of the file, in LUFS, when it was measured.
        "loudness": pass.loudness.map(|l| l + paw_engine::gain_to_db(gain)),
        // Samples that came out NaN or infinite, which the file holds as 0 or full scale.
        "nonfinite": pass.nonfinite,
        // Wall-clock time of the render loop, and of the engine alone
        // (without encoding and writing the file), in milliseconds.
        "elapsed": pass.elapsed, "processing": pass.processing,
        "blocks": pass.blocks, "threads": pass.threads,
        // Blocks of devices run, and blocks that devices at rest slept through.
        "device_runs": pass.device_blocks.0, "device_sleeps": pass.device_blocks.1,
    }))
}

/// Writes frames to a file in the plan's format, with dither for integers.
struct Encoder {
    out: Out,
    dither: Dither,
    channels: u16,
}

enum Out {
    Wav(wav::Writer),
    Flac(Box<Flac>),
}

impl Encoder {
    fn create(plan: &Plan, path: &Path) -> Result<Self> {
        let out = match plan.format {
            Format::Wav | Format::Mp3 | Format::Vorbis | Format::Opus => Out::Wav(
                wav::Writer::with_channels(
                    path,
                    plan.sample_rate,
                    plan.bits,
                    plan.bits == 32,
                    plan.channels,
                )
                .with_context(|| format!("creating {}", path.display()))?,
            ),
            Format::Flac => Out::Flac(Box::new(Flac::create(path, plan)?)),
        };
        Ok(Self {
            out,
            dither: Dither::new(if plan.dither { plan.bits } else { 32 }),
            channels: plan.channels,
        })
    }

    fn sample(&mut self, sample: f32) -> Result<()> {
        let sample = self.dither.apply(sample);
        match &mut self.out {
            Out::Wav(w) => w.write(sample),
            Out::Flac(f) => f.write(sample),
        }
    }

    fn frame(&mut self, l: f32, r: f32) -> Result<()> {
        self.sample(l)?;
        if self.channels == 2 {
            self.sample(r)?;
        }
        Ok(())
    }

    fn finish(self) -> Result<()> {
        match self.out {
            Out::Wav(w) => w.finish(),
            Out::Flac(f) => (*f).finish(),
        }
    }
}

/// A FLAC file written a frame at a time, its header put right at the end.
struct Flac {
    file: BufWriter<File>,
    config: flacenc::error::Verified<flacenc::config::Encoder>,
    stream: flacenc::component::Stream,
    buf: flacenc::source::FrameBuf,
    context: flacenc::source::Context,
    /// Interleaved samples of the frame being filled.
    pending: Vec<i32>,
    channels: usize,
    scale: f32,
    /// Smallest and largest frame written, in bytes.
    sizes: (usize, usize),
    sink: flacenc::bitsink::ByteSink,
}

/// Samples per channel in a FLAC frame.
const FLAC_BLOCK: usize = 4096;

impl Flac {
    fn create(path: &Path, plan: &Plan) -> Result<Self> {
        use flacenc::error::Verify;
        let channels = plan.channels as usize;
        let bits = plan.bits as usize;
        let mut config = flacenc::config::Encoder::default();
        // flacenc's fixed predictors can pick a Rice parameter far too small
        // for a block of loud 24-bit sound (the demo song's), which writes
        // one frame of hundreds of megabytes. Its LPC does not, and does the
        // fixed predictors' work as well.
        config.subframe_coding.use_fixed = false;
        let config = config
            .into_verified()
            .map_err(|e| anyhow!("FLAC settings: {e:?}"))?;
        let mut stream = flacenc::component::Stream::new(plan.sample_rate as usize, channels, bits)
            .map_err(|e| anyhow!("FLAC stream: {e:?}"))?;
        stream
            .stream_info_mut()
            .set_block_sizes(FLAC_BLOCK, FLAC_BLOCK)
            .map_err(|e| anyhow!("FLAC stream: {e:?}"))?;
        // Tags go after STREAMINFO, as a Vorbis comment block (type 4) and a
        // picture block (type 6); the header is the same size when it is
        // written again at the end.
        let mut block = |tag, data: &[u8]| {
            let data = flacenc::component::MetadataBlockData::new_unknown(tag, data)
                .map_err(|e| anyhow!("FLAC metadata: {e:?}"))?;
            stream.add_metadata_block(data);
            Ok::<_, anyhow::Error>(())
        };
        if plan.tags.has_text() {
            block(4, &tags::vorbis_comments(&plan.tags))?;
        }
        if let Some(cover) = &plan.cover {
            block(6, &cover.picture_block())?;
        }
        let file = File::create(path).with_context(|| format!("creating {}", path.display()))?;
        let mut flac = Self {
            file: BufWriter::new(file),
            config,
            stream,
            buf: flacenc::source::FrameBuf::with_size(channels, FLAC_BLOCK)
                .map_err(|e| anyhow!("FLAC buffer: {e:?}"))?,
            context: flacenc::source::Context::new(bits, channels),
            pending: Vec::with_capacity(FLAC_BLOCK * channels),
            channels,
            scale: ((1i64 << (bits - 1)) - 1) as f32,
            sizes: (usize::MAX, 0),
            sink: flacenc::bitsink::ByteSink::new(),
        };
        // The header as it will be, to be written again when the totals are known.
        flac.write_header()?;
        Ok(flac)
    }

    fn write_header(&mut self) -> Result<()> {
        use flacenc::component::BitRepr;
        self.sink.clear();
        self.stream
            .write(&mut self.sink)
            .map_err(|e| anyhow!("FLAC header: {e:?}"))?;
        self.file.write_all(self.sink.as_slice())?;
        Ok(())
    }

    fn write(&mut self, sample: f32) -> Result<()> {
        // As the WAV writer rounds: towards zero, after clamping.
        self.pending
            .push((sample.clamp(-1.0, 1.0) * self.scale) as i32);
        if self.pending.len() == FLAC_BLOCK * self.channels {
            self.frame()?;
        }
        Ok(())
    }

    fn frame(&mut self) -> Result<()> {
        use flacenc::component::BitRepr;
        use flacenc::source::Fill;
        if self.pending.is_empty() {
            return Ok(());
        }
        let mut target = (&mut self.buf, &mut self.context);
        target
            .fill_interleaved(&self.pending)
            .map_err(|e| anyhow!("FLAC: {e:?}"))?;
        let number = self.context.current_frame_number().unwrap_or(0);
        let frame = flacenc::encode_fixed_size_frame(
            &self.config,
            &self.buf,
            number,
            self.stream.stream_info(),
        )
        .map_err(|e| anyhow!("FLAC: {e:?}"))?;
        self.sink.clear();
        frame
            .write(&mut self.sink)
            .map_err(|e| anyhow!("FLAC: {e:?}"))?;
        let bytes = self.sink.as_slice();
        self.sizes = (self.sizes.0.min(bytes.len()), self.sizes.1.max(bytes.len()));
        self.file.write_all(bytes)?;
        self.pending.clear();
        Ok(())
    }

    fn finish(mut self) -> Result<()> {
        self.frame()?;
        let total = self.context.total_samples();
        let md5 = self.context.md5_digest();
        let info = self.stream.stream_info_mut();
        info.set_md5_digest(&md5);
        info.set_total_samples(total);
        if self.sizes.1 > 0 {
            let _ = info.set_frame_sizes(self.sizes.0, self.sizes.1);
        }
        self.file.flush()?;
        let mut file = self.file.into_inner().map_err(|e| e.into_error())?;
        file.seek(SeekFrom::Start(0))?;
        let mut header = BufWriter::new(file);
        {
            use flacenc::component::BitRepr;
            self.sink.clear();
            self.stream
                .write(&mut self.sink)
                .map_err(|e| anyhow!("FLAC header: {e:?}"))?;
            header.write_all(self.sink.as_slice())?;
        }
        header.flush()?;
        header
            .into_inner()
            .map_err(|e| e.into_error())?
            .sync_all()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_format_that_cannot_be_written_is_refused_by_name() {
        assert_eq!(format_of(Path::new("mix.WAV"), None).unwrap(), Format::Wav);
        assert_eq!(format_of(Path::new("mix.flac"), None).unwrap(), Format::Flac);
        let err = format_of(Path::new("mix.m4a"), None).unwrap_err().to_string();
        assert!(err.contains("AAC") && err.contains(".wav"), "{err}");
        let err = format_of(Path::new("mix.mp3"), Some("/no/such/ffmpeg")).unwrap_err().to_string();
        assert!(err.contains("MP3") && err.contains("ffmpeg") && err.contains(".wav"), "{err}");
        let err = format_of(Path::new("mix.xyz"), None).unwrap_err().to_string();
        assert!(err.contains(".xyz") && err.contains("WAV"), "{err}");
        let err = format_of(Path::new("mix"), None).unwrap_err().to_string();
        assert!(err.contains("no extension"), "{err}");
    }
}
