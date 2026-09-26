-- RunJournal same-seed comparison (T-330): stats.by_seed groups the seeds played more
-- than once, stats.compare lines two runs up ante by ante. Synthetic records through
-- recorder.save; nothing here runs the game.
local H = ...

local function setup()
  love.filesystem.createDirectory('1')
  RunJournal = {}
  return require('runjournal.recorder'), require('runjournal.stats')
end

local function hand(name, score) return {hand = name, chips = score, mult = 1, score = score} end

local function blind(kind, won, hands, skipped)
  local b = {kind = kind, key = 'bl_'..kind:lower(), skipped = skipped or false, hands = hands or {}}
  if not skipped then b.won = won end
  return b
end

-- An ante that was cleared: Small, Big, Boss won, one hand each.
local function cleared(dollars, best)
  return {dollars_start = 4, dollars_end = dollars, blinds = {
    blind('Small', true, {hand('Pair', 40)}),
    blind('Big', true, {hand('High Card', 10), hand(best or 'Flush', 200)}),
    blind('Boss', true, {hand('Two Pair', 90)}),
  }}
end

local function record(seed, t, antes, won)
  return {run_id = seed..':'..t, seed = seed, deck = 'b_red', stake = 1, started_at = t,
    ended_at = won ~= nil and t + 100 or nil, won = won, final_ante = #antes, final_round = 3 * #antes,
    antes = antes, jokers_seen = {}, origin = {}}
end

