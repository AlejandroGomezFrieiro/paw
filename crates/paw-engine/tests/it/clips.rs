//! Replacing one track's clips while playing must not disturb the others.

use paw_engine::{
    ClipSet, DeviceSlot, Engine, EngineHandle, MAX_BLOCK, Msg, Registry, SchedEntry, Schedule,
    TrackRt, TrackSlot,
};
use paw_types::EventKind;

use crate::common::{SR, send};

/// Two tracks with a synth each. Track 1 holds one long note; track 2 holds
/// `second` (a note, or nothing).
fn engine(second: bool) -> (Engine, EngineHandle) {
    let (engine, mut handle) = Engine::new(SR);
    let registry = Registry::with_builtins();
    for (n, device) in [(1u32, DeviceSlot(0)), (2, DeviceSlot(1))] {
        let slot = TrackSlot(n);
        send(
            &mut handle,
            Msg::InsertTrack {
                slot,
                track: TrackRt::new(),
            },
        );
        let synth = registry
            .get("synth")
            .unwrap()
            .create(SR as f32, MAX_BLOCK)
            .unwrap()
            .device;
        send(
            &mut handle,
            Msg::InsertDevice {
                slot: device,
                device: synth,
            },
        );
        send(
            &mut handle,
            Msg::SetChain {
                track: slot,
                chain: Box::new([device]),
            },
        );
        let mut clips = ClipSet::default();
        if n == 1 || second {
            clips.push_note(0.0, 64.0, 57 + n as u8, 0.8);
        }
        clips.finish();
        send(
            &mut handle,
            Msg::SetClips {
                track: slot,
                clips: Box::new(clips),
            },
        );
    }
    let entry = |slot| SchedEntry::new(slot, TrackSlot::MASTER);
    let entries = vec![
        entry(TrackSlot(1)),
        entry(TrackSlot(2)),
        SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE),
    ];
    send(
        &mut handle,
        Msg::SetSchedule(Box::new(Schedule::new(entries, 0))),
    );
    send(&mut handle, Msg::Play);
    (engine, handle)
}

fn run(engine: &mut Engine, blocks: usize) -> Vec<f32> {
    let mut out = Vec::new();
    let (mut l, mut r) = (vec![0.0; 256], vec![0.0; 256]);
    for _ in 0..blocks {
        engine.process(&mut l, &mut r);
        out.extend_from_slice(&l);
    }
    out
}

#[test]
fn replacing_one_tracks_clips_leaves_the_others_playing() {
    let (mut reference, _keep) = engine(false);
    let expected = run(&mut reference, 400);

    let (mut edited, mut handle) = engine(false);
    let mut got = run(&mut edited, 100);
    // Track 2's clips are replaced (by the same nothing) three times while
    // track 1's note sounds. Track 1 must not be stopped and restarted.
    for _ in 0..3 {
        let mut empty = ClipSet::default();
        empty.finish();
        send(
            &mut handle,
            Msg::SetClips {
                track: TrackSlot(2),
                clips: Box::new(empty),
            },
        );
        got.extend(run(&mut edited, 100));
    }
    handle.collect_garbage();
    let worst = expected
        .iter()
        .zip(&got)
        .map(|(a, b)| (a - b).abs())
        .fold(0f32, f32::max);
    assert_eq!(
        worst, 0.0,
        "track 1 changed when only track 2's clips were replaced"
    );
}

#[test]
fn replacing_a_tracks_clips_stops_its_own_notes() {
    let (mut edited, mut handle) = engine(true);
    run(&mut edited, 50);
    assert!(handle.shared.meter(TrackSlot(2)).0 > 0.01, "track 2 sounds at first");
    let mut empty = ClipSet::default();
    empty.finish();
    send(
        &mut handle,
        Msg::SetClips {
            track: TrackSlot(2),
            clips: Box::new(empty),
        },
    );
    // Release (0.2 s) plus the meter's fall.
    run(&mut edited, 400);
    assert!(
        handle.shared.meter(TrackSlot(2)).0 < 1e-3,
        "the note on track 2 stopped with its clip"
    );
    assert!(handle.shared.meter(TrackSlot(1)).0 > 0.01, "track 1 plays on");
}

