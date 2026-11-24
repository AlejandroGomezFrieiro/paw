#!/bin/sh
# The file manager: a folder of sounds edited as text, after oil.nvim. A
# file renamed, one moved into a folder by its name, one deleted, and :w
# showing the plan before doing it. The program's home is a directory
# made for the scene (in /tmp, so that the path shown is short, as the
# utau scenes' sockets are), and ~/music the folder made in it.
. "$MAKE/rig.sh"
PAW_HOME=$(mktemp -d)
MUSIC=$PAW_HOME/music
mkdir -p "$MUSIC/samples" "$MUSIC/loops"
tone() { ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=$2:duration=$3" -ac "$4" -ar 44100 "$MUSIC/$1"; }
tone samples/kick.wav 60 0.4 1
tone samples/snare.wav 180 0.3 1
tone samples/hat.wav 4000 0.1 1
tone loops/break.wav 120 4.4 2
tone pad.wav 220 4 2
tone take3.wav 440 2.5 2
tone "vox idea.wav" 330 6 2
printf 'bass from bar 5\n' > "$MUSIC/notes.txt"
SETUP=$TUI_DEMO
rig_start
term_start
rec_start tui-files
cap ":e ~/music shows the folder as text, a line for each file"
pause 0.5; key colon; TYPE_DELAY=110 typ "e ~/music"; key Return; pause 1.3
cap "cw renames a file; a path in its name moves it"
keys 0.3 G k; TYPE_DELAY=140 typ "cw"; TYPE_DELAY=100 typ "lead-take"; key Escape; pause 0.6
key k; TYPE_DELAY=100 typ "0isamples/"; key Escape; pause 0.6
cap "dd deletes (to the trash); :w shows the plan, y does it"
key G d d; pause 0.6
key colon w Return; pause 1.8
key y; pause 1.2
cap "Enter on a folder goes in, - goes back up"
keys 0.25 g g j; key Return; pause 1.1; key minus; pause 1.1
# The loop: back to the arrange view, where the scene started.
key colon; TYPE_DELAY=90 typ "e arrange"; key Return; pause 1.0
rec_stop
rm -rf "$PAW_HOME"
