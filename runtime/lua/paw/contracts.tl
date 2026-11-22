-- The contracts: the tables that an extension gives to paw and that paw
-- gives back to it. A view, a buffer type, a kind of text buffer, a kind of
-- track, a kind of clip, a role, a picker, a status line component, a query field, a
-- source of grep, a health check and a manifest. Each record has the
-- fields that the runtime reads (paw/ui.tl, paw/layout.tl, paw/keymap.tl,
-- paw/mouse.tl, paw/scene.tl, paw/canvas.tl, paw/statusline.tl and the
-- other readers), with the types that they read.
--
-- Types only: the module is an empty table at run time. It requires only
-- paw.types, so a module of the runtime in Teal can require it, and the
-- functions of the modules in Lua that take a contract name it in their
-- `@type` lines (tools/apidoc.lua). In an extension in Teal they are
-- `paw.contracts.View`, `paw.contracts.PickSource<T>` and the others:
--
--   local record Clock is paw.contracts.View
--     ticks: integer
--   end
--   local clock: Clock = { ticks = 0 }
--   function clock:render(buf: paw.contracts.Buf) buf:text(0, 0, tostring(self.ticks)) end
--   paw.ui.view("clock", clock)
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local type types = require("paw.types")
-- The objects of tracks and devices (paw/objects.tl), which a kind of
-- track gets. Only their types come in: paw/objects.tl requires no contract.
local type objects = require("paw.objects")

