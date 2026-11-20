-- The shapes of the data that crosses `paw.api`, for the modules written in
-- Teal and for runtime/types/paw.d.tl, which names them as `types.Name` in
-- the kernel's signatures (`// @param` and `// @return` in api.rs).
--
--   local type types = require("paw.types")
--   local attr: types.NoteAttr = { type = 0x11, data = 0xA000 }
--
-- It holds types only: at run time it is an empty table.

local record types
  --- How `paw.api.base64_encode` writes: `url` for the URL alphabet (`-_`),
  --- `pad = false` for no `=` at the end.
  record Base64Options
    url: boolean
    pad: boolean
  end

  --- The MIDI 2.0 attribute of a note's start (`paw.attr`): its type, and
  --- sixteen bits of data.
  record NoteAttr
    type: integer
    data: integer
  end
end

return types
