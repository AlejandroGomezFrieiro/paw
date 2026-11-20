-- The one key rule every view keeps (docs/reference/key-rule.md),
-- as a check over the mappings: what `tests/keys_constitution.lua` runs, and
-- anyone writing an extension can run with `:lua =paw.keyrule.broken()`.
local keymap = paw.keymap
local M = {}

--- Keys that are Vim's motions, and only ever motions in every view: the
--- structural ones too, by Vim's and Tree-sitter's meanings (`]]` `[[`
--- the next or previous of the same kind, `]s` `[s` a sibling, `[{` `]}`
--- up to the enclosing group and its end), and the arrows, as `h` `j` `k` `l`.
M.motions = { "h", "j", "k", "l", "w", "b", "e", "0", "^", "$", "gg", "G", "]]", "[[", "]s", "[s", "[{", "]}",
  "<Left>", "<Down>", "<Up>", "<Right>" }


--- What the value keys change: the main value, or the second.
M.values = { ["+"] = "main+", ["<C-a>"] = "main+", ["-"] = "main-", ["<C-x>"] = "main-", ["]"] = "second+", ["["] = "second-" }

--- Views that are text, edited as in Vim (`paw.textbuf`): their value keys
--- are Vim's own on text (`Ctrl-a` adds to a number, `-` goes up, as in
--- oil.nvim), so only the motion and operator parts of the rule hold there.
M.text = { textbuf = true }

--- Every mapping that breaks the rule, as "scope mode keys: why", sorted.
--- Insert mode is left out (its keys enter material), and so are keys
--- made with `prompt = true`, which answer a question on the screen.
function M.broken()
  local out = {}
  local function bad(map, why) out[#out + 1] = map.scope .. " " .. map.mode .. " " .. map.lhs .. ": " .. why end
  local motions, by_scope = {}, {}
  for _, k in ipairs(M.motions) do motions[table.concat(keymap.parse(k))] = true end
  for _, map in ipairs(keymap.every()) do
    local keys = table.concat(map.keys)
    local typed = map.mode ~= "i" and not map.prompt
    if typed and motions[keys] and not (map.motion or map.object) then bad(map, "a motion key that does not move") end
    if typed and map.mode ~= "o" and (keys == "<lt>" or keys == ">") and not map.operator then bad(map, "not the time operator") end
    if map.mode == "n" and not M.text[map.scope] then
      if keys == "K" and map.role ~= "describe" then bad(map, "`K` describes") end
      if keys == "ge" and map.scope ~= "global" then bad(map, "`ge` is the plugin window in every view") end
      if keys == "gc" and map.role ~= "mute" then bad(map, "`gc` mutes") end
      if keys == "gC" and not (type(map.rhs) == "string" and map.rhs:match("^curve%.open")) then bad(map, "`gC` opens a curve") end
      local value = M.values[keys]
      if value and map.role ~= value then bad(map, "should change the " .. value:gsub("[+-]$", "") .. " value") end
      by_scope[map.scope] = by_scope[map.scope] or {}
      by_scope[map.scope][keys] = map
    end
  end
  -- A view's own keys never take a global leader key away: they sit on
  -- `<localleader>`, so that `,m` is the mixer in every view.
  local leader = {}
  for _, map in ipairs(keymap.every()) do
    if map.scope == "global" and map.lhs:lower():find("<leader>", 1, true) and (map.mode == "n" or map.mode == "x") then
      leader[map.mode .. table.concat(map.keys)] = true
    end
  end
  for _, map in ipairs(keymap.every()) do
    if map.scope ~= "global" and (map.mode == "n" or map.mode == "x") then
      local keys = table.concat(map.keys)
      if leader["n" .. keys] or leader[map.mode .. keys] then bad(map, "shadows a global leader key: use `<localleader>`") end
    end
  end
  -- `+` and `Ctrl-a` go together, as do `-` and `Ctrl-x`: the second with a count.
  for scope, list in pairs(by_scope) do
    for a, b in pairs({ ["+"] = "<C-a>", ["-"] = "<C-x>" }) do
      if (list[a] == nil) ~= (list[b] == nil) then
        out[#out + 1] = scope .. " n " .. a .. ": `" .. a .. "` and `" .. b .. "` go together"
      end
    end
  end
  table.sort(out)
  return out
end

--- Named groups of keys that lead to no key, as "scope keys (name)".
function M.lost_groups()
  local lost = {}
  for scope, names in pairs(keymap.groups()) do
    for prefix, name in pairs(names) do
      local found = false
      for _, map in ipairs(keymap.every()) do
        local keys = table.concat(map.keys)
        if (map.scope == scope or scope == "global") and #keys > #prefix and keys:sub(1, #prefix) == prefix then found = true end
      end
      if not found then lost[#lost + 1] = scope .. " " .. prefix .. " (" .. name .. ")" end
    end
  end
  table.sort(lost)
  return lost
end

return M
