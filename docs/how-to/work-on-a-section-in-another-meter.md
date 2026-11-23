# How to work on a section in another meter

<!-- tags: section-in-another-meter meter 6/8 bridge -->

You can write a section of a song in another meter, for example a bridge
in 6/8 in a song in 4/4, and work on it with bars that count from 1. The
steps use bars 17 to 24 as the bridge. To narrow
to a section in the meter of the song, see
[How to work on one section of a song](work-on-one-section-of-a-song.md).

## Put the meter in the song

1. Type `:timesig 6/8 at 17`. The message says `6/8 from bar 17`.
2. Type `:timesig 4/4 at 25`. The song goes back to 4/4 at bar 25, so
   bars 17 to 24 are eight bars of 6/8. A bar of 6/8 has three beats, so
   the bridge is 24 beats long.

Set the meter before you make the region, so that the region covers
eight bars of 6/8 and not eight bars of 4/4.

## Make a region over the section

1. Type `17|` to go to bar 17.
2. Press `v`, then `8W`, to select the eight bars.
3. Press `<Space>rn` and type `Bridge`. The message says that the region
   starts at bar 17 and is 24 beats long.

## Work in the section

1. With the cursor in the bridge, press `znar`. The window shows only the
   bridge, and the message describes it:

   ```
   Song › Bridge · bars 1-8 (song @17-24) · 6/8 · 3 parts · `zw` goes back
   ```

   The ruler counts the bars of the bridge from 1 in 6/8, with the bars
   of the song under them, and the bridge ends at a `┃`. The status line
   shows the place of the cursor in the bars of the bridge and in the bars
   of the song, for example `Bridge 1.1 @17.1`, and the loop is the
   bridge.
2. Edit as usual. The bars that you type are the bars of the bridge, so
   `3|` goes to bar 3 of the bridge, which is bar 19 of the song. To name
   a bar of the song, put `@` before it, for example `@19|`.
3. Press `K` to see the path, the bars and the meter of the bridge again.
4. Press `]z` to go to the next region of the song in the same window,
   and `[z` to come back to the bridge.
5. Press `zw` to return to the whole song.

The meter is part of the song, so the bridge plays in 6/8 in the song
too, and a tempo change of the song is heard in the bridge.

## Fold the section away

When you work on the rest of the song, you can fold the bridge into one
narrow column.

1. Put the cursor in the bridge and press `zfar`. The bridge shows as one
   column, `Bridge ▸ 8`, and the bars after it move left. The song still
   plays through it.
2. To work in the bridge again, press `znn` on the column. `zw` brings
   you back to the column, still folded.
3. To open the fold, press `za` on it.

## If some parts stay in the old meter

If the drums must stay in 4/4 under a bridge in 6/8, the meter can't be
in the song, because the song has one meter at each bar. Make the bridge
a subproject with parts and a meter of its own:

1. Type `17|` to go to bar 17.
2. Type `:nest.new Bridge 8 6/8 meter=own`. The message ends with
   `(the song's meter stays)`, and the window goes inside the
   subproject, with one empty part.
3. Add the parts of the bridge there. Inside the subproject, the ruler
   and the status line count bars of 6/8, and `3|` goes to bar 3. The
   song keeps its bars in 4/4.
4. Press `zw` to return to the song.

See [Subprojects](../reference/subprojects.md) for the details.

## See also

- [About scopes](../explanation/about-scopes.md)
- [Scopes](../reference/narrowing.md)
- [Tempo and time signatures](../reference/tempo.md)
