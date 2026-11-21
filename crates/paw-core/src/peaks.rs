//! Waveform overviews of audio files, for drawing clips.
//!
//! An overview is made once per file and kept in the bake cache
//! (`bake::Store`), keyed by the hash of the file's bytes, so that drawing a
//! long file zoomed out after the first time reads the overview and not the
//! file, wherever the file is now.

use std::io::Read;
use std::path::{Path, PathBuf};

use paw_engine::AudioData;

use crate::bake::{BakeJob, EntryKey, Input, Output, Stream};
use crate::media::SourceHash;

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

    /// Keep the overview in a file (of a bake entry, which is put in
    /// place whole).
    pub fn write(&self, path: &Path) -> std::io::Result<()> {
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
        std::fs::write(path, bytes)
    }
}

/// Who makes overviews: a new form of [`Summary`] is a new tool.
pub const TOOL: &str = "paw.peaks/1";

/// The file of an overview in its bake entry.
pub const FILE: &str = "peaks.bin";

/// The bake of the overview of the file whose bytes hash to `source`, and
/// its key.
pub fn bake(source: SourceHash) -> (BakeJob, EntryKey) {
    let job = BakeJob {
        op: "peaks".into(),
        version: 1,
        params: serde_json::json!({ "block": BLOCK }),
        inputs: vec![Input::File { source }],
        output: Output {
            stream: Stream::Data,
            rate: None,
            format: Some("peaks".into()),
        },
    };
    let key = EntryKey::new(&job, TOOL);
    (job, key)
}

/// The cache directory the decoded sound of long files is kept in and
/// played from: `$XDG_CACHE_HOME/paw/media`.
pub fn media_dir() -> PathBuf {
    paw_proto::dirs::cache()
        .unwrap_or_else(std::env::temp_dir)
        .join("paw")
        .join("media")
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
    use crate::bake::Store;
    use crate::sync::AudioCache;

    #[test]
    fn an_overview_is_kept_by_the_bytes_of_the_file_wherever_it_is() {
        let dir = tempfile::tempdir().unwrap();
        let wav = dir.path().join("tone.wav");
        let write = |wav: &Path, level: f32| {
            let mut w = paw_engine::wav::Writer::create(wav, 48_000, 16, false).unwrap();
            for i in 0..48_000 * 4 {
                let s = level * (i as f32 * 0.05).sin();
                w.write(s).unwrap();
                w.write(s).unwrap();
            }
            w.finish().unwrap();
        };
        write(&wav, 0.5);
        let store = Store::new(dir.path().join("bakes"), crate::bake::store::DEFAULT_LIMIT);
        let entries = || store.tidy(&Default::default()).kept;
        let source = SourceHash::of_file(&wav).unwrap();
        let first = AudioCache::with_bakes(store.clone()).peaks(&wav, Some(source), 0.0, 4.0, 100).unwrap();
        assert!((first[50][1] - 0.5).abs() < 0.01, "{:?}", first[50]);
        let one = entries();
        assert!(one > 0, "one overview is kept");

        // The entry holds what is drawn: put another overview in it, then
        // move the file. Drawn zoomed out, the moved file shows the entry.
        let entry = store.open(&bake(source).1).unwrap();
        let quiet = dir.path().join("quiet.wav");
        write(&quiet, 0.25);
        let data = AudioData::load_with(&quiet, None).unwrap();
        Summary::new(&data).write(&entry.file(FILE)).unwrap();
        let moved = dir.path().join("moved").join("tone.wav");
        std::fs::create_dir_all(moved.parent().unwrap()).unwrap();
        std::fs::rename(&wav, &moved).unwrap();
        let again = AudioCache::with_bakes(store.clone()).peaks(&moved, Some(source), 0.0, 4.0, 100).unwrap();
        assert!((again[50][1] - 0.25).abs() < 0.01, "drawn from the entry: {:?}", again[50]);
        assert_eq!(entries(), one, "no second entry");
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
