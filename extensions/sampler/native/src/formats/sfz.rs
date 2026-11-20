//! SFZ (sfzformat.com): headers `<control> <global> <master> <group>
//! <region> <curve>`, opcodes inherited down that chain, `#define` and
//! `#include`. Unknown opcodes are reported, never fatal.

use super::{FormatReader, extension_is, parse_key};
use crate::error::FormatError;
use crate::model::*;
use std::path::{Path, PathBuf};

pub struct Sfz;

impl FormatReader for Sfz {
    fn name(&self) -> &'static str {
        "sfz"
    }

    fn detect(&self, path: &Path, _head: &[u8]) -> bool {
        extension_is(path, "sfz")
    }

    fn read(&self, path: &Path) -> Result<Instrument, FormatError> {
        let dir = path.parent().unwrap_or(Path::new(".")).to_path_buf();
        let mut text = String::new();
        let mut warnings = Vec::new();
        let mut defines = Vec::new();
        include(path, &dir, &mut defines, 0, &mut text, &mut warnings)?;
        let mut instrument = parse(&text, &dir);
        for w in warnings {
            instrument.warn(w);
        }
        Ok(instrument)
    }
}

/// Reads `path` into `out` with comments taken out, `#include`d files put
/// in place and `#define`d names replaced.
fn include(
    path: &Path,
    dir: &Path,
    defines: &mut Vec<(String, String)>,
    depth: usize,
    out: &mut String,
    warnings: &mut Vec<String>,
) -> Result<(), FormatError> {
    if depth > 16 {
        return Err(FormatError::IncludeTooDeep(path.to_path_buf()));
    }
    let bytes = std::fs::read(path).map_err(|e| FormatError::io(path, e))?;
    let text = String::from_utf8_lossy(&bytes);
    let mut in_block = false;
    for raw in text.lines() {
        let line = strip_comments(raw, &mut in_block);
        let trimmed = line.trim_start();
        if let Some(rest) = trimmed.strip_prefix("#define") {
            let mut parts = rest.trim().splitn(2, char::is_whitespace);
            if let (Some(name), Some(value)) = (parts.next(), parts.next()) {
                let value = substitute(value.trim(), defines);
                defines.retain(|(n, _)| n != name);
                defines.push((name.to_string(), value));
                // Longest first, so that `$NOTE` does not eat `$NOTE_LO`.
                defines.sort_by(|a, b| b.0.len().cmp(&a.0.len()));
            }
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("#include") {
            let name = substitute(rest.trim().trim_matches('"'), defines);
            let file = dir.join(name.replace('\\', "/"));
            if let Err(e) = include(&file, dir, defines, depth + 1, out, warnings) {
                warnings.push(format!("#include: {e}"));
            }
            continue;
        }
        out.push_str(&substitute(&line, defines));
        out.push('\n');
    }
    Ok(())
}

fn strip_comments(line: &str, in_block: &mut bool) -> String {
    let mut out = String::new();
    let mut rest = line;
    loop {
        if *in_block {
            match rest.find("*/") {
                Some(end) => {
                    *in_block = false;
                    rest = &rest[end + 2..];
                }
                None => return out,
            }
        }
        let line_comment = rest.find("//");
        let block = rest.find("/*");
        match (line_comment, block) {
            (Some(l), b) if b.is_none_or(|b| l < b) => {
                out.push_str(&rest[..l]);
                return out;
            }
            (_, Some(b)) => {
                out.push_str(&rest[..b]);
                rest = &rest[b + 2..];
                *in_block = true;
            }
            _ => {
                out.push_str(rest);
                return out;
            }
        }
    }
}

fn substitute(text: &str, defines: &[(String, String)]) -> String {
    if !text.contains('$') {
        return text.to_string();
    }
    let mut text = text.to_string();
    for (name, value) in defines {
        if text.contains(name.as_str()) {
            text = text.replace(name.as_str(), value);
        }
    }
    text
}

#[derive(Debug, PartialEq)]
enum Token {
    Header(String),
    Opcode(String, String),
}

/// Splits the text into headers and opcodes. A value runs to the end of
/// the line, the next header, or the next `name=` (sample paths may hold
/// spaces).
fn tokens(text: &str) -> Vec<Token> {
    let mut out = Vec::new();
    for line in text.lines() {
        let mut rest = line;
        while !rest.trim().is_empty() {
            rest = rest.trim_start();
            if let Some(after) = rest.strip_prefix('<') {
                let end = after.find('>').unwrap_or(after.len());
                out.push(Token::Header(after[..end].trim().to_ascii_lowercase()));
                rest = after.get(end + 1..).unwrap_or("");
                continue;
            }
            let Some(eq) = rest.find('=') else { break };
            let name = rest[..eq].trim().to_string();
            let after = &rest[eq + 1..];
            let mut end = after.find('<').unwrap_or(after.len());
            if let Some(next) = next_opcode(&after[..end]) {
                end = next;
            }
            out.push(Token::Opcode(name, after[..end].trim().to_string()));
            rest = &after[end..];
        }
    }
    out
}

/// Where the next `name=` starts in a value, if one does.
fn next_opcode(value: &str) -> Option<usize> {
    let bytes = value.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i].is_ascii_whitespace() {
            let start = i + 1;
            let mut j = start;
            while j < bytes.len() && (bytes[j].is_ascii_alphanumeric() || bytes[j] == b'_') {
                j += 1;
            }
            if j > start && j < bytes.len() && bytes[j] == b'=' {
                return Some(start);
            }
        }
        i += 1;
    }
    None
}

