-- RunJournal hunt outcomes (T-331): stats.by_filter groups the runs the Seed Finder
-- started by origin.filter_name. Synthetic records through recorder.save; nothing
-- here runs the game.
local H = ...

local function setup()
  love.filesystem.createDirectory('1')
  RunJournal = {}
  return require('runjournal.recorder'), require('runjournal.stats')
end

-- A record started at t from `filter` (nil: no Finder origin). won: true / false
-- (finished) or nil (unfinished).
local function record(seed, t, filter, ante, won)
  return {run_id = seed..':'..t, seed = seed, deck = 'b_red', stake = 1, started_at = t,
    ended_at = won ~= nil and t + 100 or nil, won = won, final_ante = ante, final_round = 3 * ante,
    antes = {}, jokers_seen = {}, origin = {filter_name = filter}}
end

H.test('by_filter groups finished runs per filter name', function()
  local rec, stats = setup()
  assert(rec.save(record('A', 10, 'Blueprint by 2', 3, true)))
  assert(rec.save(record('B', 20, 'Blueprint by 2', 1, false)))
  assert(rec.save(record('C', 30, nil, 5, true)))            -- no origin: not a hunt
  local g = stats.by_filter()
  H.eq(#g, 1, 'one filter')
  local h = g[1]
  H.eq(h.filter_name, 'Blueprint by 2')
  H.eq(h.runs, 2); H.eq(h.wins, 1); H.eq(h.win_rate, 0.5)
  H.eq(h.best_ante, 3); H.eq(h.avg_ante, 2)
  H.eq(h.newest, 20, 'the newest run started at 20')
  H.eq(h.unfinished, 0)
end)

H.test('by_filter orders by win rate, then runs, newest, name', function()
  local _, stats = setup()
  local list = {
    record('A', 1, 'Low', 2, false), record('B', 2, 'Low', 2, false),
    record('C', 3, 'High', 8, true),
    record('D', 4, 'Half', 4, true), record('E', 5, 'Half', 2, false),
    record('F', 6, 'Half2', 4, true), record('G', 7, 'Half2', 2, false),
    record('H', 8, 'Half2', 3, true), record('I', 9, 'Half2', 1, false),
    record('J', 1, 'Zed', 1, false), record('K', 2, 'Alpha', 1, false),
  }
  local g = stats.by_filter(list)
  local names = {}
  for i, x in ipairs(g) do names[i] = x.filter_name end
  H.eq(table.concat(names, ','), 'High,Half2,Half,Low,Alpha,Zed')
end)

H.test('by_filter: unfinished runs count apart; avg over finished only', function()
  local _, stats = setup()
  local g = stats.by_filter({
    record('A', 1, 'F', 2, true), record('B', 2, 'F', 4, false),
    record('C', 9, 'F', 6, nil),                               -- in progress, deepest
  })
  H.eq(#g, 1)
  H.eq(g[1].runs, 2); H.eq(g[1].unfinished, 1)
  H.eq(g[1].avg_ante, 3, 'finished runs only')
  H.eq(g[1].best_ante, 6, 'any run reached ante 6')
  H.eq(g[1].newest, 9)
  local only = stats.by_filter({record('D', 1, 'G', 2, nil)})
  H.eq(only[1].runs, 0); H.eq(only[1].win_rate, 0); H.eq(only[1].avg_ante, nil)
end)

H.test('by_filter reads the origin from the record for index entries', function()
  local rec, stats = setup()
  assert(rec.save(record('A', 10, 'Hunt', 3, true)))
  assert(rec.save(record('B', 20, nil, 2, false)))
  local entries = rec.list()
  H.eq(entries[1].origin, nil, 'index entries carry no origin')
  local g = stats.by_filter(entries)
  H.eq(#g, 1); H.eq(g[1].filter_name, 'Hunt'); H.eq(g[1].wins, 1)
  -- A record gone from disk is skipped, not an error.
  local ghost = {run_id = 'Z:1', seed = 'Z', started_at = 1, ended_at = 2, won = true, final_ante = 9}
  entries[#entries + 1] = ghost
  H.eq(#stats.by_filter(entries), 1)
  H.eq(stats.by_filter(entries)[1].best_ante, 3)
end)

H.test('by_filter ignores blank names and bad rows; empty journal is empty', function()
  local _, stats = setup()
  local blank = record('A', 1, '', 2, true)
  local bad = record('B', 2, nil, 2, true); bad.origin = {filter_name = 42}
  H.eq(#stats.by_filter({blank, bad, 'junk', {}}), 0)
  H.eq(#stats.by_filter({}), 0, 'empty list')
  H.eq(#stats.by_filter(), 0, 'empty journal')
end)

H.test('a saved record without origin is no hunt, set_origin pending or not', function()
  local rec, stats = setup()
  -- set_origin copies only filter_name into the next new record's origin.
  rec.set_origin({filter_name = 'Live', other = 1})
  local r = record('L', 5, nil, 2, false)
  r.origin = nil
  assert(rec.save(r))
  H.eq(#stats.by_filter(), 0, 'save() does not consume set_origin')
  rec.set_origin(nil)
end)

H.test('by_filter does not write to the journal', function()
  local rec, stats = setup()
  assert(rec.save(record('W', 1, 'F', 2, true)))
  local n, orig = 0, love.filesystem.write
  love.filesystem.write = function(...) n = n + 1; return orig(...) end
  stats.by_filter()
  love.filesystem.write = orig
  H.eq(n, 0)
end)
