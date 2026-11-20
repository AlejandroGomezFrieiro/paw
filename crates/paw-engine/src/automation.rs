//! Automation as the audio thread sees it: per track, the lanes that are on,
//! each a list of points in the target's own units.

use crate::slot::DeviceSlot;

/// The value of a lane at `beat`: linear between points, the first value
/// before the first point and the last after the last. `points` must be sorted
/// by beat; where two share a beat, the later one wins from that beat on.
pub fn value_at(points: &[(f64, f64)], beat: f64) -> Option<f64> {
    let next = points.partition_point(|p| p.0 <= beat);
    match (next.checked_sub(1).map(|i| points[i]), points.get(next)) {
        (None, None) => None,
        (Some(a), None) => Some(a.1),
        (None, Some(b)) => Some(b.1),
        (Some(a), Some(b)) => Some(a.1 + (b.1 - a.1) * (beat - a.0) / (b.0 - a.0)),
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum AutoTarget {
    /// The fader, with points in dB.
    Volume,
    /// -1 (left) to 1 (right).
    Pan,
    /// A parameter, by position in the device's parameter list.
    Param { device: DeviceSlot, index: u32 },
}

pub struct AutoLane {
    pub target: AutoTarget,
    pub points: Box<[(f64, f64)]>,
    /// The parameter value last sent, so that a device only hears about changes.
    pub(crate) last: f64,
}

impl AutoLane {
    pub fn new(target: AutoTarget, points: impl Into<Box<[(f64, f64)]>>) -> Self {
        Self {
            target,
            points: points.into(),
            last: f64::NAN,
        }
    }
}

/// What a point of a state lane does on the audio thread when its time
/// comes. Made on the main thread; the engine only reads it. A state that
/// only the main thread can load (a plugin's whole saved state) has an
/// empty change here, and the session loads it (see the explanation of
/// state lanes).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct StateChange {
    /// Parameters set on the point's frame: (position in the device's
    /// parameter list, value).
    pub params: Box<[(u32, f32)]>,
    /// A program change (and bank) sent to the device on the point's frame.
    pub program: Option<(u8, Option<u16>)>,
    /// A message the device's controller prepared for its audio side (an
    /// LV2 `patch:Set`), handed to it with [`Device::message`]. It is
    /// handed on the last frame of the block before the point, so that a
    /// plugin that finishes the change after the block that brings it (an
    /// LV2 worker) plays it from the point's frame.
    ///
    /// [`Device::message`]: crate::Device::message
    pub message: Option<Box<[u8]>>,
}

impl StateChange {
    pub fn is_empty(&self) -> bool {
        self.params.is_empty() && self.program.is_none() && self.message.is_none()
    }
}

/// A lane of states: at each point a device takes one of a few states, and
/// keeps it up to the next point. Before the first point the first state
/// holds, as a curve's first value does.
pub struct StateLane {
    pub device: DeviceSlot,
    /// `(beat, index in changes)`, sorted by beat.
    pub points: Box<[(f64, u32)]>,
    pub changes: Box<[StateChange]>,
    /// The index last applied, so a device hears only of changes.
    pub(crate) last: Option<u32>,
    /// The state whose message was handed early, on the last frame of the
    /// block before its point (see [`StateChange::message`]): not to be
    /// handed again on the point.
    pub(crate) sent_early: Option<u32>,
}

impl StateLane {
    pub fn new(
        device: DeviceSlot,
        points: impl Into<Box<[(f64, u32)]>>,
        changes: impl Into<Box<[StateChange]>>,
    ) -> Self {
        Self {
            device,
            points: points.into(),
            changes: changes.into(),
            last: None,
            sent_early: None,
        }
    }
}

/// The index of the state in force at `beat`: that of the last point at
/// or before it, the first point's before the first. None with no points.
pub fn state_at(points: &[(f64, u32)], beat: f64) -> Option<u32> {
    let next = points.partition_point(|p| p.0 <= beat);
    match next.checked_sub(1) {
        Some(i) => Some(points[i].1),
        None => points.first().map(|p| p.1),
    }
}

/// The beat of the first point after `beat`, if any.
pub fn next_point(points: &[(f64, u32)], beat: f64) -> Option<f64> {
    let next = points.partition_point(|p| p.0 <= beat);
    points.get(next).map(|p| p.0)
}

/// Every active lane of one track. Built on the main thread and handed to the
/// engine whole, like a [`ClipSet`](crate::ClipSet).
#[derive(Default)]
pub struct Automation {
    pub lanes: Vec<AutoLane>,
    pub states: Vec<StateLane>,
}

#[cfg(test)]
mod tests {
    use super::{next_point, state_at, value_at};

    #[test]
    fn states_hold_to_the_next_point() {
        let points = [(4.0, 1), (8.0, 0), (8.0, 2)];
        assert_eq!(state_at(&[], 1.0), None);
        assert_eq!(
            state_at(&points, 0.0),
            Some(1),
            "the first state before the first point"
        );
        assert_eq!(state_at(&points, 4.0), Some(1));
        assert_eq!(state_at(&points, 7.99), Some(1));
        assert_eq!(
            state_at(&points, 8.0),
            Some(2),
            "the later of two on one beat"
        );
        assert_eq!(next_point(&points, 4.0), Some(8.0));
        assert_eq!(next_point(&points, 3.0), Some(4.0));
        assert_eq!(next_point(&points, 8.0), None);
    }

    #[test]
    fn interpolates_and_holds() {
        let points = [(2.0, -60.0), (6.0, 0.0), (6.0, -12.0)];
        assert_eq!(value_at(&[], 1.0), None);
        assert_eq!(value_at(&points, 0.0), Some(-60.0));
        assert_eq!(value_at(&points, 4.0), Some(-30.0));
        assert_eq!(value_at(&points, 6.0), Some(-12.0));
        assert_eq!(value_at(&points, 100.0), Some(-12.0));
    }
}
