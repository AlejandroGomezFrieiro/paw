//! The kernel of paw: the project model, the engine it drives, and the Lua
//! state that everything user-facing is written in.

// The interface of the crate: what the binary (paw-tui), the fuzz targets
// and the benchmarks use. In these modules, an item is `pub` only when one
// of them uses it, or when it is part of an item that they use (the type
// of a `pub` field, for example). Each other module is private to the crate.
pub mod api;
pub mod clipfile;
pub mod clock;
pub mod grid;
pub mod media;
pub mod model;
pub mod remote;
pub mod rpc;
pub mod session;
pub mod startuptime;
pub mod stretch;
pub mod sync;
pub mod tls;

pub use kernel::{Frontend, InputEvent, Kernel, KernelMsg, KernelOpts};

mod attr_map;
mod bake;
mod codec;
mod edits;
mod events;
mod ext_api;
mod audio;
mod freeze;
#[cfg(test)]
mod golden;
mod fs_api;
mod history;
mod undofile;
mod io;
mod io_runtime;
mod kernel;
mod luadev_api;
mod measure;
mod monitor;
mod peaks;
#[cfg(test)]
mod props;
mod resample;
mod safe;
mod scene;
mod stretched;
mod tempo_api;
mod toml_api;
mod upload;
mod warp;
mod watchdog;
mod xml;

