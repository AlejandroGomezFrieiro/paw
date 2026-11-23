//! The remote protocol, as each side reads what the other sends: one JSON
//! message to a line. The terminal attached to a far kernel puts each
//! `ui.grid` payload into its grid and reads `audio.frame` payloads; the
//! kernel reads the input events of a far terminal. Each line goes to all
//! three readers, and the grid is kept from line to line, as a session
//! keeps it. An error is the right answer to a bad line, never a panic.

#![no_main]

use libfuzzer_sys::fuzz_target;
use paw_core::grid::Grid;
use paw_core::remote;
use serde_json::Value;

fuzz_target!(|bytes: &[u8]| {
    let mut grid = Grid::new(80, 24);
    for line in bytes.split(|&b| b == b'\n') {
        let Ok(payload) = serde_json::from_slice::<Value>(line) else {
            continue;
        };
        let _ = remote::apply(&mut grid, &payload);
        remote::input_of(&payload);
        let _ = paw_proto::monitor::decode(&payload);
    }
});
