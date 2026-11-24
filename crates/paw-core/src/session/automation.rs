//! Automation lanes: adding one, and the ranges of plugin parameters that
//! the lanes on [`Document`] take. The rest is in
//! `session/document/automation.rs`.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]

use super::*;

impl Session {
    pub(crate) fn lane_add(&mut self, part: Id, opts: LaneOpts) -> Result<Id> {
        if self.doc.project.part(part).is_none() {
            bail!("no part {part}");
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
                if self.doc.project.find_device(device).map(|(t, _)| t) != Some(part) {
                    bail!("device {device} is not on part {part}");
                }
                Target::Param {
                    device,
                    param: self.param_info(device, name)?.key,
                }
            }
            LaneKind::State => {
                let device = opts.device.context("state lanes need a `device`")?;
                if self.doc.project.find_device(device).map(|(t, _)| t) != Some(part) {
                    bail!("device {device} is not on part {part}");
                }
                Target::State { device }
            }
        };
        let states = opts
            .states
            .into_iter()
            .map(|s| document::check_lane_state(s).map(Arc::new))
            .collect::<Result<Vec<_>>>()?;
        if !states.is_empty() && !matches!(target, Target::State { .. }) {
            bail!("only a state lane has `states`");
        }
        if self
            .doc.project
            .part(part)
            .with_context(|| format!("no part {part}"))?
            .lanes
            .iter()
            .any(|l| l.target == target)
        {
            bail!("part {part} already has a lane for that");
        }
        if let Target::Param { device, param } = &target
            && !self
                .doc.project
                .device(*device)
                .with_context(|| format!("no device {device}"))?
                .params
                .contains_key(param)
        {
            // Give the parameter a value of its own in the project, so that
            // there is something to return to when the lane is turned off.
            let value = self.device_view(*device)?["params"][param].as_f64();
            let key = param.clone();
            self.doc.edit(|p| {
                let params = &mut p.device_in(*device)?.params;
                params.insert(key, value.unwrap_or_default());
                Ok(())
            })?;
        }
        let points = document::clean_points(&target, states.len(), opts.points, &param_range(&self.live))?;
        let id = self.doc.new_id();
        self.doc.edit(|p| {
            p.part_in(part)?.lanes.push(Arc::new(Lane {
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

    pub(crate) fn lane_view(&self, id: Id) -> Result<Value> {
        self.doc.lane_view(id, &param_range(&self.live))
    }

    /// The automation lanes of a part, without their points.
    pub(crate) fn lane_list(&self, part: Id) -> Result<Value> {
        self.doc.lane_list(part, &param_range(&self.live))
    }

    pub(crate) fn lane_set(&mut self, id: Id, key: &str, value: Value) -> Result<()> {
        self.doc.lane_set(id, key, value, &param_range(&self.live))
    }

    /// Replace a lane's points, or add one, replacing any already at its beat.
    pub(crate) fn lane_set_points(&mut self, id: Id, new: Vec<(f64, f64)>, add: bool) -> Result<()> {
        self.doc.lane_set_points(id, new, add, &param_range(&self.live))
    }
}

/// The range of each plugin parameter, as its live plugin gives it.
fn param_range(live: &LiveDevices) -> impl Fn(Id, &str) -> Option<(f64, f64)> + '_ {
    |device, param| {
        let live = live.get(&device)?;
        let info = live.params.iter().find(|p| p.key == param)?;
        Some((info.min as f64, info.max as f64))
    }
}
