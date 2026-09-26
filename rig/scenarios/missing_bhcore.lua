-- missing_bhcore: SeedOracle and SeedFinder installed without bh-core (say, two dev
-- folders copied by hand). The game still boots and starts a run; both mods stay off, and the
-- main menu says why. Screenshot: menu.png (the notice).
-- rig-mods: SeedOracle, SeedFinder
return {
  {name = 'mods stayed off', run = function(ctx)
    ctx.assert(BHCore == nil, 'bh-core loaded although it is not installed')
    ctx.assert(SeedOracle == nil and SeedFinder == nil, 'a mod ran without bh-core')
    local n = BHSuiteNotice
    ctx.assert(n and #n.mods == 2, 'the notice lists '..(n and #n.mods or 0)..' mods, want 2')
    ctx.assert(n.found == 'not installed', 'notice says bh-core found: '..tostring(n.found))
    return true
  end},
  {name = 'notice shot', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    ctx.shot('menu')
    return true
  end},
  {name = 'start run', run = function(ctx)
    ctx.start_run{}
    return true
  end},
  {name = 'blind select', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
  end},
}
