-- Adversarial store tests, written by the wave-2 T-002 verifier (independent of the
-- implementer) and adopted by the orchestrator as the T-002a/b gate. Orchestrator-owned:
-- implementers may not edit this file.
local H = ...
local now = 1700000000
local real_time = os.time
local function clock(t) now = t; os.time = function() return now end end
local reset = H.reset
H.reset = function() reset(); clock(1700000000) end
local function store() return require('saveslots.store') end
local function names(l) local o = {} for i, e in ipairs(l) do o[i] = e.name end return table.concat(o, ',') end
local function fail_writes(pred, times)
  local write, left = love.filesystem.write, times or math.huge
  love.filesystem.write = function(p, d) if left > 0 and pred(p) then left = left - 1; return false, 'disk full' end return write(p, d) end
  return function() love.filesystem.write = write end
end
local function tear_writes(pred, times)
  local write, left = love.filesystem.write, times or math.huge
  love.filesystem.write = function(p, d) if left > 0 and pred(p) then left = left - 1; write(p, d:sub(1, math.floor(#d/2))); return false, 'disk full' end return write(p, d) end
  return function() love.filesystem.write = write end
end
local function fail_removes(pred)
  local rm = love.filesystem.remove
  love.filesystem.remove = function(p) if pred(p) then return false end return rm(p) end
  return function() love.filesystem.remove = rm end
end
local function bs(k, run) love.filesystem.createDirectory('1'); compress_and_save('1/saveState'..k..'.jkr', run) end
local function count_bs(l) local c = 0 for _, e in ipairs(l) do if e.name:match('^Brainstorm') then c = c + 1 end end return c end

-- (1) duplicate import after index failure + retry, several failure modes
for _, mode in ipairs{'stage', 'final', 'tearfinal', 'stage+norm'} do
  H.test('R1 import retry no dup: '..mode, function()
    local s = store()
    s.save(H.fake_run{ante = 9, seed = 'OTHER000'}, 'mine')
    bs(1, H.fake_run{ante = 1}); bs(2, H.fake_run{ante = 2})
    local restore
    if mode == 'stage' then restore = fail_writes(function(p) return p:match('index%.jkr') end)
    elseif mode == 'final' then restore = fail_writes(function(p) return p == '1/saveslots/index.jkr' end)
    elseif mode == 'tearfinal' then restore = tear_writes(function(p) return p == '1/saveslots/index.jkr' end)
    else local r1 = fail_writes(function(p) return p:match('index%.jkr') end); local r2 = fail_removes(function(p) return not p:match('index') end); restore = function() r2(); r1() end end
    clock(1700000100)
    local r, err = s.import_brainstorm()
    restore()
    if mode == 'tearfinal' then H.eq(r, 2) else H.eq(r, nil); H.ok(err) end
    local r2 = s.import_brainstorm()
    H.eq(r2, mode == 'tearfinal' and 0 or 2)
    H.eq(count_bs(s.list()), 2, 'list')
    love.filesystem.write('1/saveslots/index.jkr', 'Zbroken'); love.filesystem.remove('1/saveslots/index.jkr.tmp')
    local l = s.list()
    H.eq(#l, 3, 'after rebuild: '..names(l))
    H.eq(s.import_brainstorm(), 0)
  end)
end

-- (2) overwrite + index failure: read agrees with list, old run kept
for _, mode in ipairs{'stage', 'final', 'tearfinal-once', 'tear-stage'} do
  H.test('R2 overwrite index failure: '..mode, function()
    local s = store()
    local a = s.save(H.fake_run{ante = 1}, 'a')
    clock(1700000100)
    local restore
    if mode == 'stage' then restore = fail_writes(function(p) return p:match('index%.jkr') end)
    elseif mode == 'final' then restore = fail_writes(function(p) return p == '1/saveslots/index.jkr' end)
    elseif mode == 'tearfinal-once' then restore = tear_writes(function(p) return p == '1/saveslots/index.jkr' end, 1)
    else restore = tear_writes(function(p) return p == '1/saveslots/index.jkr.tmp' end) end
    local r, err = s.save(H.fake_run{ante = 9}, 'x', a)
    restore()
    local l = s.list()
    local rd = s.read(a)
    if r then
      H.eq(rd.GAME.round_resets.ante, 9); H.eq(l[1].summary.ante, 9); H.eq(l[1].name, 'x')
    else
      H.ok(err); H.eq(rd.GAME.round_resets.ante, 1, 'read old'); H.eq(l[1].summary.ante, 1, 'list old'); H.eq(l[1].name, 'a')
    end
    H.eq(love.filesystem.getInfo('1/saveslots/'..a..'.jkr.tmp'), nil, 'no slot tmp')
  end)
end

-- (2b) overwrite when slot's only committed copy is its .tmp and index fails
H.test('R2b overwrite tmp-only slot + index fail', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'a')
  local p = '1/saveslots/'..a..'.jkr'
  love.filesystem.write(p..'.tmp', love.filesystem.read(p)); love.filesystem.write(p, 'Ztorn{')
  local restore = fail_writes(function(q) return q:match('index%.jkr') end)
  local r = s.save(H.fake_run{ante = 9}, 'x', a)
  restore()
  H.eq(r, nil)
  H.eq(s.read(a).GAME.round_resets.ante, 1)
  H.eq(s.list()[1].summary.ante, 1)
end)

-- (2c) overwrite of an unreadable slot + index fail: stays unreadable, list unchanged
H.test('R2c overwrite unreadable slot + index fail', function()
  local s = store()
  local a = s.save(H.fake_run{ante = 1}, 'a')
  local p = '1/saveslots/'..a..'.jkr'
  love.filesystem.write(p, 'Zjunk{')
  local restore = fail_writes(function(q) return q:match('index%.jkr') end)
  local r = s.save(H.fake_run{ante = 9}, 'x', a)
  restore()
  H.eq(r, nil)
  H.eq(s.read(a), nil)
  H.eq(love.filesystem.read(p), 'Zjunk{')
  H.eq(love.filesystem.getInfo(p..'.tmp'), nil)
end)

-- (3)
H.test('R3 read returns exactly one value from both paths, two on failure', function()
  local s = store()
  local id = s.save(H.fake_run{ante = 4}, 'a')
  H.eq(select('#', s.read(id)), 1)
  local p = '1/saveslots/'..id..'.jkr'
  love.filesystem.write(p..'.tmp', love.filesystem.read(p)); love.filesystem.write(p, 'Zx{')
  H.eq(select('#', s.read(id)), 1)
  love.filesystem.remove(p)
  H.eq(select('#', s.read(id)), 1)
  love.filesystem.write(p..'.tmp', 'Zx{')
  local r, e = s.read(id)
  H.eq(r, nil); H.ok(e)
end)

-- Brainstorm: two distinct saveStates of the same round/dollars
H.test('X1 two distinct Brainstorm saves in the same round both import', function()
  local s = store()
  bs(1, H.fake_run{state = G.STATES.SELECTING_HAND})
  bs(2, H.fake_run{state = G.STATES.SHOP, jokers = {}})
  local n = s.import_brainstorm()
  H.eq(n, 2, 'imported '..tostring(n)..': '..names(s.list()))
end)

H.test('X2 a user save at the same point blocks Brainstorm import', function()
  local s = store()
  s.save(H.fake_run(), 'mine')
  bs(1, H.fake_run{jokers = {}})
  local n = s.import_brainstorm()
  H.eq(n, 1, 'imported '..tostring(n)..': '..names(s.list()))
end)

-- new_id vs orphan file on disk
H.test('X3 new id never overwrites an unlisted slot file', function()
  local s = store()
  s.save(H.fake_run(), 'a')
  compress_and_save('1/saveslots/1700000100.jkr', H.fake_run{ante = 5})
  clock(1700000100)
  local id = s.save(H.fake_run(), 'b')
  H.ok(id ~= '1700000100')
end)

-- torn stage while the slot is torn and tmp committed: heal fails
H.test('X4 heal failure keeps the only committed copy', function()
  local s = store()
  s.save(H.fake_run(), 'a')
  love.filesystem.write('1/saveslots/index.jkr.tmp', love.filesystem.read('1/saveslots/index.jkr'))
  love.filesystem.write('1/saveslots/index.jkr', 'Zret{')
  local restore = tear_writes(function(p) return p:match('index%.jkr') end)
  clock(1700000100)
  local r = s.save(H.fake_run(), 'b')
  restore()
  H.eq(r, nil)
  H.eq(names(s.list()), 'a')
end)

-- save onto slot while index is served from .tmp (index.jkr torn), index final write fails
H.test('X5 delete then list: no resurrection when removal works', function()
  local s = store()
  local a = s.save(H.fake_run(), 'a')
  s.delete(a)
  love.filesystem.remove('1/saveslots/index.jkr')
  H.eq(#s.list(), 0)
end)

H.test('X6 rename with torn index + tmp committed, then rename works', function()
  local s = store()
  local a = s.save(H.fake_run(), 'a')
  love.filesystem.write('1/saveslots/index.jkr.tmp', love.filesystem.read('1/saveslots/index.jkr'))
  love.filesystem.write('1/saveslots/index.jkr', 'Zret{')
  H.eq(s.rename(a, 'b'), true)
  H.eq(names(s.list()), 'b')
  H.eq(love.filesystem.getInfo('1/saveslots/index.jkr.tmp'), nil)
end)

H.test('X7 no function raises when write throws', function()
  local s = store()
  local a = s.save(H.fake_run(), 'a')
  bs(1, H.fake_run{ante = 3})
  local w = love.filesystem.write
  love.filesystem.write = function() error('boom') end
  for _, f in ipairs{function() return s.save(H.fake_run(), 'x') end, function() return s.save(H.fake_run(), 'x', a) end,
    function() return s.rename(a, 'q') end, function() return s.delete(a) end, function() return s.import_brainstorm() end,
    function() return s.list() end, function() return s.read(a) end} do
    local ok, e = pcall(f); H.ok(ok, tostring(e))
  end
  love.filesystem.write = w
  H.eq(names(s.list()), 'a')
  H.eq(s.read(a).GAME.round_resets.ante, 2)
end)

H.reset = reset
os.time = real_time
local H = ...
H.test('X8 overwrite of a listed slot whose file is gone + index fail changes nothing', function()
  os.time = function() return 1700000000 end
  local s = require('saveslots.store')
  local a = s.save(H.fake_run{ante = 1}, 'a')
  local b = s.save(H.fake_run{ante = 2}, 'b')
  love.filesystem.remove('1/saveslots/'..a..'.jkr')
  local write = love.filesystem.write
  love.filesystem.write = function(p, d) if p:match('index%.jkr') then return false, 'disk full' end return write(p, d) end
  local r, err = s.save(H.fake_run{ante = 9}, 'x', a)
  love.filesystem.write = write
  if os.getenv("VERBOSE") == "1" then print('X8 save ->', r, err) end
  local rd = s.read(a)
  local l = s.list()
  local e; for _, x in ipairs(l) do if x.id == a then e = x end end
  if os.getenv("VERBOSE") == "1" then print('X8 read ante', rd and rd.GAME.round_resets.ante, 'list entry', e and e.name, e and e.summary.ante) end
  H.ok(r ~= nil or rd == nil or (e and e.summary.ante == rd.GAME.round_resets.ante), 'read disagrees with list after a failed save')
end)