/// A track whose clips were just replaced must not stop and restart its
/// notes a block into playback: the note-on at the very start arrives once.
#[test]
fn a_note_at_the_start_is_started_once() {
    use paw_engine::{Device, Io, ProcessCtx};
    use std::sync::Arc;
    use std::sync::atomic::{AtomicU32, Ordering};

    struct Counter(Arc<AtomicU32>);
    impl Device for Counter {
        fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
            for event in io.events.as_slice() {
                if matches!(event.kind, EventKind::NoteOn { .. }) {
                    self.0.fetch_add(1, Ordering::Relaxed);
                }
            }
        }
        fn set_param(&mut self, _index: u32, _value: f32) {}
    }

    let (mut engine, mut handle) = Engine::new(48000.0);
    let count = Arc::new(AtomicU32::new(0));
    let mut clips = ClipSet::default();
    clips.push_note(0.0, 4.0, 60, 0.8);
    clips.finish();
    for msg in [
        Msg::InsertTrack {
            slot: TrackSlot(1),
            track: TrackRt::new(),
        },
        Msg::InsertDevice {
            slot: DeviceSlot(0),
            device: Box::new(Counter(count.clone())),
        },
        Msg::SetChain {
            track: TrackSlot(1),
            chain: Box::new([DeviceSlot(0)]),
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
        Msg::Seek(0.0),
        Msg::Play,
    ] {
        send(&mut handle, msg);
    }
    let (mut left, mut right) = (vec![0.0f32; 256], vec![0.0f32; 256]);
    for _ in 0..8 {
        engine.process(&mut left, &mut right);
    }
    assert_eq!(count.load(Ordering::Relaxed), 1);
}

/// `data` from beat 0 for `beats` beats, at unity gain, without fades.
fn plain_region(data: std::sync::Arc<paw_engine::AudioData>, beats: f64) -> paw_engine::AudioRegion {
    paw_engine::AudioRegion {
        start: 0.0,
        end: beats,
        data,
        offset: 0.0,
        gain: 1.0,
        fade_in: 0.0,
        fade_out: 0.0,
        declick_in: false,
        declick_out: false,
        hold: Default::default(),
        direction: Default::default(),
    }
}

/// One track playing `region`, at 120 BPM, from beat 0.
fn region_engine(region: paw_engine::AudioRegion) -> (Engine, EngineHandle) {
    let (engine, mut handle) = Engine::new(SR);
    let mut clips = ClipSet::default();
    clips.audio.push(region);
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
        Msg::SetTempo(120.0),
        Msg::Seek(0.0),
        Msg::Play,
    ] {
        send(&mut handle, msg);
    }
    (engine, handle)
}

/// A sound still being made plays as far as it is there: past that it is
/// silent, and where more has come it starts again, without a click either
/// way.
#[test]
fn a_sound_being_made_plays_as_far_as_it_is_there_without_clicks() {
    use paw_engine::Sink;
    use std::sync::Arc;
    let sine: Vec<f32> = (0..SR as usize * 8)
        .map(|i| 0.5 * (std::f64::consts::TAU * 220.0 * i as f64 / SR).sin() as f32)
        .collect();
    let mut sink = Sink::growing(sine.len(), SR as u32, None).unwrap();
    let data = Arc::new(sink.playing().unwrap());
    let second = SR as usize;
    sink.push(&sine[..second], None).unwrap();
    let (mut engine, _handle) = region_engine(plain_region(data, 16.0));
    // A second there, two played: the second one silent.
    let mut out = run(&mut engine, 2 * second / 256);
    // More comes, as far as three seconds, and the third second plays.
    sink.push(&sine[second..3 * second], None).unwrap();
    out.extend(run(&mut engine, second / 256));
    let level = |from: f64, to: f64| {
        let s = &out[(from * SR) as usize..(to * SR) as usize];
        s.iter().fold(0.0f32, |m, x| m.max(x.abs()))
    };
    assert!(level(0.1, 0.99) > 0.45, "the first second plays");
    assert_eq!(level(1.01, 2.0), 0.0, "silent past what is there");
    assert!(level(2.01, 2.99) > 0.45, "and plays again once more is there");
    let largest = out
        .windows(2)
        .map(|w| (w[1] - w[0]).abs())
        .fold(0.0, f32::max);
    let sine_step = sine
        .windows(2)
        .map(|w| (w[1] - w[0]).abs())
        .fold(0.0, f32::max);
    assert!(
        largest <= sine_step * 1.01,
        "a step of {largest} against the sine's {sine_step}"
    );
    // Once it is all there it plays as any sound does.
    sink.finish(SR as u32).unwrap();
    let done = run(&mut engine, second / 256);
    assert!(done.iter().fold(0.0f32, |m, x| m.max(x.abs())) > 0.45);
}

