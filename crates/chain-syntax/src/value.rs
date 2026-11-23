//! The values of the language: numbers with units, note values, texts,
//! references and lists, and how each one is written.
//!
//! A number keeps its value in the base unit of its dimension (hertz for
//! `kHz`, seconds for `ms`). A change of unit moves the decimal point in the
//! digits, not a multiplication of floats, so `2.5kHz` is exactly 2500 Hz
//! and prints again as `2.5kHz`.

use std::fmt::{self, Write as _};

use serde::{Deserialize, Serialize};

/// What a number measures. Each dimension has one base unit, in which a
/// [`Number`] keeps its value.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Dimension {
    /// Decibels: `dB`.
    Gain,
    /// Hertz: `Hz`, and `kHz` for a thousand.
    Frequency,
    /// Seconds: `s`, and `ms` for a thousandth.
    Time,
    /// Percent: `%`.
    Percent,
    /// Semitones: `st`.
    Pitch,
}

/// A unit that a number can have in the text.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Unit {
    #[serde(rename = "dB")]
    Decibel,
    #[serde(rename = "Hz")]
    Hertz,
    #[serde(rename = "kHz")]
    Kilohertz,
    #[serde(rename = "ms")]
    Millisecond,
    #[serde(rename = "s")]
    Second,
    #[serde(rename = "%")]
    Percent,
    #[serde(rename = "st")]
    Semitone,
}

impl Unit {
    /// Each unit, in the order that the reference page lists them.
    pub const ALL: [Unit; 7] = [
        Unit::Decibel,
        Unit::Hertz,
        Unit::Kilohertz,
        Unit::Millisecond,
        Unit::Second,
        Unit::Percent,
        Unit::Semitone,
    ];

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Decibel => "dB",
            Self::Hertz => "Hz",
            Self::Kilohertz => "kHz",
            Self::Millisecond => "ms",
            Self::Second => "s",
            Self::Percent => "%",
            Self::Semitone => "st",
        }
    }

    pub fn from_suffix(suffix: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|unit| unit.as_str() == suffix)
    }

    pub const fn dimension(self) -> Dimension {
        match self {
            Self::Decibel => Dimension::Gain,
            Self::Hertz | Self::Kilohertz => Dimension::Frequency,
            Self::Millisecond | Self::Second => Dimension::Time,
            Self::Percent => Dimension::Percent,
            Self::Semitone => Dimension::Pitch,
        }
    }

    /// The power of ten of one of this unit in the base unit: 3 for `kHz`.
    pub(crate) const fn exponent(self) -> i32 {
        match self {
            Self::Kilohertz => 3,
            Self::Millisecond => -3,
            _ => 0,
        }
    }

    /// `value` in this unit, in the base unit of its dimension.
    pub fn to_base(self, value: f64) -> f64 {
        scale(value, self.exponent())
    }
}

impl Dimension {
    /// The unit that the printer writes for `value` (in the base unit).
    /// Frequencies of a thousand hertz or more are in `kHz`, and times
    /// under a second in `ms`.
    pub fn unit_for(self, value: f64) -> Unit {
        match self {
            Self::Gain => Unit::Decibel,
            Self::Frequency if value.abs() >= 1000.0 => Unit::Kilohertz,
            Self::Frequency => Unit::Hertz,
            Self::Time if value.abs() >= 1.0 => Unit::Second,
            Self::Time => Unit::Millisecond,
            Self::Percent => Unit::Percent,
            Self::Pitch => Unit::Semitone,
        }
    }
}

/// A number, with the dimension of its unit. `value` is in the base unit
/// of the dimension.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Number {
    pub value: f64,
    pub dimension: Option<Dimension>,
}

impl Number {
    pub const fn plain(value: f64) -> Self {
        Self { value, dimension: None }
    }

    pub const fn with(value: f64, dimension: Dimension) -> Self {
        Self { value, dimension: Some(dimension) }
    }

    /// The number as the printer writes it: the digits of the shortest
    /// decimal that reads back as the same float, then the unit.
    /// `signed` writes `+` before a positive number, as a modulation depth
    /// has it.
    pub fn write(&self, out: &mut String, signed: bool) {
        let (digits, unit) = match self.dimension {
            None => (decimal(self.value), None),
            Some(dimension) => {
                let unit = dimension.unit_for(self.value);
                (shift(&decimal(self.value), -unit.exponent()), Some(unit))
            }
        };
        if signed && !digits.starts_with('-') {
            out.push('+');
        }
        out.push_str(&digits);
        if let Some(unit) = unit {
            out.push_str(unit.as_str());
        }
    }
}

