//! What an editor asks at a place of a text: completion, hover and
//! definition. A `$` in a text of these tests marks the place.

use chain_syntax::{Completion, CompletionKind, Span, complete, definition, hover};

/// The text without its `$`, and the byte offset of the `$`.
fn at(marked: &str) -> (String, usize) {
    let offset = marked.find('$').expect("the text marks the place with `$`");
    (marked.replacen('$', "", 1), offset)
}

fn labels(marked: &str) -> Vec<String> {
    let (text, offset) = at(marked);
    complete(&text, offset, &crate::schema(), None)
        .into_iter()
        .map(|completion| completion.label)
        .collect()
}

fn hover_lines(marked: &str) -> Option<Vec<String>> {
    let (text, offset) = at(marked);
    hover(&text, offset, &crate::schema()).map(|hover| hover.lines)
}

fn defined_at(marked: &str) -> Option<String> {
    let (text, offset) = at(marked);
    definition(&text, offset).map(|span| {
        format!(
            "{}:{} {}",
            span.line,
            span.column,
            &text[span.start..span.end]
        )
    })
}

#[test]
fn completion_offers_the_words_of_the_schema_that_fit_the_place() {
    let devices_and_splits = [
        "synth",
        "arp",
        "eq",
        "compressor",
        "saturation",
        "gate",
        "delay",
        "limiter",
        "sampler",
        "rack",
        "layer",
        "band",
    ];
    let cases: &[(&str, &[&str])] = &[
        ("chain 1\n$", &devices_and_splits),
        ("chain 1\ncom$", &["compressor"]),
        ("chain 1\nrack\n  sat$", &["saturation"]),
        ("chain 1\nsaturation dr$", &["drive"]),
        // A key that the line has already is not offered again.
        ("chain 1\nsaturation drive=2dB $", &["curve", "mix"]),
        ("chain 1\nsaturation curve=t$", &["tube", "tape"]),
        ("chain 1\ndelay pingpong=$", &["on", "off"]),
        ("chain 1\nlayer\n  | Dry $", &["gain", "pan", "mute"]),
        ("chain 1\nmods\n  $", &["macro", "lfo"]),
        ("chain 1\nmods\n  lfo s$", &["sync", "shape"]),
        // No word fits the header, a check, a number, a link or a kind that
        // the schema does not have.
        ("chain$", &[]),
        ("chain 1\nchecks\n  lat$", &[]),
        ("chain 1\nsaturation drive=1$", &[]),
        ("chain 1\neq #2\nmods\n  lfo -> $", &[]),
        ("chain 1\nreverb $", &[]),
    ];
    for (marked, expected) in cases {
        assert_eq!(labels(marked), *expected, "completion in {marked:?}");
    }
}

#[test]
fn a_completed_key_replaces_the_typed_word_and_adds_its_equals_sign() {
    let (text, offset) = at("chain 1\nsaturation dr$");
    let expected = Completion {
        label: "drive".into(),
        insert: "drive=".into(),
        detail: "a number in dB from 0 to 36, default 6".into(),
        kind: CompletionKind::Parameter,
        span: Span {
            start: 19,
            end: 21,
            line: 2,
            column: 12,
        },
    };
    assert_eq!(complete(&text, offset, &crate::schema(), None), [expected]);
    let (text, offset) = at("chain 1\nsaturation dr$=2dB");
    let inserts: Vec<String> = complete(&text, offset, &crate::schema(), None)
        .into_iter()
        .map(|c| c.insert)
        .collect();
    assert_eq!(inserts, ["drive"], "a key with its `=` already");
}

#[test]
fn hover_gives_the_schema_of_a_kind_and_of_a_parameter() {
    let kind = hover_lines("chain 1\ngat$e threshold=-50dB");
    assert_eq!(
        kind.unwrap(),
        [
            "`gate` (Gate): a device",
            "threshold: a number in dB from -80 to 0, default -40",
            "key: a source: `@id`, `@in`, `@\"path\"` or a name that the host knows",
        ]
    );
    let param = hover_lines("chain 1\ncompressor ra$tio=4");
    assert_eq!(
        param.unwrap(),
        ["`ratio`", "a number (:1) from 1 to 20, default 4"]
    );
    let target = hover_lines("chain 1\nsaturation #21\nmods\n  macro -> #21.dr$ive +6dB");
    assert_eq!(
        target.unwrap(),
        ["`drive`", "a number in dB from 0 to 36, default 6"],
        "a link's target"
    );
    assert_eq!(
        hover_lines("chain 1\nreverb$ size=2"),
        None,
        "a kind that the schema does not have"
    );
}

#[test]
fn definition_goes_from_a_reference_or_a_link_to_the_id_that_it_names() {
    const CHAIN: &str =
        "chain 1\neq #2\nsaturation #21\ncompressor key=@2\nmods\n  macro -> #21.drive +6dB";
    let mark = |word: &str| CHAIN.replacen(word, &format!("{word}$"), 1);
    assert_eq!(
        defined_at(&mark("@2")),
        Some("2:4 #2".into()),
        "a reference"
    );
    assert_eq!(
        defined_at(&mark("#21.dr")),
        Some("3:12 #21".into()),
        "a link's target"
    );
    assert_eq!(
        defined_at("chain 1\ncompressor key=@in$"),
        None,
        "the input of the chain"
    );
    assert_eq!(
        defined_at("chain 1\nmods\n  lfo -> #9.mix$ +1%"),
        None,
        "an id that the text does not define"
    );
}

#[test]
fn completion_in_version_2_offers_roles_kinds_and_the_ends_of_the_context() {
    let with_context = |marked: &str| {
        let (text, offset) = at(marked);
        complete(&text, offset, &crate::schema(), Some(&crate::context()))
            .into_iter()
            .map(|completion| completion.label)
            .collect::<Vec<String>>()
    };
    let strings = ["@\"Strings/Violin I/Notes\"", "@\"Strings/Bus\""];
    let cases: &[(&str, &[&str])] = &[
        (
            "chain 2\n$",
            &["strip", "bus", "master", "send", "vca", "producer", "io"],
        ),
        ("chain 2\nproducer mi$", &["midi-keys"]),
        ("chain 2\nio $", &["audio-in", "midi-in"]),
        ("chain 2\nsend #1 le$", &["level"]),
        ("chain 2\nstrip #1\n  syn$", &["synth"]),
        ("chain 2\n#1 -> @\"Str$", &strings),
        (
            "chain 2\nstrip\n  compressor key=@\"Dr$",
            &["@\"Drums/Kick\""],
        ),
        ("chain 2\n#1 => \"S$", &["\"Sung\"", strings[0], strings[1]]),
    ];
    for (marked, expected) in cases {
        assert_eq!(with_context(marked), *expected, "completion in {marked:?}");
    }
    assert_eq!(
        labels("chain 2\n#1 -> @\"Str$"),
        Vec::<String>::new(),
        "no context, no ends"
    );
}

#[test]
fn hover_on_a_port_of_a_wire_gives_its_stream() {
    let port = hover_lines("chain 2\nproducer singer #6\n\"Notes\" -> #6.no$tes");
    assert_eq!(
        port.unwrap(),
        ["`#6.notes`: an input of midi with lyrics=on, the main one"]
    );
}
