//! The messages the main thread sends the audio thread, and what goes back to be freed.

use rtrb::Producer;

use crate::automation::Automation;
use crate::clip::ClipSet;
use crate::device::Device;
use crate::event::EventKind;
use crate::launch::{Launch, Slots};
use crate::midi_filter::MidiFilter;
use crate::midi_out::MidiOut;
use crate::pool::Pool;
use crate::preview::Preview;
use crate::record::Take;
use crate::slot::{DeviceSlot, TrackSlot};
use crate::tempo::TempoMap;

use super::device_rt::{KeyBuf, OutBufs};
use super::schedule::Schedule;
use super::track::TrackRt;

pub enum Msg {
    InsertTrack {
        slot: TrackSlot,
        track: Box<TrackRt>,
    },
    RemoveTrack {
        slot: TrackSlot,
    },
    SetSchedule(Box<Schedule>),
    SetMix {
        slot: TrackSlot,
        gain: f32,
        pan: f32,
        mute: bool,
        /// Silenced by another track's solo (see `TrackRt::quiet`).
        quiet: bool,
    },
    InsertDevice {
        slot: DeviceSlot,
        device: Box<dyn Device>,
    },
    /// Give a device a buffer for its side-chain, which the track it listens
    /// to fills each block, or take it away with `None`.
    SetKey {
        device: DeviceSlot,
        key: Option<Box<KeyBuf>>,
    },
    /// Give a device buffers for its further output pairs, as many as are
    /// routed somewhere, or take them away with `None`.
    SetOutputs {
        device: DeviceSlot,
        outs: Option<Box<OutBufs>>,
    },
    RemoveDevice {
        slot: DeviceSlot,
    },
    SetChain {
        track: TrackSlot,
        chain: Box<[DeviceSlot]>,
    },
    SetParam {
        device: DeviceSlot,
        param: u32,
        value: f32,
    },
    SetBypass {
        device: DeviceSlot,
        bypass: bool,
    },
    /// The wet/dry mix and gain the host puts around a device (see `host`).
    SetHost {
        device: DeviceSlot,
        path: Box<crate::host::HostPath>,
    },
    /// Frames the device's output is behind its input, for the dry signal.
    SetDeviceLatency {
        device: DeviceSlot,
        frames: u32,
    },
    SetClips {
        track: TrackSlot,
        clips: Box<ClipSet>,
    },
    /// Take out and put in some of the parts of a track's clips (see
    /// [`ClipSet::edit`]): what an edit of a few clips sends.
    EditClips {
        track: TrackSlot,
        edit: Box<crate::clip::PartEdit>,
    },
    /// While playing, the lanes set the track's fader, pan and device
    /// parameters at the start of each block, over whatever was set directly.
    SetAutomation {
        track: TrackSlot,
        automation: Box<Automation>,
    },
    /// The devices already hold the states their state lanes give at the
    /// play position (a render gave them before it started): the next
    /// `Play` does not give them again.
    StatesHeld,
    /// Follow a new tempo map from the next block on.
    SetTempoMap(Box<TempoMap>),
    /// Change the first tempo of the map, keeping its other points.
    SetTempo(f64),
    /// Change the first signature of the map, keeping its other points.
    SetTimeSig {
        num: u32,
        den: u32,
    },
    SetLoop {
        enabled: bool,
        start: f64,
        end: f64,
    },
    SetMetronome(bool),
    /// The metronome's gain (1 for its own level), whether the first beat
    /// of a bar is higher, and the first output channel (from 1) of the
    /// pair it plays on, or 0 for with the song.
    SetClick {
        gain: f32,
        accent: bool,
        output: u16,
    },
    Play,
    /// Count in, then play: click `clicks` times, `every` frames apart and
    /// the first of every `per_bar` higher, and start playing on the frame
    /// `frames` from now, where the next click would have been. The clicks
    /// are heard as late as the song is (the schedule's latency), so that
    /// they lead into it evenly. [`Msg::Stop`] calls it off.
    CountIn {
        frames: u64,
        every: f64,
        clicks: u32,
        per_bar: u32,
    },
    Stop,
    Seek(f64),
    /// A note played live rather than from a clip, delivered at the next block.
    Live {
        track: TrackSlot,
        event: EventKind,
    },
    /// Which input channels a track takes (`channels` is 0 for none), whether
    /// they are heard, and whether the track is armed.
    SetInput {
        track: TrackSlot,
        first: usize,
        channels: usize,
        monitor: bool,
        armed: bool,
    },
    /// Which MIDI input an armed track without audio input takes: a port's
    /// key ([`crate::midi::port_key`]) or 0 for all, a channel from 1 to 16
    /// or 0 for all.
    SetMidiInput {
        track: TrackSlot,
        port: u32,
        channel: u8,
    },
    /// The MIDI output port a track sends what it plays to, by its key (0
    /// for none), on a channel from 1 to 16 or 0 for each message's own,
    /// in a form for ports that take no MIDI 2.0.
    SetMidiOutput {
        track: TrackSlot,
        port: u32,
        channel: u8,
        form: crate::midi_form::Form,
    },
    /// Where MIDI output goes: the queue a sender thread reads (see
    /// [`EngineHandle::midi_output`]), or nowhere.
    SetMidiOut(Option<Box<Producer<MidiOut>>>),
    /// Start capturing into a take, or stop with `None`.
    SetTake(Option<Box<Take>>),
    /// A note as if it came from a MIDI input port, by its key (0 for none
    /// in particular, which only tracks that take every port hear).
    MidiIn {
        port: u32,
        kind: EventKind,
    },
    /// The controls of MIDI input that tracks do not get (see
    /// [`crate::midi_filter`]), in place of those before.
    SetMidiFilter(Box<MidiFilter>),
    /// Worker threads to process tracks on, or `None` for the audio thread alone.
    SetPool(Option<Box<Pool>>),
    /// The clips in a track's slots, to be launched.
    SetSlots {
        track: TrackSlot,
        slots: Box<Slots>,
    },
    /// Launch slots, stop them or go back to the arrangement, each track on
    /// the first boundary of its quantize from where the engine is when it
    /// takes the message (at once while stopped). Launches sent together
    /// are timed together.
    Launch(Box<Vec<Launch>>),
    /// Where a copy of what is played goes, left and right interleaved, for
    /// someone listening elsewhere (see [`EngineHandle::monitor`]), or nowhere.
    SetMonitor(Option<Box<Producer<f32>>>),
    /// A sound file to hear over everything else, outside the project (see
    /// [`crate::preview`]), or silence with `None`. What played before fades
    /// out.
    SetPreview(Option<Box<Preview>>),
    /// The level of the file being heard, as a linear gain.
    SetPreviewGain(f32),
    /// Whether devices at rest are left asleep through silent blocks (see
    /// [`Device::resting`]). The sound is the same either way.
    SetSleep(bool),
}

