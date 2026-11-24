//! The parser: the lines of a text into a [`Document`].
//!
//! The parser never stops at an error. A line that does not parse gives a
//! diagnostic and is left out of the tree, and the parser goes on with the
//! next line. A token that does not parse is left out of its line. So one
//! pass finds every error of the text.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::float_cmp, reason = "debt: pay down")]

use crate::diagnostic::{Code, Diagnostic, Span};
use crate::lex::{self, Line, Tok, Token};
use crate::tree::{
    Arrow, Body, Branch, Check, Checks, Content, Document, End, Field, GraphNode, Header,
    Item as TopItem, Link, Mods, Modulator, Node, Role, Spanned, Trivia, VERSION, VERSION_1, Wire,
};
use crate::value::{Reference, Value};

/// A parsed text: the tree, and each problem that the parser found.
#[derive(Clone, Debug)]
pub struct Parsed {
    pub document: Document,
    pub diagnostics: Vec<Diagnostic>,
}

impl Parsed {
    /// Whether the text has an error. A host does not apply a text with an error.
    pub fn has_errors(&self) -> bool {
        self.diagnostics.iter().any(Diagnostic::is_error)
    }
}

/// Parses a chain text. See the crate's documentation for the language.
pub fn parse(text: &str) -> Parsed {
    let mut diagnostics = Vec::new();
    let (items, end) = items(text, &mut diagnostics);
    // A text with no header, or a version that the reader does not know,
    // is read in the version that its lines fit, so that the header gives
    // the one error.
    let fallback = if items.iter().any(Item::fits_version_2) {
        VERSION
    } else {
        VERSION_1
    };
    let mut parser = Parser {
        items: items.into_iter().peekable(),
        diagnostics,
    };
    let mut document = Document {
        header: parser.header(fallback),
        end,
        ..Document::default()
    };
    if document.header.version == VERSION_1 {
        document.root = parser.body(0, Place::Top, &mut document.checks);
    } else {
        document.graph = parser.graph(&mut document.checks);
    }
    let mut diagnostics = parser.diagnostics;
    diagnostics.sort_by_key(|diagnostic| (diagnostic.span.start, diagnostic.span.end));
    Parsed {
        document,
        diagnostics,
    }
}

/// A line with tokens, and the comments and the empty lines before it.
struct Item {
    line: Line,
    trivia: Trivia,
}

impl Item {
    fn first(&self) -> Option<&Tok> {
        self.line.tokens.first().map(|token| &token.tok)
    }

    /// Whether the line can only be a line of version 2: a wire, or a node
    /// line of a role at the top level.
    fn fits_version_2(&self) -> bool {
        let role = matches!(self.first(), Some(Tok::Word(word)) if Role::from_word(word).is_some());
        self.line.level == 0 && (role || matches!(LineKind::of(self), LineKind::Wire))
    }

    /// Whether the line is the one word `word`, as `mods` and `checks` are.
    fn is_keyword(&self, word: &str) -> bool {
        self.line.tokens.len() == 1 && self.first() == Some(&Tok::Word(word.into()))
    }
}

/// Splits the text into lines, lexes each one, and gives each comment line
/// and empty line to the next line with tokens. The trivia that is left at
/// the end goes into the second value.
fn items(text: &str, diagnostics: &mut Vec<Diagnostic>) -> (Vec<Item>, Trivia) {
    let mut items = Vec::new();
    let mut pending = Trivia::default();
    let mut start = 0;
    for (index, raw) in text.split('\n').enumerate() {
        let content = raw.strip_suffix('\r').unwrap_or(raw);
        let line = lex::line(content, start, index as u32 + 1, diagnostics);
        start += raw.len() + 1;
        if line.tokens.is_empty() {
            match line.comment {
                Some(comment) => pending.comments.push(comment),
                // An empty line before the first comment of an item.
                None if pending.comments.is_empty() => pending.blank_before = true,
                // An empty line between comments: the comments before it
                // stay with the next item.
                None => {}
            }
            continue;
        }
        let trivia = Trivia {
            span: line.span,
            trailing: line.comment.clone(),
            ..std::mem::take(&mut pending)
        };
        items.push(Item { line, trivia });
    }
    // The text's last newline makes one empty line that is not a blank line.
    if text.ends_with('\n') && pending.comments.is_empty() {
        pending.blank_before = false;
    }
    (items, pending)
}

