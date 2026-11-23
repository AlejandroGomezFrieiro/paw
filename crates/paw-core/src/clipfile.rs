//! MIDI 2.0 Clip Files (`.midi2`): a MIDI clip's notes and controller moves
//! as Universal MIDI Packets, as the MIDI Association's "MIDI Clip File"
//! specification (M2-116-U) has them.
//!
//! A file is the eight bytes `SMF2CLIP`, then a header and a sequence of
//! packets, each after a Delta Clockstamp that says how many ticks it comes
//! after the one before. The header gives the ticks of a quarter note
//! (a beat); the sequence starts with Start of Clip and ends with End of
//! Clip, at the clip's length.
//!
//! paw writes [`TPQ`] ticks to a beat, notes and controllers as MIDI 2.0
//! channel voice messages on group 1, channel 1, and what MIDI has no
//! message for (a note's `meta`, its id when the ids are not 1, 2, 3, ...
//! in order, notes that start before the clip) as Flex Data text that
//! starts with `paw:`, which other programs pass over. So a clip written and
//! read again is the same clip, but for times, which are rounded to a tick.
//! It reads MIDI 1.0 channel voice messages as well, and any number of ticks
//! to a beat.

use std::collections::HashMap;

use anyhow::{Result, bail};
use paw_types::{EventKind, ump::{self, scale_down, scale_up}};
use serde_json::{Map, Value, json};

use crate::model::{Control, ControlKind, Note, NoteAttr, check_clip_beat};

/// The magic bytes a clip file starts with.
pub(crate) const MAGIC: &[u8; 8] = b"SMF2CLIP";

/// Ticks to a beat in the files paw writes: 2^12 * 3 * 5, so that sixteenths
/// down to 1/4096 of a beat, triplets and quintuplets fall on a tick. At
/// 120 BPM a tick is 8 microseconds, less than a sample at 48 kHz.
pub(crate) const TPQ: u32 = 61440;

/// A clip as a file holds it.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct Clip {
    pub notes: Vec<Note>,
    pub controls: Vec<Control>,
    /// Beats from the start to End of Clip.
    pub length: f64,
    /// What was in the file that a clip has no place for, said once each:
    /// "3 system exclusive messages".
    pub skipped: Vec<String>,
}

/// Whether bytes are a clip file, by their first eight.
pub(crate) fn is_clip_file(bytes: &[u8]) -> bool {
    bytes.starts_with(MAGIC)
}

fn ticks(beats: f64) -> i64 {
    (beats * TPQ as f64).round() as i64
}

fn utility(status: u32, data: u32) -> u32 {
    status << 20 | data
}

/// Delta Clockstamps for `delta` ticks: one for each 2^20 - 1 of them.
fn clockstamps(out: &mut Vec<u32>, mut delta: u64) {
    const MAX: u64 = (1 << 20) - 1;
    loop {
        let step = delta.min(MAX);
        out.push(utility(0x4, step as u32));
        delta -= step;
        if delta == 0 {
            break;
        }
    }
}

/// Flex Data text (status bank 1, metadata; status 0, unknown) of any length,
/// in packets of twelve bytes.
fn flex_text(out: &mut Vec<u32>, text: &str) {
    let bytes = text.as_bytes();
    let chunks: Vec<&[u8]> = bytes.chunks(12).collect();
    let count = chunks.len().max(1);
    for i in 0..count {
        let chunk = chunks.get(i).copied().unwrap_or(&[]);
        // Complete, start, continue, end.
        let form = match (count, i) {
            (1, _) => 0,
            (_, 0) => 1,
            (n, i) if i + 1 == n => 3,
            _ => 2,
        };
        // Addressed to the group (addrs 1), status bank 1, status 0.
        out.push(0xD << 28 | form << 22 | 1 << 20 | 0x01 << 8);
        let mut words = [0u32; 3];
        for (j, b) in chunk.iter().enumerate() {
            words[j / 4] |= (*b as u32) << (24 - 8 * (j % 4));
        }
        out.extend_from_slice(&words);
    }
}

fn stream(status: u32) -> [u32; 4] {
    [0xF << 28 | status << 16, 0, 0, 0]
}

/// What a note-off or a note-on is: its order among the messages of one tick.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Order {
    Off,
    Control,
    On,
}

struct Message {
    tick: i64,
    order: Order,
    seq: usize,
    words: Vec<u32>,
}

