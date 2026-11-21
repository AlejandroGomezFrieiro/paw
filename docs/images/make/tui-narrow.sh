#!/bin/sh
# A large project in small pieces: the demo song's tracks in two groups,
# one narrowed to with zn, a region narrowed to with :narrow, while the rest of the song plays from files
# (scope_rest=frozen), and a group frozen for good with :freeze.
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO local t = paw.tracks()
paw.groups.make({ t[1], t[2] }, 'Rhythm') paw.groups.make({ t[3], t[4] }, 'Harmony')
paw.markers.add(paw.time.bar_start(5), 'Chorus', { length = paw.time.bar_start(9) - paw.time.bar_start(5) })
paw.opt.scope_rest = 'frozen' paw.cursor.set_track(paw.tracks()[1]) paw.flush()"
rig_start
term_start
rec_start tui-narrow
cap "zn on a group: a tab of its tracks alone, the rest of the song played from files"
pause 0.5; key space space; pause 0.8; key z n; pause 2.4
cap "Motions, ranges and the mixer see only the group: :t* is its tracks"
keys 0.4 j j; key colon; TYPE_DELAY=110 typ "t* solo"; pause 1.0; key Escape; pause 0.4
cap "zw widens again; :narrow Chorus narrows to a region: its bars count from 1"
key z w; pause 1.0; key colon; TYPE_DELAY=110 typ "narrow Chorus"; key Return; pause 2.2
cap "zw again; :freeze renders a group and plays the file (F)"
key z w; pause 1.0; key space space; pause 0.4
key colon; TYPE_DELAY=110 typ "freeze Harmony"; key Return; pause 3.4
rec_stop