/// Where a body is, which decides the lines that it can hold.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Place {
    /// The top level of a chain of version 1: nodes, `mods` and `checks`.
    Top,
    /// Under a strip, a bus or the master: nodes and `mods`.
    Inserts,
    /// Under a split: nodes or branches, and `mods`.
    Split,
    /// Under a `|` line: nodes only.
    Branch,
}

struct Parser {
    /// The lines that are not read yet.
    items: std::iter::Peekable<std::vec::IntoIter<Item>>,
    diagnostics: Vec<Diagnostic>,
}

impl Parser {
    fn peek(&mut self) -> Option<&Item> {
        self.items.peek()
    }

    fn error(&mut self, code: Code, span: Span, message: impl Into<String>) {
        self.diagnostics.push(Diagnostic::new(code, span, message));
    }

    /// Takes the next item, which the caller has seen with `peek`.
    fn take(&mut self) -> Item {
        self.items
            .next()
            .expect("the caller has seen the item with `peek`")
    }

    /// Leaves out the lines deeper than `level`, after a line that has an
    /// error: the lines under a bad line cannot be placed.
    fn skip_under(&mut self, level: usize) {
        while self.items.next_if(|item| item.line.level > level).is_some() {}
    }

    /// The header, `chain 2`, when the first line is one. Else a header of
    /// the version `fallback`, and a diagnostic.
    fn header(&mut self, fallback: u32) -> Header {
        let missing = Header {
            version: fallback,
            ..Header::default()
        };
        let Some(item) = self.peek() else {
            let span = Span {
                line: 1,
                column: 1,
                ..Span::default()
            };
            self.error(
                Code::MissingHeader,
                span,
                "the text is empty: a chain starts with the line `chain 2`",
            );
            return missing;
        };
        if item.first() != Some(&Tok::Word("chain".into())) {
            let span = item.line.span;
            self.error(
                Code::MissingHeader,
                span,
                "a chain starts with the line `chain 2`",
            );
            return missing;
        }
        let item = self.take();
        let mut tokens = Cursor::new(&item.line.tokens[1..], item.line.span);
        let version = match tokens.next() {
            Some(Token {
                tok:
                    Tok::Number {
                        number,
                        signed: false,
                    },
                span,
            }) if number.dimension.is_none() && number.value.fract() == 0.0 => {
                if number.value == f64::from(VERSION_1) {
                    VERSION_1
                } else if number.value == f64::from(VERSION) {
                    VERSION
                } else {
                    let message = format!(
                        "this text is in version {} of the language; this reader knows versions {VERSION_1} and {VERSION}",
                        number.value
                    );
                    self.error(Code::Version, span, message);
                    fallback
                }
            }
            _ => {
                self.error(
                    Code::MissingHeader,
                    item.line.span,
                    "`chain` needs the version of the language: `chain 2`",
                );
                fallback
            }
        };
        let name = tokens.name();
        let fields = tokens.fields(&mut self.diagnostics, false);
        Header {
            version,
            name,
            fields,
            trivia: item.trivia,
        }
    }

