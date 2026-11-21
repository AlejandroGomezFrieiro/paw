//! Clips as the engine plays them: MIDI compiled to events, audio as
//! regions, sent whole or as the parts an edit changed; and the clips off
//! the timeline, in their rows.

use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;

use paw_engine::launch::{SlotClip, Slots};
use paw_engine::{AudioData, AudioRegion, ClipSet, MidiEv, Part, PartEdit, db_to_gain};

use super::SyncCtx;
use super::mapper::{CueEvents, Mapper};
use crate::model::{Clip, ClipContent, Control, Id, Note, Notes, Track};

/// One MIDI clip's notes and controller moves as engine events, sorted. A
/// looped clip plays what lies in its repeated stretch over and over, each
/// note cut at the end of its repeat.
fn compile_clip(clip: &Clip, notes: &Notes, controls: &[Control]) -> Arc<[MidiEv]> {
    let mut set = ClipSet::default();
    let Some((from, beats)) = clip.repeat() else {
        return compile_part(clip, notes, controls);
    };
    let inside = |at: f64| at >= from && at < from + beats;
    for (base, end) in repeats(from, beats, clip.length) {
        let place = |at: f64| base + (at - from);
        for control in controls.iter().filter(|c| inside(c.start)) {
            let at = place(control.start);
            if at >= 0.0 && at < clip.length {
                set.push_event(clip.start + at, control.event(0));
            }
        }
        for note in notes.iter().filter(|n| inside(n.start)) {
            let at = place(note.start);
            if at >= 0.0 && at < clip.length {
                let stop = (at + note.length).min(end);
                let vel = note.velocity.clamp(1, 127) as f32 / 127.0;
                let (start, stop) = (clip.start + at, clip.start + stop);
                set.push_note_attr(start, stop, note.pitch, vel, attr_of(note));
            }
        }
    }
    set.finish();
    set.midi.into()
}

/// Some of the notes and controllers of a clip that does not loop, as
/// engine events: what [`compile_clip`] makes of them all.
fn compile_part<'a>(
    clip: &Clip,
    notes: impl IntoIterator<Item = &'a Note>,
    controls: &[Control],
) -> Arc<[MidiEv]> {
    let mut set = ClipSet::default();
    for control in controls
        .iter()
        .filter(|c| c.start >= 0.0 && c.start < clip.length)
    {
        set.push_event(clip.start + control.start, control.event(0));
    }
    for note in notes
        .into_iter()
        .filter(|n| n.start >= 0.0 && n.start < clip.length)
    {
        let end = (note.start + note.length).min(clip.length);
        let vel = note.velocity.clamp(1, 127) as f32 / 127.0;
        let (start, end) = (clip.start + note.start, clip.start + end);
        set.push_note_attr(start, end, note.pitch, vel, attr_of(note));
    }
    set.finish();
    set.midi.into()
}

/// A note's attribute as the engine has it.
fn attr_of(note: &Note) -> paw_engine::Attr {
    note.attr.map_or(paw_engine::Attr::NONE, Into::into)
}

/// Where each repeat of a looped clip begins and ends, from the clip's
/// start, for a repeated stretch beginning at `from` and `period` long, in
/// a clip `length` long: the first begins at or before 0, the last ends
/// at `length` or later. In beats for MIDI, in seconds for sound.
pub fn repeats(from: f64, period: f64, length: f64) -> impl Iterator<Item = (f64, f64)> {
    // The repeat the clip's start falls in.
    let first = from - period * (from / period).ceil();
    let count = if period > 0.0 {
        ((length - first) / period).ceil().max(0.0) as usize
    } else {
        0
    };
    (0..count).map(move |k| {
        let a = first + k as f64 * period;
        (a, first + (k + 1) as f64 * period)
    })
}

/// Whether sound repeated from `from` for `seconds` runs on from its end
/// into its start without a jump: the frame after its end is about the
/// frame at its start, as near as one frame is to the next around there.
fn joins_itself(data: &AudioData, from: f64, seconds: f64) -> bool {
    let rate = data.sample_rate as f64;
    let (a, b) = (
        (from * rate).round() as i64,
        ((from + seconds) * rate).round() as i64,
    );
    let at = |c: &[f32], i: i64| {
        usize::try_from(i)
            .ok()
            .and_then(|i| c.get(i))
            .copied()
            .unwrap_or(0.0)
    };
    data.channels.iter().all(|c| {
        let jump = (at(c, b) - at(c, a)).abs();
        let step = [a, b]
            .iter()
            .flat_map(|&i| {
                [
                    (at(c, i) - at(c, i - 1)).abs(),
                    (at(c, i + 1) - at(c, i)).abs(),
                ]
            })
            .fold(0.0, f32::max);
        jump <= 2.0 * step + 1e-4
    })
}

