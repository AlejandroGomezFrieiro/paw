-- The default colours. Override any group with `paw.ui.hl(name, def)`, or
-- change `palette` and call `paw.ui.theme(require("paw.theme").build())`.
--
-- What is content stays neutral: names, numbers, the grid. Colour is spent
-- on what matters now: amber for focus, the playhead and keys to press; the
-- mode's colour in the mode pill and the cursor; red for recording and
-- errors; a track's own colour for what belongs to that track.
--
-- Tracks take their colour from `hues` in turn (or from `track.color`), and
-- everything that belongs to a track is drawn in shades of it: its clips,
-- its notes in the piano roll, its strip in the mixer. Those shades are made
-- on demand by `paw.draw.hue`. The window uses the same twelve hues.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local type types = require("paw.types")

--- The colours of the theme by name, each `#rrggbb`.
local record Palette
  bg: string
  bg_dark: string
  bg_alt: string
  bg_hl: string
  sel: string
  raise: string
  cursor_line: string
  line: string
  line_beat: string
  line_hi: string
  faint: string
  dim: string
  fg: string
  bright: string
  accent: string
  normal: string
  insert: string
  visual: string
  mute: string
  solo: string
  red: string
  monitor: string
  automation: string
  loop_ruler: string
  loop_lane: string
  punch_ruler: string
  meter_low: string
  meter_mid: string
  meter_high: string
  playhead_clip: string
  cyan: string
  blue: string
  green: string
  yellow: string
  orange: string
  magenta: string
end

--- Highlight groups by name: what `paw.ui.theme` takes.
local type Groups = {string:types.CellStyle}

local c: Palette = {
  bg = "#101216",        -- the screen
  bg_dark = "#0c0d10",   -- outside a clip, black keys' rows, automation
  bg_alt = "#16191f",    -- chrome: headers, the ruler, title bars, status and key lines
  bg_hl = "#20242d",     -- wells: chips that are off, meter rails
  sel = "#262c38",       -- the selected header, strip or row
  raise = "#2c3240",     -- what stands out from a panel
  cursor_line = "#35425c", -- the row the cursor is on, within the selected strip
  line = "#1b1f26",      -- grid steps
  line_beat = "#252a33", -- beat lines
  line_hi = "#363d4b",   -- bar lines and rules between panes
  faint = "#565d6d",
  dim = "#8a91a3",
  fg = "#c9ced8",
  bright = "#eef1f6",
  accent = "#f5a95c",    -- focus, the playhead, keys to press
  normal = "#6aa9e9",    -- the modes
  insert = "#8fc96a",
  visual = "#ac93e6",
  mute = "#e8a33d",
  solo = "#e3cf4f",
  red = "#ef5b5b",       -- arm, record, errors
  monitor = "#6cc3b8",
  automation = "#e98d55",
  loop_ruler = "#4a3a24",
  loop_lane = "#14161a",
  punch_ruler = "#4c2428",
  meter_low = "#6fbf73",
  meter_mid = "#e3cf4f",
  meter_high = "#ef5b5b",
  playhead_clip = "#3a3022",
  -- Older names, kept for configurations that use them.
  cyan = "#6cc3b8",
  blue = "#6aa9e9",
  green = "#8fc96a",
  yellow = "#e3cf4f",
  orange = "#e98d55",
  magenta = "#ac93e6",
}

-- One per track, in turn: the same twelve as the window's.
local hues: {string} = {
  "#e0605a", "#e58a45", "#d9ab3a", "#a9c04a", "#5fb56a", "#45b3a3",
  "#4aa3df", "#6d8ff0", "#9a7ff0", "#c773d6", "#e06b9a", "#b39c7d",
}
-- Their names, for `:track.color`.
local hue_names: {string} = { "coral", "orange", "gold", "lime", "green", "teal", "sky", "blue", "violet", "purple", "pink", "sand" }