    /// The lines at `level` and the lines under them, up to the first line
    /// that is less deep.
    fn body(&mut self, level: usize, place: Place, checks: &mut Option<Checks>) -> Body {
        let mut nodes = Vec::new();
        let mut branches = Vec::new();
        let mut mods: Option<Mods> = None;
        while let Some(item) = self.peek() {
            let (span, line_level, kind) = (item.line.span, item.line.level, LineKind::of(item));
            if line_level < level {
                break;
            }
            if line_level > level {
                self.error(
                    Code::TooDeep,
                    span,
                    "this line is more than one step deeper than the line above it",
                );
                self.take();
                self.skip_under(line_level);
                continue;
            }
            match kind {
                LineKind::Branch => {
                    let branch = self.branch(level);
                    match place {
                        Place::Split if !nodes.is_empty() => self.error(Code::Place, span, MIXED),
                        Place::Split => branches.push(branch),
                        Place::Top | Place::Inserts => {
                            self.error(
                                Code::Place,
                                span,
                                "a `|` branch goes under a split, one step in",
                            );
                        }
                        Place::Branch => {
                            self.error(
                                Code::Place,
                                span,
                                "a `|` branch goes under a split, not under another branch",
                            );
                        }
                    }
                }
                LineKind::Mods => {
                    let block = self.mods(level);
                    if place == Place::Branch {
                        let message =
                            "`mods` goes under a split or at the top level, not under a branch";
                        self.error(Code::Place, span, message);
                    } else if mods.is_some() {
                        self.error(
                            Code::Place,
                            span,
                            "a split has one `mods` block: put each modulator in the first one",
                        );
                    } else {
                        mods = Some(block);
                    }
                }
                LineKind::Checks => {
                    let block = self.checks(level);
                    if place != Place::Top {
                        self.error(Code::Place, span, "`checks` goes at the top level only");
                    } else if checks.is_some() {
                        self.error(Code::Place, span, "a chain has one `checks` block");
                    } else {
                        *checks = Some(block);
                    }
                }
                LineKind::Header => {
                    self.error(
                        Code::Place,
                        span,
                        "the header `chain 2` comes once, on the first line",
                    );
                    self.take();
                    self.skip_under(level);
                }
                LineKind::Wire => {
                    let message = "a wire goes at the top level of a text of version 2, not in a chain of inserts";
                    self.error(Code::Place, span, message);
                    self.take();
                    self.skip_under(level);
                }
                LineKind::Node => {
                    if let Some(node) = self.node(level) {
                        if branches.is_empty() {
                            nodes.push(node);
                        } else {
                            self.error(Code::Place, span, MIXED);
                        }
                    }
                }
            }
        }
        let content = if branches.is_empty() {
            Content::Nodes(nodes)
        } else {
            Content::Branches(branches)
        };
        Body { content, mods }
    }

    /// A node and the lines under it. A line with no kind gives `None`: its
    /// diagnostic is in place, and the lines under it are read and dropped
    /// with it, so that they give no second error.
    fn node(&mut self, level: usize) -> Option<Node> {
        let item = self.take();
        let mut tokens = Cursor::new(&item.line.tokens, item.line.span);
        let kind = tokens.kind(&mut self.diagnostics);
        let id = tokens.id();
        let name = tokens.name();
        let fields = tokens.fields(&mut self.diagnostics, false);
        let body = self.body(level + 1, Place::Split, &mut None);
        Some(Node {
            kind: kind?,
            id,
            name,
            fields,
            body,
            trivia: item.trivia,
        })
    }

    fn branch(&mut self, level: usize) -> Branch {
        let item = self.take();
        let mut tokens = Cursor::new(&item.line.tokens[1..], item.line.span);
        let name = tokens.branch_name();
        let id = tokens.id();
        let fields = tokens.fields(&mut self.diagnostics, false);
        let nodes = match self.body(level + 1, Place::Branch, &mut None).content {
            Content::Nodes(nodes) => nodes,
            Content::Branches(_) => Vec::new(),
        };
        Branch {
            name,
            id,
            fields,
            nodes,
            trivia: item.trivia,
        }
    }

    fn mods(&mut self, level: usize) -> Mods {
        let head = self.take();
        let mut modulators = Vec::new();
        while self.peek().is_some_and(|item| item.line.level > level) {
            let item = self.take();
            if item.line.level > level + 1 {
                self.error(
                    Code::TooDeep,
                    item.line.span,
                    "a modulator has no lines under it",
                );
                continue;
            }
            let mut tokens = Cursor::new(&item.line.tokens, item.line.span);
            let kind = tokens.kind(&mut self.diagnostics);
            let id = tokens.id();
            let name = tokens.name();
            let fields = tokens.fields(&mut self.diagnostics, true);
            let links = tokens.links(&mut self.diagnostics);
            if let Some(kind) = kind {
                modulators.push(Modulator {
                    kind,
                    id,
                    name,
                    fields,
                    links,
                    trivia: item.trivia,
                });
            }
        }
        Mods {
            modulators,
            trivia: head.trivia,
        }
    }

