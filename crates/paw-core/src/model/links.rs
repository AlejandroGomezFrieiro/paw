//! Linked clips: MIDI clips that share one set of notes and controller
//! moves, by the name of their link (`Clip::link`).
//!
//! The clips of one link hold the same [`Notes`] (the very same runs behind
//! `Arc`) and equal controller moves, so the sync compiles their events one
//! time. An edit changes one clip of a link: [`Links::spread`] then gives
//! that clip's notes to the other clips of the link, in the same edit and so
//! in the same undo step. The notes stay plain MIDI notes in each clip, so a
//! project with links opens and plays as any other.

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::{Result, bail};

use super::{Clip, ClipContent, Control, Notes, Project, Track};

/// What the clips of one link hold.
#[derive(Clone)]
struct Shared {
    notes: Notes,
    controls: Vec<Control>,
}

impl Shared {
    /// What a MIDI clip holds; `None` for a clip of another kind.
    fn of(clip: &Clip) -> Option<Self> {
        match &clip.content {
            ClipContent::Midi { notes, controls } => {
                Some(Self { notes: notes.clone(), controls: controls.clone() })
            }
            _ => None,
        }
    }

    /// A MIDI clip's content of these notes and controller moves.
    fn content(&self) -> ClipContent {
        ClipContent::Midi { notes: self.notes.clone(), controls: self.controls.clone() }
    }

    /// Whether `clip` holds this, unchanged: its notes are the same runs,
    /// not only equal notes, so that the clips go on sharing them.
    fn held_by(&self, clip: &Clip) -> bool {
        match &clip.content {
            ClipContent::Midi { notes, controls } => {
                self.notes.same_runs(notes) && self.controls == *controls
            }
            _ => true,
        }
    }
}

/// What `clip` must hold and does not: that of its link in `links`.
fn wanted<'a>(links: &'a HashMap<String, Shared>, clip: &Clip) -> Option<&'a Shared> {
    let shared = links.get(clip.link.as_ref()?)?;
    (!shared.held_by(clip)).then_some(shared)
}

/// Every clip of a track, on the timeline and off it (cues).
fn clips_of(track: &Track) -> impl Iterator<Item = &Arc<Clip>> {
    track.clips.iter().chain(track.cues.iter())
}

/// What each link held before an edit, by the name of the link.
pub(crate) struct Links(HashMap<String, Shared>);

impl Links {
    /// What each link of `project` holds now: that of its first clip.
    pub(crate) fn before(project: &Project) -> Self {
        let mut links = HashMap::new();
        for track in project.all_tracks() {
            for clip in clips_of(track) {
                if let Some(name) = &clip.link
                    && !links.contains_key(name)
                    && let Some(shared) = Shared::of(clip)
                {
                    links.insert(name.clone(), shared);
                }
            }
        }
        Self(links)
    }

    /// After an edit: give the other clips of each link that the edit
    /// changed what the changed clip holds now. When the edit changed two
    /// clips of one link, the first on the first track wins.
    pub(crate) fn spread(&self, project: &mut Project) {
        if self.0.is_empty() {
            return;
        }
        let mut changed = HashMap::new();
        for track in project.all_tracks() {
            for clip in clips_of(track) {
                let Some(name) = &clip.link else { continue };
                if changed.contains_key(name) {
                    continue;
                }
                // A link that the edit made has nothing to spread yet.
                let Some(before) = self.0.get(name) else { continue };
                if !before.held_by(clip)
                    && let Some(now) = Shared::of(clip)
                {
                    changed.insert(name.clone(), now);
                }
            }
        }
        project.give(&changed);
    }
}

impl Project {
    /// Give each clip of the links in `links` what its link holds. Only the
    /// tracks and the clips that change are copied, so that the undo
    /// history goes on sharing the others.
    fn give(&mut self, links: &HashMap<String, Shared>) {
        if links.is_empty() {
            return;
        }
        let tracks = self.tracks.iter_mut().chain(std::iter::once(&mut self.master));
        for track in tracks {
            if !clips_of(track).any(|clip| wanted(links, clip).is_some()) {
                continue;
            }
            let track = Arc::make_mut(track);
            for list in [&mut track.clips, &mut track.cues] {
                for index in 0..list.len() {
                    let Some(shared) = wanted(links, &list[index]) else { continue };
                    if let Some(clip) = list.get_mut(index) {
                        Arc::make_mut(clip).content = shared.content();
                    }
                }
            }
        }
    }

