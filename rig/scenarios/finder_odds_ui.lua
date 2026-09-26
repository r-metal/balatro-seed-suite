-- Finder Odds UI (T-306): the Search panel's Odds button and hits per million.
--   1. Main menu -> Options -> Seed Finder. The filter is set by code
--      (ui.set_filter): ante-1 Charm Tag (any blind) AND the ante-1 Hone voucher,
--      Red Deck, stake 1 (finder_odds' filter: about 1 hit in 80 seeds).
--   2. Odds: a 20,000-seed sample on the workers. Once done, the first Odds line
--      holds "about 1 in N seeds", N being odds.estimate on the engine's own
--      counts (ui.odds().counts) rounded by the T-306 rule (two significant
--      digits, K/M/B; this file's own copy of the rule), and the second names
--      the bottleneck clause by its generated label, "(extrapolated)" exactly
--      when the estimate says so. The overlay keeps its x extent.
--      -> "check: odds line shows the engine's estimate" (shot odds_shown)
--   3. The match cycle goes to Any clause (a real click): the Odds lines clear.
--      -> "check: odds line clears on a filter change" (shot odds_cleared)
--   4. A clause that can't pass (Negative Tag at ante 1: its min_ante is 2):
--      Odds says "clause 2 never passed in 20,000 seeds: it may be impossible or
--      locked" (the sentence over its two lines) and names Negative Tag.
--      -> "check: never-passing clause named" (shot odds_never)
--   5. Back to the Charm + Hone filter, Start: while the search runs, the stats
--      row's Per M shows a positive figure (shot per_million); once it stops by
--      itself at 64 hits, Per M is engine.poll's hits_per_million (to display
--      rounding). -> "check: stats row shows hits per million"
-- No scan on this thread: the sample and the search run on the Finder's workers.
local ui = require('seedfinder.ui')
local odds = require('seedfinder.odds')
local engine = require('seedfinder.engine')

local F = {name = 'Charm + Hone', deck = 'b_red', stake = 1, all_unlocked = false, mode = 'all', clauses = {
  {kind = 'tag', ante = 1, blind = 'any', key = 'tag_charm'},
  {kind = 'voucher', ante = 1, key = 'v_hone'}}}
local NEVER = {name = 'Charm + Negative', deck = 'b_red', stake = 1, all_unlocked = false, mode = 'all', clauses = {
  {kind = 'tag', ante = 1, blind = 'any', key = 'tag_charm'},
  {kind = 'tag', ante = 1, blind = 'any', key = 'tag_negative'}}}

local S = {samples = {}}

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU ~= true and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function text_of(id)
  local node = uie(id)
  if not node then return nil end
  if node.config.ref_table then return tostring(node.config.ref_table[node.config.ref_value]) end
  return tostring(node.config.text)
end

-- The T-306 reading rule: below 100 the whole number; above, two significant
-- digits, then the largest of K, M, B the rounded figure reaches.
local function reading(n)
  if n < 100 then return tostring(math.floor(n + 0.5)) end
  local mag = 10 ^ (math.floor(math.log10(n)) - 1)
  local r = math.floor(n / mag + 0.5) * mag
  local x, suffix = r, ''
  if r >= 1e9 then x, suffix = r / 1e9, 'B' elseif r >= 1e6 then x, suffix = r / 1e6, 'M'
  elseif r >= 1e3 then x, suffix = r / 1e3, 'K' end
  local s = x >= 10 and ('%d'):format(math.floor(x + 0.5)) or ('%.1f'):format(x):gsub('%.0$', '')
  return s..suffix
end

-- The overlay's x extent (as finder_ui's check_fits reads it).
local function extent()
  local root = G.OVERLAY_MENU.UIRoot.children[1]
  return root.T.x, root.T.x + root.T.w
end

local function same_extent(ctx, label)
  local x1, x2 = extent()
  ctx.log(('layout %s: overlay x %.2f..%.2f'):format(label, x1, x2))
  ctx.assert(math.abs(x1 - S.x1) <= 0.01 and math.abs(x2 - S.x2) <= 0.01, ('%s: overlay x %.2f..%.2f, was %.2f..%.2f')
    :format(label, x1, x2, S.x1, S.x2))
