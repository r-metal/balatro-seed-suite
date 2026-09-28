-- Daily run (T-377): seedfinder.daily.play and the Oracle's blind-mode lock, in
-- the real game, through the real Oracle button and hotkey. The day is the real
-- UTC date: each play is bracketed by daily.today() calls, so a UTC midnight
-- falling mid-scenario is told apart from a wrong seed instead of failing.
--   1. Main menu, the day's deck unlocked (its center's flags, as vanilla's
--      unlock_all sets them, on this isolated profile), RunJournal's set_origin
--      spied on (it still runs): daily.play('blind'). The run's seed and deck
--      are today()'s, stake 1,
--      G.GAME.seeded is true, bh_daily = {date, mode = 'blind'}, and set_origin
--      got {kind = 'daily', date, mode = 'blind'} before the run started.
--      -> "check: blind daily starts seeded" (shot daily_blind)
--   2. ctrl+o shows the lock note, not the overlay; ctrl+o closes it. The pause
--      menu's Seed Oracle button shows it too, and its Back returns to the pause
--      menu. -> "check: oracle locked in blind" (shots locked_hotkey, locked_button)
--   3. Vanilla's own blind-select autosave holds bh_daily on disk. Pause -> Main
--      Menu -> Play -> Continue (vanilla's first-Continue unlock card dismissed):
--      the loaded run keeps bh_daily and `seeded`, and ctrl+o still shows the
--      note. -> "check: lock survives reload" (shot locked_after_reload)
--   4. The day's deck back to its fresh-profile lock, daily.play('routed')
--      from inside the run: the same seed, deck_for's deck (Red, with the reason,
--      when the day's deck is locked: the fallback path), bh_daily.mode
--      'routed', still seeded. The pause menu's Seed Oracle button opens the
--      overlay on that seed. -> "check: routed daily opens oracle" (shot routed_oracle)
-- Screenshots: daily_blind, locked_hotkey, locked_button, locked_after_reload, routed_oracle.
local daily = require('seedfinder.daily')
local ui = require('seedoracle.ui')

local LOCKED_MSG = 'Daily blind run: the Oracle is locked'
local S = {origins = {}}

local function idle() return not G.CONTROLLER.locks.frame end

local function hotkey()
  G.CONTROLLER.held_keys['lctrl'] = true
  G.CONTROLLER:key_press_update('o', 0)
  G.CONTROLLER.held_keys['lctrl'] = nil
end

local function blind_select_ready(seed)
  return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
    and G.GAME.pseudorandom.seed == seed and not G.CONTROLLER.locks.load and G.OVERLAY_MENU == nil
end

-- daily.play(mode), with today() read on both sides of it.
local function play(ctx, mode)
  local before = daily.today()
  local ok, info = daily.play(mode)
  local after = daily.today()
  ctx.assert(ok, 'daily.play('..mode..') refused: '..tostring(info))
  ctx.log(string.format('daily.play(%s): %s seed %s deck %s%s', mode, info.date, info.seed, info.deck,
    info.reason and ' ('..info.reason..')' or ''))
  return {before = before, after = after, info = info}
end

-- The today() of the day the run was started on (bh_daily.date).
local function day_of(p)
  local d = G.GAME.bh_daily
  local date = type(d) == 'table' and d.date
  if date == p.before.date then return p.before end
  if date == p.after.date then return p.after end
end

local function deck_key()
  local b = G.GAME.selected_back_key
  return type(b) == 'table' and b.key or b
end

-- Whether the overlay on screen holds the lock message.
local function note_text()
  local found = false
  local function walk(node)
    if type(node) ~= 'table' or found then return end
    if node.config and node.config.text == LOCKED_MSG then found = true end
    for _, child in pairs(node.children or {}) do walk(child) end
  end
  walk(G.OVERLAY_MENU and G.OVERLAY_MENU ~= true and G.OVERLAY_MENU.UIRoot)
  return found
end

local function assert_locked(ctx, how)
  ctx.assert(not ui.is_open(), how..' opened the Oracle overlay in a blind daily')
  ctx.assert(ui.lock_shown(), how..' did not show the lock note')
  ctx.assert(note_text(), how..': the note does not read "'..LOCKED_MSG..'"')
end

-- Vanilla shows unlock cards as overlays: the first Continue on a profile
-- unlocks a Joker, and its card pops a few seconds into the loaded run. A
-- player dismisses it with its own button; so does this. True while one is up
-- or was dismissed less than a second ago.
local unlock = {dismissed = -math.huge}
local function dismiss_unlock(ctx)
  local now = love.timer.getTime()
  if not (G.OVERLAY_MENU and ctx.find_button('continue_unlock')) then
    return now - unlock.dismissed < 1
  end
  if unlock.box ~= G.OVERLAY_MENU then unlock.box, unlock.at = G.OVERLAY_MENU, now end
  if now - unlock.at > 1.5 then
    ctx.log('dismissed a vanilla unlock card')
    ctx.click('continue_unlock')
    unlock.dismissed = now
  end
  return true
end

local function saved_on_disk()
  local raw = get_compressed(G.SETTINGS.profile..'/save.jkr')
  local t = raw and STR_UNPACK(raw)
  return t and t.GAME
end

return {
  {name = 'setup', run = function(ctx)
    ctx.assert(type(SeedFinder) == 'table' and SeedFinder.daily == daily, 'seedfinder.daily not loaded')
    ctx.assert(type(SeedOracle) == 'table', 'SeedOracle not loaded')
    love.mouse.setPosition(4, 4)
    if SaveSlots and SaveSlots.settings then SaveSlots.settings.auto_checkpoints = false end
    local rec = type(RunJournal) == 'table' and RunJournal.recorder
    ctx.assert(rec and rec.set_origin, 'RunJournal not loaded')
    local orig = rec.set_origin
    rec.set_origin = function(o, ...)
      S.origins[#S.origins + 1] = {o = o, stage = G.STAGE}
      return orig(o, ...)
    end
    -- Unlocked the way vanilla's unlock_all leaves a deck (the center's flags):
    -- the all_unlocked flag alone would start the run, but vanilla's Continue
    -- panel reads the center and would show the save's deck as Locked.
    S.deck = daily.today().deck
    local c = G.P_CENTERS[S.deck]
    S.was = {unlocked = c.unlocked, discovered = c.discovered}
    c.unlocked, c.discovered = true, true
    local deck, why = daily.deck_for()
    ctx.assert(deck == S.deck and why == nil, 'the day\'s deck is not playable once unlocked')
    return true
  end},

  -- 1. The blind daily.
  {name = 'play blind', run = function(ctx)
    if G.OVERLAY_MENU or not idle() or ctx.step_time() < 0.5 then return false end
    S.blind = play(ctx, 'blind')
    return true
  end},
  {name = 'blind daily starts', timeout = 20, run = function(ctx)
    local p = S.blind
    if not (blind_select_ready(p.info.seed) and ctx.step_time() > 1.5) then return false end
    local day = day_of(p)
    ctx.assert(day, 'bh_daily.date '..tostring(G.GAME.bh_daily and G.GAME.bh_daily.date)
      ..' is neither today\'s '..p.before.date..' nor '..p.after.date)
    ctx.assert(G.GAME.pseudorandom.seed == day.seed, 'seed '..G.GAME.pseudorandom.seed..', today() says '..day.seed)
    ctx.assert(deck_key() == day.deck, 'deck '..tostring(deck_key())..', today() says '..day.deck)
    ctx.assert(G.GAME.selected_back.name == G.P_CENTERS[day.deck].name, 'selected_back is '..tostring(G.GAME.selected_back.name))
    ctx.assert(G.GAME.stake == 1, 'stake '..tostring(G.GAME.stake))
    ctx.assert(G.GAME.seeded == true, 'the blind daily is not seeded')
    ctx.assert(G.GAME.bh_daily.mode == 'blind', 'bh_daily.mode '..tostring(G.GAME.bh_daily.mode))
    ctx.assert(G.GAME.challenge == nil, 'a challenge run')
    ctx.assert(#S.origins == 1, #S.origins..' set_origin calls')
    local o = S.origins[1]
    ctx.assert(o.o.kind == 'daily' and o.o.date == day.date and o.o.mode == 'blind',
      'set_origin got kind='..tostring(o.o.kind)..' date='..tostring(o.o.date)..' mode='..tostring(o.o.mode))
    ctx.assert(o.stage ~= G.STAGES.RUN, 'set_origin was called after the run started')
    S.day = day
    ctx.log(string.format('blind daily %s: seed %s, %s, stake %d, seeded', day.date, day.seed, day.deck, G.GAME.stake))
    ctx.log('check: blind daily starts seeded')
    ctx.shot('daily_blind')
    return true
  end},

  -- 2. The lock, by hotkey and by the pause button.
  {name = 'ctrl+o in blind', run = function(ctx)
    if not idle() then return false end
    hotkey()
    ctx.assert(not ui.is_open(), 'ctrl+o opened the Oracle overlay in a blind daily')
    return ui.lock_shown()
  end},
  {name = 'hotkey note', run = function(ctx)
    if ctx.step_time() < 0.6 then return false end
    assert_locked(ctx, 'ctrl+o')
    ctx.shot('locked_hotkey')
    return true
  end},
  {name = 'ctrl+o closes the note', run = function(ctx)
    if not idle() then return false end
    hotkey()
    ctx.assert(not ui.lock_shown() and not G.OVERLAY_MENU, 'ctrl+o did not close the lock note')
    return true
  end},
  {name = 'pause', run = function(ctx)
    if G.OVERLAY_MENU or not idle() or ctx.step_time() < 0.3 then return false end
    return ctx.click('options')
  end},
  {name = 'seed oracle button', run = function(ctx)
    if not ctx.find_button('seedoracle_open') or ctx.step_time() < 0.6 or not idle() then return false end
    ctx.assert(ctx.click('seedoracle_open'), 'no Seed Oracle button')
    return true
  end},
  {name = 'button note', run = function(ctx)
    if ctx.step_time() < 0.6 then return false end
    assert_locked(ctx, 'the Seed Oracle button')
    ctx.shot('locked_button')
    ctx.log('check: oracle locked in blind')
    return true
  end},
  {name = 'note back', run = function(ctx)
    if not idle() then return false end
    local b = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('overlay_menu_back_button')
    ctx.assert(b and b.config.button == 'options', 'the note\'s Back does not return to the pause menu')
    G.FUNCS[b.config.button](b)
    return true
  end},
  {name = 'pause again', run = function(ctx)
    if not ctx.find_button('seedoracle_open') or ctx.step_time() < 0.6 then return false end
    ctx.assert(not ui.lock_shown(), 'the note is still up')
    return true
  end},

  -- 3. Save, quit to the menu, Continue.
  {name = 'autosave on disk', timeout = 20, run = function(ctx)
    local g = saved_on_disk()
    if not (g and g.pseudorandom and g.pseudorandom.seed == S.day.seed and type(g.bh_daily) == 'table') then
      if G.FILE_HANDLER then G.FILE_HANDLER.force = true end
      return false
    end
    ctx.assert(g.bh_daily.mode == 'blind' and g.bh_daily.date == S.day.date, 'save.jkr holds another bh_daily')
    ctx.assert(g.seeded == true, 'save.jkr: not seeded')
    ctx.log('save.jkr holds bh_daily = {'..g.bh_daily.date..', '..g.bh_daily.mode..'}')
    return true
  end},
  {name = 'main menu button', run = function(ctx)
    if not idle() or ctx.step_time() < 1 then return false end
    return ctx.click('go_to_menu')
  end},
  {name = 'main menu', timeout = 20, run = function(ctx)
    if G.STAGE ~= G.STAGES.MAIN_MENU or dismiss_unlock(ctx) then return false end
    return G.MAIN_MENU_UI ~= nil and G.OVERLAY_MENU == nil and idle() and ctx.step_time() > 1.5
  end},
  {name = 'open play', run = function(ctx)
    return ctx.click('setup_run')
  end},
  {name = 'continue tab', run = function(ctx)
    if not G.OVERLAY_MENU or not idle() or ctx.step_time() < 1 then return false end
    local tab = ctx.find_button('change_tab', 'tab_but_'..localize('b_continue'))
    ctx.assert(tab, 'no Continue tab')
    tab:click()
    return true
  end},
  {name = 'continue', run = function(ctx)
    if G.SETTINGS.current_setup ~= 'Continue' or not idle() or ctx.step_time() < 0.8 then return false end
    local g = G.SAVED_GAME and G.SAVED_GAME.GAME
    ctx.assert(g and g.pseudorandom.seed == S.day.seed, 'Continue does not hold the daily')
    return ctx.click('start_setup_run')
  end},
  {name = 'continued', timeout = 30, run = function(ctx)
    if G.STAGE ~= G.STAGES.RUN or dismiss_unlock(ctx) then return false end
    -- The unlock card comes a few seconds into the loaded run: wait past it.
    if not (blind_select_ready(S.day.seed) and idle() and ctx.step_time() > 5) then return false end
    local d = G.GAME.bh_daily
    ctx.assert(type(d) == 'table' and d.mode == 'blind' and d.date == S.day.date,
      'bh_daily lost on Continue: '..tostring(d and d.mode)..' '..tostring(d and d.date))
    ctx.assert(G.GAME.seeded == true, 'the continued daily is not seeded')
    return true
  end},
  {name = 'ctrl+o after reload', run = function(ctx)
    if not idle() then return false end
    hotkey()
    return ui.lock_shown()
  end},
  {name = 'reload note', run = function(ctx)
    if ctx.step_time() < 0.6 then return false end
    assert_locked(ctx, 'ctrl+o after Continue')
    ctx.shot('locked_after_reload')
    ctx.log('check: lock survives reload')
    return true
  end},
  {name = 'close the reload note', run = function(ctx)
    if not idle() then return false end
    hotkey()
    ctx.assert(not G.OVERLAY_MENU, 'ctrl+o did not close the lock note')
    return true
  end},

  -- 4. The routed daily, from inside the run, on the profile's own locks.
  {name = 'play routed', run = function(ctx)
    if G.OVERLAY_MENU or not idle() or ctx.step_time() < 1 then return false end
    local c = G.P_CENTERS[S.deck]
    c.unlocked, c.discovered = S.was.unlocked, S.was.discovered
    S.want_deck, S.want_reason = daily.deck_for()
    S.routed = play(ctx, 'routed')
    return true
  end},
  {name = 'routed start', timeout = 20, run = function(ctx)
    local p = S.routed
    if not (blind_select_ready(p.info.seed) and type(G.GAME.bh_daily) == 'table'
      and G.GAME.bh_daily.mode == 'routed' and ctx.step_time() > 1.5) then return false end
    local day = day_of(p)
    ctx.assert(day, 'bh_daily.date is neither today()\'s before nor after the play')
    if day.date == S.day.date then
      ctx.assert(day.seed == S.day.seed and G.GAME.pseudorandom.seed == S.day.seed,
        'routed seed '..G.GAME.pseudorandom.seed..', the blind daily was '..S.day.seed)
    else
      ctx.log('UTC midnight passed between the plays: '..S.day.date..' -> '..day.date)
      ctx.assert(G.GAME.pseudorandom.seed == day.seed, 'routed seed is not today()\'s')
    end
    ctx.assert(deck_key() == S.want_deck, 'deck '..tostring(deck_key())..', deck_for says '..tostring(S.want_deck))
    if day.deck ~= 'b_red' then
      ctx.assert(S.want_deck == 'b_red' and S.want_reason and p.info.reason == S.want_reason,
        'the locked '..day.deck..' did not fall back to Red with a reason')
      ctx.log('fallback: '..p.info.reason)
    end
    ctx.assert(G.GAME.seeded == true and G.GAME.stake == 1, 'the routed daily is unseeded or not White Stake')
    return true
  end},
  {name = 'pause (routed)', run = function(ctx)
    if not idle() then return false end
    return ctx.click('options')
  end},
  {name = 'seed oracle button (routed)', run = function(ctx)
    if not ctx.find_button('seedoracle_open') or ctx.step_time() < 0.6 or not idle() then return false end
    ctx.assert(ctx.click('seedoracle_open'), 'no Seed Oracle button')
    return true
  end},
  {name = 'routed oracle', run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 0.8 then return false end
    ctx.assert(not ui.lock_shown(), 'the lock note is up in a routed daily')
    local model = SeedOracle.oracle.get()
    ctx.assert(model and model.seed == G.GAME.pseudorandom.seed, 'the Oracle predicts another seed')
    ctx.shot('routed_oracle')
    ctx.log('check: routed daily opens oracle')
    return true
  end},
  {name = 'back to pause', run = function(ctx)
    ctx.assert(ctx.click('options'), 'no Back button to the pause menu')
    return true
  end},
  {name = 'close pause', run = function(ctx)
    if not ctx.find_button('seedoracle_open') or ctx.step_time() < 0.5 or not idle() then return false end
    G.FUNCS.exit_overlay_menu()
    return true
  end},
}
