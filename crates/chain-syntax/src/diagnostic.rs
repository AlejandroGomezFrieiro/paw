//! Places in the text, and the diagnostics that the parser and the check
//! give.

use std::fmt;

/// A part of the text: the bytes `start..end`, and the line and column of
/// `start`. Lines and columns count from 1, and a column counts characters
/// (Unicode scalar values), not bytes.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct Span {
    pub start: usize,
    pub end: usize,
    pub line: u32,
    pub column: u32,
}

/// How bad a diagnostic is. An error stops an apply: a host must not
/// change its chain from a text with an error.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Severity {
    Error,
    Warning,
}

/// The kind of a diagnostic. The code is stable: tools and tests match on
/// it, and the reference page lists each one.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[non_exhaustive]
pub enum Code {
    // The parser: the text is not a chain.
    /// The text does not start with the line `chain 1`.
    MissingHeader,
    /// The header names a version of the language that this crate does not know.
    Version,
    /// A tab in the indent of a line.
    Tab,
    /// An indent that is not a whole number of steps of two spaces.
    OddIndent,
    /// A line that is more than one step deeper than the line it goes under.
    TooDeep,
    /// A character or a token that the line cannot have at its place.
    Token,
    /// A number with a unit that the language does not know.
    Unit,
    /// A quoted text that does not end, or a bad escape in it.
    Quote,
    /// A line at a place where its kind of line cannot go.
    Place,
    // The check: the text is a chain, but the schema does not allow it.
    /// A kind that the schema does not have.
    UnknownKind,
    /// A parameter that the kind does not have.
    UnknownParameter,
    /// A value of the wrong type for its parameter.
    Type,
    /// A number with the wrong unit for its parameter.
    WrongUnit,
    /// A number outside the range of its parameter.
    Range,
    /// Two nodes, branches or modulators with one id.
    DuplicateId,
    /// One parameter twice on one line.
    DuplicateParameter,
    /// A split with a number of branches that its kind does not take.
    Branches,
    /// A device with nodes under it: only a split holds nodes.
    NotSplit,
    /// A reference (`@id`) to no node, to the node itself or to a later node.
    Reference,
    /// A modulation link to no node, to a node outside the container, or to
    /// a parameter that the node does not have.
    Link,
    /// A list of values in the wrong order or with the wrong count.
    List,
    /// A stream of the wrong type: at a wire, at a source, or between two
    /// inserts in series. The message names the stream or the property
    /// that is missing.
    StreamType,
    /// An insert of a strip whose kind does not run live.
    NotLive,
    /// A live wire `->` from a node that does not run live: its output
    /// reaches the live graph only through a lane.
    LiveFromLater,
    /// Two store wires `=>` into one lane.
    TwoStores,
    /// The wires of the text make a cycle.
    Cycle,
    /// A port that the kind of the node does not have.
    UnknownPort,
    /// A lane or a stream outside the text that the context of the host
    /// does not have, or no context: its type is not checked.
    UnknownOutside,
    /// A kind of plugin that the schema does not have: its fields stay as
    /// they are written, with no check.
    UnknownPlugin,
}

impl Code {
    /// Each code, in the order of the reference page.
    pub const ALL: [Code; 29] = [
        Self::MissingHeader,
        Self::Version,
        Self::Tab,
        Self::OddIndent,
        Self::TooDeep,
        Self::Token,
        Self::Unit,
        Self::Quote,
        Self::Place,
        Self::UnknownKind,
        Self::UnknownParameter,
        Self::Type,
        Self::WrongUnit,
        Self::Range,
        Self::DuplicateId,
        Self::DuplicateParameter,
        Self::Branches,
        Self::NotSplit,
        Self::Reference,
        Self::Link,
        Self::List,
        Self::StreamType,
        Self::NotLive,
        Self::LiveFromLater,
        Self::TwoStores,
        Self::Cycle,
        Self::UnknownPort,
        Self::UnknownPlugin,
        Self::UnknownOutside,
    ];

    /// The code as the diagnostics and the reference page write it.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::MissingHeader => "E101",
            Self::Version => "E102",
            Self::Tab => "E103",
            Self::OddIndent => "E104",
            Self::TooDeep => "E105",
            Self::Token => "E106",
            Self::Unit => "E107",
            Self::Quote => "E108",
            Self::Place => "E109",
            Self::UnknownKind => "E201",
            Self::UnknownParameter => "E202",
            Self::Type => "E203",
            Self::WrongUnit => "E204",
            Self::Range => "E205",
            Self::DuplicateId => "E206",
            Self::DuplicateParameter => "E207",
            Self::Branches => "E208",
            Self::NotSplit => "E209",
            Self::Reference => "E210",
            Self::Link => "E211",
            Self::List => "E212",
            Self::StreamType => "E213",
            Self::NotLive => "E214",
            Self::LiveFromLater => "E215",
            Self::TwoStores => "E216",
            Self::Cycle => "E217",
            Self::UnknownPort => "E218",
            Self::UnknownPlugin => "W301",
            Self::UnknownOutside => "W302",
        }
    }

    /// The severity of each diagnostic of this code.
    pub const fn severity(self) -> Severity {
        match self {
            Self::UnknownPlugin | Self::UnknownOutside => Severity::Warning,
            _ => Severity::Error,
        }
    }
}

/// One problem of a text, at its place.
#[derive(Clone, Debug, PartialEq)]
pub struct Diagnostic {
    pub code: Code,
    pub message: String,
    pub span: Span,
}

impl Diagnostic {
    pub(crate) fn new(code: Code, span: Span, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            span,
        }
    }

    pub fn severity(&self) -> Severity {
        self.code.severity()
    }

    pub fn is_error(&self) -> bool {
        self.severity() == Severity::Error
    }
}

/// `line:column: error E202: message`, one diagnostic on one line.
impl fmt::Display for Diagnostic {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let severity = match self.severity() {
            Severity::Error => "error",
            Severity::Warning => "warning",
        };
        write!(
            f,
            "{}:{}: {severity} {}: {}",
            self.span.line,
            self.span.column,
            self.code.as_str(),
            self.message
        )
    }
}

/// The nearest of `candidates` to `word`, for a "did you mean" in a
/// message. None when no candidate is near.
pub(crate) fn nearest<'a>(
    word: &str,
    candidates: impl IntoIterator<Item = &'a str>,
) -> Option<&'a str> {
    candidates
        .into_iter()
        .map(|candidate| (strsim::damerau_levenshtein(word, candidate), candidate))
        // A third of the word may change, and at least one character.
        .filter(|(distance, _)| *distance <= (word.chars().count() / 3).max(1))
        .min_by_key(|(distance, _)| *distance)
        .map(|(_, candidate)| candidate)
}

/// `; did you mean `x`?` for the end of a message, when a candidate is near.
pub(crate) fn did_you_mean<'a>(
    word: &str,
    candidates: impl IntoIterator<Item = &'a str>,
) -> Option<String> {
    nearest(word, candidates).map(|near| format!("; did you mean `{near}`?"))
}
