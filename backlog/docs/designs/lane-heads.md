# Lane heads: the kind of a row gives its head

Status: accepted by the owner 2026-11-23 (Q1-Q9 as recommended). ADR: architecture/decisions/0034-lane-heads-by-kind.md.
Related: TASK-177 (B7), TASK-306 (A2), TASK-309 (LA), TASK-313 (B6), TASK-314 (TK),
TASK-316 (RD), TASK-320 (VD), piano-roll-ux.md (PR2), ADR 0018, 0019, 0025, 0026, 0027, 0030.
Base of the study: main at deb79a0f.

## 1. Summary

- A **head** is the left part of a row in the arrange view. It shows a part, a
  lane, or a part with its one lane. It owns no data.
- The core keeps the **frame** of each row: the track column (numbers, signs,
  folds), the stripe with the colour and the selection, the lit flags, the
  rule, the mouse edge for the height, and every key of the view.
- A head is a record in a registry, `paw.heads`, by name. A part kind, a clip
  kind, a producer and a lane can name a head. A name that is not registered
  falls back, in the end to the default head.
- The **default head** is made of **pieces**: name, badge, chips, automation,
  bake, volume, meter, input button, route, sends, input, takes, value,
  picture. Each head of a kind uses the same pieces.
- A head can wish for more rows. The core decides the height. A head can add
  keys on `<localleader>`, only on its own rows.
- The first bundle (HD) moves today's header code into pieces with no change
  on the screen. The golden screens of today stay the same.

## 2. What paw draws today

`runtime/lua/paw/views/arrange_track.tl:116-491` draws one header for each
track (`M.header`). `arrange.tl` calls it for each track row
(`arrange.tl:2058`) and for the master (`arrange.tl:2299`). Other rows draw
their own header half in `arrange.tl`: the automation lane
(`lane_header`, `draw_lane_row`, `arrange.tl:1118-1143`), the take lane
(`draw_take_row`, `arrange.tl:1322-1334`), the tempo lane
(`draw_tempo_row`, `arrange.tl:1270-1276`) and the closing line of a
subproject (`draw_closing_line`, `arrange.tl:1872`). A kind of track adds
only its letter, through the layer `paw.ui.layer("arrange", "header")`
(`track_kinds.lua:188-192`). The mouse finds the chips by fixed columns and
rows (`arrange_mouse.tl:754-836`, `view.flags`).

Real screens of main (shared binary, `tests/tools/run.sh --headless`, the
utau and drums extensions loaded). The header width is 12 on a screen of 60
columns, 22 on 100, 26 on 140 (`view.header_width`, `arrange.tl:230`).

```text
60 columns (narrow)            100 columns (default)
 1 ▌ Guitar M │▏riff            1 ▌ Guitar        MSRI │▏riff
   ▌ ─── -3.5 │▄▄▄▄               ▌in ─────────── -3.5 │▄▄▄▄
   ▌ L30      │                   ▌   L30              │
 2 █ Piano  S │▏chords          2 █ Piano         MSRI │▏chords
   █ ──── 0.0 │                   █in ──────────── 0.0 │
   █          │▀▀▀▀               █   C                │▀▀▀▀
 3 ▌VVocal    │▏                3 ▌ V Vocal       MSRI │▏
   ▌ ──── 0.0 │                   ▌in ──────────── 0.0 │
   ▌ UTAU vo… │                   ▌   C   UTAU voice   │
     o new tra│                       o new track      │

140 columns (wide), four rows: the fourth row stays empty
 1 ▌ Guitar         M S R I │▏riff
   ▌in ─────────────── -3.5 │
   ▌   L30                  │▀▀▀▀
   ▌                        │

A lane row and a group (100 columns)
 1  ▌ Guitar     A MSRI │▏riff
    ▌in ────────── -3.5 │▄▄▄▄
    ▌   L30             │
    ▏ ↳ Volume          │▏🬍🬂🬂🬂🬂◆🬂🬂🬂🬂🬂
    ▏   -6.0 dB    read │▏
 3 ▾▌ Band         MSRI │▏
   │▌in ─────────── 0.0 │▏
 4 │▌ V Vocal      MSRI │▏
```

What the screens show:

- Each kind gets the same head. The vocal head shows its letter and the
  device chain (`UTAU voice`), not its singer.
- On the narrow screen the letter of the kind touches the name (`▌VVocal`).
- A head of four rows leaves a row empty when the track has no input or
  sends.
- The header code is in four places, and each new row kind adds one more.

## 3. Words

| Word | Meaning |
| --- | --- |
| row | One entry of the arrange view's rows: a part row, a lane row, a merged row, the master row. `j` and `k` move by row. |
| merged row | The row of a part that has one lane. It shows the part and its lane in one head, as a track today. |
| frame | What the core draws on each row: the track column, the stripe, the lit flags, the rule. |
| head | The cells of a row between the stripe and the rule, less the lit flags. A head draws them. |
| subject | What a head shows: a part, a lane, or both. |
| piece | A small drawing function that a head uses: the name, the chips, the meter. |
| lit flag | A switch that is on (mute, solo, arm, monitor). The core shows it when the head does not. |
| wish | The number of rows that a head asks for. The core decides the height. |