end

local function click(label, button, id, wait)
  return {name = label, timeout = 10, run = function(ctx)
    if wait and not wait() then return false end
    if G.CONTROLLER.locks.frame then return false end
    return ctx.click(button, id)
  end}
end

-- Sets f as the filter being edited and waits for the filter panel to show it.
local function set_filter(label, f)
  return {name = label, timeout = 5, run = function(ctx)
    if not S.set then
      ctx.assert(ui.set_filter(f))
      S.set = true
      return false
    end
    local cur = ui.current()
    if ctx.step_time() < 0.5 or not uie('seedfinder_c2_kind_r') then return false end
    ctx.assert(#cur.clauses == 2 and cur.clauses[2].key == f.clauses[2].key, label..': the filter was not set')
    ctx.assert(ui.odds() == nil, label..': odds of another filter still shown')
    S.set = nil
    return true
  end}
end

-- Presses Odds and waits for the sample to finish and its lines to be drawn.
local function odds_done(label)
  return {name = label, timeout = 90, run = function(ctx)
    local o = ui.odds()
    ctx.assert(o, label..': no odds job')
    ctx.assert(not o.err, label..': odds failed: '..tostring(o.err))
    if not o.done or ctx.step_time() < 0.3 or not text_of('seedfinder_odds_1') then return false end
    if text_of('seedfinder_odds_1'):find('Sampling', 1, true) then return false end
    S.samples[#S.samples + 1] = o.sample
    return true
  end}
end

return {
  click('open options', 'options'),
  click('open finder', 'seedfinder_open', nil, function() return G.OVERLAY_MENU end),
  {name = 'finder open', timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 1 then return false end
    return true
  end},
  set_filter('charm + hone', F),
  {name = 'extent before odds', run = function(ctx)
    S.x1, S.x2 = extent()
    ctx.log(('layout before odds: overlay x %.2f..%.2f'):format(S.x1, S.x2))
    ctx.assert(uie('seedfinder_odds') and not uie('seedfinder_odds_1'), 'the Odds box shows a line before Odds')
    return true
  end},
  click('odds', 'seedfinder_odds'),
  odds_done('odds done'),
  {name = 'odds line shows the estimate', run = function(ctx)
    local o = ui.odds()
    ctx.assert(o.counts and o.counts.n == 20000, 'sampled '..tostring(o.counts and o.counts.n)..' seeds, not 20,000')
    local est = assert(odds.estimate(o.counts))
    local l1, l2 = text_of('seedfinder_odds_1'), text_of('seedfinder_odds_2') or ''
    ctx.log(('counts n=%d clauses={%s} full=%d; expected seeds %.2f, bottleneck %d, %s'):format(o.counts.n,
      table.concat(o.counts.clauses, ','), o.counts.full, est.expected_seeds, est.bottleneck, est.confidence))
    ctx.log('odds line 1: '..l1)
    ctx.log('odds line 2: '..l2)
    local want = 'about 1 in '..reading(est.expected_seeds)..' seeds'
    ctx.assert(l1:find(want, 1, true), 'odds line "'..l1..'" lacks "'..want..'"')
    ctx.assert(l1:find('/s', 1, true) and (l1:find(', ~', 1, true) or l1:find(', under 1 s', 1, true)),
      'odds line "'..l1..'" has no time at a rate')
    ctx.assert(l2:find('bottleneck: clause '..est.bottleneck, 1, true), 'no bottleneck in "'..l2..'"')
    local label = est.bottleneck == 2 and 'Hone' or 'Charm Tag'
    ctx.assert(l2:find(label, 1, true), 'bottleneck label "'..label..'" not in "'..l2..'"')
    ctx.assert((l2:find('(extrapolated)', 1, true) ~= nil) == (est.confidence == 'extrapolated'),
      '"(extrapolated)" shown for a '..est.confidence..' estimate')
    same_extent(ctx, 'odds shown')
    ctx.shot('odds_shown')
    ctx.log('check: odds line shows the engine\'s estimate')
    return true
  end},
  -- The next frame: the shot is taken at the end of the frame above.
  {name = 'change filter', timeout = 5, run = function(ctx)
    if G.CONTROLLER.locks.frame then return false end
    return ctx.click('seedfinder_cycle', 'seedfinder_mode_r')
  end},
  {name = 'odds line clears', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(ui.current().mode == 'any', 'the match cycle did not change the filter')
    ctx.assert(ui.odds() == nil, 'ui.odds() survives a filter change')
    ctx.assert(uie('seedfinder_odds') and not uie('seedfinder_odds_1') and not uie('seedfinder_odds_2'),
      'the Odds lines are still drawn after a filter change')
    same_extent(ctx, 'odds cleared')
    ctx.shot('odds_cleared')
    ctx.log('check: odds line clears on a filter change')
    return true
  end},
  set_filter('charm + negative', NEVER),
  click('odds, impossible clause', 'seedfinder_odds'),
  odds_done('odds done, impossible clause'),
  {name = 'never-passing clause named', run = function(ctx)
    -- The sentence runs over the two lines; joined, it reads whole.
    local l = text_of('seedfinder_odds_1')..' '..tostring(text_of('seedfinder_odds_2'))
    ctx.log('odds lines: '..l)
    ctx.assert(ui.odds().counts.clauses[2] == 0, 'Negative Tag passed at ante 1')
    local want = 'clause 2 never passed in 20,000 seeds: it may be impossible or locked'
    ctx.assert(l:find(want, 1, true) and l:find('Negative Tag', 1, true),
      'odds lines "'..l..'" lack "'..want..'" and the clause label')
    same_extent(ctx, 'odds never')
    ctx.shot('odds_never')
    ctx.log('check: never-passing clause named')
    return true
  end},
  set_filter('charm + hone again', F),
  click('start', 'seedfinder_start'),
  {name = 'per million while searching', timeout = 60, run = function(ctx)
    local s = ui.search()
    -- The first frame with seeds scanned, while the search still runs (it stops by
    -- itself at 64 hits, a few thousand seeds in).
    if not (s and s.scanned > 0) then return false end
    ctx.assert(s.running, 'the search ended before the first frame that showed seeds scanned')
    local shown = text_of('seedfinder_hpm')
    local v = tonumber(((shown or ''):gsub(',', '')))
    ctx.assert(v and v > 0 and v <= 1e6, 'Per M shows "'..tostring(shown)..'" while running, '..s.scanned..' scanned')
    ctx.log(('search running: %d scanned, %d verified hits, Per M "%s"'):format(s.scanned, #s.found, shown))
    ctx.shot('per_million')
    return true
  end},
  -- Once the search stops (64 hits), Per M is the engine's final figure.
  {name = 'per million when done', timeout = 60, run = function(ctx)
    local s = ui.search()
    if s.running or ctx.step_time() < 0.3 then return false end
    local p = engine.poll(s.handle)
    local shown = text_of('seedfinder_hpm')
    local v = tonumber(((shown or ''):gsub(',', '')))
    ctx.log(('search done: %d scanned, %d hits, Per M "%s", engine %.2f'):format(s.scanned, #s.found, shown,
      p.hits_per_million))
    ctx.assert(p.done and v and math.abs(v - p.hits_per_million) <= math.max(1, 0.001 * p.hits_per_million),
      ('Per M "%s", engine %.2f'):format(tostring(shown), p.hits_per_million))
    ctx.log('check: stats row shows hits per million')
    return true
  end},
  {name = 'workers exit', timeout = 5, run = function(ctx)
    local s = ui.search()
    if s.running or engine.alive(s.handle) > 0 then return false end
    for _, h in ipairs(S.samples) do if engine.alive(h) > 0 then return false end end
    return true
  end},
}
