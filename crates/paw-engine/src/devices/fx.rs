//! Built-in effects.

use crate::db_to_gain;
use crate::device::{Device, Io, ParamInfo, ProcessCtx};

pub(super) fn gain_params() -> Vec<ParamInfo> {
    vec![ParamInfo::new("gain", -60.0, 24.0, 0.0, "dB")]
}

pub(super) struct Gain {
    target: f32,
    current: f32,
    /// Set once a block has been processed; before that, changes do not ramp.
    started: bool,
}

impl Gain {
    pub(super) fn new() -> Self {
        Self {
            target: 1.0,
            current: 1.0,
            started: false,
        }
    }
}

impl Device for Gain {
    /// Silence in is silence out, once a new gain has been ramped to.
    fn resting(&self) -> bool {
        self.current == self.target
    }

    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        let n = io.left.len().max(1);
        let step = (self.target - self.current) / n as f32;
        for (l, r) in io.left.iter_mut().zip(io.right.iter_mut()) {
            self.current += step;
            *l *= self.current;
            *r *= self.current;
        }
        self.current = self.target;
        self.started = true;
    }

    fn set_param(&mut self, index: u32, value: f32) {
        if index == 0 {
            self.target = db_to_gain(value as f64);
            if !self.started {
                self.current = self.target;
            }
        }
    }
}
