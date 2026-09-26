-- Oracle divergence detector (T-323): the Oracle checks every shop, reroll
-- and opened shop pack against what its model predicted, and when play
-- leaves the policy it says where the prediction broke and why.
--   1. Start SEED (Red Deck, stake 1) and play it by the policy: win Small,
--      in its shop open both packs in slot order and skip them, reroll twice,
--      win Big, reroll its shop twice. Every check ran (2 per shop entry, 1
--      per pack, 1 per reroll: 10) and none broke: no divergence, and the
--      Oracle opened there shows no banner -> "check: no banner by policy".
--   2. A second run of SEED: in the first shop, buy the first shop joker,
--      then reroll. SEED is pinned so that the bought joker is what reroll 1
--      would have drawn (the live pool no longer has it): the reroll breaks.
--      The record says ante 1 shop 1, 'reroll 1', expected = predict.reroll on
--      a capture taken before the purchase (the shelf in bh_shop), got = the
--      row on screen, likely = "bought <that joker>" -> "check: divergence
--      recorded". The detector re-anchored once and invalidated once: a
--      second reroll matches the recomputed prediction (no new divergence).
--      The Oracle opened there shows the banner with those names ->
--      "check: banner shown".
--   3. Play on through Big and the Boss: their shops match (the tracker was
--      re-anchored on the live run), and at ante 2 the banner is gone ->
--      "check: banner cleared at the next ante".
-- Screenshots: diverge_policy.png (no banner), diverge_banner.png.
-- SEED was found offline by a one-off probe (invariant 8: no scan here):
-- ODIV0091's first shop is Scary Face + Smiley Face; reroll 1 draws Ride the
-- Bus + Scary Face, which becomes Ride the Bus + Misprint once Scary Face is
-- bought.
local state = require('bhcore.sim.state')
local predict = require('bhcore.sim.predict')
local oracle = require('seedoracle.oracle')
local ui = require('seedoracle.ui')

local SEED = 'ODIV0091'
local TURBO = 8

local base = {}       -- oracle.stats at a step's start, by name
local want_reroll     -- run 2: predict.reroll before the purchase
local bought          -- run 2: the joker bought

local function turbo()
  for _ = 1, TURBO do G:update(1/20) end
end

local function eq(ctx, what, want, got)
  ctx.log(string.format('%s: expected %s, got %s', what, tostring(want), tostring(got)))
  ctx.assert(want == got, what..': expected '..tostring(want)..', got '..tostring(got))
end

local function keys(list)
  local out = {}
  for i, r in ipairs(list or {}) do out[i] = r.key or (r.config and r.config.center.key) end
  return table.concat(out, ' ')
end

local function stats()
  local s = oracle.stats
  return {checks = s.checks, divergences = s.divergences, anchors = s.anchors, computes = s.computes}
end

local function blind_select_ready()
  return G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil and not G.CONTROLLER.locks.load
    and G.GAME.round_resets.blind_tags and G.GAME.round_resets.blind_tags.Big ~= nil
end

local function shop_ready()
  return G.STATE == G.STATES.SHOP and G.shop and G.shop_jokers and G.shop_booster
    and #G.shop_booster.cards == 2 and #G.shop_jokers.cards == G.GAME.shop.joker_max
    and not G.CONTROLLER.locks.toggle_shop and not G.CONTROLLER.locks.shop_reroll
end

local function shop_settled()
  return G.STATE == G.STATES.SHOP and G.shop and G.shop_booster and G.shop_jokers
    and not G.CONTROLLER.locks.shop_reroll and not G.CONTROLLER.locks.use
    and not G.CONTROLLER.locks.toggle_shop
end

local function select_button()
  local kind = G.GAME.blind_on_deck
  local box = G.blind_select_opts and kind and G.blind_select_opts[string.lower(kind)]
  local btn = box and box:get_UIE_by_ID('select_blind_button')
  if btn and btn.config.button == 'select_blind' then return btn, kind end
end

