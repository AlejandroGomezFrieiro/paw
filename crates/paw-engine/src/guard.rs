//! Keeping one bad device from taking the rest down with it.
//!
//! Each device's `process` runs inside [`process`], which catches a panic and
//! reports it instead of letting it unwind through the audio thread; the
//! engine then bypasses that device. Its output is checked by [`finite`] and
//! silenced when it holds NaN or infinity, so those never reach a fader, a
//! meter or the master. Neither allocates, locks or makes a system call on
//! the way through: the thread-local flag is a `const` cell, and the check is
//! one pass of arithmetic over the block.

use std::cell::Cell;
use std::panic::{AssertUnwindSafe, catch_unwind};

use crate::device::{Device, Io, ProcessCtx};

thread_local! {
    static IN_DEVICE: Cell<bool> = const { Cell::new(false) };
}

/// Whether this thread is inside a device's `process` right now. A panic
/// hook asks, so that a device's panic (caught and reported by the engine)
/// is not treated as the program's.
pub fn in_device() -> bool {
    IN_DEVICE.with(Cell::get)
}

/// Run one block of a device. False if it panicked: what it left in the
/// buffers is not to be trusted, and it should not be run again.
#[inline]
pub fn process(device: &mut dyn Device, ctx: &ProcessCtx, io: &mut Io) -> bool {
    IN_DEVICE.with(|f| f.set(true));
    let ok = catch_unwind(AssertUnwindSafe(|| device.process(ctx, io))).is_ok();
    IN_DEVICE.with(|f| f.set(false));
    ok
}

/// Whether every sample is a finite number. `x * 0` is 0 for every finite
/// `x` and NaN for NaN and the infinities, so one sum tells, and the loop
/// has no branch to keep it from being vectorised.
#[inline]
pub fn finite(samples: &[f32]) -> bool {
    let mut acc = [0f32; 8];
    let mut chunks = samples.chunks_exact(8);
    for chunk in &mut chunks {
        for i in 0..8 {
            acc[i] += chunk[i] * 0.0;
        }
    }
    let mut sum: f32 = acc.iter().sum();
    for x in chunks.remainder() {
        sum += x * 0.0;
    }
    sum == 0.0
}

bitflags::bitflags! {
    /// What [`fault`](crate::Shared::fault) reports about a device. The engine keeps
    /// the bits in one atomic byte per slot.
    #[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
    pub struct Fault: u8 {
        const PANICKED = 1;
        const NOT_FINITE = 2;
    }
}

/// Devices that fail on purpose, for tests: `test.panic` panics in
/// `process` while its `fail` parameter is on, and `test.nan` puts out NaN
/// and infinity. Each passes its input through otherwise.
/// They are not part of the registry unless asked for.
pub fn register_test_devices(registry: &mut crate::Registry) {
    use crate::device::{Category, DeviceInfo, FnFactory, ParamInfo};
    for (kind, name, make) in [
        (
            "test.panic",
            "Test: panics",
            (|_| Box::new(Failing(0, 0.0)) as Box<dyn Device>) as fn(f32) -> Box<dyn Device>,
        ),
        ("test.nan", "Test: NaN", |_| Box::new(Failing(1, 0.0))),
    ] {
        registry.register(std::rc::Rc::new(FnFactory {
            info: DeviceInfo::builtin(
                kind,
                name,
                Category::Effect,
                vec![ParamInfo::new("fail", 0.0, 1.0, 0.0, "")],
            ),
            make,
            latency: 0.0,
            outputs: &[],
        }));
    }
}

/// How it fails, and whether it is failing.
struct Failing(u8, f32);

impl Device for Failing {
    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        if self.1 < 0.5 {
            return;
        }
        match self.0 {
            0 => panic!("test.panic was told to fail"),
            _ => {
                io.left.fill(f32::NAN);
                io.right[0] = f32::INFINITY;
            }
        }
    }

    fn set_param(&mut self, _index: u32, value: f32) {
        self.1 = value;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finite_finds_nan_and_infinity_anywhere() {
        let mut block = vec![0.5f32; 37];
        assert!(finite(&block));
        for at in [0, 7, 8, 36] {
            for bad in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY] {
                block[at] = bad;
                assert!(!finite(&block), "{bad} at {at}");
                block[at] = 0.5;
            }
        }
        assert!(finite(&[f32::MAX, -f32::MAX, f32::MIN_POSITIVE]));
    }
}
