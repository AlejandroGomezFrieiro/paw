//! The tools that listen: render and measure the song, or measure a file.

use std::fmt::Write as _;
use std::path::Path;

use serde_json::{Map, Value, json};

use super::{Effect, Outcome, Run, Tool, Tools, err, items};
use crate::audio::{self, Segments};
use crate::format;
use crate::music::{self, Meter, num};
use crate::schema::*;

pub(super) fn tools() -> Vec<Tool> {
    vec![
        Tool {
            name: "render",
            title: "Render and measure",
            description: "Render the project (or a stretch of it) to a file, faster than real time, and measure it: duration, loudness in LUFS (integrated, short-term maximum, loudness range) and true peak, and, for WAV, peak and RMS per channel, clipping, stereo correlation and width, level per bar, and octave-band spectrum. The format is the file's extension: wav, flac, and mp3, ogg or opus when ffmpeg is installed. Choose the stretch with `region` (a marker region by name), or `start` and `end`; only some tracks with `tracks` (they play through what they pass through to the master, as when soloed); every track on its own with `stems` (then `path` is a directory). `loudness` (LUFS) and `normalize` (peak dB) bring the file to a level. The file is written under the server's working directory unless --allow-any-path.".into(),
            schema: obj(json!({
                "path": {"type": "string", "description": "File to write (default render.wav; with stems, the directory, default stems); overwritten if it exists"},
                "start": position("Where to start (default the start)"),
                "end": position("Where to stop (default the end of the last clip)"),
                "region": marker_ref("Render this region (a named stretch made with the marker tool); instead of start and end"),
                "tracks": {"type": "array", "items": track_ref("A track"), "description": "Only these tracks, with what they pass through"},
                "stems": {"type": "boolean", "description": "One file per track in the directory `path`, named after the track (the tracks that are not muted and have clips, or `tracks`)"},
                "format": {"type": "string", "enum": ["wav", "flac", "mp3", "ogg", "opus"], "description": "With stems: the files' format (default wav); otherwise the path's extension decides"},
                "tail": {"type": "number", "minimum": 0, "description": "Seconds to keep rendering after the end, for release and echoes (default 1)"},
                "bits": {"type": "integer", "enum": [16, 24, 32], "description": "16 or 24 bit PCM, or 32 bit float (default 24)"},
                "sample_rate": {"type": "integer", "minimum": 8000, "maximum": 192000, "description": "Sample rate (default the engine's)"},
                "loudness": {"type": "number", "minimum": -70, "maximum": 0, "description": "Bring the integrated loudness to this level in LUFS, such as -14"},
                "normalize": {"type": "number", "maximum": 0, "description": "Bring the loudest sample to this level in dB, such as -1; with loudness, a ceiling"},
                "quality": {"type": "string", "enum": ["low", "medium", "high", "best"], "description": "For mp3, ogg and opus (default high)"},
                "max_segments": {"type": "integer", "minimum": 1, "maximum": 128, "description": "At most this many level-over-time pieces; bars are grouped to fit (default 32)"}
            }), &[]),
            effect: Effect::Changes,
            run: Run::Call(Tools::render),
        },
        Tool {
            name: "analyze_audio",
            title: "Measure an audio file",
            description: "Measure an audio file, such as an earlier render or a sample: loudness in LUFS and true peak (any format paw reads), and for WAV also duration, peak and RMS per channel, stereo, level over time and spectrum. Reads only.".into(),
            schema: obj(json!({
                "path": {"type": "string", "description": "Audio file"},
                "segment_seconds": {"type": "number", "exclusiveMinimum": 0, "description": "Length of each level-over-time piece (default: the file split into about 16)"}
            }), &["path"]),
            effect: Effect::Reads,
            run: Run::Call(Tools::analyze_audio),
        },
    ]
}

