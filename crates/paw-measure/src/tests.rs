//! The measurements against signals whose readings are known: the EBU Tech
//! 3341 and 3342 test cases that are made of sine tones (generated here, not
//! downloaded), and true-peak cases whose answer follows from the signal.

use crate::analysis::{Analysis, analyze};

const PI2: f64 = 2.0 * std::f64::consts::PI;

/// A stereo signal built from pieces.
struct Signal {
    rate: f64,
    left: Vec<f32>,
    right: Vec<f32>,
}

impl Signal {
    fn new(rate: f64) -> Self {
        Self {
            rate,
            left: Vec::new(),
            right: Vec::new(),
        }
    }

    /// A sine of `freq` Hz at a peak level of `dbfs`, the same in both channels,
    /// continuing the phase of what came before.
    fn sine(mut self, freq: f64, dbfs: f64, seconds: f64) -> Self {
        let amp = 10f64.powf(dbfs / 20.0);
        let start = self.left.len();
        for i in 0..(seconds * self.rate).round() as usize {
            let x = (amp * (PI2 * freq * (start + i) as f64 / self.rate).sin()) as f32;
            self.left.push(x);
            self.right.push(x);
        }
        self
    }

    fn silence(mut self, seconds: f64) -> Self {
        let n = (seconds * self.rate).round() as usize;
        self.left.extend(std::iter::repeat_n(0.0, n));
        self.right.extend(std::iter::repeat_n(0.0, n));
        self
    }

    fn map(mut self, f: impl Fn(f32, f32) -> (f32, f32)) -> Self {
        for (l, r) in self.left.iter_mut().zip(self.right.iter_mut()) {
            (*l, *r) = f(*l, *r);
        }
        self
    }

    fn run(&self) -> Analysis {
        analyze(self.rate, &self.left, &self.right)
    }
}

fn noise(seed: u64) -> impl FnMut() -> f32 {
    let mut state = seed;
    move || {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        ((state >> 11) as f64 / (1u64 << 53) as f64 * 2.0 - 1.0) as f32
    }
}

#[track_caller]
fn near(got: f64, want: f64, tolerance: f64, what: &str) {
    assert!(
        (got - want).abs() <= tolerance,
        "{what}: got {got:.3}, want {want} ± {tolerance}"
    );
}

#[test]
fn k_weighting_matches_the_table_in_bs1770_at_48k() {
    let [shelf, high_pass] = crate::analysis::k_weighting(48_000.0);
    let table = [
        (shelf.b[0], 1.53512485958697),
        (shelf.b[1], -2.69169618940638),
        (shelf.b[2], 1.19839281085285),
        (shelf.a[0], -1.69065929318241),
        (shelf.a[1], 0.73248077421585),
        (high_pass.a[0], -1.99004745483398),
        (high_pass.a[1], 0.99007225036621),
    ];
    for (i, (got, want)) in table.iter().enumerate() {
        near(*got, *want, 1e-8, &format!("coefficient {i}"));
    }
    // And at other rates the filter keeps its gain: a 997 Hz stereo sine at
    // X dBFS reads X LUFS.
    for rate in [44_100.0, 48_000.0, 96_000.0] {
        let a = Signal::new(rate).sine(997.0, -20.0, 10.0).run();
        near(
            a.integrated.unwrap(),
            -20.0,
            0.02,
            &format!("997 Hz at {rate}"),
        );
    }
}

#[test]
fn tech_3341_case_1_and_2_steady_sines() {
    // Case 1: 1 kHz stereo sine at -23 dBFS reads -23.0 for M, S and I.
    let a = Signal::new(48_000.0).sine(1000.0, -23.0, 20.0).run();
    near(a.integrated.unwrap(), -23.0, 0.1, "case 1 integrated");
    near(a.momentary_max.unwrap(), -23.0, 0.1, "case 1 momentary max");
    near(
        a.short_term_max.unwrap(),
        -23.0,
        0.1,
        "case 1 short-term max",
    );
    // Case 2: the same at -33 dBFS reads -33.0.
    let a = Signal::new(48_000.0).sine(1000.0, -33.0, 20.0).run();
    near(a.integrated.unwrap(), -33.0, 0.1, "case 2 integrated");
}

