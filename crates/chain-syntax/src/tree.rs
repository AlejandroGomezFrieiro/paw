//! The tree of a chain text: the header, the nodes in series, the splits
//! with their branches, the modulators and the checks.
//!
//! Each line of the text is one item of the tree, and each item has a
//! [`Trivia`]: its place in the text and its comments. Two trees are equal
//! when they hold the same graph: `==` does not compare the trivia, so a
//! tree that the parser reads from a formatted text equals the tree of the
//! text before the format.

use crate::diagnostic::Span;
use crate::value::Value;

/// The latest version of the language, which the header names: `chain 1`.
pub const VERSION: u32 = 1;

/// The place of a line in the text, and the comments around it. It is not
/// part of the graph: any two trivia are equal.
#[derive(Clone, Debug, Default)]
pub struct Trivia {
    /// The line of the item, from its first token to its last.
    pub span: Span,
    /// The comment lines just before the item, each without its `--`.
    pub comments: Vec<String>,
    /// The comment at the end of the item's line, without its `--`.
    pub trailing: Option<String>,
    /// An empty line came before the item (or before its comments).
    pub blank_before: bool,
}

impl PartialEq for Trivia {
    fn eq(&self, _: &Self) -> bool {
        true
    }
}

/// A whole chain text.
#[derive(Clone, Debug, PartialEq, Default)]
pub struct Document {
    pub header: Header,
    /// The top level of the chain: its nodes in series and its modulators.
    pub root: Body,
    /// The `checks` block, when the text has one.
    pub checks: Option<Checks>,
    /// The comments after the last line.
    pub end: Trivia,
}

/// `chain 1 "Name" key=value`: the version of the language, and a name and
/// fields that the host gives a meaning to.
#[derive(Clone, Debug, PartialEq)]
pub struct Header {
    pub version: u32,
    pub name: Option<String>,
    pub fields: Vec<Field>,
    pub trivia: Trivia,
}

impl Default for Header {
    fn default() -> Self {
        Self { version: VERSION, name: None, fields: Vec::new(), trivia: Trivia::default() }
    }
}

/// `key=value`. A key is a word (`b1.freq`) or a quoted text (`"Drive"`).
#[derive(Clone, Debug, PartialEq)]
pub struct Field {
    pub key: String,
    pub value: Value,
    /// The place of the key, for a diagnostic.
    pub span: Spanned,
}

/// A place that is not part of the graph, as [`Trivia`] is not.
#[derive(Clone, Copy, Debug, Default)]
pub struct Spanned(pub Span);

impl PartialEq for Spanned {
    fn eq(&self, _: &Self) -> bool {
        true
    }
}

/// One line of a chain: a device, or a split with its branches under it.
/// The schema of the host says which kinds are splits.
#[derive(Clone, Debug, PartialEq)]
pub struct Node {
    pub kind: String,
    pub id: Option<String>,
    pub name: Option<String>,
    pub fields: Vec<Field>,
    /// What the lines under the node hold. Empty for a device.
    pub body: Body,
    pub trivia: Trivia,
}

/// What is under a split: its branches (or, for a split of one branch,
/// its nodes) and its modulators.
#[derive(Clone, Debug, PartialEq, Default)]
pub struct Body {
    pub content: Content,
    pub mods: Option<Mods>,
}

impl Body {
    pub fn is_empty(&self) -> bool {
        self.mods.is_none()
            && match &self.content {
                Content::Nodes(nodes) => nodes.is_empty(),
                Content::Branches(branches) => branches.is_empty(),
            }
    }
}

/// The lines under a split: nodes in series (one branch with no head), or
/// branches that each start with a `|` line.
#[derive(Clone, Debug, PartialEq)]
pub enum Content {
    Nodes(Vec<Node>),
    Branches(Vec<Branch>),
}

impl Default for Content {
    fn default() -> Self {
        Self::Nodes(Vec::new())
    }
}

/// `| Name #id key=value`, and the nodes of the branch under it.
#[derive(Clone, Debug, PartialEq)]
pub struct Branch {
    pub name: Option<String>,
    pub id: Option<String>,
    pub fields: Vec<Field>,
    pub nodes: Vec<Node>,
    pub trivia: Trivia,
}

/// The `mods` line and the modulators under it.
#[derive(Clone, Debug, PartialEq, Default)]
pub struct Mods {
    pub modulators: Vec<Modulator>,
    pub trivia: Trivia,
}

/// `lfo #31 rate=2Hz -> #8.mix +10%, #9.drive -2dB`: a source of
/// modulation and its links.
#[derive(Clone, Debug, PartialEq)]
pub struct Modulator {
    pub kind: String,
    pub id: Option<String>,
    pub name: Option<String>,
    pub fields: Vec<Field>,
    pub links: Vec<Link>,
    pub trivia: Trivia,
}

/// `#22.threshold -4dB`: a parameter of a node, and how far the source
/// moves it.
#[derive(Clone, Debug, PartialEq)]
pub struct Link {
    pub target: String,
    pub key: String,
    pub depth: Value,
    pub span: Spanned,
}

/// The `checks` line and the checks under it.
#[derive(Clone, Debug, PartialEq, Default)]
pub struct Checks {
    pub lines: Vec<Check>,
    pub trivia: Trivia,
}

/// `latency <= 6ms`, `gain pink -20dB = 0dB +- 1dB`: a claim about the
/// sound of the chain that a host can measure. The language only reads it.
#[derive(Clone, Debug, PartialEq)]
pub struct Check {
    /// What is measured: words and values before the comparison.
    pub subject: Vec<Value>,
    pub compare: Compare,
    pub expected: Value,
    /// `+- 1dB`: how far the measure may be from `expected`.
    pub tolerance: Option<Value>,
    pub trivia: Trivia,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Compare {
    Less,
    LessOrEqual,
    Equal,
    GreaterOrEqual,
    Greater,
}

impl Compare {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Less => "<",
            Self::LessOrEqual => "<=",
            Self::Equal => "=",
            Self::GreaterOrEqual => ">=",
            Self::Greater => ">",
        }
    }
}

impl Document {
    /// Each node of the chain in the order that the signal meets them:
    /// depth first, each branch from its first node to its last.
    pub fn nodes(&self) -> Vec<&Node> {
        let mut out = Vec::new();
        self.root.walk(&mut out);
        out
    }
}

impl Body {
    fn walk<'a>(&'a self, out: &mut Vec<&'a Node>) {
        match &self.content {
            Content::Nodes(nodes) => nodes.iter().for_each(|node| node.walk(out)),
            Content::Branches(branches) => {
                branches.iter().flat_map(|branch| &branch.nodes).for_each(|node| node.walk(out));
            }
        }
    }

    /// The nodes in this body, at any depth, in signal order.
    pub fn nodes(&self) -> Vec<&Node> {
        let mut out = Vec::new();
        self.walk(&mut out);
        out
    }

    /// The branches of the body, at its own level.
    pub fn branches(&self) -> &[Branch] {
        match &self.content {
            Content::Branches(branches) => branches,
            Content::Nodes(_) => &[],
        }
    }
}

impl Node {
    fn walk<'a>(&'a self, out: &mut Vec<&'a Node>) {
        out.push(self);
        self.body.walk(out);
    }
}
