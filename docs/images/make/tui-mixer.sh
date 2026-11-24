#!/bin/sh
# The mixer while the song plays, a device added from the picker (which
# plays what it would add), and its parameters.
. "$MAKE/rig.sh"
SETUP=$TUI_DEMO
rig_start
term_start
rec_start tui-mixer
cap "Space Space plays; Space mm opens the mixer"
pause 0.5; key space space; pause 0.3; key space m m; pause 1.0
cap "l picks a strip; + - move its fader; gcc mutes it, again unmutes"
key l; pause 0.3; keys 0.25 plus plus minus
key g c c; pause 0.8; key g c c; pause 0.5
cap "a adds a device: the picker plays each one before you choose"
key a; pause 0.4; TYPE_DELAY=180 typ "chor"; pause 1.2
key Return; pause 0.8
cap "Space dd shows its parameters: j k pick one, + - change it"
key space d d; pause 0.6
keys 0.25 G k k k; keys 0.15 3 0 plus; pause 0.6; keys 0.15 2 0 plus; pause 1.0
key space space; pause 0.4
# The loop: close the panel and the mixer, undo the eight changes (three fader
# keys, two mutes, the device, two parameters), and put the playhead and the cursor back.
key space d d; pause 0.5; key space m m; pause 0.5
TYPE_DELAY=150 typ "8"; key u; pause 0.6; keys 0.2 g s k; pause 0.8
rec_stop
