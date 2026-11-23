//! What an editor asks about a place in a chain text: the words that can
//! go there (completion), what a word means (hover) and where an id is
//! defined (definition).
//!
//! These functions read only the lines around the place, with the lexer,
//! and not the tree: a text that a person types is often not complete, and
//! the parser leaves a bad line out of the tree. All that they know of the
//! kinds and their parameters comes from the schema of the host.
//!
//! A place is a byte offset in the text. An offset at the end of a word is
//! in that word, so that a completion continues the word that is typed.

use crate::diagnostic::Span;
use crate::lex::{self, Line, Tok, Token};
use crate::schema::{Param, ParamValue, Schema};

/// What a completion offers.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum CompletionKind {
    Device,
    Split,
    Modulator,
    Parameter,
    /// A value of a parameter: a choice, `on` or `off`.
    Value,
}

/// A word that can go at a place of the text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Completion {
    /// The word as the text writes it, quoted when it must be.
    pub label: String,
    /// The text that replaces `span`: the label, and `=` after a key that
    /// has none yet.
    pub insert: String,
    /// What the word is, for people: the name and the type of a kind or a
    /// parameter.
    pub detail: String,
    pub kind: CompletionKind,
    /// The part of the text that the completion replaces: the word at the
    /// place, or an empty span at the place.
    pub span: Span,
}

/// What the word at a place means.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Hover {
    /// The word.
    pub span: Span,
    /// The text to show, one line of plain text for each item.
    pub lines: Vec<String>,
}

/// The words that can go at `offset` of `text`: the kinds of the schema at
/// the start of a line, the parameters of the kind of the line after it,
/// and the choices of a parameter after its `=`. Empty where the schema
/// gives no word (a header, a check, a link, a number).
pub fn complete(text: &str, offset: usize, schema: &Schema) -> Vec<Completion> {
    let lines = Lines::new(text);
    let Some(index) = lines.index_of(offset) else {
        return Vec::new();
    };
    let line = lines.lex(index);
    let role = lines.role(index, &line, offset);
    let before: Vec<&Token> = line
        .tokens
        .iter()
        .filter(|token| token.span.start < offset)
        .collect();
    // The token at the place: a word that the completion replaces. In a
    // number, an id, a reference or a bad token, nothing can be completed.
    // After a sign such as `=`, the completion starts a new word.
    let word = match before.last() {
        Some(token) if token.span.end >= offset && is_word_like(&token.tok) => Some(*token),
        Some(token) if token.span.end >= offset && !is_sign(&token.tok) => return Vec::new(),
        _ => None,
    };
    let span = word.map_or_else(|| lines.span_at(index, offset), |token| token.span);
    let prefix = word.map_or("", |token| &text[token.span.start..offset]);
    // The tokens before the word at the place.
    let earlier = &before[..before.len() - usize::from(word.is_some())];
    if earlier.is_empty() {
        return kinds(role, schema, prefix, span);
    }
    if earlier.iter().any(|token| token.tok == Tok::Arrow) {
        // A link of a modulator: a target, not a field.
        return Vec::new();
    }
    let Some(params) = role.params(schema) else {
        return Vec::new();
    };
    if let [.., key, last] = earlier
        && last.tok == Tok::Equals
    {
        let Some(param) =
            key_of(&key.tok).and_then(|key| params.iter().find(|param| param.key == key))
        else {
            return Vec::new();
        };
        return values(param, prefix, span);
    }
    let has_equals = line
        .tokens
        .iter()
        .any(|token| token.span.start == span.end && token.tok == Tok::Equals);
    let taken = keys_on(&line, word);
    params
        .iter()
        .filter(|param| !taken.contains(&param.key.as_str()) && matches(&param.key, prefix))
        .map(|param| {
            let label = written(&param.key);
            let insert = if has_equals {
                label.clone()
            } else {
                format!("{label}=")
            };
            Completion {
                label,
                insert,
                detail: describe(param),
                kind: CompletionKind::Parameter,
                span,
            }
        })
        .collect()
}

