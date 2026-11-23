//! The reference page of the language (docs/reference/chain-language.md):
//! each rule of its grammar has a section with an example, and each
//! example parses, passes the check against the example schema and
//! context, and is in the format that the formatter writes. The page lists
//! each code of a diagnostic. The package of the crate leaves this test
//! out: it has no page of the repository.

use chain_syntax::{Code, Context, Schema, check_text, format};

/// A page of docs/reference. It is read when the test runs, not when it
/// builds: the flake's clippy check builds the tests without the docs.
fn page(name: &str) -> String {
    let path = format!("{}/../../docs/reference/{name}", env!("CARGO_MANIFEST_DIR"));
    std::fs::read_to_string(&path).unwrap_or_else(|error| panic!("{path}: {error}"))
}

/// The text of each fenced block of `language` on the page.
fn blocks(page: &str, language: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut current: Option<String> = None;
    for line in page.lines() {
        match &mut current {
            None if line == format!("```{language}") => current = Some(String::new()),
            Some(text) if line == "```" => {
                out.push(std::mem::take(text));
                current = None;
            }
            Some(text) => {
                text.push_str(line);
                text.push('\n');
            }
            None => {}
        }
    }
    out
}

#[test]
fn each_example_of_the_page_parses_checks_and_is_formatted() {
    let schema =
        Schema::from_json(include_str!("fixtures/schema.json")).expect("the example schema loads");
    let context = Context::from_json(include_str!("fixtures/context.json"))
        .expect("the example context loads");
    let examples = blocks(&page("chain-language.md"), "chain");
    assert!(examples.len() > 20, "the page has its examples");
    for example in examples {
        // A warning of a plugin that is not installed is part of an
        // example; a lane that the context does not have is not.
        let problems: Vec<String> = check_text(&example, &schema, Some(&context))
            .diagnostics
            .iter()
            .filter(|diagnostic| diagnostic.is_error() || diagnostic.code == Code::UnknownOutside)
            .map(ToString::to_string)
            .collect();
        assert_eq!(problems, Vec::<String>::new(), "the example:\n{example}");
        assert_eq!(
            format(&example).as_deref(),
            Ok(example.as_str()),
            "the example is formatted"
        );
    }
}

#[test]
fn each_rule_of_the_grammar_has_a_section_with_an_example() {
    let page = page("chain-language.md");
    let grammar = blocks(&page, "ebnf").concat();
    let rules: Vec<&str> = grammar
        .lines()
        .filter_map(|line| line.split_once(" = "))
        .map(|(name, _)| name.trim())
        .collect();
    assert!(rules.len() > 20, "the grammar has its rules");
    for rule in rules {
        let heading = format!("### `{rule}`\n");
        let Some(at) = page.find(&heading) else {
            panic!("the rule `{rule}` has no section")
        };
        let section = &page[at + heading.len()..];
        let section = &section[..section.find("\n### ").unwrap_or(section.len())];
        assert!(
            section.contains("```chain\n"),
            "the section of `{rule}` has an example"
        );
    }
}

#[test]
fn the_examples_of_the_schema_page_load() {
    let examples = blocks(&page("chain-schema.md"), "json");
    assert_eq!(
        examples.len(),
        2,
        "the schema page has a schema and a context"
    );
    let schema = Schema::from_json(&examples[0]).expect("the example schema of the page loads");
    assert!(schema.split("band").is_some() && schema.is_open("clap:com.example.other"));
    assert!(schema.stream("curve").is_some_and(|curve| curve.control));
    assert!(schema.producer("mono").is_some_and(|mono| mono.converts));
    let context = Context::from_json(&examples[1]).expect("the example context of the page loads");
    assert!(context.lane("Mic").is_some() && context.outside("Strings/Bus").is_some());
}

#[test]
fn the_page_lists_each_code_of_a_diagnostic() {
    let page = page("chain-language.md");
    for code in Code::ALL {
        assert!(
            page.contains(&format!("| `{}` |", code.as_str())),
            "the page lists {}",
            code.as_str()
        );
    }
}