/// The bytes of a clip file for a clip's notes and controller moves, in
/// the order they come in, and its length in beats.
///
/// # Errors
///
/// A time out of the range that a clip holds
/// ([`MAX_BEATS`](crate::model::MAX_BEATS)): far times
/// would take billions of clockstamps.
pub fn encode<'a>(
    notes: impl IntoIterator<Item = &'a Note>,
    controls: &[Control],
    length: f64,
) -> Result<Vec<u8>> {
    let notes: Vec<&Note> = notes.into_iter().collect();
    check_times(notes.iter().copied(), controls, length)?;
    let mut messages = Vec::new();
    for c in controls {
        if let Some(words) = ump::encode(0, c.event(0)) {
            messages.push((ticks(c.start), Order::Control, words.to_vec()));
        }
    }
    note_messages(&notes, &mut messages);
    let messages: Vec<Message> = messages
        .into_iter()
        .enumerate()
        .map(|(seq, (tick, order, words))| Message {
            tick,
            order,
            seq,
            words,
        })
        .collect();
    let mut bytes = Vec::new();
    bytes.extend_from_slice(MAGIC);
    for w in sequence_words(messages, length) {
        bytes.extend_from_slice(&w.to_be_bytes());
    }
    Ok(bytes)
}

/// An error unless each time of a clip is in the range that a clip holds.
/// In that range a clip file has a bounded number of clockstamps, and no
/// count of ticks overflows. Only the start and the end of each note
/// matter: the length is the gap between them.
fn check_times<'a>(
    notes: impl IntoIterator<Item = &'a Note>,
    controls: &[Control],
    length: f64,
) -> Result<()> {
    for n in notes {
        check_clip_beat("a note", n.start)?;
        check_clip_beat("the end of a note", n.start + n.length)?;
    }
    for c in controls {
        check_clip_beat("a controller move", c.start)?;
    }
    check_clip_beat("the end of the clip", length)
}

/// The start tick of a note and the tick where it ends (at least one later).
fn span(n: &Note) -> (i64, i64) {
    let start = ticks(n.start);
    (start, ticks(n.start + n.length).max(start + 1))
}

/// Reading pairs a note-off with the first note on its key to start (or
/// with one whose length the file gives that ends there). A note that
/// would be paired wrongly that way has its length written: these are the
/// notes (by place) that need it.
fn notes_needing_length(notes: &[&Note]) -> Vec<bool> {
    let mut needs_length = vec![false; notes.len()];
    let mut events: Vec<(i64, Order, usize)> = Vec::new();
    for (i, n) in notes.iter().enumerate() {
        let (start, end) = span(n);
        events.push((start, Order::On, i));
        events.push((end, Order::Off, i));
    }
    events.sort();
    let mut open: HashMap<u8, Vec<usize>> = HashMap::new();
    for (_, order, i) in events {
        let queue = open.entry(notes[i].pitch).or_default();
        if order == Order::On {
            queue.push(i);
            continue;
        }
        if queue.iter().find(|&&j| !needs_length[j]) != Some(&i) {
            needs_length[i] = true;
        }
        queue.retain(|&j| j != i);
    }
    needs_length
}

/// The note-on (with its `paw:` text when it has one) and the note-off of
/// each note, as `(tick, order, words)`.
fn note_messages(notes: &[&Note], out: &mut Vec<(i64, Order, Vec<u32>)>) {
    // Ids are written only when they are not what reading gives anyway.
    let plain_ids = notes.iter().enumerate().all(|(i, n)| n.id == i as u64 + 1)
        || notes.iter().all(|n| n.id == 0);
    let needs_length = notes_needing_length(notes);
    for (i, n) in notes.iter().enumerate() {
        let (start, end) = span(n);
        let mut extra = Map::new();
        if !plain_ids {
            extra.insert("id".into(), json!(n.id));
        }
        if !n.meta.is_empty() {
            extra.insert("meta".into(), Value::Object(n.meta.clone()));
        }
        if needs_length[i] {
            extra.insert("len".into(), json!(end - start));
        }
        let mut words = Vec::new();
        if !extra.is_empty() {
            flex_text(&mut words, &format!("paw:{}", Value::Object(extra)));
            // Its own clockstamp follows, of 0 ticks.
            words.push(utility(0x4, 0));
        }
        let vel = scale_up(n.velocity.clamp(1, 127) as u32, 7, 16);
        let attr = n.attr.map(|a| (a.kind, a.data)).unwrap_or((0, 0));
        words.push(4 << 28 | 0x9 << 20 | (n.pitch as u32 & 127) << 8 | attr.0 as u32);
        words.push(vel << 16 | attr.1 as u32);
        out.push((start, Order::On, words));
        out.push((
            end,
            Order::Off,
            vec![4 << 28 | 0x8 << 20 | (n.pitch as u32 & 127) << 8, 0],
        ));
    }
}

