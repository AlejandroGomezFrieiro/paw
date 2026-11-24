//! Where a launch lands: the first boundary of a grid, a beat or a bar at
//! or after a position.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]

use crate::tempo::{EPS, TempoMap};

/// Where launches land.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Quantize {
    /// At once.
    Off,
    /// On a grid of this many beats (quarter notes), counted from the
    /// start of each bar.
    Grid(f64),
    /// On the beats of the signature: an eighth in 6/8.
    Beat,
    /// On the start of every so many bars, counted from the first.
    Bars(u32),
}

impl Quantize {
    /// The first boundary at or after `beat`.
    pub fn next(self, map: &TempoMap, beat: f64) -> f64 {
        let beat = beat.max(0.0);
        match self {
            Quantize::Off => beat,
            Quantize::Bars(every) => {
                let every = every.max(1) as i64;
                let mut bar = map.bar_of(beat);
                if map.bar_start(bar) < beat - EPS {
                    bar += 1;
                }
                map.bar_start((bar + every - 1).div_euclid(every) * every)
            }
            Quantize::Grid(_) | Quantize::Beat => {
                let bar = map.bar_of(beat);
                let start = map.bar_start(bar);
                let unit = match self {
                    Quantize::Grid(unit) => unit.max(1e-3),
                    _ => 4.0 / map.bar_signature(bar).1 as f64,
                };
                let steps = ((beat - start) / unit - EPS).ceil().max(0.0);
                (start + steps * unit).min(map.bar_start(bar + 1))
            }
        }
    }
}
