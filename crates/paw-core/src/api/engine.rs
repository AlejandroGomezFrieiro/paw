//! `paw.api`: the engine: audio devices, statistics and renders.

use std::path::PathBuf;
use std::rc::Rc;

use paw_engine::backend::{BackendChoice, BackendOptions, TestInput};
use mlua::{Lua, Table, Value as LuaValue};
use serde::Deserialize;

use crate::model::Id;
use crate::session::{FilterRule, RenderOpts};

use super::{LuaResult, Shared, from_lua, options, to_lua};

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct EngineOpts {
    backend: Option<String>,
    sample_rate: Option<u32>,
    buffer_size: Option<u32>,
    /// Open the audio device's input. On by default.
    input: Option<bool>,
    /// Devices by name, id or part of a name; the system's default without.
    output_device: Option<String>,
    input_device: Option<String>,
    test_input: Option<TestInputOpts>,
    /// MIDI ports for the null backend to list, by name.
    test_midi: Option<Vec<String>>,
    /// Open the real MIDI ports even on the null backend, which otherwise
    /// leaves them closed.
    midi: Option<bool>,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct AudioWatchOpts {
    auto: Option<bool>,
    period: Option<f64>,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct TestDeviceOpts {
    present: Option<bool>,
    fail_after: Option<u64>,
    back_after: Option<u64>,
}

/// Which devices to change to: `{ output = "UR22", input = "UR22", buffer = 128 }`.
#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct AudioUseOpts {
    output: Option<String>,
    input: Option<String>,
    buffer: Option<u32>,
    /// The sound system: `auto`, `pipewire`, `alsa`, `jack`.
    backend: Option<String>,
    /// Hz, or 0 for the device's own.
    rate: Option<u32>,
}

/// A sine for the null backend to use as input: `{ frequency = 440, level = -12, channels = 2 }`.
#[derive(Deserialize)]
#[serde(default, deny_unknown_fields)]
struct TestInputOpts {
    frequency: f64,
    /// Peak level in dB.
    level: f64,
    channels: u16,
}

impl Default for TestInputOpts {
    fn default() -> Self {
        Self {
            frequency: 440.0,
            level: -12.0,
            channels: 2,
        }
    }
}

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- engine ---
        // @return types.EngineInfo
        fn engine_get(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().engine_view()) }
        // What changes of the engine by itself, as `engine_get` gives it but
        // without a table, for what is read on each frame: `cpu`, `xruns`
        // and `block`.
        // @return number, integer, integer
        fn engine_load(_, sh, () => ()) { Ok(sh.session.borrow().engine_load()) }
        // The number of audio blocks that the engine finished since it
        // started. With a device id, the number of blocks that this device
        // ran: the blocks that it slept through do not count. A change sent
        // to the engine is in effect in the block after the next one that
        // finishes, so wait until the count is two more (the test helper
        // `T.next_block` does this). Nil for a device that the engine does
        // not have.
        // @return integer
        fn blocks(_, sh, device => Option<Id>) {
            Ok(sh.session.borrow().blocks(device))
        }
        // Forget the process times that `engine_get().blocks` recorded until now.
        // @return nil
        fn engine_reset_stats(_, sh, () => ()) {
            sh.session.borrow().engine_reset_stats();
            Ok(())
        }
        // Play a part from a sound file for now, as if it is frozen, or live
        // again with nil. Nil also works for a part that is gone. Another
        // project plays all its parts live. The project does not change
        // (see `freeze.rs`).
        // @return nil
        fn engine_hold(_, sh, (part, file) => (Id, Option<String>)) {
            sh.session.borrow_mut().hold(part, file.map(PathBuf::from)).lua()
        }
        // @return {integer}
        fn engine_held(_, sh, () => ()) { Ok(sh.session.borrow().held()) }
        // Only these parts heard for now, as a solo would, or all with nil.
        // @return nil
        fn engine_audible(_, sh, parts => Option<Vec<Id>>) {
            sh.session.borrow_mut().set_audible(parts);
            Ok(())
        }
        // The part that plays MIDI input while no part is armed, as if
        // monitored, or none with nil (`paw.opt.midi_follows_selection`).
        // @return nil
        fn engine_follow(_, sh, part => Option<Id>) {
            sh.session.borrow_mut().set_follow(part);
            Ok(())
        }
        // The part that plays MIDI input as if monitored, also while another
        // part is armed, or none with nil. While set, it takes the place of
        // `engine_follow`'s part. Step input sets it to the part of the
        // clip it enters into, so that the controller sounds there.
        // @return nil
        fn engine_follow_always(_, sh, part => Option<Id>) {
            sh.session.borrow_mut().set_follow_always(part);
            Ok(())
        }
        // Controls of MIDI input that parts do not get: they neither sound
        // nor record. Scripts still hear them, as `midi.in` events with
        // `filtered = true`. Each `name` (`"step"`, `"learn"`) keeps its own
        // list beside the others; nil or an empty list removes it.
        // @param rules? {types.MidiFilterRule}
        // @return nil
        fn engine_midi_filter(lua, sh, (name, rules) => (String, LuaValue)) {
            let rules: Vec<FilterRule> = match rules {
                LuaValue::Nil => Vec::new(),
                rules => from_lua(lua, rules)?,
            };
            sh.session.borrow_mut().set_midi_filter(&name, rules).lua()
        }
        // The number of threads that process parts, with the audio thread. 0
        // lets paw select the number. `engine_get().threads` gives the number in use.
        // @return nil
        fn engine_set_threads(_, sh, threads => usize) {
            sh.session.borrow_mut().set_threads(threads).lua()
        }
        // With true, devices at rest sleep through silence: a reverb after
        // its tail, a synth with no note that sounds. When the song is
        // stopped and nothing sounds, the whole engine rests. The sound is
        // the same with false. `engine_get().device_sleeps` counts the
        // blocks that devices slept through, and `engine_get().engine_rests`
        // the blocks that the engine rested.
        // @return nil
        fn engine_set_sleep(_, sh, sleep => bool) {
            sh.session.borrow_mut().set_sleep(sleep);
            Ok(())
        }
        // The quality that the built-in devices play at live: `"full"`, or
        // `"edit"` to lower their costly settings while you edit, such as the
        // oversampling of `saturation`. A render, an export, stems, a
        // freeze and a bounce always play at full quality. `paw.opt.quality`
        // calls it.
        // @return nil
        fn engine_set_quality(_, sh, quality => String) {
            let quality = quality.parse().lua()?;
            sh.session.borrow_mut().set_quality(quality);
            Ok(())
        }
        // Start the engine again with these options. With no `backend`, it
        // keeps the one that runs: `null`, `step`, `test` or the sound system
        // that opened.
        // @param opts? types.EngineOptions
        // @return nil
        fn engine_restart(lua, sh, opts => LuaValue) {
            let opts: EngineOpts = options(lua, opts)?;
            let running = sh.session.borrow().backend().clone();
            let backend = BackendOptions {
                backend: opts.backend.as_deref().map_or(running, BackendChoice::from),
                sample_rate: opts.sample_rate,
                buffer_size: opts.buffer_size,
                input: opts.input.unwrap_or(true),
                output_device: opts.output_device,
                input_device: opts.input_device,
                test_input: opts.test_input.map(|t| TestInput {
                    frequency: t.frequency,
                    level: t.level,
                    channels: t.channels,
                }),
            };
            let mut session = sh.session.borrow_mut();
            session.set_test_ports(opts.test_midi.unwrap_or_default());
            session.set_midi_without_audio(opts.midi.unwrap_or(false));
            session.engine_restart(&backend).lua()
        }
        // The audio devices the system offers, and which are open.
        // @return types.AudioDevices
        fn audio_devices(lua, sh, () => ()) {
            to_lua(lua, &sh.session.borrow().audio_devices().lua()?)
        }
        // Try to open again the device that went away. Returns true when it is open.
        // @return boolean
        fn audio_reconnect(_, sh, () => ()) { sh.session.borrow_mut().audio_reconnect().lua() }
        // With `{ auto = false }`, paw does not open again a device that returns
        // by itself. `period` is the interval between checks, in milliseconds.
        // @return nil
        // @param opts? types.AudioWatchOptions
        fn audio_watch(lua, sh, opts => LuaValue) {
            let opts: AudioWatchOpts = options(lua, opts)?;
            let period = opts.period.map(super::millis);
            sh.session.borrow_mut().set_audio_watch(opts.auto, period);
            Ok(())
        }
        // The simulated device of the `test` backend. `{ present = false }`
        // disconnects it. `fail_after = n` disconnects it after n blocks of the
        // next stream. `back_after = ms` connects it again `ms` after it goes.
        // @return nil
        // @param opts? types.TestDeviceOptions
        fn audio_test_device(lua, _sh, opts => LuaValue) {
            let opts: TestDeviceOpts = options(lua, opts)?;
            paw_engine::backend::test_device::set(opts.present, opts.fail_after, opts.back_after);
            Ok(())
        }
        // The MIDI ports the null backend lists, as if plugged in.
        // @return nil
        fn midi_test_ports(_, sh, ports => Vec<String>) {
            sh.session.borrow_mut().set_test_ports(ports);
            Ok(())
        }
        // Open other devices, and remember them for the next run.
        // @param opts? types.AudioUseOptions
        // @return nil
        fn audio_use(lua, sh, opts => LuaValue) {
            let opts: AudioUseOpts = options(lua, opts)?;
            let choice = crate::session::AudioChoice { backend: opts.backend, rate: opts.rate };
            sh.session.borrow_mut().audio_use(opts.output, opts.input, opts.buffer, choice).lua()
        }
        // The level of each input channel of the device, as linear gain,
        // whatever takes it.
        // @return {number}
        fn input_levels(_, sh, () => ()) { Ok(sh.session.borrow().input_levels()) }
        // What a render can write: `{ { name = "WAV", extensions = { "wav" } } }`.
        // @return {types.RenderFormat}
        fn render_formats(lua, _sh, ffmpeg => Option<String>) {
            to_lua(lua, &crate::session::render::formats_json(ffmpeg.as_deref()))
        }
        // Nothing when a render can write `path`, or why not.
        // @return string
        fn render_check(_, _sh, (path, ffmpeg) => (String, Option<String>)) {
            Ok(crate::session::render::format_of(path.as_ref(), ffmpeg.as_deref()).err().map(|e| e.to_string()))
        }
        // @param opts? types.RenderOptions
        // @return types.RenderResult
        fn render(lua, sh, (path, opts) => (String, LuaValue)) {
            let opts: RenderOpts = options(lua, opts)?;
            to_lua(lua, &sh.session.borrow_mut().render(path.as_ref(), &opts).lua()?)
        }
        // Start a render on a separate thread. Then the events `render.progress`
        // and `render.done`, `render.failed` or `render.cancelled` come.
        // @param opts? types.RenderOptions
        // @return nil
        fn render_start(lua, sh, (path, opts) => (String, LuaValue)) {
            let opts: RenderOpts = options(lua, opts)?;
            sh.session.borrow_mut().render_start(path.as_ref(), &opts).lua()
        }
        // @return boolean
        fn render_cancel(_, sh, () => ()) { Ok(sh.session.borrow_mut().render_cancel()) }
        // The render that runs now, `{ path, fraction, seconds, cancelling }`, or nil.
        // @return types.RenderStatus
        fn render_status(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().render_status()) }

    }
    Ok(())
}
