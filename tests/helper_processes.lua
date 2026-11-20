-- Helper processes tests.
local T = ...
local test, eq, fails, until_, scratch, read_file = T.test, T.eq, T.fails, T.until_, T.scratch, T.read_file
local paw = require("paw")
local api = paw.api

test("scripts run helper processes and talk to them over sockets", function()
  local log = scratch .. "/helper.log"
  local proc = api.proc_spawn({ "sh", "-c", "echo helper says hi; exit 3" }, { log = log })
  until_(function() return not api.proc_status(proc).running end, "the helper to exit")
  eq(api.proc_status(proc).code, 3, "exit code")
  eq(read_file(log):find("helper says hi", 1, true) ~= nil, true, "output goes to the log")
  api.proc_kill(proc)
  fails(function() api.proc_status(proc) end, "no process", "a process is forgotten once killed")

  local path = scratch .. "/sockets/helper.sock"
  local listener = api.sock_listen(path)
  eq(api.sock_accept(listener), nil, "nobody has connected yet")
  local client = api.sock_connect(path)
  local server = api.sock_accept(listener)
  eq(api.sock_read(server), "", "nothing has arrived yet")
  local chunk = string.rep("\0\1\2\255", 16384)
  local got, sent = {}, {}
  for _ = 1, 20 do
    api.sock_write(client, chunk)
    sent[#sent + 1] = chunk
    got[#got + 1] = api.sock_read(server)
  end
  local big = table.concat(sent)
  local deadline = api.now() + 5000
  while #table.concat(got) < #big and api.now() < deadline do
    got[#got + 1] = api.sock_read(server)
  end
  eq(table.concat(got) == big, true, "bytes arrive unchanged, binary included")
  api.sock_close(client)
  eq(api.sock_read(server), nil, "nil once the other side closed")
  api.sock_close(server)
  api.sock_close(listener)
end)