/// What the word at `offset` of `text` means: a kind, a parameter (its
/// key before `=`, or `#id.key` in a link) or a reference `@id`. None for
/// another word, or a word that the schema does not know.
pub fn hover(text: &str, offset: usize, schema: &Schema) -> Option<Hover> {
    let lines = Lines::new(text);
    let index = lines.index_of(offset)?;
    let line = lines.lex(index);
    let role = lines.role(index, &line, offset);
    let at = token_at(&line, offset)?;
    let token = &line.tokens[at];
    let lines_of = |lines: Vec<String>| {
        Some(Hover {
            span: token.span,
            lines,
        })
    };
    match &token.tok {
        Tok::Word(kind) if at == 0 => lines_of(about_kind(role, kind, schema)?),
        Tok::Word(key) | Tok::Quoted(key)
            if line
                .tokens
                .get(at + 1)
                .is_some_and(|next| next.tok == Tok::Equals) =>
        {
            let param = role
                .params(schema)?
                .iter()
                .find(|param| &param.key == key)?;
            lines_of(about_param(param))
        }
        Tok::Target(id, key) => {
            let kind = lines.kind_of_id(id)?;
            let param = node_params(schema, &kind)?
                .iter()
                .find(|param| &param.key == key)?;
            lines_of(about_param(param))
        }
        Tok::Ref(id) if id == "in" => {
            lines_of(vec!["`@in`: the signal that comes into the chain".into()])
        }
        Tok::Ref(id) => {
            let kind = lines.kind_of_id(id)?;
            lines_of(vec![format!("`@{id}`: the output of `{kind}` #{id}")])
        }
        _ => None,
    }
}

/// Where the id that the word at `offset` names is defined: the `#id` of
/// a node, a branch or a modulator, for a reference `@id` or a link target
/// `#id.key`. None for another word, for `@in`, or for an id that no line
/// defines.
pub fn definition(text: &str, offset: usize) -> Option<Span> {
    let lines = Lines::new(text);
    let index = lines.index_of(offset)?;
    let line = lines.lex(index);
    let token = &line.tokens[token_at(&line, offset)?];
    let id = match &token.tok {
        Tok::Ref(id) if id != "in" => id,
        Tok::Target(id, _) => id,
        _ => return None,
    };
    lines.defined(id).map(|token| token.span)
}

/// The lines of a text, each with the byte where it starts.
struct Lines<'t> {
    text: &'t str,
    starts: Vec<usize>,
}

impl<'t> Lines<'t> {
    fn new(text: &'t str) -> Self {
        let starts = std::iter::once(0)
            .chain(text.match_indices('\n').map(|(at, _)| at + 1))
            .collect();
        Self { text, starts }
    }

    /// The line of a byte offset. An offset past the end is in no line.
    fn index_of(&self, offset: usize) -> Option<usize> {
        if offset > self.text.len() {
            return None;
        }
        Some(self.starts.partition_point(|&start| start <= offset) - 1)
    }

