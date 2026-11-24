//! The kinds that `paw.kinds.define` puts, as the kernel reads them.
//!
//! Lua keeps the registries (`runtime/lua/paw/kinds.tl`): each family is
//! a `paw.registry`, with the owner of each entry and the entries that an
//! entry on top shadows. Each change of the entry on top of a kind comes
//! here through `paw.api.kinds_put`, so this mirror holds only the entry
//! on top. The kernel reads what it saves or checks: the properties of a
//! stream kind, the stream that a clip kind gives, and the schema of the
//! data of a kind, which `paw.api.kinds_list` gives to tools such as
//! `paw-mcp`.

use std::collections::BTreeMap;

use anyhow::{Context, Result, bail};
use chain_syntax::{Param, ParamValue, Stream, TimeBase};
use paw_types::stream::{Prop, StreamType};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::model::kinds::{ClipFamily, Family, KindId, Kinds, MetaFamily, Owner, PartFamily, StreamFamily, Version};

/// The schema of the data of a kind: the words of each field, as the
/// parameters of a Lua device have them (`ParamSchema`).
pub(crate) type DataSchema = BTreeMap<String, ParamValue>;

/// A stream kind as `paw.kinds.define("stream", name, spec)` gives it.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct StreamGiven {
    #[serde(default)]
    title: String,
    #[serde(default)]
    time: Option<TimeBase>,
    #[serde(default)]
    records: bool,
    #[serde(default)]
    control: bool,
    #[serde(default)]
    props: DataSchema,
}

impl StreamGiven {
    /// The stream of the chain schema that the kind `name` is.
    fn into_stream(self, name: &str) -> Stream {
        let props = self
            .props
            .into_iter()
            .map(|(key, value)| Param { key, name: String::new(), label: String::new(), description: String::new(), value })
            .collect();
        Stream { stream: name.to_owned(), name: self.title, time: self.time, records: self.records, control: self.control, props }
    }
}

/// A clip kind as the kernel keeps it: the stream that its clips give to
/// their lane, and the schema of its data.
#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct ClipSpec {
    pub gives: KindId<StreamFamily>,
    #[serde(default)]
    title: String,
    #[serde(default)]
    schema: Option<DataSchema>,
}

/// A part kind or a declared key of `meta`, as the kernel keeps it: its
/// title, the version of its data (of a `meta` key), and the schema of its
/// data.
#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct DataSpec {
    #[serde(default)]
    title: String,
    #[serde(default)]
    version: Version,
    #[serde(default)]
    schema: Option<DataSchema>,
}

/// The families that the kernel mirrors, by the name that Lua gives.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum FamilyName {
    Stream,
    Clip,
    Part,
    Meta,
}

impl FamilyName {
    const ALL: [Self; 4] = [Self::Stream, Self::Clip, Self::Part, Self::Meta];

    fn parse(word: &str) -> Result<Self> {
        Ok(match word {
            "stream" => Self::Stream,
            "clip" => Self::Clip,
            "part" => Self::Part,
            "meta" => Self::Meta,
            other => bail!("`{other}` is no family of kinds that the kernel keeps: stream, clip, part or meta"),
        })
    }

    /// The owner of an entry that the core put (Lua gives no owner).
    fn core(self) -> Owner {
        Owner::Paw(match self {
            Self::Stream => "paw.streams",
            Self::Clip => "paw.clips",
            Self::Part => "paw.parts",
            Self::Meta => "paw.meta",
        })
    }
}

/// One kind as `paw.api.kinds_list` gives it.
#[derive(Serialize, schemars::JsonSchema)]
#[schemars(rename = "KindInfo")]
pub(crate) struct KindInfo {
    /// The family: `stream`, `clip`, `part` or `meta`.
    family: &'static str,
    name: String,
    /// The extension that defined the kind, or `paw.<feature>` for the core.
    owner: String,
    title: String,
    /// The stream that the clips of a clip kind give to their lane.
    #[serde(skip_serializing_if = "Option::is_none")]
    gives: Option<String>,
    /// The version of the data of a `meta` key.
    #[serde(skip_serializing_if = "Option::is_none")]
    version: Option<u32>,
    /// The words of each field of the data of the kind (of a stream kind:
    /// of each property). Nil when the kind gave none.
    #[schemars(with = "Option<BTreeMap<String, chain_syntax::ParamSchema>>")]
    schema: Option<Value>,
    /// A tool may write the data of the kind: the kind gave a schema.
    writable: bool,
}

