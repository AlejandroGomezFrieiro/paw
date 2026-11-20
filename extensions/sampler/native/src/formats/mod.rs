//! Instrument formats. Each is a reader that turns a file into the one
//! model in `model.rs`; adding a format is adding a reader here and a test.

use crate::error::FormatError;
use crate::model::Instrument;
use std::io::Read;
use std::path::Path;

pub mod dspreset;
pub mod sfz;

pub trait FormatReader: Sync {
    /// The format's short name, as `describe` reports it.
    fn name(&self) -> &'static str;
    /// Whether the file is of this format (by its name, or its first bytes).
    fn detect(&self, path: &Path, head: &[u8]) -> bool;
    fn read(&self, path: &Path) -> Result<Instrument, FormatError>;
}

/// Every format the player reads, tried in order.
pub static READERS: &[&dyn FormatReader] = &[&sfz::Sfz, &dspreset::DecentSampler];

/// How much of a file the readers look at to know its format.
const HEAD: u64 = 512;

/// Reads an instrument file of any known format.
pub fn read(path: &Path) -> Result<Instrument, FormatError> {
    let mut head = Vec::new();
    std::fs::File::open(path)
        .and_then(|file| file.take(HEAD).read_to_end(&mut head))
        .map_err(|e| FormatError::io(path, e))?;
    let reader = READERS
        .iter()
        .find(|r| r.detect(path, &head))
        .ok_or_else(|| FormatError::UnknownFormat(path.to_path_buf()))?;
    let mut instrument = reader.read(path)?;
    instrument.format = reader.name().to_string();
    instrument.path = path.to_path_buf();
    if instrument.name.is_empty() {
        instrument.name = path
            .file_stem()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default();
    }
    if instrument.curves.is_empty() {
        instrument.curves = crate::model::Curve::builtin();
    }
    Ok(instrument)
}

pub fn extension_is(path: &Path, ext: &str) -> bool {
    path.extension()
        .is_some_and(|e| e.to_string_lossy().eq_ignore_ascii_case(ext))
}

/// A key as a number (`60`) or a name (`c4`, `C#4`, `db4`), middle C being
/// C4 = 60 as paw names it. `octave_offset` shifts named keys only, as SFZ
/// counts it; the caller adds `note_offset`.
pub fn parse_key(text: &str) -> Option<i32> {
    let text = text.trim();
    if let Ok(n) = text.parse::<i32>() {
        return Some(n);
    }
    let mut chars = text.chars();
    let letter = chars.next()?.to_ascii_lowercase();
    let base = match letter {
        'c' => 0,
        'd' => 2,
        'e' => 4,
        'f' => 5,
        'g' => 7,
        'a' => 9,
        'b' => 11,
        _ => return None,
    };
    let rest: String = chars.collect();
    let (accidental, octave) = match rest.chars().next() {
        Some('#') | Some('♯') => (1, &rest[rest.chars().next()?.len_utf8()..]),
        Some('b') | Some('♭') if rest.len() > 1 => (-1, &rest[rest.chars().next()?.len_utf8()..]),
        _ => (0, rest.as_str()),
    };
    let octave: i32 = octave.parse().ok()?;
    Some((octave + 1) * 12 + base + accidental)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_by_name_and_number() {
        assert_eq!(parse_key("60"), Some(60));
        assert_eq!(parse_key("c4"), Some(60));
        assert_eq!(parse_key("C#4"), Some(61));
        assert_eq!(parse_key("db4"), Some(61));
        assert_eq!(parse_key("a0"), Some(21));
        assert_eq!(parse_key("c-1"), Some(0));
        assert_eq!(parse_key("x"), None);
    }
}
