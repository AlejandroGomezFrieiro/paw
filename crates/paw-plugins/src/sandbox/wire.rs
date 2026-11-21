//! The control wire: requests, answers and the helper's hello.

use std::borrow::Cow;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

use anyhow::Result;
use paw_engine::device::ParamInfo;
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;
use super::*;
use super::factory::*;

// --- the control wire --------------------------------------------------------------
//
// The socket carries frames: `[length: u32 LE][first byte][payload]`, the
// length counting the first byte. A request's first byte is its `Op`. The
// requests that are answered get a frame back whose first byte is 0, or 1
// with the reason when the plugin refused. The wire is paw's own: a helper
// and a DAW built apart understand each other only while these bytes stay.

/// What a request asks for: its first byte on the wire.
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum Op {
    SetValue = 1,
    SaveState = 2,
    LoadState = 3,
    OpenEditor = 4,
    CloseEditor = 5,
    SetOffline = 6,
    Call = 7,
    Quit = 8,
    Values = 9,
}

impl TryFrom<u8> for Op {
    type Error = u8;

    fn try_from(byte: u8) -> Result<Self, u8> {
        Ok(match byte {
            1 => Self::SetValue,
            2 => Self::SaveState,
            3 => Self::LoadState,
            4 => Self::OpenEditor,
            5 => Self::CloseEditor,
            6 => Self::SetOffline,
            7 => Self::Call,
            8 => Self::Quit,
            9 => Self::Values,
            other => return Err(other),
        })
    }
}

