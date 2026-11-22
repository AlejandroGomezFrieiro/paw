# How to write a language server

You can make a server that checks the mix and gives diagnostics with
fixes. The steps assume that you know Lua or a language that reads JSON,
and every field and message is in
[Language servers and diagnostics](../reference/language-servers.md).

## Write a server in Lua

A server in Lua runs in the kernel process, and it is the shortest way to
write a server.

1. In `init.lua`, or in an extension, configure the server:

   ```lua
   paw.lsp.config("loud", { server = {
     initialize = function() return { capabilities = { paw = { subjects = { "mix" } } } } end,
     ["textDocument/didOpen"] = function(p, ctx)
       local list = {}
       for _, t in ipairs(p.textDocument.data.tracks) do   -- the subject as a table
         if t.volume > 6 then
           list[#list + 1] = { severity = 2, message = t.name .. " is very loud",
             data = { location = { uri = t.address } } }
         end
       end
       ctx.notify("textDocument/publishDiagnostics", { uri = p.textDocument.uri, diagnostics = list })
     end,
     ["textDocument/didChange"] = function(p, ctx) end,
   } })
   ```

2. Start it with `paw.lsp.enable("loud")`.
3. Type `:lsp info` to make sure that the server runs and gets the `mix`
   subject.
4. Move a fader above +6 dB. A sign shows on the track header, and
   `:diagnostics` lists the problem.

If the server must react to changes, publish the diagnostics again in
`textDocument/didChange`.

## Write a server as a program

1. Write a program that speaks JSON-RPC on its standard input, one message
   for each line:
   1. Answer `initialize` with the subjects that the program wants:
      `{ "capabilities": { "paw": { "subjects": ["mix"] } } }`.
   2. Read `textDocument/didOpen` and `textDocument/didChange`, where the
      `text` field is the subject as JSON.
   3. Send `textDocument/publishDiagnostics` with your findings, and put
      the location in `data.location`.
2. To offer a fix, add `data.fixes`, which is a list of `{ title, edit }`.
   The edit is a workspace edit, for example
   `[ { "uri": "paw://track/4", "set": { "volume": 0 } } ]`.
3. Configure and start it:

   ```lua
   paw.lsp.config("mixcheck", {
     cmd = { "python3", "/path/to/mixcheck.py" },
     attach = { subjects = { "mix" } },
   })
   paw.lsp.enable("mixcheck")
   ```

4. If the server does not start, type `:lsp info` for the last error. The
   errors of the program are in `$XDG_STATE_HOME/paw/lsp-mixcheck.log`.

`tests/fixtures/mix_lint.py` is a complete server of that kind, in about a
hundred lines.

## Check each render with a command

If your check is a program that reads a sound file and prints findings,
use a one-shot server.

1. Make the program print
   `{ "findings": [ { "rule": "...", "severity": "warning", "message": "..." } ] }`.
2. Configure it with `{file}` in its arguments:

   ```lua
   paw.lsp.config("peaks", {
     kind = "oneshot",
     cmd = { "/path/to/check-peaks", "{file}" },
     attach = { subjects = { "render" } },
     timeout_ms = 10000,
   })
   paw.lsp.enable("peaks")
   ```

3. Render the song, and `:diagnostics` shows the findings under Renders.

To give a result a location or a fix, add a `diagnostic(finding, doc)`
function to the config.