#[derive(Clone, Copy, PartialEq)]
enum Level {
    Control,
    Global,
    Master,
    Group,
    Region,
    Curve,
    Ignored,
}

/// A region's keyswitch opcodes, resolved once every region is read.
#[derive(Default, Clone)]
struct SwitchOps {
    lolast: Option<u8>,
    hilast: Option<u8>,
    label: Option<String>,
}

struct Ctx {
    dir: PathBuf,
    default_path: String,
    note_offset: i32,
    octave_offset: i32,
    sw_lokey: Option<u8>,
    sw_hikey: Option<u8>,
    sw_default: Option<u8>,
    instrument: Instrument,
    switch_ops: Vec<SwitchOps>,
    labels: Vec<Option<String>>,
}

fn parse(text: &str, dir: &Path) -> Instrument {
    let mut ctx = Ctx {
        dir: dir.to_path_buf(),
        default_path: String::new(),
        note_offset: 0,
        octave_offset: 0,
        sw_lokey: None,
        sw_hikey: None,
        sw_default: None,
        instrument: Instrument { curves: Curve::builtin(), ..Default::default() },
        switch_ops: Vec::new(),
        labels: Vec::new(),
    };
    let (mut global, mut master, mut group, mut region, mut curve) =
        (Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new());
    let mut level = Level::Global;
    let finish = |level: Level, ctx: &mut Ctx, ops: [&Vec<(String, String)>; 4], curve: &[(String, String)]| {
        match level {
            Level::Region => build_region(ctx, ops),
            Level::Curve => build_curve(ctx, curve),
            _ => {}
        }
    };
    for token in tokens(text) {
        match token {
            Token::Header(name) => {
                finish(level, &mut ctx, [&global, &master, &group, &region], &curve);
                region.clear();
                curve.clear();
                level = match name.as_str() {
                    "control" => Level::Control,
                    "global" => {
                        global.clear();
                        master.clear();
                        group.clear();
                        Level::Global
                    }
                    "master" => {
                        master.clear();
                        group.clear();
                        Level::Master
                    }
                    "group" => {
                        group.clear();
                        Level::Group
                    }
                    "region" => Level::Region,
                    "curve" => Level::Curve,
                    other => {
                        ctx.instrument.warn(format!("<{other}> is not played"));
                        Level::Ignored
                    }
                }
            }
            Token::Opcode(name, value) => match level {
                Level::Control => control(&mut ctx, &name, &value),
                Level::Global => global.push((name, value)),
                Level::Master => master.push((name, value)),
                Level::Group => group.push((name, value)),
                Level::Region => region.push((name, value)),
                Level::Curve => curve.push((name, value)),
                Level::Ignored => {}
            },
        }
    }
    finish(level, &mut ctx, [&global, &master, &group, &region], &curve);
    resolve_switches(&mut ctx);
    ctx.instrument
}

fn cc_suffix<'a>(name: &'a str, prefix: &str) -> Option<u8> {
    name.strip_prefix(prefix)?.parse::<u8>().ok().filter(|&n| n < 128)
}

fn control(ctx: &mut Ctx, name: &str, value: &str) {
    if let Some(cc) = cc_suffix(name, "set_cc") {
        let v = value.parse::<f32>().unwrap_or(0.0) / 127.0;
        set_cc(&mut ctx.instrument, cc, v);
    } else if let Some(cc) = cc_suffix(name, "set_hdcc") {
        set_cc(&mut ctx.instrument, cc, value.parse::<f32>().unwrap_or(0.0));
    } else if let Some(cc) = cc_suffix(name, "label_cc") {
        ctx.instrument.cc_labels.retain(|(c, _)| *c != cc);
        ctx.instrument.cc_labels.push((cc, value.to_string()));
    } else if let Some(key) = cc_suffix(name, "label_key") {
        ctx.instrument.key_labels.retain(|(k, _)| *k != key);
        ctx.instrument.key_labels.push((key, value.to_string()));
    } else {
        match name {
            "default_path" => ctx.default_path = value.replace('\\', "/"),
            "note_offset" => ctx.note_offset = value.parse().unwrap_or(0),
            "octave_offset" => ctx.octave_offset = value.parse().unwrap_or(0),
            _ if name.starts_with("hint_") => {}
            _ => ctx.instrument.warn(format!("unknown opcode `{name}` in <control>")),
        }
    }
}

