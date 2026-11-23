use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;

use paw_engine::{
    Controller, Device, DeviceFactory, DeviceInfo, Engine, EngineHandle, Instance, Io, MidiEv, Msg, ParamInfo,
    ProcessCtx, Registry,
};
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
            waker: Default::default(),
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

/// A half second of a tone at 48 kHz, as a 16-bit mono WAV file `name` in
/// a scratch folder of the test, which the caller removes.
fn tone_wav(name: &str) -> (std::path::PathBuf, std::path::PathBuf) {
    let dir = std::env::temp_dir().join(format!("paw-sync-test-{name}-{}", std::process::id()));
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
    (dir, file)
}

/// A custom clip with an audio sound is scheduled as the audio clip is.
#[test]
fn a_custom_clip_plays_its_audio_sound() {
    let (dir, file) = tone_wav("custom");
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
        waker: Default::default(),
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
            waker: Default::default(),
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

/// A copy with overrides (`model/overrides.rs`) plays its notes transposed
/// and with the velocity change, as a copy whose notes were changed that
/// way does, while the first copy, which shares the same notes, plays
/// them as they are. A note that the transpose takes above 127 is silent.
#[test]
fn a_copy_with_overrides_plays_its_notes_changed() {
    let note = |pitch: u64, velocity: u64| json!({ "start": 0.0, "length": 1.0, "pitch": pitch, "velocity": velocity });
    let two_copies = |second: Value, overrides: Value| {
        let mut p = with_clip(json!({ "kind": "midi", "notes": [note(60, 100), note(126, 100)] }), true);
        let first = p.track(1).unwrap().clips[0].clone();
        let mut copy: Clip = serde_json::from_value(json!({ "id": 8, "name": "", "start": 2.0, "length": 4.0,
            "muted": false, "content": { "kind": "midi", "notes": second }, "overrides": overrides }))
        .unwrap();
        // The copy with overrides shares the first copy's notes, as a link does.
        if overrides != json!({}) {
            copy.content = first.content.clone();
        }
        p.track_mut(1).unwrap().clips = vec![first, Arc::new(copy)].into();
        p
    };
    let notes = json!([note(60, 100), note(126, 100)]);
    let overridden = played(&two_copies(notes, json!({ "transpose": 3, "velocity": -10 })));
    let changed = played(&two_copies(json!([note(63, 90)]), json!({})));
    assert!(overridden.iter().any(|s| *s != 0.0), "the copies sound");
    assert!(overridden == changed, "the copy plays its notes as changed notes play");
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

/// A frozen block plays its file on the row, as an audio clip of that file
/// there does, and nothing of its subproject: the synth inside rests.
#[test]
fn a_frozen_block_plays_its_file_and_its_subproject_rests() {
    let (dir, file) = tone_wav("frozen-block");
    let mut frozen = with_nest(vec![row(&[32.0], 4.0, false)], 4.0, &phrase(), instrument(false));
    let block = frozen.tracks.iter_mut().find(|t| t.id == 1).unwrap();
    let block = Arc::make_mut(Arc::make_mut(block).clips.get_mut(0).unwrap());
    block.meta.insert("frozen".into(), json!({ "file": file, "length": 4.0 }));
    let audio = json!({ "id": 100, "name": "", "start": 32.0, "length": 4.0, "muted": false,
        "timebase": "beats", "content": { "kind": "audio", "file": file, "offset": 0.0, "gain": 0.0 } });
    let file_alone: Project = serde_json::from_value(json!({
        "name": "t", "tempo": 120.0, "sig_num": 4, "sig_den": 4,
        "master": track_json(0, "Master", None, json!([]), json!([])),
        "tracks": [track_json(1, "Ballad", None, json!([]), json!([audio]))],
    }))
    .unwrap();
    let (a, b) = (played_from(&frozen, 31.5), played_from(&file_alone, 31.5));
    std::fs::remove_dir_all(&dir).unwrap();
    assert!(b.iter().any(|s| *s != 0.0), "the file sounds");
    let worst = a.iter().zip(&b).fold(0.0f32, |m, (x, y)| m.max((x - y).abs()));
    assert!(worst < peak(&b) * 1e-6, "the frozen block plays its file alone: {worst}");
    let placed = nests::Placed::of(&frozen);
    assert_eq!(placed.resting().collect::<Vec<_>>(), vec![crate::model::NestId(10)], "its subproject rests");
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

// Null tests ---------------------------------------------------------------------------

/// A tempo where a frame is 2^-15 of a beat, exactly in `f64`: the beat of
/// each frame has no rounding error. The rows at 120 BPM and on a ramp,
/// where it has, show that the frame of a note does not depend on where the
/// blocks fall.
const EXACT_TEMPO: f64 = 87.890625;

/// Frames in one beat at [`EXACT_TEMPO`].
const FRAMES_PER_BEAT: usize = 32768;

/// The length of each render: 16 beats, a whole number of blocks of each
/// size in the table.
const RENDER_FRAMES: usize = 16 * FRAMES_PER_BEAT;

/// Ticks of the clip files in one beat.
const TICKS: usize = crate::clipfile::TPQ as usize;

/// A MIDI clip of `count` notes, `step` ticks apart, from key `low` up.
///
/// Each note starts on a tick, so a save and a load keep it exactly. Each
/// `step` used here is a whole number of blocks of 512 frames, and each
/// note is 0, 119 or 239 ticks after its step: on frame 0, 63 or 127 of a
/// block of 512. In blocks of 64 or 128 frames, frame 63 or 127 is the
/// last frame of a block, so an error at the end of a block shows.
fn null_clip(id: u64, start: f64, count: usize, step: usize, low: usize) -> Value {
    let notes: Vec<Value> = (0..count)
        .map(|k| {
            let at = (k * step + [0, 119, 239][k % 3]) as f64 / TICKS as f64;
            json!({ "start": at, "length": 0.375, "pitch": low + (k * 5) % 19, "velocity": 70 + k % 50 })
        })
        .collect();
    let length = (count * step) as f64 / TICKS as f64 + 1.0;
    json!({ "id": id, "name": "", "start": start, "length": length, "muted": false,
        "content": { "kind": "midi", "notes": notes } })
}

/// A small mix at [`EXACT_TEMPO`]. Keys has a synth and a delay that is
/// half wet. Bass has a synth, its fader and pan off the middle, and a send
/// to Room. Room has a reverb. Keys and Bass play for about 4 beats, stop
/// until each device comes to rest, and play again from beat 12.
fn null_mix() -> Project {
    null_mix_at(EXACT_TEMPO)
}

/// The mix at 120 BPM. A beat is 24000 frames, and a tick is not a whole
/// number of frames, so the notes fall on frames and between them.
fn null_mix_120() -> Project {
    null_mix_at(120.0)
}

/// The mix on a ramp from 120 BPM down to 60 BPM at beat 16. Of the ramps
/// that a simulation of the engine's old arithmetic tried, this one put a
/// note of the mix one frame off between blocks of 64 and of 512.
fn null_mix_on_a_ramp() -> Project {
    let mut p = null_mix_at(120.0);
    p.tempo_ramp = true;
    p.tempo_changes = vec![crate::model::TempoChange { beat: 16.0, bpm: 60.0, ramp: false }];
    p
}

/// The mix of [`null_mix`] at `tempo`.
fn null_mix_at(tempo: f64) -> Project {
    let keys = json!([
        { "id": 2, "kind": "synth", "bypass": false, "params": { "wave": 1.0, "release": 0.05 } },
        { "id": 3, "kind": "delay", "bypass": false,
          "params": { "time": 123.0, "feedback": 0.2, "fx_wet": 50.0 } },
    ]);
    let bass = json!([{ "id": 5, "kind": "synth", "bypass": false, "params": { "wave": 2.0 } }]);
    let room = json!([{ "id": 6, "kind": "reverb", "bypass": false, "params": { "decay": 0.5 } }]);
    let (quarter, half) = (TICKS / 4, TICKS / 2);
    let keys_clips = json!([null_clip(10, 0.0, 12, 5 * TICKS / 16, 60), null_clip(11, 12.0, 6, quarter, 60)]);
    let bass_clips = json!([null_clip(21, 0.5, 7, half, 36), null_clip(22, 12.0, 4, half, 36)]);
    let mut bass_track = track_json(20, "Bass", None, bass, bass_clips);
    bass_track["volume"] = json!(-6.0);
    bass_track["pan"] = json!(-0.25);
    bass_track["sends"] = json!([{ "target": 30, "level": -3.0 }]);
    serde_json::from_value(json!({
        "name": "t", "tempo": tempo, "sig_num": 4, "sig_den": 4,
        "master": track_json(0, "Master", None, json!([]), json!([])),
        "tracks": [
            track_json(1, "Keys", None, keys, keys_clips),
            bass_track,
            track_json(30, "Room", None, room, json!([])),
        ],
    }))
    .unwrap()
}

/// The mix with the first clip of Keys three beats later.
fn null_moved() -> Project {
    let mut p = null_mix();
    Arc::make_mut(&mut p.track_mut(1).unwrap().clips[0]).start += 3.0;
    p
}

/// The mix, saved to a project folder and read back.
fn null_saved_and_loaded() -> Project {
    use crate::session::folder::{Home, commit, layout, read};
    let dir = tempfile::tempdir().unwrap();
    let files = layout(&null_mix(), &Value::Null, None, dir.path(), &Home::default()).unwrap();
    commit(dir.path(), &files, None).unwrap();
    read(&Home::default(), dir.path()).unwrap().project
}

/// The mix with the delay of Keys bypassed.
fn null_bypassed() -> Project {
    let mut p = null_mix();
    Arc::make_mut(&mut p.track_mut(1).unwrap().devices[1]).bypass = true;
    p
}

/// The mix with no delay on Keys.
fn null_without_delay() -> Project {
    let mut p = null_mix();
    p.track_mut(1).unwrap().devices.remove(1);
    p
}

/// The mix with the first clip of Keys in a subproject (nest 40). The
/// track of the clip (42) has no devices, and a block on Keys plays that
/// track only. This is the pass mode of `nest.md` 4.4: the song sounds as
/// if the clip was on Keys.
fn null_in_subproject() -> Project {
    let mut p = null_mix();
    let keys = p.track_mut(1).unwrap();
    let clip = keys.clips.remove(0);
    let length = clip.length;
    let block: Clip = serde_json::from_value(json!({ "id": 43, "name": "", "start": 0.0, "length": length,
        "muted": false, "content": { "kind": "nest", "nest": 40, "play": { "track": 42 } } }))
    .unwrap();
    keys.clips.insert(0, Arc::new(block));
    let track = |id, name| -> crate::model::Track {
        serde_json::from_value(track_json(id, name, Some(40), json!([]), json!([]))).unwrap()
    };
    let mut inside = track(42, "Keys");
    inside.clips.push(clip);
    p.tracks.push(Arc::new(inside));
    p.tracks.push(Arc::new(track(41, "Master")));
    let nest = json!({ "id": 40, "name": "Verse", "length": length, "master": 41 });
    p.nests.insert(crate::model::NestId(40), Arc::new(serde_json::from_value(nest).unwrap()));
    p
}

/// How a case renders: the size of the blocks, the threads, and whether
/// devices at rest sleep.
#[derive(Clone, Copy)]
struct Way {
    block: usize,
    threads: usize,
    sleep: bool,
}

/// As a render to a file does it.
const PLAIN: Way = Way { block: 512, threads: 1, sleep: true };

/// The left and right samples of a render, and how many blocks devices
/// slept through.
struct Rendered {
    left: Vec<f32>,
    right: Vec<f32>,
    slept: u64,
}

impl Rendered {
    /// The first frame where `self` and `other` differ, or None when they
    /// null. The comparison is `==` on each sample: bit for bit, but -0.0
    /// and 0.0 are the same.
    fn first_difference(&self, other: &Rendered) -> Option<usize> {
        let frames = |r: &Rendered| r.left.iter().zip(&r.right).map(|(l, r)| (*l, *r)).collect::<Vec<_>>();
        frames(self).into_iter().zip(frames(other)).position(|(a, b)| a != b)
    }
}

/// [`RENDER_FRAMES`] from the start of the last of `states`, by an engine
/// that the sync took through each of `states` in turn.
fn null_render(states: &[Project], way: Way) -> Rendered {
    let path: Vec<&Project> = states.iter().collect();
    let (mut engine, mut handle, _) = engine(&path);
    engine.set_offline(true);
    engine.set_sleep(way.sleep);
    if way.threads > 1 {
        engine.set_pool(Some(Box::new(paw_engine::Pool::new(way.threads))));
    }
    handle.send_while(Msg::Play, &mut engine);
    let (mut l, mut r) = (vec![0.0; way.block], vec![0.0; way.block]);
    let mut out = Rendered { left: Vec::new(), right: Vec::new(), slept: 0 };
    for _ in 0..RENDER_FRAMES / way.block {
        engine.process(&mut l, &mut r);
        out.left.extend_from_slice(&l);
        out.right.extend_from_slice(&r);
    }
    handle.collect_garbage();
    out.slept = engine.shared().device_blocks().1;
    out
}

/// One project rendered two ways that must sound the same nulls: the
/// difference of the two renders is silence, sample by sample. The code is
/// certain in each case, so no case has a limit in dB.
///
/// The threads case does not show that the work was shared between the
/// threads: that depends on how long the tracks took.
/// `crates/paw-engine/tests/it/threads.rs` shows it on a larger project.
#[test]
fn one_project_rendered_two_ways_nulls() {
    type States = fn() -> Vec<Project>;
    let mix: States = || vec![null_mix()];
    let at_120: States = || vec![null_mix_120()];
    let ramp: States = || vec![null_mix_on_a_ramp()];
    let blocks = |block| Way { block, ..PLAIN };
    #[rustfmt::skip]
    let cases: [(&str, States, Way, States, Way); 12] = [
        ("blocks of 64 and of 512 frames", mix, blocks(64), mix, PLAIN),
        ("blocks of 128 and of 512 frames", mix, blocks(128), mix, PLAIN),
        ("blocks of 64 and of 512 frames at 120 BPM", at_120, blocks(64), at_120, PLAIN),
        ("blocks of 128 and of 512 frames at 120 BPM", at_120, blocks(128), at_120, PLAIN),
        ("blocks of 64 and of 512 frames on a tempo ramp", ramp, blocks(64), ramp, PLAIN),
        ("blocks of 128 and of 512 frames on a tempo ramp", ramp, blocks(128), ramp, PLAIN),
        ("one thread and four", mix, PLAIN, mix, Way { threads: 4, ..PLAIN }),
        ("a clip moved and moved back", || vec![null_mix(), null_moved(), null_mix()], PLAIN, mix, PLAIN),
        ("render, save, load, render", mix, PLAIN, || vec![null_saved_and_loaded()], PLAIN),
        ("a bypassed device and no device", || vec![null_bypassed()], PLAIN, || vec![null_without_delay()], PLAIN),
        ("devices that sleep and devices awake", mix, PLAIN, mix, Way { sleep: false, ..PLAIN }),
        ("a subproject's track and its clip on the row", || vec![null_in_subproject()], PLAIN, mix, PLAIN),
    ];
    for (name, a_states, a_way, b_states, b_way) in cases {
        let a = null_render(&a_states(), a_way);
        let b = null_render(&b_states(), b_way);
        assert!(a.left.iter().any(|s| s.abs() > 0.01), "{name}: something sounds");
        // The devices sleep through the rest in the middle, and wake
        // again at beat 12.
        assert!(!a_way.sleep || a.slept > 0, "{name}: devices sleep through the rest");
        assert_eq!(a.first_difference(&b), None, "{name}: the first frame that differs");
    }
}

/// What a plugin hears of the host, in order: "offline" or "realtime"
/// when its controller is told the render mode, "block" when it runs a
/// block.
type Heard = Arc<std::sync::Mutex<Vec<&'static str>>>;

/// A plugin that records what it hears (a spy).
struct Spy {
    info: DeviceInfo,
    heard: Heard,
}

struct SpyDevice(Heard);

impl Device for SpyDevice {
    fn process(&mut self, _ctx: &ProcessCtx, _io: &mut Io) {
        self.0.lock().unwrap().push("block");
    }
    fn set_param(&mut self, _index: u32, _value: f32) {}
}

struct SpyController(Heard);

impl Controller for SpyController {
    fn params(&self) -> Vec<ParamInfo> {
        Vec::new()
    }
    fn value(&self, _index: usize) -> Option<f64> {
        None
    }
    fn save_state(&mut self) -> anyhow::Result<Option<Vec<u8>>> {
        Ok(None)
    }
    fn load_state(&mut self, _state: &[u8]) -> anyhow::Result<()> {
        Ok(())
    }
    fn set_offline(&mut self, offline: bool) {
        self.0.lock().unwrap().push(if offline { "offline" } else { "realtime" });
    }
}

impl DeviceFactory for Spy {
    fn info(&self) -> &DeviceInfo {
        &self.info
    }
    fn create(&self, _sample_rate: f32, _max_block: usize) -> anyhow::Result<Instance> {
        Ok(Instance {
            device: Box::new(SpyDevice(self.heard.clone())),
            controller: Some(Box::new(SpyController(self.heard.clone()))),
        })
    }
}

/// What a plugin on a track hears up to the end of its first block, when
/// the sync makes it for a render (`offline`) or to play live.
fn heard_to_the_first_block(offline: bool) -> Vec<&'static str> {
    let heard = Heard::default();
    let mut registry = Registry::with_builtins();
    let info = DeviceInfo { kind: "spy".into(), ..Default::default() };
    registry.register(std::rc::Rc::new(Spy { info, heard: heard.clone() }));
    let spy = json!([{ "id": 2, "kind": "spy", "bypass": false, "params": {} }]);
    let project: Project = serde_json::from_value(json!({
        "name": "t", "tempo": 120.0, "sig_num": 4, "sig_den": 4,
        "master": track_json(0, "Master", None, json!([]), json!([])),
        "tracks": [track_json(1, "T", None, spy, json!([]))],
    }))
    .unwrap();
    let (mut engine, mut handle) = Engine::new(48000.0);
    engine.set_sleep(false);
    let sources = crate::media::Sources::default();
    let (mut audio, mut live, mut warnings) = (AudioCache::default(), LiveDevices::new(), Vec::new());
    let mut ctx = SyncCtx {
        registry: &registry,
        sources: &sources,
        audio: &mut audio,
        live: &mut live,
        sample_rate: 48000.0,
        warnings: &mut warnings,
        offline,
        waker: Default::default(),
    };
    let mut sent = Vec::new();
    sync(&Project::default(), &project, &mut Mapper::new(), &mut ctx, &mut |msg| sent.push(msg), &mut Vec::new());
    assert_eq!(warnings, Vec::<String>::new(), "the spy is made");
    for msg in sent {
        handle.send_while(msg, &mut engine);
    }
    engine.process(&mut [0.0; 512], &mut [0.0; 512]);
    heard.lock().unwrap().clone()
}

/// A plugin made for a render (a render, an export, stems, a freeze) is
/// told that the render is offline before its first block. A plugin made
/// to play live is never told: a render makes instances of its own, so no
/// live instance has to go back to realtime after a render.
#[test]
fn a_plugin_made_for_a_render_is_set_offline_before_its_first_block() {
    assert_eq!(heard_to_the_first_block(true), ["offline", "block"]);
    assert_eq!(heard_to_the_first_block(false), ["block"]);
}
