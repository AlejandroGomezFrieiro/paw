//! Lossy formats (MP3, Ogg Vorbis, Opus), made by `ffmpeg` when it is
//! installed. No encoder for them is linked into the program: a render of
//! one of these writes a WAV first, and this module has ffmpeg turn it into
//! the file asked for. The render's own thread starts it and takes its
//! reports; ffmpeg itself runs as a task on the kernel's I/O runtime, so the
//! main loop never waits for it.

use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::process::{Command, Stdio};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, BufReader as AsyncBufReader};
use std::sync::Mutex;
use std::sync::mpsc::{RecvTimeoutError, Sender, channel};
use std::time::Duration;

use anyhow::{Context, Result, anyhow, bail};

use super::tags::{self, Cover, Tags};

/// A lossy format ffmpeg can make.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Lossy {
    Mp3,
    Vorbis,
    Opus,
}

/// How good a lossy file should be, in words that mean the same in every format.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Quality {
    Low,
    Medium,
    High,
    Best,
}

impl Quality {
    pub fn parse(word: &str) -> Result<Self> {
        Ok(match word.to_ascii_lowercase().as_str() {
            "low" => Quality::Low,
            "medium" => Quality::Medium,
            "high" => Quality::High,
            "best" => Quality::Best,
            _ => bail!("quality is low, medium, high or best, not `{word}`"),
        })
    }
}

impl Lossy {
    fn encoder(self) -> &'static str {
        match self {
            Lossy::Mp3 => "libmp3lame",
            Lossy::Vorbis => "libvorbis",
            Lossy::Opus => "libopus",
        }
    }

    fn muxer(self) -> &'static str {
        match self {
            Lossy::Mp3 => "mp3",
            Lossy::Vorbis => "ogg",
            Lossy::Opus => "opus",
        }
    }

    /// The encoder's settings for a quality, or for a bitrate in kbit/s.
    fn settings(self, quality: Quality, bitrate: Option<u32>) -> Vec<String> {
        let pair = |flag: &str, value: String| vec![flag.to_owned(), value];
        if let Some(kbit) = bitrate {
            return pair("-b:a", format!("{kbit}k"));
        }
        match (self, quality) {
            // LAME's variable bitrate: about 115, 165 and 190 kbit/s.
            (Lossy::Mp3, Quality::Low) => pair("-q:a", "6".into()),
            (Lossy::Mp3, Quality::Medium) => pair("-q:a", "4".into()),
            (Lossy::Mp3, Quality::High) => pair("-q:a", "2".into()),
            (Lossy::Mp3, Quality::Best) => pair("-b:a", "320k".into()),
            (Lossy::Vorbis, Quality::Low) => pair("-q:a", "3".into()),
            (Lossy::Vorbis, Quality::Medium) => pair("-q:a", "5".into()),
            (Lossy::Vorbis, Quality::High) => pair("-q:a", "7".into()),
            (Lossy::Vorbis, Quality::Best) => pair("-q:a", "9".into()),
            (Lossy::Opus, Quality::Low) => pair("-b:a", "64k".into()),
            (Lossy::Opus, Quality::Medium) => pair("-b:a", "96k".into()),
            (Lossy::Opus, Quality::High) => pair("-b:a", "128k".into()),
            (Lossy::Opus, Quality::Best) => pair("-b:a", "192k".into()),
        }
    }

    /// The sample rate to ask ffmpeg for when it is not the one rendered at.
    fn rate(self, rendered: u32) -> Option<u32> {
        match self {
            Lossy::Opus => Some(48000).filter(|r| *r != rendered),
            Lossy::Mp3 if rendered > 48000 => Some(48000),
            _ => None,
        }
    }
}

/// What to run: `ffmpeg` on the PATH unless told where it is.
pub fn program(ffmpeg: Option<&str>) -> &str {
    ffmpeg.filter(|p| !p.is_empty()).unwrap_or("ffmpeg")
}

/// The encoders each ffmpeg that was asked has, remembered: asking costs a
/// process. Only answers are kept, so that installing ffmpeg is noticed.
static ENCODERS: Mutex<Option<HashMap<String, HashSet<String>>>> = Mutex::new(None);

