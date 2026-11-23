//! The audio thread never allocates or frees: checked with a global allocator
//! that counts every allocation and deallocation made while the current
//! thread is marked as the audio thread, across every message the engine
//! takes and every built-in device.

use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use paw_engine::midi_filter::{Control, MidiFilter, Rule};
use paw_engine::record::{AudioCapture, Take, TakeShared};
use paw_engine::{
    Attr, AudioData, AudioRegion, AutoLane, AutoTarget, Automation, ClipSet, Ctl, Delay,
    DeviceSlot, Engine, EngineHandle, EventKind, KeyRt, MAX_BLOCK, Msg, NoteCtl, OutRt, Pool,
    Quality, Registry, SchedEntry, Schedule, SendRt, StateChange, StateLane, Switch, TrackRt,
    TrackSlot,
};

// Not `assert_no_alloc`: it forbids only inside a closure and counts on the
// thread that broke the rule, so it cannot mark the pool's workers for good and
// count what they do while the engine plays on them ("playback on four threads").
struct Guard;

thread_local! {
    static AUDIO: Cell<bool> = const { Cell::new(false) };
}
static VIOLATIONS: AtomicUsize = AtomicUsize::new(0);

fn audio() -> bool {
    let on = AUDIO.try_with(|a| a.get()).unwrap_or(false);
    if on {
        let _ = HERE.try_with(|h| h.set(h.get() + 1));
    }
    on
}

thread_local! {
    /// Violations on this thread alone, for tests that run beside others.
    static HERE: Cell<usize> = const { Cell::new(0) };
}

// SAFETY: every call goes on to `System` with the same arguments, so the
// memory is `System`'s and keeps its guarantees. The counting before it does
// not allocate: the thread-locals are const-initialized `Cell`s without a
// destructor, and the counter is an atomic.
unsafe impl GlobalAlloc for Guard {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        if audio() {
            VIOLATIONS.fetch_add(1, Ordering::Relaxed);
        }
        // SAFETY: the caller's promises for `alloc`, passed on.
        unsafe { System.alloc(layout) }
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        if audio() {
            VIOLATIONS.fetch_add(1, Ordering::Relaxed);
        }
        // SAFETY: the caller's promises for `alloc_zeroed`, passed on.
        unsafe { System.alloc_zeroed(layout) }
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        if audio() {
            VIOLATIONS.fetch_add(1, Ordering::Relaxed);
        }
        // SAFETY: `ptr` came from this allocator with `layout`, so from
        // `System` with it.
        unsafe { System.dealloc(ptr, layout) }
    }
    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        if audio() {
            VIOLATIONS.fetch_add(1, Ordering::Relaxed);
        }
        // SAFETY: as in `dealloc`, and the caller's promise for `new_size`.
        unsafe { System.realloc(ptr, layout, new_size) }
    }
}

#[global_allocator]
static GLOBAL: Guard = Guard;

const SR: f64 = 48000.0;

/// Run `blocks` callbacks of `frames` frames, with `channels` channels of
/// input, as the audio thread, and return how many allocations they made.
fn run(engine: &mut Engine, blocks: usize, frames: usize, channels: usize) -> usize {
    let mut left = vec![0.0f32; frames];
    let mut right = vec![0.0f32; frames];
    let input: Vec<f32> = (0..frames * channels)
        .map(|i| (i as f32 * 0.01).sin())
        .collect();
    let before = VIOLATIONS.load(Ordering::Relaxed);
    AUDIO.with(|a| a.set(true));
    for _ in 0..blocks {
        engine.process_input(&input, channels, &mut left, &mut right);
    }
    AUDIO.with(|a| a.set(false));
    VIOLATIONS.load(Ordering::Relaxed) - before
}

fn send(handle: &mut EngineHandle, msg: Msg) {
    assert!(handle.try_send(msg).is_ok(), "message queue full");
}

fn device(kind: &str) -> Box<dyn paw_engine::Device> {
    Registry::with_builtins()
        .get(kind)
        .unwrap()
        .create(SR as f32, MAX_BLOCK)
        .unwrap()
        .device
}

fn clips(audio: &Arc<AudioData>, notes: usize) -> Box<ClipSet> {
    let mut set = ClipSet::default();
    for i in 0..notes {
        let at = i as f64 * 0.25;
        let key = 36 + (i % 48) as u8;
        // Every other note with an articulation, as MIDI 2.0 has them.
        let attr = match i % 2 {
            0 => Attr::NONE,
            _ => Attr {
                kind: 0x11,
                data: (i % 16) as u16 * 0x1000,
            },
        };
        set.push_note_attr(at, at + 0.5, key, 0.8, attr);
        // Controllers of the channel and of the note, as MIDI 2.0 has them.
        let value = (i % 10) as f64 / 10.0;
        for kind in [
            EventKind::Control {
                ctl: Ctl::Cc(64),
                value,
                ch: 0,
            },
            EventKind::Control {
                ctl: Ctl::Bend,
                value: value - 0.5,
                ch: 0,
            },
            EventKind::NoteControl {
                key,
                ctl: NoteCtl::Bend,
                value: 0.01,
                ch: 0,
            },
            EventKind::Program {
                program: 3,
                bank: Some(1),
                ch: 0,
            },
        ] {
            set.push_event(at + 0.1, kind);
        }
    }
    set.finish();
    // What the instrument is told to play from each beat on (keyswitches
    // and controllers), which playback chases where it starts.
    for i in 0..notes / 4 {
        let from = set.switch_events.len();
        set.switch_events.push(EventKind::NoteOn {
            key: 24 + (i % 4) as u8,
            vel: 0.5,
            ch: 0,
            attr: Attr::NONE,
        });
        set.switch_events.push(EventKind::Control {
            ctl: Ctl::Cc(32),
            value: 0.3,
            ch: 1,
        });
        set.switches.push(Switch {
            beat: i as f64,
            events: from..set.switch_events.len(),
        });
    }
    for i in 0..8 {
        set.audio.push(AudioRegion {
            start: i as f64 * 4.0,
            end: i as f64 * 4.0 + 3.0,
            data: audio.clone(),
            offset: 0.1,
            gain: 0.5,
            fade_in: 0.5,
            fade_out: 0.25,
            declick_in: true,
            declick_out: true,
            hold: Default::default(),
            direction: Default::default(),
        });
    }
    Box::new(set)
}

