-- store.lua: slots on disk, index, summaries, Brainstorm import.
local H = ...

-- os.time() is frozen per test so ids and ordering are deterministic.
local real_time = os.time
local now = 1700000000
local function clock(t) now = t; os.time = function() return now end end

local function store() return require('saveslots.store') end
local function names(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.name end
  return table.concat(out, ',')
end
-- Every H.test starts from a fresh world (H.reset) with the clock frozen at `now`.
local reset = H.reset
H.reset = function() reset(); clock(1700000000) end

H.test('save creates a slot file under <profile>/saveslots and an index', function()
  local s = store()
  local id = s.save(H.fake_run(), 'first')
  H.eq(id, '1700000000')
  H.ok(love.filesystem.getInfo('1/saveslots/1700000000.jkr'), 'slot file')
  H.ok(love.filesystem.getInfo('1/saveslots/index.jkr'), 'index file')
  local idx = STR_UNPACK(get_compressed('1/saveslots/index.jkr'))
  H.eq(idx.version, 1)
  H.eq(idx.slots[id].name, 'first')
  H.eq(idx.slots[id].saved_at, 1700000000)
end)

H.test('paths follow the current profile, not the one at require time', function()
  local s = store()
  G.SETTINGS.profile = 3
  s.save(H.fake_run(), 'p3')
  H.ok(love.filesystem.getInfo('3/saveslots/index.jkr'))
  G.SETTINGS.profile = 1
  H.eq(#s.list(), 0, 'profile 1 sees none')
end)

H.test('list is empty with no saves, then newest first', function()
  local s = store()
  H.eq(#s.list(), 0)
  s.save(H.fake_run(), 'a')
  clock(1700000100); s.save(H.fake_run(), 'b')
  clock(1700000050); s.save(H.fake_run(), 'c')
  H.eq(names(s.list()), 'b,c,a')
end)

H.test('ids are unique within one second and ordered by creation', function()
  local s = store()
  local ids = {}
  for i = 1, 11 do ids[i] = s.save(H.fake_run(), 'n'..i) end
  H.eq(ids[2], '1700000000_2')
  H.eq(ids[11], '1700000000_11')
  local l = s.list()
  H.eq(#l, 11)
  H.eq(l[1].name, 'n11')
  H.eq(l[2].name, 'n10')
  H.eq(l[11].name, 'n1')
end)

H.test('read round-trips the run table', function()
  local s = store()
  local id = s.save(H.fake_run{ante = 6, seed = 'ZZZZ9999'}, 'x')
  local run = s.read(id)
  H.eq(run.GAME.round_resets.ante, 6)
  H.eq(run.GAME.pseudorandom.seed, 'ZZZZ9999')
  H.eq(run.cardAreas.jokers.cards[1].save_fields.center, 'j_joker')
end)

H.test('read of an unknown or malformed id returns nil, err', function()
  local s = store()
  local r, err = s.read('1234')
  H.eq(r, nil); H.ok(err)
  r, err = s.read('../save')
  H.eq(r, nil); H.eq(err, 'bad id')
end)

H.test('overwrite with an empty name keeps the name and refreshes run + saved_at', function()
  local s = store()
  local id = s.save(H.fake_run{ante = 1}, 'keep me')
  clock(1700000500)
  H.eq(s.save(H.fake_run{ante = 4}, '  ', id), id)
  local l = s.list()
  H.eq(#l, 1)
  H.eq(l[1].name, 'keep me')
  H.eq(l[1].saved_at, 1700000500)
  H.eq(l[1].summary.ante, 4)
  H.eq(s.read(id).GAME.round_resets.ante, 4)
  H.eq(s.save(H.fake_run(), nil, id), id)
  H.eq(s.list()[1].name, 'keep me')
end)

H.test('overwrite with a name changes it; unknown id is refused', function()
  local s = store()
  local id = s.save(H.fake_run(), 'old')
  s.save(H.fake_run(), 'new', id)
  H.eq(s.list()[1].name, 'new')
  local r, err = s.save(H.fake_run(), 'x', '999')
  H.eq(r, nil); H.eq(err, 'no such slot')
end)

H.test('rename trims and caps at 24 chars; empty and unknown are refused', function()
  local s = store()
  local id = s.save(H.fake_run(), 'a')
  H.eq(s.rename(id, '   renamed  '), true)
  H.eq(s.list()[1].name, 'renamed')
  s.rename(id, string.rep('x', 40))
  H.eq(s.list()[1].name, string.rep('x', 24))
  local r, err = s.rename(id, '   ')
  H.eq(r, nil); H.eq(err, 'empty name')
  r, err = s.rename('42', 'y')
  H.eq(r, nil); H.eq(err, 'no such slot')
end)

H.test('delete removes the file and the entry; unknown id is refused', function()
  local s = store()
  local a = s.save(H.fake_run(), 'a')
  local b = s.save(H.fake_run(), 'b')
  H.eq(s.delete(a), true)
  H.eq(love.filesystem.getInfo('1/saveslots/'..a..'.jkr'), nil)
  H.eq(names(s.list()), 'b')
  H.ok(s.read(b))
  local r, err = s.delete(a)
  H.eq(r, nil); H.eq(err, 'no such slot')
end)

H.test('list prunes index entries whose file is missing', function()
  local s = store()
  local a = s.save(H.fake_run(), 'a')
  s.save(H.fake_run(), 'b')
  love.filesystem.remove('1/saveslots/'..a..'.jkr')
  H.eq(names(s.list()), 'b')
  local idx = STR_UNPACK(get_compressed('1/saveslots/index.jkr'))
  H.eq(idx.slots[a], nil, 'pruned from the index on disk')
end)

H.test('a corrupt slot file makes read return nil, err without raising', function()
  local s = store()
  local id = s.save(H.fake_run(), 'a')
  love.filesystem.write('1/saveslots/'..id..'.jkr', 'Zreturn {{{ nope')
  local ok, r, err = pcall(s.read, id)
  H.ok(ok, 'read raised')
  H.eq(r, nil); H.ok(err)
  love.filesystem.write('1/saveslots/'..id..'.jkr', 'garbage-not-compressed')
  ok, r, err = pcall(s.read, id)
  H.ok(ok, 'read raised'); H.eq(r, nil); H.ok(err)
  love.filesystem.write('1/saveslots/'..id..'.jkr', 'Zreturn 42')
  r, err = s.read(id)
  H.eq(r, nil); H.ok(err)
end)

local function disk_index() return STR_UNPACK(get_compressed('1/saveslots/index.jkr')) end

-- love.filesystem.write returns false, err for every path `pred` accepts (at most `times`).
local function fail_writes(pred, times)
  local write, left = love.filesystem.write, times or math.huge
  love.filesystem.write = function(p, data)
    if left > 0 and pred(p) then left = left - 1; return false, 'disk full' end
    return write(p, data)
  end
  return function() love.filesystem.write = write end
end

H.test('a corrupt index is rebuilt from the slot files instead of starting over', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'a')
  clock(1700000100); local b = s.save(H.fake_run{ante = 5, deck = 'Blue Deck'}, 'b')
  love.filesystem.write('1/saveslots/1699999999.jkr', 'Zgarbage((')
  love.filesystem.write('1/saveslots/index.jkr', 'Z)(*&')
  local ok, l = pcall(s.list)
  H.ok(ok, 'list raised')
  H.eq(#l, 2, 'both slots recovered')
  H.eq(names(l), 'Blue Deck A5 R3,Red Deck A1 R3', 'default names, file-time order')
  H.eq(s.read(a).GAME.round_resets.ante, 1)
  H.eq(s.read(b).GAME.round_resets.ante, 5)
  H.eq(disk_index().slots[a].summary.ante, 1, 'rebuilt index written back')
  H.eq(disk_index().imported_brainstorm, true, 'no re-import once slots exist')
  H.ok(love.filesystem.getInfo('1/saveslots/1699999999.jkr'), 'unreadable slot file kept')
  clock(1700000200); H.ok(s.save(H.fake_run(), 'fresh'))
  H.eq(#s.list(), 3, 'next save keeps every older slot')
  H.eq(s.list()[1].name, 'fresh')
end)

H.test('a missing index is rebuilt from the slot files', function()
  local s = store()
  s.save(H.fake_run{ante = 1}, 'a')
  s.save(H.fake_run{ante = 2}, 'b')
  love.filesystem.remove('1/saveslots/index.jkr')
  H.eq(#s.list(), 2)
  H.ok(love.filesystem.getInfo('1/saveslots/index.jkr'), 'index rewritten')
end)

H.test('an index torn mid-rewrite falls back to its verified .tmp', function()
  local s = store()
  s.save(H.fake_run(), 'named')
  -- The crash window: .tmp written and verified, index.jkr truncated mid-write.
  love.filesystem.write('1/saveslots/index.jkr.tmp', love.filesystem.read('1/saveslots/index.jkr'))
  love.filesystem.write('1/saveslots/index.jkr', 'Zreturn {slo')
  H.eq(names(s.list()), 'named', 'names survive')
  clock(1700000100); H.ok(s.save(H.fake_run(), 'next'))
  H.eq(names(s.list()), 'next,named')
  H.eq(love.filesystem.getInfo('1/saveslots/index.jkr.tmp'), nil, 'tmp removed after commit')
end)

H.test('a failed slot write makes save return nil, err and changes nothing', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'a')
  clock(1700000100); s.save(H.fake_run{ante = 2}, 'b')
  local before = love.filesystem.read('1/saveslots/index.jkr')
  local restore = fail_writes(function(p) return p:match('/saveslots/%d[_%d]*%.jkr') end)
  clock(1700000200)
  local r, err = s.save(H.fake_run(), 'c')
  H.eq(r, nil); H.ok(err, 'err')
  r, err = s.save(H.fake_run{ante = 9}, 'a2', a)
  H.eq(r, nil); H.ok(err, 'overwrite err')
  restore()
  H.eq(love.filesystem.read('1/saveslots/index.jkr'), before, 'index untouched')
  H.eq(love.filesystem.getInfo('1/saveslots/1700000200.jkr'), nil, 'no half slot left')
  H.eq(names(s.list()), 'b,a')
  H.eq(s.read(a).GAME.round_resets.ante, 1, 'old run intact')
end)

H.test('a failed index write makes save return nil, err and keeps the old index', function()
  local s = store()
  s.save(H.fake_run(), 'a')
  local before = love.filesystem.read('1/saveslots/index.jkr')
  local restore = fail_writes(function(p) return p:match('index%.jkr') end)
  clock(1700000100)
  local r, err = s.save(H.fake_run(), 'b')
  H.eq(r, nil); H.ok(err, 'err')
  restore()
  H.eq(love.filesystem.read('1/saveslots/index.jkr'), before, 'index untouched')
  H.eq(love.filesystem.getInfo('1/saveslots/1700000100.jkr'), nil, 'uncommitted slot dropped')
  H.eq(names(s.list()), 'a')
  -- A failure on the final rewrite (after the .tmp verified) is reported too.
  restore = fail_writes(function(p) return p == '1/saveslots/index.jkr' end)
  r, err = s.save(H.fake_run(), 'c')
  H.eq(r, nil); H.ok(err, 'final-write err')
  restore()
end)

-- Writes to every path `pred` accepts (at most `times`) land only half their bytes and
-- return false: a torn write, as a crash or a full disk leaves it.
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

local function loads(path)
  local ok, t = pcall(function() return STR_UNPACK(get_compressed(path)) end)
  return ok and type(t) == 'table'
end

H.test('a torn final index write is recovered from the staged .tmp', function()
  local s = store()
  s.save(H.fake_run(), 'a')
  -- Every rewrite of index.jkr itself tears (the rollback too); its .tmp stages fine.
  local restore = tear_writes(function(p) return p == '1/saveslots/index.jkr' end)
  clock(1700000100)
  local b = s.save(H.fake_run{ante = 7}, 'b')
  restore()
  H.eq(b, '1700000100', 'committed through the verified .tmp')
  H.ok(not loads('1/saveslots/index.jkr'), 'index.jkr is torn')
  H.ok(loads('1/saveslots/index.jkr.tmp'), '.tmp holds the committed index')
  H.eq(names(s.list()), 'b,a', 'names survive, no rebuild')
  H.eq(s.list()[1].summary.ante, 7)
  -- While index.jkr is torn its .tmp is the only copy; a failed stage must not lose it.
  restore = tear_writes(function(p) return p == '1/saveslots/index.jkr.tmp' end, 1)
  H.eq(s.rename(b, 'lost?'), nil, 'rename reports the failed stage')
  restore()
  H.eq(names(s.list()), 'b,a', 'committed index survives a failed stage')
  clock(1700000200); H.ok(s.save(H.fake_run(), 'c'), 'next save heals index.jkr')
  H.eq(names(s.list()), 'c,b,a')
  H.ok(loads('1/saveslots/index.jkr'), 'index.jkr healed')
  H.eq(love.filesystem.getInfo('1/saveslots/index.jkr.tmp'), nil, 'tmp removed after commit')
end)

H.test('a half-written new slot file is removed when its write fails', function()
  local s = store()
  s.save(H.fake_run(), 'a')
  local before = love.filesystem.read('1/saveslots/index.jkr')
  clock(1700000100)
  local restore = tear_writes(function(p) return p == '1/saveslots/1700000100.jkr' end)
  local r, err = s.save(H.fake_run(), 'b')
  restore()
  H.eq(r, nil); H.ok(err, 'err')
  H.eq(love.filesystem.getInfo('1/saveslots/1700000100.jkr'), nil, 'no half file')
  H.eq(love.filesystem.getInfo('1/saveslots/1700000100.jkr.tmp'), nil, 'no staged file')
  restore = tear_writes(function(p) return p == '1/saveslots/1700000100.jkr.tmp' end)
  r, err = s.save(H.fake_run(), 'b')
  restore()
  H.eq(r, nil); H.ok(err, 'err on a torn stage')
  H.eq(love.filesystem.getInfo('1/saveslots/1700000100.jkr.tmp'), nil, 'no half .tmp')
  H.eq(love.filesystem.getInfo('1/saveslots/1700000100.jkr'), nil)
  H.eq(love.filesystem.read('1/saveslots/index.jkr'), before, 'index untouched')
  love.filesystem.remove('1/saveslots/index.jkr')
  H.eq(names(s.list()), 'Red Deck A2 R3', 'a rebuild finds only the real slot')
end)

H.test('an overwrite whose index write fails leaves the old run readable and listed', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'a')
  local slot = love.filesystem.read('1/saveslots/'..a..'.jkr')
  clock(1700000100)
  -- The index can't be staged at all.
  local restore = fail_writes(function(p) return p:match('index%.jkr') end)
  local r, err = s.save(H.fake_run{ante = 9}, 'x', a)
  restore()
  H.eq(r, nil); H.ok(err, 'err')
  H.eq(s.read(a).GAME.round_resets.ante, 1, 'old run back in the slot')
  H.eq(love.filesystem.read('1/saveslots/'..a..'.jkr'), slot, 'slot bytes restored')
  H.eq(s.list()[1].name, 'a'); H.eq(s.list()[1].summary.ante, 1); H.eq(s.list()[1].saved_at, 1700000000)
  -- The index's final rewrite fails after the .tmp staged.
  restore = fail_writes(function(p) return p == '1/saveslots/index.jkr' end)
  r, err = s.save(H.fake_run{ante = 9}, 'x', a)
  restore()
  H.eq(r, nil); H.ok(err, 'final-write err')
  H.eq(s.read(a).GAME.round_resets.ante, 1, 'old run back in the slot')
  H.eq(s.list()[1].summary.ante, 1)
  H.eq(love.filesystem.getInfo('1/saveslots/index.jkr.tmp'), nil, 'no stale index .tmp')
  -- The slot's own final rewrite tears.
  restore = tear_writes(function(p) return p == '1/saveslots/'..a..'.jkr' end, 1)
  r, err = s.save(H.fake_run{ante = 9}, 'x', a)
  restore()
  H.eq(r, nil); H.ok(err, 'slot-write err')
  H.eq(s.read(a).GAME.round_resets.ante, 1, 'torn overwrite rolled back')
  H.eq(names(s.list()), 'a')
end)

-- list() and read() tell the same story about slot `id`: a run that reads is listed with
-- that run's summary. An unreadable slot may be listed or not (read says why).
local function agrees(s, id)
  local run = s.read(id)
  if not run then return true end
  for _, e in ipairs(s.list()) do
    if e.id == id then
      return e.summary.ante == run.GAME.round_resets.ante and e.summary.dollars == run.GAME.dollars
    end
  end
  return false
end

-- Removes of every path `pred` accepts fail (the file stays), as on a locked file.
local function fail_removes(pred)
  local rm = love.filesystem.remove
  love.filesystem.remove = function(p) if pred(p) then return false end return rm(p) end
  return function() love.filesystem.remove = rm end
end

H.test('X8: overwriting a listed slot whose file is gone, then an index failure, changes nothing', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'a')
  clock(1700000100); local b = s.save(H.fake_run{ante = 2}, 'b')
  love.filesystem.remove('1/saveslots/'..a..'.jkr')
  local before = love.filesystem.read('1/saveslots/index.jkr')
  local restore = fail_writes(function(p) return p:match('index%.jkr') end)
  local r, err = s.save(H.fake_run{ante = 9}, 'x', a)
  restore()
  H.eq(r, nil); H.ok(err, 'err')
  H.eq(s.read(a), nil, 'still nothing to read')
  H.eq(love.filesystem.getInfo('1/saveslots/'..a..'.jkr'), nil, 'new run removed again')
  H.eq(love.filesystem.getInfo('1/saveslots/'..a..'.jkr.tmp'), nil, 'no staged copy')
  H.eq(love.filesystem.read('1/saveslots/index.jkr'), before, 'index untouched')
  H.eq(names(s.list()), 'b', 'the missing slot is pruned as before')
  H.ok(agrees(s, a) and agrees(s, b))
end)

H.test('an overwrite rollback restores a .tmp-only slot and an unreadable slot as they were', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 3}, 'tmp only')
  clock(1700000100); local b = s.save(H.fake_run{ante = 4}, 'broken')
  local pa, pb = '1/saveslots/'..a..'.jkr', '1/saveslots/'..b..'.jkr'
  love.filesystem.write(pa..'.tmp', love.filesystem.read(pa)); love.filesystem.remove(pa)
  love.filesystem.write(pb, 'Zreturn {GAM')
  local ta, rb = love.filesystem.read(pa..'.tmp'), love.filesystem.read(pb)
  local restore = fail_writes(function(p) return p:match('index%.jkr') end)
  clock(1700000200)
  local r1 = s.save(H.fake_run{ante = 9}, 'x', a)
  local r2 = s.save(H.fake_run{ante = 9}, 'y', b)
  restore()
  H.eq(r1, nil); H.eq(r2, nil)
  H.eq(s.read(a).GAME.round_resets.ante, 3, '.tmp-only slot reads the old run')
  local rd, rerr = s.read(b)
  H.eq(rd, nil, 'unreadable slot still unreadable'); H.ok(rerr)
  H.eq(love.filesystem.read(pb), rb, 'unreadable bytes put back')
  H.eq(love.filesystem.getInfo(pb..'.tmp'), nil, 'no staged copy of the new run')
  H.eq(love.filesystem.read(pa), ta, 'tmp-only slot: its run is back, as the slot file')
  H.eq(love.filesystem.getInfo(pa..'.tmp'), nil, 'tmp-only slot: no staged copy left')
  H.eq(names(s.list()), 'broken,tmp only')
  H.eq(s.list()[2].summary.ante, 3)
  H.ok(agrees(s, a) and agrees(s, b))
end)

H.test('rollback failure: index and restore writes both fail, list and read still agree', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'a')
  clock(1700000100); local b = s.save(H.fake_run{ante = 2}, 'b')
  -- The overwrite's own two slot writes (.tmp, then the file) land; every later one fails.
  local slot_writes = 0
  local restore = fail_writes(function(p)
    if p:match('index%.jkr') then return true end
    if p:find(a, 1, true) then slot_writes = slot_writes + 1; return slot_writes > 2 end
  end)
  clock(1700000200)
  local r, err = s.save(H.fake_run{ante = 9}, 'x', a)
  restore()
  H.eq(r, nil)
  H.ok(type(err) == 'string' and err:match('^rollback failed: '), 'reports the rollback: '..tostring(err))
  H.ok(slot_writes > 2, 'the restore was attempted')
  H.ok(agrees(s, a), 'read and list agree on the overwritten slot')
  H.ok(agrees(s, b)); H.eq(s.read(b).GAME.round_resets.ante, 2, 'other slot untouched')
  -- Nothing reads as the new run while the index still lists the old one.
  local rd = s.read(a)
  H.ok(rd == nil or rd.GAME.round_resets.ante == s.list()[2].summary.ante)
  love.filesystem.remove('1/saveslots/index.jkr')
  H.ok(agrees(s, a) and agrees(s, b), 'agree after a rebuild too')
end)

H.test('rollback failure with a one-off index failure lists the run that is on disk', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'a')
  local slot_writes = 0
  local restore = fail_writes(function(p)
    if p:match('index%.jkr') then return true end
    if p:find(a, 1, true) then slot_writes = slot_writes + 1; return slot_writes > 2 end
  end, 2)
  clock(1700000100)
  local r, err = s.save(H.fake_run{ante = 9}, 'x', a)
  restore()
  H.eq(r, nil)
  H.ok(type(err) == 'string' and err:match('^rollback failed: '), 'reports the rollback: '..tostring(err))
  H.eq(s.read(a).GAME.round_resets.ante, 9, 'the restore failed, the new run stays')
  H.eq(s.list()[1].summary.ante, 9, 'and the index now describes it')
  H.ok(agrees(s, a))
end)