fn set_cc(instrument: &mut Instrument, cc: u8, value: f32) {
    instrument.cc_init.retain(|(c, _)| *c != cc);
    instrument.cc_init.push((cc, value.clamp(0.0, 1.0)));
}

fn build_curve(ctx: &mut Ctx, ops: &[(String, String)]) {
    let mut index = None;
    let mut points: Vec<(usize, f32)> = Vec::new();
    for (name, value) in ops {
        if name == "curve_index" {
            index = value.parse::<usize>().ok();
        } else if let Some(p) = name.strip_prefix('v').and_then(|n| n.parse::<usize>().ok()) {
            if p < 128 {
                points.push((p, value.parse().unwrap_or(0.0)));
            }
        }
    }
    let Some(index) = index.filter(|&i| i < 256) else {
        ctx.instrument.warn("a <curve> without curve_index");
        return;
    };
    points.sort_by_key(|p| p.0);
    if !points.iter().any(|p| p.0 == 0) {
        points.insert(0, (0, 0.0));
    }
    if !points.iter().any(|p| p.0 == 127) {
        points.push((127, 1.0));
    }
    // Lines between the points given.
    let mut c = [0.0f32; 128];
    for w in points.windows(2) {
        let ((a, va), (b, vb)) = (w[0], w[1]);
        for (i, slot) in c.iter_mut().enumerate().take(b + 1).skip(a) {
            let t = if b > a { (i - a) as f32 / (b - a) as f32 } else { 0.0 };
            *slot = va + (vb - va) * t;
        }
    }
    let curves = &mut ctx.instrument.curves;
    while curves.len() <= index {
        curves.push(Curve([0.0; 128]));
    }
    curves[index] = Curve(c);
}

fn build_region(ctx: &mut Ctx, levels: [&Vec<(String, String)>; 4]) {
    let mut r = Region { keycenter: Some(60), ..Region::default() };
    let mut sw = SwitchOps::default();
    let mut label = None;
    let mut sample = None;
    let mut b = Build::default();
    for (name, value) in levels.iter().flat_map(|ops| ops.iter()) {
        if !opcode(ctx, &mut r, &mut sw, &mut b, name, value) {
            match name.as_str() {
                "sample" => sample = Some(value.clone()),
                "region_label" | "group_label" | "master_label" | "global_label" => {
                    label = Some(value.clone())
                }
                _ => ctx.instrument.warn(format!("unknown opcode `{name}`")),
            }
        }
    }
    let Some(sample) = sample else {
        ctx.instrument.warn("a region without a sample");
        return;
    };
    r.source = match sample.trim() {
        "*sine" => Source::Wave(Wave::Sine),
        "*saw" => Source::Wave(Wave::Saw),
        "*square" => Source::Wave(Wave::Square),
        "*triangle" | "*tri" => Source::Wave(Wave::Triangle),
        "*noise" => Source::Wave(Wave::Noise),
        "*silence" => Source::Silence,
        s if s.starts_with('*') => {
            ctx.instrument.warn(format!("no generator `{s}`"));
            return;
        }
        s => {
            let rel = format!("{}{}", ctx.default_path, s.replace('\\', "/"));
            Source::File(ctx.dir.join(rel))
        }
    };
    for (cc, fade) in b.xf_cc_lo.iter().copied() {
        let hi = b.xf_cc_hi.iter().find(|(c, o, _)| *c == cc.0 && *o == cc.1).map(|x| x.2);
        r.xf_cc.push((cc.0, Fade { lo: fade, hi: hi.unwrap_or(1.0), out: cc.1 }));
    }
    for (cc, out, hi) in b.xf_cc_hi.iter().copied() {
        if !b.xf_cc_lo.iter().any(|(c, _)| c.0 == cc && c.1 == out) {
            r.xf_cc.push((cc, Fade { lo: 0.0, hi, out }));
        }
    }
    for (out, lo, hi) in [(false, b.xfin_lokey, b.xfin_hikey), (true, b.xfout_lokey, b.xfout_hikey)] {
        if lo.is_some() || hi.is_some() {
            r.xf_key.push(Fade {
                lo: lo.unwrap_or(0.0),
                hi: hi.unwrap_or(if out { 127.0 } else { 0.0 }),
                out,
            });
        }
    }
    for (out, lo, hi) in [(false, b.xfin_lovel, b.xfin_hivel), (true, b.xfout_lovel, b.xfout_hivel)] {
        if lo.is_some() || hi.is_some() {
            r.xf_vel.push(Fade {
                lo: lo.unwrap_or(0.0),
                hi: hi.unwrap_or(if out { 127.0 } else { 0.0 }),
                out,
            });
        }
    }
    if let Some(points) = b.velcurve.take() {
        r.amp_velcurve = Some(velcurve(ctx, points));
    }
    if let Some(f) = r.filter.as_mut() {
        f.eg = b.fileg.unwrap_or(Envelope::MOD);
        f.eg_depth = b.fileg_depth;
    } else if b.fileg_depth != 0.0 {
        ctx.instrument.warn("fileg_depth with no cutoff");
    }
    for (cc, target, depth) in b.mods {
        let curve = b.curves.iter().find(|c| c.0 == cc && c.1 == target).map(|c| c.2);
        r.mods.push(CcMod { cc, target, depth, curve });
    }
    if let Some(f) = r.filter.as_mut()
        && f.keycenter == 255
    {
        f.keycenter = 60;
    }
    ctx.instrument.regions.push(r);
    ctx.switch_ops.push(sw);
    ctx.labels.push(label);
}

