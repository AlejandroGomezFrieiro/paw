-- What the core does once for many extensions: files without a shell, and
-- the codecs and helpers they share. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api

test("files without a shell: exists, a copy of a folder, removing what paw made, the free space, a program on the PATH", function()
  local dir = T.scratch .. "/shared-fs"
  api.fs_mkdir(dir .. "/a/b")
  local f = assert(io.open(dir .. "/a/b/x.txt", "w"))
  f:write("x")
  f:close()
  eq(api.fs_exists(dir .. "/a/b/x.txt"), true, "a file is there")
  eq(api.fs_exists(dir .. "/nothing"), false, "nothing is not")
  api.fs_copy(dir .. "/a", dir .. "/c")
  eq(api.fs_stat(dir .. "/c/b/x.txt").size, 1, "a folder is copied with what it holds")
  eq(pcall(api.fs_copy, dir .. "/a", dir .. "/c"), false, "a copy never overwrites")
  api.fs_remove(dir)
  eq(api.fs_exists(dir), false, "a folder paw made is removed with what it holds")
  local space = api.fs_space(T.scratch)
  eq(space.total >= space.free and space.free > 0, true, "the space of the disk")
  eq(api.which("sh") ~= nil and api.which("sh"):match("/sh$") ~= nil, true, "sh is on the PATH")
  eq(api.which("no-such-program-paw"), nil, "a program that is not there")
end)

test("paw.util.copy copies tables all the way down", function()
  local a = { 1, { x = { 2 } }, name = "n" }
  local b = paw.util.copy(a)
  b[2].x[1] = 3
  eq(a[2].x[1], 2, "the copy shares no table with the original")
  eq(b.name, "n", "and has its values")
end)
