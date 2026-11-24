//! The type of a stream: a base kind of the stream family (`midi`,
//! `audio`, `curve`, `state`, or a kind of an extension) plus properties,
//! such as the channels of audio or the frame rate of a video.
//!
//! The base kind declares the properties that it takes. The registry of
//! stream kinds checks a type against them; this module only holds the
//! values and their file form:
//!
//! ```json
//! { "base": "audio", "props": { "channels": 2 } }
//! ```

use std::collections::BTreeMap;
use std::fmt;

use serde::{Deserialize, Serialize};

use crate::kinds::{KindId, StreamFamily};

/// A base kind plus properties. A type with no properties writes no
/// `props`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StreamType {
    pub base: KindId<StreamFamily>,
    #[serde(default, skip_serializing_if = "Props::is_empty")]
    pub props: Props,
}

impl StreamType {
    /// The type of `base` with no properties.
    pub fn of(base: KindId<StreamFamily>) -> Self {
        Self { base, props: Props::default() }
    }
}

/// The properties of a stream type by name, in the order of their names.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Props(BTreeMap<String, Prop>);

impl Props {
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    pub fn get(&self, name: &str) -> Option<&Prop> {
        self.0.get(name)
    }

    /// Set the property `name`, and give the value that it had.
    pub fn insert(&mut self, name: impl Into<String>, value: Prop) -> Option<Prop> {
        self.0.insert(name.into(), value)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&str, &Prop)> {
        self.0.iter().map(|(name, value)| (name.as_str(), value))
    }
}

/// The value of one property. The file writes a flag as `true`, a count
/// as `2`, a ratio as `[30000, 1001]` and a word as `"stereo"`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Prop {
    Flag(bool),
    Count(u32),
    /// A numerator and a denominator, as a frame rate of 30000/1001.
    Ratio(u32, u32),
    Word(String),
}

impl fmt::Display for Prop {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Flag(on) => on.fmt(f),
            Self::Count(n) => n.fmt(f),
            Self::Ratio(n, d) => write!(f, "{n}/{d}"),
            Self::Word(word) => f.write_str(word),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_stream_type_round_trips_with_each_kind_of_property() {
        let text = r#"{"base":"video","props":{"alpha":false,"channels":2,"layout":"stereo","rate":[30000,1001]}}"#;
        let read: StreamType = serde_json::from_str(text).expect("a stream type");
        assert_eq!(read.base.as_str(), "video");
        assert_eq!(read.props.get("rate"), Some(&Prop::Ratio(30000, 1001)));
        assert_eq!(read.props.get("channels"), Some(&Prop::Count(2)));
        assert_eq!(read.props.get("alpha"), Some(&Prop::Flag(false)));
        assert_eq!(read.props.get("layout"), Some(&Prop::Word("stereo".into())));
        assert_eq!(serde_json::to_string(&read).unwrap(), text, "written as it was read");
        let bare = StreamType::of("midi".parse().unwrap());
        assert_eq!(serde_json::to_string(&bare).unwrap(), r#"{"base":"midi"}"#, "no props, no key");
        assert!(serde_json::from_str::<StreamType>(r#"{"base":"Midi"}"#).is_err(), "a base is a kind name");
    }
}
