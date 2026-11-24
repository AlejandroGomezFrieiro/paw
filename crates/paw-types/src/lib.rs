//! The value types that the project model and the audio engine share.
//!
//! Notes and controllers as MIDI 2.0 events ([`event`]), their wire format
//! ([`ump`]) and their MIDI 1.0 forms ([`midi_form`]), the tempo map
//! ([`tempo`]), where a launch lands ([`quantize`]), the values of
//! automation and state lanes ([`automation`]), decibels ([`gain`]) and the
//! names of pitches ([`pitch`]), and the families of kinds with their
//! registry ([`kinds`]), and the type of a stream ([`stream`]).
//!
//! The crate has no audio, no threads and no calls to the operating system,
//! so that it builds for `wasm32-unknown-unknown`. `paw-engine` plays these
//! values; `paw-core`'s model keeps them.

pub mod automation;
pub mod event;
pub mod gain;
pub mod kinds;
pub mod midi_form;
pub mod pitch;
pub mod quantize;
pub mod stream;
pub mod tempo;
pub mod ump;

pub use event::{Attr, Ctl, EventKind, NOTE_BEND_RANGE, NoteCtl};
pub use quantize::Quantize;
pub use tempo::{SigPoint, TempoMap, TempoPoint};
