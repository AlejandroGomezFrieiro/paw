//! The tests of the chain language through its public API. One binary,
//! one module for each area.

mod assist;
mod bad;
mod language;

use chain_syntax::{Context, Schema};

/// The schema of the example host in `tests/fixtures`.
pub fn schema() -> Schema {
    Schema::from_json(include_str!("../fixtures/schema.json")).expect("the example schema loads")
}

/// The context of a part of the example host in `tests/fixtures`: its
/// lanes, and the lanes and nodes of other parts.
pub fn context() -> Context {
    Context::from_json(include_str!("../fixtures/context.json")).expect("the example context loads")
}
