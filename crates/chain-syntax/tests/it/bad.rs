//! The golden files of the diagnostics: each chain in `tests/bad` with the
//! diagnostics of the parser and the check under the example schema and
//! the example context. A file whose name starts with `no-context` is
//! checked with no context. The snapshot shows each line of the chain with
//! its diagnostics under it. A line of a golden file with no diagnostic
//! under it is a case where no diagnostic fires.

use std::path::Path;

use chain_syntax::check_text;

#[test]
fn each_bad_chain_gives_the_diagnostics_of_its_golden_file() {
    let folder = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/bad");
    let mut files: Vec<_> = std::fs::read_dir(&folder)
        .expect("tests/bad is a folder")
        .map(|entry| entry.expect("an entry of tests/bad").path())
        .filter(|path| {
            path.extension()
                .is_some_and(|extension| extension == "chain")
        })
        .collect();
    files.sort();
    assert!(!files.is_empty(), "tests/bad has chains");
    let schema = crate::schema();
    let context = crate::context();
    for path in files {
        let text = std::fs::read_to_string(&path).expect("a bad chain reads");
        let name = path
            .file_stem()
            .and_then(|stem| stem.to_str())
            .expect("a file name");
        let context = (!name.starts_with("no-context")).then_some(&context);
        let parsed = check_text(&text, &schema, context);
        insta::assert_snapshot!(name, annotate(&text, &parsed.diagnostics));
    }
}

/// The text, with each diagnostic under its line: a caret at its column,
/// and its code and message.
fn annotate(text: &str, diagnostics: &[chain_syntax::Diagnostic]) -> String {
    let mut out = String::new();
    for (index, line) in text.lines().enumerate() {
        out.push_str(&format!("{:>3} | {line}\n", index + 1));
        for diagnostic in diagnostics
            .iter()
            .filter(|diagnostic| diagnostic.span.line as usize == index + 1)
        {
            let pad = " ".repeat(diagnostic.span.column as usize - 1);
            out.push_str(&format!("    | {pad}^ {diagnostic}\n"));
        }
    }
    out
}