H.test('a new slot that cannot be dropped after an index failure is never resurrected', function()
  local s = store()
  s.save(H.fake_run{ante = 1}, 'a')
  clock(1700000100)
  local restore_w = fail_writes(function(p) return p:match('index%.jkr') end)
  local restore_r = fail_removes(function(p) return p:match('/1700000100%.jkr') end)
  local r, err = s.save(H.fake_run{ante = 9}, 'b')
  restore_w(); restore_r()
  H.eq(r, nil)
  H.ok(type(err) == 'string' and err:match('^rollback failed: '), 'reports the failed drop: '..tostring(err))
  H.eq(s.read('1700000100'), nil, 'the unlisted run does not read')
  H.eq(names(s.list()), 'a')
  love.filesystem.remove('1/saveslots/index.jkr')
  H.eq(names(s.list()), 'Red Deck A1 R3', 'a rebuild does not bring it back')
  H.eq(love.filesystem.getInfo('1/saveslots/1700000100.jkr'), nil, 'its tombstone is swept')
  local fresh = s.save(H.fake_run{ante = 4}, 'c')
  H.ok(fresh, 'a new slot can be made')
  H.eq(s.read(fresh).GAME.round_resets.ante, 4, 'it holds the new run, never the discarded one')
  H.eq(#s.list(), 2)
end)

H.test('a deleted slot whose file cannot be removed does not come back on rebuild', function()
  local s = store()
  s.save(H.fake_run{ante = 1}, 'a')
  clock(1700000100); local b = s.save(H.fake_run{ante = 5}, 'b')
  local restore = fail_removes(function(p) return p:find(b, 1, true) end)
  H.eq(s.delete(b), true)
  restore()
  H.eq(s.read(b), nil)
  love.filesystem.remove('1/saveslots/index.jkr')
  H.eq(names(s.list()), 'Red Deck A1 R3')
end)

H.test('a slot write whose .tmp cannot be cleaned up reports what readers see', function()
  local s = store()
  clock(1700000100)
  -- The final rewrite fails and the verified .tmp can't be removed: it is the copy.
  local restore_w = fail_writes(function(p) return p == '1/saveslots/1700000100.jkr' end)
  local restore_r = fail_removes(function(p) return p == '1/saveslots/1700000100.jkr.tmp' end)
  local id = s.save(H.fake_run{ante = 6}, 'kept')
  restore_w(); restore_r()
  H.eq(id, '1700000100', 'committed through the .tmp, so the save succeeded')
  H.eq(s.read(id).GAME.round_resets.ante, 6)
  H.eq(names(s.list()), 'kept')
  H.ok(agrees(s, id))
end)

H.test('read falls back to the slot .tmp and returns only the run', function()
  local s = store()
  local id = s.save(H.fake_run{ante = 4}, 'a')
  local p = '1/saveslots/'..id..'.jkr'
  love.filesystem.write(p..'.tmp', love.filesystem.read(p))
  love.filesystem.write(p, 'Zreturn {GAM')
  H.eq(select('#', s.read(id)), 1, 'no stale error alongside the run')
  H.eq(s.read(id).GAME.round_resets.ante, 4)
end)

H.test('a slot whose only copy is its .tmp is kept, listed and never reused', function()
  local s = store()
  local id = s.save(H.fake_run{ante = 3}, 'only tmp')
  local p = '1/saveslots/'..id..'.jkr'
  love.filesystem.write(p..'.tmp', love.filesystem.read(p))
  love.filesystem.remove(p)
  H.eq(names(s.list()), 'only tmp', 'not pruned')
  H.eq(s.read(id).GAME.round_resets.ante, 3)
  local fresh = s.save(H.fake_run(), 'fresh')
  H.ok(fresh ~= id, 'new id skips the .tmp-only slot')
  H.eq(#s.list(), 2)
end)

H.test('rename and delete report a failed index write and change nothing', function()
  local s = store()
  local a = s.save(H.fake_run(), 'a')
  clock(1700000100); s.save(H.fake_run(), 'b')
  local before = love.filesystem.read('1/saveslots/index.jkr')
  for _, pred in ipairs{
    function(p) return p:match('index%.jkr') end,
    function(p) return p == '1/saveslots/index.jkr' end,
  } do
    local restore = fail_writes(pred)
    local r, err = s.rename(a, 'z')
    H.eq(r, nil); H.ok(err, 'rename err')
    r, err = s.delete(a)
    H.eq(r, nil); H.ok(err, 'delete err')
    restore()
    H.eq(love.filesystem.read('1/saveslots/index.jkr'), before, 'index untouched')
    H.eq(love.filesystem.getInfo('1/saveslots/index.jkr.tmp'), nil, 'no stale .tmp')
    H.ok(love.filesystem.getInfo('1/saveslots/'..a..'.jkr'), 'slot file kept')
    H.eq(names(s.list()), 'b,a')
    H.ok(s.read(a))
  end
end)

H.test('a rebuilt index takes saved_at from each slot file modtime', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'a')
  local b = s.save(H.fake_run{ante = 2}, 'b')
  local mt = {['1/saveslots/'..a..'.jkr'] = 1600000200, ['1/saveslots/'..b..'.jkr'] = 1600000100}
  local getInfo = love.filesystem.getInfo
  love.filesystem.getInfo = function(p)
    local i = getInfo(p)
    if i and mt[p] then i.modtime = mt[p] end
    return i
  end
  love.filesystem.write('1/saveslots/index.jkr', 'Zbroken')
  clock(1800000000)
  local l = s.list()
  H.eq(#l, 2)
  H.eq(l[1].id, a); H.eq(l[1].saved_at, 1600000200)
  H.eq(l[2].id, b); H.eq(l[2].saved_at, 1600000100)
end)

H.test('summarize returns every contract field, incl. state name and joker count', function()
  local s = store()
  local j = {save_fields = {center = 'j_joker'}}
  local sm = s.summarize(H.fake_run{deck = 'Blue Deck', stake = 3, ante = 5, round = 14,
    dollars = 27, seed = 'SEED0001', state = G.STATES.SHOP, jokers = {j, j, j}})
  H.eq(sm.deck, 'Blue Deck'); H.eq(sm.stake, 3); H.eq(sm.ante, 5); H.eq(sm.round, 14)
  H.eq(sm.dollars, 27); H.eq(sm.seed, 'SEED0001'); H.eq(sm.state, 'SHOP')
  H.eq(sm.hands, 4); H.eq(sm.discards, 3); H.eq(sm.version, '1.0.1o-FULL'); H.eq(sm.jokers, 3)
  H.eq(s.summarize(H.fake_run{state = G.STATES.BLIND_SELECT, jokers = {}}).state, 'BLIND_SELECT')
  H.eq(s.summarize(H.fake_run{jokers = {}}).jokers, 0)
  H.eq(s.save(H.fake_run(), 'x') and s.list()[1].summary.state, 'SHOP', 'stored in index')
end)

H.test('summarize tolerates a sparse run', function()
  local s = store()
  local sm = s.summarize({GAME = {}})
  H.eq(sm.jokers, 0); H.eq(sm.deck, nil); H.eq(sm.ante, nil)
  H.eq(next(s.summarize(nil)), nil)
end)

H.test('save refuses a nil or non-table run', function()
  local s = store()
  local r, err = s.save(nil, 'x')
  H.eq(r, nil); H.eq(err, 'no run')
  r, err = s.save('return {}', 'x')
  H.eq(r, nil); H.eq(err, 'no run')
  H.eq(love.filesystem.getInfo('1/saveslots/index.jkr'), nil, 'nothing written')
end)

H.test('default name is "<deck> A<ante> R<round>", and long names are capped', function()
  local s = store()
  s.save(H.fake_run{deck = 'Green Deck', ante = 3, round = 8})
  H.eq(s.list()[1].name, 'Green Deck A3 R8')
  clock(1700000001); s.save(H.fake_run{deck = 'Checkered Deck', ante = 12, round = 36}, '')
  H.eq(s.list()[1].name, 'Checkered Deck A12 R36')
  clock(1700000002); s.save(H.fake_run(), '  '..string.rep('n', 30)..'  ')
  H.eq(s.list()[1].name, string.rep('n', 24))
end)

-- Brainstorm writes <profile>/saveState<k>.jkr with compress_and_save.
local function brainstorm_slot(k, run)
  love.filesystem.createDirectory('1')
  compress_and_save('1/saveState'..k..'.jkr', run)
end

H.test('import_brainstorm copies saveState1-5 once, keeps originals, is idempotent', function()
  local s = store()
  brainstorm_slot(1, H.fake_run{ante = 1})
  brainstorm_slot(3, H.fake_run{ante = 3})
  love.filesystem.write('1/saveState4.jkr', 'Zbroken((')
  local before = {love.filesystem.read('1/saveState1.jkr'), love.filesystem.read('1/saveState3.jkr'),
    love.filesystem.read('1/saveState4.jkr')}
  -- Fake fs reports modtime=0 for these; give slot 3 a real one.
  local getInfo = love.filesystem.getInfo
  love.filesystem.getInfo = function(p)
    local i = getInfo(p)
    if i and p == '1/saveState3.jkr' then i.modtime = 1600000000 end
    return i
  end
  H.eq(s.import_brainstorm(), 2)
  local l = s.list()
  H.eq(names(l), 'Brainstorm slot 1,Brainstorm slot 3')
  H.eq(l[1].saved_at, 1700000000, 'modtime 0 falls back to os.time()')
  H.eq(l[2].saved_at, 1600000000, 'modtime used')
  H.eq(s.read(l[2].id).GAME.round_resets.ante, 3)
  H.eq(love.filesystem.read('1/saveState1.jkr'), before[1], 'original untouched')
  H.eq(love.filesystem.read('1/saveState3.jkr'), before[2], 'original untouched')
  H.eq(love.filesystem.read('1/saveState4.jkr'), before[3], 'original untouched')
  H.eq(STR_UNPACK(get_compressed('1/saveslots/index.jkr')).imported_brainstorm, true)
  H.eq(s.import_brainstorm(), 0, 'second call is a no-op')
  H.eq(#s.list(), 2)
end)

H.test('import_brainstorm with no Brainstorm files sets the flag and imports 0', function()
  local s = store()
  H.eq(s.import_brainstorm(), 0)
  brainstorm_slot(2, H.fake_run())
  H.eq(s.import_brainstorm(), 0, 'flag already set')
  H.eq(#s.list(), 0)
end)

H.test('import_brainstorm with a failed write leaves the flag unset; a retry finishes it', function()
  local s = store()
  brainstorm_slot(1, H.fake_run{ante = 1})
  brainstorm_slot(2, H.fake_run{ante = 2})
  local restore = fail_writes(function(p) return p:match('_2%.jkr') end, 1)
  H.eq(s.import_brainstorm(), 1)
  restore()
  H.eq(disk_index().imported_brainstorm, false, 'flag unset after a failure')
  H.eq(names(s.list()), 'Brainstorm slot 1')
  H.eq(s.import_brainstorm(), 1, 'retry imports only the missing slot')
  H.eq(disk_index().imported_brainstorm, true)
  local l = s.list()
  H.eq(#l, 2, 'no duplicate of slot 1')
  H.eq(names(l), 'Brainstorm slot 2,Brainstorm slot 1')
  H.eq(s.import_brainstorm(), 0)
end)

H.test('a failed index write drops the import copies; a retry makes no duplicate', function()
  local s = store()
  s.save(H.fake_run{ante = 9, seed = 'OTHER000'}, 'mine')
  brainstorm_slot(1, H.fake_run{ante = 1})
  local restore = fail_writes(function(p) return p:match('index%.jkr') end)
  clock(1700000100)
  local r, err = s.import_brainstorm()
  restore()
  H.eq(r, nil); H.ok(err, 'import reports the failed index write')
  H.eq(love.filesystem.getInfo('1/saveslots/1700000100.jkr'), nil, 'uncommitted copy dropped')
  H.eq(disk_index().imported_brainstorm, false)
  H.eq(s.import_brainstorm(), 1, 'retry imports it')
  love.filesystem.write('1/saveslots/index.jkr', 'Zbroken')
  H.eq(names(s.list()), 'Brainstorm slot 1,Red Deck A9 R3', 'one copy after a rebuild')
end)

H.test('an unlisted slot file holding a Brainstorm run is not taken for its import', function()
  local s = store()
  s.save(H.fake_run{ante = 9, seed = 'OTHER000'}, 'mine')
  brainstorm_slot(1, H.fake_run{ante = 1})
  -- Unlisted, same run as saveState1, but nothing says it was imported from it.
  compress_and_save('1/saveslots/1600000000.jkr', H.fake_run{ante = 1})
  local orphan = love.filesystem.read('1/saveslots/1600000000.jkr')
  clock(1700000100)
  H.eq(s.import_brainstorm(), 1)
  local by = {}
  for _, e in ipairs(s.list()) do by[e.name] = e.id end
  H.eq(by['Brainstorm slot 1'], '1700000100', 'a copy of its own')
  H.eq(s.read('1700000100').GAME.round_resets.ante, 1)
  H.eq(love.filesystem.read('1/saveslots/1600000000.jkr'), orphan, 'the unlisted file is left alone')
  H.eq(disk_index().slots['1700000100'].origin, 'brainstorm:1', 'origin recorded')
end)

H.test('no duplicate Brainstorm import after the index is rebuilt', function()
  local s = store()
  brainstorm_slot(1, H.fake_run{ante = 1})
  brainstorm_slot(3, H.fake_run{ante = 3})
  H.eq(s.import_brainstorm(), 2)
  love.filesystem.write('1/saveslots/index.jkr', 'Zbroken')
  local l = s.list()
  H.eq(#l, 2)
  local seen = {}
  for _, e in ipairs(l) do seen[e.name] = true end
  H.ok(seen['Brainstorm slot 1'] and seen['Brainstorm slot 3'], 'imports recognised by name')
  H.eq(s.import_brainstorm(), 0, 'flag survives the rebuild')
  H.eq(#s.list(), 2)
end)

H.test('Brainstorm import matches by slot identity, never by run contents', function()
  local s = store()
  s.save(H.fake_run(), 'mine')                                  -- same point as saveState1
  brainstorm_slot(1, H.fake_run())
  brainstorm_slot(2, H.fake_run())                              -- same run as saveState1
  brainstorm_slot(3, H.fake_run{state = G.STATES.SELECTING_HAND}) -- same round, other state
  clock(1700000100)
  H.eq(s.import_brainstorm(), 3, 'a user save or a twin saveState blocks nothing')
  local seen = {}
  for _, e in ipairs(s.list()) do seen[e.name] = (seen[e.name] or 0) + 1 end
  H.eq(seen['Brainstorm slot 1'], 1); H.eq(seen['Brainstorm slot 2'], 1)
  H.eq(seen['Brainstorm slot 3'], 1); H.eq(seen['mine'], 1)
end)

H.test('an imported slot keeps its origin through rename and overwrite, and is not re-imported', function()
  local s = store()
  brainstorm_slot(1, H.fake_run{ante = 1})
  brainstorm_slot(2, H.fake_run{ante = 2})
  H.eq(s.import_brainstorm(), 2)
  local id1
  for _, e in ipairs(s.list()) do if e.name == 'Brainstorm slot 1' then id1 = e.id end end
  H.eq(s.rename(id1, 'kept'), true)
  H.ok(s.save(H.fake_run{ante = 7}, nil, id1), 'overwrite')
  H.eq(disk_index().slots[id1].origin, 'brainstorm:1', 'origin survives rename + overwrite')
  H.eq(s.list()[1].origin, nil, 'origin is not part of list()')
  -- Force a second import pass: slot 1 is known by origin, slot 2 by name.
  local idx = disk_index(); idx.imported_brainstorm = false
  compress_and_save('1/saveslots/index.jkr', idx)
  H.eq(s.import_brainstorm(), 0)
  H.eq(#s.list(), 2)
end)

H.test('an index without origin fields (written before them) loads and imports by name', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'Brainstorm slot 1')
  local b = s.save(H.fake_run{ante = 5}, 'mine')
  compress_and_save('1/saveslots/index.jkr', {version = 1, imported_brainstorm = false, slots = {
    [a] = {name = 'Brainstorm slot 1', saved_at = 1, summary = {ante = 1}},
    [b] = {name = 'mine', saved_at = 2, summary = {ante = 5}},
  }})
  brainstorm_slot(1, H.fake_run{ante = 3})
  brainstorm_slot(2, H.fake_run{ante = 5})
  H.eq(names(s.list()), 'mine,Brainstorm slot 1', 'old index read as it is')
  clock(1700000100)
  H.eq(s.import_brainstorm(), 1, 'slot 1 counts as imported by name; slot 2 is copied')
  H.eq(#s.list(), 3)
end)

H.test('a Brainstorm entry whose file is gone does not count as imported', function()
  local s = store()
  brainstorm_slot(1, H.fake_run{ante = 1})
  local idx = {version = 1, imported_brainstorm = false, slots = {
    ['1600000000'] = {name = 'Brainstorm slot 1', saved_at = 1, summary = {}, origin = 'brainstorm:1'}}}
  compress_and_save('1/saveslots/index.jkr', idx)
  H.eq(s.import_brainstorm(), 1)
  H.eq(names(s.list()), 'Brainstorm slot 1')
  H.eq(s.read(s.list()[1].id).GAME.round_resets.ante, 1)
end)

H.test('rebuild gives exact saveState copies their identity back, each k once; the rest are user slots', function()
  local s = store()
  s.save(H.fake_run(), 'mine')                         -- same summary as saveState1/2, not a copy
  brainstorm_slot(1, H.fake_run{jokers = {}})
  brainstorm_slot(2, H.fake_run{jokers = {}})          -- identical to saveState1
  clock(1700000100)
  H.eq(s.import_brainstorm(), 2)
  love.filesystem.write('1/saveslots/index.jkr', 'Zbroken')
  local l = s.list()
  H.eq(#l, 3)
  local origins, users = {}, 0
  for id, e in pairs(disk_index().slots) do
    if e.origin then origins[e.origin] = e.name else users = users + 1 end
  end
  H.eq(origins['brainstorm:1'], 'Brainstorm slot 1')
  H.eq(origins['brainstorm:2'], 'Brainstorm slot 2')
  H.eq(users, 1, 'the user save matching only by summary stays the player\'s own')
  H.eq(disk_index().slots['1700000000'].origin, nil)
  H.eq(s.import_brainstorm(), 0, 'flag set by the rebuild')
end)

H.test('import: when the final index write fails the copies stay listed and a retry sets the flag', function()
  local s = store()
  brainstorm_slot(1, H.fake_run{ante = 1})
  brainstorm_slot(2, H.fake_run{ante = 2})
  local idx_writes = 0
  -- Staging the first index write works; everything after it fails.
  local restore = fail_writes(function(p)
    if p:match('index%.jkr') then idx_writes = idx_writes + 1; return idx_writes > 2 end
  end)
  clock(1700000100)
  H.eq(s.import_brainstorm(), 2, 'the copies are committed by the first index write')
  restore()
  H.eq(disk_index().imported_brainstorm, false, 'flag not written')
  H.eq(names(s.list()), 'Brainstorm slot 2,Brainstorm slot 1')
  H.eq(s.import_brainstorm(), 0, 'retry finds both copies')
  H.eq(disk_index().imported_brainstorm, true)
  H.eq(#s.list(), 2)
end)

H.test('import: a failed first index write changes nothing on disk', function()
  local s = store()
  s.save(H.fake_run{ante = 9, seed = 'OTHER000'}, 'mine')
  brainstorm_slot(1, H.fake_run{ante = 1})
  local before = love.filesystem.read('1/saveslots/index.jkr')
  local restore = fail_writes(function(p) return p:match('index%.jkr') end)
  local writes = 0
  local w = love.filesystem.write
  love.filesystem.write = function(p, d) if not p:match('index') then writes = writes + 1 end return w(p, d) end
  clock(1700000100)
  local r, err = s.import_brainstorm()
  love.filesystem.write = w; restore()
  H.eq(r, nil); H.ok(err)
  H.eq(writes, 0, 'no copy was written')
  H.eq(love.filesystem.read('1/saveslots/index.jkr'), before)
end)

H.test('delete: a file that can be neither removed nor tombstoned keeps its entry and fails', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'a')
  local slot = '1/saveslots/'..a..'.jkr'
  local restore_r = fail_removes(function(p) return p == slot end)
  local restore_w = fail_writes(function(p) return p == slot end)
  local ok, err = s.delete(a)
  restore_w(); restore_r()
  H.eq(ok, nil)
  H.ok(type(err) == 'string' and err:match('could not remove'), 'err: '..tostring(err))
  H.eq(names(s.list()), 'a', 'entry kept')
  H.eq(s.read(a).GAME.round_resets.ante, 1, 'run still reads')
  H.eq(s.delete(a), true, 'deletes once the filesystem allows it')
  H.eq(#s.list(), 0)
end)

H.test('delete: a tombstoned file is swept later, and new ids and rebuilds look past it', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'a')
  local slot = '1/saveslots/'..a..'.jkr'
  local restore_r = fail_removes(function(p) return p == slot end)
  H.eq(s.delete(a), true, 'tombstoned counts as deleted')
  H.ok(love.filesystem.getInfo(slot), 'tombstone on disk while removal fails')
  H.eq(s.read(a), nil)
  H.eq(#s.list(), 0, 'not listed')
  local b = s.save(H.fake_run{ante = 3}, 'b')       -- same second as a
  H.eq(b, a, 'new_id ignores the tombstone')
  H.eq(s.read(b).GAME.round_resets.ante, 3)
  H.eq(s.delete(b), true)
  love.filesystem.remove('1/saveslots/index.jkr')
  H.eq(#s.list(), 0, 'a rebuild skips it')
  H.ok(love.filesystem.getInfo(slot), 'still there while removal fails')
  restore_r()
  H.eq(#s.list(), 0)
  H.eq(love.filesystem.getInfo(slot), nil, 'swept once removal works')
end)

-- T-002c: a torn import copy doesn't count; a retry repairs it in place.
H.test('import: a listed copy whose files do not unpack is rewritten into the same id', function()
  local s = store()
  brainstorm_slot(1, H.fake_run{ante = 1})
  local idx = {version = 1, imported_brainstorm = false, slots = {
    ['1600000000'] = {name = 'Brainstorm slot 1', saved_at = 1, summary = {}, origin = 'brainstorm:1'}}}
  compress_and_save('1/saveslots/index.jkr', idx)
  love.filesystem.write('1/saveslots/1600000000.jkr.tmp', 'Ztorn((')   -- crash mid-staging
  H.eq(names(s.list()), 'Brainstorm slot 1', 'the torn copy is listed')
  H.eq(s.read('1600000000'), nil, 'and unreadable')
  local n, err = s.import_brainstorm()
  H.eq(n, 1); H.eq(err, nil)
  local l = s.list()
  H.eq(#l, 1, 'no second Brainstorm slot 1')
  H.eq(l[1].id, '1600000000', 'same id')
  H.eq(s.read('1600000000').GAME.round_resets.ante, 1)
  H.eq(l[1].summary.ante, 1, 'entry describes the copy')
  H.eq(love.filesystem.getInfo('1/saveslots/1600000000.jkr.tmp'), nil, 'torn .tmp gone')
  H.eq(disk_index().imported_brainstorm, true)
  H.eq(s.import_brainstorm(), 0)
end)

H.test('import: a readable copy under a renamed entry (origin kept) still counts', function()
  local s = store()
  brainstorm_slot(1, H.fake_run{ante = 1})
  H.eq(s.import_brainstorm(), 1)
  local id = s.list()[1].id
  H.eq(s.rename(id, 'mine now'), true)
  local idx = disk_index(); idx.imported_brainstorm = false
  compress_and_save('1/saveslots/index.jkr', idx)
  local n, err = s.import_brainstorm()
  H.eq(n, 0); H.eq(err, nil)
  H.eq(names(s.list()), 'mine now')
end)

H.test('import: a failed repair of a torn copy keeps its entry and bytes, and says partial', function()
  local s = store()
  brainstorm_slot(1, H.fake_run{ante = 1})
  local idx = {version = 1, imported_brainstorm = false, slots = {
    ['1600000000'] = {name = 'Brainstorm slot 1', saved_at = 7, summary = {ante = 'old'}, origin = 'brainstorm:1'}}}
  compress_and_save('1/saveslots/index.jkr', idx)
  love.filesystem.write('1/saveslots/1600000000.jkr', 'Ztorn((')
  local restore = fail_writes(function(p) return p:match('1600000000%.jkr') end)
  local n, err = s.import_brainstorm()
  restore()
  H.eq(n, 0)
  H.eq(err, 'partial: 1 of 1 failed')
  H.eq(love.filesystem.read('1/saveslots/1600000000.jkr'), 'Ztorn((', 'bytes untouched')
  H.eq(love.filesystem.getInfo('1/saveslots/1600000000.jkr.tmp'), nil, 'no .tmp left')
  local e = disk_index().slots['1600000000']
  H.eq(e.saved_at, 7, 'old entry back'); H.eq(e.summary.ante, 'old')
  H.eq(disk_index().imported_brainstorm, false)
  H.eq(s.import_brainstorm(), 1, 'retry repairs it')
  H.eq(#s.list(), 1)
  H.eq(s.read('1600000000').GAME.round_resets.ante, 1)
end)

H.test('import: the second value is set exactly when the flag is left unset', function()
  local s = store()
  brainstorm_slot(1, H.fake_run{ante = 1})
  brainstorm_slot(2, H.fake_run{ante = 2})
  local restore = fail_writes(function(p) return p:match('_2%.jkr') end, 1)
  local n, err = s.import_brainstorm()
  restore()
  H.eq(n, 1, 'count keeps its meaning')
  H.eq(err, 'partial: 1 of 2 failed')
  H.eq(disk_index().imported_brainstorm, false)
  n, err = s.import_brainstorm()
  H.eq(n, 1); H.eq(err, nil, 'no error once the flag is set')
  H.eq(disk_index().imported_brainstorm, true)
  n, err = s.import_brainstorm()
  H.eq(n, 0); H.eq(err, nil)
end)

H.test('import: a failed flag write returns the count and an error', function()
  local s = store()
  brainstorm_slot(1, H.fake_run{ante = 1})
  local idx_writes = 0
  local restore = fail_writes(function(p)
    if p:match('index%.jkr') then idx_writes = idx_writes + 1; return idx_writes > 2 end
  end)
  local n, err = s.import_brainstorm()
  restore()
  H.eq(n, 1)
  H.ok(type(err) == 'string' and err:match('disk full'), 'err: '..tostring(err))
  H.eq(disk_index().imported_brainstorm, false)
  n, err = s.import_brainstorm()
  H.eq(n, 0); H.eq(err, nil)
  H.eq(disk_index().imported_brainstorm, true)
end)

-- T-002c: write_data never changes a previous .tmp when it fails.
for _, how in ipairs{'fail', 'tear'} do
  H.test('a failed staging write ('..how..') puts the previous .tmp bytes back', function()
    local s = store()
    local a = s.save(H.fake_run{ante = 1}, 'a')
    local p = '1/saveslots/'..a..'.jkr'
    love.filesystem.write(p..'.tmp', 'Zjunk{')
    local w, n = love.filesystem.write, 0
    love.filesystem.write = function(q, d)
      if q == p..'.tmp' and n == 0 then n = 1; if how == 'tear' then w(q, d:sub(1, 5)) end return false, 'disk full' end
      return w(q, d)
    end
    local r, err = s.save(H.fake_run{ante = 9}, 'x', a)
    love.filesystem.write = w
    H.eq(r, nil); H.ok(err)
    H.eq(love.filesystem.read(p..'.tmp'), 'Zjunk{', '.tmp bytes as before')
    H.eq(s.read(a).GAME.round_resets.ante, 1)
    H.eq(names(s.list()), 'a')
  end)
end

H.test('a failed staging write with no previous .tmp leaves none', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'a')
  local p = '1/saveslots/'..a..'.jkr'
  local w = love.filesystem.write
  love.filesystem.write = function(q, d)
    if q == p..'.tmp' then w(q, d:sub(1, 5)); return false, 'disk full' end
    return w(q, d)
  end
  local r = s.save(H.fake_run{ante = 9}, 'x', a)
  love.filesystem.write = w
  H.eq(r, nil)
  H.eq(love.filesystem.getInfo(p..'.tmp'), nil, 'torn staging removed')
  H.eq(s.read(a).GAME.round_resets.ante, 1)
end)

H.test('a failed final rewrite puts the previous .tmp bytes back too', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'a')
  local p = '1/saveslots/'..a..'.jkr'
  love.filesystem.write(p..'.tmp', 'Zjunk{')
  local restore = fail_writes(function(q) return q == p end, 1)
  local r = s.save(H.fake_run{ante = 9}, 'x', a)
  restore()
  H.eq(r, nil)
  H.eq(love.filesystem.read(p..'.tmp'), 'Zjunk{', '.tmp bytes as before')
  H.eq(s.read(a).GAME.round_resets.ante, 1)
  H.eq(names(s.list()), 'a')
end)

H.reset = reset
os.time = real_time

H.test('a renamed copy matching two saveStates is not reused for both in one pass', function()
  local s = require('saveslots.store')
  love.filesystem.createDirectory('1')
  compress_and_save('1/saveState1.jkr', H.fake_run{ante = 1, seed = 'SEEDONE1'})
  compress_and_save('1/saveState2.jkr', H.fake_run{ante = 2, seed = 'SEEDTWO2'})
  H.eq(s.import_brainstorm(), 2)
  -- Rename the slot-1 copy to look like slot 2's, tear its file, and unset the flag.
  local one
  for _, e in ipairs(s.list()) do if e.summary.seed == 'SEEDONE1' then one = e.id end end
  H.ok(s.rename(one, 'Brainstorm slot 2'))
  local two
  for _, e in ipairs(s.list()) do if e.summary.seed == 'SEEDTWO2' then two = e.id end end
  H.ok(s.delete(two))
  love.filesystem.write('1/saveslots/'..one..'.jkr', 'Ztorn')
  love.filesystem.remove('1/saveslots/'..one..'.jkr.tmp')
  local idx = STR_UNPACK(get_compressed('1/saveslots/index.jkr'))
  idx.imported_brainstorm = false
  compress_and_save('1/saveslots/index.jkr', idx)
  s.import_brainstorm()
  local seeds = {}
  for _, e in ipairs(s.list()) do
    local run = s.read(e.id)
    if run then seeds[run.GAME.pseudorandom.seed] = (seeds[run.GAME.pseudorandom.seed] or 0) + 1 end
  end
  H.eq(seeds.SEEDONE1, 1, 'saveState1 readable exactly once')
  H.eq(seeds.SEEDTWO2, 1, 'saveState2 readable exactly once')
end)

H.test('a renamed copy of saveState1 never counts as saveState2 on a retry', function()
  local s = require('saveslots.store')
  love.filesystem.createDirectory('1')
  compress_and_save('1/saveState1.jkr', H.fake_run{ante = 1, seed = 'SEEDONE1'})
  compress_and_save('1/saveState2.jkr', H.fake_run{ante = 2, seed = 'SEEDTWO2'})
  H.eq(s.import_brainstorm(), 2)
  local one, two
  for _, e in ipairs(s.list()) do
    if e.summary.seed == 'SEEDONE1' then one = e.id else two = e.id end
  end
  H.ok(s.rename(one, 'Brainstorm slot 2'))
  H.ok(s.delete(two))
  local idx = STR_UNPACK(get_compressed('1/saveslots/index.jkr'))
  idx.imported_brainstorm = false
  compress_and_save('1/saveslots/index.jkr', idx)
  s.import_brainstorm()
  local seeds = {}
  for _, e in ipairs(s.list()) do
    local run = s.read(e.id)
    if run then seeds[run.GAME.pseudorandom.seed] = true end
  end
  H.ok(seeds.SEEDONE1, 'saveState1 still listed')
  H.ok(seeds.SEEDTWO2, 'saveState2 re-imported, not shadowed by the renamed slot-1 copy')
end)
