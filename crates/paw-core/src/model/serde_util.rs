//! What the saved types share for serde: the test that leaves a field out
//! of a file when it has its default value, and the newtypes whose
//! `Default` is not the default of the number in them.
//!
//! A field that is left out when it is default reads back as its default:
//! the field has `#[serde(default, skip_serializing_if = "is_default")]`.

use serde::{Deserialize, Serialize};

/// Whether `value` is the default of its type: the files leave it out.
pub(crate) fn is_default<T: Default + PartialEq>(value: &T) -> bool {
    *value == T::default()
}

/// A factor that is 1 by default: the stretch of a clip, the mix of a
/// split. The files write it as a plain number.
#[derive(Clone, Copy, Debug, PartialEq, PartialOrd, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Factor(pub f64);

impl Default for Factor {
    fn default() -> Self {
        Factor(1.0)
    }
}

/// The velocity of a note, 1 to 127, and 100 by default. The files write
/// it as a plain number. The check of a project (`check_notes`) refuses a
/// velocity above 127.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Velocity(pub u8);

impl Default for Velocity {
    fn default() -> Self {
        Velocity(100)
    }
}

impl Velocity {
    /// The velocity on the scale 0 to 1 that the engine plays.
    pub fn unit(self) -> f32 {
        f32::from(self.0) / 127.0
    }

    /// The velocity of `unit` on the scale 0 to 1: rounded, and in 1 to 127
    /// so that a note that was played is never silent. NaN is the default
    /// velocity.
    pub fn from_unit(unit: f32) -> Velocity {
        if unit.is_nan() {
            return Velocity::default();
        }
        // The clamp keeps the value in the range of u8 before the cast.
        Velocity((unit * 127.0).round().clamp(1.0, 127.0) as u8)
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use crate::model::{Clip, Note};

    #[test]
    fn a_value_that_a_file_leaves_out_reads_as_its_default_and_saves_the_same() {
        let note: Note = serde_json::from_value(json!({ "start": 0.0, "length": 1.0, "pitch": 60 })).unwrap();
        assert_eq!(note.velocity.0, 100);
        assert_eq!(serde_json::to_value(&note).unwrap()["velocity"], 100, "a note writes its velocity");
        let clip = json!({ "id": 2, "name": "a", "start": 0.0, "length": 4.0, "muted": false, "meta": {},
            "content": { "kind": "midi", "notes": [] } });
        let read: Clip = serde_json::from_value(clip.clone()).unwrap();
        assert_eq!(read.stretch.0, 1.0);
        assert_eq!(serde_json::to_value(&read).unwrap(), clip, "a stretch of 1 is left out");
    }

    #[test]
    fn a_velocity_from_the_unit_scale_is_rounded_and_never_silent() {
        assert_eq!(super::Velocity::from_unit(0.0).0, 1);
        assert_eq!(super::Velocity::from_unit(0.5).0, 64);
        assert_eq!(super::Velocity::from_unit(2.0).0, 127);
        assert_eq!(super::Velocity::from_unit(f32::NAN), super::Velocity::default());
        assert_eq!(super::Velocity(127).unit(), 1.0);
    }
}
