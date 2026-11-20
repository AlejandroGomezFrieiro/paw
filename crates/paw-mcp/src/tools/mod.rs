//! The tools: what each does. Arguments are checked against the tool's own
//! schema first (`check.rs`), then normalized here (note names, positions,
//! paths) and handed to the kernel side in `mcp.lua` as one call, so each tool
//! call is one kernel turn and, when it writes, one undo step. The answer is
//! given as text for a person or a model that reads prose, and as
//! `structuredContent` for a program.
//!
//! Each tool is one entry of [`table`]: its name, description and schema
//! together with its code. The entries live by area: [`read`], [`write`],
//! [`session`], [`listen`] and [`escape`].

mod escape;
mod listen;
mod read;
mod session;
mod write;

use std::path::{Component, Path, PathBuf};
use std::sync::LazyLock;

use serde_json::{Map, Value, json};

use crate::check::validate;
use crate::format::{self, items};
use crate::kernel::{CallError, Kernel};
use crate::music::{self, Meter};

const LUA: &str = include_str!("mcp.lua");

/// What the server lets a model do beyond the typed tools.
#[derive(Clone, Debug, Default)]
pub struct Policy {
    /// Offer `lua`, `run_command` and `send_keys`.
    pub allow_eval: bool,
    /// Let file-writing tools write anywhere, not only under `root`.
    pub allow_any_path: bool,
    /// Where relative paths start, and the only place files are written to
    /// unless `allow_any_path`.
    pub root: PathBuf,
}

pub struct Tools {
    pub kernel: Kernel,
    pub policy: Policy,
}

/// A failed tool call: the text the model gets back with `isError`.
#[derive(Debug)]
pub struct ToolError(pub String);

impl From<CallError> for ToolError {
    fn from(err: CallError) -> Self {
        ToolError(err.to_string())
    }
}

impl From<anyhow::Error> for ToolError {
    fn from(err: anyhow::Error) -> Self {
        ToolError(format!("{err:#}"))
    }
}

/// What a tool answers: prose, and the same as JSON.
pub struct Reply {
    pub text: String,
    pub data: Value,
}

pub type Outcome = Result<Reply, ToolError>;

fn err<T>(msg: impl Into<String>) -> Result<T, ToolError> {
    Err(ToolError(msg.into()))
}

/// Lists that Lua may hand over as an empty table, which is not an array
/// until it is made one.
const LISTS: [&str; 24] = [
    "tracks", "clips", "devices", "lanes", "sends", "notes", "markers", "params", "messages",
    "results", "findings", "published", "history", "redoable", "steps", "found", "param_info",
    "points", "removed", "skipped", "stems", "keys_used", "choices", "tempo_changes",
];

/// The data a result carries for a program: empty lists as lists, and where
/// there is a position or a pitch, how a musician writes it.
fn enrich(value: &mut Value, meter: Meter) {
    match value {
        Value::Array(list) => list.iter_mut().for_each(|v| enrich(v, meter)),
        Value::Object(map) => {
            for key in LISTS {
                if map.get(key).is_some_and(|v| v.as_object().is_some_and(Map::is_empty)) {
                    map.insert(key.into(), json!([]));
                }
            }
            let start = map.get("start").and_then(Value::as_f64);
            if let (Some(pitch), Some(start)) = (map.get("pitch").and_then(Value::as_u64), start)
                && map.contains_key("length")
            {
                map.insert("name".into(), json!(music::name(pitch.min(127) as u8)));
                map.insert("at".into(), json!(meter.format(start)));
            } else if matches!(map.get("kind").and_then(Value::as_str), Some("midi" | "audio"))
                && let Some(start) = start
            {
                map.insert("at".into(), json!(meter.format(start)));
            } else if map.contains_key("region")
                && let Some(beat) = map.get("beat").and_then(Value::as_f64)
            {
                map.insert("at".into(), json!(meter.format(beat)));
            }
            map.values_mut().for_each(|v| enrich(v, meter));
        }
        _ => {}
    }
}

/// The name of the undo step a call makes: `mcp: add_track Bass`.
fn undo_label(name: &str, a: &Map<String, Value>) -> String {
    let subject = ["name", "track", "clip", "device", "marker"]
        .iter()
        .find_map(|key| match a.get(*key) {
            Some(Value::String(s)) => Some(s.clone()),
            Some(Value::Number(n)) => Some(n.to_string()),
            _ => None,
        });
    match subject {
        Some(s) => format!("mcp: {name} {}", s.chars().take(40).collect::<String>()),
        None => format!("mcp: {name}"),
    }
}