    fn checks(&mut self, level: usize) -> Checks {
        let head = self.take();
        let mut lines = Vec::new();
        while self.peek().is_some_and(|item| item.line.level > level) {
            let item = self.take();
            if item.line.level > level + 1 {
                self.error(
                    Code::TooDeep,
                    item.line.span,
                    "a check has no lines under it",
                );
                continue;
            }
            let mut tokens = Cursor::new(&item.line.tokens, item.line.span);
            if let Some(mut check) = tokens.check(&mut self.diagnostics) {
                check.trivia = item.trivia;
                lines.push(check);
            }
        }
        Checks {
            lines,
            trivia: head.trivia,
        }
    }

    /// The top level of a text of version 2: node lines with their
    /// inserts, wires, and one `checks` block.
    fn graph(&mut self, checks: &mut Option<Checks>) -> Vec<TopItem> {
        let mut items = Vec::new();
        while let Some(item) = self.peek() {
            let (span, level, kind) = (item.line.span, item.line.level, LineKind::of(item));
            let role = match item.first() {
                Some(Tok::Word(word)) => Role::from_word(word),
                _ => None,
            };
            if level > 0 {
                self.error(
                    Code::TooDeep,
                    span,
                    "this line is more than one step deeper than the line above it",
                );
                self.take();
                self.skip_under(level);
                continue;
            }
            let misplaced = match kind {
                LineKind::Wire => {
                    items.extend(self.wire().map(TopItem::Wire));
                    continue;
                }
                LineKind::Checks => {
                    let block = self.checks(0);
                    if checks.is_some() {
                        self.error(Code::Place, span, "a chain has one `checks` block");
                    } else {
                        *checks = Some(block);
                    }
                    continue;
                }
                LineKind::Node if role.is_some() => {
                    items.extend(
                        role.and_then(|role| self.graph_node(role))
                            .map(TopItem::Node),
                    );
                    continue;
                }
                LineKind::Header => {
                    "the header `chain 2` comes once, on the first line".to_string()
                }
                LineKind::Mods => {
                    "in version 2, `mods` goes under a strip, with the inserts that it changes"
                        .to_string()
                }
                LineKind::Branch => {
                    "a `|` branch goes under a split, in the inserts of a strip".to_string()
                }
                LineKind::Node => {
                    let roles: Vec<&str> = Role::ALL.iter().map(|role| role.as_str()).collect();
                    let first = self
                        .peek()
                        .and_then(Item::first)
                        .map_or_else(String::new, Tok::describe);
                    format!(
                        "the top level of version 2 holds node lines ({}) and wires; put {first} under a strip",
                        roles.join(", ")
                    )
                }
            };
            self.error(Code::Place, span, misplaced);
            self.take();
            self.skip_under(0);
        }
        items
    }

    /// `strip #1 "Name" key=value` and its inserts, or `producer kind #id`.
    fn graph_node(&mut self, role: Role) -> Option<GraphNode> {
        let item = self.take();
        let mut tokens = Cursor::new(&item.line.tokens[1..], item.line.span);
        let kind = match tokens.peek() {
            _ if !role.has_kind() => None,
            Some(Tok::Word(_) | Tok::Quoted(_) | Tok::Bad) => tokens.kind(&mut self.diagnostics),
            _ => {
                let span = tokens
                    .tokens
                    .get(tokens.at)
                    .map_or_else(|| tokens.end(), |token| token.span);
                let message = format!(
                    "`{0}` needs a kind of the host after it, such as `{0} render`",
                    role.as_str()
                );
                self.error(Code::Token, span, message);
                None
            }
        };
        let id = tokens.id();
        let name = tokens.name();
        let fields = tokens.fields(&mut self.diagnostics, false);
        let inserts = if role.holds_inserts() {
            self.body(1, Place::Inserts, &mut None)
        } else {
            self.nothing_under(role.as_str());
            Body::default()
        };
        if role.has_kind() && kind.is_none() {
            return None;
        }
        Some(GraphNode {
            role,
            kind,
            id,
            name,
            fields,
            inserts,
            trivia: item.trivia,
        })
    }

