-- RunJournal hunt outcomes (T-331): runs the Seed Finder started are grouped per
-- filter in the overlay's Hunts tab.
--   1. RunJournal.recorder.set_origin{filter_name = 'Test filter'} (what the Finder's
--      Play does), then run A, seed RJHUNTS1 (stake 1): win_ante forced to 2, antes 1
--      and 2 won (each blind's target forced to 1, as runjournal_compare.lua does):
--      the Boss of ante 2 wins the run at ante 3.
--   2. set_origin again, run B (same seed): ante 1 Small lost with one hand left.
--   3. No set_origin, run C (same seed): ante 1 Small lost. Its record has no filter.
--      stats.by_filter gives one group: 'Test filter', 2 runs, 1 win, best ante 3.
--      -> "check: hunts grouped by filter"
--   4. Main menu, Options, Run Journal, Hunts tab: one row, 'Test filter', 2 runs,
--      best ante 3, no second row; the overlay keeps the Overview's size and fits the
--      room. -> "check: hunts tab matches by_filter"
-- Speed: vsync off, GAMESPEED 64, extra Game:update passes. Screenshots: won_a,
-- game_over_b, game_over_c, hunts.
local recorder = require('runjournal.recorder')
local stats = require('runjournal.stats')
local ui = require('runjournal.ui')

local SEED = 'RJHUNTS1'
local FILTER = 'Test filter'
local S = {ids = {}}

local function turbo()
  for _ = 1, 4 do G:update(1/20) end
end

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function select_blind(kind)
  return {name = 'select '..kind, timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.BLIND_SELECT or not G.blind_select or ctx.step_time() < 0.3 then return false end
    local on_deck = G.GAME.blind_on_deck
    local box = G.blind_select_opts and on_deck and G.blind_select_opts[string.lower(on_deck)]
    if on_deck ~= kind then return false end
    local btn = box and box:get_UIE_by_ID('select_blind_button')
    if not (btn and btn.config.button == 'select_blind') then return false end
    G.FUNCS.select_blind(btn)
    return true
  end}
end

-- Plays up to five cards against `target`, with `hands_left` forced when given.
local function play(label, target, hands_left)
  return {name = 'play '..label, timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or ctx.step_time() < 0.2
      or G.CONTROLLER.locks.frame then return false end
    G.GAME.blind.chips = target
    G.GAME.blind.chip_text = number_format(target)
    if hands_left then G.GAME.current_round.hands_left = hands_left end
    for i = 1, #G.hand.cards do
      if #G.hand.highlighted >= math.min(5, G.hand.config.highlighted_limit or 5) then break end
      if not G.hand.cards[i].highlighted then G.hand:add_to_highlighted(G.hand.cards[i]) end
    end
    ctx.assert(#G.hand.highlighted > 0, 'no cards highlighted')
    G.FUNCS.play_cards_from_highlighted()
    return true
  end}
end

local function cash_out()
  return {name = 'cash out', timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.ROUND_EVAL or ctx.step_time() < 0.2 then return false end
    return ctx.click('cash_out')
  end}
end

local function shop()
  return {name = 'shop', timeout = 30, run = function(ctx)
    turbo()
    -- Leaving before the shop's delayed event lands crashes it (game.lua:3090).
    if G.STATE ~= G.STATES.SHOP or not G.shop or ctx.step_time() < 0.3
      or not (G.shop_booster and #G.shop_booster.cards == 2) then return false end
    return ctx.click('toggle_shop')
  end}
end

-- origin: the filter name set_origin gets before the run, nil for none.
-- win_ante: G.GAME.win_ante once the run is up, nil to keep vanilla's.
local function start(label, origin, win_ante)
  return {
    {name = 'start '..label, run = function(ctx)
      recorder.set_origin(origin and {filter_name = origin} or nil)
      ctx.start_run{seed = SEED, stake = 1}
      return true
    end},
    {name = label..' blind select', timeout = 20, run = function(ctx)
      turbo()
      if not (G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select
        and G.GAME.pseudorandom.seed == SEED and G.GAME.round_resets.ante == 1) or ctx.step_time() < 1 then
        return false
      end
      local r = recorder.current()
      ctx.assert(r and r.seed == SEED, 'no live record for '..label)
      for _, id in pairs(S.ids) do ctx.assert(r.run_id ~= id, 'no new live record for '..label) end
      ctx.assert((r.origin and r.origin.filter_name) == origin,
        label..' origin '..tostring(r.origin and r.origin.filter_name))
      S.ids[label] = r.run_id
      if win_ante then G.GAME.win_ante = win_ante end
      ctx.log(label..' run id '..r.run_id..' origin '..tostring(origin))
      return true
    end},
  }
end

local function win_ante(last)
  local out = {}
  for _, kind in ipairs({'Small', 'Big', 'Boss'}) do
    out[#out + 1] = select_blind(kind)
    out[#out + 1] = play(kind, 1)
    if not (last and kind == 'Boss') then
      out[#out + 1] = cash_out()
      out[#out + 1] = shop()
    end
  end
  return out
end

local function won(label)
  return {name = label..' won', timeout = 30, run = function(ctx)
    turbo()
    local r = recorder.current()
    if not (r and r.ended_at and G.OVERLAY_MENU) or ctx.step_time() < 1.5 then return false end
    ctx.assert(r.run_id == S.ids[label] and r.won == true, label..' ended without a win')
    ctx.shot('won_'..label)
    return true
  end}
end

local function lose_small(label)
  return {
    select_blind('Small'),
    play('Small (lose)', 1e12, 1),
    {name = label..' game over', timeout = 30, run = function(ctx)
      turbo()
      if G.STATE ~= G.STATES.GAME_OVER or not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
      ctx.shot('game_over_'..label)
      return true
    end},
  }
end

local steps = {
  {name = 'speed up', run = function()
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    return true
  end},
}

local function add(list) for _, s in ipairs(list) do steps[#steps + 1] = s end end

add(start('a', FILTER, 2))
add(win_ante())
add(win_ante(true))
add({won('a')})
add(start('b', FILTER))
add(lose_small('b'))
add(start('c', nil))
add(lose_small('c'))

add({
  {name = 'hunts grouped by filter', run = function(ctx)
    local a, b, c = recorder.read(S.ids.a), recorder.read(S.ids.b), recorder.read(S.ids.c)
    ctx.assert(a and b and c, 'records on disk')
    ctx.assert(a.won == true and a.final_ante == 3, 'run a: won '..tostring(a.won)..' ante '..tostring(a.final_ante))
    ctx.assert(b.won == false and b.final_ante == 1, 'run b: won '..tostring(b.won)..' ante '..tostring(b.final_ante))
    ctx.assert(c.won == false and c.final_ante == 1, 'run c: won '..tostring(c.won)..' ante '..tostring(c.final_ante))
    ctx.assert(a.origin.filter_name == FILTER and b.origin.filter_name == FILTER, 'a/b origin')
    ctx.assert(c.origin.filter_name == nil, 'run c has origin '..tostring(c.origin.filter_name))
    local g = stats.by_filter()
    ctx.assert(#g == 1, #g..' hunt groups')
    local h = g[1]
    ctx.log(string.format('hunt %s: runs %d wins %d rate %.2f best %s avg %s', h.filter_name, h.runs, h.wins,
      h.win_rate, tostring(h.best_ante), tostring(h.avg_ante)))
    ctx.assert(h.filter_name == FILTER and h.runs == 2 and h.wins == 1 and h.best_ante == 3 and h.avg_ante == 2,
      'by_filter group')
    ctx.log('check: hunts grouped by filter')
    return true
  end},
  {name = 'main menu', run = function(ctx) return ctx.click('go_to_menu') end},
  {name = 'options', timeout = 20, run = function(ctx)
    if not (G.STAGE == G.STAGES.MAIN_MENU and G.MAIN_MENU_UI) or G.OVERLAY_MENU or ctx.step_time() < 1.5 then
      return false
    end
    G.FUNCS.options()
    return true
  end},
  {name = 'open run journal', timeout = 5, run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    return ctx.click('runjournal_open')
  end},
  {name = 'hunts tab', timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 0.5 then return false end
    local e = ctx.find_button('change_tab', 'tab_but_Hunts')
    if not e then return false end
    local root = G.OVERLAY_MENU.UIRoot.children[1]
    S.overview = {root.T.x, root.T.x + root.T.w}
    e:click()
    return true
  end},
  {name = 'hunts view', timeout = 5, run = function(ctx)
    if ctx.step_time() < 1 then return false end
    local function text_of(id)
      local n = uie(id)
      ctx.assert(n, 'no UI element '..id)
      return n.config.text
    end
    local shown = ui.hunts()
    ctx.assert(shown and #shown == 1, 'the tab shows '..tostring(shown and #shown)..' hunts')
    ctx.assert(text_of('runjournal_hunt_name_1') == FILTER, 'row name '..tostring(text_of('runjournal_hunt_name_1')))
    ctx.assert(text_of('runjournal_hunt_runs_1') == '2', 'row runs '..tostring(text_of('runjournal_hunt_runs_1')))
    ctx.assert(text_of('runjournal_hunt_wins_1') == '1', 'row wins '..tostring(text_of('runjournal_hunt_wins_1')))
    ctx.assert(text_of('runjournal_hunt_best_1') == 'Ante 3', 'row best '..tostring(text_of('runjournal_hunt_best_1')))
    ctx.assert(text_of('runjournal_hunt_rate_1') == '50%', 'row rate '..tostring(text_of('runjournal_hunt_rate_1')))
    ctx.assert(uie('runjournal_hunt_name_2') == nil, 'a second hunt row')
    local top, back = uie('tab_but_Overview'), uie('overlay_menu_back_button')
    local root = G.OVERLAY_MENU.UIRoot.children[1]
    local x1, x2, y1, y2 = root.T.x, root.T.x + root.T.w, top.T.y, back.T.y + back.T.h
    ctx.log(string.format('layout hunts: panel x %.2f..%.2f y %.2f..%.2f in room %.2fx%.2f',
      x1, x2, y1, y2, G.ROOM.T.w, G.ROOM.T.h))
    ctx.assert(x1 >= 0 and y1 >= 0 and x2 <= G.ROOM.T.w and y2 <= G.ROOM.T.h, 'the overlay does not fit the room')
    ctx.assert(math.abs(x1 - S.overview[1]) < 0.01 and math.abs(x2 - S.overview[2]) < 0.01,
      string.format('the panel changed size: Overview x %.2f..%.2f', S.overview[1], S.overview[2]))
    ctx.shot('hunts')
    ctx.log('check: hunts tab matches by_filter')
    return true
  end},
})

return steps
