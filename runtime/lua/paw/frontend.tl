-- What a graphical frontend needs to draw the project, in one call.
--
-- A frontend polls `paw.frontend.state(known)` many times a second. The
-- answer always holds what moves on its own (transport position, meters). The
-- project itself is only included when it has changed since revision `known`,
-- so an idle project costs almost nothing to watch. Waveforms are a separate
-- call, `paw.frontend.peaks(clip)`, made only when a clip's `waveform` changes.
--
-- The module is in parts, in paw/frontend/: core.tl holds the table and
-- the records that it gives, host.tl what the parts read of `paw`,
-- state.tl the state, dialogs.tl what the window asks for its dialogs,
-- and act/ the pointer's gestures (`paw.frontend.act`), one file for
-- each area.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local M = require("paw.frontend.core")
require("paw.frontend.state")
require("paw.frontend.dialogs")
require("paw.frontend.act.clips")
require("paw.frontend.act.tempo")
require("paw.frontend.act.timeline")
require("paw.frontend.act.window")
require("paw.frontend.act.routing")
require("paw.frontend.act.parts")
require("paw.frontend.act.notes")
require("paw.frontend.act.lanes")
require("paw.frontend.act.devices")

return M
