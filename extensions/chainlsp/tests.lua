-- Tests for extensions/chainlsp, run by tests/suite.lua with its helpers.
-- The test with the server runs when the checkout has built chain-lsp
-- (target/debug or target/release), and is skipped otherwise. Each test
-- gives the server the schema of crates/chain-lsp/tests/fixtures, not paw's.
local T = ...
local eq = T.eq

local function load()
  if not paw.ext.loaded.chainlsp then
    paw.opt.chainlsp_autostart = false
    paw.ext.load("extensions/chainlsp")
  end
  local chainlsp = require("chainlsp")
  local schema = T.read_file("crates/chain-lsp/tests/fixtures/schema.json")
  local saved = chainlsp.schema
  chainlsp.schema = function() return schema end
  T.after(function()
    chainlsp.schema = saved
    paw.lsp.stop()
    paw.diagnostic.reset()
  end)
  return chainlsp
end

-- A saved project with a chain file in its `racks` folder.
local function project_with(text)
  T.start()
  paw.project.save(T.scratch .. "/chainlsp")
  local chainlsp = load()
  local folder = chainlsp.folder()
  os.execute("mkdir -p '" .. folder .. "/racks'")
  T.write_file(folder .. "/racks/glue.chain", text)
  return chainlsp, folder
end

local function server_or_skip()
  for _, path in ipairs({ "target/debug/chain-lsp", "target/release/chain-lsp" }) do
    if paw.api.fs_exists(path) then return io.popen("pwd"):read("*l") .. "/" .. path end
  end
  return nil, "no chain-lsp: `cargo build -p chain-lsp` to run this"
end

T.test("chainlsp: :chainlsp says which server runs and which chain files of the project it checks", function()
  local chainlsp = project_with("chain 1\n")
  paw.opt.chainlsp_cmd = "/opt/chain-lsp --log"
  chainlsp.configure()
  eq(table.concat(paw.lsp.configs:get("chain-lsp").cmd(), " "), "/opt/chain-lsp --log", "the option, as words")
  T.keys(":chainlsp<CR>")
  local screen = T.screen()
  eq(screen:find("/opt/chain-lsp --log", 1, true) ~= nil, true, "the server")
  eq(screen:find("racks/glue.chain", 1, true) ~= nil, true, "the file of the project")
end)

T.test("chainlsp: chain-lsp checks the chain files of the project, and :chainlsp check reads them again", function()
  local server, skip = server_or_skip()
  if not server then return skip end
  local chainlsp = project_with("chain 1\nsaturation drive=40dB\n")
  paw.opt.chainlsp_cmd = server
  T.keys(":chainlsp start<CR>")
  local address = chainlsp.address("racks/glue.chain")
  T.until_(function() return #paw.diagnostic.get(address) == 1 end, "a diagnostic of the file")
  eq(
    paw.diagnostic.get(address)[1].message,
    "2:12 `drive` goes from 0dB to 36dB, so `40dB` is out of range",
    "with its line and column"
  )
  T.keys(":diagnostics<CR>")
  eq(T.screen():find("2:12 `drive` goes from", 1, true) ~= nil, true, ":diagnostics lists it")
  T.keys("<Esc>")
  T.write_file(chainlsp.folder() .. "/racks/glue.chain", "chain 1\nsaturation drive=30dB\n")
  T.keys(":chainlsp check<CR>")
  T.until_(function() return #paw.diagnostic.get(address) == 0 end, "the fixed file has no diagnostic")
end)

T.test("chainlsp: unloaded, the extension takes its server, subject and dialect away", function()
  load().configure()
  paw.ext.unload("chainlsp")
  eq(paw.lsp.configs:get("chain-lsp"), nil, "the server")
  eq(paw.lsp.subjects:get("chain-lsp"), nil, "the subject")
  eq(paw.lsp.adapters:get("chain-lsp"), nil, "the dialect")
end)
