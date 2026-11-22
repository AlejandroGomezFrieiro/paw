use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;

use paw_engine::{Engine, EngineHandle, MidiEv, Msg, ParamInfo, Registry};
use serde_json::{Value, json};

use super::*;
use crate::model::{Clip, ClipContent, Project};


/// A track with a synth and `clips` short clips that overlap, the same
/// keys in each, and one long clip of 1000 notes and some controllers.
fn project(clips: usize) -> Project {
    let note = |start: f64, pitch: u64| {
        json!({ "start": start, "length": 0.75, "pitch": pitch, "velocity": 90 })
    };
    let mut list: Vec<Value> = (0..clips)
        .map(|i| {
            let notes: Vec<Value> = (0..6).map(|k| note(k as f64 * 0.5, 48 + (k % 3))).collect();
            json!({
                "id": 100 + i, "name": "", "start": (i % 9) as f64 * 1.25, "length": 3.0,
                "muted": false, "content": { "kind": "midi", "notes": notes },
            })
        })
        .collect();
    let notes: Vec<Value> = (0..1000).map(|k| note(k as f64 * 0.125, 60 + (k % 7))).collect();
    let controls: Vec<Value> = (0..20)
        .map(|k| json!({ "start": k as f64, "type": "cc", "number": 1, "value": k as f64 / 20.0 }))
        .collect();
    list.push(json!({
        "id": 99, "name": "long", "start": 0.5, "length": 130.0, "muted": false,
        "content": { "kind": "midi", "notes": notes, "controls": controls },
    }));
    let track = |id: u64, name: &str, devices: Value, clips: Value| {
        json!({ "id": id, "name": name, "volume": 0.0, "pan": 0.0, "mute": false, "solo": false,
            "armed": false, "output": null, "sends": [], "color": null,
            "devices": devices, "clips": clips })
    };
    let synth = json!([{ "id": 2, "kind": "synth", "bypass": false, "params": {} }]);
    let project = json!({
        "name": "t", "tempo": 120.0, "sig_num": 4, "sig_den": 4,
        "master": track(0, "Master", json!([]), json!([])),
        "tracks": [track(1, "T", synth, Value::Array(list))],
    });
    serde_json::from_value(project).unwrap()
}

/// The events compiled for track 1, by where they are kept.
fn compiled(map: &Mapper) -> HashMap<*const MidiEv, usize> {
    let Some(parts) = map.parts.get(&1) else { return HashMap::new() };
    let pieces = parts.clips.values().flat_map(|s| &s.pieces);
    pieces.map(|p| (p.as_ptr(), p.len())).collect()
}

