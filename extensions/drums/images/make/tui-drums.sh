#!/bin/sh
# The drum grid in the terminal, on the demo song's drums: claps put in by
# name, a hit made harder, the bar repeated, and played.
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO paw.ext.load('extensions/drums') paw.cursor.set_part(paw.parts()[1]) paw.cmd('drums.map', { 'gm' })"
rig_start
term_start
rec_start tui-drums
cap "Enter on a drum part's clip opens the grid: a row for each piece"
pause 0.5; key Return; pause 1.4
cap "/ finds a piece by name; Enter puts a hit in, and it is heard"
key slash; TYPE_DELAY=110 typ "clap"; key Return; pause 0.5
keys 0.3 4 l Return; keys 0.3 8 l Return; pause 0.6
cap "+ - make the hit under the cursor harder or softer"
keys 0.3 minus minus minus; pause 0.6

cap "& repeats the bar to the end of the clip; Space Space plays"
key ampersand; pause 0.8; key space space; pause 3.0; key space space; pause 0.4
rec_stop