    /// An error for the lines under a line that holds none, and those lines left out.
    fn nothing_under(&mut self, what: &str) {
        if let Some(item) = self.items.next_if(|item| item.line.level > 0) {
            let message = format!("a `{what}` line holds no lines under it");
            self.error(Code::Place, item.line.span, message);
            self.skip_under(0);
        }
    }

    /// `from -> to` or `from => lane`.
    fn wire(&mut self) -> Option<Wire> {
        let item = self.take();
        self.nothing_under("wire");
        let tokens = &item.line.tokens;
        let from = self.end(&tokens[0]);
        let arrow = if tokens[1].tok == Tok::Store {
            Arrow::Store
        } else {
            Arrow::Live
        };
        let Some(token) = tokens.get(2) else {
            let end = Cursor::new(tokens, item.line.span).end();
            let message = format!(
                "`{}` needs an end after it, such as `#2`, \"Notes\" or @\"Part/Lane\"",
                arrow.as_str()
            );
            self.error(Code::Token, end, message);
            return None;
        };
        let to = self.end(token);
        if let Some(extra) = tokens.get(3) {
            let message = format!(
                "a wire joins two ends, one wire on each line; found {} after them",
                extra.tok.describe()
            );
            self.error(Code::Token, extra.span, message);
        }
        let (from, to) = (from?, to?);
        if arrow == Arrow::Store && matches!(to, End::Node { .. }) {
            let message =
                "`=>` stores in a lane: end it at a lane, such as \"Keys\", or at @\"Part/Lane\"";
            self.error(Code::Place, token.span, message);
            return None;
        }
        if arrow == Arrow::Live && matches!(to, End::Lane(_)) {
            let message = "a lane keeps what comes into it: a wire into a lane is `=>`, not `->`";
            self.error(Code::Place, tokens[1].span, message);
            return None;
        }
        if !matches!(from, End::Node { .. }) && !matches!(to, End::Node { .. }) {
            self.error(
                Code::Place,
                item.line.span,
                "a wire joins a node: one of its ends is `#id`",
            );
            return None;
        }
        Some(Wire {
            from,
            arrow,
            to,
            trivia: item.trivia,
        })
    }

    /// One end of a wire.
    fn end(&mut self, token: &Token) -> Option<End> {
        let end = match &token.tok {
            Tok::Id(id) => End::Node {
                id: id.clone(),
                port: None,
            },
            Tok::Target(id, port) => End::Node {
                id: id.clone(),
                port: Some(port.clone()),
            },
            Tok::Quoted(lane) => End::Lane(lane.clone()),
            Tok::Outside(path) => End::Outside(path.clone()),
            Tok::Bad => return None,
            Tok::Word(word) => {
                let message = format!("a lane is a quoted name: \"{word}\"");
                self.error(Code::Token, token.span, message);
                return None;
            }
            tok => {
                let message = format!(
                    "an end of a wire is `#id`, `#id.port`, a lane \"Name\" or @\"Part/Lane\", not {}",
                    tok.describe()
                );
                self.error(Code::Token, token.span, message);
                return None;
            }
        };
        Some(end)
    }
}

/// What a line is, by its first tokens.
enum LineKind {
    Node,
    Branch,
    Mods,
    Checks,
    Header,
    Wire,
}

impl LineKind {
    fn of(item: &Item) -> Self {
        let second = item.line.tokens.get(1).map(|token| &token.tok);
        if matches!(second, Some(Tok::Arrow | Tok::Store)) {
            Self::Wire
        } else if item.first() == Some(&Tok::Bar) {
            Self::Branch
        } else if item.is_keyword("mods") {
            Self::Mods
        } else if item.is_keyword("checks") {
            Self::Checks
        } else if item.first() == Some(&Tok::Word("chain".into())) && item.line.tokens.len() > 1 {
            Self::Header
        } else {
            Self::Node
        }
    }
}

const MIXED: &str = "a split holds `|` branches or nodes, not both: put these nodes in a branch";

/// The tokens of one line, read from the start.
struct Cursor<'t> {
    tokens: &'t [Token],
    at: usize,
    /// The line, for an error at its end.
    line: Span,
}

impl<'t> Cursor<'t> {
    fn new(tokens: &'t [Token], line: Span) -> Self {
        Self {
            tokens,
            at: 0,
            line,
        }
    }

