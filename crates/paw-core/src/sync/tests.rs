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
    pieces.map(|p| (p.events.as_ptr(), p.events.len())).collect()
}

/// An engine brought through each of `states` in turn, as a session
/// syncs it; what it was sent for the last, and how many events were
/// compiled for it.
fn engine(states: &[&Project]) -> (Engine, EngineHandle, (Vec<&'static str>, usize)) {
    let (mut engine, mut handle) = Engine::new(48000.0);
    let registry = Registry::with_builtins();
    let (mut audio, mut live, mut warnings) = (AudioCache::default(), LiveDevices::new(), Vec::new());
    let mut map = Mapper::new();
    let empty = Project::default();
    let mut last = Vec::new();
    let mut fresh = 0;
    let mut old = &empty;
    for state in states {
        let mut ctx = SyncCtx {
            registry: &registry,
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
