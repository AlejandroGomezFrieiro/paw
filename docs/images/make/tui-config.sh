#!/bin/sh
# Configuration is Lua: init.lua edited in Neovim above the program, and
# :reload running it again while the song plays.
. "$MAKE/rig.sh"
SETUP=$TUI_DEMO
CONFIG=$D/.config/paw
EDIT=$CONFIG/init.lua
export EDIT
mkdir -p "$CONFIG"
printf -- '-- ~/.config/paw/init.lua\npaw.opt.zoom = 2.75\n' > "$EDIT"
rig_start
term_start
# Neovim, in the pane above, has the keyboard; pane down and pane up move
# it between the panes (tmux's keys, not the program's).
pane down; pause 0.4
rec_start tui-config
cap "Space Space plays; init.lua, above, is your configuration, in Lua"
pause 0.5; key space space; pause 1.2
pane up; pause 0.5
cap "Add a colour and a key to it, and write it"
key G o; TYPE_DELAY=35 typ 'paw.ui.hl("Playhead", { bg = "#f38ba8" })'
key Return; TYPE_DELAY=35 typ 'paw.keymap.set("<leader>tS", "part.add Strings device=synth")'
key Escape; key colon; typ "w"; key Return; pause 0.6
pane down; pause 0.4
cap ":reload runs it again without stopping the sound"
key colon; TYPE_DELAY=90 typ "reload"; key Return; pause 1.4
cap "Space tS, the new key, adds a part"
key space t S; pause 1.8
rec_stop
