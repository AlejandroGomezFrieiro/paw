//! The client's one tokio runtime, for the I/O of every [`Connection`] in
//! the process: connecting, TLS, reading what the kernel sends and writing
//! what is sent to it.
//!
//! A current-thread runtime on one thread of its own, `paw-client`, made
//! the first time a connection is opened, as `paw_core::io_runtime` is for
//! the kernel. It sleeps while no socket has anything to say and no time
//! limit runs. The blocking calls of [`Connection`] wait on it with
//! [`Handle::block_on`], which the runtime's own thread drives: they must
//! not be called from inside an async task.
//!
//! [`Connection`]: crate::Connection

use std::sync::{Mutex, OnceLock};

use anyhow::{Context, Result};
use tokio::runtime::Handle;

/// The handle to spawn the connections' tasks on and to wait on them with.
/// The runtime and its thread are made on the first call and live as long
/// as the process.
pub(crate) fn handle() -> Result<&'static Handle> {
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
        .context("starting the connection's I/O")?;
    let handle = runtime.handle().clone();
    std::thread::Builder::new()
        .name("paw-client".into())
        .spawn(move || runtime.block_on(std::future::pending::<()>()))
        .context("starting the connection's I/O thread")?;
    Ok(RUNTIME.get_or_init(|| handle))
}
