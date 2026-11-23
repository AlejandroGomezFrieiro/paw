//! The native lane: built-in ops, each run on a worker thread of its own
//! at a lower priority than the kernel and the window.
//!
//! The built-in ops are a closed set, so they are one enum and a `match`
//! (no `trait Op`): conversion, edit lists and peaks join the stretch here.

use std::sync::Arc;

use anyhow::{Context, Result};

use super::scheduler::{Bake, Lane, Task};
use crate::stretched::Stretch;

/// A built-in op.
pub(crate) enum Op {
    /// Stretch, warp, shift or edit a file (`stretched.rs`).
    Stretch(Stretch),
}

/// A bake made by paw itself, on a thread.
pub(crate) struct Native {
    op: Op,
}

impl Native {
    pub(crate) fn of(op: Op) -> Arc<dyn Bake> {
        Arc::new(Self { op })
    }
}

impl Bake for Native {
    fn lane(&self) -> Lane {
        Lane::Native
    }

    fn what(&self) -> String {
        match &self.op {
            Op::Stretch(stretch) => stretch.what(),
        }
    }

    fn start(self: Arc<Self>, task: Task) -> Result<()> {
        std::thread::Builder::new()
            .name("bake".into())
            .spawn(move || {
                lower_priority();
                let result = match &self.op {
                    Op::Stretch(stretch) => stretch.run(&task),
                };
                task.end(result);
            })
            .context("starting a bake thread")?;
        Ok(())
    }
}

/// Nice 10 for the calling thread: bakes give way to the kernel and the
/// window. (On Linux the nice value is per thread.)
pub(super) fn lower_priority() {
    // Only a hint: failing it changes nothing else.
    let _ = rustix::process::setpriority_process(None, 10);
}