-- Plays blinds by the policy (chips needed set to 1, won with the first five
-- cards) until the shop after the blind `until_kind` is settled.
local function play_to_shop(until_kind)
  local p
  return function(ctx)
    p = p or {phase = 'select', frames = 0}
    turbo()
    p.frames = p.frames + 1
    local function go(phase) p.phase, p.frames = phase, 0 end
    if p.phase == 'select' then
      if G.STATE == G.STATES.SHOP and shop_settled() and p.frames >= 2 then
        ctx.click('toggle_shop') -- left over from an earlier step
        p.frames = 0
        return false
      end
      if not blind_select_ready() or p.frames < 2 then return false end
      local btn, kind = select_button()
      if not btn then return false end
      p.kind = kind
      G.FUNCS.select_blind(btn)
      go('play')
    elseif p.phase == 'play' then
      if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or p.frames < 2
        or G.CONTROLLER.locks.frame then return false end
      G.GAME.blind.chips = 1
      G.GAME.blind.chip_text = number_format(1)
      for i = 1, #G.hand.cards do
        if #G.hand.highlighted >= math.min(5, G.hand.config.highlighted_limit or 5) then break end
        if not G.hand.cards[i].highlighted then G.hand:add_to_highlighted(G.hand.cards[i]) end
      end
      G.FUNCS.play_cards_from_highlighted()
      go('cash_out')
    elseif p.phase == 'cash_out' then
      if G.STATE ~= G.STATES.ROUND_EVAL or p.frames < 2 then return false end
      if ctx.click('cash_out') then go('shop') end
    elseif p.phase == 'shop' then
      if not shop_ready() or p.frames < 2 then return false end
      if p.kind == until_kind then return true end
      if ctx.click('toggle_shop') then go('select') end
    end
    return false
  end
end

local PACK_STATES
local function in_pack_state()
  PACK_STATES = PACK_STATES or {[G.STATES.TAROT_PACK] = true, [G.STATES.PLANET_PACK] = true,
    [G.STATES.SPECTRAL_PACK] = true, [G.STATES.STANDARD_PACK] = true, [G.STATES.BUFFOON_PACK] = true}
  return PACK_STATES[G.STATE]
end

-- Opens each shop pack in slot order and skips it (the detector compares).
local function open_packs()
  local p
  return function(ctx)
    p = p or {phase = 'open', frames = 0, opened = 0}
    turbo()
    p.frames = p.frames + 1
    local function go(phase) p.phase, p.frames = phase, 0 end
    if p.phase == 'open' then
      if G.OVERLAY_MENU or not shop_settled() or p.frames < 2 then return false end
      if p.opened >= 2 then return true end
      local slot = p.opened + 1
      local booster
      for _, c in ipairs(G.shop_booster.cards) do
        if c.ability.booster_pos == slot then booster = c end
      end
      ctx.assert(booster, 'pack '..slot..' missing')
      p.opened, p.size = slot, booster.config.center.config.extra
      G.GAME.dollars = math.max(G.GAME.dollars, 50)
      G.FUNCS.use_card({config = {ref_table = booster, button = 'use_card'}})
      go('pack')
    elseif p.phase == 'pack' then
      if not in_pack_state() or not G.pack_cards or not G.pack_cards.cards
        or #G.pack_cards.cards < p.size or p.frames < 3 then return false end
      go('skip')
    elseif p.phase == 'skip' then
      if p.frames < 2 then return false end
      if ctx.click('skip_booster') then go('closing') end
    elseif p.phase == 'closing' then
      if G.booster_pack or not shop_settled() or p.frames < 3 then return false end
      go('open')
    end
    return false
  end
end

-- Rerolls the shop n times, each once the last one settled and was checked.
local function reroll(n)
  local p
  return function(ctx)
    p = p or {done = 0, frames = 0}
    turbo()
    p.frames = p.frames + 1
    if not shop_settled() or p.frames < 3 then return false end
    -- A reroll refills the row (a purchase may have emptied a slot before).
    if p.done > 0 and #G.shop_jokers.cards < G.GAME.shop.joker_max then return false end
    if p.done >= n then return true end
    G.GAME.dollars = math.max(G.GAME.dollars, 50)
    G.FUNCS.reroll_shop({})
    p.done, p.frames = p.done + 1, 0
    return false
  end
