---
type: C4 Component
title: Project files
status: stable
groma:
  id: project-files
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/session/folder.rs
    - scanner: rust
      file: crates/paw-core/src/session/files_watch.rs
    - scanner: rust
      file: crates/paw-core/src/session/project.rs
    - scanner: rust
      file: crates/paw-core/src/session/panic.rs
    - scanner: rust
      file: crates/paw-core/src/safe.rs
    - scanner: rust
      file: crates/paw-core/src/clipfile.rs
  group: Project model and files
  technology: Rust, serde_json, MIDI 2.0 Clip File
description: Opens and saves a project as a folder of text files, safely, and notices outside changes.
---

A project is a folder: a file per track and per clip, MIDI clips as MIDI 2.0 Clip Files (`.midi2`). Writes are crash-safe, a panic writes a safety copy, and changes made outside paw to the open project's files are detected.
