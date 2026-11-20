-- A one-file extension that adds a view: the transport position in big digits.
-- It starts hidden. `,C` and `:clock` show and hide it.
local glyphs = {
  ["0"] = { "█▀█", "█ █", "▀▀▀" }, ["1"] = { " █ ", " █ ", " ▀ " }, ["2"] = { "▀▀█", "█▀▀", "▀▀▀" },
  ["3"] = { "▀▀█", " ▀█", "▀▀▀" }, ["4"] = { "█ █", "▀▀█", "  ▀" }, ["5"] = { "█▀▀", "▀▀█", "▀▀▀" },
  ["6"] = { "█▀▀", "█▀█", "▀▀▀" }, ["7"] = { "▀▀█", "  █", "  ▀" }, ["8"] = { "█▀█", "█▀█", "▀▀▀" },
  ["9"] = { "█▀█", "▀▀█", "▀▀▀" }, ["."] = { " ", " ", "▀" },
}

paw.ui.hl("ClockDigits", { fg = "#ff9e64", bold = true })
paw.ui.hl("ClockPlaying", { fg = "#9ece6a", bold = true })

paw.ui.view("clock", {
  focusable = false,
  render = function(_, buf)
    local transport = paw.transport.get()
    local text = paw.time.format(transport.position)
    local x = 2
    for ch in text:gmatch(".") do
      local glyph = glyphs[ch]
      for row, line in ipairs(glyph) do
        buf:text(x, row - 1, line, transport.playing and "ClockPlaying" or "ClockDigits")
      end
      x = x + paw.api.str_width(glyph[1]) + 1
    end
    buf:text(x + 2, 1, string.format("%g bpm", paw.project.tempo), "Dim")
  end,
})

paw.ui.dock("clock", { side = "top", size = 3 })
paw.ui.hide("clock")
paw.command("clock", function() paw.ui.toggle("clock") end, { desc = "Show or hide the big clock" })
paw.keymap.set("<leader>C", "clock", { desc = "Show or hide the big clock" })
