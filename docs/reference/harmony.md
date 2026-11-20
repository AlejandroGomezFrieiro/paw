# Harmony

<!-- tags: harmony chords keys -->

`paw.harmony` reads the chords and the key of the song from its notes. The
piano roll shows the chords, snippets and suggestions use them, and a
language server can give its own reading. Without an extension, the module
is there and uses its built-in reading. For how the built-in reading works,
see [About the harmony reading](../explanation/about-the-harmony-reading.md).

## What paw reads

The reading uses the notes of each track, except:

- drum tracks: a track with a drum map (from the drums extension), a
  `drums` device, or a name that contains drum, perc, kit or beat
- muted tracks
- muted clips.

## Chords

| Property | Value |
| --- | --- |
| Roots | the twelve pitch classes |
| Qualities | major, minor, dim, aug, sus4, sus2, 5, 7, maj7, m7, m7b5, dim7, m(maj7), 6, m6, 7sus4, add9, 9, maj9, m9 |
| Step | `paw.opt.harmony_step` beats (0.5). The shortest chord is about two steps. |
| Inversions | The bass note names the inversion: `C/E`, `G7/B`. In an arpeggio, the bass is the lowest note. |
| End | A chord continues over rests until the next chord. The last chord ends with its notes. |

A melody alone, with one note on each beat, gives no chords. The chord
before it continues.

## Keys

The reading finds major and minor keys on all twelve tonics. A key changes
only where the new key is established, usually at its dominant. A key that
you set with `:key D minor` replaces the key that paw reads, in all of
paw. The project keeps the key as `key` in its `project.toml`
(`key = "D minor"`), and undo applies to it. The `:key` command comes with
the musicops extension. In Lua, use `paw.harmony.set_key`.

## Names and numerals

- Chord names use the letters of the key: Bb in F major, A# in B major. In
  C major, and with no key, the names are C#, Eb, F#, Ab and Bb.
- A diminished chord that is not in the key has the name of the leading
  note (a technical name) that it is: G#dim7 before A minor.
- Roman numerals count from the tonic as in the major scale, in each mode:
  `bVII`, `bVI`, `i`, `V7`, `viiø7`, `ii°`.

## In the piano roll

The piano roll shows the chords in a row above the ruler, each chord at its
start, and the key at the left edge. In the graphical window, the row is
the top of the ruler. The arrange view does not show chords.

| Option | Values |
| --- | --- |
| `paw.opt.chords` | `"names"` (default), `"roman"`, `"both"`, or `false` for no row |

## Lua

Positions are in project beats. paw reads the harmony again only when the
project changes, so a call on each key press costs almost nothing.

```lua
paw.harmony.chords(0, 16)   --> { { at = 0, length = 4, root = 9, quality = "min", bass = 9,
                            --      tones = { 9, 0, 4 }, name = "Am", roman = "i" }, ... }
paw.harmony.at(8)  paw.harmony.next(8)  paw.harmony.prev(8)   -- a chord, or nil
paw.harmony.key(8)          --> { tonic = 9, mode = "minor", name = "A minor", root = 9, scale = "minor", steps = {...} }
paw.harmony.keys()          --> every key read, { at, length, tonic, mode, name }
paw.harmony.set_key("D minor")   paw.harmony.project_key()   -- the key set, or nil
paw.on("harmony.changed", fn)    -- the reading changed
```

| Function | Result |
| --- | --- |
| `paw.harmony.chords(from, to)` | The chords in a range. |
| `paw.harmony.at(beat)`, `next(beat)`, `prev(beat)` | The chord at a beat, after it, before it. Nil if there is none. |
| `paw.harmony.key(beat)` | The key at a beat. |
| `paw.harmony.keys()` | Each key that paw reads, with `at`, `length`, `tonic`, `mode`, `name`. |
| `paw.harmony.set_key(name)` | Set the key of the project. |
| `paw.harmony.project_key()` | The key that is set, or nil. |
| `paw.harmony.provider()` | The name of the provider whose reading paw uses. |
| `paw.harmony.invalidate()` | Tell paw that the answer of a provider changed. |
| `paw.harmony.read` | The built-in reading, as pure functions on lists of notes. |

The event `harmony.changed` comes when the reading changes.

### Providers

The reading comes from the provider with the highest priority that gives
an answer. The built-in reading has priority 0. A language server or a
script can give a reading:

```lua
paw.harmony.provide("my-analysis", function(from, to)
  return { { at = 0, length = 4, root = 2, quality = "m7" }, ... },   -- chords
         { { at = 0, length = 64, tonic = 0, mode = "major" } }     -- keys
end, 100)
paw.harmony.provide("my-analysis", nil)   -- removed
```

- A provider that returns nil gives the reading to the next provider.
- The answer of a provider applies to the range that it covers. The
  providers below it give the rest of the song. For example, MIDI LSP gives
  the chords of the clip that it gets, with their function (`T`, `S`, `D`),
  and the built-in reading gives the other chords.
- paw adds the names and numerals that a provider does not give.
- paw accepts other names of qualities: `major`, `min7`, `dom7`,
  `half-dim`.

### Theory

| Function | Result |
| --- | --- |
| `paw.harmony.parse_key("F# dorian")` | A key from its name. |
| `paw.harmony.key_name(key)` | The name of a key. |
| `paw.harmony.pc_name(pc, key)` | The name of a pitch class, spelled for the key. |
| `paw.harmony.in_key(key, pitch)` | True if the pitch is in the scale. |
| `paw.harmony.snap(key, pitch, dir)` | The nearest pitch in the scale. |
| `paw.harmony.degree(key, pitch)` | The scale degree of a pitch. |
| `paw.harmony.degree_pitch(key, degree)` | The pitch of a scale degree. |
| `paw.harmony.step(key, pitch, n)` | The pitch `n` scale degrees away. |
| `paw.harmony.scales`, `paw.harmony.scale_names()` | The scales. |
| `paw.harmony.tones(root, quality)` | The pitch classes of a chord. |
| `paw.harmony.parse_chord("F#m7b5/C")` | A chord from its name. |
| `paw.harmony.chord_name(chord, key)` | The name of a chord. |
| `paw.harmony.chord_roman(chord, key)` | The Roman numeral of a chord. |

### Voicings

`paw.harmony.voice.voice(tones, opts)` gives the pitches for a chord.
`tones` are pitch classes, with the root first.

| Field of `opts` | Effect |
| --- | --- |
| `low`, `high` | The range of the pitches. |
| `style` | `"close"`, `"drop2"`, `"open"`, `"spread"`, or `"smooth"`: the style that moves least. |
| `prev`, `next` | The pitches of the chords before and after. The voicing moves least from `prev` and into `next`. |
| `bass` | Put the bass note lowest. |
| `count` | The number of voices. For more voices, the root doubles. For fewer, the fifth goes. |

### Ranges

`paw.harmony.range(track)` is the range of a part for the track:

1. `track.meta.range = { low, high }`, if it is set.
2. Else a range from words in the names of the track and its devices: bass
   (E1 to G3), guitar, strings, voices by part, woodwinds and brass. These
   are the ranges of MIDI LSP, made smaller to where the instrument sounds
   well.
3. Else C3 to C6.
