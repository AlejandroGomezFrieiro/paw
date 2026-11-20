//! Decent Sampler presets (`.dspreset`): `<groups>` of `<group>`s of
//! `<sample>`s, attributes inherited down that chain, `<tags>`, and
//! keyswitches as `<midi><note>` bindings that enable groups or tags (or
//! choose a `<ui>` menu's option that does). Effects, modulators and the
//! UI's look are not played.

use super::{FormatReader, extension_is, parse_key};
use crate::error::FormatError;
use crate::model::*;
use roxmltree::{Document, Node};
use std::path::Path;

pub struct DecentSampler;

impl FormatReader for DecentSampler {
    fn name(&self) -> &'static str {
        "dspreset"
    }

    fn detect(&self, path: &Path, head: &[u8]) -> bool {
        extension_is(path, "dspreset")
            || String::from_utf8_lossy(head).contains("<DecentSampler")
    }

    fn read(&self, path: &Path) -> Result<Instrument, FormatError> {
        let text = std::fs::read_to_string(path).map_err(|e| FormatError::io(path, e))?;
        let dir = path.parent().unwrap_or(Path::new("."));
        let xml = |source| FormatError::Xml { path: path.to_path_buf(), source };
        match Document::parse(&text) {
            Ok(doc) => read_document(&doc, dir),
            // Decent Sampler reads presets that are not quite XML: an
            // attribute given twice keeps its first value there.
            Err(roxmltree::Error::DuplicatedAttribute(..)) => {
                let text = first_attributes(&text);
                let doc = Document::parse(&text).map_err(xml)?;
                read_document(&doc, dir)
            }
            Err(e) => Err(xml(e)),
        }
    }
}

/// The text with every attribute given twice in a tag left out after its
/// first.
fn first_attributes(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(open) = rest.find('<') {
        out.push_str(&rest[..open]);
        rest = &rest[open..];
        let end = rest.find('>').map_or(rest.len(), |e| e + 1);
        let tag = &rest[..end];
        rest = &rest[end..];
        if tag.starts_with("<!") || tag.starts_with("<?") || tag.starts_with("</") {
            out.push_str(tag);
            continue;
        }
        // The name, then `name = "value"` pairs.
        let name_end = tag[1..].find(|c: char| c.is_whitespace() || c == '>' || c == '/').map_or(tag.len(), |i| i + 1);
        out.push_str(&tag[..name_end]);
        let mut seen: Vec<&str> = Vec::new();
        let mut t = &tag[name_end..];
        loop {
            let trimmed = t.trim_start();
            let Some(eq) = trimmed.find('=') else { break };
            let attr = trimmed[..eq].trim();
            let after = trimmed[eq + 1..].trim_start();
            let Some(quote) = after.chars().next().filter(|c| *c == '"' || *c == '\'') else { break };
            let Some(close) = after[1..].find(quote) else { break };
            let value = &after[..close + 2];
            if !seen.contains(&attr) {
                seen.push(attr);
                out.push(' ');
                out.push_str(attr);
                out.push('=');
                out.push_str(value);
            }
            t = &after[close + 2..];
        }
        out.push_str(t.trim_start());
    }
    out.push_str(rest);
    out
}

/// A binding that turns a group or a tag on or off.
#[derive(Clone, Debug)]
enum Enable {
    Group(usize, bool),
    Tag(String, bool),
}

/// A tag's first state and its polyphony, and the numbers that choke
/// tags get.
struct Tags {
    enabled: Vec<(String, bool)>,
    polyphony: Vec<(String, u32)>,
    ids: Vec<String>,
}

impl Tags {
    /// The tags declared under `<tags>`, each with its first state.
    fn read(root: Node) -> Tags {
        let mut tags = Tags { enabled: Vec::new(), polyphony: Vec::new(), ids: Vec::new() };
        if let Some(node) = child(root, "tags") {
            for tag in node.children().filter(|n| n.has_tag_name("tag")) {
                let name = tag.attribute("name").unwrap_or("").to_string();
                tags.enabled.push((name.clone(), tag.attribute("enabled") != Some("false")));
                if let Some(p) = tag.attribute("polyphony").and_then(|p| p.parse::<i64>().ok())
                    && p > 0
                {
                    tags.polyphony.push((name, p as u32));
                }
            }
        }
        tags
    }