fn as_map(value: &Value) -> Map<String, Value> {
    value.as_object().cloned().unwrap_or_default()
}

/// A tool's arguments: a JSON object.
pub type Args = Map<String, Value>;

/// What a tool does to the project, as clients are told in its annotations.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Effect {
    /// Reads only; calling it again gives the same answer.
    Reads,
    /// Changes the project, or the transport.
    Changes,
    /// May remove or replace what is there.
    Destroys,
}

/// Turns a writing tool's arguments into the kernel's units.
type Prepare = fn(&Tools, &Args, Meter) -> Result<Args, ToolError>;

/// How a tool runs.
pub enum Run {
    /// Its own code.
    Call(fn(&mut Tools, &Args) -> Outcome),
    /// A change a `batch` can run too: its arguments in the kernel's units
    /// (as they are when there is no `prepare`), then the kernel side's
    /// tool of the same name as one undo step, then its answer as text.
    Write { prepare: Option<Prepare>, show: fn(&Value, Meter) -> String },
    /// Code of the model's choosing: offered only with `--allow-eval`.
    Escape(fn(&mut Tools, &Args) -> Outcome),
}

/// One tool: what a model sees of it, and its code.
pub struct Tool {
    pub name: &'static str,
    pub title: &'static str,
    pub description: String,
    /// Its input schema (see `schema.rs` for the subset it keeps to).
    pub schema: Value,
    pub effect: Effect,
    pub run: Run,
}

impl Tool {
    pub fn is_escape(&self) -> bool {
        matches!(self.run, Run::Escape(_))
    }

    pub fn is_write(&self) -> bool {
        matches!(self.run, Run::Write { .. })
    }

    /// The tool as `tools/list` gives it.
    pub fn to_mcp(&self) -> rmcp::model::Tool {
        let schema = match &self.schema {
            Value::Object(map) => map.clone(),
            _ => Map::new(),
        };
        let reads = self.effect == Effect::Reads;
        let annotations = rmcp::model::ToolAnnotations::with_title(self.title)
            .read_only(reads)
            .destructive(self.effect == Effect::Destroys)
            .idempotent(reads)
            .open_world(self.is_escape());
        rmcp::model::Tool::new(self.name, self.description.clone(), schema)
            .with_title(self.title)
            .with_annotations(annotations)
    }
}

/// Every tool, in the order `tools/list` gives them.
pub fn table() -> &'static [Tool] {
    static TABLE: LazyLock<Vec<Tool>> = LazyLock::new(|| {
        [read::tools(), write::tools(), session::tools(), listen::tools(), escape::tools()]
            .into_iter()
            .flatten()
            .collect()
    });
    &TABLE
}

fn find(name: &str) -> Option<&'static Tool> {
    table().iter().find(|t| t.name == name)
}

impl Tools {
    /// The tools this server offers.
    pub fn list(&self) -> Vec<rmcp::model::Tool> {
        self.offered().map(Tool::to_mcp).collect()
    }