fn encoders(program: &str) -> Result<HashSet<String>, String> {
    let mut known = ENCODERS.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(set) = known.get_or_insert_default().get(program) {
        return Ok(set.clone());
    }
    // A short blocking probe, cached after the first answer: kept as a plain process.
    let out = Command::new(program)
        .args(["-hide_banner", "-encoders"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .map_err(|e| format!("ffmpeg could not be run ({program}: {e})"))?;
    if !out.status.success() {
        return Err(format!("ffmpeg could not be run ({program} failed)"));
    }
    let set: HashSet<String> = String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter_map(|line| line.split_whitespace().nth(1).map(str::to_owned))
        .collect();
    known
        .get_or_insert_default()
        .insert(program.to_owned(), set.clone());
    Ok(set)
}

/// Why `format` cannot be written on this machine, or nothing.
pub fn unavailable(format: Lossy, ffmpeg: Option<&str>) -> Option<String> {
    let program = program(ffmpeg);
    match encoders(program) {
        Err(why) => Some(format!(
            "it needs ffmpeg, and {why}: install it or set paw.opt.ffmpeg to where it is"
        )),
        Ok(set) if !set.contains(format.encoder()) => Some(format!(
            "this ffmpeg ({program}) was built without the {} encoder",
            format.encoder()
        )),
        Ok(_) => None,
    }
}

/// What one encode needs.
pub struct Job<'a> {
    pub format: Lossy,
    pub program: &'a str,
    pub input: &'a Path,
    pub output: &'a Path,
    /// The WAV's sample rate, and its length in seconds.
    pub rate: u32,
    pub seconds: f64,
    pub tags: &'a Tags,
    pub cover: Option<&'a Cover>,
    /// Files this writes for ffmpeg to read, and the caller removes: the
    /// tags (a cover can be larger than one command-line argument may be),
    /// and for MP3 the cover.
    pub metadata: &'a Path,
    pub cover_file: &'a Path,
    pub quality: Quality,
    /// kbit/s, instead of the quality's.
    pub bitrate: Option<u32>,
}

impl Job<'_> {
    /// The cover in the file's comments (Ogg Vorbis and Opus), where MP3
    /// has it as a picture of its own.
    fn cover_in_comments(&self) -> Option<&Cover> {
        self.cover.filter(|_| self.format != Lossy::Mp3)
    }

    fn has_metadata(&self) -> bool {
        self.tags.has_text() || self.cover_in_comments().is_some()
    }

    /// Write the files `args` names.
    fn prepare(&self) -> Result<()> {
        if self.has_metadata() {
            std::fs::write(self.metadata, tags::ffmetadata(self.tags, self.cover_in_comments()))
                .with_context(|| format!("writing {}", self.metadata.display()))?;
        }
        if let (Some(cover), Lossy::Mp3) = (self.cover, self.format) {
            std::fs::write(self.cover_file, &cover.data)
                .with_context(|| format!("writing {}", self.cover_file.display()))?;
        }
        Ok(())
    }

    fn args(&self) -> Vec<String> {
        let mut args: Vec<String> = [
            "-hide_banner", "-nostdin", "-nostats", "-loglevel", "error", "-progress", "pipe:1", "-y", "-i",
        ]
        .map(str::to_owned)
        .into();
        args.push(self.input.display().to_string());
        // The inputs after the sound: the tags, then MP3's cover.
        let mut inputs = 1;
        if self.has_metadata() {
            args.extend(["-f", "ffmetadata", "-i"].map(str::to_owned));
            args.push(self.metadata.display().to_string());
            inputs += 1;
        }
        let mp3_cover = self.cover.filter(|_| self.format == Lossy::Mp3);
        if mp3_cover.is_some() {
            args.push("-i".to_owned());
            args.push(self.cover_file.display().to_string());
        }
        args.extend(["-map", "0:a"].map(str::to_owned));
        if mp3_cover.is_some() {
            args.extend(["-map".to_owned(), format!("{inputs}:v")]);
        }
        if self.has_metadata() {
            args.extend(["-map_metadata", "1"].map(str::to_owned));
        }
        args.extend(["-c:a", self.format.encoder()].map(str::to_owned));
        if mp3_cover.is_some() {
            args.extend(
                [
                    "-c:v", "copy", "-disposition:v:0", "attached_pic", "-id3v2_version", "3",
                    "-metadata:s:v", "title=Cover", "-metadata:s:v", "comment=Cover (front)",
                ]
                .map(str::to_owned),
            );
        }
        args.extend(self.format.settings(self.quality, self.bitrate));
        if let Some(rate) = self.format.rate(self.rate) {
            args.extend(["-ar".to_owned(), rate.to_string()]);
        }
        args.extend(["-f", self.format.muxer()].map(str::to_owned));
        args.push(self.output.display().to_string());
        args
    }
}

