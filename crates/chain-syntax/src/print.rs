//! The printer: a [`Document`] into its one canonical text. The formatter
//! is a parse and then a print, so this module decides the format: two
//! spaces of indent for each level, one space between tokens, each number
//! in the unit of its size, a quote only where a word cannot stand, one
//! empty line where the text had one or more, and each comment kept.

use crate::lex;
use crate::tree::{
    Body, Check, Content, Document, End, Field, GraphNode, Item, Link, Mods, Modulator, Node,
    Trivia, Wire,
};
use crate::value::{Number, Reference, Value};

/// The text of a document.
pub fn print(document: &Document) -> String {
    let mut printer = Printer { out: String::new() };
    let header = &document.header;
    printer.open(&header.trivia, 0);
    printer.out.push_str(&format!("chain {}", header.version));
    printer.name(header.name.as_deref());
    printer.fields(&header.fields);
    printer.close(&header.trivia);
    printer.body(&document.root, 0);
    for item in &document.graph {
        match item {
            Item::Node(node) => printer.graph_node(node),
            Item::Wire(wire) => printer.wire(wire),
        }
    }
    if let Some(checks) = &document.checks {
        printer.open(&checks.trivia, 0);
        printer.out.push_str("checks");
        printer.close(&checks.trivia);
        for check in &checks.lines {
            printer.check(check);
        }
    }
    printer.comments(&document.end, 0);
    printer.out
}

struct Printer {
    out: String,
}

impl Printer {
    /// The empty line and the comment lines before an item, and the indent
    /// of its line.
    fn open(&mut self, trivia: &Trivia, level: usize) {
        self.comments(trivia, level);
        self.indent(level);
    }

    fn comments(&mut self, trivia: &Trivia, level: usize) {
        if trivia.blank_before && !self.out.is_empty() {
            self.out.push('\n');
        }
        for comment in &trivia.comments {
            self.indent(level);
            self.out.push_str("--");
            self.out.push_str(comment);
            self.out.push('\n');
        }
    }

    fn indent(&mut self, level: usize) {
        self.out.extend(std::iter::repeat_n("  ", level));
    }

    /// The comment at the end of the line, and the end of the line.
    fn close(&mut self, trivia: &Trivia) {
        if let Some(comment) = &trivia.trailing {
            self.out.push_str(" --");
            self.out.push_str(comment);
        }
        self.out.push('\n');
    }

    fn body(&mut self, body: &Body, level: usize) {
        match &body.content {
            Content::Nodes(nodes) => nodes.iter().for_each(|node| self.node(node, level)),
            Content::Branches(branches) => {
                for branch in branches {
                    self.open(&branch.trivia, level);
                    self.out.push('|');
                    if let Some(name) = &branch.name {
                        self.out.push(' ');
                        self.text(name);
                    }
                    self.id(branch.id.as_deref());
                    self.fields(&branch.fields);
                    self.close(&branch.trivia);
                    branch
                        .nodes
                        .iter()
                        .for_each(|node| self.node(node, level + 1));
                }
            }
        }
        if let Some(mods) = &body.mods {
            self.mods(mods, level);
        }
    }

    fn node(&mut self, node: &Node, level: usize) {
        self.open(&node.trivia, level);
        self.kind(&node.kind);
        self.id(node.id.as_deref());
        self.name(node.name.as_deref());
        self.fields(&node.fields);
        self.close(&node.trivia);
        self.body(&node.body, level + 1);
    }

    fn graph_node(&mut self, node: &GraphNode) {
        self.open(&node.trivia, 0);
        self.out.push_str(node.role.as_str());
        if let Some(kind) = &node.kind {
            self.out.push(' ');
            self.kind(kind);
        }
        self.id(node.id.as_deref());
        self.name(node.name.as_deref());
        self.fields(&node.fields);
        self.close(&node.trivia);
        self.body(&node.inserts, 1);
    }

    fn wire(&mut self, wire: &Wire) {
        self.open(&wire.trivia, 0);
        self.end(&wire.from);
        self.out.push(' ');
        self.out.push_str(wire.arrow.as_str());
        self.out.push(' ');
        self.end(&wire.to);
        self.close(&wire.trivia);
    }

