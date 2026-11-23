//! The parser: the lines of a text into a [`Document`].
//!
//! The parser never stops at an error. A line that does not parse gives a
//! diagnostic and is left out of the tree, and the parser goes on with the
//! next line. A token that does not parse is left out of its line. So one
//! pass finds every error of the text.

use crate::diagnostic::{Code, Diagnostic, Span};
use crate::lex::{self, Line, Tok, Token};
use crate::tree::{
    Body, Branch, Check, Checks, Content, Document, Field, Header, Link, Mods, Modulator, Node, Spanned, Trivia,
    VERSION,
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
    let mut parser = Parser { items, at: 0, diagnostics };
    let mut document = Document { header: parser.header(), end, ..Document::default() };
    document.root = parser.body(0, Place::Top, &mut document.checks);
    let mut diagnostics = parser.diagnostics;
    diagnostics.sort_by_key(|diagnostic| (diagnostic.span.start, diagnostic.span.end));
    Parsed { document, diagnostics }
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
        let trivia = Trivia { span: line.span, trailing: line.comment.clone(), ..std::mem::take(&mut pending) };
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
    /// The top level of the chain: nodes, `mods` and `checks`.
    Top,
    /// Under a split: nodes or branches, and `mods`.
    Split,
    /// Under a `|` line: nodes only.
    Branch,
}

struct Parser {
    items: Vec<Item>,
    at: usize,
    diagnostics: Vec<Diagnostic>,
}

impl Parser {
    fn peek(&self) -> Option<&Item> {
        self.items.get(self.at)
    }

    fn error(&mut self, code: Code, span: Span, message: impl Into<String>) {
        self.diagnostics.push(Diagnostic::new(code, span, message));
    }

    /// Takes the next item, which the caller has seen with `peek`.
    fn take(&mut self) -> Item {
        let item = std::mem::replace(
            &mut self.items[self.at],
            Item { line: Line { level: 0, tokens: Vec::new(), comment: None, span: Span::default() }, trivia: Trivia::default() },
        );
        self.at += 1;
        item
    }

    /// Leaves out the lines deeper than `level`, after a line that has an
    /// error: the lines under a bad line cannot be placed.
    fn skip_under(&mut self, level: usize) {
        while self.peek().is_some_and(|item| item.line.level > level) {
            self.at += 1;
        }
    }

