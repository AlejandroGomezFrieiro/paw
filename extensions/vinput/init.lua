-- Virtual inputs: chains that turn something else into an input a track can
-- take. The kind there is so far turns a guitar into MIDI with gdi2m.
-- See README.md beside this file.
paw.option.define("vinput_gdi2m", "") -- the gdi2m program; "" looks for it
paw.option.define("vinput_file", "") -- where the inputs are kept between runs; "" is the state directory
paw.option.define("vinput_run", "auto", { type = { "string", "boolean" }, values = { "auto", true, false } }) -- run the trackers: "auto" (with a real audio device), true, false

require("vinput")
require("vinput.gdi2m")
require("vinput.run")
require("vinput.panel")
require("vinput.gui")
require("vinput.commands")
require("vinput").load()
