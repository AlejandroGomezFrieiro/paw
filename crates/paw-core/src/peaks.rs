//! Waveform overviews of audio files, for drawing clips.
//!
//! An overview is made once per file and kept on disk in the cache directory
//! (`~/.cache/paw/peaks`), named after the file's path, size and time of
//! last change, so that drawing a long file zoomed out after the first time
//! reads the overview and not the file.

use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use paw_engine::AudioData;

/// Frames covered by each entry of a [`Summary`].
const BLOCK: usize = 256;

/// The lowest and highest sample of each run of [`BLOCK`] frames and the
/// mean of their squares, both channels together, so that drawing a long
/// file zoomed out reads a fraction of its samples.
pub struct Summary {
    blocks: Vec<[f32; 3]>,
    pub frames: usize,
    pub sample_rate: u32,
}

/// What a stored overview starts with: a name and a version.
const MAGIC: &[u8; 8] = b"PAWPKS01";

impl Summary {
    pub fn new(data: &AudioData) -> Self {
        let blocks = (0..data.frames().div_ceil(BLOCK))
            .map(|b| scan(data, b * BLOCK, ((b + 1) * BLOCK).min(data.frames())))
            .collect();
        Self {
            blocks,
            frames: data.frames(),
            sample_rate: data.sample_rate,
        }
    }

    /// An overview stored by [`write`](Self::write), or `None` when there
    /// is none or it cannot be read.
    pub fn read(path: &Path) -> Option<Self> {
        let mut bytes = Vec::new();
        std::fs::File::open(path)
            .ok()?
            .read_to_end(&mut bytes)
            .ok()?;
        let body = bytes.strip_prefix(MAGIC)?;
        let (head, body) = body.split_at_checked(20)?;
        let sample_rate = u32::from_le_bytes(head[..4].try_into().ok()?);
        let frames = u64::from_le_bytes(head[4..12].try_into().ok()?) as usize;
        let count = u64::from_le_bytes(head[12..20].try_into().ok()?) as usize;
        if count != frames.div_ceil(BLOCK) || body.len() != count * 12 || sample_rate == 0 {
            return None;
        }
        let blocks = body
            .chunks_exact(12)
            .map(|c| {
                let f = |i: usize| f32::from_le_bytes(c[i..i + 4].try_into().expect("4 bytes"));
                [f(0), f(4), f(8)]
            })
            .collect();
        Some(Self {
            blocks,
            frames,
            sample_rate,
        })
    }

    /// Keep the overview in a file, whole or not at all.
    pub fn write(&self, path: &Path) -> std::io::Result<()> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let mut bytes = Vec::with_capacity(28 + self.blocks.len() * 12);
        bytes.extend_from_slice(MAGIC);
        bytes.extend_from_slice(&self.sample_rate.to_le_bytes());
        bytes.extend_from_slice(&(self.frames as u64).to_le_bytes());
        bytes.extend_from_slice(&(self.blocks.len() as u64).to_le_bytes());
        for block in &self.blocks {
            for v in block {
                bytes.extend_from_slice(&v.to_le_bytes());
            }
        }
        let tmp = path.with_extension(format!("{}.part", std::process::id()));
        std::fs::File::create(&tmp)?.write_all(&bytes)?;
        std::fs::rename(&tmp, path)
    }
}

/// Where the overview of `file` as it is now is kept under `dir`, and the
/// identity it is kept by (path, size and time of last change).
/// `None` when the file is not there to be known by.
pub fn stored(dir: &Path, file: &Path) -> Option<(PathBuf, u64)> {
    use std::os::unix::ffi::OsStrExt;
    let file = std::path::absolute(file).unwrap_or_else(|_| file.to_path_buf());
    let meta = std::fs::metadata(&file).ok().filter(|m| m.is_file())?;
    let size = meta.len();
    let modified = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_nanos());
    // FNV-1a over the identity: the same file as it was gives the same name.
    let mut hash = 0xcbf2_9ce4_8422_2325u64;
    let mut eat = |bytes: &[u8]| {
        for b in bytes {
            hash = (hash ^ *b as u64).wrapping_mul(0x100_0000_01b3);
        }
    };
    eat(file.as_os_str().as_bytes());
    eat(&size.to_le_bytes());
    eat(&modified.to_le_bytes());
    Some((dir.join(format!("{hash:016x}.peaks")), hash))
}

/// The cache directory overviews are kept in: `$XDG_CACHE_HOME/paw/peaks`.
pub fn cache_dir() -> PathBuf {
    paw_proto::dirs::cache()
        .unwrap_or_else(std::env::temp_dir)
        .join("paw")
        .join("peaks")
}

/// The cache directory the decoded sound of long files is kept in and
/// played from: `$XDG_CACHE_HOME/paw/media`.
pub fn media_dir() -> PathBuf {
    cache_dir().with_file_name("media")
}

/// As [`peaks`], from the overview alone, when each point covers at least a
/// block; `None` when zoomed in further, where the samples are needed.
pub fn coarse(summary: &Summary, from: f64, to: f64, n: usize) -> Option<Vec<[f32; 3]>> {
    let step = (to - from) / n as f64;
    if n == 0 || step < BLOCK as f64 {
        return None;
    }
    let count = summary.blocks.len();
    let at = |i: usize| ((from + step * i as f64).max(0.0) as usize / BLOCK).min(count);
    Some(
        (0..n)
            .map(|i| {
                let (start, end) = (at(i), at(i + 1).max(at(i) + 1).min(count));
                if start >= end || start * BLOCK >= summary.frames {
                    return [0.0, 0.0, 0.0];
                }
                let mut range = [f32::INFINITY, f32::NEG_INFINITY];
                let mut squares = 0.0f64;
                for block in &summary.blocks[start..end] {
                    range = [range[0].min(block[0]), range[1].max(block[1])];
                    squares += block[2] as f64;
                }
                let rms = (squares / (end - start) as f64).sqrt() as f32;
                [range[0], range[1], rms]
            })
            .collect(),
    )
}

