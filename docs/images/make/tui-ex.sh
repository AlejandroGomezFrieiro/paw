#!/bin/sh
# Ex over bars and parts: a substitution confirmed match by match, then
# parts muted by a range.
. "$MAKE/rig.sh"
SETUP=$TUI_DEMO
rig_start
term_start
rec_start tui-ex
cap ":%s/c5/d5/gc previews every match; Enter asks about each"
pause 0.5; key colon; TYPE_DELAY=110 typ "%s/c5/d5/gc"; pause 1.2
key Return; pause 0.8
cap "y yes, n no, a all the rest; u undoes the whole line at once"
keys 0.6 y n a; pause 0.8; key u; pause 1.0
cap ":t2,t4 mute is a range of parts, previewed too; :t* unmute"
key colon; TYPE_DELAY=110 typ "t2,t4 mute"; pause 1.2; key Return; pause 1.0
key colon; TYPE_DELAY=110 typ "t* unmute"; pause 0.6; key Return; pause 1.0
rec_stop
