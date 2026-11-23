//! MCP resources: the manual's pages (`paw://help/<page>`, read from the
//! kernel, which knows where its docs are) and the API reference made from the
//! source (`paw://reference/...`), so that an agent reads the docs itself.

use serde_json::{Value, json};

use crate::format::items;
use crate::reference;
use crate::tools::{ToolError, Tools};

const HELP: &str = "paw://help/";
const LUA: &str = "paw://reference/lua/";

fn entry(uri: &str, name: &str, description: &str) -> Value {
    json!({ "uri": uri, "name": name, "description": description, "mimeType": "text/markdown" })
}

impl Tools {
    /// Every resource there is. The manual's pages are asked of the kernel;
    /// without one the references are still listed.
    pub(crate) fn resources_list(&mut self) -> Vec<Value> {
        let mut out = vec![
            entry(
                "paw://reference/api",
                "paw.api reference",
                "Every kernel function (paw.api.*, and `paw ctl <name>`), with its arguments and what it does",
            ),
            entry(
                "paw://reference/lua",
                "Lua modules index",
                "The modules of paw's Lua runtime; read one as paw://reference/lua/<module>",
            ),
        ];
        if let Ok(r) = self.lua("help_pages", json!({})) {
            for p in items(&r["pages"]) {
                let name = p["name"].as_str().unwrap_or("");
                let group = p["group"].as_str().unwrap_or("manual");
                out.push(entry(
                    &format!("{HELP}{name}"),
                    name,
                    &format!("paw's help ({group}): the page `{name}`"),
                ));
            }
        }
        out
    }

    pub(crate) fn resource_templates(&self) -> Vec<Value> {
        vec![
            json!({"uriTemplate": "paw://help/{page}", "name": "A page of paw's manual", "mimeType": "text/markdown"}),
            json!({"uriTemplate": "paw://reference/lua/{module}", "name": "A Lua module's documented functions", "mimeType": "text/markdown"}),
        ]
    }

    pub(crate) fn resource_read(&mut self, uri: &str) -> Result<Value, ToolError> {
        let text = if uri == "paw://reference/api" {
            reference::api()
        } else if uri == "paw://reference/lua" {
            reference::lua_index()
        } else if let Some(module) = uri.strip_prefix(LUA) {
            reference::lua_module(module)
                .ok_or_else(|| ToolError(format!("no Lua module `{module}`; paw://reference/lua lists them")))?
        } else if let Some(page) = uri.strip_prefix(HELP) {
            let r = self.lua("help_page", json!({ "name": page }))?;
            r["text"].as_str().unwrap_or("").to_string()
        } else {
            return Err(ToolError(format!("no resource `{uri}`")));
        };
        Ok(json!({ "contents": [{ "uri": uri, "mimeType": "text/markdown", "text": text }] }))
    }
}
