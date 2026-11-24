//! Musical values as a model writes them: note names, positions in beats or
//! `bar.beat`, lengths as beats, bars or note values. Everything is turned
//! into the kernel's units (MIDI note numbers, beats) before it is sent.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::float_cmp, reason = "debt: pay down"))]

use anyhow::{Context, Result, bail};
use arrayvec::ArrayVec;
use paw_types::pitch;
use serde_json::{Value, json};

/// Signature changes a [`Meter`] keeps after the first; later ones are
/// left out of `bar.beat` positions.
const MAX_CHANGES: usize = 31;

/// The project's time signatures, which `bar.beat` positions depend on: the
/// one at the start, and where it changes along the song (each change
/// starting a bar, as paw's tempo map has them).
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Meter {
    pub num: u32,
    pub den: u32,
    changes: ArrayVec<Change, MAX_CHANGES>,
}

/// One signature change: where it is, the signature and the bar it starts.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Change {
    beat: f64,
    num: u32,
    den: u32,
    /// Index of the bar the change starts.
    bar: i64,
}

impl Default for Meter {
    fn default() -> Self {
        Self::new(4, 4)
    }
}

impl Meter {
    pub(crate) fn new(num: u32, den: u32) -> Self {
        Self {
            num: num.max(1),
            den: den.max(1),
            changes: ArrayVec::new(),
        }
    }

    pub(crate) fn from_project(project: &Value) -> Self {
        let mut meter = Self::new(
            project["sig_num"].as_u64().unwrap_or(4) as u32,
            project["sig_den"].as_u64().unwrap_or(4) as u32,
        );
        if let Some(list) = project["sig_changes"].as_array() {
            for c in list {
                let (beat, num, den) = (
                    c["beat"].as_f64().unwrap_or(0.0),
                    c["num"].as_u64().unwrap_or(4).max(1) as u32,
                    c["den"].as_u64().unwrap_or(4).max(1) as u32,
                );
                meter.add(beat, num, den);
            }
        }
        meter
    }

    /// A signature change starting a bar at `beat`, after those added before.
    pub(crate) fn add(&mut self, beat: f64, num: u32, den: u32) {
        if self.changes.is_full() {
            return;
        }
        let (start, sig_num, sig_den, bar) = self.segment_at_beat(beat);
        let len = sig_num as f64 * 4.0 / sig_den as f64;
        let bars = ((beat - start) / len - 1e-9).ceil().max(1.0) as i64;
        self.changes.push(Change {
            beat,
            num: num.max(1),
            den: den.max(1),
            bar: bar + bars,
        });
    }

    /// The stretch of one signature a beat is in: (start, num, den, first bar).
    fn segment_at_beat(&self, beat: f64) -> (f64, u32, u32, i64) {
        let mut seg = (0.0, self.num, self.den, 0);
        for c in &self.changes {
            if c.beat <= beat + 1e-9 {
                seg = (c.beat, c.num, c.den, c.bar);
            }
        }
        seg
    }

    fn segment_at_bar(&self, bar: i64) -> (f64, u32, u32, i64) {
        let mut seg = (0.0, self.num, self.den, 0);
        for c in &self.changes {
            if c.bar <= bar {
                seg = (c.beat, c.num, c.den, c.bar);
            }
        }
        seg
    }

    /// Where bar `bar` (counting from 0) starts, and its signature.
    pub(crate) fn bar_start(&self, bar: i64) -> (f64, u32, u32) {
        let (start, num, den, first) = self.segment_at_bar(bar);
        (
            start + (bar - first) as f64 * num as f64 * 4.0 / den as f64,
            num,
            den,
        )
    }

    /// Length of a bar in beats (quarter notes): the first bar's.
    pub(crate) fn bar(&self) -> f64 {
        self.num as f64 * 4.0 / self.den as f64
    }

