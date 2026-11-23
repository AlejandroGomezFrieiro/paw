//! The transport that devices see on a part with a time of its own (a
//! subproject's part): its bars from 1 at the start of the block that
//! plays, at the song's tempo there. A song part sees the song's bars.

use std::sync::{Arc, Mutex};

use paw_engine::GraphPlan;
use paw_engine::{
    Device, DeviceSlot, Engine, Io, LocalTime, Msg, Place, ProcessCtx, SchedEntry, Schedule,
    PartRt, PartSlot,
};
use paw_types::{SigPoint, TempoMap, TempoPoint};

use crate::common::{SR, send};

/// A device that keeps the transport of the first block it is given.
struct Recorder(Arc<Mutex<Option<ProcessCtx>>>);

impl Device for Recorder {
    fn process(&mut self, ctx: &ProcessCtx, _io: &mut Io) {
        let mut seen = self.0.lock().unwrap();
        if seen.is_none() {
            *seen = Some(*ctx);
        }
    }
    fn set_param(&mut self, _index: u32, _value: f32) {}
}

/// What a recorder on part 1 (with `local`) and one on part 2 (the
/// song's time) see of the block that starts at song beat `from`, with
/// the song at 180 bpm and 66 bpm from bar 33 (beat 128), in 4/4.
fn seen(local: LocalTime, from: f64) -> (ProcessCtx, ProcessCtx) {
    let (mut engine, mut handle) = Engine::new(SR);
    let map = TempoMap::new(
        &[
            TempoPoint { beat: 0.0, bpm: 180.0, ramp: false },
            TempoPoint { beat: 128.0, bpm: 66.0, ramp: false },
        ],
        &[SigPoint { beat: 0.0, num: 4, den: 4 }],
    );
    let (inside, song) = (Arc::new(Mutex::new(None)), Arc::new(Mutex::new(None)));
    for msg in [
        Msg::SetTempoMap(Box::new(map)),
        Msg::InsertPart { slot: PartSlot(1), part: PartRt::new() },
        Msg::InsertPart { slot: PartSlot(2), part: PartRt::new() },
        Msg::InsertDevice { slot: DeviceSlot(0), device: Box::new(Recorder(inside.clone())) },
        Msg::InsertDevice { slot: DeviceSlot(1), device: Box::new(Recorder(song.clone())) },
        Msg::SetGraph { slot: PartSlot(1).into(), plan: GraphPlan::serial(&[DeviceSlot(0)]) },
        Msg::SetGraph { slot: PartSlot(2).into(), plan: GraphPlan::serial(&[DeviceSlot(1)]) },
        Msg::SetLocalTime { part: PartSlot(1), time: Some(Box::new(local)) },
        Msg::SetSchedule(Box::new(Schedule::new(
            vec![
                SchedEntry::new(PartSlot(1), PartSlot::MASTER),
                SchedEntry::new(PartSlot(2), PartSlot::MASTER),
                SchedEntry::new(PartSlot::MASTER, PartSlot::NONE),
            ],
            0,
        ))),
        Msg::Seek(from),
        Msg::Play,
    ] {
        send(&mut handle, msg);
    }
    let (mut l, mut r) = (vec![0.0; 256], vec![0.0; 256]);
    engine.process(&mut l, &mut r);
    let inside = inside.lock().unwrap().expect("the device on the subproject's part ran");
    let song = song.lock().unwrap().expect("the device on the song's part ran");
    (inside, song)
}

/// A block of a subproject at song bar 33: its devices see bar 1, beat 0,
/// at the song's tempo there; a song part's devices see bar 33.
#[test]
fn a_device_in_a_subproject_sees_its_bars_and_the_songs_tempo() {
    let blocks = vec![
        Place { from: 32.0, to: 64.0, zero: 32.0 },
        Place { from: 128.0, to: 160.0, zero: 128.0 },
    ];
    let (inside, song) = seen(LocalTime::new(blocks, &[]), 128.0);
    assert_eq!((inside.bar, inside.position, inside.bar_start), (0, 0.0, 0.0), "bar 1, beat 0");
    assert_eq!(inside.tempo, 66.0, "the song's tempo at bar 33");
    assert!(inside.seconds.abs() < 1e-9, "its seconds from its start");
    assert_eq!((song.bar, song.position, song.tempo), (32, 128.0, 66.0), "the song part: bar 33");
    // Inside the block, two bars on; and a meter of its own, in 6/8.
    let (inside, _) = seen(LocalTime::new(vec![Place { from: 128.0, to: 160.0, zero: 128.0 }], &[]), 136.0);
    assert_eq!((inside.bar, inside.position), (2, 8.0), "bar 3 of the block");
    let six = [SigPoint { beat: 0.0, num: 6, den: 8 }];
    let (inside, _) = seen(LocalTime::new(vec![Place { from: 128.0, to: 160.0, zero: 128.0 }], &six), 137.0);
    assert_eq!((inside.bar, inside.bar_start, inside.sig_num, inside.sig_den), (3, 9.0, 6, 8), "its own 6/8");
}

/// A block of a subproject with a tempo of its own (132 bpm) at song bar
/// 33, where the song plays 66: its devices see its tempo, and its beats
/// counted at that tempo from the block's start.
#[test]
fn a_device_in_a_subproject_with_its_own_tempo_sees_that_tempo() {
    let block = || LocalTime::new(vec![Place { from: 128.0, to: 160.0, zero: 128.0 }], &[]);
    let own = [TempoPoint { beat: 0.0, bpm: 132.0, ramp: false }];
    // 4 song beats at 66 bpm are 8 of its beats at 132.
    let (inside, _) = seen(block().with_tempo(&own), 132.0);
    assert_eq!(inside.tempo, 132.0, "its own tempo");
    assert!((inside.position - 8.0).abs() < 1e-9, "its beat 8: {}", inside.position);
    assert_eq!(inside.bar, 2, "bar 3 of it");
}