## 4. The contract

The records go in `runtime/lua/paw/contracts.tl`. The module is
`runtime/lua/paw/heads.tl` (registry, choice, draw) with
`runtime/lua/paw/heads/pieces.tl` and `runtime/lua/paw/heads/default.tl`.
Before bundle LA, a part is a track and the lane is nil.

```teal
--- The kind of row that a head shows.
enum HeadRow
  "part"     -- a part with zero or two or more lanes
  "lane"     -- one lane under its part
  "merged"   -- a part with one lane: the part and the lane in one head
  "master"   -- the master of the root part
end

--- The width class of a head: under 16 columns, 16 to 25, 26 or more.
enum HeadWidth
  "narrow" "default" "wide"
end

--- What a head shows. `kind` is the name that chose the head: a part
--- kind, a clip kind, a producer, or "default".
record HeadSubject
  row: HeadRow
  part: integer
  lane: integer           -- nil on a part row and the master row
  kind: string
end

--- What `rows` gets.
record HeadSize
  subject: HeadSubject
  width: integer
  class: HeadWidth
end

--- What a press on a hit does: a command as `:` takes it, or a function.
type HeadAction = string | function(s: HeadSubject, e: MouseEvent)

--- What `render` gets. `buf` holds the cells of the head only: the
--- track column, the stripe and the rule are not in it. The core drew the
--- ground. `part` and `lane` are the public records of the API.
record HeadContext
  buf: Buf
  width: integer
  height: integer
  class: HeadWidth
  subject: HeadSubject
  part: types.Part
  lane: types.Lane
  selected: boolean       -- the cursor is on this row
  focused: boolean        -- the window has the keyboard
  g: Glyphs               -- paw.draw.g, with the ASCII glyphs when paw.opt.ascii
  --- The piece `name` at x, y, in at most w columns. Returns the columns
  --- that it used: 0 when it has nothing to show or does not fit.
  piece: function(self: HeadContext, name: string, x: integer, y: integer, w: integer): integer
  --- One line of pieces. `left` goes from the left, `right` from the
  --- right. The last piece of `left` gets the columns that are left. When
  --- the room is short, the piece with the lowest `keep` goes first.
  line: function(self: HeadContext, y: integer, left: {string}, right: {string})
  --- Words in a style, cut with "…" to w columns.
  text: function(self: HeadContext, x: integer, y: integer, w: integer, words: string, style: string)
  --- A picture (`paw.canvas.image`) over x, y, w, h: an image where the
  --- terminal shows images, else half blocks. Nothing when paw.opt.head_pictures is false.
  picture: function(self: HeadContext, x: integer, y: integer, w: integer, h: integer, key: string): boolean
  --- A context for a part of the head, for example the column beside a picture.
  sub: function(self: HeadContext, x: integer, y: integer, w: integer, h: integer): HeadContext
  --- The cells x, y, w, h do `action` on a press of the pointer.
  hit: function(self: HeadContext, x: integer, y: integer, w: integer, h: integer, action: HeadAction)
  --- The column before the name, for the layers of other modules.
  mark_at: integer
end

--- A key of a head: `<localleader>` and `lhs`, only while the cursor is on
--- a row of this head.
record HeadKey
  lhs: string
  run: string | function(s: HeadSubject)
  desc: string
end

--- A head (`paw.heads.define`).
record Head
  name: string
  title: string
  --- The rows that the head wishes for, 1 to 6. Nil: the height of the view.
  --- Only of the subject's settings and the width, never of data that
  --- comes late (a picture that loads).
  rows: function(size: HeadSize): integer
  render: function(ctx: HeadContext)
  keys: {HeadKey}
  --- Lines that `K` adds after the lines of the core.
  describe: function(s: HeadSubject): {string}
  --- What the head reads outside the model, as a key: the singer, a file.
  --- A change of it draws the head again.
  stamp: function(s: HeadSubject): string
  --- The extension that defined it (paw/ext.lua), nil for the user's.
  ext: string
end

--- A piece (`paw.heads.piece`).
record Piece
  name: string
  keep: integer           -- higher: it stays longer when the room is short
  min: integer            -- the fewest columns that it draws in
  line: boolean           -- true: it takes a whole line (meter, route, sends, input)
  flags: {string}         -- the flags that it shows: "mute" "solo" "armed" "monitor"
  has: function(ctx: HeadContext): boolean   -- nil: always
  draw: function(ctx: HeadContext, x: integer, y: integer, w: integer): integer
  ext: string
end

--- A line of a head made with `paw.heads.compose`.
record HeadLine
  left: {string}
  right: {string}
end
```

The module:

