//! Tracks processed on several threads: the output is the same, bit for
//! bit, as on one, and a schedule that is wrong does no harm.

use paw_engine::GraphPlan;
use paw_engine::{
    AutoLane, AutoTarget, Automation, ClipSet, Delay, DeviceSlot, Engine, EngineHandle, MAX_BLOCK,
    Msg, Pool, Registry, SchedEntry, Schedule, SendRt, TrackRt, TrackSlot,
};

use crate::common::SR;

fn send(handle: &mut EngineHandle, engine: &mut Engine, msg: Msg) {
    handle.send_while(msg, engine);
}

fn device(kind: &str) -> Box<dyn paw_engine::Device> {
    Registry::with_builtins()
        .get(kind)
        .unwrap()
        .create(SR as f32, MAX_BLOCK)
        .unwrap()
        .device
}

/// Forty tracks of a synth and a delay playing different notes, with volume
/// and pan automation. Most go to one of four buses, which go to the master;
/// some also send to another bus, a few from before their fader and late.
fn project(entries: impl FnOnce(Vec<SchedEntry>) -> Vec<SchedEntry>) -> (Engine, EngineHandle) {
    let (mut engine, mut handle) = Engine::new(SR);
    // As a render: shared between threads whenever that is faster.
    engine.set_offline(true);
    let buses: Vec<TrackSlot> = (1..=4).map(TrackSlot).collect();
    let sources: Vec<TrackSlot> = (5..45).map(TrackSlot).collect();
    let mut next_device = 0;
    let mut list = Vec::new();
    for &slot in sources.iter().chain(&buses) {
        send(
            &mut handle,
            &mut engine,
            Msg::InsertTrack {
                slot,
                track: TrackRt::new(),
            },
        );
        let bus = buses.contains(&slot);
        let kinds: &[&str] = if bus { &["delay"] } else { &["synth", "delay"] };
        let chain: Box<[DeviceSlot]> = kinds
            .iter()
            .map(|kind| {
                let dev = DeviceSlot(next_device);
                next_device += 1;
                send(
                    &mut handle,
                    &mut engine,
                    Msg::InsertDevice {
                        slot: dev,
                        device: device(kind),
                    },
                );
                dev
            })
            .collect();
        send(
            &mut handle,
            &mut engine,
            Msg::SetGraph { slot: slot.into(), plan: GraphPlan::serial(&chain) },
        );
        let i = slot.index();
        if !bus {
            let mut clips = ClipSet::default();
            for step in 0..64 {
                let at = step as f64 * 0.25 + (i % 3) as f64 * 0.01;
                clips.push_note(at, at + 0.2, 36 + ((i * 7 + step * 5) % 48) as u8, 0.7);
            }
            clips.finish();
            send(
                &mut handle,
                &mut engine,
                Msg::SetClips {
                    track: slot,
                    clips: Box::new(clips),
                },
            );
        }
        let lanes = vec![
            AutoLane::new(AutoTarget::Volume, vec![(0.0, -12.0), (8.0, -3.0)]),
            AutoLane::new(AutoTarget::Pan, vec![(0.0, -0.5), (8.0, 0.5)]),
        ];
        send(
            &mut handle,
            &mut engine,
            Msg::SetAutomation {
                track: slot,
                automation: Box::new(Automation { lanes, ..Default::default() }),
            },
        );
        let mut entry = SchedEntry::new(slot, if bus { TrackSlot::MASTER } else { buses[i % 4] });
        if !bus && i.is_multiple_of(5) {
            entry.sends.push(SendRt::new(buses[(i + 1) % 4], 0.3));
        }
        if !bus && i.is_multiple_of(7) {
            entry.sends.push(SendRt {
                pre: true,
                delay: Delay::new(100 + i),
                ..SendRt::new(buses[(i + 2) % 4], 0.5)
            });
            entry.delay = Delay::new(64);
        }
        list.push(entry);
    }
    list.push(SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE));
    send(
        &mut handle,
        &mut engine,
        Msg::SetSchedule(Box::new(Schedule::new(entries(list), 0))),
    );
    send(&mut handle, &mut engine, Msg::SetTempo(140.0));
    send(&mut handle, &mut engine, Msg::Play);
    (engine, handle)
}

/// Two seconds of output, in blocks of uneven sizes.
fn play(engine: &mut Engine) -> Vec<u32> {
    let mut out = Vec::new();
    let (mut left, mut right) = (vec![0.0f32; 700], vec![0.0f32; 700]);
    let mut done = 0;
    let mut size = 0;
    while done < 96000 {
        size = (size * 31 + 97) % 700 + 1;
        engine.process(&mut left[..size], &mut right[..size]);
        for (l, r) in left[..size].iter().zip(&right[..size]) {
            out.push(l.to_bits());
            out.push(r.to_bits());
        }
        done += size;
    }
    out
}