#[test]
fn tech_3341_cases_3_to_5_gating() {
    // Case 3: -36, -23, -36 dBFS for 10, 60, 10 s: the quiet parts fall
    // under the relative gate and the programme reads -23.0.
    let a = Signal::new(48_000.0)
        .sine(1000.0, -36.0, 10.0)
        .sine(1000.0, -23.0, 60.0)
        .sine(1000.0, -36.0, 10.0)
        .run();
    near(a.integrated.unwrap(), -23.0, 0.1, "case 3");
    // Case 4: -72, -36, -23, -36, -72 for 10, 10, 60, 10, 10 s: the -72
    // parts fall under the absolute gate as well.
    let a = Signal::new(48_000.0)
        .sine(1000.0, -72.0, 10.0)
        .sine(1000.0, -36.0, 10.0)
        .sine(1000.0, -23.0, 60.0)
        .sine(1000.0, -36.0, 10.0)
        .sine(1000.0, -72.0, 10.0)
        .run();
    near(a.integrated.unwrap(), -23.0, 0.1, "case 4");
    // Case 5: -26, -20, -26 for 20, 20.1, 20 s: nothing is gated and the
    // energy mean is -23.0.
    let a = Signal::new(48_000.0)
        .sine(1000.0, -26.0, 20.0)
        .sine(1000.0, -20.0, 20.1)
        .sine(1000.0, -26.0, 20.0)
        .run();
    near(a.integrated.unwrap(), -23.0, 0.1, "case 5");
}

#[test]
fn the_absolute_gate_ignores_material_under_minus_70() {
    let a = Signal::new(48_000.0).sine(1000.0, -75.0, 10.0).run();
    assert_eq!(a.integrated, None, "nothing passes the gate");
    // Silence around a tone is gated out. The three blocks at each edge that
    // hold 3/4, 1/2 and 1/4 of tone pass the gates, as the standard has it:
    // 97 whole blocks and 6 partial ones average 100/103 of the tone's power.
    let a = Signal::new(48_000.0)
        .silence(5.0)
        .sine(1000.0, -23.0, 10.0)
        .silence(5.0)
        .run();
    let want = -23.0 + 10.0 * (100.0f64 / 103.0).log10();
    near(a.integrated.unwrap(), want, 0.02, "silence is gated out");
}

#[test]
fn tech_3341_case_9_short_term_is_steady() {
    // Case 9: 1.34 s at -20 dBFS and 1.66 s at -30 dBFS, 20 times: every
    // 3 s window holds the same energy and reads -23.0.
    let mut s = Signal::new(48_000.0);
    for _ in 0..20 {
        s = s.sine(1000.0, -20.0, 1.34).sine(1000.0, -30.0, 1.66);
    }
    let a = s.run();
    let steady = &a.series.short_term[29..a.series.short_term.len() - 1];
    for (i, v) in steady.iter().enumerate() {
        near(
            *v,
            -23.0,
            0.1,
            &format!("short-term at {:.1} s", (i + 30) as f64 * 0.1),
        );
    }
}

#[test]
fn tech_3342_loudness_range_cases_1_to_4() {
    let lra = |levels: &[f64]| {
        let mut s = Signal::new(48_000.0);
        for level in levels {
            s = s.sine(1000.0, *level, 20.0);
        }
        s.run().lra.unwrap()
    };
    near(lra(&[-20.0, -30.0]), 10.0, 1.0, "case 1");
    near(lra(&[-20.0, -15.0]), 5.0, 1.0, "case 2");
    near(lra(&[-40.0, -20.0]), 20.0, 1.0, "case 3");
    near(
        lra(&[-50.0, -35.0, -20.0, -35.0, -50.0]),
        15.0,
        1.0,
        "case 4",
    );
    // A short programme has no 3 s window.
    assert_eq!(
        Signal::new(48_000.0).sine(1000.0, -20.0, 2.0).run().lra,
        None
    );
}

/// A sine with a slow fade at each end, so that the edges do not ring above
/// the sine's own peak.
fn faded(rate: f64, freq: f64, amp: f64, phase: f64, seconds: f64) -> Signal {
    let n = (seconds * rate) as usize;
    let fade = (0.05 * rate) as usize;
    let mut s = Signal::new(rate);
    for i in 0..n {
        let env = if i < fade {
            i as f64 / fade as f64
        } else if i >= n - fade {
            (n - i) as f64 / fade as f64
        } else {
            1.0
        };
        let x = (amp * env * (PI2 * freq * i as f64 / rate + phase).sin()) as f32;
        s.left.push(x);
        s.right.push(x);
    }
    s
}

