//! The API reference, made from the source this program was built from: the
//! kernel's flat `paw.api` functions (the comments above each in
//! `crates/paw-core/src/api/`) and the documented functions of the Lua
//! modules in `runtime/lua/paw`. Nothing is written by hand, so the
//! reference is as current as the build.

use include_dir::{Dir, include_dir};

static RUNTIME: Dir = include_dir!("$CARGO_MANIFEST_DIR/../../runtime/lua");
/// The files of `crates/paw-core/src/api/`, in the order of the sections
/// of the reference. A file left out of this list loses its functions from
/// the reference: the test `every_file_of_the_api_is_read` checks it.
const API: [(&str, &str); 16] = [
    ("mod.rs", include_str!("../../paw-core/src/api/mod.rs")),
    ("project.rs", include_str!("../../paw-core/src/api/project.rs")),
    ("tracks.rs", include_str!("../../paw-core/src/api/tracks.rs")),
    ("devices.rs", include_str!("../../paw-core/src/api/devices.rs")),
    ("clips.rs", include_str!("../../paw-core/src/api/clips.rs")),
    ("automation.rs", include_str!("../../paw-core/src/api/automation.rs")),
    ("transport.rs", include_str!("../../paw-core/src/api/transport.rs")),
    ("midi.rs", include_str!("../../paw-core/src/api/midi.rs")),
    ("engine.rs", include_str!("../../paw-core/src/api/engine.rs")),
    ("undo.rs", include_str!("../../paw-core/src/api/undo.rs")),
    ("screen.rs", include_str!("../../paw-core/src/api/screen.rs")),
    ("timers.rs", include_str!("../../paw-core/src/api/timers.rs")),
    ("processes.rs", include_str!("../../paw-core/src/api/processes.rs")),
    ("formats.rs", include_str!("../../paw-core/src/api/formats.rs")),
    ("system.rs", include_str!("../../paw-core/src/api/system.rs")),
    ("kind_data.rs", include_str!("../../paw-core/src/api/kind_data.rs")),
];

/// The text between `fn name(` and the `) {` that ends the signature, as
/// `name(id: Id, range: LuaValue)`.
fn signature(line: &str) -> Option<String> {
    let rest = line.trim().strip_prefix("fn ")?;
    let (name, args) = rest.split_once('(')?;
    let args = args.split_once(") {")?.0;
    // Split at the top-level commas: `lua, sh, (id, range) => (Id, LuaValue)`.
    let mut parts = Vec::new();
    let (mut depth, mut start) = (0i32, 0usize);
    for (i, c) in args.char_indices() {
        match c {
            '(' | '<' | '[' => depth += 1,
            ')' | '>' | ']' if !(c == '>' && args[..i].ends_with('=')) => depth -= 1,
            ',' if depth == 0 => {
                parts.push(&args[start..i]);
                start = i + 1;
            }
            _ => {}
        }
    }
    parts.push(&args[start..]);
    let call = parts.get(2)?.trim();
    let Some((names, types)) = call.split_once("=>") else {
        return Some(format!("{name}()"));
    };
    let (names, types) = (names.trim(), types.trim());
    let strip = |text: &str| {
        text.trim_start_matches('(')
            .trim_end_matches(')')
            .split(',')
            .map(|p| p.trim().to_string())
            .filter(|p| !p.is_empty())
            .collect::<Vec<_>>()
    };
    let (names, types) = (strip(names), strip(types));
    let list: Vec<String> = names
        .iter()
        .enumerate()
        .map(|(i, n)| match types.get(i) {
            Some(t) if names.len() == types.len() => format!("{n}: {t}"),
            _ => n.clone(),
        })
        .collect();
    Some(format!("{name}({})", list.join(", ")))
}

/// Every `paw.api` function with what its comment says.
pub(crate) fn api() -> String {
    let mut out = String::from(
        "# paw.api reference\n\nThe kernel's flat functions, called from Lua as `paw.api.name(...)`, over the control socket (`paw ctl name args...`) as a method of the same name, and from the typed Lua objects (`paw.tracks()`, `track:add_clip(...)`). Indices count from 1 where they count; positions and lengths are in beats; volumes in dB. Generated from `crates/paw-core/src/api/` when this server was built.\n",
    );
    let mut comment: Vec<String> = Vec::new();
    for line in API.iter().flat_map(|(_, text)| text.lines()) {
        let t = line.trim();
        if let Some(text) = t.strip_prefix("//") {
            let text = text.strip_prefix(' ').unwrap_or(text);
            if let Some(section) = text
                .strip_prefix("--- ")
                .and_then(|s| s.strip_suffix(" ---"))
            {
                out.push_str(&format!("\n## {section}\n"));
                comment.clear();
            } else {
                comment.push(text.to_string());
            }
        } else if let Some(sig) = signature(t).filter(|_| t.starts_with("fn ") && t.contains(") {"))
        {
            // Only the functions of `define!` take `sh` as their second argument.
            if t.contains("sh,") || t.contains("_sh,") {
                out.push_str(&format!("\n### `{sig}`\n"));
                if !comment.is_empty() {
                    out.push_str(&format!("{}\n", comment.join("\n")));
                }
            }
            comment.clear();
        } else if !t.is_empty() {
            comment.clear();
        }
    }
    out
}