/// The kinds of each family that the kernel mirrors, each with its entry
/// on top and the owner of that entry.
#[derive(Default)]
pub(crate) struct KindBook {
    streams: Kinds<StreamFamily, Stream>,
    clips: Kinds<ClipFamily, ClipSpec>,
    parts: Kinds<PartFamily, DataSpec>,
    metas: Kinds<MetaFamily, DataSpec>,
}

/// Put `entry` at `name` in `kinds`, in place of every entry there, or
/// clear the kind when `entry` is `None`.
fn mirror<F: Family, S>(kinds: &mut Kinds<F, S>, name: &str, entry: Option<(S, Owner)>) -> Result<()> {
    let kind: KindId<F> = name.parse()?;
    while kinds.remove(&kind).is_some() {}
    if let Some((spec, owner)) = entry {
        kinds.put(kind, spec, owner);
    }
    Ok(())
}

/// Read the spec of a kind as Lua gave it.
fn read<T: serde::de::DeserializeOwned>(family: FamilyName, name: &str, spec: Value) -> Result<T> {
    serde_json::from_value(spec).with_context(|| format!("the {family:?} kind `{name}`").to_lowercase())
}

/// One kind of `kinds` as `kinds_list` gives it, with its title, schema
/// and extra fields from `entry`.
fn info_of<F: Family, S>(
    kinds: &Kinds<F, S>,
    entry: impl Fn(&S) -> (String, Option<Value>, Option<String>, Option<u32>),
) -> Vec<KindInfo> {
    kinds.iter().map(|(kind, spec)| {
        let (title, schema, gives, version) = entry(spec);
        KindInfo {
            family: F::NAME,
            name: kind.to_string(),
            owner: kinds.owner(kind).map(ToString::to_string).unwrap_or_default(),
            title,
            gives,
            version,
            writable: schema.is_some(),
            schema,
        }
    })
    .collect()
}

/// The schema of `props` as JSON, or `None` when it has no field.
fn schema_json<'a>(props: impl IntoIterator<Item = (&'a str, &'a ParamValue)>) -> Option<Value> {
    let map: serde_json::Map<String, Value> =
        props.into_iter().filter_map(|(key, value)| serde_json::to_value(value).ok().map(|v| (key.to_owned(), v))).collect();
    (!map.is_empty()).then_some(Value::Object(map))
}

impl KindBook {
    /// The kind `name` of `family` is now `spec` (a table as Lua gave it)
    /// of `owner` (an extension; `None` for the core), or no kind when
    /// `spec` is `None`.
    pub(crate) fn put(&mut self, family: &str, name: &str, spec: Option<Value>, owner: Option<String>) -> Result<()> {
        let family = FamilyName::parse(family)?;
        let owner = owner.map_or_else(|| family.core(), |name| Owner::Extension(name.into()));
        match family {
            FamilyName::Stream => {
                let given = spec.map(|spec| read::<StreamGiven>(family, name, spec)).transpose()?;
                mirror(&mut self.streams, name, given.map(|given| (given.into_stream(name), owner)))
            }
            FamilyName::Clip => {
                let given = spec.map(|spec| read::<ClipSpec>(family, name, spec)).transpose()?;
                if let Some(spec) = &given
                    && self.streams.get(&spec.gives).is_none()
                {
                    bail!("the clip kind `{name}` gives `{}`, which is no stream kind", spec.gives);
                }
                mirror(&mut self.clips, name, given.map(|spec| (spec, owner)))
            }
            FamilyName::Part => {
                let given = spec.map(|spec| read::<DataSpec>(family, name, spec)).transpose()?;
                mirror(&mut self.parts, name, given.map(|spec| (spec, owner)))
            }
            FamilyName::Meta => {
                let given = spec.map(|spec| read::<DataSpec>(family, name, spec)).transpose()?;
                mirror(&mut self.metas, name, given.map(|spec| (spec, owner)))
            }
        }
    }

