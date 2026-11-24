//! The names of pitches: `C4` is MIDI pitch 60, middle C.

/// The names of the twelve pitch classes from C, with sharps.
pub const NAMES: [&str; 12] = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
];

/// The name of a MIDI pitch with its octave: 60 is `C4`, 0 is `C-1`. A
/// pitch out of 0 to 127 has a name too (the tuner can hear one).
pub fn name(pitch: i32) -> String {
    format!(
        "{}{}",
        NAMES[pitch.rem_euclid(12) as usize],
        pitch.div_euclid(12) - 1
    )
}

/// The MIDI pitch of a name with its octave: a letter (either case), then
/// `#` or `b` or nothing, then the octave. `C4` is 60, `Bb2` is 46. The
/// pitch can be out of 0 to 127: the caller checks the range.
pub fn parse(text: &str) -> Option<i64> {
    let mut chars = text.chars();
    let class = match chars.next()?.to_ascii_uppercase() {
        'C' => 0,
        'D' => 2,
        'E' => 4,
        'F' => 5,
        'G' => 7,
        'A' => 9,
        'B' => 11,
        _ => return None,
    };
    let rest = chars.as_str();
    let (shift, octave) = if let Some(octave) = rest.strip_prefix('#') {
        (1, octave)
    } else if let Some(octave) = rest.strip_prefix('b') {
        (-1, octave)
    } else {
        (0, rest)
    };
    let octave: i64 = octave.parse().ok()?;
    octave
        .checked_add(1)?
        .checked_mul(12)?
        .checked_add(class + shift)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pitch_has_its_name_and_octave() {
        assert_eq!(name(60), "C4");
        assert_eq!(name(0), "C-1");
        assert_eq!(name(127), "G9");
        assert_eq!(
            name(-1),
            "B-2",
            "under the MIDI range, as the tuner may hear"
        );
    }

    #[test]
    fn a_name_gives_its_pitch() {
        for (text, pitch) in [
            ("C4", 60),
            ("a4", 69),
            ("F#3", 54),
            ("Bb2", 46),
            ("C-1", 0),
            ("G10", 139),
        ] {
            assert_eq!(parse(text), Some(pitch), "{text}");
        }
        for text in ["", "H2", "C", "C#x", "C922337203685477580"] {
            assert_eq!(parse(text), None, "{text}");
        }
    }
}
