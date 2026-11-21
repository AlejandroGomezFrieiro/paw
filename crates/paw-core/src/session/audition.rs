//! Hearing something before choosing it, without the project or its undo
//! history keeping any trace: what the pickers do as their selection moves.
//!
//! Two things make that up. A trial is a stretch of edits that are made
//! and heard as any others, then either thrown away, the project put back
//! exactly as it was, or kept as one undo step: a preset tried on a device,
//! an instrument tried on a track. The preview is a sound file heard on
//! its own over everything else ([`paw_engine::preview`]), at a level of
//! its own, decoded on a thread of its own so that a long file holds
//! nothing up.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::mpsc::{Receiver, TryRecvError};
use std::time::{Duration, Instant};

use anyhow::{Result, bail};
use paw_engine::{AudioData, Msg, Preview};
use serde_json::{Value, json};

use super::Session;
use crate::model::Id;

/// Points in a file's outline, for drawing it beside a picker.
const OUTLINE: usize = 256;

/// The edits under way that may yet be thrown away.
#[derive(Default)]
pub(super) struct Trial {
    /// Devices a preset was loaded into during the trial: their state
    /// before it is the one the step before holds.
    pub loaded: HashSet<Id>,
}

/// What is being tried and heard before it is chosen: the trial under way
/// and the sound file heard on its own, with the level it plays at.
pub(super) struct Audition {
    pub trial: Option<Trial>,
    preview: Option<Previewing>,
    /// The last preview's id, so that the engine's reports of an older one
    /// are told apart.
    preview_ids: u32,
    /// The level of the preview in dB.
    preview_level: f64,
}

impl Default for Audition {
    fn default() -> Self {
        Self {
            trial: None,
            preview: None,
            preview_ids: 0,
            preview_level: -12.0,
        }
    }
}

/// The sound file heard on its own.
struct Previewing {
    file: PathBuf,
    id: u32,
    stage: Stage,
}

enum Stage {
    Loading(Receiver<Result<Arc<AudioData>>>),
    Playing {
        data: Arc<AudioData>,
        outline: Vec<f32>,
        /// When it was sent, and whether the engine has been seen playing
        /// it: until then it is starting, not over.
        since: Instant,
        heard: bool,
    },
    Failed(String),
}

/// The loudest sample of each of `n` equal stretches of the sound.
fn outline(data: &AudioData, n: usize) -> Vec<f32> {
    let (l, r) = (&*data.channels[0], &*data.channels[1]);
    let len = l.len().min(r.len());
    if len == 0 {
        return Vec::new();
    }
    (0..n)
        .map(|i| {
            let (from, to) = (i * len / n, ((i + 1) * len / n).max(i * len / n + 1).min(len));
            l[from..to]
                .iter()
                .chain(&r[from..to])
                .fold(0.0f32, |m, s| m.max(s.abs()))
        })
        .collect()
}

impl Session {
    // --- trials --------------------------------------------------------------

    /// Start a trial: edits from here on are made and heard, and
    /// [`trial_end`](Self::trial_end) keeps them as one undo step or puts
    /// the project back as it was. Edits made before it close their step.
    pub fn trial_begin(&mut self) -> Result<()> {
        if self.audition.trial.is_some() {
            bail!("a trial is under way already");
        }
        self.flush();
        self.checkpoint();
        self.audition.trial = Some(Trial::default());
        Ok(())
    }

    /// Whether a trial is under way.
    pub fn trial_active(&self) -> bool {
        self.audition.trial.is_some()
    }

    /// End the trial: keep its edits, which become the next undo step, or
    /// put the project back exactly as it was before it. True when there
    /// was one.
    pub fn trial_end(&mut self, keep: bool) -> bool {
        let Some(trial) = self.audition.trial.take() else {
            return false;
        };
        if keep || !self.undo.touched {
            return true;
        }
        // The step before holds the project as it was, but plugins keep
        // their state to themselves until asked: take what they hold now,
        // except where the trial loaded a preset.
        let mut back = self.undo.checkpoint.clone();
        let before: std::collections::HashMap<Id, &Option<String>> = self
            .undo.checkpoint
            .all_tracks()
            .flat_map(|t| &t.devices)
            .map(|d| (d.id, &d.state))
            .collect();
        for track in self.project.all_tracks() {
            for device in &track.devices {
                // Only what differs is copied, so that what did not change
                // is the same to the engine and left alone.
                if !trial.loaded.contains(&device.id)
                    && before.get(&device.id).is_some_and(|s| **s != device.state)
                    && let Some(old) = back.device_mut(device.id)
                {
                    old.state = device.state.clone();
                }
            }
        }
        self.project = back;
        self.undo.touched = false;
        self.dirty = true;
        self.undo.restoring = true;
        self.undo.edits += 1;
        self.undo.sweep = Default::default();
        self.undo.history.clear_labels();
        true
    }

