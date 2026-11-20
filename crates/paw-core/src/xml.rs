//! XML for the file formats of extensions (`paw.api.xml_decode`,
//! `xml_encode`): MusicXML, DAWproject, the states of JUCE plugins.
//!
//! An element is a Lua table `{ name, attr, order, children, text, span }`:
//! `attr` maps each attribute to its text, `order` lists the attributes as
//! they come, `children` the child elements, `text` the text and CDATA
//! directly in the element (nil when it has none). With spans asked for,
//! `span` says where the element is in the text, so that what is not changed
//! can be written back byte for byte: `{ from, open, close, to, lead, tail }`,
//! byte positions from 1: `from` its `<`, `open` the `>` of its start tag,
//! `close` the `<` of its end tag (nil for `<a/>`), `to` its last `>`, `lead`
//! where the text before it starts (after the sibling before it, or after
//! the parent's start tag), `tail` where the text after its last child
//! starts.

use std::borrow::Cow;

use mlua::{Lua, Table, Value as LuaValue};
use quick_xml::events::Event;
use quick_xml::reader::Reader;

fn utf8_of(text: &[u8]) -> Cow<'_, str> {
    // UTF-16 by its byte order mark, a UTF-8 one left out.
    let utf16 = |be: bool| {
        let units: Vec<u16> = text[2..]
            .chunks_exact(2)
            .map(|c| if be { u16::from_be_bytes([c[0], c[1]]) } else { u16::from_le_bytes([c[0], c[1]]) })
            .collect();
        Cow::Owned(String::from_utf16_lossy(&units))
    };
    match text {
        [0xFF, 0xFE, ..] => utf16(false),
        [0xFE, 0xFF, ..] => utf16(true),
        [0xEF, 0xBB, 0xBF, rest @ ..] => String::from_utf8_lossy(rest),
        _ => String::from_utf8_lossy(text),
    }
}

/// Text with its references read: the five named entities and character
/// references. Another entity (one a DTD defines) is kept as it is.
pub fn unescape(raw: &str) -> Cow<'_, str> {
    if !raw.contains('&') {
        return Cow::Borrowed(raw);
    }
    let mut out = String::with_capacity(raw.len());
    let mut rest = raw;
    while let Some(i) = rest.find('&') {
        out.push_str(&rest[..i]);
        rest = &rest[i..];
        let Some(end) = rest[1..].find(';').map(|e| e + 1).filter(|e| *e <= 12) else {
            out.push('&');
            rest = &rest[1..];
            continue;
        };
        if let Some(c) = reference(&rest[1..end]) {
            out.push(c);
        } else {
            out.push_str(&rest[..=end]);
        }
        rest = &rest[end + 1..];
    }
    out.push_str(rest);
    Cow::Owned(out)
}

fn reference(name: &str) -> Option<char> {
    match name {
        "amp" => Some('&'),
        "lt" => Some('<'),
        "gt" => Some('>'),
        "quot" => Some('"'),
        "apos" => Some('\''),
        _ => {
            let n = if let Some(hex) = name.strip_prefix("#x").or_else(|| name.strip_prefix("#X")) {
                u32::from_str_radix(hex, 16).ok()?
            } else {
                name.strip_prefix('#')?.parse().ok()?
            };
            char::from_u32(n)
        }
    }
}

struct Open {
    el: Table,
    text: Option<String>,
    span: Option<Table>,
    /// Where the text before the next child starts.
    next_lead: usize,
}

