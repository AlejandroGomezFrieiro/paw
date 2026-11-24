//! What expanding nest clips costs the sync layer (the spike N0 of the nest
//! design): `count` nest clips of one nest part on 10 host parts, against
//! the same music placed as `count` plain clips.
//!
//! A nest clip in pass mode plays its nest part's clips as clips of the
//! host part: expanding one is making a copy of each nest clip's clips at
//! the place of the nest clip (the copy shares the notes, as a pasted clip
//! does). Then the sync compiles the host's clips as it compiles any others.
//!
//! `cargo bench -p paw-core --bench nest_expand -- [count] [notes] [reps]`
//! prints one JSON line per case: the processor time of the thread, in
//! milliseconds, as the median, minimum and maximum over the repetitions.
//!
//! - `place`: the plain clips, synced into an engine that has none;
//! - `expand`: making the copies of the nest clips (no sync);
//! - `expand+sync`: the copies made and synced into an engine that has none;
//! - `edit plain`: one note of one plain clip changed, synced;
//! - `edit nest`: one note of the nest part changed: every copy is made
//!   again and synced, as each nest clip plays the change;
//! - `edit nest cut`: the same, with each nest clip's window starting 4
//!   beats into the nest: the notes before the cut are left out and the
//!   rest are moved to the window's start, one time for all the copies of
//!   one window;
//! - `edit nest sync`: as `edit nest`, with the copies made before the time
//!   measured: what the sync alone costs.

#![expect(clippy::unwrap_used, reason = "test code: a failed unwrap is a failed test")]
#![cfg_attr(test, expect(clippy::cast_precision_loss, reason = "debt: pay down"))]

use paw_core::model::chain::SplitRegistry as _;
use std::collections::HashMap;
use std::sync::Arc;

use paw_core::model::{Clip, ClipContent, Project, Part};
use paw_core::sync::{AudioCache, LiveDevices, Mapper, SyncCtx, sync};
use paw_engine::Registry;
use serde_json::{Value, json};

const HOSTS: usize = 10;
/// A nest is 8 bars of 4/4 long.
const LENGTH: f64 = 32.0;

/// Processor time of this thread, in milliseconds.
fn cpu_ms() -> f64 {
    let mut t = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    // SAFETY: `t` is a valid timespec for the call to write.
    unsafe { libc::clock_gettime(libc::CLOCK_THREAD_CPUTIME_ID, &raw mut t) };
    t.tv_sec as f64 * 1e3 + t.tv_nsec as f64 / 1e6
}

/// One clip of `notes` notes over the nest's 8 bars, as JSON.
fn nest_clip(notes: usize) -> Value {
    let list: Vec<Value> = (0..notes)
        .map(|k| {
            let start = k as f64 * LENGTH / notes as f64;
            json!({ "start": start, "length": 0.25, "pitch": 48 + (k % 24), "velocity": 90 })
        })
        .collect();
    json!({ "id": 1_000_000, "name": "", "start": 0.0, "length": LENGTH, "muted": false,
            "content": { "kind": "midi", "notes": list } })
}

/// The song: a master and `HOSTS` parts with a synth each and no clips.
fn song() -> Project {
    let part = |id: usize, devices: Value, clips: Value| {
        json!({ "id": id, "name": format!("T{id}"), "volume": 0.0, "pan": 0.0, "mute": false,
            "solo": false, "armed": false, "output": null, "sends": [], "color": null,
            "devices": devices, "clips": clips })
    };
    let parts: Vec<Value> = (1..=HOSTS)
        .map(|i| part(i, json!([{ "id": 100 + i, "kind": "synth", "bypass": false, "params": {} }]), json!([])))
        .collect();
    serde_json::from_value(json!({
        "name": "t", "tempo": 120.0, "sig_num": 4, "sig_den": 4,
        "master": part(0, json!([]), json!([])),
        "parts": parts,
    }))
    .unwrap()
}

