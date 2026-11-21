//! The process's one tokio runtime, for I/O that waits. The client uses it
//! for every [`Connection`]: connecting, TLS, reading what the kernel sends
//! and writing what is sent to it. The kernel (`paw_core::io_runtime`) uses
//! the same runtime for its sockets and helper processes, so a process that
//! is both kernel and client has one I/O thread, not two.
//!
//! A current-thread runtime on one thread of its own, `paw-io`, made the
//! first time something asks for it. It sleeps while no socket or pipe has
//! anything to say and no time limit runs. Tasks on it do I/O only: work
//! for the processor stays on threads of its own. The blocking calls of
//! [`Connection`] wait on it with [`Handle::block_on`], which the runtime's
//! own thread drives: they must not be called from inside an async task.
//!
//! [`Connection`]: crate::Connection

use std::sync::{Mutex, OnceLock};

use anyhow::{Context, Result};
use tokio::runtime::Handle;

/// The handle to spawn tasks on, to wait on them with, and to enter for
/// turning a standard socket or pipe into a tokio one. The runtime and its
/// thread are made on the first call and live as long as the process.
pub fn handle() -> Result<&'static Handle> {
    static RUNTIME: OnceLock<Handle> = OnceLock::new();
    static MAKING: Mutex<()> = Mutex::new(());
    if let Some(handle) = RUNTIME.get() {
        return Ok(handle);
    }
    let _one_at_a_time = MAKING.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(handle) = RUNTIME.get() {
        return Ok(handle);
    }
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
        .context("starting the I/O runtime")?;
    let handle = runtime.handle().clone();
    std::thread::Builder::new()
        .name("paw-io".into())
        .spawn(move || runtime.block_on(std::future::pending::<()>()))
        .context("starting the I/O thread")?;
    Ok(RUNTIME.get_or_init(|| handle))
}
