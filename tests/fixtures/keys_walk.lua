-- Run by tests/keys_constitution.lua in a kernel of its own, so that loading
-- every bundled extension does not change the suite's: the key rule over
-- every view's mappings, and Escape staying in the extensions' views.
-- Prints one line for each thing wrong, each starting `wrong:`, then `done`
-- (messages the program shows are printed too, and are not counted).
--   paw --clean --no-plugins --no-listen --audio null -l tests/fixtures/keys_walk.lua
local api = paw.api
for _, entry in ipairs(api.read_dir("extensions")) do
  if
    entry.is_dir
    and (io.open("extensions/" .. entry.name .. "/init.lua") or io.open("extensions/" .. entry.name .. "/init.tl"))
  then
    local ok, err = pcall(paw.ext.load, "extensions/" .. entry.name)
    if not ok or not (paw.ext.loaded[entry.name] and paw.ext.loaded[entry.name].ok) then
      print("wrong: load " .. entry.name .. ": " .. tostring(err or paw.ext.loaded[entry.name].error))
    end
  end
end
for _, line in ipairs(paw.keyrule.broken()) do
  print("wrong: rule " .. line)
end
for _, line in ipairs(paw.keyrule.lost_groups()) do
  print("wrong: group " .. line .. " leads to nothing")
end

-- The leader keys are a domain, then a verb or an object (docs/reference/keys.md):
-- the key after the leader is one of these, with this name, in every view.
local domains = {
  a = "automation",
  c = "clip",
  d = "devices",
  f = "find",
  g = "versions",
  h = "tutor",
  l = "language servers",
  m = "mix",
  n = "notation",
  p = "project",
  r = "markers and regions",
  t = "tracks",
  T = "tempo and transport",
  u = "utau",
  v = "views",
  z = "scopes",
}
local leader = table.concat(paw.keymap.parse("<leader>"))
local groups = paw.keymap.groups()
for _, map in ipairs(paw.keymap.every()) do
  local keys = map.keys
  if (map.mode == "n" or map.mode == "x") and keys[1] == leader and #keys >= 2 and map.role ~= "play" then
    local domain = keys[2]
    local prefix = leader .. domain
    local name = (groups[map.scope] or {})[prefix] or (groups.global or {})[prefix]
    if #keys == 2 then
      print("wrong: domain " .. map.scope .. " " .. map.lhs .. ": one key after the leader, not a domain and a key")
    elseif domains[domain] == nil then
      print("wrong: domain " .. map.scope .. " " .. map.lhs .. ": " .. domain .. " is not a domain of the leader")
    elseif name ~= domains[domain] then
      print(
        "wrong: domain "
          .. map.scope
          .. " "
          .. map.lhs
          .. ": the group is "
          .. tostring(name)
          .. ", not "
          .. domains[domain]
      )
    end
  end
end

-- Escape cancels and stays.
local t = paw.add_track({ name = "Keys" })
t:add_device("synth")
t:add_clip({ name = "c", start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
api.undo_checkpoint()
paw.cursor.set_track(t)
paw.cursor.set_beat(0)
local function stays(name, open)
  paw.ui.focus("arrange")
  local ok, err = pcall(open)
  if not ok then return print("wrong: escape " .. name .. ": did not open: " .. tostring(err)) end
  if paw.ui.focused ~= name then return print("wrong: escape " .. name .. ": did not open") end
  paw.keymap.feed("3<Esc><Esc><Esc>")
  if paw.ui.focused ~= name then print("wrong: escape " .. name .. ": left for " .. tostring(paw.ui.focused)) end
  if paw.keymap.pending() ~= "" then
    print("wrong: escape " .. name .. ": left " .. paw.keymap.pending() .. " typed")
  end
end
stays("drums", function()
  local beat = require("drums").make_track({ name = "Beat" })
  beat:add_clip({ start = 0, length = 4 })
  paw.cursor.set_track(beat)
  paw.keymap.feed("<CR>")
end)
stays("notation", function()
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  paw.keymap.feed("<localleader>n")
end)
stays("vinput", function()
  paw.ui.show("vinput")
  paw.ui.focus("vinput")
end)
print("done")
api.quit(0)
