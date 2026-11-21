//! Atom buffers and the time position sent to a plugin's atom ports.

use std::ptr;

use paw_engine::ProcessCtx;

use super::*;
use super::urid::*;

/// Where the song is and how fast it goes, as a `time:Position` object for
/// a plugin's atom port. LV2 counts in beats of the signature's own unit,
/// where the engine counts in quarter notes.
pub(super) fn time_position(ctx: &ProcessCtx) -> [u8; 184] {
    let u = urids();
    let per_quarter = ctx.sig_den as f64 / 4.0;
    let bar = ctx.bar;
    let frame = ctx.seconds * ctx.sample_rate as f64;
    let mut out = [0u8; 184];
    let mut at = 0;
    let mut put = |bytes: &[u8]| {
        out[at..at + bytes.len()].copy_from_slice(bytes);
        // Every value is padded out to eight bytes.
        at += bytes.len().div_ceil(4) * 4;
    };
    // The object: its size after this header, its type, then id and class.
    for word in [176, u.object, 0, u.time_position] {
        put(&word.to_ne_bytes());
    }
    let mut property = |key: u32, type_: u32, value: &[u8]| {
        for word in [key, 0, value.len() as u32, type_] {
            put(&word.to_ne_bytes());
        }
        let mut body = [0u8; 8];
        body[..value.len()].copy_from_slice(value);
        put(&body);
    };
    property(u.time_frame, u.long, &(frame.round() as i64).to_ne_bytes());
    let speed: f32 = if ctx.playing { 1.0 } else { 0.0 };
    property(u.time_speed, u.float, &speed.to_ne_bytes());
    property(u.time_bar, u.long, &bar.to_ne_bytes());
    let bar_beat = ((ctx.position - ctx.bar_start) * per_quarter) as f32;
    property(u.time_bar_beat, u.float, &bar_beat.to_ne_bytes());
    property(u.time_beat_unit, u.int, &(ctx.sig_den as i32).to_ne_bytes());
    property(
        u.time_beats_per_bar,
        u.float,
        &(ctx.sig_num as f32).to_ne_bytes(),
    );
    let tempo = (ctx.tempo * per_quarter) as f32;
    property(u.time_beats_per_minute, u.float, &tempo.to_ne_bytes());
    out
}

/// An atom port's buffer: 64-bit aligned, as atoms must be.
pub(super) struct AtomBuffer {
    pub(super) data: Vec<u64>,
    pub(super) input: bool,
}

impl AtomBuffer {
    pub(super) fn new(input: bool) -> Self {
        Self {
            data: vec![0; ATOM_CAPACITY / 8],
            input,
        }
    }

    pub(super) fn header(&mut self) -> &mut SequenceHeader {
        // SAFETY: `data` is a Vec<u64>, so it is 8-byte aligned, and `new` makes it at least 16 bytes
        // (ATOM_CAPACITY / 8 words), which is the size of a SequenceHeader; `&mut self` makes the borrow unique.
        unsafe { &mut *(self.data.as_mut_ptr() as *mut SequenceHeader) }
    }

    /// Get the buffer ready for a block: an empty sequence to read from, or
    /// free space for the plugin to write into.
    pub(super) fn reset(&mut self) {
        let u = urids();
        let input = self.input;
        let header = self.header();
        header.unit = 0;
        header.pad = 0;
        if input {
            header.size = 8;
            header.type_ = u.sequence;
        } else {
            header.size = (ATOM_CAPACITY - 8) as u32;
            header.type_ = u.chunk;
        }
    }

    pub(super) fn push_midi(&mut self, frame: u32, bytes: [u8; 3], len: u32) {
        let used = 8 + self.header().size as usize;
        if used + 24 > ATOM_CAPACITY {
            return;
        }
        // SAFETY: `used + 24 <= ATOM_CAPACITY` (checked above), so the 16-byte event header and the 8 bytes
        // of body written here are inside `data`; `used` is a multiple of 8 because the sequence header
        // is 8 bytes and every event added is padded to 8, so the header write is aligned.
        unsafe {
            let at = (self.data.as_mut_ptr() as *mut u8).add(used);
            (at as *mut EventHeader).write(EventHeader {
                frames: frame as i64,
                size: len,
                type_: urids().midi_event,
            });
            // Two or three bytes of MIDI, padded out to eight.
            let mut body = [0u8; 8];
            body[..3].copy_from_slice(&bytes);
            ptr::copy_nonoverlapping(body.as_ptr(), at.add(16), 8);
        }
        self.header().size += 24;
    }

    /// Append an event holding `atom`, a complete atom: header and body.
    pub(super) fn push_atom(&mut self, frame: u32, atom: &[u8]) {
        let used = 8 + self.header().size as usize;
        let padded = atom.len().div_ceil(8) * 8;
        if atom.len() < 8 || used + 8 + padded > ATOM_CAPACITY {
            return;
        }
        // SAFETY: `used + 8 + padded <= ATOM_CAPACITY` (checked above), so the frame stamp, the padding and
        // the `atom.len()` bytes copied are inside `data`; `atom` is a slice in another allocation, so
        // the copy does not overlap; `used` is a multiple of 8, so the i64 write is aligned.
        unsafe {
            let at = (self.data.as_mut_ptr() as *mut u8).add(used);
            (at as *mut i64).write(frame as i64);
            ptr::write_bytes(at.add(8), 0, padded);
            ptr::copy_nonoverlapping(atom.as_ptr(), at.add(8), atom.len());
        }
        self.header().size += (8 + padded) as u32;
    }

    /// Call `f` with each event's atom (header and body) in a sequence the
    /// plugin wrote.
    pub(super) fn each_event(&self, mut f: impl FnMut(&[u8])) {
        let bytes =
            // SAFETY: `data` holds `ATOM_CAPACITY / 8` initialized u64 words, so the same memory is
            // ATOM_CAPACITY initialized bytes; the plugin is not running while `&self` is borrowed.
            unsafe { std::slice::from_raw_parts(self.data.as_ptr() as *const u8, ATOM_CAPACITY) };
        // SAFETY: `data` is 8-byte aligned and at least 16 bytes, the size of a SequenceHeader, and every
        // bit pattern is a valid value for its integer fields.
        let header = unsafe { &*(self.data.as_ptr() as *const SequenceHeader) };
        if header.type_ != urids().sequence {
            return;
        }
        let end = (8 + header.size as usize).min(ATOM_CAPACITY);
        let mut at = 16;
        while at + 16 <= end {
            let size = u32::from_le_bytes(bytes[at + 8..at + 12].try_into().unwrap()) as usize;
            if at + 16 + size > end {
                break;
            }
            f(&bytes[at + 8..at + 16 + size]);
            at += 16 + size.div_ceil(8) * 8;
        }
    }
}

