//! Decibels and linear gain, for each crate of paw.
//!
//! The functions keep the arithmetic and the floor that each caller had, so
//! that the sound bytes and the numbers that a user reads do not change. A
//! caller with a floor of its own gives it.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::float_cmp, reason = "debt: pay down"))]

/// The level that the faders, the sends and the meters of the engine treat
/// as silence.
pub const SILENCE_DB: f64 = -120.0;

/// The floor of [`lin_to_db`]: the decibels of an amplitude of 1e-10, so
/// that silence stays finite in the devices.
pub const DEVICE_FLOOR_DB: f32 = -200.0;

/// Decibels to linear gain. Anything at or below [`SILENCE_DB`] is
/// silence.
#[inline]
pub fn db_to_gain(db: f64) -> f32 {
    if db <= SILENCE_DB {
        0.0
    } else {
        10f64.powf(db / 20.0) as f32
    }
}

/// Linear gain to decibels, with [`SILENCE_DB`] as the floor.
#[inline]
pub fn gain_to_db(gain: f32) -> f64 {
    if gain <= 1e-6 {
        SILENCE_DB
    } else {
        20.0 * f64::from(gain).log10()
    }
}

/// Decibels to linear gain in `f32`, for any finite input (no floor): the
/// form that the devices use at the rate of the sound.
#[inline]
pub fn db_to_lin(db: f32) -> f32 {
    (db * (std::f32::consts::LN_10 / 20.0)).exp()
}

/// Linear gain to decibels in `f32`, with [`DEVICE_FLOOR_DB`] as the floor.
#[inline]
pub fn lin_to_db(x: f32) -> f32 {
    20.0 * x.max(1e-10).log10()
}

/// An amplitude to decibels, with `floor_db` for silence and for any level
/// under it.
#[inline]
pub fn amplitude_to_db(amplitude: f64, floor_db: f64) -> f64 {
    if amplitude > 0.0 {
        (20.0 * amplitude.log10()).max(floor_db)
    } else {
        floor_db
    }
}

/// A ratio of powers (or of mean squares) to decibels, `10 log10`, with
/// `floor_db` for silence and for any level under it.
#[inline]
pub fn power_to_db(power: f64, floor_db: f64) -> f64 {
    if power > 0.0 {
        (10.0 * power.log10()).max(floor_db)
    } else {
        floor_db
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn silence_has_a_floor_in_each_form() {
        assert_eq!(db_to_gain(SILENCE_DB), 0.0);
        assert_eq!(gain_to_db(0.0), SILENCE_DB);
        assert_eq!(lin_to_db(0.0), DEVICE_FLOOR_DB);
        assert_eq!(amplitude_to_db(0.0, -200.0), -200.0);
        assert_eq!(power_to_db(0.0, -150.0), -150.0);
    }

    #[test]
    fn six_decibels_is_about_twice_the_amplitude() {
        assert!((db_to_gain(6.0206) - 2.0).abs() < 1e-4);
        assert!((gain_to_db(0.5) + 6.0206).abs() < 1e-4);
        assert!((db_to_lin(-6.0206) - 0.5).abs() < 1e-4);
        assert!((amplitude_to_db(2.0, -200.0) - 6.0206).abs() < 1e-4);
        assert!((power_to_db(4.0, -150.0) - 6.0206).abs() < 1e-4);
    }
}