/// The regions an audio clip plays: the part of `data` from `offset`
/// seconds, or, looped, its repeated stretch again and again. A fade in
/// belongs to the first repeat and a fade out to the last, each as long
/// as that repeat at most.
fn audio_regions(
    clip: &Clip,
    data: Arc<AudioData>,
    offset: f64,
    gain: f32,
    tempo: &paw_engine::TempoMap,
    out: &mut Vec<AudioRegion>,
) {
    let seconds = tempo.seconds_between(clip.start, clip.start + clip.length);
    let end = clip.start + clip.length;
    let Some((from, beats)) = clip.repeat() else {
        out.push(AudioRegion {
            start: clip.start,
            end,
            // An edge inside the recording is a cut.
            declick_in: offset > 1e-6,
            declick_out: offset + seconds < data.whole_seconds() - 1e-6,
            data,
            offset,
            gain,
            fade_in: clip.fade_in,
            fade_out: clip.fade_out,
            hold: Default::default(),
        });
        return;
    };
    // A repeat lasts as long in seconds as its beats do from the clip's start.
    let period = tempo.seconds_between(clip.start, clip.start + beats);
    if period <= 1e-9 {
        return;
    }
    let lead = from * period / beats;
    let begins = offset + lead;
    let joins = joins_itself(&data, begins, period);
    let t0 = tempo.seconds(clip.start);
    let first = out.len();
    for (a, b) in repeats(lead, period, seconds) {
        let (ra, rb) = (a.max(0.0), b.min(seconds));
        if rb - ra <= 1e-9 {
            continue;
        }
        let into = begins + (ra - a);
        let start = if ra <= 0.0 {
            clip.start
        } else {
            tempo.beat(t0 + ra)
        };
        let stop = if rb >= seconds {
            end
        } else {
            tempo.beat(t0 + rb)
        };
        out.push(AudioRegion {
            start,
            end: stop,
            declick_in: if ra <= 0.0 { into > 1e-6 } else { !joins },
            declick_out: if rb >= seconds {
                into + (rb - ra) < data.whole_seconds() - 1e-6
            } else {
                !joins
            },
            data: data.clone(),
            offset: into,
            gain,
            fade_in: 0.0,
            fade_out: 0.0,
            hold: Default::default(),
        });
    }
    if let Some(r) = out.get_mut(first) {
        r.fade_in = clip.fade_in.min(r.end - r.start);
    }
    if out.len() > first
        && let Some(r) = out.last_mut()
    {
        r.fade_out = clip.fade_out.min(r.end - r.start);
    }
}

/// What the engine has of a track's clips, sent as parts: one for each
/// clip, or for a long MIDI clip one for its controllers and one for each
/// few runs of its notes (see [`Notes`]), so that a note edited compiles
/// again only the notes beside it.
#[derive(Default)]
pub(super) struct Parts {
    /// Each clip by id, as compiled and sent.
    pub clips: HashMap<Id, SentClip>,
    /// How many parts the engine has, and room for.
    len: usize,
    room: usize,
    /// The clips were sent as one list, through the track's attribute map:
    /// only their events are kept, to compile only what changed.
    flat: bool,
}

/// One clip as the engine was sent it.
pub(super) struct SentClip {
    clip: Arc<Clip>,
    /// Its order (see [`paw_engine::Part::order`]); its parts have this
    /// order and those after it, one each.
    order: u64,
    /// Its events in pieces (see [`pieces_of`]); none for an audio clip.
    pub pieces: Vec<Piece>,
    /// The orders of the parts the engine has of it: those not empty.
    parts: Vec<u64>,
}

// SAFETY: the pointers only name runs to compare with: never read through.
unsafe impl Send for SentClip {}

/// The space between the orders of two clips side by side when a track's
/// parts are sent whole: clips put in between later take orders between.
const ORDER_GAP: u64 = 1 << 32;
/// An edit of more clips than this sends the track's clips whole.
const MAX_EDIT: usize = 512;