/// The modules of the Lua runtime, by name, with the first words of what each is.
pub(crate) fn lua_modules() -> Vec<(String, String)> {
    let Some(dir) = RUNTIME.get_dir("paw") else {
        return Vec::new();
    };
    let mut out: Vec<(String, String)> = dir
        .files()
        .filter_map(|f| {
            let name = f.path().file_stem()?.to_str()?.to_string();
            matches!(f.path().extension()?.to_str()?, "lua" | "tl").then(|| {
                let intro = f
                    .contents_utf8()
                    .and_then(|text| text.lines().next())
                    .and_then(|l| l.strip_prefix("--"))
                    .map(|l| l.trim().trim_start_matches('-').trim().to_string())
                    .unwrap_or_default();
                (name, intro)
            })
        })
        .collect();
    out.sort();
    out
}

/// The index of the Lua modules.
pub(crate) fn lua_index() -> String {
    let mut out = String::from(
        "# The Lua modules of paw\n\nEach is read as `paw://reference/lua/<module>`, and is `paw.<module>` in scripts. Made from the doc comments in `runtime/lua/paw`.\n\n",
    );
    for (name, intro) in lua_modules() {
        out.push_str(&format!("- `{name}`{}\n", if intro.is_empty() { String::new() } else { format!(": {intro}") }));
    }
    out
}

/// `key(beat: number): Key` as a script calls it, `key(beat)`: the name and
/// the parameters' names, without Teal's types, type parameters or a body
/// that follows on the same line.
fn untyped_call(rest: &str) -> String {
    let Some(open) = rest.find('(') else {
        return rest.trim_end_matches(" end").trim().to_string();
    };
    let name = rest[..open].split('<').next().unwrap_or("").trim();
    let mut depth = 0;
    let mut params: Vec<String> = Vec::new();
    let mut current = String::new();
    for c in rest[open + 1..].chars() {
        match c {
            '(' | '{' | '<' | '[' => depth += 1,
            ')' if depth == 0 => break,
            ')' | '}' | '>' | ']' => depth -= 1,
            ',' if depth == 0 => {
                params.push(std::mem::take(&mut current));
                continue;
            }
            _ => {}
        }
        current.push(c);
    }
    params.push(current);
    let names: Vec<&str> = params
        .iter()
        .map(|p| p.split(':').next().unwrap_or("").trim().trim_end_matches('?'))
        .filter(|p| !p.is_empty())
        .collect();
    format!("{name}({})", names.join(", "))
}

/// A module's documented functions, in the order of the file.
pub(crate) fn lua_module(module: &str) -> Option<String> {
    // A module is Lua, or Teal (Lua with types) once it is ported.
    let file = RUNTIME
        .get_file(format!("paw/{module}.lua"))
        .or_else(|| RUNTIME.get_file(format!("paw/{module}.tl")))?;
    let text = file.contents_utf8()?;
    let mut out = format!("# paw.{module}\n\n");
    // The comment at the top of the file says what the module is for.
    let intro: Vec<&str> = text
        .lines()
        .take_while(|l| l.starts_with("--") && !l.starts_with("---"))
        .map(|l| l.trim_start_matches('-').strip_prefix(' ').unwrap_or(""))
        .collect();
    if !intro.is_empty() {
        out.push_str(&intro.join("\n"));
        out.push_str("\n\n");
    }
    let mut doc: Vec<&str> = Vec::new();
    for line in text.lines() {
        if let Some(d) = line.strip_prefix("---") {
            doc.push(d.strip_prefix(' ').unwrap_or(d));
            continue;
        }
        let declared = line
            .strip_prefix("function M.")
            .or_else(|| line.strip_prefix("function M:"))
            .map(|rest| {
                let sep = if line.starts_with("function M:") { ":" } else { "." };
                (sep, rest.trim_end())
            });
        if let (Some((sep, rest)), false) = (declared, doc.is_empty()) {
            let call = untyped_call(rest);
            out.push_str(&format!("### `paw.{module}{sep}{call}`\n{}\n\n", doc.join("\n")));
        }
        doc.clear();
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_api_reference_has_the_functions_and_their_comments() {
        let text = api();
        assert!(text.contains("### `clip_notes(id: Id, range: LuaValue)`"), "{text}");
        assert!(text.contains("The notes of a MIDI clip, in the order of their start."));
        assert!(text.contains("### `undo()`"));
        assert!(text.contains("### `track_meter(id: Id)`"));
        assert!(text.matches("### `").count() > 200);
    }

    #[test]
    fn every_file_of_the_api_is_read() {
        let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/../paw-core/src/api");
        let mut files: Vec<String> = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .filter(|name| name.ends_with(".rs"))
            .collect();
        files.sort();
        let mut listed: Vec<String> = API.iter().map(|(name, _)| name.to_string()).collect();
        listed.sort();
        assert_eq!(listed, files);
    }

    #[test]
    fn the_lua_reference_has_the_documented_functions() {
        let names: Vec<String> = lua_modules().into_iter().map(|m| m.0).collect();
        assert!(names.iter().any(|n| n == "harmony"));
        let text = lua_module("harmony").unwrap();
        assert!(text.contains("### `paw.harmony.key(beat, latest)`"), "{text}");
        assert!(text.contains("The key at `beat`"));
        assert!(lua_module("no-such-module").is_none());
    }
}
