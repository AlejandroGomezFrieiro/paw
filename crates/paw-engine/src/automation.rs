//! Automation as the audio thread sees it: per part, the lanes that are on,
//! each a list of points in the target's own units.

use crate::slot::DeviceSlot;

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

/// Every active lane of one part. Built on the main thread and handed to the
/// engine whole, like a [`ClipSet`](crate::ClipSet).
#[derive(Default)]
pub struct Automation {
    pub lanes: Vec<AutoLane>,
    pub states: Vec<StateLane>,
}
