# Scopes

<!-- tags: narrowing scope narrow region subproject nest zn znn zw zW -->

In a large project, you can narrow a window to a part of the song. The
part is a group of tracks, the time of a region, some tracks, or both
tracks and time. The window then shows only that part. Unlike a
subproject in REAPER, the narrowed window is the same project. The part is
a scope, and the Lua module is `paw.scope`.

## Keys and commands

| Keys, command | Effect |
| --- | --- |
| `zn{motion}`, `{Visual}zn` | Enter the scope that the motion or the selection covers, in this window. `znar`: the region at the cursor. `znag`: the group. `znit`: the track. `Vjjzn`: the three tracks. A visual block: those tracks in that time. |
| `znn` | Enter the innermost scope at the cursor that the window does not show yet. On a clip of a subproject, the subproject. In a region, the region inside it at the cursor. Else the group of the track, else the track. |
| `<CR>` on a clip of a subproject | Enter the subproject, as `znn` does. |
| `:narrow Strings`, `:narrow Bridge` | Enter a group or a region by name. A named scope comes first, then a group, then a region of the same name. A name can be the start of the name. Of two regions with the same name, the region in the current scope comes first. A path of regions also finds one: `:narrow Chorus 2/Verse A`. Alone, `:narrow` is `znn`. |
| `zw`, `:widen` | Go up one level. |
| `zW`, `:widen!` | Go up to the whole song. |
| `]z` `[z`, `:scope.next`, `:scope.prev` | Go to the next scope beside this one, or to the one before, in the same parent. A subproject: the next clip of a subproject in time, which is the next block of the same subproject or another subproject. A region: the next region of the same parent region. A group: the next group in the same group. A track: the next track of the parent scope. A block with time: the same tracks, the next stretch of the same length. `3]z` goes three on. |
| `<C-o>` `<C-i>` | Move backward and forward through the jump list. To enter, to leave and `]z` are jumps. A jump keeps the scope, so `<C-o>` returns into the scope and to the place. |
| `<Space>zz`, `<Space>fz`, `:scope.list` | Choose from a list: the levels of this window's scope (to go up to), the named scopes, the groups, the subprojects (marked `nest`) and the regions as a tree. |
| `<Space>zs` `<Space>zv` `<Space>zt`, `:scope.split`, `:scope.vsplit`, `:scope.tab` | Show the scope at the cursor (or of the selection, or one by name) in a new split, vertical split or tab. The window that you were in stays as it was. |
| `<Space>zn`, `:scope.name Strings in bridge` | Name the scope of this window, so that the list and `:narrow` find it again. |
| `:set scope_rest=mute` | Set what the tracks outside the scope do (see below). |

## A scope belongs to a window

- Each arrange window keeps its own scope, as each window of Vim keeps its
  folds. A split can show the whole song beside the bridge.
- A new split starts with the scope of the window that it comes from.
- The other windows of a tab (the mixer, the device panel, the piano roll)
  show the scope of the arrange window of the tab that had the keyboard last.
- The tab has the name of the scope of its current window.
- The status line shows the path of the scope of the current window.
- The project keeps the scope of each window and the named scopes with its
  windows (`screen.json`). They are not in the song and not in undo.

## A scope in a scope

In a narrowed window, a new scope goes one level down. It shows only
what both scopes show. For example, `:narrow Bridge`, then `:narrow
Strings`, shows the strings in the time of the bridge. The status line
shows the path: `Song › Bridge › Strings`. `zw` goes up one level, and
`zW` goes up to the song.

If the two scopes have no track or no time in common, paw does not go
down. The message gives the reason, for example `no track of Brass is in
Strings`.

## In a narrowed window

- It is the same project, with one undo tree. Undo in any window undoes an
  edit made in the narrowed window. Every window shows an edit at once.
- To narrow and to widen change nothing in the project. They are not undo
  steps.