/// The device of each track that listens to a side-chain: its last.
const KINDS: [&str; 6] = [
    "synth",
    "drums",
    "gain",
    "saturation",
    "delay",
    "compressor",
];
fn keyed_device(track: usize) -> DeviceSlot {
    DeviceSlot((track * KINDS.len() + KINDS.len() - 1) as u32)
}

/// Each track's drum kit, which has further output pairs.
fn kit_device(track: usize) -> DeviceSlot {
    DeviceSlot((track * KINDS.len() + 1) as u32)
}

/// A lane of states on a device: parameters, a program change and a
/// message, at points that blocks end on, inside the loop and across it.
fn state_lane(device: DeviceSlot) -> StateLane {
    let changes = vec![
        StateChange {
            params: vec![(5, 300.0), (6, 0.4)].into(),
            program: Some((7, Some(2))),
            message: Some(vec![1, 2, 3, 4].into()),
        },
        StateChange {
            params: vec![(5, 2000.0)].into(),
            program: None,
            message: Some(vec![5; 64].into()),
        },
        StateChange::default(),
    ];
    let points: Vec<(f64, u32)> = (0..48).map(|i| (i as f64 * 0.37, (i % 3) as u32)).collect();
    StateLane::new(device, points, changes)
}

fn schedule(tracks: &[TrackSlot]) -> Box<Schedule> {
    let mut entries: Vec<SchedEntry> = tracks
        .iter()
        .enumerate()
        .map(|(i, &slot)| {
            // The first track feeds the second, which sends to the third,
            // before its fader and through a delay, as when devices are late.
            let output = if i == 0 { tracks[1] } else { TrackSlot::MASTER };
            let mut entry = SchedEntry::new(slot, output);
            if i == 1 {
                entry.sends.push(SendRt {
                    pre: true,
                    delay: Delay::new(300),
                    ..SendRt::new(tracks[2], 0.5)
                });
                entry.delay = Delay::new(128);
            }
            // The fourth keys a compressor on the fifth, late, and the fifth
            // one on the sixth from before its fader.
            if i == 3 || i == 4 {
                entry.keys.push(KeyRt {
                    device: keyed_device(i + 1),
                    track: tracks[i + 1],
                    pre: i == 4,
                    delay: Delay::new(if i == 3 { 64 } else { 0 }),
                });
            }
            // The fourth's drum kit plays its kick pair into the sixth, late,
            // and its hats into the fifth.
            if i == 3 {
                for (pair, target, delay) in [(0, tracks[5], 32), (2, tracks[4], 0)] {
                    entry.outs.push(OutRt {
                        device: kit_device(i),
                        pair,
                        target,
                        delay: Delay::new(delay),
                    });
                }
            }
            entry
        })
        .collect();
    entries.push(SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE));
    Box::new(Schedule::new(entries, 300))
}

