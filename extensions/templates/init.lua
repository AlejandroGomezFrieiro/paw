-- Templates: a track, a group of tracks, or a chain of devices saved under a
-- name, to make again in any project. See README.md beside this file.
paw.option.define("templates_dir", "") -- where they are kept; "" is the data directory

require("templates")
require("templates.commands")
