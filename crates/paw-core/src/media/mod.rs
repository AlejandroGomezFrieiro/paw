//! Sources of sound and other media: what a file is, wherever it is.

pub mod hash;
pub(crate) mod index;
pub(crate) mod sources;
pub(crate) mod table;
mod worker;

pub use sources::Sources;
pub(crate) use sources::Changed;
pub(crate) use table::{MediaRecord, MediaTable, SourceHash};
