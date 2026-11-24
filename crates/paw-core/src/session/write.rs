//! Writing automation by moving things while the song plays.
//!
//! Each part has a mode (`Part::automation`). In `touch`, `latch` and
//! `write`, and on every part while the transport's `write` switch is on
//! (which latches), a fader, pan or parameter that is moved (from a script,
//! a frontend, a controller, or a plugin's own window) is held: every turn
//! its value is written into its lane at the playhead, over whatever the
//! lane held there.
//!
//! - `latch` holds from the first move until playback stops.
//! - `touch` holds while the control is held ([`Session::automation_hold`])
//!   or for a moment after it was last moved, then lets the lane take over
//!   again: the lane is joined back to what it held before.
//! - `write` holds everything the part's lanes move from where playback
//!   began, moved or not.
#![expect(clippy::float_cmp, reason = "debt: pay down")]

use std::time::Duration;

use crate::clock::ScheduleTime;

use anyhow::Result;
use paw_types::automation::value_at;

use super::{LaneKind, LaneOpts, Session};
use crate::model::{AutoMode, Id, Target};

/// Whether moving a fader or a parameter while playing writes automation,
/// and the values being written.
#[derive(Default)]
pub(super) struct Writing {
    /// The transport's `write` switch: every part latches.
    pub on: bool,
    pub latched: Vec<Latch>,
}

/// A value being written into a lane as the song plays.
pub(super) struct Latch {
    part: Id,
    target: Target,
    value: f64,
    /// What it was before it was first moved, for the start of a new lane.
    before: f64,
    /// Where and what was last written.
    last: Option<(f64, f64)>,
    /// The last point written only marks how far a run of one value has got,
    /// and moves on with the playhead.
    moving: bool,
    /// When it was last moved, and whether something still holds it.
    touched: ScheduleTime,
    held: bool,
    /// Let go by hand: it stops at the next turn, however lately it moved.
    let_go: bool,
    /// The lane's points before anything was written, to join back to.
    original: Option<Vec<(f64, f64)>>,
}

/// The shortest step between two points written while a value is held, in beats.
const STEP: f64 = 1.0 / 16.0;

/// How long after its last move a control in touch mode is let go, unless
/// something holds it.
const TOUCH_RELEASE: Duration = Duration::from_millis(600);

/// Beats over which a lane goes back to what it held when a control is let go.
const RETURN: f64 = 1.0 / 8.0;

impl Session {
    /// How moves on a part are treated right now.
    pub(super) fn auto_mode(&self, part: Id) -> AutoMode {
        let mode = self
            .doc.project
            .part(part)
            .map_or(AutoMode::Read, |t| t.automation);
        // The transport's switch latches every part that does not write
        // in a way of its own.
        if self.writing.on && !mode.writes() {
            return AutoMode::Latch;
        }
        mode
    }

    /// Note that something was moved from `before` to `value`.
    pub(super) fn touch(&mut self, part: Id, target: Target, before: f64, value: f64) {
        if !self.play.playing || !self.auto_mode(part).writes() {
            return;
        }
        match self
            .writing
            .latched
            .iter_mut()
            .find(|l| l.part == part && l.target == target)
        {
            Some(latch) => {
                latch.value = value;
                latch.touched = self.now;
                latch.let_go = false;
            }
            None => self.writing.latched.push(Latch {
                part,
                target,
                value,
                before,
                last: None,
                moving: false,
                touched: self.now,
                held: false,
                let_go: false,
                original: None,
            }),
        }
    }

    /// Say that a control is being held (a fader under the pointer), or has
    /// been let go. In touch mode it writes for as long as it is held, moved
    /// or not, and stops when it is let go.
    pub(crate) fn automation_hold(&mut self, part: Id, target: Target, on: bool) {
        if on {
            let Some(value) = self.target_value(part, &target) else {
                return;
            };
            self.touch(part, target.clone(), value, value);
        }
        if let Some(latch) = self
            .writing
            .latched
            .iter_mut()
            .find(|l| l.part == part && l.target == target)
        {
            latch.held = on;
            if !on {
                // Let go: as if its moment had passed.
                latch.held = false;
                latch.let_go = true;
            }
        }
    }

