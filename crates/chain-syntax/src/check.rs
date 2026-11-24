//! The check: a parsed text against the schema of a host and, when the
//! host gives one, the context of the text. It finds what the parser
//! cannot know: an unknown kind or parameter, a value of the wrong type,
//! unit or range, two items with one id, a reference to a later node, a
//! link out of its container, a split with the wrong number of branches,
//! an insert that does not run live, and a stream of the wrong type
//! between two inserts in series. The wires of version 2 are checked in
//! `graph.rs`.

#![expect(
    clippy::too_many_lines,
    reason = "debt: pay down"
)]

use std::collections::{BTreeSet, HashMap, HashSet};

use crate::context::{Context, OutsideEnd};
use crate::diagnostic::{Code, Diagnostic, Span, did_you_mean};
use crate::print::value_text;
use crate::schema::{Count, Param, ParamValue, Schema, SplitKind, Tier};
use crate::tree::{Body, Content, Document, Field, Mods, Node, VERSION_1};
use crate::value::{Dimension, Number, Reference, Unit, Value};

/// Each problem of `document` under `schema` and `context`, in the order
/// of the text.
pub fn check(document: &Document, schema: &Schema, context: Option<&Context>) -> Vec<Diagnostic> {
    let mut checker = Checker {
        schema,
        context,
        diagnostics: Vec::new(),
        reach: Reach::Before(HashMap::new()),
        position: 0,
    };
    checker.ids(document);
    if document.header.version == VERSION_1 {
        let input = checker.strip_input(None);
        checker.chain(&document.root, input);
    } else {
        checker.graph(document);
    }
    checker
        .diagnostics
        .sort_by_key(|diagnostic| (diagnostic.span.start, diagnostic.span.end));
    checker.diagnostics
}

pub(crate) struct Checker<'s> {
    pub(crate) schema: &'s Schema,
    pub(crate) context: Option<&'s Context>,
    pub(crate) diagnostics: Vec<Diagnostic>,
    /// What an `@id` in a field may name.
    pub(crate) reach: Reach<'s>,
    /// The place in signal order of the node that the check is at.
    position: usize,
}