/// What a region collects before it can be put together.
#[derive(Default)]
struct Build {
    xf_cc_lo: Vec<((u8, bool), f32)>,
    xf_cc_hi: Vec<(u8, bool, f32)>,
    xfin_lokey: Option<f32>,
    xfin_hikey: Option<f32>,
    xfout_lokey: Option<f32>,
    xfout_hikey: Option<f32>,
    xfin_lovel: Option<f32>,
    xfin_hivel: Option<f32>,
    xfout_lovel: Option<f32>,
    xfout_hivel: Option<f32>,
    velcurve: Option<Vec<(u8, f32)>>,
    fileg: Option<Envelope>,
    fileg_depth: f32,
    mods: Vec<(u8, Target, f32)>,
    curves: Vec<(u8, Target, usize)>,
}

impl Build {
    fn fileg(&mut self) -> &mut Envelope {
        self.fileg.get_or_insert(Envelope::MOD)
    }
}

/// A velocity curve from `amp_velcurve_N` points, kept as a curve.
fn velcurve(ctx: &mut Ctx, mut points: Vec<(u8, f32)>) -> usize {
    points.sort_by_key(|p| p.0);
    if points.first().is_none_or(|p| p.0 != 0) {
        points.insert(0, (0, 0.0));
    }
    if points.last().is_none_or(|p| p.0 != 127) {
        points.push((127, 1.0));
    }
    let mut c = [0.0f32; 128];
    for w in points.windows(2) {
        let ((a, va), (b, vb)) = ((w[0].0 as usize, w[0].1), (w[1].0 as usize, w[1].1));
        for (i, slot) in c.iter_mut().enumerate().take(b + 1).skip(a) {
            let t = if b > a { (i - a) as f32 / (b - a) as f32 } else { 0.0 };
            *slot = va + (vb - va) * t;
        }
    }
    ctx.instrument.curves.push(Curve(c));
    ctx.instrument.curves.len() - 1
}

fn mod_target(name: &str) -> Option<(Target, &str)> {
    const TARGETS: &[(&str, Target)] = &[
        ("amplitude", Target::Amplitude),
        ("volume", Target::Volume),
        ("gain", Target::Volume),
        ("pan", Target::Pan),
        ("pitch", Target::Pitch),
        ("tune", Target::Pitch),
        ("cutoff", Target::Cutoff),
        ("resonance", Target::Resonance),
    ];
    TARGETS
        .iter()
        .find_map(|(prefix, t)| name.strip_prefix(prefix).map(|rest| (*t, rest)))
}

/// An opcode and its value, with the readings that most opcodes need.
struct Op<'a> {
    name: &'a str,
    value: &'a str,
    /// What `note_offset` and `octave_offset` add to a key.
    key_offset: i32,
}

impl Op<'_> {
    fn f(&self) -> f32 {
        self.value.trim().parse::<f32>().unwrap_or(0.0)
    }

    fn key(&self) -> Option<u8> {
        parse_key(self.value).map(|k| (k + self.key_offset).clamp(0, 127) as u8)
    }

    fn frames(&self) -> u64 {
        self.value.trim().parse::<f64>().unwrap_or(0.0).max(0.0) as u64
    }

    fn byte(&self) -> u8 {
        self.f().clamp(0.0, 127.0) as u8
    }
}

/// Applies one opcode to the region; false when it is not one of these.
fn opcode(ctx: &mut Ctx, r: &mut Region, sw: &mut SwitchOps, b: &mut Build, name: &str, value: &str) -> bool {
    let op = Op { name, value, key_offset: ctx.note_offset + 12 * ctx.octave_offset };
    controller_opcode(r, b, &op)
        || envelope_opcode(ctx, r, b, &op)
        || mapping_opcode(ctx, r, sw, &op)
        || playback_opcode(r, &op)
        || filter_opcode(ctx, r, &op)
        || crossfade_opcode(r, b, &op)
}