/// A request from the DAW to its helper, and what the helper answers.
#[derive(Clone, Debug, PartialEq)]
pub(super) enum Request<'a> {
    /// Set a parameter. No answer.
    SetValue { index: u32, value: f64 },
    /// The plugin's state, answered as [`optional`] bytes.
    SaveState,
    LoadState(&'a [u8]),
    /// Open the editor, in a window with this title.
    OpenEditor(Cow<'a, str>),
    /// No answer.
    CloseEditor,
    /// No answer.
    SetOffline(bool),
    /// A parameter's value as text ([`Controller::value_text`]): a
    /// [`Op::Call`] of [`PARAM_TEXT`]. Answered with the text.
    ValueText { index: u32, value: f64 },
    /// The value that a parameter's text stands for
    /// ([`Controller::text_value`]): a [`Op::Call`] of [`PARAM_VALUE`].
    /// Answered with the value in 8 bytes, or with none.
    TextValue { index: u32, text: Cow<'a, str> },
    /// Get a call ready for the audio thread ([`Controller::prepare`]): a
    /// [`Op::Call`] of [`PREPARE`], answered as [`optional`] bytes.
    Prepare { method: Cow<'a, str>, data: &'a [u8] },
    /// Any other call ([`Controller::call`]).
    Call { method: Cow<'a, str>, data: &'a [u8] },
    /// End. No answer.
    Quit,
    /// The parameters' values, answered as a JSON array (see [`read_values`]).
    Values,
}

impl<'a> Request<'a> {
    fn op(&self) -> Op {
        match self {
            Self::SetValue { .. } => Op::SetValue,
            Self::SaveState => Op::SaveState,
            Self::LoadState(_) => Op::LoadState,
            Self::OpenEditor(_) => Op::OpenEditor,
            Self::CloseEditor => Op::CloseEditor,
            Self::SetOffline(_) => Op::SetOffline,
            Self::ValueText { .. }
            | Self::TextValue { .. }
            | Self::Prepare { .. }
            | Self::Call { .. } => Op::Call,
            Self::Quit => Op::Quit,
            Self::Values => Op::Values,
        }
    }

    /// The request as one frame. A call's method ends in a 0 byte.
    fn frame(&self) -> Vec<u8> {
        fn method(out: &mut Vec<u8>, name: &str) {
            out.extend_from_slice(name.as_bytes());
            out.push(0);
        }
        let mut out = vec![0; 4];
        out.push(self.op() as u8);
        match self {
            Self::SetValue { index, value } => {
                out.extend_from_slice(&index.to_le_bytes());
                out.extend_from_slice(&value.to_le_bytes());
            }
            Self::ValueText { index, value } => {
                method(&mut out, PARAM_TEXT);
                out.extend_from_slice(&index.to_le_bytes());
                out.extend_from_slice(&value.to_le_bytes());
            }
            Self::SaveState | Self::CloseEditor | Self::Quit | Self::Values => {}
            Self::LoadState(state) => out.extend_from_slice(state),
            Self::OpenEditor(title) => out.extend_from_slice(title.as_bytes()),
            Self::SetOffline(offline) => out.push(u8::from(*offline)),
            Self::TextValue { index, text } => {
                method(&mut out, PARAM_VALUE);
                out.extend_from_slice(&index.to_le_bytes());
                out.extend_from_slice(text.as_bytes());
            }
            Self::Prepare { method: inner, data } => {
                method(&mut out, PREPARE);
                method(&mut out, inner);
                out.extend_from_slice(data);
            }
            Self::Call { method: name, data } => {
                method(&mut out, name);
                out.extend_from_slice(data);
            }
        }
        let length = (out.len() - 4) as u32;
        out[..4].copy_from_slice(&length.to_le_bytes());
        out
    }

    /// The request in a frame's payload, or `None` for one too short to
    /// say what it asks.
    pub(super) fn decode(op: Op, payload: &'a [u8]) -> Option<Self> {
        Some(match op {
            Op::SetValue => Self::SetValue {
                index: le_u32(payload)?,
                value: le_f64(payload.get(4..)?)?,
            },
            Op::SaveState => Self::SaveState,
            Op::LoadState => Self::LoadState(payload),
            Op::OpenEditor => Self::OpenEditor(String::from_utf8_lossy(payload)),
            Op::CloseEditor => Self::CloseEditor,
            Op::SetOffline => Self::SetOffline(payload.first() == Some(&1)),
            Op::Quit => Self::Quit,
            Op::Values => Self::Values,
            Op::Call => {
                let (method, data) = split_method(payload);
                let index = le_u32(data);
                if method == PREPARE {
                    let (method, data) = split_method(data);
                    Self::Prepare { method, data }
                } else if method == PARAM_TEXT
                    && let (Some(index), Some(value)) = (index, data.get(4..).and_then(le_f64))
                {
                    Self::ValueText { index, value }
                } else if method == PARAM_VALUE
                    && let Some(index) = index
                {
                    Self::TextValue {
                        index,
                        text: String::from_utf8_lossy(&data[4..]),
                    }
                } else {
                    Self::Call { method, data }
                }
            }
        })
    }
}

/// A call's method, up to its 0 byte, and the data after it.
fn split_method(payload: &[u8]) -> (Cow<'_, str>, &[u8]) {
    let end = payload
        .iter()
        .position(|b| *b == 0)
        .unwrap_or(payload.len());
    (
        String::from_utf8_lossy(&payload[..end]),
        payload.get(end + 1..).unwrap_or(&[]),
    )
}

fn le_u32(bytes: &[u8]) -> Option<u32> {
    Some(u32::from_le_bytes(bytes.get(..4)?.try_into().ok()?))
}

pub(super) fn le_f64(bytes: &[u8]) -> Option<f64> {
    Some(f64::from_le_bytes(bytes.get(..8)?.try_into().ok()?))
}

/// Bytes that may be absent, as a state and a prepared call are answered:
/// `[0]` for none, `[1][bytes]` for some.
pub(super) fn optional(bytes: Option<Vec<u8>>) -> Vec<u8> {
    match bytes {
        Some(mut bytes) => {
            bytes.insert(0, 1);
            bytes
        }
        None => vec![0],
    }
}

pub(super) fn from_optional(mut answer: Vec<u8>) -> Option<Vec<u8>> {
    (answer.first() == Some(&1)).then(|| answer.split_off(1))
}

/// The first byte of an answer: the plugin did it.
const DONE: u8 = 0;
/// The first byte of an answer: the plugin refused, and the rest says why.
const REFUSED: u8 = 1;

pub(super) fn send(stream: &mut UnixStream, request: &Request) -> std::io::Result<()> {
    stream.write_all(&request.frame())
}

/// Send an answer: what was asked for, or why the plugin refused.
pub(super) fn answer(stream: &mut UnixStream, answer: Result<&[u8], &str>) -> std::io::Result<()> {
    let (first, payload) = match answer {
        Ok(bytes) => (DONE, bytes),
        Err(why) => (REFUSED, why.as_bytes()),
    };
    let mut frame = Vec::with_capacity(payload.len() + 5);
    frame.extend_from_slice(&(payload.len() as u32 + 1).to_le_bytes());
    frame.push(first);
    frame.extend_from_slice(payload);
    stream.write_all(&frame)
}

/// Read an answer: what was asked for, or why the plugin refused.
pub(super) fn receive(stream: &mut UnixStream) -> std::io::Result<Result<Vec<u8>, String>> {
    let mut length = [0u8; 4];
    stream.read_exact(&mut length)?;
    let length = u32::from_le_bytes(length) as usize;
    if length == 0 || length > 1 << 30 {
        return Err(std::io::Error::other("a frame of an impossible size"));
    }
    let mut frame = vec![0u8; length];
    stream.read_exact(&mut frame)?;
    let rest = frame.split_off(1);
    Ok(match frame[0] {
        DONE => Ok(rest),
        _ => Err(String::from_utf8_lossy(&rest).into_owned()),
    })
}

/// The helper's first word: what the plugin that it made is like.
///
/// JSON has no word for a number that is not finite: serde_json writes it
/// as null, and the DAW reads that as 0.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub(super) struct Hello {
    #[serde(deserialize_with = "params_null_as_zero")]
    pub(super) params: Vec<ParamInfo>,
    #[serde(deserialize_with = "values_null_as_zero")]
    pub(super) values: Vec<f64>,
    pub(super) has_editor: bool,
    pub(super) follows_state: bool,
    pub(super) sidechain: bool,
    pub(super) outputs: Vec<String>,
}

impl Hello {
    /// The bytes on the wire. They go through a [`Value`], whose keys are
    /// in order, as the helper has always written them.
    pub(super) fn to_vec(&self) -> serde_json::Result<Vec<u8>> {
        serde_json::to_vec(&serde_json::to_value(self)?)
    }
}

fn params_null_as_zero<'de, D: Deserializer<'de>>(from: D) -> Result<Vec<ParamInfo>, D::Error> {
    let mut params = Vec::<Value>::deserialize(from)?;
    for param in &mut params {
        for key in ["min", "max", "default"] {
            if let Some(number) = param.get_mut(key)
                && number.is_null()
            {
                *number = 0.0.into();
            }
        }
    }
    params
        .into_iter()
        .map(|param| ParamInfo::deserialize(param).map_err(serde::de::Error::custom))
        .collect()
}

fn values_null_as_zero<'de, D: Deserializer<'de>>(from: D) -> Result<Vec<f64>, D::Error> {
    let values = Vec::<Option<f64>>::deserialize(from)?;
    Ok(values.into_iter().map(|v| v.unwrap_or(0.0)).collect())
}

/// The answer to [`Request::Values`]: each value, or `None` for one that
/// was not finite.
pub(super) fn read_values(answer: &[u8]) -> Option<Vec<Option<f64>>> {
    serde_json::from_slice(answer).ok()
}

/// Why a helper is gone, or gave no answer.
#[derive(Clone, Debug, thiserror::Error)]
pub(super) enum HelperError {
    /// It ended: the reason it gave, or how its process ended.
    #[error("{0}")]
    Exited(String),
    /// The plugin refused, saying why.
    #[error("{0}")]
    Refused(String),
    /// No answer to a request within the limit.
    #[error("it did not answer for {} seconds and was ended", .0.as_secs())]
    Silent(Duration),
    #[error(
        "it did not answer for {} seconds while it was being made, and was ended",
        .0.as_secs()
    )]
    SilentMaking(Duration),
    #[error("it did not load its state within {} seconds, and was ended", .0.as_secs())]
    SilentLoading(Duration),
    /// No block answered for this long, while some came late.
    #[error("it stopped answering (no block for {} seconds) and was ended", .0.as_secs())]
    Stalled(Duration),
    /// Given up on by the audio side in a render, with no reason given.
    #[error("it did not answer a block of the render in time and was ended")]
    LateInRender,
    #[error("the connection to it broke ({0})")]
    Broken(String),
    #[error("the connection to it broke")]
    Disconnected,
}