```teal
record Heads
  heads: registry.Registry<Head>      -- by name; a new head of a name hides the old one
  pieces: registry.Registry<Piece>
  define: function(name: string, spec: Head): Head
  remove: function(name: string)
  piece: function(name: string, spec: Piece): Piece
  --- A render from lines: the first line always, then each line whose
  --- pieces have something, while there are rows.
  compose: function(lines: {HeadLine | string}): function(ctx: HeadContext)
  --- The head that a row uses, after the fallback.
  of: function(s: HeadSubject): Head
  --- How many heads paw drew since it started: tests count work with it.
  draws: integer
end
```

How a kind names its head:

| Who | Field | Bundle |
| --- | --- | --- |
| A kind of track (today), a part kind (after A2) | `head = "vocal"` in `paw.track_kinds.define`, then in `paw.kinds.define("part", ...)` | HD, A2 |
| A clip kind (the kind of a lane) | `head = "video"` in `paw.clip_kinds.define`, then `paw.kinds.define("clip", ...)` | HD, A2 |
| A producer (a derived lane) | `head = "script"` in `paw.producers.define` | RD |
| One lane | `meta.head`, set by `:lane.head <name>` (one undo step) or by what made the lane | LA |

The registry is `paw.registry`, so an extension owns its heads and pieces,
and they go when it unloads. The user replaces a head with the same name in
`init.lua`: `paw.heads.define("default", ...)`. The old head comes back
when the user's head goes.

## 5. How paw chooses the head of a row

paw takes the first name that is registered:

1. On a lane row: `lane.meta.head`; then the producer of the active take,
   when the take is derived; then the clip kind of the lane; then
   `default.lane`.
2. On a merged row: the part kind's head; then the steps of a lane row, but
   the last name is `default`.
3. On a part row: the part kind's head; then `default.part`.
4. On the master row: `master`.

A name that no loaded extension registers falls back to the next. So a
project opens without the extension, and its rows get the default head. `K`
says which head the row asked for: `head vocal (no extension here defines
it)`.

A head that fails draws nothing. paw draws the default head over the row
and gives one message for each head: `the head vocal failed: <the first
line of the error>; paw shows the default head`. The head runs under
`paw.limit`, as a clip kind does (`paw.opt.head_limit`, 5 ms). A head that
goes over the limit is out until the extension loads again, with the same
message. `:checkhealth` lists the heads that are out.

## 6. The pieces and the default head

| Piece | What it draws | keep | Line | Flags |
| --- | --- | --- | --- | --- |
| `name` | The name; a fold `+3`; a group `≡`; a return row `⧉Bridge ×2`; the indent when the column has no `fold` | 100 | no | |
| `badge` | The letter or glyph of the kind (`V`, `▶`, `ƒ`) | 90 | no | |
| `chips` | `M S R I` with room, `MSRI` in less, the lit ones in less still. Switch marks. Hits | 80 | no | all four |
| `automation` | `A`, or the mode `T` `L` `W` `-` | 40 | no | |
| `bake` | `F` `f` today; after RD: `fresh`, `stale`, `◔ 40%`, `absent` | 60 | no | |
| `volume` | The dB text (on a one-row head) | 30 | no | |
| `meter` | The meter with the fader place, the dB, the clip light. A bound mark. Hit: drag the volume | 70 | yes | |
| `input_button` | `in`, lit when the part has an input. Hit: the menu of inputs | 20 | no | |
| `route` | The pan knob, the device chain, the output. Hit: drag the pan | 50 | yes | |
| `sends` | `↗ Reverb -9  ↗ Delay -12` | 40 | yes | |
| `input` | The input with its level. The level becomes a bound mark | 45 | yes | |
| `takes` | `take B of 3`, `B/3`, a comp mark (TK) | 50 | no | |
| `stack` | The stack of the lane, `≡ q4 dbl` (M4) | 35 | no | |
| `value` | A curve lane: the value at the cursor and its mode `read` | 70 | yes | |
| `source` | A derived lane: `← Notes · drop2` (RD) | 55 | yes | |
| `lanes` | A folded part: the badges of its lanes, `3 lanes` | 50 | yes | |
| `picture` | `ctx:picture` as a piece of a fixed size, for heads that compose | 10 | no | |

The default heads, with `paw.heads.compose`:

```lua
paw.heads.define("default", { title = "Part", render = paw.heads.compose({
  { left = { "badge", "name" }, right = { "bake", "automation", "volume", "chips" } },
  { left = { "input_button", "meter" }, right = {} },
  "route", "sends", "input", "takes",
}) })
paw.heads.define("default.part", { title = "Part", render = paw.heads.compose({
  { left = { "name" }, right = { "automation", "chips" } },
  { left = { "input_button", "meter" }, right = {} },
  "lanes", "route", "sends",
}) })
paw.heads.define("default.lane", { title = "Lane", render = paw.heads.compose({
  { left = { "badge", "name" }, right = { "bake", "takes", "chips" } },
  "source", "input", "stack",
}) })
paw.heads.define("master", { title = "Master", render = paw.heads.compose({
  { left = { "name" }, right = {} },
  { left = { "meter" }, right = {} },
}) })
```