/// A region played backwards plays the same stretch of its source, from
/// its end to its start; sound still being made does not play backwards.
#[test]
fn a_reversed_region_plays_its_stretch_of_the_source_from_the_end() {
    use paw_engine::{AudioData, Sink};
    use std::sync::Arc;
    let ramp: Vec<f32> = (0..SR as usize).map(|k| k as f32 / SR as f32).collect();
    let data = Arc::new(AudioData {
        sample_rate: SR as u32,
        channels: [ramp.clone().into(), ramp.clone().into()],
    });
    // A beat at 120 BPM, from a quarter of a second in: source frames
    // 12 000 to 35 999, played from the last.
    let region = paw_engine::AudioRegion { offset: 0.25, ..plain_region(data, 1.0) };
    let (mut engine, _handle) = region_engine(region.reversed().unwrap());
    let out = run(&mut engine, 100);
    for frame in [0, 1, 255, 256, 12_345, 23_999] {
        let want = ramp[35_999 - frame];
        assert!((out[frame] - want).abs() < 1e-6, "frame {frame}: {} against {want}", out[frame]);
    }
    assert_eq!(out[24_000], 0.0, "silent after the region");
    let mut sink = Sink::growing(1000, SR as u32, None).unwrap();
    sink.push(&ramp[..10], None).unwrap();
    let making = plain_region(Arc::new(sink.playing().unwrap()), 1.0);
    assert!(making.reversed().is_err());
}

/// Clips that overlap, with notes and controllers on the same beats in
/// different clips and sound of their own: each clip's events (sorted as a
/// clip's are) and sound.
fn overlapping_clips(data: &std::sync::Arc<paw_engine::AudioData>, count: usize) -> Vec<ClipSet> {
    use paw_engine::AudioRegion;
    use paw_types::Ctl;
    (0..count)
        .map(|c| {
            let mut set = ClipSet::default();
            let start = (c % 7) as f64 * 1.5;
            for i in 0..12 {
                let at = start + i as f64 * 0.5;
                // The same keys from clip to clip, so that which ends a
                // note and which starts it depends on their order.
                let length = 0.5 + (c % 3) as f64 * 0.25;
                set.push_note(at, at + length, 48 + (i % 5) as u8, 0.3 + 0.02 * c as f32);
                set.push_event(
                    at,
                    EventKind::Control {
                        ctl: Ctl::Cc(1 + (i % 2) as u8),
                        value: c as f64 / count as f64,
                        ch: 0,
                    },
                );
            }
            if c % 4 == 0 {
                let kind = EventKind::Program { program: c as u8, bank: None, ch: 0 };
                set.push_event(start + 0.25, kind);
            }
            set.finish();
            if c % 3 == 0 {
                set.audio.push(AudioRegion {
                    start,
                    end: start + 3.0 + c as f64 * 0.1,
                    data: data.clone(),
                    offset: 0.05 * c as f64,
                    gain: 0.25,
                    fade_in: 0.1,
                    fade_out: 0.2,
                    declick_in: true,
                    declick_out: false,
                    hold: Default::default(),
                    direction: Default::default(),
                });
            }
            set
        })
        .collect()
}

fn region_copy(r: &paw_engine::AudioRegion) -> paw_engine::AudioRegion {
    paw_engine::AudioRegion {
        start: r.start,
        end: r.end,
        data: r.data.clone(),
        offset: r.offset,
        gain: r.gain,
        fade_in: r.fade_in,
        fade_out: r.fade_out,
        declick_in: r.declick_in,
        declick_out: r.declick_out,
        hold: Default::default(),
        direction: r.direction,
    }
}

/// All of the clips in one list, as a track was sent them before there were pieces.
fn as_list(clips: &[ClipSet]) -> ClipSet {
    let mut set = ClipSet::default();
    for clip in clips {
        set.midi.extend_from_slice(&clip.midi);
        set.audio.extend(clip.audio.iter().map(region_copy));
    }
    set.finish();
    set
}

