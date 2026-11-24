//! `paw.api`: sound files, programs, the file system, the environment and kept state.
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]

use std::path::Path;
use std::rc::Rc;

use mlua::{Lua, Table, Value as LuaValue};
use serde_json::Value;

use super::{Shared, from_lua, to_lua};

// What `paw.api.build()` gives, so that the loader of extensions refuses one
// whose `needs` this build does not have (runtime/lua/paw/ext.lua). The Lua
// follows the mlua feature of Cargo.toml. A planned split of the kernel puts processes and network
// behind the cargo feature `native`; its gates go here too.
#[cfg(not(target_vendor = "browserpod"))]
const BUILD_VM: &str = "luajit";
#[cfg(not(target_vendor = "browserpod"))]
const BUILD_FEATURES: &[&str] = &["ffi", "processes", "network", "native"];
// A BrowserPod pod: PUC Lua 5.2 without `ffi`, and no plugins.
#[cfg(target_vendor = "browserpod")]
const BUILD_VM: &str = "lua52";
#[cfg(target_vendor = "browserpod")]
const BUILD_FEATURES: &[&str] = &["processes", "network"];

/// A folder as the Lua side sees it.
fn lua_path(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- sound files, programs ---

        // The levels of a sound file, any format the engine plays: `{ rate,
        // channels, frames, seconds, peaks, peak, onset, blocks }`, levels
        // as linear gain. `peaks` holds the loudest sample of each channel,
        // `peak` the loudest of all. `onset(level, from)` gives the time in
        // seconds of the first frame, at `from` seconds or later, where a
        // channel is louder than `level` (nil when none is). `blocks(from,
        // to, ms)` gives the loudest sample of each block of `ms`
        // milliseconds (default 1) between two times in seconds.
        // @return types.SoundEnvelope
        fn sound_envelope(lua, _sh, path => String) { crate::ext_api::sound_envelope(lua, &path) }
        // Write a WAV file: `opts` is `{ rate, channels (2), bits (16, 24,
        // or 32 for float) }`. `samples` is the interleaved samples as bytes
        // of 32-bit floats in the order of the machine (`ffi.string` of a
        // `float[?]`), or a function `(frame, count)` that gives them one
        // piece at a time and nil at the end. Returns the number of frames.
        // @param opts types.SoundWriteOptions
        // @param samples string | function(frame: integer, count: integer): string
        // @return integer
        fn sound_write(_, _sh, (path, opts, samples) => (String, Table, LuaValue)) {
            crate::ext_api::sound_write(&path, &opts, samples)
        }
        // Where a program is on `PATH`, as `command -v` says; nil when it
        // is not there. A name with a `/` is checked as it is.
        // @return string
        fn which(_, _sh, program => String) { Ok(crate::ext_api::which(&program)) }
        // Remove a file, or a directory with all it holds: only for what paw
        // or an extension made for itself, a cache or a temporary folder.
        // The files of the user go to the trash (`fs_trash`) instead.
        // Nothing there is no error.
        // @return nil
        fn fs_remove(_, _sh, path => String) {
            let p = Path::new(&path);
            let Ok(meta) = p.symlink_metadata() else { return Ok(()) };
            let done = if meta.is_dir() { std::fs::remove_dir_all(p) } else { std::fs::remove_file(p) };
            done.map_err(|e| mlua::Error::runtime(format!("{path}: {e}")))
        }
        // The space of the disk that holds a path: `{ free, total }` in
        // bytes (free: what a program that is not root can use).
        // @return types.DiskSpace
        fn fs_space(lua, _sh, path => String) {
            let st = rustix::fs::statvfs(path.as_str())
                .map_err(|e| mlua::Error::runtime(format!("{path}: {}", std::io::Error::from(e))))?;
            let t = lua.create_table()?;
            t.set("free", st.f_bavail as f64 * st.f_frsize as f64)?;
            t.set("total", st.f_blocks as f64 * st.f_frsize as f64)?;
            Ok(t)
        }
        // True when a file or directory is there (a link that leads nowhere is not).
        // @return boolean
        fn fs_exists(_, _sh, path => String) { Ok(Path::new(&path).exists()) }
        // @return {string}
        fn warnings(_, sh, () => ()) { Ok(std::mem::take(&mut sh.session.borrow_mut().doc.warnings)) }
        // Open an item of the start that `paw --startuptime` times: a module,
        // an extension, the configuration. `startup_leave` closes it with its
        // line. Nothing happens when the start is not timed.
        // @return nil
        fn startup_enter(_, _sh, () => ()) {
            crate::startuptime::enter();
            Ok(())
        }
        // Close the item `startup_enter` opened last: its line in the file of
        // `--startuptime` gives its time with and without the items opened in it.
        // @return nil
        fn startup_leave(_, _sh, label => String) {
            crate::startuptime::leave(&label);
            Ok(())
        }
        // True while `paw --startuptime` times the start.
        // @return boolean
        fn startup_timed(_, _sh, () => ()) { Ok(crate::startuptime::is_on()) }
        // What this build of paw has: `{ vm, features }`. `vm` is the Lua
        // that runs the code, `"luajit"` or `"lua52"`. `features` lists
        // what an extension can name in the `needs` of its manifest:
        // `"ffi"` (LuaJIT's `ffi`), `"processes"` (helper programs,
        // `io.popen`), `"network"` (sockets and requests over the network)
        // and `"native"` (parts that Nix builds, such as plugins).
        // @return types.Build
        fn build(lua, _sh, () => ()) {
            let t = lua.create_table()?;
            t.set("vm", BUILD_VM)?;
            t.set("features", BUILD_FEATURES)?;
            Ok(t)
        }
        // @return types.Env
        fn env(lua, sh, () => ()) {
            let env = lua.create_table()?;
            env.set("config_dir", sh.env.config_dir.to_string_lossy().into_owned())?;
            env.set("runtime_dir", sh.env.runtime_dir.as_ref().map(|p| p.to_string_lossy().into_owned()))?;
            env.set("clean", sh.env.clean)?;
            env.set("scripted", sh.env.scripted)?;
            // Where the program keeps what is the user's but not configuration:
            // recordings and the like, and what it needs between runs.
            let dirs = sh.session.borrow().dirs.clone();
            env.set("data_dir", lua_path(&dirs.paw_data()))?;
            env.set("state_dir", lua_path(&dirs.paw_state()))?;
            env.set("pid", std::process::id())?;
            env.set("argv", sh.env.argv.clone())?;
            // A hash of the Teal declarations and modules of the runtime: it
            // changes when the types that an extension in Teal sees change.
            env.set("teal_types", crate::kernel::teal_types())?;
            Ok(env)
        }
        // The text of a file of the runtime that is built into the program,
        // by its path under `runtime`: a module (`lua/paw/util.tl`) or a
        // declaration of Teal (`types/paw.d.tl`). Nil when the program has
        // no such file. The loader checks the types of a file in Teal with
        // these.
        // @return string
        fn runtime_file(_, _sh, path => String) { Ok(crate::kernel::runtime_file(&path)) }
        // @return any
        fn state_get(lua, sh, key => String) {
            match sh.state.borrow().get(&key) {
                Some(value) => to_lua(lua, value),
                None => Ok(LuaValue::Nil),
            }
        }
        // @return nil
        fn state_set(lua, sh, (key, value) => (String, LuaValue)) {
            if value.is_nil() {
                sh.state.borrow_mut().remove(&key);
            } else {
                let value: Value = from_lua(lua, value)?;
                sh.state.borrow_mut().insert(key, value);
            }
            Ok(())
        }
        // @return {types.DirEntry}
        fn read_dir(lua, _sh, path => String) {
            let list = lua.create_table()?;
            let Ok(entries) = std::fs::read_dir(&path) else { return Ok(list) };
            let mut names: Vec<(String, bool, Option<f64>)> = entries
                .flatten()
                .map(|e| {
                    // When it was last written, in seconds since 1970.
                    let mtime = e.metadata().ok().and_then(|m| m.modified().ok())
                        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                        .map(|d| d.as_secs_f64());
                    (e.file_name().to_string_lossy().into_owned(), e.path().is_dir(), mtime)
                })
                .collect();
            names.sort_by(|a, b| a.0.cmp(&b.0));
            for (name, is_dir, mtime) in names {
                let entry = lua.create_table()?;
                entry.set("name", name)?;
                entry.set("is_dir", is_dir)?;
                entry.set("mtime", mtime)?;
                list.push(entry)?;
            }
            Ok(list)
        }
    }
    Ok(())
}
