//! The kernel of paw: the project model, the engine it drives, and the Lua
//! state that everything user-facing is written in.

#![warn(clippy::undocumented_unsafe_blocks)]

pub mod api;
pub mod attr_map;
pub mod bake;
pub mod clipfile;
pub mod codec;
pub mod edits;
pub mod events;
pub mod ext_api;
pub mod audio;
pub mod freeze;
pub mod fs_api;
pub mod grid;
pub mod history;
pub mod undofile;
pub mod io;
mod io_runtime;
pub mod kernel;
pub mod luadev_api;
pub mod media;
pub mod measure;
pub mod model;
pub mod monitor;
pub mod peaks;
pub mod remote;
pub mod resample;
pub mod rpc;
pub mod safe;
pub mod scene;
pub mod session;
pub mod startuptime;
pub mod stretch;
pub mod stretched;
pub mod sync;
pub mod tempo_api;
pub mod toml_api;
pub mod tls;
pub mod upload;
pub mod warp;
pub mod watchdog;
pub mod xml;

pub use kernel::{Frontend, InputEvent, Kernel, KernelMsg, KernelOpts};
