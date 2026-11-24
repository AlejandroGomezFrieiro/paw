//! The tags a rendered file carries: title, artist, album, track, year,
//! genre, comment and a cover picture. They are set for the project
//! (`project.meta.tags`) and can be overridden for one render (`tags` in its
//! options). Each format has its own way of holding them: a WAV a `LIST`
//! chunk of `INFO`, a FLAC Vorbis comments and a `PICTURE` block; the lossy
//! formats get them from ffmpeg, through a metadata file (see `encode.rs`),
//! because a cover can be larger than one command-line argument may be.

use std::fs::OpenOptions;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use serde::{Deserialize, Deserializer};
use serde_json::Value;

use crate::model::Project;

/// The largest cover taken: a FLAC metadata block holds under 16 MiB.
const MAX_COVER: usize = 8 << 20;

/// A tag is text; a track or a year may be given as a number.
fn text<'de, D: Deserializer<'de>>(de: D) -> Result<String, D::Error> {
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Text {
        Text(String),
        Number(f64),
    }
    Ok(match Option::<Text>::deserialize(de)? {
        None => String::new(),
        Some(Text::Text(s)) => s.trim().to_owned(),
        Some(Text::Number(n)) if n.fract() == 0.0 => format!("{}", n as i64),
        Some(Text::Number(n)) => n.to_string(),
    })
}

/// What a file is tagged with; an empty field is left out of the file.
#[derive(Clone, Debug, Default, PartialEq, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub(crate) struct Tags {
    #[serde(deserialize_with = "text")]
    pub title: String,
    #[serde(deserialize_with = "text")]
    pub artist: String,
    #[serde(deserialize_with = "text")]
    pub album: String,
    /// The track's number, or "3/12".
    #[serde(deserialize_with = "text")]
    pub track: String,
    #[serde(deserialize_with = "text")]
    pub year: String,
    #[serde(deserialize_with = "text")]
    pub genre: String,
    #[serde(deserialize_with = "text")]
    pub comment: String,
    /// A PNG or JPEG file; a relative path is from the project's directory.
    #[serde(deserialize_with = "text")]
    pub cover: String,
}

impl Tags {
    /// The project's own tags (`project.meta.tags`), when it has any that
    /// make sense; a malformed entry is an error that says so.
    pub(crate) fn of_project(project: &Project) -> Result<Self> {
        match project.meta.get("tags") {
            None | Some(Value::Null) => Ok(Self::default()),
            Some(value) => serde_json::from_value(value.clone())
                .context("project.meta.tags is not a table of title, artist, album, track, year, genre, comment and cover"),
        }
    }

    /// These tags, with the fields `over` has set taking the place of them.
    pub(crate) fn over(mut self, over: &Tags) -> Self {
        let take = |mine: &mut String, theirs: &String| {
            if !theirs.is_empty() {
                mine.clone_from(theirs);
            }
        };
        take(&mut self.title, &over.title);
        take(&mut self.artist, &over.artist);
        take(&mut self.album, &over.album);
        take(&mut self.track, &over.track);
        take(&mut self.year, &over.year);
        take(&mut self.genre, &over.genre);
        take(&mut self.comment, &over.comment);
        take(&mut self.cover, &over.cover);
        self
    }

    /// The text tags that are set, as (key in a Vorbis comment, value).
    fn fields(&self) -> Vec<(&'static str, &str)> {
        [
            ("TITLE", &self.title),
            ("ARTIST", &self.artist),
            ("ALBUM", &self.album),
            ("TRACKNUMBER", &self.track),
            ("DATE", &self.year),
            ("GENRE", &self.genre),
            ("COMMENT", &self.comment),
        ]
        .into_iter()
        .filter(|(_, v)| !v.is_empty())
        .map(|(k, v)| (k, v.as_str()))
        .collect()
    }

    /// Whether any text tag is set.
    pub(crate) fn has_text(&self) -> bool {
        !self.fields().is_empty()
    }