/// Read a document into its root element; the error says what is wrong and
/// at which byte.
pub fn decode(lua: &Lua, bytes: &[u8], spans: bool, meta: Option<Table>) -> mlua::Result<Result<Table, String>> {
    let text = utf8_of(bytes);
    // Spans are of the bytes as given: past a UTF-8 byte order mark, and
    // none for UTF-16 (read as UTF-8).
    let off = if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) { 3 } else { 0 };
    let spans = spans && !matches!(bytes, [0xFF, 0xFE, ..] | [0xFE, 0xFF, ..]);
    let mut reader = Reader::from_str(&text);
    let config = reader.config_mut();
    config.check_end_names = true;
    config.allow_dangling_amp = true;
    let mut stack: Vec<Open> = Vec::new();
    let mut root: Option<Table> = None;
    let fail = |reader: &Reader<&[u8]>, what: String| -> mlua::Result<Result<Table, String>> {
        Ok(Err(format!("the XML is broken at byte {}: {what}", reader.error_position() + 1)))
    };
    loop {
        let at = reader.buffer_position() as usize + off;
        let event = match reader.read_event() {
            Ok(e) => e,
            Err(e) => return fail(&reader, e.to_string()),
        };
        let end = reader.buffer_position() as usize + off;
        match event {
            Event::Start(ref e) | Event::Empty(ref e) => {
                let empty = matches!(event, Event::Empty(_));
                let el = lua.create_table()?;
                if let Some(meta) = &meta {
                    el.set_metatable(Some(meta.clone()))?;
                }
                el.set("name", String::from_utf8_lossy(e.name().as_ref()).as_ref())?;
                let attr = lua.create_table()?;
                let order = lua.create_table()?;
                for a in e.attributes() {
                    let a = match a {
                        Ok(a) => a,
                        Err(err) => return fail(&reader, err.to_string()),
                    };
                    let key = String::from_utf8_lossy(a.key.as_ref()).into_owned();
                    let value = String::from_utf8_lossy(&a.value);
                    attr.set(key.as_str(), unescape(&value).as_ref())?;
                    order.push(key)?;
                }
                el.set("attr", attr)?;
                el.set("order", order)?;
                el.set("children", lua.create_table()?)?;
                let span = if spans {
                    let s = lua.create_table()?;
                    s.set("from", at + 1)?;
                    s.set("open", end)?;
                    s.set("lead", stack.last().map_or(1 + off, |p| p.next_lead))?;
                    if empty {
                        s.set("to", end)?;
                    }
                    el.set("span", s.clone())?;
                    Some(s)
                } else {
                    None
                };
                if let Some(parent) = stack.last_mut() {
                    parent.el.get::<Table>("children")?.push(el.clone())?;
                    parent.next_lead = end + 1;
                } else if root.is_none() {
                    root = Some(el.clone());
                } else {
                    return fail(&reader, "there is more than one root element".into());
                }
                if !empty {
                    stack.push(Open { el, text: None, span, next_lead: end + 1 });
                } else if let Some(s) = &span {
                    s.set("tail", end + 1)?;
                }
            }
            Event::End(_) => {
                let Some(done) = stack.pop() else {
                    return fail(&reader, "an end tag closes nothing".into());
                };
                if let Some(s) = &done.span {
                    s.set("close", at + 1)?;
                    s.set("to", end)?;
                    s.set("tail", done.next_lead)?;
                }
                if let Some(t) = done.text {
                    done.el.set("text", t)?;
                }
                if let Some(parent) = stack.last_mut() {
                    parent.next_lead = end + 1;
                }
            }
            Event::Text(t) => {
                if let Some(top) = stack.last_mut() {
                    let raw = String::from_utf8_lossy(&t);
                    top.text.get_or_insert_with(String::new).push_str(&unescape(&raw));
                }
            }
            Event::GeneralRef(r) => {
                if let Some(top) = stack.last_mut() {
                    let name = String::from_utf8_lossy(&r);
                    let text = top.text.get_or_insert_with(String::new);
                    match reference(&name) {
                        Some(c) => text.push(c),
                        None => {
                            text.push('&');
                            text.push_str(&name);
                            text.push(';');
                        }
                    }
                }
            }
            Event::CData(c) => {
                if let Some(top) = stack.last_mut() {
                    top.text.get_or_insert_with(String::new).push_str(&String::from_utf8_lossy(&c));
                }
            }
            Event::Eof => break,
            _ => {}
        }
    }
    if let Some(open) = stack.last() {
        let name: String = open.el.get("name")?;
        return fail(&reader, format!("<{name}> is not closed"));
    }
    match root {
        Some(root) => Ok(Ok(root)),
        None => Ok(Err("there is no element in it".into())),
    }
}

/// Text made safe for XML: in an attribute's quotes, line ends and tabs
/// are written as references too.
pub fn escape(text: &str, attribute: bool) -> Cow<'_, str> {
    let special = |c: char| matches!(c, '&' | '<' | '>') || (attribute && matches!(c, '"' | '\n' | '\r' | '\t'));
    if !text.contains(special) {
        return Cow::Borrowed(text);
    }
    let mut out = String::with_capacity(text.len() + 8);
    for c in text.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' if attribute => out.push_str("&quot;"),
            '\n' if attribute => out.push_str("&#10;"),
            '\r' if attribute => out.push_str("&#13;"),
            '\t' if attribute => out.push_str("&#9;"),
            c => out.push(c),
        }
    }
    Cow::Owned(out)
}

pub struct EncodeOpts {
    /// Each level is indented by this, each element on a line of its own.
    pub indent: Option<String>,
    /// The most digits after the point of a number; the shortest text that
    /// reads back the same without.
    pub digits: Option<usize>,
    /// The text the tree was read from, with spans.
    pub source: Option<Vec<u8>>,
}