/// Clip `index` of `clips` as a piece, `order` among them, its events
/// counted from its first, as the sync sends them.
fn piece(clips: &[ClipSet], index: usize, order: u64) -> paw_engine::Piece {
    let clip = &clips[index];
    let offset = clip.midi.first().map_or(0.0, |e| e.beat);
    let midi = clip.midi.iter().map(|e| paw_engine::MidiEv { beat: e.beat - offset, kind: e.kind });
    paw_engine::Piece::new(
        index as u64 + 100,
        order,
        midi.collect(),
        clip.audio.iter().map(region_copy).collect(),
    )
    .with_offset(offset)
}

type Seen = std::sync::Arc<std::sync::Mutex<Vec<String>>>;

/// One track whose first device writes down every event it is given, with
/// its frame, and whose second is a synth.
fn recording_engine(clips: ClipSet) -> (Engine, EngineHandle, Seen) {
    use paw_engine::{Device, Io, ProcessCtx};
    struct Recorder(Seen);
    impl Device for Recorder {
        fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
            let mut seen = self.0.lock().unwrap();
            for event in io.events.as_slice() {
                seen.push(format!("{} {:?}", event.frame, event.kind));
            }
        }
        fn set_param(&mut self, _index: u32, _value: f32) {}
    }
    let (engine, mut handle) = Engine::new(SR);
    let seen = Seen::default();
    let synth = Registry::with_builtins()
        .get("synth")
        .unwrap()
        .create(SR as f32, MAX_BLOCK)
        .unwrap()
        .device;
    for msg in [
        Msg::InsertTrack { slot: TrackSlot(1), track: TrackRt::new() },
        Msg::InsertDevice { slot: DeviceSlot(0), device: Box::new(Recorder(seen.clone())) },
        Msg::InsertDevice { slot: DeviceSlot(1), device: synth },
        Msg::SetChain { track: TrackSlot(1), chain: Box::new([DeviceSlot(0), DeviceSlot(1)]) },
        Msg::SetClips { track: TrackSlot(1), clips: Box::new(clips) },
        Msg::SetSchedule(Box::new(Schedule::new(
            vec![
                SchedEntry::new(TrackSlot(1), TrackSlot::MASTER),
                SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE),
            ],
            0,
        ))),
    ] {
        send(&mut handle, msg);
    }
    (engine, handle, seen)
}

fn tone() -> std::sync::Arc<paw_engine::AudioData> {
    let wave = |f: f32| (0..44100 * 4).map(|i| (i as f32 * f).sin()).collect::<Vec<f32>>().into();
    std::sync::Arc::new(paw_engine::AudioData { sample_rate: 44100, channels: [wave(0.03), wave(0.05)] })
}

/// Play from `from` for `blocks` blocks of 256 frames: both channels.
fn play_from(engine: &mut Engine, handle: &mut EngineHandle, from: f64, blocks: usize) -> Vec<f32> {
    send(handle, Msg::Seek(from));
    send(handle, Msg::Play);
    let mut out = Vec::new();
    let (mut l, mut r) = (vec![0.0; 256], vec![0.0; 256]);
    for _ in 0..blocks {
        engine.process(&mut l, &mut r);
        out.extend_from_slice(&l);
        out.extend_from_slice(&r);
    }
    out
}

fn clone_piece(p: &paw_engine::Piece) -> paw_engine::Piece {
    paw_engine::Piece::new(p.id, p.order, p.midi.clone(), p.audio().iter().map(region_copy).collect())
        .with_offset(p.offset())
}

#[test]
fn clips_sent_as_parts_play_as_the_same_clips_in_one_list() {
    let data = tone();
    let clips = overlapping_clips(&data, 24);
    // The pieces given in another order than the clips', which their orders put right.
    let pieces: Vec<_> = (0..clips.len())
        .rev()
        .map(|i| piece(&clips, i, (i as u64 + 1) * 10))
        .collect();
    for from in [0.0, 3.3, 7.75] {
        let (mut a, mut ha, seen_a) = recording_engine(as_list(&clips));
        let set = ClipSet::default().with_pieces(pieces.iter().map(clone_piece).collect(), 64);
        let (mut b, mut hb, seen_b) = recording_engine(set);
        let out_a = play_from(&mut a, &mut ha, from, 300);
        let out_b = play_from(&mut b, &mut hb, from, 300);
        let (seen_a, seen_b) = (seen_a.lock().unwrap(), seen_b.lock().unwrap());
        assert!(seen_a.len() > 100, "{} events", seen_a.len());
        assert_eq!(*seen_a, *seen_b, "the same events from {from}");
        assert!(out_a.iter().any(|x| *x != 0.0));
        assert!(out_a == out_b, "the same sound to the bit from {from}");
    }
}

