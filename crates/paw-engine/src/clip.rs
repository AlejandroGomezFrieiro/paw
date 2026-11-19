//! What a track plays back: note events and audio regions, laid out in beats.

use std::fmt::Display;
use std::fs::File;
use std::io::ErrorKind;
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::{Context, Result, bail};
use symphonia::core::codecs::audio::AudioDecoderOptions;
use symphonia::core::codecs::audio::well_known::{CODEC_ID_MP1, CODEC_ID_MP2, CODEC_ID_MP3};
use symphonia::core::errors::Error;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, TrackType};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;

use crate::event::{Attr, EventKind};
use crate::samples::{DiskStore, Samples, Sink, store_name};

#[derive(Clone, Copy, Debug)]
pub struct MidiEv {
    /// Project position in beats.
    pub beat: f64,
    pub kind: EventKind,
}

/// Decoded audio, a run of samples per channel, always stereo: in memory,
/// or read from the disk as it is played (see [`crate::samples`]).
pub struct AudioData {
    pub sample_rate: u32,
    pub channels: [Samples; 2],
}

impl AudioData {
    pub fn frames(&self) -> usize {
        self.channels[0].len()
    }

    pub fn seconds(&self) -> f64 {
        self.frames() as f64 / self.sample_rate as f64
    }

    /// Whether all of the sound is there: false while it is still being
    /// made, when [`frames`](Self::frames) is how much of it is.
    pub fn complete(&self) -> bool {
        self.channels[0].complete()
    }

    /// How long the sound is once it is all there, in seconds.
    pub fn whole_seconds(&self) -> f64 {
        self.channels[0].whole_len() as f64 / self.sample_rate as f64
    }

    /// Decode a whole audio file: WAV, AIFF, FLAC, MP3 or Ogg Vorbis. Mono is
    /// copied to both channels; channels past the second are ignored.
    pub fn load(path: &Path) -> Result<Arc<Self>> {
        Self::load_with(path, None)
    }

    /// As [`load`](Self::load); a file whose decoded sound is larger than
    /// `store`'s limit is kept in the store and read from the disk as it is
    /// played, and one that was kept there before is not decoded again.
    pub fn load_with(path: &Path, store: Option<&DiskStore>) -> Result<Arc<Self>> {
        let kept = store.and_then(|store| Some((store, store_name(path, "src")?)));
        if let Some((store, name)) = &kept
            && let Some(data) = store.open(name)
        {
            return Ok(Arc::new(data));
        }
        let file = File::open(path).with_context(|| format!("opening {}", path.display()))?;
        decode(path, file, Sink::new(kept)).map(Arc::new)
    }

    /// Whether the samples are read from the disk as they are played.
    pub fn on_disk(&self) -> bool {
        self.channels[0].on_disk()
    }

    /// Ask for `from..to` seconds to be brought in from the disk now.
    pub fn advise(&self, from: f64, to: f64) {
        let rate = self.sample_rate as f64;
        let (from, to) = ((from.max(0.0) * rate) as usize, (to.max(0.0) * rate) as usize);
        for channel in &self.channels {
            channel.advise(from, to);
        }
    }
}

const READABLE: &str = "WAV, AIFF, FLAC, MP3 or Ogg Vorbis";

