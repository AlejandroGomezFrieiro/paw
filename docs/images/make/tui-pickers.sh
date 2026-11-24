#!/bin/sh
# Finding things: the clips picker with its preview, the notes picker, and
# :vimgrep putting every match in the quickfix list, gone through with ]q.
. "$MAKE/rig.sh"
SETUP=$TUI_DEMO
rig_start
term_start
rec_start tui-pickers
cap "Space fc lists every clip; the pane on the right draws the one selected"
pause 0.4; key space f c; pause 1.0; TYPE_DELAY=150 typ "mel"; pause 1.2; key Escape; pause 0.3
cap "Space fn lists every note, and plays it with its chord as the selection rests"
key space f n; pause 0.6; TYPE_DELAY=120 typ "G5 mel"; pause 0.5; keys 0.5 ctrl+n ctrl+n; key Escape; pause 0.3
cap ":vimgrep finds text anywhere in the project and fills the quickfix list"
key colon; TYPE_DELAY=70 typ "vimgrep /^[CE]$/ clip"; key Return; pause 0.6
key colon; TYPE_DELAY=70 typ "copen"; key Return; pause 0.8
cap "]q goes to the next place found, wherever it is"
keys 0.8 bracketright q bracketright q; pause 1.0
# The loop: close the list and put the cursor back. The qf item of the status line
# stays until the next start.
key colon; TYPE_DELAY=70 typ "cclose"; key Return; pause 0.4; keys 0.2 j 0; pause 0.8
rec_stop
