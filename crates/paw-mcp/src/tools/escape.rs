//! The escape hatches: code of the model's choosing, offered only with
//! `--allow-eval`.

use std::fmt::Write as _;

use serde_json::{Value, json};

use super::{Args, Effect, Outcome, Run, Tool, Tools};
use crate::music::Meter;
use crate::schema::obj;

pub(super) fn tools() -> Vec<Tool> {
    vec![
        Tool {
            name: "lua",
            title: "Escape hatch: run Lua in paw",
            description: "ESCAPE HATCH: run Lua inside paw with the whole `paw` scripting interface (paw.tracks(), paw.project, paw.api.*, ...) and return what it returns, as text. Read the manual and the API reference as resources (paw://reference/api, paw://reference/lua/<module>) first. An expression is returned as is (`paw.project.tempo`); statements need `return`. This is arbitrary code in paw's process, with its file and network access, which the typed tools' checks do not cover: a client should ask the person before running it. Only offered with --allow-eval. One undo step; not rolled back on failure.".into(),
            schema: obj(json!({"code": {"type": "string", "description": "Lua code"}}), &["code"]),
            effect: Effect::Destroys,
            run: Run::Escape(Tools::lua_code),
        },
        Tool {
            name: "run_command",
            title: "Escape hatch: run a paw command",
            description: "ESCAPE HATCH, for what the typed tools do not cover: run a command line as typed after `:` in paw, such as `track.add Bass device=synth`, `tempo 96`, `commands` or `lua <code>`. Commands act on paw's cursor and selection. Returns the command's result and any messages it showed. One undo step; not rolled back on failure. It can run Lua and write files: a client should ask the person first. Only offered with --allow-eval.".into(),
            schema: obj(json!({"line": {"type": "string", "description": "The command line, without the leading `:`"}}), &["line"]),
            effect: Effect::Destroys,
            run: Run::Escape(Tools::run_command),
        },
        Tool {
            name: "send_keys",
            title: "Escape hatch: type keys",
            description: "ESCAPE HATCH: type keys into paw as a person would, in Neovim notation (`ggdd`, `<Space>`, `<C-r>`, `:tempo 90<CR>`). Acts on the focused view and the cursor; the result gives the mode and focus afterwards, and any messages. One undo step per call. A client should ask the person first. Only offered with --allow-eval.".into(),
            schema: obj(json!({"keys": {"type": "string", "description": "Keys in Neovim notation"}}), &["keys"]),
            effect: Effect::Destroys,
            run: Run::Escape(Tools::send_keys),
        },
    ]
}

impl Tools {
    fn lua_code(&mut self, a: &Args) -> Outcome {
        self.escape("lua", json!({ "code": a["code"] }))
    }

    fn run_command(&mut self, a: &Args) -> Outcome {
        self.escape("command", json!({ "line": a["line"] }))
    }

    fn send_keys(&mut self, a: &Args) -> Outcome {
        self.escape("keys", json!({ "keys": a["keys"] }))
    }

    fn escape(&mut self, tool: &str, args: Value) -> Outcome {
        let r = self.lua(tool, args)?;
        let mut out = String::new();
        match tool {
            "keys" => {
                let _ = writeln!(
                    out,
                    "Typed. Mode {}, focus {}{}",
                    r["mode"].as_str().unwrap_or("?"),
                    r["focused"].as_str().unwrap_or("?"),
                    r["pending"]
                        .as_str()
                        .filter(|p| !p.is_empty())
                        .map(|p| format!(", waiting for more after `{p}`"))
                        .unwrap_or_default()
                );
            }
            _ => match r["result"].as_str() {
                Some(text) if !text.is_empty() => {
                    let _ = writeln!(out, "{text}");
                }
                _ => out.push_str("Done (no result).\n"),
            },
        }
        if r["edited"].as_bool() == Some(true) {
            out.push_str("(the project changed: one undo step)\n");
        }
        Ok(Self::reply(out, &r, Meter::default()))
    }
}