/// The words of the file after the magic: the header, Start of Clip, the
/// messages in order with their clockstamps, and End of Clip.
fn sequence_words(mut messages: Vec<Message>, length: f64) -> Vec<u32> {
    messages.sort_by_key(|m| (m.tick, m.order, m.seq));
    let origin = messages.first().map_or(0, |m| m.tick.min(0));
    let mut words = Vec::new();
    // The header: ticks to a beat, and where the clip starts if a note
    // starts before it.
    words.push(utility(0x4, 0));
    words.push(utility(0x3, TPQ));
    if origin < 0 {
        words.push(utility(0x4, 0));
        flex_text(&mut words, &format!("paw:{}", json!({ "origin": origin })));
    }
    words.push(utility(0x4, 0));
    words.extend(stream(0x20));
    let mut at = origin;
    for m in &messages {
        clockstamps(&mut words, (m.tick - at) as u64);
        at = m.tick;
        words.extend_from_slice(&m.words);
    }
    let end = ticks(length).max(at);
    clockstamps(&mut words, (end - at) as u64);
    words.extend(stream(0x21));
    words
}

/// How many 32-bit words a packet of this message type takes.
fn packet_words(kind: u32) -> usize {
    match kind {
        0x0 | 0x1 | 0x2 | 0x6 | 0x7 => 1,
        0x3 | 0x4 | 0x8 | 0x9 | 0xA => 2,
        0xB | 0xC => 3,
        _ => 4,
    }
}

struct Open {
    /// Its place among the notes, by when it started.
    seq: usize,
    /// The tick it starts at: its length is counted in ticks, so that a
    /// length of 0.25 does not come back as 0.25000000000000006.
    tick: i64,
    note: Note,
    /// The tick it ends at, when the file said so.
    end: Option<i64>,
}

/// What reading a file has seen so far.
struct Reader {
    tpq: u32,
    tick: i64,
    origin: i64,
    started: bool,
    ended: Option<i64>,
    clip: Clip,
    open: HashMap<u8, Vec<Open>>,
    done: Vec<(usize, Note)>,
    count: usize,
    /// The bytes of the Flex Data text read so far. Bytes, not characters:
    /// a character of UTF-8 can be cut between two packets.
    text: Vec<u8>,
    pending: Option<Map<String, Value>>,
    skipped: HashMap<&'static str, usize>,
}

impl Reader {
    fn new() -> Self {
        Reader {
            tpq: 96,
            tick: 0,
            origin: 0,
            started: false,
            ended: None,
            clip: Clip::default(),
            open: HashMap::new(),
            done: Vec::new(),
            count: 0,
            text: Vec::new(),
            pending: None,
            skipped: HashMap::new(),
        }
    }

    fn beat(&self, tick: i64) -> f64 {
        tick as f64 / self.tpq as f64
    }

    fn skip(&mut self, what: &'static str) {
        *self.skipped.entry(what).or_default() += 1;
    }

    /// A utility message: ticks to a beat, or a Delta Clockstamp.
    fn utility(&mut self, w0: u32) {
        match (w0 >> 20) & 15 {
            0x3 => self.tpq = (w0 & 0xffff).max(1),
            // An origin from the file can be any number: the ticks stop at
            // the largest one and do not overflow.
            0x4 if self.started => self.tick = self.tick.saturating_add((w0 & 0xfffff) as i64),
            _ => {}
        }
    }

    /// A stream message: Start of Clip, or End of Clip (true).
    fn stream(&mut self, w0: u32) -> bool {
        match (w0 >> 16) & 0x3ff {
            0x20 => {
                self.started = true;
                self.tick = self.origin;
            }
            0x21 => {
                self.ended = Some(self.tick);
                return true;
            }
            _ => {}
        }
        false
    }

