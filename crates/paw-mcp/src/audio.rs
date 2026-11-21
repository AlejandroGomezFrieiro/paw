//! What a model can learn from a render without ears: levels per channel,
//! level over time, and where the energy sits in the spectrum.
//!
//! These are plain signal measurements (sample peak, RMS in dBFS, an averaged
//! FFT in octave bands), not perceptual loudness: RMS is not LUFS.

use std::fmt::Write as _;
use std::path::Path;

use anyhow::{Context, Result, bail};

const FFT_SIZE: usize = 4096;
/// Octave band centres, ISO 266.
const BANDS: [f64; 10] = [
    31.5, 63.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0,
];
/// At or below this a signal counts as silence.
const SILENCE_DB: f64 = -90.0;

pub struct Audio {
    pub sample_rate: u32,
    pub bits: u16,
    /// One vector of samples per channel, in -1..1.
    pub channels: Vec<Vec<f32>>,
}

pub fn read_wav(path: &Path) -> Result<Audio> {
    let mut reader =
        hound::WavReader::open(path).with_context(|| format!("reading {}", path.display()))?;
    let spec = reader.spec();
    let n = spec.channels.max(1) as usize;
    let interleaved: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Float => reader.samples::<f32>().collect::<Result<_, _>>()?,
        hound::SampleFormat::Int => {
            let scale = (1i64 << (spec.bits_per_sample - 1)) as f32;
            reader
                .samples::<i32>()
                .map(|s| s.map(|s| s as f32 / scale))
                .collect::<Result<_, _>>()?
        }
    };
    let mut channels = vec![Vec::with_capacity(interleaved.len() / n); n];
    for frame in interleaved.chunks_exact(n) {
        for (c, sample) in frame.iter().enumerate() {
            channels[c].push(*sample);
        }
    }
    Ok(Audio {
        sample_rate: spec.sample_rate,
        bits: spec.bits_per_sample,
        channels,
    })
}

pub fn db(linear: f64) -> f64 {
    if linear <= 1e-10 {
        -200.0
    } else {
        20.0 * linear.log10()
    }
}

fn fmt_db(value: f64) -> String {
    if value <= -199.0 {
        "-inf".into()
    } else {
        format!("{value:.1}")
    }
}

/// How the stretch of time is split for the level-over-time summary.
pub enum Segments {
    /// Equal pieces of about this many seconds.
    Seconds(f64),
    /// Musical bars: the render's start beat, tempo and bar length in beats,
    /// so that each piece is a bar (or several, for a long render).
    Bars {
        start_beat: f64,
        tempo: f64,
        bar_beats: f64,
        /// Beat where the music ends and the tail begins.
        end_beat: f64,
    },
}

/// One line of levels for a stem: `peak -3.1 dBFS, RMS -17.2 dBFS`, or
/// `silent`.
pub fn level_line(audio: &Audio) -> String {
    let (mut peak, mut sum, mut count) = (0f32, 0f64, 0usize);
    for ch in &audio.channels {
        for s in ch {
            peak = peak.max(s.abs());
            sum += (*s as f64).powi(2);
        }
        count += ch.len();
    }
    if db(peak as f64) <= SILENCE_DB {
        return "silent".into();
    }
    let rms = (sum / count.max(1) as f64).sqrt();
    format!(
        "peak {} dBFS, RMS {} dBFS",
        fmt_db(db(peak as f64)),
        fmt_db(db(rms))
    )
}

