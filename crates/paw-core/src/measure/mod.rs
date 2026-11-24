//! Measuring the mix: `paw.api.measure*`.
//!
//! The project (or a stretch of it, or one part's share of it) is rendered by
//! a private engine on a worker thread and measured as it is rendered, so the
//! interface keeps running; an audio file is decoded and measured the same
//! way, by the analyzer of the `paw-measure` crate, which `paw-mcp` shares.
//! What comes back is plain data: see [`paw_measure::Analysis`] and the
//! per-part peaks added here.
//!
//!   measure_start(opts) -> id      start measuring
//!   measure_poll(id) -> status     { done, progress, elapsed, result | error }
//!   measure_cancel(id)
//!   measure(opts) -> result        the same, waiting for the answer
//!
//! Options: `start`, `end` (beats), `tail` (seconds, default 1), `sample_rate`,
//! `part` (measure only this part's contribution), `file` (measure an audio
//! file instead of the project).
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]

use std::cell::RefCell;
use std::collections::HashMap;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering::Relaxed};
use std::thread::JoinHandle;
use std::time::Instant;

use anyhow::{Result, anyhow, bail};
use paw_engine::{AudioData, Engine, EngineHandle, MAX_BLOCK};
use mlua::{Lua, Table, Value as LuaValue};
use paw_measure::{Analysis, Analyzer, FLOOR_DB};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::api::{LuaResult, Shared, from_lua, guarded, to_lua};
use crate::model::{Id, MASTER_ID};
use crate::session::RenderOpts;
use crate::sync::LiveDevices;

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct MeasureOpts {
    start: f64,
    end: Option<f64>,
    tail: Option<f64>,
    sample_rate: Option<u32>,
    part: Option<Id>,
    file: Option<PathBuf>,
}

/// Peak of one part's output, after its fader, from the engine's meters.
#[derive(Clone, Debug, Serialize)]
pub(crate) struct PartPeak {
    pub id: Id,
    /// dBFS, and where, in seconds from the start of the render: the end of
    /// the engine block (about 21 ms at 48 kHz) it happened in.
    pub peak: f64,
    pub peak_at: f64,
    /// Where the part first went over full scale, if it did.
    pub over_at: Option<f64>,
}

/// What the worker thread hands back: the engine, to be dropped on the main
/// thread after its controllers, and the measurements.
type Outcome = Result<(Option<(Engine, EngineHandle)>, Analysis, Vec<PartPeak>)>;

struct Job {
    done: Arc<AtomicU64>,
    total: u64,
    cancel: Arc<AtomicBool>,
    thread: Option<JoinHandle<Outcome>>,
    live: Option<LiveDevices>,
    started: Instant,
    /// Set for a project render.
    context: Value,
}

impl Job {
    /// Wait for the thread and turn what it made into plain data.
    fn join(mut self) -> Result<Value> {
        let thread = self.thread.take().expect("joined once");
        let outcome = thread
            .join()
            .map_err(|_| anyhow!("the measuring thread panicked"))?;
        let elapsed = self.started.elapsed().as_secs_f64();
        let (engine, analysis, parts) = match outcome {
            Ok(done) => done,
            Err(err) => {
                drop(self.live.take());
                return Err(err);
            }
        };
        // As in a render: controllers first, then the devices.
        drop(self.live.take());
        drop(engine);
        let mut value = serde_json::to_value(&analysis)?;
        value["parts"] = serde_json::to_value(&parts)?;
        value["elapsed"] = json!(elapsed);
        value["floor"] = json!(FLOOR_DB);
        if let (Value::Object(out), Value::Object(context)) = (&mut value, &self.context) {
            out.extend(context.clone());
        }
        Ok(value)
    }
}

impl Drop for Job {
    fn drop(&mut self) {
        self.cancel.store(true, Relaxed);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
        drop(self.live.take());
    }
}

/// The measurements whose thread still runs: `paw.api.pending()` counts
/// them, so that a wait of the tests waits for them.
#[derive(Clone, Default)]
pub(crate) struct Running(Arc<AtomicUsize>, paw_engine::Bell);

impl Running {
    /// Measurements that ring `bell` as each ends.
    pub(crate) fn with_bell(bell: paw_engine::Bell) -> Self {
        Self(Arc::default(), bell)
    }

    pub(crate) fn count(&self) -> usize {
        self.0.load(Relaxed)
    }

    /// Count one more until the token that it gives is dropped, at the end
    /// of the thread (also when it fails).
    fn enter(&self) -> RunningToken {
        self.0.fetch_add(1, Relaxed);
        RunningToken(self.clone())
    }
}