/// Controllers by number: `loccN`, `xfin_loccN`, `amplitude_onccN`, ...
fn controller_opcode(r: &mut Region, b: &mut Build, op: &Op) -> bool {
    let name = op.name;
    let f = op.f();
    if let Some(cc) = cc_suffix(name, "locc") {
        cc_range(r, cc).lo = f / 127.0;
        return true;
    }
    if let Some(cc) = cc_suffix(name, "hicc") {
        cc_range(r, cc).hi = f / 127.0;
        return true;
    }
    for (prefix, out) in [("xfin_locc", false), ("xfout_locc", true)] {
        if let Some(cc) = cc_suffix(name, prefix) {
            b.xf_cc_lo.push(((cc, out), f / 127.0));
            return true;
        }
    }
    for (prefix, out) in [("xfin_hicc", false), ("xfout_hicc", true)] {
        if let Some(cc) = cc_suffix(name, prefix) {
            b.xf_cc_hi.push((cc, out, f / 127.0));
            return true;
        }
    }
    if let Some(n) = name.strip_prefix("amp_velcurve_").and_then(|n| n.parse::<u8>().ok()) {
        b.velcurve.get_or_insert_with(Vec::new).push((n.min(127), f));
        return true;
    }
    if let Some((target, rest)) = mod_target(name) {
        let cc = cc_suffix(rest, "_oncc").or_else(|| cc_suffix(rest, "_cc"));
        if let Some(cc) = cc {
            b.mods.retain(|m| !(m.0 == cc && m.1 == target));
            b.mods.push((cc, target, f));
            return true;
        }
        if let Some(cc) = cc_suffix(rest, "_curvecc") {
            b.curves.push((cc, target, f as usize));
            return true;
        }
    }
    false
}

/// `ampeg_`, `pitcheg_` and `fileg_` stages.
fn envelope_opcode(ctx: &mut Ctx, r: &mut Region, b: &mut Build, op: &Op) -> bool {
    let f = op.f();
    if let Some(stage) = op.name.strip_prefix("ampeg_") {
        return envelope(&mut r.amp_eg, stage, f, ctx);
    }
    if let Some(stage) = op.name.strip_prefix("pitcheg_") {
        if stage == "depth" {
            r.pitch_eg_depth = f;
            return true;
        }
        return envelope(&mut r.pitch_eg, stage, f, ctx);
    }
    if let Some(stage) = op.name.strip_prefix("fileg_") {
        if stage == "depth" {
            b.fileg_depth = f;
            return true;
        }
        return envelope(b.fileg(), stage, f, ctx);
    }
    false
}

/// When the region plays: its keys, velocities, channels, random range,
/// sequence, keyswitches, trigger and groups.
fn mapping_opcode(ctx: &mut Ctx, r: &mut Region, sw: &mut SwitchOps, op: &Op) -> bool {
    let (value, f) = (op.value, op.f());
    match op.name {
        "key" => {
            if let Some(k) = op.key() {
                r.lokey = k;
                r.hikey = k;
                r.keycenter = Some(k);
            }
        }
        "lokey" => r.lokey = op.key().unwrap_or(0),
        "hikey" => r.hikey = op.key().unwrap_or(127),
        "lovel" => r.lovel = op.byte().max(1),
        "hivel" => r.hivel = op.byte(),
        "lochan" => r.lochan = f as u8,
        "hichan" => r.hichan = f as u8,
        "lorand" => r.lorand = f,
        "hirand" => r.hirand = f,
        "seq_length" => r.seq_length = f.max(1.0) as u32,
        "seq_position" => r.seq_position = f.max(1.0) as u32,
        "sw_lokey" => ctx.sw_lokey = op.key(),
        "sw_hikey" => ctx.sw_hikey = op.key(),
        "sw_last" => {
            sw.lolast = op.key();
            sw.hilast = op.key();
        }
        "sw_lolast" => sw.lolast = op.key(),
        "sw_hilast" => sw.hilast = op.key(),
        "sw_label" => sw.label = Some(value.to_string()),
        "sw_default" => ctx.sw_default = op.key(),
        "sw_down" => r.sw_down = op.key(),
        "sw_up" => r.sw_up = op.key(),
        "sw_previous" => r.sw_previous = op.key(),
        "trigger" => {
            r.trigger = match value {
                "release" => Trigger::Release,
                "release_key" => Trigger::ReleaseKey,
                "first" => Trigger::First,
                "legato" => Trigger::Legato,
                _ => Trigger::Attack,
            }
        }
        "rt_decay" => r.rt_decay = f,
        "group" => r.groups = vec![value.trim().parse().unwrap_or(0)],
        "off_by" => r.off_by = vec![value.trim().parse().unwrap_or(0)],
        "off_mode" => r.off_fast = value != "normal" && value != "time",
        "off_time" => {
            r.off_time = f;
            r.off_fast = false;
        }
        "polyphony" => r.polyphony = Some(f.max(1.0) as u32),
        "note_polyphony" => r.note_polyphony = Some(f.max(1.0) as u32),
        _ => return false,
    }
    true
}