/// A piece of a clip's events.
#[derive(Clone)]
pub(super) struct Piece {
    /// The runs of notes it is compiled from (none for the controllers, or
    /// for a clip in one piece). Only compared, never read through.
    pub runs: Vec<*const Vec<Note>>,
    pub events: Arc<[MidiEv]>,
}

impl Piece {
    fn whole(events: Arc<[MidiEv]>) -> Self {
        Self { runs: Vec::new(), events }
    }
}

/// Notes in a piece of a clip's events: runs side by side go in one piece
/// until it has this many.
const PIECE: usize = 256;

/// The pieces of a clip's events: its controllers and its notes in pieces
/// of a few runs (in that order, which is the order a clip's events are
/// compiled in); a short or looped clip in one piece. A piece of the very
/// same runs as one of the clip `before` is not compiled again.
fn pieces_of(clip: &Clip, before: Option<&SentClip>) -> Vec<Piece> {
    let ClipContent::Midi { notes, controls } = &clip.content else {
        return Vec::new();
    };
    // The very same clip: nothing to compile.
    if let Some(b) = before.filter(|b| std::ptr::eq(&*b.clip, clip)) {
        return b.pieces.clone();
    }
    if notes.len() <= PIECE || clip.repeat().is_some() {
        return vec![Piece::whole(compile_clip(clip, notes, controls))];
    }
    // Compiled pieces of the clip before, by their first run.
    let mut known: HashMap<*const Vec<Note>, &Piece> = HashMap::new();
    if let Some(b) = before.filter(|b| b.clip.start == clip.start && b.clip.length == clip.length) {
        for piece in &b.pieces {
            if let Some(&first) = piece.runs.first() {
                known.insert(first, piece);
            }
        }
    }
    let mut out = Vec::new();
    // The controllers are compiled again with any change of the clip.
    out.push(Piece::whole(compile_part(clip, &[], controls)));
    let runs = notes.runs();
    let mut at = 0;
    while at < runs.len() {
        let (mut end, mut count) = (at, 0);
        while end < runs.len() && count < PIECE {
            count += runs[end].len();
            end += 1;
        }
        let ptrs: Vec<*const Vec<Note>> = runs[at..end].iter().map(Arc::as_ptr).collect();
        let events = match known.get(&ptrs[0]) {
            Some(was) if was.runs == ptrs => was.events.clone(),
            _ => compile_part(clip, runs[at..end].iter().flat_map(|r| r.iter()), &[]),
        };
        out.push(Piece { runs: ptrs, events });
        at = end;
    }
    out
}

/// A clip's parts from `order` on, compiling only what changed since
/// `before`, and the clip as sent.
fn parts_of(
    clip: &Arc<Clip>,
    order: u64,
    before: Option<&SentClip>,
    tempo: &paw_engine::TempoMap,
    ctx: &mut SyncCtx,
) -> (Vec<Part>, SentClip) {
    let mut audio = Vec::new();
    let mut pieces = Vec::new();
    if !clip.muted {
        match &clip.content {
            ClipContent::Midi { .. } => pieces = pieces_of(clip, before),
            ClipContent::Audio { file, offset, gain, .. } => {
                clip_audio(clip, (file, *offset, *gain), tempo, ctx, &mut audio)
            }
            // A custom clip does not play its sound yet.
            ClipContent::Custom(_) => {}
        }
    }
    let mut parts = Vec::with_capacity(pieces.len().max(1));
    if !audio.is_empty() {
        parts.push(Part::new(clip.id, order, Arc::from([]), audio));
    }
    for (k, piece) in pieces.iter().enumerate() {
        parts.push(Part::new(clip.id, order + k as u64, piece.events.clone(), Vec::new()));
    }
    parts.retain(|p| !p.is_empty());
    let sent = SentClip {
        clip: clip.clone(),
        order,
        pieces,
        parts: parts.iter().map(|p| p.order).collect(),
    };
    (parts, sent)
}

/// How many orders a clip's parts take.
fn orders_taken(clip: &Clip) -> u64 {
    match &clip.content {
        ClipContent::Midi { notes, .. } => notes.runs().len() as u64 + 1,
        ClipContent::Audio { .. } | ClipContent::Custom(_) => 1,
    }
}

/// Whether a track's events go through its attribute map: then its clips
/// are sent as one list, which the map changes as a whole.
fn mapped(track: &Track) -> bool {
    track.attr_map.as_ref().is_some_and(|m| m.plan().is_ok())
}