    /// Make the clips of each link share the notes of its first clip, as
    /// they do in memory: for a project just read, whose clips each read
    /// their notes on their own.
    pub fn join_links(&mut self) {
        let links = Links::before(self);
        self.give(&links.0);
    }

    /// How many clips the link `name` has.
    pub fn link_count(&self, name: &str) -> usize {
        self.all_tracks()
            .flat_map(|track| clips_of(track))
            .filter(|clip| clip.link.as_deref() == Some(name))
            .count()
    }

    /// A name for a new link, made from `stem` (a clip's name): letters,
    /// digits, `-` and `_`, as a file name takes them, and no other link's
    /// name in any case (`riff`, `riff-2`, ...).
    pub fn new_link_name(&self, stem: &str) -> String {
        let safe: String = stem
            .trim()
            .chars()
            .map(|c| if c.is_alphanumeric() || c == '-' || c == '_' { c } else { '-' })
            .collect();
        let stem = if safe.is_empty() { "link".to_string() } else { safe };
        let taken: Vec<String> = self
            .all_tracks()
            .flat_map(|track| clips_of(track))
            .filter_map(|clip| clip.link.as_ref().map(|name| name.to_lowercase()))
            .collect();
        let mut name = stem.clone();
        let mut n = 2;
        while taken.contains(&name.to_lowercase()) {
            name = format!("{stem}-{n}");
            n += 1;
        }
        name
    }

    /// The clips of each link are MIDI clips with the same notes and
    /// controller moves, and the name of a link can be a file name.
    pub(super) fn check_links(&self) -> Result<()> {
        let mut first: HashMap<&str, &Clip> = HashMap::new();
        for clip in self.all_tracks().flat_map(|track| clips_of(track)) {
            let Some(name) = clip.link.as_deref() else { continue };
            if !is_link_name(name) {
                bail!("clip {} has the link name {name:?}: use letters, digits, - and _", clip.id);
            }
            if !matches!(clip.content, ClipContent::Midi { .. }) {
                bail!("clip {} is linked to {name}, but only MIDI clips can be linked", clip.id);
            }
            let other = *first.entry(name).or_insert(clip);
            let (ClipContent::Midi { notes, controls }, ClipContent::Midi { notes: n, controls: c }) =
                (&clip.content, &other.content)
            else {
                continue;
            };
            if notes != n || controls != c {
                bail!("clips {} and {} are linked to {name}, but their notes differ", other.id, clip.id);
            }
        }
        Ok(())
    }
}

/// Letters, digits, `-` and `_`, and at least one of them.
fn is_link_name(name: &str) -> bool {
    !name.is_empty() && name.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_')
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    /// A project with one track of three clips: two of the link `riff`
    /// that share their notes, and a plain copy of them. Built from the
    /// defaults, so that a new field of a track or a project does not
    /// change it.
    fn project() -> Project {
        let notes = json!([{ "start": 0.0, "length": 1.0, "pitch": 60, "velocity": 100 }]);
        let clip = |id: u64, link: Option<&str>| -> Arc<Clip> {
            let value = json!({ "id": id, "name": "riff", "start": id as f64 * 4.0, "length": 4.0,
                "muted": false, "link": link, "content": { "kind": "midi", "notes": notes } });
            Arc::new(serde_json::from_value(value).expect("a clip"))
        };
        let mut track = Track::new(1);
        track.clips = vec![clip(2, Some("riff")), clip(3, Some("riff")), clip(4, None)].into();
        let mut p = Project::default();
        p.tracks.push(Arc::new(track));
        p.join_links();
        p
    }

    /// A file whose linked clips differ, or that links an audio clip, is
    /// refused with the clips it names.
    #[test]
    fn a_link_whose_clips_differ_is_refused() {
        let mut p = project();
        if let ClipContent::Midi { notes, .. } = &mut p.clip_mut(3).expect("the clip").content {
            notes[0].pitch = 62;
        }
        let error = format!("{:#}", p.validate().expect_err("refused"));
        assert!(error.contains("clips 2 and 3"), "{error}");
        let mut p = project();
        p.clip_mut(4).expect("the clip").link = Some("a b".into());
        assert!(p.validate().is_err());
    }
}