struct RunningToken(Running);

impl Drop for RunningToken {
    fn drop(&mut self) {
        self.0.0.fetch_sub(1, Relaxed);
        self.0.1.ring();
    }
}

#[expect(clippy::disallowed_methods, reason = "the seconds that a measure took are a measure of work")]
#[expect(clippy::too_many_lines, reason = "a sequence of steps in one place; the split into named steps is open work")]
fn start(shared: &Shared, opts: MeasureOpts) -> Result<Job> {
    let done = Arc::new(AtomicU64::new(0));
    let cancel = Arc::new(AtomicBool::new(false));
    let (progress, stop) = (done.clone(), cancel.clone());
    let started = Instant::now();

    if let Some(path) = opts.file {
        if opts.part.is_some() {
            bail!("`file` and `part` cannot be measured together");
        }
        let data = AudioData::load(&path)?;
        let total = data.frames() as u64;
        let token = shared.measures.enter();
        let thread =
            std::thread::Builder::new()
                .name("measure".into())
                .spawn(move || -> Outcome {
                    let _token = token;
                    let mut analyzer = Analyzer::new(data.sample_rate as f64);
                    let [left, right] = &data.channels;
                    for (l, r) in left.chunks(1 << 16).zip(right.chunks(1 << 16)) {
                        if stop.load(Relaxed) {
                            bail!("cancelled");
                        }
                        analyzer.push(l, r);
                        progress.fetch_add(l.len() as u64, Relaxed);
                    }
                    Ok((None, analyzer.finish(), Vec::new()))
                })?;
        return Ok(Job {
            done,
            total,
            cancel,
            thread: Some(thread),
            live: None,
            started,
            context: json!({ "file": path }),
        });
    }

    let render = RenderOpts {
        start: opts.start,
        end: opts.end,
        tail: opts.tail.unwrap_or(1.0),
        sample_rate: opts.sample_rate,
        bits: 32,
        ..RenderOpts::default()
    };
    let solo = opts.part.filter(|id| *id != MASTER_ID);
    let offline = shared.session.borrow_mut().offline(&render, solo)?;
    let crate::session::offline::Offline {
        mut engine,
        handle,
        live,
        sample_rate,
        frames,
        slots,
        start,
        tempo,
    } = offline;
    let rate = sample_rate as f64;
    let token = shared.measures.enter();
    let thread = std::thread::Builder::new()
        .name("measure".into())
        .spawn(move || -> Outcome {
            let _token = token;
            // The analysis runs beside the render on a thread of its own, a
            // few pieces behind it.
            let (tx, rx) = std::sync::mpsc::sync_channel::<(Vec<f32>, Vec<f32>)>(4);
            let analysis = std::thread::Builder::new()
                .name("measure-analysis".into())
                .spawn(move || {
                    let mut analyzer = Analyzer::new(rate);
                    for (l, r) in rx {
                        analyzer.push(&l, &r);
                    }
                    analyzer.finish()
                })?;
            let mut peaks: Vec<(f32, usize, Option<usize>)> = vec![(0.0, 0, None); slots.len()];
            let mut left = vec![0.0f32; MAX_BLOCK];
            let mut right = vec![0.0f32; MAX_BLOCK];
            const PIECE: usize = 32 * MAX_BLOCK;
            let mut piece = (Vec::with_capacity(PIECE), Vec::with_capacity(PIECE));
            let mut at = 0;
            while at < frames {
                if stop.load(Relaxed) {
                    drop(tx);
                    let _ = analysis.join();
                    bail!("cancelled");
                }
                let n = (frames - at).min(MAX_BLOCK);
                engine.process(&mut left[..n], &mut right[..n]);
                piece.0.extend_from_slice(&left[..n]);
                piece.1.extend_from_slice(&right[..n]);
                if piece.0.len() >= PIECE {
                    let full = std::mem::replace(
                        &mut piece,
                        (Vec::with_capacity(PIECE), Vec::with_capacity(PIECE)),
                    );
                    // The receiver only goes away if it panicked; join reports that.
                    let _ = tx.send(full);
                }
                // One engine block per call, so each meter reading is this
                // block's peak or the falling hold of an earlier, higher one:
                // the largest reading is the part's peak, in its own block.
                // A block is placed by its end, so that an over just after a
                // bar line is not put in the bar before.
                for ((_, slot), peak) in slots.iter().zip(peaks.iter_mut()) {
                    let (l, r) = handle.shared.meter(*slot);
                    let level = l.max(r);
                    if level > peak.0 {
                        peak.0 = level;
                        peak.1 = at + n;
                    }
                    if level > 1.0 && peak.2.is_none() {
                        peak.2 = Some(at + n);
                    }
                }
                at += n;
                progress.store(at as u64, Relaxed);
            }
            let _ = tx.send(piece);
            drop(tx);
            let analysis = analysis
                .join()
                .map_err(|_| anyhow!("the analysis thread panicked"))?;
            let parts = slots
                .iter()
                .zip(peaks)
                .map(|((id, _), (peak, peak_at, over))| PartPeak {
                    id: *id,
                    peak: analysis_db(peak),
                    peak_at: peak_at as f64 / rate,
                    over_at: over.map(|f| f as f64 / rate),
                })
                .collect();
            Ok((Some((engine, handle)), analysis, parts))
        })?;
    Ok(Job {
        done,
        total: frames as u64,
        cancel,
        thread: Some(thread),
        live: Some(live),
        started,
        context: json!({
            "start": start, "tempo": tempo, "end": render.end, "tail": render.tail,
            "part": solo, "edits": shared.session.borrow().project_view()["edits"],
        }),
    })
}

