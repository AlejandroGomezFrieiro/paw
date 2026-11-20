-- Binary formats of the core: ZIP archives (paw.zip), base64 and the
-- compressed forms (paw.bytes, paw.api).
local T = ...
local test, eq = T.test, T.eq
local api = paw.api

test("zip: archives written and read again, and one the zip program deflated", function()
  local bytes = paw.zip.write({ { name = "a.txt", data = "hello" }, { name = "dir/b.bin", data = string.rep("\0\255", 1000) } })
  local files, names = paw.zip.read(bytes)
  eq(table.concat(names, ","), "a.txt,dir/b.bin", "names in order")
  eq(files["a.txt"], "hello", "a file back")
  eq(files["dir/b.bin"], string.rep("\0\255", 1000), "binary back")
  local fixtures = "extensions/interop/fixtures/dawproject/"
  local made = paw.zip.read(T.read_file(fixtures .. "studio.dawproject"))
  eq(made["project.xml"], T.read_file(fixtures .. "studio/project.xml"), "deflated XML")
  eq(made["audio/loop.wav"], T.read_file(fixtures .. "studio/audio/loop.wav"), "deflated audio")
  local none, why = paw.zip.read("not a zip")
  eq(none == nil and why:find("not a ZIP", 1, true) ~= nil, true, "not an archive: " .. tostring(why))
end)

test("bytes: base64 and compressed data, and where a compressed stream ends", function()
  local data = string.rep("paw\0\255", 300)
  eq(paw.bytes.unbase64(paw.bytes.base64(data)), data, "base64 there and back")
  eq(pcall(paw.bytes.unbase64, "*not*"), false, "text that is not base64 is refused")
  for _, format in ipairs({ "raw", "zlib", "gzip" }) do
    local packed = assert(api.deflate(data, format))
    local back, used = api.inflate(packed .. "tail", format)
    eq(back, data, format .. " there and back")
    eq(used, #packed, format .. ": the stream ends before what follows it")
  end
  eq(api.inflate("not compressed", "zlib"), nil, "bytes that are not zlib")
end)
