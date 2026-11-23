//! A `.midi2` clip file, as a project folder or `paw clip cat` reads it:
//! an error or a clip, and the clip as text, never a panic. A clip that
//! reads also writes again, in bounded time and memory.

#![no_main]

use libfuzzer_sys::fuzz_target;
use paw_core::clipfile;

fuzz_target!(|bytes: &[u8]| {
    if let Ok(clip) = clipfile::decode(bytes) {
        clipfile::text(&clip);
        clipfile::encode(&clip.notes, &clip.controls, clip.length)
            .expect("a clip that paw reads, paw writes");
    }
});
