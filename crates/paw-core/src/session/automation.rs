//! Automation lanes: their points, targets and modes.

use super::*;

impl Session {
    /// The lowest and highest value a target takes: for a state lane with
    /// `states` states, the first and the last.
    pub(super) fn target_range(&self, target: &Target, states: usize) -> (f64, f64) {
        match target {
            Target::Volume => (-120.0, 24.0),
            Target::Pan => (-1.0, 1.0),
            Target::Param { device, param } => self
                .live
                .get(device)
                .and_then(|l| l.params.iter().find(|p| &p.key == param))
                .map_or((f64::MIN, f64::MAX), |p| (p.min as f64, p.max as f64)),
            Target::State { .. } => (0.0, states.saturating_sub(1) as f64),
        }
    }

    /// Points made valid for a target: finite, at beat 0 or later, within the
    /// target's range, and sorted by beat (points sharing a beat keep their
    /// order). A state lane's points name a state of its `states` by number.
    pub(super) fn clean_points(
        &self,
        target: &Target,
        states: usize,
        points: Vec<(f64, f64)>,
    ) -> Result<Vec<(f64, f64)>> {
        let (min, max) = self.target_range(target, states);
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

    pub fn lane_view(&self, id: Id) -> Result<Value> {
        let (track, _) = self
            .project
            .find_lane(id)
            .with_context(|| format!("no lane {id}"))?;
        Ok(self.lane_json(self.project.lane(id).unwrap(), track))
    }

    pub(super) fn lane_json(&self, l: &Lane, track: Id) -> Value {
        let (min, max) = self.target_range(&l.target, l.states.len());
        let mut v = json!({
            "id": l.id, "track": track, "enabled": l.enabled, "point_count": l.points.len(),
            "min": min, "max": max,
        });
        match &l.target {
            Target::Volume => v["target"] = json!("volume"),
            Target::Pan => v["target"] = json!("pan"),
            Target::Param { device, param } => {
                v["target"] = json!("param");
                v["device"] = json!(device);
                v["param"] = json!(param);
            }
            Target::State { device } => {
                v["target"] = json!("state");
                v["device"] = json!(device);
                v["states"] = json!(l.states.iter().map(|s| s.name.as_str()).collect::<Vec<_>>());
            }
        }
        v
    }

    /// The automation lanes of a track, without their points.
    pub fn lane_list(&self, track: Id) -> Result<Value> {
        let t = self
            .project
            .track(track)
            .with_context(|| format!("no track {track}"))?;
        Ok(Value::Array(
            t.lanes.iter().map(|l| self.lane_json(l, track)).collect(),
        ))
    }

    pub fn lane_add(&mut self, track: Id, opts: LaneOpts) -> Result<Id> {
        if self.project.track(track).is_none() {
            bail!("no track {track}");
        }
        let kind = match opts.target {
            Some(kind) => kind,
            None => "".parse()?,
        };
        let target = match kind {
            LaneKind::Volume => Target::Volume,
            LaneKind::Pan => Target::Pan,
            LaneKind::Param => {
                let device = opts.device.context("parameter lanes need a `device`")?;
                let name = opts
                    .param
                    .as_deref()
                    .context("parameter lanes need a `param`")?;
                if self.project.find_device(device).map(|(t, _)| t) != Some(track) {
                    bail!("device {device} is not on track {track}");
                }
                Target::Param {
                    device,
                    param: self.param_info(device, name)?.key,
                }
            }
            LaneKind::State => {
                let device = opts.device.context("state lanes need a `device`")?;
                if self.project.find_device(device).map(|(t, _)| t) != Some(track) {
                    bail!("device {device} is not on track {track}");
                }
                Target::State { device }
            }
        };
        let states = opts
            .states
            .into_iter()
            .map(|s| self.check_lane_state(s).map(Arc::new))
            .collect::<Result<Vec<_>>>()?;
        if !states.is_empty() && !matches!(target, Target::State { .. }) {
            bail!("only a state lane has `states`");
        }
        if self
            .project
            .track(track)
            .unwrap()
            .lanes
            .iter()
            .any(|l| l.target == target)
        {
            bail!("track {track} already has a lane for that");
        }
        if let Target::Param { device, param } = &target
            && !self
                .project
                .device(*device)
                .unwrap()
                .params
                .contains_key(param)
        {
            // Give the parameter a value of its own in the project, so that
            // there is something to return to when the lane is turned off.
            let value = self.device_view(*device)?["params"][param].as_f64();
            let key = param.clone();
            self.edit(|p| {
                let params = &mut p.device_mut(*device).unwrap().params;
                params.insert(key, value.unwrap_or_default());
                Ok(())
            })?;
        }
        let points = self.clean_points(&target, states.len(), opts.points)?;
        let id = self.new_id();
        self.edit(|p| {
            p.track_mut(track).unwrap().lanes.push(Arc::new(Lane {
                id,
                target,
                enabled: opts.enabled.unwrap_or(true),
                points,
                shapes: Vec::new(),
                states,
            }));
            Ok(id)
        })
    }

    pub fn lane_remove(&mut self, id: Id) -> Result<()> {
        self.edit(|p| {
            let (track, index) = p.find_lane(id).with_context(|| format!("no lane {id}"))?;
            p.track_mut(track).unwrap().lanes.remove(index);
            Ok(())
        })
    }

    pub fn lane_set(&mut self, id: Id, key: &str, value: Value) -> Result<()> {
        if holds(&self.lane_view(id), key, &value) {
            return Ok(());
        }
        self.edit(|p| {
            let l = p.lane_mut(id).with_context(|| format!("no lane {id}"))?;
            match key {
                "enabled" => l.enabled = de(key, value)?,
                _ => bail!("lanes have no settable field `{key}`"),
            }
            Ok(())
        })
    }

    pub fn lane_points(&self, id: Id) -> Result<&[(f64, f64)]> {
        Ok(&self
            .project
            .lane(id)
            .with_context(|| format!("no lane {id}"))?
            .points)
    }

    /// Replace a lane's points, or add one, replacing any already at its beat.
    pub fn lane_set_points(&mut self, id: Id, new: Vec<(f64, f64)>, add: bool) -> Result<()> {
        let lane = self
            .project
            .lane(id)
            .with_context(|| format!("no lane {id}"))?
            .clone();
        let states = lane.states.len();
        let mut points = self.clean_points(&lane.target, states, new)?;
        if add {
            let mut all = lane.points.clone();
            all.retain(|p| !points.iter().any(|n| n.0 == p.0));
            all.append(&mut points);
            points = self.clean_points(&lane.target, states, all)?;
        }
        self.edit(|p| {
            let lane = p.lane_mut(id).unwrap();
            // A shape stays with a point that stays where it was.
            lane.shapes.retain(|s| points.iter().any(|q| q.0 == s.beat));
            lane.points = points;
            Ok(())
        })
    }

    /// The shapes of a lane's stretches that are not straight.
    pub fn lane_shapes(&self, id: Id) -> Result<&[Segment]> {
        Ok(&self
            .project
            .lane(id)
            .with_context(|| format!("no lane {id}"))?
            .shapes)
    }

    /// Replace the shapes of a lane's stretches: each by the beat of a point
    /// of the lane; a straight one need not be listed.
    pub fn lane_set_shapes(&mut self, id: Id, shapes: Vec<Segment>) -> Result<()> {
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
            p.lane_mut(id).unwrap().shapes = kept;
            Ok(())
        })
    }

    /// The lane's value at a beat, or nothing when it has no points.
    pub fn lane_value_at(&self, id: Id, beat: f64) -> Result<Option<f64>> {
        let lane = self.project.lane(id).with_context(|| format!("no lane {id}"))?;
        Ok(paw_engine::automation::value_at(&lane.played(), beat))
    }

    /// A state for a state lane, checked: a name, a state that is base64,
    /// a program within MIDI's range.
    pub(super) fn check_lane_state(&self, mut state: LaneState) -> Result<LaneState> {
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

    /// The states of a state lane, whole.
    pub fn lane_states(&self, id: Id) -> Result<Vec<Arc<LaneState>>> {
        let lane = self.project.lane(id).with_context(|| format!("no lane {id}"))?;
        if !matches!(lane.target, Target::State { .. }) {
            bail!("lane {id} is not a state lane");
        }
        Ok(lane.states.clone())
    }

    /// Replace the states of a state lane, as one edit. A point that names
    /// a state no longer there names the last; with no states, the points go.
    pub fn lane_set_states(&mut self, id: Id, states: Vec<LaneState>) -> Result<()> {
        self.lane_states(id)?;
        let states = states
            .into_iter()
            .map(|s| self.check_lane_state(s).map(Arc::new))
            .collect::<Result<Vec<_>>>()?;
        let mut names = std::collections::HashSet::new();
        if let Some(twice) = states.iter().find(|s| !names.insert(s.name.as_str())) {
            bail!("two states are named `{}`", twice.name);
        }
        let lane = self.project.lane(id).unwrap().clone();
        let points = if states.is_empty() {
            Vec::new()
        } else {
            self.clean_points(&lane.target, states.len(), lane.points.clone())?
        };
        self.edit(|p| {
            let lane = p.lane_mut(id).unwrap();
            lane.states = states;
            lane.points = points;
            Ok(())
        })
    }

    /// Add a state to a state lane, or replace the one of the same name,
    /// as one edit. Returns its index, from 0.
    pub fn lane_add_state(&mut self, id: Id, state: LaneState) -> Result<usize> {
        let mut states: Vec<LaneState> =
            self.lane_states(id)?.iter().map(|s| (**s).clone()).collect();
        let state = self.check_lane_state(state)?;
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
