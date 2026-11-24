# Piano roll UX: the design (bundle PR)

Status: design, for the owner. Nothing was built. No tracked file
changed. Internal text (ASD-STE100). Date: 2026-11-23. Base: main at
deb79a0f. Writer: the roll UX designer (agent).

The owner (verbatim): "Piano-roll UX is something we will have to
refine, as it's the default (but not necessarily only!) editor view for
midi".

This design is bundle PR of `architecture-plan.md` (V2.10, m-15). It
comes before M5 ("the roll and readers of the stack"). It uses the words
of V2.1: part, lane, take, comp, clip, stack, render, producer. It obeys
the key rule (`docs/reference/key-rule.md`) and the owner's answers of
2026-11-23 (`owner-answers-2026-11-23.md`, rounds 3.C, 4.5, 5.4).

Contents:

1. The roll as it is: what works, and the problems, with evidence
2. Prior art: strengths and costs
3. Goals and limits
4. The model: what the roll shows
5. Layout
6. Modes, focus and the key grammar
7. Per-note expressions and producer controls
8. Takes and comps in the roll
9. Ink and ghosts
10. The editor subject: what the roll gives to other editors
11. Before and after screens (100x30)
12. Key counts for common tasks
13. Golden screens
14. Bundles (one Opus agent each)
15. Questions for the owner

---

## 1. The roll as it is

### 1.1 How the evidence was taken

- Screens: the shared binary (deb79a0f) through `tests/tools/run.sh`,
  a scratch home and XDG folders, `--clean --no-plugins --audio null
  --headless`. The scripts are in the scratchpad (`rollux/roll.lua`,
  `rollux/roll2.lua`). Sizes: 100x30 and 120x36.
- The song: track Keys with clip "verse" (4 bars: 12 chord notes and 13
  melody notes from F3 to G5, 27 semitones; a CC 1 ramp; a per-note
  bend on the E5 at 2.1), clip "verse 2" after it, and track Bass with
  clip "low".
- The text of a frame loses the colors. A note body is a colored
  background, so in the text a note shows as its name and then blank
  cells. The rows of `▏ ▏ ▏` are the grid where no note is.
- The code read: `views/pianoroll.tl` (1848 lines),
  `views/pianoroll_strip.tl` (453), `views/pianoroll_mouse.tl` (684),
  `roll_draw.tl`, `roll_clips.tl`, `defaults/keys.lua` (the roll keys,
  lines 640 to 1420), `views/curve.lua` (`gC` `gX`), and the reference
  pages `piano-roll.md`, `grammar.md`, `key-rule.md`.

### 1.2 What works, and stays

- The grammar. The text objects are objects of the music: `in` `ic`
  `ip` `iv` `i=` `ib` `ir` `ie`. Each operator acts on them (`>ic`,
  `div`, `yip`, `vi=+`). No other piano roll has this. It stays as it
  is.
- The pencil (insert mode) with an edge, chords by name (`c`, `C`),
  marks (`mk` `mt`), step input (`I`), snippets (`Ctrl-s`), and
  suggestions as ghosts (`Ctrl-Space`). They stay.
