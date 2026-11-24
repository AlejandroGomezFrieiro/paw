//! Automation lanes: their points, shapes and states, as the model holds
//! them. The range of a plugin parameter is the live plugin's: the session
//! gives it ([`ParamRange`]). Adding a lane asks the plugin, so it is the
//! session's, in `session/automation.rs`.
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::float_cmp, reason = "debt: pay down")]

use std::sync::Arc;

use anyhow::{Context, Result, bail};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use serde::Serialize;

use super::Document;
use super::values::patch;
use crate::model::{Id, Lane, LaneState, Segment, Shape, Target};

/// The lowest and highest value of a plugin's parameter (device, key),
/// or none when the plugin is not there to say.
pub(crate) type ParamRange<'a> = &'a dyn Fn(Id, &str) -> Option<(f64, f64)>;

/// A lane as `paw.api.lane_get` gives it, without its points.
#[derive(Serialize, schemars::JsonSchema)]
#[schemars(rename = "Lane")]
pub(crate) struct LaneView<'a> {
    id: Id,
    part: Id,
    /// A lane that is off keeps its points but does not move its target.
    enabled: bool,
    point_count: usize,
    /// The lowest value of the target.
    min: f64,
    /// The highest value of the target.
    max: f64,
    target: LaneTarget,
    /// The device of a parameter or state lane.
    device: Option<Id>,
    /// The key of the parameter of a parameter lane.
    param: Option<&'a str>,
    /// The names of the states of a state lane.
    states: Option<Vec<&'a str>>,
}

/// What a lane moves.
#[derive(Serialize, schemars::JsonSchema)]
#[serde(rename_all = "lowercase")]
enum LaneTarget {
    Volume,
    Pan,
    Param,
    State,
}

impl<'a> LaneView<'a> {
    fn of(l: &'a Lane, part: Id, param_range: ParamRange) -> Self {
        let (min, max) = target_range(&l.target, l.states.len(), param_range);
        let (target, device, param, states) = match &l.target {
            Target::Volume => (LaneTarget::Volume, None, None, None),
            Target::Pan => (LaneTarget::Pan, None, None, None),
            Target::Param { device, param } => (LaneTarget::Param, Some(*device), Some(param.as_str()), None),
            Target::State { device } => {
                let states = l.states.iter().map(|s| s.name.as_str()).collect();
                (LaneTarget::State, Some(*device), None, Some(states))
            }
        };
        LaneView {
            id: l.id,
            part,
            enabled: l.enabled,
            point_count: l.points.len(),
            min,
            max,
            target,
            device,
            param,
            states,
        }
    }
}

patch! {
    /// What `paw.api.lane_set` changes in a lane.
    #[schemars(rename = "LaneChanges")]
    pub(crate) struct LanePatch => LaneChange, "lanes have no settable field" {
        /// A lane that is off keeps its points but does not move its target.
        "enabled" enabled: bool => Enabled value,
    }
}

