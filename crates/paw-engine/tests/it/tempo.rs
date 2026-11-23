//! The engine follows the tempo map sample by sample: the metronome, MIDI
//! clips and audio regions land where the map's arithmetic puts them.

use std::sync::Arc;

use paw_engine::{
    AudioData, AudioRegion, ClipSet, Engine, Msg, SchedEntry, Schedule, SigPoint, TempoMap,
    TempoPoint, TrackRt, TrackSlot,
};

use crate::common::{SR, send};

/// 4/4 at 120 for eight bars, then 6/8, with a ramp from 120 to 90 over
/// bars 3 and 4.
fn song() -> TempoMap {
    let t = |beat, bpm, ramp| TempoPoint { beat, bpm, ramp };
    TempoMap::new(
        &[
            t(0.0, 120.0, false),
            t(8.0, 120.0, true),
            t(16.0, 90.0, false),
        ],
        &[
            SigPoint {
                beat: 0.0,
                num: 4,
                den: 4,
            },
            SigPoint {
                beat: 32.0,
                num: 6,
                den: 8,
            },
        ],
    )
}

/// Frames where sound starts after at least `gap` silent frames.
fn onsets(out: &[f32], gap: usize) -> Vec<usize> {
    let mut found = Vec::new();
    let mut silent = gap;
    for (i, s) in out.iter().enumerate() {
        if *s == 0.0 {
            silent += 1;
        } else {
            if silent >= gap {
                found.push(i);
            }
            silent = 0;
        }
    }
    found
}

fn play(engine: &mut Engine, seconds: f64, block: usize) -> Vec<f32> {
    let frames = (seconds * SR) as usize;
    let mut out = Vec::with_capacity(frames);
    let (mut l, mut r) = (vec![0.0; block], vec![0.0; block]);
    while out.len() < frames {
        engine.process(&mut l, &mut r);
        out.extend_from_slice(&l);
    }
    out
}

#[test]
fn the_metronome_follows_the_map() {
    let map = song();
    let (mut engine, mut handle) = Engine::new(SR);
    send(&mut handle, Msg::SetTempoMap(Box::new(map.clone())));
    send(&mut handle, Msg::SetMetronome(true));
    send(&mut handle, Msg::Play);
    let seconds = map.seconds(44.0);
    // An odd block size, so that clicks fall anywhere in a block.
    let out = play(&mut engine, seconds, 333);
    let heard = onsets(&out, 50);
    let mut expected = Vec::new();
    let heard_to = map.beat((out.len() as f64 - 2.0) / SR);
    map.lines(0.0, heard_to, |line| {
        expected.push(line);
        true
    });
    assert!(
        expected
            .iter()
            .any(|l| l.beat > 40.0 && l.beat.fract() == 0.5)
    );
    assert_eq!(
        heard.len(),
        expected.len(),
        "one click per beat of the signature"
    );
    for (at, line) in heard.iter().zip(&expected) {
        // A click starts at a zero crossing, so it is first heard one frame on.
        let want = (map.seconds(line.beat) * SR) as usize + 1;
        assert!(
            at.abs_diff(want) <= 1,
            "click at beat {} heard at frame {at}, expected {want}",
            line.beat
        );
    }
    // Bar lines are accented: compare the first cycle of two clicks.
    let first_bar = heard[0];
    let second_beat = heard[1];
    assert_ne!(
        out[first_bar + 5],
        out[second_beat + 5],
        "the bar's first beat sounds different"
    );
}

