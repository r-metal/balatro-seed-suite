-- saveslots.sharecode: one pasteable string for a slot or a hunt. Plain data in,
-- plain data out; nothing here reads or writes the live run or the disk.
-- Decision: SWARM_TASKS.md kickoff answer D3 (the route is included).
--
-- Format
--   'BHS1:'..base64(flag..body)..'.'..checksum
--     flag     'z' = body is love.data.compress('string', 'zlib', STR_PACK(t));
--              'r' = body is STR_PACK(t) as is (no love, e.g. a CLI or a test).
--              Both decode anywhere love exists; a 'z' code without love fails.
--     checksum Adler-32 of everything before the '.', 8 lowercase hex digits.
--   The version is the digits between 'BHS' and ':'. Only 1 is known.
--
-- Schema (t)
--   {seed = 'ABCD1234' (1..8 of A-Z 0-9), deck = 'b_...', stake = 1..8,
--    route = plain table?, notes = string (<= 2000)?, filter = plain table?}
--   Any other top-level key is rejected. "Plain" = string/number/boolean
--   leaves under string/number keys, at most MAX_DEPTH deep. A filter is also
--   run through seedfinder.filter.validate when SeedFinder is loaded.
--
-- API
--   sharecode.encode(t)  -> code, or nil, err (t outside the schema).
--   sharecode.decode(s)  -> t, or nil, err. Never raises. Surrounding
--                           whitespace (a clipboard paste) is ignored.
--   sharecode.validate(t) -> true, or nil, err.
--   sharecode.base64(s), sharecode.unbase64(s), sharecode.checksum(s):
--     the encoders, for tests and anything that builds codes by hand.
--
-- Traps
--   * decode loads attacker-controlled Lua. Like seedfinder.filter.deserialize
--     it runs in setfenv({}), but an empty env alone still leaves the string
--     metatable reachable (("x"):rep(1e9)) and lets a chunk loop. So the text is
--     first held to STR_PACK's own grammar: outside string literals only
--     [%w_ %s [ ] { } = , . - +] and no '[[', '[=' or '--' (a long string or
--     comment would desync the scan from Lua's own), which rules out calls,
--     method calls and any statement after `return`. It must also start with
--     'return {'.
--   * Size limits apply before and after decompression (MAX_CODE, MAX_BODY), so
--     a small code cannot inflate into a large load.
local M = {}

M.VERSION = 1
M.PREFIX = 'BHS'..M.VERSION..':'
M.MAX_CODE = 8 * 1024
M.MAX_BODY = 64 * 1024
M.MAX_NOTES = 2000
M.MAX_DEPTH = 8

local KEYS = {seed = true, deck = true, stake = true, route = true, notes = true, filter = true}

------------------------------------------------------------------------------
-- Encoders

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64_INDEX = {}
for i = 1, 64 do B64_INDEX[B64:byte(i)] = i - 1 end

function M.base64(s)
  local out, n = {}, #s
  for i = 1, n, 3 do
    local a, b, c = s:byte(i, i + 2)
    local v = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = math.floor(v / 262144) % 64
    local c2 = math.floor(v / 4096) % 64
    local c3 = math.floor(v / 64) % 64
    local c4 = v % 64
    out[#out+1] = B64:sub(c1 + 1, c1 + 1)..B64:sub(c2 + 1, c2 + 1)
      ..(b and B64:sub(c3 + 1, c3 + 1) or '=')..(c and B64:sub(c4 + 1, c4 + 1) or '=')
  end
  return table.concat(out)
end

-- nil on anything that isn't canonical padded base64.
function M.unbase64(s)
  if #s % 4 ~= 0 then return nil end
  local out = {}
  for i = 1, #s, 4 do
    local last = i + 3 == #s
    local q, pad = {}, 0
    for j = 0, 3 do
      local ch = s:byte(i + j)
      if ch == 61 and last and j >= 2 then -- '='
        pad = pad + 1; q[j+1] = 0
      elseif pad > 0 then return nil
      else
        q[j+1] = B64_INDEX[ch]
        if not q[j+1] then return nil end
      end
    end
    local v = q[1] * 262144 + q[2] * 4096 + q[3] * 64 + q[4]
    local a, b, c = math.floor(v / 65536), math.floor(v / 256) % 256, v % 256
    if pad == 0 then out[#out+1] = string.char(a, b, c)
    elseif pad == 1 then out[#out+1] = string.char(a, b)
    else out[#out+1] = string.char(a) end
  end
  return table.concat(out)
end

-- Adler-32 as 8 hex digits: catches a mistyped or truncated paste, nothing more.
function M.checksum(s)
  local a, b = 1, 0
  for i = 1, #s do
    a = (a + s:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return string.format('%04x%04x', b, a)
end

------------------------------------------------------------------------------
-- Schema

local function plain(v, depth, where)
  if depth > M.MAX_DEPTH then return nil, where..' nests too deep' end
  for k, x in pairs(v) do
    local tk, tx = type(k), type(x)
    if tk ~= 'string' and tk ~= 'number' then return nil, where..' has a '..tk..' key' end
    if tx == 'table' then
      local ok, err = plain(x, depth + 1, where..'.'..tostring(k))
      if not ok then return nil, err end
    elseif tx ~= 'string' and tx ~= 'number' and tx ~= 'boolean' then
      return nil, where..'.'..tostring(k)..' is a '..tx
    elseif tx == 'number' and (x ~= x or x == math.huge or x == -math.huge) then
      return nil, where..'.'..tostring(k)..' is not finite'
    end
  end
  return true
end

function M.validate(t)
  if type(t) ~= 'table' then return nil, 'sharecode: not a table' end
  for k in pairs(t) do
    if not KEYS[k] then return nil, 'sharecode: unknown field '..tostring(k) end
  end
  if type(t.seed) ~= 'string' or #t.seed < 1 or #t.seed > 8 or not t.seed:match('^[%u%d]+$') then
    return nil, 'sharecode: bad seed'
  end
  if type(t.deck) ~= 'string' or not t.deck:match('^b_[%w_]+$') then return nil, 'sharecode: bad deck' end
  if type(t.stake) ~= 'number' or t.stake % 1 ~= 0 or t.stake < 1 or t.stake > 8 then
    return nil, 'sharecode: bad stake'
  end
  if t.notes ~= nil and (type(t.notes) ~= 'string' or #t.notes > M.MAX_NOTES) then
    return nil, 'sharecode: bad notes'
  end
  for _, k in ipairs({'route', 'filter'}) do
    if t[k] ~= nil then
      if type(t[k]) ~= 'table' then return nil, 'sharecode: '..k..' is not a table' end
      local ok, err = plain(t[k], 1, k)
      if not ok then return nil, 'sharecode: '..err end
    end
  end
  local filter = package.loaded['seedfinder.filter']
  if t.filter ~= nil and type(filter) == 'table' and filter.validate then
    local ok, err = filter.validate(t.filter)
    if not ok then return nil, 'sharecode: filter: '..tostring(err) end
  end
  return true
end

------------------------------------------------------------------------------
-- Encode / decode

local function zlib()
  return type(love) == 'table' and type(love.data) == 'table' and love.data.compress and love.data
end

function M.encode(t)
  local ok, err = M.validate(t)
  if not ok then return nil, err end
  local body, flag = STR_PACK(t), 'r'
  local data = zlib()
  if data then
    local okc, z = pcall(data.compress, 'string', 'zlib', body)
    if okc and type(z) == 'string' then body, flag = z, 'z' end
  end
  local head = M.PREFIX..M.base64(flag..body)
  local code = head..'.'..M.checksum(head)
  if #code > M.MAX_CODE then return nil, 'sharecode: too long ('..#code..' bytes)' end
  return code
end

-- STR_PACK's grammar, loosely: 'return {' then, outside "..." literals (with
-- \ escapes, as %q writes them), only word chars, space and [ ] { } = , . - +
local SAFE = '[%w_%s%[%]{}=,%.%-+]'
local function packed_text(s)
  if not s:match('^return%s*{') then return nil, 'sharecode: not a packed table' end
  local i, n = 1, #s
  while i <= n do
    local ch = s:sub(i, i)
    if ch == '"' then
      i = i + 1
      while true do
        if i > n then return nil, 'sharecode: unterminated string' end
        local d = s:sub(i, i)
        if d == '\\' then i = i + 2
        elseif d == '"' then break
        else i = i + 1 end
      end
    elseif not ch:match(SAFE) then
      return nil, 'sharecode: unexpected '..string.format('%q', ch)..' in packed table'
    else
      -- Long brackets and comments would let Lua read a '"' this scanner
      -- took for a string start (or the reverse). STR_PACK never writes them.
      local two = s:sub(i, i + 1)
      if two == '[[' or two == '[=' or two == '--' then
        return nil, 'sharecode: unexpected '..two..' in packed table'
      end
    end
    i = i + 1
  end
  return true
end

function M.decode(s)
  if type(s) ~= 'string' then return nil, 'sharecode: not a string' end
  if #s > M.MAX_CODE then return nil, 'sharecode: too long ('..#s..' bytes)' end
  s = s:match('^%s*(.-)%s*$')
  local ver = s:match('^BHS(%d+):')
  if not ver then return nil, 'sharecode: not a share code' end
  if tonumber(ver) ~= M.VERSION then return nil, 'sharecode: unknown version BHS'..ver end
  local head, sum = s:match('^(.-)%.(%x+)$')
  if not head then return nil, 'sharecode: missing checksum' end
  if sum:lower() ~= M.checksum(head) then return nil, 'sharecode: bad checksum' end
  local raw = M.unbase64(head:sub(#M.PREFIX + 1))
  if not raw or #raw < 1 then return nil, 'sharecode: bad base64' end
  local flag, body = raw:sub(1, 1), raw:sub(2)
  if flag == 'z' then
    local data = zlib()
    if not (data and data.decompress) then return nil, 'sharecode: compressed code needs love.data' end
    local ok, out = pcall(data.decompress, 'string', 'zlib', body)
    if not ok or type(out) ~= 'string' then return nil, 'sharecode: bad compressed body' end
    body = out
  elseif flag ~= 'r' then
    return nil, 'sharecode: unknown body flag'
  end
  if #body > M.MAX_BODY then return nil, 'sharecode: body too large' end
  local safe, serr = packed_text(body)
  if not safe then return nil, serr end
  local chunk, err = loadstring(body, '=sharecode')
  if not chunk then return nil, 'sharecode: '..tostring(err) end
  setfenv(chunk, {})
  local ok, t = pcall(chunk)
  if not ok then return nil, 'sharecode: '..tostring(t) end
  local valid, verr = M.validate(t)
  if not valid then return nil, verr end
  return t
end

return M
