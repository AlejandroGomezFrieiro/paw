//! How early or late stamped MIDI leaves through the sequencer: notes
//! stamped some time ahead go out of `MidiOutputs` to a port of our own
//! `MidiInputs`, and each is timed where it arrives.
//!
//! `cargo bench -p paw-engine --bench midi_lateness -- [notes]` prints one
//! JSON line: the median and the worst of how early and how late the notes
//! came, in nanoseconds. It needs the ALSA sequencer, and makes only ports
//! of its own.

use std::sync::mpsc::{Receiver, channel};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use paw_engine::midi::{MidiInputs, MidiTarget, port_key};
use paw_engine::midi_form::Form;
use paw_engine::midi_out::{MidiOut, MidiOutputs, clock_ns};
use paw_engine::{Attr, EventKind};

const PORT: &str = "Lateness";
/// How far ahead the first note is stamped, and the notes apart.
const AHEAD_NS: u64 = 200_000_000;
const APART_NS: u64 = 50_000_000;

/// The inputs with our port, and the time each note-on arrives there.
fn listen() -> (MidiInputs, Receiver<u64>) {
    let (tx, rx) = channel();
    let sink = Arc::new(Mutex::new(MidiTarget {
        engine: None,
        tap: Some(Box::new(move |_, kind| {
            if matches!(kind, EventKind::NoteOn { .. }) {
                let _ = tx.send(clock_ns());
            }
        })),
    }));
    // No port but our own: the notes of other programs are not timed.
    let inputs = MidiInputs::start(sink, Some(Vec::new())).expect("the ALSA sequencer");
    inputs.open_port(PORT);
    (inputs, rx)
}

/// The outputs, once they list our port.
fn outputs() -> MidiOutputs {
    let outputs = MidiOutputs::start().expect("the ALSA sequencer");
    let name = format!("paw: {PORT}");
    while !outputs.ports().iter().any(|p| p.name == name) {
        std::thread::sleep(Duration::from_millis(20));
    }
    outputs
}

fn median(mut values: Vec<u64>) -> u64 {
    values.sort_unstable();
    values[values.len() / 2]
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).filter(|a| a != "--bench").collect();
    let notes: u64 = args.first().and_then(|a| a.parse().ok()).unwrap_or(40);
    let (_inputs, rx) = listen();
    let outputs = outputs();
    let (mut tx, queue) = rtrb::RingBuffer::<MidiOut>::new(2 * notes as usize);
    outputs.set_queue(queue);
    let port = port_key(&format!("paw: {PORT}"));
    let start = clock_ns() + AHEAD_NS;
    let stamps: Vec<u64> = (0..notes).map(|i| start + i * APART_NS).collect();
    for &at in &stamps {
        for (at, kind) in [
            (at, EventKind::NoteOn { key: 60, vel: 0.8, ch: 0, attr: Attr::NONE }),
            (at + APART_NS / 2, EventKind::NoteOff { key: 60, ch: 0 }),
        ] {
            tx.push(MidiOut { at, port, form: Form::Auto, kind }).expect("room in the queue");
        }
    }
    let deadline = Instant::now() + Duration::from_nanos(AHEAD_NS + notes * APART_NS) * 2;
    let mut arrived = Vec::new();
    while arrived.len() < stamps.len() {
        let left = deadline.saturating_duration_since(Instant::now());
        let Ok(at) = rx.recv_timeout(left) else { break };
        arrived.push(at);
    }
    assert!(!arrived.is_empty(), "no note arrived at our port");
    let pairs = || stamps.iter().zip(&arrived);
    let early: Vec<u64> = pairs().map(|(want, at)| want.saturating_sub(*at)).collect();
    let late: Vec<u64> = pairs().map(|(want, at)| at.saturating_sub(*want)).collect();
    println!(
        "{{\"notes\":{},\"arrived\":{},\"early_median_ns\":{},\"early_max_ns\":{},\"late_median_ns\":{},\"late_max_ns\":{}}}",
        notes,
        arrived.len(),
        median(early.clone()),
        early.iter().max().copied().unwrap_or(0),
        median(late.clone()),
        late.iter().max().copied().unwrap_or(0),
    );
}