#[test]
fn the_click_has_a_level_an_accent_and_an_output() {
    let peak = |out: &[f32]| out.iter().fold(0.0f32, |m, s| m.max(s.abs()));
    let run = |click: Option<Msg>| {
        let (mut engine, mut handle) = Engine::new(SR);
        send(&mut handle, Msg::SetMetronome(true));
        if let Some(click) = click {
            send(&mut handle, click);
        }
        send(&mut handle, Msg::Play);
        let (mut l, mut r) = (vec![0.0; 4800], vec![0.0; 4800]);
        let mut main = Vec::new();
        let mut own = Vec::new();
        for _ in 0..30 {
            engine.process(&mut l, &mut r);
            main.extend_from_slice(&l);
            if let Some((first, cl, _)) = engine.click_output(l.len()) {
                assert_eq!(first, 2, "outputs 3/4 are channels 2 and 3 from 0");
                own.extend_from_slice(cl);
            }
        }
        (main, own)
    };
    let (plain, _) = run(None);
    let (quiet, _) = run(Some(Msg::SetClick {
        gain: 0.5,
        accent: true,
        output: 0,
    }));
    let ratio = peak(&quiet) / peak(&plain);
    assert!((ratio - 0.5).abs() < 0.01, "half the gain, half the level: {ratio}");

    let (flat, _) = run(Some(Msg::SetClick {
        gain: 1.0,
        accent: false,
        output: 0,
    }));
    let heard = onsets(&flat, 50);
    assert_eq!(
        flat[heard[0] + 5],
        flat[heard[1] + 5],
        "with no accent the bar's first beat sounds as the others"
    );

    let (main, own) = run(Some(Msg::SetClick {
        gain: 1.0,
        accent: true,
        output: 3,
    }));
    assert_eq!(peak(&main), 0.0, "on an output of its own, the click is not in the song");
    assert!((peak(&own) - peak(&plain)).abs() < 1e-6, "but on its outputs");
}

#[test]
fn audio_regions_keep_to_time_through_a_ramp() {
    // A file with one click per second: wherever the region starts, its
    // clicks are a second apart however the tempo moves.
    let rate = 48000u32;
    let mut data = vec![0.0f32; rate as usize * 6];
    for second in 0..6 {
        data[second * rate as usize + 100] = 1.0;
    }
    let audio = Arc::new(AudioData {
        sample_rate: rate,
        channels: [data.clone().into(), data.into()],
    });
    let map = song();
    // Starts in the middle of the ramp; it lasts six seconds of beats.
    let start = 10.0;
    let end = map.beat(map.seconds(start) + 6.0);
    let mut clips = ClipSet::default();
    clips.audio.push(AudioRegion {
        start,
        end,
        data: audio,
        offset: 0.0,
        gain: 1.0,
        fade_in: 0.0,
        fade_out: 0.0,
        declick_in: false,
        declick_out: false,
        hold: Default::default(),
        direction: Default::default(),
    });
    clips.finish();
    let (mut engine, mut handle) = Engine::new(SR);
    send(&mut handle, Msg::SetTempoMap(Box::new(map.clone())));
    send(
        &mut handle,
        Msg::InsertTrack {
            slot: TrackSlot(1),
            track: TrackRt::new(),
        },
    );
    send(
        &mut handle,
        Msg::SetClips {
            track: TrackSlot(1),
            clips: Box::new(clips),
        },
    );
    let entries = vec![
        SchedEntry::new(TrackSlot(1), TrackSlot::MASTER),
        SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE),
    ];
    send(
        &mut handle,
        Msg::SetSchedule(Box::new(Schedule::new(entries, 0))),
    );
    send(&mut handle, Msg::Play);
    let out = play(&mut engine, map.seconds(start) + 6.5, 512);
    let heard: Vec<usize> = out
        .iter()
        .enumerate()
        .filter(|(_, s)| s.abs() > 0.5)
        .map(|(i, _)| i)
        .collect();
    assert_eq!(heard.len(), 6, "every click of the file plays: {heard:?}");
    let begin = map.seconds(start) * SR;
    for (k, at) in heard.iter().enumerate() {
        let want = begin + (k * rate as usize + 100) as f64;
        assert!(
            (*at as f64 - want).abs() <= 1.0,
            "click {k} at frame {at}, expected {want}"
        );
    }
}
