-- store.lua 0.2 meta: set_meta, the kind filter, meta through save/overwrite, and
-- 0.1.0 indexes (no meta) loading unchanged. Contract: docs/contracts-0.2.md.
local H = ...

local now = 1700000000
local function clock(t) now = t; os.time = function() return now end end
local reset = H.reset
H.reset = function() reset(); clock(1700000000) end

local function store() return require('saveslots.store') end
local function disk_index() return STR_UNPACK(get_compressed('1/saveslots/index.jkr')) end
local function by_id(list, id)
  for _, e in ipairs(list) do if e.id == id then return e end end
end
local function ids(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.id end
  return table.concat(out, ',')
end

-- love.filesystem.write returns false, err for every path `pred` accepts.
local function fail_writes(pred)
  local write = love.filesystem.write
  love.filesystem.write = function(p, data)
    if pred(p) then return false, 'disk full' end
    return write(p, data)
  end
  return function() love.filesystem.write = write end
end
local function is_index(p) return p:find('index%.jkr') ~= nil end

H.test('a slot saved without meta lists as kind save and keeps the 0.1.0 entry shape', function()
  local s = store()
  local id = s.save(H.fake_run(), 'plain')
  local e = s.list()[1]
  H.eq(e.meta.kind, 'save')
  H.eq(e.meta.target, nil)
  H.eq(disk_index().slots[id].meta, nil, 'no meta field written for a plain save')
end)

H.test('save with meta stores it; list hands out a copy', function()
  local s = store()
  local id = s.save(H.fake_run(), 'hunt', nil, {kind = 'hunt', target = 'Win A8',
    origin = {kind = 'finder', filter_name = 'Charm soul', filter = {clauses = {{kind = 'tag', ante = 1}}}}})
  local e = s.list()[1]
  H.eq(e.meta.kind, 'hunt'); H.eq(e.meta.target, 'Win A8')
  H.eq(e.meta.origin.filter_name, 'Charm soul')
  H.eq(e.meta.origin.filter.clauses[1].kind, 'tag')
  e.meta.target = 'mutated'; e.meta.origin.filter_name = 'mutated'
  local again = s.list()[1]
  H.eq(again.meta.target, 'Win A8', 'list must return a copy')
  H.eq(again.meta.origin.filter_name, 'Charm soul')
  H.eq(disk_index().slots[id].meta.kind, 'hunt')
end)

H.test('the caller\'s meta table is copied, not kept', function()
  local s = store()
  local meta = {kind = 'practice', practice = {jokers = {'j_blueprint'}}}
  local id = s.save(H.fake_run(), 'p', nil, meta)
  meta.practice.jokers[1] = 'j_mime'
  meta.kind = 'hunt'
  H.eq(s.list()[1].meta.kind, 'practice')
  H.eq(s.list()[1].meta.practice.jokers[1], 'j_blueprint')
  H.ok(s.set_meta(id, meta))
  meta.practice.jokers[1] = 'j_baron'
  H.eq(s.list()[1].meta.practice.jokers[1], 'j_mime')
end)

H.test('set_meta merges fields and keeps name, summary and every other field', function()
  local s = store()
  local id = s.save(H.fake_run{ante = 5}, 'keep me', nil, {kind = 'checkpoint', run_id = 'SEED:1', notes = 'n'})
  H.eq(s.set_meta(id, {target = 'Beat Cerulean'}), true)
  local e = s.list()[1]
  H.eq(e.name, 'keep me'); H.eq(e.summary.ante, 5)
  H.eq(e.meta.kind, 'checkpoint'); H.eq(e.meta.run_id, 'SEED:1')
  H.eq(e.meta.notes, 'n'); H.eq(e.meta.target, 'Beat Cerulean')
  H.ok(s.set_meta(id, {notes = 'second'}))
  e = s.list()[1]
  H.eq(e.meta.target, 'Beat Cerulean'); H.eq(e.meta.notes, 'second')
end)

H.test('target and notes are trimmed and capped; an empty string clears one', function()
  local s = store()
  local id = s.save(H.fake_run(), 'x')
  H.ok(s.set_meta(id, {target = '  '..string.rep('t', 40)..'  ', notes = string.rep('n', 99)}))
  local e = s.list()[1]
  H.eq(#e.meta.target, 24); H.eq(#e.meta.notes, 60)
  H.eq(s.TARGET_MAX, 24); H.eq(s.NOTES_MAX, 60)
  H.ok(s.set_meta(id, {target = '   '}))
  e = s.list()[1]
  H.eq(e.meta.target, nil, 'blank target clears it')
  H.eq(#e.meta.notes, 60, 'notes untouched')
  H.ok(s.set_meta(id, {notes = ''}))
  H.eq(s.list()[1].meta.notes, nil)
end)

H.test('set_meta refuses bad input and unknown slots, changing nothing', function()
  local s = store()
  local id = s.save(H.fake_run(), 'x', nil, {kind = 'save', target = 'T'})
  local before = get_compressed('1/saveslots/index.jkr')
  local cases = {
    {id, {kind = 'bogus'}}, {id, {target = 5}}, {id, {notes = {}}}, {id, {run_id = 7}},
    {id, {origin = 'finder'}}, {id, 'meta'}, {id, nil}, {id, {x = function() end}},
    {id, {x = 0/0}}, {id, {x = math.huge}}, {id, {[true] = 1}},
    {'1234', {target = 'a'}}, {'../x', {target = 'a'}}, {nil, {target = 'a'}},
  }
  for i, c in ipairs(cases) do
    local ok, err = s.set_meta(c[1], c[2])
    H.eq(ok, nil, 'case '..i..' accepted')
    H.ok(type(err) == 'string', 'case '..i..' has no err')
  end
  H.eq(get_compressed('1/saveslots/index.jkr'), before, 'index changed by a refused set_meta')
  H.eq(s.list()[1].meta.target, 'T')
end)

H.test('save with a bad meta writes nothing', function()
  local s = store()
  local id, err = s.save(H.fake_run(), 'x', nil, {kind = 'nope'})
  H.eq(id, nil); H.ok(err)
  H.eq(#s.list(), 0)
  H.eq(love.filesystem.getInfo('1/saveslots/1700000000.jkr'), nil, 'no slot file for a refused save')
end)

H.test('set_meta reports a failed index write and changes nothing', function()
  local s = store()
  local id = s.save(H.fake_run(), 'x', nil, {target = 'old'})
  local restore = fail_writes(is_index)
  local ok, err = s.set_meta(id, {target = 'new'})
  restore()
  H.eq(ok, nil); H.ok(err)
  H.eq(s.list()[1].meta.target, 'old')
end)

H.test('list filters by kind; a slot without meta is a save', function()
  local s = store()
  local a = s.save(H.fake_run(), 'a')
  clock(now + 1); local b = s.save(H.fake_run(), 'b', nil, {kind = 'checkpoint'})
  clock(now + 1); local c = s.save(H.fake_run(), 'c', nil, {kind = 'practice'})
  clock(now + 1); local d = s.save(H.fake_run(), 'd', nil, {kind = 'hunt'})
  clock(now + 1); local e = s.save(H.fake_run(), 'e', nil, {kind = 'save', notes = 'x'})
  H.eq(ids(s.list()), table.concat({e, d, c, b, a}, ','))
  H.eq(ids(s.list({kind = 'save'})), e..','..a)
  H.eq(ids(s.list({kind = 'checkpoint'})), b)
  H.eq(ids(s.list({kind = 'practice'})), c)
  H.eq(ids(s.list({kind = 'hunt'})), d)
  H.eq(#s.list({kind = 'other'}), 0)
  H.eq(#s.list({}), 5, 'a filter without kind lists everything')
  H.eq(#s.list('junk'), 5, 'a non-table filter is ignored')
end)

H.test('an overwrite keeps the slot meta and merges a new one in', function()
  local s = store()
  local id = s.save(H.fake_run{ante = 1}, 'x', nil, {kind = 'hunt', target = 'T', notes = 'N'})
  clock(now + 5)
  H.eq(s.save(H.fake_run{ante = 3}, nil, id), id)
  local e = s.list()[1]
  H.eq(e.summary.ante, 3)
  H.eq(e.meta.kind, 'hunt'); H.eq(e.meta.target, 'T'); H.eq(e.meta.notes, 'N')
  H.eq(s.save(H.fake_run{ante = 4}, nil, id, {notes = 'N2'}), id)
  e = s.list()[1]
  H.eq(e.meta.kind, 'hunt'); H.eq(e.meta.target, 'T'); H.eq(e.meta.notes, 'N2')
end)

H.test('rename keeps meta; delete drops the entry with it', function()
  local s = store()
  local id = s.save(H.fake_run(), 'x', nil, {kind = 'practice', target = 'T'})
  H.ok(s.rename(id, 'y'))
  local e = s.list()[1]
  H.eq(e.name, 'y'); H.eq(e.meta.kind, 'practice'); H.eq(e.meta.target, 'T')
  H.ok(s.delete(id))
  H.eq(#s.list({kind = 'practice'}), 0)
  H.eq(disk_index().slots[id], nil)
end)

H.test('meta survives a fresh module (it lives in the index on disk)', function()
  local s = store()
  local id = s.save(H.fake_run(), 'x', nil, {kind = 'checkpoint', run_id = 'R:1', target = 'T'})
  package.loaded['saveslots.store'] = nil
  local s2 = require('saveslots.store')
  local e = s2.list()[1]
  H.eq(e.id, id); H.eq(e.meta.kind, 'checkpoint'); H.eq(e.meta.run_id, 'R:1'); H.eq(e.meta.target, 'T')
end)

-- A 0.1.0 index, written by hand: version 1, entries {name, saved_at, summary, origin?}.
local function write_v010(s)
  local run = H.fake_run{ante = 4, seed = 'OLDSEED1'}
  love.filesystem.createDirectory('1/saveslots')
  H.ok(love.filesystem.write('1/saveslots/1600000000.jkr', love.data.compress('string', 'deflate', STR_PACK(run))))
  H.ok(love.filesystem.write('1/saveslots/1600000001.jkr', love.data.compress('string', 'deflate', STR_PACK(run))))
  local idx = {version = 1, imported_brainstorm = true, slots = {
    ['1600000000'] = {name = 'Old one', saved_at = 1600000000, summary = s.summarize(run)},
    ['1600000001'] = {name = 'Brainstorm slot 1', saved_at = 1600000001, summary = s.summarize(run),
      origin = 'brainstorm:1'},
  }}
  H.ok(love.filesystem.write('1/saveslots/index.jkr', love.data.compress('string', 'deflate', STR_PACK(idx))))
end

H.test('a 0.1.0 index (no meta) lists, filters and reads unchanged', function()
  local s = store()
  write_v010(s)
  local l = s.list()
  H.eq(#l, 2)
  H.eq(l[2].name, 'Old one'); H.eq(l[2].meta.kind, 'save')
  H.eq(#s.list({kind = 'save'}), 2)
  H.eq(#s.list({kind = 'checkpoint'}), 0)
  H.eq(s.read('1600000000').GAME.pseudorandom.seed, 'OLDSEED1')
  local idx = disk_index()
  H.eq(idx.slots['1600000000'].meta, nil, 'listing must not rewrite old entries')
  H.eq(idx.version, 1)
end)

H.test('set_meta on a 0.1.0 entry adds meta and keeps origin and version', function()
  local s = store()
  write_v010(s)
  H.ok(s.set_meta('1600000001', {notes = 'from brainstorm'}))
  local idx = disk_index()
  H.eq(idx.version, 1)
  local e = idx.slots['1600000001']
  H.eq(e.origin, 'brainstorm:1'); H.eq(e.name, 'Brainstorm slot 1'); H.eq(e.meta.notes, 'from brainstorm')
  H.eq(by_id(s.list(), '1600000001').meta.kind, 'save')
  H.eq(s.import_brainstorm(), 0, 'the import flag is untouched')
end)

H.test('junk meta on disk lists as a save instead of raising', function()
  local s = store()
  local id = s.save(H.fake_run(), 'x')
  local idx = disk_index()
  idx.slots[id].meta = 'junk'
  H.ok(love.filesystem.write('1/saveslots/index.jkr', love.data.compress('string', 'deflate', STR_PACK(idx))))
  H.eq(s.list()[1].meta.kind, 'save')
  H.ok(s.set_meta(id, {target = 'T'}))
  H.eq(s.list()[1].meta.target, 'T')
end)

H.test('favorite: set, filter, clear drops the field, and a non-boolean is refused', function()
  local s = store()
  local a = s.save(H.fake_run(), 'a')
  clock(now + 1)
  local b = s.save(H.fake_run(), 'b', nil, {kind = 'checkpoint'})
  H.ok(s.set_meta(a, {favorite = true}))
  H.eq(by_id(s.list(), a).meta.favorite, true)
  H.eq(ids(s.list({favorite = true})), a)
  H.eq(#s.list({kind = 'checkpoint', favorite = true}), 0, 'filters combine')
  H.ok(s.set_meta(b, {favorite = true}))
  H.eq(ids(s.list({kind = 'checkpoint', favorite = true})), b)
  H.ok(s.set_meta(a, {favorite = false}))
  H.eq(disk_index().slots[a].meta, nil, 'unfavoriting a plain save restores the 0.1.0 shape')
  H.eq(ids(s.list({favorite = true})), b)
  local ok, err = s.set_meta(b, {favorite = 'yes'})
  H.eq(ok, nil); H.eq(err, 'favorite must be a boolean')
  H.ok(s.save(H.fake_run(), nil, b))
  H.eq(by_id(s.list(), b).meta.favorite, true, 'an overwrite keeps the favorite')
end)
