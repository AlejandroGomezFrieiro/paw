//! A whole chain, and the whole graph of a part, through the parser, the
//! check and the formatter.

use chain_syntax::{
    Arrow, Content, SchemaError, Value, check_text, format, format_with, parse, print,
};

/// The graph of one part: each role of a node line, live and store wires,
/// lanes, outside ends, a port, a parameter, and a wire that needs a
/// converter.
const PART: &str = "\
chain 2 \"Violin I\" rev=a41c07
-- the notes play the synth, and the room mic has its own strip
strip #1 \"Violin I\" gain=-3dB
  synth #2 voices=4
  eq #3 hp=120Hz
  compressor #4 ratio=3 key=@\"Drums/Kick\"
strip #5 \"Room\"
bus #6 \"Section\"
send #7 \"To hall\" level=-12dB
vca #8 \"Strings\"
producer midi-keys #9 smooth=20ms
producer singer #10 voice=alto
producer pitch #11
io midi-in #12 \"Keyboard\"
\"Notes\" -> #1
\"Room\" -> #5
\"Volume\" -> #1.gain
#8 -> #5.gain
#1 -> #6
#5 -> #6
#1 -> #7
#7 -> @\"Strings/Bus\"
#6 -> @\"Strings/Bus\"
\"Notes\" -> #9.notes
#9 => \"Keys\"
\"Notes\" -> #10
#10 => \"Sung\"
\"Room\" -> #11
#11 => @\"Strings/Violin I/Notes\"
#12 => \"Chords\"
checks
  latency <= 6ms
";

#[test]
fn a_part_graph_with_each_kind_of_node_and_wire_checks_and_formats_to_itself() {
    let parsed = check_text(PART, &crate::schema(), Some(&crate::context()));
    let report: Vec<String> = parsed.diagnostics.iter().map(ToString::to_string).collect();
    assert_eq!(report, Vec::<String>::new());
    assert_eq!(format(PART).as_deref(), Ok(PART));
    let document = parsed.document;
    assert_eq!(document.graph_nodes().count(), 9);
    assert_eq!(
        document
            .wires()
            .filter(|wire| wire.arrow == Arrow::Store)
            .count(),
        4
    );
}

#[test]
fn a_reader_of_version_2_reads_a_text_of_version_1_as_the_inserts_of_one_strip() {
    let upgraded = parse(BUS).document.to_version_2();
    let text = print(&upgraded);
    assert!(
        text.starts_with("chain 2 \"Gtr bus\"\nstrip\n  -- the bus of the four guitars\n  eq #2 "),
        "{text}"
    );
    let again = check_text(&text, &crate::schema(), Some(&crate::context()));
    let errors: Vec<String> = again
        .diagnostics
        .iter()
        .filter(|d| d.is_error())
        .map(ToString::to_string)
        .collect();
    assert_eq!(errors, Vec::<String>::new(), "{text}");
    assert_eq!(
        again.document, upgraded,
        "the text of version 2 holds the same graph"
    );
}

const BUS: &str = "\
chain 1 \"Gtr bus\"
-- the bus of the four guitars
eq #2 hp=90Hz lp=9kHz
band #8 \"Tame\" xover=150Hz,2.5kHz
  | Low #81
    compressor #5 ratio=4 threshold=-20dB key=@in
  | High #82 gain=-1dB
    saturation #6 drive=12dB curve=tube -- a little grit
layer #9 \"Crush\"
  | Dry
  | Crush gain=-12dB
    compressor #10 ratio=20 attack=0.1ms key=@2
    clap:com.example.sat #11 \"Drive amount\"=9dB
rack #20 \"Glue\"
  saturation #21 drive=2dB curve=tape
  mods
    macro #31 \"glue\" value=40% -> #21.drive +6dB
mods
  lfo #30 sync=1/4 -> #81.gain -3dB, #9.mix +10%
checks
  latency <= 6ms
  gain pink -20dB = 0dB +- 1dB
";

#[test]
fn a_canonical_chain_parses_checks_and_formats_to_itself() {
    let parsed = check_text(BUS, &crate::schema(), None);
    let report: Vec<String> = parsed.diagnostics.iter().map(ToString::to_string).collect();
    assert_eq!(
        report,
        [
            "13:5: warning W301: `clap:com.example.sat` is not installed: its fields stay as they are written, with no check"
        ]
    );
    assert_eq!(format(BUS).as_deref(), Ok(BUS));
}

#[test]
fn the_tree_holds_the_splits_branches_and_values_of_the_text() {
    let document = parse(BUS).document;
    let ids: Vec<&str> = document
        .nodes()
        .iter()
        .filter_map(|node| node.id.as_deref())
        .collect();
    assert_eq!(
        ids,
        ["2", "8", "5", "6", "9", "10", "11", "20", "21"],
        "the nodes in signal order"
    );
    let band = document.nodes()[1];
    let Content::Branches(branches) = &band.body.content else {
        panic!("the band split has branches")
    };
    assert_eq!(branches.len(), 2);
    assert_eq!(band.fields[0].key, "xover");
    let Value::List(crossovers) = &band.fields[0].value else {
        panic!("xover is a list")
    };
    let hertz: Vec<f64> = crossovers
        .iter()
        .map(|value| match value {
            Value::Number(number) => number.value,
            other => panic!("{other:?}"),
        })
        .collect();
    assert_eq!(hertz, [150.0, 2500.0], "kHz is read in hertz");
}

#[test]
fn the_formatter_writes_the_one_layout_and_keeps_the_comments() {
    let messy = "\
-- a comment before the header
chain   1


eq   #2  hp=0.09kHz   -- the low cut
layer #9
  |   Dry
  |  \"Wet\"  gain=-6dB
      -- the reverb of the wet branch
    reverb  #4  time=1500ms
";
    let want = "\
-- a comment before the header
chain 1

eq #2 hp=90Hz -- the low cut
layer #9
  | Dry
  | Wet gain=-6dB
    -- the reverb of the wet branch
    reverb #4 time=1.5s
";
    assert_eq!(format(messy).as_deref(), Ok(want));
}

#[test]
fn the_formatter_with_a_schema_orders_the_fields_and_drops_the_defaults() {
    let text = "chain 1\ncompressor #1 key=@in ratio=4 attack=5ms threshold=-30dB\n";
    let want = "chain 1\ncompressor #1 threshold=-30dB attack=5ms key=@in\n";
    assert_eq!(format_with(text, &crate::schema()).as_deref(), Ok(want));
}

#[test]
fn the_formatter_refuses_a_text_with_an_error() {
    let Err(diagnostics) = format("chain 1\neq #2 hp=90kHZ\n") else {
        panic!("a bad unit formatted")
    };
    assert_eq!(diagnostics.len(), 1);
    assert_eq!(diagnostics[0].code.as_str(), "E107");
}

#[test]
fn a_schema_of_another_version_does_not_load() {
    let Err(error) = chain_syntax::Schema::from_json(r#"{"chain_schema": 1, "devices": []}"#)
    else {
        panic!("a schema of version 1 loaded")
    };
    assert!(matches!(error, SchemaError::Version(1)), "{error:?}");
    assert_eq!(
        error.to_string(),
        "the schema is in version 1 of the format; this reader knows version 2"
    );
}
