-- Writes the SUMMARY.md of the website (the sidebar) from docs/README.md.
--
-- usage: lua summary.lua <staged-root>
--
-- The staged root holds README.md, docs/ and extensions/ as the repository
-- has them, so every relative link of every page works as it does on GitHub.
-- The sidebar follows docs/README.md: its `##` headings are the parts, its
-- `###` headings are groups, and its list items are the chapters. A page
-- that the contents omit goes under "More pages", and each extension has a
-- part of its own.

local root = assert(arg[1], "usage: summary.lua <staged-root>")

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function lines(path)
  local t = {}
  for l in (read(path) or ""):gmatch("([^\n]*)\n?") do
    t[#t + 1] = l
  end
  return t
end

local function h1(path)
  for _, l in ipairs(lines(path)) do
    local t = l:match("^# (.+)$")
    if t then return (t:gsub("`", "")) end
  end
  return path
end

-- Every Markdown file of the staged tree, as a path relative to the root.
local md = {}
do
  local p = io.popen('cd "' .. root .. '" && find . -name "*.md" | sed "s|^\\./||" | sort')
  for l in p:lines() do
    md[#md + 1] = l
  end
  p:close()
end

local function normalize(path)
  local parts = {}
  for seg in path:gmatch("[^/]+") do
    if seg == ".." then
      parts[#parts] = nil
    elseif seg ~= "." then
      parts[#parts + 1] = seg
    end
  end
  return table.concat(parts, "/")
end

local out, seen = {}, {}

local function chapter(level, title, path)
  seen[path] = true
  out[#out + 1] = string.rep("  ", level) .. "- [" .. title .. "](" .. path .. ")"
end

out[#out + 1] = "# Summary\n"
out[#out + 1] = "[paw](README.md)"
seen["README.md"] = true
out[#out + 1] = "[The paw manual](docs/README.md)\n"
seen["docs/README.md"] = true

-- docs/README.md: parts, groups and chapters.
local level, current = 0, ""
for _, l in ipairs(lines(root .. "/docs/README.md")) do
  local part = l:match("^## (.+)$")
  local group = l:match("^### (.+)$")
  if part then
    current = part
    -- "Start here" repeats pages that the other parts list in their place.
    if part ~= "Start here" then out[#out + 1] = "\n# " .. part .. "\n" end
    level = 0
  elseif group then
    out[#out + 1] = "- [" .. group .. "]()"
    level = 1
  else
    local indent, title, target = l:match("^(%s*)%- %[(.-)%]%(([^)]-)%)")
    if title and current ~= "Start here" and not target:match("^%a+:") and not target:find("#", 1, true) then
      local path = normalize("docs/" .. target)
      if path:match("%.md$") and not seen[path] and read(root .. "/" .. path) then
        chapter(level + math.floor(#indent / 2), (title:gsub("`", "")), path)
      end
    end
  end
end

-- Pages that the contents omit.
local rest = {}
for _, path in ipairs(md) do
  if not seen[path] and path:match("^docs/") then rest[#rest + 1] = path end
end
if #rest > 0 then
  out[#out + 1] = "\n# More pages\n"
  for _, path in ipairs(rest) do
    chapter(0, h1(root .. "/" .. path), path)
  end
end

-- One part for the extensions.
local exts = {}
for _, path in ipairs(md) do
  if path:match("^extensions/[^/]+/README%.md$") then exts[#exts + 1] = path end
end
if #exts > 0 then
  out[#out + 1] = "\n# Extensions\n"
  for _, path in ipairs(exts) do
    chapter(0, (path:match("^extensions/([^/]+)/")), path)
    local dir = path:gsub("README%.md$", "")
    for _, sub in ipairs(md) do
      if sub:sub(1, #dir + 4) == dir .. "doc/" and not seen[sub] then chapter(1, h1(root .. "/" .. sub), sub) end
    end
  end
end

-- The crates, and the rules for people who change paw.
local crates = {}
for _, path in ipairs(md) do
  if path:match("^crates/[^/]+/README%.md$") then crates[#crates + 1] = path end
end
if #crates > 0 or read(root .. "/AGENTS.md") then
  out[#out + 1] = "\n# Work on paw\n"
  if read(root .. "/AGENTS.md") then chapter(0, "Instructions for agents and maintainers", "AGENTS.md") end
  for _, path in ipairs(crates) do
    chapter(0, h1(root .. "/" .. path), path)
  end
end

local f = assert(io.open(root .. "/SUMMARY.md", "wb"))
f:write(table.concat(out, "\n"), "\n")
f:close()