fn decode(path: &Path, file: File, mut sink: Sink) -> Result<AudioData> {
    let name = path.display();
    let stream = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let probed = symphonia::default::get_probe().probe(
        &hint,
        stream,
        FormatOptions::default(),
        MetadataOptions::default(),
    );
    let mut format = match probed {
        Ok(format) => format,
        Err(Error::IoError(err)) if err.kind() == ErrorKind::UnexpectedEof => {
            bail!("{name} is truncated: it ends before its own headers say it should")
        }
        Err(Error::IoError(err)) => return Err(err).with_context(|| format!("reading {name}")),
        Err(Error::Unsupported(_)) => {
            bail!("{name} is not an audio file in a format that can be read ({READABLE})")
        }
        Err(err) => bail!("{name} cannot be read: {err}"),
    };
    let Some(track) = format.default_track(TrackType::Audio) else {
        bail!("{name} holds no audio");
    };
    let Some(params) = track.codec_params.as_ref().and_then(|p| p.audio()) else {
        bail!("{name} holds no audio");
    };
    // An MPEG audio length without a LAME header is guessed from the bitrate,
    // too roughly to show that the file is cut short.
    let mpeg = [CODEC_ID_MP1, CODEC_ID_MP2, CODEC_ID_MP3].contains(&params.codec);
    let expected = track.num_frames.filter(|_| !mpeg || track.delay.is_some());
    let track_id = track.id;
    let mut decoder = match symphonia::default::get_codecs()
        .make_audio_decoder(params, &AudioDecoderOptions::default())
    {
        Ok(decoder) => decoder,
        Err(Error::Unsupported(_)) => {
            bail!("{name} uses an audio codec that is not supported: convert it to {READABLE}")
        }
        Err(err) => bail!("{name} cannot be decoded: {err}"),
    };
    let mut sample_rate = params.sample_rate.unwrap_or(0);
    if let Some(frames) = expected {
        sink.reserve(frames as usize);
    }
    let mut planes: Vec<Vec<f32>> = Vec::new();
    let mut damaged = None;
    loop {
        let packet = match format.next_packet() {
            Ok(Some(packet)) => packet,
            Ok(None) => break,
            Err(Error::IoError(err)) if err.kind() == ErrorKind::UnexpectedEof => {
                bail!("{}", truncated(&name, sink.frames(), expected, sample_rate))
            }
            Err(Error::ResetRequired) => {
                bail!("{name} changes its audio format partway through, which is not supported")
            }
            Err(err) => bail!("{name} is damaged: {err}"),
        };
        if packet.track_id != track_id {
            continue;
        }
        let buffer = match decoder.decode(&packet) {
            Ok(buffer) => buffer,
            // One bad packet is a click at worst; keep going and only give up
            // if nothing at all decodes.
            Err(Error::DecodeError(err)) => {
                damaged.get_or_insert(err);
                continue;
            }
            Err(err) => bail!("{name} cannot be decoded: {err}"),
        };
        if buffer.frames() == 0 || buffer.num_planes() == 0 {
            continue;
        }
        sample_rate = buffer.spec().rate();
        buffer.copy_to_vecs_planar(&mut planes);
        sink.push(&planes[0], planes.get(1).map(Vec::as_slice))
            .with_context(|| format!("keeping the sound of {name}"))?;
    }
    if sink.frames() == 0 {
        match damaged {
            Some(err) => bail!("{name} is damaged and none of its audio decodes: {err}"),
            None => bail!("{name} holds no audio"),
        }
    }
    // A little slack for decoders that trim a few frames differently.
    if expected.is_some_and(|n| (sink.frames() as f64) < n as f64 * 0.98) {
        bail!("{}", truncated(&name, sink.frames(), expected, sample_rate));
    }
    if sample_rate == 0 {
        bail!("{name} does not say what its sample rate is");
    }
    sink.finish(sample_rate)
        .with_context(|| format!("keeping the sound of {name}"))
}

fn truncated(name: &dyn Display, frames: usize, expected: Option<u64>, rate: u32) -> String {
    let seconds = |n: f64| n / rate.max(1) as f64;
    let got = seconds(frames as f64);
    match expected {
        Some(n) => format!(
            "{name} is truncated: it holds {got:.2} s of audio but says it has {:.2} s",
            seconds(n as f64)
        ),
        None => format!("{name} is truncated: the audio stops after {got:.2} s"),
    }
}

pub struct AudioRegion {
    /// Project position in beats where the region starts and ends.
    pub start: f64,
    pub end: f64,
    pub data: Arc<AudioData>,
    /// Seconds into the source where playback starts.
    pub offset: f64,
    pub gain: f32,
    /// Beats over which the region comes in and goes out.
    pub fade_in: f64,
    pub fade_out: f64,
    /// The region starts, or ends, in the middle of its source, where a
    /// very short fade keeps the cut from clicking.
    pub declick_in: bool,
    pub declick_out: bool,
    /// Where the region stands with sound that is still being made.
    pub hold: Hold,
}

/// How a region plays sound that is still being made (a stretch played
/// while it is made): up to where the making has got, fading out just
/// before it, silent past it, and fading in again where it picks up once
/// more is there. Only the audio thread that plays the region touches it.
pub struct Hold(AtomicU64);

/// While the region has run out of sound.
const STARVED: f64 = f64::INFINITY;
/// While it plays as usual.
const PLAYING: f64 = f64::NEG_INFINITY;

