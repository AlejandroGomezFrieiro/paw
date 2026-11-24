//! The lexer: one line of text into its indent, its tokens and its
//! comment. A token that does not lex gives a diagnostic, and the lexer
//! goes on after the next space, so one line can report more than one
//! error.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]

use winnow::Parser;
use winnow::ascii::digit1;
use winnow::combinator::{opt, preceded};
use winnow::token::{one_of, take_while};

use crate::diagnostic::{Code, Diagnostic, Span, did_you_mean};
use crate::tree::Compare;
use crate::value::{Feel, Note, Number, Unit, shift};

/// One token of a line.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Tok {
    /// A bare word: a kind, a key, a name or a value (`compressor`, `b1.freq`, `on`).
    Word(String),
    /// A quoted text, with its escapes read.
    Quoted(String),
    /// A number. `signed` is true when the text gives a `+` or `-`.
    Number {
        number: Number,
        signed: bool,
    },
    Note(Note),
    /// `#id`.
    Id(String),
    /// `#id.key`: a parameter of a node, in a link, or a port or a
    /// parameter of a node, at the end of a wire.
    Target(String, String),
    /// `@id`, or `@in` as `Ref("in")`.
    Ref(String),
    /// `@"path"`: a stream outside the text.
    Outside(String),
    Equals,
    Comma,
    Bar,
    Arrow,
    /// `=>`: a wire that a lane keeps.
    Store,
    Compare(Compare),
    PlusMinus,
    /// A token that did not lex. The lexer gave its diagnostic, so the
    /// parser takes it in silence where any token can be.
    Bad,
}

impl Tok {
    /// How a message names the token.
    pub(crate) fn describe(&self) -> String {
        match self {
            Self::Word(word) => format!("`{word}`"),
            Self::Quoted(text) => format!("\"{text}\""),
            Self::Number { .. } => "a number".into(),
            Self::Note(note) => format!("`{note}`"),
            Self::Id(id) => format!("`#{id}`"),
            Self::Target(id, key) => format!("`#{id}.{key}`"),
            Self::Ref(id) => format!("`@{id}`"),
            Self::Outside(path) => format!("`@\"{path}\"`"),
            Self::Equals => "`=`".into(),
            Self::Comma => "`,`".into(),
            Self::Bar => "`|`".into(),
            Self::Arrow => "`->`".into(),
            Self::Store => "`=>`".into(),
            Self::Compare(compare) => format!("`{}`", compare.as_str()),
            Self::PlusMinus => "`+-`".into(),
            Self::Bad => "a bad token".into(),
        }
    }
}

#[derive(Clone, Debug)]
pub(crate) struct Token {
    pub tok: Tok,
    pub span: Span,
}

/// One line of the text, lexed.
#[derive(Clone, Debug)]
pub(crate) struct Line {
    /// The indent, in steps of two spaces.
    pub level: usize,
    pub tokens: Vec<Token>,
    /// The comment at the end of the line, without its `--`.
    pub comment: Option<String>,
    /// From the first token to the end of the last, or the comment of a
    /// line with no token.
    pub span: Span,
}

/// Lexes the line `text`, which starts at the byte `start` of the whole
/// text and is the line `number` (from 1).
pub(crate) fn line(
    text: &str,
    start: usize,
    number: u32,
    diagnostics: &mut Vec<Diagnostic>,
) -> Line {
    let mut lexer = Lexer {
        text,
        start,
        number,
        rest: text,
        diagnostics,
    };
    let level = lexer.indent();
    let mut tokens = Vec::new();
    let mut comment = None;
    loop {
        lexer.rest = lexer.rest.trim_start_matches(' ');
        if lexer.rest.is_empty() {
            break;
        }
        if let Some(text) = lexer.rest.strip_prefix("--") {
            comment = Some(text.trim_end().to_string());
            lexer.rest = "";
            break;
        }
        let from = lexer.offset();
        match lexer.token() {
            Ok(tok) => tokens.push(Token {
                tok,
                span: lexer.span(from),
            }),
            Err((code, message)) => {
                // Go on after the next space.
                let skip = lexer.rest.find([' ', '\t']).unwrap_or(lexer.rest.len());
                lexer.rest = &lexer.rest[skip..];
                let span = lexer.span(from);
                lexer.diagnostics.push(Diagnostic::new(code, span, message));
                tokens.push(Token {
                    tok: Tok::Bad,
                    span,
                });
            }
        }
    }
    let span = match (tokens.first(), tokens.last()) {
        (Some(first), Some(last)) => Span {
            end: last.span.end,
            ..first.span
        },
        _ => lexer.span_at(lexer.indent_bytes(), text.len()),
    };
    Line {
        level,
        tokens,
        comment,
        span,
    }
}

struct Lexer<'t, 'd> {
    text: &'t str,
    start: usize,
    number: u32,
    rest: &'t str,
    diagnostics: &'d mut Vec<Diagnostic>,
}

type Lexed = Result<Tok, (Code, String)>;

