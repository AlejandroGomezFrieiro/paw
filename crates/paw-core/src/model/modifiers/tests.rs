use serde_json::json;

use super::*;
use crate::model::ControlKind;

fn entry(value: Value) -> Modifier {
    serde_json::from_value(value).expect("an entry")
}

fn note(pitch: u8, start: f64) -> Note {
    serde_json::from_value(json!({ "start": start, "length": 1.0, "pitch": pitch, "velocity": 100 })).unwrap()
}

fn midi(notes: Vec<Note>, controls: Vec<Control>) -> Midi {
    Midi { notes: notes.into(), controls: controls.into() }
}

/// The result of `stack` over `input`, and what it skipped.
fn run(kinds: &ModKinds, stack: &[Modifier], input: Midi) -> (Midi, Vec<(usize, Skipped)>) {
    let mut skipped = Vec::new();
    let key = input.source_key();
    match evaluate(kinds, stack, 0..stack.len(), key, input, &mut skipped) {
        Progress::Done { result, .. } => (result, skipped),
        Progress::Needs(job) => panic!("an extension kind at {:?}", job.rest),
    }
}

fn played(result: &Midi) -> Vec<(u8, u8)> {
    result.notes.iter().map(|n| (n.pitch, n.velocity)).collect()
}

#[test]
fn an_old_overrides_field_reads_as_two_entries_and_a_stack_writes_a_list() {
    let old: Stack = serde_json::from_value(json!({ "transpose": 3, "velocity": -10 })).unwrap();
    assert_eq!(
        serde_json::to_value(&old).unwrap(),
        json!([{ "kind": "transpose", "params": { "semitones": 3 } }, { "kind": "velocity", "params": { "add": -10 } }])
    );
    let one: Stack = serde_json::from_value(json!({ "velocity": 5 })).unwrap();
    assert_eq!(one.0.len(), 1, "a field of 0 is no entry");
    assert!(serde_json::from_value::<Stack>(json!({ "pitch": 3 })).is_err(), "an unknown old field");
    // An entry keeps what paw does not read, and leaves out the defaults.
    let off = entry(json!({ "kind": "arp.up", "off": true, "params": { "rate": [1, 2] }, "version": 3 }));
    assert_eq!(serde_json::to_value(&off).unwrap()["params"], json!({ "rate": [1, 2] }));
    assert_eq!(serde_json::to_value(entry(json!({ "kind": "transpose" }))).unwrap(), json!({ "kind": "transpose" }));
}

#[test]
fn transpose_and_velocity_change_what_plays_in_the_midi_range() {
    let kinds = ModKinds::builtin();
    let bend = |key: u8| Control { start: 0.0, what: ControlKind::Bend, value: 0.5, key: Some(key) };
    let wheel = Control { start: 0.0, what: ControlKind::Cc { number: 1 }, value: 0.5, key: None };
    let input = midi(vec![note(60, 0.0), note(125, 1.0)], vec![bend(60), bend(125), wheel.clone()]);
    let stack = [
        entry(json!({ "kind": "transpose", "params": { "semitones": 3 } })),
        entry(json!({ "kind": "velocity", "params": { "add": 30 } })),
    ];
    let (result, skipped) = run(&kinds, &stack, input);
    assert!(skipped.is_empty());
    assert_eq!(played(&result), [(63, 127)], "125 + 3 does not play, and 130 stays at 127");
    assert_eq!(&*result.controls, [bend(63), wheel], "a note's bend follows it, or goes with it");
    let down = [entry(json!({ "kind": "velocity", "params": { "add": -120 } }))];
    assert_eq!(played(&run(&kinds, &down, midi(vec![note(60, 0.0)], vec![])).0), [(60, 1)], "at least 1");
}

#[test]
fn a_scope_changes_only_the_notes_that_start_in_it() {
    let kinds = ModKinds::builtin();
    let stack = [entry(json!({ "kind": "transpose", "params": { "semitones": 12 }, "scope": { "from": 1.0, "to": 2.0 } }))];
    let input = midi(vec![note(60, 0.0), note(60, 1.0), note(60, 2.0)], vec![]);
    assert_eq!(played(&run(&kinds, &stack, input).0), [(60, 100), (72, 100), (60, 100)]);
}

