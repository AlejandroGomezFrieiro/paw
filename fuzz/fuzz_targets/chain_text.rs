//! A chain text, as a host reads a `.chain` file or a buffer: the parser
//! and the check give diagnostics, never a panic. A text that parses with
//! no error prints, parses again to the same graph, and formats to a text
//! that a second format does not change.

#![no_main]

use chain_syntax::{Schema, check, format, parse, print};
use libfuzzer_sys::fuzz_target;

fuzz_target!(|bytes: &[u8]| {
    let Ok(text) = std::str::from_utf8(bytes) else { return };
    let schema = Schema::from_json(include_str!("../../crates/chain-syntax/tests/fixtures/schema.json"))
        .expect("the example schema loads");
    let parsed = parse(text);
    check(&parsed.document, &schema);
    if parsed.has_errors() {
        return;
    }
    let printed = print(&parsed.document);
    assert_eq!(parse(&printed).document, parsed.document, "print then parse gives the same graph");
    let formatted = format(text).expect("a text with no parse error formats");
    assert_eq!(format(&formatted).as_deref(), Ok(formatted.as_str()), "a second format changes nothing");
});