impl Lexer<'_, '_> {
    fn offset(&self) -> usize {
        self.text.len() - self.rest.len()
    }

    fn indent_bytes(&self) -> usize {
        self.text.len() - self.text.trim_start_matches([' ', '\t']).len()
    }

    /// The span from the byte `from` of the line to where the lexer is.
    fn span(&self, from: usize) -> Span {
        self.span_at(from, self.offset())
    }

    fn span_at(&self, from: usize, to: usize) -> Span {
        Span {
            start: self.start + from,
            end: self.start + to,
            line: self.number,
            column: self.text[..from].chars().count() as u32 + 1,
        }
    }

    /// Reads the indent. A tab, or a count of spaces that is not even,
    /// gives a diagnostic, and the level is the nearest step down.
    fn indent(&mut self) -> usize {
        let width = self.indent_bytes();
        let indent = &self.text[..width];
        self.rest = &self.text[width..];
        if self.rest.is_empty() || self.rest.starts_with("--") {
            return 0;
        }
        if let Some(tab) = indent.find('\t') {
            let span = self.span_at(tab, tab + 1);
            self.diagnostics.push(Diagnostic::new(
                Code::Tab,
                span,
                "a tab in the indent: indent with two spaces",
            ));
        } else if width % 2 == 1 {
            let span = self.span_at(0, width);
            self.diagnostics.push(Diagnostic::new(
                Code::OddIndent,
                span,
                format!("an indent of {width} spaces: indent in steps of two spaces"),
            ));
        }
        indent.matches(' ').count() / 2
    }

    fn token(&mut self) -> Lexed {
        let rest = &mut self.rest;
        let first = rest.chars().next().unwrap_or(' ');
        match first {
            '"' => quoted(rest),
            '#' => {
                *rest = &rest[1..];
                let id = id(rest, "#")?;
                if let Some(after) = rest.strip_prefix('.') {
                    *rest = after;
                    return Ok(Tok::Target(id, key(rest)?));
                }
                Ok(Tok::Id(id))
            }
            '@' => {
                *rest = &rest[1..];
                if rest.starts_with('"') {
                    return match quoted(rest)? {
                        Tok::Quoted(path) => Ok(Tok::Outside(path)),
                        _ => unreachable!("quoted gives a quoted text"),
                    };
                }
                Ok(Tok::Ref(id(rest, "@")?))
            }
            '=' if rest[1..].starts_with('>') => punct(rest, 2, Tok::Store),
            '=' => punct(rest, 1, Tok::Equals),
            ',' => punct(rest, 1, Tok::Comma),
            '|' => punct(rest, 1, Tok::Bar),
            '<' | '>' if rest[1..].starts_with('=') => {
                let compare = if first == '<' {
                    Compare::LessOrEqual
                } else {
                    Compare::GreaterOrEqual
                };
                punct(rest, 2, Tok::Compare(compare))
            }
            '<' => punct(rest, 1, Tok::Compare(Compare::Less)),
            '>' => punct(rest, 1, Tok::Compare(Compare::Greater)),
            '-' if rest[1..].starts_with('>') => punct(rest, 2, Tok::Arrow),
            '+' if rest[1..].starts_with('-') => punct(rest, 2, Tok::PlusMinus),
            '+' | '-' | '0'..='9' => number(rest),
            c if is_word_start(c) => Ok(Tok::Word(word(rest).unwrap_or_default().to_string())),
            c => {
                *rest = &rest[c.len_utf8()..];
                Err((Code::Token, format!("`{c}` cannot start a token here")))
            }
        }
    }
}

fn punct(rest: &mut &str, width: usize, tok: Tok) -> Lexed {
    *rest = &rest[width..];
    Ok(tok)
}

pub(crate) fn is_word_start(c: char) -> bool {
    c.is_alphabetic() || c == '_'
}

pub(crate) fn is_word_char(c: char) -> bool {
    c.is_alphanumeric() || matches!(c, '_' | '.' | ':' | '/' | '+' | '-')
}

pub(crate) fn is_id_char(c: char) -> bool {
    c.is_alphanumeric() || matches!(c, '_' | '-')
}

/// Whether `text` lexes as one bare word, so that the printer can write it
/// without quotes.
pub(crate) fn is_word(text: &str) -> bool {
    let mut chars = text.chars();
    chars.next().is_some_and(is_word_start) && chars.all(is_word_char) && !text.contains("--")
}

#[cfg(test)]
pub(crate) fn is_id(text: &str) -> bool {
    !text.is_empty() && text.chars().all(is_id_char)
}

fn word<'t>(rest: &mut &'t str) -> winnow::Result<&'t str> {
    (one_of(is_word_start), take_while(0.., is_word_char))
        .take()
        .parse_next(rest)
}

fn id(rest: &mut &str, sign: &str) -> Result<String, (Code, String)> {
    take_while(1.., is_id_char)
        .parse_next(rest)
        .map(str::to_string)
        .map_err(|_: winnow::error::ContextError| {
            (
                Code::Token,
                format!("`{sign}` needs an id after it, such as `{sign}7`"),
            )
        })
}