impl Default for Hold {
    fn default() -> Self {
        Self(AtomicU64::new(PLAYING.to_bits()))
    }
}

impl Hold {
    fn get(&self) -> f64 {
        f64::from_bits(self.0.load(Ordering::Relaxed))
    }

    fn set(&self, at: f64) {
        self.0.store(at.to_bits(), Ordering::Relaxed);
    }

    /// Whether playing has to look at the hold: the sound is still being
    /// made, or the region is fading in again after it ran out.
    pub fn watched(&self, complete: bool) -> bool {
        !complete || self.get() != PLAYING
    }

    /// The region ran out of sound.
    pub fn starve(&self) {
        self.set(STARVED);
    }

    /// The gain at source frame `pos`, with `frames` frames there (all of
    /// them when `complete`); the fades are `fade` source frames long and
    /// shaped by `curve`.
    pub fn gain(
        &self,
        pos: f64,
        frames: usize,
        complete: bool,
        fade: f64,
        curve: fn(f64) -> f32,
    ) -> f32 {
        let mut from = self.get();
        if from == STARVED {
            // Picking up again here.
            from = pos;
            self.set(from);
        }
        let mut gain = 1.0;
        if pos >= from {
            if pos - from < fade {
                gain *= curve((pos - from) / fade);
            } else {
                self.set(PLAYING);
            }
        }
        let left = frames as f64 - 1.0 - pos;
        if !complete && left < fade {
            gain *= curve(left / fade);
        }
        gain
    }
}

/// Everything one track plays. Built on the main thread and handed to the
/// engine whole; the audio thread changes it only by the [`PartEdit`]s it
/// is sent, without allocating.
///
/// What it plays is in one list ([`ClipSet::midi`] and [`ClipSet::audio`]),
/// or in [`Part`]s, one for each clip, or both: the list plays first on a
/// beat, then the parts in their order. An edit of one clip then sends and
/// changes only that clip's part.
#[derive(Default)]
pub struct ClipSet {
    /// Sorted by beat, with note-offs before note-ons on the same beat.
    pub midi: Vec<MidiEv>,
    pub audio: Vec<AudioRegion>,
    /// Where what the track's instrument is told to play changes (the
    /// keyswitches and controllers its notes' attributes are turned into),
    /// by beat: what playing from a place after it sends again first.
    pub switches: Vec<Switch>,
    /// The events of each switch, `Switch::events` into this.
    pub switch_events: Vec<EventKind>,
    /// Sorted by where they start, then by their order: see [`ClipSet::with_parts`].
    parts: Vec<Part>,
    /// The longest stretch a part has been seen to span, in beats: the
    /// parts that can sound from a beat start at most this far before it.
    reach: f64,
    /// The parts that sound in the block being played, with how far into
    /// each the block's events start: as long as `parts` can grow, so that
    /// it never has to grow on the audio thread.
    sounding: Vec<(u32, u32)>,
}

/// One clip's share of what a track plays.
pub struct Part {
    /// The clip's id: what an edit names the part by.
    pub id: u64,
    /// Where its clip is among the track's clips, from 1: on the same beat,
    /// what a part with a lower order plays comes first.
    pub order: u64,
    /// Sorted as [`ClipSet::midi`] is.
    pub midi: Arc<[MidiEv]>,
    pub audio: Vec<AudioRegion>,
    /// The first and last beat it has anything on.
    from: f64,
    to: f64,
}

impl Part {
    pub fn new(id: u64, order: u64, midi: Arc<[MidiEv]>, audio: Vec<AudioRegion>) -> Self {
        let mut from = f64::INFINITY;
        let mut to = f64::NEG_INFINITY;
        if let (Some(first), Some(last)) = (midi.first(), midi.last()) {
            from = first.beat;
            to = last.beat;
        }
        for region in &audio {
            from = from.min(region.start);
            to = to.max(region.end);
        }
        Self { id, order, midi, audio, from, to }
    }

    /// Whether it plays nothing: no part is kept for it.
    pub fn is_empty(&self) -> bool {
        self.midi.is_empty() && self.audio.is_empty()
    }
}

/// Parts to take out of a [`ClipSet`] by id and order, and parts to put
/// in, applied on the audio thread by [`ClipSet::edit`]. The parts taken
/// out are kept in it, to be freed on another thread.
#[derive(Default)]
pub struct PartEdit {
    pub remove: Vec<(u64, u64)>,
    pub add: Vec<Part>,
    pub removed: Vec<Part>,
}

