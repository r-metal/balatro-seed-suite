-- lovely_paused_sim: for the real-lovely rig next to Steamodded
-- (rig/lovely-rig.sh lovely_paused_sim --smods). Steamodded's pseudoseed returns
-- math.random() while G.SETTINGS.paused, and the Finder and Oracle overlays pause the
-- game; the simulator must still be deterministic then. With the game paused, a seed's
-- predicted tags match the unpaused prediction every time, and a Finder search's
-- main-thread check rejects none of the worker hits. In 0.3.2 it rejected all of them.
local filter = require('seedfinder.filter')
local predict = require('bhcore.sim.predict')
local engine = require('seedfinder.engine')
local F = {name = 'probe', deck = 'b_checkered', stake = 2, mode = 'all', clauses = {
  {kind = 'tag', ante = 1, blind = 'Small', key = 'tag_investment'},
  {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
  {kind = 'legendary', index = 1, key = 'j_triboulet'}}}
local SEED = 'BA1VEIY9'
local S = {}
local function tags() local t = predict.tags(filter.fresh(F, SEED), 1); return t.small..'/'..t.big end
return {
  {name = 'unpaused', run = function(ctx)
    ctx.assert(SMODS, 'Steamodded not loaded (run with --smods)')
    S.want = tags()
    ctx.log('unpaused: '..S.want)
    return true
  end},
  {name = 'paused is deterministic', run = function(ctx)
    G.SETTINGS.paused = true
    for i = 1, 5 do
      local got = tags()
      ctx.assert(got == S.want, 'paused prediction '..i..' is '..got..', unpaused '..S.want)
    end
    ctx.assert(G.SETTINGS.paused == true, 'the pause was not restored')
    return true
  end},
  {name = 'paused search', run = function(ctx)
    S.h = engine.start(F, {workers = 4, max_seeds = 300000, start = 0})
    return true
  end},
  {name = 'paused search done', timeout = 300, run = function(ctx)
    local p = engine.poll(S.h)
    ctx.assert(not p.error, 'search failed: '..tostring(p.error))
    if not p.done then return false end
    ctx.log(('paused search: candidates %d, rejected %d, verified %d'):format(p.candidates, p.rejected, #p.found))
    ctx.assert(p.candidates > 0, 'no candidates')
    ctx.assert(p.rejected == 0, p.rejected..' of '..p.candidates..' hits rejected with the game paused')
    G.SETTINGS.paused = false
    return true
  end},
}
