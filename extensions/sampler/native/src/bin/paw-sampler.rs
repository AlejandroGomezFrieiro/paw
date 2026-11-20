//! paw-sampler: what the plugin knows, from the command line.
//!
//!   paw-sampler describe <instrument>        its range, keyswitches and articulations as JSON
//!   paw-sampler render <instrument> <out.wav> <note>...
//!                                            plays notes `key:start:length[:velocity[:m2]]`
//!                                            (seconds; velocity 1-127; m2 like 11.A)
//!   paw-sampler bench <instrument> [voices]  the cost of a voice
//!   paw-sampler fixtures <dir>               writes the test instruments (sines of known pitches)

use anyhow::{Context, Result, anyhow};
use clap::{Parser, Subcommand};
use paw_sampler::audio::{Store, write_wav};
use paw_sampler::engine::{Engine, Program};
use paw_sampler::{describe, formats, m2, params};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Instant;

#[derive(Parser)]
#[command(name = "paw-sampler", about = "paw's sample player, from the command line")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Prints an instrument's range, keyswitches and articulations as JSON
    Describe { instrument: PathBuf },
    /// Plays notes through an instrument into a WAV file
    Render {
        instrument: PathBuf,
        out: PathBuf,
        /// A note as `key:start:length[:velocity[:m2]]`: seconds, velocity 1-127, m2 like 11.A
        notes: Vec<String>,
    },
    /// Times the cost of a voice
    Bench {
        instrument: PathBuf,
        /// How many voices to hold
        #[arg(default_value_t = 64)]
        voices: usize,
    },
    /// Writes the test instruments (sines of known pitches) into a folder
    Fixtures { dir: PathBuf },
}

fn main() {
    if let Err(e) = run(Cli::parse().command) {
        eprintln!("paw-sampler: {e:#}");
        std::process::exit(1);
    }
}

fn run(command: Command) -> Result<()> {
    match command {
        Command::Describe { instrument } => describe_instrument(&instrument),
        Command::Render { instrument, out, notes } => render(&instrument, &out, &notes),
        Command::Bench { instrument, voices } => bench(&instrument, voices),
        Command::Fixtures { dir } => Ok(paw_sampler::fixtures::write(&dir)?),
    }
}

fn load(path: &Path) -> Result<Arc<Program>> {
    let instrument = formats::read(path)?;
    Ok(Arc::new(Program::new(instrument, &mut Store::default())))
}

fn describe_instrument(path: &Path) -> Result<()> {
    let program = load(path)?;
    let defaults: Vec<f64> = params::PARAMS.iter().map(|p| p.default).collect();
    let v = describe::describe(Some(&program), &path.to_string_lossy(), None, &defaults);
    println!("{}", serde_json::to_string_pretty(&v)?);
    Ok(())
}

struct Note {
    key: u8,
    start: f64,
    end: f64,
    vel: f32,
    attr: Option<(u8, u16)>,
}

/// A note as `key:start:length[:velocity[:m2]]`.
fn parse_note(text: &str) -> Result<Note> {
    let bad = || anyhow!("bad note `{text}`");
    let f: Vec<&str> = text.split(':').collect();
    let num = |i: usize| f.get(i).and_then(|v| v.parse::<f64>().ok());
    let key = f.first().and_then(|k| formats::parse_key(k)).ok_or_else(bad)?;
    let start = num(1).ok_or_else(bad)?;
    let length = num(2).ok_or_else(bad)?;
    let attr = f.get(4).and_then(|c| m2::parse_code(c)).map(|c| ((c >> 16) as u8, c as u16));
    Ok(Note { key: key as u8, start, end: start + length, vel: num(3).unwrap_or(100.0) as f32 / 127.0, attr })
}

fn render(path: &Path, out: &Path, notes: &[String]) -> Result<()> {
    let program = load(path)?;
    let parsed = notes.iter().map(|n| parse_note(n)).collect::<Result<Vec<_>>>()?;
    let rate = 48000.0;
    let mut engine = Engine::new(rate);
    engine.swap(Some(program));
    let last = parsed.iter().map(|n| n.end).fold(0.0, f64::max) + 2.0;
    let frames = (last * rate) as usize;
    let (mut left, mut right) = (vec![0.0f32; frames], vec![0.0f32; frames]);
    // Events in time order, offs before ons at the same frame.
    let mut events: Vec<(usize, bool, usize)> = Vec::new();
    for (i, n) in parsed.iter().enumerate() {
        events.push(((n.start * rate) as usize, true, i));
        events.push(((n.end * rate) as usize, false, i));
    }
    events.sort_by_key(|e| (e.0, e.1));
    let mut at = 0;
    for (frame, on, i) in events {
        let frame = frame.min(frames);
        engine.render(&mut left[at..frame], &mut right[at..frame]);
        at = frame;
        let n = &parsed[i];
        if on {
            engine.note_on(n.key, n.vel, 0, n.attr);
        } else {
            engine.note_off(n.key, 0);
        }
    }
    engine.render(&mut left[at..], &mut right[at..]);
    let mut interleaved = Vec::with_capacity(frames * 2);
    for i in 0..frames {
        interleaved.push(left[i]);
        interleaved.push(right[i]);
    }
    Ok(write_wav(out, rate as u32, 2, &interleaved, None, None)?)
}

/// Holds `voices` notes across the instrument's range and times a
/// quarter of a second of blocks, five times over; the best time counts,
/// as the least disturbed by whatever else the machine does.
fn bench(path: &Path, voices: usize) -> Result<()> {
    let program = load(path)?;
    let (lo, hi) = program.instrument.range().context("the instrument plays no key")?;
    let rate = 48000.0;
    let block = 256;
    let blocks = 47;
    for quality in [0.0, 1.0, 2.0] {
        let mut best = f64::MAX;
        let mut sounding = 0;
        for _ in 0..5 {
            let mut engine = Engine::new(rate);
            engine.swap(Some(program.clone()));
            let mut values: Vec<f64> = params::PARAMS.iter().map(|p| p.default).collect();
            values[1] = 256.0;
            values[9] = quality;
            engine.settings = params::settings(&values);
            let mut key = lo;
            while engine.voice_count() < voices as u32 {
                let before = engine.voice_count();
                engine.note_on(key, 0.8, (engine.voice_count() % 16) as u8, None);
                key = if key >= hi { lo } else { key + 1 };
                if engine.voice_count() == before && key == lo {
                    break;
                }
            }
            let (mut left, mut right) = (vec![0.0f32; block], vec![0.0f32; block]);
            let started = Instant::now();
            for _ in 0..blocks {
                left.fill(0.0);
                right.fill(0.0);
                engine.render(&mut left, &mut right);
            }
            best = best.min(started.elapsed().as_secs_f64());
            // Voices that ended meanwhile (a short sample) would make the rest look cheap.
            sounding = engine.voice_count();
        }
        let frames = (blocks * block) as f64;
        let per_voice_frame = best / frames / sounding.max(1) as f64 * 1e9;
        let load = best / (frames / rate) * 100.0;
        let name = params::to_text(&params::PARAMS[9], quality);
        println!(
            "{name}: {sounding} voices, {per_voice_frame:.1} ns per voice and frame, {load:.1} % of a core at 48 kHz ({:.2} % per voice)",
            load / sounding.max(1) as f64
        );
    }
    println!("loaded in {:.1} ms, {} samples, {} bytes", program.load_ms, program.samples.len(), program.memory());
    Ok(())
}
