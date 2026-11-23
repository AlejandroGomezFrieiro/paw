//! The properties of the printer and the formatter, for texts that a
//! strategy makes, of version 1 (a chain) and of version 2 (node lines,
//! live and store wires, and outside ends):
//!
//! - print then parse gives the same graph;
//! - the format of a text in any layout, with comments, gives the same
//!   graph as the text;
//! - the format of a formatted text is the same text.
//!
//! The normal run uses a fixed seed (see `config`), so each run tries the
//! same cases. `PROPTEST_CASES` and `PROPTEST_RNG_SEED` change them.

use proptest::prelude::*;
use proptest::test_runner::{Config, RngSeed};

use crate::lex::is_id;
use crate::tree::{
    Arrow, Body, Branch, Check, Checks, Compare, Content, Document, End, Field, GraphNode, Header,
    Item, Link, Mods, Modulator, Node, Role, VERSION, VERSION_1, Wire,
};
use crate::value::{Dimension, Feel, Note, Number, Reference, Value};
use crate::{format, parse, print};

/// The seed of the normal run: the bytes of "chainprp".
const SEED: u64 = 0x6368_6169_6e70_7270;

fn config() -> Config {
    let mut config = Config::default();
    if config.rng_seed == RngSeed::Random {
        config.rng_seed = RngSeed::Fixed(SEED);
    }
    config
}

/// Any text: spaces, quotes, backslashes, control characters, letters of
/// any script. Names, kinds and keys can hold each of these.
fn text() -> impl Strategy<Value = String> {
    prop_oneof![
        "[a-z][a-z0-9.:_-]{0,8}",
        "[ -~]{0,10}",
        any::<String>().prop_map(|text| text.chars().take(10).collect()),
    ]
}

fn id() -> impl Strategy<Value = String> {
    "[A-Za-z0-9_-]{1,6}".prop_filter("`in` is kept for @in", |id| id != "in" && is_id(id))
}

fn number() -> impl Strategy<Value = Number> {
    let value = prop_oneof![
        (-100_000i64..100_000, 0u32..4)
            .prop_map(|(units, places)| units as f64 / 10f64.powi(places as i32)),
        any::<f64>().prop_filter("a finite number", |value| value.is_finite()),
    ];
    let dimension = prop_oneof![
        Just(None),
        Just(Some(Dimension::Gain)),
        Just(Some(Dimension::Frequency)),
        Just(Some(Dimension::Time)),
        Just(Some(Dimension::Percent)),
        Just(Some(Dimension::Pitch)),
    ];
    (value, dimension).prop_map(|(value, dimension)| Number { value, dimension })
}

/// One value that is not a list.
fn single() -> impl Strategy<Value = Value> {
    let feel = prop_oneof![
        Just(Feel::Straight),
        Just(Feel::Dotted),
        Just(Feel::Triplet)
    ];
    prop_oneof![
        number().prop_map(Value::Number),
        (1u32..64, 1u32..64, feel).prop_map(|(count, division, feel)| Value::Note(Note {
            count,
            division,
            feel
        })),
        text().prop_map(Value::Text),
        Just(Value::Reference(Reference::Input)),
        id().prop_map(|id| Value::Reference(Reference::Node(id))),
        text().prop_map(|path| Value::Reference(Reference::Outside(path))),
    ]
}

/// A value of a field: one value, or a list of two or more (a list of one
/// is written as its one value).
fn value() -> impl Strategy<Value = Value> {
    prop_oneof![3 => single(), 1 => prop::collection::vec(single(), 2..4).prop_map(Value::List)]
}

fn fields() -> impl Strategy<Value = Vec<Field>> {
    prop::collection::vec(
        (text(), value()).prop_map(|(key, value)| Field {
            key,
            value,
            span: Default::default(),
        }),
        0..3,
    )
}

