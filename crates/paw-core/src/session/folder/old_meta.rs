//! The converter of the keys of `meta` that became fields: a part's
//! `meta.kind` becomes `Part::kind`, its `meta.group` becomes
//! `Part::parent`, and a note's `meta.lyric` becomes `Note::lyric`. Each
//! open runs it: the reader of a project folder, the open of a project in
//! one JSON file and the open of a safety copy. So a project that an older
//! paw saved keeps its part kinds, groups and lyrics.
//! The next save writes only the fields.
//! It also keeps the read of a lyric in the `paw:` text of an older clip
//! file ([`clip_lyric`]).
//!
//! paw keeps no backward compatibility before its first release. Remove
//! this module at the first release, when no project of the older form is
//! left to open.

use std::sync::Arc;

use serde_json::{Map, Value};

use crate::model::{Clip, ClipContent, Part, Project};

/// The lyric of a note in the `paw:` text of an older clip file, which
/// now writes it as a Flex Data Lyrics message.
pub(crate) fn clip_lyric(extra: &Map<String, Value>) -> Option<String> {
    extra.get("lyric").and_then(Value::as_str).map(str::to_owned)
}

/// Move the old keys of `meta` of each part and note of `project` into
/// their fields. A field that has a value keeps it, and the old key goes.
pub(crate) fn convert(project: &mut Project) {
    for part in project.parts.iter_mut().chain(std::iter::once(&mut project.master)) {
        if needs_part(part) {
            convert_part(Arc::make_mut(part));
        }
    }
}

/// True when `part` holds an old key, in its own `meta` or in a note.
fn needs_part(part: &Part) -> bool {
    part.meta.contains_key("kind")
        || part.meta.contains_key("group")
        || part.clips.iter().chain(part.cues.iter()).any(|clip| needs_clip(clip))
}

fn needs_clip(clip: &Clip) -> bool {
    match &clip.content {
        ClipContent::Midi { notes, .. } => notes.iter().any(|n| n.meta.get("lyric").is_some_and(Value::is_string)),
        _ => false,
    }
}

fn convert_part(part: &mut Part) {
    // A kind that is no name of a kind stays in `meta`, where the user can
    // still read it.
    if let Some(kind) = part.meta.get("kind").and_then(Value::as_str).and_then(|word| word.parse().ok()) {
        part.kind.get_or_insert(kind);
        part.meta.remove("kind");
    }
    if let Some(group) = part.meta.get("group").and_then(Value::as_u64) {
        part.parent.get_or_insert(group);
        part.meta.remove("group");
    }
    for clips in [&mut part.clips, &mut part.cues] {
        if clips.iter().any(|clip| needs_clip(clip)) {
            for clip in clips.iter_mut() {
                if needs_clip(clip) {
                    convert_clip(Arc::make_mut(clip));
                }
            }
        }
    }
}

fn convert_clip(clip: &mut Clip) {
    let ClipContent::Midi { notes, .. } = &mut clip.content else { return };
    for note in notes.iter_mut() {
        if let Some(Value::String(lyric)) = note.meta.get("lyric") {
            note.lyric.get_or_insert_with(|| lyric.clone());
            note.meta.remove("lyric");
        }
    }
}