impl Tools {
    fn render(&mut self, a: &Map<String, Value>) -> Outcome {
        let meter = self.meter()?;
        let stems = a.get("stems") == Some(&json!(true));
        if a.contains_key("region") && (a.contains_key("start") || a.contains_key("end")) {
            return err("give a `region` or `start` and `end`, not both");
        }
        if a.contains_key("format") && !stems {
            return err("`format` is for stems; for one file, its extension says the format");
        }
        let default = if stems { "stems" } else { "render.wav" };
        let path = self.output_path(a.get("path").and_then(Value::as_str).unwrap_or(default))?;
        let mut args = a.clone();
        args.insert("path".into(), json!(path));
        for key in ["start", "end"] {
            if let Some(v) = a.get(key) {
                args.insert(key.into(), json!(music::position(v, &meter, key)?));
            }
        }
        args.remove("max_segments");
        let r = self.lua("render", Value::Object(args))?;
        let info = &r["render"];
        let (start, end) = (
            info["start"].as_f64().unwrap_or(0.0),
            info["end"].as_f64().unwrap_or(0.0),
        );
        let tail = num(a.get("tail").and_then(Value::as_f64).unwrap_or(1.0));
        let wav = |p: &Path| p.extension().is_some_and(|e| e.eq_ignore_ascii_case("wav"));
        let mut out = String::new();
        if stems {
            let files = items(&info["stems"]);
            let _ = writeln!(
                out,
                "Rendered {} stem{} of beats {} to {} (+{tail} s tail) into {}",
                files.len(),
                if files.len() == 1 { "" } else { "s" },
                format::at(start, &meter),
                format::at(end, &meter),
                path.display()
            );
            for f in files.iter().filter_map(Value::as_str) {
                let file = Path::new(f);
                let name = file.file_name().map_or(f.into(), |n| n.to_string_lossy());
                let levels = if wav(file) {
                    audio::read_wav(file).map(|w| audio::level_line(&w)).unwrap_or_else(|e| format!("{e:#}"))
                } else {
                    "not a WAV: levels are measured on WAV files".into()
                };
                let _ = writeln!(out, "  {name}: {levels}");
            }
        } else {
            let _ = writeln!(
                out,
                "Rendered beats {} to {} (+{tail} s tail) to {}",
                format::at(start, &meter),
                format::at(end, &meter),
                path.display()
            );
            if let Some(length) = info["project_length"].as_f64()
                && end > length + meter.bar()
            {
                let _ = writeln!(
                    out,
                    "Note: the end is {} beats after the last clip, so that part is silence.",
                    num(end - length)
                );
            }
            if let Some(line) = format::loudness(&r["loudness"]) {
                out.push_str(&line);
            }
            if wav(&path) {
                let audio = audio::read_wav(&path)?;
                let segments = Segments::Bars {
                    start_beat: start,
                    tempo: info["tempo"].as_f64().unwrap_or(120.0),
                    bar_beats: meter.bar(),
                    end_beat: end,
                };
                let max = a.get("max_segments").and_then(Value::as_u64).unwrap_or(32) as usize;
                out.push_str(&audio::analyze(&audio, segments, max)?);
            } else {
                out.push_str("(level per bar, stereo and spectrum are measured on WAV files; render a WAV to see them)\n");
            }
        }
        let mut reply = Self::reply(out, &r, &meter);
        reply.data["path"] = json!(path.display().to_string());
        Ok(reply)
    }

    fn analyze_audio(&mut self, a: &Map<String, Value>) -> Outcome {
        let path = self.read_path(a["path"].as_str().unwrap_or(""));
        if !path.is_file() {
            return err(format!("no audio file at {}", path.display()));
        }
        let r = self.lua("analyze", json!({ "path": path }))?;
        let mut out = format!("{}: ", path.display());
        if path.extension().is_some_and(|e| e.eq_ignore_ascii_case("wav")) {
            let audio = audio::read_wav(&path)?;
            let seconds =
                audio.channels.first().map_or(0, Vec::len) as f64 / audio.sample_rate as f64;
            let piece = a
                .get("segment_seconds")
                .and_then(Value::as_f64)
                .unwrap_or_else(|| (seconds / 16.0).max(0.05));
            out.push_str(&audio::analyze(&audio, Segments::Seconds(piece), 128)?);
        } else {
            out.push('\n');
            out.push_str("(only WAV files are analysed for levels over time and spectrum)\n");
        }
        if let Some(line) = format::loudness(&r["loudness"]) {
            out.push_str(&line);
        }
        Ok(Self::reply(out, &r, &Meter::default()))
    }
}
