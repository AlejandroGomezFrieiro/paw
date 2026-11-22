//! The terminal's keys as they arrive in pieces (paw-tui's keys.rs):
//! escape sequences cut anywhere, pauses inside them, mouse reports and
//! bracketed paste. The joiner gives events, never a panic.
//!
//! The input is text: each character is the key that crossterm reports
//! for it, with these exceptions. ESC is the Escape key, NUL is a pause in
//! which nothing arrives, CR and LF are Enter, TAB is Tab, and DEL is an
//! event that is not a key (a change of size).

#![no_main]

use std::time::Duration;

use crossterm::event::{Event, KeyCode, KeyEvent, KeyModifiers};
use libfuzzer_sys::fuzz_target;
use paw_tui::keys::{Joiner, Scripted};

fn step(c: char) -> Option<Event> {
    let key = |code| Some(Event::Key(KeyEvent::new(code, KeyModifiers::NONE)));
    match c {
        '\0' => None,
        '\x1b' => key(KeyCode::Esc),
        '\r' | '\n' => key(KeyCode::Enter),
        '\t' => key(KeyCode::Tab),
        '\x7f' => Some(Event::Resize(80, 24)),
        c => key(KeyCode::Char(c)),
    }
}

fuzz_target!(|bytes: &[u8]| {
    let text = String::from_utf8_lossy(bytes);
    // The wait does not pass: a pause in the script ends it at once.
    let mut joiner = Joiner::new(
        Scripted::new(text.chars().map(step)),
        Duration::from_millis(15),
    );
    while joiner.next_event().is_some() {}
});
