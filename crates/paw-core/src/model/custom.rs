//! Clips of a kind that an extension defines: video, lyrics, light cues.
//!
//! The core never reads such a clip's data. It keeps four things for it:
//! the kind's **data** (a plain value, or text in the kind's own format:
//! the kind serializes its data to one of these), the
//! **media** files it uses, the **sound** it makes you hear (a built-in MIDI
//! or audio content that the kind compiled) and the **signals** it sends
//! (timed messages to the kernel or to an OSC port). The sound and the
//! signals are saved with the project, so that a project plays without the
//! extension.
//!
//! The data is a value, never bytes that the core cannot read. A
//! [`KindValue`] is saved as pretty JSON with its keys sorted, so that one
//! value has one text (save, load and save give the same bytes) and a
//! change of one field is one line in `git diff`.

use std::fmt;
use std::path::PathBuf;
use std::str::FromStr;
use std::sync::Arc;

use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;

use super::ClipContent;
use super::kinds::{ClipFamily, KindId, Version};

/// A bad name or a bad content in a custom clip.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum CustomError {
    #[error(
        "`{0}` is not a name: use a lowercase word of 1 to 32 letters, digits, `_` and `-` that starts with a letter"
    )]
    BadWord(String),
    #[error("`{0}` is not an OSC address: it starts with `/` and has no spaces")]
    BadAddress(String),
    #[error("the sound of a clip is MIDI or audio, not a clip of the kind `{0}`")]
    NestedCustom(String),
    #[error(
        "the data is {0} bytes, over the limit of 1 MB: big or binary data goes in a media file: give it in `media`"
    )]
    TooBig(usize),
}

/// The most bytes that a custom clip's data can have, as compact JSON or as
/// text. More is media, not data.
pub(crate) const DATA_LIMIT: usize = 1 << 20;

/// A lowercase word, `[a-z][a-z0-9_-]{0,31}`, shared by clips that use it:
/// the role of a media file, the name of an OSC port.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct Word(Arc<str>);

impl Word {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl FromStr for Word {
    type Err = CustomError;

    fn from_str(text: &str) -> Result<Self, CustomError> {
        let mut chars = text.chars();
        let first = chars.next().is_some_and(|c| c.is_ascii_lowercase());
        let rest =
            chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-');
        if first && rest && text.len() <= 32 {
            Ok(Word(text.into()))
        } else {
            Err(CustomError::BadWord(text.to_string()))
        }
    }
}

impl TryFrom<String> for Word {
    type Error = CustomError;

    fn try_from(text: String) -> Result<Self, CustomError> {
        text.parse()
    }
}

impl From<Word> for String {
    fn from(word: Word) -> String {
        word.0.to_string()
    }
}

impl fmt::Display for Word {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// What a media file is to its clip, in the kind's words: `source`,
/// `proxy`, `thumbs`.
pub(crate) type MediaRole = Word;

/// The name of an OSC port: the project names it, and the machine's
/// setting says where it goes.
pub(crate) type PortName = Word;

/// A plain JSON value that the core keeps and never reads: what a kind
/// serialized its data or a signal's body to. Clips that share it share
/// one value, so a clone is a count. Its maps keep their keys sorted, so
/// one value has one text.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(transparent)]
pub struct KindValue(Arc<Value>);

impl KindValue {
    pub fn get(&self) -> &Value {
        &self.0
    }
}

impl From<Value> for KindValue {
    fn from(value: Value) -> Self {
        KindValue(Arc::new(value))
    }
}

impl PartialEq for KindValue {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0) || self.0 == other.0
    }
}

/// What a custom clip's own positions count.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Timeline {
    /// Beats: the data follows the tempo, as notes do.
    #[default]
    Beats,
    /// Seconds: the data follows time, as a film does.
    Seconds,
}

/// The data of a custom clip: the kind's own, as the kind serialized it.
/// The core keeps it and never reads it.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum KindData {
    /// A plain value, saved as pretty JSON with sorted keys.
    Json(KindValue),
    /// Text in the kind's own format (an `.lrc` file), with the file
    /// extension that it is saved with. Saved as it is.
    Text {
        ext: Word,
        text: Arc<str>,
    },
}

impl KindData {
    /// Refuse data over [`DATA_LIMIT`]: what a kind gives stays small
    /// enough to save, load and compare at each edit.
    pub fn check_size(&self) -> Result<(), CustomError> {
        let size = match self {
            KindData::Json(value) => serde_json::to_vec(value.get()).map_or(usize::MAX, |b| b.len()),
            KindData::Text { text, .. } => text.len(),
        };
        if size > DATA_LIMIT {
            return Err(CustomError::TooBig(size));
        }
        Ok(())
    }
}

/// A file that a custom clip uses.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MediaRef {
    pub role: MediaRole,
    pub path: PathBuf,
    /// Made from other files by the kind, and named by the hash of what
    /// made it: it can be made again.
    #[serde(default, skip_serializing_if = "super::is_default")]
    pub derived: bool,
}

/// What a custom clip makes you hear: a built-in MIDI or audio content,
/// never a custom one, so that a clip's sound never holds a sound.
#[derive(Clone, Debug, Serialize)]
#[serde(transparent)]
pub struct Sound(ClipContent);

impl Sound {
    pub fn content(&self) -> &ClipContent {
        &self.0
    }
}

impl TryFrom<ClipContent> for Sound {
    type Error = CustomError;

    fn try_from(content: ClipContent) -> Result<Self, CustomError> {
        match content {
            ClipContent::Custom(custom) => Err(CustomError::NestedCustom(custom.kind.to_string())),
            built_in => Ok(Sound(built_in)),
        }
    }
}

impl<'de> Deserialize<'de> for Sound {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Sound::try_from(ClipContent::deserialize(deserializer)?).map_err(serde::de::Error::custom)
    }
}

