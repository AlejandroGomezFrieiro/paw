//! Frozen tracks: a track rendered to a sound file, which the engine plays in
//! place of the track's clips and devices, so that they cost nothing while it
//! is frozen.
//!
//! A track is frozen when its meta holds `frozen.file` (the runtime's
//! `paw.freeze` writes it, so freezing is saved and undone with the track).
//! The file is what comes out of the track before its fader: its clips, its
//! devices, and every track whose sound reaches it through outputs (the
//! members of a group). The fader, pan, mute and sends stay live. While it is
//! frozen, its devices are held (bypassed in the engine, not in the model)
//! and the tracks that feed it are held and silent, as the file holds them.
//!
//! The session can hold further tracks the same way without touching the
//! project ([`Mapper::held_files`](crate::sync::Mapper)): what narrowing to a
//! group does to the rest of the song, when asked to.
//!
//! A block of a subproject (a nest clip) is frozen the same way: its meta
//! holds `frozen.file`, the sound that the block plays into its row, and
//! `frozen.length`, the beats of that file. The engine plays the file as an
//! audio clip of the row in place of the block ([`block_sound`]), and the
//! subproject's devices rest when no live block plays it
//! (`sync/nests.rs`). A block inside a subproject is rendered where the
//! blocks of its [`block_path`] place it in the song ([`block_alone`]).

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{Result, bail};
use serde_json::{Map, Value};

use crate::model::nest::Timing;
use crate::model::{Clip, ClipContent, Id, MASTER_ID, NestId, NestPlay, Project, Target, Timebase, Track};

/// What the engine plays of a track.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Played {
    /// Its clips through its devices.
    Live,
    /// This file, from the start of the song, with its devices held.
    Frozen(PathBuf),
    /// Nothing: its sound is in a frozen track it feeds.
    Held,
}

/// The sound file of a freeze that `meta` keeps (`frozen.file`).
fn meta_file(meta: &Map<String, Value>) -> Option<PathBuf> {
    meta.get("frozen")
        .and_then(|f| f.get("file"))
        .and_then(Value::as_str)
        .filter(|f| !f.is_empty())
        .map(PathBuf::from)
}

/// Point the freeze that `meta` keeps at the file that `f` gives for it.
/// Returns whether it changed.
fn map_meta_file(
    meta: &mut Map<String, Value>,
    f: &mut impl FnMut(&std::path::Path) -> Option<PathBuf>,
) -> bool {
    let Some(new) = meta_file(meta).and_then(|file| f(&file)) else {
        return false;
    };
    if let Some(Value::Object(frozen)) = meta.get_mut("frozen") {
        frozen.insert(
            "file".into(),
            Value::String(new.to_string_lossy().into_owned()),
        );
        return true;
    }
    false
}

/// The sound file a track is frozen to, from its meta.
pub(crate) fn frozen_file(track: &Track) -> Option<PathBuf> {
    meta_file(&track.meta)
}

/// Point a frozen track at another file (saving relative to the project,
/// relinking a moved one). Returns whether it changed.
pub(crate) fn map_frozen_file(
    track: &mut Track,
    f: &mut impl FnMut(&std::path::Path) -> Option<PathBuf>,
) -> bool {
    map_meta_file(&mut track.meta, f)
}

/// The sound file a block of a subproject is frozen to, from its meta.
/// None for every other clip.
pub(crate) fn block_file(clip: &Clip) -> Option<PathBuf> {
    match clip.content {
        ClipContent::Nest { .. } => meta_file(&clip.meta),
        _ => None,
    }
}

/// Point a frozen block at another file, as [`map_frozen_file`] does for a
/// track. Returns whether it changed.
pub(crate) fn map_block_file(
    clip: &mut Clip,
    f: &mut impl FnMut(&std::path::Path) -> Option<PathBuf>,
) -> bool {
    matches!(clip.content, ClipContent::Nest { .. }) && map_meta_file(&mut clip.meta, f)
}