fn modulator() -> impl Strategy<Value = Modulator> {
    let link = (id(), text(), single()).prop_map(|(target, key, depth)| Link {
        target,
        key,
        depth,
        span: Default::default(),
    });
    (
        text(),
        prop::option::of(id()),
        prop::option::of(text()),
        fields(),
        prop::collection::vec(link, 0..3),
    )
        .prop_map(|(kind, id, name, fields, links)| Modulator {
            kind,
            id,
            name,
            fields,
            links,
            trivia: Default::default(),
        })
}

fn mods() -> impl Strategy<Value = Option<Mods>> {
    prop::option::of(
        prop::collection::vec(modulator(), 0..3).prop_map(|modulators| Mods {
            modulators,
            trivia: Default::default(),
        }),
    )
}

/// A node with a body of nodes or branches, to a depth of three splits.
fn node() -> impl Strategy<Value = Node> {
    let leaf = (
        text(),
        prop::option::of(id()),
        prop::option::of(text()),
        fields(),
    )
        .prop_map(|(kind, id, name, fields)| Node {
            kind,
            id,
            name,
            fields,
            body: Body::default(),
            trivia: Default::default(),
        });
    leaf.prop_recursive(3, 24, 4, |inner| {
        let branch = (
            prop::option::of(text()),
            prop::option::of(id()),
            fields(),
            prop::collection::vec(inner.clone(), 0..3),
        )
            .prop_map(|(name, id, fields, nodes)| Branch {
                name,
                id,
                fields,
                nodes,
                trivia: Default::default(),
            });
        let content = prop_oneof![
            prop::collection::vec(inner.clone(), 0..3).prop_map(Content::Nodes),
            prop::collection::vec(branch, 1..4).prop_map(Content::Branches),
        ];
        (
            text(),
            prop::option::of(id()),
            prop::option::of(text()),
            fields(),
            content,
            mods(),
        )
            .prop_map(|(kind, id, name, fields, content, mods)| Node {
                kind,
                id,
                name,
                fields,
                body: Body { content, mods },
                trivia: Default::default(),
            })
    })
}

fn checks() -> impl Strategy<Value = Option<Checks>> {
    let compare = prop_oneof![
        Just(Compare::Less),
        Just(Compare::LessOrEqual),
        Just(Compare::Equal),
        Just(Compare::GreaterOrEqual),
        Just(Compare::Greater)
    ];
    let check = (
        prop::collection::vec(single(), 1..3),
        compare,
        single(),
        prop::option::of(single()),
    )
        .prop_map(|(subject, compare, expected, tolerance)| Check {
            subject,
            compare,
            expected,
            tolerance,
            trivia: Default::default(),
        });
    prop::option::of(prop::collection::vec(check, 0..3).prop_map(|lines| Checks {
        lines,
        trivia: Default::default(),
    }))
}

fn header(version: u32) -> impl Strategy<Value = Header> {
    (prop::option::of(text()), fields()).prop_map(move |(name, fields)| Header {
        version,
        name,
        fields,
        ..Header::default()
    })
}

/// A text of version 1: one chain.
fn chain() -> impl Strategy<Value = Document> {
    (
        header(VERSION_1),
        prop::collection::vec(node(), 0..4),
        mods(),
        checks(),
    )
        .prop_map(|(header, nodes, mods, checks)| Document {
            header,
            root: Body {
                content: Content::Nodes(nodes),
                mods,
            },
            graph: Vec::new(),
            checks,
            end: Default::default(),
        })
}

/// A node line of version 2, with inserts when its role holds them.
fn graph_node() -> impl Strategy<Value = GraphNode> {
    let role = prop::sample::select(Role::ALL.to_vec());
    let inserts = (prop::collection::vec(node(), 0..3), mods()).prop_map(|(nodes, mods)| Body {
        content: Content::Nodes(nodes),
        mods,
    });
    (
        role,
        text(),
        prop::option::of(id()),
        prop::option::of(text()),
        fields(),
        inserts,
    )
        .prop_map(|(role, kind, id, name, fields, inserts)| GraphNode {
            role,
            kind: role.has_kind().then_some(kind),
            id,
            name,
            fields,
            inserts: if role.holds_inserts() {
                inserts
            } else {
                Body::default()
            },
            trivia: Default::default(),
        })
}

