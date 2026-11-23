//! Devices at rest sleep through silent blocks: the output is the same, bit
//! for bit, as when every device runs every block, and they do sleep. When
//! the song is stopped and nothing sounds, the whole engine rests.

use paw_engine::host::HostPath;
use paw_engine::launch::{Launch, Quantize, Target};
use paw_engine::{
    Attr, ClipSet, DeviceSlot, Engine, EngineHandle, EventKind, MAX_BLOCK, Msg, Registry,
    SchedEntry, Schedule, SendRt, TrackRt, TrackSlot,
};

use crate::common::SR;

fn send(handle: &mut EngineHandle, engine: &mut Engine, msg: Msg) {
    handle.send_while(msg, engine);
}

/// Instruments and effects on four tracks and a bus, playing two bars,
/// then nothing for long enough that every tail dies away, then two bars
/// again. Around some devices the host mixes wet and dry with a latency,
/// and one is bypassed.
fn project(sleep: bool) -> (Engine, EngineHandle) {
    let (mut engine, mut handle) = Engine::new(SR);
    engine.set_sleep(sleep);
    let registry = Registry::with_builtins();
    let chains: [(u32, &[&str]); 5] = [
        (1, &["synth", "delay", "eq"]),
        (2, &["drums", "chorus", "utility"]),
        (3, &["synth", "phaser", "tremolo", "gain"]),
        (4, &["synth", "flanger"]),
        (5, &["reverb", "delay"]),
    ];
    let mut next = 0;
    let mut list = Vec::new();
    for (n, kinds) in chains {
        let slot = TrackSlot(n);
        send(
            &mut handle,
            &mut engine,
            Msg::InsertTrack {
                slot,
                track: TrackRt::new(),
            },
        );
        let mut chain = Vec::new();
        for kind in kinds {
            let factory = registry.get(kind).unwrap();
            let device = factory.create(SR as f32, MAX_BLOCK).unwrap().device;
            let dev = DeviceSlot(next);
            next += 1;
            send(
                &mut handle,
                &mut engine,
                Msg::InsertDevice { slot: dev, device },
            );
            if dev.0 % 3 == 1 {
                // Half wet, and the dry signal held back 9000 frames: longer than
                // some devices take to come to rest.
                let base = factory.info().params.len() as u32;
                let path = Box::new(HostPath::new(base, 9000, MAX_BLOCK));
                send(&mut handle, &mut engine, Msg::SetHost { device: dev, path });
                let wet = Msg::SetParam {
                    device: dev,
                    param: base,
                    value: 50.0,
                };
                send(&mut handle, &mut engine, wet);
            }
            if dev.0 == 5 {
                let bypass = Msg::SetBypass {
                    device: dev,
                    bypass: true,
                };
                send(&mut handle, &mut engine, bypass);
            }
            chain.push(dev);
        }
        send(
            &mut handle,
            &mut engine,
            Msg::SetChain {
                track: slot,
                chain: chain.into(),
            },
        );
        if n < 5 {
            let mut clips = ClipSet::default();
            for bars in [0.0, 64.0] {
                for step in 0..32 {
                    let at = bars + step as f64 * 0.25;
                    let key = 36 + ((n as usize * 7 + step * 5) % 40) as u8;
                    clips.push_note(at, at + 0.2, key, 0.8);
                }
            }
            clips.finish();
            let clips = Box::new(clips);
            send(&mut handle, &mut engine, Msg::SetClips { track: slot, clips });
        }
        let mut entry = SchedEntry::new(slot, if n < 5 { TrackSlot(5) } else { TrackSlot::MASTER });
        if n == 1 {
            entry.sends.push(SendRt::new(TrackSlot::MASTER, 0.5));
        }
        list.push(entry);
    }
    list.push(SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE));
    let schedule = Box::new(Schedule::new(list, 0));
    send(&mut handle, &mut engine, Msg::SetSchedule(schedule));
    send(&mut handle, &mut engine, Msg::SetTempo(120.0));
    send(&mut handle, &mut engine, Msg::Play);
    (engine, handle)
}

/// Seventy-two beats (36 seconds) of output, in blocks of uneven sizes,
/// and the meters of every track after each block.
fn play(engine: &mut Engine) -> Vec<u32> {
    let mut out = Vec::new();
    let (mut left, mut right) = (vec![0.0f32; 700], vec![0.0f32; 700]);
    let (mut done, mut size) = (0, 0);
    while done < 36 * 48000 {
        size = (size * 31 + 97) % 700 + 1;
        engine.process(&mut left[..size], &mut right[..size]);
        for (l, r) in left[..size].iter().zip(&right[..size]) {
            out.push(l.to_bits());
            out.push(r.to_bits());
        }
        for slot in 0..6 {
            let (l, r) = engine.shared().meter(TrackSlot(slot));
            out.push(l.to_bits());
            out.push(r.to_bits());
        }
        done += size;
    }
    out
}

