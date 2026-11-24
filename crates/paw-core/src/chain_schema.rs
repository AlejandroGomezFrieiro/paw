//! paw's schema for the chain language (`paw chain schema`): the kinds of
//! stream, the roles of a node of the part's graph, each kind of device
//! that the registry has (built-in, CLAP, VST3, LV2 and Lua), the kinds of
//! split of the model's registry (`model/chain/kinds.rs`), and the kinds of
//! modulator, as the generic crate `chain-syntax` reads them.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]
#![expect(clippy::float_cmp, reason = "debt: pay down")]

use chain_syntax::{Count, Kind, Param, ParamValue, Port, Schema, SplitKind, Stream, TimeBase, Unit};
use paw_engine::{Category, DeviceFormat, DeviceInfo, ParamInfo};

use crate::model::chain::{BuiltinSplit, KindSpec, SplitImpl, SplitKinds};

mod params;

use params::params_of;

/// The kinds that a host can lack, by their prefix: a plugin that is not
/// installed on this machine, or a Lua device of an extension that is not
/// loaded. The check gives a warning for one, not an error.
const OPEN_PREFIXES: [&str; 4] = ["clap:", "vst3:", "lv2:", "lua:"];

/// The schema of the kinds of device that `session` has now, as JSON: what
/// `paw chain schema` prints and `paw.api.chain_schema` gives.
pub(crate) fn json(session: &crate::session::Session) -> String {
    schema(session.registry.iter().map(|factory| factory.info()), session.doc.split_kinds()).to_json()
}

/// The schema of the kinds of device in `devices`, with paw's streams and
/// roles of a node, the kinds of split of `kinds`, and paw's kinds of
/// modulator.
pub(crate) fn schema<'a>(devices: impl IntoIterator<Item = &'a DeviceInfo>, kinds: &SplitKinds) -> Schema {
    let mut schema = Schema::new("paw");
    schema.streams = streams();
    schema.default_ports = vec![port("in", "audio", false), port("out", "audio", true)];
    schema.nodes = nodes();
    schema.devices = devices.into_iter().map(device).collect();
    schema.splits = splits(kinds);
    schema.modulators = modulators();
    schema.open_prefixes = OPEN_PREFIXES.map(String::from).to_vec();
    schema
}

fn device(info: &DeviceInfo) -> Kind {
    Kind {
        kind: info.kind.clone(),
        name: info.name.clone(),
        // A value that the device only shows is not a field of the text.
        params: info.params.iter().filter(|param| !param.read_only).map(param).collect(),
        // A plugin with no parameters in its description has them only
        // for each instance (`DeviceInfo::params`).
        open_params: info.params.is_empty() && info.format != DeviceFormat::Builtin,
        // An instrument plays the notes that come in; an effect has the
        // default ports, audio in and out.
        ports: (info.category == Category::Instrument).then(|| vec![port("notes", "midi", false), port("out", "audio", true)]),
        ..Kind::default()
    }
}

/// A main port of `stream`: an output when `out`.
fn port(name: &str, stream: &str, out: bool) -> Port {
    Port { port: name.into(), stream: stream.into(), props: Default::default(), main: true, out }
}

/// The kinds of stream that a lane of paw keeps and a wire carries.
fn streams() -> Vec<Stream> {
    let stream = |stream: &str, name: &str, time: TimeBase, control: bool| Stream {
        stream: stream.into(),
        name: name.into(),
        time: Some(time),
        records: true,
        control,
        props: Vec::new(),
    };
    vec![
        stream("audio", "Audio", TimeBase::Samples, false),
        stream("midi", "MIDI", TimeBase::Beats, false),
        stream("curve", "Curve", TimeBase::Beats, true),
    ]
}

/// The roles of a node line, with the parameters and ports of each. A
/// strip takes notes for the instrument among its inserts, and audio.
fn nodes() -> Vec<Kind> {
    let fader = params_of::<params::Fader>;
    let role = |kind: &str, params: Vec<Param>, ports: Option<Vec<Port>>| Kind { kind: kind.into(), params, ports, ..Kind::default() };
    let strip_ports = vec![port("in", "audio", false), port("notes", "midi", false), port("out", "audio", true)];
    vec![
        role("strip", fader(), Some(strip_ports)),
        role("bus", fader(), None),
        role("master", fader(), None),
        role("send", params_of::<params::SendParams>(), None),
        role("vca", params_of::<params::Vca>(), Some(vec![port("out", "curve", true)])),
    ]
}