/// A wire that the parser takes: `=>` ends at a lane, and one end at least
/// is a node.
fn wire() -> impl Strategy<Value = Wire> {
    fn node() -> impl Strategy<Value = End> {
        (id(), prop::option::of(text())).prop_map(|(id, port)| End::Node { id, port })
    }
    fn lane() -> impl Strategy<Value = End> {
        prop_oneof![text().prop_map(End::Lane), text().prop_map(End::Outside)]
    }
    prop_oneof![
        (node(), lane()).prop_map(|(from, to)| (from, Arrow::Store, to)),
        (prop_oneof![node(), lane()], node()).prop_map(|(from, to)| (from, Arrow::Live, to)),
        (node(), text().prop_map(End::Outside)).prop_map(|(from, to)| (from, Arrow::Live, to)),
    ]
    .prop_map(|(from, arrow, to)| Wire {
        from,
        arrow,
        to,
        trivia: Default::default(),
    })
}

/// A text of version 2: the graph of a part.
fn part() -> impl Strategy<Value = Document> {
    let item = prop_oneof![
        graph_node().prop_map(Item::Node),
        wire().prop_map(Item::Wire)
    ];
    (header(VERSION), prop::collection::vec(item, 0..6), checks()).prop_map(
        |(header, graph, checks)| Document {
            header,
            root: Body::default(),
            graph,
            checks,
            end: Default::default(),
        },
    )
}

fn document() -> impl Strategy<Value = Document> {
    prop_oneof![chain(), part()]
}

/// The text in another layout, by the choices in `changes`: more spaces
/// between tokens, spaces at the ends of lines, empty lines, and comments
/// on lines of their own and at the ends of lines.
fn messy(text: &str, changes: &[u8]) -> String {
    let mut out = String::new();
    for (index, line) in text.lines().enumerate() {
        let change = changes[index % changes.len()];
        if change & 1 != 0 {
            out.push('\n');
        }
        if change & 2 != 0 {
            out.push_str("-- a comment line\n");
        }
        let indent = line.len() - line.trim_start().len();
        out.push_str(&line[..indent]);
        // Double each space between tokens, outside the quotes.
        let mut quoted = false;
        let mut escaped = false;
        for c in line[indent..].chars() {
            out.push(c);
            match c {
                '\\' if quoted && !escaped => {
                    escaped = true;
                    continue;
                }
                '"' if !escaped => quoted = !quoted,
                ' ' if !quoted && change & 4 != 0 => out.push(' '),
                _ => {}
            }
            escaped = false;
        }
        if change & 8 != 0 {
            out.push_str("  -- a comment at the end");
        } else if change & 16 != 0 {
            out.push_str("   ");
        }
        out.push('\n');
    }
    out
}

proptest! {
    #![proptest_config(config())]

    #[test]
    fn print_then_parse_gives_the_same_graph(document in document()) {
        let text = print(&document);
        let parsed = parse(&text);
        prop_assert!(parsed.diagnostics.is_empty(), "{:?} in\n{text}", parsed.diagnostics);
        prop_assert_eq!(parsed.document, document, "the text:\n{}", text);
    }

    #[test]
    fn the_format_keeps_the_graph_and_a_second_format_changes_nothing(
        document in document(),
        changes in prop::collection::vec(any::<u8>(), 1..16),
    ) {
        let text = messy(&print(&document), &changes);
        let formatted = format(&text);
        prop_assert!(formatted.is_ok(), "{:?} in\n{text}", formatted);
        let formatted = formatted.unwrap_or_default();
        prop_assert_eq!(&parse(&formatted).document, &parse(&text).document, "the text:\n{}", text);
        prop_assert_eq!(&parse(&text).document, &document, "the text:\n{}", text);
        prop_assert_eq!(format(&formatted), Ok(formatted.clone()));
    }
}
