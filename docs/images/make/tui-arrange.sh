#!/bin/sh
# The hero: the song playing while it is edited as a text is in Vim:
# motions, an operator with a count, `.`, undo, and a substitution
# previewed as it is typed.
. "$MAKE/rig.sh"
SETUP=$TUI_DEMO
rig_start
term_start
rec_start tui-arrange
cap "Space Space plays; j w move over tracks and clips as over lines and words"
pause 0.5; key space space; pause 0.6
keys 0.4 j w
cap "3>ic moves the clip three steps later, . does it again, u undoes"
TYPE_DELAY=200 typ "3>ic"; pause 0.8; key period; pause 0.8; key u; pause 0.5; key u; pause 0.6
cap ":%s changes notes, previewed as it is typed"
key colon; TYPE_DELAY=110 typ "%s/e5/g5/g"; pause 1.4; key Return; pause 1.4
rec_stop