    /// A Flex Data packet: text of `paw:` that goes before a note or the
    /// clip's origin.
    fn flex_data(&mut self, packet: &[u32]) {
        let w0 = packet[0];
        let form = (w0 >> 22) & 3;
        let bank = (w0 >> 8) & 0xff;
        if bank != 0x01 || w0 & 0xff != 0 {
            return;
        }
        if form == 0 || form == 1 {
            self.text.clear();
        }
        for w in &packet[1..] {
            for b in w.to_be_bytes() {
                if b != 0 {
                    self.text.push(b);
                }
            }
        }
        if form == 0 || form == 3 {
            if let Some(json) = self.text.strip_prefix(b"paw:")
                && let Ok(Value::Object(map)) = serde_json::from_slice::<Value>(json)
            {
                if !self.started {
                    self.origin = map.get("origin").and_then(Value::as_i64).unwrap_or(0);
                } else {
                    self.pending = Some(map);
                }
            }
            self.text.clear();
        }
    }

    /// A MIDI 1.0 (kind 2) or MIDI 2.0 (kind 4) channel voice message.
    fn channel_voice(&mut self, kind: u32, packet: &[u32]) {
        let Some((_, event)) = ump::decode(packet) else {
            self.skip("other channel messages");
            return;
        };
        match event {
            EventKind::NoteOn { key, attr, .. } => {
                let vel = if kind == 4 {
                    scale_down(packet[1] >> 16, 16, 7) as u8
                } else {
                    (packet[0] & 0x7f) as u8
                };
                self.note_on(key, vel, attr);
            }
            EventKind::NoteOff { key, .. } => self.note_off(key),
            other => self.control(other),
        }
    }

    fn note_on(&mut self, key: u8, vel: u8, attr: paw_types::Attr) {
        let extra = self.pending.take().unwrap_or_default();
        let note = Note {
            start: self.beat(self.tick),
            length: 0.0,
            pitch: key,
            velocity: vel.clamp(1, 127),
            meta: match extra.get("meta") {
                Some(Value::Object(m)) => m.clone(),
                _ => Map::new(),
            },
            id: extra.get("id").and_then(Value::as_u64).unwrap_or(0),
            attr: NoteAttr::of(attr),
        };
        let end = extra
            .get("len")
            .and_then(Value::as_i64)
            .map(|l| self.tick.saturating_add(l));
        self.open.entry(key).or_default().push(Open {
            seq: self.count,
            tick: self.tick,
            note,
            end,
        });
        self.count += 1;
    }

    fn note_off(&mut self, key: u8) {
        let tick = self.tick;
        let queue = self.open.entry(key).or_default();
        let pos = queue
            .iter()
            .position(|o| o.end == Some(tick))
            .or_else(|| queue.iter().position(|o| o.end.is_none()));
        if let Some(pos) = pos {
            let mut o = queue.remove(pos);
            o.note.length = self.beat(tick.saturating_sub(o.tick));
            self.done.push((o.seq, o.note));
        }
    }

    fn control(&mut self, event: EventKind) {
        let at = self.beat(self.tick);
        match Control::from_event(at, event) {
            Some(mut c) => {
                // A note's registered controller is the control
                // change of that number, kept on the note.
                if c.key.is_some()
                    && let ControlKind::Registered { index, .. } = c.what
                {
                    c.what = ControlKind::Cc { number: index };
                }
                c.value = shortest(c.value, matches!(c.what, ControlKind::Bend));
                self.clip.controls.push(c);
            }
            None => self.skip("other channel messages"),
        }
    }

    /// The clip, when every packet has been read.
    fn finish(mut self) -> Clip {
        // Notes still sounding at the end end there.
        let end_tick = self.ended.unwrap_or(self.tick);
        for (_, queue) in std::mem::take(&mut self.open) {
            for o in queue {
                let mut note = o.note;
                let end = o.end.unwrap_or(end_tick);
                note.length = self.beat(end.saturating_sub(o.tick));
                self.done.push((o.seq, note));
            }
        }
        // In the order they started.
        self.done.sort_by_key(|(seq, _)| *seq);
        let length = self.beat(end_tick).max(0.0);
        let mut clip = self.clip;
        clip.notes = self.done.into_iter().map(|(_, n)| n).collect();
        // A file that gives no ids has the ids 1, 2, 3 in order, as the
        // session would give them: nothing is left to name after reading.
        if clip.notes.iter().all(|n| n.id == 0) {
            for (i, n) in clip.notes.iter_mut().enumerate() {
                n.id = i as u64 + 1;
            }
        }
        clip.length = length;
        let mut skipped: Vec<_> = self.skipped.into_iter().collect();
        skipped.sort();
        clip.skipped = skipped
            .into_iter()
            .map(|(what, n)| format!("{n} {what}"))
            .collect();
        clip
    }
}