fn param(info: &ParamInfo) -> Param {
    let (min, max, default) = (exact(info.min), exact(info.max), exact(info.default));
    let unit = unit(&info.unit);
    let value = if info.boolean {
        ParamValue::Switch { default: Some(default > min) }
    } else if !info.choices.is_empty() {
        // The default is the number of its step from `min`.
        let step = (default - min).round().max(0.0) as usize;
        ParamValue::Choice { choices: info.choices.clone(), default: info.choices.get(step).cloned() }
    } else {
        let whole = info.steps > 0 && f64::from(info.steps) == max - min;
        ParamValue::Number { unit, min: Some(min), max: Some(max), default: Some(default), integer: whole }
    };
    // A unit of paw that the language has not (`°`, `:1`, `x`) stays as a label.
    let label = if unit.is_none() && !info.boolean && info.choices.is_empty() { info.unit.clone() } else { String::new() };
    Param { key: info.key.clone(), name: info.name.clone(), label, description: String::new(), value }
}

/// The unit of the language for a unit as paw's devices write it.
fn unit(text: &str) -> Option<Unit> {
    match text.trim() {
        "st" | "semitones" => Some(Unit::Semitone),
        other => Unit::from_suffix(other),
    }
}

/// An `f32` of a device as the `f64` of its shortest decimal: 0.1 stays
/// 0.1, not 0.100000001490116.
fn exact(value: f32) -> f64 {
    format!("{value}").parse().unwrap_or(f64::from(value))
}

/// The kinds of split of `kinds`: the built-in kinds in their order, then
/// the kinds that extensions defined. Each split has a dry and wet `mix`
/// and an output `gain`, and each branch a gain, a pan, a mute and a solo.
/// The text names the kind `chain` (one branch in series) `rack`, as the
/// header of a document is `chain`.
fn splits(kinds: &SplitKinds) -> Vec<SplitKind> {
    let builtin = BuiltinSplit::ALL.into_iter().filter(|b| kinds.get(&b.kind()) == Some(&SplitImpl::Builtin(*b)));
    let declared = kinds.iter().filter_map(|(kind, found)| match found {
        SplitImpl::Declared(spec) => Some(split(kind.as_str(), "", *spec)),
        SplitImpl::Builtin(_) => None,
    });
    builtin.map(builtin_split).chain(declared).collect()
}

/// A split kind of the language with the parameters that each split has.
fn split(kind: &str, name: &str, spec: KindSpec) -> SplitKind {
    SplitKind {
        kind: kind.into(),
        name: name.into(),
        branches: Count { min: spec.min, max: spec.max },
        params: params_of::<params::Split>(),
        branch_params: params_of::<params::Branch>(),
    }
}

/// A built-in kind of split, with its own parameters.
fn builtin_split(builtin: BuiltinSplit) -> SplitKind {
    let spec = builtin.spec();
    match builtin {
        BuiltinSplit::Chain => split("rack", "Rack", spec),
        BuiltinSplit::Layer => split("layer", "Layer", spec),
        BuiltinSplit::Band => {
            let mut band = split("band", "Band split", spec);
            band.params.push(Param {
                key: "xover".into(),
                name: "Crossovers".into(),
                label: String::new(),
                description: String::new(),
                value: ParamValue::List {
                    unit: Some(Unit::Hertz),
                    min: Some(20.0),
                    max: Some(20000.0),
                    count: Some(Count { min: spec.min - 1, max: spec.max - 1 }),
                    ascending: true,
                },
            });
            band
        }
        BuiltinSplit::Ms => split("ms", "Mid and side", spec),
        BuiltinSplit::Lr => split("lr", "Left and right", spec),
        BuiltinSplit::Key | BuiltinSplit::Vel => {
            let name = if builtin == BuiltinSplit::Key { "Key split" } else { "Velocity split" };
            let mut zones = split(builtin.word(), name, spec);
            zones.branch_params.extend(params_of::<params::Zone>());
            zones
        }
        BuiltinSplit::Select => {
            let mut select = split("select", "Selector", spec);
            select.params.extend(params_of::<params::Select>());
            select
        }
        BuiltinSplit::Outs => split("outs", "Outputs of the device before", spec),
    }
}

