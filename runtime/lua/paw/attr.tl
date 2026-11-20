-- `paw.attr`: the MIDI 2.0 attribute a note may carry on its start, and
-- the articulations of the Note On Orchestral Articulation Profile
-- (M2-123) that are the attribute's commonest use.
--
--   note.attr = { type = 0x11, data = 0xA000 }   -- on a note; nil for none
--   paw.attr.m2("11.A")                -- { type = 0x11, data = 0xA000 }: pizzicato
--   paw.attr.m2("10.23")               -- legato, its variation 3 ("10.2.3" too)
--   paw.attr.m2("11.A", { direction = "up", string = 4 })
--   paw.attr.m2({ type = 0x11, data = 0xA000 })   -- "11.A"
--   paw.attr.parts(attr)               -- { type, subclass, variation, direction, reset, string }
--   paw.attr.describe(attr)            -- { code = "11.A", tag = "pz", name = "Pizzicato", ... }
--   paw.attr.delay_of(track, attr)     -- milliseconds the track's attr_map moves such a note: -80
--
-- A code is the classification (the attribute type, 10 to 1F in hex), a
-- dot, the subclass (one hex digit), and the variation (one more hex
-- digit) when it is not 0: "11.A" is classification 0x11 (staccatos and
-- shorts), subclass A (pizzicato); "10.23" legato, variation 3. Its sixteen bits of data are, from the top:
-- subclass 4, variation 4, direction 2, reserved 2, reset round robin 1,
-- string 3 (Figure 1 of M2-123). Types 0x1A to 0x1F are a library's own
-- articulations; 0x18 and 0x19 are reserved. Other types are not
-- articulations: 3 is a pitch in 7.9 (semitones and 512ths), 1 is a
-- manufacturer's and 2 a profile's own.
--
-- The core keeps and plays the attribute; what an instrument is told for
-- one it does not take (keyswitches, controllers) is the track's
-- `attr_map` (docs/reference/lua-objects.md). Names here are the profile's, short
-- tags for the piano roll; an articulation map may name them its own way.
--
-- Written in Teal (paw/lang.lua): the build compiles it to Lua.
local type types = require("paw.types")
local type Attr = types.NoteAttr
local api = require("paw.api")

--- A classification: its name, and each subclass's name and tag.
local record Class
  name: string
  subclasses: {integer:{string}}
end

--- The fields of an attribute's data.
local record Parts
  type: integer
  data: integer
  subclass: integer
  variation: integer
  direction: integer
  reset: boolean
  string: integer
end

--- What `m2` adds to a code.
local record Options
  variation: integer
  direction: string | integer
  string: integer
  reset: boolean
end

--- An attribute for people.
local record Description
  code: string
  tag: string
  name: string
  class: string
  text: string
end

--- Something with an id: a track object.
local interface HasId
  id: integer
end

local record M
  classes: {integer:Class}
end

