-- Finder engine (T-112): seedfinder.engine on real love.thread workers.
--
--   1. Projection: the STR_PACK blob the workers get; logs its size and how
--      many numbers STR_PACK's %.14g rounding changed: none in centers, tags
--      or cards, and in blinds only colours (which no generation reads).
--   2. Charm Tag + Soul (ante-1 Charm Tag, a Soul in its Mega Arcana) on 4
--      workers for 8 s over the random-start seed sequence: logs the rate as
--      "finder rate: <N> seeds/s" (gate >= 2000). Every reported hit is
--      re-evaluated here with filter.eval_seed; the engine's own counters must
--      account for every candidate.
--   3. Cancel that scan mid-flight: 1 s later no worker thread is running.
--   4. Re-check guard: the workers run a looser filter (the Charm Tag alone)
--      while the handle's filter is Charm Tag + Soul, over 3,000 fixed seeds.
--      Candidates without the Soul must be rejected on the main thread and
--      never reach `found`; found = exactly the candidates the main thread
--      accepts.
--   5. Tag-only on 1 worker vs the main thread's own eval over the same 2,000
--      seeds: identical hit sets (and nothing rejected). Then the same for a
--      Zodiac Deck (starting vouchers), stake 8 filter over 600 seeds.
local engine = require('seedfinder.engine')
local filter = require('seedfinder.filter')

local CHARM_SOUL = {name = 'Charm Soul', clauses = {
  {kind = 'tag', ante = 1, blind = 'any', key = 'tag_charm'},
  {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true}}}
local CHARM = {name = 'Charm', clauses = {{kind = 'tag', ante = 1, blind = 'any', key = 'tag_charm'}}}

local DECK = {name = 'Zodiac stake 8', deck = 'b_zodiac', stake = 8, mode = 'any', clauses = {
  {kind = 'voucher', ante = 1, key = 'v_hone'},
  {kind = 'shop_joker', ante = 1, key = 'j_joker', rerolls = 1}}}

local SCAN_SECS = 8
local S = {}

local function set_of(list)
  local s, n = {}, 0
  for _, v in ipairs(list) do if not s[v] then s[v], n = true, n + 1 end end
  return s, n
end

local function same_set(a, b)
  local sa, na = set_of(a)
  local sb, nb = set_of(b)
  if na ~= nb then return false end
  for k in pairs(sa) do if not sb[k] then return false end end
  return true
end

local function seeds_from(base, n)
  local out = {}
  for i = 1, n do out[i] = engine.seed_at(base + i) end
  return out
end

-- Polls h; fails the step on an engine error.
local function poll(ctx, h)
  local p = engine.poll(h)
  ctx.assert(not p.error, 'engine error: '..tostring(p.error))
  return p
end

