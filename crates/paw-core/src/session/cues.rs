//! Cues: a clip kept off the timeline played on a track from a boundary,
//! in place of the track's timeline, until it is stopped or the track goes
//! back to its timeline.
//!
//! A cue clip is a clip like any other (its notes are edited with the same
//! calls, it is saved and undone with the project) kept in `Track::cues`.
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

/// One track's cue, from a script: `{ track =, clip = }` plays a clip of
/// the track's cues, `{ track =, stop = true }` has the track play nothing,
/// and `{ track =, timeline = true }` has it play its timeline again.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct CueOpts {
    pub track: Id,
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
    /// A track's clips off the timeline, without their notes.
    pub(crate) fn cue_list(&self, track: Id) -> Result<Vec<super::ClipView<'_>>> {
        let t = self
            .doc.project
            .track(track)
            .with_context(|| format!("no track {track}"))?;
        Ok(t.cues
            .iter()
            .map(|c| {
                let mut view = super::clip_json(c, track, self.files_there.after(self.doc.changes(), self.now));
                view.cue = Some(true);
                view
            })
            .collect())
    }


    /// Cue clips, stop tracks or send them back to their timelines: every
    /// track asked for on the boundary of its quantize, all timed together.
    pub(crate) fn cue(&mut self, asked: Vec<CueOpts>) -> Result<()> {
        // The engine must hold the cue clips as they are now.
        self.flush();
        let mut launches = Vec::with_capacity(asked.len());
        for opts in asked {
            if self.doc.project.track(opts.track).is_none() {
                bail!("no track {}", opts.track);
            }
            let Some(&slot) = self.engine.map.tracks.get(&opts.track) else {
                continue;
            };
            let target = match (opts.clip, opts.stop, opts.timeline) {
                (Some(clip), false, false) => {
                    let row = self.engine.map.cue_row(opts.track, clip).with_context(|| {
                        if self.doc.project.find_cue_clip(clip).is_some() {
                            format!("clip {clip} is off the timeline of another track")
                        } else {
                            format!("clip {clip} is not off the timeline of track {}", opts.track)
                        }
                    })?;
                    Target::Slot(row)
                }
                (None, true, false) => Target::Stop,
                (None, false, true) => Target::Arrangement,
                _ => bail!("a cue names one of `clip`, `stop` or `timeline`"),
            };
            launches.push(Launch {
                track: slot,
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

    /// Every track back to its timeline at once, with nothing queued: for
    /// a project just opened, whose tracks may sit where another's were.
    pub(super) fn cue_reset(&mut self) {
        let launches: Vec<Launch> = self
            .doc.project
            .tracks
            .iter()
            .filter_map(|t| self.engine.map.tracks.get(&t.id))
            .map(|&track| Launch {
                track,
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

    /// What each track plays, as the engine last said: `clip` (the id of a
    /// cue clip) or `stopped`, or neither for the timeline; `phase` (beats
    /// into the clip's loop) and `length`; `since`, the beat it began on;
    /// and what is queued (`queued` is a clip's id, `"stop"` or
    /// `"timeline"`) with the beat it happens on (`at`).
    pub(crate) fn cue_state(&self) -> Value {
        let mut out = Vec::new();
        for track in &self.doc.project.tracks {
            let Some(state) = self
                .engine.map
                .tracks
                .get(&track.id)
                .and_then(|&slot| self.engine.handle.shared.launch(slot))
            else {
                continue;
            };
            let name = |target: Target| match target {
                Target::Slot(row) => json!(self.engine.map.cue_clip(track.id, row)),
                Target::Stop => json!("stop"),
                Target::Arrangement => json!("timeline"),
            };
            let mut view = json!({ "track": track.id, "since": state.since });
            match state.playing {
                Target::Slot(row) => {
                    let id = self.engine.map.cue_clip(track.id, row);
                    view["clip"] = json!(id);
                    view["phase"] = json!(state.phase);
                    if let Some(c) = id.and_then(|id| track.cues.iter().find(|c| c.id == id)) {
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
