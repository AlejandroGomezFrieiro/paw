//! Tells the crate whether LuaJIT is being built to look for hooks in
//! compiled code: `.cargo/config.toml` asks for it through the C flags that
//! `mlua`'s build of LuaJIT reads.
//!
//! It also compiles the Lua runtime (`runtime/lua`) to LuaJIT bytecode, which
//! the kernel loads in place of the source: parsing the runtime was most of
//! the time the program took to start.
//!
//! A module written in Teal (`.tl`) is compiled to Lua first, by the Teal
//! compiler that the runtime contains (`runtime/lua/tl.lua`): the program
//! contains the Lua, and no `.tl` module of the runtime is compiled when it
//! starts. The types are not checked here; the test suite checks them.

use std::fmt::Write as _;
use std::path::{Path, PathBuf};

fn main() {
    println!("cargo:rustc-check-cfg=cfg(lua_checkhook)");
    let target = std::env::var("TARGET").unwrap_or_default();
    let names = [
        format!("CFLAGS_{target}"),
        format!("CFLAGS_{}", target.replace('-', "_")),
        "TARGET_CFLAGS".to_string(),
        "CFLAGS".to_string(),
    ];
    for name in &names {
        println!("cargo:rerun-if-env-changed={name}");
    }
    // The first of these that is set is the one the C compiler is given.
    let flags = names.iter().find_map(|name| std::env::var(name).ok());
    if flags.is_some_and(|flags| flags.contains("LUAJIT_ENABLE_CHECKHOOK")) {
        println!("cargo:rustc-cfg=lua_checkhook");
    }
    compile_runtime(&target);
}

/// Write `$OUT_DIR/bytecode.rs`: the runtime's modules as bytecode, by their
/// path under `runtime/lua`, sorted (`BYTECODE`), empty when the program is
/// built for another machine, whose LuaJIT may not read this one's
/// bytecode; and the Lua that each Teal module compiles to (`TEAL`).
fn compile_runtime(target: &str) {
    let out = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR"));
    let root = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"))
        .join("../../runtime/lua");
    println!("cargo:rerun-if-changed={}", root.display());
    let mut files = Vec::new();
    collect(&root, &root, &mut files);
    files.sort();
    let lua = mlua::Lua::new();
    let teal = compile_teal(&lua, &root, &files, &out);
    if std::env::var("HOST").ok().as_deref() != Some(target) {
        files.clear();
    }
    let dir = out.join("bytecode");
    std::fs::create_dir_all(&dir).expect("bytecode directory");
    let mut code = String::from("pub static BYTECODE: &[(&str, &[u8])] = &[\n");
    for (i, rel) in files.iter().enumerate() {
        let source = match teal.iter().find(|(path, _)| path == rel) {
            Some((_, lua)) => lua.clone().into_bytes(),
            None => std::fs::read(root.join(rel)).expect("a runtime file"),
        };
        // A module that does not compile is left as source: loading it
        // gives the same error, with the same message, as before.
        let Ok(func) = lua
            .load(&source[..])
            .set_name(format!("@runtime/lua/{rel}"))
            .into_function()
        else {
            continue;
        };
        let file = dir.join(format!("{i}.luac"));
        std::fs::write(&file, func.dump(false)).expect("writing bytecode");
        writeln!(code, "    ({rel:?}, include_bytes!({:?})),", file.display().to_string()).unwrap();
    }
    code.push_str("];\n");
    code.push_str("pub static TEAL: &[(&str, &str)] = &[\n");
    for (rel, _) in &teal {
        let file = out.join("teal").join(rel.replace('/', "_")).with_extension("lua");
        writeln!(code, "    ({rel:?}, include_str!({:?})),", file.display().to_string()).unwrap();
    }
    code.push_str("];\n");
    std::fs::write(out.join("bytecode.rs"), code).expect("writing bytecode.rs");
}

/// The Lua of each Teal module among `files`, by its path, written to
/// `$OUT_DIR/teal` as well. A module that does not parse is left out: the
/// program then says so when the module is required.
fn compile_teal(lua: &mlua::Lua, root: &Path, files: &[String], out: &Path) -> Vec<(String, String)> {
    let modules: Vec<&String> = files.iter().filter(|f| f.ends_with(".tl")).collect();
    if modules.is_empty() {
        return Vec::new();
    }
    let source = std::fs::read(root.join("tl.lua")).expect("runtime/lua/tl.lua, the Teal compiler");
    let tl: mlua::Table = lua
        .load(&source[..])
        .set_name("@runtime/lua/tl.lua")
        .call(())
        .expect("the Teal compiler loads");
    let parse: mlua::Function = tl.get("parse").unwrap();
    let generate: mlua::Function = tl.get("generate").unwrap();
    let dir = out.join("teal");
    std::fs::create_dir_all(&dir).expect("teal directory");
    let mut done = Vec::new();
    for rel in modules {
        let text = std::fs::read_to_string(root.join(rel)).expect("a Teal module");
        let (ast, errors): (mlua::Value, mlua::Table) =
            parse.call((text, format!("runtime/lua/{rel}"))).expect("parsing Teal");
        if errors.raw_len() > 0 {
            println!("cargo:warning=runtime/lua/{rel} does not parse as Teal");
            continue;
        }
        let code: String = generate.call((ast, "5.1")).expect("generating Lua from Teal");
        std::fs::write(dir.join(rel.replace('/', "_")).with_extension("lua"), &code).expect("writing Lua");
        done.push((rel.clone(), code));
    }
    done
}

/// The `.lua` files under `dir`, as paths relative to `root` with `/`.
fn collect(root: &Path, dir: &Path, files: &mut Vec<String>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect(root, &path, files);
        } else if path.extension().is_some_and(|e| e == "lua" || e == "tl")
            && let Ok(rel) = path.strip_prefix(root)
        {
            files.push(rel.to_string_lossy().replace('\\', "/"));
        }
    }
}
