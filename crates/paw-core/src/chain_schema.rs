//! paw's schema for the chain language (`paw chain schema`): each kind of
//! device that the registry has (built-in, CLAP, VST3, LV2 and Lua), the
//! kinds of split, and the kinds of modulator, as the generic crate
//! `chain-syntax` reads them.

use chain_syntax::{Count, Kind, Param, ParamValue, Schema, SplitKind, Unit};
use paw_engine::{DeviceFormat, DeviceInfo, ParamInfo};

/// The kinds that a host can lack, by their prefix: a plugin that is not
/// installed on this machine, or a Lua device of an extension that is not
/// loaded. The check gives a warning for one, not an error.
const OPEN_PREFIXES: [&str; 4] = ["clap:", "vst3:", "lv2:", "lua:"];

/// The schema of the kinds of device in `devices`, with paw's kinds of
/// split and modulator.
pub fn schema<'a>(devices: impl IntoIterator<Item = &'a DeviceInfo>) -> Schema {
    let mut schema = Schema::new("paw");
    schema.devices = devices.into_iter().map(device).collect();
    schema.splits = splits();
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
    }
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
    Param { key: info.key.clone(), name: info.name.clone(), label, value }
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

fn number(key: &str, unit: Option<Unit>, min: f64, max: f64, default: f64) -> Param {
    Param {
        key: key.into(),
        name: String::new(),
        label: String::new(),
        value: ParamValue::Number { unit, min: Some(min), max: Some(max), default: Some(default), integer: false },
    }
}

fn switch(key: &str) -> Param {
    Param { key: key.into(), name: String::new(), label: String::new(), value: ParamValue::Switch { default: Some(false) } }
}

fn text(key: &str) -> Param {
    Param { key: key.into(), name: String::new(), label: String::new(), value: ParamValue::Text { default: None } }
}

/// The kinds of split of the devices graph. Each split has a dry and wet
/// `mix` and an output `gain`, and each branch a gain, a pan, a mute and a
/// solo. This table follows the design of the devices graph; the kernel
/// model of the graph gives the kinds their sound.
fn splits() -> Vec<SplitKind> {
    let split_params = || vec![number("mix", Some(Unit::Percent), 0.0, 100.0, 100.0), number("gain", Some(Unit::Decibel), -60.0, 24.0, 0.0)];
    let branch_params = || {
        vec![
            number("gain", Some(Unit::Decibel), -60.0, 24.0, 0.0),
            number("pan", None, -1.0, 1.0, 0.0),
            switch("mute"),
            switch("solo"),
        ]
    };
    let split = |kind: &str, name: &str, min: usize, max: usize| SplitKind {
        kind: kind.into(),
        name: name.into(),
        branches: Count { min, max },
        params: split_params(),
        branch_params: branch_params(),
    };
    let mut band = split("band", "Band split", 2, 6);
    band.params.push(Param {
        key: "xover".into(),
        name: "Crossovers".into(),
        label: String::new(),
        value: ParamValue::List {
            unit: Some(Unit::Hertz),
            min: Some(20.0),
            max: Some(20000.0),
            count: Some(Count { min: 1, max: 5 }),
            ascending: true,
        },
    });
    let mut key = split("key", "Key split", 1, 16);
    key.branch_params.push(text("zone"));
    let mut velocity = split("vel", "Velocity split", 1, 16);
    velocity.branch_params.push(text("zone"));
    let mut select = split("select", "Selector", 1, 16);
    select.params.push(Param {
        key: "index".into(),
        name: "Index".into(),
        label: String::new(),
        value: ParamValue::Number { unit: None, min: Some(1.0), max: Some(16.0), default: Some(1.0), integer: true },
    });
    select.params.push(number("fade", Some(Unit::Millisecond), 0.0, 1000.0, 10.0));
    vec![
        split("rack", "Rack", 1, 1),
        split("layer", "Layer", 1, 16),
        band,
        split("ms", "Mid and side", 2, 2),
        split("lr", "Left and right", 2, 2),
        key,
        velocity,
        select,
        split("outs", "Outputs of the device before", 1, 64),
    ]
}

/// The kinds of modulator of the devices graph.
fn modulators() -> Vec<Kind> {
    let shape = Param {
        key: "shape".into(),
        name: "Shape".into(),
        label: String::new(),
        value: ParamValue::Choice {
            choices: ["sine", "triangle", "square", "saw", "random"].map(String::from).to_vec(),
            default: Some("sine".into()),
        },
    };
    let sync = Param { key: "sync".into(), name: "Sync".into(), label: String::new(), value: ParamValue::Note { default: None } };
    vec![
        Kind {
            kind: "macro".into(),
            name: "Macro".into(),
            params: vec![number("value", Some(Unit::Percent), 0.0, 100.0, 0.0)],
            open_params: false,
        },
        Kind {
            kind: "lfo".into(),
            name: "LFO".into(),
            params: vec![
                number("rate", Some(Unit::Hertz), 0.01, 50.0, 1.0),
                sync,
                shape,
                number("phase", Some(Unit::Percent), 0.0, 100.0, 0.0),
            ],
            open_params: false,
        },
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kind_of<'a>(schema: &'a Schema, kind: &str) -> &'a Kind {
        schema.device(kind).unwrap_or_else(|| panic!("the schema has `{kind}`"))
    }

    #[test]
    fn the_schema_has_each_built_in_device_and_a_text_of_them_checks() {
        let registry = paw_engine::Registry::with_builtins();
        let schema = schema(registry.iter().map(|factory| factory.info()));
        assert_eq!(schema.devices.len(), registry.iter().count(), "one kind for each device");
        // The JSON that `paw chain schema` writes loads again as the same schema.
        let loaded = Schema::from_json(&schema.to_json()).expect("paw's schema loads");
        assert_eq!(loaded, schema);
        let text = "chain 1\ncompressor #1\nlayer #2\n  | Dry\n  | Wet gain=-6dB\n    clap:org.example.missing #3\n";
        let errors: Vec<String> = chain_syntax::check_text(text, &schema)
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
            ParamInfo { boolean: true, ..ParamInfo::new("Bypass", 0.0, 1.0, 1.0, "") },
            ParamInfo::choice("Mode", &["clean", "tube"], 1),
            ParamInfo::new("Drive", -12.0, 12.0, 0.1, "dB"),
            ParamInfo { steps: 4, ..ParamInfo::new("Voices", 1.0, 5.0, 2.0, "") },
            ParamInfo::new("Angle", 0.0, 360.0, 90.0, "°"),
            ParamInfo { read_only: true, ..ParamInfo::new("Meter", 0.0, 1.0, 0.0, "") },
        ];
        let info = DeviceInfo { kind: "clap:org.example.amp".into(), format: DeviceFormat::Clap, params, ..DeviceInfo::default() };
        let schema = schema([&info]);
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
}
