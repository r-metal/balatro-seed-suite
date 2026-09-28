-- store.lua 0.3.4 folders and search: meta.folder (set, trim, cap, clear), list's
-- folder and query fields combined with kind and favorite, store.folders(), and
-- prune_checkpoints keeping a filed checkpoint. Contract: docs/contracts-0.2.md
-- § SaveSlots 0.3.4.
local H = ...

local now = 1700000000
local function clock(t) now = t; os.time = function() return now end end
local reset = H.reset
H.reset = function() reset(); clock(1700000000) end

local function store() return require('saveslots.store') end
local function index_bytes() return get_compressed('1/saveslots/index.jkr') end
local function disk_index() return STR_UNPACK(index_bytes()) end
local function by_id(list, id)
  for _, e in ipairs(list) do if e.id == id then return e end end
end
local function ids(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.id end
  return table.concat(out, ',')
end

-- Saves one slot per spec, a second apart (so list order is the reverse of `specs`).
-- spec = {name, meta?, run?}. Returns the ids in spec order.
local function save_all(s, specs)
  local out = {}
  for i, sp in ipairs(specs) do
    if i > 1 then clock(now + 1) end
    out[i] = s.save(sp.run or H.fake_run(), sp.name, nil, sp.meta)
    H.ok(out[i], 'save '..tostring(sp.name)..' failed')
  end
  return out
end

H.test('set, trim, cap and clear a folder', function()
  local s = store()
  H.eq(s.FOLDER_MAX, 16)
  local id = s.save(H.fake_run(), 'x')
  H.ok(s.set_meta(id, {folder = '  perkeo 20  '}))
  H.eq(s.list()[1].meta.folder, 'perkeo 20', 'trimmed')
  H.eq(disk_index().slots[id].meta.folder, 'perkeo 20')
  H.ok(s.set_meta(id, {folder = string.rep('f', 30)}))
  H.eq(s.list()[1].meta.folder, string.rep('f', 16), 'capped at FOLDER_MAX')
  -- a cap that lands after a space is trimmed again
  H.ok(s.set_meta(id, {folder = string.rep('a', 15)..' b'}))
  H.eq(s.list()[1].meta.folder, string.rep('a', 15))
  H.ok(s.set_meta(id, {folder = '   '}))
  H.eq(s.list()[1].meta.folder, nil, 'blank clears it')
  H.eq(disk_index().slots[id].meta, nil, 'clearing the only field restores the 0.1.0 shape')
end)

H.test('a folder beside target and notes: clearing one keeps the others', function()
  local s = store()
  local id = s.save(H.fake_run(), 'x', nil, {kind = 'hunt', target = 'T', notes = 'N', folder = 'F'})
  H.ok(s.set_meta(id, {folder = ''}))
  local m = s.list()[1].meta
  H.eq(m.folder, nil); H.eq(m.target, 'T'); H.eq(m.notes, 'N'); H.eq(m.kind, 'hunt')
end)

H.test('a 0.1.0 entry (no meta) lists under folder = false', function()
  local s = store()
  local run = H.fake_run{seed = 'OLDSEED1'}
  love.filesystem.createDirectory('1/saveslots')
  H.ok(love.filesystem.write('1/saveslots/1600000000.jkr', love.data.compress('string', 'deflate', STR_PACK(run))))
  local idx = {version = 1, imported_brainstorm = true, slots = {
    ['1600000000'] = {name = 'Old one', saved_at = 1600000000, summary = s.summarize(run)},
  }}
  H.ok(love.filesystem.write('1/saveslots/index.jkr', love.data.compress('string', 'deflate', STR_PACK(idx))))
  local filed = s.save(H.fake_run(), 'filed', nil, {folder = 'F'})
  H.eq(ids(s.list({folder = false})), '1600000000')
  H.eq(ids(s.list({folder = '  '})), '1600000000', 'a blank folder string is unfiled too')
  H.eq(ids(s.list({folder = 'F'})), filed)
  H.eq(#s.list({folder = 'Old one'}), 0)
  H.eq(disk_index().slots['1600000000'].meta, nil, 'listing must not rewrite old entries')
  H.eq(disk_index().version, 1)
end)

H.test('folder matches case-sensitively after trimming; a bad filter type filters nothing', function()
  local s = store()
  local a, b = unpack(save_all(s, {
    {name = 'a', meta = {folder = 'Perkeo'}},
    {name = 'b', meta = {folder = 'perkeo'}},
  }))
  H.eq(ids(s.list({folder = ' Perkeo '})), a)
  H.eq(ids(s.list({folder = 'perkeo'})), b)
  H.eq(#s.list({folder = 'PERKEO'}), 0)
  H.eq(#s.list({folder = 'Perk'}), 0, 'a folder is not a prefix match')
  H.eq(#s.list({folder = 7}), 2)
  H.eq(#s.list({folder = true}), 2)
end)

H.test('folder combines with kind and with favorite', function()
  local s = store()
  local sv, cp, hunt, other, fav = unpack(save_all(s, {
    {name = 'save', meta = {folder = 'F'}},
    {name = 'cp', meta = {kind = 'checkpoint', folder = 'F'}},
    {name = 'hunt', meta = {kind = 'hunt', folder = 'F', favorite = true}},
    {name = 'other', meta = {kind = 'hunt', folder = 'G'}},
    {name = 'fav', meta = {favorite = true}},
  }))
  H.eq(ids(s.list({folder = 'F'})), table.concat({hunt, cp, sv}, ','))
  H.eq(ids(s.list({folder = 'F', kind = 'hunt'})), hunt)
  H.eq(ids(s.list({folder = 'F', kind = 'checkpoint'})), cp)
  H.eq(ids(s.list({folder = 'G', kind = 'hunt'})), other)
  H.eq(#s.list({folder = 'G', kind = 'save'}), 0)
  H.eq(ids(s.list({folder = 'F', favorite = true})), hunt)
  H.eq(ids(s.list({folder = false, favorite = true})), fav)
  H.eq(ids(s.list({folder = false, kind = 'save'})), fav)
  H.eq(#s.list({folder = false, kind = 'hunt'}), 0)
end)

H.test('query matches each of the six fields', function()
  local s = store()
  local byname, seed, deck, notes, target, folder = unpack(save_all(s, {
    {name = 'Alpha zulu'},
    {name = 'b', run = H.fake_run{seed = 'QWERTY12'}},
    {name = 'c', run = H.fake_run{deck = 'Plasma Deck'}},
    {name = 'd', meta = {notes = 'reroll for Blueprint'}},
    {name = 'e', meta = {target = 'Win at ante 8'}},
    {name = 'f', meta = {folder = 'legendaries'}},
  }))
  H.eq(ids(s.list({query = 'zulu'})), byname, 'name')
  H.eq(ids(s.list({query = 'ERTY1'})), seed, 'summary.seed')
  H.eq(ids(s.list({query = 'plasma'})), deck, 'summary.deck')
  H.eq(ids(s.list({query = 'blueprint'})), notes, 'meta.notes')
  H.eq(ids(s.list({query = 'ante 8'})), target, 'meta.target')
  H.eq(ids(s.list({query = 'legend'})), folder, 'meta.folder')
  H.eq(#s.list({query = 'nowhere'}), 0)
end)

H.test('query is case-insensitive and trimmed', function()
  local s = store()
  local a, b = unpack(save_all(s, {
    {name = 'Perkeo Run'},
    {name = 'other', meta = {notes = 'PERKEO in the shop'}},
  }))
  H.eq(ids(s.list({query = 'perkeo'})), b..','..a)
  H.eq(ids(s.list({query = 'PeRkEo'})), b..','..a)
  H.eq(ids(s.list({query = '  keo r  '})), a, 'inner spaces kept, outer ones trimmed')
end)

H.test('query treats % and . and other magic characters literally', function()
  local s = store()
  local pct, dot, plain = unpack(save_all(s, {
    {name = '50% off'},
    {name = 'v1.0 run'},
    {name = 'v100 run'},
  }))
  H.eq(ids(s.list({query = '%'})), pct, '% is a plain character')
  H.eq(ids(s.list({query = '0%'})), pct)
  H.eq(ids(s.list({query = '.'})), dot, '. matches only a dot')
  H.eq(ids(s.list({query = '1.0'})), dot, '1.0 does not match 100')
  H.eq(#s.list({query = '%a'}), 0, '%a is not a letter class')
  H.eq(#s.list({query = '[v]'}), 0)
  H.eq(#s.list({query = '('}), 0, 'an unbalanced ( does not raise')
  H.ok(plain)
end)

H.test('a blank or non-string query filters nothing', function()
  local s = store()
  save_all(s, {{name = 'a'}, {name = 'b', meta = {kind = 'checkpoint'}}})
  H.eq(#s.list({query = ''}), 2)
  H.eq(#s.list({query = '   '}), 2)
  H.eq(#s.list({query = 5}), 2)
  H.eq(#s.list({query = '', kind = 'checkpoint'}), 1, 'the other fields still apply')
end)

H.test('query combines with folder, kind and favorite', function()
  local s = store()
  local a, b, c = unpack(save_all(s, {
    {name = 'Perkeo one', meta = {folder = 'F'}},
    {name = 'Perkeo two', meta = {folder = 'F', kind = 'hunt', favorite = true}},
    {name = 'Perkeo three'},
  }))
  H.eq(ids(s.list({query = 'perkeo', folder = 'F'})), b..','..a)
  H.eq(ids(s.list({query = 'perkeo', folder = false})), c)
  H.eq(ids(s.list({query = 'perkeo', folder = 'F', kind = 'hunt'})), b)
  H.eq(ids(s.list({query = 'one', folder = 'F', favorite = true})), '')
  H.eq(ids(s.list({query = 'two', folder = 'F', favorite = true})), b)
end)

H.test('folders() is sorted case-insensitively and distinct', function()
  local s = store()
  H.eq(#s.folders(), 0, 'no slots, no folders')
  save_all(s, {
    {name = 'a', meta = {folder = 'zeta'}},
    {name = 'b', meta = {folder = 'Alpha'}},
    {name = 'c', meta = {folder = 'beta'}},
    {name = 'd', meta = {folder = 'zeta'}},
    {name = 'e'},
    {name = 'f', meta = {folder = 'alpha'}},
  })
  H.eq(table.concat(s.folders(), ','), 'Alpha,alpha,beta,zeta')
end)

H.test('folders() drops a folder once its last slot leaves it', function()
  local s = store()
  local a, b = unpack(save_all(s, {{name = 'a', meta = {folder = 'F'}}, {name = 'b', meta = {folder = 'G'}}}))
  H.eq(table.concat(s.folders(), ','), 'F,G')
  H.ok(s.set_meta(a, {folder = ''}))
  H.eq(table.concat(s.folders(), ','), 'G')
  H.ok(s.delete(b))
  H.eq(#s.folders(), 0)
end)

H.test('prune keeps a checkpoint that has a folder', function()
  local s = store()
  local old, mid, new = unpack(save_all(s, {
    {name = 'Auto A1', meta = {kind = 'checkpoint', run_id = 'R:1'}},
    {name = 'Auto A2', meta = {kind = 'checkpoint', run_id = 'R:1'}},
    {name = 'Auto A3', meta = {kind = 'checkpoint', run_id = 'R:1'}},
  }))
  H.ok(s.set_meta(old, {folder = 'keep'}))
  H.eq(s.prune_checkpoints(1, 3), 1, 'one of the two unfiled is over the limit')
  H.ok(by_id(s.list(), old), 'the filed checkpoint was pruned')
  H.ok(by_id(s.list(), new))
  H.eq(by_id(s.list(), mid), nil)
  H.eq(s.prune_checkpoints(0, 0), 1, 'even a limit of zero keeps it')
  H.eq(ids(s.list()), old)
end)

H.test('a folder survives an overwrite, and a new one merges in', function()
  local s = store()
  local id = s.save(H.fake_run{ante = 1}, 'x', nil, {kind = 'hunt', folder = 'F'})
  clock(now + 5)
  H.eq(s.save(H.fake_run{ante = 3}, nil, id), id)
  local e = s.list()[1]
  H.eq(e.summary.ante, 3); H.eq(e.meta.folder, 'F'); H.eq(e.meta.kind, 'hunt')
  H.eq(s.save(H.fake_run{ante = 4}, nil, id, {folder = ' G '}), id)
  H.eq(s.list()[1].meta.folder, 'G')
  H.ok(s.rename(id, 'y'))
  H.eq(s.list()[1].meta.folder, 'G', 'a rename keeps it')
end)

H.test('a bad folder type is refused: nil, err, and nothing written', function()
  local s = store()
  local id = s.save(H.fake_run(), 'x', nil, {folder = 'F'})
  local before = index_bytes()
  for i, bad in ipairs({5, true, false, {}, {'F'}}) do
    local ok, err = s.set_meta(id, {folder = bad})
    H.eq(ok, nil, 'set_meta case '..i..' accepted')
    H.eq(err, 'folder must be a string', 'set_meta case '..i)
  end
  H.eq(index_bytes(), before, 'index changed by a refused set_meta')
  local nid, err = s.save(H.fake_run(), 'y', nil, {folder = 7})
  H.eq(nid, nil); H.eq(err, 'folder must be a string')
  H.eq(index_bytes(), before, 'index changed by a refused save')
  H.eq(#s.list(), 1)
  H.eq(s.list()[1].meta.folder, 'F')
  local oid, oerr = s.save(H.fake_run{ante = 7}, nil, id, {folder = {}})
  H.eq(oid, nil); H.ok(oerr)
  H.eq(s.list()[1].summary.ante, 2, 'a refused overwrite writes nothing')
end)

H.test('a share code has no room for a folder (local organisation only)', function()
  local sharecode = require('saveslots.sharecode')
  local code, err = sharecode.encode({seed = 'ABCD1234', deck = 'b_red', stake = 1, notes = 'n', folder = 'F'})
  H.eq(code, nil, 'the share code schema took a folder')
  H.ok(err)
end)
