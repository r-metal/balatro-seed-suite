-- selftest_filter_probe: runs one filter over a fixed seed range and logs the worker
-- candidates, the main-thread re-check's rejections and the verified hits, so the same
-- range can be compared under plain lovely and under Steamodded (rig/lovely-rig.sh).
-- The filter is the one from a real report: Ghost Deck, Red Stake, Investment Tag on the
-- ante 1 Small Blind, the Soul in the Charm tag's Arcana pack, first Soul = Triboulet.
local engine = require('seedfinder.engine')
local F = {name = 'Investment Soul Triboulet', deck = os.getenv('PROBE_DECK') or 'b_ghost', stake = 2, mode = 'all', clauses = {
  {kind = 'tag', ante = 1, blind = 'Small', key = 'tag_investment'},
  {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
  {kind = 'legendary', index = 1, key = 'j_triboulet'}}}
local N = tonumber(os.getenv('PROBE_SEEDS') or '') or 600000
local S = {}
-- PROBE_IN_RUN=1: search from inside a live run holding PROBE_GIVE (a Joker key), the way
-- the report did (a run that had just made Triboulet).
local steps = {}
if os.getenv('PROBE_IN_RUN') == '1' then
  steps[#steps + 1] = {name = 'start run', run = function(ctx) ctx.start_run{}; return true end}
  steps[#steps + 1] = {name = 'in run', timeout = 30, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.jokers ~= nil
  end}
  steps[#steps + 1] = {name = 'give joker', run = function(ctx)
    local key = os.getenv('PROBE_GIVE') or 'j_triboulet'
    local c = create_card('Joker', G.jokers, nil, nil, nil, nil, key)
    c:add_to_deck()
    G.jokers:emplace(c)
    ctx.log('probe: live run holds '..key)
    return true
  end}
end
local function discovered()
  local n = 0
  for _, c in pairs(G.P_CENTERS) do if c.discovered then n = n + 1 end end
  for _, c in pairs(G.P_TAGS) do if c.discovered then n = n + 1 end end
  return n
end
for _, st in ipairs({
  {name = 'start', run = function(ctx)
    S.disc0 = discovered()
    local ok, h = pcall(engine.start, F, {workers = tonumber(os.getenv('PROBE_WORKERS') or '') or 4, max_seeds = N,
      start = tonumber(os.getenv('PROBE_START') or '') or 0})
    ctx.assert(ok, 'engine.start raised: '..tostring(h))
    S.h = h
    return true
  end},
  {name = 'done', timeout = 900, run = function(ctx)
    local p = engine.poll(S.h)
    ctx.assert(not p.error, 'search failed: '..tostring(p.error))
    if not p.done then return false end
    ctx.log(('probe: scanned %d, candidates %s, rejected %s, verified %d: %s'):format(p.scanned,
      tostring(p.candidates), tostring(p.rejected), #p.found, table.concat(p.found, ' ')))
    -- For the first rejected seeds: which clause fails on the main thread now.
    local filter = require('seedfinder.filter')
    local kept, n = {}, 0
    for _, s in ipairs(p.found) do kept[s] = true end
    for _, seed in ipairs(S.h.reported or {}) do
      if not kept[seed] and n < 3 then
        n = n + 1
        local res = {}
        for i, c in ipairs(F.clauses) do
          local f1 = {name = 'c'..i, deck = F.deck, stake = F.stake, mode = 'all', clauses = {c}}
          local ok, r = pcall(filter.eval_seed, f1, seed)
          res[#res + 1] = c.kind..'='..(ok and tostring(r) or ('error '..tostring(r)))
        end
        ctx.log('probe: rejected '..seed..': '..table.concat(res, ' '))
      end
    end
    ctx.log(('probe: discovered prototypes before %d, after %d'):format(S.disc0, discovered()))
    ctx.log('probe: live used_jokers: '..(function()
      local t = {} for k in pairs(G.GAME and G.GAME.used_jokers or {}) do t[#t + 1] = k end return table.concat(t, ',') end)())
    return true
  end},
}) do steps[#steps + 1] = st end
return steps
