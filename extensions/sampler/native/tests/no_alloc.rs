//! Nothing the audio thread does allocates or frees: notes, keyswitches,
//! attributes, controllers, the pedal, release triggers, voices stolen,
//! loops and every interpolation, checked by `assert_no_alloc`, which counts
//! each allocation and each free of the thread inside its closure.

use assert_no_alloc::{AllocDisabler, assert_no_alloc, reset_violation_count, violation_count};
use paw_sampler::audio::Store;
use paw_sampler::engine::{Engine, Program};
use paw_sampler::{fixtures, formats, params};
use std::sync::Arc;

#[global_allocator]
static ALLOCATOR: AllocDisabler = AllocDisabler;

#[test]
fn playing_allocates_nothing() {
    let dir = std::env::temp_dir().join(format!("paw-sampler-alloc-{}", std::process::id()));
    fixtures::write(&dir).unwrap();
    let names = ["ks.sfz", "rr.sfz", "release.sfz", "loop.sfz", "choke.sfz", "envelope.sfz", "ks.dspreset"];
    let mut programs = Vec::new();
    for name in names {
        let instrument = formats::read(&dir.join(name)).unwrap();
        programs.push(Arc::new(Program::new(instrument, &mut Store::default())));
    }
    let (mut left, mut right) = (vec![0.0f32; 256], vec![0.0f32; 256]);
    reset_violation_count();
    for quality in [0.0, 1.0, 2.0] {
        for program in &programs {
            let mut e = Engine::new(48000.0);
            let mut values: Vec<f64> = params::PARAMS.iter().map(|p| p.default).collect();
            values[1] = 6.0;
            values[9] = quality;
            e.settings = params::settings(&values);
            e.swap(Some(program.clone()));
            e.render(&mut left, &mut right);
            assert_no_alloc(|| {
                e.control(64, 1.0);
                e.note_on(25, 0.8, 0, None);
                for key in 60..72 {
                    e.note_on(key, 0.8, 0, if key % 2 == 0 { Some((0x11, 0)) } else { None });
                    e.render(&mut left, &mut right);
                }
                e.control(1, 0.5);
                e.pitch_bend(0.5);
                for key in 60..72 {
                    e.note_off(key, 0);
                }
                e.control(64, 0.0);
                for _ in 0..40 {
                    e.render(&mut left, &mut right);
                }
                e.control(123, 0.0);
                e.render(&mut left, &mut right);
            });
        }
    }
    std::fs::remove_dir_all(&dir).unwrap();
    assert_eq!(violation_count(), 0, "allocations or frees while playing");
}
