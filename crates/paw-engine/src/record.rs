//! Capturing a take while recording.
//!
//! The audio thread copies each recorded track's dry input into a ring, and a
//! writer thread per track empties the ring into a WAV file. Notes that reach
//! armed tracks go into another ring for the main thread to collect. Nothing
//! here touches a file on the audio thread.

use std::fs::File;
use std::io::{Seek, SeekFrom, Write};
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use atomic_float::AtomicF64;
use paw_types::EventKind;
use rtrb::{Consumer, Producer};

use crate::bell::Bell;
use crate::slot::TrackSlot;

/// What the engine captures while a take is installed and the transport plays.
/// Built on the main thread and sent over with [`Msg::SetTake`](crate::Msg::SetTake).
pub struct Take {
    pub audio: Vec<AudioCapture>,
    pub midi: Producer<MidiCapture>,
    pub shared: Arc<TakeShared>,
    /// With the loop on, a take goes round with it: every time the song
    /// jumps back to the loop's start, the number of frames captured up to
    /// there is pushed here, for the main thread to cut the take into
    /// passes by.
    pub wraps: Producer<u64>,
    /// Punched in and out: only what is played from the first beat up to
    /// the second is captured, though the song plays on either side. The
    /// engine cuts its blocks at both, so that capturing starts and stops
    /// on the frame.
    pub punch: Option<(f64, f64)>,
    /// Frames captured so far, and times round the loop: the audio thread's own.
    pub frames: u64,
    pub pass: u32,
}

impl Take {
    pub fn new(
        audio: Vec<AudioCapture>,
        midi: Producer<MidiCapture>,
        shared: Arc<TakeShared>,
        wraps: Producer<u64>,
    ) -> Self {
        Self {
            audio,
            midi,
            shared,
            wraps,
            punch: None,
            frames: 0,
            pass: 0,
        }
    }

    /// Whether what is played at `beat` is captured: always, unless the take
    /// is punched and the beat is outside its range.
    pub fn captures_at(&self, beat: f64) -> bool {
        self.punch
            .is_none_or(|(from, to)| beat >= from - PUNCH_EPS && beat < to - PUNCH_EPS)
    }
}

/// How close to a punch point, in beats, counts as on it: a block cut there
/// may start a rounding error short of it.
pub const PUNCH_EPS: f64 = 1e-9;

/// One track's input, copied as it arrives.
pub struct AudioCapture {
    /// First input channel, counting from 0.
    pub first: usize,
    /// 1 or 2. Samples are interleaved when there are two.
    pub channels: usize,
    pub ring: Producer<f32>,
}

/// A note that reached an armed track while recording.
#[derive(Clone, Copy, Debug)]
pub struct MidiCapture {
    pub slot: TrackSlot,
    /// Transport position, in beats, of the block the note was played in.
    pub beat: f64,
    pub kind: EventKind,
    /// Which time round the loop it was played in, from 0.
    pub pass: u32,
}

/// What the audio thread reports about a take.
#[derive(Default)]
pub struct TakeShared {
    start: AtomicF64,
    end: AtomicF64,
    started: AtomicBool,
    closed: AtomicBool,
    dropped: AtomicU64,
    /// A writer could not write: the take should stop.
    failed: AtomicBool,
    /// Writer threads that have not finished their files.
    writing: AtomicU32,
    /// Tells the main loop that the engine let go of the take, or that a
    /// writer finished its file.
    bell: Bell,
}

impl TakeShared {
    /// A take whose news goes to the main loop with `bell`.
    pub fn with_bell(bell: Bell) -> Self {
        Self { bell, ..Self::default() }
    }

    /// Writer threads that have not finished their files.
    pub fn writing(&self) -> u32 {
        self.writing.load(Ordering::Acquire)
    }

    /// Where capturing began, once the transport has played with the take installed.
    pub fn start(&self) -> Option<f64> {
        self.started
            .load(Ordering::Acquire)
            .then(|| self.start.load(Ordering::Relaxed))
    }

    pub(crate) fn begin(&self, beat: f64) {
        if !self.started.load(Ordering::Relaxed) {
            self.start.store(beat, Ordering::Relaxed);
            self.started.store(true, Ordering::Release);
        }
    }

    /// The transport position when the take was removed from the engine.
    pub fn end(&self) -> f64 {
        self.end.load(Ordering::Relaxed)
    }

    /// Whether the engine has let go of the take: nothing more will be captured.
    pub fn closed(&self) -> bool {
        self.closed.load(Ordering::Acquire)
    }