fn analysis_db(level: f32) -> f64 {
    if level > 0.0 {
        (20.0 * (level as f64).log10()).max(FLOOR_DB)
    } else {
        FLOOR_DB
    }
}

/// Add the `measure*` functions to the `paw.api` table.
pub(crate) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    let jobs: Rc<RefCell<HashMap<u64, Job>>> = Rc::default();
    let next = Rc::new(std::cell::Cell::new(0u64));

    let (sh, js) = (shared.clone(), jobs.clone());
    // @param opts? types.MeasureOptions
    // @return integer
    api.set(
        "measure_start",
        lua.create_function(guarded!("measure_start", move |lua, opts: LuaValue| {
            let opts: MeasureOpts = if opts.is_nil() {
                MeasureOpts::default()
            } else {
                from_lua(lua, opts)?
            };
            let job = start(&sh, opts).lua()?;
            let id = next.get() + 1;
            next.set(id);
            js.borrow_mut().insert(id, job);
            Ok(id)
        }))?,
    )?;

    let js = jobs.clone();
    // @return types.MeasureStatus
    api.set(
        "measure_poll",
        lua.create_function(guarded!("measure_poll", move |lua, id: u64| {
            let finished = match js.borrow().get(&id) {
                None => return Err(mlua::Error::runtime(format!("no measurement {id}"))),
                Some(job) => job.thread.as_ref().is_none_or(|t| t.is_finished()),
            };
            if !finished {
                let jobs = js.borrow();
                let job = &jobs[&id];
                let done = job.done.load(Relaxed) as f64;
                let status = json!({
                    "done": false,
                    "progress": if job.total > 0 { done / job.total as f64 } else { 0.0 },
                    "elapsed": job.started.elapsed().as_secs_f64(),
                });
                return to_lua(lua, &status);
            }
            let job = js.borrow_mut().remove(&id).expect("present");
            let status = match job.join() {
                Ok(result) => json!({ "done": true, "progress": 1.0, "result": result }),
                Err(err) => json!({ "done": true, "error": format!("{err:#}") }),
            };
            to_lua(lua, &status)
        }))?,
    )?;

    let js = jobs;
    // @return nil
    api.set(
        "measure_cancel",
        lua.create_function(guarded!("measure_cancel", move |_, id: u64| {
            // Dropping the job stops the thread and waits for it.
            js.borrow_mut().remove(&id);
            Ok(())
        }))?,
    )?;

    let sh = shared.clone();
    // @param opts? types.MeasureOptions
    // @return types.Measurement
    api.set(
        "measure",
        lua.create_function(guarded!("measure", move |lua, opts: LuaValue| {
            let opts: MeasureOpts = if opts.is_nil() {
                MeasureOpts::default()
            } else {
                from_lua(lua, opts)?
            };
            let result = start(&sh, opts).and_then(Job::join).lua()?;
            to_lua(lua, &result)
        }))?,
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::doorbell::{Waiter, Woken};

    #[test]
    fn a_measurement_that_ends_rings_after_it_is_no_longer_counted() {
        let waiter = Waiter::new().unwrap();
        let running = Running::with_bell(waiter.doorbell().bell(Woken::MEASURES));
        let token = running.enter();
        assert_eq!(running.count(), 1);
        std::thread::spawn(move || drop(token)).join().unwrap();
        waiter.wait(None).unwrap();
        assert_eq!(waiter.doorbell().take(), Woken::MEASURES);
        assert_eq!(running.count(), 0);
    }
}
