//! Sources of sound and other media: what a file is, wherever it is.

pub mod hash;
pub mod index;
pub mod sources;
pub mod table;
mod worker;

pub use sources::{Changed, Sources};
pub use table::{MediaRecord, MediaTable, Probe, SourceHash, StreamInfo};
