# About time stretch

<!-- tags: about-stretching -->

To stretch sound is to change its length without a change of pitch, or its
pitch without a change of length. No method is good for all sound. This
page tells which methods paw has, why, and why paw stretches a file one
time and not while it plays. For the commands and fields, see
[Stretched and looped clips](../reference/stretch.md).

## Two methods

paw has two methods, both written for paw in Rust
(`crates/paw-core/src/stretch.rs`).

- **`tonal`** is a phase vocoder with identity phase lock. It starts its
  phases again at each onset. It is good for held and melodic sound, at any
  ratio.
- **`percussive`** overlaps pieces of the file at their own speed (WSOLA).
  It puts each piece where it continues the last piece best, and plays
  each onset one time, complete, at its position. It is good for drums and
  speech, where a phase vocoder smears the attacks.

`auto`, the default, selects `percussive` for a sound with two onsets or
more each second. Both methods keep the two channels as one stereo image.

## Formants

A pitch shift is a stretch, then a change of sample rate. This change
moves all frequencies, also the formants: the peaks of the spectrum that tell which
vowel a voice sings. So a voice shifted far sounds smaller or larger.

When a clip keeps its formants, the vocoder finds the spectral envelope of
each frame (from the cepstrum, liftered at 1.5 ms). It moves the envelope
in the opposite direction before the change of rate, and the change of
rate moves it back. The harmonics move, and the formants stay. This needs the
vocoder, so a clip that keeps its formants uses `tonal` in all modes.

## Why paw stretches a file one time

A stretch while the sound plays costs CPU in each block, on each play, and
its result can depend on where playback starts. paw stretches the file one
time, on a thread of its own, and the engine plays the result as any
file. So a stretched clip costs the same as any audio clip when it plays,
and a render is the same each time.

paw makes the result many times faster than it plays, from the start, and
the clip plays as far as the result is ready. So a long file plays
immediately after a change. Before paw starts the result, the clip plays
a rough preview. The preview is short pieces of the file at its own
pitch, each at the place where the stretch puts it. It is not exact, but
you hear the rhythm, not silence.

paw keeps each result by the bytes of its file and its settings. A large result goes into the bake cache for
later runs and for other projects.

## Warp markers

A uniform stretch cannot correct a part that is not in time. A warp
marker pins a moment of the file to a beat, and each part between two
markers stretches by its own amount. A move of a marker changes only its
two neighbors. paw saves the markers as moments of the file with no
stretch. So they stay on the sound when you trim, slip or stretch the
clip.