    /// The text of line `index`, without its line break.
    fn content(&self, index: usize) -> &'t str {
        let start = self.starts[index];
        let end = self
            .starts
            .get(index + 1)
            .map_or(self.text.len(), |next| next - 1);
        let raw = &self.text[start..end];
        raw.strip_suffix('\r').unwrap_or(raw)
    }

    fn lex(&self, index: usize) -> Line {
        // The diagnostics of the line are the parser's job, not this one's.
        lex::line(
            self.content(index),
            self.starts[index],
            index as u32 + 1,
            &mut Vec::new(),
        )
    }

    /// An empty span at `offset` of line `index`, with its line and column.
    fn span_at(&self, index: usize, offset: usize) -> Span {
        let start = self.starts[index];
        let column = self.text[start..offset].chars().count() as u32 + 1;
        Span {
            start: offset,
            end: offset,
            line: index as u32 + 1,
            column,
        }
    }

    /// The level of line `index`. On a line with no token, the level of
    /// the place: a person who types a new line has typed its indent.
    fn level(&self, index: usize, line: &Line, offset: usize) -> usize {
        if !line.tokens.is_empty() {
            return line.level;
        }
        let start = self.starts[index];
        let typed = &self.text[start..offset.max(start)];
        (typed.len() - typed.trim_start_matches(' ').len()) / 2
    }

    /// The nearest line before line `index` with a token and a level less
    /// than `level`: the line that this line goes under.
    fn parent(&self, index: usize, level: usize) -> Option<(usize, Line)> {
        (0..index)
            .rev()
            .map(|at| (at, self.lex(at)))
            .find(|(_, line)| !line.tokens.is_empty() && line.level < level)
    }

    /// What line `index` is, from its first token and the line it goes under.
    fn role(&self, index: usize, line: &Line, offset: usize) -> Role {
        let level = self.level(index, line, offset);
        let first = line.tokens.first().map(|token| &token.tok);
        // The first line with a token is the header.
        if self.parent(index, usize::MAX).is_none() {
            return Role::Header;
        }
        if matches!(first, Some(Tok::Word(word)) if (word == "mods" || word == "checks") && line.tokens.len() == 1)
        {
            return Role::Keyword;
        }
        let parent = if level == 0 {
            None
        } else {
            self.parent(index, level)
        };
        let parent_word = parent.as_ref().and_then(|(_, line)| {
            match line.tokens.first().map(|token| &token.tok) {
                Some(Tok::Word(word)) => Some(word.clone()),
                _ => None,
            }
        });
        match (first, parent_word.as_deref()) {
            (_, Some("mods")) => Role::Modulator(kind_word(line)),
            (_, Some("checks")) => Role::Other,
            (Some(Tok::Bar), Some(split)) => Role::Branch(split.to_string()),
            (Some(Tok::Bar), None) => Role::Other,
            _ => Role::Node(kind_word(line)),
        }
    }

    /// The token `#id` that defines `id`, on the first line that has one.
    fn defined(&self, id: &str) -> Option<Token> {
        (0..self.starts.len()).find_map(|index| {
            self.lex(index)
                .tokens
                .into_iter()
                .find(|token| matches!(&token.tok, Tok::Id(found) if found == id))
        })
    }

    /// The kind of the node or modulator that `#id` defines.
    fn kind_of_id(&self, id: &str) -> Option<String> {
        (0..self.starts.len()).find_map(|index| {
            let line = self.lex(index);
            let defines = line
                .tokens
                .iter()
                .any(|token| matches!(&token.tok, Tok::Id(found) if found == id));
            defines.then(|| kind_word(&line)).flatten()
        })
    }
}

/// What a line is, which decides the words that can go on it.
enum Role {
    /// The first line, `chain 1`: its fields are the host's.
    Header,
    /// `mods` or `checks`.
    Keyword,
    /// A device or a split, with its kind when the line has one yet.
    Node(Option<String>),
    /// A modulator under `mods`.
    Modulator(Option<String>),
    /// A `|` line under the split of this kind.
    Branch(String),
    /// A line of the `checks` block, or a line that cannot be placed.
    Other,
}

impl Role {
    /// The parameters that the fields of the line can name.
    fn params<'s>(&self, schema: &'s Schema) -> Option<&'s [Param]> {
        match self {
            Self::Node(Some(kind)) => node_params(schema, kind),
            Self::Modulator(Some(kind)) => {
                schema.modulator(kind).map(|kind| kind.params.as_slice())
            }
            Self::Branch(split) => schema
                .split(split)
                .map(|split| split.branch_params.as_slice()),
            _ => None,
        }
    }
}

/// The parameters of a node of `kind`: those of a split, else of a device.
fn node_params<'s>(schema: &'s Schema, kind: &str) -> Option<&'s [Param]> {
    match schema.split(kind) {
        Some(split) => Some(&split.params),
        None => schema.device(kind).map(|device| device.params.as_slice()),
    }
}