The `volume` piece draws only on a head of one row, as today. On a lane row
the `chips` piece shows `M R I` (lane mute, arm, monitor). Solo is on strips
(ADR 0027).

A head of a kind, the vocal head of the utau extension (sketch):

```lua
paw.heads.define("vocal", {
  title = "Vocal part",
  rows = function(size) return size.class == "narrow" and 3 or (size.class == "wide" and 4 or 3) end,
  stamp = function(s) return utau.config(s.part).singer or "" end,
  render = function(ctx)
    local body = ctx
    local key = singer_picture(ctx.subject.part)          -- paw.canvas.image, made once
    if key and ctx.class ~= "narrow" and ctx.height >= 2 then
      local w = ctx.class == "wide" and 6 or 4
      ctx:picture(ctx.class == "wide" and 1 or 0, 0, w, ctx.height, key)
      body = ctx:sub(w + (ctx.class == "wide" and 2 or 1), 0, ctx.width, ctx.height)
    end
    body:line(0, { "badge", "name" }, { "chips" })
    if body.height >= 2 then body:line(1, { "meter" }, {}) end
    if body.height >= 3 then body:text(0, 2, body.width, singer_words(ctx.subject.part), "TrackInfo") end
    if body.height >= 4 then body:piece("takes", 0, 3, body.width) end
  end,
  keys = { { lhs = "s", run = "utau.singer", desc = "Choose the singer" } },
  describe = function(s) return { "singer " .. singer_words(s.part) } end,
})
paw.track_kinds.define("vocal", { title = "Vocal track", letter = "V", head = "vocal", ... })
```

The picture comes from the singer's `image` field, which the OpenUtau
protocol gives (`extensions/utau/lua/utau/proto.lua:278`). The extension
reads the file once and keeps the key of `paw.canvas.image`.

## 7. Today's code and the pieces

| Today | After |
| --- | --- |
| `arrange_track.tl` `M.header`: the `trackhead` mark (ground, stripe, colour, selection) | The core frame (`heads.draw`) |
| `arrange_track.tl` `draw_chips` | Piece `chips`; the core lit flags |
| `arrange_track.tl` `draw_states`: the automation letter | Piece `automation` |
| `arrange_track.tl` `draw_states`: `F` and `f` | Piece `bake` |
| `arrange_track.tl` `draw_states`: the volume on one row | Piece `volume` |
| `arrange_track.tl` `name_text`, `places_text` | Piece `name` |
| `track_kinds.lua:188-192`, the letter as a layer | Piece `badge`; the layer goes |
| `arrange_track.tl` `draw_meter_row` | Pieces `input_button` and `meter` |
| `arrange_track.tl` `draw_route`, `chain` | Piece `route` |
| `arrange_track.tl` `sends_text` | Piece `sends` |
| `arrange_track.tl` `draw_input` | Piece `input` |
| `arrange_track.tl` `draw_lines` | `paw.heads.compose` |
| `paw.ui.paint("arrange", "header", ...)` | Stays. The core calls it after the head, with `x = ctx.mark_at` |
| `arrange.tl` `lane_header`, the header half of `draw_lane_row` | Head `curve` with pieces `badge`, `name`, `value` (B6) |
| `arrange.tl` the header half of `draw_take_row` | Head `take` with piece `takes` (TK) |
| `arrange.tl` the header half of `draw_tempo_row` | Head `tempo` (B6) |
| `arrange.tl` `draw_closing_line` | Stays in the core: it is a frame of a subproject, not a head |
| `arrange.tl` `draw_master` | Head `master` |
| `arrange_mouse.tl` `press_chips`, `press_volume`, `press_pan`, `name_at` | The hits of the pieces |
| `view.flags` and the window state `flags` | The window state `hits` |

What goes away from `arrange.tl`: the two calls of `track_parts.header`
become one call of `heads.draw(F, row)` for each row (HD). The header
halves of the lane, take and tempo rows go to their heads (B6, TK). The
fields `flags` and `column_width` go. `view.header_width`, `NARROW_HEADER`,
the layout and the rows stay in the view: the core decides where heads go.
About 380 lines leave `arrange_track.tl` for `paw/heads/`. The marks
(`trackhead`, `switch`, `label`, `hmeter`, `knob`, `button`) do not change,
so the window needs no change.

## 8. Mock screens

Glyphs: `▌` `█` the stripe (core), `▏` the thin stripe of a lane row (core),
`▀` a half-block cell (two pixels in colour), the numbers and `▸ ▾ │ ╰` the
track column (core), `│` at the right the rule (core). A blank area beside
`Vocal` in the image screens is the image. Under each screen a line says
what the core draws. The rest is the head.

### 8.1 The default head (audio and MIDI): the same as today

Bundle HD must give these cells. They are today's cells, with one change on
the narrow screen: the badge has a space after it (`▌V Vocal`).

