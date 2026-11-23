//! The check: a parsed chain against the schema of a host. It finds what
//! the parser cannot know: an unknown kind or parameter, a value of the
//! wrong type, unit or range, two items with one id, a reference to a
//! later node, a link out of its container, and a split with the wrong
//! number of branches.

use std::collections::{HashMap, HashSet};

use crate::diagnostic::{Code, Diagnostic, Span, did_you_mean};
use crate::print::value_text;
use crate::schema::{Count, Param, ParamValue, Schema};
use crate::tree::{Body, Content, Document, Field, Mods, Node};
use crate::value::{Dimension, Number, Reference, Unit, Value};

/// Each problem of `document` under `schema`, in the order of the text.
pub fn check(document: &Document, schema: &Schema) -> Vec<Diagnostic> {
    let order: HashMap<&str, usize> = document
        .nodes()
        .iter()
        .enumerate()
        .filter_map(|(index, node)| Some((node.id.as_deref()?, index)))
        .collect();
    let mut checker = Checker { schema, diagnostics: Vec::new(), order, position: 0 };
    checker.ids(document);
    checker.body(&document.root, None);
    checker.diagnostics.sort_by_key(|diagnostic| (diagnostic.span.start, diagnostic.span.end));
    checker.diagnostics
}

struct Checker<'s> {
    schema: &'s Schema,
    diagnostics: Vec<Diagnostic>,
    /// The place of each node with an id in signal order, for references.
    order: HashMap<&'s str, usize>,
    /// The place in signal order of the node that the check is at.
    position: usize,
}

/// The parameters of a kind, or none when the schema says that any key is allowed.
type Params<'s> = Option<&'s [Param]>;

impl<'s> Checker<'s> {
    fn error(&mut self, code: Code, span: Span, message: impl Into<String>) {
        self.diagnostics.push(Diagnostic::new(code, span, message));
    }

    /// Two items with one id, and the id that `@in` keeps.
    fn ids(&mut self, document: &Document) {
        let mut seen = HashSet::new();
        let mut ids: Vec<(&str, Span)> = Vec::new();
        collect_ids(&document.root, &mut ids);
        for (id, span) in ids {
            if id == "in" {
                self.error(Code::DuplicateId, span, "the id `in` is kept for `@in`, the input of the chain");
            } else if !seen.insert(id) {
                self.error(Code::DuplicateId, span, format!("two items have the id `#{id}`"));
            }
        }
    }