/// The summary, as compact text.
pub fn analyze(audio: &Audio, segments: Segments, max_segments: usize) -> Result<String> {
    let frames = audio.channels.first().map_or(0, Vec::len);
    if frames == 0 {
        bail!("the file holds no audio");
    }
    let rate = audio.sample_rate as f64;
    let mut out = String::new();
    let names = channel_names(audio.channels.len());
    writeln!(
        out,
        "{:.2} s, {} Hz, {} channel{}, {} bit",
        frames as f64 / rate,
        audio.sample_rate,
        audio.channels.len(),
        if audio.channels.len() == 1 { "" } else { "s" },
        audio.bits
    )?;

    let mut overall_peak = 0f64;
    for (name, ch) in names.iter().zip(&audio.channels) {
        let peak = ch.iter().fold(0f32, |m, s| m.max(s.abs())) as f64;
        let rms = (ch.iter().map(|s| (*s as f64).powi(2)).sum::<f64>() / ch.len() as f64).sqrt();
        let clipped = ch.iter().filter(|s| s.abs() >= 0.999).count();
        let dc = ch.iter().map(|s| *s as f64).sum::<f64>() / ch.len() as f64;
        overall_peak = overall_peak.max(peak);
        write!(
            out,
            "{name}: peak {} dBFS, RMS {} dBFS, crest {:.1} dB",
            fmt_db(db(peak)),
            fmt_db(db(rms)),
            if rms > 0.0 { db(peak) - db(rms) } else { 0.0 }
        )?;
        if clipped > 0 {
            write!(out, ", {clipped} samples at full scale (clipping)")?;
        }
        if dc.abs() > 0.01 {
            write!(out, ", DC offset {dc:.3}")?;
        }
        out.push('\n');
    }
    if db(overall_peak) <= SILENCE_DB {
        out.push_str("SILENT: nothing above -90 dBFS.\n");
        return Ok(out);
    }
    if audio.channels.len() == 2 {
        let (l, r) = (&audio.channels[0], &audio.channels[1]);
        let (mut lr, mut ll, mut rr, mut mid, mut side) = (0f64, 0f64, 0f64, 0f64, 0f64);
        for (a, b) in l.iter().zip(r) {
            let (a, b) = (*a as f64, *b as f64);
            lr += a * b;
            ll += a * a;
            rr += b * b;
            mid += ((a + b) / 2.0).powi(2);
            side += ((a - b) / 2.0).powi(2);
        }
        let correlation = if ll > 0.0 && rr > 0.0 {
            lr / (ll * rr).sqrt()
        } else {
            0.0
        };
        let width = if side <= 1e-20 {
            "mono (left = right)".to_string()
        } else {
            format!(
                "side {} dB below mid",
                fmt_db(db(mid.sqrt()) - db(side.sqrt()))
            )
        };
        writeln!(
            out,
            "stereo: correlation {correlation:.2} (1 mono, 0 wide, <0 out of phase), {width}, balance L-R {:+.1} dB",
            db(ll.sqrt()) - db(rr.sqrt())
        )?;
    }

    // Level over time.
    let mono: Vec<f32> = (0..frames)
        .map(|i| audio.channels.iter().map(|c| c[i]).sum::<f32>() / audio.channels.len() as f32)
        .collect();
    let pieces = split(frames, rate, &segments, max_segments);
    let unit = match segments {
        Segments::Bars { .. } => "bars",
        Segments::Seconds(_) => "seconds",
    };
    writeln!(
        out,
        "level over time ({unit}: RMS / peak dBFS, all channels):"
    )?;
    let mut line = String::new();
    for (label, from, to) in &pieces {
        let mut sum = 0f64;
        let mut peak = 0f32;
        for ch in &audio.channels {
            for s in &ch[*from..*to] {
                sum += (*s as f64).powi(2);
                peak = peak.max(s.abs());
            }
        }
        let n = ((to - from) * audio.channels.len()).max(1);
        let entry = format!(
            "{label} {}/{}",
            fmt_db(db((sum / n as f64).sqrt())),
            fmt_db(db(peak as f64))
        );
        if line.len() + entry.len() > 100 {
            writeln!(out, " {}", line.trim_end().trim_end_matches('·').trim_end())?;
            line.clear();
        }
        line.push_str(&entry);
        line.push_str(" · ");
    }
    if !line.is_empty() {
        writeln!(out, " {}", line.trim_end().trim_end_matches('·').trim_end())?;
    }

    let (bands, centroid) = spectrum(&mono, rate);
    let loudest = bands.iter().cloned().fold(f64::MIN, f64::max);
    write!(
        out,
        "spectrum (octave bands, dB relative to the loudest band):"
    )?;
    for (centre, level) in BANDS.iter().zip(&bands) {
        if *centre >= rate / 2.0 {
            break;
        }
        let label = if *centre >= 1000.0 {
            format!("{}k", super::music::num(centre / 1000.0))
        } else {
            super::music::num(*centre)
        };
        write!(out, " {label} {}", fmt_db(level - loudest))?;
    }
    writeln!(
        out,
        "\nspectral centroid {centroid:.0} Hz ({})",
        brightness(centroid)
    )?;
    Ok(out)
}

fn channel_names(n: usize) -> Vec<String> {
    match n {
        1 => vec!["mono".into()],
        2 => vec!["left".into(), "right".into()],
        _ => (1..=n).map(|i| format!("ch{i}")).collect(),
    }
}

fn brightness(centroid: f64) -> &'static str {
    match centroid {
        c if c < 500.0 => "dark, bass heavy",
        c if c < 1500.0 => "warm",
        c if c < 3500.0 => "balanced",
        c if c < 6000.0 => "bright",
        _ => "very bright, hissy",
    }
}

/// (label, first frame, end frame) for each piece of the summary.
fn split(frames: usize, rate: f64, segments: &Segments, max: usize) -> Vec<(String, usize, usize)> {
    let max = max.max(1);
    let mut out = Vec::new();
    match *segments {
        Segments::Seconds(seconds) => {
            let total = frames as f64 / rate;
            let count = ((total / seconds.max(0.01)).ceil() as usize).clamp(1, max);
            let size = frames.div_ceil(count);
            for i in 0..count {
                let (from, to) = (i * size, ((i + 1) * size).min(frames));
                if from < to {
                    out.push((format!("{:.1}s", from as f64 / rate), from, to));
                }
            }
        }
        Segments::Bars {
            start_beat,
            tempo,
            bar_beats,
            end_beat,
        } => {
            let frame_of =
                |beat: f64| (((beat - start_beat) * 60.0 / tempo) * rate).round() as usize;
            let first_bar = (start_beat / bar_beats + 1e-9).floor() as i64;
            let last_bar = ((end_beat / bar_beats) - 1e-9).ceil() as i64;
            let bars = (last_bar - first_bar).max(1) as usize;
            let per = bars.div_ceil(max);
            let mut bar = first_bar;
            while bar < last_bar {
                let next = (bar + per as i64).min(last_bar);
                let from = frame_of((bar as f64 * bar_beats).max(start_beat)).min(frames);
                let to = frame_of((next as f64 * bar_beats).min(end_beat)).min(frames);
                if from < to {
                    let label = if per == 1 {
                        format!("{}", bar + 1)
                    } else {
                        format!("{}-{}", bar + 1, next)
                    };
                    out.push((label, from, to));
                }
                bar = next;
            }
            let tail_from = frame_of(end_beat).min(frames);
            if tail_from + (rate as usize / 20) < frames {
                out.push(("tail".into(), tail_from, frames));
            }
        }
    }
    out
}