/// Every message, every device, playback with loops, seeks, live notes,
/// MIDI input, monitoring and recording: none of it may allocate on the
/// audio thread.
#[test]
fn the_audio_thread_never_allocates() {
    // The guard itself works: an allocation and a free while marked count.
    let before = VIOLATIONS.load(Ordering::Relaxed);
    AUDIO.with(|a| a.set(true));
    drop(std::hint::black_box(vec![1u8; 16]));
    AUDIO.with(|a| a.set(false));
    assert_eq!(
        VIOLATIONS.load(Ordering::Relaxed) - before,
        2,
        "the guard counts"
    );

    let (mut engine, mut handle) = Engine::new(SR);
    // A source at another rate, so that audio regions are resampled.
    let audio = Arc::new(AudioData {
        sample_rate: 44100,
        channels: [
            (0..44100 * 4)
                .map(|i| (i as f32 * 0.03).sin())
                .collect::<Vec<f32>>()
                .into(),
            (0..44100 * 4)
                .map(|i| (i as f32 * 0.05).sin())
                .collect::<Vec<f32>>()
                .into(),
        ],
    });
    // Three in a chain, and three more beside them that nothing feeds.
    let tracks: Vec<TrackSlot> = (1..=6).map(TrackSlot).collect();
    let kinds = KINDS;
    for (i, &slot) in tracks.iter().enumerate() {
        send(
            &mut handle,
            Msg::InsertTrack {
                slot,
                track: TrackRt::new(),
            },
        );
        for (k, kind) in kinds.iter().enumerate() {
            let dev = DeviceSlot((i * kinds.len() + k) as u32);
            send(
                &mut handle,
                Msg::InsertDevice {
                    slot: dev,
                    device: device(kind),
                },
            );
        }
        let chain: Box<[DeviceSlot]> = (0..kinds.len())
            .map(|k| DeviceSlot((i * kinds.len() + k) as u32))
            .collect();
        send(&mut handle, Msg::SetChain { track: slot, chain });
        // The saturation at 4x (its parameter 2), which edit quality plays
        // without oversampling.
        send(
            &mut handle,
            Msg::SetParam {
                device: DeviceSlot((i * kinds.len() + 3) as u32),
                param: 2,
                value: 1.0,
            },
        );
        // Every other track has a time of its own, as a subproject's track
        // does: its devices see its bars.
        if i % 2 == 1 {
            let blocks = vec![
                paw_engine::Place { from: 0.0, to: 8.0, zero: 0.0 },
                paw_engine::Place { from: 8.0, to: 64.0, zero: 6.0 },
            ];
            let six = [paw_engine::SigPoint { beat: 0.0, num: 6, den: 8 }];
            let time = paw_engine::LocalTime::new(blocks, if i == 3 { &six } else { &[] });
            send(&mut handle, Msg::SetLocalTime { track: slot, time: Some(Box::new(time)) });
        }
        send(
            &mut handle,
            Msg::SetClips {
                track: slot,
                clips: clips(&audio, 400),
            },
        );
        let lanes = vec![
            AutoLane::new(AutoTarget::Volume, vec![(0.0, -12.0), (8.0, 0.0)]),
            AutoLane::new(AutoTarget::Pan, vec![(0.0, -1.0), (8.0, 1.0)]),
            AutoLane::new(
                AutoTarget::Param {
                    device: DeviceSlot((i * kinds.len()) as u32),
                    index: 5,
                },
                vec![(0.0, 200.0), (8.0, 4000.0)],
            ),
        ];
        send(
            &mut handle,
            Msg::SetAutomation {
                track: slot,
                automation: Box::new(Automation {
                    lanes,
                    states: vec![state_lane(DeviceSlot((i * kinds.len()) as u32))],
                }),
            },
        );
        send(
            &mut handle,
            Msg::SetMix {
                slot,
                gain: 0.8,
                pan: 0.1,
                mute: false,
                quiet: i == 5,
            },
        );
        send(
            &mut handle,
            Msg::SetInput {
                track: slot,
                first: i,
                channels: 2,
                monitor: true,
                armed: i == 2,
            },
        );
        // One track takes MIDI from one port and channel.
        send(
            &mut handle,
            Msg::SetMidiInput {
                track: slot,
                port: if i == 1 { 77 } else { 0 },
                channel: if i == 1 { 2 } else { 0 },
            },
        );
        // Two tracks send what they play to MIDI output ports, one of them
        // on a channel of its own.
        if i < 2 {
            send(
                &mut handle,
                Msg::SetMidiOutput {
                    track: slot,
                    port: 99 + i as u32,
                    channel: if i == 0 { 5 } else { 0 },
                    form: if i == 0 {
                        paw_engine::midi_form::Form::Mpe(15)
                    } else {
                        paw_engine::midi_form::Form::Auto
                    },
                },
            );
        }
        if i == 4 || i == 5 {
            send(
                &mut handle,
                Msg::SetKey {
                    device: keyed_device(i),
                    key: Some(paw_engine::key_buf()),
                },
            );
        }
        if i == 3 {
            send(
                &mut handle,
                Msg::SetOutputs {
                    device: kit_device(i),
                    outs: Some(paw_engine::out_bufs(&[0, 2])),
                },
            );
        }
    }
    // MIDI output goes into a queue nobody reads here: once it is full,
    // what does not fit is counted and dropped.
    let _midi_out = handle.midi_output();
    // So does a copy of the output for a listener elsewhere; and one
    // replaced by another is let go of off the audio thread.
    let _first = handle.monitor(0.05);
    let _monitor = handle.monitor(0.05);
    send(&mut handle, Msg::SetSchedule(schedule(&tracks)));
    send(&mut handle, Msg::SetTempo(133.0));
    send(&mut handle, Msg::SetTimeSig { num: 7, den: 8 });
    // A map with ramps and signature changes, swapped in whole.
    let ramps: Vec<_> = (0..64)
        .map(|i| paw_engine::TempoPoint {
            beat: i as f64 * 0.75,
            bpm: 80.0 + (i * 7 % 60) as f64,
            ramp: i % 2 == 0,
        })
        .collect();
    let sigs: Vec<_> = (0..16)
        .map(|i| paw_engine::SigPoint {
            beat: i as f64 * 2.5,
            num: 3 + i % 4,
            den: 8,
        })
        .collect();
    send(
        &mut handle,
        Msg::SetTempoMap(Box::new(paw_engine::TempoMap::new(&ramps, &sigs))),
    );
    send(&mut handle, Msg::SetTempo(133.0));
    send(
        &mut handle,
        Msg::SetLoop {
            enabled: true,
            start: 2.0,
            end: 6.0,
        },
    );
    send(&mut handle, Msg::SetMetronome(true));
    send(&mut handle, Msg::Play);
    assert_eq!(run(&mut engine, 200, 512, 4), 0, "set-up and playback");
    send(&mut handle, Msg::SetQuality(Quality::Edit));
    assert_eq!(run(&mut engine, 20, 512, 4), 0, "playback in edit quality");
    send(&mut handle, Msg::SetQuality(Quality::Full));
    assert_eq!(run(&mut engine, 20, 512, 4), 0, "back to full quality");

    // The rest on several threads. The workers count as audio threads too:
    // every one of them is marked before the engine is given the pool.
    let mut pool = Pool::new(4);
    let marked = AtomicUsize::new(0);
    while marked.load(Ordering::Relaxed) < 4 {
        pool.run(64, &|_| {
            if !AUDIO.with(|a| a.replace(true)) {
                marked.fetch_add(1, Ordering::Relaxed);
            }
            std::thread::sleep(std::time::Duration::from_micros(200));
        });
    }
    AUDIO.with(|a| a.set(false));
    send(&mut handle, Msg::SetPool(Some(Box::new(pool))));
    assert_eq!(run(&mut engine, 200, 512, 4), 0, "playback on four threads");

    // Clip launching: slots given and replaced, launched on every kind of
    // boundary, legato, stopped, back to the arrangement, across seeks, the
    // loop going round and the song stopping.
    use paw_engine::launch::{Launch, Quantize, SlotClip, Slots, Target};
    let slots = |round: usize| {
        let rows = (0..4)
            .map(|row| {
                (row != 2).then(|| SlotClip {
                    clips: *clips(&audio, 20 + round),
                    length: 1.0 + row as f64 + round as f64 * 0.5,
                })
            })
            .collect();
        Box::new(Slots { rows })
    };
    let quantizes = [
        Quantize::Off,
        Quantize::Grid(0.25),
        Quantize::Beat,
        Quantize::Bars(1),
        Quantize::Bars(4),
    ];
    let targets = [
        Target::Slot(0),
        Target::Slot(1),
        Target::Slot(2),
        Target::Slot(3),
        Target::Slot(9),
        Target::Stop,
        Target::Arrangement,
    ];
    for round in 0..12 {
        for &slot in &tracks {
            send(
                &mut handle,
                Msg::SetSlots {
                    track: slot,
                    slots: slots(round),
                },
            );
        }
        let launches = tracks
            .iter()
            .enumerate()
            .map(|(i, &track)| Launch {
                track,
                target: targets[(i + round) % targets.len()],
                quantize: quantizes[(i * 3 + round) % quantizes.len()],
                legato: (i + round) % 3 == 0,
                from: (round % 5 == 2).then_some(round as f64 * 0.3),
            })
            .collect();
        send(&mut handle, Msg::Launch(launches));
        if round % 4 == 1 {
            send(&mut handle, Msg::Seek(round as f64 * 0.7));
        }
        if round == 7 {
            send(&mut handle, Msg::Stop);
            send(&mut handle, Msg::Play);
        }
        assert_eq!(run(&mut engine, 30, 512, 4), 0, "launching clips");
        handle.collect_garbage();
    }

    // Recording: a take capturing two tracks' input and MIDI input.
    let (audio_tx, mut audio_rx) = rtrb::RingBuffer::new(1 << 20);
    let (midi_tx, mut midi_rx) = rtrb::RingBuffer::new(1024);
    let (wraps_tx, _wraps_rx) = rtrb::RingBuffer::new(64);
    let take = Take::new(
        vec![AudioCapture {
            first: 0,
            channels: 2,
            ring: audio_tx,
        }],
        midi_tx,
        Arc::new(TakeShared::default()),
        wraps_tx,
    );
    send(&mut handle, Msg::SetTake(Some(Box::new(take))));
    // Some keys taken by the input filter, swapped in on the audio thread.
    let rule = |key| Rule {
        port: 77,
        channel: 0,
        control: Control::Note(key),
    };
    let filter = MidiFilter::try_from((40..50).map(rule).collect::<Vec<_>>()).unwrap();
    send(&mut handle, Msg::SetMidiFilter(Box::new(filter)));
    for key in 40..60 {
        send(
            &mut handle,
            Msg::MidiIn {
                port: 77,
                kind: EventKind::NoteOn {
                    key,
                    vel: 0.5,
                    ch: 1,
                    attr: Attr::NONE,
                },
            },
        );
        send(
            &mut handle,
            Msg::Live {
                track: tracks[0],
                event: EventKind::NoteOn {
                    key,
                    vel: 0.5,
                    ch: 0,
                    attr: Attr::NONE,
                },
            },
        );
    }
    let mut midi = handle.take_midi_input().unwrap();
    for key in 40..60 {
        let _ = midi.push((77, EventKind::NoteOff { key, ch: 1 }));
    }
    assert_eq!(run(&mut engine, 100, 256, 4), 0, "recording");
    while audio_rx.pop().is_ok() {}
    while midi_rx.pop().is_ok() {}

    // A take punched in and out inside the loop, and a count-in before
    // playing again, with the metronome on and off.
    let (audio_tx, mut audio_rx) = rtrb::RingBuffer::new(1 << 20);
    let (midi_tx, mut midi_rx) = rtrb::RingBuffer::new(1024);
    let (wraps_tx, _wraps_rx) = rtrb::RingBuffer::new(64);
    let mut take = Take::new(
        vec![AudioCapture {
            first: 0,
            channels: 2,
            ring: audio_tx,
        }],
        midi_tx,
        Arc::new(TakeShared::default()),
        wraps_tx,
    );
    take.punch = Some((3.0, 4.5));
    send(&mut handle, Msg::SetTake(Some(Box::new(take))));
    for key in 40..50 {
        send(
            &mut handle,
            Msg::MidiIn {
                port: 0,
                kind: EventKind::NoteOn {
                    key,
                    vel: 0.5,
                    ch: 0,
                    attr: Attr::NONE,
                },
            },
        );
    }
    assert_eq!(run(&mut engine, 100, 256, 4), 0, "punched recording");
    for metronome in [true, false] {
        send(&mut handle, Msg::SetMetronome(metronome));
        send(
            &mut handle,
            Msg::CountIn {
                frames: 48000,
                every: 6000.0,
                clicks: 8,
                per_bar: 4,
            },
        );
        assert_eq!(run(&mut engine, 120, 512, 4), 0, "counting in");
        send(
            &mut handle,
            Msg::CountIn {
                frames: 48000,
                every: 12000.0,
                clicks: 4,
                per_bar: 4,
            },
        );
        send(&mut handle, Msg::Stop);
        send(&mut handle, Msg::Play);
        assert_eq!(run(&mut engine, 10, 512, 4), 0, "a count called off");
    }
    send(&mut handle, Msg::SetTake(None));
    assert_eq!(run(&mut engine, 4, 256, 4), 0, "punched take let go");
    handle.collect_garbage();
    while audio_rx.pop().is_ok() {}
    while midi_rx.pop().is_ok() {}

    // Everything replaced while playing: the old parts go to the garbage queue.
    for round in 0..20 {
        for (i, &slot) in tracks.iter().enumerate() {
            send(
                &mut handle,
                Msg::SetClips {
                    track: slot,
                    clips: clips(&audio, 100 + round),
                },
            );
            send(
                &mut handle,
                Msg::SetAutomation {
                    track: slot,
                    automation: Box::default(),
                },
            );
            let dev = DeviceSlot((i * kinds.len()) as u32);
            send(
                &mut handle,
                Msg::SetParam {
                    device: dev,
                    param: (round % 8) as u32,
                    value: 0.5,
                },
            );
            send(
                &mut handle,
                Msg::SetBypass {
                    device: DeviceSlot(dev.0 + 1),
                    bypass: round % 2 == 0,
                },
            );
            send(
                &mut handle,
                Msg::InsertDevice {
                    slot: DeviceSlot(dev.0 + 2),
                    device: device("gain"),
                },
            );
            let chain: Box<[DeviceSlot]> = (0..kinds.len())
                .rev()
                .map(|k| DeviceSlot((i * kinds.len() + k) as u32))
                .collect();
            send(&mut handle, Msg::SetChain { track: slot, chain });
            // Side-chains and output pairs taken away and given again.
            if i == 4 {
                send(
                    &mut handle,
                    Msg::SetKey {
                        device: keyed_device(i),
                        key: (round % 2 == 1).then(paw_engine::key_buf),
                    },
                );
            }
            if i == 3 {
                send(
                    &mut handle,
                    Msg::SetOutputs {
                        device: kit_device(i),
                        outs: (round % 2 == 0).then(|| paw_engine::out_bufs(&[0, 2])),
                    },
                );
            }
        }
        send(&mut handle, Msg::SetSchedule(schedule(&tracks)));
        send(&mut handle, Msg::Seek(round as f64 * 1.5));
        send(&mut handle, Msg::SetTake(None));
        assert_eq!(
            run(&mut engine, 5, 1024 + 7, 2),
            0,
            "replacing parts, round {round}"
        );
        handle.collect_garbage();
    }

    // Clips sent as a part each, then edited a few at a time while playing:
    // the parts taken out go to the garbage queue in the edit.
    let part = |id: u64, order: u64| {
        let set = clips(&audio, 8 + id as usize % 5);
        let audio = set.audio.iter().take(2).map(|r| AudioRegion {
            start: r.start + id as f64,
            end: r.end + id as f64,
            data: r.data.clone(),
            offset: r.offset,
            gain: r.gain,
            fade_in: r.fade_in,
            fade_out: r.fade_out,
            declick_in: r.declick_in,
            declick_out: r.declick_out,
            hold: Default::default(),
            direction: Default::default(),
        });
        // Its events counted from where it plays them, as copies of a clip share them.
        paw_engine::Part::new(id, order, set.midi.into(), audio.collect()).with_offset(id as f64)
    };
    for &slot in &tracks[..3] {
        let parts = (0..40).map(|id| part(id, (id + 1) * 1000)).collect();
        let set = Box::new(ClipSet::default().with_parts(parts, 64));
        send(&mut handle, Msg::SetClips { track: slot, clips: set });
    }
    send(&mut handle, Msg::Seek(2.0));
    assert_eq!(run(&mut engine, 4, 512, 2), 0, "parts set");
    for round in 0..30u64 {
        for &slot in &tracks[..3] {
            let gone = round % 40;
            let edit = paw_engine::PartEdit {
                remove: vec![(gone, (gone + 1) * 1000 + round / 40), (1000 + round, 500 + round - 1)],
                add: vec![part(gone, (gone + 1) * 1000 + round / 40 + 1), part(1000 + round + 1, 500 + round)],
                removed: Vec::with_capacity(2),
            };
            send(&mut handle, Msg::EditClips { track: slot, edit: Box::new(edit) });
        }
        assert_eq!(run(&mut engine, 3, 512, 2), 0, "parts edited, round {round}");
        handle.collect_garbage();
    }

    // Removing everything, stopping, and messages for slots that do not exist.
    for (i, &slot) in tracks.iter().enumerate() {
        for k in 0..kinds.len() {
            send(
                &mut handle,
                Msg::RemoveDevice {
                    slot: DeviceSlot((i * kinds.len() + k) as u32),
                },
            );
        }
        send(&mut handle, Msg::RemoveTrack { slot });
    }
    send(
        &mut handle,
        Msg::SetClips {
            track: TrackSlot(999),
            clips: Box::default(),
        },
    );
    send(
        &mut handle,
        Msg::InsertTrack {
            slot: TrackSlot(u32::MAX - 1),
            track: TrackRt::new(),
        },
    );
    send(
        &mut handle,
        Msg::InsertDevice {
            slot: DeviceSlot(u32::MAX - 1),
            device: device("delay"),
        },
    );
    send(
        &mut handle,
        Msg::SetChain {
            track: TrackSlot(999),
            chain: Box::new([DeviceSlot(1), DeviceSlot(2)]),
        },
    );
    send(
        &mut handle,
        Msg::SetParam {
            device: DeviceSlot(99999),
            param: 0,
            value: 1.0,
        },
    );
    send(
        &mut handle,
        Msg::Live {
            track: TrackSlot(999),
            event: EventKind::AllNotesOff,
        },
    );
    send(&mut handle, Msg::Stop);
    send(&mut handle, Msg::SetSchedule(Box::default()));
    assert_eq!(run(&mut engine, 20, 64, 0), 0, "removing");

    // A garbage queue nobody empties: the engine must leak, not free.
    for _ in 0..20000 {
        if handle
            .try_send(Msg::SetAutomation {
                track: TrackSlot::MASTER,
                automation: Box::default(),
            })
            .is_err()
        {
            assert_eq!(run(&mut engine, 1, 16, 0), 0, "full garbage queue");
        }
    }
    assert_eq!(run(&mut engine, 1, 16, 0), 0, "full garbage queue");
    assert!(
        handle.shared.leaked() > 0,
        "the queue should have overflowed"
    );
    handle.collect_garbage();

    the_sampler_never_allocates();
    a_sound_being_made_never_allocates();
    a_file_heard_on_its_own_never_allocates();
    an_engine_at_rest_never_allocates();
    reversed_slices_never_allocate();
    a_stepped_stream_never_allocates();
}