/// What the engine plays in place of a frozen block: an audio clip of its
/// file at the block's start, as long as the file (`frozen.length` beats,
/// the tail included), on the block's beat. None for a clip that is not a
/// frozen block.
pub(crate) fn block_sound(clip: &Clip) -> Option<Clip> {
    let file = block_file(clip)?;
    let length = clip
        .meta
        .get("frozen")
        .and_then(|f| f.get("length"))
        .and_then(Value::as_f64)
        .filter(|l| *l > 0.0)
        .unwrap_or(clip.length);
    Some(Clip {
        id: clip.id,
        name: clip.name.clone(),
        start: clip.start,
        length,
        muted: clip.muted,
        content: ClipContent::Audio {
            file,
            offset: 0.0,
            gain: 0.0,
            edits: Vec::new(),
        },
        fade_in: 0.0,
        fade_out: 0.0,
        timebase: Some(Timebase::Beats),
        stretch: 1.0,
        pitch: 0.0,
        stretch_mode: Default::default(),
        source_tempo: None,
        warp: Vec::new(),
        formants: false,
        looped: false,
        loop_length: None,
        loop_start: 0.0,
        meta: Map::new(),
        source: None,
        origin: None,
        link: None,
        overrides: Default::default(),
    })
}

/// The tracks whose outputs lead, one after another, into `id`.
fn feeders(project: &Project, id: Id) -> HashSet<Id> {
    let output: HashMap<Id, Option<Id>> = project.tracks.iter().map(|t| (t.id, t.output)).collect();
    let mut out = HashSet::new();
    for t in &project.tracks {
        let mut at = t.output;
        // Routing has no loops (the model refuses them); the bound is a guard.
        for _ in 0..64 {
            match at {
                Some(next) if next == id => {
                    out.insert(t.id);
                    break;
                }
                Some(next) if next != MASTER_ID => at = output.get(&next).copied().flatten(),
                _ => break,
            }
        }
    }
    out
}

/// What the engine plays of every track that is not live: frozen in the
/// project or in `extra`, or held inside a frozen track. A track frozen
/// inside another frozen track is held.
pub(crate) fn played(project: &Project, extra: &HashMap<Id, PathBuf>) -> HashMap<Id, Played> {
    let mut out = HashMap::new();
    let frozen: HashMap<Id, PathBuf> = project
        .tracks
        .iter()
        .filter_map(|t| {
            frozen_file(t)
                .or_else(|| extra.get(&t.id).cloned())
                .map(|f| (t.id, f))
        })
        .collect();
    if frozen.is_empty() {
        return out;
    }
    for (&id, file) in &frozen {
        out.entry(id)
            .or_insert_with(|| Played::Frozen(file.clone()));
        for fed in feeders(project, id) {
            out.insert(fed, Played::Held);
        }
    }
    out
}

/// Turn a copy of the project into what freezing `id` renders: the track
/// and the tracks that feed it, as they sound before its fader, with every
/// other track silent and the master's own processing left to the caller.
/// The track itself plays live, even when it is frozen now; tracks frozen
/// inside it play their files.
pub(crate) fn alone(project: &mut Project, id: Id) -> Result<()> {
    if id == MASTER_ID {
        bail!("the master track cannot be frozen");
    }
    if project.track(id).is_none() {
        bail!("no track {id} to freeze");
    }
    tracks_alone(project, &[id], Fader::Out)?;
    project.track_mut(id).expect("checked above").meta.remove("frozen");
    Ok(())
}

/// Whether a render of tracks alone hears their faders.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Fader {
    /// Before the fader: no fader, pan, mute, VCA, or volume and pan lane.
    Out,
    /// After the fader, the pan and the mute.
    In,
}

