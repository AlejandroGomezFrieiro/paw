//! A `.midi2` clip file, as a project folder or `paw clip cat` reads it:
//! an error or a clip, and the clip as text, never a panic.

#![no_main]

use libfuzzer_sys::fuzz_target;
use paw_core::clipfile;

fuzz_target!(|bytes: &[u8]| {
    if let Ok(clip) = clipfile::decode(bytes) {
        clipfile::text(&clip);
    }
});
