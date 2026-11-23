//! The settings of the property tests of the crate (`*/props.rs`).
//!
//! A property test makes its cases from a seed. The normal run uses a fixed
//! seed, so that each run tries the same cases and a result does not change
//! from run to run. The nightly tier gives a new seed and more cases:
//!
//! ```text
//! PROPTEST_CASES=10000 PROPTEST_RNG_SEED=<n> cargo nextest run -p paw-core -E 'test(/::props::/)'
//! ```
//!
//! A case that fails is shrunk to a small one and written to
//! `proptest-regressions/<module path>.txt` beside `src/`. Commit that file:
//! each run tries its cases first.

use proptest::test_runner::{Config, RngSeed};

/// The seed of the normal run: the bytes of "paw_prop".
const SEED: u64 = 0x7061_775f_7072_6f70;

/// The default settings (256 cases, or `PROPTEST_CASES`), with the fixed
/// seed unless `PROPTEST_RNG_SEED` gives one.
pub(crate) fn config() -> Config {
    let mut config = Config::default();
    if config.rng_seed == RngSeed::Random {
        config.rng_seed = RngSeed::Fixed(SEED);
    }
    config
}