```text
narrow (60)         default (100)               wide (140), four rows
 1 ▌ Guitar M │      1 ▌ Guitar        MSRI │      1 ▌ Guitar         M S R I │
   ▌ ─── -3.5 │        ▌in ─────────── -3.5 │        ▌in ─────────────── -3.5 │
   ▌ L30      │        ▌   L30  amp › verb  │        ▌   L30  amp › verb      │
 2 █ Piano  S │      2 █ Piano         MSRI │        ▌   ▆ Mic 1 (L)          │
   █ ──── 0.0 │        █in ──────────── 0.0 │      2 █ Piano          M S R I │
   █          │        █   C   Surge XT     │        █in ──────────────── 0.0 │
                                                     █   C   Surge XT         │
                                                     █   ↗ Reverb -9          │
core: " 1 " column, ▌ stripe, │ rule. narrow: only the lit chips (M, S).
```

The audio part and the MIDI part use one default head. The pieces show
what each part has: an input (`▆ Mic 1 (L)`) or a plugin (`Surge XT`).

### 8.2 A diffsinger (vocal) head with the singer's picture

```text
narrow (60): no picture      one row (any width): no picture
 3 ▌V Vocal M │               3 ▌ V Vocal   0.0 MSRI │
   ▌ ──── 0.0 │
   ▌ Kitane   │

default (100), half blocks        wide (140), half blocks           wide (140), image (kitty)
 3 ▌▀▀▀▀ Vocal     MSRI │          3 ▌ ▀▀▀▀▀▀ Vocal   M S R I │      3 ▌        Vocal   M S R I │
   ▌▀▀▀▀ ────────── 0.0 │            ▌ ▀▀▀▀▀▀ ─────────── 0.0 │        ▌        ─────────── 0.0 │
   ▌▀▀▀▀ Kitane · ja    │            ▌ ▀▀▀▀▀▀ Kitane · ja     │        ▌        Kitane · ja     │
                                     ▌ ▀▀▀▀▀▀ take B of 3     │        ▌        take B of 3     │
core: column, stripe, rule. head: picture, badge, name, chips, meter, singer, takes.
```

The picture is 4 by 3 cells on the default screen (4 by 6 pixels in half
blocks), and 6 by 4 cells on the wide screen (6 by 8 pixels). Half blocks
show the colours of the face and the hair, not the details. With the kitty
protocol, the same cells hold the real picture. On a narrow head or a head
of one row there is no picture. `paw.opt.head_pictures = false` turns all
pictures off.

### 8.3 A script (transformation) lane, derived from the notes

The lane "Voicing" is a derived MIDI lane under the part Piano. A Lua
script (a producer of tier kernel) makes it from the lane Notes. The head
`script` of the producer shows the state of the bake and its source. It has
no fader, no input and no arm.

```text
narrow (60)          default (100)                  wide (140)
 2 █ Piano  S │       2 █ Piano         MSRI │       2 █ Piano          M S R I │
   █ ──── 0.0 │         █in ──────────── 0.0 │         █in ──────────────── 0.0 │
   ▏ƒVoicin ✓ │         ▏ ↳ ƒ Voicing  fresh │         ▏ ↳ ƒ Voicing   ◔ 40%  M │
   ▏ ← Notes  │         ▏   ← Notes · drop2  │         ▏   ← Notes · drop2.lua  │
core: ▏ the lane stripe; on the wide screen the `M` is a lit flag of the core:
the lane is muted, and the head `script` does not show chips.
```

The states: `fresh` (`✓` when narrow), `stale` (`!`), `◔ 40%` (a bake that
runs), `absent` (the producer is not here; the kept result plays).

### 8.4 A video lane

```text
narrow (60)          default (100)                wide (140)
 4 ▌▶ Film    │       4 ▌ ▶ Film           M │     4 ▌ ▶ Film               M │
   ▌ 1080p 25 │         ▌   1080p 25 fps     │       ▌   1920×1080 25 fps h264│
                        ▌   ♪ Film sound     │       ▌   ♪ Film sound · 2 ch  │
core: the `M` is the chip of the head (the head shows only mute).
```

A video lane has no fader: the sound is a lane of its own (ADR 0023). The
head names that lane (`♪ Film sound`). The thumbnails go in the clips, not
in the head.

### 8.5 A part head with its lanes folded, then open

```text
narrow (60), folded   default (100), folded         wide (140), folded
 5▸▌ Violin I │        5 ▸▌ Violin I     MSRI │      5 ▸▌ Violin I      M S R I │
   ▌ ─── -6.0 │           ▌in ────────── -6.0 │         ▌in ────────────── -6.0 │
   ▌ 3 lanes  │           ▌   ♩ ✎ ∿   3 lanes │         ▌   ♩ Notes ✎ Words ∿ … │

default (100), open (za)
 5 ▾▌ Violin I     MSRI │▏verse
   │▌in ────────── -6.0 │
   │▏ ↳ ♩ Notes       R │▏verse
   │▏ ↳ ✎ Words  lyrics │▏la la
   ╰▏ ↳ ∿ Sung  ƒ B/3   │▏~~~~
core: ▸ ▾ │ ╰ the fold in the column; ▌ the part stripe; ▏ the lane stripes.
head: the part row is `default.part`; each lane row its own head.
```

