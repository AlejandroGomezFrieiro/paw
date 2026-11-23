//! What the ALSA sequencer headers define as macros, which the bindings
//! leave out. The MIDI input (`midi`) and the MIDI output (`midi_out`) share
//! these values.

use std::ffi::c_int;

use bitflags::bitflags;

bitflags! {
    /// What a port can do (`SND_SEQ_PORT_CAP_*`).
    #[derive(Clone, Copy, PartialEq, Eq)]
    pub struct Caps: u32 {
        const READ = 1 << 0;
        const WRITE = 1 << 1;
        const SUBS_READ = 1 << 5;
        const SUBS_WRITE = 1 << 6;
        const NO_EXPORT = 1 << 7;
    }

    /// What a port is (`SND_SEQ_PORT_TYPE_*`).
    #[derive(Clone, Copy, PartialEq, Eq)]
    pub struct PortType: u32 {
        const MIDI_GENERIC = 1 << 1;
        const APPLICATION = 1 << 20;
    }
}

/// `SND_SEQ_OPEN_OUTPUT`.
pub(crate) const OPEN_OUTPUT: c_int = 1;
/// `SND_SEQ_OPEN_INPUT`.
pub(crate) const OPEN_INPUT: c_int = 2;
/// `SND_SEQ_NONBLOCK`.
pub(crate) const NONBLOCK: c_int = 1;
/// Set on an event that carries a Universal MIDI Packet.
pub(crate) const EVENT_UMP: u8 = 1 << 5;
/// `SND_SEQ_CLIENT_MIDI_2_0`.
pub(crate) const MIDI_2_0: c_int = 2;
/// The sequencer's own client, and its announce port.
pub(crate) const SYSTEM_CLIENT: c_int = 0;
pub(crate) const SYSTEM_ANNOUNCE: c_int = 1;
