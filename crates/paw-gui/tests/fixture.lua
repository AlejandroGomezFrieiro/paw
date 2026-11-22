-- The song the window's in-process tests are drawn from (src/tests.rs):
-- `tests/fixture.sh` runs this in a kernel and keeps what the kernel tells
-- a window, in tests/fixture.json.
local api = paw.api
paw.project.tempo = 120
local a = paw.add_track({ name = "A" })
a:add_clip({
  start = 4,
  length = 4,
  name = "c",
  notes = {
    { pitch = 60, start = 0, length = 1 },
    { pitch = 64, start = 1, length = 1 },
    { pitch = 67, start = 2, length = 2 },
  },
})
local b = paw.add_track({ name = "B" })
b:add_clip({ start = 12, length = 4, name = "d", notes = { { pitch = 48, start = 0, length = 4 } } })
paw.add_track({ name = "C" })
paw.markers.add(8, "Verse")
local lane = a:automate("volume")
lane:set_points({ { 0, -12 }, { 8, 0 } })
paw.lanes.open(a)
paw.tempo.set(16, 140)
a:add_device("synth")
paw.cursor.set_track(a.id)
api.undo_checkpoint()
