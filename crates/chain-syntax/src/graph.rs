//! The check of the top level of version 2: the node lines and the wires
//! of a part's graph. Each node line has a role or a kind that the schema
//! knows, and fields that its parameters take. Each wire joins ports that
//! exist, of types that meet, from a node that runs live when the wire is
//! live. No two wires store in one lane, and the wires make no cycle.

use std::collections::{HashMap, HashSet};

use crate::check::{Checker, Reach};
use crate::context::OutsideEnd;
use crate::diagnostic::{Code, Span, did_you_mean};
use crate::schema::{Kind, Param, ParamValue, Port, PropValue, Props, Tier};
use crate::tree::{Arrow, Document, End, GraphNode, Role, Wire};

/// The type of a stream at a port or a lane: its kind and the values of
/// its properties.
#[derive(Clone, Copy)]
struct Type<'s> {
    stream: &'s str,
    props: &'s Props,
}

/// What one end of a wire is, as far as the schema and the context know.
enum Side<'s> {
    /// Ports of a node, or the type of a lane: the wire joins one of them.
    Types { types: Vec<Type<'s>>, tier: Tier },
    /// A parameter of a node, which a stream that controls can feed.
    Param { param: &'s Param, tier: Tier },
    /// An end whose type is not known: no type is checked.
    Unknown,
}

impl<'s> Checker<'s> {
    /// The node lines and the wires of a text of version 2.
    pub(crate) fn graph(&mut self, document: &'s Document) {
        let nodes: HashMap<&str, &GraphNode> = document
            .graph_nodes()
            .filter_map(|node| Some((node.id.as_deref()?, node)))
            .collect();
        for node in document.graph_nodes() {
            self.graph_node(node, &nodes);
        }
        let inserts: HashSet<&str> = document
            .graph_nodes()
            .flat_map(|node| node.inserts.nodes())
            .filter_map(|node| node.id.as_deref())
            .collect();
        let mut stores: HashMap<&End, Span> = HashMap::new();
        for wire in document.wires() {
            self.wire(wire, &nodes, &inserts);
            if wire.arrow == Arrow::Store {
                let span = wire.trivia.span;
                match stores.get(&wire.to) {
                    Some(first) => {
                        let message = format!(
                            "{} gets a second `=>` wire: a lane keeps the result of one wire, and the first is on line {}",
                            end_text(&wire.to),
                            first.line
                        );
                        self.error(Code::TwoStores, span, message);
                    }
                    None => {
                        stores.insert(&wire.to, span);
                    }
                }
            }
        }
        self.cycles(document);
    }

    fn graph_node(&mut self, node: &'s GraphNode, nodes: &HashMap<&'s str, &'s GraphNode>) {
        let span = node.trivia.span;
        let kind = self.schema.kind_of(node);
        let params = match (kind, node.kind.as_deref()) {
            (Some(kind), _) => (!kind.open_params).then_some(kind.params.as_slice()),
            (None, Some(word)) if self.schema.is_open(word) => {
                self.unknown_kind(word, span);
                None
            }
            (None, Some(word)) => {
                let schema = self.schema;
                let list = if node.role == Role::Producer {
                    &schema.producers
                } else {
                    &schema.io
                };
                let hint = did_you_mean(word, list.iter().map(|kind| kind.kind.as_str()))
                    .unwrap_or_default();
                self.error(
                    Code::UnknownKind,
                    span,
                    format!("no {} kind `{word}`{hint}", node.role.as_str()),
                );
                None
            }
            (None, None) => {
                let message = format!(
                    "the schema of the host has no `{}` node",
                    node.role.as_str()
                );
                self.error(Code::UnknownKind, span, message);
                None
            }
        };
        self.reach = Reach::Any(nodes.keys().copied().collect());
        self.fields(&node.fields, params, span);
        if node.role.holds_inserts() {
            let input = self.strip_input(kind);
            self.chain(&node.inserts, input);
        }
    }

    fn wire(
        &mut self,
        wire: &'s Wire,
        nodes: &HashMap<&'s str, &'s GraphNode>,
        inserts: &HashSet<&str>,
    ) {
        let span = wire.trivia.span;
        let from = self.side(&wire.from, true, nodes, inserts, span);
        let to = self.side(&wire.to, false, nodes, inserts, span);
        let (Some(from), Some(to)) = (from, to) else {
            return;
        };
        if wire.arrow == Arrow::Live
            && let (
                Side::Types {
                    tier: from_tier, ..
                },
                Side::Types {
                    tier: Tier::Live, ..
                }
                | Side::Param {
                    tier: Tier::Live, ..
                },
            ) = (&from, &to)
            && *from_tier != Tier::Live
            && matches!(wire.from, End::Node { .. })
        {
            let message = format!(
                "{} runs in tier {}, so a live wire cannot leave it: store its output in a lane with `=>`, and wire the lane",
                end_text(&wire.from),
                from_tier.as_str()
            );
            self.error(Code::LiveFromLater, span, message);
        }
        match (&from, &to) {
            (Side::Types { types: given, .. }, Side::Types { types: wanted, .. }) => {
                if let Some(message) = self.gap(given, wanted, &wire.from, &wire.to) {
                    self.error(Code::StreamType, span, message);
                }
            }
            (Side::Types { types: given, .. }, Side::Param { param, .. }) => {
                let controls = |ty: &Type<'_>| {
                    self.schema
                        .stream(ty.stream)
                        .is_some_and(|stream| stream.control)
                };
                if !given.iter().any(controls) {
                    let streams: Vec<&str> = self
                        .schema
                        .streams
                        .iter()
                        .filter(|stream| stream.control)
                        .map(|stream| stream.stream.as_str())
                        .collect();
                    let wanted = if streams.is_empty() {
                        "no stream of this host".to_string()
                    } else {
                        streams.join(" or ")
                    };
                    let message = format!(
                        "{} is a parameter: it takes {wanted}, and {} gives {}",
                        end_text(&wire.to),
                        end_text(&wire.from),
                        stream_list(given)
                    );
                    self.error(Code::StreamType, span, message);
                } else if !matches!(param.value, ParamValue::Number { .. }) {
                    let message = format!(
                        "{} is not a number, so a stream cannot move it",
                        end_text(&wire.to)
                    );
                    self.error(Code::StreamType, span, message);
                }
            }
            _ => {}
        }
    }

    /// One end of a wire: `out` for the end that the wire leaves. None
    /// after an error at the end.
    fn side(
        &mut self,
        end: &End,
        out: bool,
        nodes: &HashMap<&'s str, &'s GraphNode>,
        inserts: &HashSet<&str>,
        span: Span,
    ) -> Option<Side<'s>> {
        match end {
            End::Node { id, port } => {
                let Some(node) = nodes.get(id.as_str()) else {
                    let message = if inserts.contains(id.as_str()) {
                        format!(
                            "`#{id}` is an insert of a strip: a wire joins the node lines of the top level"
                        )
                    } else {
                        format!("no node line has the id `#{id}`")
                    };
                    self.error(Code::Reference, span, message);
                    return None;
                };
                let Some(kind) = self.schema.kind_of(node) else {
                    return Some(Side::Unknown);
                };
                self.node_side(node, kind, port.as_deref(), out, span)
            }
            End::Lane(name) => {
                let Some(context) = self.context else {
                    let message = format!(
                        "no context of the host: the type of the lane \"{name}\" is not checked"
                    );
                    self.error(Code::UnknownOutside, span, message);
                    return Some(Side::Unknown);
                };
                let Some(lane) = context.lane(name) else {
                    let message = format!(
                        "the context of the host has no lane \"{name}\" in this part: its type is not checked"
                    );
                    self.error(Code::UnknownOutside, span, message);
                    return Some(Side::Unknown);
                };
                Some(Side::Types {
                    types: vec![Type {
                        stream: &lane.stream,
                        props: &lane.props,
                    }],
                    tier: Tier::Live,
                })
            }
            End::Outside(path) => {
                let found = self.context.and_then(|context| context.outside(path));
                let Some(outside) = found else {
                    self.outside_stream(path, span);
                    return Some(Side::Unknown);
                };
                match &outside.end {
                    OutsideEnd::Lane { stream, props } => Some(Side::Types {
                        types: vec![Type { stream, props }],
                        tier: Tier::Live,
                    }),
                    OutsideEnd::Node { node, kind } => {
                        let kind = Role::from_word(node)
                            .and_then(|role| self.schema.graph_kind(role, kind.as_deref()));
                        let Some(kind) = kind else {
                            return Some(Side::Unknown);
                        };
                        let ports = self
                            .schema
                            .ports(kind)
                            .iter()
                            .filter(|port| port.out == out && port.main);
                        Some(Side::Types {
                            types: ports.map(Type::of).collect(),
                            tier: kind.tier,
                        })
                    }
                }
            }
        }
    }

    /// The end of a wire at a node line of `kind`: a port by its name, a
    /// parameter by its key (only where the wire arrives), or the main
    /// ports.
    fn node_side(
        &mut self,
        node: &GraphNode,
        kind: &'s Kind,
        port: Option<&str>,
        out: bool,
        span: Span,
    ) -> Option<Side<'s>> {
        let ports: Vec<&'s Port> = self
            .schema
            .ports(kind)
            .iter()
            .filter(|candidate| candidate.out == out)
            .collect();
        let direction = if out { "output" } else { "input" };
        let id = node.id.as_deref().unwrap_or_default();
        let Some(port) = port else {
            let main: Vec<Type<'s>> = ports
                .iter()
                .filter(|port| port.main)
                .map(|port| Type::of(port))
                .collect();
            let types = if main.is_empty() {
                ports.iter().map(|port| Type::of(port)).collect()
            } else {
                main
            };
            if types.is_empty() {
                let message = format!("`#{id}` (`{}`) has no {direction}", node.role.as_str());
                self.error(Code::UnknownPort, span, message);
                return None;
            }
            return Some(Side::Types {
                types,
                tier: kind.tier,
            });
        };
        if let Some(found) = ports.iter().find(|candidate| candidate.port == port) {
            return Some(Side::Types {
                types: vec![Type::of(found)],
                tier: kind.tier,
            });
        }
        if !out && let Some(param) = kind.params.iter().find(|param| param.key == port) {
            return Some(Side::Param {
                param,
                tier: kind.tier,
            });
        }
        let names: Vec<&str> = ports.iter().map(|port| port.port.as_str()).collect();
        let what = if out { "output" } else { "input or parameter" };
        let list = if names.is_empty() {
            format!("it has no {direction}")
        } else {
            format!("its {direction}s are {}", names.join(", "))
        };
        let message = format!("`#{id}` (`{}`) has no {what} `{port}`: {list}", kind.kind);
        self.error(Code::UnknownPort, span, message);
        None
    }

    /// Why a stream of one of the types `given` cannot go to a port of one
    /// of the types `wanted`, or None when one pair meets, or when the
    /// schema has a converter for one pair (a host puts it on the wire).
    fn gap(&self, given: &[Type<'s>], wanted: &[Type<'s>], from: &End, to: &End) -> Option<String> {
        let pairs = || {
            given
                .iter()
                .flat_map(|given| wanted.iter().map(move |wanted| (*given, *wanted)))
        };
        if pairs().any(|(given, wanted)| {
            given.stream == wanted.stream && self.missing(given, wanted).is_none()
        }) {
            return None;
        }
        if pairs().any(|(given, wanted)| self.converts(given, wanted)) {
            return None;
        }
        // Two ports of one stream that differ in a property, or else no
        // port of one stream.
        let gap = pairs().find_map(|(given, wanted)| {
            let missing = (given.stream == wanted.stream)
                .then(|| self.missing(given, wanted))
                .flatten()?;
            Some((given, wanted, missing))
        });
        Some(match gap {
            Some((given, wanted, (key, value))) => {
                let has = given
                    .props
                    .get(&key)
                    .cloned()
                    .or_else(|| self.default_of(given.stream, &key));
                let has = has.map_or_else(|| format!("no `{key}`"), |has| format!("{key}={has}"));
                format!(
                    "{} needs {} with {key}={value}, and {} gives {has}, and the host has no converter",
                    end_text(to),
                    wanted.stream,
                    end_text(from)
                )
            }
            None => format!(
                "{} takes {}, and {} gives {}",
                end_text(to),
                stream_list(wanted),
                end_text(from),
                stream_list(given)
            ),
        })
    }

    /// The first property that `wanted` asks for and `given` does not
    /// give, with the value that `wanted` asks for. A property that `given`
    /// does not name has the default of its stream.
    fn missing(&self, given: Type<'s>, wanted: Type<'s>) -> Option<(String, PropValue)> {
        wanted.props.iter().find_map(|(key, value)| {
            let has = given
                .props
                .get(key)
                .cloned()
                .or_else(|| self.default_of(given.stream, key));
            (has.as_ref() != Some(value)).then(|| (key.clone(), value.clone()))
        })
    }

    /// The default of a property of a stream, as the schema gives it.
    fn default_of(&self, stream: &str, key: &str) -> Option<PropValue> {
        let param = self
            .schema
            .stream(stream)?
            .props
            .iter()
            .find(|param| param.key == key)?;
        match &param.value {
            ParamValue::Number { default, .. } => default.map(PropValue::Number),
            ParamValue::Switch { default } => default.map(PropValue::Switch),
            ParamValue::Choice { default, .. } | ParamValue::Text { default } => {
                default.clone().map(PropValue::Text)
            }
            _ => None,
        }
    }

    /// Whether a converter of the schema takes `given` and gives `wanted`.
    fn converts(&self, given: Type<'s>, wanted: Type<'s>) -> bool {
        self.schema
            .producers
            .iter()
            .filter(|kind| kind.converts)
            .any(|kind| {
                let ports = self.schema.ports(kind);
                let input = ports.iter().find(|port| !port.out);
                let output = ports.iter().find(|port| port.out);
                match (input, output) {
                    (Some(input), Some(output)) => {
                        let (input, output) = (Type::of(input), Type::of(output));
                        input.stream == given.stream
                            && self.missing(given, input).is_none()
                            && output.stream == wanted.stream
                            && self.missing(output, wanted).is_none()
                    }
                    _ => false,
                }
            })
    }

    /// The wires as arrows between their ends: a cycle is an error at the
    /// wire that closes it.
    fn cycles(&mut self, document: &'s Document) {
        let wires: Vec<&Wire> = document.wires().collect();
        let mut next: HashMap<Place<'_>, Vec<usize>> = HashMap::new();
        for (index, wire) in wires.iter().enumerate() {
            next.entry(Place::of(&wire.from)).or_default().push(index);
        }
        let mut reported = HashSet::new();
        for (start, wire) in wires.iter().enumerate() {
            // A walk along the wires from the end of this one that comes
            // back to its start. Each path is a list of wires.
            let target = Place::of(&wire.from);
            let mut stack = vec![vec![start]];
            let mut seen = HashSet::new();
            while let Some(path) = stack.pop() {
                let here = Place::of(&wires[path[path.len() - 1]].to);
                if here == target {
                    let mut key = path.clone();
                    key.sort_unstable();
                    if reported.insert(key) {
                        let mut places: Vec<String> = path
                            .iter()
                            .map(|&index| Place::of(&wires[index].from).text())
                            .collect();
                        places.push(target.text());
                        let message = format!("the wires make a cycle: {}", places.join(" -> "));
                        let closing = path.iter().copied().max().unwrap_or(start);
                        self.error(Code::Cycle, wires[closing].trivia.span, message);
                    }
                    break;
                }
                if !seen.insert(here) {
                    continue;
                }
                for &following in next.get(&here).map(Vec::as_slice).unwrap_or_default() {
                    let mut longer = path.clone();
                    longer.push(following);
                    stack.push(longer);
                }
            }
        }
    }
}

