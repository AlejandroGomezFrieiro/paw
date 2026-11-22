# Narrowed tabs

<!-- tags: narrowing scope narrow region -->

In a large project, you can narrow a tab to a part of the song. The part
is a group of tracks, the time of a region, or both. The tab then shows only that
part. This is similar to a subproject in REAPER, but it is the same
project. The part is a scope, and the module is `paw.scope`.

## Commands

| Keys, command | Effect |
| --- | --- |
| `:narrow Strings`, `zn` | Show a group and the tracks inside it, at any depth. `zn`: the group at the cursor, on its header or on one of its tracks. |
| `:narrow Bridge` | Show every track in the time of the region Bridge. |
| `:widen`, `zw` | Go up one level. From the first level, close the narrowed tab and go to the tab that it came from. |
| `:widen!` | Go up to the whole song, and close the narrowed tab. |
| `gt` | Go between the tabs, as for any tabs. |
| `:set scope_rest=mute` | Set what the tracks outside the scope do (see below). |

`:narrow` takes a group or a region by name. A group comes before a
region of the same name. A name can be the start of the name. Of two
regions with the same name, the region in the current scope comes first.
A path of regions also finds one: `:narrow Chorus 2/Verse A`.

From the song, `:narrow` opens a tab after the current tab. If a tab
already shows that scope, paw goes to that tab.

## A scope in a scope

In a narrowed tab, `:narrow` goes one level down in the same tab. The new
scope shows only what both scopes show. For example, `:narrow Bridge`,
then `:narrow Strings`, shows the strings in the time of the bridge. The
status line shows the path: `Song › Bridge › Strings`. `zw` goes up one
level, and `:widen!` goes up to the song.

If the two scopes have no track or no time in common, paw does not go
down. The message gives the reason, for example `no track of Brass is in
Strings`.

## In a narrowed tab

- It is the same project, with one undo tree. Undo in any tab undoes an
  edit made in the narrowed tab.
- To narrow and to widen change nothing in the project. They are not undo
  steps.
- Only the tracks of the scope show in these: the arrange view, the
  mixer, the device panel, the session view of the clip launcher,
  `paw://tracks`, the pickers.
- The track motions (`gg`, `G`, `j`) and the Ex ranges use only these
  tracks. `t1` is the first track of the scope, `t*` and `%` are its
  tracks, and `:g` and `:s` look only in them.
- The fold of the group is open.
- The status line shows the path of the scope, and the tab has the name of
  the innermost scope.
- A track that you add in the scope of a group goes into the group.
- Several scopes can be open at the same time, each in its own tab.
- The graphical window shows the tab as the terminal does.

## A scope with time

A scope of a region shows the time of the region.

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
- While the tab is in front, the loop is the time of the scope. The loop
  that you had returns when you widen or go to another tab.

`paw.opt.scopebars` sets the bar numbers, and `paw.opt.scopeloop` the
loop:

| Option | Default | Effect |
| --- | --- | --- |
| `scopebars` | `"both"` | `"local"`: the bars count from 1 at the start of the scope. `"song"`: the bars of the song. `"both"`: from 1, with the bars of the song on a second row of the ruler. |
| `scopeloop` | `true` | Loop the time of the scope while its tab is in front. |

## The rest of the song

`paw.opt.scope_rest` sets what the tracks outside the scope do while a
narrowed tab is in front. No value changes the project. A scope of time
only (a region) has no tracks outside it: the loop keeps the playhead in
its time.

| Value | Effect |
| --- | --- |
| `play` | Default. The rest plays, as a reference. |
| `mute` | The rest is silent, as with a solo of the scope. The tracks that the sound of the scope goes through still play. The mutes and solos of the project do not change. |
| `frozen` | paw renders each part of the rest in the background (each full group, and each track outside a group), and plays the files, so that their devices rest. A part that you edit plays live until paw renders it again. paw releases the files when the tab is not in front. |

## Lua

A scope is a table. `kind` is `"group"`, `"track"`, `"tracks"`,
`"region"` or `"range"`. `id` is the group, track or region. `tracks` is
a list of track ids, and `from` and `to` are beats. `name` is its
name, and `parent` is the scope
that it is in, or nil.

| Function | Result |
| --- | --- |
| `paw.scope.narrow(which)` | Narrow to a group or a region, by its id, its track or its name. |
| `paw.scope.enter(scope)` | Narrow to a scope, for example `{ kind = "range", tracks = { 3, 4 }, from = 64, to = 96 }`. |
| `paw.scope.widen(top)` | Go up one level, or with `top` up to the song. |
| `paw.scope.current()` | The scope of the current tab, or nil. |
| `paw.scope.group()` | The innermost group of the current scope, or nil. |
| `paw.scope.children()` | The scopes one level inside the current scope. For a region, they are the regions inside it. |
| `paw.scope.tracks()` | The tracks that the current tab shows. |
| `paw.scope.span()` | The time that the current tab shows, `from, to` in beats, or nil for all of it. |
| `paw.scope.contains(track)` | True if the current tab shows the track. |
| `paw.scope.breadcrumb()` | The path, for example `Song › Bridge › Strings`. |
| `paw.scope.song_bar(n)` | The bar of the song for bar `n` of the scope. |

`paw.api.engine_audible(ids)` and `paw.api.engine_hold(track, file)` give
`mute` and `frozen` (see
[The audio engine](engine.md#scripts-and-the-engine)).
