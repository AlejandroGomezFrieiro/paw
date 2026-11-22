//! MIDI output: what an engine's tracks send is stamped with when it is
//! heard, on their port and channel, and a track that stops ends its notes.
//! With the `midi` feature, a route's messages leave through the sequencer
//! to a port of our own MIDI input that the test listens to.
//!
//! No test here compares a time with the clock: when a stamped message
//! leaves is the sequencer's work, and the unit test of `queue_time` in
//! `src/midi_out.rs` checks what paw asks it for. How early or late the
//! messages arrive is measured by `benches/midi_lateness.rs`.

use paw_engine::midi::port_key;
use paw_engine::midi_form::Form;
use paw_engine::midi_out::MidiOut;
use paw_engine::{
    Attr, ClipSet, Ctl, Engine, EngineHandle, EventKind, MidiEv, Msg, SchedEntry, Schedule,
    TrackRt, TrackSlot,
};

const RATE: f64 = 48_000.0;

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
    let kinds: Vec<EventKind> = played.iter().map(|m| m.kind).collect();
    assert_eq!(
        kinds,
        [
            EventKind::NoteOn { key: 50, vel: 0.5, ch: 9, attr: Attr::NONE },
            EventKind::NoteOn { key: 52, vel: 0.5, ch: 9, attr: Attr::NONE },
        ],
        "both notes, on the track's channel"
    );
    // A beat at 120 BPM is 500 ms. A frame turned into nanoseconds is
    // rounded down, so the stamps may be some nanoseconds off, never a
    // frame (20 833 ns at 48 kHz).
    let apart = played[1].at - played[0].at;
    assert!(apart.abs_diff(500_000_000) < 1_000, "a beat apart: {apart} ns");
    // Stopped: the held notes end, and the pedal and the wheel go back.
    let kinds: Vec<EventKind> = stopped.iter().map(|m| m.kind).collect();
    assert_eq!(
        kinds,
        [
            EventKind::AllNotesOff,
            EventKind::Control { ctl: Ctl::Cc(64), value: 0.0, ch: 9 },
            EventKind::Control { ctl: Ctl::Bend, value: 0.0, ch: 9 },
        ],
        "the notes ended when the track stopped"
    );
}

/// Through the sequencer, to a port of our own MIDI input.
#[cfg(feature = "midi")]
mod sequencer {
    use std::sync::mpsc::{Receiver, channel};
    use std::sync::{Arc, Mutex};
    use std::time::{Duration, Instant};

    use paw_engine::NoteCtl;
    use paw_engine::midi::{MidiInputs, MidiTarget};
    use paw_engine::midi_out::{MidiOutputs, clock_ns};

    use super::*;

    /// The inputs with a port of ours, `name`, and what arrives there.
    /// `None` where there is no sequencer, as on a build machine.
    fn listen(name: &str) -> Option<(MidiInputs, Receiver<EventKind>)> {
        let (tx, rx) = channel();
        let sink = Arc::new(Mutex::new(MidiTarget {
            engine: None,
            tap: Some(Box::new(move |_, kind| {
                let _ = tx.send(kind);
            })),
        }));
        let inputs = MidiInputs::start(sink).ok()?;
        inputs.open_port(name);
        Some((inputs, rx))
    }

    /// The outputs, once they list the port of our inputs.
    fn outputs(name: &str) -> Option<MidiOutputs> {
        let outputs = MidiOutputs::start().ok()?;
        let deadline = Instant::now() + Duration::from_secs(4);
        while Instant::now() < deadline {
            if outputs.ports().iter().any(|p| p.name == format!("paw: {name}")) {
                return Some(outputs);
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        panic!("the outputs never listed our port");
    }

    /// Messages as they arrive, until `count` of them or a while.
    fn collect(rx: &Receiver<EventKind>, count: usize) -> Vec<EventKind> {
        let mut got = Vec::new();
        let deadline = Instant::now() + Duration::from_secs(5);
        while got.len() < count {
            let left = deadline.saturating_duration_since(Instant::now());
            match rx.recv_timeout(left) {
                Ok(message) => got.push(message),
                Err(_) => break,
            }
        }
        got
    }

    #[test]
    fn a_route_in_mpe_gives_each_note_a_channel_and_its_bend_there() {
        let Some((_inputs, rx)) = listen("Loop C") else {
            eprintln!("skipped: no ALSA sequencer");
            return;
        };
        let outputs = outputs("Loop C").unwrap();
        let (mut tx, queue) = rtrb::RingBuffer::<MidiOut>::new(64);
        outputs.set_queue(queue);
        let port = port_key("paw: Loop C");
        let at = clock_ns() + 50_000_000;
        let form = Form::Mpe(3);
        // A chord on one channel, and the middle note bent a semitone up.
        for kind in [
            EventKind::NoteOn { key: 60, vel: 0.8, ch: 0, attr: Attr::NONE },
            EventKind::NoteOn { key: 64, vel: 0.8, ch: 0, attr: Attr::NONE },
            EventKind::NoteOn { key: 67, vel: 0.8, ch: 0, attr: Attr::NONE },
            EventKind::NoteControl { key: 64, ctl: NoteCtl::Bend, value: 1.0 / 48.0, ch: 0 },
            EventKind::AllNotesOff,
        ] {
            tx.push(MidiOut { at, port, form, kind }).unwrap();
        }
        // The zone's announcement (24 control changes), three notes and a
        // bend, then three note-offs, three All Notes Off and the bend put back.
        let got = collect(&rx, 35);
        let ons: Vec<(u8, u8)> = got
            .iter()
            .filter_map(|kind| match kind {
                EventKind::NoteOn { key, ch, .. } => Some((*key, *ch)),
                _ => None,
            })
            .collect();
        assert_eq!(ons, [(60, 1), (64, 2), (67, 3)], "each note on a member channel of its own");
        let bend = got.iter().find_map(|kind| match kind {
            EventKind::Control { ctl: Ctl::Bend, value, ch: 2 } if *value != 0.0 => Some(*value),
            _ => None,
        });
        let bend = bend.expect("the bent note's channel was bent");
        assert!((bend * 48.0 - 1.0).abs() < 0.01, "a semitone of 48: {bend}");
        // The zone was announced on the manager channel: registered parameter
        // 6, three member channels.
        assert!(
            got.iter().any(|kind| matches!(
                kind,
                EventKind::Control { ctl: Ctl::Cc(6), ch: 0, value } if (*value - paw_engine::ump::unit7(3)).abs() < 1e-9
            )),
            "the MPE configuration message"
        );
        let offs = got.iter().filter(|kind| matches!(kind, EventKind::NoteOff { .. })).count();
        assert_eq!(offs, 3, "all notes off ends each where it was sent");
    }
}
