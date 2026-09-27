-- lovely_content_mod: for the real-lovely rig next to a real content mod
-- (rig/lovely-rig.sh lovely_content_mod --smods --mod tools/pokermon). The suite detects
-- the mod, the Finder refuses to search, and the Oracle still opens in a run without
-- taking the game down. Screenshots: finder.png, oracle.png.
local CHARM = {name = 'Charm', clauses = {{kind = 'tag', ante = 1, blind = 'any', key = 'tag_charm'}}}
return {
  {name = 'content mod detected', run = function(ctx)
    BHCore._env = nil
    local e = BHCore.env()
    ctx.log('env: smods='..tostring(e.smods)..' content={'..table.concat(e.content, ',')..'}')
    ctx.assert(#e.content > 0, 'no content mod detected')
    ctx.log('notice: '..tostring((BHCore.env_notice())))
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
    G.FUNCS.exit_overlay_menu()
    return true
  end},
  {name = 'start run', run = function(ctx) ctx.start_run{}; return true end},
  {name = 'blind select', timeout = 30, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
  end},
  {name = 'oracle opens', timeout = 20, run = function(ctx)
    if ctx.step_time() < 1 then return false end
    if not G.OVERLAY_MENU then G.FUNCS.seedoracle_open(); return false end
    if ctx.step_time() < 3 then return false end
    ctx.shot('oracle')
    return true
  end},
}
