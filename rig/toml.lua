-- Minimal reader for the lovely.toml subset our mods use. Returns
-- {priority=, modules = {{name=, source=}...}, copies = {{target=, position=, sources={...}}...}}.
-- Any other patch kind (pattern, regex, ...) is an error: the rig cannot emulate
-- it, and silently skipping one would make a smoke PASS meaningless.
local toml = {}

local function unquote(v, where)
  local s = v:match('^"(.*)"$') or v:match("^'(.*)'$")
  if not s then error(where..': expected a string, got '..v) end
  return s
end

local function value(v, where)
  if v:sub(1, 1) == '[' then
    local out = {}
    for item in v:sub(2, -2):gmatch('[^,]+') do
      item = item:match('^%s*(.-)%s*$')
      if item ~= '' then out[#out+1] = unquote(item, where) end
    end
    return out
  end
  if v == 'true' or v == 'false' then return v == 'true' end
  if v:match('^%-?%d+$') then return tonumber(v) end
  return unquote(v, where)
end

function toml.parse(text, chunkname)
  chunkname = chunkname or 'lovely.toml'
  local patches, cur, section, manifest = {}, nil, nil, {}
  local n = 0
  for line in (text..'\n'):gmatch('(.-)\r?\n') do
    n = n + 1
    local where = chunkname..':'..n
    line = line:gsub('%s+#.*$', ''):gsub('^#.*$', ''):match('^%s*(.-)%s*$')
    if line == '' then
      -- blank or comment
    elseif line == '[[patches]]' then
      cur = {}; patches[#patches+1] = cur; section = 'patches'
    elseif line:match('^%[patches%.([%w_]+)%]$') then
      if not cur then error(where..': patch table outside [[patches]]') end
      local kind = line:match('^%[patches%.([%w_]+)%]$')
      cur.kind = kind; section = 'patch'
    elseif line:match('^%[') then
      cur = nil; section = line
    else
      local k, v = line:match('^([%w_]+)%s*=%s*(.+)$')
      if not k then error(where..': cannot parse: '..line) end
      if section == 'patch' then cur[k] = value(v, where)
      elseif section == '[manifest]' then manifest[k] = value(v, where) end
      -- other tables are irrelevant to the rig
    end
  end

  local out = {priority = tonumber(manifest.priority) or 0, modules = {}, copies = {}}
  for i, p in ipairs(patches) do
    if p.kind == 'module' then
      if not (p.name and p.source) then error(chunkname..': module patch #'..i..' needs name and source') end
      out.modules[#out.modules+1] = {name = p.name, source = p.source}
    elseif p.kind == 'copy' then
      if not (p.target and p.sources) then error(chunkname..': copy patch #'..i..' needs target and sources') end
      local pos = p.position or 'append'
      if pos ~= 'append' and pos ~= 'prepend' then error(chunkname..': copy patch #'..i..': unsupported position '..pos) end
      out.copies[#out.copies+1] = {target = p.target, position = pos,
        sources = type(p.sources) == 'table' and p.sources or {p.sources}}
    else
      error(chunkname..': patch #'..i..' of kind '..tostring(p.kind)..' is not supported by the smoke rig')
    end
  end
  return out
end

return toml
