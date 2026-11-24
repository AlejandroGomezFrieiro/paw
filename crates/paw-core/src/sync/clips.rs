//! Clips as the engine plays them: MIDI compiled to events, audio as
//! regions, sent whole or as the pieces an edit changed; and the clips off
//! the timeline, in their rows.

use std::collections::HashMap;
use std::hash::{Hash, Hasher};

use rustc_hash::{FxHashMap, FxHasher};
use std::path::Path;
use std::sync::Arc;

use paw_engine::launch::{SlotClip, Slots};
use paw_engine::{AudioData, AudioRegion, ClipSet, MidiEv, Piece, PieceEdit, db_to_gain};

use super::SyncCtx;
use super::mapper::{CueEvents, Mapper};
use super::stacks::Results;
use crate::model::{Clip, ClipContent, Control, Id, Note, Notes, Part, repeats};

/// What a piece of a MIDI clip's events is compiled from, and all that
/// they depend on: runs of the notes that it plays, its controllers, its
/// length and its loop. A clip with a modifier stack plays the result of
/// its stack (`stacks.rs`): copies with the same notes and stack share the
/// result that the last `ChainKey` names, so they share its runs and its
/// events. Not where the clip starts: events are compiled from the clip's
/// start, and its pieces play them from there (see [`Piece::with_offset`]),
/// so that copies of a clip at many places share one list.
#[derive(Clone, Copy)]
pub(super) struct Source<'a> {
    runs: &'a [Run],
    controls: &'a [Control],
    length: f64,
    repeat: Option<(f64, f64)>,
}

type Run = Arc<Vec<Note>>;

impl<'a> Source<'a> {
    /// All of a MIDI clip: the notes and controllers that it plays.
    pub(super) fn whole(clip: &Clip, notes: &'a Notes, controls: &'a [Control]) -> Self {
        Self {
            runs: notes.runs(),
            controls,
            length: clip.length,
            repeat: clip.repeat(),
        }
    }

    /// What tells it apart from other sources: runs by where they are
    /// kept (two copies of a clip share them), the rest by value.
    fn key(&self) -> u64 {
        let mut hash = FxHasher::default();
        for run in self.runs {
            Arc::as_ptr(run).hash(&mut hash);
        }
        self.length.to_bits().hash(&mut hash);
        self.repeat.map(|(a, b)| (a.to_bits(), b.to_bits())).hash(&mut hash);
        self.controls.len().hash(&mut hash);
        for c in self.controls {
            (c.start.to_bits(), c.value.to_bits(), c.key).hash(&mut hash);
        }
        hash.finish()
    }

    fn notes(&self) -> impl Iterator<Item = &'a Note> + use<'a> {
        self.runs.iter().flat_map(|r| r.iter())
    }

    /// Its notes and controller moves as engine events, sorted, from
    /// `origin` (0 for a piece, which plays them from its clip's start). A
    /// looped clip plays what lies in its repeated stretch over and over,
    /// each note cut at the end of its repeat.
    pub(super) fn compile(&self, origin: f64) -> Arc<[MidiEv]> {
        #[cfg(test)]
        COMPILES.with(|c| c.set(c.get() + 1));
        let mut set = ClipSet::default();
        let length = self.length;
        let Some((from, beats)) = self.repeat else {
            for control in self.controls.iter().filter(|c| c.start >= 0.0 && c.start < length) {
                set.push_event(origin + control.start, control.event(0));
            }
            for note in self.notes().filter(|n| n.start >= 0.0 && n.start < length) {
                let end = (note.start + note.length).min(length);
                let vel = note.velocity.unit();
                let (start, end) = (origin + note.start, origin + end);
                set.push_note_attr(start, end, note.pitch, vel, attr_of(note));
            }
            set.finish();
            return set.midi.into();
        };
        let inside = |at: f64| at >= from && at < from + beats;
        for (base, end) in repeats(from, beats, length) {
            let place = |at: f64| base + (at - from);
            for control in self.controls.iter().filter(|c| inside(c.start)) {
                let at = place(control.start);
                if at >= 0.0 && at < length {
                    set.push_event(origin + at, control.event(0));
                }
            }
            for note in self.notes().filter(|n| inside(n.start)) {
                let at = place(note.start);
                if at >= 0.0 && at < length {
                    let stop = (at + note.length).min(end);
                    let vel = note.velocity.unit();
                    set.push_note_attr(origin + at, origin + stop, note.pitch, vel, attr_of(note));
                }
            }
        }
        set.finish();
        set.midi.into()
    }
}