/// How the sample sounds: pitch, offsets, loop, level and place.
fn playback_opcode(r: &mut Region, op: &Op) -> bool {
    let (value, f) = (op.value, op.f());
    match op.name {
        "pitch_keycenter" => r.keycenter = if value.trim() == "sample" { None } else { op.key() },
        "pitch_keytrack" => r.keytrack = f,
        "tune" | "pitch" => r.tune = f,
        "transpose" => r.transpose = f as i32,
        "pitch_veltrack" => r.pitch_veltrack = f,
        "bend_up" | "bendup" => r.bend_up = f,
        "bend_down" | "benddown" => r.bend_down = f,
        "offset" => r.offset = op.frames(),
        "offset_random" => r.offset_random = op.frames(),
        "end" => r.end = Some(op.frames()),
        "delay" => r.delay = f,
        "loop_mode" | "loopmode" => {
            r.loop_mode = Some(match value {
                "one_shot" => LoopMode::OneShot,
                "loop_continuous" => LoopMode::Continuous,
                "loop_sustain" => LoopMode::Sustain,
                _ => LoopMode::NoLoop,
            })
        }
        "loop_start" | "loopstart" => r.loop_start = Some(op.frames()),
        "loop_end" | "loopend" => r.loop_end = Some(op.frames()),
        "loop_crossfade" => r.loop_crossfade = f,
        "volume" | "gain" => r.volume = f,
        "amplitude" => r.amplitude = f / 100.0,
        "pan" => r.pan = f / 100.0,
        "width" => r.width = f / 100.0,
        "position" => r.position = f / 100.0,
        "amp_veltrack" => r.amp_veltrack = f / 100.0,
        _ => return false,
    }
    true
}

fn filter_opcode(ctx: &mut Ctx, r: &mut Region, op: &Op) -> bool {
    let f = op.f();
    match op.name {
        "fil_type" | "filtype" => {
            let kind = match op.value {
                "lpf_1p" => FilterKind::Lp1,
                "hpf_1p" => FilterKind::Hp1,
                "lpf_2p" => FilterKind::Lp2,
                "hpf_2p" => FilterKind::Hp2,
                "bpf_2p" => FilterKind::Bp2,
                "brf_2p" => FilterKind::Br2,
                "lpf_4p" => FilterKind::Lp4,
                "hpf_4p" => FilterKind::Hp4,
                other => {
                    ctx.instrument.warn(format!("filter `{other}` played as lpf_2p"));
                    FilterKind::Lp2
                }
            };
            filter(r).kind = kind;
        }
        "cutoff" => filter(r).cutoff = f,
        "resonance" => filter(r).resonance = f,
        "fil_keytrack" => filter(r).keytrack = f,
        "fil_keycenter" => filter(r).keycenter = op.key().unwrap_or(60),
        "fil_veltrack" => filter(r).veltrack = f,
        _ => return false,
    }
    true
}

fn crossfade_opcode(r: &mut Region, b: &mut Build, op: &Op) -> bool {
    let value = op.value;
    match op.name {
        "xfin_lokey" => b.xfin_lokey = op.key().map(f32::from),
        "xfin_hikey" => b.xfin_hikey = op.key().map(f32::from),
        "xfout_lokey" => b.xfout_lokey = op.key().map(f32::from),
        "xfout_hikey" => b.xfout_hikey = op.key().map(f32::from),
        "xfin_lovel" => b.xfin_lovel = Some(op.f()),
        "xfin_hivel" => b.xfin_hivel = Some(op.f()),
        "xfout_lovel" => b.xfout_lovel = Some(op.f()),
        "xfout_hivel" => b.xfout_hivel = Some(op.f()),
        "xf_keycurve" => r.xf_keycurve = xf_curve(value),
        "xf_velcurve" => r.xf_velcurve = xf_curve(value),
        "xf_cccurve" => r.xf_cccurve = xf_curve(value),
        _ => return false,
    }
    true
}

fn xf_curve(value: &str) -> XfCurve {
    if value == "gain" { XfCurve::Gain } else { XfCurve::Power }
}

fn cc_range(r: &mut Region, cc: u8) -> &mut CcRange {
    if let Some(i) = r.cc_ranges.iter().position(|c| c.cc == cc) {
        return &mut r.cc_ranges[i];
    }
    r.cc_ranges.push(CcRange { cc, lo: 0.0, hi: 1.0 });
    r.cc_ranges.last_mut().unwrap()
}