fn nest_part(notes: usize) -> Part {
    serde_json::from_value(json!({ "id": 999, "name": "N", "volume": 0.0, "pan": 0.0,
        "mute": false, "solo": false, "armed": false, "output": null, "sends": [],
        "color": null, "devices": [], "clips": [nest_clip(notes)] }))
    .unwrap()
}

/// A nest clip: where it is in the song, from which beat of the nest, how long.
#[derive(Clone, Copy)]
struct Place {
    start: f64,
    offset: f64,
    length: f64,
}

/// The places of `count` nest clips, end to end on the hosts in turn, each
/// showing the nest from beat `offset`.
fn places(count: usize, offset: f64) -> Vec<Vec<Place>> {
    let mut out = vec![Vec::new(); HOSTS];
    for k in 0..count {
        let host = k % HOSTS;
        let start = out[host].len() as f64 * LENGTH;
        out[host].push(Place { start, offset, length: LENGTH - offset });
    }
    out
}

/// A nest clip cut `by` beats after its start: its notes before the cut
/// are left out and the others moved to the cut.
fn cut(clip: &Clip, by: f64) -> Clip {
    let mut out = clip.clone();
    if let ClipContent::Midi { notes, .. } = &mut out.content {
        notes.retain(|n| n.start >= by);
        for n in notes.iter_mut() {
            n.start -= by;
        }
    }
    out.start += by;
    out.length -= by;
    out
}

/// Pass-mode expansion: each of the nest part's clips that a nest clip's
/// window shows, copied to the song's time and cut at the window's ends.
/// A clip cut at the window's start is cut once in `cuts`, which every
/// copy of that window shares, as copies of one clip share its notes.
fn expand(
    nest: &Part,
    at: &[Place],
    cuts: &mut HashMap<(usize, u64), Clip>,
    next_id: &mut u64,
    out: &mut Vec<Arc<Clip>>,
) {
    for p in at {
        for (k, clip) in nest.clips.iter().enumerate() {
            let (from, to) = (clip.start.max(p.offset), (clip.start + clip.length).min(p.offset + p.length));
            if to <= from {
                continue;
            }
            let by = from - clip.start;
            let shown: &Clip = if by > 0.0 {
                &*cuts.entry((k, by.to_bits())).or_insert_with(|| cut(clip, by))
            } else {
                clip
            };
            let mut copy = Clip::clone(shown);
            copy.id = *next_id;
            *next_id += 1;
            copy.start = p.start + (from - p.offset);
            copy.length = to - from;
            out.push(Arc::new(copy));
        }
    }
}

/// The song with the hosts' clips set from the places.
fn expanded(base: &Project, nest: &Part, places: &[Vec<Place>]) -> Project {
    let mut p = base.clone();
    let mut id = 2_000_000;
    let mut cuts = HashMap::new();
    for (i, at) in places.iter().enumerate() {
        let mut clips = Vec::with_capacity(at.len());
        expand(nest, at, &mut cuts, &mut id, &mut clips);
        Arc::make_mut(&mut p.parts[i]).clips = clips.into();
    }
    p
}

struct Syncer {
    registry: Registry,
    sources: paw_core::media::Sources,
    audio: AudioCache,
    live: LiveDevices,
    warnings: Vec<String>,
    map: Mapper,
}

impl Syncer {
    fn new() -> Self {
        Self {
            registry: Registry::with_builtins(),
            sources: Default::default(),
            audio: AudioCache::default(),
            live: LiveDevices::new(),
            warnings: Vec::new(),
            map: Mapper::new(),
        }
    }

    /// Sync from `old` to `new`; the messages are kept until the caller
    /// drops them, out of the time measured.
    fn sync(&mut self, old: &Project, new: &Project, sent: &mut Vec<paw_engine::Msg>) {
        let mut ctx = SyncCtx {
            registry: &self.registry,
            sources: &self.sources,
            audio: &mut self.audio,
            live: &mut self.live,
            sample_rate: 48000.0,
            warnings: &mut self.warnings,
            offline: true,
            waker: Default::default(),
            bell: Default::default(),
            now: paw_core::clock::ScheduleTime::ZERO,
            kinds: &paw_core::model::chain::SplitKinds::builtin(),
            modifiers: &paw_core::model::modifiers::builtin_kinds(),
        };
        sync(old, new, &mut self.map, &mut ctx, &mut |m| sent.push(m), &mut Vec::new());
    }
}

