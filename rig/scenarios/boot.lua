-- Boot: the game reaches the main menu with the mod loaded, then starts a run
-- and reaches blind select. Screenshots: menu.png, run.png.
return {
  {name = 'mod loaded', run = function(ctx)
    ctx.assert(type(SaveSlots) == 'table', 'SaveSlots global missing')
    ctx.assert(SaveSlots.VERSION == BHCore.VERSION, 'SaveSlots.VERSION is '..tostring(SaveSlots.VERSION))
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
  {name = 'run shot', run = function(ctx)
    -- let the blind-select panel finish sliding in
    if ctx.step_time() < 1.5 then return false end
    ctx.shot('run')
    return true
  end},
}