    fn on(&self, tag: &str) -> bool {
        self.enabled.iter().find(|x| x.0 == tag).is_none_or(|x| x.1)
    }

    /// Choke tags as numbers, from 1.
    fn id(&mut self, tag: &str) -> i64 {
        if let Some(i) = self.ids.iter().position(|x| x == tag) {
            return i as i64 + 1;
        }
        self.ids.push(tag.to_string());
        self.ids.len() as i64
    }
}

/// One option of a `<ui>` menu and what choosing it turns on or off.
struct MenuOption {
    name: String,
    set: Vec<Enable>,
}

/// A `<menu>` control, found by its position among the tab's controls.
struct Menu {
    position: usize,
    options: Vec<MenuOption>,
}

/// A `<midi><note>` binding that switches groups or tags.
struct Keyswitch {
    key: u8,
    set: Vec<Enable>,
    swallow: bool,
}

/// Articulations as menu options in the UI.
fn read_menus(root: Node, groups: &[Node]) -> Vec<Menu> {
    let mut menus = Vec::new();
    let Some(ui) = child(root, "ui") else { return menus };
    for (position, control) in ui
        .descendants()
        .filter(|n| n.is_element() && n.parent().is_some_and(|p| p.has_tag_name("tab")))
        .enumerate()
    {
        if control.has_tag_name("menu") {
            let options = control
                .children()
                .filter(|n| n.has_tag_name("option"))
                .map(|o| MenuOption { name: o.attribute("name").unwrap_or("").to_string(), set: enables(o, groups) })
                .collect();
            menus.push(Menu { position, options });
        }
    }
    menus
}

/// Articulations as keyswitch notes.
fn read_keyswitches(root: Node, groups: &[Node], menus: &[Menu]) -> Vec<Keyswitch> {
    let mut keyswitches = Vec::new();
    let Some(midi) = child(root, "midi") else { return keyswitches };
    for note in midi.children().filter(|n| n.has_tag_name("note")) {
        if note.attribute("enabled") == Some("false") || note.attribute("eventType") == Some("note_off") {
            continue;
        }
        let Some(key) = note.attribute("note").and_then(parse_key) else { continue };
        let mut set = enables(note, groups);
        // A keyswitch may choose a menu's option instead.
        for b in note.children().filter(|n| n.has_tag_name("binding")) {
            if b.attribute("level") == Some("ui") && b.attribute("parameter") == Some("VALUE") {
                let position = b.attribute("position").and_then(|p| p.parse::<usize>().ok());
                let value = b.attribute("translationValue").and_then(|v| v.parse::<usize>().ok());
                if let (Some(p), Some(v)) = (position, value)
                    && let Some(menu) = menus.iter().find(|m| m.position == p)
                    && let Some(option) = menu.options.get(v.saturating_sub(1))
                {
                    set.extend(option.set.iter().cloned());
                }
            }
        }
        let swallow = note.attribute("swallowNotes") == Some("true");
        if !set.is_empty() && (0..128).contains(&key) {
            keyswitches.push(Keyswitch { key: key as u8, set, swallow });
        }
    }
    keyswitches
}

/// The switch layers: every group and tag that something turns on or off.
struct Layers(Vec<Enable>);

impl Layers {
    fn collect(keyswitches: &[Keyswitch], menus: &[Menu]) -> Layers {
        let mut layers: Vec<Enable> = Vec::new();
        let all_sets = keyswitches
            .iter()
            .map(|k| &k.set)
            .chain(menus.iter().flat_map(|m| m.options.iter().map(|o| &o.set)));
        for set in all_sets {
            for e in set {
                let known = layers.iter().any(|l| match (l, e) {
                    (Enable::Group(a, _), Enable::Group(b, _)) => a == b,
                    (Enable::Tag(a, _), Enable::Tag(b, _)) => a == b,
                    _ => false,
                });
                if !known && layers.len() < 128 {
                    layers.push(e.clone());
                }
            }
        }
        Layers(layers)
    }

