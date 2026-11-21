//! Bakes: what paw computes from sources and keeps in one cache for all
//! projects, found again by a key of what was asked. Never saved, never
//! wrong: a different job is a different key.

pub mod key;
pub mod store;

pub use key::{BakeJob, Digest, EntryKey, Hasher, Input, Output, Stream};
pub use store::{Entry, EntryWriter, Store, Tidied, Write};
