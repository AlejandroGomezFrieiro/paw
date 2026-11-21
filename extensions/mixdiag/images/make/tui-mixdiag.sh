#!/bin/sh
# Mix diagnostics: the bass pushed far too loud, the song measured, and what
# is wrong listed as findings with places to jump to.
. "$MAKE/rig.sh"
SETUP="$TUI_DEMO paw.ext.load('extensions/mixdiag')"
rig_start
term_start
rec_start tui-mixdiag
cap "A mistake to find: the bass 14 dB up (k, 14+)"
pause 0.5; key k; pause 0.3; keys 0.12 1 4 plus; pause 0.8
cap "Space ma measures the song, rendered in memory, as a language server checks code"
key space m a; pause 4.0
cap "Space mx lists the findings: what is wrong, by how much, what would fix it"
key space m x; pause 3.0
rec_stop
