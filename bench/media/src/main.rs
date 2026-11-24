//! Numbers for the media design (bench/media.md): stretch speed per mode,
//! decode speed, BLAKE3 on warm and cold files, `stat` of many files.
//!
//! Each case runs REPS times (default 7); a line gives the median and the
//! min-max. Run it under `taskset` and `flock` (see bench/media.md).
//!
//!   media-bench stretch
//!   media-bench decode <file>...
//!   media-bench hash <file>...
//!   media-bench stat <folder>        (a folder of many small files)

use std::fs::File;
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;
use std::time::Instant;

use paw_core::stretch::{self, Mode, Params};
use paw_engine::{AudioData, Sink};
use symphonia::core::codecs::audio::AudioDecoderOptions;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, PartType};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;

fn reps() -> usize {
    std::env::var("REPS").ok().and_then(|s| s.parse().ok()).unwrap_or(7)
}

/// Runs `f` REPS times; each run gives a value; prints median and range.
fn measure(label: &str, unit: &str, mut f: impl FnMut() -> f64) {
    let mut v: Vec<f64> = (0..reps()).map(|_| f()).collect();
    v.sort_by(|a, b| a.total_cmp(b));
    let median = v[v.len() / 2];
    println!(
        "{label:<46} median {median:>10.1} {unit}  min-max {:.1}-{:.1}  (n={})",
        v[0],
        v[v.len() - 1],
        v.len()
    );
}

fn secs(t: Instant) -> f64 {
    t.elapsed().as_secs_f64()
}

fn load_avg() -> String {
    std::fs::read_to_string("/proc/loadavg").unwrap_or_default().trim().to_string()
}

/// Evicts the file's pages from the page cache (needs no privilege for
/// clean pages).
fn evict(path: &Path) {
    let f = File::open(path).unwrap();
    // SAFETY: a valid descriptor, a whole-file advice.
    unsafe { libc::posix_fadvise(f.as_raw_fd(), 0, 0, libc::POSIX_FADV_DONTNEED) };
}

// ---------------------------------------------------------------- stretch

/// A minute of music-like sound at 44.1 kHz: chords with a slow decay and
/// a noisy drum hit on each beat (120 BPM), a little different in each channel.
fn music(seconds: f64) -> AudioData {
    let rate = 44_100u32;
    let n = (seconds * rate as f64) as usize;
    let mut seed = 1u32;
    let mut noise = move || {
        seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        (seed >> 8) as f32 / (1u32 << 24) as f32 - 0.5
    };
    let chords = [[220.0, 277.2, 329.6], [196.0, 246.9, 293.7], [174.6, 220.0, 261.6], [196.0, 246.9, 392.0]];
    let mut left = vec![0.0f32; n];
    let mut right = vec![0.0f32; n];
    let beat = rate as usize / 2;
    let mut hit = 0.0f32;
    for i in 0..n {
        let t = i as f64 / rate as f64;
        if i % beat == 0 {
            hit = 1.0;
        }
        hit *= 0.9992;
        let chord = &chords[(t / 2.0) as usize % chords.len()];
        let env = (-(t % 2.0) * 0.8).exp() as f32;
        let mut tone = 0.0f32;
        for f in chord {
            for h in 1..=4 {
                tone += ((std::f64::consts::TAU * f * h as f64 * t).sin() as f32) / (h * h) as f32;
            }
        }
        let drum = noise() * hit * 0.5;
        left[i] = tone * env * 0.15 + drum;
        right[i] = tone * env * 0.13 + noise() * hit * 0.4;
    }
    AudioData { sample_rate: rate, channels: [left.into(), right.into()] }
}

fn run_stretch() {
    let data = music(60.0);
    println!("stretch: 60 s stereo 44.1 kHz synthetic music; speed = output seconds per wall second");
    println!("auto picks: {}", stretch::choose(&data).name());
    let cancel = AtomicBool::new(false);
    for (mode, ratio, semis) in [
        (Mode::Tonal, 0.5, 0.0),
        (Mode::Tonal, 1.25, 0.0),
        (Mode::Tonal, 2.0, 0.0),
        (Mode::Tonal, 1.0, 3.0),
        (Mode::Percussive, 0.5, 0.0),
        (Mode::Percussive, 1.25, 0.0),
        (Mode::Percussive, 2.0, 0.0),
        (Mode::Percussive, 1.0, 3.0),
        (Mode::Auto, 1.25, 0.0),
    ] {
        let params = Params::even(ratio, semis, mode);
        measure(&format!("{} ratio {ratio} pitch {semis:+}", mode.name()), "x real time", || {
            let t = Instant::now();
            let out = stretch::render(&data, &params, Sink::memory(), &cancel).unwrap();
            let wall = secs(t);
            out.seconds() / wall
        });
    }
    let mut formants = Params::even(1.0, 3.0, Mode::Tonal);
    formants.formants = true;
    measure("tonal pitch +3 with formants", "x real time", || {
        let t = Instant::now();
        let out = stretch::render(&data, &formants, Sink::memory(), &cancel).unwrap();
        out.seconds() / secs(t)
    });
}

// ----------------------------------------------------------------- decode