/// What an `@id` in a field may name.
pub(crate) enum Reach<'s> {
    /// In a chain of inserts: a node of the chain before this one, by the
    /// place of each node with an id in signal order.
    Before(HashMap<&'s str, usize>),
    /// On a node line of version 2: any node line of the text.
    Any(HashSet<&'s str>),
}

/// The parameters of a kind, or none when the schema says that any key is allowed.
type Params<'s> = Option<&'s [Param]>;

/// The kinds of stream that reach a place of a chain of inserts.
type Streams<'s> = BTreeSet<&'s str>;

impl<'s> Checker<'s> {
    pub(crate) fn error(&mut self, code: Code, span: Span, message: impl Into<String>) {
        self.diagnostics.push(Diagnostic::new(code, span, message));
    }

    /// Two items with one id, and the id that `@in` keeps.
    fn ids(&mut self, document: &'s Document) {
        let mut seen = HashSet::new();
        let mut ids: Vec<(&str, Span)> = Vec::new();
        collect_ids(&document.root, &mut ids);
        for node in document.graph_nodes() {
            ids.extend(node.id.as_deref().map(|id| (id, node.trivia.span)));
            collect_ids(&node.inserts, &mut ids);
        }
        for (id, span) in ids {
            if id == "in" {
                self.error(
                    Code::DuplicateId,
                    span,
                    "the id `in` is kept for `@in`, the input of the chain",
                );
            } else if !seen.insert(id) {
                self.error(
                    Code::DuplicateId,
                    span,
                    format!("two items have the id `#{id}`"),
                );
            }
        }
    }

    /// The kinds of stream that come into a strip: the inputs of the role
    /// `strip` (or `role`) in the schema, else its default inputs. None
    /// when the schema has no streams: the streams are then not checked.
    pub(crate) fn strip_input(&self, kind: Option<&'s crate::schema::Kind>) -> Option<Streams<'s>> {
        let schema = self.schema;
        if schema.streams.is_empty() {
            return None;
        }
        let kind = kind.or_else(|| schema.graph_kind(crate::tree::Role::Strip, None));
        let ports = kind.map_or(schema.default_ports.as_slice(), |kind| schema.ports(kind));
        Some(
            ports
                .iter()
                .filter(|port| !port.out)
                .map(|port| port.stream.as_str())
                .collect(),
        )
    }

    /// A chain of inserts: its nodes, its modulators and, when `input` gives
    /// the streams that come into it, the streams between its nodes.
    pub(crate) fn chain(&mut self, body: &'s Body, input: Option<Streams<'s>>) {
        let order = body
            .nodes()
            .into_iter()
            .enumerate()
            .filter_map(|(index, node)| Some((node.id.as_deref()?, index)))
            .collect();
        self.reach = Reach::Before(order);
        self.position = 0;
        self.body(body, None);
        if let Some(input) = input {
            self.streams_of(body, input);
        }
    }

    /// The nodes of a body and their modulators. `split` is the kind of the
    /// split that holds the body, for the fields of its branches.
    fn body(&mut self, body: &'s Body, split: Option<&'s SplitKind>) {
        match &body.content {
            Content::Nodes(nodes) => nodes.iter().for_each(|node| self.node(node)),
            Content::Branches(branches) => {
                for branch in branches {
                    if let Some(split) = split {
                        self.fields(
                            &branch.fields,
                            Some(&split.branch_params),
                            branch.trivia.span,
                        );
                    }
                    branch.nodes.iter().for_each(|node| self.node(node));
                }
            }
        }
        if let Some(mods) = &body.mods {
            self.mods(mods, body, split);
        }
    }

    fn node(&mut self, node: &'s Node) {
        let span = node.trivia.span;
        let position = self.position;
        self.position += 1;
        let schema = self.schema;
        let has_body = !node.body.is_empty();
        if let Some(split) = schema.split(&node.kind) {
            self.fields_at(&node.fields, Some(&split.params), span, position);
            let count = match &node.body.content {
                Content::Branches(branches) => branches.len(),
                Content::Nodes(_) => 1,
            };
            if !split.branches.contains(count) {
                let message = format!(
                    "a `{}` split takes {} branches; this one has {count}",
                    node.kind,
                    range_text(split.branches)
                );
                self.error(Code::Branches, span, message);
            }
            self.body(&node.body, Some(split));
            return;
        }
        if let Some(kind) = schema.insert(&node.kind) {
            if has_body {
                let message = format!(
                    "`{}` is a device, so it holds no nodes; only a split does",
                    node.kind
                );
                self.error(Code::NotSplit, span, message);
            }
            if kind.tier != Tier::Live {
                let message = format!(
                    "`{}` runs in tier {}, so it cannot be an insert, which runs live: make it a `producer` line and store its output in a lane with `=>`",
                    node.kind,
                    kind.tier.as_str()
                );
                self.error(Code::NotLive, span, message);
            }
            let params = (!kind.open_params).then_some(kind.params.as_slice());
            self.fields_at(&node.fields, params, span, position);
        } else {
            self.unknown_kind(&node.kind, span);
            self.fields_at(&node.fields, None, span, position);
        }
        self.body(&node.body, None);
    }

    pub(crate) fn unknown_kind(&mut self, kind: &str, span: Span) {
        if self.schema.is_open(kind) {
            let message = format!(
                "`{kind}` is not installed: its fields stay as they are written, with no check"
            );
            self.error(Code::UnknownPlugin, span, message);
            return;
        }
        let schema = self.schema;
        let kinds = schema
            .devices
            .iter()
            .map(|k| k.kind.as_str())
            .chain(schema.splits.iter().map(|k| k.kind.as_str()));
        let message = format!(
            "no kind `{kind}`{}",
            did_you_mean(kind, kinds).unwrap_or_default()
        );
        self.error(Code::UnknownKind, span, message);
    }

    fn mods(&mut self, mods: &'s Mods, body: &'s Body, split: Option<&'s SplitKind>) {
        let schema = self.schema;
        // The targets that a link may name: the nodes and branches in the container.
        let mut targets: HashMap<&str, Params<'s>> = HashMap::new();
        if let Some(split) = split {
            for branch in body.branches() {
                if let Some(id) = &branch.id {
                    targets.insert(id, Some(&split.branch_params));
                }
            }
        }
        for node in body.nodes() {
            if let Some(id) = &node.id {
                targets.insert(id, self.params_of(&node.kind));
            }
            if let Some(split) = schema.split(&node.kind) {
                for branch in node.body.branches() {
                    if let Some(id) = &branch.id {
                        targets.insert(id, Some(&split.branch_params));
                    }
                }
            }
        }
        for modulator in &mods.modulators {
            let span = modulator.trivia.span;
            match schema.modulator(&modulator.kind) {
                Some(kind) => {
                    let params = (!kind.open_params).then_some(kind.params.as_slice());
                    self.fields(&modulator.fields, params, span);
                }
                None => {
                    let kinds = schema.modulators.iter().map(|k| k.kind.as_str());
                    let message = format!(
                        "no modulator `{}`{}",
                        modulator.kind,
                        did_you_mean(&modulator.kind, kinds).unwrap_or_default()
                    );
                    self.error(Code::UnknownKind, span, message);
                }
            }
            for link in &modulator.links {
                let span = link.span.0;
                let Some(params) = targets.get(link.target.as_str()) else {
                    let message = format!(
                        "`#{}` is not a node or a branch in this container",
                        link.target
                    );
                    self.error(Code::Link, span, message);
                    continue;
                };
                let Some(params) = params else { continue };
                let Some(param) = params.iter().find(|param| param.key == link.key) else {
                    let keys = params.iter().map(|param| param.key.as_str());
                    let message = format!(
                        "`#{}` has no parameter `{}`{}",
                        link.target,
                        link.key,
                        did_you_mean(&link.key, keys).unwrap_or_default()
                    );
                    self.error(Code::Link, span, message);
                    continue;
                };
                self.depth(&link.depth, param, span);
            }
        }
    }

    /// The parameters of a kind, as a link target sees them.
    fn params_of(&self, kind: &str) -> Params<'s> {
        let schema = self.schema;
        if let Some(split) = schema.split(kind) {
            return Some(&split.params);
        }
        schema
            .insert(kind)
            .filter(|device| !device.open_params)
            .map(|device| device.params.as_slice())
    }

    /// A modulation depth: a number in the unit of the parameter, or in %.
    fn depth(&mut self, depth: &Value, param: &Param, span: Span) {
        let unit = match &param.value {
            ParamValue::Number { unit, .. } | ParamValue::List { unit, .. } => *unit,
            _ => {
                let message = format!("`{}` is not a number, so it cannot be modulated", param.key);
                self.error(Code::Link, span, message);
                return;
            }
        };
        let fits = |number: &Number| {
            number.dimension.is_none_or(|dimension| {
                dimension == Dimension::Percent || Some(dimension) == unit.map(Unit::dimension)
            })
        };
        match depth {
            Value::Number(number) if fits(number) => {}
            other => {
                let wanted = unit.map_or("no unit".to_string(), |unit| unit.as_str().to_string());
                let message = format!(
                    "a depth on `{}` is a number in {wanted} or in %, not `{}`",
                    param.key,
                    value_text(other)
                );
                self.error(Code::WrongUnit, span, message);
            }
        }
    }

    /// The fields of a line that is not a node of a chain: a branch, a
    /// modulator or a node line of version 2. Its place in signal order is
    /// before the next node, so a reference reaches each node that comes
    /// before that place.
    pub(crate) fn fields(&mut self, fields: &[Field], params: Params<'_>, line: Span) {
        let position = self.position;
        self.fields_at(fields, params, line, position);
    }

    /// The fields of a line at `position` in signal order.
    fn fields_at(&mut self, fields: &[Field], params: Params<'_>, line: Span, position: usize) {
        let mut seen = HashSet::new();
        for field in fields {
            let span = if field.span.0 == Span::default() {
                line
            } else {
                field.span.0
            };
            if !seen.insert(field.key.as_str()) {
                self.error(
                    Code::DuplicateParameter,
                    span,
                    format!("`{}` is set twice on this line", field.key),
                );
            }
            self.references(&field.value, span, position);
            let Some(params) = params else { continue };
            match params.iter().find(|param| param.key == field.key) {
                Some(param) => self.value(&field.value, param, span),
                None => {
                    let keys = params.iter().map(|param| param.key.as_str());
                    let message = format!(
                        "no parameter `{}`{}",
                        field.key,
                        did_you_mean(&field.key, keys).unwrap_or_default()
                    );
                    self.error(Code::UnknownParameter, span, message);
                }
            }
        }
    }

    /// Each `@id` must name a node that the field can reach, and each
    /// `@"path"` a stream that the context has.
    fn references(&mut self, value: &Value, span: Span, position: usize) {
        match value {
            Value::Reference(Reference::Node(id)) => {
                match &self.reach {
                    Reach::Any(ids) if ids.contains(id.as_str()) => {}
                    Reach::Any(_) => self.error(
                        Code::Reference,
                        span,
                        format!("no node line has the id `#{id}`"),
                    ),
                    Reach::Before(order) => match order.get(id.as_str()) {
                        None => self.error(
                            Code::Reference,
                            span,
                            format!("no node of this chain has the id `#{id}`"),
                        ),
                        Some(&at) if at == position => {
                            self.error(Code::Reference, span, format!("`@{id}` is the node itself: a node cannot listen to its own output"));
                        }
                        Some(&at) if at > position => {
                            let message = format!(
                                "`@{id}` comes later in the signal: a node can only listen to a node before it"
                            );
                            self.error(Code::Reference, span, message);
                        }
                        Some(_) => {}
                    },
                }
            }
            Value::Reference(Reference::Outside(path)) => {
                self.outside_stream(path, span);
            }
            Value::List(values) => values
                .iter()
                .for_each(|value| self.references(value, span, position)),
            _ => {}
        }
    }

    /// The stream of the lane at an outside path, when the context has it.
    /// A path that the context does not have gives W302.
    pub(crate) fn outside_stream(&mut self, path: &str, span: Span) -> Option<&'s str> {
        let found = self.context.map(|context| context.outside(path));
        match found {
            Some(Some(outside)) => match &outside.end {
                OutsideEnd::Lane { stream, .. } => Some(stream.as_str()),
                OutsideEnd::Node { .. } => None,
            },
            Some(None) => {
                let message =
                    format!("the context of the host has no @\"{path}\": its type is not checked");
                self.error(Code::UnknownOutside, span, message);
                None
            }
            None => {
                let message =
                    format!("no context of the host: the type of @\"{path}\" is not checked");
                self.error(Code::UnknownOutside, span, message);
                None
            }
        }
    }

    /// A value against its parameter.
    fn value(&mut self, value: &Value, param: &Param, span: Span) {
        let key = &param.key;
        let shown = format!("`{}`", value_text(value));
        match (&param.value, value) {
            (
                ParamValue::Number {
                    unit,
                    min,
                    max,
                    integer,
                    ..
                },
                Value::Number(number),
            ) => {
                if self.number(number, *unit, *min, *max, key, span)
                    && *integer
                    && number.value.fract() != 0.0
                {
                    self.error(
                        Code::Range,
                        span,
                        format!("`{key}` takes a whole number, not {shown}"),
                    );
                }
            }
            (ParamValue::Switch { .. }, Value::Text(text)) if text == "on" || text == "off" => {}
            (ParamValue::Switch { .. }, _) => {
                self.error(
                    Code::Type,
                    span,
                    format!("`{key}` is a switch: write `on` or `off`, not {shown}"),
                );
            }
            (ParamValue::Choice { choices, .. }, Value::Text(text)) => {
                if !choices.contains(text) {
                    let hint = did_you_mean(text, choices.iter().map(String::as_str))
                        .unwrap_or_else(|| format!("; the choices are {}", choices.join(" ")));
                    let message = format!("`{key}` has no choice {shown}{hint}");
                    self.error(Code::Type, span, message);
                }
            }
            (
                ParamValue::Source {
                    stream: Some(wanted),
                    ..
                },
                Value::Reference(Reference::Outside(path)),
            ) => {
                let given = self
                    .context
                    .and_then(|context| context.outside(path))
                    .and_then(|outside| match &outside.end {
                        OutsideEnd::Lane { stream, .. } => Some(stream),
                        OutsideEnd::Node { .. } => None,
                    });
                if let Some(given) = given.filter(|given| *given != wanted) {
                    let message = format!("`{key}` takes {wanted}, and @\"{path}\" gives {given}");
                    self.error(Code::StreamType, span, message);
                }
            }
            (ParamValue::Text { .. }, Value::Text(_))
            | (ParamValue::Note { .. }, Value::Note(_))
            | (ParamValue::Source { .. }, Value::Reference(_) | Value::Text(_)) => {}
            (
                ParamValue::List {
                    unit,
                    min,
                    max,
                    count,
                    ascending,
                },
                value,
            ) => {
                let numbers: Vec<&Value> = match value {
                    Value::List(values) => values.iter().collect(),
                    single => vec![single],
                };
                if let Some(count) = count
                    && !count.contains(numbers.len())
                {
                    let message = format!(
                        "`{key}` takes {} values, not {}",
                        range_text(*count),
                        numbers.len()
                    );
                    self.error(Code::List, span, message);
                }
                let mut last: Option<f64> = None;
                for item in numbers {
                    let Value::Number(number) = item else {
                        self.error(
                            Code::Type,
                            span,
                            format!("`{key}` takes numbers, not `{}`", value_text(item)),
                        );
                        continue;
                    };
                    self.number(number, *unit, *min, *max, key, span);
                    if *ascending && last.is_some_and(|last| number.value <= last) {
                        let message = format!("the values of `{key}` must go up: {shown}");
                        self.error(Code::List, span, message);
                    }
                    last = Some(number.value);
                }
            }
            (kind, _) => {
                let message = format!("`{key}` takes {}, not {shown}", wanted(kind));
                self.error(Code::Type, span, message);
            }
        }
    }

    /// A number against the unit and the range of its parameter. Returns
    /// whether it has the right unit.
    fn number(
        &mut self,
        number: &Number,
        unit: Option<Unit>,
        min: Option<f64>,
        max: Option<f64>,
        key: &str,
        span: Span,
    ) -> bool {
        let shown = format!("`{}`", value_text(&Value::Number(*number)));
        if number.dimension != unit.map(Unit::dimension) {
            let message = match unit {
                Some(unit) => format!("`{key}` takes a number in {}, not {shown}", unit.as_str()),
                None => format!("`{key}` takes a number with no unit, not {shown}"),
            };
            self.error(Code::WrongUnit, span, message);
            return false;
        }
        let base = |limit: f64| unit.map_or(limit, |unit| unit.to_base(limit));
        let below = min.is_some_and(|min| number.value < base(min));
        let above = max.is_some_and(|max| number.value > base(max));
        if below || above {
            let limit = |limit: Option<f64>| {
                limit.map_or("any".to_string(), |limit| {
                    value_text(&Value::Number(Number {
                        value: base(limit),
                        dimension: number.dimension,
                    }))
                })
            };
            let message = format!(
                "`{key}` goes from {} to {}, so {shown} is out of range",
                limit(min),
                limit(max)
            );
            self.error(Code::Range, span, message);
        }
        true
    }

    /// The streams after the nodes of a body, from the streams that come
    /// into it. A node takes the streams of its main inputs and gives the
    /// streams of its outputs. A stream that it does not take passes it, so
    /// MIDI passes an effect of audio. A main input that no stream before
    /// it gives is an error.
    fn streams_of(&mut self, body: &'s Body, input: Streams<'s>) -> Streams<'s> {
        match &body.content {
            Content::Nodes(nodes) => nodes
                .iter()
                .fold(input, |streams, node| self.streams_at(node, streams)),
            Content::Branches(branches) => {
                let mut out = Streams::new();
                for branch in branches {
                    let through = branch.nodes.iter().fold(input.clone(), |streams, node| {
                        self.streams_at(node, streams)
                    });
                    out.extend(through);
                }
                out
            }
        }
    }

    fn streams_at(&mut self, node: &'s Node, mut streams: Streams<'s>) -> Streams<'s> {
        let schema = self.schema;
        if schema.split(&node.kind).is_some() {
            return self.streams_of(&node.body, streams);
        }
        let Some(kind) = schema.insert(&node.kind) else {
            return streams;
        };
        let ports = schema.ports(kind);
        for port in ports.iter().filter(|port| port.main && !port.out) {
            if !streams.contains(port.stream.as_str()) {
                let given: Vec<&str> = streams.iter().copied().collect();
                let given = if given.is_empty() {
                    "nothing".to_string()
                } else {
                    given.join(" and ")
                };
                let message = format!(
                    "`{}` takes {} at `{}`, and the inserts before it give {given}",
                    node.kind, port.stream, port.port
                );
                self.error(Code::StreamType, node.trivia.span, message);
            }
        }
        for port in ports.iter().filter(|port| port.main && !port.out) {
            streams.remove(port.stream.as_str());
        }
        streams.extend(
            ports
                .iter()
                .filter(|port| port.out)
                .map(|port| port.stream.as_str()),
        );
        streams
    }
}