--- The classifications: their names, and each subclass's name and tag.
M.classes = {
  [0x10] = { name = "Core sounds: sustains and strikes", subclasses = {
    [0] = { "Normal", "nor" }, { "Normal (part 2)", "nor" }, { "Legato", "leg" }, { "Molto legato", "mleg" },
    { "Glissando", "gls" }, { "Détaché", "det" }, { "Marcato", "mrc" }, { "Martelé", "mrt" },
    { "Senza vibrato", "nv" }, { "Con vibrato", "vib" }, { "Synchronized vibrato", "svib" },
  } },
  [0x11] = { name = "Staccatos and shorts", subclasses = {
    [0] = { "Staccato off the string", "stc" }, { "Staccato on the string", "stco" }, { "Slurred staccato", "slst" },
    { "Accented staccato", "acst" }, { "Staccatissimo", "stcs" }, { "Spiccato", "spc" }, { "Sautillé", "sau" },
    { "Martellato", "mtl" }, { "Long staccato", "lst" }, { "Portato", "por" }, { "Pizzicato", "pz" },
    { "Bartók pizzicato", "bpz" }, { "Col legno battuto", "clb" }, { "Col legno gestrichen", "clg" },
    { "String hand tap", "htap" }, { "Jeté", "jet" },
  } },
  [0x12] = { name = "Same note trills and repeats", subclasses = {
    [0] = { "Tremolo, flutter tongue", "trm" }, { "Growl", "grl" }, { "Other coloristic tremolo", "ctrm" },
    { "One note trill", "1tr" }, { "2 repeats", "rp2" }, { "3 repeats", "rp3" }, { "4 repeats", "rp4" },
    { "5 repeats", "rp5" }, { "6 repeats", "rp6" }, { "Faster repeats", "rpf" },
  } },
  [0x13] = { name = "Intervallic trills", subclasses = {
    [0] = { "Trill, half step", "trm2" }, { "Trill, half step, baroque", "trm2b" }, { "Trill, whole step", "trM2" },
    { "Trill, whole step, baroque", "trM2b" }, { "Tremolo, minor 3rd", "trm3" }, { "Tremolo, major 3rd", "trM3" },
    { "Tremolo, perfect 4th", "tr4" }, { "Tremolo, tritone", "trtt" }, { "Tremolo, perfect 5th", "tr5" },
    { "Tremolo, minor 6th", "trm6" }, { "Tremolo, major 6th", "trM6" }, { "Tremolo, minor 7th", "trm7" },
    { "Tremolo, major 7th", "trM7" }, { "Tremolo, octave", "tr8" },
  } },
  [0x14] = { name = "Additional colours, sustained", subclasses = {
    [0] = { "Natural harmonics", "hrm" }, { "Artificial harmonics", "ahrm" }, { "Col legno tratto", "clt" },
    { "Flautando", "fla" }, { "Octaves", "oct" }, { "Intervals, chords", "chd" }, { "Cuivré", "cui" },
    { "Lontano", "lon" }, { "Singing into the instrument", "sing" },
  } },
  [0x15] = { name = "Pitch and dynamic gestures", subclasses = {
    [0] = { "Fall at the end", "fall" }, { "Fall into the note", "fin" }, { "Rise at the end", "rise" },
    { "Rise into the note", "rin" }, { "Blue note down", "blu-" }, { "Blue note up", "blu+" },
    { "Grace note from below", "grc" }, { "Grace note from above", "grcb" }, { "Shake", "shk" },
    { "Crescendo", "cre" }, { "Decrescendo", "dim" }, { "Crescendo, decrescendo", "<>" },
    { "Decrescendo, crescendo", "><" }, { "Sforzando crescendo", "sfz<" },
  } },
  [0x16] = { name = "Scales, runs and arpeggios", subclasses = {
    [0] = { "Playable runs", "run" }, { "Playable tremolos", "ptrm" }, { "Playable glissando", "pgls" },
    { "Major scale run", "smaj" }, { "Minor scale run", "smin" }, { "Dominant 7th run", "sdom" },
    { "Diminished run, whole-half", "sdw" }, { "Diminished run, half-whole", "sdh" },
    { "Whole tone scale from C", "wt1" }, { "Whole tone scale from C#", "wt2" },
    { "Major pentatonic", "pmaj" }, { "Minor pentatonic", "pmin" }, { "Lydian", "lyd" }, { "Lydian b7", "lyd7" },
    { "Chromatic", "chr" }, { "Other scales and runs", "scl" },
  } },
  [0x17] = { name = "Effects and noises", subclasses = {
    [0] = { "Noises, sustained", "fx" }, { "Behind the bridge", "bbr" }, { "Random pizzicato", "rpz" },
    { "Harmonic glissando", "hgls" }, { "Random glissando", "rgls" }, { "Air, chiff, squeak", "air" },
    { "Mechanical, sustained", "mech" }, { "Mechanical, short", "mchs" }, { "Finger glide", "fgl" },
    { "Fret buzz", "fret" }, { "Thump", "thmp" }, { "Knock", "knck" }, { "Slap", "slap" }, { "Pop", "pop" },
    { "Tap", "tap" }, { "Click", "clik" },
  } },
}

local DIRECTIONS: {string:integer} = { down = 1, up = 2 }
local DIRECTION_NAMES: {integer:string} = { [1] = "down stroke", [2] = "up stroke" }

local function is_m2(kind: integer): boolean return kind >= 0x10 and kind <= 0x1F end

