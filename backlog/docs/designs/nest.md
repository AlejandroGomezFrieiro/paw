# Nests: views of the project, and saved nests (subprojects, folds, narrowing)

Author: NEST (design agent), 2026-11-21. Design only: no file of the repository changed.
Status: a proposal, **revision 3**. The owner answers section 6 before anyone builds it.

**Revision 2 (owner, 2026-11-21).** "Since subprojects/folds/nests are just different ways to view
the same thing, it is important that I can move around them freely. […] They are, unless saved
independently, just views." So the default nest is now a **view**: a scope over the one project
(any set of tracks x any time range). Data (a nest folder, nest clips, links, own tempo, freeze)
exists only when the user **saves a view independently**. What changed:

| Where | Revision 1 | Revision 2 |
| --- | --- | --- |
| Section 1 | the nest is data; C (time narrowing) a first step | **rewritten**: the scope (a view) is the model; saved nests are a later, optional step |
| Section 2 | A, B, C | kept; B is now "saved nest". A new column V (scope view) in 2.0 |
| Section 3 | — | **new**: the view model, free movement, folds as scopes shown in place |
| Section 4 | the design of nests | kept as the design of **saved** nests; keys moved (4.5 marked) |
| Section 5 | N0-N13 | **rewritten**: the view parts first (V1-V7), saved nests later (S1-S11); what the N1 agent changes |
| Section 6 | 12 questions | revised: answered or moved ones marked, new ones added |
| Section 7 | — | **new**: decisions |
| Keys | `zf` made a nest (data), `zd` unnested | `zf` makes a fold (a view, as in Vim), `zd` deletes the fold; saving and inlining are on `<Space>z` |

**Revision 3 (owner, 2026-11-21).** "One use case I see of a 'proper' subproject is if I want to
add a subproject that has different tracks than the main project. Say, a slow piano section inside
a main metal song, or a breakdown in electronic music. Let's refine the design to allow for views
and proper subprojects." So there are **two first-class things**, and one way to move between and
through them:

1. **Views** (the default): scopes over the one project (section 3, revision 2, unchanged).
2. **Subprojects** (proper ones): a section with **its own tracks** that the song does not have,
   its own devices and mix, and possibly its own meter and tempo, played in the song as one block.
   This is the data of revision 1 (section 4), now first-class: made new and empty with
   `<Space>za` / `:nest.new`, or by saving a view (`<Space>zw`).

What changed in revision 3: section 1 (one paragraph on subprojects), **new section 3.7**
(subprojects: what the song draws, outputs, relations, conversion, the 6/8 piano example, keys),
section 4's banner (it is the subproject's data now, not only a saved view), section 5.2 (the
subproject parts, reordered: own tracks and the return row first), section 6 (questions 18-23),
section 7 (the decision). Revision 2 is kept as `DESIGN.rev2.md`.

**Revision 4 (owner, 2026-11-21).** (1) "There should also be ways to promote a subproject to a
view, bring its tracks, clips, markers etc to the main project." → `<Space>zi` / `:nest.inline`
is renamed **`<Space>zp` / `:nest.promote`** ("promote a subproject to a view"), and **new section
3.9** lists exactly what comes back. (2) Nested regions ("a region might contain Verse A and
Verse B subregions, each with its own subregions … similar to track grouping"): **new section
3.8**, the decision **core**, by time containment, no change of the file format. Also: section 5.1
(parts R1, R2), section 6 (questions 24-30), section 7. Revision 3 is kept as `DESIGN.rev3.md`.

Words (revision 3): **view** or **scope** = a scope over the project. **Subproject** = the user's
word; **nest** = the same thing in commands and code (`:nest.new`, `paw.nest`), as the owner
accepted in revision 1. Section 6, question 18 asks whether commands should say `subproject`.

Read with: `scratchpad/media/DESIGN.md` (sources, bakes, kept bakes, the scheduler; M0-M3 are
merged), `scratchpad/clipkinds/DESIGN.md` (custom clip kinds), and in the repository
`docs/reference/narrowing.md` (`zn`/`zw`, `paw.scope`, `scope_rest`), `docs/reference/tempo.md`,
`docs/reference/project-files.md`, `docs/reference/routing.md`, `docs/reference/grammar.md`,
`runtime/lua/paw/scope.lua`, `runtime/lua/paw/groups.tl`.

The owner's requests, all covered here:

1. Work on a section (a 6/8 bridge in a 4/4 song) by itself in its own editor, and include it in
   the song. Study REAPER-like subprojects (A), a clip or track that holds a project (B), and
   anything simpler (C).
2. Turn a selection or a region into such a self-contained project, and back.
3. Along both axes: a time range of every track, a set of tracks over the whole song, and a
   rectangle of tracks x bars (and several rectangles).
4. (Revision 2) Move freely between track nests, project nests and selection nests: they are
   views, unless saved independently.

---

## 1. Summary and recommendation (rewritten in revision 2, a paragraph added in revision 3)

**One model: the scope.** A scope is a view of the one project: a set of tracks x a time
range, where either may be "all". The song is the scope of all tracks x all time. A group, a
track, a region, a visual selection or block, a group x a region: each is a scope. Scopes nest:
a scope entered inside a scope is the intersection, and its path is the breadcrumb
(`Song › Strings › Bridge`). A scope is shown in one of three ways, and these are the same
object:

- **entered** (focused): a window shows only the scope. This is today's narrowing (`zn`), now
  for any scope, in the current window, a split or a tab.
- **folded**: the scope is drawn in place, collapsed, in its parent's view: a group's rows into
  one row (today's `za`), a time range into one narrow column, a block into one cell.
- **open**: drawn in place as usual, with a thin frame when it is a named or folded scope.

So folds, narrowing and nests-as-views are one model with one registry (`paw.scope`), one set of
keys, and one undo tree. No track or clip moves anywhere; an edit in any view is an edit of the
project, and every other view shows it at once.

**The 6/8 example.** The meter is the song's map (`:timesig 6/8 at 17`, `:timesig 4/4 at 25`).
`znar` in the bridge region enters it: the ruler shows bars 1-8 in 6/8, the status line
`Song › Bridge 3.2 (19.2)`, the loop is the bridge, and the rest of the song plays, mutes or
rests as `scope_rest` says. A ritardando of the song is heard as it is: there is one tempo map.

**Free movement (Vim-like, by the key rule).** `zn{motion}` enters the scope that the motion or
text object covers (`znar` region, `znag` group, `znit` track, a visual block `zn`), `zw` goes up
one level, `zW` to the song, `]z` `[z` to the next or previous sibling (next region, next group,
the next block of the same size), `<C-o>` `<C-i>` through the jump list across scopes,
`<Space>zz` a picker of scopes, `<Space>zs` `<Space>zv` `<Space>zt` the scope in a split, a
vertical split, a tab. Folds use Vim's keys: `zf{motion}` makes a fold, `za` toggles one, `zd`
deletes one, `zR` `zM` open or close all, `zE` deletes all.

**Saved independently.** `<Space>zw` (`:scope.write [name]`) saves the scope as a **saved nest**:
the data of revision 1 (section 4): its tracks and clips move into `nests/<name>/`, the song gets
nest clips in their place, and the song sounds the same. `:scope.write ~/lib/bridge` writes a
standalone project folder instead (a copy, nothing moves). `<Space>zp` (`:nest.promote`) promotes a
saved nest to a view (its contents back into the song), and leaves a scope at the same place, so the view the user had is
still there. Links, own tempo, own meter (polymeter), freeze of a nest clip, a closed boundary,
`unused/nests` and sharing between songs apply only to saved nests.

**Subprojects with their own tracks (revision 3, section 3.7).** A ballad in a metal song or a
breakdown with its own synths is a **subproject**: its own tracks, devices and mix, none shared
with the song. `<Space>za` (`:nest.new Ballad 8 6/8`) adds one over the region or the next 8 bars:
the song gets **one row of its own** (the subproject's return track, which the song mixes like any
track) with **one block** over the section's time, and the cursor enters it. Inside, the user adds
tracks and plays them as in any project. It goes out as one stereo return by default, or as stems
(`:nest.outputs stems`: one return row per subproject track, grouped under its row). It follows the
song's tempo map by default (the slow tempo is a tempo change of the song, so the bars after it stay
in place), and may have its own meter and tempo. Entering, leaving, siblings, the jump list, the
picker and the breadcrumb are the same keys as for views: a subproject is a scope of kind `nest`.
`<Space>zp` promotes it to a view: its tracks become song tracks in a group with its name.

**Why.** The owner's point is right: for one song, a subproject, a fold and a narrowed tab show
the same notes. Making them views gives free movement, no copy, no stale audio, no second
truth, and no data migration when the user changes his mind. paw already has most of it: tabs
narrowed to a group, `scope_rest`, one undo tree for all tabs, group folds, relative bars on the
ruler. Saved nests stay for what a view cannot do: one section placed twice (a chorus edited
once), a section with its own tempo, a section shared between songs, and freezing a section.

**Prior art in one line.** REAPER renders subprojects (users like the CPU, hate the waits and the
stale audio); FL Studio, Kdenlive and Resolve link nested sequences; Blender enters a node group
with Tab and leaves with Ctrl+Tab; Pro Tools nests clip groups; Vim and Emacs fold and narrow. A
view-first model with optional saving is closest to Emacs's `narrow-to-region` plus Vim's folds,
with Blender's free enter and leave, and FL Studio's links only where the user asks for them.

Size: the view parts V1-V7 are one L and the rest S or M. The subproject parts S0-S12 (revision 3
order) come after,
in the order of section 5, and each is useful alone.

---

## 2. Comparison

*Revision 2:* the tables 2.1-2.6 are kept from revision 1. There, B is now the **saved nest**
(section 4), and C is the time-only first step of the view model. Table 2.0 is new: the view
model (V) against them. The keys in 2.4 and 2.5 are revision 1's (`zf`, `zd`, `<Space>rz`); section
3.4 and 4.5 give the keys now.

### 2.0 The view model (V) against A, B, C (new in revision 2)

| Question | A REAPER subproject | B saved nest | C time narrowing (rev. 1) | V scope view (rev. 2) |
| --- | --- | --- | --- | --- |
| What it is | a second project | data in the project | a tab of a time range | a view: any tracks x any time, nested, entered, folded or open |
| Shapes (time, tracks, rectangle, several) | items/tracks | all, one nest per rectangle | time only | all; several rectangles are several scopes, siblings by `]z` |
| Data change to enter | a new project | moves tracks and clips | none | none |
| 6/8 meter | child's own map | own meter (polymeter) | song's map | song's map, local bars |
| Ritardando across the boundary | no | `follow`: yes | yes | yes |
| Move between views | open and close projects | enter, leave | one level | free: in, up, top, sideways, jump list, picker, split, tab |
| In place | no | `za` on a nest row | no | folds are scopes drawn in place |
| Undo | two trees | one tree | one tree | one tree |
| Stale audio | yes | no (live), or `stale` when frozen | no | no |
| One section in two places | links via files | links | no | no (save it as a nest) |
| Own tempo, sharing, freeze | yes | yes | no | no (save it as a nest) |
| Same sound after the action | depends on the render | yes (per track) | yes (no change) | yes (no change) |
| Cost | L | S1-S11 | M | V1-V7 |

A = REAPER-like subproject (separate project folder, parent plays its render).
B = nest (tracks with their own timeline inside the project, placed by nest clips; this
design). C = time narrowing (a narrowed tab of a range; no new data). For B, "per track" is the
default layout of `zf` (the nest's tracks have no devices and play through the song's tracks);
"mix" is `zF` and the track shape (the nest has devices; one clip plays its mix).

### 2.1 Time, meter, tempo

| Question | A | B | C |
| --- | --- | --- | --- |
| The 6/8 bridge | the child has its own map (6/8); the parent's map in bars 17-24 is what the user writes there (4/4 by default: the parent's bars do not match the child's) | the nest has its own meter (6/8, copied from the song's map at creation, or written in it); the song's map is untouched; the two may differ (polymeter is allowed and `K` says so) | the song's map holds the 6/8; the narrowed tab shows it |
| Bar numbers inside | the child's, from 1 | the nest's, from 1. The status line also shows the song's place: `Song › Bridge 3.2 (song 19.2)` | the song's (`17|` goes to bar 17), or from 1 with `narrow_bars=local` |
| Bar numbers outside | the parent's | the song's | the song's |
| `17|` and relative bars | per project | per tab: the tab's timeline; `relativebar` counts the tab's bars | the song's, or local |
| Tempo | the child's own; the parent hears a render at the child's tempo | `follow` (default): the song's tempo at the clip's place, so a tempo change of the song changes the nest. `own`: the nest's map; the clip keeps its length in seconds (as an audio clip with `timebase=time`) | the song's |
| Ritardando across the boundary | no: two maps, the render is fixed | `follow`: yes, exact (one map). `own`: no, as in A | yes |
| Track-shaped child (shape 2) | own meter and tempo, which must be kept equal to the parent's by hand | meter and tempo `follow`: the nest has none of its own and shows the song's | not applicable (narrow to a group already exists) |

