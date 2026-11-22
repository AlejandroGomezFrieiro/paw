-- What the core does once for many extensions: files without a shell, and
-- the codecs and helpers they share. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api

test(
  "files without a shell: exists, a copy of a folder, removing what paw made, the free space, a program on the PATH",
  function()
    local dir = T.scratch .. "/shared-fs"
    api.fs_mkdir(dir .. "/a/b")
    local f = assert(io.open(dir .. "/a/b/x.txt", "w"))
    f:write("x")
    f:close()
    eq(api.fs_exists(dir .. "/a/b/x.txt"), true, "a file is there")
    eq(api.fs_exists(dir .. "/nothing"), false, "nothing is not")
    api.fs_copy(dir .. "/a", dir .. "/c")
    eq(api.fs_stat(dir .. "/c/b/x.txt").size, 1, "a folder is copied with what it holds")
    eq(pcall(api.fs_copy, dir .. "/a", dir .. "/c"), false, "a copy never overwrites")
    api.fs_remove(dir)
    eq(api.fs_exists(dir), false, "a folder paw made is removed with what it holds")
    local space = api.fs_space(T.scratch)
    eq(space.total >= space.free and space.free > 0, true, "the space of the disk")
    eq(api.which("sh") ~= nil and api.which("sh"):match("/sh$") ~= nil, true, "sh is on the PATH")
    eq(api.which("no-such-program-paw"), nil, "a program that is not there")
  end
)

test(
  "a button of a painted view takes a press of the pointer; what is not on a place goes to the view's pointer",
  function()
    local pressed, other = 0, 0
    local view = { hits = paw.canvas.hit_list() }
    function view:paint(g)
      self.hits:clear()
      paw.canvas.button(g:sub(10, 10, 200, 50), self.hits, 5, 5, "Press", function() pressed = pressed + 1 end)
    end
    function view:pointer() other = other + 1 end
    paw.ui.view("shared-hits", view)
    paw.canvas.paint("shared-hits", 300, 100)
    paw.canvas.pointer("shared-hits", { kind = "down", x = 20, y = 20, button = "left" })
    paw.canvas.pointer("shared-hits", { kind = "up", x = 20, y = 20, button = "left" })
    eq(pressed, 1, "the button, at its place in the sub-painter")
    paw.canvas.pointer("shared-hits", { kind = "down", x = 250, y = 80, button = "left" })
    eq(other, 1, "elsewhere, the view's pointer")
    eq(view.hits.list[1].label, "Press", "the button keeps its label")
    paw.ui.views["shared-hits"] = nil
  end
)

test("paw.util.copy copies tables all the way down", function()
  local a = { 1, { x = { 2 } }, name = "n" }
  local b = paw.util.copy(a)
  b[2].x[1] = 3
  eq(a[2].x[1], 2, "the copy shares no table with the original")
  eq(b.name, "n", "and has its values")
end)

test(
  "a table marked as a JSON array is written as one when it is empty",
  function() eq(api.json_encode({ list = api.json_array(), map = {} }), '{"list":[],"map":{}}', "[] and {}") end
)

test("paw.api.device_find finds a kind of device by its kind, its format, or its name in any case", function()
  local synth = api.device_find({ kind = "synth" })
  eq(synth and synth.kind, "synth", "by kind")
  eq(api.device_find({ name = synth.name:upper() }).kind, "synth", "by name in any case")
  eq(api.device_find({ kind = "synth", format = "clap" }), nil, "not in another format")
  eq(api.device_find({ name = "no such device" }), nil, "nothing")
  local builtin = api.device_find_all({ format = "builtin" })
  eq(#builtin > 1 and builtin[1].format, "builtin", "device_find_all: a list")
end)

test(
  "paw.xml reads a DOCTYPE, comments, CDATA, references and quotes with > in them, and writes back what did not change byte for byte",
  function()
    local xml = paw.xml
    local root = assert(
      xml.decode(
        '\239\187\191<?xml version="1.0"?><!DOCTYPE x [ <!ENTITY a "b"> ]><!-- c --><a k="1 > 0" j=\'q\'>'
          .. "<b>x &amp; y &#233; &#x263A; &a;</b><![CDATA[<raw>]]><c/></a>"
      )
    )
    eq(root.name, "a", "the root")
    eq(root.attr.k .. "|" .. root.attr.j, "1 > 0|q", "attributes, a > inside quotes")
    eq(xml.text(root, "b"), "x & y é ☺ &a;", "references as UTF-8, an entity of the DTD as written")
    eq(root.text, "<raw>", "CDATA as text")
    eq(#root:all(), 2, "two child elements")
    eq(select(2, xml.decode("<a><b></a>")) ~= nil, true, "a tag closed by the wrong one is an error")
    local made = xml.element("Track", { name = 'A "b" & c', gain = 0.5, on = true }, { "name" })
    made:add("Note", { key = 60 })
    eq(
      xml.encode(made),
      '<Track name="A &quot;b&quot; &amp; c" gain="0.5" on="true"><Note key="60"/></Track>',
      "written: `order` first, then by name"
    )
    local text = '<?xml version="1.0"?>\n<r  a = "1"  >\n  <x v="&#65;"/>\n  <y v="2" ></y>\n</r>\n'
    local tree = assert(xml.decode(text, { spans = true }))
    eq(xml.encode(tree, { source = text }), text, "unchanged: the same bytes")
    tree.children[2].attr.v = "3"
    table.remove(tree.children, 1)
    eq(
      xml.encode(tree, { source = text }),
      '<?xml version="1.0"?>\n<r  a = "1"  >\n  <y v="3"></y>\n</r>\n',
      "a changed element written anew, a removed one gone with the space before it"
    )
  end
)

test("paw.toml reads TOML with its keys in order, says the line of an error, and writes a table back", function()
  local t = assert(paw.toml.decode([==[
# a comment
b = "x\ty"   # after a value
a = 1
[t.u]
c = [1, 2,
  3, ]
d = { f = true, e = 'lit' }
[[arr]]
x = 2.5
]==]))
  eq(
    paw.json.encode(t),
    '{"a":1,"arr":[{"x":2.5}],"b":"x\\ty","t":{"u":{"c":[1,2,3],"d":{"e":"lit","f":true}}}}',
    "the table"
  )
  eq(table.concat(getmetatable(t).__keys, ","), "b,a,t,arr", "keys in the order written")
  eq(select(2, paw.toml.decode("a = 1\na = 2")):match("^line 2: ") ~= nil, true, "the line of an error")
  eq(paw.toml.encode({ m2 = "11.0", out = "ks=D1" }, true), '{ m2 = "11.0", out = "ks=D1" }', "a value on one line")
  eq(paw.json.encode(paw.toml.decode(paw.toml.encode(t))), paw.json.encode(t), "a document written reads back the same")
end)