    fn of_group(&self, g: usize) -> Option<usize> {
        self.0.iter().position(|l| matches!(l, Enable::Group(x, _) if *x == g))
    }

    fn of_tag(&self, t: &str) -> Option<usize> {
        self.0.iter().position(|l| matches!(l, Enable::Tag(x, _) if x == t))
    }

    /// The layers a set touches, and the value it gives each.
    fn mask_values(&self, set: &[Enable]) -> (u128, u128) {
        let (mut mask, mut values) = (0u128, 0u128);
        for e in set {
            let (layer, on) = match e {
                Enable::Group(g, on) => (self.of_group(*g), *on),
                Enable::Tag(t, on) => (self.of_tag(t), *on),
            };
            if let Some(l) = layer {
                mask |= 1 << l;
                if on {
                    values |= 1 << l;
                } else {
                    values &= !(1 << l);
                }
            }
        }
        (mask, values)
    }
}

fn group_on(groups: &[Node], g: usize) -> bool {
    groups[g].attribute("enabled") != Some("false")
}

/// What a set turns on, as a name: its groups' names and its tags.
fn set_name(set: &[Enable], groups: &[Node]) -> Option<String> {
    let names: Vec<String> = set
        .iter()
        .filter_map(|e| match e {
            Enable::Group(g, true) => groups[*g].attribute("name").map(str::to_string),
            Enable::Tag(t, true) => Some(t.clone()),
            _ => None,
        })
        .collect();
    (!names.is_empty()).then(|| names.join(" + "))
}

/// The switches, the default layers and the articulations: one for each
/// keyswitch, then those menu options that no keyswitch chooses.
fn add_articulations(inst: &mut Instrument, layers: &Layers, groups: &[Node], tags: &Tags, keyswitches: &[Keyswitch], menus: &[Menu]) {
    for (i, layer) in layers.0.iter().enumerate() {
        let on = match layer {
            Enable::Group(g, _) => group_on(groups, *g),
            Enable::Tag(t, _) => tags.on(t),
        };
        if on {
            inst.default_switch |= 1 << i;
        }
    }
    for k in keyswitches {
        let (mask, values) = layers.mask_values(&k.set);
        inst.switches.push(Switch { key: k.key, mask, values, swallow: k.swallow });
        let name = set_name(&k.set, groups).unwrap_or_else(|| format!("Keyswitch {}", crate::m2::key_name(k.key)));
        inst.articulations.push(Articulation {
            m2: crate::m2::code_for_name(&name),
            name,
            keyswitch: Some(k.key),
            mask,
            values,
        });
    }
    for option in menus.iter().flat_map(|m| &m.options) {
        let (mask, values) = layers.mask_values(&option.set);
        if mask == 0 || inst.articulations.iter().any(|a| a.mask == mask && a.values == values) {
            continue;
        }
        inst.articulations.push(Articulation {
            m2: crate::m2::code_for_name(&option.name),
            name: option.name.clone(),
            keyswitch: None,
            mask,
            values,
        });
    }
    inst.default_articulation = inst.articulations.iter().position(|a| inst.default_switch & a.mask == a.values);
}

fn read_document(doc: &Document, dir: &Path) -> Result<Instrument, FormatError> {
    let root = doc.root_element();
    if root.tag_name().name() != "DecentSampler" {
        return Err(FormatError::NotDecentSampler);
    }
    let mut inst = Instrument { curves: Curve::builtin(), ..Default::default() };
    let groups_node = child(root, "groups").ok_or(FormatError::NoGroups)?;
    let groups: Vec<Node> = groups_node
        .children()
        .filter(|n| n.is_element() && n.tag_name().name() == "group")
        .collect();
    let mut tags = Tags::read(root);
    let menus = read_menus(root, &groups);
    let keyswitches = read_keyswitches(root, &groups, &menus);
    let layers = Layers::collect(&keyswitches, &menus);
    add_articulations(&mut inst, &layers, &groups, &tags, &keyswitches, &menus);

    let preset = Preset { dir, groups_node, groups: &groups, layers: &layers };
    for (gi, group) in groups.iter().enumerate() {
        read_group(&mut inst, &preset, &mut tags, gi, *group);
    }
    for name in ["effects", "modulators", "buses"] {
        if child(root, name).is_some_and(|n| n.children().any(|c| c.is_element())) {
            inst.warn(format!("<{name}> is not played"));
        }
    }
    Ok(inst)
}

