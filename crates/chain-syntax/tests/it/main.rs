//! The tests of the chain language through its public API. One binary,
//! one module for each area.

mod bad;
mod language;

use chain_syntax::Schema;

/// The schema of the example host in `tests/fixtures`.
pub fn schema() -> Schema {
    Schema::from_json(include_str!("../fixtures/schema.json")).expect("the example schema loads")
}
