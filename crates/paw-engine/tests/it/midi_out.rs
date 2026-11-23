//! MIDI output: what an engine's tracks send is stamped with when it is
//! heard, on their port and channel, and a track that stops ends its notes.
//!
//! No test here opens the ALSA sequencer: it is shared by every process of
//! the machine, and a test that listens there hears the notes of others.
//! The unit tests in `src/midi_out.rs` check where a route's messages go
//! and in which form, with a spy in place of the sequencer, and what paw
//! asks the sequencer for (`queue_time`). The round trip through the
//! sequencer is `tests/midi_out.lua` and `tests/midi2.lua`. How early or
//! late the messages arrive is measured by `benches/midi_lateness.rs`.

use paw_engine::midi::port_key;
use paw_engine::midi_out::MidiOut;
use paw_engine::{
    ClipSet, Engine, EngineHandle, MidiEv, Msg, SchedEntry, Schedule, TrackRt, TrackSlot,
};
use paw_types::{Attr, Ctl, EventKind, midi_form::Form};

const RATE: f64 = 48_000.0;

/// What a track sends to end what it plays, on channel 10: its notes, the
/// pedal and the wheel.
const RESET: [EventKind; 3] = [
    EventKind::AllNotesOff,
    EventKind::Control { ctl: Ctl::Cc(64), value: 0.0, ch: 9 },
    EventKind::Control { ctl: Ctl::Bend, value: 0.0, ch: 9 },
];

/// A track that sends to `port` on channel 10 a note held from the first
/// beat and another from the second, at 120 BPM; and what the engine
/// sends out, read where the MIDI output thread reads it.
fn engine_sending_to(port: u32) -> (Engine, EngineHandle, rtrb::Consumer<MidiOut>) {
    let (mut engine, mut handle) = Engine::new(RATE);
    let sent = handle.midi_output();
    let mut clips = ClipSet::default();
    clips.midi = vec![
        MidiEv { beat: 0.0, kind: EventKind::NoteOn { key: 50, vel: 0.5, ch: 0, attr: Attr::NONE } },
        MidiEv { beat: 1.0, kind: EventKind::NoteOn { key: 52, vel: 0.5, ch: 0, attr: Attr::NONE } },
    ];
    let entries = vec![
        SchedEntry::new(TrackSlot(1), TrackSlot::MASTER),
        SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE),
    ];
    for msg in [
        Msg::InsertTrack { slot: TrackSlot(1), track: TrackRt::new() },
        Msg::SetClips { track: TrackSlot(1), clips: Box::new(clips) },
        Msg::SetMidiOutput { track: TrackSlot(1), port, channel: 10, form: Form::Auto },
        Msg::SetSchedule(Box::new(Schedule::new(entries, 0))),
        Msg::SetTempo(120.0),
    ] {
        handle.send_while(msg, &mut engine);
    }
    (engine, handle, sent)
}

/// Run `frames` frames in one callback.
fn run(engine: &mut Engine, frames: usize) {
    let (mut left, mut right) = (vec![0.0; frames], vec![0.0; frames]);
    engine.process(&mut left, &mut right);
}

/// Everything the engine has sent since the last read.
fn drain(sent: &mut rtrb::Consumer<MidiOut>) -> Vec<MidiOut> {
    std::iter::from_fn(|| sent.pop().ok()).collect()
}

#[test]
fn an_engine_stamps_what_a_track_plays_and_ends_it_when_stopped() {
    let port = port_key("paw: Synth");
    let (mut engine, mut handle, mut sent) = engine_sending_to(port);

    // One callback a little past the second beat: its stamps all count
    // from the same time, so they are as far apart as the notes.
    handle.send_while(Msg::Play, &mut engine);
    run(&mut engine, 24_480);
    let played = drain(&mut sent);
    handle.send_while(Msg::Stop, &mut engine);
    run(&mut engine, 64);
    let stopped = drain(&mut sent);

    assert!(
        played.iter().chain(&stopped).all(|m| m.port == port && m.form == Form::Auto),
        "all to the track's port, in its form"
    );
    // New clips reset what the track plays first: its first block sends
    // the reset, then both notes on the track's channel.
    let kinds: Vec<EventKind> = played.iter().map(|m| m.kind).collect();
    let mut want = RESET.to_vec();
    want.extend([
        EventKind::NoteOn { key: 50, vel: 0.5, ch: 9, attr: Attr::NONE },
        EventKind::NoteOn { key: 52, vel: 0.5, ch: 9, attr: Attr::NONE },
    ]);
    assert_eq!(kinds, want, "the reset, then both notes on the track's channel");
    // A beat at 120 BPM is 500 ms. A frame turned into nanoseconds is
    // rounded down, so the stamps may be some nanoseconds off, never a
    // frame (20 833 ns at 48 kHz).
    let apart = played[4].at - played[3].at;
    assert!(apart.abs_diff(500_000_000) < 1_000, "a beat apart: {apart} ns");
    // Stopped: the held notes end, and the pedal and the wheel go back.
    let kinds: Vec<EventKind> = stopped.iter().map(|m| m.kind).collect();
    assert_eq!(kinds, RESET, "the notes ended when the track stopped");
}