/// What every region of a preset is read against.
struct Preset<'a, 'i> {
    dir: &'a Path,
    groups_node: Node<'a, 'i>,
    groups: &'a [Node<'a, 'i>],
    layers: &'a Layers,
}

/// A sample's attributes, each inherited from its group and then from
/// `<groups>`.
struct Attrs<'a, 'i> {
    sample: Node<'a, 'i>,
    group: Node<'a, 'i>,
    groups: Node<'a, 'i>,
}

impl<'a> Attrs<'a, '_> {
    fn get(&self, name: &str) -> Option<&'a str> {
        self.sample
            .attribute(name)
            .or_else(|| self.group.attribute(name))
            .or_else(|| self.groups.attribute(name))
    }

    fn num(&self, name: &str) -> Option<f32> {
        self.get(name).and_then(|v| v.trim().parse::<f32>().ok())
    }

    fn key(&self, name: &str) -> Option<u8> {
        self.get(name).and_then(parse_key).map(|k| k.clamp(0, 127) as u8)
    }
}

/// The regions of one `<group>`.
fn read_group(inst: &mut Instrument, preset: &Preset, tags: &mut Tags, gi: usize, group: Node) {
    if !group_on(preset.groups, gi) && preset.layers.of_group(gi).is_none() {
        return;
    }
    let samples: Vec<Node> = group.children().filter(|n| n.has_tag_name("sample")).collect();
    // Round robin length found from the positions when not given.
    let auto_length = samples
        .iter()
        .filter_map(|s| s.attribute("seqPosition").and_then(|p| p.parse::<u32>().ok()))
        .max()
        .unwrap_or(1);
    for sample in samples {
        let attrs = Attrs { sample, group, groups: preset.groups_node };
        if let Some(region) = read_region(inst, preset, tags, gi, &attrs, auto_length) {
            inst.regions.push(region);
        }
    }
}

