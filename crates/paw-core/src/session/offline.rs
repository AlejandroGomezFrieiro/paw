//! An offline engine built from the project, for measuring the mix in memory.
//!
//! [`Session::render`] writes a file; this sets up the same private engine and
//! hands it over, so that the caller can run it wherever it likes and read the
//! output and the part meters as it goes.

use std::sync::Arc;

use anyhow::{Result, bail};
use paw_engine::{Engine, EngineHandle, Msg, PartSlot};

use super::{RenderOpts, Session};
use crate::model::{Id, MASTER_ID, Project};
use crate::sync::{LiveDevices, Mapper, SyncCtx, sync};

pub(crate) struct Offline {
    pub engine: Engine,
    pub handle: EngineHandle,
    /// The main-thread side of the engine's devices. Keep it on the main
    /// thread, alive until the engine is dropped, and drop it first.
    pub live: LiveDevices,
    pub sample_rate: u32,
    pub frames: usize,
    /// Every part's slot in the engine, the master included.
    pub slots: Vec<(Id, PartSlot)>,
    /// Beat the render starts at, and the tempo.
    pub start: f64,
    pub tempo: f64,
}

impl Session {
    /// Build an engine that plays the project from `opts.start` to `opts.end`
    /// plus `opts.tail` seconds. With `solo`, only that part sounds, with
    /// what it feeds on the way to the master, as when it is soloed.
    pub(crate) fn offline(&mut self, opts: &RenderOpts, solo: Option<Id>) -> Result<Offline> {
        self.capture_states();
        let mut project = self.doc.project.clone();
        if let Some(id) = solo.filter(|id| *id != MASTER_ID) {
            if project.part(id).is_none() {
                bail!("no part with id {id}");
            }
            for part in project.parts.iter_mut() {
                let wanted = part.id == id;
                if part.solo != wanted {
                    Arc::make_mut(part).solo = wanted;
                }
            }
        }
        let sample_rate = opts.sample_rate.unwrap_or(self.engine.stream.info.sample_rate);
        let end = opts.end.unwrap_or_else(|| project.end());
        if end <= opts.start {
            bail!(
                "nothing to measure between beat {} and beat {end}",
                opts.start
            );
        }
        let seconds = project.tempo_map().seconds_between(opts.start, end) + opts.tail.max(0.0);
        let frames = (seconds * sample_rate as f64).ceil() as usize;

        let (mut engine, mut handle) = Engine::new(sample_rate as f64);
        engine.set_pool(self.pool(None));
        engine.set_sleep(self.sleep());
        engine.set_offline(true);
        let mut live = LiveDevices::new();
        let mut map = Mapper::new();
        let waker = handle.waker();
        {
            let mut send = |msg| {
                let mut msg = msg;
                while let Err(back) = handle.try_send(msg) {
                    msg = back;
                    engine.pump();
                }
            };
            send(Msg::SetTempo(project.tempo));
            send(Msg::SetTimeSig {
                num: project.sig_num,
                den: project.sig_den,
            });
            let mut ctx = SyncCtx {
                registry: &self.registry,
                sources: &self.sources,
                audio: &mut self.audio,
                live: &mut live,
                sample_rate: sample_rate as f32,
                warnings: &mut self.doc.warnings,
                offline: true,
                waker,
                bell: paw_engine::Bell::none(),
                now: self.now,
                kinds: &self.doc.split_kinds,
            };
            sync(
                &Project::default(),
                &project,
                &mut map,
                &mut ctx,
                &mut send,
                &mut Vec::new(),
            );
        }
        super::settle_plugins(&mut engine, &live);
        handle.send_while(Msg::Seek(opts.start), &mut engine);
        handle.send_while(Msg::Play, &mut engine);
        // Devices that look ahead make the output late by this much. Run it
        // now and throw it away, so that what is measured starts where the
        // song does, as a render to a file does.
        let mut late = map.latency as usize;
        let mut scratch = vec![0.0f32; 2 * paw_engine::MAX_BLOCK];
        while late > 0 {
            let n = late.min(paw_engine::MAX_BLOCK);
            let (left, right) = scratch.split_at_mut(paw_engine::MAX_BLOCK);
            engine.process(&mut left[..n], &mut right[..n]);
            late -= n;
        }
        Ok(Offline {
            engine,
            handle,
            live,
            sample_rate,
            frames,
            slots: map.parts.iter().map(|(id, slot)| (*id, *slot)).collect(),
            start: opts.start,
            tempo: project.tempo,
        })
    }
}
