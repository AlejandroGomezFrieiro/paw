//! A device and its parameters as `paw.api.device_get` gives them: typed
//! views over the model and the running instance, with their JSON Schema.

use std::collections::BTreeMap;

use paw_engine::{DeviceInfo, ParamInfo, Ports};
use serde::Serialize;
use serde_json::{Map, Value};

use crate::model::Id;

/// A parameter of a device, as `param_info` lists it.
#[derive(Serialize, schemars::JsonSchema)]
#[schemars(rename = "ParamInfo")]
pub(crate) struct ParamView<'a> {
    /// The key that scripts and lanes name it by.
    key: &'a str,
    /// The device's own id for it, or its key.
    id: &'a str,
    name: &'a str,
    group: &'a str,
    min: f32,
    max: f32,
    default: f32,
    unit: &'a str,
    /// The names of its steps, for a parameter of named steps.
    choices: &'a [String],
    #[schemars(with = "String", extend("x-teal" = "ParamKind"))]
    kind: &'static str,
    /// The number of its steps; 0 for a continuous one.
    steps: u32,
    automatable: bool,
    read_only: bool,
    per_note: bool,
    /// Its place in the device's list, from 1.
    index: Option<usize>,
    /// A lane of the part moves it.
    automated: Option<bool>,
    /// Its value now (`device_param`).
    value: Option<f64>,
    /// Its value now as the device writes it (`device_param`).
    text: Option<String>,
}

impl<'a> ParamView<'a> {
    /// The description of `p`, with no place, lane or value.
    pub(super) fn of(p: &'a ParamInfo) -> Self {
        ParamView {
            key: &p.key,
            id: p.stable_id(),
            name: &p.name,
            group: &p.group,
            min: p.min,
            max: p.max,
            default: p.default,
            unit: &p.unit,
            choices: &p.choices,
            kind: p.kind(),
            steps: p.steps,
            automatable: p.automatable,
            read_only: p.read_only,
            per_note: p.per_note,
            index: None,
            automated: None,
            value: None,
            text: None,
        }
    }

    /// The description, with its place in the device's list (from 0) and
    /// whether a lane moves it.
    pub(super) fn at(p: &'a ParamInfo, index: usize, automated: bool) -> Self {
        ParamView { index: Some(index + 1), automated: Some(automated), ..Self::of(p) }
    }

    /// The description, with its value now and that value as text.
    pub(super) fn with_value(self, value: f64, text: String) -> Self {
        ParamView { value: Some(value), text: Some(text), ..self }
    }
}

/// A device on a part.
#[derive(Serialize, schemars::JsonSchema)]
#[schemars(rename = "Device")]
pub(crate) struct DeviceView<'a> {
    /// Who made it and which it is, as its format names it; nil for a
    /// device of paw.
    pub(super) plugin: Option<DevicePlugin<'a>>,
    pub(super) id: Id,
    pub(super) kind: &'a str,
    pub(super) name: &'a str,
    pub(super) offline: bool,
    pub(super) format: &'a str,
    pub(super) part: Id,
    /// Its place in the chain of its part, from 1.
    pub(super) index: usize,
    pub(super) bypass: bool,
    /// The value now of each parameter, by key.
    pub(super) params: BTreeMap<&'a str, f64>,
    /// The parameters that the project sets, over what the plugin's state
    /// says.
    pub(super) overrides: &'a BTreeMap<String, f64>,
    pub(super) param_info: Vec<ParamView<'a>>,
    #[schemars(extend("x-teal" = "Meta"))]
    pub(super) meta: &'a Map<String, Value>,
    /// Whether its own window shows; nil for a device with no window.
    pub(super) editor: Option<EditorState>,
    /// Not running: not installed, not made yet, or made and gone.
    pub(super) missing: bool,
    /// Why the device has stopped working, for a plugin that crashed, hung
    /// or could not be made.
    pub(super) stopped: Option<String>,
    pub(super) status: DeviceStatus,
    /// The part it listens to.
    pub(super) sidechain: Option<Id>,
    pub(super) sidechain_pre: bool,
    /// The part that each further output pair plays into, by the pair's
    /// number as text.
    pub(super) outputs: PairOutputs<'a>,
    pub(super) ports: DevicePorts,
}

impl<'a> DeviceView<'a> {
    /// The value now of the parameter `key`.
    pub(crate) fn param(&self, key: &str) -> Option<f64> {
        self.params.get(key).copied()
    }

    /// The description of the parameter `key`, as `param_info` lists it.
    pub(super) fn into_param(self, key: &str) -> Option<ParamView<'a>> {
        self.param_info.into_iter().find(|p| p.key == key)
    }
}

/// A parameter's value now, as `paw.api.device_param` reads it.
pub(crate) struct ParamNow {
    pub(super) key: String,
    pub(crate) value: f64,
    pub(super) text: String,
}

/// Who made a plugin and which it is.
#[derive(Serialize, schemars::JsonSchema)]
pub(crate) struct DevicePlugin<'a> {
    format: &'a str,
    id: &'a str,
    name: &'a str,
    vendor: &'a str,
    version: &'a str,
}

impl<'a> DevicePlugin<'a> {
    /// The plugin of `info`; none for a device of paw (no id).
    pub(super) fn of(info: &'a DeviceInfo) -> Option<Self> {
        (!info.id.is_empty()).then(|| DevicePlugin {
            format: info.format.as_str(),
            id: &info.id,
            name: &info.name,
            vendor: &info.vendor,
            version: &info.version,
        })
    }
}

/// What a running device takes and gives besides its main pair.
#[derive(Serialize, schemars::JsonSchema)]
pub(crate) struct DevicePorts {
    /// It listens to a side-chain.
    sidechain: bool,
    /// The names of its output pairs, the main one first.
    outputs: Vec<String>,
}

impl From<Ports> for DevicePorts {
    fn from(ports: Ports) -> Self {
        DevicePorts { sidechain: ports.sidechain, outputs: ports.outputs }
    }
}

/// Whether a device's own window shows.
#[derive(Clone, Copy, Serialize, schemars::JsonSchema)]
#[serde(rename_all = "lowercase")]
pub(crate) enum EditorState {
    Open,
    Closed,
}

/// Whether a device runs, and why not.
#[derive(Clone, Copy, Serialize, schemars::JsonSchema)]
#[serde(rename_all = "lowercase")]
pub(crate) enum DeviceStatus {
    Running,
    /// Being made apart (session/loading.rs).
    Loading,
    Stopped,
    /// Set so: not made at all.
    Offline,
    /// Not installed.
    Missing,
}

/// The output pairs of a device by number, written with the numbers as
/// text: a Lua table keyed by numbers from 2 up reads as a list with holes.
pub(crate) struct PairOutputs<'a>(pub(super) &'a BTreeMap<u32, Id>);

impl Serialize for PairOutputs<'_> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.collect_map(self.0.iter().map(|(pair, to)| (pair.to_string(), to)))
    }
}

impl schemars::JsonSchema for PairOutputs<'_> {
    fn inline_schema() -> bool {
        true
    }

    fn schema_name() -> std::borrow::Cow<'static, str> {
        "PairOutputs".into()
    }

    fn json_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
        BTreeMap::<String, Id>::json_schema(generator)
    }
}
