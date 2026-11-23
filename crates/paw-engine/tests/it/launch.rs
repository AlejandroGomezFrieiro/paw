//! Clips launched from slots start and stop on their boundary, to the frame,
//! and the timeline is silent on a track while it plays a slot.

use std::sync::Arc;

use paw_engine::launch::{Launch, Quantize, SlotClip, Slots, Target};
use paw_engine::{
    AudioData, AudioRegion, ClipSet, Engine, EngineHandle, Msg, SchedEntry, Schedule, TempoMap,
    TempoPoint, TrackSlot,
};

use crate::common::{SR, send};

/// Frames in a beat at 120 BPM.
const BEAT: usize = 24000;
const TRACK: TrackSlot = TrackSlot(1);

/// Sound that is `level` throughout, for ten seconds.
fn steady(level: f32) -> Arc<AudioData> {
    let samples: Vec<f32> = vec![level; 10 * SR as usize];
    Arc::new(AudioData {
        sample_rate: SR as u32,
        channels: [samples.clone().into(), samples.into()],
    })
}

fn region(level: f32, start: f64, end: f64) -> AudioRegion {
    AudioRegion {
        start,
        end,
        data: steady(level),
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

/// One track playing 0.25 on the timeline, with a slot 0 that plays 0.5
/// for `sounding` beats of every `length`, and a slot 1 that plays 0.125.
fn engine(length: f64, sounding: f64) -> (Engine, EngineHandle) {
    let (engine, mut handle) = Engine::new(SR);
    send(
        &mut handle,
        Msg::InsertTrack {
            slot: TRACK,
            track: paw_engine::TrackRt::new(),
        },
    );
    let mut timeline = ClipSet::default();
    timeline.audio.push(region(0.25, 0.0, 64.0));
    send(
        &mut handle,
        Msg::SetClips {
            track: TRACK,
            clips: Box::new(timeline),
        },
    );
    let slot = |level: f32, length: f64, sounding: f64| {
        let mut clips = ClipSet::default();
        clips.audio.push(region(level, 0.0, sounding));
        Some(SlotClip { clips, length })
    };
    send(
        &mut handle,
        Msg::SetSlots {
            track: TRACK,
            slots: Box::new(Slots {
                rows: vec![slot(0.5, length, sounding), slot(0.125, 4.0, 4.0)],
            }),
        },
    );
    let entries = vec![
        SchedEntry::new(TRACK, TrackSlot::MASTER),
        SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE),
    ];
    send(
        &mut handle,
        Msg::SetSchedule(Box::new(Schedule::new(entries, 0))),
    );
    (engine, handle)
}

/// Run `frames` frames in blocks of `block` and return the left output.
fn run(engine: &mut Engine, frames: usize, block: usize) -> Vec<f32> {
    let mut out = Vec::with_capacity(frames);
    let mut done = 0;
    while done < frames {
        let n = block.min(frames - done);
        let (mut left, mut right) = (vec![0.0f32; n], vec![0.0f32; n]);
        engine.process(&mut left, &mut right);
        out.extend_from_slice(&left);
        done += n;
    }
    out
}

fn launch(target: Target, quantize: Quantize) -> Msg {
    Msg::Launch(Box::new(vec![Launch {
        track: TRACK,
        target,
        quantize,
        legato: false,
        from: None,
    }]))
}

/// The first frame from `from` on whose level is not `level`.
fn changes(out: &[f32], from: usize, level: f32) -> usize {
    from + out[from..]
        .iter()
        .position(|s| (s - level).abs() > 1e-4)
        .unwrap_or(out.len() - from)
}

#[test]
fn a_launch_lands_on_the_next_bar_to_the_frame_and_silences_the_timeline() {
    let (mut engine, mut handle) = engine(4.0, 4.0);
    send(&mut handle, Msg::Play);
    // Into the first bar, in blocks that do not divide a beat.
    let mut out = run(&mut engine, 1000, 333);
    send(&mut handle, launch(Target::Slot(0), Quantize::Bars(1)));
    out.extend(run(&mut engine, 6 * BEAT, 333));
    assert_eq!(changes(&out, 0, 0.25), 4 * BEAT, "the slot starts on bar 2");
    assert_eq!(
        changes(&out, 4 * BEAT, 0.5),
        out.len(),
        "the slot alone is heard"
    );
    let state = engine.shared().launch(TRACK).unwrap();
    assert_eq!(state.playing, Target::Slot(0));
    assert_eq!(state.since, 4.0);
    assert!((state.phase - 2.0 - 1000.0 / BEAT as f64).abs() < 1e-6);
}

#[test]
fn a_slot_goes_round_its_loop() {
    // Two beats long, sounding for the first.
    let (mut engine, mut handle) = engine(2.0, 1.0);
    send(&mut handle, Msg::Play);
    send(&mut handle, launch(Target::Slot(0), Quantize::Off));
    let out = run(&mut engine, 6 * BEAT, 512);
    for beat in 0..6 {
        let level = if beat % 2 == 0 { 0.5 } else { 0.0 };
        let at = beat * BEAT;
        // The end of the sound inside the clip is placed as on the timeline,
        // to within a frame; where the clip goes round is on the frame.
        assert!(changes(&out, at + 1, level) >= at + BEAT - 1, "beat {beat}");
        if level > 0.0 {
            assert_eq!(changes(&out, at - 2.min(at), 0.0), at, "beat {beat}");
        }
    }
}

#[test]
fn stopping_and_going_back_to_the_arrangement_wait_for_their_boundary() {
    let (mut engine, mut handle) = engine(4.0, 4.0);
    send(&mut handle, Msg::Play);
    send(&mut handle, launch(Target::Slot(0), Quantize::Off));
    let mut out = run(&mut engine, BEAT / 2, 256);
    send(&mut handle, launch(Target::Stop, Quantize::Beat));
    out.extend(run(&mut engine, 2 * BEAT + 100, 256));
    send(
        &mut handle,
        launch(Target::Arrangement, Quantize::Grid(0.25)),
    );
    out.extend(run(&mut engine, BEAT, 256));
    assert_eq!(changes(&out, 0, 0.5), BEAT, "stops on the beat");
    let state = engine.shared().launch(TRACK).unwrap();
    assert_eq!(state.playing, Target::Arrangement);
    // Asked for 100 frames after 2.5 beats, so back on the next sixteenth.
    let back = BEAT * 11 / 4;
    assert_eq!(changes(&out, BEAT, 0.0), back, "silent until then");
    assert_eq!(changes(&out, back, 0.25), out.len());
}

#[test]
fn launches_sent_together_land_together_and_a_queued_one_shows() {
    let (mut engine, mut handle) = engine(4.0, 4.0);
    send(&mut handle, Msg::Play);
    run(&mut engine, 100, 100);
    send(&mut handle, launch(Target::Slot(1), Quantize::Bars(2)));
    run(&mut engine, 100, 100);
    let state = engine.shared().launch(TRACK).unwrap();
    assert_eq!(state.playing, Target::Arrangement);
    assert_eq!(state.queued, Some((Target::Slot(1), 8.0)));
    // A second launch replaces the first.
    send(&mut handle, launch(Target::Slot(0), Quantize::Bars(1)));
    let out = run(&mut engine, 5 * BEAT, 100);
    assert_eq!(changes(&out, 0, 0.25), 4 * BEAT - 200);
    assert_eq!(engine.shared().launch(TRACK).unwrap().queued, None);
}

#[test]
fn stopping_the_song_plays_the_timeline_again() {
    let (mut engine, mut handle) = engine(4.0, 4.0);
    send(&mut handle, Msg::Play);
    send(&mut handle, launch(Target::Slot(0), Quantize::Off));
    run(&mut engine, 1000, 500);
    send(&mut handle, Msg::Stop);
    send(&mut handle, Msg::Seek(0.0));
    send(&mut handle, Msg::Play);
    let out = run(&mut engine, 1000, 500);
    assert_eq!(changes(&out, 0, 0.25), out.len());
}

#[test]
fn a_launch_past_the_end_of_the_loop_lands_where_the_loop_begins_again() {
    let (mut engine, mut handle) = engine(4.0, 4.0);
    send(
        &mut handle,
        Msg::SetLoop {
            enabled: true,
            start: 0.0,
            end: 6.0,
        },
    );
    send(&mut handle, Msg::Seek(5.0));
    send(&mut handle, Msg::Play);
    run(&mut engine, 375, 375);
    // Bar 3 starts at beat 8, beyond the loop: the next bar is its start.
    send(&mut handle, launch(Target::Slot(0), Quantize::Bars(1)));
    let out = run(&mut engine, 2 * BEAT, 256);
    // On the frame the loop goes round, which the engine puts within one
    // frame of its end's beat.
    let at = changes(&out, 0, 0.25);
    assert!(at.abs_diff(BEAT - 375) <= 1, "{at}");
    assert_eq!(changes(&out, at, 0.5), out.len());
    assert_eq!(engine.shared().launch(TRACK).unwrap().since, 0.0);
}

#[test]
fn a_launch_counted_from_an_earlier_beat_starts_where_the_clip_would_have_got_to() {
    // Three beats long, sounding for the first; counted from a beat ago.
    let (mut engine, mut handle) = engine(3.0, 1.0);
    send(&mut handle, Msg::Play);
    send(
        &mut handle,
        Msg::Launch(Box::new(vec![Launch {
            track: TRACK,
            target: Target::Slot(0),
            quantize: Quantize::Off,
            legato: false,
            from: Some(-1.0),
        }])),
    );
    let out = run(&mut engine, 4 * BEAT, 256);
    assert_eq!(changes(&out, 0, 0.0), 2 * BEAT, "silent to the end of its loop");
    assert!(changes(&out, 2 * BEAT, 0.5) >= 3 * BEAT - 1);
}

#[test]
fn boundaries_follow_bars_and_the_signature() {
    let map = TempoMap::constant(120.0, 4, 4);
    assert_eq!(Quantize::Bars(1).next(&map, 4.0), 4.0);
    assert_eq!(Quantize::Bars(1).next(&map, 4.01), 8.0);
    assert_eq!(Quantize::Bars(2).next(&map, 4.1), 8.0);
    assert_eq!(Quantize::Bars(4).next(&map, 0.5), 16.0);
    assert_eq!(Quantize::Grid(0.25).next(&map, 1.1), 1.25);
    assert_eq!(Quantize::Beat.next(&map, 1.1), 2.0);
    assert_eq!(Quantize::Off.next(&map, 1.1), 1.1);
    // In 6/8 a beat is an eighth, and a bar three quarter notes.
    let map = TempoMap::new(
        &[TempoPoint {
            beat: 0.0,
            bpm: 120.0,
            ramp: false,
        }],
        &[paw_engine::SigPoint {
            beat: 0.0,
            num: 6,
            den: 8,
        }],
    );
    assert_eq!(Quantize::Beat.next(&map, 1.1), 1.5);
    assert_eq!(Quantize::Bars(1).next(&map, 1.1), 3.0);
    // A grid does not run past the bar's end.
    assert_eq!(Quantize::Grid(2.0).next(&map, 2.5), 3.0);
}