#[test]
fn true_peak_finds_peaks_between_samples() {
    let rate = 48_000.0;
    // fs/4 with 45 degrees of phase: every sample is at 0.7071 of the peak,
    // 3.01 dB under it.
    let a = faded(rate, rate / 4.0, 0.5, std::f64::consts::FRAC_PI_4, 1.0).run();
    near(a.sample_peak, -6.02 - 3.01, 0.01, "fs/4 sample peak");
    near(a.true_peak, -6.02, 0.1, "fs/4 true peak");
    // fs/6 with the samples 30 degrees either side of the crest: 1.25 dB under.
    let a = faded(rate, rate / 6.0, 0.5, 0.0, 1.0).run();
    near(a.sample_peak, -6.02 - 1.25, 0.01, "fs/6 sample peak");
    near(a.true_peak, -6.02, 0.1, "fs/6 true peak");
    // An inter-sample over: no sample reaches full scale, the signal does.
    let a = faded(rate, rate / 4.0, 1.2, std::f64::consts::FRAC_PI_4, 1.0).run();
    assert!(a.sample_peak < 0.0, "samples stay under full scale");
    near(
        a.true_peak,
        20.0 * 1.2f64.log10(),
        0.1,
        "over full scale between the samples",
    );
    // A low tone's samples already hold its peak.
    let a = faded(rate, 997.0, 0.5, 0.3, 1.0).run();
    near(a.true_peak, -6.02, 0.05, "997 Hz");
    // Tech 3341's tolerance for true peak is +0.2 / -0.4 dB; high tones at
    // any phase stay inside it, at 44.1 and 48 kHz.
    for rate in [44_100.0, 48_000.0] {
        for freq in [5_000.0, 10_000.0, 15_000.0, 19_000.0] {
            for phase in [0.1, 0.7, 1.3] {
                let a = faded(rate, freq, 0.5, phase, 0.5).run();
                let got = a.true_peak + 6.02;
                assert!(
                    (-0.4..=0.2).contains(&got),
                    "{freq} Hz at {rate}, phase {phase}: off by {got:.3} dB"
                );
            }
        }
    }
}

#[test]
fn clipped_runs_are_counted_and_placed() {
    let rate = 48_000.0;
    // A 100 Hz sine at twice full scale, cut flat at full scale: every half
    // cycle is a run, 200 in a second, the first starting before 2.5 ms.
    let a = Signal::new(rate)
        .silence(1.0)
        .sine(100.0, 6.02, 1.0)
        .map(|l, r| (l.clamp(-1.0, 1.0), r.clamp(-1.0, 1.0)))
        .run();
    assert_eq!(a.clip_runs, 200, "a run per half cycle");
    near(a.runs[0].at, 1.0, 0.003, "the first run's place");
    assert_eq!(a.over_samples, 0, "flat at full scale, never over it");
    near(a.sample_peak, 0.0, 0.001, "peak at full scale");
    // A single sample over full scale in a float mix will clip when written.
    let mut s = Signal::new(rate).sine(440.0, -6.0, 1.0);
    s.left[24_000] = 1.3;
    let a = s.run();
    assert_eq!(a.clip_runs, 1, "one over");
    near(a.runs[0].at, 0.5, 0.001, "where");
    // A loud sine that never reaches full scale has none.
    assert_eq!(Signal::new(rate).sine(440.0, -0.5, 1.0).run().clip_runs, 0);
}

#[test]
fn dc_offset_crest_and_silence() {
    let rate = 48_000.0;
    let a = Signal::new(rate)
        .silence(2.0)
        .sine(1000.0, -6.02, 5.0)
        .silence(3.0)
        .map(|l, r| (l + 0.01, r))
        .run();
    near(a.dc[0], 0.01, 1e-4, "left offset");
    near(a.dc[1], 0.0, 1e-4, "right offset");
    near(
        a.sound_start.unwrap(),
        0.0,
        1e-3,
        "the offset is sound from the start",
    );
    let a = Signal::new(rate)
        .silence(2.0)
        .sine(1000.0, -6.02, 5.0)
        .silence(3.0)
        .run();
    near(a.sound_start.unwrap(), 2.0, 0.01, "sound starts after 2 s");
    near(a.sound_end.unwrap(), 7.0, 0.01, "and ends at 7 s");
    // A steady sine's crest factor is 3.01 dB.
    let a = Signal::new(rate).sine(1000.0, -6.02, 5.0).run();
    near(a.crest.unwrap(), 3.01, 0.02, "sine crest factor");
}

