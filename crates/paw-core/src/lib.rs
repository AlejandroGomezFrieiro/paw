//! The kernel of paw: the project model, the engine it drives, and the Lua
//! state that everything user-facing is written in.

pub mod api;
pub mod attr_map;
pub mod clipfile;
pub mod codec;
pub mod edits;
pub mod audio;
pub mod freeze;
pub mod fs_api;
pub mod grid;
pub mod history;
pub mod io;
pub mod kernel;
pub mod luadev_api;
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
pub mod stretch;
pub mod stretched;
pub mod sync;
pub mod tempo_api;
pub mod tls;
pub mod upload;
pub mod warp;
pub mod watchdog;

pub use kernel::{Frontend, InputEvent, Kernel, KernelMsg, KernelOpts};
