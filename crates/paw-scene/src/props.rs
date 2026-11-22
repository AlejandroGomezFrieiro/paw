//! What a role node shows (its `props`), role by role, as the window reads
//! it: runtime/lua/paw/roles/widgets.lua and the views give these tables,
//! and paw-gui paints from them. tools/apidoc.lua reads this file and
//! writes runtime/types/paw/role_props.d.tl, a Teal record for each struct.
//!
//! Each field is optional: what a view leaves out reads as its default
//! (nothing, 0, false). Props that do not have the shape of their role read
//! as all defaults (see [`parse`]).

use serde::de::{Deserializer, IgnoredAny, SeqAccess, Visitor};
use serde::Deserialize;
use serde_json::Value;

/// The props of a role as `T`: all defaults when they do not fit.
pub fn parse<'a, T: Deserialize<'a> + Default>(props: &'a Value) -> T {
    match props {
        Value::Object(_) => T::deserialize(props).unwrap_or_default(),
        _ => T::default(),
    }
}

/// A list of numbers with gaps: what is not a number (`false`) is none.
fn numbers_or_none<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<Option<f64>>, D::Error> {
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Item {
        Number(f64),
        Other(IgnoredAny),
    }
    let items = Vec::<Item>::deserialize(d)?;
    Ok(items.into_iter().map(|i| if let Item::Number(n) = i { Some(n) } else { None }).collect())
}

/// What a key of a piano is called: `{ pitch, name }`, and what else the
/// cells use (a style), which the window leaves alone.
#[derive(Debug, Default, PartialEq)]
pub struct KeyName<'a> {
    pub pitch: i64,
    pub name: &'a str,
}

impl<'de: 'a, 'a> Deserialize<'de> for KeyName<'a> {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        struct Seq<'a>(std::marker::PhantomData<&'a ()>);
        impl<'de: 'a, 'a> Visitor<'de> for Seq<'a> {
            type Value = KeyName<'a>;
            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str("{ pitch, name }")
            }
            fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<KeyName<'a>, A::Error> {
                let missing = || serde::de::Error::custom("a key's name is { pitch, name }");
                let pitch = seq.next_element()?.ok_or_else(missing)?;
                let name = seq.next_element()?.ok_or_else(missing)?;
                while seq.next_element::<IgnoredAny>()?.is_some() {}
                Ok(KeyName { pitch, name })
            }
        }
        d.deserialize_seq(Seq(std::marker::PhantomData))
    }
}

/// What every role may have: what it is called, for whoever reads the
/// window without seeing it.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct RoleProps<'a> {
    pub label: Option<&'a str>,
}

/// A line of text: `align` "left", "right" or "center"; `font` "sans" for
/// words or "title" for a heading (else monospace); `tone` a colour of the
/// palette; `capital` its first letter in capitals; `strike` a line through.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct LabelProps<'a> {
    pub text: Option<&'a str>,
    pub align: Option<&'a str>,
    pub font: Option<&'a str>,
    pub tone: Option<&'a str>,
    pub capital: bool,
    pub strike: bool,
    pub label: Option<&'a str>,
}

/// A button: `on` lit, `off` dimmed, `quiet` a face only under the pointer,
/// `menu` with a caret; its `text`, or `words` in place of the cells'
/// glyph, and `icon` the name of an icon for that glyph.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct ButtonProps<'a> {
    pub text: Option<&'a str>,
    pub words: Option<&'a str>,
    pub icon: Option<&'a str>,
    pub tone: Option<&'a str>,
    pub on: bool,
    pub off: bool,
    pub quiet: bool,
    pub menu: bool,
    pub label: Option<&'a str>,
}

/// A switch: `on`, its `letter` or `icon`, lit in `tone`.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct SwitchProps<'a> {
    pub on: bool,
    pub letter: Option<&'a str>,
    pub icon: Option<&'a str>,
    pub tone: Option<&'a str>,
    pub label: Option<&'a str>,
}

