//! The modifier stack of a clip (`model/modifiers.rs`): a stack that Lua
//! gives, checked against the kinds of modifier, and the render of a prefix
//! of the stack into the clip's notes. Each change is one undo step.


use anyhow::{Context, Result, bail};
use serde::Serialize;

use super::Document;
use crate::model::modifiers::{self, Midi, Progress, Skipped};
use crate::model::{ClipContent, Id, Stack};

/// What a render did, for its message.
#[derive(Debug, PartialEq, Eq, Serialize)]
pub(crate) struct Rendered {
    /// The entries that left the stack.
    pub modifiers: usize,
    /// The notes of the clip after it.
    pub notes: usize,
    /// The notes that an entry left out (a transpose out of 0 to 127).
    pub dropped: usize,
}

impl Document {
    /// `stack`, checked against the kinds of modifier, with the values of
    /// each built-in kind as a file writes them.
    pub(crate) fn check_stack(&self, stack: Stack) -> Result<Stack> {
        Ok(modifiers::check(&self.modifier_kinds, stack)?)
    }

    /// Render the first `count` entries of the stack of the MIDI clip `id`
    /// (all of them when `None`): their result becomes the clip's notes and
    /// controller moves, and they leave the stack. The entries before
    /// the render stay in the undo step only. A clip of a link is refused:
    /// the render would change the notes of each clip of the link. An
    /// entry in the prefix that cannot run is refused too, with its place.
    pub(crate) fn clip_render(&mut self, id: Id, count: Option<usize>) -> Result<Rendered> {
        let clip = self.project.clip(id).with_context(|| format!("no clip {id}"))?;
        let ClipContent::Midi { notes, controls } = &clip.content else {
            bail!("only a MIDI clip has modifiers to render");
        };
        if let Some(link) = &clip.link {
            bail!("{} is linked ({link}): a render changes the notes of each clip of the link", clip.name);
        }
        let entries = clip.stack.0.len();
        let count = count.unwrap_or(entries);
        if entries == 0 {
            bail!("{} has no modifiers to render", clip.name);
        }
        if count == 0 || count > entries {
            bail!("{} has modifiers 1 to {entries}, not {count}", clip.name);
        }
        let input = Midi { notes: notes.clone(), controls: controls.as_slice().into() };
        let before = input.notes.len();
        let mut skipped = Vec::new();
        let key = input.source_key();
        let result = match modifiers::evaluate(&self.modifier_kinds, &clip.stack.0, 0..count, key, input, &mut skipped) {
            Progress::Done { result, .. } => result,
            Progress::Needs(job) => bail!("modifier {} ({}) runs in an extension: it cannot render yet", job.rest.start, job.entry.kind),
        };
        if let Some((at, why)) = skipped.first() {
            let hint = match why {
                Skipped::Waits(_) | Skipped::Newer(_) => "load its extension, or remove it",
                Skipped::Error(_) => "change its values, or remove it",
            };
            bail!("modifier {} cannot render: {why}; {hint}", at + 1);
        }
        let rendered = Rendered { modifiers: count, notes: result.notes.len(), dropped: before - result.notes.len() };
        self.edit_named(|p| {
            let c = p.clip_mut(id).with_context(|| format!("no clip {id}"))?;
            c.stack.0.drain(..count);
            if let ClipContent::Midi { notes, controls } = &mut c.content {
                *notes = result.notes;
                *controls = result.controls.to_vec();
            }
            // The notes are the project's own now, not those of a file.
            c.origin = c.source.take().or(c.origin.take());
            Ok(())
        })?;
        Ok(rendered)
    }
}

#[cfg(test)]
mod tests {
    use serde_json::{Value, json};

    use super::super::{ClipOpts, ClipPatch, PartOpts};
    use super::*;

    /// A document with a MIDI clip `clip` on a part: C4 and G9 (127 - 4),
    /// and `modifiers`.
    fn with_clip(modifiers: Value) -> Document {
        let mut doc = Document::default();
        let part = doc.part_add(PartOpts::default()).unwrap();
        let opts: ClipOpts = serde_json::from_value(json!({
            "name": "clip",
            "notes": [
                { "start": 0.0, "length": 1.0, "pitch": 60, "velocity": 100 },
                { "start": 1.0, "length": 1.0, "pitch": 123, "velocity": 100 },
            ],
            "length": 4.0,
            "modifiers": modifiers,
        }))
        .unwrap();
        doc.clip_add(part, opts, None, |_| Ok(0.0)).unwrap();
        doc
    }

    fn clip_id(doc: &Document) -> Id {
        doc.project.all_parts().flat_map(|t| t.clips.iter()).next().unwrap().id
    }

    #[test]
    fn a_render_of_a_prefix_writes_its_result_and_keeps_the_rest_of_the_stack() {
        let mut doc = with_clip(json!([
            { "kind": "transpose", "params": { "semitones": 5 } },
            { "kind": "velocity", "params": { "add": -10 } },
        ]));
        let id = clip_id(&doc);
        let done = doc.clip_render(id, Some(1)).unwrap();
        assert_eq!(done, Rendered { modifiers: 1, notes: 1, dropped: 1 }, "123 + 5 is out of the MIDI range");
        let clip = doc.project.clip(id).unwrap();
        let ClipContent::Midi { notes, .. } = &clip.content else { unreachable!() };
        assert_eq!(notes.iter().map(|n| (n.pitch, n.velocity)).collect::<Vec<_>>(), [(65, 100)]);
        assert_eq!(serde_json::to_value(&clip.stack).unwrap(), json!([{ "kind": "velocity", "params": { "add": -10 } }]));
    }

    #[test]
    fn a_render_is_refused_on_a_link_on_a_count_out_of_the_stack_and_on_an_entry_that_waits() {
        let mut doc = with_clip(json!([
            { "kind": "velocity", "params": { "add": 1 } },
            { "kind": "arp.up" },
        ]));
        let id = clip_id(&doc);
        let refused = |doc: &mut Document, count| doc.clip_render(id, count).unwrap_err().to_string();
        assert_eq!(refused(&mut doc, Some(3)), "clip has modifiers 1 to 2, not 3");
        assert_eq!(
            refused(&mut doc, None),
            "modifier 2 cannot render: `arp.up` waits: no extension that is loaded defines it; load its extension, or remove it"
        );
        doc.clip_link(id).unwrap();
        assert!(refused(&mut doc, Some(1)).starts_with("clip is linked (clip):"), "{}", refused(&mut doc, Some(1)));
    }

    #[test]
    fn a_stack_from_lua_is_checked_and_an_empty_table_is_no_stack() {
        let mut doc = with_clip(json!([]));
        let id = clip_id(&doc);
        // What `clip_set(id, { modifiers = value })` gives the document.
        let mut set = |value: Value| -> Result<()> {
            let patch: ClipPatch = serde_json::from_value(json!({ "modifiers": value }))?;
            patch.changes()?.into_iter().try_for_each(|change| doc.clip_set(id, change))
        };
        let bad = set(json!([{ "kind": "transpose", "params": { "semitones": 300 } }]));
        assert_eq!(bad.unwrap_err().to_string(), "transpose: semitones is a whole number from -127 to 127, not 300");
        set(json!([{ "kind": "transpose", "params": { "semitones": 2.0 } }])).unwrap();
        set(json!({})).unwrap();
        assert!(doc.project.clip(id).unwrap().stack.is_empty());
    }
}
