-- Checks the links of the built website.
--
-- usage: lua linkcheck.lua <staged-root> <site-dir> <repo-root> <repo-url>
--
-- Each relative link of each page must reach a file of the site, and a
-- fragment must name an id on that page. A link that leaves the site for a
-- file of the repository (a source file, for example) is not an error: the
-- script points it at the repository on GitHub, where it shows. The script
-- exits with 1 on any other broken link.

local site = assert(arg[2])
local repo = assert(arg[3])
local url = assert(arg[4])

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function isdir(path)
  local f = io.open(path .. "/.", "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local pages = {}
do
  local p = io.popen('cd "' .. site .. '" && find . -name "*.html" | sed "s|^\\./||" | sort')
  for l in p:lines() do
    pages[#pages + 1] = l
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

local ids = {}
local function idsof(page)
  if ids[page] then return ids[page] end
  local set = {}
  for id in (read(site .. "/" .. page) or ""):gmatch('%sid="([^"]+)"') do
    set[id] = true
  end
  ids[page] = set
  return set
end

local function unescape(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local broken, total, rewritten = {}, 0, 0
for _, page in ipairs(pages) do
  if page ~= "print.html" and page ~= "toc.html" and page ~= "404.html" then
    local html = read(site .. "/" .. page)
    local dir = page:match("^(.*)/[^/]*$") or ""
    local changed = false
    html = html:gsub('(<a [^>]-href=")([^"]*)(")', function(pre, href, post)
      if href:match("^%a[%w+.-]*:") or href:match("^//") or href:sub(1, 1) == "/" then return nil end
      total = total + 1
      local path, frag = href:match("^([^#]*)#?(.*)$")
      path = unescape(path)
      local target = page
      if path ~= "" then
        target = normalize((dir ~= "" and dir .. "/" or "") .. path)
        if target == "" or path:match("/$") then target = target .. "/index.html" end
        target = target:gsub("^/", "")
      end
      if exists(site .. "/" .. target) then
        if frag ~= "" and target:match("%.html$") and not idsof(target)[unescape(frag)] then
          broken[#broken + 1] = page .. ": #" .. frag .. " is not on " .. target
        end
        return nil
      end
      -- Not on the site: a file of the repository, which GitHub shows.
      local source = target:gsub("%.html$", ".md")
      for _, candidate in ipairs({ target, source }) do
        local d = isdir(repo .. "/" .. candidate)
        if d or exists(repo .. "/" .. candidate) then
          rewritten = rewritten + 1
          changed = true
          return pre
            .. url
            .. (d and "/tree/main/" or "/blob/main/")
            .. candidate
            .. (frag ~= "" and "#" .. frag or "")
            .. post
        end
      end
      broken[#broken + 1] = page .. ": " .. href .. " (" .. target .. " is not on the site or in the repository)"
      return nil
    end)
    if changed then
      local f = assert(io.open(site .. "/" .. page, "wb"))
      f:write(html)
      f:close()
    end
  end
end

print(
  string.format(
    "%d pages, %d relative links, %d broken, %d to repository files that the site sends to GitHub",
    #pages,
    total,
    #broken,
    rewritten
  )
)
for _, b in ipairs(broken) do
  print("BROKEN " .. b)
end
os.exit(#broken == 0 and 0 or 1)