    fn peek(&self) -> Option<&'t Tok> {
        self.tokens.get(self.at).map(|token| &token.tok)
    }

    fn next(&mut self) -> Option<Token> {
        let token = self.tokens.get(self.at).cloned();
        self.at += usize::from(token.is_some());
        token
    }

    /// The place just after the last token, for "this line needs more".
    fn end(&self) -> Span {
        let column = self.line.column + (self.line.end - self.line.start) as u32;
        Span {
            start: self.line.end,
            end: self.line.end,
            line: self.line.line,
            column,
        }
    }

    /// The kind that starts a node or a modulator line.
    fn kind(&mut self, diagnostics: &mut Vec<Diagnostic>) -> Option<String> {
        match self.next() {
            Some(Token {
                tok: Tok::Word(word) | Tok::Quoted(word),
                ..
            }) => Some(word),
            Some(Token { tok: Tok::Bad, .. }) | None => None,
            Some(token) => {
                let message = format!(
                    "a line starts with a kind, such as `compressor`, not {}",
                    token.tok.describe()
                );
                diagnostics.push(Diagnostic::new(Code::Token, token.span, message));
                None
            }
        }
    }

    fn id(&mut self) -> Option<String> {
        match self.peek() {
            Some(Tok::Id(id)) => {
                self.at += 1;
                Some(id.clone())
            }
            _ => None,
        }
    }

    /// The name of a node or a modulator: a quoted text that no `=`
    /// follows. A quote keeps it apart from the kind.
    fn name(&mut self) -> Option<String> {
        match (
            self.peek(),
            self.tokens.get(self.at + 1).map(|token| &token.tok),
        ) {
            (Some(Tok::Quoted(name)), next) if next != Some(&Tok::Equals) => {
                self.at += 1;
                Some(name.clone())
            }
            _ => None,
        }
    }

    /// The name of a branch: also a bare word that no `=` follows, as in `| Low`.
    fn branch_name(&mut self) -> Option<String> {
        match (
            self.peek(),
            self.tokens.get(self.at + 1).map(|token| &token.tok),
        ) {
            (Some(Tok::Word(name)), next) if next != Some(&Tok::Equals) => {
                self.at += 1;
                Some(name.clone())
            }
            _ => self.name(),
        }
    }

    /// `key=value` fields up to the end of the line, or up to `->` when
    /// `links` follow. A token that cannot start a field gives a diagnostic
    /// and is left out.
    fn fields(&mut self, diagnostics: &mut Vec<Diagnostic>, links: bool) -> Vec<Field> {
        let mut fields = Vec::new();
        while let Some(token) = self.next() {
            let key = match token.tok {
                Tok::Arrow if links => {
                    self.at -= 1;
                    break;
                }
                Tok::Arrow => {
                    let message = "`->` links go on a modulator, in a `mods` block";
                    diagnostics.push(Diagnostic::new(Code::Place, token.span, message));
                    self.at = self.tokens.len();
                    break;
                }
                Tok::Word(key) | Tok::Quoted(key) => key,
                Tok::Bad => continue,
                Tok::Id(_) => {
                    diagnostics.push(Diagnostic::new(
                        Code::Token,
                        token.span,
                        "the `#id` comes just after the kind",
                    ));
                    continue;
                }
                tok => {
                    let message = format!("expected `key=value`, found {}", tok.describe());
                    diagnostics.push(Diagnostic::new(Code::Token, token.span, message));
                    continue;
                }
            };
            if self.peek() != Some(&Tok::Equals) {
                let message = format!("`{key}` needs `=` and a value, such as `{key}=1`");
                diagnostics.push(Diagnostic::new(Code::Token, token.span, message));
                continue;
            }
            self.at += 1;
            if let Some(value) = self.value(diagnostics, true) {
                fields.push(Field {
                    key,
                    value,
                    span: Spanned(token.span),
                });
            }
        }
        fields
    }

    /// One value, or a list of values with commas between them when `list`.
    fn value(&mut self, diagnostics: &mut Vec<Diagnostic>, list: bool) -> Option<Value> {
        let first = self.single(diagnostics)?;
        if !list || self.peek() != Some(&Tok::Comma) {
            return Some(first);
        }
        let mut values = vec![first];
        while self.peek() == Some(&Tok::Comma) {
            self.at += 1;
            values.push(self.single(diagnostics)?);
        }
        Some(Value::List(values))
    }

    fn single(&mut self, diagnostics: &mut Vec<Diagnostic>) -> Option<Value> {
        let Some(token) = self.next() else {
            diagnostics.push(Diagnostic::new(
                Code::Token,
                self.end(),
                "a value is missing at the end of the line",
            ));
            return None;
        };
        match token.tok {
            Tok::Number { number, .. } => Some(Value::Number(number)),
            Tok::Note(note) => Some(Value::Note(note)),
            Tok::Word(text) | Tok::Quoted(text) => Some(Value::Text(text)),
            Tok::Ref(id) if id == "in" => Some(Value::Reference(Reference::Input)),
            Tok::Ref(id) => Some(Value::Reference(Reference::Node(id))),
            Tok::Outside(path) => Some(Value::Reference(Reference::Outside(path))),
            Tok::Bad => None,
            tok => {
                let message = format!("expected a value, found {}", tok.describe());
                diagnostics.push(Diagnostic::new(Code::Token, token.span, message));
                None
            }
        }
    }

    /// `-> #id.key depth, #id.key depth`, after the fields of a modulator.
    fn links(&mut self, diagnostics: &mut Vec<Diagnostic>) -> Vec<Link> {
        let mut links = Vec::new();
        if self.next().is_none() {
            return links;
        }
        loop {
            match self.next() {
                Some(Token {
                    tok: Tok::Target(target, key),
                    span,
                }) => {
                    let Some(depth) = self.value(diagnostics, false) else {
                        break;
                    };
                    links.push(Link {
                        target,
                        key,
                        depth,
                        span: Spanned(span),
                    });
                }
                Some(Token { tok: Tok::Bad, .. }) => break,
                Some(token) => {
                    let message = format!(
                        "expected a parameter such as `#7.mix`, found {}",
                        token.tok.describe()
                    );
                    diagnostics.push(Diagnostic::new(Code::Token, token.span, message));
                    break;
                }
                None => {
                    diagnostics.push(Diagnostic::new(
                        Code::Token,
                        self.end(),
                        "`->` needs a parameter, such as `#7.mix +10%`",
                    ));
                    break;
                }
            }
            match self.next() {
                None => break,
                Some(Token {
                    tok: Tok::Comma, ..
                }) => {}
                Some(token) => {
                    let message = format!(
                        "expected `,` before the next link, found {}",
                        token.tok.describe()
                    );
                    diagnostics.push(Diagnostic::new(Code::Token, token.span, message));
                    break;
                }
            }
        }
        links
    }

    /// `subject... compare expected [+- tolerance]`.
    fn check(&mut self, diagnostics: &mut Vec<Diagnostic>) -> Option<Check> {
        let mut subject = Vec::new();
        let compare = loop {
            match self.peek() {
                Some(Tok::Compare(compare)) => {
                    self.at += 1;
                    break *compare;
                }
                Some(Tok::Equals) => {
                    self.at += 1;
                    break crate::tree::Compare::Equal;
                }
                Some(_) => subject.push(self.single(diagnostics)?),
                None => {
                    let message =
                        "a check compares a measure with a value, such as `latency <= 6ms`";
                    diagnostics.push(Diagnostic::new(Code::Token, self.line, message));
                    return None;
                }
            }
        };
        let expected = self.single(diagnostics)?;
        let tolerance = match self.next() {
            None => None,
            Some(Token {
                tok: Tok::PlusMinus,
                ..
            }) => Some(self.single(diagnostics)?),
            Some(token) => {
                let message = format!(
                    "expected `+-` or the end of the check, found {}",
                    token.tok.describe()
                );
                diagnostics.push(Diagnostic::new(Code::Token, token.span, message));
                return None;
            }
        };
        if subject.is_empty() {
            diagnostics.push(Diagnostic::new(
                Code::Token,
                self.line,
                "a check names what it measures before the comparison",
            ));
            return None;
        }
        Some(Check {
            subject,
            compare,
            expected,
            tolerance,
            trivia: Trivia::default(),
        })
    }
}
