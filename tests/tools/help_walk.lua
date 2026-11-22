-- Run by tests/help_owners.lua in a kernel of its own (loading every
-- bundled extension would change what the suite's other tests see): asks
-- `:help` for every command and key an extension owns and prints where it
-- lands. `WALKED n` is the count; `WRONG` a topic that left its
-- extension's pages; `UNNAMED` one that found only the extension's page.
local paw = require("paw")
for _, name in ipairs(paw.ext.bundled()) do
  paw.ext.load_bundled(name)
end
local walked = 0
local function check(topic, owners)
  walked = walked + 1
  local tag = paw.help.lookup(topic)
  local ext = tag and tag.source.ext
  local ok = false
  for _, o in ipairs(owners) do
    ok = ok or ext == o
  end
  if not ok then
    print(
      "WRONG "
        .. topic
        .. " ("
        .. table.concat(owners, "/")
        .. ") -> "
        .. (tag and (tag.source.name .. "#" .. tag.name) or "nothing")
    )
  elseif tag.name == ext then
    print("UNNAMED " .. topic .. " (" .. ext .. ")")
  end
end
for _, spec in ipairs(paw.commands.list()) do
  if spec.ext and paw.ext.loaded[spec.ext] and paw.ext.loaded[spec.ext].ok then
    check(":" .. spec.name, { spec.ext })
  end
end
local seen = {}
for _, map in ipairs(paw.keymap.every()) do
  local topic = paw.keymap.human(map.lhs)
  if map.ext and not seen[topic] then
    seen[topic] = true
    local owners = paw.help.owners(topic)
    if #owners > 0 then check(topic, owners) end
  end
end
for topic, ext in pairs({ [":drums.track"] = "drums", [":art.measure"] = "articulations", [":Pdiff"] = "projdiff" }) do
  if paw.help.lookup(topic).source.ext ~= ext then print("WRONG " .. topic .. " (" .. ext .. ")") end
end
if paw.help.lookup("gU").source.ext ~= nil then print("WRONG gU is the core's") end
print("WALKED " .. walked)
os.exit(0)
