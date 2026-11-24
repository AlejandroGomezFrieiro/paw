//! The JSON Schema of the data that crosses `paw.api`, from the Rust types
//! that read and write it (schemars). `paw.api.api_schema` gives it, and
//! tools/apidoc.lua makes the generated records of runtime/lua/paw/types.tl
//! from it, so that the Teal records and the kernel cannot differ.
//!
//! A field or a type with the keyword `x-teal` has that Teal type: a name
//! that types.tl defines by hand, such as `Meta`.

use schemars::SchemaGenerator;
use schemars::generate::SchemaSettings;
use serde_json::{Map, Value};

use crate::session::{ClipPatch, ClipView};

/// The definitions of each type of `paw.api` that has a schema, by the name
/// of its Teal record, with each type that they hold.
pub(crate) fn definitions() -> Map<String, Value> {
    let mut generator = SchemaGenerator::new(SchemaSettings::draft2020_12());
    generator.subschema_for::<ClipView<'static>>();
    generator.subschema_for::<ClipPatch>();
    generator.take_definitions(true)
}