/// Read a clip file.
pub fn decode(bytes: &[u8]) -> Result<Clip> {
    if !is_clip_file(bytes) {
        bail!("not a MIDI 2.0 clip file (it does not start with SMF2CLIP)");
    }
    let body = &bytes[8..];
    if !body.len().is_multiple_of(4) {
        bail!("the clip file is cut short");
    }
    let words: Vec<u32> = body
        .chunks_exact(4)
        .map(|c| u32::from_be_bytes([c[0], c[1], c[2], c[3]]))
        .collect();
    let mut reader = Reader::new();
    let mut i = 0;
    while i < words.len() {
        let w0 = words[i];
        let kind = w0 >> 28;
        let n = packet_words(kind);
        if i + n > words.len() {
            bail!("the clip file is cut short");
        }
        let packet = &words[i..i + n];
        i += n;
        match kind {
            0x0 => reader.utility(w0),
            0xF if reader.stream(w0) => break,
            0xD => reader.flex_data(packet),
            0x2 | 0x4 if reader.started => reader.channel_voice(kind, packet),
            0x3 | 0x5 => reader.skip("system exclusive messages"),
            _ => {}
        }
    }
    let clip = reader.finish();
    // A file from elsewhere can put a note at any tick: paw takes only the
    // clips that it can write again.
    check_times(&clip.notes, &clip.controls, clip.length)?;
    Ok(clip)
}

/// The number with the fewest digits that is still the same 32-bit value:
/// a 0.25 written is read as 0.25, not 0.2500000000582.
fn shortest(value: f64, bipolar: bool) -> f64 {
    let code = |v: f64| {
        if bipolar {
            ump::from_bipolar(v)
        } else {
            ump::from_unit(v)
        }
    };
    let want = code(value);
    for digits in 1..=12 {
        let scale = 10f64.powi(digits);
        let near = (value * scale).round() / scale;
        if code(near) == want {
            return near;
        }
    }
    value
}

const NAMES: [&str; 12] = [
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
];

/// A key's name: 60 is C4.
pub(crate) fn key_name(key: u8) -> String {
    format!("{}{}", NAMES[key as usize % 12], key as i32 / 12 - 1)
}

/// A clip as text, one note or controller move to a line, in the order they
/// happen: for `git diff` (`paw clip cat`) and for reading.
pub fn text(clip: &Clip) -> String {
    let mut lines: Vec<(f64, u8, String)> = Vec::new();
    for n in &clip.notes {
        let mut line = format!(
            "{:>10}  note {:<4} {:>3}  len {}  vel {}",
            fmt(n.start),
            key_name(n.pitch),
            n.pitch,
            fmt(n.length),
            n.velocity
        );
        if let Some(a) = n.attr {
            line += &format!("  attr {}:{}", a.kind, a.data);
        }
        if !n.meta.is_empty() {
            line += &format!("  {}", Value::Object(n.meta.clone()));
        }
        lines.push((n.start, 1, line));
    }
    for c in &clip.controls {
        let what = match c.what {
            ControlKind::Cc { number } => format!("cc {number}"),
            ControlKind::Bend => "bend".into(),
            ControlKind::Pressure => "pressure".into(),
            ControlKind::Registered { bank, index } => format!("rpn {bank}:{index}"),
            ControlKind::Assignable { bank, index } => format!("nrpn {bank}:{index}"),
            ControlKind::Program { program, bank } => match bank {
                Some(b) => format!("program {program} bank {b}"),
                None => format!("program {program}"),
            },
        };
        let mut line = format!("{:>10}  {what}", fmt(c.start));
        if !matches!(c.what, ControlKind::Program { .. }) {
            line += &format!(" = {}", fmt(c.value));
        }
        if let Some(key) = c.key {
            line += &format!("  key {} {key}", key_name(key));
        }
        lines.push((c.start, 0, line));
    }
    lines.sort_by(|a, b| a.0.total_cmp(&b.0).then(a.1.cmp(&b.1)));
    let mut out = format!(
        "# {} notes, {} controller moves, {} beats\n",
        clip.notes.len(),
        clip.controls.len(),
        fmt(clip.length)
    );
    for (_, _, line) in lines {
        out += line.trim_end();
        out.push('\n');
    }
    for s in &clip.skipped {
        out += &format!("# left out: {s}\n");
    }
    out
}