fn number_text(n: f64, digits: Option<usize>) -> String {
    if n.fract() == 0.0 && n.abs() < 1e15 {
        return format!("{}", n as i64);
    }
    match digits {
        Some(d) => {
            let s = format!("{n:.d$}");
            let s = s.trim_end_matches('0');
            s.trim_end_matches('.').to_string()
        }
        None => format!("{n}"),
    }
}

fn value_text(v: &LuaValue, digits: Option<usize>) -> mlua::Result<Option<String>> {
    Ok(match v {
        LuaValue::Nil => None,
        LuaValue::String(s) => Some(s.to_string_lossy()),
        LuaValue::Integer(i) => Some(i.to_string()),
        LuaValue::Number(n) => Some(number_text(*n, digits)),
        LuaValue::Boolean(b) => Some(if *b { "true" } else { "false" }.to_string()),
        other => return Err(mlua::Error::runtime(format!("an attribute cannot be a {}", other.type_name()))),
    })
}

/// The attributes as they are written: those of `order` first, then the
/// others by name.
fn attributes(el: &Table, digits: Option<usize>) -> mlua::Result<Vec<(String, String)>> {
    let mut out = Vec::new();
    let Some(attr) = el.get::<Option<Table>>("attr")? else { return Ok(out) };
    let mut seen = std::collections::HashSet::new();
    if let Some(order) = el.get::<Option<Table>>("order")? {
        for key in order.sequence_values::<String>() {
            let key = key?;
            if seen.contains(&key) {
                continue;
            }
            if let Some(text) = value_text(&attr.get::<LuaValue>(key.as_str())?, digits)? {
                seen.insert(key.clone());
                out.push((key, text));
            }
        }
    }
    let mut rest = Vec::new();
    for pair in attr.pairs::<String, LuaValue>() {
        let (key, value) = pair?;
        if !seen.contains(&key)
            && let Some(text) = value_text(&value, digits)?
        {
            rest.push((key, text));
        }
    }
    rest.sort();
    out.extend(rest);
    Ok(out)
}

/// What a start tag in the source says: its name, and each attribute with
/// its text as written and as read.
fn source_tag(tag: &[u8]) -> Option<(String, Vec<(String, String, String)>)> {
    let mut reader = Reader::from_reader(tag);
    reader.config_mut().check_end_names = false;
    match reader.read_event().ok()? {
        Event::Start(e) | Event::Empty(e) => {
            let name = String::from_utf8_lossy(e.name().as_ref()).into_owned();
            let mut attrs = Vec::new();
            for a in e.attributes() {
                let a = a.ok()?;
                let raw = String::from_utf8_lossy(&a.value).into_owned();
                let read = unescape(&raw).into_owned();
                attrs.push((String::from_utf8_lossy(a.key.as_ref()).into_owned(), raw, read));
            }
            Some((name, attrs))
        }
        _ => None,
    }
}

/// The text directly in the source between two positions (0-based, end
/// excluded), outside the child elements.
fn source_text(src: &[u8], from: usize, to: usize) -> Option<String> {
    let mut reader = Reader::from_reader(&src[from..to]);
    let config = reader.config_mut();
    config.check_end_names = false;
    config.allow_unmatched_ends = true;
    config.allow_dangling_amp = true;
    let (mut depth, mut text): (i32, Option<String>) = (0, None);
    loop {
        match reader.read_event().ok()? {
            Event::Start(_) => depth += 1,
            Event::End(_) => depth -= 1,
            Event::Text(t) if depth == 0 => {
                text.get_or_insert_with(String::new).push_str(&unescape(&String::from_utf8_lossy(&t)))
            }
            Event::GeneralRef(r) if depth == 0 => {
                let name = String::from_utf8_lossy(&r).into_owned();
                let t = text.get_or_insert_with(String::new);
                match reference(&name) {
                    Some(c) => t.push(c),
                    None => t.push_str(&format!("&{name};")),
                }
            }
            Event::CData(c) if depth == 0 => text.get_or_insert_with(String::new).push_str(&String::from_utf8_lossy(&c)),
            Event::Eof => return text,
            _ => {}
        }
    }
}

struct Span {
    from: usize,
    open: usize,
    close: Option<usize>,
    to: usize,
    lead: usize,
    tail: usize,
}

fn span_of(el: &Table, len: usize) -> mlua::Result<Option<Span>> {
    let Some(s) = el.get::<Option<Table>>("span")? else { return Ok(None) };
    let span = Span {
        from: s.get("from")?,
        open: s.get("open")?,
        close: s.get("close")?,
        to: s.get("to")?,
        lead: s.get::<Option<usize>>("lead")?.unwrap_or(0),
        tail: s.get::<Option<usize>>("tail")?.unwrap_or(0),
    };
    let ok = span.from >= 1 && span.from <= span.open && span.open <= span.to && span.to <= len;
    Ok(ok.then_some(span))
}