/// How a note value is played: straight, dotted (`1/8.`) or as a triplet
/// (`1/8t`).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Feel {
    Straight,
    Dotted,
    Triplet,
}

/// A length in notes, such as `1/4` (a quarter note) or `3/16`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Note {
    pub count: u32,
    pub division: u32,
    pub feel: Feel,
}

impl fmt::Display for Note {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}/{}", self.count, self.division)?;
        match self.feel {
            Feel::Straight => Ok(()),
            Feel::Dotted => f.write_char('.'),
            Feel::Triplet => f.write_char('t'),
        }
    }
}

impl std::str::FromStr for Note {
    type Err = ();

    /// Reads a note value as the language writes it: `1/4`, `1/8.`, `1/8t`.
    fn from_str(text: &str) -> Result<Self, ()> {
        crate::lex::note_value(text).ok_or(())
    }
}

/// What `@` names: the input of the chain, or a node by its id.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Reference {
    /// `@in`: the signal that comes into the chain.
    Input,
    /// `@id`: the output of a node of the chain.
    Node(String),
}

/// A value of a field.
#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Number(Number),
    Note(Note),
    /// A word or a quoted text: `on`, `tube`, `"Lead vox"`. The two are one
    /// value: the printer quotes a text only when it must.
    Text(String),
    Reference(Reference),
    /// Values separated by commas: `150Hz,2.5kHz`. A list holds no list.
    List(Vec<Value>),
}

/// The shortest decimal digits that read back as `value`, with no
/// exponent. Rust's `Display` of a float gives them.
fn decimal(value: f64) -> String {
    format!("{value}")
}

/// `value` times ten to the power `exponent`, exact to the digits: the
/// decimal point of the digits moves, and the result is read again.
pub(crate) fn scale(value: f64, exponent: i32) -> f64 {
    if exponent == 0 {
        return value;
    }
    shift(&decimal(value), exponent).parse().unwrap_or(value)
}

/// Moves the decimal point of `digits` (`-12.5`) by `places`: to the right
/// for a positive count. The result has no leading or trailing zeros that
/// a number does not need.
pub(crate) fn shift(digits: &str, places: i32) -> String {
    let (sign, digits) = digits.strip_prefix('-').map_or(("", digits), |rest| ("-", rest));
    let (whole, fraction) = digits.split_once('.').unwrap_or((digits, ""));
    let all: String = format!("{whole}{fraction}");
    // The place of the point, counted from the start of `all`.
    let point = whole.len() as i64 + i64::from(places);
    let (mut integer, mut fraction) = if point <= 0 {
        (String::from("0"), "0".repeat(point.unsigned_abs() as usize) + &all)
    } else if point as usize >= all.len() {
        (all.clone() + &"0".repeat(point as usize - all.len()), String::new())
    } else {
        (all[..point as usize].to_string(), all[point as usize..].to_string())
    };
    let trimmed = integer.trim_start_matches('0');
    integer = if trimmed.is_empty() { "0".into() } else { trimmed.into() };
    fraction.truncate(fraction.trim_end_matches('0').len());
    let zero = integer == "0" && fraction.is_empty();
    let mut out = String::from(if zero { "" } else { sign });
    out.push_str(&integer);
    if !fraction.is_empty() {
        out.push('.');
        out.push_str(&fraction);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_shift_moves_the_point_and_keeps_every_digit() {
        let cases = [
            ("2.5", 3, "2500"),
            ("2500", -3, "2.5"),
            ("10", -3, "0.01"),
            ("0.01", 3, "10"),
            ("-12.5", -3, "-0.0125"),
            ("1234.5", -3, "1.2345"),
            ("0", 3, "0"),
            ("-0", -3, "0"),
            ("7", 0, "7"),
        ];
        for (digits, places, want) in cases {
            assert_eq!(shift(digits, places), want, "{digits} by {places}");
        }
    }

    #[test]
    fn a_number_prints_in_the_unit_of_its_size() {
        let cases = [
            (Number::with(2500.0, Dimension::Frequency), false, "2.5kHz"),
            (Number::with(999.0, Dimension::Frequency), false, "999Hz"),
            (Number::with(0.01, Dimension::Time), false, "10ms"),
            (Number::with(1.5, Dimension::Time), false, "1.5s"),
            (Number::with(-18.0, Dimension::Gain), true, "-18dB"),
            (Number::with(20.0, Dimension::Percent), true, "+20%"),
            (Number::plain(4.0), false, "4"),
        ];
        for (number, signed, want) in cases {
            let mut out = String::new();
            number.write(&mut out, signed);
            assert_eq!(out, want, "{number:?}");
        }
    }
}