/// A number with no more digits than it needs, at most six after the point.
fn fmt(x: f64) -> String {
    let s = format!("{x:.6}");
    let s = s.trim_end_matches('0').trim_end_matches('.');
    if s == "-0" { "0".into() } else { s.into() }
}

#[cfg(test)]
mod props;
#[cfg(test)]
mod tests {
    use super::*;

    fn note(start: f64, length: f64, pitch: u8) -> Note {
        Note {
            start,
            length,
            pitch,
            velocity: 100,
            meta: Map::new(),
            id: 0,
            attr: None,
        }
    }

    fn named(mut notes: Vec<Note>) -> Vec<Note> {
        for (i, n) in notes.iter_mut().enumerate() {
            n.id = i as u64 + 1;
        }
        notes
    }

    /// A clip with each thing a file holds: a triplet, a note's `meta`, a
    /// MIDI 2.0 attribute, the lowest velocity, a controller, a bend on one
    /// key, and a program change with a bank.
    fn each_part() -> (Vec<Note>, Vec<Control>) {
        let mut notes = named(vec![
            note(0.0, 0.5, 60),
            note(0.5, 0.25, 64),
            note(1.0 / 3.0, 1.0, 67),
        ]);
        notes.sort_by(|a, b| a.start.total_cmp(&b.start));
        notes[1].meta.insert("lyric".into(), json!("la"));
        notes[2].attr = Some(NoteAttr {
            kind: 17,
            data: 40960,
        });
        notes[0].velocity = 1;
        let controls = vec![
            Control {
                start: 0.0,
                what: ControlKind::Cc { number: 1 },
                value: 0.25,
                key: None,
            },
            Control {
                start: 0.5,
                what: ControlKind::Bend,
                value: -0.5,
                key: Some(64),
            },
            Control {
                start: 1.0,
                what: ControlKind::Program {
                    program: 5,
                    bank: Some(300),
                },
                value: 0.0,
                key: None,
            },
        ];
        (notes, controls)
    }

    /// The words of a clip file after its magic bytes, one packet to a
    /// line, in hexadecimal.
    fn packets(bytes: &[u8]) -> String {
        let words: Vec<u32> = bytes[MAGIC.len()..]
            .chunks_exact(4)
            .map(|c| u32::from_be_bytes([c[0], c[1], c[2], c[3]]))
            .collect();
        let mut lines = Vec::new();
        let mut i = 0;
        while i < words.len() {
            let n = packet_words(words[i] >> 28).min(words.len() - i);
            let packet: Vec<String> = words[i..i + n].iter().map(|w| format!("{w:08x}")).collect();
            lines.push(packet.join(" "));
            i += n;
        }
        lines.join("\n")
    }

    #[test]
    fn a_clip_file_has_the_packets_of_the_golden_file() {
        let (notes, controls) = each_part();
        let bytes = encode(&notes, &controls, 4.0).unwrap();
        let clip = decode(&bytes).unwrap();
        insta::assert_snapshot!(format!("{}{}", text(&clip), packets(&bytes)));
    }

    #[test]
    fn a_clip_comes_back_the_same() {
        let (notes, controls) = each_part();
        let bytes = encode(&notes, &controls, 4.0).unwrap();
        let clip = decode(&bytes).unwrap();
        assert_eq!(clip.length, 4.0);
        assert_eq!(clip.controls.len(), 3);
        assert_eq!(clip.controls[0].what, ControlKind::Cc { number: 1 });
        assert_eq!(clip.controls[0].value, 0.25);
        assert_eq!(clip.controls[1].value, -0.5);
        assert_eq!(clip.controls[1].key, Some(64));
        assert_eq!(clip.notes.len(), 3);
        for (a, b) in clip.notes.iter().zip(&notes) {
            assert_eq!(a.pitch, b.pitch);
            assert_eq!(a.velocity, b.velocity);
            assert_eq!(a.meta, b.meta);
            assert_eq!(a.attr, b.attr);
            assert!((a.start - b.start).abs() < 1e-4);
            assert!((a.length - b.length).abs() < 1e-4);
        }
        // Its bytes, read and written again, are the same bytes.
        let again = encode(&clip.notes, &clip.controls, clip.length).unwrap();
        assert_eq!(again, bytes);
    }

