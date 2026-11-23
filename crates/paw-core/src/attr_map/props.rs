//! Property tests of a part's attribute map: a map saved in the project
//! file and read again.

use proptest::collection::{btree_map, vec};
use proptest::prelude::*;
use serde_json::{Map, Value, json};

use super::{Art, AttrMap, SendWhen, TypeKey, parse};
use crate::clipfile::key_name;
use crate::props::config;

/// One event of an `out` line, of each kind that a map can send.
fn word() -> impl Strategy<Value = String> {
    let key = prop_oneof![(0u8..=127).prop_map(|key| key.to_string()), (0u8..=127).prop_map(key_name)];
    let strike = (prop_oneof![Just("ks"), Just("hold")], key, prop::option::of(1u8..=127)).prop_map(
        |(what, key, velocity)| match velocity {
            Some(velocity) => format!("{what}={key}:{velocity}"),
            None => format!("{what}={key}"),
        },
    );
    prop_oneof![
        strike,
        (0u8..=127, 0u8..=127).prop_map(|(number, value)| format!("cc{number}={value}")),
        (0u8..=127, prop::option::of(0u16..=16383)).prop_map(|(program, bank)| match bank {
            Some(bank) => format!("pc={program}/{bank}"),
            None => format!("pc={program}"),
        }),
        (-1.0..=1.0f64).prop_map(|bend| format!("bend={bend}")),
        (1u8..=16).prop_map(|channel| format!("ch={channel}")),
        Just("attr".to_string()),
    ]
}

fn line() -> impl Strategy<Value = String> {
    vec(word(), 0..4).prop_map(|words| words.join(" "))
}

fn delay() -> impl Strategy<Value = Option<f64>> {
    prop::option::of(-2000.0..=2000.0f64)
}

/// What else the writer of an entry keeps in it: a name, a tag.
fn rest() -> impl Strategy<Value = Map<String, Value>> {
    let key = "[a-z]{1,6}".prop_filter("a field of its own", |key| key != "out" && key != "delay");
    let value = prop_oneof!["\\PC{0,8}".prop_map(Value::from), any::<i64>().prop_map(Value::from), any::<bool>().prop_map(Value::from)];
    btree_map(key, value, 0..3).prop_map(|rest| rest.into_iter().collect())
}

fn art() -> impl Strategy<Value = Art> {
    prop_oneof![
        line().prop_map(Art::Line),
        (line(), delay(), rest()).prop_map(|(out, delay, rest)| Art::Table { out, delay, rest }),
    ]
}

/// An articulation's code: "11.A", or "11.A2" with a variation.
fn code() -> impl Strategy<Value = String> {
    (0x10u8..=0x1f, 0u8..16, prop::option::of(1u8..16)).prop_map(|(class, subclass, variation)| match variation {
        Some(variation) => format!("{class:X}.{subclass:X}{variation:X}"),
        None => format!("{class:X}.{subclass:X}"),
    })
}

/// Any map that plays (`AttrMap::plan` takes it).
fn attr_map() -> impl Strategy<Value = AttrMap> {
    let send = prop_oneof![Just(SendWhen::Change), Just(SendWhen::Every)];
    let by_type = btree_map((1u8..=255).prop_map(TypeKey), art(), 0..3);
    (send, vec(0u8..=127, 0..3), prop::option::of(art()), btree_map(code(), art(), 0..4), by_type, any::<bool>(), delay())
        .prop_map(|(send, chase, default, arts, by_type, attribute, delay)| AttrMap {
            send,
            chase,
            default,
            arts,
            by_type,
            attribute,
            delay,
        })
}

proptest! {
    #![proptest_config(config())]

    /// A map saved in the project file and read again is the same map.
    #[test]
    fn an_attr_map_comes_back_from_the_project_file(map in attr_map()) {
        let text = serde_json::to_string(&json!({ "attr_map": map })).expect("a map is written");

        let file: Value = serde_json::from_str(&text).expect("the text is JSON");
        let read = parse(file["attr_map"].clone());

        prop_assert_eq!(read.expect("the map plays"), Some(map));
    }
}