    /// The nodes of a body and their modulators. `split` is the kind of the
    /// split that holds the body, for the fields of its branches.
    fn body(&mut self, body: &'s Body, split: Option<&'s crate::schema::SplitKind>) {
        match &body.content {
            Content::Nodes(nodes) => nodes.iter().for_each(|node| self.node(node)),
            Content::Branches(branches) => {
                for branch in branches {
                    if let Some(split) = split {
                        self.fields(&branch.fields, Some(&split.branch_params), branch.trivia.span);
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
        if let Some(device) = schema.device(&node.kind) {
            if has_body {
                let message = format!("`{}` is a device, so it holds no nodes; only a split does", node.kind);
                self.error(Code::NotSplit, span, message);
            }
            let params = (!device.open_params).then_some(device.params.as_slice());
            self.fields_at(&node.fields, params, span, position);
        } else {
            self.unknown_kind(&node.kind, span);
            self.fields_at(&node.fields, None, span, position);
        }
        self.body(&node.body, None);
    }

    fn unknown_kind(&mut self, kind: &str, span: Span) {
        if self.schema.is_open(kind) {
            let message = format!("`{kind}` is not installed: its fields stay as they are written, with no check");
            self.error(Code::UnknownPlugin, span, message);
            return;
        }
        let schema = self.schema;
        let kinds = schema.devices.iter().map(|k| k.kind.as_str()).chain(schema.splits.iter().map(|k| k.kind.as_str()));
        let message = format!("no kind `{kind}`{}", did_you_mean(kind, kinds).unwrap_or_default());
        self.error(Code::UnknownKind, span, message);
    }

    fn mods(&mut self, mods: &'s Mods, body: &'s Body, split: Option<&'s crate::schema::SplitKind>) {
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
                    let message = format!("no modulator `{}`{}", modulator.kind, did_you_mean(&modulator.kind, kinds).unwrap_or_default());
                    self.error(Code::UnknownKind, span, message);
                }
            }
            for link in &modulator.links {
                let span = link.span.0;
                let Some(params) = targets.get(link.target.as_str()) else {
                    let message = format!("`#{}` is not a node or a branch in this container", link.target);
                    self.error(Code::Link, span, message);
                    continue;
                };
                let Some(params) = params else { continue };
                let Some(param) = params.iter().find(|param| param.key == link.key) else {
                    let keys = params.iter().map(|param| param.key.as_str());
                    let message =
                        format!("`#{}` has no parameter `{}`{}", link.target, link.key, did_you_mean(&link.key, keys).unwrap_or_default());
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
        schema.device(kind).filter(|device| !device.open_params).map(|device| device.params.as_slice())
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
                let message =
                    format!("a depth on `{}` is a number in {wanted} or in %, not `{}`", param.key, value_text(other));
                self.error(Code::WrongUnit, span, message);
            }
        }
    }

    fn fields(&mut self, fields: &[Field], params: Params<'_>, line: Span) {
        let position = self.position;
        self.fields_at(fields, params, line, position);
    }

    /// The fields of a line at `position` in signal order.
    fn fields_at(&mut self, fields: &[Field], params: Params<'_>, line: Span, position: usize) {
        let mut seen = HashSet::new();
        for field in fields {
            let span = if field.span.0 == Span::default() { line } else { field.span.0 };
            if !seen.insert(field.key.as_str()) {
                self.error(Code::DuplicateParameter, span, format!("`{}` is set twice on this line", field.key));
            }
            self.references(&field.value, span, position);
            let Some(params) = params else { continue };
            match params.iter().find(|param| param.key == field.key) {
                Some(param) => self.value(&field.value, param, span),
                None => {
                    let keys = params.iter().map(|param| param.key.as_str());
                    let message = format!("no parameter `{}`{}", field.key, did_you_mean(&field.key, keys).unwrap_or_default());
                    self.error(Code::UnknownParameter, span, message);
                }
            }
        }
    }

    /// Each `@id` must name a node that the signal meets before this one.
    fn references(&mut self, value: &Value, span: Span, position: usize) {
        match value {
            Value::Reference(Reference::Node(id)) => match self.order.get(id.as_str()) {
                None => self.error(Code::Reference, span, format!("no node has the id `#{id}`")),
                Some(&at) if at == position => {
                    self.error(Code::Reference, span, format!("`@{id}` is the node itself: a node cannot listen to its own output"));
                }
                Some(&at) if at > position => {
                    let message = format!("`@{id}` comes later in the signal: a node can only listen to a node before it");
                    self.error(Code::Reference, span, message);
                }
                Some(_) => {}
            },
            Value::List(values) => values.iter().for_each(|value| self.references(value, span, position)),
            _ => {}
        }
    }

    /// A value against its parameter.
    fn value(&mut self, value: &Value, param: &Param, span: Span) {
        let key = &param.key;
        let shown = format!("`{}`", value_text(value));
        match (&param.value, value) {
            (ParamValue::Number { unit, min, max, integer, .. }, Value::Number(number)) => {
                if self.number(number, *unit, *min, *max, key, span) && *integer && number.value.fract() != 0.0 {
                    self.error(Code::Range, span, format!("`{key}` takes a whole number, not {shown}"));
                }
            }
            (ParamValue::Switch { .. }, Value::Text(text)) if text == "on" || text == "off" => {}
            (ParamValue::Switch { .. }, _) => {
                self.error(Code::Type, span, format!("`{key}` is a switch: write `on` or `off`, not {shown}"));
            }
            (ParamValue::Choice { choices, .. }, Value::Text(text)) => {
                if !choices.contains(text) {
                    let hint = did_you_mean(text, choices.iter().map(String::as_str))
                        .unwrap_or_else(|| format!("; the choices are {}", choices.join(" ")));
                    let message = format!("`{key}` has no choice {shown}{hint}");
                    self.error(Code::Type, span, message);
                }
            }
            (ParamValue::Text { .. }, Value::Text(_))
            | (ParamValue::Note { .. }, Value::Note(_))
            | (ParamValue::Source, Value::Reference(_) | Value::Text(_)) => {}
            (ParamValue::List { unit, min, max, count, ascending }, value) => {
                let numbers: Vec<&Value> = match value {
                    Value::List(values) => values.iter().collect(),
                    single => vec![single],
                };
                if let Some(count) = count
                    && !count.contains(numbers.len())
                {
                    let message = format!("`{key}` takes {} values, not {}", range_text(*count), numbers.len());
                    self.error(Code::List, span, message);
                }
                let mut last: Option<f64> = None;
                for item in numbers {
                    let Value::Number(number) = item else {
                        self.error(Code::Type, span, format!("`{key}` takes numbers, not `{}`", value_text(item)));
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
    fn number(&mut self, number: &Number, unit: Option<Unit>, min: Option<f64>, max: Option<f64>, key: &str, span: Span) -> bool {
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
                    value_text(&Value::Number(Number { value: base(limit), dimension: number.dimension }))
                })
            };
            let message = format!("`{key}` goes from {} to {}, so {shown} is out of range", limit(min), limit(max));
            self.error(Code::Range, span, message);
        }
        true
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
            out.extend(modulator.id.as_deref().map(|id| (id, modulator.trivia.span)));
        }
    }
}

fn range_text(count: Count) -> String {
    if count.min == count.max { count.min.to_string() } else { format!("{} to {}", count.min, count.max) }
}

fn wanted(kind: &ParamValue) -> &'static str {
    match kind {
        ParamValue::Number { .. } => "a number",
        ParamValue::Switch { .. } => "`on` or `off`",
        ParamValue::Choice { .. } => "one of its choices",
        ParamValue::Text { .. } => "a text",
        ParamValue::Note { .. } => "a note value such as `1/4`",
        ParamValue::List { .. } => "numbers separated by commas",
        ParamValue::Source => "a source: `@id`, `@in` or a name",
    }
}
