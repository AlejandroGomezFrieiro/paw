//! What a block costs with many audio regions in one piece against a few:
//! the same two regions sound under the playhead either way.
//!
//! `cargo bench -p paw-engine --bench regions -- <regions> [backward]`
//! prints one JSON line: the median and the spread of the mean time of a
//! block of 128 frames over the rounds.

use std::sync::Arc;
use std::time::Instant;

use paw_engine::{
    AudioData, AudioRegion, ClipSet, Engine, EngineHandle, Msg, Piece, SchedEntry, Schedule,
    TrackRt, TrackSlot,
};

const SR: f64 = 48000.0;
const BLOCK: usize = 128;
/// Each region's length in beats, and the beat the rounds play from.
const LENGTH: f64 = 0.25;
const AT: f64 = 1250.0;
const ROUNDS: usize = 400;
const BLOCKS: usize = 40;

fn send(handle: &mut EngineHandle, msg: Msg) {
    assert!(handle.try_send(msg).is_ok(), "message queue full");
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).filter(|a| a != "--bench").collect();
    let count: usize = args.first().and_then(|a| a.parse().ok()).unwrap_or(10_000);
    let backward = args.iter().any(|a| a == "backward");
    let tone: Vec<f32> = (0..SR as usize).map(|i| (i as f32 * 0.03).sin()).collect();
    let data = Arc::new(AudioData {
        sample_rate: SR as u32,
        channels: [tone.clone().into(), tone.into()],
    });
    // Regions end to end around beat `AT`: the many from beat 0, the few
    // only the ones next to it.
    let middle = (AT / LENGTH) as usize;
    let first = if count >= 2 * middle { 0 } else { middle - count / 2 };
    let regions = (first..first + count)
        .map(|k| {
            let region = AudioRegion {
                start: k as f64 * LENGTH,
                end: (k + 1) as f64 * LENGTH,
                data: data.clone(),
                offset: 0.1,
                gain: 0.5,
                fade_in: 0.01,
                fade_out: 0.01,
                declick_in: true,
                declick_out: true,
                hold: Default::default(),
                direction: Default::default(),
            };
            if backward { region.reversed().unwrap() } else { region }
        })
        // In the order a long glue of slices is laid out in: not sorted.
        .rev()
        .collect();
    let set = ClipSet::default().with_pieces(vec![Piece::new(1, 1, Arc::from([]), regions)], 4);
    let (mut engine, mut handle) = Engine::new(SR);
    for msg in [
        Msg::InsertTrack { slot: TrackSlot(1), track: TrackRt::new() },
        Msg::SetClips { track: TrackSlot(1), clips: Box::new(set) },
        Msg::SetSchedule(Box::new(Schedule::new(
            vec![
                SchedEntry::new(TrackSlot(1), TrackSlot::MASTER),
                SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE),
            ],
            0,
        ))),
        Msg::SetTempo(120.0),
        Msg::Play,
    ] {
        send(&mut handle, msg);
    }
    let (mut left, mut right) = (vec![0.0f32; BLOCK], vec![0.0f32; BLOCK]);
    let mut means = Vec::with_capacity(ROUNDS);
    let mut peak = 0.0f32;
    for _ in 0..ROUNDS {
        send(&mut handle, Msg::Seek(AT));
        // The seek is taken in the first block, which is not timed.
        engine.process(&mut left, &mut right);
        let began = Instant::now();
        for _ in 0..BLOCKS {
            engine.process(&mut left, &mut right);
            peak = peak.max(left.iter().fold(0.0, |m, x| m.max(x.abs())));
        }
        means.push(began.elapsed().as_nanos() as f64 / BLOCKS as f64);
        handle.collect_garbage();
    }
    assert!(peak > 0.1, "the regions should sound");
    means.sort_by(f64::total_cmp);
    println!(
        "{{\"regions\":{count},\"backward\":{backward},\"block\":{BLOCK},\"median_ns\":{:.0},\"min_ns\":{:.0},\"max_ns\":{:.0}}}",
        means[ROUNDS / 2],
        means[0],
        means[ROUNDS - 1]
    );
}