#[test]
fn stereo_correlation_width_and_mono_loss() {
    let rate = 48_000.0;
    let mono = Signal::new(rate).sine(440.0, -10.0, 5.0).run();
    near(mono.correlation, 1.0, 1e-6, "identical sides");
    near(mono.width, 0.0, 1e-6, "no side");
    near(mono.mono_loss.unwrap(), 0.0, 0.01, "nothing lost in mono");

    let flipped = Signal::new(rate)
        .sine(440.0, -10.0, 5.0)
        .map(|l, r| (l, -r))
        .run();
    near(flipped.correlation, -1.0, 1e-6, "opposite polarity");
    near(flipped.width, 1.0, 1e-6, "all side");
    assert_eq!(flipped.mono_integrated, None, "cancels in mono");
    assert!(
        flipped.series.correlation[20..40]
            .iter()
            .all(|c| *c < -0.99),
        "and over time"
    );

    // Unrelated noise in each side: correlation 0, 3 dB lost in mono.
    let (mut a, mut b) = (noise(1), noise(2));
    let n = (10.0 * rate) as usize;
    let s = Signal {
        rate,
        left: (0..n).map(|_| 0.3 * a()).collect(),
        right: (0..n).map(|_| 0.3 * b()).collect(),
    };
    let wide = s.run();
    near(wide.correlation, 0.0, 0.02, "unrelated sides");
    near(wide.width, 0.5, 0.02, "half side");
    near(wide.mono_loss.unwrap(), 3.01, 0.1, "3 dB lost in mono");
}

#[test]
fn spectrum_puts_a_tone_in_its_octave() {
    let a = Signal::new(48_000.0).sine(1000.0, -10.0, 5.0).run();
    let band = |name: &str| a.bands.iter().find(|b| b.name == name).unwrap().share;
    near(band("1k"), 0.0, 0.1, "all in the 1 kHz octave");
    assert!(band("125") < -60.0, "nothing far below: {}", band("125"));
    assert!(band("8k") < -60.0, "nothing far above: {}", band("8k"));
    near(
        a.centroid,
        1000.0,
        10.0,
        "the centroid of a tone is its frequency",
    );
    // Two tones of equal level split the energy evenly.
    let s = Signal::new(48_000.0).sine(100.0, -10.0, 5.0);
    let t = Signal::new(48_000.0).sine(4000.0, -10.0, 5.0);
    let mixed = Signal {
        rate: 48_000.0,
        left: s.left.iter().zip(&t.left).map(|(a, b)| a + b).collect(),
        right: s.right.iter().zip(&t.right).map(|(a, b)| a + b).collect(),
    }
    .run();
    let band = |name: &str| mixed.bands.iter().find(|b| b.name == name).unwrap().share;
    near(band("125"), -3.01, 0.1, "half in the 125 Hz octave");
    near(band("4k"), -3.01, 0.1, "half in the 4 kHz octave");
    near(
        mixed.centroid,
        2050.0,
        20.0,
        "the centroid is between the two",
    );
    let silence = analyze(48_000.0, &[0.0; 48_000], &[0.0; 48_000]);
    assert_eq!(silence.centroid, 0.0, "silence has no centroid");
}

#[test]
fn series_place_a_loud_passage() {
    let a = Signal::new(48_000.0)
        .sine(1000.0, -30.0, 5.0)
        .sine(1000.0, -10.0, 1.0)
        .sine(1000.0, -30.0, 5.0)
        .run();
    let m = &a.series.momentary;
    let loudest = (0..m.len()).max_by(|i, j| m[*i].total_cmp(&m[*j])).unwrap();
    // Window i ends at (i + 1) * 0.1 s; the loud second is 5 to 6 s.
    let end = (loudest + 1) as f64 * 0.1;
    assert!((5.4..=6.0).contains(&end), "loudest window ends at {end}");
    near(a.momentary_max.unwrap(), -10.0, 0.1, "momentary max");
    let tp = &a.series.true_peak;
    near(tp[55], -10.0, 0.05, "true peak in the loud hop");
    near(tp[20], -30.0, 0.05, "and in a quiet one");
}
