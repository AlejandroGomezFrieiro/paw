//! Bakes: what paw computes from sources and keeps in one cache for all
//! projects, found again by a key of what was asked. Never saved, never
//! wrong: a different job is a different key.
//!
//! `key` names a bake, `store` keeps it, `scheduler` decides what is made
//! when, and `native` and `helper` are the two lanes it is made in.
#![expect(clippy::allow_attributes, reason = "debt: pay down")]

// No bake uses the helper lane yet: the proxies of video files and the bakes
// of extensions are to use it. `expect` cannot take its place: an item under
// `expect(dead_code)` counts as used, so the expectation is never met.
#[allow(dead_code, reason = "the helper lane has no bake yet")]
pub(crate) mod helper;
pub(crate) mod key;
pub(crate) mod native;
pub(crate) mod scheduler;
pub(crate) mod store;

pub(crate) use key::{BakeJob, EntryKey, Input, Output, Stream};
pub(crate) use store::{Store, Tidied, Write};
