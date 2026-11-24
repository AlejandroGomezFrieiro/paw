#!/bin/sh
# A large project in small pieces: the demo song's parts in two groups,
# one narrowed to with znn, a region narrowed to with :narrow, while the rest of the song plays from files
# (scope_rest=frozen), and a group frozen for good with :freeze.
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO local t = paw.parts()
paw.groups.make({ t[1], t[2] }, 'Rhythm') paw.groups.make({ t[3], t[4] }, 'Harmony')
paw.markers.add(paw.time.bar_start(5), 'Chorus', { length = paw.time.bar_start(9) - paw.time.bar_start(5) })
paw.opt.scope_rest = 'frozen' paw.cursor.set_part(paw.parts()[1]) paw.flush()"
rig_start
term_start
rec_start tui-narrow
cap "znn on a group shows its parts alone; the rest plays from files"
pause 0.5; key space space; pause 0.8; key z n n; pause 2.4
cap "Motions, ranges and the mixer see only the group: :t* is its parts"
keys 0.4 j j; key colon; TYPE_DELAY=110 typ "t* solo"; pause 1.0; key Escape; pause 0.4
cap "zw widens; :narrow Chorus narrows to a region, counted from bar 1"
key z w; pause 1.0; key colon; TYPE_DELAY=110 typ "narrow Chorus"; key Return; pause 2.2
cap "zw again; :freeze renders a group and plays the file (F)"
# :freeze is refused while the render of the rest of the song runs: the pause lets it end.
key z w; pause 2.5; key space space; pause 0.4
key colon; TYPE_DELAY=110 typ "freeze Harmony"; key Return; pause 3.4
# The loop: thaw the group and put the cursor and the playhead back.
key colon; TYPE_DELAY=90 typ "unfreeze Harmony"; key Return; pause 0.8
keys 0.2 g g 0 g s; pause 0.6
rec_stop
