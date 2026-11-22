-- The terminal the pictures are taken in: WezTerm as its author uses it
-- (FiraCode Nerd Font, Catppuccin Mocha), without a tab bar or padding.
-- With $EDIT set, Neovim edits that file in a pane above the program.
local wezterm = require "wezterm"
local config = wezterm.config_builder()
config.color_scheme = "Catppuccin Mocha"
config.font = wezterm.font("FiraCode Nerd Font")
config.font_size = 12.0
config.front_end = "Software"
config.enable_kitty_graphics = true
config.enable_tab_bar = false
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }
config.inactive_pane_hsb = { saturation = 0.9, brightness = 0.75 }
config.check_for_updates = false
config.audible_bell = "Disabled"
config.window_close_confirmation = "NeverPrompt"

local edit = os.getenv("EDIT")
if edit then
  wezterm.on("gui-startup", function(cmd)
    local _, pane = wezterm.mux.spawn_window(cmd or {})
    -- The file is shown as it is named in a home directory, not by the
    -- scratch directory the scene keeps it in.
    pane:split({
      direction = "Top",
      size = 0.3,
      args = {
        "nvim",
        "--clean",
        "-c",
        "set nu",
        "-c",
        "cd %:h",
        "-c",
        "set statusline=~/.config/paw/init.lua\\ %m%=%l,%c",
        edit,
      },
    })
  end)
end
return config
