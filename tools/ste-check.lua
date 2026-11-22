-- A checker for ASD-STE100 Simplified Technical English in paw's Markdown.
--
--   paw --clean --no-plugins -l tools/ste-check.lua docs/how-to/*.md README.md
--
-- It reports what a program can find: sentences that are too long (20 words
-- in a procedure, 25 in a description), semicolons, paragraphs of more than
-- six sentences, contractions, "-ing" forms, the present perfect, the passive
-- with "by", phrasal verbs, British spellings and unapproved words, each with
-- an alternative. A code span, a hyphenated word and a text in parentheses
-- count as one word. Code blocks, tables' values and generated pages are
-- skipped. It is a help to a writer, not the standard: see
-- .claude/skills/diataxis-docs/SKILL.md.

local files = arg or { ... }

-- Unapproved words and phrases, and what to write instead.
local WORDS = {
  ["ensure"] = "make sure",
  ["ensures"] = "makes sure",
  ["verify"] = "make sure",
  ["verifies"] = "makes sure",
  ["utilize"] = "use",
  ["utilise"] = "use",
  ["via"] = "through",
  ["e.g."] = "for example",
  ["i.e."] = "that is",
  ["etc."] = "and other ...",
  ["simply"] = "(remove)",
  ["basically"] = "(remove)",
  ["obviously"] = "(remove)",
  ["approximately"] = "about",
  ["prior"] = "before",
  ["subsequently"] = "then",
  ["thus"] = "so, then",
  ["hence"] = "so",
  ["whilst"] = "while",
  ["amongst"] = "among",
  ["upon"] = "on",
  ["whereas"] = "but",
  ["therefore"] = "so",
  ["additionally"] = "also",
  ["furthermore"] = "also",
  ["moreover"] = "also",
  ["however"] = "but",
  ["whether"] = "if",
  ["regarding"] = "about",
  ["numerous"] = "many",
  ["sufficient"] = "enough",
  ["commence"] = "start",
  ["terminate"] = "stop",
  ["attempt"] = "try",
  ["obtain"] = "get",
  ["retrieve"] = "get",
  ["modify"] = "change",
  ["perform"] = "do",
  ["performs"] = "does",
  ["facilitate"] = "help",
  ["leverage"] = "use",
  ["handy"] = "useful",
  ["lots"] = "many",
  ["gonna"] = "will",
  ["kinda"] = "(remove)",
}
local PHRASES = {
  { "in order to", "to" },
  { "set up", "configure, prepare" },
  { "sets up", "configures" },
  { "look up", "find" },
  { "looks up", "finds" },
  { "turn on", "enable, start" },
  { "turn off", "disable, stop" },
  { "go back", "return" },
  { "goes back", "returns" },
  { "carry out", "do" },
  { "find out", "find" },
  { "pick up", "get" },
  { "make up", "make" },
  { "fill in", "write" },
  { "point out", "show" },
  { "come back", "return" },
  { "comes back", "returns" },
  { "give up", "stop" },
  { "put in", "add" },
  { "take out", "remove" },
  { "out of the box", "(remove)" },
  { "under the hood", "inside" },
  { "a lot of", "many, much" },
  { "as well as", "and" },
  { "so that", "(two sentences, or: to)" },
  { "in case", "if" },
  { "as soon as", "when" },
  { "a number of", "some, many" },
  { "no-op", "does nothing" },
}
local BRITISH = {
  colour = "color",
  colours = "colors",
  coloured = "colored",
  behaviour = "behavior",
  behaviours = "behaviors",
  centre = "center",
  centres = "centers",
  licence = "license",
  licences = "licenses",
  grey = "gray",
  favour = "favor",
  favourite = "favorite",
  neighbour = "neighbor",
  neighbours = "neighbors",
  analyse = "analyze",
  catalogue = "catalog",
  dialogue = "dialog",
  metre = "meter",
  fibre = "fiber",
  programme = "program",
  travelled = "traveled",
  cancelled = "canceled",
  labelled = "labeled",
  modelled = "modeled",
  signalling = "signaling",
}
-- Words in "-ing" that are not verb forms.
local ING = {}
for w in
  ([[thing things nothing something anything everything string strings during bring brings
  ring rings king spring sing sings swing wing ping pings ceiling ceilings morning evening
  setting settings heading headings recording recordings binding bindings drawing drawings
  mapping mappings meaning meanings warning warnings timing timings rendering ending endings
  beginning padding offset spacing building wiring routing listing listings keyring
  thinking reading writing rating swing swings ming bling sting sling]]):gmatch("%S+")
do
  ING[w] = true
end

-- Stems of verbs that American spelling writes with -ize.
local IZE = {}
for w in
  ([[organ recogn real normal optim initial serial custom summar priorit synchron
  visual minim maxim final standard categor author special util emphas memor quant local
  random sanit token parameter apolog critic character general special harmon stabil]]):gmatch("%S+")
do
  IZE[w] = true
end

local function is_british_ise(w)
  local stem = w:match("^(%a+)is[ei][ds]?$") or w:match("^(%a+)ising$") or w:match("^(%a+)isations?$")
  return stem ~= nil and IZE[stem] == true
end

local reports, checked = 0, 0
local function report(path, line, msg)
  reports = reports + 1
  print(string.format("%s:%d: %s", path, line, msg))
end

local function words_of(s)
  s = s:gsub("`[^`]*`", " CODE "):gsub("%b()", " PAREN "):gsub("%[([^%]]*)%]%b()", "%1")
  s = s:gsub("%*%*", ""):gsub("[%*_]", "")
  local out = {}
  for w in s:gmatch("[%w'%.%-/]+") do
    if w:match("%a") or w:match("%d") then out[#out + 1] = w end
  end
  return out
end

local function sentences_of(text)
  local out, start = {}, 1
  text = text:gsub("`[^`]*`", function(c) return (c:gsub("[%.!?]", "\1")) end)
  for i = 1, #text do
    local ch = text:sub(i, i)
    if (ch == "." or ch == "!" or ch == "?") and (i == #text or text:sub(i + 1, i + 1):match("%s")) then
      local prev = text:sub(math.max(1, i - 4), i)
      if not (prev:match("e%.g%.$") or prev:match("i%.e%.$") or prev:match("etc%.$") or prev:match("%f[%a]vs%.$")) then
        out[#out + 1] = text:sub(start, i)
        start = i + 1
      end
    end
  end
  if text:sub(start):match("%S") then out[#out + 1] = text:sub(start) end
  for i, s in ipairs(out) do
    out[i] = s:gsub("\1", "."):match("^%s*(.-)%s*$")
  end
  return out
end

local function check_sentence(path, line, s, limit)
  local ws = words_of(s)
  if #ws > limit then report(path, line, string.format("%d words (at most %d): %s", #ws, limit, s:sub(1, 70))) end
  local plain = (" " .. s:gsub("`[^`]*`", " "):gsub("%b()", " "):lower() .. " ")
  if plain:find(";", 1, true) then report(path, line, "semicolon: write two sentences") end
  if
    plain:match("%a+n't")
    or plain:match("%a+'re%f[%A]")
    or plain:match("%a+'ve%f[%A]")
    or plain:match("%a+'ll%f[%A]")
    or plain:match("%f[%a]i'm%f[%A]")
    or plain:match("%a+'d%f[%A]")
  then
    report(path, line, "contraction: write the words in full")
  end
  for w in plain:gmatch("%a+") do
    if WORDS[w] then report(path, line, string.format("'%s': write %s", w, WORDS[w])) end
    if BRITISH[w] then report(path, line, string.format("'%s': American spelling is '%s'", w, BRITISH[w])) end
    if is_british_ise(w) then report(path, line, string.format("'%s': American spelling ends in -ize", w)) end
    if w:match("^%a%a%a+ing$") and not ING[w] then
      report(path, line, string.format("'%s': an -ing form (only in a technical name)", w))
    end
  end
  for _, abbr in ipairs({ "e.g.", "i.e.", "etc." }) do
    if plain:find(abbr, 1, true) then report(path, line, string.format("'%s': write %s", abbr, WORDS[abbr])) end
  end
  for _, p in ipairs(PHRASES) do
    if plain:find("%f[%a]" .. p[1]:gsub("%-", "%%-") .. "%f[%A]") then
      report(path, line, string.format("'%s': write %s", p[1], p[2]))
    end
  end
  if
    plain:match("%f[%a]ha[sv]e? been%f[%A]")
    or plain:match("%f[%a]ha[sv]e? %a+ed%f[%A]")
    or plain:match("%f[%a]had %a+ed%f[%A]")
  then
    report(path, line, "present perfect: use the simple present or past")
  end
  if
    plain:match("%f[%a][ai][rs]e? %a+ed by%f[%A]")
    or plain:match("%f[%a]w[ae][rs]e? %a+ed by%f[%A]")
    or plain:match("%f[%a]been %a+ed by%f[%A]")
  then
    report(path, line, "passive with 'by': write it in the active voice")
  end
  if plain:match("%f[%a][ai][rs]e? %a+ing%f[%A]") and not plain:match("[ai][rs]e? %a+ing [%a]") then
    -- "is playing" at the end of a clause
    report(path, line, "continuous form: use the simple present")
  end
end

for _, path in ipairs(files) do
  if path:match("reference/api%.md$") or path:match("tutorials/course/") then goto continue end
  local f = io.open(path, "rb")
  if not f then
    report(path, 0, "cannot read")
    goto continue
  end
  checked = checked + 1
  local text = f:read("*a")
  f:close()
  local limit, para, para_line, in_code, in_comment = 25, {}, 0, false, false
  local procedural_path = path:match("/tutorials/") or path:match("/how%-to/")
  local function flush()
    if #para > 0 then
      local body = table.concat(para, " ")
      local ss = sentences_of(body)
      if #ss > 6 then report(path, para_line, string.format("paragraph of %d sentences (at most 6)", #ss)) end
      for _, s in ipairs(ss) do
        check_sentence(path, para_line, s, limit)
      end
    end
    para = {}
  end
  local n = 0
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    n = n + 1
    if line:match("^%s*```") then
      flush()
      in_code = not in_code
    elseif in_code then
      -- code
    elseif in_comment or line:match("^%s*<!%-%-") then
      in_comment = not line:match("%-%->%s*$")
    elseif line:match("^#+%s") then
      flush()
      local h = line:gsub("^#+%s*", "")
      limit = (procedural_path or h:match("^How to") or h:match("^Try it")) and 20 or 25
      local first = h:match("^(%a+)")
      if first and first:match("ing$") and not ING[first:lower()] then
        report(path, n, string.format("heading starts with '%s': use a verb or a noun", first))
      end
    elseif line:match("^%s*|") then
      flush()
    elseif line:match("^%s*$") then
      flush()
    elseif line:match("^%s*[-*+] ") or line:match("^%s*%d+[.)] ") then
      flush()
      para_line = n
      para[1] = line:gsub("^%s*[-*+] ", ""):gsub("^%s*%d+[.)] ", "")
    else
      if #para == 0 then para_line = n end
      para[#para + 1] = line
    end
  end
  flush()
  ::continue::
end
print(string.format("ste-check: %d files, %d reports", checked, reports))