    /// The clip kind `kind`, when a clip of it is made with data: an
    /// extension defined it. A built-in kind (`paw.clips`) has its own
    /// content and is not made so.
    pub(crate) fn data_clip(&self, kind: &KindId<ClipFamily>) -> Result<&ClipSpec> {
        let spec = self.clips.get(kind).with_context(|| {
            format!("no clip kind `{kind}` is defined: an extension defines it with paw.kinds.define(\"clip\", ...)")
        })?;
        if matches!(self.clips.owner(kind), Some(Owner::Paw(_))) {
            bail!("`{kind}` is a built-in kind of clip, and a clip of it holds no data of an extension");
        }
        Ok(spec)
    }

    /// The kinds of `family` (of every family when `None`), each with its
    /// owner and the schema of its data.
    pub(crate) fn list(&self, family: Option<&str>) -> Result<Vec<KindInfo>> {
        let wanted = family.map(FamilyName::parse).transpose()?;
        let mut out = Vec::new();
        for family in FamilyName::ALL.into_iter().filter(|f| wanted.is_none_or(|w| w == *f)) {
            match family {
                FamilyName::Stream => out.extend(info_of(&self.streams, |stream| {
                    let schema = schema_json(stream.props.iter().map(|p| (p.key.as_str(), &p.value)));
                    (stream.name.clone(), schema, None, None)
                })),
                FamilyName::Clip => out.extend(info_of(&self.clips, |spec| {
                    (spec.title.clone(), data_schema(spec.schema.as_ref()), Some(spec.gives.to_string()), None)
                })),
                FamilyName::Part => out.extend(info_of(&self.parts, |spec| {
                    (spec.title.clone(), data_schema(spec.schema.as_ref()), None, None)
                })),
                FamilyName::Meta => out.extend(info_of(&self.metas, |spec| {
                    (spec.title.clone(), data_schema(spec.schema.as_ref()), None, Some(spec.version.get()))
                })),
            }
        }
        Ok(out)
    }

    /// The stream kinds, as the chain schema lists them.
    pub(crate) fn streams(&self) -> impl Iterator<Item = &Stream> {
        self.streams.iter().map(|(_, stream)| stream)
    }

    /// Check a stream type against its base kind: the kind is defined, and
    /// it takes each property with its value.
    pub(crate) fn check_stream(&self, ty: &StreamType) -> Result<()> {
        let base = &ty.base;
        let stream = self
            .streams
            .get(base)
            .with_context(|| format!("no stream kind `{base}`: an extension defines one with paw.kinds.define(\"stream\", ...)"))?;
        for (name, value) in ty.props.iter() {
            let Some(param) = stream.props.iter().find(|p| p.key == name) else {
                let known: Vec<&str> = stream.props.iter().map(|p| p.key.as_str()).collect();
                bail!("the stream kind `{base}` has no property `{name}` (it has: {})", words(&known));
            };
            if !fits(&param.value, value) {
                bail!("the property `{name}` of `{base}` does not take {value}");
            }
        }
        Ok(())
    }
}

/// The schema of the data of a kind as JSON, or `None` when it has none.
fn data_schema(schema: Option<&DataSchema>) -> Option<Value> {
    schema.and_then(|schema| schema_json(schema.iter().map(|(key, value)| (key.as_str(), value))))
}

/// `a, b` for a message, or "none".
fn words(list: &[&str]) -> String {
    if list.is_empty() { "none".to_owned() } else { list.join(", ") }
}

/// True when `value` is in the range of `min` and `max`.
fn within(value: f64, min: Option<f64>, max: Option<f64>) -> bool {
    min.is_none_or(|m| value >= m) && max.is_none_or(|m| value <= m)
}