/// The ids of the nodes, branches and modulators of a body, in the order of the text.
fn collect_ids<'a>(body: &'a Body, out: &mut Vec<(&'a str, Span)>) {
    match &body.content {
        Content::Nodes(nodes) => {
            for node in nodes {
                out.extend(node.id.as_deref().map(|id| (id, node.trivia.span)));
                collect_ids(&node.body, out);
            }
        }
        Content::Branches(branches) => {
            for branch in branches {
                out.extend(branch.id.as_deref().map(|id| (id, branch.trivia.span)));
                for node in &branch.nodes {
                    out.extend(node.id.as_deref().map(|id| (id, node.trivia.span)));
                    collect_ids(&node.body, out);
                }
            }
        }
    }
    if let Some(mods) = &body.mods {
        for modulator in &mods.modulators {
            out.extend(
                modulator
                    .id
                    .as_deref()
                    .map(|id| (id, modulator.trivia.span)),
            );
        }
    }
}

fn range_text(count: Count) -> String {
    if count.min == count.max {
        count.min.to_string()
    } else {
        format!("{} to {}", count.min, count.max)
    }
}

fn wanted(kind: &ParamValue) -> &'static str {
    match kind {
        ParamValue::Number { .. } => "a number",
        ParamValue::Switch { .. } => "`on` or `off`",
        ParamValue::Choice { .. } => "one of its choices",
        ParamValue::Text { .. } => "a text",
        ParamValue::Note { .. } => "a note value such as `1/4`",
        ParamValue::List { .. } => "numbers separated by commas",
        ParamValue::Source { .. } => "a source: `@id`, `@in`, `@\"path\"` or a name",
    }
}
