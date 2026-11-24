#!/bin/sh
# Recording round the loop into takes, and comping them. There is no
# keyboard here: a script plays a lead-in to the melody (bar 4) into the program
# through paw.midi.inject, as a MIDI controller would, a little differently
# each time round.
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO paw.api.engine_restart({ backend = 'null', test_midi = { 'Keys A' } })
paw.transport.loop_start, paw.transport.loop_end = 12, 16 paw.transport.loop_enabled = true paw.transport.seek(12)"
rig_start
term_start
# One time round the loop (a bar at 108 bpm), a phrase of four notes.
phrase() {
  for p in "$@"; do
    ctl "paw.midi.note_on($p, 96)" >/dev/null
    sleep 0.40
    ctl "paw.midi.note_off($p)" >/dev/null
    sleep 0.09
  done
}
feed() {
  phrase 76 74 71 68
  phrase 76 71 68 64
  phrase 76 74 72 71
}
key j; pause 0.4
rec_start tui-takes
cap "r arms the lead; R records round the loop, a take each time round"
pause 0.5; key r; pause 0.6; key R; feed & FEED=$!
pause 7.0; wait $FEED; key space space; pause 0.8
cap "zt shows the takes as lanes under the clip; the last one plays"
key z t; pause 1.6
cap "Comping: select the first half, :take 1 plays the first take there"
keys 0.12 3 W; keys 0.1 v 7 l; key colon; TYPE_DELAY=110 typ "take 1"; pause 0.4; key Return; pause 1.4
# The loop: hide the take lanes, undo the recording and the comp (two steps), disarm the lead.
key z t; pause 0.4; TYPE_DELAY=150 typ "2"; key u; pause 0.5; key r; pause 0.4
# The cursor and the playhead go back to where SETUP put them.
key 0; ctl "paw.transport.seek(12)" >/dev/null; pause 0.8
rec_stop
