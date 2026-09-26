-- Finder odds (T-305): seedfinder.engine.sample on real love.thread workers.
--
--   1. Sample 20,000 seeds for a two-clause filter (ante-1 Charm Tag AND the
--      ante-1 Hone voucher) on 4 workers, split in two jobs over one index
--      range: the first 2,000 seeds from SAMPLE_BASE, then the next 18,000.
--   2. Cross-check: odds.sample on the main thread over the same 2,000 seeds
--      (the only main-thread sampling) gives the first job's counts exactly,
--      clause by clause and for the whole filter.
--   3. The two jobs' counts sum to 20,000 seeds, and poll's estimate on the
--      second job and odds.estimate on the summed counts are well formed
--      (rates in 0..1, a bottleneck, expected seeds). Logs the 20k estimate.
--   4. A search's poll reports hits_per_million, equal to the verified hits
--      per million scanned once the scan is done (a fixed 3,000-seed list,
--      tag-only filter, so the re-check rejects nothing).
local engine = require('seedfinder.engine')
local odds = require('seedfinder.odds')

local F = {name = 'Charm + Hone', deck = 'b_red', stake = 1, mode = 'all', clauses = {
  {kind = 'tag', ante = 1, blind = 'any', key = 'tag_charm'},
  {kind = 'voucher', ante = 1, key = 'v_hone'}}}
local CHARM = {name = 'Charm', clauses = {{kind = 'tag', ante = 1, blind = 'any', key = 'tag_charm'}}}

local TOTAL, PREFIX = 20000, 2000
local S = {}

local function poll(ctx, h)
  local p = engine.poll(h)
  ctx.assert(not p.error, 'engine error: '..tostring(p.error))
  return p
end

local function fmt_counts(c)
  return ('n=%d clauses={%s} full=%d'):format(c.n, table.concat(c.clauses, ','), c.full)
end

local function well_formed(ctx, est, what)
  ctx.assert(est, what..': no estimate')
  for i = 1, #F.clauses do
    local r = est.per_clause[i]
    ctx.assert(type(r) == 'number' and r >= 0 and r <= 1, what..': clause '..i..' rate '..tostring(r))
  end
  ctx.assert(est.bottleneck and est.expected_seeds > 0, what..': no bottleneck or expected seeds')
  ctx.assert(est.confidence == 'measured' or est.confidence == 'extrapolated', what..': confidence '..tostring(est.confidence))
end

return {
  {name = 'start samples', run = function(ctx)
    S.base = engine.SAMPLE_BASE
    S.h1 = engine.sample(F, PREFIX, {workers = 4, start = S.base})
    S.h2 = engine.sample(F, TOTAL - PREFIX, {workers = 4, start = S.base + PREFIX})
    S.t0 = love.timer.getTime()
    return true
  end},

  {name = 'samples done', timeout = 90, run = function(ctx)
    local p1, p2 = poll(ctx, S.h1), poll(ctx, S.h2)
    if not (p1.done and p2.done) then return false end
    ctx.assert(p1.scanned == PREFIX and p1.counts.n == PREFIX, 'prefix job sampled '..p1.counts.n)
    ctx.assert(p2.scanned == TOTAL - PREFIX and p2.counts.n == TOTAL - PREFIX, 'rest job sampled '..p2.counts.n)
    ctx.assert(#p1.found == 0 and p1.candidates == 0, 'a sample job reported search hits')
    ctx.log(('workers: %d seeds sampled in %.2f s (two jobs, 4 workers each)'):format(
      p1.counts.n + p2.counts.n, love.timer.getTime() - S.t0))
    S.p1, S.p2 = p1, p2
    return true
  end},

  {name = 'cross-check main thread', timeout = 60, run = function(ctx)
    local seeds = {}
    for i = 1, PREFIX do seeds[i] = engine.seed_at(S.base + i - 1) end
    local t = love.timer.getTime()
    local main = odds.sample(F, seeds)
    local secs = love.timer.getTime() - t
    local w = S.p1.counts
    ctx.log(('prefix %d seeds: workers %s; main thread %s (%.2f s)'):format(PREFIX, fmt_counts(w), fmt_counts(main), secs))
    ctx.assert(main.n == w.n and main.full == w.full and main.mode == w.mode,
      'full-filter counts differ: workers '..fmt_counts(w)..', main '..fmt_counts(main))
    for i = 1, #F.clauses do
      ctx.assert(main.clauses[i] == w.clauses[i], ('clause %d: workers %d, main %d'):format(i, w.clauses[i], main.clauses[i]))
    end
    ctx.assert(main.clauses[1] > 0 and main.clauses[2] > 0, 'degenerate clauses: '..fmt_counts(main))
    ctx.assert(main.clauses[1] < PREFIX and main.clauses[2] < PREFIX, 'degenerate clauses: '..fmt_counts(main))
    well_formed(ctx, S.p1.estimate, 'prefix estimate')
    ctx.log(('check: finder_odds workers equal main thread (%d seeds, clauses %d/%d, full %d)'):format(
      PREFIX, main.clauses[1], main.clauses[2], main.full))
    return true
  end},

  {name = 'combined estimate', run = function(ctx)
    local a, b = S.p1.counts, S.p2.counts
    local sum = {n = a.n + b.n, mode = a.mode, full = a.full + b.full, clauses = {}}
    for i = 1, #F.clauses do sum.clauses[i] = a.clauses[i] + b.clauses[i] end
    ctx.assert(sum.n == TOTAL, 'summed n '..sum.n)
    well_formed(ctx, S.p2.estimate, 'rest estimate')
    local est = odds.estimate(sum)
    well_formed(ctx, est, '20k estimate')
    ctx.log(('20k estimate: %s; per clause %.4f / %.4f, independent %.5f, joint %s, expected seeds %.1f, bottleneck %d, %s'):format(
      fmt_counts(sum), est.per_clause[1], est.per_clause[2], est.independent,
      est.joint and ('%.5f'):format(est.joint) or 'nil', est.expected_seeds, est.bottleneck, est.confidence))
    S.search_seeds = {}
    for i = 1, 3000 do S.search_seeds[i] = engine.seed_at(4000000 + i) end
    S.h3 = engine.start(CHARM, {workers = 2, seeds = S.search_seeds})
    return true
  end},

  {name = 'search hits_per_million', timeout = 30, run = function(ctx)
    local p = poll(ctx, S.h3)
    ctx.assert(type(p.hits_per_million) == 'number', 'poll has no hits_per_million')
    if not p.done then return false end
    ctx.assert(p.scanned == #S.search_seeds and p.rejected == 0, 'search: scanned '..p.scanned..', rejected '..p.rejected)
    ctx.assert(#p.found > 0, 'search found nothing')
    local want = #p.found * 1e6 / p.scanned
    ctx.assert(math.abs(p.hits_per_million - want) < 1e-6,
      ('hits_per_million %.3f, want %.3f'):format(p.hits_per_million, want))
    ctx.log(('check: finder_odds search reports hits_per_million (%d hits in %d seeds = %.1f per million)'):format(
      #p.found, p.scanned, p.hits_per_million))
    return true
  end},

  {name = 'workers exit', timeout = 5, run = function(ctx)
    return engine.alive(S.h1) == 0 and engine.alive(S.h2) == 0 and engine.alive(S.h3) == 0
  end},
}