    fn offered(&self) -> impl Iterator<Item = &'static Tool> {
        let allow_eval = self.policy.allow_eval;
        table().iter().filter(move |t| allow_eval || !t.is_escape())
    }

    pub fn call(&mut self, name: &str, args: &Value) -> Outcome {
        let Some(tool) = find(name) else {
            let names: Vec<&str> = self.offered().map(|t| t.name).collect();
            return err(format!(
                "unknown tool `{name}`; the tools are: {}",
                names.join(", ")
            ));
        };
        if tool.is_escape() && !self.policy.allow_eval {
            return err(format!(
                "`{name}` is an escape hatch that runs arbitrary code in paw, and this server was started without --allow-eval. Use the typed tools, or ask the user to restart the server with --allow-eval."
            ));
        }
        let args = match args {
            Value::Object(map) => map.clone(),
            Value::Null => Map::new(),
            _ => return err("arguments must be an object"),
        };
        validate(&tool.schema, &args)?;
        let notice = self.kernel.notice.take();
        let mut reply = match &tool.run {
            Run::Call(run) | Run::Escape(run) => run(self, &args),
            Run::Write { .. } => self.write(tool, &args),
        };
        // A kernel restarted under us is news whether the call worked or not.
        if let Some(notice) = notice.or_else(|| self.kernel.notice.take()) {
            match &mut reply {
                Ok(Reply { text, data }) => {
                    *text = format!("NOTE: {notice}\n{text}");
                    data["notice"] = json!(notice);
                }
                Err(ToolError(text)) => *text = format!("NOTE: {notice}\n{text}"),
            }
        }
        reply
    }

    /// A writing tool's arguments in the kernel's units.
    fn prepare(&self, tool: &Tool, a: &Args, meter: Meter) -> Result<Args, ToolError> {
        match tool.run {
            Run::Write { prepare: Some(prepare), .. } => prepare(self, a, meter),
            _ => Ok(a.clone()),
        }
    }

    /// The answer of a writing tool, as text and as data.
    fn show(tool: &Tool, r: &Value, meter: Meter) -> Reply {
        let text = match tool.run {
            Run::Write { show, .. } => show(r, meter),
            _ => String::new(),
        };
        Self::reply(text, r, meter)
    }

    /// A writing tool called alone: one undo step.
    fn write(&mut self, tool: &Tool, a: &Args) -> Outcome {
        let meter = self.meter()?;
        let args = self.prepare(tool, a, meter)?;
        let r = self.lua_as(tool.name, Value::Object(args), Some(&undo_label(tool.name, a)))?;
        Ok(Self::show(tool, &r, meter))
    }

    // --- plumbing ------------------------------------------------------------

    /// Run one tool of the kernel side.
    pub fn lua(&mut self, tool: &str, args: Value) -> Result<Value, ToolError> {
        self.lua_as(tool, args, None)
    }

    /// Run one tool of the kernel side, naming the undo step it makes.
    fn lua_as(&mut self, tool: &str, args: Value, label: Option<&str>) -> Result<Value, ToolError> {
        let mut params = vec![json!(tool), args];
        params.extend(label.map(|l| json!(l)));
        Ok(self.kernel.eval(LUA, params)?)
    }

    fn meter(&mut self) -> Result<Meter, ToolError> {
        Ok(Meter::from_project(
            &self.kernel.call("project_get", json!([]))?,
        ))
    }

    /// The text with what paw said while the call ran, and the data in the
    /// shape a program wants.
    fn reply(mut text: String, r: &Value, meter: Meter) -> Reply {
        format::messages(&mut text, &r["messages"]);
        let mut data = r.clone();
        enrich(&mut data, meter);
        Reply { text, data }
    }

    // --- paths ---------------------------------------------------------------

    /// A path to read from: relative ones start at the root.
    fn read_path(&self, raw: &str) -> PathBuf {
        normalize(&self.policy.root.join(raw))
    }

    /// A path to write to, refused outside the root unless allowed.
    fn write_path(&self, raw: &str) -> Result<PathBuf, ToolError> {
        if raw.trim().is_empty() {
            return err("the path is empty");
        }
        let path = self.read_path(raw);
        if self.policy.allow_any_path {
            return Ok(path);
        }
        let root = self
            .policy
            .root
            .canonicalize()
            .unwrap_or_else(|_| self.policy.root.clone());
        if !resolve_links(&path).starts_with(&root) {
            return err(format!(
                "refusing to write {}: it is outside the working directory {} (the server was not started with --allow-any-path). Use a relative path such as \"song.json\".",
                path.display(),
                root.display()
            ));
        }
        Ok(path)
    }

    /// [`write_path`](Self::write_path), with its directory made if needed.
    fn output_path(&self, raw: &str) -> Result<PathBuf, ToolError> {
        let path = self.write_path(raw)?;
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)
                .map_err(|e| ToolError(format!("creating {}: {e}", dir.display())))?;
        }
        Ok(path)
    }
}

/// Remove `.` and `..` without touching the file system.
fn normalize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for part in path.components() {
        match part {
            Component::ParentDir => {
                out.pop();
            }
            Component::CurDir => {}
            other => out.push(other),
        }
    }
    out
}