    /// `bar.beat.hundredths`, counting from 1, as paw shows positions.
    pub(crate) fn format(&self, beats: f64) -> String {
        let (start, num, den, first) = self.segment_at_beat(beats);
        let len = num as f64 * 4.0 / den as f64;
        let unit = 4.0 / den as f64;
        let whole = ((beats - start) / len + 1e-9).floor();
        let bar = (first as f64 + whole).max(0.0);
        let in_bar = beats - start - whole * len;
        let beat = (in_bar / unit + 1e-9).floor();
        let part = (((in_bar / unit - beat) * 100.0).round() as i64).min(99);
        if part == 0 {
            format!("{}.{}", bar as i64 + 1, beat as i64 + 1)
        } else {
            format!("{}.{}.{:02}", bar as i64 + 1, beat as i64 + 1, part)
        }
    }
}

/// A number with no more decimals than it needs: 4, 0.5, 0.333.
pub(crate) fn num(value: f64) -> String {
    if !value.is_finite() {
        return format!("{value}");
    }
    let text = format!("{value:.3}");
    let text = text.trim_end_matches('0').trim_end_matches('.');
    if text == "-0" {
        "0".into()
    } else {
        text.into()
    }
}

/// A position: a JSON number is beats from the start (of the project, or of
/// the clip for notes); a string is `bar`, `bar.beat` or `bar.beat.hundredths`
/// counting from 1 (or with colons, `bar:beat`), or beats written as `"6b"`.
pub(crate) fn position(value: &Value, meter: &Meter, what: &str) -> Result<f64> {
    let beats = match value {
        Value::Number(n) => n.as_f64().context("not a number")?,
        Value::String(text) => parse_position(text.trim(), meter)
            .with_context(|| format!("bad {what} `{text}`: use beats as a JSON number (4.5), or a string counting bars and beats from 1: \"3.1\", \"3:1\", \"2.3.50\" or \"bar 3 beat 1\", with the beat inside the bar ({}/{})", meter.num, meter.den))?,
        _ => bail!("{what} must be a number of beats or a \"bar.beat\" string"),
    };
    if !beats.is_finite() || beats < 0.0 {
        bail!("{what} must be 0 or later, not {beats}");
    }
    Ok(beats)
}

/// `bar 5`, `bar 5 beat 2`, `bar 5, beat 2.5`: the words some models write.
fn parse_spoken(text: &str, meter: &Meter) -> Option<f64> {
    let lower = text.to_ascii_lowercase().replace(',', " ");
    let mut words = lower.split_whitespace();
    if words.next()? != "bar" {
        return None;
    }
    let bar: i64 = words.next()?.parse().ok().filter(|b| *b >= 1)?;
    let (start, num, den) = meter.bar_start(bar - 1);
    let beat: f64 = match words.next() {
        None => 1.0,
        Some("beat") => words.next()?.parse().ok().filter(|b| *b >= 1.0 && *b < num as f64 + 1.0)?,
        Some(_) => return None,
    };
    words.next().is_none().then_some(start + (beat - 1.0) * 4.0 / den as f64)
}

fn parse_position(text: &str, meter: &Meter) -> Option<f64> {
    if text.len() > 3 && text[..3].eq_ignore_ascii_case("bar") && text[3..].starts_with([' ', ',']) {
        return parse_spoken(text, meter);
    }
    if let Some(beats) = text
        .strip_suffix("beats")
        .or_else(|| text.strip_suffix("beat"))
        .or_else(|| text.strip_suffix('b'))
    {
        return beats.trim().parse().ok();
    }
    let separator = if text.contains(':') { ':' } else { '.' };
    let parts: Vec<&str> = text.split(separator).collect();
    if parts.len() > 3 || parts.iter().any(|p| p.is_empty()) {
        return None;
    }
    let bar: f64 = parts[0].parse::<u32>().ok().filter(|b| *b >= 1)? as f64;
    let beat: f64 = match parts.get(1) {
        Some(p) => {
            p.parse::<u32>()
                .ok()
                .filter(|b| *b >= 1 && *b <= meter.bar_start(bar as i64 - 1).1)? as f64
        }
        None => 1.0,
    };
    let hundredths: f64 = match parts.get(2) {
        Some(p) => {
            let digits = p.parse::<u32>().ok()? as f64;
            // "3.1.5" is half a beat on, like "3.1.50".
            if p.len() == 1 { digits * 10.0 } else { digits }
        }
        None => 0.0,
    };
    let (start, _, den) = meter.bar_start(bar as i64 - 1);
    Some(start + (beat - 1.0 + hundredths / 100.0) * 4.0 / den as f64)
}