#[cfg(test)]
thread_local! {
    /// How many times events were compiled on this thread: what the tests
    /// count.
    pub(super) static COMPILES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

/// Events compiled, by what they were compiled from: every clip of the
/// same notes, controllers, length and loop shares one list, wherever it
/// starts and on whichever part. Shared by all the parts of a [`Mapper`].
#[derive(Default)]
pub(super) struct Compiled {
    entries: FxHashMap<u64, Entry>,
    /// The events of a piece with nothing in it, which every such piece shares.
    empty: Arc<[MidiEv]>,
    /// How many entries there were after the last sweep.
    swept: usize,
    /// What the clips with a modifier stack play, which their events are
    /// compiled from.
    pub(super) stacks: Results,
}

/// One list of events and what it was compiled from. It holds the runs, so
/// that no other run can be kept where one of them was while it is here.
struct Entry {
    runs: Vec<Run>,
    controls: Vec<Control>,
    length: f64,
    repeat: Option<(f64, f64)>,
    events: Arc<[MidiEv]>,
}

impl Entry {
    fn is(&self, s: &Source) -> bool {
        self.length.to_bits() == s.length.to_bits()
            && self.repeat.map(|(a, b)| (a.to_bits(), b.to_bits()))
                == s.repeat.map(|(a, b)| (a.to_bits(), b.to_bits()))
            && self.runs.len() == s.runs.len()
            && self.runs.iter().zip(s.runs).all(|(a, b)| Arc::ptr_eq(a, b))
            && self.controls == s.controls
    }
}

impl Compiled {
    /// The events of `source`, compiled only if no clip had them yet.
    fn events(&mut self, source: Source) -> Arc<[MidiEv]> {
        if source.runs.is_empty() && source.controls.is_empty() {
            return self.empty.clone();
        }
        let key = source.key();
        if let Some(entry) = self.entries.get(&key).filter(|e| e.is(&source)) {
            return entry.events.clone();
        }
        let events = source.compile(0.0);
        self.entries.insert(
            key,
            Entry {
                runs: source.runs.to_vec(),
                controls: source.controls.to_vec(),
                length: source.length,
                repeat: source.repeat,
                events: events.clone(),
            },
        );
        events
    }

    /// Forget the lists that no clip plays any more, once there are as
    /// many again as after the last sweep: a clip sent holds its lists.
    pub(super) fn sweep(&mut self) {
        if self.entries.len() > 2 * self.swept + 64 {
            self.entries.retain(|_, e| Arc::strong_count(&e.events) > 1);
            self.swept = self.entries.len();
        }
        self.stacks.sweep();
    }
}

/// A note's attribute as the engine has it.
fn attr_of(note: &Note) -> paw_types::Attr {
    note.attr.map_or(paw_types::Attr::NONE, Into::into)
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

/// The regions an audio clip plays: the piece of `data` from `offset`
/// seconds, or, looped, its repeated stretch again and again. A fade in
/// belongs to the first repeat and a fade out to the last, each as long
/// as that repeat at most.
fn audio_regions(
    clip: &Clip,
    data: Arc<AudioData>,
    offset: f64,
    gain: f32,
    tempo: &paw_types::TempoMap,
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
            direction: Default::default(),
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
            direction: Default::default(),
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

/// What the engine has of a part's clips, sent as pieces: one for each
/// clip, or for a long MIDI clip one for its controllers and one for each
/// few runs of its notes (see [`Notes`]), so that a note edited compiles
/// again only the notes beside it.
#[derive(Default)]
pub(super) struct Pieces {
    /// Each clip by id, as compiled and sent.
    pub clips: FxHashMap<Id, SentClip>,
    /// How many pieces the engine has, and room for.
    len: usize,
    room: usize,
    /// The clips were sent as one list, through the part's attribute map:
    /// only their events are kept, to compile only what changed.
    flat: bool,
}

/// One clip as the engine was sent it.
pub(super) struct SentClip {
    clip: Arc<Clip>,
    /// Its order (see [`paw_engine::Piece::order`]); its pieces have this
    /// order and those after it, one each.
    order: u64,
    /// Its events in pieces (see [`pieces_of`]), each counted from the
    /// clip's start; none for an audio clip.
    pub pieces: Vec<Arc<[MidiEv]>>,
    /// It has a piece of sound, of its order.
    sounds: bool,
}

impl SentClip {
    /// The orders of the pieces the engine has of it: those not empty.
    fn orders(&self) -> impl Iterator<Item = u64> + '_ {
        let sound = self.sounds.then_some(self.order);
        let pieces = self.pieces.iter().enumerate().filter(|(_, e)| !e.is_empty());
        sound.into_iter().chain(pieces.map(|(k, _)| self.order + k as u64))
    }
}

/// The space between the orders of two clips side by side when a part's
/// pieces are sent whole: clips put in between later take orders between.
const ORDER_GAP: u64 = 1 << 32;
/// An edit of more clips than this sends the part's clips whole.
const MAX_EDIT: usize = 512;

/// Notes in a piece of a clip's events: runs side by side go in one piece
/// until it has this many.
const PIECE: usize = 256;

/// The pieces of a clip's events, counted from its start: its controllers
/// and its notes in pieces of a few runs (in that order, which is the
/// order a clip's events are compiled in); a short or looped clip in one
/// piece. A piece that a clip sent already has (the clip `before`, or a
/// copy anywhere) is not compiled again.
fn pieces_of(
    clip: &Clip,
    before: Option<&SentClip>,
    compiled: &mut Compiled,
    ctx: &mut SyncCtx,
) -> Vec<Arc<[MidiEv]>> {
    let Some(ClipContent::Midi { notes, controls }) = clip.playable() else {
        return Vec::new();
    };
    // The very same clip: nothing to look up.
    if let Some(b) = before.filter(|b| std::ptr::eq(&*b.clip, clip)) {
        return b.pieces.clone();
    }
    // The result of its stack has as many runs as its notes, or fewer: its
    // pieces fit in the orders that the clip takes (`orders_taken`).
    let played = compiled.stacks.played(clip, notes, controls, ctx.modifiers, ctx.warnings);
    let (notes, controls) = match &played {
        Some(result) => (&result.notes, &result.controls[..]),
        None => (notes, &controls[..]),
    };
    let whole = Source::whole(clip, notes, controls);
    if notes.len() <= PIECE || whole.repeat.is_some() {
        return vec![compiled.events(whole)];
    }
    let mut out = vec![compiled.events(Source { runs: &[], ..whole })];
    let runs = notes.runs();
    let mut at = 0;
    while at < runs.len() {
        let (mut end, mut count) = (at, 0);
        while end < runs.len() && count < PIECE {
            count += runs[end].len();
            end += 1;
        }
        out.push(compiled.events(Source {
            runs: &runs[at..end],
            controls: &[],
            ..whole
        }));
        at = end;
    }
    out
}

/// A clip's pieces from `order` on, put in `out`, compiling only what no
/// clip sent has; and the clip as sent.
fn send_pieces(
    clip: &Arc<Clip>,
    order: u64,
    before: Option<&SentClip>,
    tempo: &paw_types::TempoMap,
    compiled: &mut Compiled,
    ctx: &mut SyncCtx,
    out: &mut Vec<Piece>,
) -> SentClip {
    let mut audio = Vec::new();
    let mut pieces = Vec::new();
    if !clip.muted {
        // A custom clip plays its sound, if it has one, as its own.
        match clip.playable() {
            Some(ClipContent::Midi { .. }) => pieces = pieces_of(clip, before, compiled, ctx),
            Some(ClipContent::Audio { file, offset, gain, .. }) => {
                clip_audio(clip, (file, *offset, *gain), tempo, ctx, &mut audio)
            }
            Some(ClipContent::Custom(_) | ClipContent::Nest { .. }) | None => {}
        }
    }
    let sounds = !audio.is_empty();
    if sounds {
        out.push(Piece::new(clip.id, order, Arc::from([]), audio));
    }
    let sent = SentClip {
        clip: clip.clone(),
        order,
        pieces,
        sounds,
    };
    for (k, events) in sent.pieces.iter().enumerate().filter(|(_, e)| !e.is_empty()) {
        let piece = Piece::new(clip.id, order + k as u64, events.clone(), Vec::new());
        out.push(piece.with_offset(clip.start));
    }
    sent
}

/// How many orders a clip's pieces take.
fn orders_taken(clip: &Clip) -> u64 {
    match clip.playable() {
        Some(ClipContent::Midi { notes, .. }) => notes.runs().len() as u64 + 1,
        _ => 1,
    }
}

/// Whether a part's events go through its attribute map: then its clips
/// are sent as one list, which the map changes as a whole.
fn mapped(part: &Part) -> bool {
    part.attr_map.as_ref().is_some_and(|m| m.plan().is_ok())
}

/// Everything a part plays. A MIDI clip that is the very same as at the
/// last sync reuses its events; the part's events are those of its clips in
/// order, sorted again (stably, so the result is what sorting all the notes at
/// once gives, and nearly free when the clips follow each other in time).
pub(super) fn build_clips(
    part: &Part,
    tempo: &paw_types::TempoMap,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
) -> ClipSet {
    let cached = map.pieces.remove(&part.id).unwrap_or_default();
    let mut kept = Pieces {
        clips: FxHashMap::with_capacity_and_hasher(part.clips.len(), Default::default()),
        flat: mapped(part),
        ..Pieces::default()
    };
    if kept.flat {
        // In the order a clip's events are compiled in, which the sort keeps
        // on the same beat.
        let mut set = ClipSet::default();
        let mut pieces = Vec::new();
        for clip in part.clips.iter() {
            let before = cached.clips.get(&clip.id);
            let sent = send_pieces(clip, 0, before, tempo, &mut map.compiled, ctx, &mut pieces);
            for piece in pieces.drain(..) {
                set.midi.extend(piece.events());
                set.audio.extend(piece.into_audio());
            }
            kept.clips.insert(clip.id, sent);
        }
        set.finish();
        downgrade(part, &mut set, tempo);
        map.pieces.insert(part.id, kept);
        drop(cached);
        map.compiled.sweep();
        return set;
    }
    let mut pieces = Vec::with_capacity(part.clips.len());
    for (i, clip) in part.clips.iter().enumerate() {
        let order = (i as u64 + 1) * ORDER_GAP;
        let before = cached.clips.get(&clip.id);
        let sent = send_pieces(clip, order, before, tempo, &mut map.compiled, ctx, &mut pieces);
        kept.clips.insert(clip.id, sent);
    }
    kept.len = pieces.len();
    kept.room = 2 * pieces.len() + 64;
    let set = ClipSet::default().with_pieces(pieces, kept.room);
    map.pieces.insert(part.id, kept);
    drop(cached);
    map.compiled.sweep();
    set
}

/// The pieces of the clips an edit changed, to take out of the engine and
/// put in again, from the clips of `part` that differ from those of
/// `prev` (the same part as the engine has it). `None` when the part's
/// clips are to be sent whole: they are sent as one list, or the edit
/// changed many, or the pieces would not fit in the room the engine has.
pub(super) fn edit_pieces(
    prev: &Part,
    part: &Part,
    tempo: &paw_types::TempoMap,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
) -> Option<PieceEdit> {
    let kept = map.pieces.get_mut(&part.id)?;
    if kept.flat || mapped(part) {
        return None;
    }
    let (old, new) = part.clips.changed(&prev.clips);
    if old.len() + new.len() > MAX_EDIT {
        return None;
    }
    // The orders on each side of the stretch, which the clips put in again
    // take orders between, each as many as it has pieces.
    let low = match new.start {
        0 => 0,
        at => {
            let c = part.clips.get(at - 1)?;
            kept.clips.get(&c.id)?.order + orders_taken(c)
        }
    };
    let count = new.len() as u64;
    let step = match part.clips.get(new.end) {
        Some(c) => (kept.clips.get(&c.id)?.order.checked_sub(low)?) / (count + 1),
        None => ORDER_GAP,
    };
    if part.clips.range(new.clone()).any(|c| orders_taken(c) >= step) {
        return None;
    }
    let mut edit = PieceEdit {
        remove: Vec::with_capacity(old.len()),
        add: Vec::with_capacity(new.len()),
        ..PieceEdit::default()
    };
    let mut gone = FxHashMap::with_capacity_and_hasher(old.len(), Default::default());
    for clip in prev.clips.range(old) {
        if let Some(was) = kept.clips.remove(&clip.id) {
            edit.remove.extend(was.orders().map(|order| (clip.id, order)));
            gone.insert(clip.id, was);
        }
    }
    let mut sent = Vec::with_capacity(new.len());
    for (k, clip) in part.clips.range(new).enumerate() {
        let order = low + (k as u64 + 1) * step;
        let before = gone.get(&clip.id);
        sent.push(send_pieces(clip, order, before, tempo, &mut map.compiled, ctx, &mut edit.add));
    }
    let len = kept.len - edit.remove.len() + edit.add.len();
    if len > kept.room {
        // Sent whole, with more room.
        map.pieces.remove(&part.id);
        return None;
    }
    kept.len = len;
    for now in sent {
        kept.clips.insert(now.clip.id, now);
    }
    edit.removed = Vec::with_capacity(edit.remove.len());
    drop(gone);
    map.compiled.sweep();
    Some(edit)
}

/// What the part's attribute map sends, put among its events.
fn downgrade(part: &Part, set: &mut ClipSet, tempo: &paw_types::TempoMap) {
    // A map is checked when it is set; one that no longer reads (from a
    // file edited by hand) plays as if there were none.
    if let Some(plan) = part.attr_map.as_ref().and_then(|m| m.plan().ok()) {
        crate::attr_map::downgrade(set, &plan, tempo);
    }
}

/// The regions an audio clip plays, once its sound is at hand.
fn clip_audio(
    clip: &Clip,
    (file, offset, gain): (&Path, f64, f64),
    tempo: &paw_types::TempoMap,
    ctx: &mut SyncCtx,
    out: &mut Vec<AudioRegion>,
) {
    let rate = ctx.sample_rate as u32;
    // A stretched, warped or shifted clip plays a version made for it, in
    // which its file's moments are where its warp puts them (`warp.rs`):
    // a rough preview until its bake starts (or its file has a hash), then the version as far as it
    // is made. A render waits for the bakes, and never plays a preview.
    let warp = crate::warp::of(clip, tempo);
    let offset = warp.as_ref().map_or(offset, |w| w.forward(offset));
    let gain = db_to_gain(gain);
    let Some(key) = crate::stretched::Key::of(clip, rate, tempo, ctx.sources) else {
        if let Some(data) = ctx.audio.get(file, rate, ctx.warnings) {
            audio_regions(clip, data, offset, gain, tempo, out);
        }
        return;
    };
    if let Some(data) = ctx.audio.stretched(&key, ctx.now, ctx.warnings) {
        audio_regions(clip, data, offset, gain, tempo, out);
    } else if !ctx.offline
        && ctx.audio.renders.status(&key) != crate::bake::scheduler::Status::Failed
        && let Some(source) = ctx.audio.get(file, rate, ctx.warnings)
    {
        let warp = warp.unwrap_or_else(|| crate::warp::Warp::even(1.0));
        crate::stretched::preview(clip, source, (offset, gain), &warp, tempo, out);
    }
}

/// What a frozen part plays: its file from the start of the song, as it
/// was rendered, at unity gain and without fades.
pub(super) fn frozen_clips(file: &Path, tempo: &paw_types::TempoMap, ctx: &mut SyncCtx) -> ClipSet {
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
            direction: Default::default(),
        });
    }
    set.finish();
    set
}

