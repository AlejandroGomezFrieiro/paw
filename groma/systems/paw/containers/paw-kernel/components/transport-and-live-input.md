---
type: C4 Component
title: Transport and live input
status: stable
groma:
  id: transport-and-live-input
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-core/src/session/transport.rs
    - scanner: rust
      file: crates/paw-core/src/session/engine.rs
    - scanner: rust
      file: crates/paw-core/src/session/watch.rs
    - scanner: rust
      file: crates/paw-core/src/session/midi_in.rs
    - scanner: rust
      file: crates/paw-core/src/session/midi_out.rs
    - scanner: rust
      file: crates/paw-core/src/session/audition.rs
    - scanner: rust
      file: crates/paw-core/src/session/cues.rs
    - scanner: rust
      file: crates/paw-core/src/session/write.rs
    - scanner: rust
      file: crates/paw-core/src/audio.rs
  group: Session operations
  technology: Rust
description: Play, stop, seek, loop, count-in and recording, MIDI ports, auditions and cues.
---

Controls the running engine and the audio device (including losing and regaining it), routes MIDI input to the armed track and MIDI output to ports, plays picker previews without touching the project, launches cues and writes automation from live moves.

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-core/src/session/transport.rs](../../../../../../crates/paw-core/src/session/transport.rs) | [crates/paw-engine/src/engine/handle.rs](../../../../../../crates/paw-engine/src/engine/handle.rs) | Controls playback | Engine messages |
