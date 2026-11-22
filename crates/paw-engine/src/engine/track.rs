//! A track as the audio thread holds it, and the connections between tracks.

use crate::automation::Automation;
use crate::clip::ClipSet;
use crate::event::{Event, EventBuf, EventKind};
use crate::launch::Launcher;
use crate::slot::{DeviceSlot, TrackSlot};

use super::MAX_BLOCK;

pub struct TrackRt {
    pub(super) buf: [Vec<f32>; 2],
    pub(super) chain: Box<[DeviceSlot]>,
    pub(super) clips: Box<ClipSet>,
    pub(super) automation: Box<Automation>,
    pub(super) gain: f32,
    pub(super) pan: f32,
    pub(super) mute: bool,
    /// Silenced because another track is soloed: not heard, but what
    /// listens to it as a side-chain still hears it.
    pub(super) quiet: bool,
    /// Per-channel gain actually applied at the end of the last block.
    pub(super) applied: [f32; 2],
    /// The same for what is sent on before the fader: 0 when muted, else 1.
    pub(super) applied_pre: f32,
    /// The same for what is heard of it after the fader: 0 when quiet.
    pub(super) applied_heard: f32,
    /// Whether the track has produced a block yet. Until then a fader change
    /// takes effect at once rather than ramping from the default.
    pub(super) started: bool,
    pub(super) events: EventBuf,
    pub(super) live: Vec<EventKind>,
    pub(super) peak: [f32; 2],
    /// First input channel and how many channels (0, 1 or 2) the track takes.
    pub(super) input_first: usize,
    pub(super) input_channels: usize,
    /// Whether the input is heard.
    pub(super) monitor: bool,
    /// Armed tracks without an audio input receive MIDI input.
    pub(super) armed: bool,
    /// Which MIDI input it takes when armed: a port's key from
    /// [`crate::midi::port_key`], or 0 for every port; and a channel from 1
    /// to 16, or 0 for every channel.
    pub(super) midi_port: u32,
    pub(super) midi_channel: u8,
    /// Keys held down through MIDI input, released if the track is disarmed.
    pub(super) held: u128,
    /// The MIDI output port it sends what it plays to, by its key (0 for
    /// none), the channel (1 to 16, or 0 for each message's own), and the
    /// form it goes in.
    pub(super) midi_out: u32,
    pub(super) midi_out_channel: u8,
    pub(super) midi_out_form: crate::midi_form::Form,
    /// What it played this block, on its way to the port.
    pub(super) sent: Vec<Event>,
    /// The track's clips were replaced: stop its notes, and start again those
    /// the new clips hold at the play position. Other tracks play on.
    pub(super) flush: bool,
    pub(super) chase: bool,
    /// The clips in its slots, and which of them plays.
    pub(super) launcher: Launcher,
    /// Its own time, which its devices see instead of the song's: a
    /// subproject's bars.
    pub(super) local: Option<Box<crate::tempo::LocalTime>>,
}

impl TrackRt {
    pub fn new() -> Box<Self> {
        Box::new(Self {
            buf: [vec![0.0; MAX_BLOCK], vec![0.0; MAX_BLOCK]],
            chain: Box::new([]),
            clips: Box::default(),
            automation: Box::default(),
            gain: 1.0,
            pan: 0.0,
            mute: false,
            quiet: false,
            applied: [1.0, 1.0],
            applied_pre: 1.0,
            applied_heard: 1.0,
            started: false,
            events: EventBuf::with_capacity(1024),
            live: Vec::with_capacity(256),
            peak: [0.0; 2],
            input_first: 0,
            input_channels: 0,
            monitor: false,
            armed: false,
            midi_port: 0,
            midi_channel: 0,
            held: 0,
            midi_out: 0,
            midi_out_channel: 0,
            midi_out_form: crate::midi_form::Form::Auto,
            sent: Vec::with_capacity(1024),
            flush: false,
            chase: false,
            launcher: Launcher::default(),
            local: None,
        })
    }

    /// An armed track with an audio input records that; one without plays
    /// and records MIDI input. A monitored one without plays it only.
    pub(super) fn takes_midi(&self) -> bool {
        (self.armed || self.monitor) && self.input_channels == 0
    }

    /// Whether a message from MIDI input on `port` is for this track.
    pub(super) fn hears(&self, port: u32, kind: &EventKind) -> bool {
        self.takes_midi()
            && (self.midi_port == 0 || self.midi_port == port)
            && (self.midi_channel == 0
                || kind.channel().is_none_or(|ch| ch + 1 == self.midi_channel))
    }