/// The index of the token at `offset` of a line: the token that holds it,
/// or the token that ends at it.
fn token_at(line: &Line, offset: usize) -> Option<usize> {
    line.tokens
        .iter()
        .position(|token| token.span.start <= offset && offset <= token.span.end)
}

/// The kind that a node or modulator line starts with.
fn kind_word(line: &Line) -> Option<String> {
    match line.tokens.first().map(|token| &token.tok) {
        Some(Tok::Word(word)) => Some(word.clone()),
        _ => None,
    }
}

/// A token that a completion can continue.
fn is_word_like(tok: &Tok) -> bool {
    matches!(tok, Tok::Word(_) | Tok::Quoted(_))
}

/// A token that ends a word, after which a new word starts.
fn is_sign(tok: &Tok) -> bool {
    matches!(
        tok,
        Tok::Equals | Tok::Comma | Tok::Bar | Tok::Arrow | Tok::Compare(_) | Tok::PlusMinus
    )
}

/// The key that a field token names.
fn key_of(tok: &Tok) -> Option<&str> {
    match tok {
        Tok::Word(key) | Tok::Quoted(key) => Some(key),
        _ => None,
    }
}

/// The keys that the fields of a line name, but for the word at the place.
fn keys_on<'l>(line: &'l Line, word: Option<&Token>) -> Vec<&'l str> {
    line.tokens
        .windows(2)
        .filter(|pair| {
            pair[1].tok == Tok::Equals && word.is_none_or(|word| word.span != pair[0].span)
        })
        .filter_map(|pair| key_of(&pair[0].tok))
        .collect()
}

/// Whether a word that the schema gives continues the typed `prefix`. A
/// quote that the person typed is not part of the word.
fn matches(word: &str, prefix: &str) -> bool {
    word.starts_with(prefix.trim_start_matches('"'))
}

/// A key or a choice as the text writes it: a bare word, or quoted.
fn written(word: &str) -> String {
    if lex::is_word(word) {
        word.to_string()
    } else {
        format!("\"{}\"", word.replace('\\', "\\\\").replace('"', "\\\""))
    }
}

/// The kinds that can start a line of this role.
fn kinds(role: Role, schema: &Schema, prefix: &str, span: Span) -> Vec<Completion> {
    let offer = |kind: &str, name: &str, detail: String, of: CompletionKind| {
        matches(kind, prefix).then(|| Completion {
            label: kind.to_string(),
            insert: kind.to_string(),
            detail: if name.is_empty() {
                detail
            } else {
                format!("{name}: {detail}")
            },
            kind: of,
            span,
        })
    };
    match role {
        Role::Node(_) => schema
            .devices
            .iter()
            .filter_map(|device| {
                offer(
                    &device.kind,
                    &device.name,
                    "device".into(),
                    CompletionKind::Device,
                )
            })
            .chain(schema.splits.iter().filter_map(|split| {
                let detail = format!(
                    "split of {} to {} branches",
                    split.branches.min, split.branches.max
                );
                offer(&split.kind, &split.name, detail, CompletionKind::Split)
            }))
            .collect(),
        Role::Modulator(_) => schema
            .modulators
            .iter()
            .filter_map(|kind| {
                offer(
                    &kind.kind,
                    &kind.name,
                    "modulator".into(),
                    CompletionKind::Modulator,
                )
            })
            .collect(),
        _ => Vec::new(),
    }
}

/// The values that a parameter offers after its `=`: its choices, or `on`
/// and `off`. A number, a note or a text has none.
fn values(param: &Param, prefix: &str, span: Span) -> Vec<Completion> {
    let words: Vec<&str> = match &param.value {
        ParamValue::Choice { choices, .. } => choices.iter().map(String::as_str).collect(),
        ParamValue::Switch { .. } => vec!["on", "off"],
        _ => Vec::new(),
    };
    words
        .into_iter()
        .filter(|word| matches(word, prefix))
        .map(|word| Completion {
            label: written(word),
            insert: written(word),
            detail: format!("a value of `{}`", param.key),
            kind: CompletionKind::Value,
            span,
        })
        .collect()
}