/// The stepped backend runs blocks on the caller's thread, with its test
/// input, without allocating. Run from the test above.
fn a_stepped_stream_never_allocates() {
    use paw_engine::backend::{self, BackendOptions, TestInput};
    let opts = BackendOptions {
        backend: "step".into(),
        test_input: Some(TestInput { frequency: 440.0, level: -12.0, channels: 2 }),
        ..Default::default()
    };
    let opened = backend::open(&opts).unwrap();
    let (engine, handle) = Engine::new(f64::from(opened.sample_rate()));
    let mut stream = opened.start(engine).unwrap();
    let at = stream.end_of(100).unwrap();
    let before = VIOLATIONS.load(Ordering::Relaxed);
    AUDIO.with(|a| a.set(true));
    let ran = stream.run_to(at);
    AUDIO.with(|a| a.set(false));
    assert_eq!(VIOLATIONS.load(Ordering::Relaxed) - before, 0, "stepped blocks");
    assert_eq!(ran, 100, "the blocks ran");
    drop(stream);
    drop(handle);
}

/// A clip cut into a thousand slices, played backwards with fades, across
/// block edges and a loop, and edited while it plays: none of it allocates.
/// Run from the test above.
fn reversed_slices_never_allocate() {
    use paw_engine::{Part, PartEdit};
    let (mut engine, mut handle) = Engine::new(SR);
    let tone: Vec<f32> = (0..44100).map(|i| (i as f32 * 0.05).sin()).collect();
    let data = Arc::new(AudioData {
        sample_rate: 44100,
        channels: [tone.clone().into(), tone.into()],
    });
    let slices = |id: u64| {
        let audio = (0..1000)
            .map(|k| {
                let start = k as f64 * 0.01;
                AudioRegion {
                    start,
                    end: start + 0.01,
                    data: data.clone(),
                    offset: (k % 50) as f64 * 0.01,
                    gain: 0.5,
                    fade_in: 0.002,
                    fade_out: 0.003,
                    declick_in: true,
                    declick_out: true,
                    hold: Default::default(),
                    direction: Default::default(),
                }
                .reversed()
                .unwrap()
            })
            .rev()
            .collect();
        Part::new(id, id, Arc::from([]), audio)
    };
    let clips = ClipSet::default().with_parts(vec![slices(1)], 4);
    for msg in [
        Msg::InsertTrack { slot: TrackSlot(1), track: TrackRt::new() },
        Msg::SetClips { track: TrackSlot(1), clips: Box::new(clips) },
        Msg::SetSchedule(Box::new(Schedule::new(
            vec![
                SchedEntry::new(TrackSlot(1), TrackSlot::MASTER),
                SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE),
            ],
            0,
        ))),
        Msg::SetTempo(120.0),
        Msg::SetLoop { enabled: true, start: 2.0, end: 6.0 },
        Msg::Seek(1.5),
        Msg::Play,
    ] {
        send(&mut handle, msg);
    }
    assert_eq!(run(&mut engine, 200, 512 + 3, 0), 0, "reversed slices");
    let edit = PartEdit { remove: vec![(1, 1)], add: vec![slices(2)], removed: Vec::with_capacity(1) };
    send(&mut handle, Msg::EditClips { track: TrackSlot(1), edit: Box::new(edit) });
    assert_eq!(run(&mut engine, 100, 512, 0), 0, "reversed slices replaced");
    handle.collect_garbage();
}

