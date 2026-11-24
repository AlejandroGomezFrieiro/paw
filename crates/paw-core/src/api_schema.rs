//! The JSON Schema of the data that crosses `paw.api`, from the Rust types
//! that read and write it (schemars). `paw.api.api_schema` gives it, and
//! tools/apidoc.lua makes the generated records of runtime/lua/paw/types.tl
//! and the schemas of crates/paw-mcp/src/api_schema.json from it, so that
//! the Teal records, the MCP tools and the kernel cannot differ.
//!
//! A field or a type with the keyword `x-teal` has that Teal type: a name
//! that types.tl defines by hand, such as `Meta`.

use schemars::SchemaGenerator;
use schemars::generate::SchemaSettings;
use serde_json::{Map, Value};

use crate::model::{Control, Note};
use crate::session::{
    ClipPatch, ClipView, DevicePatch, DeviceView, LanePatch, LaneView, PartPatch, PartView, ProjectPatch, ProjectView,
    TransportPatch, TransportView,
};

/// The definitions of each type of `paw.api` that has a schema, by the name
/// of its Teal record, with each type that they hold.
pub(crate) fn definitions() -> Map<String, Value> {
    let mut generator = SchemaGenerator::new(SchemaSettings::draft2020_12());
    // What a getter gives and what its setter takes, for each kind of data.
    generator.subschema_for::<ClipView<'static>>();
    generator.subschema_for::<ClipPatch>();
    generator.subschema_for::<PartView<'static>>();
    generator.subschema_for::<PartPatch>();
    generator.subschema_for::<ProjectView<'static>>();
    generator.subschema_for::<ProjectPatch>();
    generator.subschema_for::<TransportView>();
    generator.subschema_for::<TransportPatch>();
    generator.subschema_for::<LaneView<'static>>();
    generator.subschema_for::<LanePatch>();
    generator.subschema_for::<DeviceView<'static>>();
    generator.subschema_for::<DevicePatch>();
    // The data of a MIDI clip.
    generator.subschema_for::<Note>();
    generator.subschema_for::<Control>();
    // The words of a parameter of a Lua device (`dsp.lua`) and of a kind
    // of the chain language.
    generator.subschema_for::<chain_syntax::ParamSchema>();
    generator.take_definitions(true)
}
