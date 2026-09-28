-- RunJournal daily list and pick rate (T-378b): stats.dailies (the daily seed's runs,
-- found by a record's origin.kind or an index entry's daily flag, newest first) and
-- stats.jokers' offered / picked / pick_rate (counted only over records that have
-- T-372a's `offered`), plus the "Pick rate" sort. Synthetic records through
-- recorder.save (which derives T-370's index flags); nothing here runs the game.
local H = ...

local function setup()
  love.filesystem.createDirectory('1')
  RunJournal = {}
  return require('runjournal.recorder'), require('runjournal.stats')
end

-- A record. o.won: true / false (finished), nil (unfinished). o.daily = 'blind' |
-- 'routed' makes it a daily run of o.date (seeded, as daily.play leaves it).
local function record(id, o)
  o = o or {}
  local t = o.t or 1000
  local r = {run_id = id..':'..t, seed = id, deck = o.deck or 'b_red', stake = o.stake or 1,
    started_at = t, ended_at = (o.won ~= nil or o.ended) and t + 100 or nil, won = o.won,
    final_ante = o.ante or 2, final_round = 6, antes = {}, jokers_seen = o.seen or {},
    jokers_final = o.final, origin = o.origin or {}, offered = o.offered, endless = o.endless}
  if o.daily then
    r.seeded = true
    r.origin = {kind = 'daily', date = o.date or '2026-09-28', mode = o.daily}
  end
  if o.seeded then r.seeded = true end
  return r
end

local function ids(rows)
  local out = {}
  for i, r in ipairs(rows) do out[i] = tostring(r.seed) end
  return table.concat(out, ',')
end

local function by_key(rows)
  local out = {}
  for _, r in ipairs(rows) do out[r.key] = r end
  return out
end

H.test('dailies() finds daily records by origin and index entries by flag, newest first', function()
  local rec, stats = setup()
  local list = {
    record('D1', {daily = 'blind', date = '2026-09-26', won = true, t = 100, ante = 8}),
    record('D2', {daily = 'routed', date = '2026-09-27', won = false, t = 200, ante = 3, deck = 'b_blue'}),
    record('D3', {daily = 'blind', date = '2026-09-28', t = 300}),
  }
  for _, r in ipairs(list) do assert(rec.save(r)) end
  -- Records passed in: found by origin.kind.
  local from_records = stats.dailies(list)
  H.eq(ids(from_records), 'D3,D2,D1', 'records, newest first')
  -- Index entries (no origin): found by the daily flag, date and mode from the record.
  local rows = stats.dailies()
  H.eq(ids(rows), 'D3,D2,D1', 'index entries, newest first')
  H.eq(rows[1].date, '2026-09-28'); H.eq(rows[1].mode, 'blind')
  H.eq(rows[2].date, '2026-09-27'); H.eq(rows[2].mode, 'routed'); H.eq(rows[2].deck, 'b_blue')
  H.eq(rows[3].date, '2026-09-26'); H.eq(rows[3].mode, 'blind')
  for i, r in ipairs(from_records) do
    for _, k in ipairs({'run_id', 'date', 'mode', 'seed', 'deck', 'stake', 'won', 'final_ante', 'started_at', 'ended_at'}) do
      H.eq(r[k], rows[i][k], r.seed..': '..k..' from the record and from the entry')
    end
  end
end)

H.test('dailies(): won, lost at an ante, unfinished', function()
  local rec, stats = setup()
  assert(rec.save(record('W', {daily = 'blind', won = true, t = 1, ante = 8})))
  assert(rec.save(record('L', {daily = 'routed', won = false, t = 2, ante = 3})))
  assert(rec.save(record('U', {daily = 'blind', t = 3, ante = 1})))
  -- The endless reload: ended, won nil, endless: unfinished, as compute counts it.
  assert(rec.save(record('E', {daily = 'blind', t = 4, ended = true, endless = true, ante = 9})))
  local got = {}
  for _, r in ipairs(stats.dailies()) do got[r.seed] = r end
  H.eq(got.W.won, true); H.eq(got.W.final_ante, 8)
  H.eq(got.L.won, false, 'finished without a win'); H.eq(got.L.final_ante, 3)
  H.eq(got.U.won, nil, 'in progress'); H.eq(got.U.ended_at, nil)
  H.eq(got.E.won, nil, 'the endless reload is unfinished, never a loss')
end)

H.test('dailies() excludes every run that is not a daily', function()
  local rec, stats = setup()
  assert(rec.save(record('N', {won = true, t = 1})))
  assert(rec.save(record('S', {won = true, t = 2, seeded = true})))
  assert(rec.save(record('F', {won = false, t = 3, origin = {filter_name = 'Hunt'}})))
  assert(rec.save(record('I', {won = false, t = 4, origin = {kind = 'import'}})))
  assert(rec.save(record('D', {daily = 'routed', won = false, t = 5})))
  H.eq(ids(stats.dailies()), 'D', 'only the daily run, from the index')
  local records = {}
  for _, e in ipairs(rec.list()) do records[#records + 1] = rec.read(e.run_id) end
  H.eq(ids(stats.dailies(records)), 'D', 'only the daily run, from records')
  H.eq(#stats.dailies({}), 0, 'an empty list')
end)

H.test('dailies() lists every run of a date: nothing is collapsed', function()
  local rec, stats = setup()
  assert(rec.save(record('9CWQP4Y9', {daily = 'blind', won = false, t = 10, ante = 2})))
  local again = record('9CWQP4Y9', {daily = 'routed', won = true, t = 20, ante = 8})
  assert(rec.save(again))
  assert(rec.save(record('9CWQP4Y9', {daily = 'routed', t = 30})))
  local rows = stats.dailies()
  H.eq(#rows, 3, 'three runs of one date')
  H.eq(rows[1].started_at, 30); H.eq(rows[2].started_at, 20); H.eq(rows[3].started_at, 10)
  H.eq(rows[2].mode, 'routed'); H.eq(rows[3].mode, 'blind')
  for _, r in ipairs(rows) do H.eq(r.date, '2026-09-28') end
end)

H.test('dailies() reads only daily entries; an unreadable one keeps its row', function()
  local rec, stats = setup()
  assert(rec.save(record('N', {won = true, t = 1})))
  assert(rec.save(record('D1', {daily = 'blind', won = true, t = 86400 * 3 + 5})))
  assert(rec.save(record('D2', {daily = 'routed', won = false, t = 86400 * 4 + 5})))
  local reads = {}
  local function read(id)
    reads[#reads + 1] = id
    if id:find('^D2') then return nil, 'gone' end
    return rec.read(id)
  end
  local rows = stats.dailies(rec.list(), read)
  H.eq(#reads, 2, 'one read per daily entry, none for the normal run')
  H.eq(ids(rows), 'D2,D1')
  H.eq(rows[1].mode, nil, 'no record: no mode')
  H.eq(rows[1].date, os.date('!%Y-%m-%d', 86400 * 4 + 5), 'no record: the UTC start date')
  H.eq(rows[1].won, false, 'the entry still says how it ended')
  H.eq(rows[2].mode, 'blind'); H.eq(rows[2].date, '2026-09-28')
  -- A reader that raises is caught like one that returns nil.
  local rows2 = stats.dailies(rec.list(), function() error('boom') end)
  H.eq(#rows2, 2); H.eq(rows2[1].mode, nil)
end)

H.test('pick_rate: offered in 4 runs, held in 1 -> 25%', function()
  local rec, stats = setup()
  -- Blueprint offered in four runs; only run A held it at a later shop.
  assert(rec.save(record('A', {won = true, t = 1, seen = {{'j_joker'}, {'j_joker', 'j_blueprint'}},
    final = {'j_blueprint'}, offered = {j_blueprint = 2, j_joker = 1}})))
  assert(rec.save(record('B', {won = false, t = 2, seen = {{'j_joker'}}, final = {'j_joker'},
    offered = {j_blueprint = 1, j_joker = 3}})))
  assert(rec.save(record('C', {won = false, t = 3, seen = {{}}, final = {}, offered = {j_blueprint = 1}})))
  assert(rec.save(record('D', {won = true, t = 4, seen = {{'j_mime'}}, final = {'j_mime'},
    offered = {j_blueprint = 4, j_mime = 1}})))
  local rows = by_key(stats.jokers())
  local bp = rows.j_blueprint
  H.eq(bp.offered, 4, 'runs that offered it, not how many times')
  H.eq(bp.picked, 1); H.eq(bp.pick_rate, 0.25)
  H.eq(rows.j_joker.offered, 2); H.eq(rows.j_joker.picked, 2); H.eq(rows.j_joker.pick_rate, 1)
  H.eq(rows.j_mime.pick_rate, 1)
  -- The same numbers from index entries read through recorder.read.
  local direct = by_key(stats.jokers(nil, rec.list()))
  H.eq(direct.j_blueprint.pick_rate, 0.25); H.eq(direct.j_joker.offered, 2)
end)

H.test('records without offered are ignored for the pick rate but count runs and wins', function()
  local rec, stats = setup()
  -- An old run (no offered) that ended holding Blueprint and won, held at two shops.
  assert(rec.save(record('OLD', {won = true, t = 1, seen = {{'j_blueprint'}, {'j_blueprint'}},
    final = {'j_blueprint'}})))
  -- A 0.4.0 run that offered Blueprint and never held it.
  assert(rec.save(record('NEW', {won = false, t = 2, seen = {{}}, final = {}, offered = {j_blueprint = 1}})))
  -- An old run with Baron only: no offered data for Baron anywhere.
  assert(rec.save(record('OLD2', {won = true, t = 3, seen = {{'j_baron'}}, final = {'j_baron'}})))
  local rows = by_key(stats.jokers())
  local bp = rows.j_blueprint
  H.eq(bp.runs, 1, 'the old run counts in runs'); H.eq(bp.wins, 1); H.eq(bp.held, 1)
  H.eq(bp.offered, 1, 'only the run with offered data'); H.eq(bp.picked, 0, 'the old hold is not a pick')
  H.eq(bp.pick_rate, 0)
  local baron = rows.j_baron
  H.eq(baron.runs, 1); H.eq(baron.wins, 1); H.eq(baron.offered, 0)
  H.eq(baron.pick_rate, nil, 'no offered data: no pick rate')
  -- compute() is unchanged by offered: the same buckets, no new fields.
  local s = stats()
  H.eq(s.runs, 3); H.eq(s.wins, 2)
  H.eq(s.by_joker.j_blueprint.runs, 1); H.eq(s.by_joker.j_blueprint.offered, nil)
  local keys = {}
  for k in pairs(s) do keys[#keys + 1] = k end
  table.sort(keys)
  H.eq(table.concat(keys, ','), 'by_deck,by_joker,by_stake,runs,unfinished,win_rate,wins')
end)

H.test('pick rate: an offered-only joker gets a row; the filter and unfinished runs apply', function()
  local rec, stats = setup()
  assert(rec.save(record('N', {won = false, t = 1, seen = {{'j_joker'}}, final = {'j_joker'},
    offered = {j_egg = 2, j_joker = 1}})))
  -- Seeded (hidden by DEFAULT_FILTER) and unfinished runs add nothing.
  assert(rec.save(record('S', {won = true, t = 2, seeded = true, seen = {{'j_egg'}}, final = {'j_egg'},
    offered = {j_egg = 1}})))
  assert(rec.save(record('U', {t = 3, seen = {{'j_egg'}}, final = {'j_egg'}, offered = {j_egg = 1}})))
  local rows = by_key(stats.jokers(stats.DEFAULT_FILTER))
  local egg = rows.j_egg
  H.ok(egg, 'Egg was only offered, and still has a row')
  H.eq(egg.runs, 0); H.eq(egg.held, 0); H.eq(egg.offered, 1); H.eq(egg.pick_rate, 0)
  H.eq(rows.j_joker.pick_rate, 1)
  local all = by_key(stats.jokers())
  H.eq(all.j_egg.offered, 2, 'no filter: the seeded run too, never the unfinished one')
  H.eq(all.j_egg.picked, 1); H.eq(all.j_egg.pick_rate, 0.5)
  -- A junk offered table (non-numbers, zero counts) is skipped.
  assert(rec.save(record('J', {won = true, t = 4, seen = {}, final = {}, offered = {j_mime = 0, j_dna = 'x', [3] = 1}})))
  local junk = by_key(stats.jokers())
  H.eq(junk.j_mime, nil); H.eq(junk.j_dna, nil)
end)

H.test('the "Pick rate" sort: highest first, ties by name, no data last', function()
  local _, stats = setup()
  local rows = {
    {key = 'j_c', name = 'Zany Joker', runs = 1, pick_rate = 0.5},
    {key = 'j_a', name = 'Abstract Joker', runs = 3, pick_rate = 0.5},
    {key = 'j_b', name = 'Mime', runs = 9, pick_rate = nil},
    {key = 'j_d', name = 'Baron', runs = 0, pick_rate = 1},
    {key = 'j_e', name = 'Egg', runs = 2, pick_rate = 0},
  }
  local out = {}
  for i, r in ipairs(stats.sort_jokers(rows, 'pick_rate')) do out[i] = r.key end
  H.eq(table.concat(out, ','), 'j_d,j_a,j_c,j_e,j_b', 'Baron, then Abstract before Zany, Egg at 0, Mime without data')
end)

H.test('jokers() from real-shaped rows sorts by pick rate with names from name_of', function()
  local rec, stats = setup()
  assert(rec.save(record('A', {won = true, t = 1, seen = {{'j_joker', 'j_mime'}}, final = {'j_joker', 'j_mime'},
    offered = {j_joker = 1, j_mime = 1, j_egg = 1}})))
  assert(rec.save(record('B', {won = false, t = 2, seen = {{}}, final = {}, offered = {j_joker = 1, j_mime = 1}})))
  local names = {j_joker = 'Joker', j_mime = 'Mime', j_egg = 'Egg'}
  local rows = stats.sort_jokers(stats.jokers(), 'pick_rate', function(k) return names[k] end)
  local out = {}
  for i, r in ipairs(rows) do out[i] = r.key..'='..tostring(r.pick_rate) end
  H.eq(table.concat(out, ' '), 'j_joker=0.5 j_mime=0.5 j_egg=0', 'Joker and Mime tie at 50%, by name')
end)