    /// [`automation_hold`](Self::automation_hold) with the control named
    /// as a lane's target is: "volume", "pan", or "param" with its device
    /// and parameter.
    pub(crate) fn automation_hold_named(
        &mut self,
        part: Id,
        target: &str,
        device: Option<Id>,
        param: Option<String>,
        on: bool,
    ) -> Result<()> {
        let target = match (target, device, param) {
            ("volume", _, _) => Target::Volume,
            ("pan", _, _) => Target::Pan,
            ("param", Some(device), Some(param)) => Target::Param { device, param },
            ("param", _, _) => anyhow::bail!("a parameter is named by its device and its key"),
            (other, _, _) => anyhow::bail!("`{other}` is not something automation moves"),
        };
        if self.doc.project.part(part).is_none() {
            anyhow::bail!("no part {part}");
        }
        self.automation_hold(part, target, on);
        Ok(())
    }

    /// What a fader, pan or parameter is set to in the project.
    fn target_value(&self, part: Id, target: &Target) -> Option<f64> {
        let t = self.doc.project.part(part)?;
        match target {
            Target::Volume => Some(t.volume),
            Target::Pan => Some(t.pan),
            Target::Param { device, param } => {
                self.doc.project.device(*device)?.params.get(param).copied()
            }
            Target::State { .. } => None,
        }
    }

    /// In write mode everything a part's lanes move is held from the start.
    fn hold_written_parts(&mut self) {
        let mut wanted = Vec::new();
        for part in self.doc.project.all_parts() {
            if part.automation != AutoMode::Write {
                continue;
            }
            for lane in &part.lanes {
                let known = self
                    .writing
                    .latched
                    .iter()
                    .any(|l| l.part == part.id && l.target == lane.target);
                if !known && let Some(value) = self.target_value(part.id, &lane.target) {
                    wanted.push((part.id, lane.target.clone(), value));
                }
            }
        }
        for (part, target, value) in wanted {
            self.touch(part, target, value, value);
        }
    }

    /// Write what is being held into its lanes at the playhead. Called once a turn.
    pub(crate) fn write_automation(&mut self) {
        if !self.play.playing {
            self.writing.latched.clear();
            return;
        }
        self.hold_written_parts();
        if self.writing.latched.is_empty() {
            return;
        }
        let now = self.position();
        let mut latched = std::mem::take(&mut self.writing.latched);
        latched.retain_mut(|latch| {
            let mode = self.auto_mode(latch.part);
            if !mode.writes() {
                return false;
            }
            let let_go = mode == AutoMode::Touch
                && !latch.held
                && (latch.let_go || self.now - latch.touched >= TOUCH_RELEASE);
            let written = if let_go {
                self.release_latch(latch, now)
            } else {
                self.write_latch(latch, now)
            };
            if let Err(err) = written {
                self.doc.warnings
                    .push(format!("could not write automation: {err:#}"));
            }
            !let_go
        });
        // Whatever was moved while these were written is held too.
        latched.append(&mut self.writing.latched);
        self.writing.latched = latched;
    }

    /// The lane a latch writes into, made if the target has none yet.
    fn latch_lane(&mut self, latch: &Latch) -> Result<Option<Id>> {
        let Some(part) = self.doc.project.part(latch.part) else {
            return Ok(None);
        };
        if let Some(lane) = part.lanes.iter().find(|l| l.target == latch.target) {
            return Ok(Some(lane.id));
        }
        let (target, device, param) = match &latch.target {
            Target::Volume => (LaneKind::Volume, None, None),
            Target::Pan => (LaneKind::Pan, None, None),
            Target::Param { device, param } => (LaneKind::Param, Some(*device), Some(param.clone())),
            // Nothing moves a state lane but its points.
            Target::State { .. } => return Ok(None),
        };
        self.lane_add(
            latch.part,
            LaneOpts {
                target: Some(target),
                device,
                param,
                enabled: Some(true),
                points: Vec::new(),
                states: Vec::new(),
            },
        )
        .map(Some)
    }