/// A sound file heard on its own, at another rate than the engine's, while
/// the transport plays and while it does not, replaced while it plays (the
/// old one fading out), its level changed, played to its end and stopped,
/// all without allocating. Run from the test above.
fn a_file_heard_on_its_own_never_allocates() {
    use paw_engine::Preview;
    let (mut engine, mut handle) = Engine::new(SR);
    let tone: Vec<f32> = (0..44100).map(|i| (i as f32 * 0.05).sin()).collect();
    let data = Arc::new(AudioData {
        sample_rate: 44100,
        channels: [tone.clone().into(), tone.into()],
    });
    let voice = |id| Msg::SetPreview(Some(Box::new(Preview::new(data.clone(), SR, 0.25, id))));
    send(&mut handle, voice(1));
    assert_eq!(run(&mut engine, 20, 512, 0), 0, "a file heard while stopped");
    assert_eq!(handle.shared.preview().map(|p| p.0), Some(1));
    send(&mut handle, Msg::Play);
    send(&mut handle, voice(2));
    send(&mut handle, Msg::SetPreviewGain(0.5));
    assert_eq!(run(&mut engine, 20, 512, 0), 0, "another file while playing");
    assert_eq!(run(&mut engine, 200, 512, 0), 0, "a file played to its end");
    assert_eq!(handle.shared.preview(), None, "it has ended");
    send(&mut handle, voice(3));
    assert_eq!(run(&mut engine, 4, 512, 0), 0, "a file started again");
    send(&mut handle, Msg::SetPreview(None));
    assert_eq!(run(&mut engine, 4, 512, 0), 0, "a file stopped");
    assert_eq!(handle.shared.preview(), None, "it has stopped");
    handle.collect_garbage();
}

