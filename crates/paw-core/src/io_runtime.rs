//! The kernel's tokio runtime, for I/O that waits: the control socket and
//! the network server (`crate::rpc`), the output of helper processes
//! (`crate::io`) and the jobs of `crate::session::encode`.
//!
//! It is the process's one runtime, `paw_proto::runtime`, on one thread,
//! `paw-io`, which the client's connections share: a process that is both
//! kernel and client (the window, `paw attach`, a Lua connection) has one
//! I/O thread. I/O only: tasks hand what they read to the kernel's channel
//! and wake it, and the kernel never waits on a future.

use anyhow::Result;
use tokio::runtime::Handle;

/// The handle to spawn tasks on, and to enter for turning a standard socket
/// or pipe into a tokio one. Made on the first call, for the whole process.
pub(crate) fn handle() -> Result<&'static Handle> {
    paw_proto::runtime::handle()
}