impl Document {
    /// A lane as a table, without its points.
    pub(crate) fn lane_view<'a>(&'a self, id: Id, param_range: ParamRange) -> Result<LaneView<'a>> {
        let (part, _) = self
            .project
            .find_lane(id)
            .with_context(|| format!("no lane {id}"))?;
        let lane = self.project.lane(id).with_context(|| format!("no lane {id}"))?;
        Ok(LaneView::of(lane, part, param_range))
    }

    /// The automation lanes of a part, without their points.
    pub(crate) fn lane_list<'a>(&'a self, part: Id, param_range: ParamRange) -> Result<Vec<LaneView<'a>>> {
        let t = self
            .project
            .part(part)
            .with_context(|| format!("no part {part}"))?;
        Ok(t.lanes.iter().map(|l| LaneView::of(l, part, param_range)).collect())
    }

    pub(crate) fn lane_remove(&mut self, id: Id) -> Result<()> {
        self.edit(|p| {
            let (part, index) = p.find_lane(id).with_context(|| format!("no lane {id}"))?;
            p.part_in(part)?.lanes.remove(index);
            Ok(())
        })
    }

    /// Make one change of lane `id`. A value that it already holds is no
    /// change.
    pub(crate) fn lane_set(&mut self, id: Id, change: LaneChange) -> Result<()> {
        let lane = self.project.lane(id).with_context(|| format!("no lane {id}"))?;
        let LaneChange::Enabled(on) = change;
        if lane.enabled == on {
            return Ok(());
        }
        self.edit(|p| {
            p.lane_in(id)?.enabled = on;
            Ok(())
        })
    }

    pub(crate) fn lane_points(&self, id: Id) -> Result<&[(f64, f64)]> {
        Ok(&self
            .project
            .lane(id)
            .with_context(|| format!("no lane {id}"))?
            .points)
    }

    /// Replace a lane's points, or add one, replacing any already at its beat.
    pub(crate) fn lane_set_points(
        &mut self,
        id: Id,
        new: Vec<(f64, f64)>,
        add: bool,
        param_range: ParamRange,
    ) -> Result<()> {
        let lane = self
            .project
            .lane(id)
            .with_context(|| format!("no lane {id}"))?
            .clone();
        let states = lane.states.len();
        let mut points = clean_points(&lane.target, states, new, param_range)?;
        if add {
            let mut all = lane.points.clone();
            all.retain(|p| !points.iter().any(|n| n.0 == p.0));
            all.append(&mut points);
            points = clean_points(&lane.target, states, all, param_range)?;
        }
        self.edit(|p| {
            let lane = p.lane_in(id)?;
            // A shape stays with a point that stays where it was.
            lane.shapes.retain(|s| points.iter().any(|q| q.0 == s.beat));
            lane.points = points;
            Ok(())
        })
    }

    /// The shapes of a lane's stretches that are not straight.
    pub(crate) fn lane_shapes(&self, id: Id) -> Result<&[Segment]> {
        Ok(&self
            .project
            .lane(id)
            .with_context(|| format!("no lane {id}"))?
            .shapes)
    }

    /// Replace the shapes of a lane's stretches: each by the beat of a point
    /// of the lane; a straight one need not be listed.
    pub(crate) fn lane_set_shapes(&mut self, id: Id, shapes: Vec<Segment>) -> Result<()> {
        let lane = self.project.lane(id).with_context(|| format!("no lane {id}"))?;
        let mut kept: Vec<Segment> = Vec::new();
        for mut s in shapes {
            if !s.beat.is_finite() || !s.tension.is_finite() {
                bail!("a shape needs a finite beat and tension");
            }
            if !lane.points.iter().any(|q| q.0 == s.beat) {
                bail!("lane {id} has no point at beat {} to shape", s.beat);
            }
            s.tension = s.tension.clamp(-1.0, 1.0);
            kept.retain(|k| k.beat != s.beat);
            if s.shape != Shape::Linear {
                kept.push(s);
            }
        }
        kept.sort_by(|a, b| a.beat.total_cmp(&b.beat));
        self.edit(|p| {
            p.lane_in(id)?.shapes = kept;
            Ok(())
        })
    }

    /// The lane's value at a beat, or nothing when it has no points.
    pub(crate) fn lane_value_at(&self, id: Id, beat: f64) -> Result<Option<f64>> {
        let lane = self.project.lane(id).with_context(|| format!("no lane {id}"))?;
        Ok(paw_types::automation::value_at(&lane.played(), beat))
    }

    /// The states of a state lane, whole.
    pub(crate) fn lane_states(&self, id: Id) -> Result<Vec<Arc<LaneState>>> {
        let lane = self.project.lane(id).with_context(|| format!("no lane {id}"))?;
        if !matches!(lane.target, Target::State { .. }) {
            bail!("lane {id} is not a state lane");
        }
        Ok(lane.states.clone())
    }

    /// Replace the states of a state lane, as one edit. A point that names
    /// a state no longer there names the last; with no states, the points go.
    pub(crate) fn lane_set_states(&mut self, id: Id, states: Vec<LaneState>) -> Result<()> {
        self.lane_states(id)?;
        let states = states
            .into_iter()
            .map(|s| check_lane_state(s).map(Arc::new))
            .collect::<Result<Vec<_>>>()?;
        let mut names = std::collections::HashSet::new();
        if let Some(twice) = states.iter().find(|s| !names.insert(s.name.as_str())) {
            bail!("two states are named `{}`", twice.name);
        }
        let lane = self.project.lane(id).with_context(|| format!("no lane {id}"))?.clone();
        let points = if states.is_empty() {
            Vec::new()
        } else {
            // A state lane's range is its states: it has no plugin parameter.
            clean_points(&lane.target, states.len(), lane.points.clone(), &|_, _| None)?
        };
        self.edit(|p| {
            let lane = p.lane_in(id)?;
            lane.states = states;
            lane.points = points;
            Ok(())
        })
    }

    /// Add a state to a state lane, or replace the one of the same name,
    /// as one edit. Returns its index, from 0.
    pub(crate) fn lane_add_state(&mut self, id: Id, state: LaneState) -> Result<usize> {
        let mut states: Vec<LaneState> =
            self.lane_states(id)?.iter().map(|s| (**s).clone()).collect();
        let state = check_lane_state(state)?;
        let index = match states.iter().position(|s| s.name == state.name) {
            Some(i) => {
                states[i] = state;
                i
            }
            None => {
                states.push(state);
                states.len() - 1
            }
        };
        self.lane_set_states(id, states)?;
        Ok(index)
    }
}

