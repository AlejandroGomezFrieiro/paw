//! The tree of a chain text. In version 2, the top level is the graph of
//! one part: its node lines and its wires. A strip holds its inserts: the
//! devices in series, the splits with their branches, and the modulators.
//! In version 1, the top level is one chain of inserts. Both versions end
//! with the checks.
//!
//! Each line of the text is one item of the tree, and each item has a
//! [`Trivia`]: its place in the text and its comments. Two trees are equal
//! when they hold the same graph: `==` does not compare the trivia, so a
//! tree that the parser reads from a formatted text equals the tree of the
//! text before the format.

use crate::diagnostic::Span;
use crate::value::Value;

/// The latest version of the language, which the header names: `chain 2`.
/// A reader of version 2 also reads a text of version 1.
pub const VERSION: u32 = 2;

/// The first version, in which a text is one chain of devices: the inserts
/// of one strip.
pub const VERSION_1: u32 = 1;

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
    /// Version 1: the top level of the chain, its nodes in series and its
    /// modulators. Empty in version 2.
    pub root: Body,
    /// Version 2: the node lines and the wires of the top level, in the
    /// order of the text. Empty in version 1.
    pub graph: Vec<Item>,
    /// The `checks` block, when the text has one.
    pub checks: Option<Checks>,
    /// The comments after the last line.
    pub end: Trivia,
}

/// `chain 2 "Name" key=value`: the version of the language, and a name and
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
        Self {
            version: VERSION,
            name: None,
            fields: Vec::new(),
            trivia: Trivia::default(),
        }
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

/// A line of the top level of version 2: a node of the part's graph, or a
/// wire.
#[derive(Clone, Debug, PartialEq)]
pub enum Item {
    Node(GraphNode),
    Wire(Wire),
}

/// The role of a node of a part's graph: the word that starts its line.
/// The language knows these words. The schema of the host gives their
/// parameters and ports, and the kinds of producer and of input or output.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Role {
    /// Sums its inputs, with a fader, a pan and inserts.
    Strip,
    /// A strip that sums other nodes, not lanes.
    Bus,
    /// The strip at the end of the part.
    Master,
    /// A level from one node to another.
    Send,
    /// A control of the gains of other nodes.
    Vca,
    /// Makes a stream from streams, of a kind of the host.
    Producer,
    /// An input or an output of the host, of a kind of the host.
    Io,
}

impl Role {
    /// Each role, in the order of the reference page.
    pub const ALL: [Role; 7] = [
        Self::Strip,
        Self::Bus,
        Self::Master,
        Self::Send,
        Self::Vca,
        Self::Producer,
        Self::Io,
    ];

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Strip => "strip",
            Self::Bus => "bus",
            Self::Master => "master",
            Self::Send => "send",
            Self::Vca => "vca",
            Self::Producer => "producer",
            Self::Io => "io",
        }
    }

    pub fn from_word(word: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|role| role.as_str() == word)
    }

    /// A strip, a bus and the master hold inserts: a chain of version 1.
    pub const fn holds_inserts(self) -> bool {
        matches!(self, Self::Strip | Self::Bus | Self::Master)
    }

    /// A producer and an input or output name a kind of the host after
    /// the role word.
    pub const fn has_kind(self) -> bool {
        matches!(self, Self::Producer | Self::Io)
    }
}

/// `strip #1 "Violin I" gain=-3dB`, with its inserts under it, or
/// `producer midi-keys #p2 smooth=20ms`.
#[derive(Clone, Debug, PartialEq)]
pub struct GraphNode {
    pub role: Role,
    /// The kind of a producer or of an input or output.
    pub kind: Option<String>,
    pub id: Option<String>,
    pub name: Option<String>,
    pub fields: Vec<Field>,
    /// The inserts of a strip, a bus or the master: devices and splits in
    /// series, and their modulators. Empty for the other roles.
    pub inserts: Body,
    pub trivia: Trivia,
}

/// `#p2 => "Keys"`, `"Notes" -> #1`: one wire of the graph.
#[derive(Clone, Debug, PartialEq)]
pub struct Wire {
    pub from: End,
    pub arrow: Arrow,
    pub to: End,
    pub trivia: Trivia,
}

/// What a wire carries.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Arrow {
    /// `->`: a signal that the host computes as it plays.
    Live,
    /// `=>`: a result that a lane keeps. It always ends at a lane.
    Store,
}

impl Arrow {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Live => "->",
            Self::Store => "=>",
        }
    }
}

/// One end of a wire.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum End {
    /// `#id`, or `#id.port`: a node of the text, and a port or a parameter
    /// of it. With no port, the wire joins the main ports.
    Node { id: String, port: Option<String> },
    /// `"Notes"`: a lane of this part.
    Lane(String),
    /// `@"Strings/Violin I/Notes"`: a lane or a node of another part, by a
    /// path that the host gives a meaning to.
    Outside(String),
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
    /// depth first, each branch from its first node to its last. In
    /// version 2, the inserts of each strip, strip after strip.
    pub fn nodes(&self) -> Vec<&Node> {
        let mut out = Vec::new();
        self.root.walk(&mut out);
        for node in self.graph_nodes() {
            node.inserts.walk(&mut out);
        }
        out
    }

    /// The node lines of the top level of version 2, in the order of the text.
    pub fn graph_nodes(&self) -> impl Iterator<Item = &GraphNode> {
        self.graph.iter().filter_map(|item| match item {
            Item::Node(node) => Some(node),
            Item::Wire(_) => None,
        })
    }

    /// The wires of version 2, in the order of the text.
    pub fn wires(&self) -> impl Iterator<Item = &Wire> {
        self.graph.iter().filter_map(|item| match item {
            Item::Wire(wire) => Some(wire),
            Item::Node(_) => None,
        })
    }

    /// The text as version 2 reads it. A text of version 1 is the inserts
    /// of one strip with no id: the host gives it the strip of the part. A
    /// text of version 2 stays as it is.
    pub fn to_version_2(&self) -> Document {
        if self.header.version != VERSION_1 {
            return self.clone();
        }
        let strip = GraphNode {
            role: Role::Strip,
            kind: None,
            id: None,
            name: None,
            fields: Vec::new(),
            inserts: self.root.clone(),
            trivia: Trivia::default(),
        };
        Document {
            header: Header {
                version: VERSION,
                ..self.header.clone()
            },
            root: Body::default(),
            graph: vec![Item::Node(strip)],
            checks: self.checks.clone(),
            end: self.end.clone(),
        }
    }
}

impl Body {
    fn walk<'a>(&'a self, out: &mut Vec<&'a Node>) {
        match &self.content {
            Content::Nodes(nodes) => nodes.iter().for_each(|node| node.walk(out)),
            Content::Branches(branches) => {
                branches
                    .iter()
                    .flat_map(|branch| &branch.nodes)
                    .for_each(|node| node.walk(out));
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