    /// The cover, read; a relative path is from `base`, the project's directory.
    pub(crate) fn load_cover(&self, base: Option<&Path>) -> Result<Option<Cover>> {
        if self.cover.is_empty() {
            return Ok(None);
        }
        let mut path = PathBuf::from(&self.cover);
        if path.is_relative()
            && let Some(base) = base
        {
            path = base.join(path);
        }
        Cover::read(&path).map(Some)
    }
}

/// A picture to put in a file.
#[derive(Clone, Debug)]
pub(crate) struct Cover {
    pub mime: &'static str,
    pub data: Vec<u8>,
    width: u32,
    height: u32,
    /// Bits per pixel.
    depth: u32,
}

impl Cover {
    fn read(path: &Path) -> Result<Self> {
        let mut data = Vec::new();
        std::fs::File::open(path)
            .and_then(|f| f.take(MAX_COVER as u64 + 1).read_to_end(&mut data))
            .with_context(|| format!("reading the cover {}", path.display()))?;
        if data.len() > MAX_COVER {
            bail!("the cover {} is larger than {} MiB", path.display(), MAX_COVER >> 20);
        }
        Self::parse(data).with_context(|| format!("the cover {}", path.display()))
    }

    fn parse(data: Vec<u8>) -> Result<Self> {
        let be = |at: usize| data.get(at..at + 4).map(|b| u32::from_be_bytes(b.try_into().unwrap()));
        let (mime, width, height, depth) = if data.starts_with(b"\x89PNG\r\n\x1a\n") {
            let channels = match data.get(25) {
                Some(0) | Some(3) => 1,
                Some(4) => 2,
                Some(2) => 3,
                _ => 4,
            };
            (
                "image/png",
                be(16),
                be(20),
                data.get(24).map(|bits| *bits as u32 * channels),
            )
        } else if data.starts_with(&[0xFF, 0xD8, 0xFF]) {
            let (h, w, precision) = jpeg_size(&data).unwrap_or_default();
            ("image/jpeg", Some(w), Some(h), Some(precision * 3))
        } else {
            bail!("must be a PNG or JPEG picture");
        };
        Ok(Self {
            mime,
            width: width.unwrap_or(0),
            height: height.unwrap_or(0),
            depth: depth.unwrap_or(0),
            data,
        })
    }

    /// The file extension for the picture.
    pub(crate) fn extension(&self) -> &'static str {
        if self.mime == "image/png" { "png" } else { "jpg" }
    }

    /// A FLAC `PICTURE` block's contents, of the front cover. Ogg and Opus
    /// hold the same bytes, in base64, as `METADATA_BLOCK_PICTURE`.
    pub(crate) fn picture_block(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(self.data.len() + 64);
        let mut put = |n: u32| out.extend(n.to_be_bytes());
        put(3);
        put(self.mime.len() as u32);
        out.extend(self.mime.as_bytes());
        out.extend(0u32.to_be_bytes());
        for n in [self.width, self.height, self.depth, 0, self.data.len() as u32] {
            out.extend(n.to_be_bytes());
        }
        out.extend(&self.data);
        out
    }
}

/// Height, width and bits per sample of a JPEG, from its first frame header.
fn jpeg_size(data: &[u8]) -> Option<(u32, u32, u32)> {
    let mut at = 2;
    while at + 4 <= data.len() {
        if data[at] != 0xFF {
            return None;
        }
        let marker = data[at + 1];
        if marker == 0xFF {
            at += 1;
            continue;
        }
        let length = u16::from_be_bytes([data[at + 2], data[at + 3]]) as usize;
        let frame = matches!(marker, 0xC0..=0xCF) && !matches!(marker, 0xC4 | 0xC8 | 0xCC);
        if frame {
            let body = data.get(at + 4..at + 4 + 5)?;
            let height = u16::from_be_bytes([body[1], body[2]]) as u32;
            let width = u16::from_be_bytes([body[3], body[4]]) as u32;
            return Some((height, width, body[0] as u32));
        }
        at += 2 + length;
    }
    None
}