`za` on the part row folds and opens its lanes. The lane Sung is derived
(`ƒ`) with take B of 3.

## 9. Keys

The core keeps the keys of the arrange view. A head never changes what a key
of the core does.

| Keys | On a part or merged row | On a lane row |
| --- | --- | --- |
| `j` `k`, counts, `gg` `G`, `Ctrl-d` `Ctrl-u` | Move by row | Move by row |
| `+` `-` `Ctrl-a` `Ctrl-x` | The volume of the strip | A curve lane: the value of the point. Another lane: the volume of the strip that it feeds, and the message names the strip |
| `[` `]` | The pan of the strip | The pan of the strip that it feeds |
| `s` | Solo the strip | Solo the strip that it feeds |
| `M` | Mute the strip | Mute the lane |
| `r` | Arm the lanes that record | Arm the lane |
| `gc` | Mute, as an operator | Mute, as an operator |
| `K` | The lines of the core, then `describe` of the head | The same |
| `Enter` | Open the editor of the lane (merged row) | Open the editor of the lane |
| `za` | Fold the lanes and the child parts | Fold the takes |
| `]t` `[t` | The takes of the lane (merged row) | The takes of the lane |
| `<localleader>` and a key | A key of the head, when the head has it | A key of the head, when the head has it |

A head adds keys only on `<localleader>`. The keys work only while the
cursor is on a row of that head: paw puts them in a key scope (the
`key_scope` of the editor subject, B7) that the arrange view turns on for the
row under the cursor. `paw.heads.define` refuses a key that the arrange view
or a bundled extension has on `<localleader>` (today `\S` `\T` `\t` `\k`
`\V` `\i` `\n` `\fi` `\fo`, and `\c` of ADR 0026): `the head vocal cannot
take \t: the arrange view uses it (patterns)`. `tests/keys_constitution.lua`
reads the keys of each registered head.

The key rule (AGENTS.md rule 3), checked:

- `h j k l w b e 0 ^ $ gg G` only move. A head cannot map them.
- `+ -` `Ctrl-a` `Ctrl-x` change the main value, `[ ]` the second. A head
  cannot map them. The kind of the row decides the values, not the head.
- `< >` are time. `K` describes: the head adds lines, it does not replace
  the lines of the core. `Esc` cancels.
- The keys of one head go on `<localleader>`.

`M`, `s` and `r` on a head that does not show them:

- The key acts on the model, as on every other row. The head only shows.
- The core draws a lit flag that the head does not show. It draws the
  letter in the last cells of the first line of the head, over what the
  head drew there (8.3, wide). A head cannot hide a state that changes the
  sound. A head that shows a flag says so in `Piece.flags` (the `chips`
  piece) or in its own pieces.
- A row whose subject cannot do the action refuses it with a message, and
  nothing changes: `r` on a derived lane: `Voicing is derived: it does not
  record. Render it to record over it (:lane.render)`; `s` on a lane that
  feeds no strip: `Words feeds no strip: there is nothing to solo`; `r` on
  a video lane: `a video lane does not record`.

## 10. Height

- The core decides the height of each row. The order: the height that the
  user set (a drag of the bottom edge, `paw.vzoom`, `paw.opt.track_height`);
  else, when the auto height is 1 (a crowded screen), 1; else the larger of
  the auto height and the head's wish, at most 6.
- Each head draws in each height from 1 up. A head of one row draws its
  first line only (8.2, one row).
- The wish depends only on the subject's settings and the width class. It
  never depends on data that comes late: the vocal head wishes for 3 rows
  when it has a singer, also before the picture loads. paw asks `rows` once
  for each layout and keeps the result by the stamp of the subject.
- A change of a wish takes effect at the next layout. The top row of the
  window stays. The cursor's row stays in view, as today
  (`rows_with_lanes`, `arrange.tl:314`). A row above the cursor that grows
  moves the cursor's row down; paw does not scroll to hide that.
- `j` and `k` move by row, so a tall head is one step. Counts count rows.
  The track column numbers rows, not lines.
- The clip area of the row has the height of its head: one row is one
  height on both sides of the rule. A taller head gives its clips more lines
  (a taller waveform, more rows of the small piano roll).
- A row with its own height uses the path of `rows_with_lanes` today: the
  layout places rows one by one and scrolls.

## 11. Redraw and speed

- The arrange view draws a frame when something changes, as today.
- Each head keeps its cells (`buf:keep` and `buf:put_kept`, as the clip
  rows do, `arrange.tl:1023`) by a key: the head's name, the stamp of the
  part and of the lane from the kernel, the head's `stamp`, the width, the
  height, `selected`, `focused` and the generation of the options. A head
  draws again only when the key changes.