local record contracts
  -- Drawing in cells ----------------------------------------------------------

  --- How a cell is drawn: the name of a highlight group, or the colors
  --- and attributes (`{ fg = "#ff9e64", bold = true }`). Nil keeps the
  --- colors already there.
  type Style = string | types.CellStyle

  --- A piece of a line with its style: `{ "text", "Dim" }`.
  type Piece = {string, string}

  --- A line of a page: text, or text in a style.
  record PageLine
    text: string
    style: string
  end

  --- The action of a hit region, as data: `{ kind = "fader", track = 4 }`.
  --- A press, a move or the wheel on it goes to the view's gesture for its
  --- kind. Without one, `keys` are typed, or `cmd` runs as an Ex command.
  --- `hint` is what the status line says of it under the pointer.
  interface HitAction is types.Hit
    kind: string
    keys: string
    cmd: string
    hint: string
    track: integer
    clip: integer
    device: integer
    lane: integer
    index: integer
  end

  --- The props of a mark (`buf:mark(role, x, y, w, h, props)`): what the
  --- role draws, and three that every role has. `hit` makes the mark a hit
  --- region. `bind` ties it to a live value (`position`, `meter:<id>`, or
  --- a name that a view's `live_values` gives). `key` names it for a
  --- frontend. A role's own props are in a record of its own that
  --- extends this one.
  interface MarkProps
    hit: HitAction
    bind: string
    key: string
  end

  --- One axis of a plane: values of `domain` (`beat`, `pitch`), `from`
  --- at the edge of the area, `per` cells for one unit. It goes to the
  --- scene as it is (`types.SceneAxis`).
  type Axis = types.SceneAxis

  --- What `buf:plane` takes.
  record PlaneOptions
    key: string
    x: Axis
    y: Axis
    hit: HitAction
  end

  --- An area that places marks by the values of its domains (beats,
  --- pitches), not by cells: `mark` a role, `hit` a hit region over a
  --- rectangle of the domain, and `cells` where a terminal shows it
  --- (x, y, w, h in cells).
  interface Plane
    mark: function(self: Plane, role: string, x: number, y: number, w: number, h: number, props?: MarkProps): Buf
    hit: function(self: Plane, x: number, y: number, w: number, h: number, action: HitAction)
    cells: function(self: Plane, x: number, y: number, w: number, h: number): integer, integer, integer, integer
  end

  --- The size of a strip of pixels (`buf:strip`): `w` and `h`, the cell
  --- of the terminal in pixels, its colors, and the part that shows.
  record StripPixels
    w: number
    h: number
    record Cell
      w: number
      h: number
    end
    cell: Cell
    fg: string
    bg: string
    view: types.Rect
  end

  --- What `buf:strip` takes: `draw(g, px)` paints the strip, `key` names
  --- it, and with `under` the cells drawn there stay over the picture.
  record StripOptions
    key: string
    under: boolean
    draw: function(g: Painter, px: StripPixels)
  end

  --- A buffer of cells: a rectangle of the screen that a view draws in
  --- (paw/buf.tl). Coordinates count cells from 0 at its corner.
  interface Buf
    x: integer
    y: integer
    width: integer
    height: integer
    text: function(self: Buf, x: number, y: number, text: string, style?: Style): integer
    fill: function(self: Buf, x: number, y: number, w: number, h: number, char?: string, style?: Style)
    sub: function(self: Buf, x: number, y: number, w: number, h: number): Buf
    surface: function(self: Buf, x: number, y: number, w: number, h: number, name?: string): boolean
    strip: function(self: Buf, x: number, y: number, w: number, h: number, opts: StripOptions): boolean
    image: function(self: Buf, x: number, y: number, w: number, h: number, key: string): boolean
    mark: function(self: Buf, role: string, x: number, y: number, w: number, h: number, props?: MarkProps): Buf
    hit: function(self: Buf, x: number, y: number, w: number, h: number, action: HitAction)
    plane: function(self: Buf, x: number, y: number, w: number, h: number, opts: PlaneOptions): Plane
    columns: function(self: Buf, widths: {integer | string}, gap?: integer): Buf...
    keep: function(self: Buf, key: string, x: number, y: number, w: number, h: number)
    put_kept: function(self: Buf, key: string, x: number, y: number, w: number, h: number): boolean
  end

  -- Painting in pixels ---------------------------------------------------------

  --- How a painter draws a shape or text: `fill`, `stroke`, `color`,
  --- `width`, `radius`, `size`, `bold`, `align` (`left`, `center`,
  --- `right`) and, for `g:mono`, `background`, `italic`, `underline` and
  --- `strike`. Colors are `#rrggbb` or `#rrggbbaa`.
  record PaintStyle
    fill: string
    stroke: string
    color: string
    background: string
    width: number
    radius: number
    size: number
    bold: boolean
    italic: boolean
    underline: boolean
    strike: boolean
    align: string
  end

  --- A painter of paw/canvas.tl: what a view's `paint` draws with.
  interface Painter
    x: number
    y: number
    width: number
    height: number
    sub: function(self: Painter, x: number, y: number, w: number, h: number): Painter
    origin_x: function(self: Painter): number
    origin_y: function(self: Painter): number
    rect: function(self: Painter, x: number, y: number, w: number, h: number, style: PaintStyle)
    text: function(self: Painter, x: number, y: number, text: string, style: PaintStyle)
    poly: function(self: Painter, points: {number}, style: PaintStyle)
    line: function(self: Painter, x0: number, y0: number, x1: number, y1: number, style: PaintStyle)
    mono: function(self: Painter, x: number, y: number, text: string, style: PaintStyle, cells?: integer)
    glyph: function(
      self: Painter, x: number, y: number, size: number, codepoint: integer, colour: string, font?: string
    )
    image: function(self: Painter, x: number, y: number, w: number, h: number, key: string)
    cut: function(self: Painter, x: number, y0: number, y1: number)
    layer: function(self: Painter, name: string)
    contains: function(self: Painter, x: number, y: number): boolean
  end

  --- A role that a painted view marks over its picture (`ctx.marks`), in
  --- pixels: a window paints it and moves it by the live values (the
  --- playhead), with no new picture.
  record PaintMark
    role: string
    x: number
    y: number
    w: number
    h: number
    props: MarkProps
  end

  --- What a painted view's `paint` gets besides the painter: its size in
  --- pixels, whether it has the keyboard, and, in a terminal that shows
  --- images, the cell in pixels and the terminal's colors. In a scene,
  --- `marks` takes the roles it marks over its picture.
  record PaintContext
    width: number
    height: number
    focused: boolean
    surface: boolean
    cell: StripPixels.Cell
    fg: string
    bg: string
    marks: {PaintMark}
  end

  -- The pointer ------------------------------------------------------------------

  --- A pointer event of the terminal (and of a view drawn in cells in a
  --- window): `kind` is `down`, `up`, `drag`, `move`, `scroll_up`,
  --- `scroll_down`, `scroll_left` or `scroll_right`. `x` and `y` are in
  --- the view's cells (fractions in a window, which says so with
  --- `fine`). `mods` holds `C`, `A` and `S`. On a hit region, `hit` is its
  --- action and `rect` the region; in a plane, `at` is where in its domain.
  --- A terminal that reports the pointer in pixels gives them too (`px`,
  --- `py`, on the screen).
  record MouseEvent
    kind: string
    button: string
    x: number
    y: number
    px: number
    py: number
    mods: string
    double: boolean
    fine: boolean
    view_x: number
    view_y: number
    w: number
    h: number
    win: integer
    hit: HitAction
    rect: types.Rect
    at: types.Point
    dx: number
    dy: number
    moved: boolean
    clip: integer
  end

  --- A pointer event in pixels, for a view's `pointer`: `kind` is
  --- `down`, `up`, `move` (a button held), `hover`, `double` or `wheel`.
  --- From a terminal, `col` and `row` are the cell of the screen under
  --- the pointer, where a menu opens. A window gives `drop` with the
  --- `clip` dragged from another window and let go here (paw/panes.tl).
  record PointerEvent
    kind: string
    x: number
    y: number
    col: number
    row: number
    clip: integer
    button: string
    ctrl: boolean
    shift: boolean
    alt: boolean
    dx: number
    dy: number
  end

  --- One place of a hit list (`Hits:add`): what each part of a gesture
  --- does there. `label` is a button's (`paw.canvas.button`).
  record HitPlace
    down: function(e: PointerEvent)
    drag: function(e: PointerEvent)
    up: function(e: PointerEvent)
    double: function(e: PointerEvent)
    wheel: function(e: PointerEvent)
    right: function(e: PointerEvent)
    x: number
    y: number
    w: number
    h: number
    label: string
  end

  --- The places a painted view acts on (`paw.canvas.hit_list()`).
  interface Hits
    clear: function(self: Hits)
    add: function(
      self: Hits, g: Painter, x: number, y: number, w: number, h: number, on: HitPlace | function(PointerEvent)
    ): HitPlace
    under: function(self: Hits, x: number, y: number): HitPlace
    pointer: function(self: Hits, e: PointerEvent): boolean
  end

  -- Keys -------------------------------------------------------------------------

  --- An area of a view's grid: rows `r0` to `r1`, columns `c0` to `c1`.
  --- `kind` is `char`, `line` or `block`.
  --- `visual` when a selection made it, `object` when a text object made
  --- it, `unstretched` for a selection that a key has not moved yet, and
  --- `clips` the clips chosen one by one in the arrange view (a set).
  --- `notes` names the notes of a piano roll text object (`iv`): note ids
  --- by clip id. An operator then acts on those notes alone.
  record Region
    view: string
    kind: string
    r0: number
    r1: number
    c0: number
    c1: number
    visual: boolean
    object: boolean
    unstretched: boolean
    clips: {integer: boolean}
    notes: {integer: {integer: boolean}}
    --- What a text object covers as a scope (`zn{motion}`): `ar` the
    --- region, `ag` the group, `it` the track. Nil for a block.
    scope: Scope
    --- True for the whole of what the view shows (`ie`): `znie` enters nothing.
    entire: boolean
  end

  --- What a function of a key mapping gets: the count typed before it,
  --- the register, the keys, the key typed after a `char` mapping and the
  --- mode. In a buffer type's keys, also its window and its buffer; in a
  --- kind of text buffer's, also the kind, what its pattern took
  --- and the name.
  record KeyContext
    count: integer
    --- An operator's own count, when it is made with `count = "operator"`.
    op_count: integer
    register: string
    keys: string
    char: string
    mode: string
    win: Window
    buf: LayoutBuffer
    kind: TextKindInfo
    args: {string}
    target: string
  end

  --- A key mapping's function.
  type KeyFn = function(ctx?: KeyContext)

  --- What a key maps to in `keymaps` and `motions`: a function, a
  --- command line, or `{ fn, desc = ..., mode = ... }`.
  record KeyEntry is {KeyFn | string}
    desc: string
    mode: string | {string}
    motion: boolean
    linewise: boolean
    jump: boolean
    repeatable: boolean
    nowait: boolean
    role: string
  end
  type KeyRhs = KeyFn | string | KeyEntry

  --- The keys that a buffer type or a kind of text buffer declares where
  --- it is made (`paw.layout.powers`).
  interface Powers
    keymaps: {string: KeyRhs}
    motions: {string: KeyRhs}
    textobjects: {string: function(ctx?: KeyContext): Region}
    operators: {string: function(region: Region, ctx?: KeyContext)}
  end

  --- A place that a view's `grid.mark` keeps and `grid.jump` goes back
  --- to: the row and the column, and what else the view needs to find it
  --- again (a text buffer's name), or the arrange view's `track` and `beat`.
  --- A place on the jump list also has the scope of the window (`scope`,
  --- and `scoped` true; nil `scope` is the song).
  record GridMark is {number | string}
    track: integer
    beat: number
    scoped: boolean
    scope: Scope
  end

  --- A place of a search in a grid.
  record GridHit
    row: number
    col: number
  end

  --- The cursor of a view that the keymap moves (`view.grid`): `get` and
  --- `set` its row and column. `step` is a step of the columns, `down` -1
  --- for rows that count upwards. `extent(row, col)` is the end of what
  --- is at a place. `mark` and `jump` keep a place that moves with what is
  --- there (a mark), and `search(text)` gives the places that match.
  record Grid
    get: function(): number, number
    set: function(row: number, col: number)
    step: function(): number
    down: integer
    extent: function(row: number, col: number): number
    mark: function(): GridMark
    jump: function(pos: GridMark)
    search: function(text: string): {GridHit}
  end

  --- What `K` shows: lines, with `title`. With `only`, that is all there
  --- is to say.
  record Description is {string | PageLine}
    only: boolean
    title: string
  end

  -- Views ------------------------------------------------------------------------

  --- What a view's `render` gets besides the buffer: whether it has the
  --- keyboard, where it is on the screen, and its window, if any.
  --- `follower` draws a window that follows another.
  record RenderContext
    focused: boolean
    x: integer
    y: integer
    win: Window
    buf: LayoutBuffer
    follower: boolean
  end

  --- The part of the room a view keeps where windows share it: fractions.
  record Share
    column: number
    least: number
    most: number
  end

  --- The live values a view adds, by group, then by bind, then the props
  --- of the bound mark: `{ params = { [bind] = { fraction, text } } }`.
  type LiveValues = {string: {string: {string: number | string | boolean}}}

  --- A view (`paw.ui.view`): a table with a `render` that draws in cells,
  --- or a `paint` that draws in pixels, or both. `docs/reference/lua-views.md`
  --- tells each field. A view of an extension in Teal is a record of its
  --- own that is a View, with its state in its own fields.
  interface View
    name: string
    title: string
    bufname: string
    help: string
    focusable: boolean
    modal: boolean
    --- Draws the view in cells.
    render: function(self: View, buf?: Buf, ctx?: RenderContext)
    --- A text of what `render` reads that no event announces, such as
    --- the cursor and the scroll of the window. A window without the
    --- keyboard whose text did not change keeps its cells.
    stamp: function(self: View, ctx?: RenderContext): string
    --- Gets the keys that have no mapping. True when it took the key.
    on_key: function(self: View, key: string): boolean
    on_mouse: function(self: View, e: MouseEvent): boolean
    on_show: function(self: View)
    on_hide: function(self: View)
    on_close: function(self: View)
    --- A clip let go over the view from another window (`e.clip`, in the cell `e.x`, `e.y`).
    on_drop: function(self: View, e: MouseEvent)
    --- Functions for the hit regions of roles, by the kind of action.
    gestures: {string: function(self: View, e: MouseEvent): boolean}
    grid: Grid
    status: function(self: View, ctx?: StatusContext): string | {Piece}
    describe: function(self: View): Description
    --- The scopes of mappings that come before the view's own: one, or a
    --- list with the first first (`paw.keymap.scopes`).
    subscope: function(self: View): string | {string}
    --- True when insert mode is a choice of keys that the key line lists.
    insert_hints: boolean
    title_of: function(self: View): string
    --- Pixels, in a graphical frontend and a terminal that shows images.
    paint: function(self: View, g: Painter, ctx?: PaintContext)
    pointer: function(self: View, e: PointerEvent): boolean
    hits: Hits
    surface: boolean
    painted: string
    window: boolean
    window_keys: {string: string}
    --- What moves while the song plays (`docs/reference/lua-views.md`, Roles).
    live_roles: {string}
    still: boolean
    live_part: boolean
    --- For a `live_part` view: a text of what it is drawn from now, for a
    --- buffer `width` cells wide. The part is drawn again only when the
    --- text changes; nil draws it again on each frame of what moves.
    live_stamp: function(self: View, width: integer): string
    live_values: function(): LiveValues
    moving: function(self: View): boolean
    redraw_every: number
    scene_key: function(self: View): string
    scene_roles: {string}
    titled: boolean
    --- The state of each window, by the names of its fields.
    window_state: {string}
    window_fresh: {string}
    open_target: function(self: View, target: string): boolean, string
    window_target: function(self: View): string
    share: Share
    time_axis: function(self: View, ctx?: RenderContext): number, number, number
    set_time_axis: function(self: View, left: number, zoom: number, ctx?: RenderContext)
    buftype: Buftype
  end

  --- An entry of a menu at the pointer (`paw.ui.menu`): its `label`, what
  --- choosing it does (`run`) or the entries of its submenu (`items`), the
  --- keys that do the same (`keys`, shown at the right), a mark when it is
  --- `checked`, and `enabled = false` to show it but not choose it. An
  --- entry that the window does itself names it in `window` (paw/window_menus.tl).
  --- `separator`, or the text `"-"` in place of an entry, is a line.
  record MenuItem
    label: string
    run: function()
    items: {MenuEntry}
    keys: string
    checked: boolean
    enabled: boolean
    window: string
    separator: boolean
  end

  --- An entry of a menu, or `"-"` for a line between entries.
  type MenuEntry = string | MenuItem

  --- Where `paw.ui.menu` opens: a cell of the screen.
  record MenuOptions
    x: number
    y: number
  end

  --- Where a view is on the screen (`paw.ui.arrange`): its name, its
  --- window, and its rectangle in cells.
  record ScreenRect
    name: string
    win: integer
    x: integer
    y: integer
    w: integer
    h: integer
    after: string
  end

  --- The view that floats over the others (`paw.ui.open`), and the view
  --- that has the keyboard after it.
  record Float
    name: string
    title: string
    width: integer
    height: integer
    top: boolean
    back: string
  end

  --- What `paw.ui.open` takes.
  record FloatOptions
    title: string
    width: integer
    height: integer
    top: boolean
  end

  -- Buffer types -----------------------------------------------------------------

  --- What a scope is made from (paw/scope.tl). A group or a region scope
  --- follows its source: a track added to the group, or the region moved,
  --- changes the scope.
  enum ScopeKind
    "group"
    "track"
    "tracks"
    "region"
    "range"
    "nest"
  end

  --- A scope: what a window shows of the song (paw/scope.tl). `id` is the
  --- group, track, region or subproject ("nest") it is made of; `tracks` a
  --- fixed list ("tracks", "range"), nil for every track of the parent;
  --- `from` and `to` its time in beats ("range"), nil for all the time of
  --- the parent. A subproject has its own tracks and timeline; `clip` is
  --- the clip of it that the window entered through, which places its
  --- beats in the song's. `parent` is the scope it was entered from (nil:
  --- the song): the window's stack.
  record Scope
    kind: ScopeKind
    id: integer
    tracks: {integer}
    from: number
    to: number
    name: string
    clip: integer
    parent: Scope
  end

  --- A fold of a window (paw/folds.tl): a scope drawn in place, as one
  --- row ("group", "tracks") or one column ("region", "range"). `closed`
  --- says whether it is folded now; nil for a region means that the
  --- window's `foldlevel` decides. View state: never in the project.
  record Fold
    kind: ScopeKind
    id: integer
    tracks: {integer}
    from: number
    to: number
    name: string
    closed: boolean
  end

  --- The rows of one track in a window's vertical zoom.
  record TrackRows
    track: integer
    rows: integer
  end

  --- A window's vertical zoom (paw/vzoom.tl): the rows of each track in
  --- the arrange view (`track_rows`; nil: `paw.opt.track_height`), the
  --- rows of some tracks of their own (`tracks`), the rows of each
  --- automation lane (`lane_rows`; nil: 2) and the rows of each key in
  --- the piano roll (`key_rows`; nil: 1). View state: never in the project.
  record VZoom
    track_rows: integer
    tracks: {TrackRows}
    lane_rows: integer
    key_rows: integer
  end

  --- A window of the layout (paw/layout.tl): its id, the view or buffer
  --- type it shows, its buffer, its options and its own state. An
  --- interface: a window of the layout is a node of a tab's tree too
  --- (`paw.layout.Node`). `scope` is the part of the song it shows, the
  --- innermost level of its stack (nil: the whole song). `folds` are its
  --- folds (paw/folds.tl), and `foldlevel` how many levels of regions
  --- stay open (nil: all of them). `vzoom` is how tall its rows are
  --- (paw/vzoom.tl; nil: as the options say).
  interface Window
    id: integer
    view: string
    buf: integer
    hidden: boolean
    opts: {string: string | number | boolean}
    state: {string: string | number | boolean}
    scope: Scope
    folds: {Fold}
    foldlevel: integer
    vzoom: VZoom
  end

  --- A buffer (paw/layout.tl): its number, its name, its type, the
  --- target it was made for, the state that the type's `create` gave,
  --- and its options, from the type's `options`.
  record LayoutBuffer
    id: integer
    name: string
    type: string
    target: string
    listed: boolean
    single: boolean
    state: {string: string | number | boolean}
    options: {string: string | number | boolean}
  end

  --- How a buffer type keeps the time of a window (`timebind`): the beat
  --- at the left edge, the columns of a beat, and the beats shown.
  record TimeAxis
    get: function(win: Window): number, number, number
    set: function(win: Window, left: number, zoom: number)
  end

  --- A buffer type (`paw.buftype`): a buffer for each target, shown in
  --- any number of windows. Its functions get the window, whose `state`
  --- is the window's own, and `ctx.buf`, the buffer.
  interface Buftype is Powers
    name: string
    create: function(target: string, buf: LayoutBuffer): {string: string | number | boolean}
    render: function(win: Window, buf: Buf, ctx?: RenderContext)
    on_key: function(win: Window, key: string): boolean
    on_mouse: function(win: Window, e: MouseEvent): boolean
    title: function(buf: LayoutBuffer): string
    bufname: function(target: string, buf: LayoutBuffer): string
    options: {string: string | number | boolean}
    listed: boolean
    modal: boolean
    delete: function(buf: LayoutBuffer)
    alive: function(buf: LayoutBuffer): boolean
    time: TimeAxis
    claims: function(name: string): boolean
    window: function(): Window
    grid: function(win: Window): Grid
    describe: function(win: Window): Description
    status: function(win: Window, ctx?: StatusContext): string | {Piece}
    subscope: function(win: Window): string
    paint: function(win: Window, g: Painter, ctx?: PaintContext)
    pointer: function(win: Window, e: PointerEvent): boolean
    help: string
  end

  -- Text buffers -----------------------------------------------------------------

  --- An item that a kind of text buffer reads: one line, with its id.
  interface TextItem
    id: integer | string
  end

  --- What a kind's functions get: the buffer, the kind, what the pattern
  --- took from the name, and the name.
  record TextContext
    buf: LayoutBuffer
    kind: TextKindInfo
    args: {string}
    target: string
  end

  --- A line that changed (`changes.changed`): its fields as read and as
  --- they are now, and the names of the fields that differ.
  --- `row` is the line's row in the text.
  record TextChange<F>
    id: integer | string
    fields: F
    base: F
    keys: {string}
    row: integer
  end

  --- A line that is new, a copy, gone or moved: its row in the text
  --- (`row`; of a line gone, where it was read), its place among the
  --- lines that read (`place`) and where it was read (`from`).
  record TextLine<F>
    id: integer | string
    copy_of: integer | string
    fields: F
    base: F
    keys: {string}
    row: integer
    place: integer
    from: integer
  end

  --- A line that does not read: its row, its text and what is wrong.
  record TextError
    row: integer
    text: string
    error: string
  end

  --- What changed in the text, for `plan`: also the lines that do not
  --- read, and `moved` when the lines kept are in another order.
  record TextChanges<F>
    changed: {TextChange<F>}
    deleted: {TextLine<F>}
    copied: {TextLine<F>}
    added: {TextLine<F>}
    lines: {TextLine<F>}
    moves: {TextLine<F>}
    errors: {TextError}
    moved: boolean
  end

  --- What the steps of a plan share: what each step made for a line,
  --- and the functions that undo a change outside the project.
  record PlanState
    made: {integer: integer | string}
    undo: {function()}
  end

  --- A step of a plan: what it does, in words, and `run`.
  record PlanStep
    text: string
    quiet: boolean
    run: function(state: PlanState)
  end

  --- A kind of text buffer (`paw.textbuf.kind`): a list edited as text.
  --- It reads items (`I`), writes each as cells, reads a line back into
  --- fields (`F`), and makes a plan of steps from the changes.
  --- A kind of text buffer, whatever its items and fields: what a kind's
  --- functions and keys get as `ctx.kind`. A kind with fields of its own
  --- (`tree` of the files' kinds) is read with a cast.
  interface TextKindInfo
    name: string
    pattern: string
    readonly: string
    gutter: boolean
    static: boolean
    hint: string
  end

  record TextKind<I is TextItem, F> is Powers, TextKindInfo
    name: string
    pattern: string
    title: function(ctx?: TextContext): string
    read: function(ctx?: TextContext): {I}, string
    format: function(item: I, ctx?: TextContext): {string}
    parse: function(text: string, ctx?: TextContext): F, string
    plan: function(changes: TextChanges<F>, ctx?: TextContext): {PlanStep}, string
    keywords: {string: boolean}
    open: function(ctx?: TextContext, line?: TextLine<F>, text?: string)
    parent: function(ctx?: TextContext): string
    readonly: string
    gutter: boolean
    static: boolean
    paint: function(
      buf: Buf,
      x: integer,
      y: integer,
      text: string,
      kind: TextKind<I, F>,
      width: integer,
      row: integer,
      lbuf: LayoutBuffer
    )
    style: function(cell: string, index: integer): string
    first_style: string
    hint: string
    describe: function(ctx?: TextContext): Description
    status: function(ctx?: TextContext, line?: StatusContext): string | {Piece}
    keys: {{string, string}}
  end

  -- The status line --------------------------------------------------------------

  --- The characters views draw with, by what they are for
  --- (`paw.draw.g`): plain ASCII ones while `paw.opt.ascii` is on.
  record Glyphs
    rule: string
    bar: string
    beat: string
    step: string
    tick: string
    cap: string
    playhead: string
    loop_in: string
    loop_out: string
    clip_start: string
    --- Before the name of a block of a subproject.
    nest: string
    punch_in: string
    punch_out: string
    meter_full: string
    meter_half: string
    meter_off: string
    peak: string
    upper: string
    lower: string
    full: string
    slider_on: string
    knob: string
    slider_off: string
    pan_rail: string
    pan_mark: string
    fader: string
    fader_rail: string
    zero: string
    point: string
    open: string
    closed: string
    stripe: string
    stripe_sel: string
    send: string
    out: string
    chain: string
    sep: string
    dot: string
    play: string
    stop: string
    rec: string
    modified: string
    bypass: string
    on: string
    ellipsis: string
    cursor: string
    warn: string
    error: string
    hairline: string
    strip_sep: string
    tl: string
    tr: string
    bl: string
    br: string
    h: string
    v: string
    mark: string
    move_up: string
    move_down: string
    remove: string
    editor: string
    --- A cell filled from the bottom, one eighth to eight.
    eighths: {string}
  end

  --- What a status line component gets: the width of the screen, the
  --- bar (`status`, `winbar`, `inactive_winbar`, `tabline`), the mode,
  --- the focused view (and on a window's bar whether it has the keys),
  --- the glyphs, the theme, and the transport, the project and the engine
  --- (read when asked for).
  record StatusContext
    width: integer
    which: string
    mode: string
    view: string
    focused: boolean
    active: boolean
    g: Glyphs
    --- The highlight group of the mode pill by mode, of each section by
    --- its letter, and of the separators.
    record Theme
      mode: {string: string}
      a: string
      b: string
      c: string
      x: string
      y: string
      z: string
      sep: string
    end
    theme: Theme
    transport: types.Transport
    project: types.Project
    engine: types.EngineInfo
  end

  --- What a component gives: nothing, text, or pieces.
  type StatusText = string | {Piece}

  --- A status line component (`paw.statusline.component`). `min` is the
  --- narrowest screen it shows on, `rank` how late it goes when the line
  --- is too long (0 never). With `key(ctx)`, it runs again only when that
  --- changes. With `shrink`, its text is cut before any component goes.
  --- Between whole frames, while only what moves is drawn again (the
  --- meters, the playhead), the line is drawn again only when a component
  --- may have changed: `still` says it changes only when the screen is
  --- drawn whole (after a key, an edit or `paw.api.ui_redraw`), and
  --- `moves(ctx)` gives a text of what it changes with by itself (the
  --- playhead's position). Without either, its `key` is used, and with
  --- none of the three the line is drawn again on each such frame.
  record StatusComponent
    name: string
    fn: function(ctx?: StatusContext): StatusText
    min: integer
    rank: integer
    style: string
    key: function(ctx?: StatusContext): string | number
    moves: function(ctx?: StatusContext): string | number
    cond: function(ctx?: StatusContext): boolean
    fmt: function(text: string): string
    pill: boolean
    shrink: boolean
    still: boolean
  end

  -- The track column and the ruler's bar labels --------------------------------

  --- What a part of the track column or a bar label gives: nothing,
  --- text, or pieces (`{ { "3", "TrackNr" } }`).
  type ColumnCells = string | {Piece}

  --- What the track column knows of all the tracks drawn, once a draw:
  --- what a component's `width` function gets. `rows` are the ids of the
  --- tracks drawn, in order (`paw.groups.rows()`); `count` how many lines
  --- the counts of `j` and `k` go over (tracks, and lanes in normal mode
  --- when lanes are open).
  record TrackColumnFrame
    rows: {integer}
    count: integer
  end

  --- What a component of the track column draws one line from. `row` is
  --- the track's number (its place among the tracks drawn, what `5G`
  --- takes); `line` 0 for the first line of the track's row, then 1, 2,
  --- for the lines under it; `kind` `track`, or `lane` (an automation
  --- lane shown as a row, `lane` its id) or `take` (a take lane);
  --- `relative` how many `j` or `k` reach the line, nil for a line the
  --- counts skip; `cursor` true on the cursor's line; `width` the
  --- component's columns; `x` the column clicked, for `click` only;
  --- `glyphs` and `styles` the component's own (what `set` gave it).
  record TrackColumnContext
    row: integer
    line: integer
    kind: string
    lane: integer
    relative: integer
    cursor: boolean
    width: integer
    x: integer
    g: Glyphs
    glyphs: {string: string}
    styles: {string: string}
  end

  --- How wide a component is: a number of columns, or a function of the
  --- frame that gives it (0 hides the component for this draw).
  type TrackColumnWidth = function(frame: TrackColumnFrame): integer

  --- A component of the track column (`paw.trackcolumn.add`), as Neovim's
  --- 'statuscolumn': its place among the others (`order`, lower to the
  --- left), its `width`, what it draws on each line of a track
  --- (`render`), what a click on it does (`click`), and what `K` says of
  --- the cursor's track (`describe`, a line or nothing). `glyphs` and
  --- `styles` are the characters and highlight groups it draws with, by
  --- name, which a user changes with `paw.trackcolumn.set`.
  record TrackColumnComponent
    name: string
    order: number
    width: integer | TrackColumnWidth
    render: function(track: integer, ctx: TrackColumnContext): ColumnCells
    click: function(track: integer, ctx: TrackColumnContext)
    describe: function(track: integer, ctx: TrackColumnContext): string
    glyphs: {string: string}
    styles: {string: string}
    --- Added, but not put in `paw.opt.trackcolumn`.
    hidden: boolean
    --- The extension whose code added or last changed it, nil for the
    --- user's (paw/ext.lua: what an extension owns).
    ext: string
  end

  --- A sign of the `signs` component (`paw.trackcolumn.sign`): one
  --- character for a track, or nothing. Where several have one, the
  --- highest `priority` shows. `glyphs` and `styles` as a component's;
  --- `describe` what `K` says of the track.
  record TrackSign
    name: string
    priority: integer
    render: function(track: integer, ctx: TrackColumnContext): ColumnCells
    describe: function(track: integer, ctx: TrackColumnContext): string
    glyphs: {string: string}
    styles: {string: string}
    --- The extension whose code added or last changed it, nil for the
    --- user's (paw/ext.lua: what an extension owns).
    ext: string
  end

  --- What a bar label of the ruler draws one bar from. `bar` is the
  --- bar's number as shown (counted from 1 at the start of a scope with
  --- time, see `paw.scope`), `song_bar` its number in the song; `beat`
  --- where it starts; `relative` how many `W` (or
  --- `B`, behind the cursor) reach it, nil while `paw.opt.relativebar`
  --- is off; `cursor` true on the bar the cursor is in; `style` the style
  --- the bar's number has there (in the loop, in the punch range);
  --- `glyphs` and `styles` the label's own; `room` the columns left for
  --- the part before the next bar's label.
  record RulerContext
    bar: integer
    song_bar: integer
    beat: number
    room: integer
    relative: integer
    cursor: boolean
    style: string
    g: Glyphs
    glyphs: {string: string}
    styles: {string: string}
  end

  --- A part of each bar's label on the ruler (`paw.ruler.add`): its place
  --- among the others (`order`, lower first), what it draws, and the
  --- characters and highlight groups it draws with (`paw.ruler.set`).
  record RulerLabel
    name: string
    order: number
    render: function(bar: integer, ctx: RulerContext): ColumnCells
    glyphs: {string: string}
    styles: {string: string}
    --- Added, but not put in `paw.opt.barlabel`.
    hidden: boolean
    --- The extension whose code added or last changed it, nil for the
    --- user's (paw/ext.lua: what an extension owns).
    ext: string
  end

  --- What `paw.ruler.set` changes of a part of the bar labels: only the
  --- fields given; `glyphs` and `styles` are merged into the part's.
  record RulerPatch
    order: number
    render: function(bar: integer, ctx: RulerContext): ColumnCells
    glyphs: {string: string}
    styles: {string: string}
  end

  --- What a lane of the ruler draws on (`paw.ruler.add_lane`): `buf` its
  --- rows under the bar numbers (`rows` of them), `x` the column of a beat,
  --- `scroll` and `span` the beats in sight, `glyphs` and `styles` the
  --- lane's own. With time folds (paw/folds.tl), `folded(beat)` is true for
  --- a beat inside a folded span, after its start, and `closed(id)` for a
  --- region that is folded into its column.
  record RulerLaneContext
    buf: Buf
    rows: integer
    x: function(beat: number): integer
    scroll: number
    span: number
    folded: function(beat: number): boolean
    closed: function(region: integer): boolean
    glyphs: {string: string}
    styles: {string: string}
  end

  --- A lane of rows under the ruler's bar numbers, as the regions' lane:
  --- `rows` says how many rows it needs now (0 for none), `render` draws
  --- them. Lanes stack in their `order`, lower first.
  record RulerLane
    name: string
    order: number
    rows: function(ctx: RulerLaneContext): integer
    render: function(ctx: RulerLaneContext)
    glyphs: {string: string}
    styles: {string: string}
    --- The extension whose code added or last changed it, nil for the
    --- user's (paw/ext.lua: what an extension owns).
    ext: string
  end

  --- What `paw.ruler.set_lane` changes of a lane: only the fields given;
  --- `glyphs` and `styles` are merged into the lane's.
  record RulerLanePatch
    order: number
    rows: function(ctx: RulerLaneContext): integer
    render: function(ctx: RulerLaneContext)
    glyphs: {string: string}
    styles: {string: string}
  end

  --- What `paw.trackcolumn.set` and `paw.trackcolumn.set_sign` change of
  --- a component or a sign: only the fields given; `glyphs` and `styles`
  --- are merged into its own.
  record ColumnPatch
    order: number
    width: integer | TrackColumnWidth
    priority: integer
    render: function(track: integer, ctx: TrackColumnContext): ColumnCells
    click: function(track: integer, ctx: TrackColumnContext)
    describe: function(track: integer, ctx: TrackColumnContext): string
    glyphs: {string: string}
    styles: {string: string}
  end

  -- Insert mode in the arrange view ------------------------------------------------

  --- How long an inserted item is: a number of beats, or text: `"2 bars"`,
  --- `"3 steps"` (grid steps), `"8 beats"`, or `"marker"` (up to the next
  --- marker, or the start or the end of a region, after the cursor).
  type InsertLength = number | string

  --- What an insert key gets (`paw.insert`): the key and the kind as it is
  --- for the cursor's track (`per_track` applied), the cursor's track
  --- (nil when the cursor is on no track, 0 on the master track) and lane
  --- (the automation lane row it is on, or nil), the beat, the length in
  --- beats (from the kind's `length`), and `index` of `count` (`3m` makes
  --- three: 1, 2, 3). `name` is the kind's `name`, with `%d` made a number:
  --- the number of the clip on its track, of the marker or of the region.
  --- `placed(item)` is for a kind that asks first (a file): it gives the
  --- item when it is made, as `insert` returns it otherwise.
  record InsertContext
    key: string
    spec: InsertKind
    track: integer
    lane: integer
    beat: number
    length: number
    index: integer
    count: integer
    name: string
    placed: function(item: InsertedItem)
  end

  --- What an insert key made. `what` is a word (`clip`, `marker`,
  --- `region`, `point`, or the kind's own) and `id` its id. The cursor
  --- steps on by `length` beats (a grid step when nil). `remove` takes it
  --- back (`<BS>`). `text` says what it is, in the message.
  record InsertedItem
    what: string
    id: integer
    start: number
    length: number
    text: string
    remove: function()
  end

  --- A key of the arrange view's insert mode (`paw.insert.add`): what it
  --- inserts at the cursor. `kind` is `midi`, `audio` (a file, asked
  --- for), `region`, `marker`, `automation` (a point of the lane), or the
  --- name of a kind of clip (`paw.clip_kinds`); `insert(ctx)` in place of
  --- what the kind does gives full control. The data of what it inserts:
  --- `length`, `name` (`"Verse %d"`), `notes` that a MIDI clip starts
  --- with, `args` for a kind of clip's `create`. `tracks` lists the kinds
  --- of track it goes on (`track` for a track of no kind; nil for every
  --- one), and `per_track` changes it on a kind of track. `open(ctx,
  --- item)` is what `<CR>` does after it: open the item in its editor.
  --- `order` places it in the hints; `hidden` keeps it out of
  --- `paw.opt.insertkeys`.
  record InsertKind
    key: string
    kind: string
    desc: string
    length: InsertLength
    name: string
    notes: {objects.NoteInput}
    args: {string}
    tracks: {string}
    per_track: {string: InsertPatch}
    insert: function(ctx: InsertContext): InsertedItem, string
    open: function(ctx: InsertContext, item: InsertedItem)
    order: number
    hidden: boolean
    --- The extension whose code added or last changed it, nil for the
    --- user's (paw/ext.lua: what an extension owns).
    ext: string
  end

  --- What `paw.insert.set` changes of a key: only the fields given. `key`
  --- moves it to another key.
  record InsertPatch
    key: string
    kind: string
    desc: string
    length: InsertLength
    name: string
    notes: {objects.NoteInput}
    args: {string}
    tracks: {string}
    per_track: {string: InsertPatch}
    insert: function(ctx: InsertContext): InsertedItem, string
    open: function(ctx: InsertContext, item: InsertedItem)
    order: number
    hidden: boolean
  end

  -- Step input -------------------------------------------------------------------

  --- A key that the controller played for step input (`paw.step.target`):
  --- its pitch, its velocity (1 to 127, or `paw.opt.step_velocity`), its
  --- MIDI 2.0 attribute, where it came from, and `chord` when another key
  --- is still held (the key joins the chord of that key).
  record StepNote
    pitch: integer
    velocity: integer
    attr: types.NoteAttr
    channel: integer
    port: string
    chord: boolean
  end

  --- A view that takes step input (`paw.step.target(name, spec)`).
  --- `active()` is true while it listens. `track()` is the track whose
  --- MIDI input it listens to, and that plays the controller. `note(e)`
  --- enters a key, `release()` is told when the last held key is released,
  --- and `status()` is its title, for example `STEP C4 · 1 beat`.
  --- `actions` does what a control of the controller asks
  --- (`paw.step.bind`), by the name of the action: `rest`, `tie`, `back`,
  --- `dur.8` and the others. An action that the target does not have says
  --- `not here: <action>`.
  interface StepTarget
    active: function(): boolean
    track: function(): integer
    note: function(e: StepNote)
    release: function()
    status: function(): string
    actions: {string: StepAction}
  end

  --- An action of step input: `count` is how many times (1 from a control).
  type StepAction = function(count: integer)

  --- A control of the controller (`paw.step.bind`): a key or pad (`note`)
  --- or a controller (`cc`, 64 the sustain pedal), 0 to 127, from the port
  --- of that name (every port when left out), on `channel` 1 to 16 (every
  --- channel when left out).
  record StepSource
    port: string
    channel: integer
    note: integer
    cc: integer
  end

  --- What a control does besides one action (`paw.step.bind`): `keys`, the
  --- keys typed in the view (`"=8t"`); or `down`, the action when no key is
  --- held, and `held`, the action while keys are held (the sustain pedal:
  --- `{ down = "rest", held = "tie" }`).
  record StepDo
    keys: string
    down: string
    held: string
  end

  --- A control and what it does, as `paw.step.bindings()` gives it:
  --- `action`, or what `StepDo` says. `saved` when it is in the file of
  --- the controls (`:step.learn`, or the default of the pedal), not from
  --- Lua.
  record StepBinding
    source: StepSource
    action: string
    keys: string
    down: string
    held: string
    saved: boolean
  end

  -- Pickers ----------------------------------------------------------------------

  --- What `audition(item)` gives: a label, and with `loading()` whether
  --- it is still made ready, and `keep(item)` in place of `on_choose`.
  record Hearing<T>
    label: string
    loading: function(): boolean
    keep: function(item: T)
  end

  --- An action of a picker on another key.
  record PickAction<T>
    fn: function(item: T, query: string)
    desc: string
    keep: boolean
  end

  --- What every picker has, whatever its items: what `paw.pick.sources`
  --- holds, and what the picker of pickers lists.
  interface PickInfo
    title: string
    desc: string
  end

  --- What a source that is a function gets, and what `paw.pick(name,
  --- extra)` gives it: `query` is typed in already.
  record PickExtra
    query: string
  end

  --- A source of `paw.pick.sources`: a picker, or a function that makes
  --- one.
  type PickEntry = PickInfo | function(extra: PickExtra): PickInfo

  --- A picker of items of type `T` (`paw.pick`, `paw.pick.sources`): the
  --- items, the line of each, and what Enter does. A source in
  --- `paw.pick.sources` has a `desc` too. The top of paw/pick.tl tells
  --- each field.
  record PickSource<T> is PickInfo
    prompt: string
    query: string
    items: {T} | function(): {T}
    more: function(ms: number): {T}, boolean, string
    format: function(item: T): string
    primary: function(item: T): string
    search: function(item: T): string
    on_choose: function(item: T)
    on_choose_multi: function(items: {T})
    on_cancel: function()
    preview: function(item: T, width: integer, height: integer): {string | PageLine}
    actions: {string: function(item: T, query: string) | PickAction<T>}
    multi: boolean
    width: integer
    height: integer
    top: boolean
    choose: string
    empty: string
    mode: string
    rank: function(item: T, query: string, text: string): number
    boost: function(item: T): number
    location: function(item: T): string | Location
    open: function(item: T, how: string)
    delete: function(items: {T})
    insert: function(item: T)
    audition: function(item: T): string | Hearing<T>
    audition_key: string
    audition_default: boolean
    audition_delay: function(item: T, ms: number): number
  end

  --- An item of a picker that is a plain line.
  record PickLine
    text: string
    desc: string
    name: string
  end

  -- Queries and grep -------------------------------------------------------------

  --- The kinds of node of a query. `project` is the root of the tree,
  --- which a query does not find.
  enum QueryKind
    "project"
    "track"
    "group"
    "clip"
    "note"
    "cc"
    "device"
    "lane"
    "point"
    "marker"
    "region"
  end

  --- A node of a query: `data` is the thing as `paw.api` gives it, the
  --- record of its kind (types.Track, types.Clip, types.Note, ...).
  --- Cast it to that record: `node.data as paw.types.Note`.
  record QueryNode
    kind: QueryKind
    id: integer
    data: QueryData
    parent: QueryNode
    track: integer
    clip: integer
    index: integer
    place: integer
    location: Location
    text: string
  end

  --- The fields that the data of every kind of node may have. Each kind
  --- has the rest of its record.
  interface QueryData
    id: integer
    name: string
    meta: types.Meta
  end

  --- What a query field gives: a number, text, true or false, or a list
  --- of texts any of which may match.
  type QueryValue = number | string | boolean | {string}

  --- A field of a kind of node (`paw.query.field`).
  type QueryField = function(node: QueryNode): QueryValue

  --- A part of an address (paw/address.tl): a stretch of time `{ from,
  --- to }` in beats, notes by id, pitches `{ low, high }`, or a value; in
  --- a render, a stretch `{ from, to }` in seconds; in a page of help
  --- (`paw://help/...`), a line and a column.
  record Selector
    time: {number}
    notes: {integer}
    pitch: {number}
    value: number
    seconds: {number}
    line: integer
    col: integer
  end

  --- A place: an address and, optionally, a part of it.
  record Location
    uri: string
    selector: Selector
  end

  --- How a view places locations (`paw.ui.locator`): `at` the location
  --- under its cursor, `position` where its cursor is and `place` where a
  --- location is in it (with `anywhere`, also one it does not show now),
  --- each as a list of numbers to sort by; `go` puts its cursor there.
  record Locator
    at: function(): Location
    position: function(): {number}
    place: function(location: Location, anywhere?: boolean): {number}
    go: function(location: Location)
  end

  --- A text that `paw.grep` searches: what it says, what kind of text it
  --- is (`track`, `lyric`), where it is (an address or a location), and
  --- that place in a few words.
  record GrepRecord
    text: string
    field: string
    location: string | Location
    where: string
  end

  --- A source of text for grep: it calls `add` for each text.
  type GrepSource = function(add: function(record: GrepRecord))

  -- Health -------------------------------------------------------------------------

  --- What a check reports through: `ok`, `info`, `warn` and `error`,
  --- each with a text and, for the last two, advice (a line or a list).
  record Health
    ok: function(text: string)
    info: function(text: string)
    warn: function(text: string, advice?: string | {string})
    error: function(text: string, advice?: string | {string})
  end

  --- A health check (`paw.health.register`).
  type HealthCheck = function(h: Health)

  --- What `paw.health.register` takes besides the check.
  record HealthOptions
    desc: string
  end

  -- Kinds of track ---------------------------------------------------------------

  --- What `create` gets besides the track: the words after
  --- `:track.add <kind>`, and the options of `paw.track_kinds.add`.
  record TrackKindArgs is {string}
    name: string
    index: integer
  end

  --- A track as `paw.track(id)` gives it (`paw.Track`).
  type TrackHandle = objects.Track

  --- A device as `paw.device(id)` gives it (`paw.Device`).
  type DeviceHandle = objects.Device

  --- A kind of track (`paw.track_kinds.define`). `title` and `letter`
  --- say how it is offered and shown. `create` makes an ordinary track
  --- this kind. `editor` opens a clip, `describe` gives a few words for
  --- `K`, and `is` claims a track that does not say its kind.
  record TrackKind
    name: string
    title: string
    letter: string
    create: function(track: TrackHandle, args: TrackKindArgs)
    editor: function(clip: integer): boolean
    describe: function(track: integer): string
    is: function(track: integer): boolean
  end

  -- Kinds of clip ----------------------------------------------------------------

  --- A clip as `paw.clip(id)` gives it (`paw.Clip`).
  type ClipHandle = objects.Clip

  --- Plain data, as the project saves a kind's data: text, a number,
  --- a boolean, or a list or a map of them. A kind's `serialize` gives
  --- it, and its `deserialize` takes it. Text alone is data in the
  --- kind's own text format (an `.lrc` file).
  type KindJson = string | number | boolean | {KindJson: KindJson}

  --- What a kind's `create` gets: the words after the kind's name in a
  --- command, and the options of `paw.clip_kinds.add`.
  record ClipKindArgs is {string}
    name: string
    start: number
    length: number
    track: integer
  end

  --- The clip that a kind's `compile` makes the output of: where it is
  --- and where it starts in its data (`offset`, in its `timeline`).
  record ClipInfo
    id: integer
    track: integer
    start: number
    length: number
    offset: number
    timeline: types.Timeline
  end

  --- What a kind's `compile` gives: what the clip sounds as (a MIDI or
  --- audio content: `{ kind = "midi", notes = ... }`), what it makes
  --- happen (`signals`, in its timeline from the start of its data), the
  --- files it uses, and its natural length in beats (optional).
  record Compiled
    sound: types.ClipContentData
    signals: {types.Signal}
    media: {types.MediaRef}
    length: number
  end

  --- A mark inside a clip in the arrange view: `at` in beats from the
  --- clip's start, its text, and the role that draws it.
  record ClipMark
    at: number
    text: string
    role: string
  end

  --- Where a kind's `look` draws: the clip's width in cells, and the
  --- beats of the clip that the cells show.
  record ClipLookContext
    width: integer
    from: number
    to: number
  end

  --- How a clip of a kind looks in the arrange view: the label drawn in
  --- its cells, marks inside it, pixels (as `buf:strip` draws them) and
  --- a color. Each is optional.
  record ClipLook
    label: string
    marks: {ClipMark}
    strip: StripOptions
    color: string
  end

  --- A signal of a clip at play, as the kind's `on_signal` gets it: its
  --- index in the clip's signals, where it is in the clip's timeline,
  --- when it is heard (nanoseconds), its payload (JSON text) and latch.
  record SignalInfo
    index: integer
    at: number
    at_ns: number
    body: string
    latch: string
  end

  --- What a jump on a track takes back: the clip's own state, or the
  --- whole track's.
  enum ChaseBack
    "clip"
    "track"
  end

  --- A kind of clip (`paw.clip_kinds.define`). `D` is the record of its
  --- data. The core keeps the data and never looks inside it: saving it
  --- is the kind's own job. `serialize` (required) turns `D` into plain
  --- data (`KindJson`): text, numbers, booleans, lists and maps. It is
  --- an error to give anything else (a function, a cycle, a number that
  --- is not finite). `deserialize` (required) turns the plain data and
  --- the version it was saved with back into `D`: migration from an
  --- older version happens there. Bytes (pictures, sound, video) never
  --- go in the data: they go in media files (`Compiled.media`).
  ---
  --- `title` and `letter` say how the kind is offered and shown;
  --- `version` is the version of `D` (1 if not given), and `ext` the
  --- file extension of data that `serialize` gives as one text (`lrc`).
  --- `create` makes the data of a new clip, `check` tells what is wrong
  --- with data (nil when it is good), and `compile` gives what the clip
  --- sounds as and makes happen. These must be fast and change nothing:
  --- each runs under `paw.opt.clip_kind_limit` milliseconds.
  ---
  --- The edits `split`, `trim` and `slip` are optional: without them, a
  --- clip keeps its data and moves its offset in it. Their positions are
  --- in the kind's `timeline`, from the start of the data. `describe`
  --- gives a few words for `K`, `look` how the clip is drawn, and
  --- `editor` opens it. `on_signal`, `chase`, `chase_back` and `on_stop`
  --- run at play. `insert` is a key of the arrange view's insert mode
  --- that inserts a clip of the kind (`paw.insert`), and `editor` is what
  --- `<CR>` does after it.
  record ClipKind<D>
    name: string
    title: string
    letter: string
    insert: string
    version: integer
    timeline: types.Timeline
    ext: string
    track_kind: string

    serialize: function(data: D): KindJson
    deserialize: function(stored: KindJson, version: integer): D, string

    create: function(args: ClipKindArgs): D, string
    check: function(data: D): string

    compile: function(data: D, clip: ClipInfo): Compiled, string

    on_signal: function(clip: ClipHandle, signal: SignalInfo)
    chase: function(clip: ClipHandle, beat: number)
    chase_back: ChaseBack
    on_stop: function(clip: ClipHandle)

    split: function(data: D, at: number): D, D
    trim: function(data: D, from: number, to: number): D
    slip: function(data: D, offset: number): D, number

    describe: function(clip: ClipHandle): string
    look: function(clip: ClipHandle, ctx: ClipLookContext): ClipLook
    editor: function(clip: ClipHandle): boolean

    formats: {string}
  end

  -- Roles ------------------------------------------------------------------------

  --- What a role's `cells` gets besides the buffer and the props.
  record RoleContext
    role: string
  end

  --- A role (`paw.roles.define`): `cells(buf, props, ctx)` draws it in
  --- cells, as the terminal comes first. `props` names its props and
  --- their contents, for documentation. `bound` is the props that a
  --- frontend takes from the live value of a bound mark. `P` is the
  --- record of its props. `stamp(buf, props)` gives a text of what `cells`
  --- shows for these props in `buf`: a bound mark is drawn again between
  --- whole frames only when it changes (a meter that falls by less than a
  --- cell keeps its cells). Without it, any change of the bound value
  --- draws the mark again.
  record Role<P is MarkProps>
    cells: function(buf: Buf, props: P, ctx?: RoleContext)
    stamp: function(buf: Buf, props: P): string
    props: {string: string}
    bound: {string}
    ext: string
  end

  -- Commands ---------------------------------------------------------------------

  --- An argument as the command line reads it: text, a number, true or false.
  type CommandArg = string | number | boolean

  --- A command's arguments: positional ones in order, named ones by name
  --- (`track.add Bass volume=-6` is `{ "Bass", volume = -6 }`).
  record CommandArgs is {CommandArg}
    metamethod __index: function(CommandArgs, string): CommandArg
    metamethod __newindex: function(CommandArgs, string, CommandArg)
  end

  --- What an Ex pattern matches (`paw.ex.items`): a note, a clip or a track.
  enum ExLevel
    "note"
    "clip"
    "track"
  end

  --- A note, a clip or a track that a range holds (`kind`): the track's id,
  --- the clip as `paw.api` gives it, the note and its place in the clip,
  --- and `at`, its beat in the song.
  record ExItem
    kind: ExLevel
    track: integer
    clip: types.Clip
    note: types.Note
    place: integer
    at: number
    order: integer
  end

  --- A range before a command (`paw.ex`): of time (`from` and `to` in
  --- beats of the song, `to` not included, and `bars`, the first and last
  --- bar they touch), of tracks (`tracks`), or the visual selection
  --- (`selection`, its `region` and `view`; `pitches` { low, high } when
  --- it was of some pitches, `clip_ids` when it was of clips chosen one by
  --- one). `items` are the matches that `:g` hands a command, `clips` the
  --- clips that a view's own address named, `single` one plain number (a
  --- count to commands without a range), `text` the range as typed.
  record CommandRange
    from: number
    to: number
    bars: {integer}
    tracks: {integer}
    track_range: boolean
    whole: boolean
    selection: boolean
    region: Region
    view: string
    pitches: {integer}
    clip_ids: {integer: boolean}
    items: {ExItem}
    clips: {integer}
    single: boolean
    text: string
  end

  --- What a command's function gets. The one who runs it may add fields of
  --- its own, which a command in Teal reads with a record of its own.
  interface CommandContext
    args: CommandArgs
    name: string
    count: integer
    range: CommandRange
    line: string
  end

  --- What a command gives back to the one who runs it: its own data.
  record CommandResult
  end

  --- Where the word being completed is: `word`, its `index` among the
  --- arguments (from 1), the `words` before it and the whole `line`.
  record CompleteInfo
    word: string
    index: integer
    words: {string}
    line: string
  end

  --- What a function of `complete` may give for each candidate: a table with
  --- `text` (or the text first) and `desc`.
  record CompleteCandidate is {string}
    text: string
    desc: string
  end

  type CompleteFn = function(string, CompleteInfo): {string | CompleteCandidate}

  --- How a command completes its arguments: a completer's name, a name for
  --- each argument, or a function.
  type Complete = string | {string} | CompleteFn

  --- A parameter that a command lets the user change after it ran
  --- (`paw.command`'s `adjust`): its `name`, the limits `min` and `max` and
  --- the `step` of a number, the `default` that it has when none was given,
  --- and the `values` that the command line suggests.
  record AdjustParam
    name: string
    min: number
    max: number
    step: number
    default: CommandArg
    values: {string}
  end

  --- What the panel of `<leader>.` shows (`paw.commands.panel()`): its
  --- `title`, the `params` of the last command that can be adjusted, and
  --- their `values` now.
  record AdjustPanel
    title: string
    params: {AdjustParam}
    values: {string: CommandArg}
  end

  --- What `paw.command` takes besides the name and the function.
  record CommandOptions
    desc: string
    raw: boolean
    complete: Complete
    label: string
    range: boolean
    ext: string
    adjust: {AdjustParam}
  end

  --- `paw.command`: `paw.command(name, fn, opts)` defines a command, and
  --- `paw.command.alias(alias, target)` gives it another name.
  record Command
    alias: function(alias: string, target: string)
    metamethod __call: function<C is CommandContext>(
      self: Command, name: string, run: function(C), opts?: CommandOptions
    )
  end

  -- Ex: fields and views -----------------------------------------------------------

  --- What a field of an Ex pattern reads and sets: a number or text.
  type ExValue = number | string

  --- What `:s` changes in a note, a clip or a track: the fields that
  --- `paw.api` keeps for it.
  record ExChange
    start: number
    length: number
    pitch: integer
    velocity: integer
    meta: types.Meta
    attr: types.NoteAttr | boolean
    name: string
    muted: boolean
  end

  --- How a field's value is read: a number, beats (`1/8` too), a pitch
  --- (`c4`, `c`, `60`) or text.
  enum ExFieldType
    "number"
    "beats"
    "pitch"
    "text"
  end

  --- A field that `:s` and `:g` patterns can name (`paw.ex.field`): its
  --- `level`, its `type`, `get(item)` and `set(item, value, change)`,
  --- which writes what changes into `change`. `min` and `max` bound a
  --- number.
  record ExField
    name: string
    level: ExLevel
    type: ExFieldType
    desc: string
    min: number
    max: number
    get: function(item: ExItem): ExValue
    set: function(item: ExItem, value: ExValue, change: ExChange)
  end

  --- How a view reads ranges (`paw.ex.view`): its columns as beats of the
  --- song (`song`, `col`), the clips it edits, its track, and how to go
  --- to a beat. A view of several clips may also say `clips_at(s, i)`,
  --- the clips that an address of its own at `i` names and where it ends;
  --- `selection(region, r)`, what a selection of its grid is as a range;
  --- `each_clip(r, run)`, how a command of its own runs on its clips.
  --- How `each_clip` runs a command on a range.
  type ExRun = function(r: CommandRange): CommandResult

  record ExView
    song: function(col: number): number
    col: function(beat: number): number
    clips: function(): {integer}
    track: function(): integer
    go: function(beat: number)
    clips_at: function(s: string, i: integer): {integer}, integer
    selection: function(region: Region, r: CommandRange)
    each_clip: function(r: CommandRange, run: ExRun): CommandResult
  end

  -- Extensions -------------------------------------------------------------------

  --- An extension's `manifest.lua`: its name, its version, what it is,
  --- the versions of the API and of other extensions it needs, and the
  --- names others may require it by.
  record Manifest
    name: string
    version: string
    description: string
    requires: {string: string}
    provides: {string}
  end

  --- An extension that paw loaded, or tried to (`paw.ext.loaded`): its
  --- name, where it is, its manifest, and whether it loaded, or why not.
  record ExtEntry
    name: string
    path: string
    manifest: Manifest
    version: string
    ok: boolean
    error: string
  end
end

return contracts