- Several clips in one roll (`gE`, `ga`, `gn`), and notes of other
  tracks behind as `╌` (REAPER's "editable" and "visible"). The model
  stays. The keys change a little (6.6).
- `K` describes the note. It names a bend in words (screen B).
- The time axis of the strip is the time axis of the roll (screen C).

### 1.3 The problems

Each problem has its evidence. "Screen n" names a capture of 11.0.

| # | Problem | Evidence |
| --- | --- | --- |
| P1 | `Enter` opens the roll in a split under the arrange view. At 100x30 the roll gets 10 pitch rows and 3 rows of velocity. The clip spans 27 semitones, so the melody is not on the screen. | Screen 1: rows E4 to A3 only. |
| P2 | No key fits the pitch range of the clip, and no key folds the empty rows (Ableton "Fold"). Alone (`<C-w>o`), the roll gets 21 pitch rows of 30, still fewer than 27. | Screen 2. A search of the roll keys for `fit`, `zM`, `zR`: none in the roll. |
| P3 | The frame takes 6 of 30 rows: title, toolbar, chord row, ruler, status line, key line. "grid 1/16" shows three times (title, toolbar, status line). The chord row holds one letter (`C`). | Screen 2, rows 1 to 3 and 29 to 30. |
| P4 | The time zoom shows 11.5 beats at 100 columns: a phrase of 4 bars does not fit. | Screen 2: the ruler ends in bar 3. |
| P5 | The strip shows one controller. Only the pointer chooses it (a menu on its name). It has five fixed kinds: velocity, the pitch wheel, CC 1, CC 11, CC 64. No key, no other CC, no pressure, no per-note expression. This breaks rule 1 (terminal first). | `pianoroll_strip.tl` `M.kinds`; `M.show` has no key and no command. Screen 7 needed Lua. |
| P6 | `gC` and `gX` open the curve editor as new splits with their own time axis. The splits stay after `<C-w>p`. After `gC` and `gX` the roll has 1 to 3 pitch rows. | Screens 8, 10, 11, 14, 16. The curve ruler reads "2 3 4 ... 23" (beats), the roll ruler "1 2 3" (bars). |
| P7 | One value has three units. The same bend reads "+25%" in the curve, "+12.00 st" in the event list and "bends up 24 semitones" in `K`. Time reads "2.1.00" in the title and "from beat 4, 2 beats long" in `K`. | Screens 10, 13, B. |
| P8 | `]t` `[t` in the roll step the track that the roll edits. The key rule says `]t` `[t` are takes. Takes for every lane kind (TK) need these keys in the roll. | `defaults/keys.lua` near 1118; `key-rule.md` row `]x`. |
| P9 | Per-note data has no place on the screen. A bend shows as `↗` at the end of the note and nothing more. A singer's controls (lyric, phonemes, curves, vibrato) are in a second editor, the vocal editor of utau, which repeats the motions of the roll in its own code and README. | Screen A (`↗`); `extensions/utau/README.md`, "The vocal editor". |
| P10 | The roll knows clips, not lanes or takes. `roll_clips` mixes "tracks shown" and "clips edited". Eleven modules import the private type `Roll`, and 87 calls reach `views:get("pianoroll")`. A score or a drum grid cannot take part in Ex ranges, snippets, diagnostics or the language servers. | `m10-generalization-review.md` 2.2 and 2.7. |
| P11 | The velocity strip gives the number of the note under the cursor only. Equal bars of a chord hide behind the bar of the melody note at the same start. | Screen 2 (`▂70`), screen A (`▁90`). |
| P12 | `]` waits for a longer mapping (`]t`, `]c`, `]d`). After `]]` the status line and the key line keep a lone `]`. | Screen 5. |
| P13 | The toolbar (`Tracks Grid Snap Note Quantize Step List Suggest - +`) is for the pointer. In the terminal it takes a row and gives nothing that a key does not give. | Screen 2, row 2. |

### 1.4 The roll at 100x30 today

Screen 1: `Enter` on the clip "verse" in the arrange view.

```text
 Song 1.1               │▼       3      ▕5       7       9       11      13      15      17      19
 1 █ Keys          MSRI │▏verse ▄▄▅▅▆▆▇▇█▏verse 2        ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
   █in ──────────── 0.0 │▄███▀▀▄▀▀▀▀▀▄▀▀▀▀▀              ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
   █   C                │▀▀▀▀████████████▄▄▄▄            ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
 2 ▌ Bass          MSRI │▏low            ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
   ▌in ──────────── 0.0 │    ▀▀▀▀▄▄▄▄▄▄▄▄▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
   ▌   C                │▄▄▄▄            ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
       o new track      │
                        │
   ▌ Master             │
   ▌   ▀▀▀▀▀▀▀▀▀▀▀▀ 0.0 │
▌  verse  Keys  C4  1.1.00                                             grid 1/16  len 1/16  vel 100
C
        ▼       ▏       ▏       ▏       2       ▏       ▏       ▏       3       ▏       ▏       ▏
▁▁▁▁▁▁▁▁▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
       •▏E4                             ▏E4                             ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
C4     •▏C4                             ▏C4                             ▏C4
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏A3                             ▏A3
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▂70         ▄           ▂       ▁                               ▁               ▂
        █       ▇   █           █       █               ▇       █       █       █       █
 vel ▾  █       █   █           █       █               █       █       █       █       █
 NORMAL·pianoroll  ■ 1.1.00 │ 0:00.0 │ 120 bpm 4/4 │ grid 1/16                ● untitled │ cpu ▁ 0%
 Enter note · i draw notes · x delete · + up · <A-l> longer · ? keys               :help piano-roll
```

Screen 16: after `gC` and `gX` and `<C-w>p` back to the roll. The two
curve windows stay. The roll keeps one row of pitch.

```text
▌  verse  Keys  A2  2.1.00                                             grid 1/16  len 1/16  vel 100
        ▼       ▏       ▏       ▏       2       ▏       ▏       ▏       3       ▏       ▏       ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
▁C3▁▁▁▁▁▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
A2     •▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
▌ Pitch wheel of E5 · verse  2.1.00  +25%                                                  2 points
            2   3   4   5   6   7   8   9   10  11  12  13  14  15  16  17  18  19  20  21  22  23
+100%    │  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
+33%     │🬋🬋┼■🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂
         │  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
-101%    │  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
 curve +25% at 2.1.00 · grid 1/1
▌ CC 1 Modulation · verse  2.1.00  34                                                     16 points
            2   3   4   5   6   7   8   9   10  11  12  13  14  15  16  17  18  19  20  21  22  23
127      │  ▏   ▏   ▏ ■■🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂
         │  ▏   ▏   ▏■🬀 ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │  ▏   ▏   ■   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │  ▏   ▏ ■■▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │  ▏   ▏■🬀 ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
64       │  ▏  ■■   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │  ▏ ■🬀▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │  ◆■  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │ ■🬄   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │■🬀▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
0        │  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
 point 5: 34 at 2.1.00 · hold
 NORMAL·pianoroll  ■ 1.1.00 │ 0:00.0 │ 120 bpm 4/4 │ grid 1/16            g │ ● untitled │ cpu ▁ 0%
normal mode: <C-w>p goes back to the window before, :q closes this one                           g
```

Screen B: `K` on the bent note. Its time is in beats from the clip
start, not in bars.

```text
▌  verse  Keys  E5  2.1.00                                             grid 1/16  len 1/16  vel 100
 ╭─ Note  E5 ───────────────────────────────────────────────────────────╮ggest   -   +
C│   from beat 4, 2 beats long, velocity 90                             │
 │   bends up 24 semitones by its end, from 50% of it (its own pitch    │       ▏       ▏       ▏
 │   bend)                                                              │ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
 │   the chord here: reading                                            │ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
▁│                                                                      │ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
 │ Clip  verse                                                          │ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
 │   1.1.00 to 5.1.00, 16 beats                                         │ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
 │   25 notes                                                           │ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
 │                                                                      │ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
 │ Track  Keys                                                          │ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
 │   volume +0.0 dB, pan +0.00                                          │ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
▁│ K again: all of it                                                   │F5     ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
E╰──────────────────────────────────────────────────────────────────────╯ ▏ ▏ ▏ ▏E5     ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏D5 ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏D5     ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏D5
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
▁C5▁▁▁▁▁▏C5     ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏C5     ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏G4                             ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▂           ▄           ▂       ▁90                             ▁               ▂
        █       ▇   █           █       █               ▇       █       █       █       █
 vel ▾  █       █   █           █       █               █       █       █       █       █
 NORMAL·pianoroll  ■ 1.1.00 │ 0:00.0 │ 120 bpm 4/4 │ grid 1/16                ● untitled │ cpu ▁ 0%
 Enter note · i draw notes · x delete · + up · <A-l> longer · ? keys               :help piano-roll
```

---

## 2. Prior art

| Program | Strength to take | Cost to avoid | Source |
| --- | --- | --- | --- |
| REAPER MIDI editor | CC lanes stacked under the notes, any number, each on the time axis of the notes; "move CC with notes"; one editor over several items, with "editable" and "visible" items; the event list as a second look on the same data; the inline editor in the arrange view | Lane choice is a mouse menu on each lane; many options are global actions; ghost notes of other items have no key flow | [Control Channel Editing](https://www.cockos.com/wiki/index.php/Control_Channel_Editing), [MIDI Editor Controls](https://www.cockos.com/wiki/index.php/MIDI_Editor_Controls), [MIDI Editor](https://www.cockos.com/wiki/index.php/MIDI_Editor) |
| Bitwig note editor | Note expressions are curves that belong to one note (gain, pan, micro-pitch, timbre, pressure). They move with the note. Micro-pitch is drawn on the note. Layered editing of several clips | The expression lane shows only with the mouse toggle; much is drawn by hand only | [Working with Note Events](https://bitwig.com/userguide/latest/working_with_note_events), [Note Expression review](https://www.admiralbumblebee.com/music/2017/06/16/bitwig-feature-review-note-expression) |
| Ableton Live | MPE expression editors under the grid for the selected notes; the other notes are dim. "Fold" shows only rows with notes; "Scale" shows only the rows of the scale | Fold does not work with several clips; pitch envelopes hide in fold | [Editing MPE (Live 11)](https://www.ableton.com/en/live-manual/11/editing-mpe/), [Sound On Sound, Live 11](https://www.soundonsound.com/reviews/ableton-live-11) |
| Logic Pro | The Step Editor: one lane for each event kind, notes and velocities entered together; velocity as a line inside the note | Two editors for one job; the user must choose | [Step Editor (SOS)](https://www.soundonsound.com/node/4913611), [Edit note velocity](https://support.apple.com/en-ie/guide/logicpro/lgcpa8fee137/mac) |
| Cubase Key Editor | Note Expression: controller data on the note, so quantize, move, copy and delete carry it. Double-click opens the curve of the note in place | Works only with instruments that declare VST 3 note expressions; set-up in the Inspector | [Note Expression](https://archive.steinberg.help/cubase_pro_artist/v9/en/cubase_nuendo/topics/note_expression/note_expression_introduction_c.html), [VST 3 controllers](https://steinberg.help/cubase_pro_artist/v9/en/cubase_nuendo/topics/note_expression/note_expression_vst_3_controllers_c.html) |
| OpenUtau | The pitch curve drawn over the notes; vibrato as parameters of the note (depth, period, in, out); phoneme timing on the note; per-note expressions in lanes | Mouse only; many small handles | [OpenUtau](https://github.com/stakira/OpenUtau), [Getting Started](https://github-wiki-see.page/m/openutau/OpenUtau/wiki/Getting-Started) |
| Synthesizer V | Notes panel: the parameters of the selected notes in one panel; pitch modes per note | Two places for one value | [Notes panel](https://sv2.docs.dreamtonics.com/en/notes-panel) |
| Trackers (Renoise, Furnace) | Effect columns beside the note: per-note data is text in the row, fast with the keys; one cursor over notes and effects | Time goes down; a chord takes columns; no curve picture | [Pattern Editor](https://tutorials.renoise.com/wiki/Pattern_Editor), [Furnace pattern](https://github.com/tildearrow/furnace/blob/master/doc/3-pattern/README.md) |
| Vim-like music tools (Vitracker, MusiCLI, pineapple-tracker) | Modal editing of a grid works; navigation and editing modes stay apart | Small grammars; no text objects of music; no lanes | [Vitracker](https://masseyis.github.io/vitracker), [MusiCLI](https://github.com/friedev/musicli), [pineapple-tracker](https://www.github.com/pineapple-tracker/pineapple-tracker) |
| Neovim | Windows on one buffer share the data and keep their own cursor and view; `<C-w>` moves between windows; folds hide lines with `zM` `zR` `za`; the quickfix list and the location list are views of positions | — | `:help windows`, `:help folding` |

What the design takes:

- From REAPER and Logic: lanes under the notes, any number, on one time
  axis. Lane kinds are a list, chosen with keys.
- From Bitwig, Cubase and OpenUtau: per-note data belongs to the note,
  moves with it, and has a lane that follows the note under the cursor.
  The pitch curve shows over the notes.
- From Ableton: fold rows to the rows with notes; dim the notes that
  are not chosen in a note lane.
- From the trackers and Synthesizer V: one text line for the
  parameters of the note under the cursor (the note line).
- From Neovim: the lanes are windows of the roll (`<C-w>j` `<C-w>k`),
  folds are `zM` `zR`, and two editors on one subject are two windows
  on one buffer.

---

## 3. Goals and limits

Goals, each with a check:

| # | Goal | Check |
| --- | --- | --- |
| G1 | `Enter` on a clip shows all of its notes at 100x30 | Golden screen R1: no note of the 4-bar song is off the screen |
| G2 | Every lane kind and every per-note value is reachable with keys | `tests/keys_ux.lua` style test: each lane kind added, focused and changed with keys only |
| G3 | One time axis for notes, lanes and note lanes | No `gC` or `gX` opens a window with another axis unless the user asks (`<C-w>f`) |
| G4 | One unit for each value: time in bars (`2.1.00`), pitch bend in cents, velocity in 1 to 127 | `K`, the note line, the lanes and the event list agree (a test reads all four) |
| G5 | The roll shows lanes, takes, comps and stack results with no second editor | Golden screens R4 to R7 |
| G6 | A score, a drum grid and a vocal editor reuse the lanes, the look, the takes and the note line | The drum grid of `extensions/drums` shows a velocity lane from the shared host (bundle PR7) |
| G7 | Keys stay well under 100 ms on a large project (rule 7) | `bench/`: a clip of 10 000 notes, 8 lanes, a key that moves the cursor |
| G8 | The key rule holds | `tests/keys_constitution.lua` passes; `]t` `[t` are takes |

Limits:

- The roll is one editor of `midi` lanes. It is not the score, the drum
  grid or the vocal editor. It gives them its parts (section 10).
- The roll edits source takes only. A derived take is read-only (owner
  round 1.3).
- No new mode. Lanes are windows of the roll, and looks are a state of
  the view. (m10 review 2.9: "Extensible modes: Neovim has none
  either".)
- The window frontend is paused. The design keeps the scene of each part
  the same in both frontends, but no bundle touches `paw-gui`.

---

## 4. The model: what the roll shows

### 4.1 The subject

The roll edits a **subject**. A subject is one lane, one take of it, and
a range of time.

```text
subject = { lane, take, range, clips (of that take, in the range) }
   lane   : a lane of clip kind midi (V2.2 Lane)
   take   : the active take of the lane, or a take the user chose
   range  : the clip that Enter opened (default) or the whole lane (\L)
```

- `Enter` on a clip opens the subject of its lane and take, with the
  range of the clip.
- `\L` widens the range to the whole lane. Clip edges show in the ruler
  as `[` and `]`. A new note goes into the clip under the cursor. Out
  of every clip, `Enter` and the pencil make a clip of one bar (as the
  arrange view does with `i`).
- Several subjects can be edited at the same time (today's `gE`). One is
  active. The others are "edited" and show as ink of a fainter color.

### 4.2 The layers

From front to back. Each layer has its own glyph, so the text and a
terminal with few colors show it too.

| Layer | What | Glyph (text) | Edits |
| --- | --- | --- | --- |
| Cursor and selection | the cursor cell; the chosen notes | `▐`; `▓` | — |
| Ink | the notes of the active subject, through the reversible prefix of the stack (MOD 7.2) | `█` and the name | yes |
| Ink of other edited subjects | `gE` | `█` in a faint color | yes |
| Suggestion | completion | `╍` and a badge | `Tab` accepts |
| Result | the stack result, where it is not the same as the ink | `░` | no (`K` names the entry) |
| Dropped | a note that the stack drops | `✕` over the ink | — |
| Take | one other take of the same lane (`\t`) | `┄` | no (`\c` comps it) |
| Context | notes of other lanes (`paw.opt.roll_context`) | `╌` | no (`ga` makes it active) |

Rule: at most **two** ghost layers draw at one time, beside the ink.
The look (`\m`, 9.2) decides the first, and `\t` or the context the
second. More layers make the screen unreadable in cells.

### 4.3 The states of the view

```text
look      : notes | notes+played | played            (\m steps)
ghosts    : context | take X | none                  (\t, roll_context)
focus     : grid | lane k                            (<C-w>j <C-w>k)
fold      : open | rows with notes | scale rows      (zR, zM, zK; see 6.4)
range     : clip | lane                              (\L)
mode      : normal | visual | insert (pencil) | step (I)
read-only : no | derived take | look played | lane of a derived kind
```

State table of the guards (events that the roll refuses, with the
message):

| State | Event | Result |
| --- | --- | --- |
| look `played` | an edit key | refused: "the roll shows what plays: \m to edit the notes" |
| take derived | an edit key | refused: "take s1 is derived from Lyrics: \s edits the source, :lane.render makes it a source" |
| take stale (source changed) | open | the header shows `stale`; `K` says what changed; "re-derive as a new take" is `:lane.rederive` (owner round 4.2) |
| producer absent | open a producer lane | the lane shows `absent: <producer>`, kept bytes, read-only; `K` names what to install (round 4.8) |
| focus lane, kind per-note | the cursor of the grid on no note | the lane says "no note at the cursor"; `w` goes to the next note |
| several subjects | `\t` | refused: "\t shows takes of one lane: :roll.only first" |
| visual over a comp boundary | `\c` | comps the range; a note that crosses the edge stays whole from the take where it starts (round 4.4) |

---

## 5. Layout

### 5.1 The rows at 100x30

| Rows | Part | Today | New |
| --- | --- | --- | --- |
| 1 | Header: subject, look, cursor note, grid | title + toolbar + chord row (3) | 1 row |
| 1 | Ruler with chords and clip edges | ruler (1) | 1 row: `1 C · · · 2 Am` |
| 0 or 1 | Comp row | — | only with takes (`comp │A───B━━━A──`) |
| n | Pitch rows | 21 alone, 10 in the split | the rest, at least 12 |
| 1 | Line between notes and lanes | — | `─────┼────  lanes \l` |
| 0 to 3 lanes of 2 to 5 rows | Lanes | one strip, 3 rows | each lane has its own height (`z+` `z-` in the lane) |
| 1 | Note line (option) | — | the parameters of the note at the cursor |
| 2 | Status line and key line | 2 | 2 |

The toolbar shows only in the window frontend and on `\T` in the
terminal (P13).

### 5.2 Time and pitch fit

- **Time**: at open, the roll sets the zoom to the biggest whole number
  of cells for each beat that shows the clip (`zx` does it again). At
  100 columns a clip of 4 bars gets 5 cells for each beat.
- **Pitch**: when the pitch range fits, the roll shows it. When it does
  not fit, the roll folds to the rows with notes (`zM`). `zR` opens all
  rows, and `zK` shows the rows of the scale of the key (Ableton
  "Scale"). The header says the fold (`zM rows`).
- **Key column**: 5 cells: the name of each row in a folded roll, or of
  each C and the cursor row in an open roll. `▸` marks the cursor row.

### 5.3 Where the roll opens

`Enter` on a clip opens the roll **in the window of the arrange view**,
as `:e` opens a buffer in Vim (Q1). `<C-^>` (the alternate view, as `:b #`) goes back.
`<C-w>s` `Enter` keeps a split for those who want it. Today's split
gives the roll 10 rows at 100x30 (P1).

---

## 6. Modes, focus and the key grammar

### 6.1 Principles

1. The key rule first. Motions only move. `+ -` is the main value and
   `[ ]` the second value of **what has the focus**. `< >` is time.
2. A lane is a window of the roll. `<C-w>j` and `<C-w>k` move the focus
   between the note grid and the lanes. The time of the cursor stays.
3. In a lane, the keys are the keys of the curve editor (they already
   obey the rule). No new grammar.
4. The keys of the roll alone are on `<localleader>` (`\`).

### 6.2 The note grid (normal mode)

Unchanged: `h j k l w b e 0 ^ $ gg G W B ( ) ]c [c *`, the objects,
the operators, `+ -` `Ctrl-a` `Ctrl-x` (pitch), `[ ]` (velocity by
10), `Alt-h` `Alt-l` (length), `H L` (move), `i a I`, `x`, `p P`, `E`,
`K`, `gh`, `ga` `gE` `gn` `gN`.

Changed or new:

| Keys | Meaning | Why |
| --- | --- | --- |
| `]t` `[t` | the next and the previous **take** of the lane | key rule `]x`; P8 |
| `Tab` `S-Tab` | the next and the previous lane shown becomes the edited lane (today's `]t`) | it already does this |
| `<C-w>j` `<C-w>k` | focus the lane below, the grid above | Neovim windows |
| `gC` | focus the lane of the controller under the cursor, or add it | P6: no new window |
| `gX` | focus the note lane `pitch` of the note under the cursor | P6 |
| `<C-w>f` | in a lane: the same curve in a window of its own | key rule: own window |
| `zM` `zR` `zK` | fold rows to the notes; open all; the rows of the scale | P2 |
| `zx` | fit the time zoom to the subject | P4 |
| `\m` | the look: notes, notes+played, played | owner round 5.4 |
| `\l` | the lane picker: add, remove, order the lanes | P5 |
| `\t` | show a take as ghost (a picker of takes; `\t` again hides it) | 8 |
| `\c` | in visual mode: comp the range to the take under the cursor | owner round 4.5 |
| `\L` | the range: the clip or the whole lane | 4.1 |
| `\w` | type the lyrics from the note on (`Tab` next note, `Enter` keeps) | 7.5; Q4 |
| `\v` | view the subject with another editor (score, drum grid, event list, vocal editor); `\n` stays the score | 10 |
| `\s` | on a derived take: go to its source subject | 8.3 |
| `\T` | show or hide the toolbar | P13 |

### 6.3 A lane (focus on a lane)

The keys of the curve editor, on the roll's time axis:

| Keys | Lane of a controller (CC, bend, pressure) | Velocity lane | Note lane (per-note) |
| --- | --- | --- | --- |
| `h` `l` | a grid step | the note before or after | a grid step, inside the note |
| `w` `b` `e` | the next point, the one before, the end | the next note | the next point; after the last point of the note, the first point of the next note (as `w` crosses lines in Vim) |
| `j` `k` | the next lane down, up (`<C-w>j` `<C-w>k` also) | same | same |
| `+ -` `Ctrl-a` `Ctrl-x` | the value of the point (count = steps) | the velocity, by 1 | the value of the point (cents for pitch) |
| `[ ]` | the bend of the curve after the point | — | the bend of the curve |
| `< >` | the point later, earlier | — | the point later, earlier (inside the note) |
| `c` | type the value | type the velocity | type the value |
| `o` `i` `x` | add a point; draw; remove | — | add; draw; remove |
| `g~` | an operator: a wave or a ramp over a motion (`g~ib`) | — | `g~` over the note: vibrato shape |
| `~` | the shape of the part after the point | — | the shape |
| `z+` `z-` | the lane is taller, shorter | same | same |
| `gc` | the lane off or on (mute of the lane) | — | — |
| `K` | the point, the controller, the note | the note | the note and its curve |

A visual selection in the grid stays when the focus goes to a lane. In
the lane, `+` then changes the value at the cursor for each chosen note
(the velocity lane) or each point in the range (a controller lane).

### 6.4 Folds

| Keys | Effect |
| --- | --- |
| `zM` | only rows with notes (of the ink and of the ghost layers shown) |
| `zR` | all rows |
| `zK` | the rows of the scale of the key at the cursor, and rows with notes |
| `za` | at the cursor row: the octave folds into one row, or opens |

The fold belongs to the window (as the vertical zoom, `screen.json`).
It is not an undo step.

### 6.5 Insert mode and step input

No change of keys. Two changes of display:

- The pencil shows its note in the note line (`DRAW G4 end 3 steps`
  moves from the title to the note line).
- With a lane in focus, `i` draws in the lane (the curve editor's
  draw), not a note.

### 6.6 What leaves the roll

| Key today | Goes to | Why |
| --- | --- | --- |
| `]t` `[t` (next track edited) | `Tab` `S-Tab` (already the same) | `]t` are takes |
| the toolbar row | `\T`, the window | P13 |
| `gC` `gX` as new windows | `<C-w>f` from the lane | P6 |
| the strip menu on its name (pointer) | `\l`; the pointer menu stays too | P5 |

`paw.opt.keys = "classic"` keeps `]t` as before for one release, as the
key rule did for other keys.

---

## 7. Per-note expressions and producer controls

### 7.1 Three kinds of per-note data

| Kind | Stored on | Examples | Owner of the schema |
| --- | --- | --- | --- |
| MIDI 2.0 per-note controllers | the clip, keyed by note (as today: `bend` with `key`) | pitch bend, pressure, CC 74 timbre, per-note CC | paw (MIDI 2.0) |
| Note attributes | the note | articulation (MIDI 2.0 attribute), lyric (`Note.lyric`, A2) | paw, the articulations extension |
| Producer controls | `Note.ctl[producer]` (V2.2) | phoneme timing, breath, tension, gender, vibrato, pitch curve of a singer | the producer (`paw.producers.define(kind, { controls = ... })`) |

The roll shows the three in the same way. Only the place where the
data is kept differs.

### 7.2 The control schema

A producer declares its per-note controls. The roll reads the schema;
it knows no producer.

```lua
paw.producers.define("diffsinger", {
  tier = "bake",
  controls = {
    { key = "pitch",   kind = "curve",  unit = "cents", range = { -1200, 1200 }, over = "note" },
    { key = "breath",  kind = "curve",  unit = "dB",    range = { -96, 0 },      over = "note" },
    { key = "tension", kind = "curve",  unit = "%",     range = { -100, 100 },   over = "note" },
    { key = "vibrato", kind = "record", fields = { depth = "cents", rate = "Hz", fade_in = "%", fade_out = "%" },
      toggle = "on" },
    { key = "phonemes", kind = "phonemes" },   -- the rows of the phoneme lane
    { key = "gender",  kind = "value",  unit = "", range = { -100, 100 } },
  },
  ...
})
```

- `kind = "curve"`: a note lane.
- `kind = "value"`, `"record"`, `"choice"`: fields of the note line.
- `kind = "phonemes"`: the phoneme row (7.5).
- `over = "note"`: the curve lives inside the note and moves with it.
  `over = "lane"`: a curve of the lane (for a producer that reads a
  lane curve, for example a singer's dynamics). This is a curve lane of
  V2 (CV), not per-note data.

### 7.3 Three places on the screen

1. **On the note.** A glyph at the end: `↗` `↘` bend, `~` vibrato, the
   articulation tag (`pz`), the lyric in place of the name. Free, always
   there.
2. **The note line.** One row above the status line. It shows the note
   at the cursor: `ku · E5 · 2.1.00 · 2 beats · v90 · ph k u (k 40 ms
   early) · vib 25c 5.5Hz · gender 0`. `<C-w>j` to it puts the cursor on
   its fields; `h` `l` (or `w` `b`) go from field to field; `+ -` and `c`
   change the field; `~` switches a toggle (`vib on`). It is the
   inspector of Synthesizer V in one row.
3. **A note lane.** A lane of kind `curve` with `over = "note"`. It
   shows the curve of the note at the cursor of the grid, at full
   height, with the note's edges marked (`┌── note ──┐`). The curves of
   the other chosen notes show dim (Ableton). For the pitch curve, the
   grid also draws the line over the rows (OpenUtau): `╱` `▔` `─` `▁`
   in cells, a line in pixels where the terminal shows pictures.

### 7.4 Moves of notes carry their data

As Cubase and Bitwig: a move, a copy, a quantize, a delete of a note
carries its per-note controllers, its attributes and `Note.ctl`. The
pencil does it today for its bend ("its own controllers move with it").
The rule goes to every operator. A test per operator family (move,
copy, quantize, delete, paste) checks it.

### 7.5 Lyrics and phonemes

- Lanes with the property `lyrics` (A2) show the lyric in the note in
  place of its name.
- `\w` types lyrics from the note at the cursor on: the first key
  replaces the lyric, `Tab` keeps it and goes to the next note,
  `Enter` keeps it and stops, `Esc` drops the last. Several pasted
  words fill the notes in order (as `c` in the vocal editor today).
- The phoneme row shows under the pitch rows when the producer declares
  `phonemes`. In focus (`<C-w>j`), `]p` `[p` go from phoneme to phoneme
  (key rule), `+ -` move its start by 5 ticks (its main value), `c`
  types a phoneme, `x` puts back the producer's phoneme.
- `gR` asks the producer to sing again (a bake job, `:bakes`), as `r`
  does in the vocal editor. `gR` is "start again" in the key rule (a
  plugin in the panel).

### 7.6 Units

| Value | Unit on the screen | Typed as |
| --- | --- | --- |
| Time | bars `2.1.00` everywhere (`K`, note line, event list) | `2.1`, `2.1.50`, or `+1/8` |
| Length | note value and beats: `1/4 · 1 beat` | `=4`, `=8.` (as the pencil) |
| Pitch bend | cents, `+200c`; the bend range in `K` | `+200`, `+2st` |
| Velocity | 1 to 127 | `90` |
| CC | 0 to 127 (and the 32-bit value in `K` for MIDI 2.0) | `64` |
| Producer controls | the unit of the schema | a number |

---

## 8. Takes and comps in the roll

The model is TK (owner round 4): takes for every lane kind; a comp is
source data of ranges that each name a take; a MIDI note that crosses a
comp edge stays whole from the take where it starts.

### 8.1 What the roll shows

- The header names the take: `take A of A B C`. With a comp:
  `comp A│B│A`.
- The **comp row** under the ruler, only when the lane has a comp: a
  run of the take letter for each range, `━` for the range under the
  cursor.
- The ink is what plays in the range of the comp: the notes of the comp
  are the ink. A note of a range shows the ink of its take. `K` names
  the take.
- `\t` picks one take to show as ghost (`┄`). It is the "visible"
  layer of the take. `]t` `[t` change the **active** take: the ink
  becomes that take.
- A takes lane (in `\l`) shows each take as one row with its role:
  `source` or `derived · seed 7`. `Enter` on a row makes it active.

### 8.2 Comp

1. `\t` and choose take B: its notes show as `┄`.
2. Go to a ghost note of B. Select a range: `vib` (the bar), or `v` and
   motions.
3. `\c`: the range of the comp now names take B. One undo step. The
   message: `comp: 2.1 to 3.1 from take B`.

`\c` with no ghost take under the cursor uses the take of `\t`. `\c`
in normal mode comps the bar at the cursor (`\c` = `vib\c`).

### 8.3 Derived takes

A take with the role `Derived` (a bake of a producer) shows as ghosts
only (`░`), with the message of 4.3. `\s` goes to the source subject (the
lane that the recipe reads). (`gd` is the dot of the score, so it is
not free.) `K`
gives the recipe, the seed and whether the take is stale.
`:lane.render` makes it a source take (owner round 3.D).

---

## 9. Ink and ghosts

### 9.1 The stack look

From MOD 7.1, with these refinements:

- The ink is the source through the reversible prefix (MOD 7.2). An
  edit writes back through the reverse.
- The ghosts (`░`) are the result where it is not the same as the ink:
  a note that moved, a note that a kind made, a velocity that changed.
  In the velocity lane, the played velocity is a tick (`▔`) on the ink
  bar.
- `✕` over the ink marks a note that the stack drops.
- `K` on a ghost names the entry and the note that made it (`from`, MOD
  3.2): `made by dbl from C4 at 1.1.00`.
- The rows of a fold include the rows of the result in the looks
  `notes+played` and `played`.

### 9.2 `\m`

`\m` steps: `notes` (default when the stack is empty or only
reversible) → `notes+played` (default when the stack has an entry that
is not reversible) → `played` → `notes`. The header names the look. In
`played`, edits are refused (4.3).

### 9.3 Clip and lane stacks

A lane stack runs after each clip stack (round 5.1). The ghosts show
the result of both. The header shows the clip stack (`verse ≡ q4 dbl`)
and, when it has one, the lane stack (`› Notes ≡ hum`). `<Space>cs` opens
the panel of the stack of the clip, and on the header of a lane the
stack of the lane (round 5.6).

---

## 10. The editor subject: what the roll gives to other editors

B7 adds `paw.editor.define(clip_kind, view, impl)`. This design fixes
what the roll puts in it, and which parts other editors reuse.

### 10.1 The contract of an editor (Teal record)

```teal
local record Subject
  lane: LaneId
  take: TakeId
  range: Span          -- the clip, or the whole lane
  clips: {ClipId}
end

local record Editor
  name: string                         -- "pianoroll", "notation", "drums", "vocal"
  kinds: {string}                      -- clip kinds: {"midi"}
  subject: function(self): Subject
  cursor: function(self): Cursor       -- { beat, pitch?, note?, lane_focus? }
  selection: function(self): {NoteRef}
  set_cursor: function(self, Cursor)
  set_selection: function(self, {NoteRef})
  edit: function(self, fn: function(Edit)): boolean   -- one undo step
  look: function(self): Look           -- "notes" | "notes+played" | "played"
  key_scope: function(self, name: string, order: number, active: function(): boolean)
end
```

The 11 modules of P10 (Ex ranges, the language servers, snippets,
diagnostics, the quickfix list, locators, completion) read
`paw.editor.focused()` and this record, not `views:get("pianoroll")`.

### 10.2 The parts that the roll lends

| Part | Module (new) | Used by |
| --- | --- | --- |
| The lane host: lanes under a time axis, `<C-w>j` `<C-w>k`, `\l`, the curve keys | `paw.editor.lanes` | roll, drum grid (velocity, a CC), score (dynamics as a lane), vocal editor (its curves) |
| The note line | `paw.editor.noteline` | roll, score, vocal editor, drum grid (a hit) |
| The look and the ghost layers | `paw.editor.look` | roll, score (`played` read-only, MOD 7.3), drum grid |
| Takes and comp row | `paw.editor.takes` | every editor of every lane kind (TK) |
| The control schema reader | `paw.editor.controls` | roll, vocal editor |

### 10.3 Two editors side by side

Two windows can show one subject, as two Neovim windows show one
buffer. They share the subject, the selection and the cursor time. Each
keeps its own view (zoom, fold, lanes).

- `\v` in any editor: a picker of the editors of the subject's clip
  kind. Choose one: it replaces the editor in this window.
- `<C-w>v` then `\v`: the two side by side. `<C-w>s` then `\v`: one above
  the other.
- The cursor time follows between the two windows of one subject
  (`paw.opt.editor_follow = true`).
- `\n` (notation today) stays as the short key for the score.

### 10.4 What stays out of the subject

- The pitch rows and the key column (only the roll and the vocal editor
  have pitch rows).
- The pencil (insert mode). Each editor has its own insert mode. Step
  input already has `paw.step.target(name, spec)`.

---

## 11. Before and after screens (100x30)

Glyphs in the "after" screens: `█` ink (with the name or lyric at the
start), `▓` chosen, `░` result, `┄` other take, `╌` context, `▐` the
cursor, `▸` the cursor row. In a real terminal the ink has the color of
the part and the ghosts a faint color. The "before" screens are
captures; the "after" screens are drawn by `rollux/mock.py` from the
same notes.

### 11.1 Open a clip

Before (screen 2, alone after `<C-w>o`; the split of screen 1 is in
1.4): 21 rows of pitch, the melody above G5 and the chords under F3 do
not fit, 11.5 beats wide.

```text
▌  verse  Keys  C4  1.1.00                                             grid 1/16  len 1/16  vel 100
  Tracks   Grid 1/16 ▾   Snap   Note 1/16 ▾   Quantize   Step   List   Suggest   -   +
C
        ▼       ▏       ▏       ▏       2       ▏       ▏       ▏       3       ▏       ▏       ▏
▁▁▁▁▁▁▁▁▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
       •▏E4                             ▏E4                             ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
C4     •▏C4                             ▏C4                             ▏C4
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏A3                             ▏A3
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
▁▁▁▁▁▁▁▁▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏F3
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
▁C3▁▁▁▁▁▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▂70         ▄           ▂       ▁                               ▁               ▂
        █       ▇   █           █       █               ▇       █       █       █       █
 vel ▾  █       █   █           █       █               █       █       █       █       █
 NORMAL·pianoroll  ■ 1.1.00 │ 0:00.0 │ 120 bpm 4/4 │ grid 1/16                ● untitled │ cpu ▁ 0%
 Enter note · i draw notes · x delete · + up · <A-l> longer · ? keys               :help piano-roll
```

After: `Enter`. Fit time (5 cells for each beat), rows folded to the
notes (`zM rows`), chords in the ruler, two lanes (velocity, CC 1).

```text
 roll · verse · Keys › Notes · take A · notes            E5 1.2.50 v110 1.5b   grid 1/16 · zM rows
     │1 C  ·    ·    ·    2 Am ·    ·    ·    3 F  ·    ·    ·    4 G  ·    ·    ·
G5   │▏    ·    ·    G5███▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    G5████████
F5   │▏    ·    ·    ·    ▏    ·    ·    ·    F5███·    ·    ·    ▏    ·    ·    ·
E5  ▸│▏    ·  E5█████·    E5████████·    ·    ▏    E5███·    ·    ▏    ·    ·    ·
D5   │▏    D5█  ·    ·    ▏    ·    ·    D5███▏    ·    D5████████▏    D5███·    ·
C5   │C5███·    ·    ·    ▏    ·    C5███·    ▏    ·    ·    ·    ▏    ·    ·    ·
B4   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    B4███·    ·    ·
G4   │G4██████████████████▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·
E4   │E4██████████████████E4██████████████████▏    ·    ·    ·    ▏    ·    ·    ·
D4   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    D4██████████████████
C4   │C4██████████████████C4██████████████████C4██████████████████▏    ·    ·    ·
B3   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    B3██████████████████
A3   │▏    ·    ·    ·    A3██████████████████A3██████████████████▏    ·    ·    ·
G3   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    G3██████████████████
F3   │▏    ·    ·    ·    ▏    ·    ·    ·    F3██████████████████▏    ·    ·    ·
─────┼────────────────────────────────────────────────────────────────────────────────  lanes \l
vel  │        110                                                                       vel  [ ]
     │        ▃      ▁                                  ▁                   ▄
     │█    ▅  █      █    ▆         ▄    ▆    ▇    ▅    █         ▃    ▅    █
     │█    █  █      █    █         █    █    █    █    █         █    █    █
     │█    █  █      █    █         █    █    █    █    █         █    █    █
mod  │                                                                                  cc1  70
     │                                                         ▁▁▁▂▂▂▂▃▃▃▄▄▄▅▅▅▅▆▆▆▇▇▇
     │                              ▁▁▁▁▂▂▂▃▃▃▄▄▄▄▅▅▅▆▆▆▇▇▇▇██████████████████████████
     │    ▁▁▁▂▂▂▃▃▃▃▄▄▄▅▅▅▆▆▆▆▇▇▇█████████████████████████████████████████████████████


 NORMAL·roll  ■ 1.1.00 │ 120 bpm 4/4 │ grid 1/16
 + - pitch · [ ] vel · <A-h/l> length · H L move · <C-w>j lanes · \l lanes · \m look · ? keys
```

### 11.2 Shape the bend of one note

Before: `gX` opens a window of the curve editor with its own time axis.
The roll loses its rows (screen 10).

```text
▌  verse  Keys  E5  2.1.00                                             grid 1/16  len 1/16  vel 100
        ▼       ▏       ▏       ▏       2       ▏       ▏       ▏       3       ▏       ▏       ▏
E5     •▏ ▏ ▏ ▏ ▏ ▏ ▏E5         ▏ ▏ ▏ ▏ ▏E5            ↗▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏E5     ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
        ▏ ▏ ▏ ▏ ▏D5 ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏D5     ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏D5
        ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
▁C5▁▁▁▁▁▏C5     ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏C5     ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏ ▏
▌ Pitch wheel of E5 · verse  2.1.00  +25%                                                  2 points
            2   3   4   5   6   7   8   9   10  11  12  13  14  15  16  17  18  19  20  21  22  23
+100%    │  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
+33%     │🬋🬋┼■🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂
         │  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
-101%    │  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
 curve +25% at 2.1.00 · grid 1/1
▌ CC 1 Modulation · verse  2.1.00  34                                                     16 points
            2   3   4   5   6   7   8   9   10  11  12  13  14  15  16  17  18  19  20  21  22  23
127      │  ▏   ▏   ▏ ■■🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂🬂
         │  ▏   ▏   ▏■🬀 ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │  ▏   ▏   ■   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │  ▏   ▏ ■■▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │  ▏   ▏■🬀 ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
64       │  ▏  ■■   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │  ▏ ■🬀▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │  ◆■  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │ ■🬄   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
         │■🬀▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
0        │  ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏   ▏
 point 5: 34 at 2.1.00 · hold
 NORMAL·curve  ■ 1.1.00 │ 0:00.0 │ 120 bpm 4/4 │ grid 1/1                     ● untitled │ cpu ▁ 0%
 i draw · o point · x remove · w next · ~ shape · g~ wave · ? keys
```

After: `gX` (or `<C-w>j` to the lane `pitch`). The lane shows the curve
of the E5 at 2.1 inside the note edges. The grid draws the pitch line
over the rows.

```text
 roll · verse · Keys › Notes · take A · notes            E5 2.1.00 v90 2b  bend +200c   grid 1/16
     │1 C  ·    ·    ·    2 Am ·    ·    ·    3 F  ·    ·    ·    4 G  ·    ·    ·
G5   │▏    ·    ·    G5███▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    G5████████
F#5  │▏    ·    ·    ·    ▏    ·   ╱·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·
F5   │▏    ·    ·    ·    ▏    · ╱╱ ·    ·    F5███·    ·    ·    ▏    ·    ·    ·
E5  ▸│▏    ·  E5█████·    E5███████↗·    ·    ▏    E5███·    ·    ▏    ·    ·    ·
D#5  │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·
D5   │▏    D5█  ·    ·    ▏    ·    ·    D5███▏    ·    D5████████▏    D5███·    ·
C5   │C5███·    ·    ·    ▏    ·    C5███·    ▏    ·    ·    ·    ▏    ·    ·    ·
B4   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    B4███·    ·    ·
G4   │G4██████████████████▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·
E4   │E4██████████████████E4██████████████████▏    ·    ·    ·    ▏    ·    ·    ·
D4   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    D4██████████████████
C4   │C4██████████████████C4██████████████████C4██████████████████▏    ·    ·    ·
B3   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    B3██████████████████
A3   │▏    ·    ·    ·    A3██████████████████A3██████████████████▏    ·    ·    ·
─────┼────────────────────────────────────────────────────────────────────────────────  lanes \l
pitch│ of E5 2.1.00, cents                    ┌────────── note ─────────┐          +200c
+200 │                                    ●
     │                             ╱▔▔
   0 │                    ●▁▁▁▁▁╱
     │
-200 │
vel  │                    90
     │▄    ▂  ▅      ▄    ▃         ▂    ▃    ▃    ▂    ▄         ▁    ▂    ▆
     │█    █  █      █    █         █    █    █    █    █         █    █    █


 NORMAL·roll › pitch of E5  ■ 1.1.00 │ 120 bpm 4/4 │ grid 1/16
 w b point · + - cents · [ ] bend of the curve · o add · x remove · w b next note too · <C-w>k notes
```

### 11.3 See what plays (stack)

Before: no picture (the stack is not built).

After: `\m` with the stack `q4 dbl` on the clip.

```text
 roll · verse ≡ q4 dbl · Keys › Notes · take A · notes+played \m       C5 1.1.00 v96   grid 1/16
     │1 C  ·    ·    ·    2 Am ·    ·    ·    3 F  ·    ·    ·    4 G  ·    ·    ·
G5   │▏    ·    ░░░░░G5███▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    G5████████
F5   │▏    ·    ·    ·    ▏    ·    ·    ·    F5███·    ·    ·    ▏    ·    ·    ·
E5   │▏    ·  E5█████░░░░░E5███████↗░░░░░░░░░░▏    E5███·    ·    ▏    ·    ·    ·
D5   │▏    D5█  ·    ·    ▏    ·    ·    D5███▏    ·    D5████████▏    D5███░░░░░░░░░░
C5  ▸│C5███·    ░░░░░░░░░░▏    ·    C5███░░░░░▏    ·    ░░░░░░░░░░▏    ·    ·    ·
B4   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    B4███·    ░░░░░░░░░░
A4   │▏    ·    ·    ·    ▏    ·    ░░░░░░░░░░▏    ·    ░░░░░░░░░░▏    ·    ·    ·
G4   │G4██████████████████▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ░░░░░░░░░░
F4   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ░░░░░░░░░░▏    ·    ·    ·
E4   │E4██████████████████E4██████████████████▏    ·    ·    ·    ▏    ·    ·    ·
D4   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    D4██████████████████
C4   │C4██████████████████C4██████████████████C4██████████████████▏    ·    ·    ·
B3   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    B3██████████████████
A3   │▏    ·    ·    ·    A3██████████████████A3██████████████████▏    ·    ·    ·
G3   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    G3██████████████████
F3   │▏    ·    ·    ·    ▏    ·    ·    ·    F3██████████████████▏    ·    ·    ·
─────┼────────────────────────────────────────────────────────────────────────────────
vel  │
     │▂       ▄      ▂    ▁                   ▁         ▂                   ▅
     │█    ▇  █      █    █         ▇    █    █    █    █         ▆    ▇    █
     │█    █  █      █    █         █    █    █    █    █         █    █    █

 █ notes (you edit)   ░ what plays   ✕ dropped   \m notes · played · both   <Space>cs the stack



 NORMAL·roll  ■ 1.1.00 │ 120 bpm 4/4 │ grid 1/16
 K on ░: made by dbl from C4 at 1.1 · \m look · <Space>cs stack
```

### 11.4 Comp a bar from take B

Before: MIDI takes show only in the arrange view (`zt`, `]t`). The roll
cannot show them.

After: `\t B`, then `vib` on a ghost note of B in bar 2, then `\c`.

```text
 roll · Keys › Notes · take A of A B C · comp A│B│A · ┄ take B \t        D5 2.3.00   grid 1/16
     │1 C  ·    ·    ·    2 Am ·    ·    ·    3 F  ·    ·    ·    4 G  ·    ·    ·
comp │A──────────────────B━━━━━━━━━━━━━━━━━━━A───────────────────────────────────────
G5   │▏    ·    ·    G5███▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    G5████████
F5   │▏    ·    ·    ·    ▏    ·    ·    ·    F5███·    ·    ·    ▏    ·    ·    ·
E5   │▏    ·  E5█████·    E5███████↗·    ·    ▏    E5███·    ·    ▏    ·    ·    ·
D5  ▸│▏    D5█  ·    ·    ▏ ┄┄┄┄┄┄┄┄┄┄┄┄┄D5███▏    ·    D5████████▏    D5███·    ·
C5   │C5███·    ·    ·    ▏    ·    C5███·  ┄┄┄┄   ·    ·    ·    ▏    ·    ·    ·
B4   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    B4███·    ·    ·
G4   │G4██████████████████▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·
E4   │E4██████████████████E4██████████████████▏    ·    ·    ·    ▏    ·    ·    ·
D4   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    D4██████████████████
C4   │C4██████████████████C4██████████████████C4██████████████████▏    ·    ·    ·
B3   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    B3██████████████████
A3   │▏    ·    ·    ·    A3██████████████████A3██████████████████▏    ·    ·    ·
G3   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    G3██████████████████
F3   │▏    ·    ·    ·    ▏    ·    ·    ·    F3██████████████████▏    ·    ·    ·
─────┼────────────────────────────────────────────────────────────────────────────────
takes│ A ███████████████████████████████████████████████████████████████████████████████ source
     │ B ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ source
     │ C ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ derived · seed







 VISUAL·roll  ■ 1.1.00 │ 120 bpm 4/4 │ grid 1/16   vib (bar 2)
 \c comp this range to take B · ]t [t active take · \t ghost take · K names the take · u undo
```

### 11.5 A singer's lane

Before: the vocal editor of utau, a second editor with its own copy of
the motions.

After: the roll on a lane with `lyrics`, a producer `diffsinger` with
controls `pitch`, `breath`, `tension`, `vibrato`, `phonemes`, `gender`.

```text
 roll · Words › Lyrics · take A · singer diffsinger ✓ baked      ku  E5 2.1.00 v90   grid 1/16
     │1 C  ·    ·    ·    2 Am ·    ·    ·    3 F  ·    ·    ·    4 G  ·    ·    ·
G5   │▏    ·    ·    ku███▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    yo████████
F5   │▏    ·    ·    ·    ▏    ·    ·    ·    ga███·    ·    ·    ▏    ·    ·    ·
E5  ▸│▏    ·  i██████·    mo███████↗·    ·    ▏    re███·    ·    ▏    ·    ·    ·
D5   │▏    ro█  ·    ·    ▏    ·    ·    na███▏    ·    te████████▏    ku███·    ·
C5   │shi██·    ·    ·    ▏    ·    ga███·    ▏    ·    ·    ·    ▏    ·    ·    ·
B4   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    yu███·    ·    ·
phon │sh i r o  i  k u  m o    g a  n a  g a  r e  t e  y u  k u    y o
─────┼────────────────────────────────────────────────────────────────────────────────  lanes \l
pitch│ of ku (E5), cents      ●▔▔▔╲___╱▔▔▔╲___╱▔▔▔●   vibrato 25c 5.5Hz in 30% (~)
     │                     ╱                       ╲
brth │ diffsinger.breath   ▂▂▁                          ▃▄▂
tens │ diffsinger.tension  ▃▃▃▃▃▄▄▄▅▅▅▅▅▅▅▅▅▄▄▄▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃▃
note │ ku · E5 · 2.1.00 · 2 beats · ph k u (k 40 ms early) · vib on · gender 0 · vel 90













 NORMAL·roll  ■ 1.1.00 │ 120 bpm 4/4 │ grid 1/16
 c lyric · ]p [p phoneme · [ ] its start · ~ vibrato · :note.set · gR sing again · \l lanes
```

### 11.6 A derived take

```text
 roll · Words › Pitch (derived from Lyrics by diffsinger) · take s1 · read-only       grid 1/16
     │1 C  ·    ·    ·    2 Am ·    ·    ·    3 F  ·    ·    ·    4 G  ·    ·    ·
G5   │▏    ·    ·    ░░░░░▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ░░░░░░░░░░
F5   │▏    ·    ·    ·    ▏    ·    ·    ·    ░░░░░·    ·    ·    ▏    ·    ·    ·
E5  ▸│▏    ·  ░░░░░░░·    ░░░░░░░░░░·    ·    ▏    ░░░░░·    ·    ▏    ·    ·    ·
D5   │▏    ░░░  ·    ·    ▏    ·    ·    ░░░░░▏    ·    ░░░░░░░░░░▏    ░░░░░·    ·
C5   │░░░░░·    ·    ·    ▏    ·    ░░░░░·    ▏    ·    ·    ·    ▏    ·    ·    ·
B4   │▏    ·    ·    ·    ▏    ·    ·    ·    ▏    ·    ·    ·    ░░░░░·    ·    ·

 This take is derived. Edit its source (\s goes to Lyrics), or :lane.render to make it a source.


















 NORMAL·roll  ■ 1.1.00 │ 120 bpm 4/4 │ grid 1/16
 \s the source · ]t [t takes · :lane.render · K the recipe and seed
```

### 11.7 120x36

At 120x36 the same rules give 6 cells for each beat, 20 pitch rows, and
a third lane. No layout changes; the screens are golden files of their
own (13).

---

## 12. Key counts for common tasks

Counted from the key maps (`defaults/keys.lua`, `views/curve.lua`) and
checked with the captures. A chord such as `<C-w>` counts as one key.
The start: the arrange view, the cursor on the clip.

| Task | Today | Keys today | After | Keys after |
| --- | --- | --- | --- | --- |
| See every note of the clip | `Enter` `<C-w>o`, then scroll with `<C-u>` `<C-d>`: never all at once at 100x30 | 2 + scroll, not possible | `Enter` | 1 |
| Show modulation under the notes | no key: the pointer menu, or `:lua require("paw.views.pianoroll_strip").show("cc", 1)` | not possible with keys | `\l` `mod` `Enter` | 3 + 3 letters |
| A ramp of CC 1 over bar 2 | `gC`, scroll the curve window to bar 2 (its own axis), draw, `<C-w>c` | 8 or more | `<C-w>j` `g~` `ib`, choose `ramp` `Enter` | 5 |
| Raise the chord at the cursor by 20 velocity | `vic` `2` `]` | 5 | same | 5 |
| Set the chord's velocity to 50 | `vic` `50` `gzv` (musicops) | 8 | `vic` `<C-w>j` `c` `50` `Enter` | 8 (no extension needed) |
| Shape the bend of a note | `gX`, edit in the new window, `<C-w>c` | 3 + edit | `gX`, edit, `<C-w>k` | 2 + edit |
| See the stack result | — | — | `\m` | 2 |
| Comp bar 2 from take B | not in the roll | — | `\t` `B` `Enter` `vib` `\c` | 8 |
| Type 8 lyrics | vocal editor: `<Space>ue`, `c` and `Tab` for each | 2 + 8 × (word + 1) | `\w` and `Tab` for each | 2 + 8 × (word + 1) |
| Edit the bass note behind | `ga` on its note | 2 | same | 2 |
| Back to the arrange view | `<C-w>p` | 1 | `<C-^>` | 1 |

The biggest gains are not in the count: the roll keeps its rows (P6),
the axis is one (G3), and two tasks become possible with keys (P5).

---

## 13. Golden screens

Each with `T.expect_screen(name, w, h)` in a new test file
`tests/roll_ux.lua`, at 100x30, and the ones marked `+` also at 120x36.
The song is the song of 1.1, made in the test (no file of the machine).

| Name | Keys from the arrange view | Guards | Bundle |
| --- | --- | --- | --- |
| `r1_open` + | `Enter` | fit time, fold to notes, one header row, chords in the ruler, default lanes | PR1 |
| `r1_open_split` | `<C-w>s` `Enter` | the roll in a split still shows all notes (fold) | PR1 |
| `r1_fold_open` | `Enter` `zR` | all rows, the key column names each C | PR1 |
| `r1_scale` | `Enter` `zK` | the rows of the scale | PR1 |
| `r2_lane_picker` | `Enter` `\l` | the picker of lane kinds (velocity, CC by name and number, bend, pressure, note lanes, producer lanes) | PR2 |
| `r2_two_lanes` + | `Enter` `\l` add CC 1, `<C-w>j` `<C-w>j` | focus in the second lane; the status line names it | PR2 |
| `r2_ramp` | `<C-w>j` `g~ib` ramp | a ramp drawn on the roll's axis | PR2 |
| `r2_vel_selection` | `vic` `<C-w>j` `c50<CR>` | the chord's three bars at 50 | PR2 |
| `r3_note_lane_pitch` + | `gX` on the bent note | the note lane, the edges, the pitch line over the rows | PR3 |
| `r3_note_line` | `<C-w>j` to the note line, `l l` | the fields of the note, one chosen | PR3 |
| `r3_units` | `K` on the bent note | bars and cents in `K` (and the same in the event list, by a second assert) | PR3 |
| `r4_look_both` + | `\m` with a stack | ink and `░` and `✕`, the legend | PR4 (M5) |
| `r4_look_played` | `\m\m`, then `x` | the refusal message, nothing changed | PR4 (M5) |
| `r4_ghost_K` | `K` on a ghost | "made by ... from ..." | PR4 (M5) |
| `r5_take_ghost` + | `\t` B | `┄` notes, the header names both takes | PR5 |
| `r5_comp` | `\t` B, `vib`, `\c` | the comp row, the ink from B in bar 2, the message | PR5 |
| `r5_derived` | `Enter` on a derived take | ghosts only, the message with `\s` | PR5 |
| `r6_singer` + | `Enter` on a lane with lyrics and a stub producer | lyrics in notes, phoneme row, producer lanes, note line | PR6 |
| `r6_absent` | the same with the producer absent | `absent:` lanes, read-only | PR6 |
| `r7_side_by_side` | `<C-w>v` `\v` score | two editors, one subject, the cursor time the same | PR7 |

Each golden screen has a short key test beside it that checks the data
(not only the picture), so a golden file never is the only guard.

---

## 14. Bundles

Each bundle is one Opus agent. Each bundle brings its tests, golden
screens, the pages that change (`docs/reference/piano-roll.md`,
`key-rule.md`, `grammar.md`, `curve-editor.md`, the README of each
extension that it touches), and an entry in `bench/` where a key path
changes. Each obeys the skills paw-code, teal, lua-testing and
diataxis-docs.

| Id | Bundle | Depends on | Size | Milestone |
| --- | --- | --- | --- | --- |
| PR1 | The roll's frame: open in place, header in one row, chords in the ruler, fit (`zx`), folds (`zM` `zR` `zK` `za`), toolbar on `\T`, one unit for time | none | M | m-15 |
| PR2 | The lane host: lanes as windows of the roll, `\l`, `gC` focuses a lane, the curve keys on the roll's axis; replaces `pianoroll_strip.tl` | PR1 | L | m-15 |
| PR3 | Per-note data: note lanes, the pitch line over the rows, the note line, `:note.set`, moves carry the data, units in cents | PR2; A2 for `Note.ctl` and `Note.lyric` (the MIDI 2.0 part does not wait) | L | m-15 |
| PR4 | Ink and ghosts: layers, glyphs, `\m`, refusals, `K` on a ghost | PR1; M4 (the result), so it is the UX part of M5 | M | m-5 (in M5) |
| PR5 | Takes and comps in the roll: `]t` `[t` as takes (`Tab` keeps the lanes), `\t`, the comp row, `\c`, derived takes read-only, `\s` | PR2, TK | M | m-17 |
| PR6 | Producer controls: the control schema in `paw.producers.define`, producer lanes, the phoneme row, `\w`, `gR`; a stub producer in the tests | PR3, RD | L | m-17 |
| PR7 | The editor subject parts: `paw.editor.lanes`, `noteline`, `look`, `takes`, `controls`; `\v`; two windows on one subject; the drum grid uses the lane host | B7, PR2 | L | m-10 |

```text
PR1 ──▶ PR2 ──▶ PR3 ──▶ PR6 ◀── RD, A2
  │       ├───▶ PR5 ◀── TK
  │       └───▶ PR7 ◀── B7
  └───▶ PR4 ◀── M4        (PR4 is the UX part of M5)
```

PR1 and PR2 can start now (they need no new model). PR4 waits for the
stack (M4). PR5, PR6 and PR7 wait for LA/TK, RD and B7.

### 14.1 Ticket text (ready to paste)

**PR1 · The roll's frame.**
Goal: `Enter` on a clip shows all of its notes at 100x30 (G1).
Scope: the roll opens in the window of the arrange view (option
`paw.opt.roll_open = "replace" | "split"`, default from Q1); the
header is one row (subject, take, look, cursor note, grid); the chord
row moves into the ruler; the toolbar shows only in the window and on
`\T`; `zx` fits the time zoom (also at open); `zM` `zR` `zK` `za` fold
the rows (window state, `screen.json`); time in bars in `K`, the title
and the event list.
Acceptance: golden screens `r1_*`; a key test per fold key; `K` gives
bars; the docs pages of the roll and the key rule.
Out: lanes, takes, stacks.

**PR2 · The lane host.**
Goal: every controller is reachable with keys, on the roll's axis
(G2, G3).
Scope: `paw.editor.lanes` (a host of lanes under a time axis);
`pianoroll_strip.tl` becomes the velocity lane and one controller lane
kind; `\l` picker (velocity, CC 0 to 127 by name, bend, channel
pressure, program, per-note kinds later); `<C-w>j` `<C-w>k`; the keys
of 6.3 from the curve editor (shared code, not a copy); `gC` focuses or
adds the lane; `<C-w>f` pops the lane out; lane set and heights in the
window state; the pointer keeps the menu on the lane name.
Acceptance: golden screens `r2_*`; `tests/keys_constitution.lua`
passes; a bench of a key in a roll with 8 lanes on a clip of 10 000
notes.

**PR3 · Per-note data.**
Goal: per-note expressions and attributes are visible and editable in
the roll (7).
Scope: note lanes (`over = "note"`) for MIDI 2.0 per-note pitch bend
(cents), pressure and per-note CC; `w` `b` across notes in a note lane; the pitch line over the
rows; the note line with fields; `:note.set key=value` with completion
from the schema; every note operator carries per-note data (move,
copy, paste, quantize, delete); `gX` focuses the pitch note lane.
Acceptance: golden screens `r3_*`; one test per operator family for
carried data; units agree in `K`, note line, lane and event list.

**PR4 · Ink and ghosts (the UX of M5).**
Scope: the layer order and glyphs of 4.2; `\m` with the defaults of
9.2; refusals of 4.3; `K` on a ghost; fold rows include result rows;
the played velocity tick. Acceptance: `r4_*`.

**PR5 · Takes and comps in the roll.**
Scope: `]t` `[t` are takes in the roll (classic keys keep the old
meaning), `Tab` `S-Tab` keep the lanes shown; `\t` picker and the `┄`
layer; the comp row; `\c` in visual and normal mode; the takes lane;
derived takes read-only with `\s` and `:lane.render`. Acceptance:
`r5_*`; one undo step for `\c`; the note-crossing rule of round 4.4.

**PR6 · Producer controls.**
Scope: `controls` in `paw.producers.define`; producer lanes and fields;
the phoneme row with `]p` `[p` `+ -` `c` `x`; `\w`; `gR`; absent
producer read-only. A stub producer in `tests/` (no outside program).
Acceptance: `r6_*`; the utau README says which keys of its editor now
come from the roll (the extension decides when to move).

**PR7 · The editor subject parts.**
Scope: with or after B7. The parts of 10.2 as modules with Teal
records; `\v`; two windows on one subject; the drum grid shows a
velocity lane from the host. Acceptance: `r7_side_by_side`; the 11
modules of P10 read `paw.editor`.

---

## 15. Questions for the owner

Each question has a recommendation. The defaults of the bundles follow
the recommendation until the owner answers.

| # | Question | Options | Recommendation |
| --- | --- | --- | --- |
| Q1 | Where does `Enter` open the roll? | (a) in a split under the arrange view (today); (b) in place of the arrange view, as `:e` opens a buffer; `<C-^>` back | **(b)**. The split gives 10 rows at 100x30 (P1). `<C-w>s` `Enter` keeps a split for those who want it. |
| Q2 | `]t` `[t` in the roll: takes (key rule) or the next track edited (today)? | takes; tracks | **Takes.** `Tab` `S-Tab` already step the tracks shown. Classic keys keep the old meaning for one release. |
| Q3 | Your round 4.5 starting point says `[` `]` step the active take. In the roll `[` `]` are the velocity (second value). Which key steps takes? | `[ ]` everywhere; `]t` `[t` everywhere | **`]t` `[t` everywhere** (the key rule names `]t` for takes). `[ ]` stays the second value; on the header of a take lane in the arrange view, the take can be the second value. |
| Q4 | Which key types lyrics? The vocal editor uses `c`, but `c` is the change operator of the roll. | `c` on lanes with lyrics; `\w`; only `:note.set lyric=` | **`\w`** (words from the note on, `Tab` to the next), and `:note.set`. `c` stays an operator in every view. |
| Q5 | Where does the set of lanes live? | per window (`screen.json`); per lane (project data); per part kind (a default) | **Per window**, with a default from the lane's type (a lane with `lyrics` gets the phoneme row and the producer lanes; a drum map gets velocity). It is a view, not music, so it does not go in the project data. |
| Q6 | When the pitch range does not fit, fold automatically? | always open; fold to notes when it does not fit; always fold | **Fold to the notes when it does not fit**, and say it in the header (`zM rows`). `zR` opens. |
| Q7 | The vocal editor of utau: does it stay an editor of its own? | it stays; it becomes the roll with the singer's lanes | **The roll with the singer's lanes becomes the default editor of a lane with `lyrics`.** The vocal editor stays an editor of the same subject (`\v`) for what only OpenUtau shows, until the Rust port of utau (memory: notation and utau become Rust native extensions). Its motions come from the shared parts (PR7), not from a copy. |
| Q8 | How many ghost layers at one time? | all; two; one | **Two** beside the ink (the look and one of take or context). More is not readable in cells. |
| Q9 | Does the roll edit the whole lane or one clip? | one clip (today); the whole lane; both with a key | **Both**: `Enter` opens the clip, `\L` widens to the lane (REAPER "show all items"). |
| Q10 | Per-note data and a modifier stack: does a modifier see `Note.ctl` and the per-note controllers? | yes, passes them through; no | **Yes, it passes them through** as MOD 3.2 does for attributes. A kind that makes a note copies the data of the note in `from`. |