- The meter, the fader place and the clip light are bound marks
  (`hmeter`, `bind = "meter:<id>"`). The frontend moves them with the live
  values, and the head does not draw again. The level of the `input` piece
  becomes a bound mark too (today it is a glyph in cells,
  `arrange_track.tl:427`).
- A picture is a content key (`paw.canvas.image`). A frontend that has it
  gets no new bytes. A head that scrolls sends only the new place.
- On `j`, two heads draw again: the row that the cursor left and the row
  that it is on. A test counts this with `paw.heads.draws`.
- Budget: a key stays well under 100 ms on a large project (rule 7). The
  heads of one frame take under 2 ms when two heads draw again, and under
  10 ms when all heads of a 200-column screen draw again (a resize). The
  bench (`bench/`, a project of 64 parts, three kinds of head) measures
  this. No test measures time.
- A slow head goes out by `paw.limit` (section 5).

## 12. The mouse

The pieces give hits (`ctx:hit`): the chips switch their flag (a drag
across rows sets them all alike), the meter drags the volume, the knob of
`route` drags the pan, `in` opens the menu of inputs. A head of a kind gives
its own hits. The core keeps: a press on the track column, the bottom edge
(the height, Alt and a press in a terminal), and a press elsewhere on the
head (select, rename on a double click, drag to move). The window state
`hits` replaces `flags`. `arrange_mouse.tl` reads the hits and no longer
knows the columns of the header.

## 13. The plan

### 13.1 The bundles

