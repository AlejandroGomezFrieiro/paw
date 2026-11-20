-- ZIP archives, for the file formats that are one (DAWproject, MusicXML's
-- .mxl, a .dslibrary).
--
--   local files, names = paw.zip.read(bytes)   -- { ["project.xml"] = "..." } and the names in order; nil and why if it is no archive
--   local bytes = paw.zip.write({ { name = "project.xml", data = xml }, ... })
--
-- Reading takes entries stored or compressed with deflate. Writing stores
-- them as they are (method 0), which every reader of ZIP files takes.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local bytes = require("paw.bytes")

local record M
  --- An entry of an archive to write: its name in the archive, and its bytes.
  record Entry
    name: string
    data: string
  end
end

local u16, u32, p16, p32 = bytes.u16, bytes.u32, bytes.le16, bytes.le32

--- The entries of an archive: a table of name to contents, and the list of
--- names in the order of the archive (folders left out). Nil and why when
--- it is not a ZIP archive or an entry cannot be read.
function M.read(data: string): {string:string}, {string} | string
  -- The end of the central directory is in the last 64 KiB + 22 bytes.
  local eocd: integer
  for at = #data - 21, math.max(1, #data - 65557), -1 do
    if data:sub(at, at + 3) == "PK\5\6" then
      eocd = at
      break
    end
  end
  if not eocd then return nil, "not a ZIP archive (no central directory)" end
  local count, at = u16(data, eocd + 10), u32(data, eocd + 16) + 1
  local files: {string:string} = {}
  local names: {string} = {}
  for _ = 1, count do
    if data:sub(at, at + 3) ~= "PK\1\2" then return nil, "a broken ZIP central directory" end
    local method, size = u16(data, at + 10), u32(data, at + 20)
    local name_len, extra_len, comment_len = u16(data, at + 28), u16(data, at + 30), u16(data, at + 32)
    local local_at = u32(data, at + 42) + 1
    local name = data:sub(at + 46, at + 45 + name_len)
    at = at + 46 + name_len + extra_len + comment_len
    if data:sub(local_at, local_at + 3) ~= "PK\3\4" then return nil, "a broken ZIP entry: " .. name end
    local start = local_at + 30 + u16(data, local_at + 26) + u16(data, local_at + 28)
    local raw = data:sub(start, start + size - 1)
    if not name:match("/$") then
      if method == 0 then
        files[name] = raw
      elseif method == 8 then
        local inflated, why = api.inflate(raw, "raw") as (string, string)
        if not inflated then return nil, name .. ": " .. why end
        files[name] = inflated
      else
        return nil, string.format("ZIP entry %s uses compression method %d, which paw cannot read", name, method)
      end
      names[#names + 1] = name
    end
  end
  return files, names
end

--- An archive of `entries` (`{ name = , data = }` each, in order), stored
--- without compression.
function M.write(entries: {M.Entry}): string
  local parts, central: {string}, {string} = {}, {}
  local offset = 0
  for _, e in ipairs(entries) do
    local crc, size = api.crc32(e.data), #e.data
    -- Version 20, flag 0x800 (the name is UTF-8), method 0, time 0:00 on 1 Jan 1980.
    local head = p16(20) .. p16(0x800) .. p16(0) .. p16(0) .. p16(33) .. p32(crc) .. p32(size) .. p32(size)
      .. p16(#e.name)
    parts[#parts + 1] = "PK\3\4" .. head .. p16(0) .. e.name
    parts[#parts + 1] = e.data
    central[#central + 1] = "PK\1\2" .. p16(20) .. head .. p16(0) .. p16(0) .. p16(0) .. p16(0) .. p32(0)
      .. p32(offset) .. e.name
    offset = offset + 30 + #e.name + size
  end
  local dir = table.concat(central)
  return table.concat(parts) .. dir .. "PK\5\6" .. p16(0) .. p16(0) .. p16(#entries) .. p16(#entries)
    .. p32(#dir) .. p32(offset) .. p16(0)
end

return M
