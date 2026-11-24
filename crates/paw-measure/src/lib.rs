//! The measurements of a sound, in one place for each program that measures:
//! the kernel (`paw.api.measure`, which `:mix` uses) and `paw-mcp` (the
//! `render` and `analyze_audio` tools). One analyzer gives one set of
//! numbers, so a file that both measure reads the same in both.
//!
//! - [`Analyzer`] measures a stereo programme in one pass: loudness, true
//!   peak, clipping, DC offset, stereo, a spectrum in octave bands.
//! - [`Levels`] gives the plain levels of a run of samples: sample peak,
//!   RMS, DC offset and full-scale samples.

mod analysis;
pub mod bs1770;
mod levels;
#[cfg(test)]
mod tests;

pub use analysis::{Analysis, Analyzer, Band, FLOOR_DB, Run, Series, analyze};
pub use levels::{FULL_SCALE, Levels};
