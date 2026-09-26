-- Self-test for the ctx helpers on the real main menu: find_button (with and
-- without id), click, and overlay open/close. Excluded from `smoke.sh all`.
return {
  {name = 'find_button', run = function(ctx)
    -- 'setup_run' (not 'start_run') also proves the rig marked the tutorial complete
    ctx.assert(ctx.find_button('setup_run'), 'Play button (setup_run) not found')
    ctx.assert(ctx.find_button('setup_run', 'main_menu_play'), 'Play button not found by id')
    ctx.assert(ctx.find_button('setup_run', 'no_such_id') == nil, 'id filter ignored')
    ctx.assert(ctx.find_button('no_such_button') == nil, 'found a button that does not exist')
    ctx.assert(ctx.click('no_such_button') == false, 'click on a missing button should return false')
    return true
  end},
  {name = 'open options', run = function(ctx)
    ctx.assert(ctx.click('options'), 'Options button not found')
    return true
  end},
  {name = 'options overlay up', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    ctx.shot('options')
    return true
  end},
  {name = 'close overlay', run = function(ctx)
    ctx.assert(ctx.click('exit_overlay_menu'), 'Back button (exit_overlay_menu) not found in the overlay')
    return true
  end},
  {name = 'overlay gone', run = function(ctx)
    return G.OVERLAY_MENU == nil
  end},
}