/// The lowest sample, the highest, and the mean of the squares of the
/// frames `from..to`.
fn scan(data: &AudioData, from: usize, to: usize) -> [f32; 3] {
    let mut range = [f32::INFINITY, f32::NEG_INFINITY];
    let (mut squares, mut count) = (0.0f64, 0usize);
    for channel in &data.channels {
        for &s in &channel[from..to] {
            range = [range[0].min(s), range[1].max(s)];
            squares += (s * s) as f64;
            count += 1;
        }
    }
    let mean = if count > 0 {
        squares / count as f64
    } else {
        0.0
    };
    [range[0], range[1], mean as f32]
}

/// `n` (min, max, rms) triples, each covering an equal part of the frames
/// `from..to`: where the waveform reaches, and how loud it is there, which
/// is what its body looks like. Frames past the end of the file are
/// silence. A part narrower than a frame shows the frame it falls in, so
/// zooming in past the samples still draws.
pub fn peaks(data: &AudioData, summary: &Summary, from: f64, to: f64, n: usize) -> Vec<[f32; 3]> {
    let frames = data.frames();
    let step = (to - from) / n as f64;
    let at = |i: usize| (from + step * i as f64).floor().max(0.0) as usize;
    (0..n)
        .map(|i| {
            let start = at(i).min(frames);
            let end = at(i + 1).max(start + 1).min(frames);
            if start >= end {
                return [0.0, 0.0, 0.0];
            }
            // Partial blocks at either end come from the samples, whole ones
            // in between from the summary.
            let head = end.min(start.next_multiple_of(BLOCK));
            let tail = head.max(end / BLOCK * BLOCK);
            let first = scan(data, start, head);
            let mut range = [first[0], first[1]];
            // Squares are added up by how many frames each part covers.
            let mut squares = first[2] as f64 * (head - start) as f64;
            for block in &summary.blocks[head / BLOCK..tail / BLOCK] {
                range = [range[0].min(block[0]), range[1].max(block[1])];
                squares += block[2] as f64 * BLOCK as f64;
            }
            let last = scan(data, tail, end);
            squares += last[2] as f64 * (end - tail) as f64;
            let rms = (squares / (end - start) as f64).sqrt() as f32;
            [range[0].min(last[0]), range[1].max(last[1]), rms]
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sync::AudioCache;

    #[test]
    fn an_overview_is_kept_on_disk_and_used_without_decoding_the_file() {
        let dir = std::env::temp_dir().join(format!("paw-peaks-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let wav = dir.join("tone.wav");
        let write = |level: f32| {
            let mut w = paw_engine::wav::Writer::create(&wav, 48_000, 16, false).unwrap();
            for i in 0..48_000 * 4 {
                let s = level * (i as f32 * 0.05).sin();
                w.write(s).unwrap();
                w.write(s).unwrap();
            }
            w.finish().unwrap();
        };
        write(0.5);
        let store = dir.join("peaks");
        let mut cache = AudioCache::with_peak_dir(store.clone());
        let first = cache.peaks(&wav, 0.0, 4.0, 100).unwrap();
        assert!((first[50][1] - 0.5).abs() < 0.01, "{:?}", first[50]);
        assert_eq!(
            std::fs::read_dir(&store).unwrap().count(),
            1,
            "one overview is kept"
        );

        // Another run, with the samples changed behind its back but the
        // file's size and time of change put back: what is drawn comes from
        // the overview, not from the samples.
        let modified = std::fs::metadata(&wav).unwrap().modified().unwrap();
        write(0.25);
        std::fs::File::options()
            .write(true)
            .open(&wav)
            .unwrap()
            .set_modified(modified)
            .unwrap();
        let mut again = AudioCache::with_peak_dir(store.clone());
        let second = again.peaks(&wav, 0.0, 4.0, 100).unwrap();
        assert!(
            (second[50][1] - 0.5).abs() < 0.01,
            "drawn from the stored overview: {:?}",
            second[50]
        );

        // A file changed in the ordinary way is looked at again.
        std::fs::File::options()
            .write(true)
            .open(&wav)
            .unwrap()
            .set_modified(modified + std::time::Duration::from_secs(5))
            .unwrap();
        let mut third = AudioCache::with_peak_dir(store.clone());
        let changed = third.peaks(&wav, 0.0, 4.0, 100).unwrap();
        assert!((changed[50][1] - 0.25).abs() < 0.01, "{:?}", changed[50]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_overview_alone_draws_what_the_samples_do_when_zoomed_out() {
        let data = AudioData {
            sample_rate: 48_000,
            channels: [
                (0..100_000)
                    .map(|i| ((i as f32) * 0.01).sin() * 0.8)
                    .collect::<Vec<f32>>()
                    .into(),
                vec![0.0; 100_000].into(),
            ],
        };
        let summary = Summary::new(&data);
        let exact = peaks(&data, &summary, 0.0, 100_000.0, 50);
        let rough = coarse(&summary, 0.0, 100_000.0, 50).unwrap();
        for (a, b) in exact.iter().zip(&rough) {
            assert!(
                (a[0] - b[0]).abs() < 0.05 && (a[1] - b[1]).abs() < 0.05,
                "{a:?} {b:?}"
            );
        }
        assert!(
            coarse(&summary, 0.0, 1000.0, 50).is_none(),
            "zoomed in, it needs the samples"
        );
    }
}
