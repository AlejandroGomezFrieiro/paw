//! What several extensions need and the core does once: the levels of a
//! sound file, writing one, finding a program. `api/system.rs` defines the
//! `paw.api` functions with their documentation; the work is here.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use std::path::Path;
use std::sync::Arc;

use mlua::{Lua, LuaString, Table, Value as LuaValue};
use paw_engine::wav::WavFormat;

fn fail(what: impl std::fmt::Display) -> mlua::Error {
    mlua::Error::runtime(what.to_string())
}

/// `paw.api.sound_envelope`: the levels of a file as a table, with
/// `onset` and `blocks` over the decoded levels.
pub(crate) fn sound_envelope(lua: &Lua, path: &str) -> mlua::Result<Table> {
    let env = Arc::new(paw_engine::envelope::envelope(Path::new(path)).map_err(|e| fail(format!("{e:#}")))?);
    let rate = env.sample_rate as f64;
    let t = lua.create_table()?;
    t.set("rate", env.sample_rate)?;
    t.set("channels", env.channels)?;
    t.set("frames", env.frames.len())?;
    t.set("seconds", env.frames.len() as f64 / rate)?;
    t.set("peaks", env.peaks.clone())?;
    t.set("peak", env.peaks.iter().copied().fold(0.0f32, f32::max))?;
    let e = env.clone();
    t.set(
        "onset",
        lua.create_function(move |_, (level, from): (f32, Option<f64>)| {
            let from = (from.unwrap_or(0.0).max(0.0) * rate) as usize;
            Ok(e.onset(level, from).map(|f| f as f64 / rate))
        })?,
    )?;
    let e = env;
    t.set(
        "blocks",
        lua.create_function(move |_, (from, to, ms): (Option<f64>, Option<f64>, Option<f64>)| {
            let from = (from.unwrap_or(0.0).max(0.0) * rate) as usize;
            let to = to.map_or(e.frames.len(), |t| (t.max(0.0) * rate) as usize);
            let per = ((rate * ms.unwrap_or(1.0) / 1000.0) as usize).max(1);
            Ok(e.blocks(from, to, per))
        })?,
    )?;
    Ok(t)
}

/// `paw.api.sound_write`: `source` is the samples as bytes of 32-bit
/// floats (the machine's order), interleaved, or a function of `(frame,
/// count)` giving them a piece at a time until it gives nil.
pub(crate) fn sound_write(path: &str, opts: &Table, source: LuaValue) -> mlua::Result<usize> {
    let rate: u32 = opts.get::<Option<u32>>("rate")?.ok_or_else(|| fail("a sound needs a `rate`"))?;
    let channels: u16 = opts.get::<Option<u16>>("channels")?.unwrap_or(2);
    let bits: u16 = opts.get::<Option<u16>>("bits")?.unwrap_or(16);
    let format = WavFormat::from_bits(bits)
        .filter(|_| channels > 0)
        .ok_or_else(|| fail("a sound is written with 16, 24 or 32 (float) bits, and one channel or more"))?;
    let mut w = paw_engine::wav::Writer::with_channels(Path::new(path), rate, format, channels)
        .map_err(|e| fail(format!("{path}: {e:#}")))?;
    let mut samples = 0usize;
    let mut put = |bytes: &[u8]| -> mlua::Result<usize> {
        for c in bytes.chunks_exact(4) {
            w.write(f32::from_ne_bytes([c[0], c[1], c[2], c[3]])).map_err(|e| fail(format!("{path}: {e:#}")))?;
        }
        samples += bytes.len() / 4;
        Ok(bytes.len() / 4)
    };
    match source {
        LuaValue::String(s) => {
            put(&s.as_bytes())?;
        }
        LuaValue::Function(f) => {
            // A second a piece, so a long sound takes no more memory.
            let piece = rate as usize;
            let mut frame = 0usize;
            loop {
                let Some(bytes) = f.call::<Option<LuaString>>((frame, piece))? else { break };
                let n = put(&bytes.as_bytes())?;
                if n == 0 {
                    break;
                }
                frame += n / channels as usize;
            }
        }
        _ => return Err(fail("the samples are bytes or a function that gives them")),
    }
    w.finish().map_err(|e| fail(format!("{path}: {e:#}")))?;
    Ok(samples / channels as usize)
}

/// `paw.api.which`: where a program is on `PATH`, like `command -v`.
pub(crate) fn which(program: &str) -> Option<String> {
    use std::os::unix::fs::PermissionsExt;
    let runnable = |p: &Path| {
        p.metadata()
            .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    };
    if program.contains('/') {
        return runnable(Path::new(program)).then(|| program.to_string());
    }
    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path)
        .map(|dir| dir.join(program))
        .find(|p| runnable(p))
        .map(|p| p.to_string_lossy().into_owned())
}