/// Turn a copy of the project into the sound of `ids` alone: each track
/// with the tracks that feed it, straight into the master, with no sends
/// and no groups, and every other track silent. The caller leaves out the
/// master's own processing. A track of `ids` that feeds another track of
/// `ids` (a member of a listed group) is heard once, inside that track,
/// with its own fader.
pub(crate) fn tracks_alone(project: &mut Project, ids: &[Id], fader: Fader) -> Result<()> {
    if ids.contains(&MASTER_ID) {
        bail!("the master is not a track to hear alone: leave it out of the tracks");
    }
    if let Some(id) = ids.iter().find(|id| project.track(**id).is_none()) {
        bail!("no track {id} to render");
    }
    let fed: HashMap<Id, HashSet<Id>> =
        ids.iter().map(|&id| (id, feeders(project, id))).collect();
    // The listed tracks that no other listed track holds.
    let outer: Vec<Id> = ids
        .iter()
        .copied()
        .filter(|id| !fed.values().any(|set| set.contains(id)))
        .collect();
    let mut heard: HashSet<Id> = outer.iter().copied().collect();
    for id in &outer {
        heard.extend(&fed[id]);
    }
    let is_vca = |t: &Track| t.meta.get("vca").and_then(Value::as_bool) == Some(true);
    for track in project.tracks.iter_mut() {
        // A VCA carries no sound, and muting it would mute its members.
        let mute = !heard.contains(&track.id) && !is_vca(track);
        if track.solo || (mute && !track.mute) {
            let t = Arc::make_mut(track);
            t.solo = false;
            t.mute |= mute;
        }
    }
    for id in outer {
        let track = project.track_mut(id).expect("checked above");
        // Not through its groups, and not into the returns of its sends.
        track.output = None;
        track.sends.clear();
        if fader == Fader::Out {
            track.volume = 0.0;
            track.pan = 0.0;
            track.mute = false;
            track
                .lanes
                .retain(|l| !matches!(l.target, Target::Volume | Target::Pan));
            track.meta.remove("vcas");
        }
    }
    Ok(())
}

/// The block `clip` and the track that holds it, or None when `clip` is
/// no block of a subproject.
fn block_on(project: &Project, clip: Id) -> Option<(&Arc<Track>, &Arc<Clip>)> {
    let (track, index) = project.find_clip(clip)?;
    let track = project.track(track)?;
    let c = track.clips.get(index)?;
    matches!(c.content, ClipContent::Nest { .. }).then_some((track, c))
}

/// The blocks that place block `clip` in the song, from a block of the
/// song down to `clip` itself. For a block inside a subproject, each
/// subproject on the way is placed by its block in `through`, or else by
/// its first block that plays the track that the block below is on.
pub(crate) fn block_path(project: &Project, clip: Id, through: &[Id]) -> Result<Vec<Id>> {
    let Some((mut track, _)) = block_on(project, clip) else {
        bail!("no block of a subproject {clip}");
    };
    let mut path = vec![clip];
    while let Some(nest) = track.nest {
        // The model keeps subprojects at most this deep; the bound is a guard.
        if path.len() > crate::model::MAX_DEPTH {
            bail!("block {clip} is too deep inside subprojects");
        }
        // A block of `nest` that is not muted and plays this track.
        let row = track.id;
        let plays = |c: &Clip| {
            !c.muted
                && matches!(c.content, ClipContent::Nest { nest: n, play, .. }
                    if n == nest && (play == NestPlay::Master || play == NestPlay::Track(row)))
        };
        let given = through
            .iter()
            .filter_map(|id| block_on(project, *id))
            .find(|(_, c)| plays(c));
        let first = || {
            project
                .tracks
                .iter()
                .find_map(|t| t.clips.iter().find(|c| plays(c)).map(|c| (t, c)))
        };
        let Some((holder, block)) = given.or_else(first) else {
            let name = project.nest(nest).map_or(String::new(), |n| n.name.clone());
            bail!("no block plays {name}: put a block of {name} in the song first");
        };
        path.push(block.id);
        track = holder;
    }
    path.reverse();
    Ok(path)
}