/// A pan (`value` -1 to 1), round with `round`.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct KnobProps<'a> {
    pub value: f64,
    pub round: bool,
    pub label: Option<&'a str>,
}

/// A parameter: a slider `bar` cells long, filled to `fraction` (0 to 1),
/// from the middle when `centred`, a mark for each of a few `steps`; its
/// value as `text`; `dim` when it does not apply.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct ParamProps<'a> {
    pub fraction: f64,
    pub text: Option<&'a str>,
    pub bar: f64,
    pub centred: bool,
    pub steps: u64,
    pub dim: bool,
    pub label: Option<&'a str>,
}

/// The playhead at beat `at`: in a view whose columns are `per` cells a
/// beat from beat `from`, shown from `lo` to `hi`; or along `segments` of
/// time, `{ from, to, x0, x1, top, bottom }` each, in points.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct PlayheadProps {
    pub at: Option<f64>,
    pub from: f64,
    pub per: Option<f64>,
    pub lo: Option<f64>,
    pub hi: Option<f64>,
    pub segments: Option<Vec<Vec<f64>>>,
}

/// Level meters, `levels` a linear peak for each column; `hold` the
/// loudest of late, `clipped` the clip light.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct MeterProps<'a> {
    pub levels: Vec<f64>,
    pub hold: f64,
    pub clipped: bool,
    pub label: Option<&'a str>,
}

/// A level across a row (a meter, see `MeterProps`), with a fader's cap at
/// `at` (0 to 1).
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct HmeterProps<'a> {
    pub levels: Vec<f64>,
    pub hold: f64,
    pub clipped: bool,
    pub at: Option<f64>,
    pub label: Option<&'a str>,
}

/// A take being recorded from beat `start` to the playhead at `at`, as far
/// as the punch-out `to`, in columns `per` cells a beat.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct RecordingProps {
    pub start: f64,
    pub at: f64,
    pub to: Option<f64>,
    pub per: f64,
}

/// A device's power button, `on` while it plays.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct PowerProps<'a> {
    pub on: bool,
    pub label: Option<&'a str>,
}

/// A card's heading: `selected` where the cursor is, `off` dimmed.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct BandProps<'a> {
    pub selected: bool,
    pub off: bool,
    pub label: Option<&'a str>,
}

/// A note: its track's `color` (`#rrggbb`), its `velocity` (1 to 127), its
/// name as `label`; `selected`, `cursor`, `ghost` while it is dragged and
/// `pending` while it is drawn; `bend`, its own pitch bend at its end in
/// semitones, reached from `bend_at` (0 to 1) of its length.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct NoteProps<'a> {
    pub color: Option<&'a str>,
    pub velocity: f64,
    pub label: Option<&'a str>,
    pub selected: bool,
    pub cursor: bool,
    pub ghost: bool,
    pub pending: bool,
    pub bend: f64,
    pub bend_at: f64,
}

/// A piano down a roll: `top` the pitch of its first row, `cursor` the
/// cursor's pitch; `names` and `labels`, `{ pitch, name }` each, what keys
/// are called; `sounding`, the pitches that sound at the cursor.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct KeyboardProps<'a> {
    pub top: Option<i64>,
    pub cursor: Option<i64>,
    /// @type {{integer, string}}
    #[serde(borrow)]
    pub names: Vec<KeyName<'a>>,
    /// @type {{integer, string, string}}
    #[serde(borrow)]
    pub labels: Vec<KeyName<'a>>,
    pub sounding: Vec<i64>,
}

/// A scroll bar along `axis` ("x" or "y"): `span` of `total` shows, from
/// `from`.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct ScrollbarProps<'a> {
    pub axis: Option<&'a str>,
    pub from: f64,
    pub span: f64,
    pub total: f64,
}

/// A fader with its cap at `at` (0 to 1) and 0 dB at `zero`.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct FaderProps<'a> {
    pub at: f64,
    pub zero: Option<f64>,
    pub selected: bool,
    pub label: Option<&'a str>,
}

