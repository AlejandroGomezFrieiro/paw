//! Counting in before a take, and punching in and out of one, to the frame.

use std::sync::Arc;

use paw_engine::record::{AudioCapture, Take, TakeShared};
use paw_engine::{Engine, EngineHandle, Msg};

const SR: f64 = 48000.0;
/// Frames in a beat at the map's first tempo, 120 BPM.
const BEAT: usize = 24000;

fn send(handle: &mut EngineHandle, msg: Msg) {
    assert!(handle.try_send(msg).is_ok(), "message queue full");
}

/// Run `frames` frames in blocks of `block`, with one input channel of a
/// steady level, and return the left output.
fn run(engine: &mut Engine, frames: usize, block: usize) -> Vec<f32> {
    let mut out = Vec::with_capacity(frames);
    let input = vec![0.5f32; block];
    let mut done = 0;
    while done < frames {
        let n = block.min(frames - done);
        let (mut left, mut right) = (vec![0.0f32; n], vec![0.0f32; n]);
        engine.process_input(&input[..n], 1, &mut left, &mut right);
        out.extend_from_slice(&left);
        done += n;
    }
    out
}

/// A take of the input's first channel, punched or not, and the ring its
/// frames go into.
fn take(punch: Option<(f64, f64)>) -> (Take, rtrb::Consumer<f32>, Arc<TakeShared>) {
    let (audio_tx, audio_rx) = rtrb::RingBuffer::new(1 << 20);
    let (midi_tx, _midi_rx) = rtrb::RingBuffer::new(64);
    let (wraps_tx, _wraps_rx) = rtrb::RingBuffer::new(64);
    let shared = Arc::new(TakeShared::default());
    let mut take = Take::new(
        vec![AudioCapture {
            first: 0,
            channels: 1,
            ring: audio_tx,
        }],
        midi_tx,
        shared.clone(),
        wraps_tx,
    );
    take.punch = punch;
    (take, audio_rx, shared)
}

#[test]
fn a_count_in_clicks_each_beat_and_starts_the_song_on_the_frame_after_the_last() {
    let (mut engine, mut handle) = Engine::new(SR);
    send(
        &mut handle,
        Msg::CountIn {
            frames: 4 * BEAT as u64,
            every: BEAT as f64,
            clicks: 4,
            per_bar: 4,
        },
    );
    let out = run(&mut engine, 1000, 1000);
    assert_eq!(handle.shared.counting(), 4, "four beats to count");
    assert!(!handle.shared.playing(), "not playing while counting");
    let out = [out, run(&mut engine, 4 * BEAT - 1000 + 1000, 700)].concat();
    // A click on every beat of the count, from silence.
    for k in 0..4 {
        let at = k * BEAT;
        if at > 0 {
            assert_eq!(out[at - 1], 0.0, "silence before click {k}");
        }
        assert!(out[at + 3].abs() > 0.01, "click {k} sounds on its frame");
    }
    assert_eq!(handle.shared.counting(), 0, "counted");
    assert!(handle.shared.playing(), "and playing");
    // Started on frame 4 * BEAT: 1000 frames on, a twenty-fourth of a beat in.
    let position = handle.shared.position();
    assert!(
        (position - 1000.0 / BEAT as f64).abs() < 1e-9,
        "the song started on the frame after the count, at {position}"
    );
}

#[test]
fn stopping_while_counting_calls_the_count_off() {
    let (mut engine, mut handle) = Engine::new(SR);
    send(
        &mut handle,
        Msg::CountIn {
            frames: 4 * BEAT as u64,
            every: BEAT as f64,
            clicks: 4,
            per_bar: 4,
        },
    );
    run(&mut engine, BEAT, 512);
    send(&mut handle, Msg::Stop);
    let out = run(&mut engine, 4 * BEAT, 512);
    assert_eq!(handle.shared.counting(), 0, "no count");
    assert!(!handle.shared.playing(), "and no song");
    assert_eq!(handle.shared.position(), 0.0, "the playhead stays");
    assert!(out[BEAT..].iter().all(|s| *s == 0.0), "no more clicks");
}