/// What the encoder's task tells the render's thread.
enum Event {
    /// How far the encode is, 0 to 1.
    Progress(f64),
    /// The encode ended: ffmpeg's exit, or why it could not run.
    Done(Result<()>),
}

/// ffmpeg's run, as the task on the kernel's I/O runtime does it.
async fn encode(
    mut command: tokio::process::Command,
    program: String,
    seconds: f64,
    events: &Sender<Event>,
    mut cancel: tokio::sync::oneshot::Receiver<()>,
) -> Result<()> {
    let mut child = command
        .spawn()
        .with_context(|| format!("starting {program}"))?;
    let stdout = child.stdout.take().context("ffmpeg's output")?;
    let mut stderr = child.stderr.take().context("ffmpeg's errors")?;
    let reading = async {
        let mut lines = AsyncBufReader::new(stdout).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            // `out_time_ms` is, in spite of its name, in microseconds.
            let micros = line
                .strip_prefix("out_time_us=")
                .or_else(|| line.strip_prefix("out_time_ms="))
                .and_then(|v| v.trim().parse::<f64>().ok());
            if let Some(micros) = micros {
                let done = (micros / 1e6 / seconds.max(1e-9)).clamp(0.0, 1.0);
                if events.send(Event::Progress(done)).is_err() {
                    break;
                }
            }
        }
    };
    let errors = async {
        let mut text = String::new();
        let _ = stderr.read_to_string(&mut text).await;
        text
    };
    let both = async { tokio::join!(reading, errors).1 };
    let text = tokio::select! {
        text = both => text,
        _ = &mut cancel => {
            let _ = child.kill().await;
            bail!("the render was cancelled");
        }
    };
    let status = child.wait().await?;
    if !status.success() {
        let why = text.lines().rev().find(|l| !l.trim().is_empty());
        return Err(anyhow!(
            "ffmpeg failed: {}",
            why.unwrap_or("it gave no reason")
        ));
    }
    Ok(())
}

/// Run the encode and wait for it, reporting how far it is (0 to 1) to
/// `progress` and giving up, with ffmpeg stopped, when `cancelled` says so.
/// ffmpeg runs as a task on the kernel's I/O runtime; this thread, the
/// render's, takes its reports and sends the cancel.
pub fn run(
    job: &Job,
    progress: &dyn Fn(f64),
    cancelled: &dyn Fn() -> bool,
) -> Result<()> {
    job.prepare()?;
    let mut command = tokio::process::Command::new(job.program);
    command
        .args(job.args())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    // As with any helper: not to outlive the program.
    #[cfg(target_os = "linux")]
    unsafe {
        command.pre_exec(|| {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
            Ok(())
        });
    }
    let (events, reports) = channel();
    let (stop, cancel) = tokio::sync::oneshot::channel();
    let (program, seconds) = (job.program.to_owned(), job.seconds);
    crate::io_runtime::handle()?.spawn(async move {
        let result = encode(command, program, seconds, &events, cancel).await;
        let _ = events.send(Event::Done(result));
    });
    let mut stop = Some(stop);
    loop {
        if cancelled() {
            // The task kills ffmpeg and answers with the cancel.
            if let Some(stop) = stop.take() {
                let _ = stop.send(());
            }
        }
        match reports.recv_timeout(Duration::from_millis(50)) {
            Ok(Event::Progress(done)) => progress(done),
            Ok(Event::Done(result)) => return result,
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => bail!("ffmpeg's task ended"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn qualities_map_to_each_encoders_settings() {
        assert_eq!(Lossy::Mp3.settings(Quality::High, None), ["-q:a", "2"]);
        assert_eq!(Lossy::Mp3.settings(Quality::Best, None), ["-b:a", "320k"]);
        assert_eq!(Lossy::Vorbis.settings(Quality::Low, None), ["-q:a", "3"]);
        assert_eq!(Lossy::Opus.settings(Quality::Medium, None), ["-b:a", "96k"]);
        assert_eq!(Lossy::Opus.settings(Quality::Low, Some(160)), ["-b:a", "160k"]);
        assert!(Quality::parse("loud").is_err());
        assert_eq!(Quality::parse("High").unwrap(), Quality::High);
    }

    #[test]
    fn opus_and_fast_mp3_ask_for_a_rate_they_can_hold() {
        assert_eq!(Lossy::Opus.rate(44100), Some(48000));
        assert_eq!(Lossy::Opus.rate(48000), None);
        assert_eq!(Lossy::Mp3.rate(96000), Some(48000));
        assert_eq!(Lossy::Mp3.rate(44100), None);
        assert_eq!(Lossy::Vorbis.rate(96000), None);
    }
}