H.test('by_seed keeps only seeds with two or more runs, oldest run first', function()
  local rec, stats = setup()
  assert(rec.save(record('AAA', 10, {cleared(10)}, false)))
  assert(rec.save(record('BBB', 20, {cleared(10)}, false)))
  assert(rec.save(record('AAA', 30, {cleared(10)}, false)))
  assert(rec.save(record('CCC', 40, {cleared(10)}, false)))
  assert(rec.save(record('AAA', 25, {cleared(10)})))  -- unfinished counts too
  local g = stats.by_seed()
  H.eq(#g, 1, 'one repeated seed')
  H.eq(g[1].seed, 'AAA')
  H.eq(#g[1].runs, 3)
  H.eq(g[1].runs[1].run_id, 'AAA:10'); H.eq(g[1].runs[2].run_id, 'AAA:25'); H.eq(g[1].runs[3].run_id, 'AAA:30')
end)

H.test('by_seed orders groups newest first and takes any list', function()
  local _, stats = setup()
  local list = {
    {run_id = 'X:1', seed = 'X', started_at = 1}, {run_id = 'Y:2', seed = 'Y', started_at = 2},
    {run_id = 'X:5', seed = 'X', started_at = 5}, {run_id = 'Y:9', seed = 'Y', started_at = 9},
    {run_id = 'Z:3', seed = 'Z', started_at = 3}, {run_id = '?:4', started_at = 4},
  }
  local g = stats.by_seed(list)
  H.eq(#g, 2)
  H.eq(g[1].seed, 'Y', 'Y was played last'); H.eq(g[2].seed, 'X')
  H.eq(g[1].runs[1].started_at, 2)
  H.eq(#stats.by_seed({}), 0, 'empty list')
  H.eq(#stats.by_seed(), 0, 'empty journal')
end)

H.test('compare: per-ante dollars and best hand', function()
  local _, stats = setup()
  local a = record('S', 1, {cleared(12, 'Flush'), cleared(30, 'Straight')}, false)
  local b = record('S', 2, {cleared(15, 'Full House')}, false)
  a.antes[2].blinds[2].hands[2].score = 500
  local c = assert(stats.compare(a, b))
  H.eq(#c.rows, 2)
  local r1, r2 = c.rows[1], c.rows[2]
  H.eq(r1.ante, 1); H.eq(r1.dollars_a, 12); H.eq(r1.dollars_b, 15)
  H.eq(r1.best_hand_a, 'Flush'); H.eq(r1.best_hand_b, 'Full House')
  H.eq(r1.best_score_a, 200); H.eq(r1.outcome_a, 'won'); H.eq(r1.outcome_b, 'won')
  H.eq(r2.ante, 2); H.eq(r2.dollars_a, 30); H.eq(r2.dollars_b, nil, 'b never reached ante 2')
  H.eq(r2.best_hand_a, 'Straight'); H.eq(r2.best_score_a, 500)
  H.eq(r2.best_hand_b, nil); H.eq(r2.outcome_b, nil)
  H.eq(c.diverge, 2)
end)

H.test('compare: the first ante won by one run and lost by the other diverges', function()
  local _, stats = setup()
  local lost2 = {dollars_start = 10, dollars_end = 10, blinds = {blind('Small', false, {hand('Pair', 30)})}}
  local lost3 = {dollars_start = 20, dollars_end = 21, blinds = {blind('Small', false, {hand('Pair', 30)})}}
  local a = record('S', 1, {cleared(10), lost2}, false)
  local b = record('S', 2, {cleared(10), cleared(20), lost3}, false)
  local c = assert(stats.compare(a, b))
  H.eq(#c.rows, 3)
  H.eq(c.rows[1].outcome_a, 'won'); H.eq(c.rows[1].outcome_b, 'won')
  H.eq(c.rows[2].outcome_a, 'lost'); H.eq(c.rows[2].outcome_b, 'won')
  H.eq(c.rows[3].outcome_a, nil); H.eq(c.rows[3].outcome_b, 'lost')
  H.eq(c.diverge, 2)
  H.eq(stats.compare(b, a).diverge, 2, 'symmetric')
end)

H.test('compare: identical runs never diverge; skips and open antes', function()
  local _, stats = setup()
  local skipped = {dollars_start = 10, dollars_end = 18, blinds = {
    blind('Small', nil, {}, true), blind('Big', true, {hand('Flush', 120)})}}
  local a = record('S', 1, {cleared(10), skipped})
  local b = record('S', 2, {cleared(10), cleared(18)})
  local c = assert(stats.compare(a, a))
  H.eq(c.diverge, nil)
  local d = assert(stats.compare(a, b))
  H.eq(d.rows[2].outcome_a, 'open', 'a skip is not a loss; no boss yet')
  H.eq(d.rows[2].best_hand_a, 'Flush')
  H.eq(d.diverge, 2)
  -- An ante entry without blinds (ante_change after the last boss) makes no row.
  a.antes[3] = {dollars_start = 30, blinds = {}}
  H.eq(#assert(stats.compare(a, a)).rows, 2)
end)

H.test('compare reads run ids through the recorder and reports missing runs', function()
  local rec, stats = setup()
  assert(rec.save(record('R', 1, {cleared(10)}, false)))
  assert(rec.save(record('R', 2, {cleared(11)}, false)))
  local c = assert(stats.compare('R:1', 'R:2'))
  H.eq(c.rows[1].dollars_a, 10); H.eq(c.rows[1].dollars_b, 11)
  local none, err = stats.compare('R:1', 'R:404')
  H.eq(none, nil)
  H.ok(err and err:find('run b'), 'error names the missing run: '..tostring(err))
  -- by_seed's entries go straight into compare.
  local g = stats.by_seed()
  H.eq(#g, 1)
  H.eq(assert(stats.compare(g[1].runs[1].run_id, g[1].runs[2].run_id)).rows[1].dollars_b, 11)
end)

H.test('the same-seed helpers do not write to the journal', function()
  local rec, stats = setup()
  assert(rec.save(record('W', 1, {cleared(10)}, false)))
  assert(rec.save(record('W', 2, {cleared(10)}, false)))
  local n, orig = 0, love.filesystem.write
  love.filesystem.write = function(...) n = n + 1; return orig(...) end
  stats.by_seed(); stats.compare('W:1', 'W:2')
  love.filesystem.write = orig
  H.eq(n, 0)
end)
