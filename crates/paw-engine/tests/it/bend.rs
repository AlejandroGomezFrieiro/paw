//! A note's own pitch bend, arriving with the note.

use paw_engine::{Attr, Ctl, Event, EventBuf, EventKind, Io, NoteCtl, ProcessCtx, Registry};

fn rises(events: &[EventKind]) -> usize {
    let registry = Registry::with_builtins();
    let mut synth = registry
        .get("synth")
        .unwrap()
        .create(48000.0, 1024)
        .unwrap()
        .device;
    synth.set_param(0, 0.0);
    let ctx = ProcessCtx::at(48000.0, 120.0, 4, 4, true);
    let mut buf = EventBuf::with_capacity(64);
    for kind in events {
        buf.push(Event {
            frame: 0,
            kind: *kind,
        });
    }
    let (mut count, mut before) = (0, 0.0f32);
    for _ in 0..48 {
        let (mut left, mut right) = (vec![0.0f32; 1000], vec![0.0f32; 1000]);
        synth.process(
            &ctx,
            &mut Io {
                left: &mut left,
                right: &mut right,
                events: &mut buf,
                sidechain: None,
                outputs: &mut [],
            },
        );
        buf.clear();
        for s in left {
            if before < 0.0 && s >= 0.0 {
                count += 1;
            }
            before = s;
        }
    }
    count
}

#[test]
fn a_note_is_bent_by_its_own_controller_and_by_the_wheel() {
    let on = EventKind::NoteOn {
        key: 57,
        vel: 0.8,
        ch: 0,
        attr: Attr::NONE,
    };
    let own = EventKind::NoteControl {
        key: 57,
        ctl: NoteCtl::Bend,
        value: 1.0 / 48.0,
        ch: 0,
    };
    let other = EventKind::NoteControl {
        key: 60,
        ctl: NoteCtl::Bend,
        value: 1.0 / 48.0,
        ch: 0,
    };
    let wheel = EventKind::Control {
        ctl: Ctl::Bend,
        value: 1.0,
        ch: 0,
    };
    assert!((rises(&[on]) as i32 - 220).abs() <= 1);
    assert!(
        (rises(&[on, own]) as i32 - 233).abs() <= 1,
        "{}",
        rises(&[on, own])
    );
    assert!((rises(&[on, other]) as i32 - 220).abs() <= 1);
    assert!((rises(&[wheel, on]) as i32 - 247).abs() <= 1);
}