### 2.2 Files, media, versions

| Question | A | B | C |
| --- | --- | --- | --- |
| Where the child lives | a project folder: `song/subprojects/x/` or anywhere | `song/nests/<name>/` (`nest.toml` and `tracks/`), or a folder outside that the project refers to | no child |
| Media | the child has its own `media/`; copies unless told not to | the song's `media/` and `media.json` (one table, by hash); no copy | — |
| Save | two saves (child, then parent), the render on child save | one save, writes only changed files | — |
| `unused/` | the parent never moves the child | a nest that no clip uses goes to `unused/nests/<name>/` at save | — |
| Share between songs | yes, the strength of A | the nest folder outside: refer (no copy); the first edit makes it the song's own, as tracks and chains from outside today (`:nest.own` asks for it at once); `:nest.export` writes a standalone project | — |
| Git, merge | two projects, two histories in one repository | one project; a nest is files like a track; `projdiff` recurses into `nests/` | — |

### 2.3 Playback

| Question | A | B | C |
| --- | --- | --- | --- |
| Live or baked | baked (the render); live only in the child's tab | live by default; `:freeze` on a nest clip makes a kept bake (needs plugins, so kept in `media/baked/`) | live |
| Bake key | — (render on save) | BLAKE3 of the nest's canonical text, what the clip plays, the song's tempo slice over the clip (in `follow`), the rate, the plugin versions; window, gain, fades out of the key | — |
| Stale audio | yes, until the child is saved and rendered | never when live; a frozen nest says `stale` in `K` and the status line as a frozen track does | — |
| CPU | low in the parent (a file) | per track: the same as before (the song's devices); mix: the nest's devices run (or rest when frozen) | the same, or less with `scope_rest=frozen` |
| Latency | none in the parent | per track: none added; mix: the nest's delay compensation joins the song's graph | — |
| Rough preview while a bake runs | — | the live nest is the preview | — |
| Sample rate | the render's rate, converted | the engine's rate; a bake per rate | — |
| Export | plays the render | plays live or the frozen file, as the song does | — |
| Recursion | renders chain (child renders first) | nests in nests, expanded recursively; frozen inner nests play their files | — |
| Cycles (A in B in A) | REAPER: unclear | refused at the door (place, paste, import, unnest): "Bridge cannot hold itself: Bridge › Fill › Bridge". A cycle from a merge opens with the inner clip offline. Depth at most 8 | none |

### 2.4 Editing

| Question | A | B | C |
| --- | --- | --- | --- |
| Enter and leave | open the child project (a tab of its own); a second undo tree | `<CR>` or `zn` on a nest clip, `zw` to leave, `<C-o>` back; a tab narrowed to the nest | `<Space>rz` or `:narrow Bridge`, `zw` |
| The parent meanwhile | not edited in the child's tab | plays around the nest as `scope_rest` says (`play`: the song plays with the nest in its place, at the place you entered from) | the rest plays as `scope_rest` says |
| Breadcrumbs | tab names | `Song › Bridge › Fill` in the status line, and the tab name | `narrowed Bridge` |
| Undo | two trees; the parent step is "render again" | one tree, as narrowed tabs today; a step made in a nest is labelled `Bridge: …` | one tree |
| Live update of the parent | on child save | at once: one model | at once |
| Window frontend | the same tabs | the same scene: a scope is a tab field; the window draws the tab | the same |
| In-place edit | no | `za` on a nest row opens its tracks under it in the song's time (shape 2, and shape 1 at its place); edits there are edits of the nest | — |

### 2.5 Selections into nests, and back

| Question | A | B | C |
| --- | --- | --- | --- |
| What the user selects | REAPER: items or tracks | any arrange region: `ar`/`ir` (a region), `it`/`at` and `V` (tracks), `<Space>tg` groups and `za` folds (a group = its tracks), a visual block (rectangle), several blocks by repeating with `.` | a region (time only) |
| Clips at the edges | REAPER: whole items | cut at the edges, as `d` cuts | — |
| Devices, sends, buses | the child gets copies (the user rebuilds the routing) | per track (`zf`): stay in the song; the sound is the same to the sample. Mix (`zF`): copied into the nest; crossing routes are listed (section 4.7) | — |
| Automation in the range | moves | per track: track lanes stay (they are the song track's fader and devices); clip data moves. Mix: lanes in the range are copied into the nest | — |
| Tempo and meter of the range | the child gets the map | `follow` tempo; the range's meter becomes the nest's meter (6/8) | — |
| Markers and regions inside | — | move into the nest; the region that is the range itself stays in the song and names the instance | — |
| What stays in the song | one item on the first track | per track: one nest clip per row (one instance); mix: one new track with one nest clip | — |
| Same sound right after | depends on the render | per track: identical (the same events into the same devices); mix: identical when no route crosses the boundary | — |
| One undo step | yes | yes | — |
| Inverse | none built in | `zd` (one level), `zD` (recursive), `:unnest` | — |

### 2.6 Cost and fit

| Question | A | B | C |
| --- | --- | --- | --- |
| MIDI is the truth | the parent holds audio | the nest holds MIDI clips; the song plays them | unchanged |
| Plays without extensions | yes (a render) | yes (core) | yes |
| Core change | multi-project kernel or shelve-and-switch UX; render on save | model (nest, track tag, clip kind), sync expansion, scope, files | scope by time |
| Size | L (and a UX that the owner's prior art says users dislike) | about 11 parts, see section 4 | M |

---
---

## 3. The view model (new in revision 2)

### 3.1 A scope

```lua
-- runtime/lua/paw/scope.tl (scope.lua ported to Teal: it changes much)
--- What a scope is made from. Group and region scopes follow their source:
--- a track added to the group, or a region moved, changes the scope at once.
local enum ScopeKind "song" "group" "track" "tracks" "region" "range" "nest" end

local record Scope
   kind: ScopeKind
   id: integer             -- the group, track, region or saved nest
   tracks: {integer}       -- "tracks", "range": a fixed list; nil = all tracks of the parent
   from: number            -- "range": beats; nil = all time of the parent
   to: number
   name: string            -- shown in the breadcrumb; a region's or group's name by default
   parent: Scope           -- nil for the song
end
```

- **Resolution.** `scope.tracks(s)` = the scope's own tracks ∩ `scope.tracks(s.parent)`;
  `scope.span(s)` = its own time ∩ the parent's. Group: the group and its tracks at any depth
  (today's `contains`). Track: the track. Region: all tracks of the parent x the region's time.
  A block from a visual selection: `tracks` + `from`/`to`. A saved nest: its tracks and its own
  timeline (section 4). The results are cached per model generation, so a frame costs one
  lookup.
- **Nesting.** Entering a scope from inside a scope makes it a child: `Song › Strings ›
  Bridge` is the strings in the bridge. A child that is empty (no track or no time in common)
  is refused with the reason: "no track of Strings is in Drums".
- **A scope belongs to a window, not to a tab** (changed from today, where `tab.scope` holds a
  group id). Each window keeps a **scope stack** (its path) and its folds, as each Vim window
  keeps its folds. The tab shows the scope of its current window in its name. So a split can
  show the song beside the bridge, and two tabs the same scope.
- **Named scopes.** Groups, tracks, regions and saved nests are scopes by themselves. A block
  that the user wants to keep has a name: `:scope.name Strings in bridge`. Named scopes, folds
  and the scope stacks are **view state**: saved in `screen.json`, not in the project, never an
  undo step. A named block whose tracks were deleted shows the tracks that are left.

### 3.2 How the views show a scope

| View | In an entered scope |
| --- | --- |
| Arrange | only the scope's tracks, in their order and depth; only its time: `0`, `gg`, `G`, `$` stop at its edges; a clip that crosses an edge is drawn cut, with `‹` or `›` at the cut, and an edit of it is an edit of the whole clip |
| Piano roll | the clips of the scope's tracks that overlap its time; the time is limited as in the arrange |
| Mixer, device panel, session view, `paw://tracks`, pickers | the scope's tracks (as narrowing does today) |
| Ruler | **local bars**: bar 1 at the scope's start, from the song's meter map (6/8 shows as 6/8). A thin second row shows the song's bar numbers (`17`, `18`), on by default when the scope has a time range (`:set scopebars=local\|song\|both`, default `both`) |
| Meter and tempo marks | the song's `‖6/8` and `▾96` marks inside the scope, at local places |
| Track column | `number` counts the scope's tracks from 1; `relativenumber` as usual; a sign `›` on the first row says the window is in a scope |
| Status line | the breadcrumb: `Song › Strings › Bridge 3.2 (19.2)`: the path, the local place, the song's place |
| Ex | `%`, `t*`, `:g`, `:s` see the scope's tracks and time; bar numbers in commands are local (`:tempo 96 at 3`, `17|`), and `@19` names a song bar (section 6, question 13) |
| Text objects | `ie` is the entire scope; `ar` the region in the scope; `it` the track in the scope's time |
| Transport | `<Space><Space>` plays from the cursor; on entering, the loop is the scope's time when it has one (`:set scopeloop`, default on); `scope_rest` (`play`, `mute`, `frozen`) says what the tracks and time outside do, for the window in front |
| Window frontend | the same scene: a window's scope is part of the scene; the window draws its ruler rows, cuts and breadcrumb with no code of its own |

### 3.3 Folds are scopes shown in place

- **Track folds** (today): a group folded into its header. A fold of any scope with tracks and
  all time (a group, a named set of tracks) draws its rows as one row, with the scope's name.
- **Time folds** (new): a scope with a time range and all tracks of the parent (a region, a
  range) draws its time as one narrow column with its name and its length (`Bridge ▸ 8`). The
  song plays through it unchanged; the playhead jumps the column.
- **Block folds** (new): a scope with both draws one cell over its rows and time.
- `zf{motion}` makes a fold of what the motion covers: `zfar` the region (time fold), `zfag` the
  group (track fold), `Vjjzf` three tracks, a visual block `zf`. In Vim `zf` makes a fold too.
  The fold is a named scope (named after the region or group, else `Fold 1`).
- `za` toggles the fold at the cursor, `zc` closes (`zo` stays zoom out: paw has it), `zR` opens
  all, `zM` closes all, `zd` deletes the fold at the cursor (the scope, never the clips), `zE`
  deletes all folds of the window.
- **Group folds move to view state.** Today `group_folded` is in the group's `meta` (project
  data, an undo step). In the view model, folds are per window in `screen.json`, and a fold is
  not an undo step, as in Vim. (Section 6, question 14.)
- `zn` on a fold enters it; `zw` from inside comes back to the fold, closed as it was.

### 3.4 Moving freely

| Keys | Command | Effect |
| --- | --- | --- |
| `zn{motion}`, `{Visual}zn` | `:scope.enter`, `:narrow {name}` | Enter the scope that the motion covers, in this window: `znar` the region, `znag` the group, `znit` the track, `znie` (no change), a block. **`znn`** (the operator twice, as `dd`) enters the innermost scope at the cursor: a fold, a saved nest clip, else the group, else the track. `<CR>` on a fold or a nest clip enters it too. |
| `zw` | `:widen` | Up one level. At the song, nothing (and a message). |
| `zW` | `:widen!` | Up to the song. |
| `]z` `[z` | `:scope.next`, `:scope.prev` | The next or previous sibling: the same kind of scope inside the same parent. A region: the next region. A group: the next group at the same depth. A track: the next track. A block: the same tracks, the next stretch of the same length (`3]z` three on). A saved nest clip: the next clip of that nest. These are motions in the key rule's sense: they move, they change nothing. |
| `<C-o>` `<C-i>` | | Back and forward through the jump list. Entering, leaving and `]z` are jumps; a jump keeps its scope stack, so `<C-o>` comes back into the scope and to the place. |
| `<Space>zz` | `:scope.list` | A picker of scopes: the stack of this window, named scopes, folds, groups, regions, saved nests; select to enter. Also `<Space>fz`, as the find domain lists the other nouns. |
| `<Space>zs` `<Space>zv` `<Space>zt` | `:scope.split`, `:scope.vsplit`, `:scope.tab` | The scope at the cursor (or of the selection) in a new split, vertical split, tab. `:scope.tab` is what `zn` did before (section 5, V2). |
| `<Space>zn` | `:scope.name {name}` | Name the current scope (or the selection) so that the picker and `]z` find it again. |
| `<Space>za` | `:nest.new [name] [bars] [meter]` | Add a subproject with its own tracks (revision 3, section 3.7). |
| `<Space>zw` | `:scope.write [name\|folder]` | Save the scope independently (section 3.6). |
| `<Space>zp` | `:nest.promote` | Promote a subproject to a view: its contents back into the song (section 3.9). |
| `K` | `:info` | On a fold or in a scope: its path, its tracks and bars, its meter, and whether it is saved. |

- The `<Space>z` domain is new and free today. `z` already means folds and narrowing in paw
  (`za`, `zn`, `zw`), as in Vim.
- `]z` `[z`: paw's `[` `]` change the second value only as single keys; two-key `]x` motions
  exist already (`]'`, `['`), so `]z` follows them.
- Edits in any view are edits of the project, one action one undo step, in the one undo tree;
  every other window shows them at once (one model).

### 3.5 The 6/8 example under the view model

1. `:region Bridge` over bars 17-24, `:timesig 6/8 at 17`, `:timesig 4/4 at 25`: the meter is in
   the song's map, as now.
2. `znar` (or `<CR>` on the region's fold): the window shows bars 17-24 as bars 1-8 in 6/8;
   the thin row shows 17-24; the loop is the bridge; the status line says `Song › Bridge 1.1
   (17.1)`.
3. `znag` on the strings: `Song › Bridge › Strings`; `]z` goes to the brass, `zw` back to all
   tracks of the bridge, `]z` to the next region, `zW` to the song.
4. A tempo ramp in the song across bar 24 is heard in the bridge: one map.
5. If the bridge must play twice (a second time at bar 41), or keep 6/8 while the song's drums
   stay in 4/4 under it (polymeter), the user saves it: `<Space>zw` (section 3.6).

### 3.6 Saved independently

- **`<Space>zw`, `:scope.write [name]`**: save the scope as a saved nest inside the project. It
  is the action that revision 1 called `zf`: the scope's tracks (per track layout) and its clips
  in its time move into `nests/<name>/`, the song gets nest clips at the same place, and the
  song sounds the same (section 4.6). `<Space>zW`, `:scope.write! [name]`: the mix layout (the
  devices go along; revision 1's `zF`). The meter of a saved nest made from a time scope is the
  song's meter in the range, copied as its own, so that it stays the same when the nest moves
  or plays twice.
- **`:scope.write ~/lib/bridge`** (a path): write a standalone project folder of the scope (its
  tracks, clips, devices, the tempo and meter of the range, media collected by hash). Nothing in
  the song changes. `:import ~/lib/bridge` later places it as a saved nest that refers to the
  folder (section 4.3).
- **The way back: `<Space>zp`, `:nest.promote`** (revision 1's `zd`/`zD`; `:nest.promote!` also
  promotes the nests inside it): the nest's clips go back to the song (section 4.6), and a named
  scope with the nest's name stays over the same tracks and time, entered if the user was in the
  nest. So saving and promoting change the data, never what the user sees.
- Both are one undo step.
- **Only saved nests have**: links (one nest in two places, `:nest.unique`), own tempo
  (`:nest.time own`), own meter and polymeter, `:freeze` of a nest clip and its bake key, the
  closed boundary for sends and side-chains (section 4.7), `unused/nests/`, sharing between
  songs and `:nest.export`, nest kinds of extensions. A scope has none of them: it changes
  nothing, so it needs none.
- A saved nest is still entered and left as a scope (`kind = "nest"`): the movement keys of
  section 3.4 work the same on it.

### 3.7 Subprojects: sections with their own tracks (new in revision 3)

A **subproject** (a nest) is the data of section 4: tracks with their own timeline, kept in
`nests/<name>/`, placed in the song by nest clips. Revision 3 makes the case with **its own
tracks** the main one: the song has none of its tracks.

#### What the song draws: its own row (decided)

- A subproject made new has **one row of its own** in the song: its **return track** (`Ballad`),
  a usual song track whose content is the subproject's nest clips (`play = master`). The block
  spans the section's time on that row, with the name and a small view of what plays. This is the
  mix layout of section 4 (`NestPlay::Master`).
- Why a row of its own, not a block over a host track: the subproject's sound needs a fader, pan,
  sends and devices in the song's mix, and a host track's devices (the metal guitar's amp) would
  color it. A row of its own is also where the eye looks for "the ballad", and it is what REAPER's
  subproject item on its own track looks like.
- The **per track** layout (blocks over the song's own tracks, played through their devices) stays
  for a view saved with `<Space>zw`, when the clips came from those tracks and must sound the same.
- `za` on the return row opens the subproject's tracks under it **in place** (in the song's time:
  a view of the subproject, as a group fold shows a group); edits there are edits of the subproject.
- The return row can stay folded under a group, as any track.

#### Its outputs into the song

| Form | What the song gets | How |
| --- | --- | --- |
| **One stereo return** (default) | the return row: the subproject's master into a song track, with its own fader, pan, sends and devices | one nest clip per place, `play = master` |
| **Stems** (`:nest.outputs stems`) | one return row per subproject track (or per subproject group), grouped under the subproject's row (a group track with its name) | one nest clip per stem, `play = <track>`; the rows are made and named by the command, as `:device.output` makes tracks for a plugin's outputs |
| Back to one (`:nest.outputs master`) | the stem rows go, one row again | one undo step |

Stems let the song send the ballad's piano and strings to different song buses, or side-chain a
song compressor from one stem.

#### How the song's tracks and the subproject's tracks relate

- **None shared.** A track belongs to the song or to one subproject (`Track::nest`). The
  subproject's tracks are not in the song's lists, pickers, `%` or mixer, except when the user
  enters the subproject or opens its fold.
- **Tempo: read from the song, by default** (`follow`). A slow section is a tempo change of the
  song (`:tempo 66 at 33`): the song's map is the one truth, the song's bars after the section stay
  where they are, and a ramp into the section is heard. Inside a `follow` subproject, `:tempo`
  edits the song's map at the mapped place and says so ("the song's tempo at bar 33"). `own` tempo
  (`:nest.time own`) is for a block placed freely (a cue, a sound): its length in the song follows
  its seconds, and the song's map does not change.
- **Meter: its own** for a subproject made with a meter (`:nest.new Ballad 8 6/8`), else the
  song's. When the subproject fills the song's time (a section), `:nest.new` also writes the meter
  into the song's map over its span, and the song's meter back after it, so the song's bar numbers
  count the section's bars (bar 41 is 8 bars after bar 33). `meter=own` keeps the song's map as it
  is (polymeter). (Question 20.)
- **Key**: the song's `project.key`, unless the subproject sets its own (`:nest.key`); harmony and
  MIDI LSP read the subproject's when inside.
- **Buses and side-chains: no.** A subproject's track does not send to a song bus, and a song
  track does not side-chain from inside a subproject (the closed boundary, section 4.7, accepted
  in revision 1). The song does both **on the return rows**: the ballad's return sends to the
  song's Reverb; with stems, each stem does. A subproject that wants a reverb of its own has one
  inside.
- **Transport for plugins** inside: the subproject's bars (bar 1 at its start), the tempo of the
  place (section 4.4).

#### Making one, and converting

| From | To | Keys, command | What happens (one undo step) |
| --- | --- | --- | --- |
| nothing | an empty subproject | `<Space>za`, `:nest.new [name] [bars] [meter] [tempo=own]` | over the selection, the region of the cursor, or `[bars]` (default 8) from the cursor's bar: a return row below the cursor's track, one block, empty; the cursor enters it with one empty track (`paw.opt.nest_track`, default an instrument track like a new project's) |
| a view (scope) | a subproject, per track | `<Space>zw`, `:scope.write [name]` | the scope's clips move in; blocks over the song tracks they came from; the sound stays the same (section 4.6) |
| a view (scope) | a subproject, its own row | `<Space>zW`, `:scope.write! [name]` | the scope's clips, and copies of the devices and lanes of its tracks, move in; one return row; crossing routes are listed (section 4.7) |
| a subproject | a view over song tracks (promote) | `<Space>zp`, `:nest.promote` (`!`: the nests inside too) | own row: its tracks become song tracks in a **group** with its name, at the return row's place; the return row's devices, fader and sends become the group track's (after the subproject master's devices); per track: the clips go back to their rows. A named view stays over the same tracks and time |
| a subproject | a standalone project | `:nest.export <folder>` | a project folder, nothing changes in the song |
| a project folder | a subproject | `:import <folder>` | a subproject that refers to the folder; its own copy at the first edit |

- Promoting an `own`-meter subproject writes its meter into the song's map (question 8 of revision
  1). Promoting an `own`-tempo subproject writes its tempo over its span into the song's map, so
  that the song keeps its sound and the notes keep their beats; the message says so (question 21).
- One subproject placed twice (the breakdown at bar 49 and bar 97) is one subproject with two
  blocks on its row (links, accepted in revision 1); `:nest.unique` separates them.

#### The 6/8 piano section, end to end

The song: metal, 4/4, 180 BPM. Bars 33-40 are a slow piano and strings section in 6/8.

| Step | Keys | What the user sees |
| --- | --- | --- |
| 1. Go to bar 33 | `33|` | the cursor at bar 33 |
| 2. Clear the metal tracks there, if they have clips | `v8W` then `x`, or `dar` in a region | the song's tracks are empty in bars 33-40 |
| 3. Add the subproject | `<Space>za`, then type `Ballad 8 6/8` (or `:nest.new Ballad 8 6/8`) | a row `Ballad` with a block over bars 33-40; the song's ruler shows `‖6/8` at 33 and `‖4/4` at 41; the window enters it: `Song › Ballad 1.1 (33.1)`, bars 1-8 in 6/8, one empty instrument track |
| 4. The slow tempo | `:tempo 60` (in the subproject: "the song's tempo at bar 33"), and `:tempo 180 at 9` ("at bar 41") | one tempo map; `:tempo.ramp` before bar 33 makes a ritardando into the section |
| 5. The piano | `<Space>da`, choose a piano; enter notes (`i`, the piano roll, `<CR>` on the clip) | notes in bars 1-8 of the subproject; `<Space><Space>` plays the loop of the section |
| 6. The strings | `:track.add Strings`, `<Space>da` a string instrument, notes | two tracks in the subproject; the song's metal tracks are not in its lists |
| 7. Hear it in the song | `zw` (or `<C-o>`), then `<Space><Space>` before bar 33 | the song plays the metal, then the ballad from the `Ballad` row, then the metal again |
| 8. Mix it in the song | on the `Ballad` row: `+` `-` (volume), `<Space>ts` Reverb | the ballad goes to the song's Reverb at the return |
| 9. Stems, if wanted | `:nest.outputs stems` | rows `Piano` and `Strings` under the `Ballad` group row |
| 10. Look inside in place | `za` on the `Ballad` row | the piano and strings under it, in the song's time |
| 11. Move between | `]z` (the next subproject or view: the breakdown), `<Space>zz` (the picker: views and subprojects), `zW` (the song) | the same keys as for views |
| 12. Back to song tracks, if wanted | `<Space>zp` on the block | `Piano` and `Strings` become song tracks in a group `Ballad`; a view `Ballad` stays over them |

#### Navigation: one model

A subproject is a scope of kind `nest` (section 3.1). So:

- `znn` or `<CR>` on a block enters it; `zw` goes up; `zW` to the song; `]z` `[z` go to the next or
  previous sibling (another subproject on the song's level, another block of the same subproject,
  or a view of the same kind); `<C-o>` `<C-i>` keep the stack; `<Space>zz` lists views and
  subprojects together, marked (`view`, `nest`); `<Space>zs` `zv` `zt` open it in a split or tab.
- Views go **through** subprojects: inside `Ballad`, `znag` on its strings group is `Song ›
  Ballad › Strings`; a view of the song (a region) does not include the subproject's tracks
  unless the user enters the subproject or opens its fold.
- The breadcrumb marks a subproject: `Song › ⧉Ballad › Strings 2.1 (34.1)`.
- One undo tree for the song, its views and its subprojects (revision 1's answer).

### 3.8 Nested regions (new in revision 4)

A region can hold regions: `Chorus 2` holds `Verse A` and `Verse B`, each with its own parts. This
is the time axis of what groups are on the track axis, and it gives the scope model its tree of
time scopes.

#### Core or extension: core (decided)

AGENTS.md rule 5: "A feature that is not needed by all users is an extension. Core changes for an
extension are generic." `about-core-and-extensions.md`: the core is "what an extension could not
add", "the modal keys, the picker, the views", and "two extensions that need the same thing do not
each keep a copy".

| Test | Answer |
| --- | --- |
| Do regions already live in the core? | yes: `runtime/lua/paw/markers.tl`, `ir`/`ar`, `]'` `['`, `<Space>r`, `:render.regions` |
| Does nesting add data? | no: it is a reading of the regions that exist (containment); the files do not change |
| Who needs it? | the core's own scope model (3.1): a region scope's children, `]z`, the picker tree, time folds by level (3.3), breadcrumbs. An extension cannot change how the core's text objects, `]z`, folds and picker read regions without a copy of each |
| Cost to a user with flat regions | none: flat regions are a tree of depth 1 and behave as today |
| What stays for extensions | the look (ruler registry, glyphs, styles), and tools that **make** regions (song-form analysis, an arrangement template) |

So nested regions are **core**, as groups are, and generic: no musical meaning is built in.

#### Explicit parent or time containment: containment (decided)

- Track groups need an explicit parent because tracks have no geometry. Regions have one: a time
  range. A region whose range is inside another's **is** its child. An explicit `parent` field
  could say "Verse B is in Chorus 2" while Verse B lies outside Chorus 2: two truths.
- **The rule.** The parent of a region is the smallest region that contains its range (start ≥,
  end ≤). Two regions with the same range: the one made first (smaller id) is the parent. A
  marker (no length) belongs to the smallest region around it.
- **Overlaps that do not nest** (Intro 1-9, Pre 7-12): both are children of the smallest region
  that contains both (or top level). They are siblings; the region lane draws the overlap; `ar`
  at bar 8 takes the one that starts later (the innermost by start), and `K` lists both.
- The tree is computed, cached per model generation, and costs O(n log n) for n regions.

#### Data and files

No change. Regions stay in `project.meta.markers` (`id`, `beat`, `name`, `length`, `color`), in
`meta.json`. `paw.markers` gains `parent(id)`, `children(id)`, `depth(id)`, `tree()`, `path(beat)`
(the regions around a beat, outermost first). In a subproject, regions are in the nest's
`meta.markers`, in its own beats (section 4.2).

#### Editing

- **Moving a parent moves its children** (and the markers inside), in the same undo step: the
  children are those inside it when the move starts. `:marker.move`, the drag in the window, and
  `:region.move Chorus 2 +8` do this. `:region.move!` moves the region alone.
- **Resizing a parent** never changes a child. A child that is no longer inside becomes a sibling;
  the message says so ("Verse B is no longer inside Chorus 2").
- `:region` over a selection inside a region makes a child, as before (no new command).
  `:region.remove` removes one region; its children move up one level. `:region.remove!` also
  removes the regions inside it (never clips).

#### Text objects and motions

| Keys | Effect |
| --- | --- |
| `ir` `ar` | the innermost region at the cursor, on this track or on every track (as today, which is the innermost when they nest) |
| `2ir` `2ar` | the region around that one (its parent); `3ar` the next level out. As Vim's `2a(` takes the second block around the cursor |
| `]'` `['` | the next start of any marker or region (as today) |
| `]z` `[z` in a region scope | the next or previous sibling region (the same parent) |
| `]r` `[r` | (new) the next or previous region at the same level as the innermost at the cursor, outside a scope too |

#### The scope model

- A region scope's children are its subregions. In `Song › Chorus 2`, `znar` at the cursor
  enters `Verse B`: `Song › Chorus 2 › Verse B`. `zw` goes up to `Chorus 2`, `]z` goes to
  `Verse A`'s sibling, `zW` to the song.
- `znn` enters the innermost scope at the cursor (3.4), so in a region it enters the innermost
  region not yet entered.
- The picker (`<Space>zz`, `<Space>fr`) lists regions as a tree, indented, with the path in the
  preview.
- **Time folds by level.** `zfar` folds a region (3.3). As Vim's `foldlevel`: `zm` closes one more
  level of region folds, `zr` opens one, `zM` closes all, `zR` opens all. With `zm` once, every
  top-level region shows as one column; with `zm` twice, their children too. `za` toggles one.
  (`zm`, `zr`, `]r` and `[r` are free today: checked in `defaults/keys.lua` and the extensions.)

#### The ruler and the region lane

- The region lane draws one row per level (`regionlevels`, default 3; deeper regions draw on the
  last row with a `+` mark). A child is drawn under its parent, as tracks are under their group.
- The drawing goes through the `paw.ruler` registry of the track column work: a part `regions`
  with `depth`, `folded`, `children` for each region, the fold glyphs of the track column's group
  folds (`▾` `▸`) and styles `RulerRegion1`, `RulerRegion2`, `RulerRegionDeep`. An extension
  restyles or replaces it as it does the bar numbers (`paw.ruler.set("regions", …)`).
- The window frontend draws the same scene rows.

#### Rendering regions

`<Space>rR`, `:render.regions out` renders **every** region, as today, and names each file by its
path: `03 Chorus 2 - 01 Verse A.wav` (the number is the place among its siblings). `level=1`
renders the top level only, `level=leaves` the regions with no child, `level=2` one level.
`:render out.wav range=Verse A` takes any region by name, or by path `range=Chorus 2/Verse A`
when names repeat.

#### Regions and subprojects

- Saving a view as a subproject moves the regions inside into the nest (accepted in revision 1),
  with their tree; the region that is the range stays in the song and becomes the subproject's
  place in the tree.
- A subproject's regions are a tree in its own timeline; entering the subproject shows it.
- Promoting a subproject brings its regions back at song positions; they become children of the
  region over the subproject's span (made by promote if there is none), so the tree is
  `Song › Ballad › Intro`, the same path as inside the subproject before.

### 3.9 Promote a subproject to a view (new in revision 4)

`<Space>zp`, `:nest.promote` ("promote the subproject to a view") on a block. One undo step. The
subproject's contents become song data, and a **view** over them takes the subproject's place in
the navigation, so the user does not lose his place. `:nest.promote!` also promotes the
subprojects inside it. The name `promote` replaces revision 3's `inline` (no compatibility is
needed before a release): it says what the user gets, a view.

What comes back into the song:

| Part of the subproject | In the song after promote |
| --- | --- |
| Tracks | song tracks, in a **group** named after the subproject, at the place of its return row (own-row layout); per-track layout: no new tracks, the clips go back to the rows the blocks were on |
| Clips | on those tracks, at song positions: `follow` time is a shift by the block's start minus its offset; `own` time is a mapping through seconds (notes keep their beats when the tempo is written into the song, below); cut at the block's window |
| Markers and regions | at song positions, as children of a region named after the subproject over its span (made if there is none) (3.8) |
| Automation | each track's lanes, at song positions; the master's lanes go to the group track; when the return row also has a lane for the same target, the two combine (dB added for volume) into the group track's lane, and the message says so |
| Devices and their state | the same instances, moved: no plugin reloads (ids are kept, as a reload of the project keeps plugins that did not change). The subproject master's devices go first on the group track, then the return row's |
| Fader and pan | the group track's fader is the master's plus the return row's (dB added); pan: the return row's |
| Sends and returns | sends inside the subproject stay (now between song tracks of the group); the return row's sends become the group track's; with stems, each stem row's devices and sends go to its track, and a song side-chain from a stem row now listens to that track |
| Tempo | `follow`: nothing to do (one map). `own`: the subproject's tempo map is written into the song's over its span, and the song's tempo comes back after it (question 21) |
| Meter | its meter into the song's map over its span, and the song's back after it (question 8) |
| Key | when it differs from the song's, kept on the promoted region (`region.key`), as `paw.harmony` and the language servers can read a key per region later; the message says so (question 27) |
| Named scopes and folds | translated to song positions and kept in `screen.json`, under the new view |
| Undo history | nothing to merge: there is one undo tree for the song and its subprojects (revision 1). Promote is one step; `u` makes it a subproject again |
| The subproject itself | stays while other blocks play it (links); the message says "Ballad still plays at bar 97". With no block left, it goes to `unused/nests/` at save |

**The view that remains** is a scope of the group's tracks x the region's time (`Song › Ballad`):
it is in the picker, `]z` finds it among its siblings, and when the window was inside the
subproject, it is now inside the view at the same place.

**Round trip.** Promote, then save the view again (`<Space>zW` for an own-row subproject,
`<Space>zw` for a per-track one) gives the same project: the same canonical project text with ids
mapped, and the same render. A test does both, for a subproject with two tracks, regions, a lane
on the return row, and own meter.

### 3.10 What changes in core for the view model (and nested regions)

| Where | Change |
| --- | --- |
| `runtime/lua/paw/scope.lua` → `scope.tl` | the `Scope` record, resolution, the stack per window, siblings, named scopes, folds |
| `paw.layout` (windows, tabs) | a window keeps its scope stack and folds; the tab's name follows; `screen.json` saves them |
| `paw.groups` | `group_folded` moves from `meta` to view state; `rows()` takes the window's folds |
| arrange, roll, ruler, track column, status line | the views read the window's scope (they read the tab's today), local bars, the second ruler row, cuts, time folds, breadcrumbs |
| `paw.markers` (`markers.tl`) | the region tree (3.8): `parent`, `children`, `depth`, `tree`, `path`; moves of parents |
| `defaults/keys.lua` | `zn` becomes an operator (`znn` for the old `zn`), `zw` `zW` `]z` `[z` `zf` `za` `zc` `zd` `zE` `zR` `zM`, `ig`/`ag` text objects (the group: free today), the `<Space>z` domain |
| keymap jumps | a jump keeps the window's scope stack |
| Ex | ranges and bar numbers in the scope; `@N` for a song bar |
| scene | the window's scope, its ruler rows and folds, for both frontends |
| Rust | nothing for V1-V7 (time folds skip in the view, the engine plays as now); `scope_rest=frozen` exists |

---

## 4. Subprojects (nests): the data (revision 1's design; revision 3: subprojects made new or from a view)

*Revision 3:* this section is the data of a **subproject** (a nest), made new with `<Space>za`
(section 3.7) or from a view with `<Space>zw`. *Revision 2:* this section is kept as the design of a **saved** nest: what `<Space>zw`
(`:scope.write`) makes of a scope. Where it says "nest", read "saved nest". Its keys changed
(4.5). Its own view parts (entering, `zw`, breadcrumbs, the nest ruler in 4.8, the undo in 4.9)
are now the scope's (section 3): a saved nest is entered as a scope of kind `nest`.

### 4.1 Words

- A **nest** is a set of tracks with its own timeline. The project's top level is the **song**.
- A **nest clip** places a nest on a song track (or on a track of another nest).
- An **instance** is the nest clips of one nest that share a start, length and offset on several
  rows. It is drawn as one block and moved as one (`>`, `<`, `d` on one clip of it act on all of
  it; `gv` style selection takes all of it).
- **Per track** layout: each nest clip plays one track of the nest, whose events go through the
  song track's devices. **Mix** layout: one nest clip plays the nest's mix (its master).
- A nest's time is **follow** (the song's tempo at the clip; default) or **own**. Its meter is
  **follow** (the song's map; default for a nest of whole tracks) or **own** (default for a
  nest of a time range).

### 4.2 Data model (Rust, paw-core)

Nest tracks live in the project's flat track list, tagged with their nest. This is how narrowed
tabs already work (a scope filters the one list), so every existing API, view, command, device
host, undo and save path works on nest tracks with no "which project" parameter. A full
`Arc<Project>` per nest was considered: it is cleaner on paper, but every `paw.api` function
would need a project argument, and Ardour's maintainers call two sessions in one process "a
major re-engineering task" (sources). The tag gives the same behavior for far less change.

```rust
/// A nest's own id, never reused in the project.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct NestId(pub u64);

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Nest {
    pub id: NestId,
    pub name: String,
    /// Beats (quarter notes) from its start to its end.
    pub length: f64,
    pub tempo: NestTempo,
    pub meter: NestMeter,
    /// The track of the nest's mix (its master): devices, fader. Its id is a usual track id.
    pub master: Id,
    /// The order of its tracks (tracks with `nest == Some(id)` are its own).
    pub order: Vec<Id>,
    /// An extension's kind of nest ("drums.pattern"); None for a plain nest.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(default)]
    pub meta: Map<String, Value>,         // markers and regions: meta.markers, as the song
    /// A nest folder outside the project that this nest is read from (as Track::source).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<PathBuf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin: Option<PathBuf>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "mode", rename_all = "lowercase")]
pub enum NestTempo {
    /// The tempo of the place where each clip plays it. The map is kept for `own` and export.
    Follow { kept: TempoPoints },
    Own(TempoPoints),
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "mode", rename_all = "lowercase")]
pub enum NestMeter { Follow, Own(Vec<SigChange>) }   // Own: at least one change, at beat 0

// Project gains:
pub nests: BTreeMap<NestId, Arc<Nest>>,
// Track gains:
#[serde(default, skip_serializing_if = "Option::is_none")]
pub nest: Option<NestId>,

// ClipContent gains a built-in kind:
Nest {
    nest: NestId,
    /// Beats into the nest where the clip starts (trim and slip change it).
    #[serde(default, skip_serializing_if = "is_zero")]
    offset: f64,
    play: NestPlay,
},
pub enum NestPlay { Track(Id), Master }
```

- `Clip.looped`, `loop_length`, `loop_start`, `muted`, `fade_in/out` apply as for MIDI clips: a
  looped 1-bar nest is FL Studio's pattern clip.
- `TempoMap` gets a constructor for a nest timeline: `TempoMap::nest(song, clip, nest)` maps the
  nest's beat `b` to the song's beat `clip.start + (b - offset)` in `follow`, and through
  seconds in `own`. Bars come from `NestMeter`. This is the one place that converts.
- Invariant, checked in `Project::check` (as other invariants): the nest graph (nest → nests of
  its clips) has no cycle and is at most 8 deep; every `NestPlay::Track` names a track of that
  nest; a nest track's output, sends and side-chains stay inside its nest (section 4.7).

### 4.3 Files

```text
song/
├── project.toml            the song (unchanged; tracks with no nest)
├── media.json, media/      one table for the song and every nest
├── tracks/…                the song's tracks; a nest clip is a line in track.json
├── nests/
│   └── Bridge/
│       ├── nest.toml       id, name, length, tempo and meter (mode and points), kind, order, master
│       ├── meta.json       its markers and the data of extensions, if any
│       ├── master/         its mix track (devices, fader), as a track folder
│       └── tracks/Keys/…   its tracks, as track folders (clips/, devices.json, automation/)
└── unused/nests/…          a nest that no clip uses, at save
```

- Nests are flat under `nests/` even when one holds another: moving a nest clip between nests
  changes one line, and git shows a rename as a rename. Names follow the track-folder rule.
- Media paths stay relative to the project folder (`media/take1.wav`), so a nest track folder
  reads the song's media with no copy.
- A nest folder outside (`:import ~/lib/bridge`) is a full project folder or a `nest.toml`
  folder; the nest refers to it (`source`). The first edit makes it the song's own copy, says so
  once, and `origin` keeps the path (the rule of tracks from outside). Its media are named by
  hash in `media.json`; `:collect` copies them.
- `:nest.export ~/lib/bridge` writes a standalone project (`project.toml` from `nest.toml`; the
  `follow` maps resolved from the first instance), with its media collected by hash.
- `:e song/nests/Bridge` opens the song and enters Bridge.

### 4.4 Playback

**Sync expands nest clips; the engine gains nothing for the default layout.**

- **Per track, pass mode.** A nest track with no devices, unity fader and pan, and no lanes has
  no sound of its own: its clips are events. Sync places them, mapped by `TempoMap::nest` and
  cut at the clip's window, as regions on the **host** song track. They play through the host's
  devices, fader, sends and lanes exactly as clips placed there would. This is why `zf` sounds
  the same to the sample.
- **Chain mode.** A nest track with devices (or a fader, pan or lanes of its own), and the nest
  master for `play = master`, is an engine track. Sync creates one engine track per pair (nest
  track, host track), places its clips per instance, and routes its output into the host
  track, as a track output into a bus works today. Two instances on one host share it. A nest
  placed on two hosts runs its devices twice (`K` says so). Tails ring past the clip's end; a
  muted nest clip mutes its events, not tails already playing.
- **Transport for plugins.** Devices on nest tracks get the nest's bar and position (bar 1 at
  the nest's start), the tempo of the place (`follow`) or the nest's (`own`). Today the
  engine has one map for all tracks; it gains a per-track transport offset and meter. This is
  the one engine change (part N7).
- **Freeze.** `:freeze` on a nest clip renders what that instance plays (with tail, as track
  freeze) through the bake scheduler. Key: `BLAKE3("paw.nest/1" ‖ canonical nest text, nests
  inside it by their keys ‖ play ‖ tempo slice over [offset, offset+length+tail] in follow ‖
  rate ‖ plugin names and versions)`. Kept in `media/baked/` (needs plugins: kept, per the media
  design). Instances at places with the same tempo share one bake. A frozen clip plays the
  file; the nest's devices rest when no live clip uses them. While the bake runs, the live nest
  plays (the rough preview). An edit of the nest marks it stale; `K` and the status line say so.
- **Recursion.** A nest clip inside a nest expands relative to its parent clip. A frozen inner
  nest plays its file, and its key is an input of the outer key (keys chain).
- **Export and render** play what the song plays.

### 4.5 Keys and commands (terminal first)

*Changed in revision 2:* `zf` `zF` `zd` `zD` and `<Space>cn` `<Space>cN` `<Space>cu` are no
longer nest keys. `zf`/`zd` make and delete folds (3.3). Saving is `<Space>zw` (per track) and
`<Space>zW` (mix) on a scope, promoting is `<Space>zp` (`:nest.promote`, `!` for the nests inside),
and entering is the scope keys of 3.4 (`znn`, `<CR>`, `zw`). `<Space>rz` is dropped
(`znar`). The rest of the table holds, with those keys replaced.

| Keys | Command | Effect |
| --- | --- | --- |
| `zf{motion}`, `{Visual}zf`, `<Space>cn` | `:nest [name]`, `:'<,'>nest` | Nest what the motion or selection covers, per track. `zfar`: the region on every track (shape 1). `zfit`, `Vjjzf`: the tracks over the whole song (shape 2 per track). A block: a rectangle (shape 3). `<Space>cn` in normal mode nests the region of the cursor on every track. Asks for the name (default: the region's name, else `Nest 1`). |
| `zF{motion}`, `{Visual}zF`, `<Space>cN` | `:nest! [name]` | The same, mix layout: devices, lanes and fader go into the nest; one new song track plays its mix. On a group header (`zFat`): the group becomes a nest track (shape 2). |
| `<CR>`, `zn` on a nest clip | `:nest.enter [name]` | Enter the nest: a tab narrowed to it, the cursor at the place under the song's cursor. |
| `zw`, `<C-o>` | `:widen` | Leave to the tab entered from. |
| `za` on a nest row | `:track.fold` | Open or fold its tracks under it, in the song's time (edit in place). |
| `zd` | `:unnest` | Put the nest clip's contents back in the song (this instance). |
| `zD` | `:unnest!` | The same, and unnest the nests inside it. |
| `<Space>cu` | `:unnest` | As `zd`. |
| `K` | `:info` | `nest Bridge · 6/8 · 8 bars · follows the tempo · 4 tracks · 2 instances · live`. |
| | `:nest.list` | The nests, their instances and the unused ones; select to enter. |
| | `:nest.rename`, `:nest.time follow\|own`, `:nest.meter follow\|6/8` | One undo step each. |
| | `:nest.unique` | Make the instance under the cursor a nest of its own (FL Studio's "make unique"). |
| | `:nest.own`, `:nest.export dir`, `:import dir` | Section 4.3. |
| | `:freeze`, `:unfreeze` on a nest clip | Section 4.4. |
| `<Space>rz` | `:narrow Bridge` (a region name) | Part C: narrow the tab to the region's time. |

- The key rule holds: no motion changes; `zf`, `zF`, `zd`, `zD` are free today (checked in
  `defaults/keys.lua`), `za`, `zn`, `zw` keep their meaning and extend to nests. In Vim `zf`
  makes a fold and `zd`/`zD` delete one or nested ones: the same mnemonic.
- `.` repeats `zf` with the same motion: nest the next rectangle.
- Several rectangles: each `zf` makes one nest. A rectangle whose music equals an existing
  nest's is not detected (no guessing); `yar` then `p` copies instances, which link.
- `p` of a yanked nest clip links (same nest). `:nest.unique` separates.

### 4.6 Nesting a selection, and unnesting

`paw.nest.make(region, opts)` (Teal, `runtime/lua/paw/nest.tl`) over a block of rows
`r0..r1` and beats `c0..c1` (a line selection: `c0 = 0`, `c1` = the song's length), as one
undo step (`api.batch`):

1. Make the nest: name, `length = c1 - c0`. Tempo `follow`, with the song's map in the range
   kept (for `own` and export). Meter: for a whole-song range `follow`; else `own` with the
   song's meter at `c0` and its changes in the range, shifted. If `c0` is not a bar start, bar 1
   of the nest starts at `c0`, and the message says so.
2. For each selected row with clips in the range, a nest track of the same name and colour.
   Clips are cut at `c0` and `c1` as `d` cuts them, and moved into it, shifted by `-c0`. Per
   track: no devices, unity fader (pass mode). Mix (`zF`): a copy of the row's devices and
   states, fader, pan, and its lanes in the range; a group row in the selection becomes a group
   inside the nest with its members.
3. Markers and regions strictly inside move into the nest. The region that is the range stays
   in the song.
4. In the song: per track, a nest clip on each of those rows `[c0, c1)`, `play` = its nest
   track (one instance). Mix: one new track named after the nest at the first row's place, with
   the common output of the rows (the master when they differ, with a message), and one nest
   clip `play = master`.
5. Message: `nested 4 tracks, bars 17-24, as Bridge (6/8)`, and in mix layout the list of
   routes that changed (4.7).

`paw.nest.unnest(clip, { deep })`, one undo step:

- Per track: the nest track's clips in the window go back to the host row, cut at the window,
  mapped to song time (`own` time: notes retimed through both maps; audio by seconds).
- Mix: the nest's tracks come back as song tracks in a group named after the nest, output to
  the host track's output; the host track goes when it held only that clip.
- Markers come back. If the nest's meter differs from the song's over the span, the song's map
  gets the nest's meter there and the song's meter back after it, and the message says so.
- Nest clips inside stay nest clips, unless `deep` (`zD`).
- The nest stays while other clips use it; with none, it goes to `unused/` at save.
- `zf` then `zd` gives back the same project (ids aside); a test checks it.

### 4.7 Tracks, groups, folds, VCAs and sends at the boundary

The boundary of a nest is closed for audio, so that a nest is self-contained and exports:

- A nest track's output, sends and side-chains go only to tracks of the same nest. Its master
  goes into the host track. A song track may not send into a nest.
- Per track layout crosses nothing: the devices, sends, buses, VCAs and groups of the song
  tracks stay where they are and act on the nest's events.
- Mix layout (`zF`): a send from a moved track to a bus that is also in the selection moves
  with it. A send to a bus outside becomes a send of the nest's host track to that bus at the
  same level, which is exact only when one track sent; the message lists each such change, and
  `:render` before and after differ only there. A side-chain from outside is refused with the
  route named ("Comp on Bass listens to Kick: nest Kick too, or use `zf`").
- VCAs are control, not audio. A song VCA over a moved track moves to the host track in mix
  layout (message), and stays as it is in per track layout.
- Groups: a selection of a group (`zFat` on its header) makes the group the nest (shape 2): the
  song keeps one track with the group's name; `za` on it opens the nest's tracks in place, as
  the group fold did. A group inside a nest is a usual group there.
- Track folds (`za`) fold nest rows like groups. Time folds (planned: collapse bars in the
  arranger) are display only; a folded time range shows the instances in it as one column. A
  nest is data, a time fold is a view: they do not replace each other.

### 4.8 Views and the scene

- A narrowed tab's `scope` gets a time range and an optional nest: `{ group = id }` today,
  `{ range = {c0, c1} }` (C), `{ nest = id, from = clip }` (B). `paw.scope.tracks()` returns the
  nest's tracks; every view that uses the scope (arrange, mixer, device panel, session view,
  `paw://tracks`, pickers, Ex ranges, `:g`) works unchanged.
- The song scope hides nest tracks: `paw.scope.tracks()` of the song is the tracks with no nest.
  Core functions that list tracks for the user (`track_list` for pickers and `%`) go through
  the scope; `api.track_list` gets a `{ all = true }` for scripts that want every track.
- The arrange draws an instance as one block over its rows (a frame, the nest's name once, a
  `⧉` mark in the clip letter), and inside each clip a small view of the notes it plays. The
  ruler of a nest tab draws the nest's bars, and a thin second row with the song's bars
  (`17`, `18`) when `follow`.
- The status line: `Song › Bridge 3.2 (song 19.2)`; with `own` tempo: `Bridge 3.2 · own tempo`.
- The window frontend draws the same scene: a tab with a scope. No window-only code.

### 4.9 Undo

One undo tree, as narrowed tabs have now: one action is one step wherever it is made. Step
labels name the nest (`Bridge: add note`), so `:undolist` and the undo tree read well. Undo in
the song tab can undo a nest edit, and the tab follows the change (`g;` goes there). A
per-nest undo was rejected: an edit of a nest changes how the song sounds, and two trees for one
sound would disagree.

### 4.10 Extension points

- **Nest kinds.** `paw.nest.define_kind("drums.pattern", spec)` with `title`, `letter`,
  `create(region) -> NestSpec` (the tracks and clips it makes), `enter(nest) -> view` (open the
  step grid instead of the arrange), `describe(nest)`. The kind's data is in `nest.meta` under
  the extension's key. Without the extension the nest is plain: it plays and the arrange edits
  it (rule 4: the clips are the truth). Typed in `contracts.tl` as `NestKind<D>`.
- **Events**: `NestEnter`, `NestLeave`, `NestChanged` (with the nest and the steps).
- **API**: `paw.nest.make`, `unnest`, `list`, `get`, `enter`, `place(nest, track, beat, play)`,
  `unique`, `time`, `meter`.
- A custom clip kind (an extension's clip) cannot hold a nest in v1: nest clips are built in.
  An extension that wants a generated section writes its MIDI into a nest kind.

### 4.11 What changes in core

| Where | Change |
| --- | --- |
| `model.rs` | `Nest`, `NestId`, `Project::nests`, `Track::nest`, `ClipContent::Nest`, the invariants |
| `tempo` | `TempoMap::nest`: nest beats to song beats, nest bars |
| `session/folder.rs` | `nests/` read and write, `unused/nests/`, outside nests |
| `sync/clips.rs` | expansion of nest clips (pass mode), chain mode engine tracks per (nest track, host) |
| `paw-engine` | per-track transport (bar offset and meter) for nest devices |
| `freeze.rs`, `bake/` | the nest bake key; freeze of a nest clip |
| `runtime/lua/paw/scope.lua` → `scope.tl` | time ranges and nests; port to Teal (it changes much) |
| `runtime/lua/paw/nest.tl` | new: make, unnest, enter, kinds, commands |
| `defaults/keys.lua` | `zf zF zd zD`, `<Space>cn cN cu`, `<Space>rz`, `<CR>`/`zn` on a nest |
| arrange, ruler, status line, scene | instance blocks, nest ruler, breadcrumbs |
| `extensions/projdiff` | recurse into nests |

---

## 5. Plan (rewritten in revision 2, 5.2 in revision 3)

Each part is one branch with its tests and its doc changes in the same commit. Sizes: S (up to a
day of agent work), M (a few), L (a week). The view parts come first; each is useful alone.
The saved-nest parts follow, and the owner may stop after any of them.

### 5.1 The view model

| Part | What | Tests (real keys where the user feels it) | Size |
| --- | --- | --- | --- |
| V1 | **The scope record and time** (was N1): `scope.lua` to Teal; `Scope` with tracks and time, resolution, nested scopes; region and range scopes; local bars on the ruler with the song's row; the time limit of motions; `scopeloop`; `scope_rest` outside the time; `:narrow <region>` | `znar` in a region: the ruler starts at 1 in 6/8, `G` stops at its end, `3|` is song bar 19, the status line breadcrumb; a scope of a group inside a region | M |
| V2 | **Scopes per window, and movement**: the scope stack per window (not per tab); `zn` operator, `znn`, `zw`, `zW`, `]z` `[z`, jumps keep scopes, `<Space>zs` `zv` `zt`, `ig`/`ag`; `screen.json` keeps stacks | `znag` `]z` `zw` `zW` with real keys; `<C-o>` back into a scope; a split shows the song beside a scope and an edit in one shows in the other | M |
| V3 | **Views in a scope**: piano roll, mixer, device panel, session view, pickers, track column numbers, Ex ranges and `@N`, `ie`/`ar` in the scope, cut clips drawn `‹ ›` | `dar` in a scope deletes only the scope's tracks; `:%` sees the scope; the roll limits its time | M |
| R1 | **Nested regions** (revision 4, 3.8): the tree by containment, `parent`/`children`/`path`, `2ar`, `]r` `[r`, moving a parent moves its children, `:region.remove!`, the picker tree, `:render.regions level=`, path file names | `2ar` with real keys takes the parent; `:marker.move` of Chorus 2 moves Verse A; overlaps are siblings; render names | M |
| R2 | **The region lane as a tree** through the `paw.ruler` registry (rows per level, fold glyphs, styles); the scope model's region children (`znar` inside a region, `]z` among siblings) | a region lane of 3 levels in the terminal and the window (paw-gui tests); `]z` in `Song › Chorus 2` | S |
| V4 | **Folds as scopes**: time folds and block folds in the arrange, `zf` `za` `zc` `zd` `zE` `zR` `zM`; `group_folded` to view state; `zn` on a fold | `zfar` draws one column and the song still plays through it; `zm` `zr` close and open region levels; `za` opens; folds per window; the window frontend draws them (paw-gui tests) | L |
| V5 | **The picker and names**: `<Space>zz`, `<Space>fz`, `:scope.name`, `K` on a scope | the picker lists stack, folds, regions, groups; `K` text | S |
| V6 | **Explanation and how-to**: `about-scopes.md` (views, folds, narrowing as one model), "Work on a section in another meter" with its guide test; `narrowing.md`, `grammar.md`, `keys.md` updated | Vale; `tests/guides_howto.lua` | S |
| V7 | Measure: a key in a scope of a large project stays under 100 ms (bench) | `bench/` numbers | S |

### 5.2 Subprojects (rewritten in revision 3; after V1-V7)

Reordered for revision 3: a subproject with its own tracks and a return row comes first, because
it is the case that views cannot do. The per-track save of a view comes after it.

| Part | Was | What | Tests | Size |
| --- | --- | --- | --- | --- |
| S0 | N0 | Spike: a track with clips that is also the output of other tracks; per-track transport in the engine (bar offset, meter); the cost of expanding 1 000 nest clips | Rust tests; `bench/` numbers | S |
| S1 | N2 | Model and files (`Nest`, `Track::nest`, `ClipContent::Nest`, `nests/`, `unused/nests/`, cycles refused); a nest is a scope of kind `nest` (enter, leave, breadcrumb, picker, `]z`) | save and load byte-equal; a cycle refused with its path; `znn`/`zw` into and out of a nest with real keys | L |
| S2 | N7 | Playback of a subproject's own tracks into its return row (chain mode), the transport for plugins inside, tails, mute | a synth in a subproject renders as on a song track; a tempo-synced device sees bar 1 at the block's start | L |
| S3 | new | `<Space>za`, `:nest.new [name] [bars] [meter]`: the return row, the block, the meter written into the song's map, enter with one track; `:tempo` inside a `follow` subproject edits the song's map | the 6/8 piano example of 3.7, steps 1-8, with real keys, and a render | M |
| S4 | N4 | Blocks drawn on the return row, `za` in place, `K`, `:nest.list` | the window frontend draws the same scene (paw-gui tests) | S |
| S5 | new | `:nest.outputs stems` / `master`: stem rows grouped under the subproject's row | the sum of the stems renders as the stereo return | S |
| S6 | N6 | `<Space>zp`, `:nest.promote`: everything of 3.9 (tracks in a group, clips, regions as children, lanes, devices without reload, sends, tempo, meter, key, scopes); a view stays at the subproject's place | the 3.9 round trip (promote, then save again: same project text with ids mapped, same render); `u` restores | M |
| S7 | N3 + N5 | `<Space>zw`, `:scope.write`: a view into a subproject, per track (pass-mode playback) | render before and after equal; `<Space>zw` then `<Space>zp` gives the same project | M |
| S8 | N8 | `<Space>zW`: a view into a subproject with its own row; groups; routes at the boundary | crossing sends listed, side-chains refused | M |
| S9 | N9 | Own tempo (`:nest.time own`) and own meter without the song's map (`meter=own`) | a ritardando of the song changes a `follow` subproject and not an `own` one | M |
| S10 | N10 | Links (two blocks of one subproject), `:nest.unique` | an edit is heard in both blocks; unique separates | S |
| S11 | N11 | Freeze of a block | frozen render equals live; an edit marks it stale | M |
| S12 | N12 | `:nest.export`, `:import` of a folder, `:nest.own`, `projdiff`, nest kinds | an exported subproject opens alone and renders the same | M |

The order: V1, V2, R1, R2, V3-V7, then S0-S6 (the owner's metal-ballad case complete), then S7-S12.

### 5.3 What the N1 agent (scope by time range, now) should change

1. Call the part **V1**, and build the `Scope` record of section 3.1 (kind, id, tracks,
   from/to, name, parent) in `scope.tl`, not a time field added to `tab.scope`. Group scopes
   become `{ kind = "group", id = g }`; keep `paw.scope.narrow(group)` and `widen()` working.
2. Resolve scopes by intersection with the parent from the start, even if V1 enters only one
   level: nested scopes must not need a second format.
3. Keep the scope where V2 can move it to the window: put reads behind `scope.current(win)`, and
   no view reads `tab.scope` directly.
4. Bar numbers: local bars from the song's meter map, plus the song's row (`scopebars=both`);
   commands take local bars. Do not copy the meter into the scope: the view model has none of
   its own.
5. Do not add `zn` as an operator yet if it breaks the group `zn` in V1; V2 owns the keys. V1
   may add `:narrow <region>` and `<Space>rz` is **dropped** (the z domain is `<Space>z`; V2
   adds `znar`).
6. No project data, no undo step for entering or leaving; `screen.json` only.

## 6. Open questions for the owner (revised in revisions 2, 3 and 4)

Questions 1-12 are revision 1's; their status is marked. 13-17 are revision 2's, 18-23 revision 3's, 24-30 revision 4's.
*Revision 3:* the answers marked "saved nests only" apply to **subprojects** (section 3.7 and 4),
made new or from a view.

1. **Name.** *Revision 2:* "scope" for the view (`zn`, `:scope.*`), "nest" for a saved one
   (`:nest.*`, "saved nest"), and "fold" for a scope drawn in place. *Recommended: yes.*
2. **Default layout when saving.** *Applies to saved nests only.* Per track for `<Space>zw`, mix
   for `<Space>zW`. *Recommended: yes.*
3. **Paste of a nest clip links.** *Saved nests only.* *Recommended: link, `:nest.unique`.*
4. **Clips at the edges.** *Revision 2:* a scope never cuts; it draws the cut (`‹ ›`). Saving a
   scope cuts at the edges. *Recommended: yes.*
5. **Default tempo of a saved nest.** *Saved nests only.* *Recommended: follow.*
6. **Bar numbers.** *Revision 2, now for every scope with a time range:* local from 1, with the
   song's bars on a thin second ruler row and in the status line. *Recommended: yes.*
7. **Markers inside.** *Revision 2:* a scope moves nothing. Saving: markers move into the nest.
   *Recommended: yes.*
8. **Promote and the meter.** *Saved nests only.* Write the nest's meter into the song's map when
   it differs. *Recommended: yes.*
9. **One undo tree.** *Answered by revision 2:* yes, for views and saved nests.
10. **Shared nests between songs.** *Saved nests only.* Own copy at first edit. *Recommended.*
11. **Automatic bakes.** *Saved nests only.* Only on `:freeze`. *Recommended.*
12. **Closed boundary.** *Saved nests only;* a scope has no boundary. *Recommended: closed.*
13. **(New) Bar numbers in commands inside a scope.** `17|`, `:tempo 96 at 3` and `:17` take the
    scope's local bars, and `@19` names a song bar? Or song bars everywhere, with local bars only
    on the ruler? *Recommended: local, as what the eye sees on the ruler is what the hand types.*
14. **(New) Folds are view state.** Group folds move from the group's `meta` (an undo step, saved
    in the project) to each window (`screen.json`, no undo step), as Vim's folds. Two windows
    can then fold differently. *Recommended: yes.*
15. **(New) `zn` becomes an operator.** `zn` now waits for a motion (`znar`, `znag`); `znn` does
    what `zn` did (the innermost scope at the cursor). *Recommended: yes* (no compatibility
    needed before a release).
16. **(New) Enter in place, not in a new tab.** `zn` now enters in the current window, and
    `<Space>zt` opens a tab (what `zn` did). *Recommended: yes:* free movement needs `zw` to go
    back in the same window.
17. **(New) What the time outside a scope does.** `scope_rest` (`play`, `mute`, `frozen`) applies
    to tracks outside; for time outside, the loop is the scope by default (`scopeloop`).
    *Recommended: yes.*
18. **(Revision 3) The word in commands.** `:nest.new`, `<Space>za` "add a subproject", and the
    docs say "subproject (nest)"? Or rename the commands to `:subproject.*` (long) or `:sub.*`?
    *Recommended: keep `nest` in commands and code (accepted in revision 1); the docs and the
    key hints say "subproject", and `:help subproject` finds it.*
19. **(Revision 3) Where a new subproject is drawn.** Its own return row (decided in 3.7), not a
    block over a host track. *Recommended: own row;* the per-track layout stays for saving a view.
20. **(Revision 3) The meter of a section.** `:nest.new Ballad 8 6/8` writes 6/8 into the song's
    map over its span (the song's bar numbers count the section's bars), unless `meter=own`
    (polymeter). *Recommended: yes.*
21. **(Revision 3) Promoting an `own`-tempo subproject** writes its tempo into the song's map over
    its span, so that the sound and the beats stay. *Recommended: yes, and say so.*
22. **(Revision 3) Tempo inside a `follow` subproject.** `:tempo` there edits the song's map at the
    mapped place (one tempo truth). *Recommended: yes, with the message naming the song's bar.*
23. **(Revision 3) Outputs.** One stereo return by default, stems by `:nest.outputs stems`.
    *Recommended: yes.*
24. **(Revision 4) Promote.** Rename `:nest.inline` to `:nest.promote` and `<Space>zi` to `<Space>zp`?
    *Recommended: yes;* it names what the user gets, a view.
25. **(Revision 4) Nested regions in core**, by time containment, with no change of the file
    format. *Recommended: yes* (3.8).
26. **(Revision 4) Moving a parent region moves its children** (and the markers in it);
    `:region.move!` moves it alone. *Recommended: yes.*
27. **(Revision 4) The key of a promoted subproject** that differs from the song's is kept on its
    region (`region.key`), for harmony to read later. *Recommended: yes.*
28. **(Revision 4) `:render.regions`** renders every region (as today), with path names; `level=`
    chooses. *Recommended: yes.*
29. **(Revision 4) Region folds by level** with Vim's `zm` and `zr`. *Recommended: yes.*
30. **(Revision 4) Overlapping regions that do not nest** are siblings; `ar` takes the one that
    starts later. *Recommended: yes.*

---

## 7. Decisions

| Date | Who | Decision |
| --- | --- | --- |
| 2026-11-21 | owner (on revision 1) | "Let's do recommended now and I'll figure out changes later on": every recommended answer of revision 1's questions is accepted for now (name "nest", per-track default with the mix layout apart, paste links, cut at edges, tempo follows the song, bars from 1 inside, markers move in, unnest writes the meter, one undo tree, own copy at first edit, bakes only on `:freeze`, closed boundary). Keep each one easy to change. → Revision 2 keeps all of them; 2, 3, 5, 7, 8, 10, 11, 12 now apply to **saved nests only** (section 6 marks each). |
| 2026-11-21 | maintainer (on revision 1) | `z` keys stay for folds (view only; time folds take `zf`/`zd` as in Vim); the nest operator gets its own key. → Revision 2 does this: `zf`/`zd` are folds (3.3), saving is `<Space>zw`, promoting `<Space>zp` (3.6). If a separate time-folds design exists, V4 follows it and keeps folds as scopes drawn in place. |
| 2026-11-21 | owner | Subprojects, folds and nests are ways to view the same thing; the user must move freely between them (track nest, project nest, selection nest). Unless saved independently, they are only views. → The scope is the model (section 3); saved nests (section 4) exist only after `<Space>zw`. |
| 2026-11-21 | owner | Nests along both axes: time, tracks, or both (and several rectangles). → A scope is tracks x time (3.1); a saved nest keeps the shapes of 4.1. |
| 2026-11-21 | owner | Turn a selection or region into a self-contained project, and back. → `<Space>zw` / `:scope.write`, `<Space>zp` / `:nest.promote` (3.6); `:scope.write <folder>` for a standalone project. |
| 2026-11-21 | owner | Allow both views and proper subprojects: a subproject with tracks the song does not have (a slow piano section in a metal song, a breakdown). → Section 3.7: subprojects are first-class (made new with `<Space>za`), drawn on a return row of their own, one stereo return or stems, no shared tracks, tempo from the song by default; the same navigation as views. |
| 2026-11-21 | owner | Promote a subproject to a view, bringing its tracks, clips, markers and the rest into the song. → `<Space>zp` / `:nest.promote`, section 3.9. |
| 2026-11-21 | NEST (owner asked to evaluate) | Nested regions are core, by time containment, no file change (3.8): the scope model, text objects, folds and picker of the core read them; an extension restyles them through `paw.ruler`. |
| 2026-11-21 | NEST | Folds, narrowing and nests-as-views share one registry, one set of keys (`z`, `<Space>z`) and one undo tree; scopes belong to windows. |

---

## 8. Sources

Gathered by a web-research subagent; items it could not confirm are marked.

- REAPER subprojects, `.RPP-PROX`, render on save, insert and move to subproject, `=START`/`=END`
  markers, "Synchronize any parent projects on playback": Sound On Sound, "REAPER: Subprojects",
  https://www.soundonsound.com/techniques/reaper-subprojects
- "Move items to new subproject" (REAPER 5.11, "non-destructive glue"):
  https://reaper.blog/2015/12/reaper-version-5-11-update-released
- Deferred rendering, nesting, stale audio: https://www.asoundeffect.com/reaper-for-game-audio-project-scopes-subprojects
- What users like and dislike (CPU relief, MIDI editable, waits on save, clunky):
  https://forums.steinberg.net/t/steinberg-take-note-reapers-sub-projects-looks-very-cool/108433
- One subproject per tempo as a polytempo workaround:
  https://vi-control.net/community/threads/daw-simultaneous-tempo-tracks.60108/
- Cubase users ask for subprojects or Digital Performer chunks:
  https://forums.steinberg.net/t/dp-chunks-sub-projects/118211
- Cubase folder and group tracks: https://www.soundonsound.com/techniques/cubase-pro-folder-tracks-and-group-channels-v15020,
  https://forums.steinberg.net/t/make-folder-tracks-group-tracks/157925
- Bitwig: nesting is in device chains; bounce in place: https://www.musicradar.com/news/8-bitwig-studio-tips;
  launcher clips can change the meter: https://www.bitwig.com/userguide/latest/triggering_launcher_clips_0;
  no nested project found (not confirmed absent).
- Logic Pro Track Stacks (folder and summing): https://help.apple.com/logicpro/mac/10.4/en.lproj/lgcp9bc4b63d.html,
  https://www.soundonsound.com/techniques/well-stacked; Project Alternatives:
  https://help.apple.com/logicpro/mac/10.2.1/en.lproj/lgcp9a5ac3ca.html
- Studio One Song and Project pages, update of mastering files:
  https://www.soundonsound.com/techniques/seamless-mixing-mastering-studio-ones-project-page
- Ableton Live nested group tracks: https://www.ableton.com/en/live-manual/11/mixing/,
  https://forum.ableton.com/viewtopic.php?p=1617403
- FL Studio pattern clips and "make unique": https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/playlist.htm
- Pro Tools clip groups (nest, ungroup, ungroup all, regroup): https://apps.avid.com/proToolsFirstHelp/version12.3/enu/Pro%20Tools%20First%20Help/Arr4.LoopsGroups.34.14.html
- Blender node groups (Ctrl+G, Tab in, Ctrl+Tab out, ungroup): https://docs.blender.org/manual/en/4.0/interface/controls/nodes/groups.html
- Kdenlive sequences (references, "create sequence from selection", no self-insertion, one
  profile, not shared between projects): https://docs.kdenlive.org/en/cutting_and_assembling/sequence.html;
  bugs https://bugs.kde.org/show_bug.cgi?id=482949, https://bugs.kde.org/show_bug.cgi?id=492216
- DaVinci Resolve compound clips and nested timelines:
  https://forum.blackmagicdesign.com/viewtopic.php?p=779810 (third-party comparison:
  https://davinciresolve21.com/blog/compound-clip-vs-nested-timeline-davinci-resolve-which-should-i-use)
- Ardour: two sessions in one process is "a major re-engineering task":
  https://discourse.ardour.org/t/merge-sessions/89380
- Not confirmed: Renoise phrases, Premiere and Final Cut nesting, Logic Track Alternatives,
  REAPER's exact tempo behavior of a moved subproject.
- In the repository: `docs/reference/narrowing.md`, `tempo.md`, `project-files.md`,
  `routing.md`, `freezing.md`, `grammar.md`, `keys.md`; `runtime/lua/paw/defaults/keys.lua`,
  `scope.lua`, `markers.tl`, `clip_kinds.tl`; `crates/paw-core/src/model.rs`, `history.rs`;
  `scratchpad/media/DESIGN.md`.

## 8. N0 results (2026-11-21, the spike)
- A track with clips can also be the output of other tracks: the engine sums inputs with its own
  clips before its devices (test crates/paw-engine/tests/bus_clips.rs). The design holds.
- Expanding 1 000 nest clips costs ~0.07 ms; the first sync is what the same music as plain clips
  costs. But an edit inside a nest recompiles every copy (1.9 ms at 96 notes, 17.5 ms at 384 per
  clip, 90-350x a plain edit). Design change for S2: copies keep a stable identity across syncs
  (the compiled-events cache is keyed by it), and engine clip parts take a beat offset so all
  instances share one compiled event list; a cut at the window start shifts notes (not benched).

## Owner decisions, Q13-Q30 (2026-11-22)
All recommended answers of section 6 accepted for Q13-Q30 (as for Q1-Q12); the owner may change any later, so keep each easy to change.