/// Everything a track plays. A MIDI clip that is the very same as at the
/// last sync reuses its events; the track's events are those of its clips in
/// order, sorted again (stably, so the result is what sorting all the notes at
/// once gives, and nearly free when the clips follow each other in time).
pub(super) fn build_clips(
    track: &Track,
    tempo: &paw_engine::TempoMap,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
) -> ClipSet {
    let cached = map.parts.remove(&track.id).unwrap_or_default();
    let mut kept = Parts {
        clips: HashMap::with_capacity(track.clips.len()),
        flat: mapped(track),
        ..Parts::default()
    };
    if kept.flat {
        // In the order a clip's events are compiled in, which the sort keeps
        // on the same beat.
        let mut set = ClipSet::default();
        for clip in track.clips.iter() {
            let (parts, sent) = parts_of(clip, 0, cached.clips.get(&clip.id), tempo, ctx);
            for part in parts {
                set.midi.extend_from_slice(&part.midi);
                set.audio.extend(part.audio);
            }
            kept.clips.insert(clip.id, sent);
        }
        set.finish();
        downgrade(track, &mut set, tempo);
        map.parts.insert(track.id, kept);
        return set;
    }
    let mut parts = Vec::with_capacity(track.clips.len());
    for (i, clip) in track.clips.iter().enumerate() {
        let order = (i as u64 + 1) * ORDER_GAP;
        let (mut more, sent) = parts_of(clip, order, cached.clips.get(&clip.id), tempo, ctx);
        parts.append(&mut more);
        kept.clips.insert(clip.id, sent);
    }
    kept.len = parts.len();
    kept.room = 2 * parts.len() + 64;
    let set = ClipSet::default().with_parts(parts, kept.room);
    map.parts.insert(track.id, kept);
    set
}

/// The parts of the clips an edit changed, to take out of the engine and
/// put in again, from the clips of `track` that differ from those of
/// `prev` (the same track as the engine has it). `None` when the track's
/// clips are to be sent whole: they are sent as one list, or the edit
/// changed many, or the parts would not fit in the room the engine has.
pub(super) fn edit_parts(
    prev: &Track,
    track: &Track,
    tempo: &paw_engine::TempoMap,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
) -> Option<PartEdit> {
    let kept = map.parts.get_mut(&track.id)?;
    if kept.flat || mapped(track) {
        return None;
    }
    let (old, new) = track.clips.changed(&prev.clips);
    if old.len() + new.len() > MAX_EDIT {
        return None;
    }
    // The orders on each side of the stretch, which the clips put in again
    // take orders between, each as many as it has parts.
    let low = match new.start {
        0 => 0,
        at => {
            let c = track.clips.get(at - 1)?;
            kept.clips.get(&c.id)?.order + orders_taken(c)
        }
    };
    let count = new.len() as u64;
    let step = match track.clips.get(new.end) {
        Some(c) => (kept.clips.get(&c.id)?.order.checked_sub(low)?) / (count + 1),
        None => ORDER_GAP,
    };
    if track.clips.range(new.clone()).any(|c| orders_taken(c) >= step) {
        return None;
    }
    let mut edit = PartEdit::default();
    let mut gone = HashMap::new();
    for clip in prev.clips.range(old) {
        if let Some(was) = kept.clips.remove(&clip.id) {
            edit.remove.extend(was.parts.iter().map(|&order| (clip.id, order)));
            gone.insert(clip.id, was);
        }
    }
    let mut sent = Vec::with_capacity(new.len());
    for (k, clip) in track.clips.range(new).enumerate() {
        let order = low + (k as u64 + 1) * step;
        let (mut parts, now) = parts_of(clip, order, gone.get(&clip.id), tempo, ctx);
        edit.add.append(&mut parts);
        sent.push(now);
    }
    let len = kept.len - edit.remove.len() + edit.add.len();
    if len > kept.room {
        // Sent whole, with more room.
        map.parts.remove(&track.id);
        return None;
    }
    kept.len = len;
    for now in sent {
        kept.clips.insert(now.clip.id, now);
    }
    edit.removed = Vec::with_capacity(edit.remove.len());
    Some(edit)
}

/// What the track's attribute map sends, put among its events.
fn downgrade(track: &Track, set: &mut ClipSet, tempo: &paw_engine::TempoMap) {
    // A map is checked when it is set; one that no longer reads (from a
    // file edited by hand) plays as if there were none.
    if let Some(plan) = track.attr_map.as_ref().and_then(|m| m.plan().ok()) {
        crate::attr_map::downgrade(set, &plan, tempo);
    }
}

