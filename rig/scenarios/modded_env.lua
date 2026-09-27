-- modded_env: with a content mod present (a fake Joker, marked the way Steamodded marks
-- mod content: original_mod), the suite says so instead of predicting. The notice names
-- the mod, the Finder refuses to search, and both overlays show the notice. The fake is
-- removed at the end. Screenshots: finder.png, oracle.png.
local CHARM = {name = 'Charm', clauses = {{kind = 'tag', ante = 1, blind = 'any', key = 'tag_charm'}}}
local function fake(on)
  G.P_CENTERS.j_rigfake = on and {key = 'j_rigfake', set = 'Joker', name = 'Rig Fake',
    original_mod = {id = 'RigFake', name = 'RigFake'}} or nil
  BHCore._env = nil
end
return {
  {name = 'unmodded baseline', run = function(ctx)
    BHCore._env = nil
    ctx.assert(BHCore.env_notice() == nil, 'notice in an unmodded game: '..tostring((BHCore.env_notice())))
    return true
  end},
  {name = 'content mod noticed', run = function(ctx)
    fake(true)
    local n = BHCore.env_notice()
    ctx.assert(n and n:find('RigFake', 1, true), 'notice does not name the mod: '..tostring(n))
    return true
  end},
  {name = 'finder refuses', run = function(ctx)
    SeedFinder.ui.open('options')
    SeedFinder.ui.set_filter(CHARM)
    G.FUNCS.seedfinder_start()
    ctx.assert(not (SeedFinder.ui.search() and SeedFinder.ui.search().running), 'a search started')
    return true
  end},
  {name = 'finder shot', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    ctx.shot('finder')
    return true
  end},
  {name = 'start run', run = function(ctx) ctx.start_run{}; return true end},
  {name = 'blind select', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
  end},
  {name = 'oracle shot', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    if not G.OVERLAY_MENU then G.FUNCS.seedoracle_open(); return false end
    if ctx.step_time() < 2 then return false end
    ctx.shot('oracle')
    return true
  end},
  {name = 'cleanup', run = function(ctx)
    fake(false)
    ctx.assert(BHCore.env_notice() == nil, 'notice left after removing the fake mod')
    return true
  end},
}