#[test]
fn an_edit_of_some_parts_plays_as_the_clips_sent_whole() {
    use paw_engine::PieceEdit;
    let data = tone();
    let clips = overlapping_clips(&data, 24);
    // Before: clips 0 to 19. After: 3 and 11 gone, 20 to 23 put in among them.
    let order = |i: usize| match i {
        20 => 450,
        21 => 451,
        22 => 50,
        23 => 5000,
        _ => (i as u64 + 1) * 100,
    };
    let before = || (0..20).map(|i| piece(&clips, i, order(i))).collect::<Vec<_>>();
    let after: Vec<_> = (0..24)
        .filter(|i| ![3, 11].contains(i))
        .map(|i| piece(&clips, i, order(i)))
        .collect();
    // Two engines play the same for a while; then one is sent the clips
    // whole, the other only the pieces that changed.
    let (mut a, mut ha, seen_a) = recording_engine(ClipSet::default().with_pieces(before(), 64));
    let (mut b, mut hb, seen_b) = recording_engine(ClipSet::default().with_pieces(before(), 64));
    let warm_a = play_from(&mut a, &mut ha, 0.0, 10);
    let warm_b = play_from(&mut b, &mut hb, 0.0, 10);
    assert!(warm_a == warm_b);
    let whole = ClipSet::default().with_pieces(after, 64);
    send(&mut ha, Msg::SetClips { track: TrackSlot(1), clips: Box::new(whole) });
    let edit = PieceEdit {
        remove: vec![(103, 400), (111, 1200), (999, 1)],
        add: (20..24).map(|i| piece(&clips, i, order(i))).collect(),
        removed: Vec::with_capacity(3),
    };
    send(&mut hb, Msg::EditClips { track: TrackSlot(1), edit: Box::new(edit) });
    // On, and from another place, with the held notes chased.
    let mut out_a = play_from(&mut a, &mut ha, 2.25, 100);
    let mut out_b = play_from(&mut b, &mut hb, 2.25, 100);
    out_a.extend(play_from(&mut a, &mut ha, 6.5, 200));
    out_b.extend(play_from(&mut b, &mut hb, 6.5, 200));
    ha.collect_garbage();
    hb.collect_garbage();
    let (seen_a, seen_b) = (seen_a.lock().unwrap(), seen_b.lock().unwrap());
    assert!(seen_a.len() > 200, "{} events", seen_a.len());
    assert_eq!(*seen_a, *seen_b, "the same events after the edit");
    assert!(out_a == out_b, "the same sound to the bit");
}

/// Many regions of one piece, given in any order, among them one long and
/// some backwards, play as the same regions in one list sorted by where
/// they start, from wherever playing starts: also in the middle of the
/// long one, which started far before.
#[test]
fn many_regions_in_a_part_play_as_the_same_regions_in_one_list() {
    let data = tone();
    let mut regions: Vec<paw_engine::AudioRegion> = (0..200)
        .map(|k| {
            let start = k as f64 * 0.0625;
            let region = paw_engine::AudioRegion {
                start,
                end: start + 0.0625,
                offset: (k % 7) as f64 * 0.1,
                gain: 0.5,
                fade_in: 0.01,
                fade_out: 0.02,
                declick_in: true,
                declick_out: true,
                ..plain_region(data.clone(), 0.0)
            };
            if k % 3 == 0 { region.reversed().unwrap() } else { region }
        })
        .collect();
    regions.insert(17, paw_engine::AudioRegion { start: 1.03, end: 9.0, gain: 0.25, ..plain_region(data.clone(), 0.0) });
    let piece = || paw_engine::Piece::new(1, 1, std::sync::Arc::from([]), regions.iter().rev().map(region_copy).collect());
    for from in [0.0, 3.3, 7.75] {
        let mut list = ClipSet::default();
        list.audio = regions.iter().map(region_copy).collect();
        let (mut a, mut ha, _) = recording_engine(list);
        let set = ClipSet::default().with_pieces(vec![piece()], 4);
        let (mut b, mut hb, _) = recording_engine(set);
        let out_a = play_from(&mut a, &mut ha, from, 200);
        let out_b = play_from(&mut b, &mut hb, from, 200);
        assert!(out_a.iter().any(|x| *x != 0.0));
        assert!(out_a == out_b, "the same sound to the bit from {from}");
    }
}