- Only the tracks of the scope show in these: the arrange view, the
  mixer, the device panel, the session view of the clip launcher,
  `paw://tracks`, the pickers.
- The track column numbers the tracks of the scope from 1. A `›` on its
  first row says that the window is in a scope.
- The track motions (`gg`, `G`, `j`) and the Ex ranges use only these
  tracks. `t1` is the first track of the scope, `t*` and `%` are its
  tracks, and `:g` and `:s` look only in them.
- The text objects take only what the scope shows. `ie` is the entire
  scope, and `ar` is the region on the tracks of the scope, cut at the
  edges of its time. So in `Song › Bridge › Strings`, `dar` deletes only
  the clips of the strings in the region.
- The piano roll edits the clips of the tracks of the scope, and it shows
  the notes of those tracks behind them.
- The fold of the group is open.
- A track that you add in the scope of a group goes into the group.
- The graphical window shows the window as the terminal does.

## A scope with time

A scope of a region, or a block with time, shows that time.

- The cursor stays in that time. `0` goes to its start, and `$`, `W` and
  `l` stop at its end.
- The arrange view starts at the bar that the scope starts in. It dims
  the time after the end.
- The bars count from 1 at the start of the scope, from the meter map of
  the song. A region in 6/8 shows its bars in 6/8.
- A second row of the ruler shows the bars of the song, under the bars of
  the scope. The status line shows the place of the cursor in both:
  `Song › Bridge 3.2 (19.2)`.
- The bars that you type are those of the scope: `3|` and `:3` go to
  bar 3 of the scope, and `:timesig 3/4 at 3` sets the signature there.
  A bar with `@` before it is a bar of the song: `@19|`, `:@19` and
  `:tempo 96 at @19` all mean bar 19 of the song.
- `%` in an Ex range is the time of the scope, so `:%quantize` snaps
  only the notes inside it.
- A clip that crosses an edge of the scope is drawn cut, with `‹` or `›`
  at the cut, and its name after the `‹`. An edit of the clip, for
  example `x`, is an edit of all of it.
- The piano roll shows the same time: `0` and `$` stop at the edges of
  the scope.
- While the window is in front, the loop is the time of the scope. The
  loop that you had returns when you widen or go to a window of the song.

`paw.opt.scopebars` sets the bar numbers, and `paw.opt.scopeloop` the
loop:

| Option | Default | Effect |
| --- | --- | --- |
| `scopebars` | `"both"` | `"local"`: the bars count from 1 at the start of the scope. `"song"`: the bars of the song. `"both"`: from 1, with the bars of the song on a second row of the ruler. |
| `scopeloop` | `true` | Loop the time of the scope while its window is in front. |

## A subproject

A subproject has its own tracks and its own timeline, and a clip of the
subproject places it in the song. The commands and the Lua functions
call a subproject a nest. You enter a subproject as you enter any other
scope, with `znn` or `<CR>` on its clip, or from `<Space>zz`.

- The song does not show the tracks of a subproject. The arrange view,
  the mixer, `paw://tracks`, the pickers, `t*` and `%` list the tracks of
  the song only. In the subproject, they list its tracks only.
- The status line marks a subproject with `⧉`, for example
  `Song › ⧉Ballad 1.2 (9.2)`. The first place is in the bars of the
  subproject, and the place in brackets is in the bars of the song, at the
  clip that you entered through.
- The bars count from 1 at the start of the subproject, and they are the
  bars of the song at that clip: over a 6/8 section of the song, bars of
  6/8. With `scopebars=both`, the second row of the ruler shows the bars
  of the song at that clip. See [Subprojects](subprojects.md) for how to
  add one, how to save a view as one, and for its tempo.
- The cursor keeps its place in the song when you enter or leave. The
  loop is the time of the clip in the song.
