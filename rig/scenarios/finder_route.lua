-- Finder Route panel (T-302): a pinned hit's route, shown and then played step
-- by step in the real game.
--   1. The finder_chain filter (ante 1: Soul in an Arcana from a tag skip AND
--      Soul in a shop Arcana; Red Deck, stake 1) is set up by code, and its
--      pinned hit FCHAIN91662 goes in as the search's only result through
--      ui.set_results (no scan). The expected route is route.build(F, details)
--      of filter.eval_seed for that one seed. Ranking (T-303): the pinned hit
--      after a seed the filter misses (set_results, no scan) is ranked first,
--      the miss last with no cost; then the pinned hit alone is the result.
--      No step text repeats its "Ante N" heading, and a Soul used by a
--      use_soul step is only taken by its open_pack step. -> "check: ranked"
--   2. Play screen -> Find tab -> Route: the panel's rendered step lines, joined
--      per step, equal route.build's texts, and the cost line is there. Back
--      lands on the Find tab; the Find tab row shows the compact cost
--      ("A1 R0"). -> "check: tab route"
--   3. Open Seed Finder -> the hit row shows the compact cost -> its Route: the
--      same texts; the panel fits
--      the room. -> "check: route panel matches route.build" (shot route_panel)
--   4. The panel's Play starts the run (unseeded, as the row's Play does), which
--      is then played by executing the route's steps and nothing else:
--        skip      the real Skip button of the step's blind
--        play      Select, blind chips set to 1, one card played, cash out
--        open_pack the tag pack the skip opened, or the shop pack in the step's
--                  slot ($999 given); with an index, the card there must be the
--                  Soul, and it is taken (a pack Tarot's only "take" is Use);
--                  what the pack still offers is then skipped
--        use_soul  a Soul held in the consumables is used; one taken from a
--                  pack was used by the taking, and its legendary is checked
--        reroll    reroll_shop (the step's key, when given, in its slot)
--      Between steps the only glue is the game's own: leave the shop for the
--      next blind, and wait for states to settle.
--      -> "check: soul at step <k>" per Soul, "check: route played"
-- Screenshots: find_tab_hit, route_tab, hit_row, route_panel.
local ui = require('seedfinder.ui')
local filter = require('seedfinder.filter')
local route = require('seedfinder.route')

-- Pinned offline by finder_chain (the Big Blind's Charm skipped after the
-- Small's shop).
local SEED = 'FCHAIN91662'
local F = {name = 'chain', deck = 'b_red', stake = 1, mode = 'all', clauses = {
  {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
  {kind = 'soul_in_pack', ante = 1, pack = 'arcana'},
}}

local S = {}

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU ~= true and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function click(label, button, id, wait)
  return {name = label, timeout = 10, run = function(ctx)
    if wait and not wait() then return false end
    if G.CONTROLLER.locks.frame then return false end
    return ctx.click(button, id)
  end}
end

-- The panel's step texts as rendered: step k's wrapped lines joined by spaces.
local function rendered_steps()
  local out = {}
  for k = 1, 99 do
    local lines = {}
    for j = 1, 20 do
      local node = uie('seedfinder_step_'..k..'_'..j)
      if not node then break end
      lines[j] = node.config.text
    end
    if #lines == 0 then break end
    out[k] = table.concat(lines, ' ')
  end
  return out
end

local function check_panel(ctx, where)
  local r = ui.route()
  ctx.assert(r and r.seed == SEED and r.route, where..': no route shown for '..SEED..' ('..tostring(r and r.err)..')')
  local got = rendered_steps()
  ctx.assert(#got == #S.route.steps, where..': '..#got..' steps rendered, route.build has '..#S.route.steps)
  for k, st in ipairs(S.route.steps) do
    ctx.assert(got[k] == st.text, where..': step '..k..' renders "'..tostring(got[k])..'", route.build "'..st.text..'"')
  end
  ctx.assert(uie('seedfinder_route_cost') and uie('seedfinder_route_play'), where..': no cost line or Play')
  ctx.assert(uie('seedfinder_route_title').config.text == 'Route for '..SEED, where..': title')
  for k = 1, #got do
    for j = 1, 20 do
      local node = uie('seedfinder_step_'..k..'_'..j)
      if not node then break end
      ctx.assert(not node.config.text:find('[\128-\255]'), where..': non-ASCII text in step '..k)
    end
  end
end

local function check_fits(ctx, label)
  local root = G.OVERLAY_MENU.UIRoot.children[1]
  local back = uie('overlay_menu_back_button')
  local x1, x2, y1, y2 = root.T.x, root.T.x + root.T.w, root.T.y, back.T.y + back.T.h
  ctx.log(string.format('layout %s: panel x %.2f..%.2f y %.2f..%.2f in room %.2fx%.2f',
    label, x1, x2, y1, y2, G.ROOM.T.w, G.ROOM.T.h))
  ctx.assert(x1 >= 0 and y1 >= -0.2 and x2 <= G.ROOM.T.w and y2 <= G.ROOM.T.h, label..': the overlay does not fit the room')
end

-- Game-state helpers (as finder_chain).
local function select_button()
  local kind = G.GAME.blind_on_deck
  local box = G.blind_select_opts and kind and G.blind_select_opts[string.lower(kind)]
  local btn = box and box:get_UIE_by_ID('select_blind_button')
  if btn and btn.config.button == 'select_blind' then return btn, kind end
end

local function panel_button(kind, button)
  local box = G.blind_select_opts and G.blind_select_opts[string.lower(kind)]
  local function walk(node)
    if not node then return end
    if node.config and node.config.button == button then return node end
    for _, ch in pairs(node.children or {}) do
      local found = type(ch) == 'table' and walk(ch)
      if found then return found end
    end
  end
  return box and walk(box.UIRoot)
end

local function shop_settled()
  return G.STATE == G.STATES.SHOP and G.shop and G.shop_booster and G.shop_jokers
    and not G.CONTROLLER.locks.shop_reroll and not G.CONTROLLER.locks.use
    and not G.CONTROLLER.locks.toggle_shop
end

local PACK_STATES = nil
local function in_pack_state()
  if not PACK_STATES then
    PACK_STATES = {[G.STATES.TAROT_PACK] = true, [G.STATES.PLANET_PACK] = true,
      [G.STATES.SPECTRAL_PACK] = true, [G.STATES.STANDARD_PACK] = true, [G.STATES.BUFFOON_PACK] = true}
  end
  return PACK_STATES[G.STATE]
end

local function pack_dealt()
  return in_pack_state() and G.pack_cards and G.pack_cards.cards
    and #G.pack_cards.cards >= (G.GAME.pack_size or 1)
end

local function turbo()
  for _ = 1, 8 do G:update(1/20) end
end

local function keys(cards)
  local out = {}
  for i, c in ipairs(cards) do out[i] = c.config.center.key end
  return out
end

local function legendaries()
  local n = 0
  for _, c in ipairs(G.jokers and G.jokers.cards or {}) do
    if c.config.center.rarity == 4 then n = n + 1 end
  end
  return n
end

-- Runs S.route.steps in the live run, one phase per frame.
local function play_route(ctx)
  turbo()
  local P = S.play
  P.frames = P.frames + 1
  local function go(phase) P.phase, P.frames = phase, 0 end
  local st = S.route.steps[P.k]

  if P.phase == 'wait_run' then
    if not (G.STATE == G.STATES.BLIND_SELECT and G.GAME.pseudorandom.seed == SEED and select_button())
      or P.frames < 3 then return false end
    ctx.assert(not G.GAME.seeded and G.GAME.stake == 1 and G.GAME.selected_back.name == 'Red Deck',
      'Play did not start an unseeded stake-1 Red Deck run')
    go('next')
  elseif P.phase == 'next' then
    if not st then go('done'); return false end
    ctx.log(string.format('step %d: %s %s: %s', P.k, st.when, st.action, st.text))
    go(st.action)

  -- skip / play: at the step's blind (leaving the shop first when one is open).
  elseif P.phase == 'skip' or P.phase == 'play' then
    if G.STATE == G.STATES.SHOP then
      if shop_settled() and P.frames > 2 and ctx.click('toggle_shop') then P.frames = 0 end
      return false
    end
    if G.STATE ~= G.STATES.BLIND_SELECT or P.frames < 3 or G.CONTROLLER.locks.skip_blind then return false end
    ctx.assert(G.GAME.blind_on_deck == st.when, 'step '..P.k..': the blind on deck is '
      ..tostring(G.GAME.blind_on_deck)..', the step says '..st.when)
    if P.phase == 'skip' then
      ctx.assert(G.GAME.round_resets.blind_tags[st.when] == st.key, 'step '..P.k..': the '..st.when..' tag is '
        ..tostring(G.GAME.round_resets.blind_tags[st.when]))
      local btn = panel_button(st.when, 'skip_blind')
      if not btn then return false end
      G.FUNCS.skip_blind(btn)
      P.k = P.k + 1
      go('next')
    else
      local btn = select_button()
      if not btn then return false end
      G.FUNCS.select_blind(btn)
      go('hand')
    end
  elseif P.phase == 'hand' then
    if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or P.frames < 2
      or G.CONTROLLER.locks.frame then return false end
    G.GAME.blind.chips = 1
    G.GAME.blind.chip_text = number_format(1)
    G.hand:add_to_highlighted(G.hand.cards[1])
    G.FUNCS.play_cards_from_highlighted()
    go('cash_out')
  elseif P.phase == 'cash_out' then
    if G.STATE ~= G.STATES.ROUND_EVAL or P.frames < 2 then return false end
    if ctx.click('cash_out') then go('shop') end
  elseif P.phase == 'shop' then
    if not shop_settled() or P.frames < 2 then return false end
    G.GAME.dollars = 999
    P.shop_n = P.shop_n + 1
    ctx.log(string.format('shop %d: packs %s', P.shop_n, table.concat(keys(G.shop_booster.cards), ' ')))
    P.k = P.k + 1
    go('next')

  -- open_pack: the tag pack the skip opened, or buy and open the shop pack.
  elseif P.phase == 'open_pack' then
    if st.when == 'shop' then
      if not shop_settled() or P.frames < 2 then return false end
      local booster
      for _, c in ipairs(G.shop_booster.cards) do
        if c.ability.booster_pos == st.slot then booster = c end
      end
      ctx.assert(booster, 'step '..P.k..': no shop pack in slot '..tostring(st.slot))
      local key = booster.config.center.key
      ctx.assert(st.key == nil or st.key == key, 'step '..P.k..': slot '..st.slot..' holds '..key..', the step says '..tostring(st.key))
      G.FUNCS.use_card({config = {ref_table = booster, button = 'use_card'}})
    end
    go('pack')
  elseif P.phase == 'pack' then
    if not pack_dealt() or P.frames < 3 then return false end
    local got = keys(G.pack_cards.cards)
    ctx.log(string.format('step %d pack: %s', P.k, table.concat(got, ' ')))
    if st.index then
      ctx.assert(got[st.index] == 'c_soul', string.format('step %d: card %d of the %s pack is %s, not the Soul',
        P.k, st.index, st.when, tostring(got[st.index])))
      P.souls = P.souls + 1
      ctx.log('check: soul at step '..P.k)
      P.legend0 = legendaries()
      G.FUNCS.use_card({config = {ref_table = G.pack_cards.cards[st.index], button = 'use_card'}})
      go('taken')
    else
      go('close')
    end
  elseif P.phase == 'taken' then
    if G.CONTROLLER.locks.use or G.CONTROLLER.locks.frame or P.frames < 3 then return false end
    if legendaries() <= P.legend0 then return false end
    P.taken = P.taken + 1
    -- A pack with choices left stays open: what it still offers is skipped.
    if G.booster_pack and G.pack_cards and in_pack_state() then go('close') else go('closing') end
  elseif P.phase == 'close' then
    if P.frames < 2 or G.CONTROLLER.locks.frame then return false end
    if ctx.click('skip_booster') then go('closing') end
  elseif P.phase == 'closing' then
    if G.booster_pack or P.frames < 3 then return false end
    if st.when == 'shop' and not shop_settled() then return false end
    if st.when ~= 'shop' and G.STATE ~= G.STATES.BLIND_SELECT then return false end
    P.k = P.k + 1
    go('next')

  -- use_soul: a held Soul is used; a Soul taken from a pack was used when taken.
  elseif P.phase == 'use_soul' then
    if G.CONTROLLER.locks.use or G.CONTROLLER.locks.frame or P.frames < 2 then return false end
    local held
    for _, c in ipairs(G.consumeables and G.consumeables.cards or {}) do
      if c.config.center.key == 'c_soul' then held = c end
    end
    if held then
      P.legend0 = legendaries()
      G.FUNCS.use_card({config = {ref_table = held, button = 'use_card'}})
      go('used')
    else
      ctx.assert(legendaries() == P.taken, 'step '..P.k..': no Soul held and '..legendaries()
        ..' legendaries for '..P.taken..' Souls taken')
      ctx.log('step '..P.k..': the Soul was used when taken from its pack')
      P.k = P.k + 1
      go('next')
    end
  elseif P.phase == 'used' then
    if G.CONTROLLER.locks.use or legendaries() <= P.legend0 then return false end
    P.k = P.k + 1
    go('next')

  elseif P.phase == 'reroll' then
    if not shop_settled() or P.frames < 2 then return false end
    G.GAME.dollars = 999
    G.FUNCS.reroll_shop()
    go('rerolled')
  elseif P.phase == 'rerolled' then
    if not shop_settled() or P.frames < 3 then return false end
    if st.key then
      local c = G.shop_jokers.cards[st.slot]
      ctx.assert(c and c.config.center.key == st.key, 'step '..P.k..': reroll '..st.index..' slot '..st.slot
        ..' holds '..tostring(c and c.config.center.key)..', the step says '..st.key)
    end
    P.k = P.k + 1
    go('next')

  elseif P.phase == 'buy' then
    error('step '..P.k..': buy is not in this route')
  elseif P.phase == 'done' then
    ctx.assert(P.souls == S.souls and P.taken == S.souls, string.format('%d of %d Souls seen, %d taken',
      P.souls, S.souls, P.taken))
    ctx.assert(legendaries() == S.souls, legendaries()..' legendaries for '..S.souls..' Souls')
    ctx.log(string.format('route played: %d steps, %d Souls where the steps said; ended in %s ante %d',
      #S.route.steps, P.souls, tostring(G.STATE), G.GAME.round_resets.ante))
    ctx.log('check: route played')
    return true
  else
    error('step '..P.k..': unknown action '..tostring(P.phase))
  end
  return false
end

return {
  {name = 'speed up', run = function(ctx)
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    SaveSlots.settings.auto_checkpoints = false
    return true
  end},
  -- 1. The pinned hit and its route.
  {name = 'pinned hit', run = function(ctx)
    local ok, d = filter.eval_seed(F, SEED)
    ctx.assert(ok, SEED..': the filter does not hold')
    local r, err = route.build(F, d)
    ctx.assert(r, 'route.build: '..tostring(err))
    S.route, S.souls = r, 0
    for k, st in ipairs(r.steps) do
      if st.action == 'open_pack' and st.index then S.souls = S.souls + 1 end
      ctx.log(string.format('route %d: ante %d %s %s slot %s index %s key %s: %s', k, st.ante, st.when, st.action,
        tostring(st.slot), tostring(st.index), tostring(st.key), st.text))
    end
    ctx.log(string.format('cost: ante %d, %d rerolls, $%s', r.cost.ante, r.cost.rerolls, tostring(r.cost.dollars)))
    ctx.assert(S.souls == 2, 'the route takes '..S.souls..' Souls, not 2')
    S.short = ('A%d R%d'):format(r.cost.ante, r.cost.rerolls)
    for k, st in ipairs(r.steps) do
      ctx.assert(not st.text:find('Ante %d'), 'step '..k..' repeats its Ante heading: '..st.text)
      ctx.assert(not st.text:find('use it', 1, true), 'step '..k..' says to use a Soul: '..st.text)
      if st.action == 'use_soul' then
        ctx.assert(r.steps[k - 1].action == 'open_pack' and r.steps[k - 1].text:find('take it%.$'),
          'step '..(k - 1)..' before use_soul: '..r.steps[k - 1].text)
      end
    end
    -- Ranking: a miss listed first sorts after the hit.
    local MISS = 'FROUTEMISS'
    ctx.assert(not filter.eval_seed(F, MISS), MISS..' hits the filter; pick another miss')
    ctx.assert(ui.set_results(F, {MISS, SEED}))
    local s = ui.search()
    ctx.assert(s.order and s.order[1] == 2 and s.order[2] == 1, 'the hit is not ranked first: order '
      ..tostring(s.order and table.concat(s.order, ' ')))
    ctx.assert(s.costs[2] and STR_PACK(s.costs[2]) == STR_PACK(r.cost) and s.costs[1] == nil,
      'ranked costs are not route.build\'s')
    ctx.log('check: ranked')
    ctx.assert(ui.set_results(F, {SEED}))
    ctx.assert(ui.search().found[1] == SEED and not ui.search().running, 'the pinned hit is not the search result')
    return true
  end},
  -- 2. The Find tab's Route.
  click('open play', 'setup_run', nil, function() return not G.OVERLAY_MENU end),
  {name = 'find tab', timeout = 5, run = function(ctx)
    if not uie('tab_but_Find') or ctx.step_time() < 0.5 then return false end
    return ctx.click('change_tab', 'tab_but_Find')
  end},
  {name = 'find tab hit', timeout = 5, run = function(ctx)
    if not uie('seedfinder_tabroute_1') or ctx.step_time() < 1 then return false end
    local c = uie('seedfinder_tabcost_1')
    ctx.assert(c and c.config.text == S.short, 'Find tab cost: '..tostring(c and c.config.text)..', want '..S.short)
    ctx.shot('find_tab_hit')
    return true
  end},
  click('tab route', 'seedfinder_route', 'seedfinder_tabroute_1'),
  {name = 'tab route', timeout = 5, run = function(ctx)
    if not ui.route() or ctx.step_time() < 1 then return false end
    ctx.assert(ui.route().from == 'tab', 'the route does not know it came from the Find tab')
    check_panel(ctx, 'tab')
    ctx.shot('route_tab')
    return true
  end},
  -- Back in a frame of its own: the shot is drawn at the end of the frame above.
  click('tab back', 'seedfinder_route_back'),
  {name = 'back to the find tab', timeout = 5, run = function(ctx)
    if not uie('seedfinder_tab') or ctx.step_time() < 0.5 then return false end
    ctx.assert(not ui.route() and uie('seedfinder_tabroute_1'), 'Back did not land on the Find tab')
    ctx.log('check: tab route')
    return true
  end},
  -- 3. The overlay row's Route.
  click('open finder', 'seedfinder_open'),
  {name = 'hit row', timeout = 5, run = function(ctx)
    if not (ui.is_open() and uie('seedfinder_route_1')) or ctx.step_time() < 1 then return false end
    check_fits(ctx, 'hit row')
    local c = uie('seedfinder_cost_1')
    ctx.assert(c and c.config.text == S.short, 'hit row cost: '..tostring(c and c.config.text)..', want '..S.short)
    ctx.log('hit row cost: '..c.config.text)
    ctx.shot('hit_row')
    return true
  end},
  click('row route', 'seedfinder_route', 'seedfinder_route_1'),
  {name = 'route panel', timeout = 5, run = function(ctx)
    if not ui.route() or ctx.step_time() < 1 then return false end
    ctx.assert(ui.route().from == 'overlay', 'the route does not know it came from the overlay')
    check_panel(ctx, 'overlay')
    check_fits(ctx, 'route panel')
    ctx.log('cost line: '..uie('seedfinder_route_cost').config.text)
    ctx.log('check: route panel matches route.build')
    ctx.shot('route_panel')
    return true
  end},
  click('back', 'seedfinder_route_back', nil, function() return ui.route() end),
  click('route again', 'seedfinder_route', 'seedfinder_route_1', function()
    return ui.is_open() and uie('seedfinder_route_1')
  end),
  -- 4. Play, then the route's steps.
  click('route play', 'seedfinder_play', 'seedfinder_route_play', function() return ui.route() end),
  {name = 'play the route', timeout = 120, run = function(ctx)
    S.play = S.play or {k = 1, phase = 'wait_run', frames = 0, shop_n = 0, souls = 0, taken = 0}
    return play_route(ctx)
  end},
}