--- The fields of an attribute's data, as M2-123 lays them out: `{ type,
--- data, subclass, variation, direction, reset, string }`. Nil for none.
function M.parts(attr: Attr): Parts
  if not attr or (attr.type or 0) == 0 then return nil end
  local data = attr.data or 0
  return {
    type = attr.type, data = data,
    subclass = math.floor(data / 4096) % 16,
    variation = math.floor(data / 256) % 16,
    direction = math.floor(data / 64) % 4,
    reset = math.floor(data / 8) % 2 == 1,
    string = data % 8,
  }
end

--- An articulation's code as an attribute, or an attribute as its code
--- (nil when it is not an articulation of M2-123). `opts` adds what a
--- code leaves out: `variation` (0 to 15), `direction` ("down", "up", 1
--- or 2), `string` (1 to 7, highest first), `reset` (round robin).
function M.m2(code: string | Attr, opts?: Options): string | Attr
  if code is Attr then
    local p = M.parts(code)
    if not p or not is_m2(p.type) then return nil end
    local out = string.format("%X.%X", p.type, p.subclass)
    if p.variation > 0 then out = out .. string.format("%X", p.variation) end
    return out
  end
  local c, s, v = tostring(code):upper():match("^%s*(1%x)%.(%x)%.?(%x?)%s*$")
  if not c then error("an articulation's code is like 11.A or 10.23, not " .. tostring(code), 2) end
  opts = opts or {}
  local variation = v ~= "" and tonumber(v, 16) as integer or opts.variation or 0
  local dir = opts.direction
  local direction = (dir is string and DIRECTIONS[dir]) or tonumber(dir) as integer or 0
  local data = tonumber(s, 16) as integer * 4096 + variation % 16 * 256 + direction % 4 * 64
    + (opts.reset and 8 or 0) + (opts.string or 0) % 8
  return { type = tonumber(c, 16) as integer, data = data }
end

--- What an attribute is, for people: `{ code, tag, name, class, text }`
--- (`code` and `class` only for articulations), where `tag` is a few
--- letters for the piano roll and `text` one line for `K`. Nil for none.
function M.describe(attr: Attr): Description
  local p = M.parts(attr)
  if not p then return nil end
  local class = M.classes[p.type]
  if class then
    local sub = class.subclasses[p.subclass]
    local code = M.m2(attr) as string
    local name = sub and sub[1] or ("subclass " .. string.format("%X", p.subclass))
    local tag = sub and sub[2] or code
    local extra: {string} = {}
    if p.variation > 0 then extra[#extra + 1] = "variation " .. (p.variation + 1) end
    if DIRECTION_NAMES[p.direction] then extra[#extra + 1] = DIRECTION_NAMES[p.direction] end
    if p.string == 7 then extra[#extra + 1] = "another string"
    elseif p.string > 0 then extra[#extra + 1] = "string " .. p.string end
    if p.reset then extra[#extra + 1] = "round robin from its start" end
    if #extra > 0 then name = name .. ", " .. table.concat(extra, ", ") end
    return { code = code, tag = tag, name = name, class = class.name, text = string.format("%s (%s)", name, code) }
  elseif is_m2(p.type) and p.type >= 0x1A then
    local code = M.m2(attr) as string
    return { code = code, tag = code, name = "the library's own articulation " .. code, class = "Custom",
      text = string.format("the library's own articulation (%s)", code) }
  elseif p.type == 3 then
    local semis = p.data / 512
    local text = string.format("pitch %.2f", semis)
    return { tag = string.format("p%.1f", semis), name = text, text = text .. " (MIDI 2.0 attribute 3)" }
  end
  local text = string.format("attr 0x%02X 0x%04X", p.type, p.data)
  return { tag = string.format("a%02X", p.type), name = text, text = text }
end

--- The milliseconds that a note with `attr` (nil for none) on `track` plays
--- early (below 0) or late, from the `attr_map` of the track. So a library
--- that speaks slowly still sounds on the beat. 0 without a map.
function M.delay_of(track: integer | HasId, attr?: Attr): number
  return api.track_attr_delay(track is HasId and track.id or track as integer, attr)
end

--- The same attribute: both none, or the same type and data.
function M.same(a?: Attr, b?: Attr): boolean
  local ta, tb = a and a.type or 0, b and b.type or 0
  if ta == 0 or tb == 0 then return ta == tb end
  return ta == tb and (a.data or 0) == (b.data or 0)
end

return M