    /// The header, `chain 1`, when the first line is one. Else the default
    /// header and a diagnostic.
    fn header(&mut self) -> Header {
        let Some(item) = self.peek() else {
            let span = Span { line: 1, column: 1, ..Span::default() };
            self.error(Code::MissingHeader, span, "the text is empty: a chain starts with the line `chain 1`");
            return Header::default();
        };
        if item.first() != Some(&Tok::Word("chain".into())) {
            let span = item.line.span;
            self.error(Code::MissingHeader, span, "a chain starts with the line `chain 1`");
            return Header::default();
        }
        let item = self.take();
        let mut tokens = Cursor::new(&item.line.tokens[1..], item.line.span);
        let version = match tokens.next() {
            Some(Token { tok: Tok::Number { number, signed: false }, span })
                if number.dimension.is_none() && number.value.fract() == 0.0 =>
            {
                if number.value != f64::from(VERSION) {
                    let message = format!(
                        "this text is in version {} of the language; this reader knows version {VERSION}",
                        number.value
                    );
                    self.error(Code::Version, span, message);
                }
                VERSION
            }
            _ => {
                self.error(Code::MissingHeader, item.line.span, "`chain` needs the version of the language: `chain 1`");
                VERSION
            }
        };
        let name = tokens.name();
        let fields = tokens.fields(&mut self.diagnostics, false);
        Header { version, name, fields, trivia: item.trivia }
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
                self.error(Code::TooDeep, span, "this line is more than one step deeper than the line above it");
                self.at += 1;
                self.skip_under(line_level);
                continue;
            }
            match kind {
                LineKind::Branch => {
                    let branch = self.branch(level);
                    match place {
                        Place::Split if !nodes.is_empty() => self.error(Code::Place, span, MIXED),
                        Place::Split => branches.push(branch),
                        Place::Top => self.error(Code::Place, span, "a `|` branch goes under a split, one step in"),
                        Place::Branch => {
                            self.error(Code::Place, span, "a `|` branch goes under a split, not under another branch");
                        }
                    }
                }
                LineKind::Mods => {
                    let block = self.mods(level);
                    if place == Place::Branch {
                        let message = "`mods` goes under a split or at the top level, not under a branch";
                        self.error(Code::Place, span, message);
                    } else if mods.is_some() {
                        self.error(Code::Place, span, "a split has one `mods` block: put each modulator in the first one");
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
                    self.error(Code::Place, span, "the header `chain 1` comes once, on the first line");
                    self.at += 1;
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
        let content = if branches.is_empty() { Content::Nodes(nodes) } else { Content::Branches(branches) };
        Body { content, mods }
    }

    fn node(&mut self, level: usize) -> Option<Node> {
        let item = self.take();
        let mut tokens = Cursor::new(&item.line.tokens, item.line.span);
        let kind = tokens.kind(&mut self.diagnostics);
        let id = tokens.id();
        let name = tokens.name();
        let fields = tokens.fields(&mut self.diagnostics, false);
        let body = self.body(level + 1, Place::Split, &mut None);
        Some(Node { kind: kind?, id, name, fields, body, trivia: item.trivia })
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
        Branch { name, id, fields, nodes, trivia: item.trivia }
    }

    fn mods(&mut self, level: usize) -> Mods {
        let head = self.take();
        let mut modulators = Vec::new();
        while self.peek().is_some_and(|item| item.line.level > level) {
            let item = self.take();
            if item.line.level > level + 1 {
                self.error(Code::TooDeep, item.line.span, "a modulator has no lines under it");
                continue;
            }
            let mut tokens = Cursor::new(&item.line.tokens, item.line.span);
            let kind = tokens.kind(&mut self.diagnostics);
            let id = tokens.id();
            let name = tokens.name();
            let fields = tokens.fields(&mut self.diagnostics, true);
            let links = tokens.links(&mut self.diagnostics);
            if let Some(kind) = kind {
                modulators.push(Modulator { kind, id, name, fields, links, trivia: item.trivia });
            }
        }
        Mods { modulators, trivia: head.trivia }
    }

    fn checks(&mut self, level: usize) -> Checks {
        let head = self.take();
        let mut lines = Vec::new();
        while self.peek().is_some_and(|item| item.line.level > level) {
            let item = self.take();
            if item.line.level > level + 1 {
                self.error(Code::TooDeep, item.line.span, "a check has no lines under it");
                continue;
            }
            let mut tokens = Cursor::new(&item.line.tokens, item.line.span);
            if let Some(mut check) = tokens.check(&mut self.diagnostics) {
                check.trivia = item.trivia;
                lines.push(check);
            }
        }
        Checks { lines, trivia: head.trivia }
    }
}

/// What a line is, by its first tokens.
enum LineKind {
    Node,
    Branch,
    Mods,
    Checks,
    Header,
}

impl LineKind {
    fn of(item: &Item) -> Self {
        if item.first() == Some(&Tok::Bar) {
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
        Self { tokens, at: 0, line }
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
        Span { start: self.line.end, end: self.line.end, line: self.line.line, column }
    }

    /// The kind that starts a node or a modulator line.
    fn kind(&mut self, diagnostics: &mut Vec<Diagnostic>) -> Option<String> {
        match self.next() {
            Some(Token { tok: Tok::Word(word) | Tok::Quoted(word), .. }) => Some(word),
            Some(Token { tok: Tok::Bad, .. }) | None => None,
            Some(token) => {
                let message = format!("a line starts with a kind, such as `compressor`, not {}", token.tok.describe());
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
        match (self.peek(), self.tokens.get(self.at + 1).map(|token| &token.tok)) {
            (Some(Tok::Quoted(name)), next) if next != Some(&Tok::Equals) => {
                self.at += 1;
                Some(name.clone())
            }
            _ => None,
        }
    }

    /// The name of a branch: also a bare word that no `=` follows, as in `| Low`.
    fn branch_name(&mut self) -> Option<String> {
        match (self.peek(), self.tokens.get(self.at + 1).map(|token| &token.tok)) {
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
                    diagnostics.push(Diagnostic::new(Code::Token, token.span, "the `#id` comes just after the kind"));
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
                fields.push(Field { key, value, span: Spanned(token.span) });
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
            diagnostics.push(Diagnostic::new(Code::Token, self.end(), "a value is missing at the end of the line"));
            return None;
        };
        match token.tok {
            Tok::Number { number, .. } => Some(Value::Number(number)),
            Tok::Note(note) => Some(Value::Note(note)),
            Tok::Word(text) | Tok::Quoted(text) => Some(Value::Text(text)),
            Tok::Ref(id) if id == "in" => Some(Value::Reference(Reference::Input)),
            Tok::Ref(id) => Some(Value::Reference(Reference::Node(id))),
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
                Some(Token { tok: Tok::Target(target, key), span }) => {
                    let Some(depth) = self.value(diagnostics, false) else { break };
                    links.push(Link { target, key, depth, span: Spanned(span) });
                }
                Some(Token { tok: Tok::Bad, .. }) => break,
                Some(token) => {
                    let message = format!("expected a parameter such as `#7.mix`, found {}", token.tok.describe());
                    diagnostics.push(Diagnostic::new(Code::Token, token.span, message));
                    break;
                }
                None => {
                    diagnostics.push(Diagnostic::new(Code::Token, self.end(), "`->` needs a parameter, such as `#7.mix +10%`"));
                    break;
                }
            }
            match self.next() {
                None => break,
                Some(Token { tok: Tok::Comma, .. }) => {}
                Some(token) => {
                    let message = format!("expected `,` before the next link, found {}", token.tok.describe());
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
                    let message = "a check compares a measure with a value, such as `latency <= 6ms`";
                    diagnostics.push(Diagnostic::new(Code::Token, self.line, message));
                    return None;
                }
            }
        };
        let expected = self.single(diagnostics)?;
        let tolerance = match self.next() {
            None => None,
            Some(Token { tok: Tok::PlusMinus, .. }) => Some(self.single(diagnostics)?),
            Some(token) => {
                let message = format!("expected `+-` or the end of the check, found {}", token.tok.describe());
                diagnostics.push(Diagnostic::new(Code::Token, token.span, message));
                return None;
            }
        };
        if subject.is_empty() {
            diagnostics.push(Diagnostic::new(Code::Token, self.line, "a check names what it measures before the comparison"));
            return None;
        }
        Some(Check { subject, compare, expected, tolerance, trivia: Trivia::default() })
    }
}