/// The lowest and highest value a target takes: for a state lane with
/// `states` states, the first and the last. `param_range` gives a
/// plugin parameter's.
fn target_range(target: &Target, states: usize, param_range: ParamRange) -> (f64, f64) {
    match target {
        Target::Volume => (-120.0, 24.0),
        Target::Pan => (-1.0, 1.0),
        Target::Param { device, param } => param_range(*device, param).unwrap_or((f64::MIN, f64::MAX)),
        Target::State { .. } => (0.0, states.saturating_sub(1) as f64),
    }
}

/// Points made valid for a target: finite, at beat 0 or later, within the
/// target's range, and sorted by beat (points sharing a beat keep their
/// order). A state lane's points name a state of its `states` by number.
pub(crate) fn clean_points(
    target: &Target,
    states: usize,
    points: Vec<(f64, f64)>,
    param_range: ParamRange,
) -> Result<Vec<(f64, f64)>> {
    let (min, max) = target_range(target, states, param_range);
    let whole = matches!(target, Target::State { .. });
    if whole && states == 0 && !points.is_empty() {
        bail!("the state lane has no states yet: add one first");
    }
    let mut points = points
        .into_iter()
        .map(|(beat, value)| {
            if !beat.is_finite() || !value.is_finite() {
                bail!("automation points need a finite beat and value");
            }
            let value = if whole { value.round() } else { value };
            Ok((beat.max(0.0), value.clamp(min, max)))
        })
        .collect::<Result<Vec<_>>>()?;
    points.sort_by(|a, b| a.0.total_cmp(&b.0));
    Ok(points)
}

/// A state for a state lane, checked: a name, a state that is base64,
/// a program within MIDI's range.
pub(crate) fn check_lane_state(mut state: LaneState) -> Result<LaneState> {
    state.name = state.name.trim().to_string();
    if state.name.is_empty() {
        bail!("a lane's state needs a `name`");
    }
    if let Some(text) = &state.state {
        BASE64
            .decode(text)
            .context("a lane's `state` is the plugin's state in base64")?;
    }
    if state.program.is_some_and(|p| p > 127) {
        bail!("a program is from 0 to 127");
    }
    if state.bank.is_some_and(|b| b > 16383) {
        bail!("a bank is from 0 to 16383");
    }
    if state.bank.is_some() && state.program.is_none() {
        bail!("a bank goes with a `program`");
    }
    if let Some(call) = &state.call
        && call.method.is_empty()
    {
        bail!("a lane state's `call` needs a `method`");
    }
    if state.state.is_none()
        && state.call.is_none()
        && state.params.is_empty()
        && state.program.is_none()
    {
        bail!("a lane's state needs a `state`, `call`, `params` or `program`");
    }
    Ok(state)
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::PartOpts;

    #[test]
    fn a_lane_keeps_its_points_within_the_range_of_its_parameter() {
        let mut doc = Document::default();
        let part = doc.part_add(PartOpts::default()).unwrap();
        let lane = Lane {
            id: doc.new_id(),
            target: Target::Param { device: 9, param: "cutoff".into() },
            enabled: true,
            points: Vec::new(),
            shapes: Vec::new(),
            states: Vec::new(),
        };
        let id = lane.id;
        doc.project.part_mut(part).unwrap().lanes.push(Arc::new(lane));
        let cutoff = |device: Id, param: &str| (device == 9 && param == "cutoff").then_some((0.0, 1.0));
        doc.lane_set_points(id, vec![(1.0, -5.0), (0.0, 5.0)], false, &cutoff).unwrap();
        assert_eq!(doc.lane_points(id).unwrap(), [(0.0, 1.0), (1.0, 0.0)], "sorted by beat, held to 0 to 1");
    }
}
