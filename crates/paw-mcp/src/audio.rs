//! What a model can learn from a render without ears: levels per channel,
//! level over time, and where the energy sits in the spectrum.
//!
//! These are plain signal measurements (sample peak, RMS in dBFS, octave
//! bands), not perceptual loudness: RMS is not LUFS. The numbers come from
//! `paw-measure`, the analyzer that the kernel's `paw.api.measure` (and so
//! `:mix`) uses too; this module only reads the file and writes the text.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_possible_wrap, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::float_cmp, reason = "debt: pay down"))]

use std::fmt::Write as _;
use std::path::Path;

use anyhow::{Context, Result, bail};
use paw_measure::{Analysis, Analyzer, FLOOR_DB, Levels};
use paw_types::gain::amplitude_to_db;

/// The bands of [`Analysis::bands`] below and above the octave bands, which
/// the summary leaves out.
const OUTSIDE_THE_OCTAVES: [&str; 2] = ["sub", "air"];
/// At or below this a signal counts as silence.
const SILENCE_DB: f64 = -90.0;

pub(crate) struct Audio {
    pub sample_rate: u32,
    pub bits: u16,
    /// One vector of samples per channel, in -1..1.
    pub channels: Vec<Vec<f32>>,
}

impl Audio {
    /// The length in frames: samples per channel.
    pub(crate) fn frames(&self) -> usize {
        self.channels.first().map_or(0, Vec::len)
    }
}

pub(crate) fn read_wav(path: &Path) -> Result<Audio> {
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

/// The level that the tools print as `-inf`, and the floor of each level.
const LEVEL_FLOOR_DB: f64 = -200.0;

/// An amplitude in decibels, as the tools print it.
pub(crate) fn db(linear: f64) -> f64 {
    amplitude_to_db(linear, LEVEL_FLOOR_DB)
}

fn fmt_db(value: f64) -> String {
    if value <= -199.0 {
        "-inf".into()
    } else {
        format!("{value:.1}")
    }
}

/// How the stretch of time is split for the level-over-time summary.
pub(crate) enum Segments {
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
pub(crate) fn level_line(audio: &Audio) -> String {
    let levels = all_channels(audio, 0, audio.frames());
    let peak = levels.peak();
    if db(peak as f64) <= SILENCE_DB {
        return "silent".into();
    }
    let rms = levels.rms();
    format!(
        "peak {} dBFS, RMS {} dBFS",
        fmt_db(db(peak as f64)),
        fmt_db(db(rms))
    )
}

/// The summary, as compact text.
#[expect(
    clippy::too_many_lines,
    reason = "a sequence of steps in one place; the split into named steps is open work"
)]
pub(crate) fn analyze(audio: &Audio, segments: Segments, max_segments: usize) -> Result<String> {
    let frames = audio.frames();
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

    let channels: Vec<Levels> = audio.channels.iter().map(|ch| Levels::of(ch)).collect();
    let mut overall_peak = 0f64;
    for (name, levels) in names.iter().zip(&channels) {
        let (peak, rms) = (levels.peak() as f64, levels.rms());
        let (clipped, dc) = (levels.clipped(), levels.dc());
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
    let analysis = programme(audio);
    if let [left, right] = channels.as_slice() {
        // `side` is the side level relative to mid; with no side at all it
        // reads the floor.
        let width = if analysis.side <= FLOOR_DB {
            "mono (left = right)".to_string()
        } else {
            format!("side {} dB below mid", fmt_db(-analysis.side))
        };
        writeln!(
            out,
            "stereo: correlation {:.2} (1 mono, 0 wide, <0 out of phase), {width}, balance L-R {:+.1} dB",
            analysis.correlation,
            db(left.rms()) - db(right.rms())
        )?;
    }

    // Level over time.
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
        let levels = all_channels(audio, *from, *to);
        let entry = format!(
            "{label} {}/{}",
            fmt_db(db(levels.rms())),
            fmt_db(db(levels.peak() as f64))
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

    // The octave bands up to the Nyquist frequency, each relative to the
    // loudest of them. A band's centre is the geometric mean of its edges.
    let octaves: Vec<_> = analysis
        .bands
        .iter()
        .filter(|band| !OUTSIDE_THE_OCTAVES.contains(&band.name.as_str()))
        .take_while(|band| (band.low * band.high).sqrt() < rate / 2.0)
        .collect();
    let loudest = octaves
        .iter()
        .map(|band| band.share)
        .fold(f64::MIN, f64::max);
    write!(
        out,
        "spectrum (octave bands, dB relative to the loudest band):"
    )?;
    for band in octaves {
        write!(out, " {} {}", band.name, fmt_db(band.share - loudest))?;
    }
    let centroid = analysis.centroid;
    writeln!(
        out,
        "\nspectral centroid {centroid:.0} Hz ({})",
        brightness(centroid)
    )?;
    Ok(out)
}

/// The levels of all channels together over the frames `from..to`.
fn all_channels(audio: &Audio, from: usize, to: usize) -> Levels {
    let mut levels = Levels::default();
    for ch in &audio.channels {
        levels.push(&ch[from..to]);
    }
    levels
}

/// The analysis of the file as a stereo programme: left and right as they
/// are, one channel on both sides, and more than two mixed down to one.
fn programme(audio: &Audio) -> Analysis {
    let mut analyzer = Analyzer::new(audio.sample_rate as f64);
    match audio.channels.as_slice() {
        [left, right] => analyzer.push(left, right),
        [mono] => analyzer.push(mono, mono),
        channels => {
            let share = 1.0 / channels.len() as f32;
            let mix: Vec<f32> = (0..audio.frames())
                .map(|i| channels.iter().map(|ch| ch[i]).sum::<f32>() * share)
                .collect();
            analyzer.push(&mix, &mix);
        }
    }
    analyzer.finish()
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
        assert!(text.contains("mono (left = right)"), "{text}");
        assert_eq!(band(&text, "1k"), 0.0, "{text}");
        assert!(band(&text, "250") < -30.0, "{text}");
        let centroid: f64 = after(&text, "spectral centroid ").parse().unwrap();
        assert!((centroid - 1000.0).abs() < 50.0, "{text}");
    }

    /// The word after `label` in `text`.
    fn after<'a>(text: &'a str, label: &str) -> &'a str {
        let (_, rest) = text
            .split_once(label)
            .unwrap_or_else(|| panic!("no {label:?}"));
        rest.split_whitespace().next().unwrap()
    }

    /// The level of an octave band on the spectrum line.
    fn band(text: &str, label: &str) -> f64 {
        let line = text.lines().find(|l| l.starts_with("spectrum (")).unwrap();
        after(line, &format!(" {label} ")).parse().unwrap()
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