/// A FLAC metadata block's contents holding the text tags as Vorbis comments.
pub(crate) fn vorbis_comments(tags: &Tags) -> Vec<u8> {
    let mut out = Vec::new();
    let put = |out: &mut Vec<u8>, s: &str| {
        out.extend((s.len() as u32).to_le_bytes());
        out.extend(s.as_bytes());
    };
    put(&mut out, "paw");
    let fields = tags.fields();
    out.extend((fields.len() as u32).to_le_bytes());
    for (key, value) in fields {
        put(&mut out, &format!("{key}={value}"));
    }
    out
}

/// A `LIST` chunk of `INFO` for a WAV file, or nothing when no text tag is set.
fn wav_info(tags: &Tags) -> Vec<u8> {
    let ids = [
        ("INAM", &tags.title),
        ("IART", &tags.artist),
        ("IPRD", &tags.album),
        ("ITRK", &tags.track),
        ("ICRD", &tags.year),
        ("IGNR", &tags.genre),
        ("ICMT", &tags.comment),
    ];
    let mut body = b"INFO".to_vec();
    for (id, value) in ids.iter().filter(|(_, v)| !v.is_empty()) {
        let size = value.len() + 1;
        body.extend(id.as_bytes());
        body.extend((size as u32).to_le_bytes());
        body.extend(value.as_bytes());
        body.push(0);
        if size % 2 == 1 {
            body.push(0);
        }
    }
    if body.len() == 4 {
        return Vec::new();
    }
    let mut chunk = b"LIST".to_vec();
    chunk.extend((body.len() as u32).to_le_bytes());
    chunk.extend(body);
    chunk
}

/// Add the tags to a finished WAV file: a `LIST` chunk after its data, and
/// the file's size in its header put right. A WAV has no place for a cover
/// that players read, so that is left out.
pub(crate) fn write_wav(path: &Path, tags: &Tags) -> Result<()> {
    let chunk = wav_info(tags);
    if chunk.is_empty() {
        return Ok(());
    }
    let mut file = OpenOptions::new().read(true).write(true).open(path)?;
    let mut end = file.seek(SeekFrom::End(0))?;
    // Chunks start on even offsets: the data chunk of an odd number of
    // bytes (24-bit mono) is padded.
    if end % 2 == 1 {
        file.write_all(&[0])?;
        end += 1;
    }
    file.write_all(&chunk)?;
    end += chunk.len() as u64;
    let riff = u32::try_from(end - 8).context("the file is too large for a WAV")?;
    file.seek(SeekFrom::Start(4))?;
    file.write_all(&riff.to_le_bytes())?;
    file.sync_all()?;
    Ok(())
}

