-- The check of the order of layers in the runtime (tools/layers.lua), with
-- its layers (tools/layers.txt) and its allow-list
-- (tools/layers-allowed.txt). Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local layers = dofile("tools/layers.lua")

test(
  "layers: no module of the runtime reads a higher layer beyond the allow-list",
  function() eq(table.concat((layers.check(".")), "\n"), "", "the problems") end
)

test("layers: a new upward reference fails, and a smaller count asks for a smaller line", function()
  local root = T.scratch .. "/layers"
  os.execute("mkdir -p '" .. root .. "/runtime/lua/paw' '" .. root .. "/tools'")
  T.write_file(root .. "/tools/layers.txt", "[low]\npaw.low\npaw.old\n[high]\npaw.high\n")
  T.write_file(root .. "/tools/layers-allowed.txt", "# a comment\npaw.old paw.high 2\n")
  T.write_file(root .. "/runtime/lua/paw/high.tl", "local M = {}\nreturn M\n")
  -- Two names of paw.high (one through a cast), none in a comment or a
  -- string, and the type's `require` adds none.
  T.write_file(
    root .. "/runtime/lua/paw/low.tl",
    'local type H = require("paw.high")\npaw.high.open()\n-- paw.high.close()\nlocal s = "paw.high.draw"\npaw.high.open((paw.high as H).mode)\n'
  )
  -- One name of the two allowed.
  T.write_file(root .. "/runtime/lua/paw/old.lua", 'local high = require("paw.high")\n')
  T.write_file(root .. "/runtime/lua/paw/new.lua", "return {}\n")
  eq(
    table.concat((layers.check(root)), "\n"),
    table.concat({
      "runtime/lua/paw/low.tl:1: paw.low (layer low, tools/layers.txt:2) reads 2 names of paw.high"
        .. " (layer high, tools/layers.txt:5), 0 allowed: paw.high.mode, paw.high.open."
        .. " Give paw.low what it needs through an event or a callback."
        .. " If paw.low belongs higher, move tools/layers.txt:2."
        .. " If the names moved here from another module, move their count to the line"
        .. " `paw.low paw.high 2` of tools/layers-allowed.txt",
      "runtime/lua/paw/new.lua: paw.new has no layer: add the line `paw.new` under the right `[layer]`"
        .. " of tools/layers.txt",
      "tools/layers-allowed.txt:2: 1 now: make the line `paw.old paw.high 1`",
    }, "\n"),
    "the problems"
  )
  -- The graph for other tools: one edge on each line.
  local list = layers.read_layers(root .. "/tools/layers.txt")
  eq(
    layers.format_graph(layers.graph(root), list),
    "paw.low paw.high 2 paw=3,type=1 low high up runtime/lua/paw/low.tl:1\n"
      .. "paw.old paw.high 1 require=1 low high up runtime/lua/paw/old.lua:1\n",
    "the graph"
  )
end)