/// The engine's rows for a part's clips off the timeline: a clip keeps
/// the row it had, a clip gone frees its row, and a new clip takes the
/// first free row.
pub(super) fn cue_rows(mut rows: Vec<Option<Id>>, part: &Part) -> Vec<Option<Id>> {
    for row in rows.iter_mut() {
        if row.is_some_and(|id| !part.cues.iter().any(|c| c.id == id)) {
            *row = None;
        }
    }
    for clip in &part.cues {
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

/// What a part's clips off the timeline play, each laid out from its own
/// start, in its row (`rows`).
pub(super) fn build_cues(
    part: &Part,
    rows: &[Option<Id>],
    tempo: &paw_types::TempoMap,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
) -> Slots {
    // A clip that did not change is not compiled again.
    let cached = map.cue_events.remove(&part.id).unwrap_or_default();
    let mut kept = HashMap::with_capacity(cached.len() + 1);
    let mut out: Vec<Option<SlotClip>> = Vec::new();
    out.resize_with(rows.len(), || None);
    for (row, id) in rows.iter().enumerate() {
        let Some(clip) = id.and_then(|id| part.cues.iter().find(|c| c.id == id)) else {
            continue;
        };
        if clip.muted {
            continue;
        }
        let mut clips = ClipSet::default();
        match clip.playable() {
            Some(ClipContent::Midi { notes, controls }) => {
                let events = match cached.get(&clip.id) {
                    Some(was) if Arc::ptr_eq(&was.clip, clip) => was.events.clone(),
                    _ => {
                        let played = map.compiled.stacks.played(clip, notes, controls, ctx.modifiers, ctx.warnings);
                        match &played {
                            Some(result) => Source::whole(clip, &result.notes, &result.controls),
                            None => Source::whole(clip, notes, controls),
                        }
                        .compile(clip.start)
                    }
                };
                clips.midi = events.to_vec();
                kept.insert(clip.id, CueEvents { clip: clip.clone(), events });
                downgrade(part, &mut clips, tempo);
            }
            Some(ClipContent::Audio { file, offset, gain, .. }) => {
                clip_audio(clip, (file, *offset, *gain), tempo, ctx, &mut clips.audio)
            }
            Some(ClipContent::Custom(_) | ClipContent::Nest { .. }) | None => {}
        }
        out[row] = Some(SlotClip {
            clips,
            length: clip.length,
        });
    }
    if !kept.is_empty() {
        map.cue_events.insert(part.id, kept);
    }
    Slots { rows: out }
}
