//! Linked clips (`model/links.rs`): a linked copy of a MIDI clip, and a
//! clip taken out of its link. Each is one undo step.

use std::sync::Arc;

use anyhow::{Context, Result, bail};

use super::Session;
use crate::model::{ClipContent, Id};

impl Session {
    /// Put a linked copy of the MIDI clip `id` right after it on its track,
    /// and give the copy's id. A clip of no link starts a new one with its
    /// copy, named after the clip.
    pub fn clip_link(&mut self, id: Id) -> Result<Id> {
        let (track, _) = self
            .doc.project
            .find_clip(id)
            .with_context(|| format!("no clip {id} on a timeline"))?;
        let clip = self.doc.project.clip(id).with_context(|| format!("no clip {id}"))?;
        if !matches!(clip.content, ClipContent::Midi { .. }) {
            bail!("clip {id} is a clip of the kind `{}`: only MIDI clips can be linked", clip.content.kind());
        }
        let link = match &clip.link {
            Some(link) => link.clone(),
            None => self.doc.project.new_link_name(&clip.name),
        };
        // The copy shares the clip's notes: the same runs, compiled once.
        let mut copy = (**clip).clone();
        copy.start = clip.start + clip.length;
        copy.link = Some(link.clone());
        copy.id = self.doc.new_id();
        let copy_id = copy.id;
        self.doc.edit_named(|p| {
            let clip = p.clip_mut(id).with_context(|| format!("no clip {id}"))?;
            if clip.link.is_none() {
                clip.link = Some(link);
            }
            let t = p.track_mut(track).with_context(|| format!("no track {track}"))?;
            t.clips.push(Arc::new(copy));
            let at = t.clips.len() - 1;
            p.found_clip(copy_id, track, at);
            Ok(copy_id)
        })
    }

    /// Take the clip `id` out of its link: it keeps its notes, and an edit
    /// of it no longer changes the other clips of the link.
    pub fn clip_unlink(&mut self, id: Id) -> Result<()> {
        let clip = self.doc.project.clip(id).with_context(|| format!("no clip {id}"))?;
        if clip.link.is_none() {
            bail!("clip {id} is not linked");
        }
        self.doc.edit_named(|p| {
            p.clip_mut(id).with_context(|| format!("no clip {id}"))?.link = None;
            Ok(())
        })
    }
}