/// A stopped engine with synths comes to rest, rests, and wakes for a note
/// and rests again, without allocating. Run from the test above.
fn an_engine_at_rest_never_allocates() {
    let (mut engine, mut handle) = Engine::new(SR);
    let mut entries = Vec::new();
    for n in 1..=4 {
        let slot = TrackSlot(n);
        let track = TrackRt::new();
        send(&mut handle, Msg::InsertTrack { slot, track });
        let (dev, device) = (DeviceSlot(n), device("synth"));
        send(&mut handle, Msg::InsertDevice { slot: dev, device });
        let chain = vec![dev].into();
        send(&mut handle, Msg::SetChain { track: slot, chain });
        entries.push(SchedEntry::new(slot, TrackSlot::MASTER));
    }
    entries.push(SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE));
    send(&mut handle, Msg::SetSchedule(Box::new(Schedule::new(entries, 0))));
    assert_eq!(run(&mut engine, 40, 512, 2), 0, "coming to rest, and resting");
    assert!(handle.shared.engine_rests() > 0, "the engine rests");
    let on = EventKind::NoteOn {
        key: 60,
        vel: 0.8,
        ch: 0,
        attr: Attr::NONE,
    };
    let off = EventKind::NoteOff { key: 60, ch: 0 };
    for event in [on, off] {
        let track = TrackSlot(1);
        send(&mut handle, Msg::Live { track, event });
    }
    assert_eq!(run(&mut engine, 400, 512, 2), 0, "woken by a note, and at rest again");
    handle.collect_garbage();
}