/// On the same beat a note ends before a channel's controllers move, they
/// move before a note starts, and a note's own controllers come after it
/// has started.
fn rank(e: &MidiEv) -> u8 {
    match e.kind {
        EventKind::NoteOff { .. } | EventKind::AllNotesOff => 0,
        EventKind::Control { .. } | EventKind::Program { .. } => 1,
        EventKind::NoteOn { .. } => 2,
        EventKind::NoteControl { .. } => 3,
    }
}

/// Where an event is in the order a track plays its events in: by beat,
/// rank, the order of its part (0 for the list) and its place there.
#[derive(Clone, Copy)]
pub(crate) struct Stamp(f64, u8, u64, usize);

impl Stamp {
    pub(crate) const FIRST: Stamp = Stamp(f64::NEG_INFINITY, 0, 0, 0);

    fn of(ev: &MidiEv, order: u64, at: usize) -> Self {
        Stamp(ev.beat, rank(ev), order, at)
    }

    /// Whether it comes after `other`.
    pub(crate) fn after(&self, other: &Stamp) -> bool {
        self.0
            .total_cmp(&other.0)
            .then(self.1.cmp(&other.1))
            .then(self.2.cmp(&other.2))
            .then(self.3.cmp(&other.3))
            .is_gt()
    }
}

/// One change of what the instrument is told to play: from `beat` on, the
/// events `switch_events[events]` are in force.
#[derive(Clone, Debug, PartialEq)]
pub struct Switch {
    pub beat: f64,
    pub events: std::ops::Range<usize>,
}

impl ClipSet {
    pub fn push_note(&mut self, start: f64, end: f64, key: u8, vel: f32) {
        self.push_note_attr(start, end, key, vel, Attr::NONE);
    }

    /// A note with a MIDI 2.0 attribute on its start.
    pub fn push_note_attr(&mut self, start: f64, end: f64, key: u8, vel: f32, attr: Attr) {
        self.midi.push(MidiEv {
            beat: start,
            kind: EventKind::NoteOn {
                key,
                vel,
                ch: 0,
                attr,
            },
        });
        self.midi.push(MidiEv {
            beat: end,
            kind: EventKind::NoteOff { key, ch: 0 },
        });
    }

    /// Add a controller move, a program change or any other event.
    pub fn push_event(&mut self, beat: f64, kind: EventKind) {
        self.midi.push(MidiEv { beat, kind });
    }

    /// Sort the events. Call once after the last push. On the same beat a
    /// note ends before a channel's controllers move, they move before a
    /// note starts, and a note's own controllers come after it has started.
    pub fn finish(&mut self) {
        self.midi
            .sort_by(|a, b| a.beat.total_cmp(&b.beat).then(rank(a).cmp(&rank(b))));
    }

    /// The parts of a track's clips, in any order, with room for `room`
    /// parts in all before an edit has to send the set whole again.
    pub fn with_parts(mut self, parts: Vec<Part>, room: usize) -> Self {
        let room = room.max(parts.len());
        self.parts = Vec::with_capacity(room);
        self.sounding = Vec::with_capacity(room + 1);
        self.reach = 0.0;
        for part in parts.into_iter().filter(|p| !p.is_empty()) {
            self.reach = self.reach.max(part.to - part.from);
            self.parts.push(part);
        }
        self.parts
            .sort_by(|a, b| a.from.total_cmp(&b.from).then(a.order.cmp(&b.order)));
        self
    }

    /// How many parts there are, and how many there is room for.
    pub fn parts(&self) -> (usize, usize) {
        (self.parts.len(), self.parts.capacity())
    }

    /// Take out and put in the parts `edit` names. Allocates nothing as long
    /// as there is room for the parts put in and for those taken out, which
    /// whoever sends the edit sees to: an edit for which there is no room
    /// is not applied, and false returned.
    pub fn edit(&mut self, edit: &mut PartEdit) -> bool {
        let adding = edit.add.iter().filter(|p| !p.is_empty()).count();
        if edit.removed.capacity() - edit.removed.len() < edit.remove.len()
            || self.parts.len() + adding > self.parts.capacity()
        {
            return false;
        }
        for &(id, order) in &edit.remove {
            if let Some(at) = self.parts.iter().position(|p| p.id == id && p.order == order) {
                edit.removed.push(self.parts.remove(at));
            }
        }
        for part in edit.add.drain(..).filter(|p| !p.is_empty()) {
            let at = self.parts.partition_point(|p| {
                p.from.total_cmp(&part.from).then(p.order.cmp(&part.order)).is_lt()
            });
            self.reach = self.reach.max(part.to - part.from);
            self.parts.insert(at, part);
        }
        true
    }

