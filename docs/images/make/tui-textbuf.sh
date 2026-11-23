#!/bin/sh
# The parts as a text buffer under the arrange view, edited with Vim's
# keys and written as a plan.
. "$MAKE/rig.sh"
SETUP=$TUI_DEMO
rig_start
term_start
rec_start tui-textbuf
cap ":sp paw://parts shows the parts as text, one a line"
pause 0.5; key colon; TYPE_DELAY=90 typ "sp paw://parts"; pause 0.3; key Return; pause 1.2
cap "Vim's own keys edit it: cw renames a part, 3 Ctrl-x takes 3 dB off"
keys 0.25 j j j; TYPE_DELAY=160 typ "cw"; TYPE_DELAY=100 typ "Melody"; key Escape; pause 0.5
keys 0.25 w w 3 ctrl+x; pause 0.9
cap ":w shows the plan; y applies it as one undo step"
key colon w Return; pause 2.0
key y; pause 2.0
rec_stop
