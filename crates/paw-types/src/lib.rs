//! The value types that the project model and the audio engine share.
//!
//! Notes and controllers as MIDI 2.0 events ([`event`]), their wire format
//! ([`ump`]) and their MIDI 1.0 forms ([`midi_form`]), the tempo map
//! ([`tempo`]), where a launch lands ([`quantize`]), the values of
//! automation and state lanes ([`automation`]), decibels ([`gain`]) and the
//! names of pitches ([`pitch`]).
//!
//! The crate has no audio, no threads and no calls to the operating system,
//! so that it builds for `wasm32-unknown-unknown`. `paw-engine` plays these
//! values; `paw-core`'s model keeps them. The other types that the model and
//! its extensions share (the kinds of a family, versions, stored values)
//! belong here too.

pub mod automation;
pub mod event;
pub mod gain;
pub mod midi_form;
pub mod pitch;
pub mod quantize;
pub mod tempo;
pub mod ump;

pub use event::{Attr, Ctl, EventKind, NOTE_BEND_RANGE, NoteCtl};
pub use quantize::Quantize;
pub use tempo::{SigPoint, TempoMap, TempoPoint};
