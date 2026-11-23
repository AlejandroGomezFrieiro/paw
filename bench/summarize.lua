-- Summarize a results file as Markdown tables: the median of the repeated
-- runs of each configuration, both engines side by side.
--   paw --clean --no-plugins -l bench/summarize.lua bench/results/<name>.jsonl
local path = ...
local records = {}
for line in io.lines(path) do
  local r = {}
  for k, v in line:gmatch('"([%w_]+)":"([^"]*)"') do
    r[k] = v
  end
  for k, v in line:gmatch('"([%w_]+)":(%-?[%d.eE+-]+)') do
    r[k] = tonumber(v)
  end
  if r.workload then records[#records + 1] = r end
end

local function median(list)
  table.sort(list)
  if #list == 0 then return nil end
  return list[math.ceil(#list / 2)]
end

local function fmt(v)
  if v == nil then return "–" end
  if type(v) ~= "number" then return tostring(v) end
  if v >= 100 then return string.format("%.0f", v) end
  if v >= 10 then return string.format("%.1f", v) end
  if v >= 0.1 then return string.format("%.2f", v) end
  return string.format("%.3f", v)
end

--- One table: rows keyed by `keys`, a column per (variant, value).
local function tbl(title, workload, keys, variants, values)
  local rows, order = {}, {}
  for _, r in ipairs(records) do
    if r.workload == workload then
      local key = {}
      for _, k in ipairs(keys) do
        key[#key + 1] = tostring(r[k])
      end
      local id = table.concat(key, "|")
      if not rows[id] then
        rows[id] = { key = key, cells = {} }
        order[#order + 1] = id
      end
      for _, variant in ipairs(variants) do
        if variant.match(r) then
          for _, v in ipairs(values) do
            local c = variant.name .. "|" .. v
            rows[id].cells[c] = rows[id].cells[c] or {}
            table.insert(rows[id].cells[c], r[v])
          end
        end
      end
    end
  end
  if #order == 0 then return end
  table.sort(order, function(a, b)
    local ka, kb = rows[a].key, rows[b].key
    for i = 1, #ka do
      if ka[i] ~= kb[i] then
        local na, nb = tonumber(ka[i]), tonumber(kb[i])
        if na and nb then return na < nb end
        return ka[i] < kb[i]
      end
    end
    return false
  end)
  print("\n### " .. title .. "\n")
  local head, rule = {}, {}
  for _, k in ipairs(keys) do
    head[#head + 1] = k
    rule[#rule + 1] = "---"
  end
  for _, variant in ipairs(variants) do
    for _, v in ipairs(values) do
      head[#head + 1] = variant.name .. " " .. v
      rule[#rule + 1] = "---:"
    end
  end
  print("| " .. table.concat(head, " | ") .. " |")
  print("| " .. table.concat(rule, " | ") .. " |")
  for _, id in ipairs(order) do
    local row = rows[id]
    local cells = {}
    for _, k in ipairs(row.key) do
      cells[#cells + 1] = k
    end
    for _, variant in ipairs(variants) do
      for _, v in ipairs(values) do
        cells[#cells + 1] = fmt(median(row.cells[variant.name .. "|" .. v] or {}))
      end
    end
    print("| " .. table.concat(cells, " | ") .. " |")
  end
end

local function engine(name, threads)
  return {
    name = threads and (name .. "×" .. (threads == 1 and "1" or "N")) or name,
    match = function(r)
      if r.engine ~= name then return false end
      if threads == 1 then return r.threads == 1 end
      if threads == "N" then return (r.threads or 1) > 1 end
      return true
    end,
  }
end

tbl(
  "Offline render (ms of wall time for 32 s of audio)",
  "render",
  { "kind", "fx", "automation", "parts" },
  -- paw renders on every core unless told otherwise (`threads=12` rows, ×N); runs
  -- with `threads=1` fill the ×1 column.
  { engine("paw", 1), engine("paw", "N"), engine("tracktion", 1), engine("tracktion", "N") },
  { "render_ms" }
)
tbl(
  "Offline render, per-block processing time (ms; budget 10.7 ms)",
  "render",
  { "kind", "fx", "automation", "parts" },
  { engine("paw", 1), engine("paw", "N"), engine("tracktion", 1), engine("tracktion", "N") },
  { "block_p99_ms", "block_max_ms" }
)
tbl(
  "Real-time playback, ms per callback (DAW: null backend on a real-time clock; Tracktion: hosted device, back to back)",
  "blocks",
  { "kind", "parts", "buffer", "edits" },
  { engine("paw"), engine("tracktion", 1), engine("tracktion", "N") },
  { "p50_ms", "p99_ms", "max_ms" }
)
tbl(
  "Clip edits, one undo step each (ms for all of them)",
  "edit",
  { "clips" },
  { engine("paw"), engine("tracktion") },
  { "add_ms", "move_ms", "delete_ms", "undo_ms", "redo_ms" }
)
tbl(
  "Clip edits without the sync to the engine (DAW) — what Tracktion's numbers above measure",
  "edit_nosync",
  { "clips" },
  { engine("paw") },
  { "add_ms", "move_ms", "delete_ms", "undo_ms", "redo_ms" }
)
tbl(
  "Note edits without the sync to the engine (DAW)",
  "notes_nosync",
  { "notes" },
  { engine("paw") },
  { "add_ms", "move_ms", "delete_ms" }
)
tbl(
  "Clip edits: ms per edit, first and last tenth",
  "edit",
  { "clips" },
  { engine("paw") },
  { "add_first_ms", "add_last_ms", "move_first_ms", "move_last_ms" }
)
tbl(
  "Note edits in one clip, one undo step each (ms for all of them)",
  "notes",
  { "notes" },
  { engine("paw"), engine("tracktion") },
  { "add_ms", "move_ms", "delete_ms" }
)
tbl(
  "One edit in a project of N parts (ms, median of 50)",
  "scale",
  { "parts" },
  { engine("paw") },
  { "build_ms", "volume_ms", "clip_move_ms", "undo_ms", "redo_ms", "part_add_ms" }
)
tbl(
  "Save and load (ms)",
  "saveload",
  { "parts", "clips_per_part" },
  { engine("paw"), engine("tracktion") },
  { "build_ms", "save_ms", "load_ms", "file_bytes" }
)
tbl(
  "Resident memory (kB)",
  "memory",
  { "parts", "clips_per_part", "undo_steps" },
  { engine("paw"), engine("tracktion") },
  { "rss_built_kb", "rss_undo_kb" }
)
tbl(
  "Memory over repeated build/edit/render/load rounds (kB)",
  "churn",
  { "rounds" },
  { engine("paw") },
  { "rss_first_kb", "rss_mid_kb", "rss_last_kb", "growth_kb_per_round" }
)
tbl("Startup (ms)", "startup", { "plugins" }, { engine("paw"), engine("tracktion") }, { "ms" })
