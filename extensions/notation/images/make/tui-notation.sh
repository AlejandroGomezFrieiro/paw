#!/bin/sh
# The score: the melody's open last bar entered by name, then a hairpin
# written with the popover, previewed before it is written, and played.
. "$MAKE/rig.sh"
SETUP=$TUI_NOTATION
rig_start
term_start
key j w; pause 0.4
rec_start tui-notation
cap "\\n opens the clip as a score, engraved in the terminal"
pause 0.5; key backslash n; pause 1.3
cap "i enters notes by name: 6 a half, 5 a quarter; + sharpens"
keys 0.15 W W W
key i; pause 0.2; keys 0.28 6 e 5 b g plus; key Escape; pause 0.7
cap "v selects; \\d mp<f writes a hairpin, heard and drawn before Enter"
keys 0.15 0 v W W
key backslash d; pause 0.2; TYPE_DELAY=140 typ "mp<f"; pause 1.3
still tui-notation.png
key Return; pause 0.7
cap "gp puts the playhead at the cursor; Space Space plays what is written"
key g p; pause 0.2; key space space; pause 3.2; key space space; pause 0.4
rec_stop
