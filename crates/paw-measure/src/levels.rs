//! Plain signal levels of a run of samples, with no weighting: sample peak,
//! RMS, DC offset and the samples at full scale.

/// A sample at or above this is at digital full scale (it includes a 16-bit
/// file's largest positive value, 32767/32768).
pub const FULL_SCALE: f32 = 0.999_95;

/// Sums over the samples given so far. Give one channel for the levels of
/// that channel, or several for the levels of all of them together.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Levels {
    /// The highest absolute sample, linear.
    peak: f32,
    /// The sum of the squares and the plain sum of the samples, in f64 so
    /// that a long programme loses no precision.
    energy: f64,
    sum: f64,
    samples: usize,
    /// Samples at or over full scale, and samples over it.
    clipped: usize,
    overs: usize,
}

impl Levels {
    /// The levels of `samples`.
    pub fn of(samples: &[f32]) -> Self {
        let mut levels = Self::default();
        levels.push(samples);
        levels
    }

    /// Add the next run of samples.
    pub fn push(&mut self, samples: &[f32]) {
        for x in samples {
            self.add(*x);
        }
    }

    /// Add one sample.
    #[inline]
    pub fn add(&mut self, sample: f32) {
        let x = sample as f64;
        self.energy += x * x;
        self.sum += x;
        self.samples += 1;
        let magnitude = sample.abs();
        self.peak = self.peak.max(magnitude);
        if magnitude >= FULL_SCALE {
            self.clipped += 1;
        }
        if magnitude > 1.0 {
            self.overs += 1;
        }
    }

    /// The levels of the samples of `self` and of `other` together.
    #[must_use]
    pub fn merged(&self, other: &Self) -> Self {
        Self {
            peak: self.peak.max(other.peak),
            energy: self.energy + other.energy,
            sum: self.sum + other.sum,
            samples: self.samples + other.samples,
            clipped: self.clipped + other.clipped,
            overs: self.overs + other.overs,
        }
    }

    /// The highest absolute sample, linear (1 = full scale).
    pub fn peak(&self) -> f32 {
        self.peak
    }

    /// The root mean square, linear; 0 when there are no samples.
    pub fn rms(&self) -> f64 {
        if self.samples == 0 {
            0.0
        } else {
            (self.energy / self.samples as f64).sqrt()
        }
    }

    /// The sum of the squares of the samples.
    pub fn energy(&self) -> f64 {
        self.energy
    }

    /// The mean of the samples, the DC offset, linear; 0 when there are no
    /// samples.
    pub fn dc(&self) -> f64 {
        if self.samples == 0 {
            0.0
        } else {
            self.sum / self.samples as f64
        }
    }

    /// Samples at or over [`FULL_SCALE`].
    pub fn clipped(&self) -> usize {
        self.clipped
    }

    /// Samples over full scale (only a float signal has them).
    pub fn overs(&self) -> usize {
        self.overs
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn full_scale_and_overs_are_counted() {
        let levels = Levels::of(&[1.0, -1.0, 1.5, 0.9]);
        assert_eq!((levels.clipped(), levels.overs()), (3, 1));
    }

    #[test]
    fn no_samples_read_zero() {
        let levels = Levels::default();
        assert_eq!((levels.peak(), levels.rms(), levels.dc()), (0.0, 0.0, 0.0));
    }

    #[test]
    fn merged_levels_are_the_levels_of_both_runs() {
        let (a, b) = ([0.25f32, 0.25], [1.0f32, -1.0, 1.0, -1.0]);
        let both: Vec<f32> = a.iter().chain(&b).copied().collect();
        assert_eq!(Levels::of(&a).merged(&Levels::of(&b)), Levels::of(&both));
    }
}