end

local function banner_text()
  local e = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('seedoracle_diverge')
  if not e then return nil end
  local lines = {}
  local function texts(n)
    if n.config and n.config.text then lines[#lines + 1] = n.config.text end
    for _, child in pairs(n.children or {}) do texts(child) end
  end
  texts(e)
  return table.concat(lines, ' / ')
end

local function joker_name(key)
  return localize{type = 'name_text', set = 'Joker', key = key}
end

local function run_start(tag)
  return {
    {name = tag..': start', run = function(ctx)
      base.start = stats()
      ctx.start_run{seed = SEED, stake = 1}
      return true
    end},
    {name = tag..': blind select', timeout = 20, run = function(ctx)
      if not (G.STAGE == G.STAGES.RUN and G.GAME.pseudorandom.seed == SEED and blind_select_ready()
        and ctx.step_time() > 1) then return false end
      ctx.assert(oracle.divergence() == nil, tag..': a divergence at the run start')
      eq(ctx, tag..': anchored once at the run start', base.start.anchors + 1, oracle.stats.anchors)
      return true
    end},
  }
end

local steps = {
  {name = 'speed up', run = function(ctx)
    ctx.assert(type(SeedOracle) == 'table', 'SeedOracle not loaded')
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    love.mouse.setPosition(4, 4)
    if SaveSlots and SaveSlots.settings then SaveSlots.settings.auto_checkpoints = false end
    return true
  end},
}
local function add(list) for _, s in ipairs(list) do steps[#steps + 1] = s end end

-- 1. By the policy.
add(run_start('policy'))
add{
  {name = 'policy: to the Small shop', timeout = 30, run = play_to_shop('Small')},
  {name = 'policy: shop 1 checked', run = function(ctx)
    return oracle.stats.checks >= base.start.checks + 2
  end},
  {name = 'policy: open the packs', timeout = 30, run = open_packs()},
  {name = 'policy: reroll twice', timeout = 20, run = reroll(2)},
  {name = 'policy: to the Big shop', timeout = 30, run = play_to_shop('Big')},
  {name = 'policy: shop 2 checked', run = function(ctx)
    return oracle.stats.checks >= base.start.checks + 8
  end},
  {name = 'policy: reroll shop 2 twice', timeout = 20, run = reroll(2)},
  {name = 'policy: no divergence', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    eq(ctx, 'policy: checks (2 per shop, 1 per pack, 1 per reroll)', base.start.checks + 10, oracle.stats.checks)
    eq(ctx, 'policy: divergences', base.start.divergences, oracle.stats.divergences)
    ctx.assert(oracle.divergence() == nil, 'policy: a divergence recorded')
    ctx.assert(ui.open(false), 'the Oracle did not open')
    return true
  end},
  {name = 'policy: no banner', run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 0.6 then return false end
    ctx.assert(banner_text() == nil, 'policy: a banner is shown: '..tostring(banner_text()))
    ctx.shot('diverge_policy')
    ctx.log('check: no banner by policy')
    return true
  end},
  -- Shots land at the end of the frame: close a step later.
  {name = 'policy: close the Oracle', run = function(ctx)
    ui.close()
    return not ui.is_open()
  end},
}

-- 2. Buy the first shop joker, then reroll.
add(run_start('buy'))
add{
  {name = 'buy: to the Small shop', timeout = 30, run = play_to_shop('Small')},
  {name = 'buy: shop 1 checked, buy', run = function(ctx)
    if oracle.stats.checks < base.start.checks + 2 or not shop_settled() then return false end
    eq(ctx, 'buy: no divergence at entry', base.start.divergences, oracle.stats.divergences)
    local S = state.capture()
    S.game.bh_shop = {}
    local card
    for _, c in ipairs(G.shop_jokers.cards) do
      S.game.bh_shop[#S.game.bh_shop + 1] = c.config.center.key
      if not card and c.ability.set == 'Joker' then card = c end
    end
    ctx.assert(card, 'no joker in the first shop')
    want_reroll = predict.reroll(S, 1)
    bought = card.config.center.key
    ctx.log('buying '..bought..'; reroll 1 predicted before the purchase: '..keys(want_reroll))
    G.GAME.dollars = math.max(G.GAME.dollars, 50)
    base.buy = stats()
    G.FUNCS.buy_from_shop({config = {ref_table = card}})
    return true
  end},
  {name = 'buy: bought', run = function(ctx)
    turbo()
    return shop_settled() and #G.jokers.cards == 1 and G.jokers.cards[1].config.center.key == bought
      and ctx.step_time() > 0.2
  end},
  {name = 'buy: reroll', timeout = 20, run = reroll(1)},
  {name = 'buy: divergence recorded', run = function(ctx)
    turbo()
    if oracle.stats.checks < base.buy.checks + 1 then return false end
    eq(ctx, 'buy: divergences', base.buy.divergences + 1, oracle.stats.divergences)
    local d = oracle.divergence()
    ctx.assert(d, 'buy: no divergence record')
    eq(ctx, 'record ante', 1, d.ante)
    eq(ctx, 'record shop', 1, d.shop)
    eq(ctx, 'record what', 'reroll 1', d.what)
    eq(ctx, 'record expected', keys(want_reroll), table.concat(d.expected_keys, ' '))
    eq(ctx, 'record got (the row on screen)', keys(G.shop_jokers.cards), table.concat(d.got_keys, ' '))
    ctx.assert(keys(want_reroll) ~= keys(G.shop_jokers.cards), 'the reroll did not change: the check proves nothing')
    eq(ctx, 'record likely', 'bought '..joker_name(bought), d.likely)
    ctx.log('check: divergence recorded')
    return true
  end},
  {name = 'buy: re-anchored', run = function(ctx)
    turbo()
    if oracle.stats.anchors < base.buy.anchors + 1 then return false end
    base.anchored = stats()
    return true
  end},
  {name = 'buy: reroll 2', timeout = 20, run = reroll(1)},
  {name = 'buy: reroll 2 matches the recomputed prediction', run = function(ctx)
    turbo()
    if oracle.stats.checks < base.anchored.checks + 1 then return false end
    eq(ctx, 'buy: divergences after reroll 2', base.buy.divergences + 1, oracle.stats.divergences)
    eq(ctx, 'buy: anchors after reroll 2 (one per divergence)', base.buy.anchors + 1, oracle.stats.anchors)
    ctx.assert(ui.open(false), 'the Oracle did not open')
    return true
  end},
  {name = 'buy: banner', run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 0.6 then return false end
    local t = banner_text()
    ctx.log('banner: '..tostring(t))
    ctx.assert(t, 'no banner')
    local d = oracle.divergence()
    local head = string.format('Prediction broke at ante 1 shop 1: expected %s, saw %s (likely: bought %s)',
      d.expected, d.got, joker_name(bought))
    ctx.assert(t:find(head, 1, true), 'banner: expected to start with "'..head..'"')
    ctx.assert(t:find('reroll 1', 1, true), 'banner: the reroll row is not named')
    ctx.shot('diverge_banner')
    ctx.log('check: banner shown')
    return true
  end},
  {name = 'buy: close the Oracle', run = function(ctx)
    ui.close()
    return not ui.is_open()
  end},

  -- 3. On to ante 2.
  {name = 'buy: to the Boss shop', timeout = 60, run = play_to_shop('Boss')},
  {name = 'buy: banner cleared', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    eq(ctx, 'ante', 2, G.GAME.round_resets.ante)
    eq(ctx, 'buy: checks through Big and the Boss shop', base.anchored.checks + 1 + 4, oracle.stats.checks)
    eq(ctx, 'buy: divergences after the Big and Boss shops', base.buy.divergences + 1, oracle.stats.divergences)
    ctx.assert(oracle.divergence() == nil, 'the banner outlived its ante')
    ctx.log('check: banner cleared at the next ante')
    return true
  end},
}

return steps
