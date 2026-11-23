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
//! starts. The compiler checks the types first, as `tl gen` does, with the
//! declarations in `runtime/types` (tlconfig.lua): in some places the Lua
//! depends on the types (`x is F`, where `F` names a function type, tests
//! for a function). A type error fails the build.
//!
//! The declarations are in the program too (`DECLARATIONS`), with a hash of
//! what a check of a Teal file reads from the runtime (`TEAL_TYPES`): the
//! loader checks the types of an extension in Teal with them.

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
    let types = root.join("../types");
    println!("cargo:rerun-if-changed={}", root.display());
    println!("cargo:rerun-if-changed={}", types.display());
    let mut files = Vec::new();
    collect(&root, &root, &mut files);
    files.sort();
    let lua = mlua::Lua::new();
    let teal = compile_teal(&lua, &root, &types, &files, &out);
    if std::env::var("HOST").ok().as_deref() != Some(target) {
        files.clear();
    }
    let dir = out.join("bytecode");
    std::fs::create_dir_all(&dir).expect("bytecode directory");
    let mut code = String::from("pub(crate) static BYTECODE: &[(&str, &[u8])] = &[\n");
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
    code.push_str("pub(crate) static TEAL: &[(&str, &str)] = &[\n");
    for (rel, _) in &teal {
        let file = out.join("teal").join(rel.replace('/', "_")).with_extension("lua");
        writeln!(code, "    ({rel:?}, include_str!({:?})),", file.display().to_string()).unwrap();
    }
    code.push_str("];\n");
    // The declarations, and the hash of them and of the Teal modules.
    let mut declarations = Vec::new();
    collect(&types, &types, &mut declarations);
    declarations.retain(|f| f.ends_with(".d.tl"));
    declarations.sort();
    let mut hash = Fnv::default();
    code.push_str("pub(crate) static DECLARATIONS: &[(&str, &str)] = &[\n");
    for rel in &declarations {
        let file = types.join(rel);
        hash.add(rel.as_bytes());
        hash.add(&std::fs::read(&file).expect("a declaration file"));
        writeln!(code, "    ({rel:?}, include_str!({:?})),", file.display().to_string()).unwrap();
    }
    code.push_str("];\n");
    for rel in files.iter().filter(|f| f.ends_with(".tl")) {
        hash.add(rel.as_bytes());
        hash.add(&std::fs::read(root.join(rel)).expect("a Teal module"));
    }
    writeln!(code, "pub(crate) static TEAL_TYPES: &str = \"{:016x}\";", hash.0).unwrap();
    std::fs::write(out.join("bytecode.rs"), code).expect("writing bytecode.rs");
}

/// The Lua of each Teal module among `files`, by its path, written to
/// `$OUT_DIR/teal` as well. Each module is checked first, in one
/// environment with the configuration of tlconfig.lua: the declarations in
/// `types`, the global `paw` (`paw.d.tl`), and the modules found by name in
/// `root`. The build stops at an error, with the file, line and message of
/// each.
fn compile_teal(lua: &mlua::Lua, root: &Path, types: &Path, files: &[String], out: &Path) -> Vec<(String, String)> {
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
    let (root_s, types_s) = (root.display().to_string(), types.display().to_string());
    tl.set("path", format!("{types_s}/?.lua;{types_s}/?/init.lua;{root_s}/?.lua;{root_s}/?/init.lua")).unwrap();
    // As paw.lang.check makes it, from tlconfig.lua.
    let env: mlua::Table = lua
        .load(
            r#"local tl = ...
            return assert(tl.new_env({
              defaults = { feat_lax = "off", feat_arity = "on", gen_target = "5.1", gen_compat = "off" },
              predefined_modules = { "paw" },
            }))"#,
        )
        .call(&tl)
        .unwrap_or_else(|e| panic!("the Teal declarations (runtime/types/paw.d.tl) do not load: {e}"));
    let check_file: mlua::Function = tl.get("check_file").unwrap();
    let generate: mlua::Function = tl.get("generate").unwrap();
    let mut results = Vec::new();
    for rel in &modules {
        let result: mlua::Table = check_file
            .call((format!("{root_s}/{rel}"), &env))
            .unwrap_or_else(|e| panic!("checking runtime/lua/{rel}: {e}"));
        results.push(result);
    }
    // Each file the check read (the modules, and the declarations they
    // require), with its errors, said as `tl check` says them.
    let mut errors = Vec::new();
    let loaded: mlua::Table = env.get("loaded").unwrap();
    for pair in loaded.pairs::<String, mlua::Table>() {
        let (file, result) = pair.unwrap();
        let file = file.replace(&root_s, "runtime/lua").replace(&types_s, "runtime/types");
        for list in ["syntax_errors", "type_errors"] {
            let Ok(list) = result.get::<mlua::Table>(list) else { continue };
            for e in list.sequence_values::<mlua::Table>() {
                let e = e.unwrap();
                let (y, x, msg): (i64, i64, String) = (e.get("y").unwrap(), e.get("x").unwrap(), e.get("msg").unwrap());
                errors.push(format!("{file}:{y}:{x}: {msg}"));
            }
        }
    }
    if !errors.is_empty() {
        errors.sort();
        panic!("the runtime's Teal has errors (tools/tlcheck.sh says the same):\n{}", errors.join("\n"));
    }
    let dir = out.join("teal");
    std::fs::create_dir_all(&dir).expect("teal directory");
    let mut done = Vec::new();
    for (rel, result) in modules.into_iter().zip(results) {
        let ast: mlua::Value = result.get("ast").unwrap();
        let code: String = generate.call((ast, "5.1")).expect("generating Lua from Teal");
        std::fs::write(dir.join(rel.replace('/', "_")).with_extension("lua"), &code).expect("writing Lua");
        done.push((rel.clone(), code));
    }
    done
}

/// FNV-1a, 64 bits: a hash that is the same on each build of the same files.
struct Fnv(u64);

impl Default for Fnv {
    fn default() -> Self {
        Fnv(0xcbf2_9ce4_8422_2325)
    }
}

impl Fnv {
    fn add(&mut self, bytes: &[u8]) {
        for b in bytes {
            self.0 = (self.0 ^ u64::from(*b)).wrapping_mul(0x0100_0000_01b3);
        }
        // The end of a part, so that "ab" + "c" is not "a" + "bc".
        self.0 = (self.0 ^ 0xff).wrapping_mul(0x0100_0000_01b3);
    }
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
