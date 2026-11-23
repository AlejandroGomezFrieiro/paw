//! The integration tests of the engine, in one binary: each file in
//! `tests/` links the crate again, so the areas are modules of this
//! binary. `tests/no_alloc.rs` stays a binary of its own, because it sets
//! a global allocator for its process.

mod common;

mod bend;
mod bus_clips;
mod clips;
mod launch;
mod midi_out;
mod midi_ports;
mod nest_transport;
mod punch;
mod sleep;
mod states;
mod tempo;
mod threads;
