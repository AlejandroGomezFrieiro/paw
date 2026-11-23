-- The check that no crate of the chain language depends on a crate of paw
-- (tools/chaindeps.lua). Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local chaindeps = dofile("tools/chaindeps.lua")

test("chaindeps: no chain crate of the tree depends on a crate of paw", function()
  local problems, count = chaindeps.check(".")
  eq(table.concat(problems, "\n"), "", "the problems")
  eq(count > 0, true, "the tree has a chain crate")
end)

test("chaindeps: a chain crate that names a paw crate in any form of dependency fails", function()
  local root = T.scratch .. "/chaindeps"
  os.execute("mkdir -p '" .. root .. "/crates/chain-x' '" .. root .. "/crates/paw-y'")
  T.write_file(
    root .. "/crates/chain-x/Cargo.toml",
    table.concat({
      "[package]",
      'name = "chain-x"',
      'description = "a crate that paw uses"',
      "[dependencies]",
      'serde = { version = "1" } # not paw-core',
      "paw-core.workspace = true",
      'core = { package = "paw-core", path = "../paw-core" }',
      "[dev-dependencies.paw-engine]",
      "[target.'cfg(unix)'.build-dependencies]",
      'helper = { path = "../paw-y" }',
    }, "\n")
  )
  -- A paw crate may depend on a chain crate: only crates/chain-* are read.
  T.write_file(root .. "/crates/paw-y/Cargo.toml", '[dependencies]\nchain-x = { path = "../chain-x" }\n')
  local problems = chaindeps.check(root)
  local lines = {}
  for _, problem in ipairs(problems) do
    lines[#lines + 1] = problem:match("^([^ ]+)") .. " " .. problem:match("`([^`]+)`")
  end
  eq(
    table.concat(lines, "\n"),
    table.concat({
      "crates/chain-x/Cargo.toml:6: paw-core",
      "crates/chain-x/Cargo.toml:7: core",
      "crates/chain-x/Cargo.toml:8: paw-engine",
      "crates/chain-x/Cargo.toml:10: helper",
    }, "\n"),
    "the problems"
  )
end)