/// One note of a clip, higher by a semitone.
fn bump(clip: &mut Arc<Clip>) {
    if let ClipContent::Midi { notes, .. } = &mut Arc::make_mut(clip).content {
        notes[0].pitch += 1;
    }
}

fn stats(mut xs: Vec<f64>) -> (f64, f64, f64) {
    xs.sort_by(f64::total_cmp);
    (xs[xs.len() / 2], xs[0], xs[xs.len() - 1])
}

fn main() {
    let args: Vec<usize> = std::env::args().skip(1).filter_map(|a| a.parse().ok()).collect();
    let count = args.first().copied().unwrap_or(1000);
    let notes = args.get(1).copied().unwrap_or(96);
    let reps = args.get(2).copied().unwrap_or(9);
    let empty = Project::default();
    let base = song();
    let nest = nest_part(notes);
    let at = places(count, 0.0);
    let at_cut = places(count, 4.0);
    let mut edited_nest = nest.clone();
    bump(&mut edited_nest.clips[0]);

    let names = ["place", "expand", "expand+sync", "edit plain", "edit nest", "edit nest cut", "edit nest sync"];
    let mut cases: Vec<(&str, Vec<f64>)> = names
        .iter()
        .map(|n| (*n, Vec::new()))
        .collect();
    for _ in 0..reps {
        // The plain clips: the expansion made once, out of the time.
        let plain = expanded(&base, &nest, &at);
        let mut s = Syncer::new();
        let mut sent = Vec::new();
        let t = cpu_ms();
        s.sync(&empty, &plain, &mut sent);
        cases[0].1.push(cpu_ms() - t);
        sent.clear();
        let mut edited = plain.clone();
        bump(&mut Arc::make_mut(&mut edited.parts[0]).clips[0]);
        let t = cpu_ms();
        s.sync(&plain, &edited, &mut sent);
        cases[3].1.push(cpu_ms() - t);
        drop(sent);

        let t = cpu_ms();
        let first = expanded(&base, &nest, &at);
        cases[1].1.push(cpu_ms() - t);
        drop(first);

        let mut s = Syncer::new();
        let mut sent = Vec::new();
        let t = cpu_ms();
        let first = expanded(&base, &nest, &at);
        s.sync(&empty, &first, &mut sent);
        cases[2].1.push(cpu_ms() - t);
        sent.clear();
        let t = cpu_ms();
        let second = expanded(&base, &edited_nest, &at);
        s.sync(&first, &second, &mut sent);
        cases[4].1.push(cpu_ms() - t);
        drop(sent);

        let mut s = Syncer::new();
        let mut sent = Vec::new();
        s.sync(&empty, &first, &mut sent);
        sent.clear();
        let second = expanded(&base, &edited_nest, &at);
        let t = cpu_ms();
        s.sync(&first, &second, &mut sent);
        cases[6].1.push(cpu_ms() - t);
        drop(sent);

        let mut s = Syncer::new();
        let mut sent = Vec::new();
        let first = expanded(&base, &nest, &at_cut);
        s.sync(&empty, &first, &mut sent);
        sent.clear();
        let t = cpu_ms();
        let second = expanded(&base, &edited_nest, &at_cut);
        s.sync(&first, &second, &mut sent);
        cases[5].1.push(cpu_ms() - t);
    }
    for (name, xs) in cases {
        let (median, min, max) = stats(xs);
        println!(
            "{{\"bench\":\"nest_expand\",\"case\":\"{name}\",\"nest_clips\":{count},\"notes_per_clip\":{notes},\"reps\":{reps},\"cpu_ms_median\":{median:.3},\"cpu_ms_min\":{min:.3},\"cpu_ms_max\":{max:.3}}}"
        );
    }
}