| Bundle | What it builds for heads | When |
| --- | --- | --- |
| **HD (new)**: lane heads, the contract and the default head | `contracts.tl` records; `paw/heads.tl`, `paw/heads/pieces.tl`, `paw/heads/default.tl`; the pieces from `arrange_track.tl`; `heads.draw` in `arrange.tl`; `head` on `paw.track_kinds` and `paw.clip_kinds`; the choice and the fallback; lit flags; head keys in a scope; the wish and the height rule; kept cells; hits for the mouse; `paw.opt.head_pictures`, `paw.opt.head_limit`; the extension skill and the API reference | Phase 2b, after W1. Size M. Before LA. Not in the batch of LA, B6 or TK (`views/arrange*.tl`) |
| A2 (TASK-306) | Moves the field `head` from `paw.track_kinds` and `paw.clip_kinds` to the part and clip families of `paw.kinds`. The record `Head` does not change | Phase 2 |
| B7 (TASK-177) | The key scope of a head uses the `key_scope` of the editor subject. The check that a view reads no private type covers `paw/heads/` | Phase 2 |
| LA (TASK-309) | The lane subject; lane rows and merged rows; `default.part` and `default.lane`; `za` on a part row; `:lane.head` | Phase 3 |
| B6 (TASK-313) | The heads of the built-in kinds through the public API: `curve` (today's automation lane row), `tempo`, the nest return row. The header halves of `draw_lane_row` and `draw_tempo_row` leave `arrange.tl` | Phase 4 |
| TK (TASK-314) | The piece `takes`; the head `take` of take lanes; the header half of `draw_take_row` leaves `arrange.tl` | Phase 4 |
| M4 (TASK-75.4) | The piece `stack` | Phase 4 |
| RD (TASK-316) | `head` on `paw.producers.define`; the pieces `bake` (the states) and `source`; the head `script` | Phase 5 |
| VD (TASK-320) | The head `video` | Phase 6 |
| utau (new ticket) | The head `vocal` with the singer's picture and `\s` | After HD |
| PR2 (TASK-307 design) | Uses the pieces `name`, `badge` and `value` and `ctx:line` for the names of the roll's lanes. It does not use the registry: the lanes of the roll are views of one clip's data, not lanes of the model | m-15 |

The prompt of TASK-322 names B6 as TASK-306. TASK-306 is A2. B6 is
TASK-313.

### 13.2 Tests (real keys) and golden screens

HD:

1. Golden screens of the default head at 60, 100 and 140 columns, with an
   audio part (input, sends, four rows) and a MIDI part: today's cells. The
   only change is `▌V Vocal` on the narrow screen.
2. A test head in a test extension (`rows = 3`, a `text`, a `<localleader>x`
   key): its golden screen; `:ext.unload` of the extension gives the default
   head; the row stays.
3. A head that fails: the default head on the row and one message, no stack
   trace, by real keys (`j` onto the row).
4. Lit flags: a head that shows no chips; `M` with the cursor on its row;
   the screen shows `M`; `K` says `muted`.
5. Head keys: `\x` on the head's row runs its action; `\x` on another row
   does not; `paw.heads.define` refuses `\t` with the message.
6. Height: a head that wishes for 3 rows; `j` and `k` step over it in one
   key; a change of its stamp that changes its wish below the cursor
   leaves the cursor's row on the same screen line.
7. Redraw: after `j`, `paw.heads.draws` grew by two.
8. Mouse: the tests of `arrange_mouse` pass with hits (a press on `M`, a
   drag of the meter, a press on `in`).
9. A golden screen of a head with a picture at `paw.opt.graphics = false`
   (half blocks), from a picture of 4 by 6 pixels in the test.

LA, B6, TK, RD, VD: a golden screen of each new head at the default width,
and the refusals of section 9 by real keys (`r` on a derived lane, `s` on a
lane that feeds no strip).

`tests/keys_constitution.lua` reads the keys of the registered heads. The
bench gets `bench/heads` (section 11).

## 14. Changes to ADR 0034

- Decision, bullet 1. Old: "A lane kind can give a head: a `render(lane,
  buf, ctx)` function, a number of rows it wants, and optional
  `<localleader>` keys. It is part of the editor subject of the kind
  (TASK-177). A part kind can give a head too." New: "A head is a record in
  the registry `paw.heads`, by name: `render(ctx)`, the rows that it
  wishes for, `<localleader>` keys, `describe` and `stamp`. A part kind, a
  clip kind, a producer and one lane can name a head. paw takes the first
  name that is registered, and the default head last. The user can replace
  each head, the default head too."
- Decision, bullet 2. Old: "name, kind badge, M S R I, fader, input, takes,
  bake state." New: "name, badge, chips, automation, bake, volume, meter,
  input button, route, sends, input, takes, stack, value, source, lanes,
  picture."
- Decision, bullet 3. Old: "`j` and `k` move by lane. `M`, `S` and `R` act
  on each head that shows them." New: "`j` and `k` move by row. `M`, `s`
  and `r` act on the part or the lane of the row, also when its head does
  not show them. The core shows a lit flag that a head does not show. A row
  that cannot do the action refuses it with a message."
- Decision, new bullet: "A part with one lane has one head for both (a
  merged row), as a track today."
- Consequences, bullet 2. Old: "A head that asks for more rows makes its
  lane taller." New: "A head wishes for rows. The core decides the height:
  the user's height first, one row on a crowded screen, else the larger of
  the auto height and the wish, at most 6."
- Consequences, bullet 3. Old: "A head is drawn again only when its lane
  changes." New: "A head draws again only when its subject, its stamp, its
  size or the selection changes. Meters move without a draw."
- Guard. Old: "A golden screen of the default head and of one head of a
  kind. The check of TASK-177 that a view reads no private type." New: "The
  golden screens of the default head at three widths stay the same as
  before the change. A golden screen of one head of a kind. A test of the
  lit flag. A test of the fallback when the extension unloads. The check of
  TASK-177 that a view reads no private type."
- Front matter: `tickets: [TASK-177, TASK-322]` → `tickets: [TASK-177,
  TASK-322, <HD>]`; `groma: []` → `groma: [arrange-view]` if that id exists.

## 15. Questions for the owner

| # | Question | Choices | Recommendation |
| --- | --- | --- | --- |
| Q1 | Where does a head register? | (a) in the editor subject of a clip kind (the ADR text); (b) a registry `paw.heads` that kinds, producers and lanes name | **(b)**. A part kind and a producer have no editor subject. The user can replace a head by name. |
| Q2 | Can a head hide a mute, solo or arm that is on? | yes; no, the core shows lit flags | **No**. A hidden mute costs the user time. |
| Q3 | Where do the keys of a head go? | flat on `<localleader>`, with a check; under `<localleader>h` | **Flat, with the check**. A head has one or two keys. A refusal at `define` names the clash. |
| Q4 | A part with one lane: one head or two rows? | one merged head; always a part row and lane rows | **One merged head**. Today's screens stay, and a song of tracks keeps its rows. |
| Q5 | How tall can a head be? | free; a wish, honored when the screen is not crowded, at most 6 | **A wish, at most 6**. The user's height wins. |
| Q6 | The singer's picture: where, and when off? | left of the head, at 22 columns and 2 rows or more; a picture also on narrow heads | **Left, only from the default width and 2 rows**; `paw.opt.head_pictures` turns it off. |
| Q7 | `s` and `r` on a lane row | solo the strip that the lane feeds, arm the lane; refuse both | **Solo the strip, arm the lane**, and the message names the strip. |
| Q8 | Can the user choose a head for one lane? | `:lane.head <name>` in the lane's meta; no | **Yes**, one undo step, kept in `lane.json`. |
| Q9 | Does the mixer strip use heads too? | now; later with the graph view (GV) | **Later**. The mixer becomes a filter of the graph. |

## 16. Risks

- HD moves the header and the mouse code. A test of the mouse that knows a
  column can break. The hits make the mouse follow the pieces, and the
  golden screens show the cells did not change.
- A head of an extension can be slow or fail. `paw.limit` and the fallback
  keep the view working, and the message tells the user.
- Pictures with the kitty protocol in a list that scrolls can leave old
  pictures in some terminals. The strips of `buf:strip` already handle
  this for the curve views. tmux gets half blocks.
- W1 renames the track to the part. HD after W1 saves a second rename.
- LA changes the rows of the arrange view. HD must merge before LA, so LA
  builds lane rows on heads and not on the old header code.
- The marks do not change, so the paused window keeps building. HD adds no
  change to `paw-scene`.