#[test]
fn devices_that_sleep_sound_the_same() {
    let (mut awake, _a) = project(false);
    let (mut asleep, _b) = project(true);
    let want = play(&mut awake);
    let got = play(&mut asleep);
    assert!(
        want.iter().any(|bits| f32::from_bits(*bits).abs() > 0.01),
        "something sounds"
    );
    let first = want.iter().zip(&got).position(|(a, b)| a != b);
    assert!(first.is_none(), "the output differs from value {first:?} on");
    let (runs, sleeps) = awake.shared().device_blocks();
    assert_eq!(sleeps, 0, "with sleep off, every device runs");
    assert!(runs > 0);
    let (runs, sleeps) = asleep.shared().device_blocks();
    assert!(
        sleeps > runs,
        "through the long silence most devices sleep: {runs} runs, {sleeps} sleeps"
    );
}

#[test]
fn sleep_can_be_turned_off_and_on_while_playing() {
    let (mut awake, _a) = project(false);
    let (mut engine, mut handle) = project(true);
    let block = |engine: &mut Engine| {
        let (mut left, mut right) = (vec![0.0f32; 512], vec![0.0f32; 512]);
        engine.process(&mut left, &mut right);
        left.into_iter().chain(right).map(f32::to_bits).collect::<Vec<_>>()
    };
    for round in 0..3375 {
        if round % 400 == 0 {
            send(&mut handle, &mut engine, Msg::SetSleep(round % 800 != 0));
        }
        assert!(
            block(&mut awake) == block(&mut engine),
            "block {round} is the same"
        );
    }
}

/// A stopped engine with a track for each chain, each into the master.
fn stopped(sleep: bool, chains: &[&[&str]]) -> (Engine, EngineHandle) {
    let (mut engine, mut handle) = Engine::new(SR);
    engine.set_sleep(sleep);
    let registry = Registry::with_builtins();
    let mut list = Vec::new();
    let mut next = 0;
    for (n, kinds) in chains.iter().enumerate() {
        let slot = TrackSlot(n as u32 + 1);
        let track = TrackRt::new();
        send(&mut handle, &mut engine, Msg::InsertTrack { slot, track });
        let mut chain = Vec::new();
        for kind in kinds.iter() {
            let factory = registry.get(kind).unwrap();
            let device = factory.create(SR as f32, MAX_BLOCK).unwrap().device;
            let dev = DeviceSlot(next);
            next += 1;
            send(&mut handle, &mut engine, Msg::InsertDevice { slot: dev, device });
            chain.push(dev);
        }
        let chain = chain.into();
        send(&mut handle, &mut engine, Msg::SetChain { track: slot, chain });
        list.push(SchedEntry::new(slot, TrackSlot::MASTER));
    }
    list.push(SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE));
    let schedule = Box::new(Schedule::new(list, 0));
    send(&mut handle, &mut engine, Msg::SetSchedule(schedule));
    (engine, handle)
}

/// One callback of 512 frames, with a channel of input: left, then right.
fn block_with(engine: &mut Engine, input: &[f32]) -> Vec<f32> {
    let (mut left, mut right) = (vec![0.0f32; 512], vec![0.0f32; 512]);
    engine.process_input(input, usize::from(!input.is_empty()), &mut left, &mut right);
    left.into_iter().chain(right).collect()
}

fn block(engine: &mut Engine) -> Vec<f32> {
    block_with(engine, &[])
}

fn note(on: bool) -> EventKind {
    if on {
        EventKind::NoteOn {
            key: 60,
            vel: 0.9,
            ch: 0,
            attr: Attr::NONE,
        }
    } else {
        EventKind::NoteOff { key: 60, ch: 0 }
    }
}