    /// Find the parts that may sound from `start` to `end`, in their order,
    /// for [`regions`](Self::regions) and [`events`](Self::events).
    pub fn find_sounding(&mut self, start: f64, end: f64) {
        self.sounding.clear();
        if self.parts.is_empty() {
            return;
        }
        let first = self.parts.partition_point(|p| p.from < start - self.reach);
        for (i, part) in self.parts.iter().enumerate().skip(first) {
            if part.from >= end {
                break;
            }
            if part.to >= start && self.sounding.len() < self.sounding.capacity() {
                let at = part.midi.partition_point(|e| e.beat < start);
                self.sounding.push((i as u32, at as u32));
            }
        }
        let parts = &self.parts;
        self.sounding.sort_unstable_by_key(|&(i, _)| parts[i as usize].order);
    }

    /// The sound of the list, then of each part found by
    /// [`find_sounding`](Self::find_sounding), in their order.
    pub fn regions(&self) -> impl Iterator<Item = &AudioRegion> {
        self.audio.iter().chain(
            self.sounding
                .iter()
                .flat_map(|&(i, _)| self.parts[i as usize].audio.iter()),
        )
    }

    /// The events from `start` to before `end` of the list and of the parts
    /// found by [`find_sounding`](Self::find_sounding) for the same stretch,
    /// in the order they play: as if all were in one list sorted by
    /// [`finish`](Self::finish), the list first and each part after it in
    /// their order.
    pub fn events(&mut self, start: f64, end: f64, mut each: impl FnMut(&MidiEv)) {
        let first = self.midi.partition_point(|e| e.beat < start);
        if self.sounding.is_empty() {
            for ev in self.midi[first..].iter().take_while(|e| e.beat < end) {
                each(ev);
            }
            return;
        }
        let mut list = first;
        loop {
            // The next event of the list and of each part, the first of them played.
            let mut best: Option<(Stamp, Option<usize>)> = self
                .midi
                .get(list)
                .filter(|e| e.beat < end)
                .map(|e| (Stamp::of(e, 0, list), None));
            for (k, &(i, at)) in self.sounding.iter().enumerate() {
                let part = &self.parts[i as usize];
                if let Some(e) = part.midi.get(at as usize).filter(|e| e.beat < end) {
                    let stamp = Stamp::of(e, part.order, at as usize);
                    if best.as_ref().is_none_or(|(b, _)| b.after(&stamp)) {
                        best = Some((stamp, Some(k)));
                    }
                }
            }
            match best {
                None => return,
                Some((_, None)) => {
                    each(&self.midi[list]);
                    list += 1;
                }
                Some((_, Some(k))) => {
                    let (i, at) = self.sounding[k];
                    each(&self.parts[i as usize].midi[at as usize]);
                    self.sounding[k].1 += 1;
                }
            }
        }
    }

    /// Every event before `before`, of the list and of every part, each
    /// with where it is in the order the track plays them: for what a
    /// chase looks at, which is the last of them for each key and controller.
    pub(crate) fn each_before(&self, before: f64, mut each: impl FnMut(&MidiEv, Stamp)) {
        for (at, ev) in self.midi.iter().enumerate().take_while(|(_, e)| e.beat < before) {
            each(ev, Stamp::of(ev, 0, at));
        }
        for part in self.parts.iter().take_while(|p| p.from < before) {
            for (at, ev) in part.midi.iter().enumerate().take_while(|(_, e)| e.beat < before) {
                each(ev, Stamp::of(ev, part.order, at));
            }
        }
    }

    /// The events of the last switch before `beat`, if any.
    pub fn switch_before(&self, beat: f64) -> &[EventKind] {
        let at = self.switches.partition_point(|s| s.beat < beat);
        match at.checked_sub(1).and_then(|i| self.switches.get(i)) {
            Some(switch) => self
                .switch_events
                .get(switch.events.clone())
                .unwrap_or_default(),
            None => &[],
        }
    }
}