/// Decodes a whole file with symphonia to planar f32 (what paw's loader
/// does), returns the audio seconds.
fn decode_file(path: &Path) -> f64 {
    let file = File::open(path).unwrap();
    let stream = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(e) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(e);
    }
    let mut format = symphonia::default::get_probe()
        .probe(&hint, stream, FormatOptions::default(), MetadataOptions::default())
        .unwrap();
    let part = format.default_part(PartType::Audio).unwrap();
    let params = part.codec_params.as_ref().and_then(|p| p.audio()).unwrap().clone();
    let id = part.id;
    let mut decoder = symphonia::default::get_codecs()
        .make_audio_decoder(&params, &AudioDecoderOptions::default())
        .unwrap();
    let mut planes: Vec<Vec<f32>> = Vec::new();
    let mut frames = 0usize;
    let mut rate = 0;
    while let Ok(Some(packet)) = format.next_packet() {
        if packet.part_id != id {
            continue;
        }
        if let Ok(buf) = decoder.decode(&packet) {
            rate = buf.spec().rate();
            buf.copy_to_vecs_planar(&mut planes);
            frames += planes[0].len();
        }
    }
    frames as f64 / rate.max(1) as f64
}

fn run_decode(files: &[PathBuf]) {
    println!("decode: whole file to f32 planes, warm page cache; speed = audio seconds per wall second");
    for path in files {
        let name = path.file_name().unwrap().to_string_lossy().into_owned();
        measure(&format!("symphonia {name}"), "x real time", || {
            let t = Instant::now();
            let audio = decode_file(path);
            audio / secs(t)
        });
        if matches!(path.extension().and_then(|e| e.to_str()), Some("flac" | "mp3" | "wav")) {
            measure(&format!("AudioData::load {name}"), "x real time", || {
                let t = Instant::now();
                let d = AudioData::load(path).unwrap();
                d.seconds() / secs(t)
            });
        }
    }
}

// ------------------------------------------------------------------- hash

fn run_hash(files: &[PathBuf]) {
    println!("hash: MB/s of file size");
    for path in files {
        let name = path.file_name().unwrap().to_string_lossy().into_owned();
        let size = std::fs::metadata(path).unwrap().len();
        let mb = size as f64 / 1e6;
        println!("{name}: {mb:.1} MB");
        let read_all = |p: &Path| std::fs::read(p).unwrap();
        // Warm: one thread, one thread through mmap, all threads through mmap.
        measure(&format!("{name} warm, read + hash, 1 thread"), "MB/s", || {
            let t = Instant::now();
            let h = blake3::hash(&read_all(path));
            std::hint::black_box(h);
            mb / secs(t)
        });
        measure(&format!("{name} warm, update_reader, 1 thread"), "MB/s", || {
            let t = Instant::now();
            let mut h = blake3::Hasher::new();
            h.update_reader(File::open(path).unwrap()).unwrap();
            std::hint::black_box(h.finalize());
            mb / secs(t)
        });
        measure(&format!("{name} warm, mmap, 1 thread"), "MB/s", || {
            let t = Instant::now();
            let mut h = blake3::Hasher::new();
            h.update_mmap(path).unwrap();
            std::hint::black_box(h.finalize());
            mb / secs(t)
        });
        measure(&format!("{name} warm, mmap + rayon"), "MB/s", || {
            let t = Instant::now();
            std::hint::black_box(paw_core::media::hash::file(path).unwrap());
            mb / secs(t)
        });
        measure(&format!("{name} cold, update_reader, 1 thread"), "MB/s", || {
            evict(path);
            let t = Instant::now();
            let mut h = blake3::Hasher::new();
            h.update_reader(File::open(path).unwrap()).unwrap();
            std::hint::black_box(h.finalize());
            mb / secs(t)
        });
        measure(&format!("{name} cold, mmap + rayon"), "MB/s", || {
            evict(path);
            let t = Instant::now();
            std::hint::black_box(paw_core::media::hash::file(path).unwrap());
            mb / secs(t)
        });
        measure(&format!("{name} cold, start to finish"), "ms", || {
            evict(path);
            let t = Instant::now();
            std::hint::black_box(paw_core::media::hash::file(path).unwrap());
            secs(t) * 1e3
        });
    }
}

// ------------------------------------------------------------------- stat

fn run_stat(dir: &Path) {
    let mut paths: Vec<PathBuf> = std::fs::read_dir(dir)
        .unwrap()
        .map(|e| e.unwrap().path())
        .collect();
    paths.sort();
    println!("stat: {} files in a folder, warm dentry and inode caches", paths.len());
    measure("read_dir + collect", "ms", || {
        let t = Instant::now();
        let n = std::fs::read_dir(dir).unwrap().count();
        std::hint::black_box(n);
        secs(t) * 1e3
    });
    measure("fs::metadata of each (size, mtime)", "ms", || {
        let t = Instant::now();
        let mut total = 0u64;
        for p in &paths {
            total += std::fs::metadata(p).unwrap().len();
        }
        std::hint::black_box(total);
        secs(t) * 1e3
    });
    measure("read_dir entries + metadata of each", "ms", || {
        let t = Instant::now();
        let mut total = 0u64;
        for e in std::fs::read_dir(dir).unwrap() {
            total += e.unwrap().metadata().unwrap().len();
        }
        std::hint::black_box(total);
        secs(t) * 1e3
    });
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    println!("load average at start: {}", load_avg());
    let rest: Vec<PathBuf> = args.iter().skip(2).map(PathBuf::from).collect();
    match args.get(1).map(String::as_str) {
        Some("stretch") => run_stretch(),
        Some("decode") => run_decode(&rest),
        Some("hash") => run_hash(&rest),
        Some("stat") => run_stat(&rest[0]),
        _ => eprintln!("usage: media-bench stretch | decode <file>... | hash <file>... | stat <folder>"),
    }
    println!("load average at end: {}", load_avg());
}