    /// Mark the take finished at `end`. The engine does this when the take is
    /// replaced; the main thread does it if the engine is not running.
    pub fn close(&self, end: f64) {
        if !self.closed.load(Ordering::Relaxed) {
            self.end.store(end, Ordering::Relaxed);
            self.closed.store(true, Ordering::Release);
            // Maybe on the audio thread: a mark, no system call.
            self.bell.mark();
        }
    }

    /// Frames lost because a writer fell behind.
    pub fn dropped(&self) -> u64 {
        self.dropped.load(Ordering::Relaxed)
    }

    pub(crate) fn add_dropped(&self, frames: u64) {
        self.dropped.fetch_add(frames, Ordering::Relaxed);
    }

    /// Whether a writer has stopped on an error (the disk is full, say).
    /// What it wrote before is kept; the take should be stopped.
    pub fn failed(&self) -> bool {
        self.failed.load(Ordering::Acquire)
    }

    fn fail(&self) {
        self.failed.store(true, Ordering::Release);
    }
}

/// What a writer thread did: the frames now in its file, and the error it
/// stopped on, if it stopped early. The file is a complete WAV file either way.
#[derive(Debug, Default)]
pub struct Written {
    pub frames: u64,
    pub error: Option<String>,
}

/// How often a writer brings its file's header up to date and flushes it to
/// the disk, so that a crash or a power cut loses no more than this: on the
/// wall clock, or in the sound it wrote, which the stepped backend of the
/// tests records faster than the wall clock.
pub const HEADER_EVERY: Duration = Duration::from_secs(2);

// paw does not use `hound` for takes (decided). For 32-bit float it writes a
// 68-byte WAVE_FORMAT_EXTENSIBLE header, not 44 bytes, so takes would
// change. It counts the bytes given to its writer, not the bytes the disk
// took, which breaks keeping only whole frames on a full disk. It has no
// fsync. Its sizes are u32.
/// A 32-bit float WAV file written as it is recorded. The header always
/// describes whole frames that are on the disk, up to the last update.
pub struct TakeFile {
    file: File,
    channels: u16,
    /// Bytes of sample data in the file.
    data: u64,
    /// `data` when the header was last written.
    in_header: u64,
}

const HEADER_LEN: u64 = 44;

impl TakeFile {
    pub fn create(path: &Path, sample_rate: u32, channels: u16) -> Result<Self> {
        let file = File::create(path).with_context(|| format!("creating {}", path.display()))?;
        let mut take = Self {
            file,
            channels: channels.max(1),
            data: 0,
            in_header: u64::MAX,
        };
        let block = 4 * take.channels as u32;
        let mut header = Vec::with_capacity(HEADER_LEN as usize);
        header.extend_from_slice(b"RIFF");
        header.extend_from_slice(&36u32.to_le_bytes());
        header.extend_from_slice(b"WAVEfmt ");
        header.extend_from_slice(&16u32.to_le_bytes());
        header.extend_from_slice(&3u16.to_le_bytes()); // IEEE float
        header.extend_from_slice(&take.channels.to_le_bytes());
        header.extend_from_slice(&sample_rate.to_le_bytes());
        header.extend_from_slice(&(sample_rate * block).to_le_bytes());
        header.extend_from_slice(&(block as u16).to_le_bytes());
        header.extend_from_slice(&32u16.to_le_bytes());
        header.extend_from_slice(b"data");
        header.extend_from_slice(&0u32.to_le_bytes());
        take.file
            .write_all(&header)
            .with_context(|| format!("writing {}", path.display()))?;
        take.in_header = 0;
        Ok(take)
    }

    fn frame_bytes(&self) -> u64 {
        4 * self.channels as u64
    }

    /// Frames in the file so far.
    pub fn frames(&self) -> u64 {
        self.data / self.frame_bytes()
    }

    /// Append samples (interleaved). On an error, what the disk took is kept
    /// and counted; a frame cut in two is dropped by [`finish`](Self::finish).
    pub fn write(&mut self, samples: &[f32], bytes: &mut Vec<u8>) -> std::io::Result<()> {
        bytes.clear();
        for sample in samples {
            bytes.extend_from_slice(&sample.to_le_bytes());
        }
        let mut rest = &bytes[..];
        while !rest.is_empty() {
            match self.file.write(rest) {
                Ok(0) => return Err(std::io::ErrorKind::WriteZero.into()),
                Ok(n) => {
                    self.data += n as u64;
                    rest = &rest[n..];
                }
                Err(err) if err.kind() == std::io::ErrorKind::Interrupted => {}
                Err(err) => return Err(err),
            }
        }
        Ok(())
    }

