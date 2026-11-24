//! MIDI input through the sequencer, from a client of our own on the same
//! machine: MIDI 2.0 packets arrive whole, and MIDI 1.0 events arrive as
//! the same events with less detail.
//!
//! The sequencer is shared by every process of the machine, and other
//! tests send to it at the same time. So the inputs here open no port but
//! the test's own: they start with none selected, and then select the
//! sender of the test by its address, which is that client's alone.
#![cfg(feature = "midi")]
#![cfg_attr(test, expect(clippy::cast_lossless, reason = "debt: pay down"))]
#![cfg_attr(test, expect(clippy::cast_possible_truncation, reason = "debt: pay down"))]
#![cfg_attr(test, expect(clippy::cast_sign_loss, reason = "debt: pay down"))]

use std::ffi::c_int;
use std::sync::mpsc::{Receiver, channel};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use alsa_sys::*;
use paw_engine::midi::{MidiInputs, MidiTarget};
use paw_types::{Attr, Ctl, EventKind, NoteCtl, ump};

/// A sequencer client with one port that others can read from.
struct Sender {
    seq: *mut snd_seq_t,
    port: c_int,
}

impl Sender {
    /// `None` where there is no sequencer to open, as on a build machine.
    fn open(name: &std::ffi::CStr, midi2: bool) -> Option<Self> {
        // SAFETY: `seq` is a live out-pointer and is used only once it is
        // open; the names are C strings that outlive the calls.
        unsafe {
            let mut seq = std::ptr::null_mut();
            if snd_seq_open(&raw mut seq, c"default".as_ptr(), 1, 0) < 0 {
                return None;
            }
            snd_seq_set_client_name(seq, name.as_ptr());
            if midi2 && snd_seq_set_client_midi_version(seq, 2) < 0 {
                snd_seq_close(seq);
                return None;
            }
            // Readable, and open to subscriptions.
            let port =
                snd_seq_create_simple_port(seq, c"out".as_ptr(), 1 | 1 << 5, 1 << 1 | 1 << 20);
            (port >= 0).then_some(Self { seq, port })
        }
    }

    fn address(&self) -> String {
        // SAFETY: a `Sender` holds an open handle until it is dropped.
        let client = unsafe { snd_seq_client_id(self.seq) };
        format!("{client}:{}", self.port)
    }

    /// Send a Universal MIDI Packet to whoever is subscribed.
    fn packet(&self, words: [u32; 2]) {
        // SAFETY: the handle is open; all zeros is a valid (empty) event of
        // plain integers, and the call only reads it.
        unsafe {
            let mut ev: snd_seq_ump_event_t = std::mem::zeroed();
            ev.flags = 1 << 5;
            ev.queue = 253;
            ev.source.port = self.port as u8;
            ev.dest.client = 254;
            ev.dest.port = 253;
            ev.__bindgen_anon_1.ump = [words[0], words[1], 0, 0];
            assert!(snd_seq_ump_event_output_direct(self.seq, &raw mut ev) >= 0);
        }
    }

    /// Send a MIDI 1.0 event to whoever is subscribed.
    fn legacy(&self, type_: u32, fill: impl FnOnce(&mut snd_seq_event_data_t)) {
        // SAFETY: as in `packet`.
        unsafe {
            let mut ev: snd_seq_event_t = std::mem::zeroed();
            ev.type_ = type_ as u8;
            ev.queue = 253;
            ev.source.port = self.port as u8;
            ev.dest.client = 254;
            ev.dest.port = 253;
            fill(&mut ev.data);
            assert!(snd_seq_event_output_direct(self.seq, &raw mut ev) >= 0);
        }
    }
}

impl Sender {
    /// Send a MIDI 1.0 event to one port of another client.
    fn legacy_to(
        &self,
        dest: (c_int, c_int),
        type_: u32,
        fill: impl FnOnce(&mut snd_seq_event_data_t),
    ) {
        // SAFETY: as in `packet`.
        unsafe {
            let mut ev: snd_seq_event_t = std::mem::zeroed();
            ev.type_ = type_ as u8;
            ev.queue = 253;
            ev.source.port = self.port as u8;
            ev.dest.client = dest.0 as u8;
            ev.dest.port = dest.1 as u8;
            fill(&mut ev.data);
            assert!(snd_seq_event_output_direct(self.seq, &raw mut ev) >= 0);
        }
    }
}

impl Drop for Sender {
    fn drop(&mut self) {
        // SAFETY: the handle is open and owned by this `Sender` alone.
        unsafe {
            snd_seq_close(self.seq);
        }
    }
}