#[test]
fn the_output_does_not_depend_on_the_number_of_threads() {
    let (mut engine, _handle) = project(|entries| entries);
    let alone = play(&mut engine);
    assert!(
        alone.iter().any(|bits| f32::from_bits(*bits).abs() > 0.01),
        "something sounds"
    );
    for threads in [2, 3, 8] {
        let (mut engine, _handle) = project(|entries| entries);
        engine.set_pool(Some(Box::new(Pool::new(threads))));
        assert_eq!(engine.shared().threads(), threads as u32);
        let together = play(&mut engine);
        assert!(alone == together, "{threads} threads give the same samples");
    }
}

#[test]
fn a_pool_can_be_given_and_taken_away_while_playing() {
    let (mut alone, _handle) = project(|entries| entries);
    let (mut engine, mut handle) = project(|entries| entries);
    let block = |engine: &mut Engine| {
        let (mut left, mut right) = (vec![0.0f32; 480], vec![0.0f32; 480]);
        engine.process(&mut left, &mut right);
        (left, right)
    };
    for round in 0..200 {
        if round % 20 == 0 {
            let pool = (round % 40 == 0).then(|| Box::new(Pool::new(4)));
            send(&mut handle, &mut engine, Msg::SetPool(pool));
            handle.collect_garbage();
        }
        let (want, got) = (block(&mut alone), block(&mut engine));
        let same = |a: &[f32], b: &[f32]| a.iter().zip(b).all(|(a, b)| a.to_bits() == b.to_bits());
        assert!(
            same(&want.0, &got.0) && same(&want.1, &got.1),
            "block {round} is the same with and without the pool"
        );
    }
    assert_eq!(handle.shared.leaked(), 0);
}

#[test]
fn a_schedule_that_names_a_track_twice_or_shares_a_device_does_no_harm() {
    // Every source twice over, and all of them through the first bus's
    // delay as well as their own: two threads must never be in one track or
    // one device at once. What comes out is not specified; that it comes
    // out, and is finite, is.
    let (mut engine, mut handle) = project(|mut entries| {
        let again: Vec<SchedEntry> = entries
            .iter()
            .filter(|e| e.slot >= TrackSlot(5))
            .map(|e| SchedEntry::new(e.slot, e.output))
            .collect();
        let master = entries.pop().unwrap();
        entries.extend(again);
        entries.push(master);
        entries
    });
    for slot in 5..45 {
        // Device 0 is the first source's synth.
        let chain: Box<[DeviceSlot]> = Box::new([DeviceSlot(0), DeviceSlot(1)]);
        send(
            &mut handle,
            &mut engine,
            Msg::SetGraph { slot: TrackSlot(slot).into(), plan: GraphPlan::serial(&chain) },
        );
    }
    engine.set_pool(Some(Box::new(Pool::new(8))));
    let out = play(&mut engine);
    assert!(out.iter().all(|bits| f32::from_bits(*bits).is_finite()));
}

#[test]
fn only_a_group_with_enough_work_is_shared_between_threads() {
    // Forty synths and delays: worth sharing out.
    let (mut engine, _handle) = project(|entries| entries);
    engine.set_pool(Some(Box::new(Pool::new(4))));
    play(&mut engine);
    assert!(
        engine.shared().shared_groups() > 0,
        "forty busy tracks are shared out"
    );

    // Four tracks with nothing on them, live: waking the other threads
    // would cost more than the work.
    let (mut engine, mut handle) = Engine::new(SR);
    let mut list = Vec::new();
    for slot in (1..=4).map(TrackSlot) {
        let track = TrackRt::new();
        send(&mut handle, &mut engine, Msg::InsertTrack { slot, track });
        list.push(SchedEntry::new(slot, TrackSlot::MASTER));
    }
    list.push(SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE));
    let schedule = Box::new(Schedule::new(list, 0));
    send(&mut handle, &mut engine, Msg::SetSchedule(schedule));
    send(&mut handle, &mut engine, Msg::Play);
    engine.set_pool(Some(Box::new(Pool::new(4))));
    let (mut left, mut right) = (vec![0.0f32; 256], vec![0.0f32; 256]);
    for _ in 0..2000 {
        engine.process(&mut left, &mut right);
    }
    assert!(
        engine.shared().shared_groups() < 10,
        "{} of 2000 blocks shared four empty tracks out",
        engine.shared().shared_groups()
    );
}
