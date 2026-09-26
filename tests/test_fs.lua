-- bhcore.fs: the verified storage primitives moved out of SaveSlots' store (T-124).
-- Exercises the API directly, with the store tests' fault injection (failed, torn and
-- crashed writes; removes that fail) against the harness's in-memory love.filesystem.
local H = ...

local function fs() return require('bhcore.fs') end
local P = 'x/dir/rec.jkr'
local function raw(p) return love._files[p] end
local function packed(t) return love.data.compress('string', 'deflate', STR_PACK(t), 1) end

-- love.filesystem.write returns false, err for every path `pred` accepts (at most `times`).
local function fail_writes(pred, times)
  local write, left = love.filesystem.write, times or math.huge
  love.filesystem.write = function(p, data)
    if left > 0 and pred(p) then left = left - 1; return false, 'disk full' end
    return write(p, data)
  end
  return function() love.filesystem.write = write end
end

-- Writes to every path `pred` accepts land only half their bytes and return false.
local function tear_writes(pred, times)
  local write, left = love.filesystem.write, times or math.huge
  love.filesystem.write = function(p, data)
    if left > 0 and pred(p) then
      left = left - 1
      write(p, data:sub(1, math.floor(#data / 2)))
      return false, 'disk full'
    end
    return write(p, data)
  end
  return function() love.filesystem.write = write end
end

-- Removes of every path `pred` accepts fail (the file stays), as on a locked file.
local function fail_removes(pred)
  local rm = love.filesystem.remove
  love.filesystem.remove = function(p) if pred(p) then return false end return rm(p) end
  return function() love.filesystem.remove = rm end
end

-- The process dies partway through writing a path `pred` accepts: half the bytes land.
local function crash_during(pred, fn)
  local w = love.filesystem.write
  love.filesystem.write = function(p, d)
    if pred(p) then w(p, d:sub(1, math.floor(#d / 2))); coroutine.yield('crashed') end
    return w(p, d)
  end
  local co = coroutine.create(fn)
  coroutine.resume(co)
  love.filesystem.write = w
  return coroutine.status(co)
end

H.test('write_table round-trips through read_table, in save.jkr format, and drops the .tmp', function()
  local f = fs()
  H.eq(f.write_table(P, {a = 1, b = {c = 'x'}}), true)
  local t = f.read_table(P)
  H.eq(t.a, 1); H.eq(t.b.c, 'x')
  H.eq(STR_UNPACK(get_compressed(P)).b.c, 'x', 'vanilla get_compressed reads it')
  H.eq(raw(P..'.tmp'), nil, 'no .tmp left behind')
  H.ok(love.filesystem.getInfo('x/dir'), 'parent directory created')
end)

H.test('read_table: missing, corrupt and non-table files are nil, err without raising', function()
  local f = fs()
  local t, err = f.read_table(P)
  H.eq(t, nil); H.eq(err, 'missing file')
  love.filesystem.write(P, 'Z)(*&')
  t, err = f.read_table(P)
  H.eq(t, nil); H.ok(err:match('^corrupt file'), err)
  love.filesystem.write(P, 'Zreturn 5')
  t, err = f.read_table(P)
  H.eq(t, nil); H.eq(err, 'corrupt file: not a table')
  love.filesystem.write(P, 'not compressed')
  t, err = f.read_table(P)
  H.eq(t, nil); H.eq(err, 'unreadable file')
end)

H.test('read_table falls back to a verified .tmp when the file is torn or gone', function()
  local f = fs()
  love.filesystem.write(P..'.tmp', packed({v = 2}))
  H.eq(f.read_table(P).v, 2, '.tmp only')
  love.filesystem.write(P, 'Ztorn((')
  H.eq(f.read_table(P).v, 2, 'torn main')
  H.eq(f.load_table(P), nil, 'load_table has no fallback')
end)

H.test('write_table refuses non-tables and bad paths without touching disk', function()
  local f = fs()
  local ok, err = f.write_table(P, nil)
  H.eq(ok, nil); H.eq(err, 'nothing to write')
  ok, err = f.write_table(nil, {})
  H.eq(ok, nil); H.eq(err, 'bad path')
  ok, err = f.read_table(nil)
  H.eq(ok, nil); H.eq(err, 'bad path')
  H.eq(next(love._files), nil, 'no file written')
end)

H.test('a failed staging write changes nothing: old content still reads, .tmp as before', function()
  local f = fs()
  f.write_table(P, {v = 1})
  local before = raw(P)
  local restore = fail_writes(function(p) return p == P..'.tmp' end)
  local ok, err = f.write_table(P, {v = 2})
  restore()
  H.eq(ok, nil); H.ok(err:match('^write failed'), err)
  H.eq(raw(P), before)
  H.eq(raw(P..'.tmp'), nil)
  H.eq(f.read_table(P).v, 1)
end)

H.test('a torn staging write puts the previous (even unreadable) .tmp bytes back', function()
  local f = fs()
  f.write_table(P, {v = 1})
  love.filesystem.write(P..'.tmp', 'junk')
  local restore = tear_writes(function(p) return p == P..'.tmp' end, 1)
  H.eq(f.write_table(P, {v = 2}), nil)
  restore()
  H.eq(raw(P..'.tmp'), 'junk')
  H.eq(f.read_table(P).v, 1)
end)

H.test('a failed final rewrite restores the previous file and reports failure', function()
  local f = fs()
  f.write_table(P, {v = 1})
  local before = raw(P)
  local restore = tear_writes(function(p) return p == P end, 1)
  local ok = f.write_table(P, {v = 2})
  restore()
  H.eq(ok, nil)
  H.eq(raw(P), before)
  H.eq(raw(P..'.tmp'), nil)
  H.eq(f.read_table(P).v, 1)
end)

H.test('a final rewrite that can be neither done nor undone commits through the .tmp', function()
  local f = fs()
  f.write_table(P, {v = 1})
  -- Every write of the main file tears (the rewrite and its rollback): the verified
  -- .tmp is what readers get, so the result must say the write committed.
  local restore = tear_writes(function(p) return p == P end)
  local ok = f.write_table(P, {v = 2})
  restore()
  H.eq(ok, true)
  H.eq(f.read_table(P).v, 2)
end)

H.test('a torn file whose .tmp is committed is healed before staging over that .tmp', function()
  local f = fs()
  love.filesystem.write(P..'.tmp', packed({v = 1}))
  love.filesystem.write(P, 'Ztorn((')
  -- The staging write of v=2 fails: without healing, v=1 would be lost with the .tmp.
  local restore = fail_writes(function(p) return p == P..'.tmp' end)
  H.eq(f.write_table(P, {v = 2}), nil)
  restore()
  H.eq(f.read_table(P).v, 1)
  H.eq(f.load_table(P).v, 1, 'main healed from the .tmp')
end)

H.test('a crash at any write leaves read_table returning the old or the new table', function()
  for _, target in ipairs({P..'.tmp', P}) do
    H.reset()
    local f = fs()
    f.write_table(P, {v = 1})
    H.eq(crash_during(function(p) return p == target end,
      function() return f.write_table(P, {v = 2}) end), 'suspended', 'crash simulated')
    package.loaded['bhcore.fs'] = nil
    f = fs()
    local t = f.read_table(P)
    H.ok(t and (t.v == 1 or t.v == 2), 'readable after a crash writing '..target)
    H.eq(f.write_table(P, {v = 3}), true, 'next write works')
    H.eq(f.read_table(P).v, 3)
  end
end)

H.test('remove and drop report whether the files are gone, including on locked files', function()
  local f = fs()
  H.eq(f.remove(P), true, 'absent counts as gone')
  f.write_table(P, {v = 1})
  love.filesystem.write(P..'.tmp', 'x')
  local restore = fail_removes(function(p) return p == P..'.tmp' end)
  H.eq(f.drop(P), false, 'locked .tmp stays')
  H.eq(raw(P), nil, 'main removed anyway')
  restore()
  H.eq(f.drop(P), true)
  H.eq(f.exists(P), false); H.eq(f.exists(P..'.tmp'), false)
end)

H.test('exists and ensure_dir', function()
  local f = fs()
  H.eq(f.exists(P), false)
  H.eq(f.exists(nil), false)
  H.eq(f.ensure_dir('x/other'), true)
  H.eq(f.exists('x/other'), true)
  f.write_table(P, {})
  H.eq(f.exists(P), true)
end)

H.test('put_raw and committed_bytes: exact bytes back, nil means removed', function()
  local f = fs()
  H.eq(f.committed_bytes(P), nil)
  f.write_table(P, {v = 1})
  local b = raw(P)
  H.eq(f.committed_bytes(P), b)
  H.eq(f.put_raw(P, 'Ztorn'), true)
  H.eq(f.committed_bytes(P), nil, 'unreadable')
  H.eq(f.put_raw(P, nil), true)
  H.eq(raw(P), nil)
  local restore = fail_writes(function() return true end)
  local ok, err = f.put_raw(P, b)
  restore()
  H.eq(ok, nil); H.ok(err:match('could not restore'), err)
end)

H.test('SaveSlots store uses the bhcore.fs primitives (one implementation)', function()
  local f = fs()
  local seen = {}
  local wt = f.write_table
  -- The store binds the primitives at require time, so wrap before requiring it.
  f.write_table = function(p, t) seen[#seen+1] = p; return wt(p, t) end
  package.loaded['saveslots.store'] = nil
  local s = require('saveslots.store')
  f.write_table = wt
  H.ok(s.save(H.fake_run(), 'a'), 'save')
  H.ok(#seen >= 2, 'slot and index went through bhcore.fs ('..#seen..')')
end)

H.test('ensure_dir rejects a non-string path', function()
  local fs = require('bhcore.fs')
  H.eq(fs.ensure_dir(nil), nil)
  H.eq(fs.ensure_dir(42), nil)
  H.ok(fs.ensure_dir('somedir'))
end)