/// A length: a JSON number is beats; a string is beats (`"3b"`), bars
/// (`"2 bars"`, `"1bar"`) or a note value as a fraction of a whole note
/// (`"1/8"` is half a beat, `"3/16"`, `"1/4."` dotted).
pub(crate) fn length(value: &Value, meter: &Meter, what: &str) -> Result<f64> {
    let beats = match value {
        Value::Number(n) => n.as_f64().context("not a number")?,
        Value::String(text) => parse_length(text.trim(), meter).with_context(|| {
            format!("bad {what} `{text}`: use beats as a number (0.5), \"2 bars\", or a note value such as \"1/8\"")
        })?,
        _ => bail!("{what} must be a number of beats, \"N bars\" or a note value like \"1/8\""),
    };
    if !beats.is_finite() || beats <= 0.0 {
        bail!("{what} must be above 0");
    }
    Ok(beats)
}

fn parse_length(text: &str, meter: &Meter) -> Option<f64> {
    let lower = text.to_ascii_lowercase();
    for (suffix, scale) in [
        ("bars", meter.bar()),
        ("bar", meter.bar()),
        ("beats", 1.0),
        ("beat", 1.0),
        ("b", 1.0),
    ] {
        if let Some(n) = lower.strip_suffix(suffix) {
            return n.trim().parse::<f64>().ok().map(|n| n * scale);
        }
    }
    let (fraction, dotted) = match lower.strip_suffix('.') {
        Some(f) => (f, true),
        None => (lower.as_str(), false),
    };
    if let Some((a, b)) = fraction.split_once('/') {
        let a: f64 = a.trim().parse().ok()?;
        let b: f64 = b.trim().parse().ok()?;
        if b == 0.0 {
            return None;
        }
        let beats = 4.0 * a / b;
        return Some(if dotted { beats * 1.5 } else { beats });
    }
    lower.parse().ok()
}

/// `C4` is 60, middle C. Sharps `#`, flats `b`, octaves from -1 to 9.
pub(crate) fn pitch_name(text: &str) -> Result<u8> {
    let text = text.trim();
    if let Ok(n) = text.parse::<i64>() {
        return midi(n, text);
    }
    if text.is_empty() {
        bail!("empty pitch");
    }
    let n = pitch::parse(text).with_context(|| {
        format!("not a note name: `{text}` (use names like C4, F#3, Bb2, or MIDI numbers)")
    })?;
    midi(n, text)
}

fn midi(n: i64, text: &str) -> Result<u8> {
    if !(0..=127).contains(&n) {
        bail!("pitch `{text}` is outside MIDI's 0 to 127 (C-1 to G9)");
    }
    Ok(n as u8)
}

pub(crate) fn name(pitch: u8) -> String {
    pitch::name(i32::from(pitch))
}

/// One pitch or a chord: `"C4"`, `60`, `"C4+E4+G4"`, `["C4", "E4"]`.
pub(crate) fn pitches(value: &Value) -> Result<Vec<u8>> {
    match value {
        Value::Number(n) => Ok(vec![midi(
            n.as_i64().context("pitch must be a whole number")?,
            &n.to_string(),
        )?]),
        Value::String(s) => s.split('+').map(pitch_name).collect(),
        Value::Array(items) => {
            let mut out = Vec::new();
            for item in items {
                out.extend(pitches(item)?);
            }
            Ok(out)
        }
        _ => bail!("pitch must be a note name like \"C4\", a MIDI number, or a chord \"C4+E4+G4\""),
    }
}

