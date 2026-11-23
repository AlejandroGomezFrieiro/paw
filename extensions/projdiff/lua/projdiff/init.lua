-- Versions of a project to compare: a project folder (which the kernel
-- reads), a project in one JSON file, a revision in git, a state of the
-- undo tree or a snapshot, as decoded project files; the three versions of
-- a git merge that stopped on conflicts; and what to do with the
-- difference (the view, quickfix).
local data = require("projdiff.data")
local diff = require("projdiff.diff")
local merge = require("projdiff.merge")

local M = { data = data, diff = diff, merge = merge }

-- Snapshots of a project that has no file yet, by name: as checkpoints are,
-- but kept in this session.
local memory = {}

local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local function read(path)
  local file, err = io.open(path, "rb")
  if not file then return nil, err end
  local content = file:read("*a")
  file:close()
  return content
end
M.read = read

--- A project file's text as a decoded file, or nil and why.
function M.decode(content, what)
  local doc, err = paw.api.json_decode(content or "")
  if type(doc) ~= "table" or type(doc.project) ~= "table" then
    return nil, (what or "the text") .. " is not a project file" .. (err and (": " .. tostring(err)) or "")
  end
  return doc
end

--- The files a decoded project names (a clip's audio, a take's, a frozen
--- part's: every `file`), made whole from the folder `dir` where a file
--- names them relative to itself; the project open holds them whole, and
--- the same file must not read as a change.
local function whole_paths(node, dir)
  for k, v in pairs(node) do
    if k == "file" and type(v) == "string" and v ~= "" and v:sub(1, 1) ~= "/" then
      node[k] = dir .. "/" .. v
    elseif type(v) == "table" then
      whole_paths(v, dir)
    end
  end
end

local function with_whole_paths(doc, path)
  if not doc then return doc end
  local dir = path:match("^(.*)/[^/]*$") or "."
  if dir:sub(1, 1) ~= "/" then dir = (os.getenv("PWD") or ".") .. (dir == "." and "" or "/" .. dir) end
  whole_paths(doc.project, dir)
  return doc
end

--- A project file on disk, decoded as it is written. With `whole` the
--- files it names relative to its folder are made whole, to compare with
--- the project open.
function M.file(path, whole)
  local content, err = read(path)
  if not content then return nil, tostring(err) end
  local doc, why = M.decode(content, path)
  if whole then with_whole_paths(doc, path) end
  return doc, why
end

--- Whether `path` names a project folder: the folder, or its `project.toml`.
local function is_folder(path)
  if path == "project.toml" or path:match("/project%.toml$") then return paw.api.fs_exists(path) end
  return paw.api.fs_exists(path .. "/project.toml")
end

--- The folder of a project folder named by itself or by its `project.toml`.
local function folder_of(path)
  if path == "project.toml" then return "." end
  path = path:gsub("(.)/+$", "%1")
  return path:match("^(.*)/project%.toml$") or path
end

--- A project folder as the kernel reads it, as a decoded file. `files`
--- (path in the folder -> bytes) stands for the own files of the folder,
--- for a version that is not on the disk.
function M.folder(path, files)
  local ok, project = pcall(paw.api.project_read, path, files)
  if not ok then return nil, (tostring(project):match("[^\n]*"):gsub("^runtime error: ", "")) end
  return { version = 1, project = project }
end

--- What a shell command writes, all of it; empty when it cannot start.
local function output(command)
  local p = io.popen(command)
  if not p then return "" end
  local out = p:read("*a")
  p:close()
  return out
end

--- The bytes of git objects, in the order of `objects`, read in one run
--- of git in the folder `dir`. Nil when git gives fewer.
local function git_objects(dir, objects)
  -- `cat-file --batch` gives each object in the order asked, as
  -- `<object> blob <size>\n`, the bytes and `\n`.
  local out =
    output("cd " .. quote(dir) .. " && printf '%s\\n' " .. table.concat(objects, " ") .. " | git cat-file --batch")
  local list, at = {}, 1
  for i = 1, #objects do
    local head_end = out:find("\n", at, true)
    local size = head_end and tonumber(out:sub(at, head_end - 1):match(" (%d+)$"))
    if not size then return nil end
    list[i] = out:sub(head_end + 1, head_end + size)
    at = head_end + size + 2
  end
  return list
end

--- The files that paw writes in the project folder `dir`, as the revision
--- `rev` of git holds them: path in the folder -> bytes. git reads them
--- from its store in two runs (the list, then the contents), so the
--- working tree does not change. Nil when the revision has no project there.
local function git_files(rev, dir)
  local listed = output("cd " .. quote(dir) .. " && git ls-tree -r -z " .. quote(rev) .. " -- . 2>/dev/null")
  local paths, objects = {}, {}
  -- Each entry is `<mode> <type> <object>\t<path>` and a zero byte; the
  -- paths are relative to `dir`.
  for kind, object, path in listed:gmatch("%d+ (%a+) (%x+)\t([^%z]+)%z") do
    if kind == "blob" and paw.api.project_file_managed(path) then
      paths[#paths + 1] = path
      objects[#objects + 1] = object
    end
  end
  if #paths == 0 then return nil end
  local bytes = git_objects(dir, objects)
  if not bytes then return nil end
  local files = {}
  for i, path in ipairs(paths) do
    files[path] = bytes[i]
  end
  if not files["project.toml"] then return nil end
  return files
end

-- The side of a merge that each stage of git's index holds. A file that
-- git merged has one entry, stage 0, which is the same on each side. A
-- file in conflict has an entry for each side that has it.
local SIDE_OF_STAGE = { ["1"] = "base", ["2"] = "ours", ["3"] = "theirs" }

--- The three versions of the project folder `path` (the folder, or its
--- `project.toml`) in a git merge that stopped on conflicts, as decoded
--- files: `{ base, ours, theirs }`, read from git's index. `base` is nil
--- when both sides added the project. Nil and why when no file of the
--- project is in conflict, or a side does not read as a project.
function M.git_merge(path)
  local dir = folder_of(path)
  local name = dir:match("[^/]*$")
  local listed = output("cd " .. quote(dir) .. " && git ls-files -s -z -- . 2>/dev/null")
  local entries, objects, conflicted = {}, {}, false
  -- Each entry is `<mode> <object> <stage>\t<path>` and a zero byte.
  for object, stage, file in listed:gmatch("%d+ (%x+) (%d)\t([^%z]+)%z") do
    if paw.api.project_file_managed(file) then
      entries[#entries + 1] = { path = file, side = SIDE_OF_STAGE[stage] }
      objects[#objects + 1] = object
      conflicted = conflicted or stage ~= "0"
    end
  end
  if not conflicted then return nil, "git has no merge conflict in " .. name end
  local bytes = git_objects(dir, objects)
  if not bytes then return nil, "git cannot read the files of " .. name end
  local files = { base = {}, ours = {}, theirs = {} }
  for i, e in ipairs(entries) do
    if e.side then
      files[e.side][e.path] = bytes[i]
    else
      files.base[e.path], files.ours[e.path], files.theirs[e.path] = bytes[i], bytes[i], bytes[i]
    end
  end
  local sides = {}
  for _, side in ipairs({ "base", "ours", "theirs" }) do
    if files[side]["project.toml"] then
      local doc, err = M.folder(dir, files[side])
      if not doc then return nil, side .. " of " .. name .. ": " .. err end
      sides[side] = doc
    elseif side ~= "base" then
      return nil, "git has no project.toml of " .. name .. " in " .. side
    end
  end
  return sides
end

--- What a revision of git holds of the project at `path`, decoded: the
--- project folder, or a project in one file.
function M.git(rev, path)
  if is_folder(path) then
    local dir = folder_of(path)
    local files = git_files(rev, dir)
    if not files then return nil, "git has no " .. dir:match("[^/]*$") .. " at " .. rev end
    return M.folder(dir, files)
  end
  local dir = path:match("^(.*)/[^/]*$") or "."
  local name = path:match("[^/]*$")
  local prefix = output("git -C " .. quote(dir) .. " rev-parse --show-prefix 2>/dev/null"):match("[^\n]*")
  local content = output("git -C " .. quote(dir) .. " show " .. quote(rev .. ":" .. prefix .. name) .. " 2>/dev/null")
  if content == "" then return nil, "git has no " .. name .. " at " .. rev end
  local doc, err = M.decode(content, name .. " at " .. rev)
  return with_whole_paths(doc, path), err
end

--- The project as it is in an undo state; by default as it is now, the
--- edits not yet made a step of undo with it.
function M.state(id)
  if id == nil then paw.api.undo_checkpoint() end
  local ok, project = pcall(paw.api.undo_project, id)
  if not ok then
    if id then
      return nil,
        string.format("there is no undo state #%d: the states are numbered from 1, as the undo tree shows them", id)
    end
    return nil, tostring(project):match("[^\n]*"):gsub("^runtime error: ", "")
  end
  return { version = 1, project = project }
end

--- The snapshots there are: `{ name, file?, time? }`, the oldest first.
function M.snapshots()
  local out = {}
  for _, c in ipairs(paw.api.checkpoint_list()) do
    out[#out + 1] = { name = c.name, file = c.file, time = c.time }
  end
  for _, name in ipairs(data.sorted_keys(memory)) do
    out[#out + 1] = { name = name }
  end
  return out
end

--- Keep the project as it is now under a name: beside the project when it
--- has a file, in this session when it has not.
function M.snapshot(name)
  name = name and name:match("^%s*(.-)%s*$") or ""
  if name == "" then name = os.date("snapshot %H:%M:%S") end
  if paw.api.checkpoint_dir() then
    local made = paw.api.checkpoint_write(name)
    return name, made.file
  end
  memory[name] = M.state(nil).project
  return name
end

local function snapshot_doc(name)
  local found
  for _, s in ipairs(M.snapshots()) do
    if s.name == name then found = s end
  end
  if not found then return nil, "no snapshot named " .. name .. " (`:Psnapshot " .. name .. "` makes one)" end
  if found.file then return M.file(found.file, true) end
  return { version = 1, project = memory[name] }
end

--- A version of the project named in the words `:Pdiff` takes: a project
--- folder or a project file, `#12` (a state of the undo tree), `snap:name`,
--- `now` (the project as it is), or a revision of git (`HEAD`, `main~3`) of
--- the folder or file of the project.
--- Returns the decoded file and a label for titles.
function M.version(spec)
  local project = paw.api.project_get()
  if spec == "now" then
    local doc, err = M.state(nil)
    return doc, "now", err
  end
  local n = spec:match("^#(%d+)$")
  if n then
    local doc, err = M.state(tonumber(n))
    return doc, "#" .. n, err
  end
  local name = spec:match("^snap:(.+)$")
  if name then
    local doc, err = snapshot_doc(name)
    return doc, name, err
  end
  if is_folder(spec) then
    local doc, err = M.folder(spec)
    return doc, folder_of(spec):match("[^/]*$"), err
  end
  local stat = paw.api.fs_stat(spec)
  if stat and stat.dir then return nil, spec, spec .. " is a folder with no project.toml, so it is not a project" end
  local file = io.open(spec, "rb")
  if file then
    file:close()
    local doc, err = M.file(spec, true)
    return doc, spec:match("[^/]*$"), err
  end
  if not project.path then
    return nil,
      spec,
      "the project has no file yet, so there is no revision of it: "
        .. spec
        .. " is not a project folder or file either"
  end
  local doc, err = M.git(spec, project.path)
  return doc, spec, err
end

--- What `:Pdiff` compares for the words given: nothing is the project's
--- file against the project now, one version is it against now, two are
--- from the first to the second. Returns `{ from, to, from_label, to_label }`.
function M.compare(args)
  local project = paw.api.project_get()
  local first, second = args[1], args[2]
  if not first then
    if not project.path then
      return nil, "the project has no file to compare with: `:Pdiff #3` or `:Pdiff snap:name`"
    end
    first = project.path
  end
  local a, label_a, err_a = M.version(first)
  if not a then return nil, err_a end
  local b, label_b, err_b = M.version(second or "now")
  if not b then return nil, err_b end
  if not second and first == project.path then label_a = "saved" end
  return { from = a, to = b, from_label = label_a, to_label = label_b }
end

--- The full path of the project folder that `path` names, to tell whether
--- two paths name one folder.
local function full_folder(path)
  local dir = folder_of(path)
  if dir:sub(1, 1) == "/" then return dir end
  return (os.getenv("PWD") or ".") .. (dir == "." and "" or "/" .. dir)
end

local function first_line(err) return (tostring(err):match("[^\n]*"):gsub("^runtime error: ", "")) end

--- Open the merged file `merged` as the project folder `dir`, not yet
--- saved: the folder on the disk can hold the marks of git's conflicts,
--- so paw cannot open it as it is.
local function open_merged(merged, dir)
  local ok, text = pcall(paw.api.project_file_text, merged)
  if not ok then return nil, "the merge is not a project that opens: " .. first_line(text) end
  local copy = os.tmpname()
  local file = assert(io.open(copy, "wb"))
  file:write(text)
  file:close()
  local opened, why = pcall(paw.api.project_recover, copy, { as_path = dir .. "/project.toml" })
  os.remove(copy)
  if not opened then return nil, first_line(why) end
  return true
end

--- Merge the three versions of the project folder `path` that git's index
--- holds after a merge stopped on conflicts (`git_merge`), and make the
--- result the open project. When the folder is the open project, the
--- result takes its place as one undo step. Otherwise paw opens the folder
--- with the result in it, not yet saved. Where both sides changed one
--- thing, the result holds ours, and its `meta.merge_conflicts` lists the
--- conflict (`merge.files`). Returns the number of conflicts, or nil and why.
function M.merge_git(path)
  local sides, err = M.git_merge(path)
  if not sides then return nil, err end
  local merged = merge.files(sides.base, sides.ours, sides.theirs)
  local open = paw.api.project_get("path")
  local dir = full_folder(path)
  if open and is_folder(open) and full_folder(open) == dir then
    local ok, why = pcall(paw.api.project_replace, merged.project)
    if not ok then return nil, "the merge is not a project that opens: " .. first_line(why) end
    -- The merge holds what git changed in the files: a save writes it over them.
    paw.api.project_keep_changes()
    paw.api.undo_label("merge")
    paw.api.undo_checkpoint()
  else
    if paw.api.project_get("modified") then
      return nil, "the open project has changes that are not saved: `:w` saves them"
    end
    local ok, why = open_merged(merged, dir)
    if not ok then return nil, why end
  end
  return #merge.conflicts(merged)
end

--- Send the changes to the quickfix list, one entry each. An entry of a
--- change inside a subproject goes inside it, as `Enter` in the view does.
function M.to_quickfix(tree, title)
  local entries = {}
  for i, e in ipairs(diff.entries(tree)) do
    entries[i] = { address = e.address, text = e.text, level = e.sign == "-" and "warning" or "info", nest = e.nest }
  end
  paw.qf.set(entries, { title = title })
  return #entries
end

return M