    #[test]
    fn notes_before_the_start_and_overlaps_on_one_key() {
        let notes = named(vec![
            note(-1.0, 2.0, 60),
            note(0.0, 4.0, 62),
            note(0.5, 1.0, 62),
        ]);
        let bytes = encode(&notes, &[], 4.0).unwrap();
        let clip = decode(&bytes).unwrap();
        assert_eq!(clip.notes.len(), 3);
        assert_eq!(clip.notes[0].start, -1.0);
        let long = clip.notes.iter().find(|n| n.start == 0.0).unwrap();
        assert_eq!(long.length, 4.0);
        let short = clip.notes.iter().find(|n| n.start == 0.5).unwrap();
        assert_eq!(short.length, 1.0);
        assert_eq!(encode(&clip.notes, &[], clip.length).unwrap(), bytes);
    }

    #[test]
    fn ids_out_of_order_are_kept() {
        let mut notes = vec![note(0.0, 1.0, 60), note(1.0, 1.0, 61)];
        notes[0].id = 7;
        notes[1].id = 3;
        let clip = decode(&encode(&notes, &[], 2.0).unwrap()).unwrap();
        assert_eq!(clip.notes[0].id, 7);
        assert_eq!(clip.notes[1].id, 3);
    }

    #[test]
    fn midi_1_messages_read() {
        let mut bytes = MAGIC.to_vec();
        let words = [
            utility(0x4, 0),
            utility(0x3, 96),
            utility(0x4, 0),
            0xF020_0000,
            0,
            0,
            0,
            utility(0x4, 0),
            0x2090_3C64,
            utility(0x4, 48),
            0x2080_3C00,
            utility(0x4, 48),
            0xF021_0000,
            0,
            0,
            0,
        ];
        for w in words {
            bytes.extend_from_slice(&w.to_be_bytes());
        }
        let clip = decode(&bytes).unwrap();
        assert_eq!(clip.notes.len(), 1);
        assert_eq!(clip.notes[0].velocity, 100);
        assert_eq!(clip.notes[0].length, 0.5);
        assert_eq!(clip.length, 1.0);
        assert!(text(&clip).contains("note C4    60  len 0.5  vel 100"));
    }

    #[test]
    fn long_gaps_take_several_clockstamps() {
        let notes = named(vec![note(0.0, 1.0, 60), note(100.0, 1.0, 60)]);
        let clip = decode(&encode(&notes, &[], 101.0).unwrap()).unwrap();
        assert_eq!(clip.notes[1].start, 100.0);
    }

    /// The bytes of a clip file of one tick to a beat: `paw:` text before
    /// Start of Clip, then `body` and End of Clip.
    fn file_with(before_start: &str, body: &[u32]) -> Vec<u8> {
        let mut words = vec![utility(0x4, 0), utility(0x3, 1), utility(0x4, 0)];
        flex_text(&mut words, before_start);
        words.push(utility(0x4, 0));
        words.extend(stream(0x20));
        words.extend_from_slice(body);
        words.push(utility(0x4, 0));
        words.extend(stream(0x21));
        let mut bytes = MAGIC.to_vec();
        for w in words {
            bytes.extend_from_slice(&w.to_be_bytes());
        }
        bytes
    }

    // Found while writing the fuzz target `clip_file`: ticks
    // past the largest number overflowed, and a dev build panicked.
    #[test]
    fn an_origin_or_a_length_past_the_largest_tick_reads_without_a_panic() {
        // Past the range a clip holds: refused with a message.
        let far_origin = file_with(&format!("paw:{{\"origin\":{}}}", i64::MAX), &[utility(0x4, 1)]);
        assert!(decode(&far_origin).is_err());

        let mut note = vec![utility(0x4, 1)];
        flex_text(&mut note, &format!("paw:{{\"len\":{}}}", i64::MAX));
        note.extend([utility(0x4, 0), 0x2090_3C64]);
        assert!(decode(&file_with("", &note)).is_err());
    }
}

// The range of times a clip holds.
#[cfg(test)]
mod far_times;
