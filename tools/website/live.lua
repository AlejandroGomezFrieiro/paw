-- Turns the live paw directives of the staged Markdown into live paw
-- panels (tools/website/build.sh, live.js, web/browserpod/site/paw-live.js).
--
-- usage: lua live.lua <staged-root>
--
-- A page asks for a live paw with an HTML comment on a line of its own:
--
--   <!-- paw-live: {"project": "demo-song", "scope": "Melody"} -->
--
-- GitHub and :help do not show a comment, so the page reads the same there.
-- On the website, the line becomes a panel with a button that starts paw
-- at the state that the JSON gives (paw-pod.js, PawPod.open). The script fails on a
-- directive with a key that the state does not know, or with a quote that
-- the attribute cannot hold.

local root = assert(arg[1], "usage: lua live.lua <staged-root>")
local KEYS = { project = true, scope = true, lesson = true, keys = true, empty = true }
local LABEL = "Try the steps in your browser"

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function write(path, s)
  local f = assert(io.open(path, "wb"))
  f:write(s)
  f:close()
end

local bad = {}
local function element(page, state)
  if not state:match("^{.*}$") or state:find("'", 1, true) then
    bad[#bad + 1] = page .. ": the state is not a JSON object without ': " .. state
    return ""
  end
  for key in state:gmatch('"([%w_]+)"%s*:') do
    if not KEYS[key] then bad[#bad + 1] = page .. ": the state has no key " .. key end
  end
  -- A line of its own, so that Markdown keeps it as HTML.
  return ('<div class="paw-live" data-paw-live data-paw-label="%s" data-paw-state=\'%s\'></div>'):format(LABEL, state)
end

local count = 0
local p = assert(io.popen('cd "' .. root .. '" && find . -name "*.md" | sed "s|^\\./||" | sort'))
for page in p:lines() do
  local path = root .. "/" .. page
  local text = read(path)
  if text:find("<!-- paw-live:", 1, true) then
    local out = text:gsub("\n<!%-%- paw%-live: (.-) %-%->\n", function(state)
      count = count + 1
      return "\n" .. element(page, state) .. "\n"
    end)
    write(path, out)
  end
end
p:close()

if #bad > 0 then
  for _, line in ipairs(bad) do
    io.stderr:write("BAD paw-live " .. line .. "\n")
  end
  os.exit(1)
end
print(("live.lua: %d live paw directives"):format(count))
