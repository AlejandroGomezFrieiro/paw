-- Write the demo projects of the pod image (web/browserpod/default.nix):
--
--   paw --clean --no-plugins --audio null -l web/browserpod/make-home.lua DIR
--
-- DIR/demo-song is the demo song of examples/demo-song.lua as a project
-- folder, with two regions, so that a page can open it at a scope
-- (`:narrow Chords`). Run from the top of the source tree.
local dir = assert(..., "usage: make-home.lua DIR")
dofile("examples/demo-song.lua")
paw.markers.add(0, "Chords", { length = 16 })
paw.markers.add(16, "Melody", { length = 16 })
paw.flush()
paw.ex.exec("w " .. dir .. "/demo-song")
print("wrote " .. dir .. "/demo-song")