/// One `<sample>` as a region; none when it has no path, or needs a tag
/// that is off and that nothing turns on.
fn read_region(inst: &mut Instrument, preset: &Preset, tags: &mut Tags, gi: usize, a: &Attrs, auto_length: u32) -> Option<Region> {
    let Some(path) = a.sample.attribute("path") else {
        inst.warn("a <sample> without a path");
        return None;
    };
    let mut r = Region {
        source: Source::File(preset.dir.join(path.replace('\\', "/"))),
        ..Region::default()
    };
    r.keycenter = a.key("rootNote");
    r.lokey = a.key("loNote").unwrap_or(0);
    r.hikey = a.key("hiNote").unwrap_or(127);
    r.lovel = a.num("loVel").map_or(1, |v| v.clamp(1.0, 127.0) as u8);
    r.hivel = a.num("hiVel").map_or(127, |v| v.clamp(0.0, 127.0) as u8);
    r.offset = a.num("start").map_or(0, |v| v.max(0.0) as u64);
    r.end = a.num("end").map(|v| v.max(0.0) as u64);
    r.tune = 100.0
        * (a.num("tuning").unwrap_or(0.0)
            + a.group.attribute("groupTuning").and_then(|v| v.parse::<f32>().ok()).unwrap_or(0.0)
            + a.groups.attribute("globalTuning").and_then(|v| v.parse::<f32>().ok()).unwrap_or(0.0));
    r.keytrack = 100.0 * a.num("pitchKeyTrack").unwrap_or(1.0);
    // Volumes multiply down the chain.
    r.volume = [a.sample, a.group, a.groups].iter().filter_map(|n| n.attribute("volume")).map(volume_db).sum();
    r.pan = a.num("pan").unwrap_or(0.0) / 100.0;
    r.amp_veltrack = a.num("ampVelTrack").unwrap_or(1.0);
    r.amp_velcurve = Some(0);
    r.amp_eg = Envelope {
        attack: a.num("attack").unwrap_or(0.0),
        decay: a.num("decay").unwrap_or(0.0),
        sustain: a.num("sustain").unwrap_or(1.0),
        release: a.num("release").unwrap_or(0.1),
        ..Envelope::AMP
    };
    if a.get("ampEnvEnabled") == Some("false") {
        r.amp_eg = Envelope::AMP;
    }
    r.trigger = match a.get("trigger") {
        Some("release") => Trigger::Release,
        Some("first") => Trigger::First,
        Some("legato") => Trigger::Legato,
        _ => Trigger::Attack,
    };
    if let Some(decay) = a.get("releaseTriggerDecay") {
        r.rt_decay = rt_decay(decay);
    }
    read_sequence(&mut r, a, auto_length);
    read_loop(&mut r, a);
    if let Some(n) = a.num("delay") {
        match a.get("delayUnit").unwrap_or("seconds") {
            "seconds" => r.delay = n,
            other => inst.warn(format!("delayUnit `{other}` is not played")),
        }
    }
    read_cc_ranges(&mut r, a);
    if let Some(previous) = a.get("previousNotes") {
        r.sw_previous = previous.split(',').next().and_then(parse_key).map(|k| k.clamp(0, 127) as u8);
    }
    read_tags(&mut r, preset, tags, gi, a)?;
    Some(r)
}

/// Round robin and random choice among samples.
fn read_sequence(r: &mut Region, a: &Attrs, auto_length: u32) {
    r.seq_mode = match a.get("seqMode") {
        Some("round_robin") => SeqMode::RoundRobin,
        Some("random") | Some("true_random") => SeqMode::Random,
        _ => return,
    };
    r.seq_length = a.num("seqLength").map_or(auto_length, |v| v.max(1.0) as u32);
    r.seq_position = a.num("seqPosition").map_or(1, |v| v.max(1.0) as u32);
}

fn read_loop(r: &mut Region, a: &Attrs) {
    r.loop_start = a.num("loopStart").map(|v| v.max(0.0) as u64);
    r.loop_end = a.num("loopEnd").map(|v| v.max(0.0) as u64);
    r.loop_mode = a.get("loopEnabled").map(|v| if v == "true" { LoopMode::Continuous } else { LoopMode::NoLoop });
    r.loop_crossfade_frames = a.num("loopCrossfade").map_or(0, |v| v.max(0.0) as u64);
}

/// Controller conditions: `loCCN`, `hiCCN`, the sample's before the group's.
fn read_cc_ranges(r: &mut Region, a: &Attrs) {
    let mut seen: Vec<(u8, bool)> = Vec::new();
    for attr in a.sample.attributes().chain(a.group.attributes()) {
        for (prefix, lo) in [("loCC", true), ("hiCC", false)] {
            let Some(cc) = attr.name().strip_prefix(prefix).and_then(|n| n.parse::<u8>().ok()) else {
                continue;
            };
            if cc >= 128 || seen.contains(&(cc, lo)) {
                continue;
            }
            seen.push((cc, lo));
            let v = attr.value().parse::<f32>().unwrap_or(0.0) / 127.0;
            let i = match r.cc_ranges.iter().position(|c| c.cc == cc) {
                Some(i) => i,
                None => {
                    r.cc_ranges.push(CcRange { cc, lo: 0.0, hi: 1.0 });
                    r.cc_ranges.len() - 1
                }
            };
            if lo { r.cc_ranges[i].lo = v } else { r.cc_ranges[i].hi = v }
        }
    }
}