    fn end(&mut self, end: &End) {
        match end {
            End::Node { id, port } => {
                self.out.push('#');
                self.out.push_str(id);
                if let Some(port) = port {
                    self.out.push('.');
                    self.key(port);
                }
            }
            End::Lane(lane) => quote(&mut self.out, lane),
            End::Outside(path) => {
                self.out.push('@');
                quote(&mut self.out, path);
            }
        }
    }

    fn mods(&mut self, mods: &Mods, level: usize) {
        self.open(&mods.trivia, level);
        self.out.push_str("mods");
        self.close(&mods.trivia);
        for modulator in &mods.modulators {
            self.modulator(modulator, level + 1);
        }
    }

    fn modulator(&mut self, modulator: &Modulator, level: usize) {
        self.open(&modulator.trivia, level);
        self.kind(&modulator.kind);
        self.id(modulator.id.as_deref());
        self.name(modulator.name.as_deref());
        self.fields(&modulator.fields);
        if !modulator.links.is_empty() {
            self.out.push_str(" ->");
            for (index, link) in modulator.links.iter().enumerate() {
                self.out.push_str(if index == 0 { " " } else { ", " });
                self.link(link);
            }
        }
        self.close(&modulator.trivia);
    }

    fn link(&mut self, link: &Link) {
        self.out.push('#');
        self.out.push_str(&link.target);
        self.out.push('.');
        self.key(&link.key);
        self.out.push(' ');
        self.value(&link.depth, true);
    }

    fn check(&mut self, check: &Check) {
        self.open(&check.trivia, 1);
        for (index, part) in check.subject.iter().enumerate() {
            if index > 0 {
                self.out.push(' ');
            }
            self.value(part, false);
        }
        self.out.push(' ');
        self.out.push_str(check.compare.as_str());
        self.out.push(' ');
        self.value(&check.expected, false);
        if let Some(tolerance) = &check.tolerance {
            self.out.push_str(" +- ");
            self.value(tolerance, false);
        }
        self.close(&check.trivia);
    }

    /// A kind, quoted when it is not a word or when it is a word that
    /// starts another kind of line.
    fn kind(&mut self, kind: &str) {
        if lex::is_word(kind) && !matches!(kind, "chain" | "mods" | "checks") {
            self.out.push_str(kind);
        } else {
            quote(&mut self.out, kind);
        }
    }

    fn id(&mut self, id: Option<&str>) {
        if let Some(id) = id {
            self.out.push_str(" #");
            self.out.push_str(id);
        }
    }

    /// The name of a node: always quoted, so that it does not read as a kind.
    fn name(&mut self, name: Option<&str>) {
        if let Some(name) = name {
            self.out.push(' ');
            quote(&mut self.out, name);
        }
    }

    fn fields(&mut self, fields: &[Field]) {
        for field in fields {
            self.out.push(' ');
            self.key(&field.key);
            self.out.push('=');
            self.value(&field.value, false);
        }
    }

    fn key(&mut self, key: &str) {
        if lex::is_word(key) {
            self.out.push_str(key);
        } else {
            quote(&mut self.out, key);
        }
    }

    /// A text as a bare word where it lexes as one, else quoted.
    fn text(&mut self, text: &str) {
        if lex::is_word(text) {
            self.out.push_str(text);
        } else {
            quote(&mut self.out, text);
        }
    }

    fn value(&mut self, value: &Value, signed: bool) {
        match value {
            Value::Number(number) => Number::write(number, &mut self.out, signed),
            Value::Note(note) => self.out.push_str(&note.to_string()),
            Value::Text(text) => self.text(text),
            Value::Reference(Reference::Input) => self.out.push_str("@in"),
            Value::Reference(Reference::Node(id)) => {
                self.out.push('@');
                self.out.push_str(id);
            }
            Value::Reference(Reference::Outside(path)) => {
                self.out.push('@');
                quote(&mut self.out, path);
            }
            Value::List(values) => {
                for (index, value) in values.iter().enumerate() {
                    if index > 0 {
                        self.out.push(',');
                    }
                    self.value(value, false);
                }
            }
        }
    }
}

/// `text` in quotes, with the escapes that the lexer reads.
fn quote(out: &mut String, text: &str) {
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => out.push_str(&format!("\\u{{{:x}}}", u32::from(c))),
            c => out.push(c),
        }
    }
    out.push('"');
}

/// A value as the printer writes it, for a message.
pub(crate) fn value_text(value: &Value) -> String {
    let mut printer = Printer { out: String::new() };
    printer.value(value, false);
    printer.out
}