/// Where the beats of the place of the last block of `path` (a
/// [`block_path`]) are in the song: None for a block of the song.
pub(crate) fn path_timing(project: &Project, path: &[Id]) -> Result<Option<Timing>> {
    let mut timing: Option<Timing> = None;
    for &id in path.iter().take(path.len().saturating_sub(1)) {
        let Some((_, c)) = block_on(project, id) else {
            bail!("no block of a subproject {id}");
        };
        let ClipContent::Nest { nest, offset, .. } = c.content else {
            unreachable!("block_on gives blocks only");
        };
        let Some(held) = project.nest(nest) else {
            bail!("no subproject {} for block {id}", nest.0);
        };
        timing = Some(held.timing(project.tempo_map(), timing.as_ref(), c.start, offset));
    }
    Ok(timing)
}

/// Turn a copy of the project into what freezing block `clip` renders:
/// what the block plays into its row, before the row's devices and fader,
/// and nothing else. The block plays through the blocks of its
/// [`block_path`] (from `through`). On the song and in each subproject on
/// the way, the rows of the path keep their block alone and pass its sound
/// on unchanged (no devices, lanes, sends or fader), as do the masters of
/// those subprojects; every other track there is silent; and no other
/// block places a subproject of the path. The block itself plays live,
/// even when it is frozen now; blocks frozen inside its subproject play
/// their files.
pub(crate) fn block_alone(project: &mut Project, clip: Id, through: &[Id]) -> Result<()> {
    let path = block_path(project, clip, through)?;
    let Some((row, ClipContent::Nest { play, .. })) = block_on(project, clip).map(|(t, c)| (t.id, &c.content)) else {
        unreachable!("block_path found the block");
    };
    // A stem in pass mode has no sound of its own: its notes play through
    // the devices of the row, so the row holds its sound.
    if let NestPlay::Track(stem) = *play
        && project.track(stem).is_some_and(|t| crate::sync::passes(t))
    {
        let name = project.track(row).map_or(String::new(), |t| t.name.clone());
        bail!("this block plays its notes through the devices of {name}: freeze {name} instead");
    }
    // The places that the sound goes through on its way to the song: the
    // song (None) and each subproject that a block of the path above
    // `clip` places. And the subprojects that the path places.
    let mut on_way: HashSet<Option<NestId>> = HashSet::from([None]);
    let mut placed: HashSet<NestId> = HashSet::new();
    for (k, id) in path.iter().enumerate() {
        if let Some(ClipContent::Nest { nest, .. }) = project.clip(*id).map(|c| &c.content) {
            placed.insert(*nest);
            if k + 1 < path.len() {
                on_way.insert(Some(*nest));
            }
        }
    }
    // The tracks that pass the sound on: the row of each block of the
    // path, and the master of each subproject on the way.
    let mut passing: HashSet<Id> = path.iter().filter_map(|id| project.find_clip(*id).map(|(t, _)| t)).collect();
    passing.extend(on_way.iter().flatten().filter_map(|n| project.nest(*n)).map(|n| n.master));
    let is_vca = |t: &Track| t.meta.get("vca").and_then(Value::as_bool) == Some(true);
    for track in project.tracks.iter_mut() {
        let on = on_way.contains(&track.nest);
        let passes = passing.contains(&track.id);
        // Which clips the render keeps: on a track that passes the sound
        // on, its block of the path alone; elsewhere on the way, every clip
        // but the blocks; and nowhere another block of a subproject of the
        // path, which could take the place of the path's.
        let kept = |c: &Clip| match c.content {
            _ if path.contains(&c.id) => true,
            ClipContent::Nest { nest, .. } => !(on || placed.contains(&nest)),
            _ => !passes,
        };
        // A VCA carries no sound, and muting it would mute its members.
        let mute = on && !passes && !is_vca(track);
        let cut = track.clips.iter().any(|c| !kept(c));
        if !(cut || track.solo || (mute && !track.mute)) {
            continue;
        }
        let t = Arc::make_mut(track);
        t.clips.retain(|c| kept(c));
        t.solo = false;
        t.mute |= mute;
    }
    for id in passing {
        let Some(track) = project.track_mut(id) else {
            continue;
        };
        // Before the row: its devices, fader, lanes and sends stay live.
        track.devices.clear();
        track.lanes.clear();
        track.sends.clear();
        track.volume = 0.0;
        track.pan = 0.0;
        track.mute = false;
        track.output = None;
        track.meta.remove("vcas");
        track.meta.remove("frozen");
        for c in track.clips.iter_mut() {
            let c = Arc::make_mut(c);
            c.muted = false;
            c.meta.remove("frozen");
            // A block above `clip` plays all of its subproject, whose other
            // tracks are silent: as a stem in pass mode, it would play
            // through its row, which has no devices now.
            if c.id != clip
                && let ClipContent::Nest { play, .. } = &mut c.content
            {
                *play = NestPlay::Master;
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// Violins and cellos in Strings, which is frozen; drums apart.
    fn song() -> Project {
        let mut p = Project::default();
        let mut strings = Track::new(1);
        strings
            .meta
            .insert("frozen".into(), json!({ "file": "/m/strings.wav" }));
        strings.volume = -6.0;
        let mut violins = Track::new(2);
        violins.output = Some(1);
        let mut cellos = Track::new(3);
        cellos.output = Some(1);
        let drums = Track::new(4);
        p.tracks = [strings, violins, cellos, drums]
            .into_iter()
            .map(Arc::new)
            .collect();
        p
    }

    #[test]
    fn a_frozen_track_plays_its_file_and_what_feeds_it_is_held() {
        let played = played(&song(), &HashMap::new());
        assert_eq!(
            played.get(&1),
            Some(&Played::Frozen("/m/strings.wav".into()))
        );
        assert_eq!(played.get(&2), Some(&Played::Held));
        assert_eq!(played.get(&3), Some(&Played::Held));
        assert_eq!(played.get(&4), None);
        let extra = HashMap::from([(4, PathBuf::from("/m/drums.wav"))]);
        assert_eq!(
            super::played(&song(), &extra).get(&4),
            Some(&Played::Frozen("/m/drums.wav".into()))
        );
    }

    #[test]
    fn a_freeze_renders_the_track_alone_before_its_fader() {
        let mut p = song();
        alone(&mut p, 1).unwrap();
        let t = p.track(1).unwrap();
        assert_eq!((t.volume, t.mute, t.output), (0.0, false, None));
        assert!(frozen_file(t).is_none(), "the track itself plays live");
        assert!(
            !p.track(2).unwrap().mute && !p.track(3).unwrap().mute,
            "its members play"
        );
        assert!(p.track(4).unwrap().mute, "the rest is silent");
        assert!(alone(&mut p, MASTER_ID).is_err());
    }

    #[test]
    fn a_member_listed_with_its_group_is_heard_once_inside_the_group() {
        let mut p = song();
        Arc::make_mut(&mut p.tracks[1]).volume = -3.0;
        tracks_alone(&mut p, &[2, 1], Fader::In).unwrap();
        let violins = p.track(2).unwrap();
        assert_eq!(
            (violins.output, violins.volume),
            (Some(1), -3.0),
            "the violins still go into the strings, with their fader"
        );
        let strings = p.track(1).unwrap();
        assert_eq!((strings.output, strings.volume), (None, -6.0), "after the fader");
    }

    fn clip(id: Id, content: Value) -> Arc<Clip> {
        Arc::new(serde_json::from_value(json!({ "id": id, "name": "", "start": 8.0, "length": 4.0,
            "muted": false, "content": content })).unwrap())
    }

    /// A row with two frozen blocks of subproject 10 and a MIDI clip; Drums
    /// with a block of it too; Keys inside it with a block of subproject 20.
    fn blocks() -> Project {
        let block = json!({ "kind": "nest", "nest": 10, "play": "master" });
        let midi = json!({ "kind": "midi", "notes": [] });
        let mut row = Track::new(1);
        row.volume = -6.0;
        row.output = Some(4);
        for c in [clip(100, block.clone()), clip(101, block.clone()), clip(102, midi.clone())] {
            let mut c = (*c).clone();
            c.meta.insert("frozen".into(), json!({ "file": "/m/block.wav" }));
            row.clips.push(Arc::new(c));
        }
        let mut drums = Track::new(4);
        drums.clips.push(clip(103, midi));
        drums.clips.push(clip(104, block));
        let mut keys = Track::new(12);
        keys.nest = Some(crate::model::NestId(10));
        keys.clips.push(clip(105, json!({ "kind": "nest", "nest": 20, "play": "master" })));
        let mut p = Project::default();
        p.tracks = [row, drums, keys].into_iter().map(Arc::new).collect();
        p
    }

    #[test]
    fn a_block_freeze_renders_the_block_alone_before_its_row() {
        let mut p = blocks();
        block_alone(&mut p, 100, &[]).unwrap();
        let row = p.track(1).unwrap();
        let ids: Vec<Id> = row.clips.iter().map(|c| c.id).collect();
        assert_eq!(ids, vec![100], "the row keeps the block alone");
        assert!(block_file(row.clips.iter().next().unwrap()).is_none(), "the block plays live");
        assert_eq!((row.volume, row.output), (0.0, None), "before the row's fader");
        let drums = p.track(4).unwrap();
        let ids: Vec<Id> = drums.clips.iter().map(|c| c.id).collect();
        assert_eq!((drums.mute, ids), (true, vec![103]), "the rest is silent, its blocks gone");
        let keys = p.track(12).unwrap();
        assert_eq!((keys.mute, keys.clips.len()), (false, 1), "the subproject plays as it is");
        assert!(block_alone(&mut blocks(), 102, &[]).is_err(), "a clip that is not a block");
    }

    /// A block inside a subproject renders through the block of the song
    /// that it is entered through, or else the first one.
    #[test]
    fn a_block_inside_a_subproject_renders_through_a_block_of_the_song() {
        assert_eq!(block_path(&blocks(), 105, &[]).unwrap(), vec![100, 105], "the first block of the song");
        assert_eq!(block_path(&blocks(), 105, &[101]).unwrap(), vec![101, 105], "the block it is entered through");
        let mut p = blocks();
        block_alone(&mut p, 105, &[101]).unwrap();
        let row = p.track(1).unwrap();
        let ids: Vec<Id> = row.clips.iter().map(|c| c.id).collect();
        assert_eq!(ids, vec![101], "the song's row keeps the block of the path alone");
        assert!(block_file(row.clips.iter().next().unwrap()).is_none(), "which plays live");
        assert_eq!((row.volume, row.output), (0.0, None), "and passes the sound on");
        let drums = p.track(4).unwrap();
        let ids: Vec<Id> = drums.clips.iter().map(|c| c.id).collect();
        assert_eq!((drums.mute, ids), (true, vec![103]), "the rest of the song is silent, its blocks gone");
        let keys = p.track(12).unwrap();
        let ids: Vec<Id> = keys.clips.iter().map(|c| c.id).collect();
        assert_eq!((keys.mute, ids), (false, vec![105]), "the block's row plays it");
        let mut alone = blocks();
        Arc::make_mut(&mut alone.tracks[0]).clips.retain(|c| c.id == 102);
        Arc::make_mut(&mut alone.tracks[1]).clips.retain(|c| c.id == 103);
        assert!(block_path(&alone, 105, &[]).is_err(), "no block of the song plays it");
    }
}
