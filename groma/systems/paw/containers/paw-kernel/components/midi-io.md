---
type: C4 Component
title: MIDI input and output
status: stable
groma:
  id: midi-io
  parent: paw-kernel
  code:
    - scanner: rust
      file: crates/paw-engine/src/midi.rs
    - scanner: rust
      file: crates/paw-engine/src/midi_out.rs
    - scanner: rust
      file: crates/paw-engine/src/alsa.rs
    - scanner: rust
      file: crates/paw-engine/src/midi_form.rs
    - scanner: rust
      file: crates/paw-engine/src/ump.rs
  group: Audio engine
description: MIDI from and to hardware and other programs through the ALSA sequencer, and MIDI 2.0 packets.
---

## Relationships

| Source | Target | Description | Technology |
| --- | --- | --- | --- |
| [crates/paw-engine/src/midi.rs](../../../../../../crates/paw-engine/src/midi.rs) | [linux-audio-and-midi](../../../../../externals/linux-audio-and-midi.md) | Reads MIDI | ALSA sequencer |
| [crates/paw-engine/src/midi_out.rs](../../../../../../crates/paw-engine/src/midi_out.rs) | [linux-audio-and-midi](../../../../../externals/linux-audio-and-midi.md) | Sends MIDI | ALSA sequencer |