/// The kinds of modulator of a chain.
fn modulators() -> Vec<Kind> {
    vec![
        Kind { kind: "macro".into(), name: "Macro".into(), params: params_of::<params::Macro>(), ..Kind::default() },
        Kind { kind: "lfo".into(), name: "LFO".into(), params: params_of::<params::Lfo>(), ..Kind::default() },
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kind_of<'a>(schema: &'a Schema, kind: &str) -> &'a Kind {
        schema.device(kind).unwrap_or_else(|| panic!("the schema has `{kind}`"))
    }

    #[test]
    fn the_schema_has_each_built_in_device_and_a_part_of_them_checks() {
        let registry = paw_engine::Registry::with_builtins();
        let schema = schema(registry.iter().map(|factory| factory.info()), &SplitKinds::builtin());
        assert_eq!(schema.devices.len(), registry.iter().count(), "one kind for each device");
        // The JSON that `paw chain schema` writes loads again as the same schema.
        let loaded = Schema::from_json(&schema.to_json()).expect("paw's schema loads");
        assert_eq!(loaded, schema);
        // An effect before the instrument passes the notes on to it.
        let text = "chain 2\nstrip #1 gain=-3dB\n  compressor #2\n  synth #3\n  layer #4\n    | Dry\n    | Wet gain=-6dB\n      clap:org.example.missing #5\nbus #6\nsend #7 level=-12dB\nvca #8\n#1 -> #6\n#1 -> #7\n#7 -> #6\n#8 -> #6.gain\n";
        let errors: Vec<String> = chain_syntax::check_text(text, &schema, None)
            .diagnostics
            .iter()
            .filter(|diagnostic| diagnostic.is_error())
            .map(ToString::to_string)
            .collect();
        assert_eq!(errors, Vec::<String>::new(), "paw's kinds check");
    }

    #[test]
    fn a_plugin_parameter_takes_the_type_and_the_unit_of_its_description() {
        let params = vec![
            ParamInfo { boolean: true, ..ParamInfo::new("Bypass").range(0.0, 1.0).default_value(1.0) },
            ParamInfo::choice("Mode", &["clean", "tube"], 1),
            ParamInfo::new("Drive").range(-12.0, 12.0).default_value(0.1).unit("dB"),
            ParamInfo { steps: 4, ..ParamInfo::new("Voices").range(1.0, 5.0).default_value(2.0) },
            ParamInfo::new("Angle").range(0.0, 360.0).default_value(90.0).unit("°"),
            ParamInfo { read_only: true, ..ParamInfo::new("Meter").range(0.0, 1.0).default_value(0.0) },
        ];
        let info = DeviceInfo { kind: "clap:org.example.amp".into(), format: DeviceFormat::Clap, params, ..DeviceInfo::default() };
        let schema = schema([&info], &SplitKinds::builtin());
        let amp = kind_of(&schema, "clap:org.example.amp");
        let values: Vec<(&str, &str, &ParamValue)> =
            amp.params.iter().map(|param| (param.key.as_str(), param.label.as_str(), &param.value)).collect();
        assert_eq!(
            values,
            [
                ("Bypass", "", &ParamValue::Switch { default: Some(true) }),
                ("Mode", "", &ParamValue::Choice { choices: vec!["clean".into(), "tube".into()], default: Some("tube".into()) }),
                (
                    "Drive",
                    "",
                    &ParamValue::Number { unit: Some(Unit::Decibel), min: Some(-12.0), max: Some(12.0), default: Some(0.1), integer: false }
                ),
                ("Voices", "", &ParamValue::Number { unit: None, min: Some(1.0), max: Some(5.0), default: Some(2.0), integer: true }),
                ("Angle", "°", &ParamValue::Number { unit: None, min: Some(0.0), max: Some(360.0), default: Some(90.0), integer: false }),
            ],
            "the parameters of the plugin; the meter that it only shows is not one"
        );
        assert!(!amp.open_params);
        let unknown = DeviceInfo { kind: "vst3:Amp".into(), format: DeviceFormat::Vst3, ..DeviceInfo::default() };
        assert!(device(&unknown).open_params, "a plugin with no parameters known has them for each instance");
    }

    #[test]
    fn the_kinds_of_split_are_those_of_the_registry() {
        use crate::model::kinds::Owner;
        let mut kinds = SplitKinds::builtin();
        let spec = KindSpec { min: 2, max: 3, first: 2 };
        kinds.define("drums.transient".parse().unwrap(), spec, Owner::Extension("drums".into())).unwrap();
        let schema = schema([], &kinds);
        let counts: Vec<(&str, usize, usize)> =
            schema.splits.iter().map(|s| (s.kind.as_str(), s.branches.min, s.branches.max)).collect();
        assert_eq!(
            counts,
            [
                ("rack", 1, 1),
                ("layer", 1, 16),
                ("band", 2, 6),
                ("ms", 2, 2),
                ("lr", 2, 2),
                ("key", 1, 16),
                ("vel", 1, 16),
                ("select", 1, 16),
                ("outs", 1, 16),
                ("drums.transient", 2, 3),
            ],
            "the built-in kinds with the branches the model takes, then the extension's"
        );
    }
}