    fn write_latch(&mut self, latch: &mut Latch, now: f64) -> Result<()> {
        // A loop or a jump back starts a new pass.
        if latch.last.is_some_and(|(at, _)| now < at) {
            latch.last = None;
            latch.moving = false;
            latch.original = None;
        }
        let same = latch.last.is_some_and(|(_, value)| value == latch.value);
        if let Some((at, _)) = latch.last
            && same
            && now - at < STEP
        {
            return Ok(());
        }
        let Some(lane) = self.latch_lane(latch)? else {
            return Ok(());
        };
        let mut points = self.doc.lane_points(lane)?.to_vec();
        if latch.original.is_none() {
            latch.original = Some(points.clone());
        }
        if points.is_empty() {
            // Up to here the song keeps the value it had.
            points.push(((now - STEP).max(0.0), latch.before));
        } else if latch.last.is_none() {
            // The first move: up to here the lane keeps what it held, so
            // that the move is a step and not a slope from the point before.
            let just_before = (now - STEP).max(0.0);
            let held = points
                .iter()
                .any(|(beat, _)| *beat >= just_before && *beat <= now);
            if !held && let Some(value) = value_at(&points, just_before) {
                points.push((just_before, value));
            }
        }
        // What the lane held between the last point written and here gives
        // way, and so does that point if it only marked how far a held value
        // had got.
        let from = latch.last.map_or(now, |(at, _)| at);
        let moving = latch.moving;
        points.retain(|(beat, _)| {
            let passed = *beat > from && *beat <= now;
            let marker = moving && same && *beat == from;
            !passed && !marker
        });
        points.push((now, latch.value));
        self.lane_set_points(lane, points, false)?;
        latch.moving = same;
        latch.last = Some((now, latch.value));
        Ok(())
    }

    /// A control in touch mode was let go: write up to here, then join the
    /// lane back to what it held before it was touched.
    fn release_latch(&mut self, latch: &mut Latch, now: f64) -> Result<()> {
        let Some((from, _)) = latch.last else {
            // Never written: nothing to join.
            return Ok(());
        };
        if now < from {
            return Ok(());
        }
        let Some(lane) = self.latch_lane(latch)? else {
            return Ok(());
        };
        let back = now + RETURN;
        let to = latch
            .original
            .as_deref()
            .and_then(|points| value_at(points, back))
            .unwrap_or(latch.before);
        let mut points = self.doc.lane_points(lane)?.to_vec();
        points.retain(|(beat, _)| !(*beat > from && *beat <= back));
        points.push((now, latch.value));
        points.push((back, to));
        self.lane_set_points(lane, points, false)
    }
}

#[cfg(test)]
mod tests {
    use paw_engine::Registry;
    use paw_engine::backend::{BackendChoice, BackendOptions};
    use serde_json::json;

    use super::*;
    use crate::session::document::PartOpts;

    /// Change part `part` as `paw.api.part_set` does with the table `patch`.
    fn set(session: &mut Session, part: Id, patch: serde_json::Value) {
        session.part_patch(part, serde_json::from_value(patch).unwrap()).unwrap();
    }

    /// A session on the null backend, playing, with one part in touch mode.
    fn touching() -> (Session, Id) {
        let backend = BackendOptions { backend: BackendChoice::Null, ..Default::default() };
        let mut session = Session::new(&backend, Registry::with_builtins()).unwrap();
        let part = session.doc.part_add(PartOpts::default()).unwrap();
        set(&mut session, part, json!({ "automation": "touch" }));
        session.play.playing = true;
        (session, part)
    }

    #[test]
    fn a_control_in_touch_mode_is_let_go_after_a_pause_on_the_schedule_clock() {
        let (mut session, part) = touching();
        let at = |ms| ScheduleTime::from_start(Duration::from_millis(ms));
        session.set_now(at(0));
        set(&mut session, part, json!({ "volume": -6.0 }));
        session.write_automation();
        assert_eq!(session.writing.latched.len(), 1, "a move holds the control");

        session.set_now(at(400));
        set(&mut session, part, json!({ "volume": -3.0 }));
        session.set_now(at(400) + (TOUCH_RELEASE - Duration::from_millis(1)));
        session.write_automation();
        assert_eq!(session.writing.latched.len(), 1, "the pause counts from the last move");

        session.set_now(at(400) + TOUCH_RELEASE);
        session.write_automation();
        assert!(session.writing.latched.is_empty(), "a pause of {TOUCH_RELEASE:?} lets it go");
    }
}