/// What ffmpeg reads as a metadata file (`-f ffmetadata`): the text tags
/// and, for Ogg Vorbis and Opus, the cover in the way Vorbis comments hold
/// one. MP3 has its cover attached as a picture stream instead.
pub(crate) fn ffmetadata(tags: &Tags, cover_in_comments: Option<&Cover>) -> String {
    let escape = |s: &str| {
        let mut out = String::with_capacity(s.len());
        for c in s.chars() {
            if matches!(c, '=' | ';' | '#' | '\\' | '\n') {
                out.push('\\');
            }
            out.push(c);
        }
        out
    };
    let mut out = String::from(";FFMETADATA1\n");
    for (key, value) in tags.fields() {
        // What ffmpeg's muxers call these two.
        let key = match key {
            "TRACKNUMBER" => "track".to_owned(),
            other => other.to_ascii_lowercase(),
        };
        out.push_str(&format!("{key}={}\n", escape(value)));
    }
    if let Some(cover) = cover_in_comments {
        out.push_str(&format!(
            "METADATA_BLOCK_PICTURE={}\n",
            BASE64.encode(cover.picture_block())
        ));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tags() -> Tags {
        serde_json::from_value(serde_json::json!({
            "title": "Song", "artist": "Me", "album": "First", "track": 3,
            "year": 2026, "genre": "Ambient", "comment": "a=b; c"
        }))
        .unwrap()
    }

    #[test]
    fn numbers_are_text_and_empty_fields_are_left_over() {
        let t = tags();
        assert_eq!((t.track.as_str(), t.year.as_str()), ("3", "2026"));
        let over: Tags = serde_json::from_value(serde_json::json!({ "artist": "You" })).unwrap();
        let merged = t.over(&over);
        assert_eq!((merged.artist.as_str(), merged.album.as_str()), ("You", "First"));
        assert!(serde_json::from_value::<Tags>(serde_json::json!({ "artsit": "x" })).is_err());
    }

    #[test]
    fn a_wav_gets_an_info_chunk_and_a_right_size() {
        let dir = std::env::temp_dir().join(format!("paw-tags-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("t.wav");
        // Mono, 24 bits, 3 frames: an odd number of data bytes.
        let mut w = paw_engine::wav::Writer::with_channels(&path, 44100, paw_engine::wav::WavFormat::Int24, 1).unwrap();
        for _ in 0..3 {
            w.write(0.5).unwrap();
        }
        w.finish().unwrap();
        write_wav(&path, &tags()).unwrap();
        let bytes = std::fs::read(&path).unwrap();
        assert_eq!(u32::from_le_bytes(bytes[4..8].try_into().unwrap()) as usize, bytes.len() - 8);
        let list = bytes.windows(8).position(|w| &w[..4] == b"LIST").unwrap();
        assert_eq!(list % 2, 0);
        let info = String::from_utf8_lossy(&bytes[list..]).into_owned();
        assert!(info.contains("INAM") && info.contains("Song\0") && info.contains("IART"), "{info}");
        // The data chunk of 9 bytes came first, with a pad byte after it.
        let data = bytes.windows(4).position(|w| w == b"data").unwrap();
        assert_eq!(u32::from_le_bytes(bytes[data + 4..data + 8].try_into().unwrap()), 9);
        assert_eq!(list, data + 8 + 9 + 1);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn vorbis_comments_count_what_they_hold() {
        let block = vorbis_comments(&tags());
        let vendor = u32::from_le_bytes(block[..4].try_into().unwrap()) as usize;
        let count = u32::from_le_bytes(block[4 + vendor..8 + vendor].try_into().unwrap());
        assert_eq!(count, 7);
        assert!(String::from_utf8_lossy(&block).contains("TRACKNUMBER=3"));
    }

    #[test]
    fn a_cover_is_a_png_or_jpeg_with_its_size_known() {
        let mut png = b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR".to_vec();
        png.extend([0, 0, 0, 5, 0, 0, 0, 7, 8, 6, 0, 0, 0]);
        let cover = Cover::parse(png).unwrap();
        assert_eq!((cover.mime, cover.width, cover.height, cover.depth), ("image/png", 5, 7, 32));
        let block = cover.picture_block();
        assert_eq!(&block[..4], &[0, 0, 0, 3]);
        let jpeg = vec![0xFF, 0xD8, 0xFF, 0xC0, 0, 11, 8, 0, 9, 0, 6, 3, 1, 0x22, 0];
        let cover = Cover::parse(jpeg).unwrap();
        assert_eq!((cover.mime, cover.width, cover.height), ("image/jpeg", 6, 9));
        assert!(Cover::parse(b"GIF89a".to_vec()).is_err());
    }

    #[test]
    fn ffmpeg_metadata_escapes_what_it_reads_specially() {
        let text = ffmetadata(&tags(), None);
        assert!(text.starts_with(";FFMETADATA1\n"));
        assert!(text.contains("track=3\n") && text.contains("date=2026\n"));
        assert!(text.contains("comment=a\\=b\\; c\n"), "{text}");
    }
}