impl<'s> Type<'s> {
    fn of(port: &'s Port) -> Self {
        Self {
            stream: &port.stream,
            props: &port.props,
        }
    }
}

/// An end as a place of the graph: the ports of a node are one place.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
enum Place<'a> {
    Node(&'a str),
    Lane(&'a str),
    Outside(&'a str),
}

impl<'a> Place<'a> {
    fn of(end: &'a End) -> Self {
        match end {
            End::Node { id, .. } => Self::Node(id),
            End::Lane(lane) => Self::Lane(lane),
            End::Outside(path) => Self::Outside(path),
        }
    }

    fn text(self) -> String {
        match self {
            Self::Node(id) => format!("#{id}"),
            Self::Lane(lane) => format!("\"{lane}\""),
            Self::Outside(path) => format!("@\"{path}\""),
        }
    }
}

/// An end as the text writes it, for a message.
pub(crate) fn end_text(end: &End) -> String {
    match end {
        End::Node { id, port: None } => format!("`#{id}`"),
        End::Node {
            id,
            port: Some(port),
        } => format!("`#{id}.{port}`"),
        End::Lane(lane) => format!("\"{lane}\""),
        End::Outside(path) => format!("@\"{path}\""),
    }
}

fn stream_list(types: &[Type<'_>]) -> String {
    let mut streams: Vec<&str> = types.iter().map(|ty| ty.stream).collect();
    streams.dedup();
    if streams.is_empty() {
        "nothing".into()
    } else {
        streams.join(" or ")
    }
}