/// The switch layers a sample needs (its group's, its tags'), its choke
/// groups and its polyphony. None when a tag it has is off for good.
fn read_tags(r: &mut Region, preset: &Preset, tags: &mut Tags, gi: usize, a: &Attrs) -> Option<()> {
    let names: Vec<&str> = a
        .get("tags")
        .map(|t| t.split(',').map(str::trim).filter(|t| !t.is_empty()).collect())
        .unwrap_or_default();
    if let Some(l) = preset.layers.of_group(gi) {
        r.switch_all |= 1 << l;
    }
    let mut off = false;
    for t in &names {
        match preset.layers.of_tag(t) {
            Some(l) => r.switch_all |= 1 << l,
            None if !tags.on(t) => off = true,
            None => {}
        }
    }
    if off {
        return None;
    }
    r.groups = names.iter().map(|t| tags.id(t)).collect();
    r.polyphony = names
        .iter()
        .filter_map(|t| tags.polyphony.iter().find(|p| p.0 == *t).map(|p| p.1))
        .min();
    r.off_by = a
        .get("silencedByTags")
        .map(|t| t.split(',').map(str::trim).filter(|t| !t.is_empty()).map(|t| tags.id(t)).collect())
        .unwrap_or_default();
    r.off_fast = a.get("silencingMode") != Some("normal");
    if let Some(decay) = a.num("silencingDecay").filter(|d| *d > 0.0) {
        r.off_fast = false;
        r.off_time = decay;
    } else if !r.off_fast {
        r.off_time = r.amp_eg.release;
    }
    Some(())
}

fn child<'a, 'i>(node: Node<'a, 'i>, name: &str) -> Option<Node<'a, 'i>> {
    node.children().find(|n| n.is_element() && n.tag_name().name() == name)
}

/// The group and tag bindings under a node that set `ENABLED` to a fixed value.
fn enables(node: Node, groups: &[Node]) -> Vec<Enable> {
    let mut out = Vec::new();
    for b in node.children().filter(|n| n.has_tag_name("binding")) {
        if b.attribute("enabled") == Some("false") {
            continue;
        }
        let on = b.attribute("translationValue").is_none_or(|v| v == "true" || v == "1");
        match (b.attribute("level"), b.attribute("parameter")) {
            (Some("group"), Some("ENABLED")) => {
                let index = b
                    .attribute("groupIndex")
                    .or_else(|| b.attribute("position"))
                    .and_then(|p| p.parse::<usize>().ok());
                if let Some(g) = index.filter(|&g| g < groups.len()) {
                    out.push(Enable::Group(g, on));
                }
            }
            (Some("tag"), Some("TAG_ENABLED")) => {
                if let Some(t) = b.attribute("identifier") {
                    out.push(Enable::Tag(t.to_string(), on));
                }
            }
            _ => {}
        }
    }
    out
}

/// A volume as Decent Sampler writes it: linear, or with `dB` after it.
fn volume_db(text: &str) -> f32 {
    let t = text.trim();
    if let Some(db) = t.strip_suffix("dB").or_else(|| t.strip_suffix("db")) {
        return db.trim().parse().unwrap_or(0.0);
    }
    let linear: f32 = t.parse().unwrap_or(1.0);
    if linear <= 0.0 { -144.0 } else { 20.0 * linear.log10() }
}

