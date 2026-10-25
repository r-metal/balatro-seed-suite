-- A tag clause is taken (seedfinder.filter header: Policies, tag clauses):
-- the player skips its blind, and the walk and the route skip it too. The
-- filter is a user's (Ghost Deck, Blue Stake): the Investment Tag on ante 1's
-- Small, the Soul in the ante-1 Charm pack, Perkeo from the first Soul, Baron
-- by ante 4.
--   1. 35MNWDIH is not a hit: its Charm pack holds the Soul only after the
--      Small Blind's shop opened an Arcana pack, and taking the Investment Tag
--      skips that shop (0.4.0 reported it). YP48F22F is a hit, and its route
--      skips both ante-1 blinds (Investment, then Charm).
--      -> "check: 35MNWDIH not a hit", "check: YP48F22F route skips both"
--   2. YP48F22F is played in the real game by its route: every step as
--      finder_route plays it (skip, play, open_pack with take, use_soul,
--      reroll), and between steps only the game's glue: a blind no step names
--      is played (chips set to 1) and its shop left untouched. The Soul, its
--      legendary and the Baron are where the steps say.
--      -> "check: soul at step <k>", "check: take at step <k>", "check: route played"
local filter = require('seedfinder.filter')
local route = require('seedfinder.route')

local F = {name = 'take', deck = 'b_ghost', stake = 5, all_unlocked = false, mode = 'all', clauses = {
  {kind = 'tag', ante = 1, blind = 'Small', key = 'tag_investment'},
  {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
  {kind = 'legendary', index = 1, key = 'j_perkeo'},
  {kind = 'joker', ante = 4, key = 'j_baron', rerolls = 0, from = 'both'},
}}
local MISS, HIT = '35MNWDIH', 'YP48F22F'

local S = {}

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

local PACK_STATES
local function in_pack_state()
  if not PACK_STATES then
    PACK_STATES = {[G.STATES.TAROT_PACK] = true, [G.STATES.PLANET_PACK] = true,
      [G.STATES.SPECTRAL_PACK] = true, [G.STATES.STANDARD_PACK] = true, [G.STATES.BUFFOON_PACK] = true}
    -- Steamodded opens every pack in its own state (rig/lovely-rig.sh --smods).
    if G.STATES.SMODS_BOOSTER_OPENED then PACK_STATES[G.STATES.SMODS_BOOSTER_OPENED] = true end
  end
  return PACK_STATES[G.STATE]
end

-- All n cards of the open pack are out (Steamodded reuses pack_size for picks).
local function pack_dealt(n)
  return in_pack_state() and G.pack_cards and G.pack_cards.cards and #G.pack_cards.cards >= n
    and not G.CONTROLLER.locks.frame
end

local function keys(cards)
  local out = {}
  for i, c in ipairs(cards) do out[i] = c.config.center.key end
  return out
end

local function jokers()
  return keys(G.jokers and G.jokers.cards or {})
end

local function turbo() for _ = 1, 8 do G:update(1/20) end end

-- The blind a step is played or skipped at, as blind select shows it: a
-- 'Boss' play step is the Boss of its own ante (its shop draws the next's).
local function step_blind(st)
  if st.action == 'skip' or st.action == 'play' then return st.ante, st.when end
end

local function play_route(ctx)
  turbo()
  local P, r = S.play, S.route
  P.frames = P.frames + 1
  local function go(ph) P.phase, P.frames = ph, 0 end
  local st = r.steps[P.k]
  if P.phase == 'wait_run' then
    if not (G.STATE == G.STATES.BLIND_SELECT and G.GAME.pseudorandom.seed == HIT and select_button())
      or P.frames < 3 then return false end
    ctx.assert(G.GAME.selected_back.name == 'Ghost Deck' and G.GAME.stake == 5, 'not Ghost Deck at Blue Stake')
    go('next')
    return false
  end
  if P.phase == 'next' then
    if not st then go('done'); return false end
    local a, blind = step_blind(st)
    if a then
      -- Glue: leave any shop; play every blind before the step's own.
      if G.STATE == G.STATES.SHOP then
        if shop_settled() and P.frames > 2 and ctx.click('toggle_shop') then P.frames = 0 end
        return false
      end
      if G.STATE ~= G.STATES.BLIND_SELECT or P.frames < 3 or G.CONTROLLER.locks.skip_blind then return false end
      local here, on = G.GAME.round_resets.ante, G.GAME.blind_on_deck
      if here < a or (here == a and on ~= blind) then
        local btn = select_button()
        if not btn then return false end
        ctx.log(('glue: play ante %d %s'):format(here, on))
        G.FUNCS.select_blind(btn)
        P.glue = true
        go('hand')
        return false
      end
      ctx.assert(here == a and on == blind, ('step %d: at ante %d %s, the step says ante %d %s')
        :format(P.k, here, tostring(on), a, blind))
    end
    go(st.action)
    return false
  end
  if P.phase == 'skip' then
    ctx.assert(G.GAME.round_resets.blind_tags[st.when] == st.key, 'step '..P.k..': the '..st.when..' tag is '
      ..tostring(G.GAME.round_resets.blind_tags[st.when])..', the step says '..tostring(st.key))
    local btn = panel_button(st.when, 'skip_blind')
    if not btn then return false end
    G.FUNCS.skip_blind(btn)
    P.k = P.k + 1
    go('next')
  elseif P.phase == 'play' then
    local btn = select_button()
    if not btn then return false end
    G.FUNCS.select_blind(btn)
    P.glue = false
    go('hand')
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
    ctx.log(('ante %d shop: row %s; packs %s'):format(G.GAME.round_resets.ante,
      table.concat(keys(G.shop_jokers.cards), ' '), table.concat(keys(G.shop_booster.cards), ' ')))
    if not P.glue then P.k = P.k + 1 end
    go('next')
  elseif P.phase == 'open_pack' then
    if st.when == 'shop' then
      if not shop_settled() or P.frames < 2 then return false end
      local booster
      for _, c in ipairs(G.shop_booster.cards) do
        if c.ability.booster_pos == st.slot then booster = c end
      end
      ctx.assert(booster, 'step '..P.k..': no shop pack in slot '..tostring(st.slot))
      local key = booster.config.center.key
      ctx.assert(st.key == nil or st.key == key, 'step '..P.k..': slot '..st.slot..' holds '..key
        ..', the step says '..tostring(st.key))
      P.size = booster.config.center.config.extra
      G.FUNCS.use_card({config = {ref_table = booster, button = 'use_card'}})
    else
      P.size = G.P_CENTERS[st.key].config.extra
    end
    go('pack')
  elseif P.phase == 'pack' then
    if not pack_dealt(P.size) or P.frames < 3 then return false end
    local got = keys(G.pack_cards.cards)
    ctx.log(('step %d pack: %s'):format(P.k, table.concat(got, ' ')))
    if st.index then
      local want = st.take or 'c_soul'
      ctx.assert(got[st.index] == want, ('step %d: card %d is %s, not %s'):format(P.k, st.index,
        tostring(got[st.index]), want))
      ctx.log((st.take and 'check: take at step ' or 'check: soul at step ')..P.k)
      P.jokers0 = #jokers()
      G.FUNCS.use_card({config = {ref_table = G.pack_cards.cards[st.index], button = 'use_card'}})
      go('taken')
    else
      go('close')
    end
  elseif P.phase == 'taken' then
    if G.CONTROLLER.locks.use or G.CONTROLLER.locks.frame or P.frames < 3 then return false end
    if #jokers() <= P.jokers0 then return false end
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
  elseif P.phase == 'use_soul' then
    -- A Soul taken from a pack is used by the taking (its joker is checked).
    P.k = P.k + 1
    go('next')
  else
    ctx.assert(P.phase == 'done', 'step '..P.k..': unexpected action '..tostring(P.phase))
    local have = table.concat(jokers(), ' ')
    ctx.assert(have:find('j_perkeo', 1, true) and have:find('j_baron', 1, true), 'jokers: '..have)
    ctx.log('route played: jokers '..have)
    ctx.log('check: route played')
    return true
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
  {name = 'eval', timeout = 30, run = function(ctx)
    local ok, d = filter.eval_seed(F, MISS)
    ctx.assert(not ok, MISS..' is a hit: taking the Investment Tag skips the shop its Soul needs')
    ctx.assert(d.results[2] and d.results[2].ok == false, MISS..': the Charm clause should be the one that fails')
    ctx.log('check: '..MISS..' not a hit')
    local okh, dh = filter.eval_seed(F, HIT)
    ctx.assert(okh, HIT..' is not a hit')
    ctx.assert(dh.skips and dh.skips[1] and dh.skips[1].Small == 'tag_investment' and dh.skips[1].Big == 'tag_charm',
      HIT..': the walk does not skip both ante-1 blinds')
    local r = assert(route.build(F, dh))
    for k, st in ipairs(r.steps) do
      ctx.log(('route %d: ante %d %s %s slot %s index %s key %s: %s'):format(k, st.ante, st.when, st.action,
        tostring(st.slot), tostring(st.index), tostring(st.key), st.text))
    end
    local a = {}
    for i = 1, 3 do a[i] = r.steps[i].action..'/'..r.steps[i].when end
    ctx.assert(table.concat(a, ' ') == 'skip/Small skip/Big open_pack/Big', 'route starts '..table.concat(a, ' '))
    ctx.assert(r.steps[1].key == 'tag_investment' and r.steps[2].key == 'tag_charm', 'skip keys')
    ctx.assert(r.steps[#r.steps].take == 'j_baron', 'the route ends taking '..tostring(r.steps[#r.steps].take))
    ctx.log('check: '..HIT..' route skips both')
    S.route = r
    return true
  end},
  {name = 'start', run = function(ctx)
    if G.GAME then G.GAME.viewed_back = Back(G.P_CENTERS.b_ghost) end
    ctx.start_run{seed = HIT, stake = 5}
    S.play = {k = 1, phase = 'wait_run', frames = 0}
    return true
  end},
  {name = 'play the route', timeout = 240, run = play_route},
}
