//! The parts of ITU-R BS.1770-4 that the loudness meter device and the
//! analysis share: the K-weighting filter and loudness from a mean square.
//! The meter runs them on the audio thread, so nothing here allocates.
//!
//! The true peak is not here. The meter and the limiter oversample with the
//! engine's upsampler, which does not allocate, and the analysis with its
//! own filter of the same design. Two tests in paw-engine keep them in
//! agreement: `the_meter_and_the_analysis_of_a_file_agree`, and the limiter
//! test that reads its output with `analyze`.

/// A biquad in direct form I, in f64.
#[derive(Clone, Copy, Default)]
pub struct Biquad {
    /// The feed-forward coefficients.
    pub b: [f64; 3],
    /// The feedback coefficients, without the leading 1.
    pub a: [f64; 2],
    x: [f64; 2],
    y: [f64; 2],
}

impl Biquad {
    /// Filter one sample. It does not allocate: the audio thread runs it.
    #[inline]
    pub fn run(&mut self, x: f64) -> f64 {
        let y = self.b[0] * x + self.b[1] * self.x[0] + self.b[2] * self.x[1]
            - self.a[0] * self.y[0]
            - self.a[1] * self.y[1];
        self.x = [x, self.x[0]];
        self.y = [y, self.y[0]];
        y
    }

    /// Set each value of the state that is under 1e-30 to 0, so that a
    /// filter that decays into silence does not run on denormal numbers.
    pub fn flush_denormals(&mut self) {
        for z in self.x.iter_mut().chain(self.y.iter_mut()) {
            if z.abs() < 1e-30 {
                *z = 0.0;
            }
        }
    }
}

/// The two stages of BS.1770's K-weighting at any sample rate, from the
/// analogue prototypes behind the standard's 48 kHz coefficients (the same
/// derivation as libebur128's). At 48 kHz they reproduce the table in
/// BS.1770-4 to the printed precision.
pub fn k_weighting(rate: f64) -> [Biquad; 2] {
    use std::f64::consts::PI;
    // Stage 1: a high shelf of about +4 dB above 1.5 kHz, for the head.
    let (f0, gain, q) = (1681.974450955533, 3.999843853973347, 0.7071752369554196);
    let k = (PI * f0 / rate).tan();
    let vh = 10f64.powf(gain / 20.0);
    let vb = vh.powf(0.4996667741545416);
    let a0 = 1.0 + k / q + k * k;
    let shelf = Biquad {
        b: [
            (vh + vb * k / q + k * k) / a0,
            2.0 * (k * k - vh) / a0,
            (vh - vb * k / q + k * k) / a0,
        ],
        a: [2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0],
        ..Default::default()
    };
    // Stage 2: the RLB high pass at about 38 Hz.
    let (f0, q) = (38.13547087602444, 0.5003270373238773);
    let k = (PI * f0 / rate).tan();
    let a0 = 1.0 + k / q + k * k;
    let high_pass = Biquad {
        b: [1.0, -2.0, 1.0],
        a: [2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0],
        ..Default::default()
    };
    [shelf, high_pass]
}

/// Loudness in LUFS of a mean square summed over the channels (channel
/// weights 1). Silence is minus infinity: a caller with a floor applies it.
#[inline]
pub fn lufs(power: f64) -> f64 {
    -0.691 + 10.0 * power.log10()
}