/// `releaseTriggerDecay` as dB per second.
fn rt_decay(text: &str) -> f32 {
    let t = text.trim();
    if let Some(db) = t.strip_suffix("dB").or_else(|| t.strip_suffix("db")) {
        return db.trim().parse::<f32>().unwrap_or(0.0).abs();
    }
    // A linear factor lost per second.
    let factor: f32 = t.parse().unwrap_or(0.0);
    if factor <= 0.0 || factor >= 1.0 { 0.0 } else { -20.0 * (1.0 - factor).log10() }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read_text(text: &str) -> Instrument {
        let doc = Document::parse(text).unwrap();
        read_document(&doc, Path::new("/lib")).unwrap()
    }

    #[test]
    fn groups_samples_and_inheritance() {
        let i = read_text(
            r#"<DecentSampler><groups attack="0.01" volume="-6dB">
                <group name="Sustain" release="0.5" volume="0.5" seqMode="round_robin">
                  <sample path="Samples/A.wav" rootNote="60" loNote="58" hiNote="62" seqPosition="1"/>
                  <sample path="Samples/B.wav" rootNote="60" loNote="58" hiNote="62" seqPosition="2" pan="50"/>
                </group></groups></DecentSampler>"#,
        );
        assert_eq!(i.regions.len(), 2);
        let r = &i.regions[1];
        assert_eq!(r.source, Source::File("/lib/Samples/B.wav".into()));
        assert_eq!((r.lokey, r.hikey, r.keycenter), (58, 62, Some(60)));
        assert_eq!(r.amp_eg.attack, 0.01);
        assert_eq!(r.amp_eg.release, 0.5);
        assert!((r.volume - (-6.0 - 6.0206)).abs() < 0.01);
        assert_eq!(r.pan, 0.5);
        assert_eq!((r.seq_length, r.seq_position), (2, 2));
    }

    #[test]
    fn keyswitch_notes_enable_groups() {
        let i = read_text(
            r#"<DecentSampler><groups>
                <group name="Sustain"><sample path="a.wav" rootNote="60"/></group>
                <group name="Staccato" enabled="false"><sample path="b.wav" rootNote="60"/></group>
                <group name="Pads"><sample path="c.wav" rootNote="60"/></group>
              </groups>
              <midi>
                <note note="24"><binding type="general" level="group" position="0" parameter="ENABLED" translation="fixed_value" translationValue="true"/>
                                <binding type="general" level="group" position="1" parameter="ENABLED" translation="fixed_value" translationValue="false"/></note>
                <note note="25" swallowNotes="true"><binding type="general" level="group" groupIndex="0" parameter="ENABLED" translation="fixed_value" translationValue="false"/>
                                <binding type="general" level="group" groupIndex="1" parameter="ENABLED" translation="fixed_value" translationValue="true"/></note>
              </midi></DecentSampler>"#,
        );
        assert_eq!(i.regions.len(), 3);
        assert_eq!(i.articulations.len(), 2);
        assert_eq!(i.articulations[0].name, "Sustain");
        assert_eq!(i.articulations[1].name, "Staccato");
        assert_eq!(i.articulations[1].m2, Some(0x110000));
        assert_eq!(i.articulations[1].keyswitch, Some(25));
        assert_eq!(i.default_switch, 0b01);
        assert_eq!(i.default_articulation, Some(0));
        assert_eq!(i.regions[0].switch_all, 0b01);
        assert_eq!(i.regions[1].switch_all, 0b10);
        assert_eq!(i.regions[2].switch_all, 0, "a group no keyswitch touches plays always");
        assert!(i.switches[1].swallow);
    }

    #[test]
    fn an_attribute_given_twice_keeps_its_first_value() {
        let text = first_attributes(r#"<?xml version="1.0"?><a x="1" y='2' x = "3"><b z="4" z="5"/></a>"#);
        assert_eq!(text, r#"<?xml version="1.0"?><a x="1" y='2'><b z="4"/></a>"#);
    }

    #[test]
    fn tags_choke_and_release_triggers() {
        let i = read_text(
            r#"<DecentSampler><tags><tag name="off" enabled="false"/></tags><groups>
                <group><sample path="open.wav" rootNote="46" tags="hat" silencedByTags="closed"/>
                       <sample path="closed.wav" rootNote="42" tags="closed,hat"/>
                       <sample path="never.wav" rootNote="40" tags="off"/>
                       <sample path="rel.wav" rootNote="60" trigger="release" releaseTriggerDecay="3dB"/></group>
              </groups></DecentSampler>"#,
        );
        assert_eq!(i.regions.len(), 3, "a sample with a disabled tag never plays");
        assert_eq!(i.regions[0].off_by, i.regions[1].groups[..1].to_vec());
        assert_eq!(i.regions[2].trigger, Trigger::Release);
        assert_eq!(i.regions[2].rt_decay, 3.0);
    }
}