/// Mean power per octave band in dB, and the spectral centroid in Hz.
fn spectrum(mono: &[f32], rate: f64) -> (Vec<f64>, f64) {
    let window: Vec<f64> = (0..FFT_SIZE)
        .map(|i| 0.5 - 0.5 * (2.0 * std::f64::consts::PI * i as f64 / FFT_SIZE as f64).cos())
        .collect();
    let mut power = vec![0f64; FFT_SIZE / 2];
    let mut frames = 0;
    let plan = realfft::RealFftPlanner::<f64>::new().plan_fft_forward(FFT_SIZE);
    let mut frame = plan.make_input_vec();
    let mut bins = plan.make_output_vec();
    // Hop by a whole frame; with at most 2000 frames spread over the file.
    let total = mono.len().saturating_sub(FFT_SIZE) / FFT_SIZE + 1;
    let step = total.div_ceil(2000).max(1);
    let mut start = 0;
    while start < mono.len() {
        for i in 0..FFT_SIZE {
            frame[i] = mono.get(start + i).copied().unwrap_or(0.0) as f64 * window[i];
        }
        plan.process(&mut frame, &mut bins).expect("lengths match the plan");
        for (p, bin) in power.iter_mut().zip(&bins) {
            *p += bin.norm_sqr();
        }
        frames += 1;
        start += FFT_SIZE * step;
    }
    let bin_hz = rate / FFT_SIZE as f64;
    let mut bands = vec![0f64; BANDS.len()];
    let (mut weighted, mut total_power) = (0f64, 0f64);
    for (k, p) in power.iter().enumerate().skip(1) {
        let f = k as f64 * bin_hz;
        let p = p / frames.max(1) as f64;
        weighted += f * p;
        total_power += p;
        if let Some(b) = BANDS
            .iter()
            .position(|c| f >= c / std::f64::consts::SQRT_2 && f < c * std::f64::consts::SQRT_2)
        {
            bands[b] += p;
        }
    }
    let bands = bands
        .into_iter()
        .map(|p| if p > 0.0 { 10.0 * p.log10() } else { -200.0 })
        .collect();
    let centroid = if total_power > 0.0 {
        weighted / total_power
    } else {
        0.0
    };
    (bands, centroid)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sine(freq: f64, seconds: f64, amp: f32) -> Vec<f32> {
        let rate = 48000.0;
        (0..(seconds * rate) as usize)
            .map(|i| amp * (2.0 * std::f64::consts::PI * freq * i as f64 / rate).sin() as f32)
            .collect()
    }

    #[test]
    fn a_sine_lands_in_its_band() {
        let tone = sine(1000.0, 2.0, 0.5);
        let audio = Audio {
            sample_rate: 48000,
            bits: 32,
            channels: vec![tone.clone(), tone],
        };
        let text = analyze(&audio, Segments::Seconds(0.5), 8).unwrap();
        assert!(
            text.contains("left: peak -6.0 dBFS, RMS -9.0 dBFS"),
            "{text}"
        );
        assert!(text.contains("correlation 1.00"), "{text}");
        assert!(text.contains(" 1k 0.0"), "{text}");
        let (bands, centroid) = spectrum(&sine(1000.0, 1.0, 0.5), 48000.0);
        assert!((centroid - 1000.0).abs() < 50.0, "{centroid}");
        assert!(bands[5] > bands[3] + 30.0);
    }

    #[test]
    fn silence_is_called_silence() {
        let audio = Audio {
            sample_rate: 48000,
            bits: 16,
            channels: vec![vec![0.0; 48000]; 2],
        };
        assert!(
            analyze(&audio, Segments::Seconds(1.0), 8)
                .unwrap()
                .contains("SILENT")
        );
    }

    #[test]
    fn bars_split_with_a_tail() {
        let s = Segments::Bars {
            start_beat: 0.0,
            tempo: 120.0,
            bar_beats: 4.0,
            end_beat: 8.0,
        };
        // Two bars at 120 BPM are 4 s; one second of tail.
        let pieces = split(48000 * 5, 48000.0, &s, 32);
        let labels: Vec<&str> = pieces.iter().map(|p| p.0.as_str()).collect();
        assert_eq!(labels, ["1", "2", "tail"]);
        assert_eq!(pieces[1].1, 96000);
    }
}
