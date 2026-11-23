//! Property tests of the tempo map: beats to seconds and back.
//!
//! The settings are those of the property tests of `paw-core`
//! (`crates/paw-core/src/props.rs`): a fixed seed in the normal run, and
//! `PROPTEST_RNG_SEED` and `PROPTEST_CASES` from the nightly tier.

use proptest::collection::vec;
use proptest::prelude::*;
use proptest::test_runner::{Config, RngSeed};

use super::{MAX_BPM, MIN_BPM, TempoMap, TempoPoint};

/// The default settings, with the seed of the normal run (the bytes of
/// "paw_prop") unless `PROPTEST_RNG_SEED` gives one.
fn config() -> Config {
    let mut config = Config::default();
    if config.rng_seed == RngSeed::Random {
        config.rng_seed = RngSeed::Fixed(0x7061_775f_7072_6f70);
    }
    config
}

/// How far a beat may come back from where it was: a millionth of a beat,
/// far under a tick of a clip file (1/61440 of a beat). The rounding of
/// `f64` over a song of hours at 1 BPM is about 1e-9 of a beat.
const LIMIT: f64 = 1e-6;

/// Tempo points anywhere in the first 4096 beats, at any tempo the map
/// keeps, held or ramped to the next.
fn points() -> impl Strategy<Value = Vec<TempoPoint>> {
    vec((0.0..4096.0f64, MIN_BPM..=MAX_BPM, any::<bool>()), 0..8)
        .prop_map(|points| points.into_iter().map(|(beat, bpm, ramp)| TempoPoint { beat, bpm, ramp }).collect())
}

proptest! {
    #![proptest_config(config())]

    /// A beat made seconds and made a beat again is the same beat, before,
    /// in and after the ramps.
    #[test]
    fn a_beat_to_seconds_and_back_is_the_same_beat(points in points(), beat in 0.0..8192.0f64) {
        let map = TempoMap::new(&points, &[]);

        let back = map.beat(map.seconds(beat));

        prop_assert!((back - beat).abs() <= LIMIT, "beat {} comes back as {}", beat, back);
    }
}