/// What a kind is, and its parameters.
fn about_kind(role: Role, kind: &str, schema: &Schema) -> Option<Vec<String>> {
    let (what, name, params) = match role {
        Role::Node(_) => match schema.split(kind) {
            Some(split) => {
                let what = format!(
                    "a split of {} to {} branches",
                    split.branches.min, split.branches.max
                );
                (what, &split.name, &split.params)
            }
            None => {
                let device = schema.device(kind)?;
                ("a device".to_string(), &device.name, &device.params)
            }
        },
        Role::Modulator(_) => {
            let modulator = schema.modulator(kind)?;
            (
                "a modulator".to_string(),
                &modulator.name,
                &modulator.params,
            )
        }
        _ => return None,
    };
    let title = if name.is_empty() {
        format!("`{kind}`: {what}")
    } else {
        format!("`{kind}` ({name}): {what}")
    };
    Some(
        std::iter::once(title)
            .chain(
                params
                    .iter()
                    .map(|param| format!("{}: {}", written(&param.key), describe(param))),
            )
            .collect(),
    )
}

/// What a parameter takes, in one line and then its name.
fn about_param(param: &Param) -> Vec<String> {
    let title = if param.name.is_empty() {
        format!("`{}`", written(&param.key))
    } else {
        format!("`{}` ({})", written(&param.key), param.name)
    };
    vec![title, describe(param)]
}

/// A parameter's type, unit, range and default, for people:
/// `a number in dB from -60 to 0, default -18`.
fn describe(param: &Param) -> String {
    let default = |value: Option<String>| {
        value
            .map(|value| format!(", default {value}"))
            .unwrap_or_default()
    };
    let label = if param.label.is_empty() {
        String::new()
    } else {
        format!(" ({})", param.label)
    };
    match &param.value {
        ParamValue::Number {
            unit,
            min,
            max,
            default: value,
            integer,
        } => {
            let what = if *integer {
                "a whole number"
            } else {
                "a number"
            };
            let unit = unit
                .map(|unit| format!(" in {}", unit.as_str()))
                .unwrap_or_default();
            format!(
                "{what}{unit}{label}{}{}",
                range(*min, *max),
                default(value.map(|value| value.to_string()))
            )
        }
        ParamValue::Switch { default: value } => {
            format!(
                "on or off{label}{}",
                default(value.map(|on| if on { "on" } else { "off" }.to_string()))
            )
        }
        ParamValue::Choice {
            choices,
            default: value,
        } => {
            format!(
                "one of {}{label}{}",
                choices.join(", "),
                default(value.clone())
            )
        }
        ParamValue::Text { default: value } => format!("a text{label}{}", default(value.clone())),
        ParamValue::Note { default: value } => {
            format!("a note value{label}{}", default(value.clone()))
        }
        ParamValue::List {
            unit,
            min,
            max,
            count,
            ascending,
        } => {
            let unit = unit
                .map(|unit| format!(" in {}", unit.as_str()))
                .unwrap_or_default();
            let count = count
                .map(|count| format!(", {} to {} values", count.min, count.max))
                .unwrap_or_default();
            let order = if *ascending {
                ", each greater than the one before"
            } else {
                ""
            };
            format!(
                "a list of numbers{unit}{label}{}{count}{order}",
                range(*min, *max)
            )
        }
        ParamValue::Source => {
            format!("a source: `@id`, `@in` or a name that the host knows{label}")
        }
    }
}

/// ` from -60 to 0`, or the one end that the schema gives.
fn range(min: Option<f64>, max: Option<f64>) -> String {
    match (min, max) {
        (Some(min), Some(max)) => format!(" from {min} to {max}"),
        (Some(min), None) => format!(", at least {min}"),
        (None, Some(max)) => format!(", at most {max}"),
        (None, None) => String::new(),
    }
}
