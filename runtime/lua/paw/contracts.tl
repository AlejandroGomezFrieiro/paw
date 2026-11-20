-- The contracts: the tables that an extension gives to paw and that paw
-- gives back to it. A view, a buffer type, a kind of text buffer, a kind of
-- track, a role, a picker, a status line component, a query field, a
-- source of grep, a health check and a manifest. Each record has the
-- fields that the runtime reads (paw/ui.lua, paw/layout.lua, paw/keymap.lua,
-- paw/mouse.lua, paw/scene.tl, paw/canvas.tl, paw/statusline.tl and the
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
      mark: function(self: Buf, role: string, x: number, y: number, w: number, h: number, props?: MarkProps): Buf
      hit: function(self: Buf, x: number, y: number, w: number, h: number, action: HitAction)
      plane: function(self: Buf, x: number, y: number, w: number, h: number, opts: PlaneOptions): Plane
      columns: function(self: Buf, widths: {integer | string}, gap?: integer): Buf...
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
      glyph: function(self: Painter, x: number, y: number, size: number, codepoint: integer, colour: string, font?: string)
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
   record MouseEvent
      kind: string
      button: string
      x: number
      y: number
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
   end

   --- A pointer event in pixels, for a view's `pointer`: `kind` is
   --- `down`, `up`, `move` (a button held), `hover`, `double` or `wheel`.
   record PointerEvent
      kind: string
      x: number
      y: number
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
      add: function(self: Hits, g: Painter, x: number, y: number, w: number, h: number, on: HitPlace | function(PointerEvent)): HitPlace
      under: function(self: Hits, x: number, y: number): HitPlace
      pointer: function(self: Hits, e: PointerEvent): boolean
   end

   -- Keys -------------------------------------------------------------------------

   --- An area of a view's grid: rows `r0` to `r1`, columns `c0` to `c1`.
   --- `kind` is `char`, `line` or `block`.
   record Region
      view: string
      kind: string
      r0: number
      r1: number
      c0: number
      c1: number
   end

   --- What a function of a key mapping gets: the count typed before it,
   --- the register, the keys, the key typed after a `char` mapping and the
   --- mode. In a buffer type's keys, also its window and its buffer; in a
   --- kind of text buffer's, also the kind's name, what its pattern took
   --- and the name.
   record KeyContext
      count: integer
      register: string
      keys: string
      char: string
      mode: string
      win: Window
      buf: LayoutBuffer
      kind: string
      args: {string}
      target: string
   end

   --- A key mapping's function.
   type KeyFn = function(ctx?: KeyContext)

   --- What a key maps to in `keymaps` and `motions`: a function, a
   --- command line, or `{ fn, desc = ..., mode = ... }`.
   record KeyEntry
      {KeyFn | string}
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
      keymaps: {string:KeyRhs}
      motions: {string:KeyRhs}
      textobjects: {string:function(ctx?: KeyContext): Region}
      operators: {string:function(region: Region, ctx?: KeyContext)}
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
      mark: function(): {string:number}
      jump: function(pos: {string:number})
      search: function(text: string): {GridHit}
   end

   --- What `K` shows: lines, with `title`. With `only`, that is all there
   --- is to say.
   record Description
      {string | PageLine}
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
   type LiveValues = {string:{string:{string:number | string | boolean}}}

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
      --- Gets the keys that have no mapping. True when it took the key.
      on_key: function(self: View, key: string): boolean
      on_mouse: function(self: View, e: MouseEvent): boolean
      on_show: function(self: View)
      on_hide: function(self: View)
      on_close: function(self: View)
      on_drop: function(self: View, paths: {string}, e: MouseEvent)
      --- Functions for the hit regions of roles, by the kind of action.
      gestures: {string:function(self: View, e: MouseEvent): boolean}
      grid: Grid
      status: function(self: View, ctx?: StatusContext): string | {Piece}
      describe: function(self: View): Description
      subscope: function(self: View): string
      title_of: function(self: View): string
      --- Pixels, in a graphical frontend and a terminal that shows images.
      paint: function(self: View, g: Painter, ctx?: PaintContext)
      pointer: function(self: View, e: PointerEvent): boolean
      hits: Hits
      surface: boolean
      painted: string
      window: boolean
      window_keys: {string:string}
      --- What moves while the song plays (`docs/reference/lua-views.md`, Roles).
      live_roles: {string}
      still: boolean
      live_part: boolean
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

   --- A window of the layout (paw/layout.lua): its id, the view or buffer
   --- type it shows, its buffer, its options and its own state.
   record Window
      id: integer
      view: string
      buf: integer
      hidden: boolean
      opts: {string:string | number | boolean}
      state: {string:string | number | boolean}
   end

   --- A buffer (paw/layout.lua): its number, its name, its type, the
   --- target it was made for, and the state that the type's `create` gave.
   record LayoutBuffer
      id: integer
      name: string
      type: string
      target: string
      listed: boolean
      single: boolean
      state: {string:string | number | boolean}
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
      create: function(target: string, buf: LayoutBuffer): {string:string | number | boolean}
      render: function(win: Window, buf: Buf, ctx?: RenderContext)
      on_key: function(win: Window, key: string): boolean
      on_mouse: function(win: Window, e: MouseEvent): boolean
      title: function(buf: LayoutBuffer): string
      bufname: function(target: string, buf: LayoutBuffer): string
      options: {string:string | number | boolean}
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

   --- What a kind's functions get: the buffer, the kind's name, what the
   --- pattern took from the name, and the name.
   record TextContext
      buf: LayoutBuffer
      kind: string
      args: {string}
      target: string
   end

   --- A line that changed (`changes.changed`): its fields as read and as
   --- they are now, and the names of the fields that differ.
   record TextChange<F>
      id: integer | string
      fields: F
      base: F
      keys: {string}
   end

   --- A line that is new, a copy, gone or moved.
   record TextLine<F>
      id: integer | string
      copy_of: integer | string
      fields: F
      base: F
      place: integer
      from: integer
   end

   --- What changed in the text, for `plan`.
   record TextChanges<F>
      changed: {TextChange<F>}
      deleted: {TextLine<F>}
      copied: {TextLine<F>}
      added: {TextLine<F>}
      lines: {TextLine<F>}
      moves: {TextLine<F>}
   end

   --- What the steps of a plan share: what each step made for a line,
   --- and the functions that undo a change outside the project.
   record PlanState
      made: {integer:integer | string}
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
   record TextKind<I is TextItem, F> is Powers
      name: string
      pattern: string
      title: function(ctx?: TextContext): string
      read: function(ctx?: TextContext): {I}, string
      format: function(item: I, ctx?: TextContext): {string}
      parse: function(text: string, ctx?: TextContext): F, string
      plan: function(changes: TextChanges<F>, ctx?: TextContext): {PlanStep}, string
      keywords: {string:boolean}
      open: function(ctx?: TextContext, line?: TextLine<F>, text?: string)
      parent: function(ctx?: TextContext): string
      readonly: string
      gutter: boolean
      static: boolean
      paint: function(buf: Buf, x: integer, y: integer, text: string, kind: TextKind<I, F>, width: integer, row: integer, lbuf: LayoutBuffer)
      style: function(cell: string, index: integer): string
      first_style: string
      hint: string
      describe: function(ctx?: TextContext): Description
      status: function(ctx?: TextContext, line?: string): string | {Piece}
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
         mode: {string:string}
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
   record StatusComponent
      name: string
      fn: function(ctx?: StatusContext): StatusText
      min: integer
      rank: integer
      style: string
      key: function(ctx?: StatusContext): string | number
      cond: function(ctx?: StatusContext): boolean
      fmt: function(text: string): string
      pill: boolean
      shrink: boolean
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
   --- `paw.pick.sources` has a `desc` too. The top of paw/pick.lua tells
   --- each field.
   record PickSource<T> is PickInfo
      prompt: string
      query: string
      items: {T} | function(): {T}
      format: function(item: T): string
      primary: function(item: T): string
      search: function(item: T): string
      on_choose: function(item: T)
      on_choose_multi: function(items: {T})
      on_cancel: function()
      preview: function(item: T, width: integer, height: integer): {string | PageLine}
      actions: {string:function(item: T, query: string) | PickAction<T>}
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
      "project" "track" "group" "clip" "note" "cc" "device" "lane" "point" "marker" "region"
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
   record TrackKindArgs
      {string}
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

   -- Roles ------------------------------------------------------------------------

   --- What a role's `cells` gets besides the buffer and the props.
   record RoleContext
      role: string
   end

   --- A role (`paw.roles.define`): `cells(buf, props, ctx)` draws it in
   --- cells, as the terminal comes first. `props` names its props and
   --- their contents, for documentation. `bound` is the props that a
   --- frontend takes from the live value of a bound mark. `P` is the
   --- record of its props.
   record Role<P is MarkProps>
      cells: function(buf: Buf, props: P, ctx?: RoleContext)
      props: {string:string}
      bound: {string}
      ext: string
   end

   -- Extensions -------------------------------------------------------------------

   --- An extension's `manifest.lua`: its name, its version, what it is,
   --- the versions of the API and of other extensions it needs, and the
   --- names others may require it by.
   record Manifest
      name: string
      version: string
      description: string
      requires: {string:string}
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