/// Notes as the kernel takes them, `start` relative to the clip, from either
/// objects `{pitch, start, length, velocity}` or strings
/// `"pitch start length [velocity]"` such as `"C4+E4 1:3 1/8 90"`, where the
/// start is beats ("2.5") or bar:beat within the clip ("1:3").
/// A note with no length is one beat long.
pub(crate) fn notes(value: &Value, meter: &Meter) -> Result<Vec<Value>> {
    let items = match value {
        Value::Array(items) => items,
        Value::Null => return Ok(Vec::new()),
        _ => bail!("notes must be a list"),
    };
    let mut out = Vec::new();
    for (i, item) in items.iter().enumerate() {
        note(item, meter, &mut out).with_context(|| format!("note {}", i + 1))?;
    }
    Ok(out)
}

fn note(item: &Value, meter: &Meter, out: &mut Vec<Value>) -> Result<()> {
    let (pitch, start, len, velocity) = match item {
        Value::String(text) => {
            let words: Vec<&str> = text.split_whitespace().collect();
            if words.len() < 2 || words.len() > 4 {
                bail!(
                    "`{text}`: write \"pitch start [length] [velocity]\", such as \"C4 1.1 1/4 100\" or \"E4 2 0.5\""
                );
            }
            // In a note string a number is beats ("0.5"), and bar:beat
            // takes colons ("1:3"), since a dot would be a decimal point.
            let start = match words[1].parse::<f64>() {
                Ok(n) => json!(n),
                Err(_) => json!(words[1]),
            };
            let len = words.get(2).map(|w| match w.parse::<f64>() {
                Ok(n) => json!(n),
                Err(_) => json!(w),
            });
            let velocity = match words.get(3) {
                Some(v) => Some(
                    v.parse::<f64>()
                        .with_context(|| format!("bad velocity `{v}`"))?,
                ),
                None => None,
            };
            (json!(words[0]), start, len, velocity)
        }
        Value::Object(map) => {
            let pitch = map.get("pitch").context("a note needs a `pitch`")?.clone();
            let start = map.get("start").cloned().unwrap_or(json!(0));
            let len = map.get("length").cloned();
            let velocity = match map.get("velocity") {
                Some(v) => Some(
                    v.as_f64()
                        .context("velocity must be a number from 1 to 127")?,
                ),
                None => None,
            };
            (pitch, start, len, velocity)
        }
        _ => bail!(
            "a note is an object {{pitch, start, length, velocity}} or a string \"C4 1.1 1/4 100\""
        ),
    };
    let start = note_start(&start, meter)?;
    let len = match len {
        Some(l) => length(&l, meter, "length")?,
        None => 1.0,
    };
    let velocity = velocity.unwrap_or(100.0);
    if !(1.0..=127.0).contains(&velocity) {
        bail!("velocity must be from 1 to 127, not {velocity}");
    }
    for pitch in pitches(&pitch)? {
        out.push(json!({
            "pitch": pitch, "start": start, "length": len, "velocity": velocity.round() as u8,
        }));
    }
    Ok(())
}

/// A note's start inside its clip. As a string, `bar.beat` counts from the
/// clip's own first bar: "1.1" is the clip's start.
pub(crate) fn note_start(value: &Value, meter: &Meter) -> Result<f64> {
    position(value, meter, "start")
}