/// A track's name on its `color`, with its `number`.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct ChipProps<'a> {
    pub text: Option<&'a str>,
    pub color: Option<&'a str>,
    pub number: Option<i64>,
    pub selected: bool,
    pub label: Option<&'a str>,
}

/// A clip of the timeline (`id`), or one of its takes (`take`, `active`
/// when it plays): its `name` or `label`, its track's `color`, `length`
/// beats in columns `per` cells a beat; `content` the key of its notes or
/// sound; `midi`; `muted`, `current`, `chosen`, `ghost` while it is
/// dragged; its fades and `gain` (shown with `gain_line`) in beats and dB;
/// `warps` and `repeats`, the beats of its warp markers and its loops;
/// `cut_in` and `cut_out`, the beats from its start where the window's
/// scope cuts it.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct ClipProps<'a> {
    pub id: Option<i64>,
    pub take: Option<i64>,
    pub content: Option<&'a str>,
    pub name: Option<&'a str>,
    pub label: Option<&'a str>,
    pub color: Option<&'a str>,
    pub length: f64,
    pub per: f64,
    pub midi: bool,
    pub muted: bool,
    pub current: bool,
    pub chosen: bool,
    pub ghost: bool,
    pub active: bool,
    pub fade_in: f64,
    pub fade_out: f64,
    pub gain: f64,
    pub gain_line: bool,
    pub warps: Vec<f64>,
    pub repeats: Vec<f64>,
    pub cut_in: Option<f64>,
    pub cut_out: Option<f64>,
}

/// The ground of a row of the timeline, `index` from the top, in columns
/// `per` cells a beat from beat `from`: `tone` "take" or "auto" for a take
/// lane or an automation lane, `selected` for the cursor's track; the loop
/// (`loop`, `{ start, end }`) shaded; `lines`, `{ beat, bar }` each, a
/// line on each bar, and on each beat with `beats`.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct BeatsProps<'a> {
    pub index: i64,
    pub tone: Option<&'a str>,
    pub selected: bool,
    pub from: f64,
    pub per: f64,
    #[serde(rename = "loop")]
    pub looped: Option<(f64, f64)>,
    pub beats: bool,
    pub lines: Vec<(f64, bool)>,
}

/// A curve: `values` (0 to 1, one each half column, nil where there is
/// none) and its `points`, `{ beat, value }` each, in columns `per` cells a
/// beat from beat `from`; its track's `color`, grey when not `enabled`.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct CurveProps<'a> {
    /// @type {number | boolean}
    #[serde(deserialize_with = "numbers_or_none")]
    pub values: Vec<Option<f64>>,
    pub points: Vec<(f64, f64)>,
    pub from: f64,
    pub per: f64,
    pub color: Option<&'a str>,
    pub enabled: Option<bool>,
}

/// A track's header: its `color`, `selected` for the cursor's track.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct TrackheadProps<'a> {
    pub color: Option<&'a str>,
    pub selected: bool,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn props_read_by_role_and_a_wrong_shape_reads_as_defaults() {
        let props = json!({ "text": "Bass", "strike": true, "loop": [1, 2] });
        let label: LabelProps = parse(&props);
        assert_eq!((label.text, label.strike, label.capital), (Some("Bass"), true, false));
        let beats: BeatsProps = parse(&props);
        assert_eq!(beats.looped, Some((1.0, 2.0)), "a field named as Lua names it");
        let (wrong, empty) = (json!({ "text": 5 }), json!([]));
        assert_eq!(parse::<LabelProps>(&wrong).text, None);
        assert_eq!(parse::<LabelProps>(&empty).text, None, "an empty Lua table comes as a list");
        let curve = json!({ "values": [0.5, false, 1] });
        assert_eq!(parse::<CurveProps>(&curve).values, vec![Some(0.5), None, Some(1.0)], "false is a gap");
        let keys = json!({ "labels": [[60, "kick", "Style"]] });
        let labels = parse::<KeyboardProps>(&keys).labels;
        assert_eq!(labels, vec![KeyName { pitch: 60, name: "kick" }], "the cells' style is left alone");
    }
}