-- Counts numbers STR_PACK changed: the unpacked projection against the live tables.
local function inexact(a, b, path, out, seen)
  if seen[a] then return end
  seen[a] = true
  for k, v in pairs(a) do
    local w = b[k]
    if type(v) == 'number' and type(w) == 'number' and v ~= w then
      out[#out + 1] = path..'.'..tostring(k)
    elseif type(v) == 'table' and type(w) == 'table' then
      inexact(v, w, path..'.'..tostring(k), out, seen)
    end
  end
end

return {
  {name = 'projection', run = function(ctx)
    local t = love.timer.getTime()
    local blob = engine.projection()
    local ms = (love.timer.getTime() - t) * 1000
    local d = STR_UNPACK(blob)
    ctx.assert(d.pools.Tag and #d.pools.Tag == #G.P_CENTER_POOLS.Tag, 'Tag pool missing from projection')
    ctx.assert(d.template and d.template.bosses_used, 'init_game_object template missing')
    local bad = {}
    inexact(d.centers, G.P_CENTERS, 'P_CENTERS', bad, {})
    inexact(d.tags, G.P_TAGS, 'P_TAGS', bad, {})
    inexact(d.cards, G.P_CARDS, 'P_CARDS', bad, {})
    local bad_blinds = {}
    inexact(d.blinds, G.P_BLINDS, 'P_BLINDS', bad_blinds, {})
    ctx.log(('projection: %d bytes, built in %.1f ms; numbers changed by STR_PACK: %d in centers/tags/cards%s, %d in blinds%s'):format(
      #blob, ms, #bad, bad[1] and (' (e.g. '..bad[1]..')') or '', #bad_blinds,
      bad_blinds[1] and (' (e.g. '..bad_blinds[1]..')') or ''))
    ctx.assert(#bad == 0, 'STR_PACK changed '..#bad..' center/tag/card numbers, e.g. '..tostring(bad[1]))
    for _, path in ipairs(bad_blinds) do
      ctx.assert(path:find('colour', 1, true), 'STR_PACK changed a blind number the sim may read: '..path)
    end
    return true
  end},

  {name = 'start charm soul', run = function(ctx)
    S.h = engine.start(CHARM_SOUL, {workers = 4})
    S.t0 = love.timer.getTime()
    return true
  end},

  {name = 'scan 8 s', timeout = SCAN_SECS + 20, run = function(ctx)
    local p = poll(ctx, S.h)
    if love.timer.getTime() - S.t0 < SCAN_SECS then return false end
    ctx.assert(not p.done, 'the 8 s scan ended on its own; the cancel check needs it running')
    ctx.assert(p.workers == 4, 'expected 4 workers, got '..p.workers)
    ctx.log(('charm soul: %d seeds in %.2f s on 4 workers, %d candidates, %d verified, %d rejected, %d pending'):format(
      p.scanned, love.timer.getTime() - S.t0, p.candidates, #p.found, p.rejected, p.pending))
    ctx.log(('finder rate: %d seeds/s'):format(math.floor(p.rate)))
    ctx.assert(p.rate >= 2000, 'rate '..math.floor(p.rate)..' < 2000 seeds/s')
    ctx.assert(#p.found > 0, 'no Charm + Soul hits in '..p.scanned..' seeds')
    ctx.assert(p.candidates == #p.found + p.rejected + p.pending, 'candidates unaccounted for')
    ctx.assert(p.rejected == 0, p.rejected..' worker hits failed the main-thread re-check (worker != main)')
    for i, seed in ipairs(p.found) do
      local ok, det = filter.eval_seed(CHARM_SOUL, seed)
      ctx.assert(ok, 'reported hit '..seed..' fails filter.eval_seed')
      local r = det.results[2]
      if i <= 5 then ctx.log(('hit %s: %s tag, Soul at slot %d of %s'):format(seed, r.blind, r.index, r.pack)) end
    end
    S.first = p
    -- Cancel mid-scan.
    engine.cancel(S.h)
    S.tc = love.timer.getTime()
    S.scanned_at_cancel = p.scanned
    return true
  end},

  {name = 'cancel', timeout = 10, run = function(ctx)
    if love.timer.getTime() - S.tc < 1 then return false end
    local alive = engine.alive(S.h)
    local p = engine.poll(S.h)
    ctx.assert(p.done, 'handle not done after cancel')
    ctx.assert(alive == 0, alive..' worker threads still running 1 s after cancel')
    ctx.assert(#p.found == #S.first.found and p.pending == 0, 'hits changed after cancel')
    ctx.log(('check: cancel stops workers (cancelled at %d seeds of %d, 0 of 4 threads alive %.1f s later)'):format(
      S.scanned_at_cancel, p.total, love.timer.getTime() - S.tc))
    ctx.log(('check: hits rechecked on main thread (8 s scan: %d of %d candidates verified, each re-evaluated again here)'):format(
      #S.first.found, S.first.candidates))
    S.guard_seeds = seeds_from(1000000, 3000)
    S.h2 = engine.start(CHARM_SOUL, {workers = 2, seeds = S.guard_seeds, worker_filter = CHARM})
    return true
  end},

  {name = 'recheck guard', timeout = 30, run = function(ctx)
    local p = poll(ctx, S.h2)
    if not p.done then return false end
    ctx.assert(p.scanned == #S.guard_seeds, 'scanned '..p.scanned..' of '..#S.guard_seeds)
    local want = {}
    for _, seed in ipairs(S.h2.reported) do
      if filter.eval_seed(CHARM_SOUL, seed) then want[#want + 1] = seed end
    end
    ctx.assert(p.rejected > 0, 'the loose worker filter produced no rejects; the guard proves nothing')
    ctx.assert(p.candidates == #S.h2.reported and p.candidates == #p.found + p.rejected,
      'candidates unaccounted for')
    ctx.assert(same_set(p.found, want), ('found %d, main thread accepts %d of the candidates'):format(#p.found, #want))
    ctx.log(('check: hits rechecked on main thread (guard: workers ran Charm Tag only, %d candidates, %d rejected, %d reported = main-thread Charm + Soul)'):format(
      p.candidates, p.rejected, #p.found))
    S.eq_seeds = seeds_from(2000000, 2000)
    S.h3 = engine.start(CHARM, {workers = 1, seeds = S.eq_seeds})
    return true
  end},

  {name = 'worker equals main', timeout = 30, run = function(ctx)
    local p = poll(ctx, S.h3)
    if not p.done then return false end
    ctx.assert(p.scanned == 2000, 'scanned '..p.scanned)
    local t = love.timer.getTime()
    local main = {}
    for _, seed in ipairs(S.eq_seeds) do
      if filter.eval_seed(CHARM, seed) then main[#main + 1] = seed end
    end
    local secs = love.timer.getTime() - t
    ctx.assert(#main > 0 and #main < 2000, 'degenerate tag filter: '..#main..' hits')
    ctx.assert(p.rejected == 0, p.rejected..' worker hits rejected by the main thread')
    ctx.assert(same_set(S.h3.reported, main), ('worker %d hits, main thread %d'):format(#S.h3.reported, #main))
    ctx.assert(same_set(p.found, main), 'found differs from the main thread')
    ctx.log(('check: worker equals main thread (tag-only, 2000 seeds, %d hits both sides; main thread %d seeds/s)'):format(
      #main, math.floor(2000 / secs)))
    ctx.assert(engine.alive(S.h3) <= 1, 'worker count')
    S.deck_seeds = seeds_from(3000000, 600)
    S.h4 = engine.start(DECK, {workers = 2, seeds = S.deck_seeds})
    return true
  end},

  -- Beyond the gate: a voucher deck at stake 8 exercises Back:apply_to_run and
  -- Card.apply_to_run in the thread, the stake rules, shops and stickers.
  {name = 'deck + stake worker equals main', timeout = 30, run = function(ctx)
    local p = poll(ctx, S.h4)
    if not p.done then return false end
    local main = {}
    for _, seed in ipairs(S.deck_seeds) do
      if filter.eval_seed(DECK, seed) then main[#main + 1] = seed end
    end
    ctx.assert(#main > 0 and #main < #S.deck_seeds, 'degenerate deck filter: '..#main..' hits')
    ctx.assert(p.rejected == 0 and same_set(S.h4.reported, main),
      ('Zodiac stake 8: worker %d hits (%d rejected), main thread %d'):format(#S.h4.reported, p.rejected, #main))
    ctx.log(('deck check: Zodiac Deck stake 8 (voucher or shop joker), %d seeds, %d hits both sides'):format(
      #S.deck_seeds, #main))
    return true
  end},

  {name = 'workers exit', timeout = 5, run = function(ctx)
    return engine.alive(S.h2) == 0 and engine.alive(S.h3) == 0 and engine.alive(S.h4) == 0
  end},
}