/// A signature such as "3/4" or "6/8".
pub(crate) fn signature(text: &str) -> Result<(u32, u32)> {
    let (n, d) = text
        .split_once('/')
        .with_context(|| format!("bad time signature `{text}`: write it as \"3/4\""))?;
    let n: u32 = n.trim().parse().context("bad time signature numerator")?;
    let d: u32 = d.trim().parse().context("bad time signature denominator")?;
    if !(1..=64).contains(&n) || ![1, 2, 4, 8, 16, 32, 64].contains(&d) {
        bail!("time signature `{text}` is out of range");
    }
    Ok((n, d))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pitches_by_name() {
        assert_eq!(pitch_name("C4").unwrap(), 60);
        assert_eq!(pitch_name("A4").unwrap(), 69);
        assert_eq!(pitch_name("F#3").unwrap(), 54);
        assert_eq!(pitch_name("Bb2").unwrap(), 46);
        assert_eq!(pitch_name("C-1").unwrap(), 0);
        assert_eq!(pitch_name("64").unwrap(), 64);
        assert!(pitch_name("H2").is_err());
        assert!(pitch_name("G10").is_err());
        assert_eq!(name(61), "C#4");
        assert_eq!(pitches(&json!("C4+E4+G4")).unwrap(), vec![60, 64, 67]);
    }

    #[test]
    fn positions_and_lengths() {
        let m = Meter::default();
        assert_eq!(position(&json!(2.5), &m, "p").unwrap(), 2.5);
        assert_eq!(position(&json!("1.1"), &m, "p").unwrap(), 0.0);
        assert_eq!(position(&json!("3"), &m, "p").unwrap(), 8.0);
        assert_eq!(position(&json!("2.3"), &m, "p").unwrap(), 6.0);
        assert_eq!(position(&json!("2:3"), &m, "p").unwrap(), 6.0);
        assert_eq!(position(&json!("2.3.50"), &m, "p").unwrap(), 6.5);
        assert_eq!(position(&json!("6b"), &m, "p").unwrap(), 6.0);
        assert_eq!(position(&json!("bar 5"), &m, "p").unwrap(), 16.0);
        assert_eq!(position(&json!("bar 5 beat 2"), &m, "p").unwrap(), 17.0);
        assert_eq!(position(&json!("Bar 2, beat 3.5"), &m, "p").unwrap(), 6.5);
        assert!(position(&json!("bar 2 beat 5"), &m, "p").is_err());
        assert!(position(&json!("bar"), &m, "p").is_err());
        assert!(position(&json!("0.1"), &m, "p").is_err());
        assert!(position(&json!("2.5"), &m, "p").is_err());
        let six8 = Meter::new(6, 8);
        let mut changing = Meter::default();
        changing.add(32.0, 6, 8);
        assert_eq!(position(&json!("9.4"), &changing, "p").unwrap(), 33.5);
        assert_eq!(position(&json!("10"), &changing, "p").unwrap(), 35.0);
        assert_eq!(changing.format(33.5), "9.4");
        assert_eq!(changing.format(31.0), "8.4");
        assert_eq!(position(&json!("2.4"), &six8, "p").unwrap(), 4.5);
        assert_eq!(length(&json!("1/8"), &m, "l").unwrap(), 0.5);
        assert_eq!(length(&json!("1/4."), &m, "l").unwrap(), 1.5);
        assert_eq!(length(&json!("2 bars"), &m, "l").unwrap(), 8.0);
        assert_eq!(length(&json!("3b"), &m, "l").unwrap(), 3.0);
        assert!(length(&json!(0), &m, "l").is_err());
        assert_eq!(m.format(6.5), "2.3.50");
        assert_eq!(m.format(0.0), "1.1");
        assert_eq!(num(0.5), "0.5");
        assert_eq!(num(4.0), "4");
    }

    #[test]
    fn note_forms() {
        let m = Meter::default();
        let n = notes(
            &json!(["C4 1:2 1/8 90", {"pitch": "E4", "start": 2}, "G4+B4 3 2", "D4 0.5"]),
            &m,
        )
        .unwrap();
        assert_eq!(n.len(), 5);
        assert_eq!(
            n[0],
            json!({"pitch": 60, "start": 1.0, "length": 0.5, "velocity": 90})
        );
        assert_eq!(n[4]["start"], json!(0.5));
        assert_eq!(n[1]["start"], json!(2.0));
        assert_eq!(n[1]["length"], json!(1.0));
        assert_eq!(n[2]["start"], json!(3.0));
        assert_eq!(n[3]["pitch"], json!(71));
        assert!(notes(&json!(["C4"]), &m).is_err());
        assert!(notes(&json!([{"pitch": "C4", "velocity": 200}]), &m).is_err());
    }
}