/// The regions an audio clip plays, once its sound is at hand.
fn clip_audio(
    clip: &Clip,
    (file, offset, gain): (&Path, f64, f64),
    tempo: &paw_engine::TempoMap,
    ctx: &mut SyncCtx,
    out: &mut Vec<AudioRegion>,
) {
    let rate = ctx.sample_rate as u32;
    // A stretched, warped or shifted clip plays a version made for it, in
    // which its file's moments are where its warp puts them (`warp.rs`); it
    // is silent until that is started, and then plays it as far as it is made.
    let warp = crate::warp::of(clip, tempo);
    let data = match crate::stretched::Key::of(clip, rate, tempo) {
        Some(key) => ctx.audio.stretched(&key, ctx.warnings),
        None => ctx.audio.get(file, rate, ctx.warnings),
    };
    if let Some(data) = data {
        let offset = warp.map_or(offset, |w| w.forward(offset));
        audio_regions(clip, data, offset, db_to_gain(gain), tempo, out);
    }
}

/// What a frozen track plays: its file from the start of the song, as it
/// was rendered, at unity gain and without fades.
pub(super) fn frozen_clips(file: &Path, tempo: &paw_engine::TempoMap, ctx: &mut SyncCtx) -> ClipSet {
    let mut set = ClipSet::default();
    if let Some(data) = ctx.audio.get(file, ctx.sample_rate as u32, ctx.warnings) {
        let end = tempo.beat(tempo.seconds(0.0) + data.whole_seconds());
        set.audio.push(AudioRegion {
            start: 0.0,
            end,
            declick_in: false,
            declick_out: false,
            data,
            offset: 0.0,
            gain: 1.0,
            fade_in: 0.0,
            fade_out: 0.0,
            hold: Default::default(),
        });
    }
    set.finish();
    set
}

/// The engine's rows for a track's clips off the timeline: a clip keeps
/// the row it had, a clip gone frees its row, and a new clip takes the
/// first free row.
pub(super) fn cue_rows(mut rows: Vec<Option<Id>>, track: &Track) -> Vec<Option<Id>> {
    for row in rows.iter_mut() {
        if row.is_some_and(|id| !track.cues.iter().any(|c| c.id == id)) {
            *row = None;
        }
    }
    for clip in &track.cues {
        if rows.contains(&Some(clip.id)) {
            continue;
        }
        match rows.iter().position(Option::is_none) {
            Some(free) => rows[free] = Some(clip.id),
            None => rows.push(Some(clip.id)),
        }
    }
    while rows.last() == Some(&None) {
        rows.pop();
    }
    rows
}

/// What a track's clips off the timeline play, each laid out from its own
/// start, in its row (`rows`).
pub(super) fn build_cues(
    track: &Track,
    rows: &[Option<Id>],
    tempo: &paw_engine::TempoMap,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
) -> Slots {
    // A clip that did not change is not compiled again.
    let cached = map.cue_events.remove(&track.id).unwrap_or_default();
    let mut kept = HashMap::with_capacity(cached.len() + 1);
    let mut out: Vec<Option<SlotClip>> = Vec::new();
    out.resize_with(rows.len(), || None);
    for (row, id) in rows.iter().enumerate() {
        let Some(clip) = id.and_then(|id| track.cues.iter().find(|c| c.id == id)) else {
            continue;
        };
        if clip.muted {
            continue;
        }
        let mut clips = ClipSet::default();
        match &clip.content {
            ClipContent::Midi { notes, controls } => {
                let events = match cached.get(&clip.id) {
                    Some(was) if Arc::ptr_eq(&was.clip, clip) => was.events.clone(),
                    _ => compile_clip(clip, notes, controls),
                };
                clips.midi = events.to_vec();
                kept.insert(clip.id, CueEvents { clip: clip.clone(), events });
                downgrade(track, &mut clips, tempo);
            }
            ClipContent::Audio { file, offset, gain, .. } => {
                clip_audio(clip, (file, *offset, *gain), tempo, ctx, &mut clips.audio)
            }
            ClipContent::Custom(_) => {}
        }
        out[row] = Some(SlotClip {
            clips,
            length: clip.length,
        });
    }
    if !kept.is_empty() {
        map.cue_events.insert(track.id, kept);
    }
    Slots { rows: out }
}