#[test]
fn a_stopped_engine_with_nothing_to_sound_rests() {
    let (mut engine, mut h) = stopped(true, &[&["synth"][..]; 64]);
    // A launch while stopped happens at once: it does not keep the engine
    // awake after that.
    let launch = Launch {
        track: TrackSlot(1),
        target: Target::Arrangement,
        quantize: Quantize::Off,
        legato: false,
        from: None,
    };
    send(&mut h, &mut engine, Msg::Launch(Box::new([launch])));
    for _ in 0..16 {
        block(&mut engine);
    }
    let shared = engine.shared().clone();
    for _ in 0..10 {
        let (rests, (runs, _)) = (shared.engine_rests(), shared.device_blocks());
        assert!(block(&mut engine).iter().all(|s| *s == 0.0));
        assert_eq!(shared.engine_rests(), rests + 1, "the engine rests each block");
        assert_eq!(shared.device_blocks().0, runs, "and no device runs");
    }
}

#[test]
fn a_note_that_comes_while_the_engine_rests_sounds_in_the_same_block() {
    let (mut awake, mut a) = stopped(false, &[&["synth"]]);
    let (mut rested, mut r) = stopped(true, &[&["synth"]]);
    for _ in 0..16 {
        block(&mut awake);
        block(&mut rested);
    }
    assert!(rested.shared().engine_rests() > 0, "the engine rests");
    let live = || Msg::Live {
        track: TrackSlot(1),
        event: note(true),
    };
    send(&mut a, &mut awake, live());
    send(&mut r, &mut rested, live());
    let first = |b: Vec<f32>| b.iter().position(|s| *s != 0.0);
    let want = first(block(&mut awake));
    assert!(want.is_some(), "the note sounds");
    assert_eq!(first(block(&mut rested)), want);
}

/// Each block of an engine with sleep on is the same as with it off, from
/// `setup` on, and the engine does not rest while `awake` says so.
fn sounds_in_full(
    chains: &[&[&str]],
    blocks: usize,
    input: &[f32],
    setup: impl Fn(&mut Engine, &mut EngineHandle),
) -> Engine {
    let (mut awake, mut a) = stopped(false, chains);
    let (mut engine, mut h) = stopped(true, chains);
    setup(&mut awake, &mut a);
    setup(&mut engine, &mut h);
    for round in 0..blocks {
        let want = block_with(&mut awake, input);
        assert!(block_with(&mut engine, input) == want, "block {round} is the same");
    }
    engine
}

#[test]
fn a_ringing_reverb_keeps_the_engine_awake() {
    let reverb = DeviceSlot(1);
    let (mut engine, mut h) = stopped(true, &[&["synth", "reverb"]]);
    let (mut awake, mut a) = stopped(false, &[&["synth", "reverb"]]);
    for (engine, h) in [(&mut engine, &mut h), (&mut awake, &mut a)] {
        let track = TrackSlot(1);
        send(h, engine, Msg::Live { track, event: note(true) });
        for _ in 0..20 {
            block(engine);
        }
        send(h, engine, Msg::Live { track, event: note(false) });
    }
    let shared = engine.shared().clone();
    let (mut last_run, mut first_rest) = (0, None);
    for round in 0..2000 {
        let (rests, ran) = (shared.engine_rests(), shared.device_processed(reverb));
        assert!(block(&mut awake) == block(&mut engine), "block {round} is the same");
        if shared.device_processed(reverb) > ran {
            last_run = round;
        }
        if shared.engine_rests() > rests {
            first_rest.get_or_insert(round);
        }
    }
    let first_rest = first_rest.expect("the engine rests once the tail has died away");
    assert!(first_rest > last_run, "it rests after the reverb's last run ({last_run})");
}

#[test]
fn a_device_that_never_sleeps_keeps_the_engine_awake() {
    let engine = sounds_in_full(&[&["compressor"]], 100, &[], |_, _| {});
    assert_eq!(engine.shared().engine_rests(), 0);
}

#[test]
fn a_monitored_input_keeps_the_engine_awake() {
    let silent = [0.0f32; 512];
    let engine = sounds_in_full(&[&[]], 100, &silent, |engine, h| {
        let input = Msg::SetInput {
            track: TrackSlot(1),
            first: 0,
            channels: 1,
            monitor: true,
            armed: false,
        };
        send(h, engine, input);
    });
    assert_eq!(engine.shared().engine_rests(), 0);
}

#[test]
fn a_count_in_keeps_the_engine_awake() {
    // Four clicks half a second apart: much more than eight blocks of
    // silence between them.
    let engine = sounds_in_full(&[&["synth"]], 180, &[], |engine, h| {
        let count = Msg::CountIn {
            frames: 96000,
            every: 24000.0,
            clicks: 4,
            per_bar: 4,
        };
        send(h, engine, count);
    });
    assert_eq!(engine.shared().engine_rests(), 0);
}