fn filter(r: &mut Region) -> &mut Filter {
    r.filter.get_or_insert(Filter {
        kind: FilterKind::Lp2,
        cutoff: 20000.0,
        resonance: 0.0,
        keytrack: 0.0,
        keycenter: 255,
        veltrack: 0.0,
        eg_depth: 0.0,
        eg: Envelope::MOD,
    })
}

fn envelope(eg: &mut Envelope, stage: &str, v: f32, ctx: &mut Ctx) -> bool {
    match stage {
        "delay" => eg.delay = v,
        "start" => eg.start = v / 100.0,
        "attack" => eg.attack = v,
        "hold" => eg.hold = v,
        "decay" => eg.decay = v,
        "sustain" => eg.sustain = v / 100.0,
        "release" => eg.release = v,
        "vel2attack" => eg.vel2attack = v,
        "vel2decay" => eg.vel2decay = v,
        "vel2release" => eg.vel2release = v,
        "vel2sustain" => eg.vel2sustain = v / 100.0,
        // Whether controllers move the envelope while it runs: none do here.
        "dynamic" => {}
        _ => {
            ctx.instrument.warn(format!("envelope stage `{stage}` is not played"));
        }
    }
    true
}

/// Gives every key that `sw_last` names an articulation and a switch
/// layer, and makes each region need the layers of the keys it names.
fn resolve_switches(ctx: &mut Ctx) {
    let mut keys: Vec<u8> = Vec::new();
    for ops in &ctx.switch_ops {
        if let (Some(lo), Some(hi)) = (ops.lolast, ops.hilast.or(ops.lolast)) {
            for k in lo..=hi.max(lo) {
                if !keys.contains(&k) {
                    keys.push(k);
                }
            }
        }
    }
    if keys.is_empty() {
        return;
    }
    keys.sort();
    if keys.len() > 128 {
        ctx.instrument.warn("more than 128 keyswitches: the highest are not played");
        keys.truncate(128);
    }
    let all: u128 = if keys.len() == 128 { u128::MAX } else { (1u128 << keys.len()) - 1 };
    let bit = |k: u8| keys.iter().position(|&x| x == k).map(|i| 1u128 << i);
    for (i, ops) in ctx.switch_ops.iter().enumerate() {
        if let Some(lo) = ops.lolast {
            let hi = ops.hilast.unwrap_or(lo).max(lo);
            ctx.instrument.regions[i].switch_any = (lo..=hi).filter_map(bit).fold(0, |a, b| a | b);
        }
    }
    for (index, &key) in keys.iter().enumerate() {
        // The name: the regions' `sw_label`, the key's label, the regions'
        // group label, or the key itself.
        let label = ctx
            .switch_ops
            .iter()
            .filter(|o| o.lolast == Some(key) && o.hilast.is_none_or(|h| h == key))
            .find_map(|o| o.label.clone())
            .or_else(|| ctx.instrument.key_labels.iter().find(|l| l.0 == key).map(|l| l.1.clone()))
            .or_else(|| {
                ctx.switch_ops
                    .iter()
                    .zip(&ctx.labels)
                    .filter(|(o, _)| o.lolast == Some(key) && o.hilast.is_none_or(|h| h == key))
                    .find_map(|(_, l)| l.clone())
            })
            .unwrap_or_else(|| format!("Keyswitch {}", crate::m2::key_name(key)));
        ctx.instrument.articulations.push(Articulation {
            m2: crate::m2::code_for_name(&label),
            name: label,
            keyswitch: Some(key),
            mask: all,
            values: 1 << index,
        });
        ctx.instrument.switches.push(Switch { key, mask: all, values: 1 << index, swallow: false });
    }
    // Keys in the switch range that name no articulation choose none.
    if let (Some(lo), Some(hi)) = (ctx.sw_lokey, ctx.sw_hikey) {
        for key in lo..=hi.max(lo) {
            if !keys.contains(&key) {
                ctx.instrument.switches.push(Switch { key, mask: all, values: 0, swallow: false });
            }
        }
    }
    if let Some(default) = ctx.sw_default
        && let Some(i) = keys.iter().position(|&k| k == default)
    {
        ctx.instrument.default_switch = 1 << i;
        ctx.instrument.default_articulation = Some(i);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_text(text: &str) -> Instrument {
        parse(text, Path::new("/lib"))
    }

    #[test]
    fn values_with_spaces_end_at_the_next_opcode() {
        let t = tokens("<region> sample=My Piano C4.wav key=60 <region>sample=x.wav");
        assert_eq!(
            t,
            vec![
                Token::Header("region".into()),
                Token::Opcode("sample".into(), "My Piano C4.wav".into()),
                Token::Opcode("key".into(), "60".into()),
                Token::Header("region".into()),
                Token::Opcode("sample".into(), "x.wav".into()),
            ]
        );
    }

    #[test]
    fn opcodes_inherit_from_global_through_group() {
        let i = parse_text(
            "<global> volume=-6 ampeg_release=0.5\n<master> pan=-50\n<group> lovel=64 \
             <region> sample=a.wav key=60 <region> sample=b.wav key=62 volume=-3\n\
             <group> <region> sample=c.wav key=64",
        );
        assert_eq!(i.regions.len(), 3);
        assert_eq!(i.regions[0].volume, -6.0);
        assert_eq!(i.regions[0].lovel, 64);
        assert_eq!(i.regions[0].pan, -0.5);
        assert_eq!(i.regions[0].amp_eg.release, 0.5);
        assert_eq!(i.regions[1].volume, -3.0);
        assert_eq!(i.regions[2].lovel, 1, "a new group starts afresh");
        assert_eq!(i.regions[2].pan, -0.5);
        assert_eq!(i.regions[0].source, Source::File("/lib/a.wav".into()));
    }

    #[test]
    fn control_sets_paths_offsets_and_controllers() {
        let i = parse_text(
            "<control> default_path=samples\\ note_offset=12 set_cc1=127 label_cc1=Dynamics \
             label_key24=Sustain\n<region> sample=x.wav key=c3",
        );
        assert_eq!(i.regions[0].source, Source::File("/lib/samples/x.wav".into()));
        assert_eq!(i.regions[0].lokey, 60);
        assert_eq!(i.cc_init, vec![(1, 1.0)]);
        assert_eq!(i.cc_labels, vec![(1, "Dynamics".to_string())]);
        assert_eq!(i.key_labels, vec![(24, "Sustain".to_string())]);
    }

    #[test]
    fn keyswitches_become_articulations() {
        let i = parse_text(
            "<global> sw_lokey=24 sw_hikey=27 sw_default=24\n\
             <group> sw_last=24 sw_label=Sustain <region> sample=*sine\n\
             <group> sw_last=25 sw_label=Staccato <region> sample=*saw\n\
             <group> sw_last=26 sw_label=Pizzicato <region> sample=*square\n\
             <group> <region> sample=*triangle",
        );
        assert_eq!(i.articulations.len(), 3);
        assert_eq!(i.articulations[1].name, "Staccato");
        assert_eq!(i.articulations[1].keyswitch, Some(25));
        assert_eq!(i.articulations[1].m2, Some(0x110000));
        assert_eq!(i.articulations[2].m2, Some(0x11A000));
        assert_eq!(i.regions[1].switch_any, 0b010);
        assert_eq!(i.regions[3].switch_any, 0, "a region with no sw_last plays always");
        assert_eq!(i.default_switch, 0b001);
        assert_eq!(i.switches.len(), 4, "key 27 in the range chooses none");
        assert_eq!(i.range(), Some((0, 127)));
    }

    #[test]
    fn unknown_opcodes_are_reported_not_fatal() {
        let i = parse_text("<region> sample=*sine frobnicate=3 <effect> type=reverb");
        assert_eq!(i.regions.len(), 1);
        assert!(i.warnings.iter().any(|w| w.contains("frobnicate")));
        assert!(i.warnings.iter().any(|w| w.contains("<effect>")));
    }

    #[test]
    fn comments_defines_and_includes() {
        let dir = std::env::temp_dir().join(format!("paw-sampler-sfz-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("part.sfzh"), "<region> sample=*sine key=$KEY // the key\n").unwrap();
        std::fs::write(
            dir.join("main.sfz"),
            "/* a block\n comment */ #define $KEY 62\n#define $KEYS 70\n#include \"part.sfzh\"\n\
             <region> sample=*saw key=$KEYS\n",
        )
        .unwrap();
        let i = Sfz.read(&dir.join("main.sfz")).unwrap();
        assert_eq!(i.regions.len(), 2);
        assert_eq!(i.regions[0].lokey, 62);
        assert_eq!(i.regions[1].lokey, 70);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn controllers_crossfades_and_curves() {
        let i = parse_text(
            "<curve> curve_index=7 v000=0 v127=0.5\n\
             <region> sample=*sine locc1=0 hicc1=63 xfin_locc1=0 xfin_hicc1=64 \
             amplitude_oncc11=100 amplitude_curvecc11=7 amp_velcurve_127=1 amp_velcurve_64=0.8",
        );
        let r = &i.regions[0];
        assert_eq!(r.cc_ranges, vec![CcRange { cc: 1, lo: 0.0, hi: 63.0 / 127.0 }]);
        assert_eq!(r.xf_cc, vec![(1, Fade { lo: 0.0, hi: 64.0 / 127.0, out: false })]);
        assert_eq!(r.mods.len(), 1);
        assert_eq!(r.mods[0].curve, Some(7));
        assert!((i.curves[7].at(1.0) - 0.5).abs() < 1e-6);
        let vc = &i.curves[r.amp_velcurve.unwrap()];
        assert!((vc.0[64] - 0.8).abs() < 1e-6);
    }
}