#[test]
fn a_punched_take_captures_from_the_punch_in_to_the_punch_out_and_no_more() {
    for block in [512, 1000, 37] {
        let (mut engine, mut handle) = Engine::new(SR);
        let (take, mut ring, shared) = take(Some((1.0, 2.5)));
        send(&mut handle, Msg::SetTake(Some(Box::new(take))));
        send(&mut handle, Msg::Play);
        run(&mut engine, 4 * BEAT, block);
        let mut frames = 0;
        while ring.pop().is_ok() {
            frames += 1;
        }
        assert_eq!(frames, 3 * BEAT / 2, "a beat and a half, in blocks of {block}");
        let start = shared.start().expect("it captured");
        assert!((start - 1.0).abs() < 1e-9, "from the punch in, not {start}");
        assert!(handle.shared.position() > 3.9, "the song played on");
    }
}

#[test]
fn a_take_punched_from_inside_its_range_starts_at_once() {
    let (mut engine, mut handle) = Engine::new(SR);
    send(&mut handle, Msg::Seek(1.5));
    let (take, mut ring, shared) = take(Some((1.0, 2.5)));
    send(&mut handle, Msg::SetTake(Some(Box::new(take))));
    send(&mut handle, Msg::Play);
    run(&mut engine, 2 * BEAT, 512);
    let mut frames = 0;
    while ring.pop().is_ok() {
        frames += 1;
    }
    assert_eq!(frames, BEAT, "from where it began to the punch out");
    assert!((shared.start().unwrap() - 1.5).abs() < 1e-9, "at once");
}

/// A track whose audio clip plays a steady tone over the first four beats,
/// with input channel 0 armed.
fn armed_over_a_clip(handle: &mut EngineHandle) {
    use paw_engine::{AudioData, AudioRegion, ClipSet, SchedEntry, Schedule, TrackRt, TrackSlot};
    let steady = || vec![0.25f32; 44100 * 4].into();
    let data = Arc::new(AudioData { sample_rate: 44100, channels: [steady(), steady()] });
    let mut clips = ClipSet::default();
    clips.audio.push(AudioRegion {
        start: 0.0,
        end: 4.0,
        data,
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
        Msg::InsertTrack { slot: TrackSlot(1), track: TrackRt::new() },
        Msg::SetClips { track: TrackSlot(1), clips: Box::new(clips) },
        Msg::SetInput { track: TrackSlot(1), first: 0, channels: 1, monitor: false, armed: true },
        Msg::SetSchedule(Box::new(Schedule::new(
            vec![
                SchedEntry::new(TrackSlot(1), TrackSlot::MASTER),
                SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE),
            ],
            0,
        ))),
    ] {
        send(handle, msg);
    }
}

/// Run with a silent input, so that what is heard is the track's clips.
fn run_silent(engine: &mut Engine, frames: usize, block: usize) -> Vec<f32> {
    let mut out = Vec::with_capacity(frames);
    let input = vec![0.0f32; block];
    let mut done = 0;
    while done < frames {
        let n = block.min(frames - done);
        let (mut left, mut right) = (vec![0.0f32; n], vec![0.0f32; n]);
        engine.process_input(&input[..n], 1, &mut left, &mut right);
        out.extend_from_slice(&left);
        done += n;
    }
    out
}

#[test]
fn a_track_recording_its_input_does_not_play_its_clips_under_the_take() {
    let (mut engine, mut handle) = Engine::new(SR);
    armed_over_a_clip(&mut handle);
    let (take, _ring, _shared) = take(Some((1.0, 2.5)));
    send(&mut handle, Msg::SetTake(Some(Box::new(take))));
    send(&mut handle, Msg::Play);
    let out = run_silent(&mut engine, 4 * BEAT, 512);
    let heard = |from: usize, to: usize| out[from..to].iter().any(|s| s.abs() > 0.01);
    assert!(heard(BEAT / 4, BEAT - 600), "the clip plays before the punch in");
    assert!(!heard(BEAT + 600, 5 * BEAT / 2 - 600), "and not while the take captures");
    assert!(heard(5 * BEAT / 2 + 600, 4 * BEAT - 600), "and again after the punch out");
}