/// A timed message of a custom clip that is not sound.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Signal {
    /// Where it happens, in the clip's timeline from the start of its data.
    pub at: f64,
    /// How many milliseconds early it goes, so that a slow receiver acts
    /// on time.
    #[serde(default, skip_serializing_if = "super::is_default")]
    pub lead_ms: u16,
    /// Signals with the same latch are states: after a jump, the last one
    /// before the play position is given again.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latch: Option<Arc<str>>,
    pub to: SignalTo,
}

/// Where a signal goes.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum SignalTo {
    /// To the kind's code in the kernel, with this payload.
    Kernel { body: KindValue },
    /// An OSC message to a port that the machine's setting names.
    Osc {
        port: PortName,
        address: OscAddress,
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        args: Vec<OscArg>,
    },
}

/// The address of an OSC message: `/cue/1/go`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct OscAddress(Arc<str>);

impl OscAddress {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl FromStr for OscAddress {
    type Err = CustomError;

    fn from_str(text: &str) -> Result<Self, CustomError> {
        if text.starts_with('/') && !text.chars().any(|c| c.is_whitespace() || c.is_control()) {
            Ok(OscAddress(text.into()))
        } else {
            Err(CustomError::BadAddress(text.to_string()))
        }
    }
}

impl TryFrom<String> for OscAddress {
    type Error = CustomError;

    fn try_from(text: String) -> Result<Self, CustomError> {
        text.parse()
    }
}

impl From<OscAddress> for String {
    fn from(address: OscAddress) -> String {
        address.0.to_string()
    }
}

/// An argument of an OSC message, written as the JSON value it is: `1` is
/// an integer, `1.0` a float.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum OscArg {
    Bool(bool),
    Int(i32),
    Float(f32),
    Str(Arc<str>),
}

/// The content of a clip of a kind that an extension defines.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CustomContent {
    /// The kind, saved as `type` (`kind` says that the content is custom).
    #[serde(rename = "type")]
    pub kind: KindId<ClipFamily>,
    /// The version of the kind's data, for the kind's migrations.
    #[serde(default, skip_serializing_if = "Version::is_one")]
    pub version: Version,
    #[serde(default, skip_serializing_if = "super::is_default")]
    pub timeline: Timeline,
    /// Where the clip starts in its data, in its timeline: what trimming
    /// the start or slipping changes. The data does not change.
    #[serde(default, skip_serializing_if = "super::is_default")]
    pub offset: f64,
    pub data: KindData,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub media: Vec<MediaRef>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sound: Option<Sound>,
    /// In the clip's timeline, from the start of its data.
    #[serde(default, skip_serializing_if = "<[Signal]>::is_empty")]
    pub signals: Arc<[Signal]>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Clip;

    fn clip(content: serde_json::Value) -> serde_json::Value {
        serde_json::json!({ "id": 1, "name": "c", "start": 0.0, "length": 4.0, "muted": false,
            "content": content })
    }

    #[test]
    fn an_unknown_kinds_data_round_trips_as_a_value() {
        let data = serde_json::json!({ "zeta": 1.5, "alpha": [3, 2, { "n": null, "b": true }] });
        let body = serde_json::json!({ "b": 1000.0, "a": 0 });
        let content = serde_json::json!({ "kind": "custom", "type": "unknown", "data": { "json": data },
            "signals": [{ "at": 1.0, "to": { "kind": "kernel", "body": body } },
                { "at": 2.0, "to": { "kind": "osc", "port": "qlc", "address": "/go", "args": [1, 0.5, "x"] } }],
            "sound": { "kind": "midi", "notes": [] } });
        let first: Clip = serde_json::from_value(clip(content)).unwrap();
        let text = serde_json::to_string_pretty(&first).unwrap();
        let read: Clip = serde_json::from_str(&text).unwrap();
        let ClipContent::Custom(custom) = &read.content else {
            panic!("a custom clip")
        };
        let KindData::Json(json) = &custom.data else {
            panic!("JSON data")
        };
        assert_eq!(json.get(), &data);
        let SignalTo::Kernel { body: read_body } = &custom.signals[0].to else {
            panic!("a kernel signal")
        };
        assert_eq!(read_body.get(), &body);
        assert!(
            matches!(read.playable(), Some(ClipContent::Midi { .. })),
            "it plays its sound"
        );
        assert_eq!(
            serde_json::to_string_pretty(&read).unwrap(),
            text,
            "and is saved as it was read"
        );
    }

    #[test]
    fn midi_and_audio_clips_still_save_and_load() {
        for text in [
            r#"{"kind":"midi","notes":[{"start":0.0,"length":1.0,"pitch":60,"velocity":90}]}"#,
            r#"{"kind":"audio","file":"a.wav","offset":0.5,"gain":-3.0}"#,
        ] {
            let content: ClipContent = serde_json::from_str(text).unwrap();
            assert_eq!(serde_json::to_string(&content).unwrap(), text);
        }
    }

    #[test]
    fn a_sound_is_never_custom() {
        let text = r#"{ "kind": "custom", "type": "inner", "data": { "json": "1" } }"#;
        let inner: ClipContent = serde_json::from_str(text).unwrap();
        assert_eq!(
            Sound::try_from(inner).unwrap_err().to_string(),
            "the sound of a clip is MIDI or audio, not a clip of the kind `inner`"
        );
        let nested = format!(
            r#"{{ "kind": "custom", "type": "outer", "data": {{ "json": "1" }}, "sound": {text} }}"#
        );
        let err = serde_json::from_str::<ClipContent>(&nested).unwrap_err();
        assert!(err.to_string().contains("not a clip of the kind `inner`"), "{err}");
    }
}