#[test]
fn an_entry_that_cannot_run_passes_its_input_through() {
    let kinds = ModKinds::builtin();
    let stack = [
        entry(json!({ "kind": "arp.up", "params": {} })),
        entry(json!({ "kind": "transpose", "params": { "semitones": 2 }, "version": 2 })),
        entry(json!({ "kind": "velocity", "params": { "add": 500 } })),
        entry(json!({ "kind": "transpose", "params": { "semitones": 1 } })),
    ];
    let (result, skipped) = run(&kinds, &stack, midi(vec![note(60, 0.0)], vec![]));
    assert_eq!(played(&result), [(61, 100)], "only the last entry ran");
    let skipped: Vec<String> = skipped.iter().map(|(at, why)| format!("{at}: {why}")).collect();
    assert_eq!(
        skipped,
        [
            "0: `arp.up` waits: no extension that is loaded defines it",
            "1: `transpose` is of a newer version than this paw reads",
            "2: velocity: add is a whole number from -127 to 127, not 500",
        ]
    );
}

#[test]
fn evaluation_stops_at_an_extension_kind_with_the_entries_after_it() {
    let mut kinds = ModKinds::builtin();
    kinds.put("arp.up".parse().unwrap(), ModImpl::Extern { version: Version::ONE, local: false }, Owner::User);
    let stack = [
        entry(json!({ "kind": "transpose", "params": { "semitones": 1 } })),
        entry(json!({ "kind": "arp.up", "params": {} })),
        entry(json!({ "kind": "velocity", "params": { "add": 1 } })),
    ];
    let input = midi(vec![note(60, 0.0)], vec![]);
    let key = input.source_key();
    let Progress::Needs(job) = evaluate(&kinds, &stack, 0..3, key, input, &mut Vec::new()) else {
        panic!("the job of the extension kind");
    };
    assert_eq!(played(&job.input), [(61, 100)], "the input is the result of the entries before it");
    assert_eq!((job.entry.kind.as_str(), job.rest), ("arp.up", 2..3));
    assert_eq!(job.key, key.then(&stack[0]).then(&stack[1]));
}

#[test]
fn a_key_names_the_entries_that_are_on_and_their_values() {
    let a = entry(json!({ "kind": "transpose", "params": { "semitones": 1 } }));
    let source = ChainKey::source(b"notes");
    assert_eq!(source.then(&a), ChainKey::source(b"notes").then(&a), "the same input and entry");
    let changed = entry(json!({ "kind": "transpose", "params": { "semitones": 2 } }));
    assert_ne!(source.then(&a), source.then(&changed));
    let scoped = Modifier { scope: Some(Scope { from: 0.0, to: 1.0 }), ..a.clone() };
    assert_ne!(source.then(&a), source.then(&scoped));
    // An entry that is off is not in the chain: the result after it is
    // the result before it.
    let kinds = ModKinds::builtin();
    let off = Modifier { off: true, ..changed };
    let input = midi(vec![note(60, 0.0)], vec![]);
    let done = |stack: &[Modifier]| match evaluate(&kinds, stack, 0..stack.len(), source, input.clone(), &mut Vec::new()) {
        Progress::Done { key, .. } => key,
        Progress::Needs(_) => unreachable!(),
    };
    assert_eq!(done(&[a.clone(), off]), done(&[a]));
}

#[test]
fn check_refuses_the_bad_values_of_a_built_in_kind_and_lets_an_unknown_kind_wait() {
    let kinds = ModKinds::builtin();
    let refused = |value: Value| check(&kinds, Stack(vec![entry(value)])).unwrap_err().to_string();
    assert_eq!(
        refused(json!({ "kind": "transpose", "params": { "semitones": 200 } })),
        "transpose: semitones is a whole number from -127 to 127, not 200"
    );
    assert_eq!(refused(json!({ "kind": "velocity", "params": { "by": 2 } })), "velocity: it has no value `by`: say `add`");
    assert_eq!(
        refused(json!({ "kind": "velocity", "params": {}, "version": 2 })),
        "velocity: this paw reads version 1, not 2"
    );
    let waits = Stack(vec![entry(json!({ "kind": "arp.up", "params": { "any": 1.0 } }))]);
    assert_eq!(check(&kinds, waits.clone()), Ok(waits), "kept as it was given");
    let from_lua = Stack(vec![entry(json!({ "kind": "transpose", "params": { "semitones": 3.0 } }))]);
    let written = serde_json::to_value(check(&kinds, from_lua).unwrap()).unwrap();
    assert_eq!(written, json!([{ "kind": "transpose", "params": { "semitones": 3 } }]), "a whole number");
}
