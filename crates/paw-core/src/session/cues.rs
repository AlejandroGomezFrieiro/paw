//! Cues: a clip kept off the timeline played on a part from a boundary,
//! in place of the part's timeline, until it is stopped or the part goes
//! back to its timeline.
//!
//! A cue clip is a clip like any other (its notes are edited with the same
//! calls, it is saved and undone with the project) kept in `Part::cues`.
//! It starts at 0 and repeats every `length` beats while it plays. Cueing
//! is a message to the engine, which starts the clip on the next boundary
//! of its quantize, to the frame (`paw_engine::launch`); the engine does
//! the timing, so a busy kernel never starts a clip late. What plays is
//! read back from the engine and never kept here: it is not part of the
//! project or of undo. A render plays the timeline, since a fresh engine
//! has nothing cued; a script that wants a performance in a render writes
//! it into the timeline first (`extensions/launcher` captures one).
//!
//! What cues are for is the business of extensions: the clip launcher
//! (`extensions/launcher`) keeps its grid of slots and scenes in the clips'
//! and the project's `meta`, and cues them. Live looping, cue points or a
//! step sequencer can use the same calls.

use anyhow::{Context, Result, bail};
use paw_engine::Msg;
use paw_engine::launch::{Launch, Target};
use serde::Deserialize;
use serde_json::{Value, json};

use super::Session;
use crate::model::{Id, Quantize};

/// One part's cue, from a script: `{ part =, clip = }` plays a clip of
/// the part's cues, `{ part =, stop = true }` has the part play nothing,
/// and `{ part =, timeline = true }` has it play its timeline again.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct CueOpts {
    pub part: Id,
    #[serde(default)]
    pub clip: Option<Id>,
    #[serde(default)]
    pub stop: bool,
    #[serde(default)]
    pub timeline: bool,
    /// The boundary it waits for: a bar when not given.
    #[serde(default)]
    pub quantize: Option<Quantize>,
    /// Take over where the clip that plays had got to in its loop.
    #[serde(default)]
    pub legato: bool,
    /// The beat the clip's loop counts from, as if it had played since then.
    #[serde(default)]
    pub from: Option<f64>,
}

impl Session {
    /// A part's clips off the timeline, without their notes.
    pub(crate) fn cue_list(&self, part: Id) -> Result<Vec<super::ClipView<'_>>> {
        let t = self
            .doc.project
            .part(part)
            .with_context(|| format!("no part {part}"))?;
        Ok(t.cues
            .iter()
            .map(|c| {
                let mut view = super::clip_json(c, part, self.files_there.after(self.doc.changes(), self.now));
                view.cue = Some(true);
                view
            })
            .collect())
    }


    /// Cue clips, stop parts or send them back to their timelines: every
    /// part asked for on the boundary of its quantize, all timed together.
    pub(crate) fn cue(&mut self, asked: Vec<CueOpts>) -> Result<()> {
        // The engine must hold the cue clips as they are now.
        self.flush();
        let mut launches = Vec::with_capacity(asked.len());
        for opts in asked {
            if self.doc.project.part(opts.part).is_none() {
                bail!("no part {}", opts.part);
            }
            let Some(&slot) = self.engine.map.parts.get(&opts.part) else {
                continue;
            };
            let target = match (opts.clip, opts.stop, opts.timeline) {
                (Some(clip), false, false) => {
                    let row = self.engine.map.cue_row(opts.part, clip).with_context(|| {
                        if self.doc.project.find_cue_clip(clip).is_some() {
                            format!("clip {clip} is off the timeline of another part")
                        } else {
                            format!("clip {clip} is not off the timeline of part {}", opts.part)
                        }
                    })?;
                    Target::Slot(row)
                }
                (None, true, false) => Target::Stop,
                (None, false, true) => Target::Arrangement,
                _ => bail!("a cue names one of `clip`, `stop` or `timeline`"),
            };
            launches.push(Launch {
                part: slot,
                target,
                quantize: opts.quantize.unwrap_or(Quantize::Bar).engine(),
                legato: opts.legato,
                from: opts.from,
            });
        }
        if !launches.is_empty() {
            self.engine.handle.send(Msg::Launch(launches.into()));
        }
        Ok(())
    }

    /// Every part back to its timeline at once, with nothing queued: for
    /// a project just opened, whose parts may sit where another's were.
    pub(super) fn cue_reset(&mut self) {
        let launches: Vec<Launch> = self
            .doc.project
            .parts
            .iter()
            .filter_map(|t| self.engine.map.parts.get(&t.id))
            .map(|&part| Launch {
                part,
                target: Target::Arrangement,
                quantize: paw_types::Quantize::Off,
                legato: false,
                from: None,
            })
            .collect();
        if !launches.is_empty() {
            self.engine.handle.send(Msg::Launch(launches.into()));
        }
    }

    /// What each part plays, as the engine last said: `clip` (the id of a
    /// cue clip) or `stopped`, or neither for the timeline; `phase` (beats
    /// into the clip's loop) and `length`; `since`, the beat it began on;
    /// and what is queued (`queued` is a clip's id, `"stop"` or
    /// `"timeline"`) with the beat it happens on (`at`).
    pub(crate) fn cue_state(&self) -> Value {
        let mut out = Vec::new();
        for part in &self.doc.project.parts {
            let Some(state) = self
                .engine.map
                .parts
                .get(&part.id)
                .and_then(|&slot| self.engine.handle.shared.launch(slot))
            else {
                continue;
            };
            let name = |target: Target| match target {
                Target::Slot(row) => json!(self.engine.map.cue_clip(part.id, row)),
                Target::Stop => json!("stop"),
                Target::Arrangement => json!("timeline"),
            };
            let mut view = json!({ "part": part.id, "since": state.since });
            match state.playing {
                Target::Slot(row) => {
                    let id = self.engine.map.cue_clip(part.id, row);
                    view["clip"] = json!(id);
                    view["phase"] = json!(state.phase);
                    if let Some(c) = id.and_then(|id| part.cues.iter().find(|c| c.id == id)) {
                        view["length"] = json!(c.length);
                    }
                }
                Target::Stop => view["stopped"] = json!(true),
                Target::Arrangement => {}
            }
            if let Some((target, at)) = state.queued {
                view["queued"] = name(target);
                view["at"] = json!(at);
            }
            out.push(view);
        }
        Value::Array(out)
    }
}
