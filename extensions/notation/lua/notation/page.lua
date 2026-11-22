-- The page view and printed pages: systems laid on sheets of paper with
-- margins, the title and composer at the head of the first, page numbers
-- on the others (Dorico's Engrave and Print modes, in a small way). `zp`
-- shows the score so, `:notation.export score.pdf` (or `.svg`) writes it.
--
-- A page's size is kept in staff spaces: an A4 sheet with a staff space of
-- 1.75 mm (a staff 7 mm high, Gould's size for most parts) is 120 spaces
-- wide, so the page scales with the staff, and on the screen the staff
-- space is the largest whose page fits the width (unless zoomed).
local api = paw.api
local engrave = require("notation.engrave")

local floor, max, round = math.floor, math.max, function(v) return math.floor(v + 0.5) end

local P = {}

--- Sheets, width and height in millimetres.
P.SIZES = { a4 = { 210, 297 }, letter = { 215.9, 279.4 } }
--- The staff space on paper, in millimetres.
P.SPACE_MM = 1.75
--- The margins, in millimetres.
P.MARGIN_MM = 13
--- Between pages on the screen, in pixels.
P.GAP = 16

paw.option.define("notation_paper", "white") -- the page view's paper: "white", or "theme" for the theme's colours
paw.option.define("notation_sheet", "a4") -- the page view's and the PDF's sheet: "a4" or "letter"

--- The pages' geometry for a staff space `sp` in px (and a cell, for whole
--- cells): `width`, `height`, `margin`, `header` (more room above the first
--- page's music, for the title), `gap`.
function P.geometry(sp, cell)
  local size = P.SIZES[paw.opt.notation_sheet] or P.SIZES.a4
  local px = sp / P.SPACE_MM
  local cw, ch = cell and cell.w or 1, cell and cell.h or 1
  local function cols(v) return math.ceil(v / cw) * cw end
  local function rows(v) return math.ceil(v / ch) * ch end
  return {
    width = cols(size[1] * px),
    height = rows(size[2] * px),
    margin = cols(P.MARGIN_MM * px),
    header = rows(10 * sp),
    gap = rows(P.GAP),
    key = table.concat({ sp, cw, ch, paw.opt.notation_sheet }, ":"),
  }
end

--- The largest staff space of the zoom's steps whose page fits `width` px.
function P.space_for(width)
  local best = engrave.STEPS[1]
  for _, s in ipairs(engrave.STEPS) do
    if P.geometry(s).width + 2 * P.GAP <= width then best = s end
  end
  return best
end

--- What heads the score: the project's title (its `meta.title`, else its
--- name, else the clip's) and composer (`meta.composer`).
function P.heading(clip_name)
  local p = api.project_get()
  local meta = type(p.meta) == "table" and p.meta or {}
  local named = p.name and p.name ~= "" and p.name ~= "untitled" and p.name
  local title = meta.title or named or clip_name or ""
  return tostring(title), tostring(meta.composer or "")
end

--- The systems of a layout on pages `geo` across a view `width` px wide,
--- centred: `engrave.systems`' result, with `pages` and `page_x`.
function P.systems(layout, st, geo, width, cache)
  local cw = st.whole and st.cell.w or 1
  local x = max(0, floor((width - geo.width) / 2 / cw) * cw)
  local eng = engrave.systems(layout, st, {
    x = x + geo.margin,
    width = x + geo.width - geo.margin,
    top = geo.gap,
    cache = cache,
    page = { height = geo.height, margin = geo.margin, header = geo.header, gap = geo.gap },
  })
  eng.page_x, eng.geometry = x, geo
  return eng
end

--- The paper of the pages from `first` to `last` into drawing ops, moved
--- by `dx, dy`: each sheet, the title and composer on the first, the
--- number on the others.
function P.paper(out, eng, dx, dy, opts)
  local st, geo = eng.style, eng.geometry
  local s = st.sp
  local title, composer = opts.title or "", opts.composer or ""
  for i, page in ipairs(eng.pages) do
    if not opts.only or opts.only == i then
      local x, y = eng.page_x + dx, page.y + dy
      local height = opts.heights and opts.heights[i] or geo.height
      if opts.shadow then out[#out + 1] = { "r", x + 3, y + 3, geo.width, height, "#00000040", "", 1, 0 } end
      out[#out + 1] = { "r", x, y, geo.width, height, st.paper, "", 1, 0 }
      if i == 1 then
        out[#out + 1] = {
          "t",
          x + geo.width / 2,
          y + geo.margin,
          title,
          st.ink,
          round(2.6 * s),
          1,
          "center",
          geo.width - 2 * geo.margin,
        }
        if composer ~= "" then
          out[#out + 1] = {
            "t",
            x + geo.width - geo.margin,
            y + geo.margin + round(4.2 * s),
            composer,
            st.ink,
            round(1.4 * s),
            0,
            "right",
            geo.width / 2,
          }
        end
        -- A part names its instrument at the top left, as parts are printed.
        if opts.part and opts.part ~= "" then
          out[#out + 1] = {
            "t",
            x + geo.margin,
            y + geo.margin + round(4.2 * s),
            opts.part,
            st.ink,
            round(1.5 * s),
            1,
            "left",
            geo.width / 2,
          }
        end
      else
        -- Even pages' numbers at the left, odd ones' at the right.
        local right = i % 2 == 1
        out[#out + 1] = {
          "t",
          right and x + geo.width - geo.margin or x + geo.margin,
          y + round(geo.margin / 2),
          tostring(i),
          st.ink,
          round(1.3 * s),
          0,
          right and "right" or "left",
          100,
        }
      end
    end
  end
end

--- Every system's ink at its place, into drawing ops moved by `dx, dy`
--- (`only`: the systems of one page).
function P.music(out, eng, layout, dx, dy, only)
  local st = eng.style
  local cache = eng.cache or { generation = 0 }
  for _, sys in ipairs(eng.systems) do
    if not only or sys.page == only then
      for _, placed in ipairs(sys.measures) do
        engrave.place(engrave.measure(cache, st, layout, sys, placed).ops, out, placed.x + dx, sys.y + dy)
      end
      local prefix, spans = engrave.system_ink(st, layout, sys, eng)
      engrave.place(spans.ops, out, dx, sys.y + dy)
      engrave.place(prefix.ops, out, dx, sys.y + dy)
    end
  end
end

--- Write a layout's pages to `path` as "pdf" (every page), "svg" (a file
--- for each page, numbered after the first) or "png" (the first page): on
--- white paper in black, the sheet `notation_sheet` at 1.75 mm to the staff
--- space. The last page ends under its last system instead of at the foot
--- of the sheet. `heading`: `title`, `composer`, and `part` (a part's
--- instrument). Returns the files written, and the number of pages.
function P.export(layout, path, format, heading)
  local sp = 10
  local st = engrave.style({
    space = sp,
    cell = { w = 1, h = 1 },
    ink = "#000000",
    paper = "#ffffff",
    accent = "#000000",
    whole_cells = false,
  })
  local geo = P.geometry(sp)
  geo.gap = 0
  local eng = P.systems(layout, st, geo, geo.width)
  local pages = {}
  for i, page in ipairs(eng.pages) do
    local height = geo.height
    if i == #eng.pages and #page.systems > 0 then height = math.min(height, page.at - page.y + geo.margin) end
    local ops = {}
    P.paper(
      ops,
      eng,
      0,
      -page.y,
      { only = i, title = heading.title, composer = heading.composer, part = heading.part, heights = { [i] = height } }
    )
    P.music(ops, eng, layout, 0, -page.y, i)
    pages[i] = { ops = ops, width = geo.width, height = height }
  end
  local size = P.SIZES[paw.opt.notation_sheet] or P.SIZES.a4
  -- Points to a pixel: the sheet's width in points over its width in pixels.
  local scale = size[1] / 25.4 * 72 / geo.width
  local written = {}
  if format == "pdf" then
    api.canvas_export(path, "pdf", pages, scale)
    written[1] = path
  else
    for i, page in ipairs(pages) do
      if format == "png" and i > 1 then break end
      local file = i == 1 and path or path:gsub("(%.%w+)$", "-" .. i .. "%1")
      api.canvas_export(file, format, { page })
      written[#written + 1] = file
    end
  end
  return written, #pages
end

return P
