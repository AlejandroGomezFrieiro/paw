//! The kernel's one tokio runtime, for I/O that waits: the control socket
//! and the network server (`crate::rpc`), and the output of helper
//! processes (`crate::io`).
//!
//! A current-thread runtime on one thread of its own, `paw-io`, made the
//! first time something asks for it. It sleeps while no socket or pipe has
//! anything to say and no time limit runs. I/O only: tasks hand what they
//! read to the kernel's channel and wake it, and the kernel never waits on
//! a future. Work for the processor stays on threads of its own.

use std::sync::{Mutex, OnceLock};

use anyhow::{Context, Result};
use tokio::runtime::Handle;

/// The handle to spawn tasks on, and to enter for turning a standard socket
/// or pipe into a tokio one. The runtime and its thread are made on the
/// first call and live as long as the process.
pub(crate) fn handle() -> Result<&'static Handle> {
    static RUNTIME: OnceLock<Handle> = OnceLock::new();
    static MAKING: Mutex<()> = Mutex::new(());
    let _one_at_a_time = MAKING.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(handle) = RUNTIME.get() {
        return Ok(handle);
    }
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
        .context("starting the kernel's I/O")?;
    let handle = runtime.handle().clone();
    std::thread::Builder::new()
        .name("paw-io".into())
        .spawn(move || runtime.block_on(std::future::pending::<()>()))
        .context("starting the kernel's I/O thread")?;
    Ok(RUNTIME.get_or_init(|| handle))
}
