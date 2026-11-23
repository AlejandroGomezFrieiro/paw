//! What a project knows of its source files: the media table, saved as
//! `media.json` at the top of a project folder.
//!
//! A clip names a file by its path, which says where to look. The table
//! gives each path the BLAKE3 hash of the file's bytes, which says what the
//! file is, wherever it is: relink, dedupe and (later) the bake cache use
//! only the hash.

use std::collections::BTreeMap;
use std::fmt;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::Arc;

use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// The BLAKE3 hash of a file's bytes: what a source is, wherever it is.
/// Written as `b3:` and 64 hexadecimal digits.
#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub(crate) struct SourceHash([u8; 32]);

impl SourceHash {
    const PREFIX: &'static str = "b3:";

    /// The hash of the bytes of the file at `path` (see `media::hash::file`).
    pub(crate) fn of_file(path: &Path) -> std::io::Result<Self> {
        super::hash::file(path).map(Self::from)
    }

    #[cfg(test)]
    pub(crate) const fn from_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }
}

impl From<blake3::Hash> for SourceHash {
    fn from(hash: blake3::Hash) -> Self {
        Self(*hash.as_bytes())
    }
}

impl fmt::Display for SourceHash {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}{}", Self::PREFIX, blake3::Hash::from_bytes(self.0).to_hex())
    }
}

impl fmt::Debug for SourceHash {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Display::fmt(self, f)
    }
}

/// Why a text is not a [`SourceHash`].
#[derive(Debug, thiserror::Error)]
#[error("{0:?} is not a source hash (b3: and 64 hexadecimal digits)")]
pub(crate) struct BadHash(String);

impl FromStr for SourceHash {
    type Err = BadHash;

    fn from_str(text: &str) -> Result<Self, Self::Err> {
        text.strip_prefix(Self::PREFIX)
            .and_then(|hex| blake3::Hash::from_hex(hex).ok())
            .map(Self::from)
            .ok_or_else(|| BadHash(text.to_owned()))
    }
}

impl Serialize for SourceHash {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_str(self)
    }
}

impl<'de> Deserialize<'de> for SourceHash {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let text = String::deserialize(d)?;
        text.parse().map_err(serde::de::Error::custom)
    }
}

/// What the file holds, read from its header once.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub(crate) struct Probe {
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub streams: Vec<StreamInfo>,
}

/// One stream of a file. Pictures and data streams come with the kinds of
/// clip that play them (a film's picture, a subtitle part).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub(crate) enum StreamInfo {
    Sound {
        rate: u32,
        channels: u32,
        /// Not every header says (an MP3 without a length in it).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        frames: Option<u64>,
    },
}

impl Probe {
    /// Read the header of the file at `path`. A file that is not sound has
    /// no streams that paw knows yet.
    pub(crate) fn of_file(path: &Path) -> Self {
        let Ok(p) = paw_engine::probe::probe(path) else {
            return Self::default();
        };
        let frames = p
            .seconds
            .map(|s| (s * f64::from(p.sample_rate)).round() as u64);
        Self {
            streams: vec![StreamInfo::Sound { rate: p.sample_rate, channels: p.channels, frames }],
        }
    }
}

/// What the project knows of one source file.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub(crate) struct MediaRecord {
    pub hash: SourceHash,
    pub size: u64,
    #[serde(default)]
    pub probe: Probe,
}

/// Every file the project uses, by its path. In memory the paths are
/// absolute; in `media.json` they are as the clips name them in the folder.
#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) struct MediaTable(BTreeMap<PathBuf, Arc<MediaRecord>>);

impl MediaTable {
    pub(crate) fn get(&self, path: &Path) -> Option<&Arc<MediaRecord>> {
        self.0.get(path)
    }

    pub(crate) fn insert(&mut self, path: PathBuf, record: MediaRecord) {
        self.0.insert(path, Arc::new(record));
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    pub(crate) fn len(&self) -> usize {
        self.0.len()
    }

    pub(crate) fn iter(&self) -> impl Iterator<Item = (&PathBuf, &Arc<MediaRecord>)> {
        self.0.iter()
    }

    /// The same records under the paths `name` gives (records it gives no
    /// path for are left out).
    pub(crate) fn renamed(&self, mut name: impl FnMut(&Path) -> Option<PathBuf>) -> Self {
        Self(
            self.0
                .iter()
                .filter_map(|(path, r)| Some((name(path)?, Arc::clone(r))))
                .collect(),
        )
    }

    /// `media.json`: one entry per path, sorted, pretty, ending in a new line,
    /// so the same table gives the same bytes and an import adds a few lines.
    pub(crate) fn to_json(&self) -> Vec<u8> {
        let named: BTreeMap<String, &MediaRecord> = self
            .0
            .iter()
            .map(|(path, r)| (path.to_string_lossy().into_owned(), &**r))
            .collect();
        let mut text = serde_json::to_string_pretty(&named).unwrap_or_default();
        text.push('\n');
        text.into_bytes()
    }

    /// The table that [`to_json`](Self::to_json) wrote.
    pub(crate) fn from_json(bytes: &[u8]) -> serde_json::Result<Self> {
        let named: BTreeMap<PathBuf, MediaRecord> = serde_json::from_slice(bytes)?;
        Ok(Self(named.into_iter().map(|(p, r)| (p, Arc::new(r))).collect()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn media_json_saved_loaded_and_saved_again_gives_the_same_bytes() {
        let mut table = MediaTable::default();
        table.insert(
            "media/take 1.wav".into(),
            MediaRecord {
                hash: super::super::hash::bytes(b"one").into(),
                size: 3,
                probe: Probe {
                    streams: vec![StreamInfo::Sound { rate: 48_000, channels: 2, frames: Some(96_000) }],
                },
            },
        );
        table.insert(
            "/elsewhere/film.mp4".into(),
            MediaRecord { hash: super::super::hash::bytes(b"two").into(), size: 3, probe: Probe::default() },
        );
        let bytes = table.to_json();
        let back = MediaTable::from_json(&bytes).unwrap();
        assert_eq!(back, table);
        assert_eq!(back.to_json(), bytes);
        let text = String::from_utf8(bytes).unwrap();
        assert!(text.contains("\"hash\": \"b3:"), "{text}");
        assert!(text.find("/elsewhere").unwrap() < text.find("media/").unwrap(), "sorted by path: {text}");
    }
}
