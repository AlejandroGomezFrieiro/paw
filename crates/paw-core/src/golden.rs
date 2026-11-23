//! Helpers for the golden files (insta snapshots) of the formats that paw
//! writes to the disk: a folder as one text, and the settings that hide
//! what changes from one run to the next. See .claude/skills/rust-testing,
//! part 5.

use std::path::Path;

use crate::clipfile;

/// Every file under `dir` as one text, in the order of their paths: a line
/// `== <path in dir> (<n> bytes)`, then the file. A `.midi2` clip shows as
/// `paw clip cat` shows it (`clipfile::text`), other text as it is, and
/// other bytes not at all.
pub fn folder_text(dir: &Path) -> String {
    let mut files = Vec::new();
    collect(dir, dir, &mut files);
    files.sort();
    let mut out = String::new();
    for rel in files {
        let bytes = std::fs::read(dir.join(&rel)).expect("a file of the folder");
        out += &format!("== {rel} ({} bytes)\n", bytes.len());
        let body = if rel.ends_with(".midi2") {
            clipfile::text(&clipfile::decode(&bytes).expect("a clip file"))
        } else {
            String::from_utf8(bytes).unwrap_or_default()
        };
        out += &body;
        if !body.is_empty() && !body.ends_with('\n') {
            out.push('\n');
        }
    }
    out
}

/// The paths of the files under `at`, relative to `dir`, with `/` between
/// the parts on every system.
fn collect(dir: &Path, at: &Path, out: &mut Vec<String>) {
    for entry in std::fs::read_dir(at).expect("a folder").flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect(dir, &path, out);
        } else {
            let rel = path.strip_prefix(dir).expect("under the folder");
            out.push(rel.iter().map(|part| part.to_string_lossy()).collect::<Vec<_>>().join("/"));
        }
    }
}

/// The settings for a snapshot of files in `dir`: the path of `dir` is
/// `[dir]`, and a BLAKE3 hash shows as its first eight digits (they still
/// tell which blobs are the same).
pub fn settings(dir: &Path) -> insta::Settings {
    let mut settings = insta::Settings::clone_current();
    settings.add_filter(&escape(&dir.to_string_lossy()), "[dir]");
    settings.add_filter(r"\b([0-9a-f]{8})[0-9a-f]{56}\b", "$1…");
    settings
}

/// `text` as a regular expression that matches it and nothing else.
fn escape(text: &str) -> String {
    text.chars()
        .flat_map(|c| {
            let special = r"\.+*?()|[]{}^$#&-~".contains(c);
            special.then_some('\\').into_iter().chain([c])
        })
        .collect()
}
