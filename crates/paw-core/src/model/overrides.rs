//! The overrides of a MIDI clip: a transpose and a velocity change that
//! apply when the clip plays, and not to its notes. With them, each clip of
//! a link (`model/links.rs`) plays the shared notes in its own way. The
//! notes stay as they are: the sync applies the overrides when it compiles
//! the clip's events (`sync/clips.rs`), and the export of a MIDI file
//! applies them as it writes each note.

use serde::{Deserialize, Serialize};

use super::{Control, Note};

/// What a MIDI clip changes in its notes as it plays them. The default
/// changes nothing.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Overrides {
    /// Semitones that the notes play higher (lower below 0). A note that
    /// this puts outside 0 to 127 does not play.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub transpose: i8,
    /// What is added to the velocity of each note, which then stays in 1
    /// to 127.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub velocity: i8,
}

fn is_zero(value: &i8) -> bool {
    *value == 0
}

impl Overrides {
    /// True when the overrides change nothing.
    pub fn is_none(&self) -> bool {
        *self == Self::default()
    }

    /// The pitch that a note of `pitch` plays at, or `None` when the
    /// transpose puts it outside 0 to 127.
    pub fn pitch(&self, pitch: u8) -> Option<u8> {
        u8::try_from(i16::from(pitch) + i16::from(self.transpose))
            .ok()
            .filter(|p| *p <= 127)
    }

    /// The velocity that a note of `velocity` plays at: 1 to 127.
    pub fn velocity(&self, velocity: u8) -> u8 {
        (i16::from(velocity) + i16::from(self.velocity)).clamp(1, 127) as u8
    }

    /// The pitch and the velocity that `note` plays at, or `None` when it
    /// does not play.
    pub fn note(&self, note: &Note) -> Option<(u8, u8)> {
        Some((self.pitch(note.pitch)?, self.velocity(note.velocity)))
    }

    /// A controller move as it plays: a move of one key (a note's own bend
    /// or pressure) follows its note to the transposed key, and does not
    /// play when its note does not. The other moves play as they are.
    pub fn control(&self, control: &Control) -> Option<Control> {
        match control.key {
            Some(key) => Some(Control { key: Some(self.pitch(key)?), ..control.clone() }),
            None => Some(control.clone()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The transpose drops a note it takes outside the MIDI range, and the
    /// velocity change stays in 1 to 127.
    #[test]
    fn overrides_keep_notes_in_the_midi_range() {
        let up = Overrides { transpose: 3, velocity: -10 };
        assert_eq!(up.pitch(60), Some(63));
        assert_eq!(up.pitch(125), None);
        assert_eq!(Overrides { transpose: -5, velocity: 0 }.pitch(4), None);
        assert_eq!(up.velocity(5), 1);
        assert_eq!(Overrides { transpose: 0, velocity: 100 }.velocity(100), 127);
        assert!(Overrides::default().is_none() && !up.is_none());
    }
}
