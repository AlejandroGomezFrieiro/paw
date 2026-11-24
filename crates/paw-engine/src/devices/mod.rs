//! Devices that ship with the engine.

mod drums;
pub mod dsp;
pub mod dynamics;
pub mod eq;
mod fx;
pub mod limiter;
pub mod meter;
pub mod modulation;
pub mod panel;
pub mod reverb;
pub mod sampler;
mod synth;
#[cfg(test)]
mod testkit;
pub mod utility;

use std::rc::Rc;

use crate::device::{Category, Device, DeviceInfo, FnFactory, ParamInfo, Registry};

#[expect(clippy::too_many_lines, reason = "a sequence of steps in one place; the split into named steps is open work")]
pub fn register(registry: &mut Registry) {
    add(
        registry,
        "synth",
        "Synth",
        Category::Instrument,
        synth::params(),
        |sr| Box::new(synth::Synth::new(sr)),
    );
    registry.register(Rc::new(FnFactory {
        info: DeviceInfo::builtin("drums", "Drums", Category::Instrument, drums::params()),
        make: |sr| Box::new(drums::Drums::new(sr)),
        latency: 0.0,
        outputs: &drums::OUTPUTS,
    }));
    registry.register(Rc::new(sampler::Factory {
        info: DeviceInfo::builtin(
            "sampler",
            "Sampler kit",
            Category::Instrument,
            sampler::params(),
        ),
    }));
    add(
        registry,
        "gain",
        "Gain",
        Category::Effect,
        fx::gain_params(),
        |_| Box::new(fx::Gain::new()),
    );
    // The mixing effects: each with a face that answers scripts.
    effect(registry, "eq", "EQ", eq::params(), eq::make);
    effect(
        registry,
        "meter",
        "Meter",
        meter::meter_params(),
        meter::meter,
    );
    effect(
        registry,
        "tuner",
        "Tuner",
        meter::tuner_params(),
        meter::tuner,
    );
    effect(
        registry,
        "delay",
        "Delay",
        modulation::delay_params(),
        modulation::delay,
    );
    effect(
        registry,
        "chorus",
        "Chorus",
        modulation::chorus_params(),
        modulation::chorus,
    );
    effect(
        registry,
        "flanger",
        "Flanger",
        modulation::flanger_params(),
        modulation::flanger,
    );
    effect(
        registry,
        "phaser",
        "Phaser",
        modulation::phaser_params(),
        modulation::phaser,
    );
    effect(
        registry,
        "tremolo",
        "Tremolo",
        modulation::tremolo_params(),
        modulation::tremolo,
    );
    effect(registry, "reverb", "Reverb", reverb::params(), reverb::make);
    effect(
        registry,
        "utility",
        "Utility",
        utility::utility_params(),
        utility::utility,
    );
    effect(
        registry,
        "saturation",
        "Saturation",
        utility::saturation_params(),
        utility::saturation,
    );
    effect(
        registry,
        "limiter",
        "Limiter",
        limiter::params(),
        limiter::make,
    );
    effect(
        registry,
        "compressor",
        "Compressor",
        dynamics::compressor_params(),
        dynamics::compressor,
    );
    effect(
        registry,
        "gate",
        "Gate",
        dynamics::gate_params(),
        dynamics::gate,
    );
}

/// Register a built-in effect made with its [`panel::Face`].
fn effect(
    registry: &mut Registry,
    kind: &str,
    name: &str,
    params: Vec<ParamInfo>,
    make: fn(f32) -> panel::Pair,
) {
    registry.register(Rc::new(panel::Factory {
        info: DeviceInfo::builtin(kind, name, Category::Effect, params),
        make,
    }));
}

fn add(
    registry: &mut Registry,
    kind: &str,
    name: &str,
    category: Category,
    params: Vec<ParamInfo>,
    make: fn(f32) -> Box<dyn Device>,
) {
    add_late(registry, kind, name, category, params, make, 0.0);
}

/// Register a device whose output is `latency` seconds behind its input.
fn add_late(
    registry: &mut Registry,
    kind: &str,
    name: &str,
    category: Category,
    params: Vec<ParamInfo>,
    make: fn(f32) -> Box<dyn Device>,
    latency: f32,
) {
    registry.register(Rc::new(FnFactory {
        info: DeviceInfo::builtin(kind, name, category, params),
        make,
        latency,
        outputs: &[],
    }));
}

/// Default value of each parameter, in order.
fn defaults<const N: usize>(params: &[ParamInfo]) -> [f32; N] {
    std::array::from_fn(|i| params[i].default)
}

/// `x.fract()` for phases: the same result (`x - trunc(x)`), but truncating
/// through an integer conversion, which is one instruction, where
/// `f32::trunc` is a call into the maths library on the baseline x86-64
/// target. Exact for |x| below 2^31.
#[inline(always)]
fn fract(x: f32) -> f32 {
    x - (x as i32) as f32
}