/// The path with every symbolic link in the part that exists resolved.
fn resolve_links(path: &Path) -> PathBuf {
    let mut rest = Vec::new();
    let mut base = path.to_path_buf();
    loop {
        if let Ok(real) = base.canonicalize() {
            let mut out = real;
            for part in rest.iter().rev() {
                out.push(part);
            }
            return out;
        }
        match (base.file_name(), base.parent()) {
            (Some(name), Some(parent)) => {
                rest.push(name.to_os_string());
                base = parent.to_path_buf();
            }
            _ => return path.to_path_buf(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::schema::BATCHABLE;

    #[test]
    fn arguments_are_checked() {
        let schema = &find("add_clip").unwrap().schema;
        let ok = json!({"track": "Bass", "start": "2.1", "notes": ["C4 0 1", {"pitch": "E4"}]});
        assert!(validate(schema, ok.as_object().unwrap()).is_ok());
        let typo = json!({"track": 1, "strat": 0});
        assert!(
            validate(schema, typo.as_object().unwrap())
                .unwrap_err()
                .0
                .contains("unknown argument `strat`")
        );
        let missing = json!({"start": 0});
        assert!(
            validate(schema, missing.as_object().unwrap())
                .unwrap_err()
                .0
                .contains("missing required argument `track`")
        );
        let wrong = json!({"track": 1, "notes": [{"pitch": "C4", "velocity": 300}]});
        assert!(
            validate(schema, wrong.as_object().unwrap())
                .unwrap_err()
                .0
                .contains("notes[0].velocity")
        );
    }

    #[test]
    fn paths_stay_inside_the_root() {
        let root = std::env::temp_dir().canonicalize().unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread().build().unwrap();
        let socket = "/nonexistent".into();
        let tools = Tools {
            kernel: Kernel::attach(socket, std::time::Duration::from_secs(1), runtime.handle().clone()),
            policy: Policy {
                root: root.clone(),
                ..Policy::default()
            },
        };
        assert_eq!(tools.write_path("a/b.wav").unwrap(), root.join("a/b.wav"));
        assert!(tools.write_path("../x.wav").is_err());
        assert!(tools.write_path("/etc/x.json").is_err());
        assert!(tools.write_path("a/../../x.wav").is_err());
    }

    /// Walk every schema: nothing that some clients read wrongly.
    fn walk(schema: &Value, at: &str) {
        match schema {
            Value::Object(map) => {
                assert!(
                    !matches!(map.get("type"), Some(Value::Array(_))),
                    "{at}: a list of types; use anyOf"
                );
                assert!(!map.contains_key("prefixItems"), "{at}: prefixItems");
                assert_ne!(map.get("items"), Some(&json!(false)), "{at}: items: false");
                for (key, value) in map {
                    walk(value, &format!("{at}.{key}"));
                }
            }
            Value::Array(list) => list.iter().enumerate().for_each(|(i, v)| walk(v, &format!("{at}[{i}]"))),
            _ => {}
        }
    }

    #[test]
    fn schemas_use_only_what_every_client_reads() {
        for t in table() {
            walk(&t.schema, t.name);
        }
        let find = |name: &str| &find(name).unwrap().schema;
        // The automation point is a pair whose items are numbers or strings.
        let points = &find("automate")["properties"]["points"]["items"];
        assert_eq!(points["type"], "array");
        assert_eq!(points["items"]["anyOf"][0]["type"], "number");
        // A pitch is a name or a MIDI number, never only an integer.
        let pitch = &find("add_clip")["properties"]["notes"]["items"]["anyOf"][1]["properties"]["pitch"];
        assert_eq!(pitch["anyOf"][0]["type"], "string");
        // A batch runs exactly the writing tools.
        let mut writes: Vec<&str> = table().iter().filter(|t| t.is_write()).map(|t| t.name).collect();
        let mut batchable = BATCHABLE.to_vec();
        writes.sort_unstable();
        batchable.sort_unstable();
        assert_eq!(writes, batchable);
    }

    #[test]
    fn data_names_what_a_musician_would() {
        let mut v = json!({
            "tracks": {},
            "clip": {"kind": "midi", "start": 8.0, "length": 4.0,
                     "notes": [{"id": 3, "pitch": 70, "start": 2.0, "length": 1.0, "velocity": 90}]},
            "marker": {"id": 1, "beat": 16.0, "region": true},
        });
        enrich(&mut v, Meter::default());
        assert_eq!(v["tracks"], json!([]));
        assert_eq!(v["clip"]["at"], "3.1");
        assert_eq!(v["clip"]["notes"][0]["name"], "A#4");
        assert_eq!(v["clip"]["notes"][0]["at"], "1.3");
        assert_eq!(v["marker"]["at"], "5.1");
    }

    #[test]
    fn an_undo_step_is_named_after_its_subject() {
        let a = json!({"name": "Bass", "volume": -3});
        assert_eq!(undo_label("add_track", a.as_object().unwrap()), "mcp: add_track Bass");
        let b = json!({"clip": 12});
        assert_eq!(undo_label("edit_clip", b.as_object().unwrap()), "mcp: edit_clip 12");
        assert_eq!(undo_label("set_project", &Map::new()), "mcp: set_project");
    }
}
