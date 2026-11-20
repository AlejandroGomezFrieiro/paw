#!/bin/sh
# Everyday note edits as operators, on the demo song's chords in the piano
# roll: arpeggiate, strum, humanize, each undone or played.
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO paw.ext.load('extensions/musicops')"
rig_start
term_start
key Return; pause 1.0
rec_start tui-musicops
cap "gzp arpeggiates: gzpie, every chord of the clip"
pause 0.5; TYPE_DELAY=180 typ "gzpie"; pause 2.2; key u; pause 0.6
cap "gzs strums them instead; gzh humanizes, nudging starts and velocities"
TYPE_DELAY=180 typ "gzsie"; pause 1.4; TYPE_DELAY=180 typ "gzhie"; pause 1.4
cap "Space Space plays what the operators made"
key space space; pause 3.6; key space space; pause 0.4
rec_stop