- `]z` and `[z` go to the next clip of a subproject and to the one before.
- A track that you add in a subproject belongs to the subproject.
- The subproject plays in the song through the track that holds its
  clip, its return row. Its tracks play into its master track, and its
  master plays into the return row, so the fader, pan, sends and devices
  of the return row act on the whole subproject. Two clips of one
  subproject on the row play it twice, through the same devices. A muted
  clip places no notes, and a reverb inside the subproject rings on past
  the end of a clip.
- An edit in a subproject is an edit of the project, in the one undo
  tree. The name of the undo step starts with the name of the subproject,
  for example `Ballad: add note`, so that `u` in the song undoes it and
  the undo list says where it was.
- Inside a subproject, a scope of a group, a track or a time goes one
  level down as in the song, for example `Song › ⧉Ballad › Strings`.

## The rest of the song

`paw.opt.scope_rest` sets what the tracks outside the scope do while a
narrowed window is in front. No value changes the project. A scope of time
only (a region) has no tracks outside it: the loop keeps the playhead in
its time.

| Value | Effect |
| --- | --- |
| `play` | Default. The rest plays, as a reference. |
| `mute` | The rest is silent, as with a solo of the scope. The tracks that the sound of the scope goes through still play. The mutes and solos of the project do not change. |
| `frozen` | paw renders each part of the rest in the background (each full group, and each track outside a group), and plays the files, so that their devices rest. A part that you edit plays live until paw renders it again. paw releases the files when a window of the song is in front. |

## Lua

A scope is a table. `kind` is `"group"`, `"track"`, `"tracks"`,
`"region"`, `"range"` or `"nest"`. `id` is the group, track, region or
subproject. `tracks` is a list of track ids, and `from` and `to` are
beats. For a subproject, `clip` is the clip that the window entered
through. `name` is its name, and `parent` is the scope that it is in, or
nil.

A window keeps the innermost level in `win.scope`.

| Function | Result |
| --- | --- |
| `paw.scope.narrow(which)` | Narrow the current window to a group or a region, by its id, its track or its name. |
| `paw.scope.enter(scope, win)` | Narrow a window (the current one by default) to a scope, for example `{ kind = "range", tracks = { 3, 4 }, from = 64, to = 96 }`. |
| `paw.scope.widen(top, win)` | Go up one level, or with `top` up to the song. |
| `paw.scope.next(n)` | Go to the scope `n` places beside the current one. |
| `paw.scope.open(how, scope)` | Show a scope in a new `"split"`, `"vsplit"` or `"tab"`. |
| `paw.scope.name(name)` | Name the scope of the current window. |
| `paw.scope.current(win)` | The scope of a window, or nil. Without a window: of the window that paw draws, else of the current window. |
| `paw.scope.group()` | The innermost group of the current scope, or nil. |
| `paw.scope.children()` | The scopes one level inside the current scope: for a region, the regions inside it, and for a group, its members. |
| `paw.scope.tracks()` | The tracks that the current scope shows. In the song, the tracks of the song without those of the subprojects. |
| `paw.scope.nest()` | The innermost subproject of the current scope, or nil in the song. |
| `paw.scope.of_clip(id)` | The scope of the subproject that a clip places, or nil. |
| `paw.scope.song_beat(beat)` | The beat of the song for a beat that the current scope shows. In a subproject, the beat at the clip that the window entered through. |
| `paw.scope.span()` | The time that the current scope shows, `from, to` in beats, or nil for all of it. |
| `paw.scope.contains(track)` | True if the current scope shows the track. |
| `paw.scope.breadcrumb()` | The path, for example `Song › Bridge › Strings`. |
| `paw.scope.song_bar(n)` | The bar of the song for bar `n` of the scope. |

`paw.api.track_list()` gives the tracks of the song. `paw.api.track_list({ nest = id })`
gives the tracks of a subproject, and `paw.api.track_list({ all = true })`
gives every track.

`paw.api.engine_audible(ids)` and `paw.api.engine_hold(track, file)` give
`mute` and `frozen` (see
[The audio engine](engine.md#scripts-and-the-engine)).