/// An engine brought through each of `states` in turn, as a session
/// syncs it; what it was sent for the last, and how many events were
/// compiled for it.
fn engine(states: &[&Project]) -> (Engine, EngineHandle, (Vec<&'static str>, usize)) {
    let (mut engine, mut handle) = Engine::new(48000.0);
    let registry = Registry::with_builtins();
    let sources = crate::media::Sources::default();
    let (mut audio, mut live, mut warnings) = (AudioCache::default(), LiveDevices::new(), Vec::new());
    let mut map = Mapper::new();
    let empty = Project::default();
    let mut last = Vec::new();
    let mut fresh = 0;
    let mut old = &empty;
    for state in states {
        let mut ctx = SyncCtx {
            registry: &registry,
            sources: &sources,
            audio: &mut audio,
            live: &mut live,
            sample_rate: 48000.0,
            warnings: &mut warnings,
            offline: true,
        };
        let mut sent = Vec::new();
        let before = compiled(&map);
        sync(old, state, &mut map, &mut ctx, &mut |msg| sent.push(msg), &mut Vec::new());
        let after = compiled(&map);
        fresh = after.iter().filter(|(p, _)| !before.contains_key(p)).map(|(_, n)| n).sum();
        last = sent
            .iter()
            .map(|m| match m {
                Msg::SetClips { .. } => "clips",
                Msg::EditClips { .. } => "edit",
                _ => "other",
            })
            .collect();
        for msg in sent {
            handle.send_while(msg, &mut engine);
        }
        old = state;
    }
    (engine, handle, (last, fresh))
}

fn play(engine: &mut Engine, handle: &mut EngineHandle, from: f64) -> Vec<f32> {
    handle.send_while(Msg::Seek(from), engine);
    handle.send_while(Msg::Play, engine);
    let (mut l, mut r) = (vec![0.0; 512], vec![0.0; 512]);
    let mut out = Vec::new();
    for _ in 0..150 {
        engine.process(&mut l, &mut r);
        out.extend_from_slice(&l);
        out.extend_from_slice(&r);
    }
    handle.collect_garbage();
    out
}

type Edit = Box<dyn Fn(&mut Project)>;

fn long(p: &mut Project) -> &mut Clip {
    let clips = &mut p.track_mut(1).unwrap().clips;
    let last = clips.len() - 1;
    Arc::make_mut(&mut clips[last])
}

/// Edits of a few clips are sent as the parts they changed; what the
/// engine plays then is what it plays when sent every clip whole.
#[test]
fn edits_sent_as_parts_play_as_the_project_sent_whole() {
    let edits: Vec<Edit> = vec![
        Box::new(|p| Arc::make_mut(&mut p.track_mut(1).unwrap().clips[150]).start = 2.0),
        Box::new(|p| {
            p.track_mut(1).unwrap().clips.remove(10);
        }),
        Box::new(|p| {
            let mut clip = (*p.track(1).unwrap().clips[20]).clone();
            clip.id = 9000;
            clip.start = 1.0;
            p.track_mut(1).unwrap().clips.insert(30, Arc::new(clip));
        }),
        Box::new(|p| Arc::make_mut(&mut p.track_mut(1).unwrap().clips[70]).muted = true),
        // Two notes of the long clip: one run of its notes changes.
        Box::new(|p| {
            if let ClipContent::Midi { notes, .. } = &mut long(p).content {
                notes[500].pitch = 40;
                notes[501].start += 0.0625;
            }
        }),
        Box::new(|p| long(p).start = 1.0),
        Box::new(|p| {
            if let ClipContent::Midi { notes, .. } = &mut long(p).content {
                notes.remove(3);
            }
        }),
    ];
    let mut states = vec![project(300)];
    for edit in &edits {
        let mut next = states.last().unwrap().clone();
        edit(&mut next);
        states.push(next);
    }
    for k in 1..states.len() {
        let path: Vec<&Project> = states[..=k].iter().collect();
        let (mut a, mut ha, (sent, fresh)) = engine(&path);
        assert!(sent.contains(&"edit") && !sent.contains(&"clips"), "edit {k} sent {sent:?}");
        if k == 5 || k == 7 {
            // Notes of the long clip: only their piece is compiled again
            // (two events a note, at most 511 notes a piece, and the
            // controllers), not the clip's 2000 events.
            assert!(fresh <= 2 * 511 + 20, "edit {k}: {fresh} events compiled");
        }
        let (mut b, mut hb, _) = engine(&[&states[k]]);
        for from in [0.0, 3.4, 60.0] {
            let (x, y) = (play(&mut a, &mut ha, from), play(&mut b, &mut hb, from));
            assert!(x.iter().any(|s| *s != 0.0));
            assert!(x == y, "edit {k}: what plays from {from} differs");
        }
    }
}

fn param(key: &str, id: &str) -> ParamInfo {
    ParamInfo {
        id: id.into(),
        ..ParamInfo::new(key, 0.0, 1.0, 0.0, "")
    }
}

#[test]
fn parameters_keep_the_keys_the_project_knows_them_by() {
    // A new version of the plugin swapped two parameters of one name:
    // "gain" is now the one the project knew as "gain_2".
    let mut params = vec![param("gain", "20"), param("gain_2", "10"), param("mix", "30")];
    let ids = BTreeMap::from([("gain".to_string(), "10".to_string())]);
    rekey(&mut params, &ids);
    let keys: Vec<&str> = params.iter().map(|p| p.key.as_str()).collect();
    assert_eq!(keys, ["gain_2", "gain", "mix"]);
    // Renamed: the project's key wins, and an id it does not know changes nothing.
    let mut params = vec![param("drive", "7")];
    let ids = BTreeMap::from([
        ("distortion".to_string(), "7".to_string()),
        ("gone".to_string(), "99".to_string()),
    ]);
    rekey(&mut params, &ids);
    assert_eq!(params[0].key, "distortion");
}

/// A project of one track, with a synth when it has MIDI, and one clip.
fn with_clip(content: Value, synth: bool) -> Project {
    let devices = if synth {
        json!([{ "id": 2, "kind": "synth", "bypass": false, "params": {} }])
    } else {
        json!([])
    };
    let track = |id: u64, devices: Value, clips: Value| {
        json!({ "id": id, "name": "T", "volume": 0.0, "pan": 0.0, "mute": false, "solo": false,
            "armed": false, "output": null, "sends": [], "color": null,
            "devices": devices, "clips": clips })
    };
    let clip = json!({ "id": 7, "name": "", "start": 0.0, "length": 4.0, "muted": false,
        "content": content });
    serde_json::from_value(json!({
        "name": "t", "tempo": 120.0, "sig_num": 4, "sig_den": 4,
        "master": track(0, json!([]), json!([])),
        "tracks": [track(1, devices, json!([clip]))],
    }))
    .unwrap()
}

/// A custom clip of a kind nothing knows, with `sound`.
fn custom(sound: Value) -> Value {
    json!({ "kind": "custom", "type": "idea", "data": { "json": "{}" }, "sound": sound })
}

fn played(project: &Project) -> Vec<f32> {
    let (mut engine, mut handle, _) = engine(&[project]);
    play(&mut engine, &mut handle, 0.0)
}

/// A custom clip plays its sound as the clip of that sound does: MIDI to
/// the track's instrument.
#[test]
fn a_custom_clip_plays_its_midi_sound() {
    let midi = json!({ "kind": "midi", "notes": [
        { "start": 0.0, "length": 1.0, "pitch": 60, "velocity": 100 },
        { "start": 1.0, "length": 1.0, "pitch": 64, "velocity": 100 },
    ] });
    let own = played(&with_clip(midi.clone(), true));
    assert!(own.iter().any(|s| *s != 0.0), "the MIDI clip sounds");
    assert!(own == played(&with_clip(custom(midi), true)), "the custom clip sounds the same");
    let none = json!({ "kind": "custom", "type": "idea", "data": { "json": "{}" } });
    assert!(
        played(&with_clip(none, true)).iter().all(|s| *s == 0.0),
        "a custom clip with no sound is silent"
    );
}

/// A custom clip with an audio sound is scheduled as the audio clip is.
#[test]
fn a_custom_clip_plays_its_audio_sound() {
    let dir = std::env::temp_dir().join(format!("paw-sync-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("tone.wav");
    let samples: Vec<i16> = (0..24000)
        .map(|i| ((i as f32 * 0.05).sin() * 12000.0) as i16)
        .collect();
    let mut wav = Vec::new();
    let data = (samples.len() * 2) as u32;
    wav.extend(b"RIFF");
    wav.extend((36 + data).to_le_bytes());
    wav.extend(b"WAVEfmt ");
    wav.extend(16u32.to_le_bytes());
    wav.extend([1, 0, 1, 0]);
    wav.extend(48000u32.to_le_bytes());
    wav.extend(96000u32.to_le_bytes());
    wav.extend([2, 0, 16, 0]);
    wav.extend(b"data");
    wav.extend(data.to_le_bytes());
    wav.extend(samples.iter().flat_map(|s| s.to_le_bytes()));
    std::fs::write(&file, wav).unwrap();
    let audio = json!({ "kind": "audio", "file": file, "offset": 0.1, "gain": -3.0 });
    let own = played(&with_clip(audio.clone(), false));
    let wrapped = played(&with_clip(custom(audio), false));
    std::fs::remove_dir_all(&dir).unwrap();
    assert!(own.iter().any(|s| *s != 0.0), "the audio clip sounds");
    assert!(own == wrapped, "the custom clip sounds the same");
}

/// Whether track 1 hears MIDI input after a sync with `follow`, while
/// track 2 is armed.
fn follows(follow: Follow) -> bool {
    let track = |id: u64, armed: bool| {
        json!({ "id": id, "name": "", "volume": 0.0, "pan": 0.0, "mute": false, "solo": false,
            "armed": armed, "output": null, "sends": [], "color": null, "devices": [], "clips": [] })
    };
    let project: Project = serde_json::from_value(json!({
        "name": "t", "tempo": 120.0, "sig_num": 4, "sig_den": 4,
        "master": track(0, false), "tracks": [track(1, false), track(2, true)],
    }))
    .unwrap();
    let registry = Registry::with_builtins();
    let sources = crate::media::Sources::default();
    let (mut audio, mut live, mut warnings) = (AudioCache::default(), LiveDevices::new(), Vec::new());
    let mut ctx = SyncCtx {
        registry: &registry,
        sources: &sources,
        audio: &mut audio,
        live: &mut live,
        sample_rate: 48000.0,
        warnings: &mut warnings,
        offline: true,
    };
    let mut map = Mapper::new();
    map.follow = follow;
    let mut sent = Vec::new();
    sync(&Project::default(), &project, &mut map, &mut ctx, &mut |msg| sent.push(msg), &mut Vec::new());
    let slot = map.tracks[&1];
    sent.iter().any(|m| matches!(m, Msg::SetInput { track, monitor: true, .. } if *track == slot))
}

/// The selected track yields to an armed one; step input's track does not.
#[test]
fn the_track_that_always_follows_hears_midi_while_another_is_armed() {
    assert!(!follows(Follow { selected: Some(1), always: None }));
    assert!(follows(Follow { selected: None, always: Some(1) }));
}

/// A clip of `notes` notes over 32 beats, with two controller moves.
fn source_clip(notes: usize) -> Clip {
    let list: Vec<Value> = (0..notes)
        .map(|k| {
            let start = k as f64 * 32.0 / notes as f64;
            json!({ "start": start, "length": 0.3, "pitch": 48 + (k * 5) % 24, "velocity": 30 + k % 90 })
        })
        .collect();
    let controls = json!([
        { "start": 0.0, "type": "cc", "number": 1, "value": 0.25 },
        { "start": 5.5, "type": "cc", "number": 1, "value": 0.75 },
    ]);
    serde_json::from_value(json!({ "id": 7, "name": "", "start": 0.0, "length": 32.0, "muted": false,
        "content": { "kind": "midi", "notes": list, "controls": controls } }))
    .unwrap()
}

/// `source` cut `by` beats after its start, as a window that starts there
/// shows it: the notes before the cut left out, the others moved to it.
fn cut(source: &Clip, by: f64) -> Clip {
    let mut out = source.clone();
    if let ClipContent::Midi { notes, controls } = &mut out.content {
        notes.retain(|n| n.start >= by);
        for n in notes.iter_mut() {
            n.start -= by;
        }
        for c in controls.iter_mut() {
            c.start -= by;
        }
    }
    out.length -= by;
    out
}

/// Track 1 of `base` with `count` copies of `source` end to end, each
/// sharing its notes as a pasted clip does; every third copy is looped,
/// every fifth a window cut at its start (one cut, which those copies
/// share), every seventh cut short.
fn with_copies(base: &Project, source: &Clip, count: usize) -> Project {
    let cut = cut(source, 4.5);
    let mut p = base.clone();
    let clips: Vec<Arc<Clip>> = (0..count)
        .map(|k| {
            let mut copy = if k % 5 == 4 { cut.clone() } else { source.clone() };
            copy.id = 1000 + k as u64;
            copy.start = k as f64 * 33.25 + 0.125;
            if k % 3 == 2 {
                (copy.looped, copy.loop_start, copy.loop_length) = (true, 1.5, Some(6.25));
            }
            if k % 7 == 6 {
                copy.length = 9.75;
            }
            Arc::new(copy)
        })
        .collect();
    p.track_mut(1).unwrap().clips = clips.into();
    p
}

/// One note of `clip` a semitone higher.
fn bumped(clip: &Clip) -> Clip {
    let mut out = clip.clone();
    if let ClipContent::Midi { notes, .. } = &mut out.content {
        notes[100].pitch += 1;
    }
    out
}

/// A mapper brought through `states` in turn, and how many times events
/// were compiled for the last.
fn compiles(states: &[&Project]) -> (Mapper, usize) {
    let registry = Registry::with_builtins();
    let sources = crate::media::Sources::default();
    let (mut audio, mut live, mut warnings) = (AudioCache::default(), LiveDevices::new(), Vec::new());
    let mut map = Mapper::new();
    let empty = Project::default();
    let (mut old, mut count) = (&empty, 0);
    for state in states {
        let mut ctx = SyncCtx {
            registry: &registry,
            sources: &sources,
            audio: &mut audio,
            live: &mut live,
            sample_rate: 48000.0,
            warnings: &mut warnings,
            offline: true,
        };
        let before = clips::COMPILES.with(|c| c.get());
        sync(old, state, &mut map, &mut ctx, &mut |_| {}, &mut Vec::new());
        count = clips::COMPILES.with(|c| c.get()) - before;
        old = state;
    }
    (map, count)
}

/// Copies of a clip share its compiled events: an edit of the notes they
/// share compiles them one time, however many copies play them.
#[test]
fn an_edit_of_notes_that_copies_share_compiles_them_once() {
    let base = with_clip(json!({ "kind": "midi", "notes": [] }), true);
    let copies = |source: &Clip, count: usize| {
        let mut p = base.clone();
        let clips: Vec<Arc<Clip>> = (0..count)
            .map(|k| Arc::new(Clip { id: 1000 + k as u64, start: k as f64 * 32.0, ..source.clone() }))
            .collect();
        p.track_mut(1).unwrap().clips = clips.into();
        p
    };
    let source = source_clip(384);
    let (a, b) = (copies(&source, 100), copies(&bumped(&source), 100));
    let (map, count) = compiles(&[&a, &b]);
    assert_eq!(count, 1, "the piece of notes the edit changed, one time");
    // The engine has one list of each piece for all the copies.
    assert_eq!(compiled(&map).len(), 2, "the controllers and the notes");
    // A thousand copies, sent whole: as many lists as for one.
    let (map, count) = compiles(&[&copies(&source, 1000)]);
    assert_eq!((count, compiled(&map).len()), (2, 2));
}

/// An edit of one clip of a link of 10 reaches the other 9 as the same
/// notes (`model/links.rs`): the sync compiles them one time.
#[test]
fn an_edit_of_a_link_of_ten_clips_compiles_once() {
    let mut linked = with_clip(json!({ "kind": "midi", "notes": [] }), true);
    let source = Clip { link: Some("riff".into()), ..source_clip(384) };
    let clips: Vec<Arc<Clip>> = (0..10)
        .map(|k| Arc::new(Clip { id: 1000 + k, start: k as f64 * 32.0, ..source.clone() }))
        .collect();
    linked.track_mut(1).unwrap().clips = clips.into();
    let mut edited = linked.clone();
    let links = crate::model::Links::before(&edited);
    let fourth = Arc::make_mut(&mut edited.track_mut(1).unwrap().clips[3]);
    *fourth = bumped(fourth);
    links.spread(&mut edited);
    let (map, count) = compiles(&[&linked, &edited]);
    assert_eq!(count, 1, "the piece of notes the edit changed, one time");
    // Every clip of the link plays the edit, from one list of events.
    let pitches: Vec<u8> = edited.track(1).unwrap().clips.iter().map(|clip| match &clip.content {
        ClipContent::Midi { notes, .. } => notes[100].pitch,
        _ => 0,
    }).collect();
    let bumped_pitch = pitches[3];
    assert!(pitches.iter().all(|p| *p == bumped_pitch), "{pitches:?}");
    assert_eq!(compiled(&map).len(), 2, "the controllers and the notes");
}

/// The engine plays copies that share their events, looped, cut at the
/// start of a window or short, as it plays every clip's events compiled
/// where it is, in one list: the same samples.
#[test]
fn copies_that_share_events_play_as_events_compiled_in_place() {
    let base = with_clip(json!({ "kind": "midi", "notes": [] }), true);
    let project = with_copies(&base, &source_clip(384), 24);
    let (mut a, mut ha, _) = engine(&[&project]);
    let (mut b, mut hb, _) = engine(&[&project]);
    // In place: as the sync compiled every clip before copies shared them.
    let mut list = ClipSet::default();
    for clip in project.track(1).unwrap().clips.iter() {
        if let Some(ClipContent::Midi { notes, controls }) = clip.playable() {
            let events = clips::Source::whole(clip, notes, controls).compile(clip.start);
            list.midi.extend_from_slice(&events);
        }
    }
    list.finish();
    let slot = paw_engine::TrackSlot(paw_engine::TrackSlot::MASTER.0 + 1);
    hb.send_while(Msg::SetClips { track: slot, clips: Box::new(list) }, &mut b);
    for from in [0.0, 37.6, 133.1, 166.0, 402.2] {
        let (x, y) = (play(&mut a, &mut ha, from), play(&mut b, &mut hb, from));
        assert!(x.iter().any(|s| *s != 0.0), "something plays from {from}");
        assert!(x == y, "what plays from {from} differs");
    }
}

// Subprojects (nests) -------------------------------------------------------------------

/// A track as a project file has it.
fn track_json(id: u64, name: &str, nest: Option<u64>, devices: Value, clips: Value) -> Value {
    json!({ "id": id, "name": name, "volume": 0.0, "pan": 0.0, "mute": false, "solo": false,
        "armed": false, "output": null, "sends": [], "color": null, "nest": nest,
        "devices": devices, "clips": clips })
}

/// A synth, and a reverb after it when `reverb`.
fn instrument(reverb: bool) -> Value {
    let mut list = vec![json!({ "id": 13, "kind": "synth", "bypass": false, "params": {} })];
    if reverb {
        list.push(json!({ "id": 16, "kind": "reverb", "bypass": false, "params": {} }));
    }
    Value::Array(list)
}

/// A project: song tracks, and nest 10 (`Ballad`, `length` beats) whose
/// master is track 11 and whose track 12 (`Keys`) holds `keys` with its
/// instrument.
fn with_nest(song: Vec<Value>, length: f64, keys: &Clip, instrument: Value) -> Project {
    let mut tracks = song;
    tracks.push(track_json(11, "Master", Some(10), json!([]), json!([])));
    tracks.push(track_json(12, "Keys", Some(10), instrument, json!([keys])));
    serde_json::from_value(json!({
        "name": "t", "tempo": 120.0, "sig_num": 4, "sig_den": 4,
        "master": track_json(0, "Master", None, json!([]), json!([])),
        "tracks": tracks,
        "nests": [{ "id": 10, "name": "Ballad", "length": length, "master": 11 }],
    }))
    .unwrap()
}

/// The return row (track 1) with blocks of nest 10 that play its mix, at
/// `starts`, `length` long.
fn row(starts: &[f64], length: f64, muted: bool) -> Value {
    let blocks: Vec<Value> = starts
        .iter()
        .enumerate()
        .map(|(k, s)| {
            json!({ "id": 100 + k as u64, "name": "", "start": s, "length": length, "muted": muted,
                "content": { "kind": "nest", "nest": 10, "play": "master" } })
        })
        .collect();
    track_json(1, "Ballad", None, json!([]), Value::Array(blocks))
}

/// A short clip of three notes.
fn phrase() -> Clip {
    serde_json::from_value(json!({ "id": 14, "name": "", "start": 0.0, "length": 4.0, "muted": false,
        "content": { "kind": "midi", "notes": [
            { "start": 0.0, "length": 0.5, "pitch": 60, "velocity": 100 },
            { "start": 1.0, "length": 0.5, "pitch": 64, "velocity": 100 },
            { "start": 2.5, "length": 1.0, "pitch": 67, "velocity": 100 } ] } }))
    .unwrap()
}

/// The same phrase on one song track with the same synth, at `starts`.
fn plain(starts: &[f64]) -> Project {
    let clips: Vec<Clip> = starts
        .iter()
        .enumerate()
        .map(|(k, s)| Clip { id: 200 + k as u64, start: *s, ..phrase() })
        .collect();
    serde_json::from_value(json!({
        "name": "t", "tempo": 120.0, "sig_num": 4, "sig_den": 4,
        "master": track_json(0, "Master", None, json!([]), json!([])),
        "tracks": [track_json(1, "Keys", None, instrument(false), json!(clips))],
    }))
    .unwrap()
}

fn played_from(project: &Project, from: f64) -> Vec<f32> {
    let (mut engine, mut handle, _) = engine(&[project]);
    play(&mut engine, &mut handle, from)
}

fn peak(samples: &[f32]) -> f32 {
    samples.iter().fold(0.0f32, |m, s| m.max(s.abs()))
}

/// A synth in a subproject plays into its return row as the same synth and
/// notes play on a song track at the same place, below -120 dB of the peak:
/// the sound goes through two more faders (the subproject's master and the
/// row), and a fader's centre gain (`SQRT_2 * cos(PI / 4)` in `f32`) is 1
/// only to within a unit of the last place. Two blocks of the subproject
/// on the row play it twice.
#[test]
fn a_subproject_plays_as_its_notes_on_a_song_track() {
    let nest = with_nest(vec![row(&[32.0, 48.0], 8.0, false)], 8.0, &phrase(), instrument(false));
    let song = plain(&[32.0, 48.0]);
    for from in [31.5, 47.5] {
        let (a, b) = (played_from(&nest, from), played_from(&song, from));
        assert!(a.iter().any(|s| *s != 0.0), "the block at {} plays", from + 0.5);
        let worst = a.iter().zip(&b).fold(0.0f32, |m, (x, y)| m.max((x - y).abs()));
        assert!(worst < peak(&b) * 1e-6, "from {from} the subproject plays as the song track does: {worst}");
    }
}

/// A muted block is silent; a reverb inside rings on past a block's end.
#[test]
fn a_muted_block_is_silent_and_a_tail_rings_past_the_end() {
    let muted = with_nest(vec![row(&[32.0], 4.0, true)], 4.0, &phrase(), instrument(true));
    assert!(played_from(&muted, 31.5).iter().all(|s| *s == 0.0), "a muted block is silent");
    // The block ends at beat 36. From 32, 4.5 beats at 120 bpm is 2.25 s:
    // after it only the reverb plays.
    let open = with_nest(vec![row(&[32.0], 4.0, false)], 4.0, &phrase(), instrument(true));
    let (mut engine, mut handle, _) = engine(&[&open]);
    handle.send_while(Msg::Seek(32.0), &mut engine);
    handle.send_while(Msg::Play, &mut engine);
    let (mut l, mut r) = (vec![0.0; 512], vec![0.0; 512]);
    for _ in 0..(48000 * 9 / 4 / 512) {
        engine.process(&mut l, &mut r);
    }
    let mut tail = 0.0f32;
    for _ in 0..20 {
        engine.process(&mut l, &mut r);
        tail = tail.max(peak(&l));
    }
    assert!(tail > 1e-4, "the reverb rings past the end of the block: {tail}");
}

/// The return row's fader and its sends act on the subproject's sound.
#[test]
fn the_return_row_mixes_the_subproject() {
    let loud = with_nest(vec![row(&[32.0], 8.0, false)], 8.0, &phrase(), instrument(false));
    let full = played_from(&loud, 31.5);
    let mut half = loud.clone();
    Arc::make_mut(half.tracks.iter_mut().find(|t| t.id == 1).unwrap()).volume = 20.0 * 0.5f64.log10();
    let quiet = played_from(&half, 31.5);
    assert!((peak(&quiet) / peak(&full) - 0.5).abs() < 1e-3, "-6 dB on the row halves it");
    // A send of the row to a song track with a reverb.
    let reverb = json!([{ "id": 30, "kind": "reverb", "bypass": false, "params": {} }]);
    let verb: crate::model::Track = serde_json::from_value(track_json(3, "Verb", None, reverb, json!([]))).unwrap();
    let mut sent = loud.clone();
    sent.tracks.push(Arc::new(verb));
    assert!(played_from(&sent, 31.5) == full, "a song reverb with no send changes nothing");
    let send = crate::model::Send { target: 3, level: 0.0, pre: false };
    Arc::make_mut(sent.tracks.iter_mut().find(|t| t.id == 1).unwrap()).sends.push(send);
    let wet = played_from(&sent, 31.5);
    assert!(wet != full, "the send reaches the song's reverb");
}

/// An edit inside a subproject reaches the engine and compiles one time,
/// however many blocks play it.
#[test]
fn an_edit_inside_a_subproject_compiles_once() {
    let source = source_clip(384);
    let starts: Vec<f64> = (0..8).map(|k| k as f64 * 32.0).collect();
    let a = with_nest(vec![row(&starts, 32.0, false)], 32.0, &source, instrument(false));
    let b = with_nest(vec![row(&starts, 32.0, false)], 32.0, &bumped(&source), instrument(false));
    let (_, count) = compiles(&[&a, &b]);
    assert_eq!(count, 1, "the piece of notes the edit changed, one time");
    let (_, _, (sent, _)) = engine(&[&a, &b]);
    assert!(sent.contains(&"edit"), "the engine gets the parts that changed: {sent:?}");
}
