#!/bin/sh
# A pattern clip for the lead's empty first half, typed as a line of text
# and changed while the song plays.
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO paw.ext.load('extensions/pattern')"
rig_start
term_start
key j; pause 0.4
rec_start tui-pattern
cap "Space Space plays; \\tt makes a clip from a line of text, in TidalCycles' manner"
pause 0.5; key space space; pause 0.4; key backslash t t; pause 0.6
TYPE_DELAY=80 typ "a4 c5 e5 [d5 c5] # legato 0.8"; pause 0.6; key Return; pause 1.6
cap "\\tt again edits it: the clip follows the text"
key backslash t t; pause 0.5; key ctrl+u; TYPE_DELAY=80 typ "a4 <c5 e5> e5*2 [g5 e5 d5] # legato 0.8"; pause 0.6
key Return; pause 2.6
key space space; pause 0.4
rec_stop