impl HelperError {
    /// What an error of the socket means: `silent` if no answer came in
    /// time, else a broken connection.
    pub(super) fn of_io(err: &std::io::Error, silent: Self) -> Self {
        if silence(err) {
            silent
        } else {
            Self::Broken(err.to_string())
        }
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    fn answered(reply: Result<&[u8], &str>) -> String {
        let (mut ours, mut theirs) = UnixStream::pair().unwrap();
        answer(&mut ours, reply).unwrap();
        drop(ours);
        let mut bytes = Vec::new();
        theirs.read_to_end(&mut bytes).unwrap();
        hex::encode(&bytes)
    }

    /// The bytes of each request and answer as they were before the
    /// protocol had types: a helper and a DAW of other versions still
    /// understand each other.
    #[test]
    fn the_wire_keeps_its_bytes() {
        let cases = [
            (
                Request::SetValue {
                    index: 3,
                    value: 0.5,
                },
                "0d0000000103000000000000000000e03f",
            ),
            (Request::SaveState, "0100000002"),
            (Request::LoadState(b"st\0ate"), "0700000003737400617465"),
            (Request::OpenEditor("Title é".into()), "09000000045469746c6520c3a9"),
            (Request::CloseEditor, "0100000005"),
            (Request::SetOffline(true), "020000000601"),
            (
                Request::Call {
                    method: "m".into(),
                    data: &[1, 2],
                },
                "05000000076d000102",
            ),
            (
                Request::ValueText {
                    index: 2,
                    value: 0.25,
                },
                "1c000000077061772e706172616d2e746578740002000000000000000000d03f",
            ),
            (
                Request::TextValue {
                    index: 2,
                    text: "-3 dB".into(),
                },
                "1a000000077061772e706172616d2e76616c756500020000002d33206442",
            ),
            (
                Request::Prepare {
                    method: "x".into(),
                    data: b"d",
                },
                "140000000773616e64626f782e7072657061726500780064",
            ),
            (Request::Quit, "0100000008"),
            (Request::Values, "0100000009"),
        ];
        for (request, today) in cases {
            let frame = request.frame();
            assert_eq!(hex::encode(&frame), today, "{request:?}");
            let op = Op::try_from(frame[4]).unwrap();
            assert_eq!(Request::decode(op, &frame[5..]), Some(request));
        }
        assert_eq!(answered(Ok(b"yes")), "0400000000796573");
        assert_eq!(answered(Err("no")), "03000000016e6f");
    }

    /// The helper's first word, with numbers that are not finite: JSON has
    /// no word for them, so they cross as null and arrive as 0.
    #[test]
    fn the_first_word_keeps_its_bytes() {
        let params = vec![
            ParamInfo {
                id: "7".into(),
                group: "Osc 1".into(),
                min: f32::NAN,
                max: f32::INFINITY,
                default: 0.1,
                ..ParamInfo::choice("Wave", &["Sine", "Saw"], 1)
            },
            ParamInfo::new("Gain", -24.0, 24.0, f32::NEG_INFINITY, "dB"),
        ];
        let hello = Hello {
            params: params.clone(),
            values: vec![0.5, f64::NAN],
            has_editor: true,
            follows_state: false,
            sidechain: true,
            outputs: vec!["Aux".into()],
        };
        let today = concat!(
            r#"{"follows_state":false,"has_editor":true,"outputs":["Aux"],"params":["#,
            r#"{"automatable":true,"boolean":false,"choices":["Sine","Saw"],"default":0.10000000149011612,"#,
            r#""enumeration":true,"group":"Osc 1","id":"7","key":"Wave","max":null,"min":null,"name":"Wave","#,
            r#""per_note":false,"read_only":false,"steps":1,"unit":""},"#,
            r#"{"automatable":true,"boolean":false,"choices":[],"default":null,"enumeration":false,"#,
            r#""group":"","id":"","key":"Gain","max":24.0,"min":-24.0,"name":"Gain","per_note":false,"#,
            r#""read_only":false,"steps":0,"unit":"dB"}],"sidechain":true,"values":[0.5,null]}"#,
        );
        assert_eq!(String::from_utf8(hello.to_vec().unwrap()).unwrap(), today);
        let read: Hello = serde_json::from_str(today).unwrap();
        let finite = |mut p: ParamInfo| {
            for n in [&mut p.min, &mut p.max, &mut p.default] {
                if !n.is_finite() {
                    *n = 0.0;
                }
            }
            p
        };
        assert_eq!(read.params, params.into_iter().map(finite).collect::<Vec<_>>());
        assert_eq!(read.values, [0.5, 0.0]);
    }
}
