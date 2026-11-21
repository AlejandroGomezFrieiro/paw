//! What a bake is known by: its job as canonical JSON, hashed.
//!
//! ```text
//! input_key = H( "paw.bake/1\n" ‖ canonical_json(job) )
//! entry     = hex( H( input_key ‖ tool )[0..16] )
//! ```
//!
//! The job names its sources by the hash of their bytes, never by a path,
//! so a moved or copied file finds its entries again. `tool` names who made
//! the entry ("paw.peaks/1"): a new baker is a new entry, never a wrong one.
//!
//! `H` is [`Hasher`]: SHA-256 (`ring`, linked already) until the workspace
//! has `blake3`; the switch is the one type, and it changes every key, which
//! only costs the cache.

use std::fmt;
use std::io::Read;
use std::path::Path;

use serde::Serialize;
use serde_json::Value;

/// The format of a key: a change of the canonical form is a new prefix.
const PREFIX: &[u8] = b"paw.bake/1\n";

/// The hash of keys and sources. The one place that names the algorithm.
pub struct Hasher(ring::digest::Context);

impl Hasher {
    pub fn new() -> Self {
        Self(ring::digest::Context::new(&ring::digest::SHA256))
    }

    pub fn update(&mut self, bytes: &[u8]) {
        self.0.update(bytes);
    }

    pub fn finish(self) -> Digest {
        let mut out = [0u8; 32];
        out.copy_from_slice(self.0.finish().as_ref());
        Digest(out)
    }

    /// The hash of a file's bytes, read in pieces.
    pub fn file(path: &Path) -> std::io::Result<Digest> {
        let mut file = std::fs::File::open(path)?;
        let mut hasher = Self::new();
        let mut buf = vec![0u8; 1 << 20];
        loop {
            match file.read(&mut buf)? {
                0 => return Ok(hasher.finish()),
                n => hasher.update(&buf[..n]),
            }
        }
    }
}

impl Default for Hasher {
    fn default() -> Self {
        Self::new()
    }
}

/// 32 bytes of [`Hasher`]: a source's identity, or a job's input key.
/// Written as 64 hex digits.
#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Digest(pub [u8; 32]);

impl fmt::Display for Digest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.iter().try_for_each(|b| write!(f, "{b:02x}"))
    }
}

impl fmt::Debug for Digest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Display::fmt(self, f)
    }
}

impl Serialize for Digest {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_str(self)
    }
}

/// The kind of output of a bake.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Stream {
    Sound,
    Picture,
    Data,
}

/// What a bake makes.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Output {
    pub stream: Stream,
    /// Frames a second of sound or picture.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rate: Option<u32>,
    /// The form of a data output ("peaks"), or of a helper's file.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub format: Option<String>,
}

/// One input of a bake.
#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(untagged)]
pub enum Input {
    /// A whole source file, by the hash of its bytes.
    File { source: Digest },
    /// A range of frames of one stream of a source.
    Range {
        hash: Digest,
        stream: u16,
        from: u64,
        to: u64,
        reverse: bool,
    },
    /// The output of another bake: keys chain.
    Bake { key: Digest },
}

/// Everything a bake needs, and nothing else: the key is the hash of this.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct BakeJob {
    /// "peaks", "stretch", "video.proxy".
    pub op: String,
    /// Of the op's meaning.
    pub version: u32,
    /// The op's parameters: plain data.
    pub params: Value,
    pub inputs: Vec<Input>,
    pub output: Output,
}

impl BakeJob {
    /// The job as one text: compact JSON with every map's keys sorted
    /// (`serde_json` without `preserve_order`, as paw builds it; CK-A6's
    /// form), numbers as `float_roundtrip` writes them. `params` is a
    /// `Value`, which holds no NaN or infinity: a caller that builds it
    /// from floats refuses those first (`serde_json` would write `null`).
    pub fn canonical(&self) -> Vec<u8> {
        let value = serde_json::to_value(self).expect("a job is plain data");
        serde_json::to_vec(&value).expect("a value is JSON")
    }

    /// What was asked: the hash of the canonical job.
    pub fn input_key(&self) -> Digest {
        let mut hasher = Hasher::new();
        hasher.update(PREFIX);
        hasher.update(&self.canonical());
        hasher.finish()
    }
}

/// The name of a cache entry: what was asked and who made it. 128 bits,
/// written as 32 hex digits; the entry keeps the whole input key.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct EntryKey {
    pub input: Digest,
    pub tool: String,
}

impl EntryKey {
    pub fn new(job: &BakeJob, tool: impl Into<String>) -> Self {
        Self {
            input: job.input_key(),
            tool: tool.into(),
        }
    }

    /// The entry's name in the cache.
    pub fn id(&self) -> String {
        let mut hasher = Hasher::new();
        hasher.update(&self.input.0);
        hasher.update(self.tool.as_bytes());
        let full = hasher.finish().to_string();
        full[..32].to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn job() -> BakeJob {
        BakeJob {
            op: "stretch".into(),
            version: 3,
            params: serde_json::json!({ "warp": [[0, 0], [20, 30.5]], "mode": "tonal", "formants": false }),
            inputs: vec![Input::Range {
                hash: Digest([7; 32]),
                stream: 0,
                from: 0,
                to: 960_000,
                reverse: true,
            }],
            output: Output {
                stream: Stream::Sound,
                rate: Some(48_000),
                format: None,
            },
        }
    }

    #[test]
    fn a_fixed_job_has_a_fixed_key() {
        let job = job();
        assert_eq!(
            String::from_utf8(job.canonical()).unwrap(),
            r#"{"inputs":[{"from":0,"hash":"0707070707070707070707070707070707070707070707070707070707070707","reverse":true,"stream":0,"to":960000}],"op":"stretch","output":{"rate":48000,"stream":"sound"},"params":{"formants":false,"mode":"tonal","warp":[[0,0],[20,30.5]]},"version":3}"#
        );
        // Golden: a change here is a change of every key, so of the format
        // (a new PREFIX) or of the hash (a new Hasher): SHA-256 now, checked
        // with Python's hashlib; blake3 changes both lines.
        let key = EntryKey::new(&job, "paw.stretch/3");
        assert_eq!(key.input.to_string(), GOLDEN_INPUT);
        assert_eq!(key.id(), GOLDEN_ENTRY);
    }

    const GOLDEN_INPUT: &str = "4715822839237d27a2da89080e797f33de98efc8e77983b1c2cee48b826d3889";
    const GOLDEN_ENTRY: &str = "6f87884c99606eabc6fe6d68638725a0";
}