pub(super) enum Garbage {
    Track(#[allow(dead_code)] Box<TrackRt>),
    Device(#[allow(dead_code)] Box<dyn Device>),
    Schedule(#[allow(dead_code)] Box<Schedule>),
    Chain(#[allow(dead_code)] Box<[DeviceSlot]>),
    Clips(#[allow(dead_code)] Box<ClipSet>),
    PartEdit(#[allow(dead_code)] Box<crate::clip::PartEdit>),
    Automation(#[allow(dead_code)] Box<Automation>),
    Take(#[allow(dead_code)] Box<Take>),
    Pool(#[allow(dead_code)] Box<Pool>),
    Host(#[allow(dead_code)] Box<crate::host::HostPath>),
    Key(#[allow(dead_code)] Box<KeyBuf>),
    Outs(#[allow(dead_code)] Box<OutBufs>),
    MidiOut(#[allow(dead_code)] Box<Producer<MidiOut>>),
    Monitor(#[allow(dead_code)] Box<Producer<f32>>),
    TempoMap(#[allow(dead_code)] Box<TempoMap>),
    Slots(#[allow(dead_code)] Box<Slots>),
    Launches(#[allow(dead_code)] Box<Vec<Launch>>),
    Preview(#[allow(dead_code)] Box<Preview>),
    MidiFilter(#[allow(dead_code)] Box<MidiFilter>),
}