/// The inputs, open to no port yet, and what they hear.
fn listen() -> Option<(MidiInputs, Receiver<EventKind>)> {
    let (tx, rx) = channel();
    let sink = Arc::new(Mutex::new(MidiTarget {
        engine: None,
        tap: Some(Box::new(move |_, kind| {
            let _ = tx.send(kind);
        })),
    }));
    MidiInputs::start(sink, Some(Vec::new()))
        .ok()
        .map(|inputs| (inputs, rx))
}

/// Open the inputs to this port alone, and wait until they have.
fn opened(inputs: &MidiInputs, address: &str) -> bool {
    inputs.select(Some(vec![address.to_string()]));
    let deadline = Instant::now() + Duration::from_secs(3);
    while Instant::now() < deadline {
        if inputs.ports().iter().any(|p| p.id == address && p.open) {
            return true;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    false
}

/// The next message that `wanted` takes; the sender sends others too.
fn next(rx: &Receiver<EventKind>, wanted: impl Fn(&EventKind) -> bool) -> EventKind {
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        match rx.recv_timeout(left) {
            Ok(kind) if wanted(&kind) => return kind,
            Ok(_) => {}
            Err(_) => panic!("the message did not arrive"),
        }
    }
}

/// What a MIDI 2.0 client sends arrives with nothing lost.
fn packets(inputs: &MidiInputs, rx: &Receiver<EventKind>, modern: &Sender) {
    assert!(
        opened(inputs, &modern.address()),
        "the new port was not opened"
    );

    // A note on an unusual key, so that nothing else is mistaken for it.
    let note = EventKind::NoteOn {
        key: 113,
        vel: 0.5,
        ch: 5,
        attr: Attr::NONE,
    };
    modern.packet(ump::encode(0, note).unwrap());
    let EventKind::NoteOn { vel, ch, .. } =
        next(rx, |k| matches!(k, EventKind::NoteOn { key: 113, .. }))
    else {
        unreachable!()
    };
    assert_eq!(ch, 5);
    assert!(
        (vel - 0.5).abs() < 1e-4,
        "sixteen bits of velocity, got {vel}"
    );

    // A controller with all 32 bits of its value.
    modern.packet([0x40b5_4a00, 0x1234_5678]);
    let got = next(rx, |k| {
        matches!(
            k,
            EventKind::Control {
                ctl: Ctl::Cc(74),
                ch: 5,
                ..
            }
        )
    });
    let EventKind::Control { value, .. } = got else {
        unreachable!()
    };
    assert!(
        (value - 0x1234_5678u32 as f64 / u32::MAX as f64).abs() < 1e-12,
        "got {value}"
    );

    // A note's own pitch bend, which MIDI 1.0 cannot say.
    let bend = EventKind::NoteControl {
        key: 113,
        ctl: NoteCtl::Bend,
        value: 0.25,
        ch: 5,
    };
    modern.packet(ump::encode(0, bend).unwrap());
    let got = next(rx, |k| {
        matches!(
            k,
            EventKind::NoteControl {
                key: 113,
                ctl: NoteCtl::Bend,
                ..
            }
        )
    });
    let EventKind::NoteControl { value, .. } = got else {
        unreachable!()
    };
    assert!((value - 0.25).abs() < 1e-9, "got {value}");
}

#[test]
fn midi_2_packets_arrive_whole_and_midi_1_events_as_the_same_events() {
    let Some((inputs, rx)) = listen() else {
        eprintln!("skipped: no ALSA sequencer here");
        return;
    };
    // MIDI 2.0 needs a sequencer built for it (the kernel's SND_SEQ_UMP).
    // Without one, the ports are MIDI 1.0 and only that half can be tried.
    match Sender::open(c"paw-test-midi2", true) {
        Some(modern) => packets(&inputs, &rx, &modern),
        None => eprintln!("MIDI 2.0 part skipped: this system's sequencer has no UMP"),
    }

    // A MIDI 1.0 device: the same events, from seven and fourteen bits.
    let old = Sender::open(c"paw-test-midi1", false).expect("a second client");
    assert!(opened(&inputs, &old.address()));
    old.legacy(SND_SEQ_EVENT_NOTEON, |data| {
        data.note = snd_seq_ev_note {
            channel: 6,
            note: 114,
            velocity: 96,
            off_velocity: 0,
            duration: 0,
        };
    });
    let EventKind::NoteOn { vel, ch, .. } =
        next(&rx, |k| matches!(k, EventKind::NoteOn { key: 114, .. }))
    else {
        unreachable!()
    };
    assert_eq!(ch, 6);
    assert!(
        (vel - ump::velocity7(96)).abs() < 1e-4,
        "96 of 127, widened: got {vel}"
    );
    old.legacy(SND_SEQ_EVENT_PITCHBEND, |data| {
        data.control = snd_seq_ev_ctrl {
            channel: 6,
            unused: [0; 3],
            param: 0,
            value: 8191,
        };
    });
    let got = next(&rx, |k| {
        matches!(
            k,
            EventKind::Control {
                ctl: Ctl::Bend,
                ch: 6,
                ..
            }
        )
    });
    let EventKind::Control { value, .. } = got else {
        unreachable!()
    };
    assert!(
        (value - 1.0).abs() < 1e-6,
        "the wheel at its top is 1, got {value}"
    );
    old.legacy(SND_SEQ_EVENT_CONTROLLER, |data| {
        data.control = snd_seq_ev_ctrl {
            channel: 6,
            unused: [0; 3],
            param: 64,
            value: 127,
        };
    });
    let got = next(&rx, |k| {
        matches!(
            k,
            EventKind::Control {
                ctl: Ctl::Cc(64),
                ch: 6,
                ..
            }
        )
    });
    let EventKind::Control { value, .. } = got else {
        unreachable!()
    };
    assert!(
        (value - 1.0).abs() < 1e-9,
        "the pedal down is 1, got {value}"
    );

    // A port that goes away lets go of the keys it held.
    drop(old);
    let got = next(&rx, |k| matches!(k, EventKind::NoteOff { key: 114, .. }));
    assert_eq!(got, EventKind::NoteOff { key: 114, ch: 6 });
}

/// Wait for something to be true of the inputs' ports.
fn ports_settle(inputs: &MidiInputs, done: impl Fn(&[paw_engine::midi::PortInfo]) -> bool) -> bool {
    let deadline = Instant::now() + Duration::from_secs(3);
    while Instant::now() < deadline {
        if done(&inputs.ports()) {
            return true;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    false
}

#[test]
fn what_arrives_at_a_port_of_our_own_goes_by_that_ports_name() {
    let (tx, mut rx) = rtrb::RingBuffer::<(u32, EventKind)>::new(256);
    let sink = Arc::new(Mutex::new(MidiTarget {
        engine: Some(tx),
        tap: None,
    }));
    // No port but our own: the note comes from our sender alone.
    let Ok(inputs) = MidiInputs::start(sink, Some(Vec::new())) else {
        eprintln!("skipped: no ALSA sequencer here");
        return;
    };
    let name = format!("Guitar test {}", std::process::id());
    inputs.open_port(&name);
    inputs.open_port(&name);
    assert!(
        ports_settle(&inputs, |ports| ports
            .iter()
            .any(|p| p.own && p.open && p.name == name)),
        "the port is listed among the inputs"
    );
    let ports = inputs.ports();
    assert_eq!(
        ports.iter().filter(|p| p.name == name).count(),
        1,
        "opening it twice makes one port"
    );
    let own = ports.iter().find(|p| p.name == name).unwrap();
    let (client, port) = own.id.split_once(':').unwrap();
    let dest: (c_int, c_int) = (client.parse().unwrap(), port.parse().unwrap());

    // Another program sends a note straight to that port.
    let sender = Sender::open(c"paw-test-own", false).unwrap();
    sender.legacy_to(dest, SND_SEQ_EVENT_NOTEON, |data| {
        data.note.channel = 2;
        data.note.note = 101;
        data.note.velocity = 90;
    });
    let key = paw_engine::midi::port_key(&name);
    let deadline = Instant::now() + Duration::from_secs(3);
    let mut heard = None;
    while heard.is_none() && Instant::now() < deadline {
        match rx.pop() {
            Ok((from, EventKind::NoteOn { key: 101, ch, .. })) => heard = Some((from, ch)),
            Ok(_) => {}
            Err(_) => std::thread::sleep(Duration::from_millis(5)),
        }
    }
    assert_eq!(
        heard,
        Some((key, 2)),
        "the note goes with the key of the port's name"
    );

    // Closing the port releases the note still held on it.
    inputs.close_port(&name);
    let deadline = Instant::now() + Duration::from_secs(3);
    let mut released = false;
    while !released && Instant::now() < deadline {
        match rx.pop() {
            Ok((from, EventKind::NoteOff { key: 101, ch: 2 })) => released = from == key,
            Ok(_) => {}
            Err(_) => std::thread::sleep(Duration::from_millis(5)),
        }
    }
    assert!(released, "a note held on a closed port is released");
    assert!(
        ports_settle(&inputs, |ports| !ports.iter().any(|p| p.name == name)),
        "and the port is gone"
    );
}
