-- Chained antes (seedfinder.filter header): a Charm-tag Soul and a shop Arcana
-- Soul in the same ante are one playthrough, checked against the real game.
--   1. The filter "ante 1: Soul in an Arcana from a tag skip AND Soul in a shop
--      Arcana" (Red Deck, stake 1) holds for both SEEDS; its details are the
--      prediction.
--   2. Play each hit by the filter's policy through ante 1: at each blind select,
--      skip the blind whose tag is the Charm Tag (the real Skip button; its Mega
--      Arcana opens at once) and play the others (chips set to 1). A tag pack is
--      compared card for card with the filter's details and closed with nothing
--      taken (skip_booster). In each shop: $999, open both packs in slot order
--      (vanilla use_card -> Card:open), close each with nothing taken, leave.
--      Stop at the Boss's blind select.
--   3. The Souls are where the details said: the tag pack's slot, and the shop
--      (by count and by the blind it follows), slot and index.
--      -> "check: finder_chain <seed> ok" per hit, then "check: finder_chain all".
local filter = require('seedfinder.filter')

-- Found by scanning FCHAIN1.. (5.5 min on the main thread), one per shape: the
-- Big Blind's Charm skipped after the Small's shop, and the Small's skipped
-- before the Big's shop.
local SEEDS = {'FCHAIN91662', 'FCHAIN717846'}
local HITS = #SEEDS
local F = {name = 'chain', deck = 'b_red', stake = 1, mode = 'all', clauses = {
  {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
  {kind = 'soul_in_pack', ante = 1, pack = 'arcana'},
}}

local hits = {}
local P -- the hit being played

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

local function turbo()
  for _ = 1, 8 do G:update(1/20) end
end

local function keys(cards)
  local out = {}
  for i, c in ipairs(cards) do out[i] = c.config.center.key end
  return out
end

local function play_hit(seed)
  local function go(phase) P.phase, P.frames = phase, 0 end
  return function(ctx)
    turbo()
    P.frames = P.frames + 1
    local waited = P.frames
    if P.phase == 'wait_run' then
      if not (G.STATE == G.STATES.BLIND_SELECT and G.GAME.pseudorandom.seed == seed and select_button())
        or waited < 3 then return false end
      go('blind')
    elseif P.phase == 'blind' then
      if G.STATE ~= G.STATES.BLIND_SELECT or waited < 3 or G.CONTROLLER.locks.skip_blind then return false end
      local kind = G.GAME.blind_on_deck
      if kind == 'Boss' then go('done'); return false end
      if G.GAME.round_resets.blind_tags[kind] == 'tag_charm' then
        local btn = panel_button(kind, 'skip_blind')
        if not btn then return false end
        P.skipped = kind
        G.FUNCS.skip_blind(btn)
        go('tag_pack')
      else
        local btn = select_button()
        if not btn then return false end
        P.played = kind
        G.FUNCS.select_blind(btn)
        go('play')
      end
    elseif P.phase == 'tag_pack' then
      if not (G.STATE == G.STATES.TAROT_PACK and G.pack_cards and G.pack_cards.cards and #G.pack_cards.cards >= (G.GAME.pack_size or 5))
        or waited < 3 then return false end
      local got = keys(G.pack_cards.cards)
      P.tag_n = P.tag_n + 1
      local want = P.tag.packs[P.tag_n]
      ctx.assert(want and want.blind == P.skipped, seed..': unexpected tag pack at '..P.skipped)
      ctx.log(seed..' '..P.skipped..' tag pack: predicted '..table.concat(want.cards, ' ')..'; real '..table.concat(got, ' '))
      ctx.assert(table.concat(want.cards, ' ') == table.concat(got, ' '), seed..': tag pack contents mismatch')
      if P.tag.blind == P.skipped then
        ctx.assert(got[P.tag.index] == 'c_soul', seed..': no Soul at tag pack slot '..P.tag.index)
        P.tag_soul = true
      end
      P.after_close = 'blind'
      go('close')
    elseif P.phase == 'play' then
      if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or waited < 2
        or G.CONTROLLER.locks.frame then return false end
      G.GAME.blind.chips = 1
      G.GAME.blind.chip_text = number_format(1)
      G.hand:add_to_highlighted(G.hand.cards[1])
      G.FUNCS.play_cards_from_highlighted()
      go('cash_out')
    elseif P.phase == 'cash_out' then
      if G.STATE ~= G.STATES.ROUND_EVAL or waited < 2 then return false end
      if ctx.click('cash_out') then go('shop') end
    elseif P.phase == 'shop' then
      if not shop_settled() or waited < 2 or #G.shop_booster.cards ~= 2 then return false end
      P.shop_n = P.shop_n + 1
      G.GAME.dollars = 999
      P.opened = 0
      ctx.log(seed..' shop '..P.shop_n..' after '..P.played..': packs '..table.concat(keys(G.shop_booster.cards), ' '))
      go('open')
    elseif P.phase == 'open' then
      if not shop_settled() or waited < 2 then return false end
      if P.opened >= 2 then go('leave'); return false end
      local slot = P.opened + 1
      local booster
      for _, c in ipairs(G.shop_booster.cards) do
        if c.ability.booster_pos == slot then booster = c end
      end
      ctx.assert(booster, seed..': booster '..slot..' missing')
      P.opened = slot
      G.FUNCS.use_card({config = {ref_table = booster, button = 'use_card'}})
      go('shop_pack')
    elseif P.phase == 'shop_pack' then
      if not in_pack_state() or not (G.pack_cards and G.pack_cards.cards)
        or #G.pack_cards.cards < (G.GAME.pack_size or 1)
        or waited < 3 then return false end
      local got = keys(G.pack_cards.cards)
      ctx.log(seed..' shop '..P.shop_n..' pack '..P.opened..': '..table.concat(got, ' '))
      local s = P.shop
      if P.shop_n == s.shop and P.opened == s.slot then
        ctx.assert(P.played == s.after, seed..': the Soul shop follows '..s.after..', this one '..P.played)
        ctx.assert(got[s.index] == 'c_soul', seed..': no Soul at shop '..s.shop..' pack '..s.slot..' slot '..s.index)
        P.shop_soul = true
      end
      P.after_close = 'open'
      go('close')
    elseif P.phase == 'close' then
      if waited < 2 or G.CONTROLLER.locks.frame then return false end
      if ctx.click('skip_booster') then go('closing') end
    elseif P.phase == 'closing' then
      if G.booster_pack or waited < 3 then return false end
      if P.after_close == 'open' and not shop_settled() then return false end
      go(P.after_close)
    elseif P.phase == 'leave' then
      if ctx.click('toggle_shop') then go('blind') end
    elseif P.phase == 'done' then
      ctx.assert(P.tag_n == #P.tag.packs, seed..': opened '..P.tag_n..' of '..#P.tag.packs..' tag packs')
      ctx.assert(P.tag_soul and P.shop_soul, seed..': a predicted Soul never showed up')
      ctx.log('check: finder_chain '..seed..' ok')
      return true
    end
    return false
  end
end

local steps = {
  {name = 'speed up', run = function(ctx)
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    SaveSlots.settings.auto_checkpoints = false
    return true
  end},
  {name = 'hits', run = function(ctx)
    for _, seed in ipairs(SEEDS) do
      local ok, d = filter.eval_seed(F, seed)
      ctx.assert(ok, seed..': the filter does not hold')
      hits[#hits + 1] = {seed = seed, tag = d.results[1], shop = d.results[2]}
      ctx.log(string.format('hit %s: tag Soul in the %s pack slot %d; shop Soul in shop %d (after %s) pack %d slot %d',
        seed, d.results[1].blind, d.results[1].index, d.results[2].shop, d.results[2].after,
        d.results[2].slot, d.results[2].index))
    end
    return true
  end},
}

for h = 1, HITS do
  steps[#steps + 1] = {name = 'start hit '..h, run = function(ctx)
    local hit = hits[h]
    P = {seed = hit.seed, tag = hit.tag, shop = hit.shop, tag_n = 0, shop_n = 0, frames = 0, phase = 'wait_run'}
    if G.GAME then G.GAME.viewed_back = Back(G.P_CENTERS.b_red) end
    ctx.start_run{seed = hit.seed, stake = 1}
    return true
  end}
  steps[#steps + 1] = {name = 'play hit '..h, timeout = 120, run = function(ctx) return play_hit(hits[h].seed)(ctx) end}
end

steps[#steps + 1] = {name = 'all', run = function(ctx)
  ctx.log('check: finder_chain all')
  return true
end}

return steps
