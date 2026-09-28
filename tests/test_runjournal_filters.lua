-- RunJournal stats filters (T-371): the include toggles (seeded, Finder, challenge,
-- daily runs are left out by DEFAULT_FILTER), deck and stake, the endless-reload rule,
-- and stats.jokers (every joker, win rate, held, lifespan). Synthetic records through
-- recorder.save (which derives T-370's index flags); nothing here runs the game.
local H = ...

local function setup()
  love.filesystem.createDirectory('1')
  RunJournal = {}
  return require('runjournal.recorder'), require('runjournal.stats')
end

-- A finished record (won: true / false; nil leaves it unfinished) of `kind`:
-- 'seeded', 'finder', 'challenge', 'daily' or nil (normal). A daily run is seeded,
-- as the daily seed plays it.
local function record(id, kind, o)
  o = o or {}
  local t = o.t or 1000
  local r = {run_id = id..':'..t, seed = id, deck = o.deck or 'b_red', stake = o.stake or 1,
    started_at = t, ended_at = o.won ~= nil and t + 100 or nil, won = o.won,
    final_ante = o.ante or 2, final_round = 6, antes = {}, jokers_seen = o.seen or {},
    jokers_final = o.final, origin = {}, endless = o.endless}
  if kind == 'seeded' then r.seeded = true end
  if kind == 'finder' then r.origin = {filter_name = 'Hunt '..id} end
  if kind == 'challenge' then r.challenge = 'c_omelette_1' end
  if kind == 'daily' then r.seeded = true; r.origin = {kind = 'daily', date = '2026-09-28', mode = 'blind'} end
  return r
end

-- One finished run of each kind plus two normal ones, all saved.
local function mixed(rec)
  local list = {
    record('N1', nil, {won = true, t = 1}), record('N2', nil, {won = false, t = 2, deck = 'b_blue'}),
    record('S1', 'seeded', {won = true, t = 3}), record('F1', 'finder', {won = false, t = 4}),
    record('C1', 'challenge', {won = true, t = 5}), record('D1', 'daily', {won = false, t = 6}),
  }
  for _, r in ipairs(list) do assert(rec.save(r)) end
  return list
end

local function with(include, extra)
  local f = {include = include}
  for k, v in pairs(extra or {}) do f[k] = v end
  return f
end

H.test('the default hides seeded, finder, challenge and daily runs', function()
  local rec, stats = setup()
  mixed(rec)
  for _, k in ipairs(stats.KINDS) do H.eq(stats.DEFAULT_FILTER.include[k], false, 'default '..k) end
  local s = stats.compute(stats.DEFAULT_FILTER)
  H.eq(s.runs, 2, 'normal runs only'); H.eq(s.wins, 1)
  H.eq(stats(stats.DEFAULT_FILTER).runs, 2, 'callable form')
  H.eq(stats.DEFAULT_FILTER.include.seeded, false, 'compute leaves DEFAULT_FILTER alone')
end)

H.test('a bare stats() and a table filter without include count every run, as before', function()
  local rec, stats = setup()
  mixed(rec)
  H.eq(stats().runs, 6, 'bare call'); H.eq(stats().wins, 3)
  H.eq(stats.compute().runs, 6)
  H.eq(stats({deck = 'b_red'}).runs, 5, 'a 0.3 table filter')
  H.eq(stats(function(e) return e.won == true end).runs, 3, 'a function filter')
end)

H.test('each toggle brings its runs back', function()
  local rec, stats = setup()
  mixed(rec)
  local want = {seeded = 'S1', finder = 'F1', challenge = 'C1', daily = 'D1'}
  for _, k in ipairs(stats.KINDS) do
    local s = stats(with({[k] = true}))
    H.eq(s.runs, 3, k..' on')
    local seen = false
    for _, e in ipairs(rec.list()) do
      if e.seed == want[k] then seen = stats.kind_of(e) == k end
    end
    H.ok(seen, want[k]..' is a '..k..' run')
  end
  H.eq(stats(with({seeded = true, finder = true})).runs, 4, 'two toggles')
  H.eq(stats(with({seeded = true, finder = true, challenge = true, daily = true})).runs, 6, 'all on')
end)

H.test('a daily run is seeded but only the Daily toggle brings it back', function()
  local rec, stats = setup()
  assert(rec.save(record('D1', 'daily', {won = true})))
  local e = rec.list()[1]
  H.eq(e.seeded, true, 'the daily run is seeded'); H.eq(e.daily, true)
  H.eq(stats.kind_of(e), 'daily')
  H.eq(stats(with({seeded = true})).runs, 0, 'Seeded alone does not show it')
  H.eq(stats(with({daily = true})).runs, 1, 'Daily does')
  -- A Finder run the Play left seeded is still a Finder run.
  local f = record('F2', 'finder', {won = true, t = 7}); f.seeded = true
  assert(rec.save(f))
  H.eq(stats(with({seeded = true})).runs, 0)
  H.eq(stats(with({finder = true})).runs, 1)
end)

H.test('deck and stake filters combine with the toggles', function()
  local rec, stats = setup()
  mixed(rec)
  assert(rec.save(record('N3', nil, {won = true, t = 7, stake = 3})))
  assert(rec.save(record('S2', 'seeded', {won = true, t = 8, stake = 3, deck = 'b_blue'})))
  local d = stats.DEFAULT_FILTER
  H.eq(stats(with(d.include, {deck = 'b_blue'})).runs, 1, 'normal Blue runs')
  H.eq(stats(with({seeded = true}, {deck = 'b_blue'})).runs, 2, 'plus the seeded Blue run')
  H.eq(stats(with(d.include, {stake = 3})).runs, 1, 'normal stake 3 runs')
  H.eq(stats(with({seeded = true}, {stake = 3})).runs, 2)
  H.eq(stats(with({seeded = true}, {stake = 3, deck = 'b_blue'})).runs, 1, 'deck and stake')
  local s = stats(with(d.include, {deck = 'b_blue'}))
  H.eq(s.by_deck.b_red, nil, 'by_deck follows the deck filter')
  H.eq(s.by_deck.b_blue.runs, 1)
end)

H.test('entries without flags (recorded before 0.4.0) count as normal', function()
  local rec, stats = setup()
  local fs = require('bhcore.fs')
  mixed(rec)
  -- Strip the T-370 flags from the index, as a 0.3 index has none.
  local path = rec.dir()..'/index.jkr'
  local idx = assert(fs.read_table(path))
  for _, e in ipairs(idx.runs) do e.seeded, e.finder, e.daily, e.challenge, e.endless = nil, nil, nil, nil, nil end
  assert(fs.write_table(path, idx))
  for _, e in ipairs(rec.list()) do H.eq(stats.kind_of(e), nil, e.seed..' is normal') end
  H.eq(stats(stats.DEFAULT_FILTER).runs, 6, 'every old run counts under the default')
  H.eq(#stats.jokers(stats.DEFAULT_FILTER), 0, 'no jokers in these records')
end)

H.test('the endless-reload record counts as unfinished, never as a loss', function()
  local rec, stats = setup()
  assert(rec.save(record('W1', nil, {won = true, t = 1, endless = true, final = {'j_joker'}})))
  -- The reload's new record: endless, won nil, then lost (won = false) at run_end.
  assert(rec.save(record('W1', nil, {won = false, t = 2, endless = true, final = {'j_joker'}})))
  local reload = record('W1', nil, {t = 3, endless = true}); reload.ended_at = 400
  assert(rec.save(reload))
  for _, f in ipairs({false, true}) do
    local s = f and stats(stats.DEFAULT_FILTER) or stats()
    H.eq(s.runs, 1, 'only the won endless run is finished')
    H.eq(s.wins, 1); H.eq(s.win_rate, 1, 'no loss counted')
    H.eq(s.unfinished, 2, 'both reloads are unfinished')
  end
  H.eq(stats.kind_of(rec.list()[1]), nil, 'an endless run is a normal run')
  local j = stats.jokers()
  H.eq(#j, 1); H.eq(j[1].runs, 1, 'the reload holds no finished run'); H.eq(j[1].wins, 1)
end)

H.test('jokers(): runs, wins, win rate, held and lifespan', function()
  local rec, stats = setup()
  -- Blueprint held at two shops of run A (won, kept to the end) and three of run B
  -- (lost, sold before the end); Baron only at A's end (bought in its last shop).
  assert(rec.save(record('A', nil, {won = true, t = 1,
    seen = {{'j_joker'}, {'j_joker', 'j_blueprint'}, {'j_blueprint', 'j_blueprint'}},
    final = {'j_blueprint', 'j_baron'}})))
  assert(rec.save(record('B', nil, {won = false, t = 2,
    seen = {{'j_blueprint'}, {'j_blueprint', 'j_joker'}, {'j_blueprint'}, {'j_joker'}},
    final = {'j_joker'}})))
  local rows = {}
  for _, r in ipairs(stats.jokers()) do rows[r.key] = r end
  local bp = rows.j_blueprint
  H.eq(bp.runs, 1, 'Blueprint ended one run'); H.eq(bp.wins, 1); H.eq(bp.win_rate, 1)
  H.eq(bp.held, 2, 'held in both runs')
  H.eq(bp.lifespan, 2.5, 'two shops held, three shops held')
  local jk = rows.j_joker
  H.eq(jk.runs, 1); H.eq(jk.wins, 0); H.eq(jk.win_rate, 0)
  H.eq(jk.held, 2); H.eq(jk.lifespan, 2, 'A: 2 shops, B: 2 shops')
  local baron = rows.j_baron
  H.eq(baron.runs, 1); H.eq(baron.held, 0); H.eq(baron.lifespan, nil, 'never seen at a shop')
  -- The same numbers from records passed in directly.
  local direct = {}
  for _, r in ipairs(stats.jokers(nil, {rec.read('A:1'), rec.read('B:2')})) do direct[r.key] = r end
  H.eq(direct.j_blueprint.lifespan, 2.5); H.eq(direct.j_joker.runs, 1)
end)

H.test('jokers() lists every joker, not a top 10', function()
  local rec, stats = setup()
  local keys = {}
  for i = 1, 15 do keys[i] = string.format('j_test%02d', i) end
  assert(rec.save(record('A', nil, {won = true, t = 1, seen = {{keys[1], keys[2]}},
    final = {keys[1], keys[2], keys[3], keys[4], keys[5], keys[6], keys[7], keys[8]}})))
  assert(rec.save(record('B', nil, {won = false, t = 2, seen = {{keys[15]}},
    final = {keys[9], keys[10], keys[11], keys[12], keys[13], keys[14]}})))
  local rows = stats.jokers()
  H.eq(#rows, 15, 'every key, from the end sets and the shops')
  -- Sorted by runs, then key: all have one run except the held-only one.
  H.eq(rows[1].key, 'j_test01'); H.eq(rows[15].key, 'j_test15')
  H.eq(rows[15].runs, 0); H.eq(rows[15].held, 1)
end)

H.test('jokers() follows the filter and skips unfinished runs', function()
  local rec, stats = setup()
  assert(rec.save(record('N', nil, {won = true, t = 1, final = {'j_joker'}})))
  assert(rec.save(record('S', 'seeded', {won = true, t = 2, final = {'j_mime'}})))
  assert(rec.save(record('F', 'finder', {won = false, t = 3, final = {'j_baron', 'j_joker'}})))
  assert(rec.save(record('U', nil, {t = 4, seen = {{'j_dna'}}, final = {'j_dna'}})))
  local function keys(f)
    local out = {}
    for _, r in ipairs(stats.jokers(f)) do out[#out + 1] = r.key..'='..r.runs end
    table.sort(out)
    return table.concat(out, ' ')
  end
  H.eq(keys(stats.DEFAULT_FILTER), 'j_joker=1', 'normal finished runs only')
  H.eq(keys(with({seeded = true})), 'j_joker=1 j_mime=1')
  H.eq(keys(with({finder = true})), 'j_baron=1 j_joker=2')
  H.eq(keys(with({finder = true}, {deck = 'b_blue'})), '', 'no run on that deck')
  H.eq(keys(), 'j_baron=1 j_joker=2 j_mime=1', 'no filter: every finished run')
end)

H.test('jokers() reads records through the given reader; an unreadable one keeps runs/wins', function()
  local rec, stats = setup()
  assert(rec.save(record('A', nil, {won = true, t = 1, seen = {{'j_joker'}, {'j_joker'}}, final = {'j_joker'}})))
  assert(rec.save(record('B', nil, {won = true, t = 2, seen = {{'j_joker'}}, final = {'j_joker'}})))
  local reads, cache = 0, {}
  local function read(id)
    reads = reads + 1
    if id == 'B:2' then return nil, 'gone' end
    cache[id] = cache[id] or rec.read(id)
    return cache[id]
  end
  local rows = stats.jokers(nil, rec.list(), read)
  H.eq(reads, 2, 'one read per counted run')
  H.eq(#rows, 1)
  H.eq(rows[1].runs, 2, 'both runs from the index'); H.eq(rows[1].wins, 2)
  H.eq(rows[1].held, 1, 'only the readable record adds a held run'); H.eq(rows[1].lifespan, 2)
  local by = stats().by_joker.j_joker
  H.eq(by.runs, rows[1].runs, 'runs as by_joker counts them'); H.eq(by.wins, rows[1].wins)
end)

H.test('by_filter ignores the filter: hunts are Finder runs', function()
  local rec, stats = setup()
  mixed(rec)
  local f2 = record('F2', 'finder', {won = true, t = 7}); f2.seeded = true
  assert(rec.save(f2))
  H.eq(stats(stats.DEFAULT_FILTER).runs, 2, 'the default hides both Finder runs')
  local g = stats.by_filter()
  H.eq(#g, 2, 'both hunts listed')
  local names = {}
  for _, x in ipairs(g) do names[#names + 1] = x.filter_name end
  table.sort(names)
  H.eq(table.concat(names, ','), 'Hunt F1,Hunt F2')
  H.eq(#stats.by_filter(rec.list()), 2, 'index entries too')
end)

H.test('sorting ties by name', function()
  local _, stats = setup()
  local function rows()
    return {
      {key = 'j_c', name = 'Zany Joker', runs = 2, win_rate = 0.5, lifespan = 3},
      {key = 'j_a', name = 'Abstract Joker', runs = 2, win_rate = 0.5, lifespan = 3},
      {key = 'j_b', name = 'Mime', runs = 5, win_rate = 0.2, lifespan = nil},
      {key = 'j_d', name = 'Baron', runs = 1, win_rate = 1, lifespan = 1.5},
    }
  end
  local function order(list)
    local out = {}
    for i, r in ipairs(list) do out[i] = r.key end
    return table.concat(out, ',')
  end
  H.eq(order(stats.sort_jokers(rows(), 'runs')), 'j_b,j_a,j_c,j_d', 'runs; Abstract before Zany')
  H.eq(order(stats.sort_jokers(rows(), 'win_rate')), 'j_d,j_a,j_c,j_b', 'win rate')
  H.eq(order(stats.sort_jokers(rows(), 'lifespan')), 'j_a,j_c,j_d,j_b', 'lifespan; nil last')
  -- Without names, name_of names the key; without either, the key itself.
  local plain = {{key = 'j_z', runs = 1}, {key = 'j_y', runs = 1}}
  H.eq(order(stats.sort_jokers(plain, 'runs')), 'j_y,j_z', 'by key')
  local named = {{key = 'j_z', runs = 1}, {key = 'j_y', runs = 1}}
  local names = {j_z = 'Alpha', j_y = 'Beta'}
  H.eq(order(stats.sort_jokers(named, 'runs', function(k) return names[k] end)), 'j_z,j_y', 'by name_of')
end)

H.test('kind_of reads records as the recorder derives entries', function()
  local rec, stats = setup()
  local list = mixed(rec)
  local by_seed = {}
  for _, e in ipairs(rec.list()) do by_seed[e.seed] = e end
  for _, r in ipairs(list) do
    H.eq(stats.kind_of(r), stats.kind_of(by_seed[r.seed]), r.seed..': record and entry agree')
  end
  H.eq(stats.kind_of({finder = false, daily = false, seeded = false}), nil)
  H.eq(stats.kind_of('junk'), nil)
end)