    /// Bring the header up to date with the whole frames written so far and
    /// flush the file to the disk.
    pub fn update(&mut self) -> std::io::Result<()> {
        let data = self.frames() * self.frame_bytes();
        if data != self.in_header {
            let size = data.min(u32::MAX as u64 - 36) as u32;
            self.file.seek(SeekFrom::Start(4))?;
            self.file.write_all(&(size + 36).to_le_bytes())?;
            self.file.seek(SeekFrom::Start(40))?;
            self.file.write_all(&size.to_le_bytes())?;
            self.file.seek(SeekFrom::Start(HEADER_LEN + self.data))?;
            self.in_header = data;
        }
        self.file.sync_data()
    }

    /// Cut off a frame left half written, and write the final header.
    pub fn finish(mut self) -> std::io::Result<u64> {
        let whole = self.frames() * self.frame_bytes();
        if whole != self.data {
            self.file.set_len(HEADER_LEN + whole)?;
            self.data = whole;
        }
        self.update()?;
        Ok(self.frames())
    }
}

/// Create a 32-bit float WAV file and write whatever arrives in `ring` into it
/// until the take is closed and the ring is empty. Every [`HEADER_EVERY`] the
/// header is brought up to date and the file flushed to the disk. On a write
/// error the writer stops, keeps what it wrote, finishes the file and marks
/// the take [`failed`](TakeShared::failed).
pub fn spawn_writer(
    path: &Path,
    sample_rate: u32,
    channels: u16,
    mut ring: Consumer<f32>,
    shared: Arc<TakeShared>,
) -> Result<JoinHandle<Written>> {
    let mut file = TakeFile::create(path, sample_rate, channels)?;
    shared.writing.fetch_add(1, Ordering::AcqRel);
    /// Says that the writer finished, at the end of the thread's work
    /// however it ends: the count first, then the bell.
    struct Finished(Arc<TakeShared>);
    impl Drop for Finished {
        fn drop(&mut self) {
            self.0.writing.fetch_sub(1, Ordering::AcqRel);
            self.0.bell.ring();
        }
    }
    let finished = Finished(shared.clone());
    let thread = std::thread::Builder::new()
        .name("paw-recorder".into())
        .spawn(move || {
            let _finished = finished;
            let mut buf = vec![0f32; 16384];
            let mut bytes = Vec::with_capacity(buf.len() * 4);
            let mut updated = Instant::now();
            let every_frames = u64::from(sample_rate) * HEADER_EVERY.as_secs();
            let mut updated_frames = 0;
            let mut error = None;
            loop {
                // Read the flag first: whatever was captured before it was set
                // is in the ring by now.
                let closed = shared.closed();
                let (got, _) = ring.pop_partial_slice(&mut buf);
                let empty = got.is_empty();
                let written = file.write(got, &mut bytes).and_then(|()| {
                    if updated.elapsed() >= HEADER_EVERY
                        || file.frames() - updated_frames >= every_frames
                    {
                        updated = Instant::now();
                        updated_frames = file.frames();
                        file.update()?;
                    }
                    Ok(())
                });
                if let Err(err) = written {
                    error = Some(err.to_string());
                    shared.fail();
                    break;
                }
                if empty {
                    if closed {
                        break;
                    }
                    std::thread::sleep(Duration::from_millis(5));
                }
            }
            let frames = file.frames();
            match file.finish() {
                Ok(frames) => Written { frames, error },
                Err(err) => Written {
                    frames,
                    error: error.or(Some(err.to_string())),
                },
            }
        })?;
    Ok(thread)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::clip::AudioData;
    use std::process::Command;

    /// Feed one second at a time into a writer until it stops or `seconds` pass.
    fn record(path: &Path, seconds: usize) -> Written {
        let shared = Arc::new(TakeShared::default());
        let (mut tx, rx) = rtrb::RingBuffer::new(48000 * 4);
        let thread = spawn_writer(path, 48000, 1, rx, shared.clone()).unwrap();
        let second: Vec<f32> = (0..48000).map(|i| (i as f32 * 0.05).sin() * 0.5).collect();
        for _ in 0..seconds {
            if shared.failed() {
                break;
            }
            let mut rest = &second[..];
            while !rest.is_empty() && !shared.failed() {
                let n = tx.slots().min(rest.len());
                if let Ok(chunk) = tx.write_chunk_uninit(n) {
                    chunk.fill_from_iter(rest[..n].iter().copied());
                }
                rest = &rest[n..];
                std::thread::sleep(Duration::from_millis(1));
            }
        }
        shared.close(0.0);
        thread.join().unwrap()
    }

    /// Run in a child process whose files may not grow past 300 kB, as on a
    /// full disk: the write fails with EFBIG. The child sets the limit itself.
    #[test]
    fn a_write_error_keeps_what_was_written_as_a_whole_file() {
        let dir = std::env::temp_dir().join(format!("paw-record-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("take.wav");
        let mut child = Command::new(std::env::current_exe().unwrap());
        child
            .args([
                "--exact",
                "record::tests::child_writes_until_the_limit",
                "--nocapture",
            ])
            .env("PAW_TAKE_LIMITED", &path);
        let out = child.output().unwrap();
        let stdout = String::from_utf8_lossy(&out.stdout);
        assert!(
            out.status.success(),
            "{stdout}\n{}",
            String::from_utf8_lossy(&out.stderr)
        );
        assert!(stdout.contains("1 passed"), "the child ran: {stdout}");
        let data = AudioData::load(&path).expect("the file reads as a WAV file");
        let frames = (300_000 - 44) / 4;
        assert_eq!(
            data.frames(),
            frames,
            "every whole frame that fitted is kept"
        );
        assert!((data.channels[0][1000] - (1000f32 * 0.05).sin() * 0.5).abs() < 1e-6);
    }

    #[test]
    fn child_writes_until_the_limit() {
        let Some(path) = std::env::var_os("PAW_TAKE_LIMITED") else {
            return;
        };
        // rustix cannot set a signal disposition and signal-hook cannot set
        // SIG_IGN, so libc does it here. This is plain test code in the
        // child, not a pre_exec hook. Without it SIGXFSZ kills the process
        // instead of failing the write with EFBIG.
        // SAFETY: signal with SIG_IGN has no handler and no preconditions.
        unsafe {
            libc::signal(libc::SIGXFSZ, libc::SIG_IGN);
        }
        rustix::process::setrlimit(
            rustix::process::Resource::Fsize,
            rustix::process::Rlimit {
                current: Some(300_000),
                maximum: Some(300_000),
            },
        )
        .unwrap();
        let written = record(Path::new(&path), 10);
        let error = written.error.expect("the writer stopped on the error");
        assert!(error.contains("too large"), "{error}");
        assert_eq!(written.frames, (300_000 - 44) / 4);
    }

    #[test]
    fn a_writer_rings_its_bell_when_it_ends_and_a_close_only_marks_it() {
        use std::sync::atomic::{AtomicU32, AtomicUsize};
        let dir = std::env::temp_dir().join(format!("paw-record-bell-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let bits = Arc::new(AtomicU32::new(0));
        let rings = Arc::new(AtomicUsize::new(0));
        let rung = rings.clone();
        let ringer = Arc::new(move || {
            rung.fetch_add(1, Ordering::AcqRel);
        });
        let shared = Arc::new(TakeShared::with_bell(Bell::new(bits.clone(), 1, ringer)));
        let (_tx, rx) = rtrb::RingBuffer::new(16);
        let thread = spawn_writer(&dir.join("take.wav"), 48000, 1, rx, shared.clone()).unwrap();
        assert_eq!(shared.writing(), 1, "the writer is counted as it starts");
        shared.close(0.0);
        thread.join().unwrap();
        assert_eq!(shared.writing(), 0, "the count is down before the ring");
        assert_eq!(crate::bell::bits_of(bits.load(Ordering::Acquire)), 1, "a mark and a ring of one kind");
        assert_eq!(rings.load(Ordering::Acquire), 1, "the close of the audio thread rings nothing");
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn the_header_is_kept_up_to_date_while_recording() {
        let dir = std::env::temp_dir().join(format!("paw-record-hdr-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("take.wav");
        let shared = Arc::new(TakeShared::default());
        let (mut tx, rx) = rtrb::RingBuffer::new(48000 * 4);
        let thread = spawn_writer(&path, 48000, 2, rx, shared.clone()).unwrap();
        let block = vec![0.25f32; 9600];
        let started = Instant::now();
        while started.elapsed() < HEADER_EVERY + Duration::from_millis(600) {
            if let Ok(chunk) = tx.write_chunk_uninit(block.len().min(tx.slots())) {
                chunk.fill_from_iter(block.iter().copied());
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        // As a crash would leave it: read while the writer is still going.
        let data = AudioData::load(&path).expect("readable mid-take");
        assert!(
            data.seconds() > 1.5,
            "{} s are in the header",
            data.seconds()
        );
        shared.close(0.0);
        let written = thread.join().unwrap();
        assert!(written.error.is_none());
        assert_eq!(
            AudioData::load(&path).unwrap().frames() as u64,
            written.frames
        );
    }
}
