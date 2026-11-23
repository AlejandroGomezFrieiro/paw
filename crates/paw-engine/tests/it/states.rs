//! State lanes: a device takes each state on the frame of its point, as
//! parameters, a program change or a message, and hears nothing between.

use std::sync::{Arc, Mutex};

use paw_engine::{
    Automation, Device, DeviceSlot, Engine, EngineHandle, Io, Msg, ProcessCtx, SchedEntry, Schedule,
    StateChange, StateLane, TrackRt, TrackSlot,
};
use paw_types::EventKind;

use crate::common::SR;

/// What a device heard, by the song's frame: a parameter, a program, a
/// message (its first byte).
#[derive(Clone, Debug, PartialEq)]
enum Heard {
    Param(u32, f32),
    Program(u8),
    Message(u8),
}

/// A device that writes down what it hears, and on which frame.
struct Ears {
    log: Log,
    /// Frames processed before this block.
    frames: u64,
    params: Vec<(u32, f32)>,
    messages: Vec<(u32, u8)>,
}

impl Device for Ears {
    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        let mut log = self.log.lock().unwrap();
        for (index, value) in self.params.drain(..) {
            log.push((self.frames, Heard::Param(index, value)));
        }
        for (frame, first) in self.messages.drain(..) {
            log.push((self.frames + frame as u64, Heard::Message(first)));
        }
        for event in io.events.as_slice() {
            if let EventKind::Program { program, .. } = event.kind {
                log.push((self.frames + event.frame as u64, Heard::Program(program)));
            }
        }
        self.frames += io.left.len() as u64;
    }

    fn set_param(&mut self, index: u32, value: f32) {
        self.params.push((index, value));
    }

    fn message(&mut self, frame: u32, data: &[u8]) -> bool {
        self.messages.push((frame, data[0]));
        true
    }
}

fn send(handle: &mut EngineHandle, engine: &mut Engine, msg: Msg) {
    handle.send_while(msg, engine);
}

/// What the device heard, with the frame it heard it at.
type Log = Arc<Mutex<Vec<(u64, Heard)>>>;

/// An engine at 120 BPM (24000 frames a beat) with one track whose only
/// device listens, and a lane of states on it.
fn engine(
    points: Vec<(f64, u32)>,
    changes: Vec<StateChange>,
) -> (Engine, EngineHandle, Log) {
    let (mut engine, mut handle) = Engine::new(SR);
    let log = Arc::new(Mutex::new(Vec::new()));
    let track = TrackSlot(1);
    send(
        &mut handle,
        &mut engine,
        Msg::InsertTrack {
            slot: track,
            track: TrackRt::new(),
        },
    );
    let ears = Ears {
        log: log.clone(),
        frames: 0,
        params: Vec::new(),
        messages: Vec::new(),
    };
    send(
        &mut handle,
        &mut engine,
        Msg::InsertDevice {
            slot: DeviceSlot(0),
            device: Box::new(ears),
        },
    );
    send(
        &mut handle,
        &mut engine,
        Msg::SetChain {
            track,
            chain: Box::new([DeviceSlot(0)]),
        },
    );
    let entries = vec![
        SchedEntry::new(track, TrackSlot::MASTER),
        SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE),
    ];
    send(
        &mut handle,
        &mut engine,
        Msg::SetSchedule(Box::new(Schedule::new(entries, 0))),
    );
    send(&mut handle, &mut engine, Msg::SetTempo(120.0));
    let automation = Automation {
        states: vec![StateLane::new(DeviceSlot(0), points, changes)],
        ..Default::default()
    };
    send(
        &mut handle,
        &mut engine,
        Msg::SetAutomation {
            track,
            automation: Box::new(automation),
        },
    );
    (engine, handle, log)
}

fn play(engine: &mut Engine, frames: usize, block: usize) {
    let (mut left, mut right) = (vec![0.0; block], vec![0.0; block]);
    let mut done = 0;
    while done < frames {
        engine.process(&mut left, &mut right);
        done += block;
    }
}

fn change(param: f32, program: Option<u8>, message: Option<u8>) -> StateChange {
    StateChange {
        params: vec![(3, param)].into(),
        program: program.map(|p| (p, None)),
        message: message.map(|m| vec![m].into()),
    }
}

#[test]
fn a_state_lands_on_the_frame_of_its_point() {
    let changes = vec![
        change(0.25, Some(10), Some(1)),
        change(0.5, Some(20), Some(2)),
    ];
    // At beats 1.0 and 2.37: neither is on a block's edge.
    let (mut engine, mut handle, log) = engine(vec![(0.0, 0), (1.0, 1), (2.37, 0)], changes);
    send(&mut handle, &mut engine, Msg::Play);
    play(&mut engine, 24000 * 3, 512);
    let heard = log.lock().unwrap().clone();
    let second = (2.37f64 * 24000.0).round() as u64;
    assert_eq!(
        heard,
        vec![
            // The first state, from the start.
            (0, Heard::Param(3, 0.25)),
            (0, Heard::Message(1)),
            (0, Heard::Program(10)),
            // A message comes on the last frame before its point, the rest on it.
            (23999, Heard::Message(2)),
            (24000, Heard::Param(3, 0.5)),
            (24000, Heard::Program(20)),
            (second - 1, Heard::Message(1)),
            (second, Heard::Param(3, 0.25)),
            (second, Heard::Program(10)),
        ],
        "each state once, on its frame"
    );
}

#[test]
fn a_state_is_given_again_when_the_song_starts_again() {
    let changes = vec![change(0.25, None, Some(1)), change(0.5, None, None)];
    let (mut engine, mut handle, log) = engine(vec![(0.0, 0), (4.0, 1)], changes);
    send(&mut handle, &mut engine, Msg::Play);
    play(&mut engine, 4096, 256);
    send(&mut handle, &mut engine, Msg::Stop);
    play(&mut engine, 4096, 256);
    let heard_before = log.lock().unwrap().len();
    assert_eq!(heard_before, 2, "the first state, once");
    send(&mut handle, &mut engine, Msg::Play);
    play(&mut engine, 1024, 256);
    let heard = log.lock().unwrap().clone();
    assert_eq!(heard.len(), 4, "again when the song plays again: {heard:?}");
    assert_eq!(heard[2].1, Heard::Param(3, 0.25));
    assert_eq!(heard[3].1, Heard::Message(1));
}
