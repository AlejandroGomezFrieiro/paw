//! Devices at rest sleep through silent blocks: the output is the same, bit
//! for bit, as when every device runs every block, and they do sleep.

use paw_engine::host::HostPath;
use paw_engine::{
    ClipSet, DeviceSlot, Engine, EngineHandle, MAX_BLOCK, Msg, Registry, SchedEntry,
    Schedule, SendRt, TrackRt, TrackSlot,
};

const SR: f64 = 48000.0;

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