fn encode_el(el: &Table, opts: &EncodeOpts, depth: usize, out: &mut String) -> mlua::Result<()> {
    let name: String = el.get("name")?;
    let attrs = attributes(el, opts.digits)?;
    let children: Vec<Table> = match el.get::<Option<Table>>("children")? {
        Some(c) => c.sequence_values::<Table>().collect::<mlua::Result<_>>()?,
        None => Vec::new(),
    };
    let text: Option<String> = el.get("text")?;
    let src = opts.source.as_deref();
    let span = match src {
        Some(src) => span_of(el, src.len())?,
        None => None,
    };
    let pad = |out: &mut String, depth: usize| {
        if let Some(indent) = &opts.indent {
            out.push_str(&indent.repeat(depth));
        }
    };
    let empty = children.is_empty() && text.is_none();
    if let (Some(src), Some(span)) = (src, &span) {
        // What the source had, kept where it is the same.
        let tag = &src[span.from - 1..span.open];
        let (src_name, src_attrs) = source_tag(tag).unwrap_or_default();
        let same = src_name == name
            && src_attrs.len() == attrs.len()
            && src_attrs.iter().zip(&attrs).all(|(a, b)| a.0 == b.0 && a.2 == b.1);
        // An element read with an end tag keeps it, one read as `<a/>` that
        // form while there is nothing in it.
        let selfclose = empty && span.close.is_none();
        if same && (span.close.is_none() == selfclose) {
            out.push_str(&String::from_utf8_lossy(tag));
        } else {
            out.push('<');
            out.push_str(&name);
            for (key, value) in &attrs {
                let raw = src_attrs.iter().find(|a| &a.0 == key && &a.2 == value).map(|a| a.1.clone());
                out.push(' ');
                out.push_str(key);
                out.push_str("=\"");
                match raw {
                    Some(raw) => out.push_str(&raw),
                    None => out.push_str(&escape(value, true)),
                }
                out.push('"');
            }
            out.push_str(if selfclose { "/>" } else { ">" });
        }
        if selfclose {
            return Ok(());
        }
        let was = span.close.and_then(|close| source_text(src, span.open, close - 1));
        let kept = span.close.is_some() && was == text;
        if kept {
            for child in &children {
                if let Some(c) = span_of(child, src.len())?
                    && c.lead >= span.open + 1
                    && c.lead <= c.from
                {
                    out.push_str(&String::from_utf8_lossy(&src[c.lead - 1..c.from - 1]));
                }
                encode_el(child, opts, depth + 1, out)?;
            }
            let close = span.close.unwrap_or(span.to);
            if span.tail >= span.open + 1 && span.tail <= close {
                out.push_str(&String::from_utf8_lossy(&src[span.tail - 1..close - 1]));
            }
        } else {
            out.push_str(&escape(text.as_deref().unwrap_or(""), false));
            for child in &children {
                encode_el(child, opts, depth + 1, out)?;
            }
        }
        match span.close {
            Some(close) => out.push_str(&String::from_utf8_lossy(&src[close - 1..span.to])),
            None => {
                out.push_str("</");
                out.push_str(&name);
                out.push('>');
            }
        }
        return Ok(());
    }
    pad(out, depth);
    out.push('<');
    out.push_str(&name);
    for (key, value) in &attrs {
        out.push(' ');
        out.push_str(key);
        out.push_str("=\"");
        out.push_str(&escape(value, true));
        out.push('"');
    }
    if empty {
        out.push_str("/>");
    } else if children.is_empty() {
        out.push('>');
        out.push_str(&escape(text.as_deref().unwrap_or(""), false));
        out.push_str("</");
        out.push_str(&name);
        out.push('>');
    } else {
        out.push('>');
        if let Some(t) = &text {
            out.push_str(&escape(t, false));
        }
        for child in &children {
            if opts.indent.is_some() {
                out.push('\n');
            }
            encode_el(child, opts, depth + 1, out)?;
        }
        if opts.indent.is_some() {
            out.push('\n');
            pad(out, depth);
        }
        out.push_str("</");
        out.push_str(&name);
        out.push('>');
    }
    Ok(())
}

/// The text of an element and all it holds.
pub fn encode(root: &Table, opts: &EncodeOpts) -> mlua::Result<String> {
    let mut out = String::new();
    encode_el(root, opts, 0, &mut out)?;
    Ok(out)
}

