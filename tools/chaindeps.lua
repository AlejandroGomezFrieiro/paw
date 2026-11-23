-- The check that the crates of the chain language (crates/chain-*) stay
-- generic: no chain crate depends on a crate of paw, so another host can
-- use the language. It reads the manifests as text, so plain LuaJIT runs
-- it (the flake's `chaindeps` check), and so does paw (the suite's
-- tests/chaindeps.lua).
--
--   luajit tools/chaindeps.lua       check the chain crates of this tree
--
-- A dependency is a line `name = ...` or `name.workspace = true` in a
-- section of dependencies, or a section `[dependencies.name]`. It is a
-- crate of paw when its name, its `package` or its `path` names paw.
local M = {}

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

--- The manifests of the chain crates under `root`, sorted.
function M.manifests(root)
  local out = {}
  local pipe = assert(io.popen("ls -d '" .. root .. "'/crates/chain-*/Cargo.toml 2>/dev/null"))
  for line in pipe:lines() do
    out[#out + 1] = line
  end
  pipe:close()
  table.sort(out)
  return out
end

local function is_dependencies(section)
  return section:match("dependencies$") ~= nil or section:match("dependencies%.[^.]+$") ~= nil
end

local function names_paw(text) return text:match("paw") ~= nil end

--- The problems of one manifest's text: one line for each dependency on
--- a crate of paw, as `<path>:<line>: <message>`.
function M.check_manifest(path, text)
  local problems = {}
  local section = ""
  local number = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    number = number + 1
    local code = line:gsub("#.*$", "")
    local header = code:match("^%s*%[([^%]]+)%]%s*$")
    if header then
      section = header
      -- `[dependencies.paw-core]`: the name is in the header.
      local name = header:match("dependencies%.([^.]+)$")
      if name and names_paw(name) then
        problems[#problems + 1] = string.format(
          "%s:%d: a chain crate depends on the paw crate `%s`: the chain language must not depend on paw",
          path,
          number,
          name
        )
      end
    elseif is_dependencies(section) then
      local name, rest = code:match("^%s*([%w_%-]+)[%.%s]*[%w_]*%s*=%s*(.*)$")
      if name and (names_paw(name) or names_paw(rest)) then
        problems[#problems + 1] = string.format(
          "%s:%d: a chain crate depends on the paw crate `%s`: the chain language must not depend on paw",
          path,
          number,
          name
        )
      end
    end
  end
  return problems
end

--- Each problem of the chain crates under `root`, and how many manifests
--- it read.
function M.check(root)
  local problems = {}
  local manifests = M.manifests(root)
  for _, path in ipairs(manifests) do
    local relative = path:sub(#root + 2)
    for _, problem in ipairs(M.check_manifest(relative, read(path) or "")) do
      problems[#problems + 1] = problem
    end
  end
  return problems, #manifests
end

if arg and arg[0] and arg[0]:match("chaindeps%.lua$") then
  local problems, count = M.check(".")
  for _, line in ipairs(problems) do
    print(line)
  end
  if #problems > 0 then
    print(string.format("chaindeps: %d problems", #problems))
    os.exit(1)
  end
  if count == 0 then
    print("chaindeps: no crate crates/chain-*: run it at the top of the tree")
    os.exit(1)
  end
  print(string.format("chaindeps: %d chain crates, none depends on paw", count))
end

return M
