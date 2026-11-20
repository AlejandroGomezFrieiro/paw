-- What notation writes over its staves, the text and the dynamics, among
-- the text `:vimgrep` and `<leader>fg` search (`paw.grep`).
local api = paw.api
local WORDS = { text = "text", dynamic = "dynamic", dyn = "dynamic" }

paw.grep.source("notation", function(add)
  for _, id in ipairs(api.track_list()) do
    for _, c in ipairs(api.clip_list(id)) do
      local own = type(c.meta) == "table" and type(c.meta.notation) == "table" and c.meta.notation.marks
      for _, mk in ipairs(type(own) == "table" and own or {}) do
        local field = WORDS[mk.kind]
        if field and type(mk.value) == "string" and mk.value ~= "" then
          local at = tonumber(mk.at)
          add({ text = mk.value, field = field, where = c.name .. (at and " " .. paw.time.format(c.start + at) or ""),
            location = { uri = paw.address.clip(c.id), selector = at and { time = { at, at } } or nil } })
        end
      end
    end
  end
end)