--- The highlight groups made from the palette as it is now.
local function build(): Groups
  local alt = c.bg_alt
  return {
    Normal = { fg = c.fg, bg = c.bg },
    Dim = { fg = c.dim },
    Faint = { fg = c.faint },
    Bright = { fg = c.bright, bold = true },
    Accent = { fg = c.accent },
    Title = { fg = c.accent, bold = true },
    Error = { fg = c.red },
    Warn = { fg = c.mute },
    Info = { fg = c.fg },
    Border = { fg = c.line_hi },
    BorderFocus = { fg = c.accent },
    Rule = { fg = c.line_hi },
    Panel = { fg = c.fg, bg = alt },
    PanelTitle = { fg = c.dim, bg = alt, bold = true },
    PanelTitleFocus = { fg = c.bright, bg = alt, bold = true },
    -- A docked panel's title bar (`paw.ui.titlebar`).
    TitleBar = { fg = c.dim, bg = alt },
    TitleBarName = { fg = c.dim, bg = alt, bold = true },
    TitleBarFocus = { fg = c.bg, bg = c.accent },
    TitleBarNameFocus = { fg = c.bg, bg = c.accent, bold = true },
    TitleBarMark = { fg = c.line_hi, bg = alt },
    TitleBarMarkFocus = { fg = c.bg, bg = c.accent, bold = true },
    TitleBarFaint = { fg = c.faint, bg = alt },
    FloatFooter = { fg = c.dim, bg = c.bg },

    Ruler = { fg = c.faint, bg = alt },
    RulerBar = { fg = c.dim, bg = alt, bold = true },
    RulerTick = { fg = c.faint, bg = alt },
    -- With `relativebar`: the cursor's bar, and the counts of the others.
    RulerBarCursor = { fg = c.accent, bg = alt, bold = true },
    RulerBarRelative = { fg = c.faint, bg = alt },
    RulerTempo = { fg = c.accent, bg = alt },
    RulerLoop = { fg = c.bright, bg = c.loop_ruler, bold = true },
    RulerLoopTick = { fg = c.dim, bg = c.loop_ruler },
    RulerLoopEdge = { fg = c.accent, bg = alt },
    RulerLoopEdgeIn = { fg = c.accent, bg = c.loop_ruler },
    -- The punch range: where recording starts and stops.
    RulerPunch = { fg = c.bright, bg = c.punch_ruler, bold = true },
    RulerPunchTick = { fg = c.dim, bg = c.punch_ruler },
    RulerPunchEdge = { fg = c.red, bg = alt, bold = true },
    RulerCorner = { fg = c.fg, bg = alt },
    RulerCornerLabel = { fg = c.faint, bg = alt },
    RulerPlayhead = { fg = c.accent, bg = alt, bold = true },
    Ruler2 = { fg = c.faint, bg = c.bg },
    -- Markers and regions, on the ruler's second row.
    Marker = { fg = c.accent, bg = c.bg, bold = true },
    Region = { fg = c.dim, bg = c.sel },
    RegionName = { fg = c.monitor, bg = c.sel, bold = true },

    TrackHeader = { fg = c.fg, bg = alt },
    TrackHeaderSel = { fg = c.bright, bg = c.sel },
    TrackName = { fg = c.fg, bg = alt },
    TrackNameSel = { fg = c.bright, bg = c.sel, bold = true },
    TrackIndex = { fg = c.faint },
    -- The track column (paw/trackcolumn.tl), as Neovim's LineNr,
    -- CursorLineNr, FoldColumn and SignColumn.
    TrackColumn = { fg = c.faint, bg = alt },
    TrackColumnCursor = { fg = c.dim, bg = c.sel },
    TrackNr = { fg = c.faint },
    TrackNrCursor = { fg = c.accent, bold = true },
    TrackFold = { fg = c.line_hi },
    TrackSign = { fg = c.dim },
    TrackInfo = { fg = c.dim },
    TrackRoute = { fg = c.faint },
    FlagOff = { fg = c.faint, bg = c.bg_hl },
    Mute = { fg = c.bg, bg = c.mute, bold = true },
    Solo = { fg = c.bg, bg = c.solo, bold = true },
    Armed = { fg = c.bg, bg = c.red, bold = true },
    Monitor = { fg = c.bg, bg = c.monitor, bold = true },
    Input = { fg = c.monitor },

    Lane = { fg = c.line_hi, bg = c.bg },
    LaneSel = { fg = c.line_hi, bg = "#14171c" },
    LaneBar = { fg = c.line_hi },
    LaneBeat = { fg = c.line_beat },
    LaneLoop = { bg = c.loop_lane },
    -- A take lane: the takes that do not play, faint; the header's words.
    TakeLane = { fg = c.faint, bg = c.bg_dark },
    TakeLaneName = { fg = c.dim, bg = c.bg_dark },
    ClipEdge = { fg = c.bg },
    ClipWarp = { fg = c.yellow, bold = true },
    ClipMidi = { fg = c.bg, bg = c.blue },
    ClipAudio = { fg = c.bg, bg = c.green },
    ClipMuted = { fg = c.dim, bg = c.bg_hl },
    ClipCursor = { bg = "#c8d3f5" },
    ClipNotes = { fg = "#283457" },
    Automation = { fg = c.automation },
    ClipWave = { fg = "#283457" },
    -- Waveform cells that need their own style: a block that grows from the top
    -- (the wave drawn in reverse video), and columns that reach full scale.
    ClipWaveFlip = { reverse = true },
    ClipWaveClip = { fg = c.red },
    ClipWaveClipFlip = { fg = c.red, reverse = true },
    Playhead = { fg = c.accent },
    PlayheadClip = { fg = c.accent },
    PlayheadShade = { bg = c.playhead_clip },  -- where a step is a whole cell (the drum grid)
    Cursor = { bg = c.normal, fg = c.bg },
    CursorVisual = { bg = c.visual, fg = c.bg },
    CursorTail = { bg = "#2a3a50" },
    Visual = { bg = "#3a3352", fg = c.bright },
    ScopeOutside = { fg = c.faint, bg = c.bg },
    InsertCursor = { bg = c.insert, fg = c.bg },
    RulerInsert = { fg = c.bg, bg = c.insert, bold = true },
    HintKey = { fg = c.accent, bold = true },
    Welcome = { fg = c.fg },
    WelcomeTitle = { fg = c.bright, bold = true },
    Empty = { fg = c.dim },
    EmptyKey = { fg = c.accent, bold = true },

    MeterLow = { fg = c.meter_low },
    MeterMid = { fg = c.meter_mid },
    MeterHigh = { fg = c.meter_high },
    MeterOff = { fg = c.bg_hl },
    MeterPeak = { fg = c.bright },
    MeterClip = { fg = c.red, bold = true },
    MeterScale = { fg = c.faint },
    Fader = { fg = c.fg, bold = true },
    FaderSel = { fg = c.accent, bold = true },
    FaderZero = { fg = c.dim },
    FaderTrack = { fg = c.line_hi },

    StatusLine = { fg = c.fg, bg = alt },
    StatusDim = { fg = c.dim, bg = alt },
    StatusFaint = { fg = c.faint, bg = alt },
    StatusHint = { fg = c.dim, bg = alt, italic = true },
    StatusSep = { fg = c.line_hi, bg = alt },
    StatusTime = { fg = c.bright, bg = alt, bold = true },
    StatusOn = { fg = c.accent, bg = alt },
    StatusMode = { fg = c.bg, bg = c.normal, bold = true },
    StatusVisual = { fg = c.bg, bg = c.visual, bold = true },
    StatusInsert = { fg = c.bg, bg = c.insert, bold = true },
    StatusPending = { fg = c.bg, bg = c.solo, bold = true },
    StatusCommand = { fg = c.bg, bg = c.accent, bold = true },
    StatusMacro = { fg = c.red, bg = alt, bold = true },
    StatusPlay = { fg = c.insert, bg = alt, bold = true },
    StatusStop = { fg = c.dim, bg = alt },
    StatusRec = { fg = c.red, bg = alt, bold = true },
    StatusRecOn = { fg = c.red, bg = alt, bold = true },
    StatusModified = { fg = c.accent, bg = alt },
    StatusName = { fg = c.fg, bg = alt, bold = true },
    StatusWarn = { fg = c.mute, bg = alt },
    StatusError = { fg = c.red, bg = alt, bold = true },
    StatusOff = { fg = c.faint, bg = alt },

    KeyBar = { fg = c.faint, bg = alt },
    KeyBarKey = { fg = c.accent, bg = alt },
    KeyBarText = { fg = c.dim, bg = alt },
    KeyBarSep = { fg = c.line_hi, bg = alt },
    FooterKey = { fg = c.accent, bg = c.bg },
    FooterText = { fg = c.dim, bg = c.bg },
    FooterSep = { fg = c.line_hi, bg = c.bg },

    PianoWhite = { fg = "#5b6170", bg = "#c9ced8" },
    PianoBlack = { fg = c.dim, bg = "#1c1f26" },
    PianoC = { fg = "#1c1f26", bg = "#c9ced8", bold = true },
    PianoCursor = { fg = c.bg, bg = c.accent, bold = true },
    RollRow = { fg = c.line, bg = c.bg },
    RollRowBlack = { fg = c.line, bg = c.bg_dark },
    RollBar = { fg = c.line_hi },
    RollBeat = { fg = c.line_beat },
    RollStep = { fg = c.line, bg = c.bg },
    RollStepBlack = { fg = c.line, bg = c.bg_dark },
    RollOutside = { fg = c.bg_alt, bg = "#08090b" },
    RollOutsideBlack = { fg = c.bg_alt, bg = "#060709" },
    ScrollThumb = { fg = c.dim },
    Note = { fg = c.bg, bg = c.green },
    NoteCursor = { fg = c.bg, bg = c.bright, bold = true },
    RollCursor = { bg = "#2a3a50" },
    Velocity = { fg = c.dim },
    VelocityLane = { fg = c.faint, bg = c.bg_dark },
    -- Chord symbols over the piano roll, and a snippet: its notes while it
    -- is active, its span on the chord row, what the picker would write.
    RulerChord = { fg = c.fg, bg = c.bg_alt, bold = true },
    RulerChordEdge = { fg = c.faint, bg = c.bg_alt },
    SnippetNote = { fg = c.bg, bg = c.visual, bold = true },
    SnippetSpan = { fg = c.bg, bg = c.visual },
    SnippetGhost = { fg = c.visual, bg = c.bg_hl },
    -- What an Ex line being typed acts on (paw.ex): its stretch of time,
    -- the things that match, the one asked about, what a change would make.
    ExRange = { bg = "#3a3352" },
    ExMatch = { fg = c.bg, bg = c.solo },
    ExCurrent = { fg = c.bg, bg = c.accent, bold = true },
    ExGhost = { fg = c.visual, bg = c.bg_hl },
    -- Diagnostics (paw.diagnostic): the mark, a note underlined, the message
    -- after it.
    DiagnosticError = { fg = c.red, bold = true },
    DiagnosticWarn = { fg = c.mute, bold = true },
    DiagnosticInfo = { fg = c.normal },
    DiagnosticHint = { fg = c.dim },
    DiagnosticUnderlineError = { fg = c.red, underline = true, bold = true },
    DiagnosticUnderlineWarn = { fg = c.mute, underline = true, bold = true },
    DiagnosticUnderlineInfo = { fg = c.normal, underline = true },
    DiagnosticUnderlineHint = { underline = true },
    DiagnosticVirtualTextError = { fg = c.red, italic = true },
    DiagnosticVirtualTextWarn = { fg = c.mute, italic = true },
    DiagnosticVirtualTextInfo = { fg = c.normal, italic = true },
    DiagnosticVirtualTextHint = { fg = c.faint, italic = true },
    -- A label a server puts on something (paw.annotation).
    Annotation = { fg = c.monitor, italic = true },

    DeviceName = { fg = c.bright, bold = true },
    DeviceOff = { fg = c.faint, strike = true },
    DeviceFormat = { fg = c.faint },
    Param = { fg = c.fg },
    ParamValue = { fg = c.dim },
    ParamBar = { fg = c.accent },
    ParamBarDim = { fg = c.dim },
    ParamBarOff = { fg = c.bg_hl },
    Selected = { bg = c.sel },
    SelectedMark = { fg = c.accent, bg = c.sel },
    CursorLine = { fg = c.bright, bg = c.cursor_line },
    CursorLineMark = { fg = c.accent, bg = c.cursor_line },

    HelpKey = { fg = c.accent, bold = true },
    HelpSection = { fg = c.dim, bold = true },
    -- Pages of help (`:help`): titles, headings and their tags, links, code.
    HelpTitle = { fg = c.bright, bold = true },
    HelpHeading = { fg = c.accent, bold = true },
    HelpTag = { fg = c.faint },
    HelpRule = { fg = c.line_hi },
    HelpLink = { fg = c.normal, underline = true },
    HelpCode = { fg = c.monitor },
    HelpBold = { fg = c.bright, bold = true },
    HelpItalic = { italic = true },
    HelpBullet = { fg = c.dim },
    HelpTableHead = { fg = c.bright, bold = true },
    HelpDim = { fg = c.dim },

    TooSmall = { fg = c.dim, bg = c.bg },
    TooSmallTitle = { fg = c.bright, bg = c.bg, bold = true },

    -- The completion list above the command line.
    Pmenu = { fg = c.fg, bg = c.raise },
    PmenuSel = { fg = c.bright, bg = c.sel, bold = true },
    PmenuDesc = { fg = c.dim, bg = c.raise },
    PmenuSelDesc = { fg = c.fg, bg = c.sel },
    PmenuThumb = { fg = c.accent, bg = c.raise },
    -- Where a drag with the pointer will put what it holds, and the box it draws.
    MouseGhost = { fg = c.bright, bg = c.visual },
    MouseBox = { fg = c.visual, bold = true },
  }
end

local record M
  type Palette = Palette
  type Groups = Groups
  --- The colours by name: change one, then `paw.ui.theme(theme.build())`.
  palette: Palette
  --- A colour for each track in turn, and the names of those colours.
  hues: {string}
  hue_names: {string}
  build: function(): Groups
  --- The groups of the palette as paw starts.
  groups: Groups
end

M.palette, M.hues, M.hue_names, M.build = c, hues, hue_names, build
M.groups = build()
return M