/// A sound played while it is made, run out of and caught up with, is
/// played without allocating. Run from the test above.
fn a_sound_being_made_never_allocates() {
    use paw_engine::Sink;
    let (mut engine, mut handle) = Engine::new(SR);
    let mut sink = Sink::growing(SR as usize * 4, SR as u32, None).unwrap();
    let mut clips = ClipSet::default();
    clips.audio.push(AudioRegion {
        start: 0.0,
        end: 8.0,
        data: Arc::new(sink.playing().unwrap()),
        offset: 0.0,
        gain: 1.0,
        fade_in: 0.0,
        fade_out: 0.0,
        declick_in: false,
        declick_out: false,
        hold: Default::default(),
        direction: Default::default(),
    });
    for msg in [
        Msg::InsertTrack {
            slot: TrackSlot(1),
            track: TrackRt::new(),
        },
        Msg::SetClips {
            track: TrackSlot(1),
            clips: Box::new(clips),
        },
        Msg::SetSchedule(Box::new(Schedule::new(
            vec![
                SchedEntry::new(TrackSlot(1), TrackSlot::MASTER),
                SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE),
            ],
            0,
        ))),
        Msg::Play,
    ] {
        send(&mut handle, msg);
    }
    let piece: Vec<f32> = (0..SR as usize / 2)
        .map(|i| (i as f32 * 0.03).sin())
        .collect();
    for _ in 0..8 {
        // Half a second made for each second played: it runs out, then
        // picks up again.
        sink.push(&piece, None).unwrap();
        assert_eq!(run(&mut engine, 94, 512, 2), 0, "a sound being made");
    }
}

