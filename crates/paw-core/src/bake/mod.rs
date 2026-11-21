//! Bakes: what paw computes from sources and keeps in one cache for all
//! projects, found again by a key of what was asked. Never saved, never
//! wrong: a different job is a different key.
//!
//! `key` names a bake, `store` keeps it, `scheduler` decides what is made
//! when, and `native` and `helper` are the two lanes it is made in.

pub mod helper;
pub mod key;
pub mod native;
pub mod scheduler;
pub mod store;

pub use key::{BakeJob, Digest, EntryKey, Hasher, Input, Output, Stream};
pub use scheduler::{Bake, Lane, Made, Priority, Scheduler};
pub use store::{Entry, EntryWriter, Store, Tidied, Write};