    /// Whether `kind` lets go of a key this track holds from MIDI input.
    pub(super) fn releases(&self, kind: &EventKind) -> bool {
        matches!(*kind, EventKind::NoteOff { key, .. } if self.held & (1 << (key & 127)) != 0)
    }

    pub(super) fn target_gains(&self) -> [f32; 2] {
        if self.mute {
            return [0.0, 0.0];
        }
        // Equal-power pan, scaled so that centre is unity gain.
        let angle = (self.pan.clamp(-1.0, 1.0) + 1.0) * std::f32::consts::FRAC_PI_4;
        let scale = self.gain * std::f32::consts::SQRT_2;
        [scale * angle.cos(), scale * angle.sin()]
    }
}

/// The longest a connection can be held back to wait for a slower one.
pub const MAX_DELAY: usize = 1 << 17;

/// A fixed delay on one connection between tracks. Devices that look ahead
/// report how late their output is; the connections of the tracks that are
/// not late are held back by the difference, so that everything arrives at a
/// mix point together. Empty, and free, when there is nothing to wait for.
#[derive(Default)]
pub struct Delay {
    pub(super) ring: [Vec<f32>; 2],
    pub(super) at: usize,
}

impl Delay {
    pub fn new(frames: usize) -> Self {
        let frames = frames.min(MAX_DELAY);
        Self {
            ring: [vec![0.0; frames], vec![0.0; frames]],
            at: 0,
        }
    }

    pub fn frames(&self) -> usize {
        self.ring[0].len()
    }

    pub(super) fn clear(&mut self) {
        self.ring[0].fill(0.0);
        self.ring[1].fill(0.0);
    }

    /// Add `src`, this much later, into a pair of buffers, with a gain that
    /// moves from `from` to `to` over the block.
    pub(super) fn mix(&mut self, src: [&[f32]; 2], dst: [&mut [f32]; 2], from: f32, to: f32) {
        let n = src[0].len();
        let len = self.ring[0].len();
        let step = (to - from) / n.max(1) as f32;
        for (ch, (src, dst)) in src.into_iter().zip(dst).enumerate() {
            if len == 0 {
                // Nothing to wait for: a plain sum, which vectorises.
                if step == 0.0 {
                    let gain = from + step;
                    for (d, s) in dst[..n].iter_mut().zip(src) {
                        *d += s * gain;
                    }
                } else {
                    for (i, (d, s)) in dst[..n].iter_mut().zip(src).enumerate() {
                        *d += s * (from + step * (i + 1) as f32);
                    }
                }
                continue;
            }
            let mut at = self.at;
            let ring = &mut self.ring[ch];
            for (i, (d, s)) in dst[..n].iter_mut().zip(src).enumerate() {
                let gain = from + step * (i + 1) as f32;
                *d += ring[at] * gain;
                ring[at] = *s;
                at += 1;
                if at == len {
                    at = 0;
                }
            }
        }
        if len > 0 {
            self.at = (self.at + n) % len;
        }
    }
}

/// A send from one track into another.
pub struct SendRt {
    pub target: TrackSlot,
    pub gain: f32,
    /// Taken after the devices but before the fader, pan and mute.
    pub pre: bool,
    pub delay: Delay,
}

impl SendRt {
    pub fn new(target: TrackSlot, gain: f32) -> Self {
        Self {
            target,
            gain,
            pre: false,
            delay: Delay::default(),
        }
    }
}

/// A side-chain: a track's sound taken to a device on another track that
/// listens to it, such as a compressor ducking under a kick.
pub struct KeyRt {
    /// The device that listens, and the track it is on.
    pub device: DeviceSlot,
    pub track: TrackSlot,
    /// Taken after the devices but before the fader, pan and mute, so that
    /// a muted track can still key.
    pub pre: bool,
    /// Lines the key up with the sound the device is processing.
    pub delay: Delay,
}

/// One of a device's further output pairs, played into another track.
/// It is taken from the device as it is: the fader, pan and mute of the
/// device's own track do not act on it, the target's do.
pub struct OutRt {
    /// The device, and which of its further pairs: 0 for its second.
    pub device: DeviceSlot,
    pub pair: usize,
    pub target: TrackSlot,
    pub delay: Delay,
}

/// Queue a note-off for every key a track holds through MIDI input.
pub(super) fn release_held(t: &mut TrackRt) {
    while t.held != 0 {
        let key = t.held.trailing_zeros() as u8;
        t.held &= !(1 << key);
        if t.live.len() < t.live.capacity() {
            t.live.push(EventKind::NoteOff { key, ch: 0 });
        }
    }
}