/// A key after `#id.` in a link: a word or a quoted text.
fn key(rest: &mut &str) -> Result<String, (Code, String)> {
    if rest.starts_with('"') {
        return match quoted(rest)? {
            Tok::Quoted(text) => Ok(text),
            _ => unreachable!("quoted gives a quoted text"),
        };
    }
    word(rest)
        .map(str::to_string)
        .map_err(|_: winnow::error::ContextError| {
            (
                Code::Token,
                "a parameter must follow `#id.`, such as `#7.mix`".into(),
            )
        })
}

/// `"text"` with the escapes `\"`, `\\`, `\n`, `\t` and `\u{hex}`.
fn quoted(rest: &mut &str) -> Lexed {
    let mut out = String::new();
    let mut chars = rest.char_indices().skip(1);
    while let Some((at, c)) = chars.next() {
        match c {
            '"' => {
                *rest = &rest[at + 1..];
                return Ok(Tok::Quoted(out));
            }
            '\\' => match chars.next().map(|(_, c)| c) {
                Some('"') => out.push('"'),
                Some('\\') => out.push('\\'),
                Some('n') => out.push('\n'),
                Some('t') => out.push('\t'),
                Some('u') => {
                    let tail: String = chars
                        .by_ref()
                        .map(|(_, c)| c)
                        .take_while(|c| *c != '}')
                        .collect();
                    let code = tail
                        .strip_prefix('{')
                        .and_then(|hex| u32::from_str_radix(hex, 16).ok());
                    match code.and_then(char::from_u32) {
                        Some(c) => out.push(c),
                        None => return Err(escape_error(rest)),
                    }
                }
                _ => return Err(escape_error(rest)),
            },
            c => out.push(c),
        }
    }
    *rest = "";
    Err((Code::Quote, "this quoted text has no closing `\"`".into()))
}

fn escape_error(rest: &mut &str) -> (Code, String) {
    *rest = "";
    (
        Code::Quote,
        "a bad escape in a quoted text: use \\\", \\\\, \\n, \\t or \\u{hex}".into(),
    )
}

/// A number with an optional unit (`-18dB`, `2.5kHz`, `4`), or a note
/// value (`1/4`, `1/8.`, `3/16t`).
fn number(rest: &mut &str) -> Lexed {
    let sign: winnow::Result<Option<char>> = opt(one_of(['+', '-'])).parse_next(rest);
    let sign = sign.unwrap_or(None);
    let digits: winnow::Result<&str> = (digit1, opt(preceded('.', digit1))).take().parse_next(rest);
    let Ok(digits) = digits else {
        return Err((
            Code::Token,
            "a number must have a digit after its sign".into(),
        ));
    };
    if sign.is_none() && !digits.contains('.') && rest.starts_with('/') {
        return note(digits, rest);
    }
    let suffix: winnow::Result<&str> =
        take_while(0.., |c: char| c.is_alphabetic() || c == '%').parse_next(rest);
    let suffix = suffix.unwrap_or("");
    let text = format!("{}{digits}", if sign == Some('-') { "-" } else { "" });
    let number = if suffix.is_empty() {
        Number::plain(parse_digits(&text))
    } else {
        let Some(unit) = Unit::from_suffix(suffix) else {
            let units = Unit::ALL.map(Unit::as_str);
            let hint = did_you_mean(suffix, units)
                .unwrap_or_else(|| format!("; the units are {}", units.join(" ")));
            return Err((Code::Unit, format!("`{suffix}` is not a unit{hint}")));
        };
        Number::with(
            parse_digits(&shift(&text, unit.exponent())),
            unit.dimension(),
        )
    };
    Ok(Tok::Number {
        number,
        signed: sign.is_some(),
    })
}

fn parse_digits(text: &str) -> f64 {
    // The lexer gives only digits, a sign and a point, which always parse.
    text.parse().unwrap_or_default()
}

fn note(count: &str, rest: &mut &str) -> Lexed {
    let division: winnow::Result<&str> = preceded('/', digit1).parse_next(rest);
    let bad = || {
        (
            Code::Token,
            "a note value is a count and a division, such as `1/4`, `1/8.` or `1/8t`".to_string(),
        )
    };
    let division = division.map_err(|_| bad())?;
    let feel = match rest.chars().next() {
        Some('.') => Feel::Dotted,
        Some('t') => Feel::Triplet,
        _ => Feel::Straight,
    };
    if feel != Feel::Straight {
        *rest = &rest[1..];
    }
    match (count.parse::<u32>(), division.parse::<u32>()) {
        (Ok(count), Ok(division)) if count > 0 && division > 0 => Ok(Tok::Note(Note {
            count,
            division,
            feel,
        })),
        _ => Err(bad()),
    }
}

/// The note value that `text` is, and nothing after it.
pub(crate) fn note_value(mut text: &str) -> Option<Note> {
    match number(&mut text) {
        Ok(Tok::Note(note)) if text.is_empty() => Some(note),
        _ => None,
    }
}