/// The sampler plays a kit, is handed new kits while it plays, and gives the
/// old ones back, all without allocating on the audio thread. Run from the
/// test above, so that the counter is not shared with it.
fn the_sampler_never_allocates() {
    use paw_engine::{Event, EventBuf, Io, ProcessCtx};
    let dir = std::env::temp_dir().join(format!("paw-noalloc-sampler-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("hit.wav");
    let spec = hound::WavSpec {
        channels: 2,
        sample_rate: 44100,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    let mut w = hound::WavWriter::create(&file, spec).unwrap();
    for i in 0..8000 {
        w.write_sample(((i as f32 * 0.07).sin() * 8000.0) as i16)
            .unwrap();
        w.write_sample(((i as f32 * 0.05).sin() * 8000.0) as i16)
            .unwrap();
    }
    w.finalize().unwrap();
    let mut kit = String::from("sampler 1\n");
    for note in 30..90 {
        kit.push_str(&format!(
            "{note} -3 0.3 {} {} {}\n",
            note % 5,
            note % 3,
            file.display()
        ));
    }
    let instance = Registry::with_builtins()
        .get("sampler")
        .unwrap()
        .create(SR as f32, MAX_BLOCK)
        .unwrap();
    let (mut device, mut control) = (instance.device, instance.controller.unwrap());
    control.load_state(kit.as_bytes()).unwrap();
    let ctx = ProcessCtx::at(SR as f32, 120.0, 4, 4, true);
    let mut events = EventBuf::with_capacity(256);
    let (mut left, mut right) = (vec![0.0f32; 512], vec![0.0f32; 512]);
    let before = VIOLATIONS.load(Ordering::Relaxed);
    for block in 0..400 {
        if block % 50 == 25 {
            // A new kit while notes ring: built here, taken there.
            control.load_state(kit.as_bytes()).unwrap();
            control.idle();
        }
        events.clear();
        for i in 0..40u32 {
            events.push(Event {
                frame: i * 12,
                kind: EventKind::NoteOn {
                    key: 30 + ((block as u32 * 7 + i) % 62) as u8,
                    vel: 0.8,
                    ch: 0,
                    attr: Attr::NONE,
                },
            });
        }
        AUDIO.with(|a| a.set(true));
        device.set_param(0, -6.0);
        device.process(
            &ctx,
            &mut Io {
                left: &mut left,
                right: &mut right,
                events: &mut events,
                sidechain: None,
                outputs: &mut [],
            },
        );
        AUDIO.with(|a| a.set(false));
    }
    assert_eq!(
        VIOLATIONS.load(Ordering::Relaxed) - before,
        0,
        "the sampler"
    );
    assert!(left.iter().any(|s| *s != 0.0), "and it played");
}

/// Every built-in effect, with each of its parameters moved to the ends of
/// its range while it plays, and its face asked for its readings meanwhile.
#[test]
fn built_in_effects_do_not_allocate() {
    use paw_engine::{EventBuf, Io, ProcessCtx};
    let registry = Registry::with_builtins();
    let ctx = ProcessCtx::at(SR as f32, 120.0, 4, 4, true);
    for factory in registry.iter() {
        let info = factory.info().clone();
        if info.category != paw_engine::Category::Effect {
            continue;
        }
        let instance = factory.create(SR as f32, MAX_BLOCK).unwrap();
        let mut device = instance.device;
        let mut events = EventBuf::with_capacity(16);
        let mut left: Vec<f32> = (0..512).map(|i| (i as f32 * 0.03).sin()).collect();
        let mut right = left.clone();
        // Every other block with a side-chain, for those that listen to one.
        let key: Vec<f32> = (0..512).map(|i| (i as f32 * 0.07).sin()).collect();
        let before = HERE.with(|h| h.get());
        for block in 0..(info.params.len() * 4 + 40) {
            let which = block / 4;
            AUDIO.with(|a| a.set(true));
            if let Some(p) = info.params.get(which % info.params.len().max(1)) {
                let value = if block % 2 == 0 { p.max } else { p.min };
                device.set_param((which % info.params.len()) as u32, value);
            }
            for (i, (l, r)) in left.iter_mut().zip(right.iter_mut()).enumerate() {
                let x = ((block * 512 + i) as f32 * 0.031).sin() * 0.8;
                *l = x;
                *r = -x;
            }
            device.process(
                &ctx,
                &mut Io {
                    left: &mut left,
                    right: &mut right,
                    events: &mut events,
                    sidechain: (block % 2 == 1).then_some([&key[..], &key[..]]),
                    outputs: &mut [],
                },
            );
            AUDIO.with(|a| a.set(false));
        }
        assert_eq!(
            HERE.with(|h| h.get()) - before,
            0,
            "{} allocates while processing",
            info.kind
        );
    }
}