/// True when the words of a property take `value`: a flag for a switch, a
/// whole number in the range of a number (a ratio too, when the number
/// may have a fraction), and a word for a choice or a text.
fn fits(want: &ParamValue, value: &Prop) -> bool {
    match (want, value) {
        (ParamValue::Number { min, max, .. }, Prop::Count(n)) => within(f64::from(*n), *min, *max),
        (ParamValue::Number { min, max, integer: false, .. }, Prop::Ratio(n, d)) => {
            *d != 0 && within(f64::from(*n) / f64::from(*d), *min, *max)
        }
        (ParamValue::Choice { choices, .. }, Prop::Word(word)) => choices.contains(word),
        _ => matches!((want, value), (ParamValue::Switch { .. }, Prop::Flag(_)) | (ParamValue::Text { .. }, Prop::Word(_))),
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn book_with_video() -> KindBook {
        let mut book = KindBook::default();
        let spec = json!({ "title": "Video", "time": "seconds",
            "props": { "rate": { "type": "number", "minimum": 1.0 }, "alpha": { "type": "boolean" } } });
        book.put("stream", "video", Some(spec), Some("film".into())).expect("a stream kind");
        book
    }

    #[test]
    fn a_stream_kind_checks_the_properties_of_a_type() {
        let book = book_with_video();
        let ty = |text: &str| serde_json::from_str::<StreamType>(text).unwrap();
        assert!(book.check_stream(&ty(r#"{"base":"video","props":{"rate":[30000,1001],"alpha":true}}"#)).is_ok());
        let wrong = |text: &str| book.check_stream(&ty(text)).unwrap_err().to_string();
        assert_eq!(wrong(r#"{"base":"video","props":{"fps":24}}"#), "the stream kind `video` has no property `fps` (it has: alpha, rate)");
        assert_eq!(wrong(r#"{"base":"video","props":{"alpha":"yes"}}"#), "the property `alpha` of `video` does not take yes");
        assert_eq!(wrong(r#"{"base":"video","props":{"rate":0}}"#), "the property `rate` of `video` does not take 0");
        assert!(wrong(r#"{"base":"midi"}"#).starts_with("no stream kind `midi`"));
    }

    #[test]
    fn a_kind_lists_with_its_owner_and_schema_and_goes_when_cleared() {
        let mut book = book_with_video();
        let listed = serde_json::to_value(book.list(Some("stream")).unwrap()).unwrap();
        assert_eq!(listed[0]["owner"], "film");
        assert_eq!(listed[0]["writable"], true);
        assert_eq!(listed[0]["schema"]["rate"], json!({ "type": "number", "minimum": 1.0 }));
        book.put("stream", "video", None, None).unwrap();
        assert!(book.list(None).unwrap().is_empty());
        assert!(book.put("lane", "x", None, None).is_err(), "an unknown family");
    }

    #[test]
    fn a_clip_kind_gives_a_stream_kind_and_only_an_extensions_kind_takes_data() {
        let mut book = book_with_video();
        book.put("stream", "midi", Some(json!({ "title": "MIDI" })), None).unwrap();
        book.put("clip", "midi", Some(json!({ "gives": "midi" })), None).unwrap();
        book.put("clip", "film", Some(json!({ "gives": "video", "schema": { "file": { "type": "string" } } })), Some("film".into()))
            .unwrap();
        let wrong = book.put("clip", "lyrics", Some(json!({ "gives": "text" })), Some("lyrics".into())).unwrap_err();
        assert_eq!(wrong.to_string(), "the clip kind `lyrics` gives `text`, which is no stream kind");
        let kind = |name: &str| name.parse::<KindId<ClipFamily>>().unwrap();
        assert_eq!(book.data_clip(&kind("film")).unwrap().gives.as_str(), "video");
        assert!(book.data_clip(&kind("midi")).unwrap_err().to_string().starts_with("`midi` is a built-in kind of clip"));
        assert!(book.data_clip(&kind("lyrics")).unwrap_err().to_string().starts_with("no clip kind `lyrics`"));
        let listed = serde_json::to_value(book.list(Some("clip")).unwrap()).unwrap();
        assert_eq!(listed[0]["name"], "film");
        assert_eq!(listed[0]["gives"], "video");
        assert_eq!(listed[1]["owner"], "paw.clips");
        assert_eq!(listed[1]["writable"], false, "a kind with no schema is read only for a tool");
    }
}
