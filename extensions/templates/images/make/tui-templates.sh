#!/bin/sh
# Templates: the keys part saved with its chain and levels, and made again
# under another name in the same song. The program's home is a directory
# made for the scene, so that the path a template is saved to reads as a
# user's (~/.local/share/paw/templates).
. "$MAKE/rig.sh"
PAW_HOME=$(mktemp -d)
SETUP="$TUI_DEMO paw.opt.templates_dir = os.getenv('HOME') .. '/.local/share/paw/templates'
paw.ext.load('extensions/templates')"
rig_start
term_start
[ "$(ctl "return os.getenv('HOME')")" = "$PAW_HOME" ] || { echo "tui-templates: ~ is not $PAW_HOME"; rm -rf "$PAW_HOME"; exit 1; }
rec_start tui-templates
cap "\\Ts saves the part: its devices with their settings, levels and sends"
pause 0.5; key backslash T s; pause 0.5; TYPE_DELAY=110 typ "Soft keys"; key Return; pause 1.0
cap "\\Tl makes a template again, below the cursor's part: some of its name will do"
keys 0.3 j j; key backslash T l; pause 0.5; TYPE_DELAY=110 typ "soft"; pause 0.6; key Return; pause 1.2
cap "Space dd shows what it came with"
key space d d; pause 2.0
rec_stop
rm -rf "$PAW_HOME"