    /// A preset is about to be loaded into a device: during a trial its
    /// state before the first is the one to come back to.
    pub(super) fn trial_loads(&mut self, id: Id) -> bool {
        match &mut self.audition.trial {
            Some(trial) => trial.loaded.insert(id),
            None => true,
        }
    }

    // --- the preview ---------------------------------------------------------

    /// Hear a sound file on its own, from its start, in place of whatever
    /// was heard. It is decoded apart; [`preview_view`](Self::preview_view)
    /// says when it plays.
    pub fn preview_play(&mut self, file: &Path) -> Result<()> {
        if !file.is_file() {
            bail!("{} is not a file", file.display());
        }
        self.preview_stop();
        self.audition.preview_ids += 1;
        let id = self.audition.preview_ids;
        let rate = self.engine.handle.sample_rate as u32;
        // A file the project plays is decoded already.
        let stage = match self.audio.playing(file, rate) {
            Some(data) => self.preview_start(id, data.clone()),
            None => {
                let (tx, rx) = std::sync::mpsc::channel();
                let (path, store) = (file.to_path_buf(), self.audio.store.clone());
                std::thread::Builder::new()
                    .name("preview".into())
                    .spawn(move || {
                        let _ = tx.send(AudioData::load_with(&path, store.as_ref()));
                    })?;
                Stage::Loading(rx)
            }
        };
        self.audition.preview = Some(Previewing {
            file: file.to_path_buf(),
            id,
            stage,
        });
        Ok(())
    }

    fn preview_start(&mut self, id: u32, data: Arc<AudioData>) -> Stage {
        data.advise(0.0, 4.0);
        let voice = Preview::new(
            data.clone(),
            self.engine.handle.sample_rate,
            paw_engine::db_to_gain(self.audition.preview_level),
            id,
        );
        self.engine.handle.send(Msg::SetPreview(Some(Box::new(voice))));
        Stage::Playing {
            outline: outline(&data, OUTLINE),
            data,
            since: Instant::now(),
            heard: false,
        }
    }

    /// Stop the sound file heard on its own, fading it out.
    pub fn preview_stop(&mut self) {
        if self.audition.preview.take().is_some() {
            self.engine.handle.send(Msg::SetPreview(None));
        }
    }

    /// The level of the sound file heard on its own, in dB.
    pub fn preview_set_level(&mut self, db: f64) {
        self.audition.preview_level = db.clamp(-120.0, 12.0);
        self.engine.handle
            .send(Msg::SetPreviewGain(paw_engine::db_to_gain(self.audition.preview_level)));
    }

    /// Take up a file decoded since the last look, and ask for what is
    /// played next to be read in from the disk. Called from `idle`.
    pub(super) fn poll_preview(&mut self) {
        let Some(preview) = &mut self.audition.preview else {
            return;
        };
        let id = preview.id;
        match &mut preview.stage {
            Stage::Loading(rx) => match rx.try_recv() {
                Ok(Ok(data)) => {
                    let stage = self.preview_start(id, data);
                    if let Some(preview) = &mut self.audition.preview {
                        preview.stage = stage;
                    }
                }
                Ok(Err(err)) => preview.stage = Stage::Failed(format!("{err:#}")),
                Err(TryRecvError::Disconnected) => {
                    preview.stage = Stage::Failed("it could not be read".into())
                }
                Err(TryRecvError::Empty) => {}
            },
            Stage::Playing { data, heard, .. } => {
                if let Some((playing, at)) = self.engine.handle.shared.preview()
                    && playing == id
                {
                    *heard = true;
                    data.advise(at, at + 4.0);
                }
            }
            Stage::Failed(_) => {}
        }
    }

    /// What is heard on its own: `{ file, state, position, length,
    /// outline, error, level }`, with `state` "loading", "playing",
    /// "ended" or "failed", the times in seconds and the outline the
    /// loudest sample of each of 256 stretches of the file. Null when
    /// nothing is.
    pub fn preview_view(&self) -> Value {
        let Some(preview) = &self.audition.preview else {
            return Value::Null;
        };
        let mut view = json!({
            "file": preview.file, "level": self.audition.preview_level,
        });
        match &preview.stage {
            Stage::Loading(_) => view["state"] = "loading".into(),
            Stage::Failed(why) => {
                view["state"] = "failed".into();
                view["error"] = why.clone().into();
            }
            Stage::Playing {
                data,
                outline,
                since,
                heard,
            } => {
                let now = self
                    .engine.handle
                    .shared
                    .preview()
                    .filter(|(id, _)| *id == preview.id);
                // Sent but not yet taken up by the engine, it is starting
                // rather than over (unless it has had time to play whole).
                let starting = now.is_none()
                    && !*heard
                    && since.elapsed() < Duration::from_secs_f64(data.seconds() + 1.0);
                view["state"] = if now.is_some() || starting { "playing" } else { "ended" }.into();
                view["position"] = match now {
                    Some((_, at)) => at,
                    None if starting => 0.0,
                    None => data.seconds(),
                }
                .into();
                view["length"] = data.seconds().into();
                view["outline"] = json!(outline);
            }
        }
        view
    }
}
