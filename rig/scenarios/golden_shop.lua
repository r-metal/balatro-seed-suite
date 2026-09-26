-- Golden shop (T-106): bhcore.sim.predict's shops, rerolls, packs and pack
-- contents against the real game, on 10 fixed seeds. The reference is always
-- the real run; the prediction is made from state.fresh(seed) before that run
-- exists.
--
-- Per seed (Red Deck; stake 1, or stake 8 for the Gold seeds, so eternal,
-- perishable and rental stickers are in play):
--   1. predict: fresh(seed), then predict.plan(S, {antes = 3, rerolls =
--      REROLLS, open_packs = true}) -- every stable and conditional call in the
--      game's order (predict.lua header).
--   2. play the real run with the same policy through antes 1 and 2: no skips,
--      no purchases. Each blind is selected, its chips needed set to 1, and won
--      by playing the first five cards in hand; then cash out and shop. In
--      every shop: $999 (so rerolls and packs are affordable), compare the row
--      of G.shop_jokers (key, edition, stickers, front/seal) and both packs of
--      G.shop_booster; reroll REROLLS times through G.FUNCS.reroll_shop,
--      comparing each new row; then open each pack in slot order through the
--      vanilla use_card -> Card:open flow, compare G.pack_cards with the
--      predicted contents once they land, and skip it (skip_booster, nothing
--      taken); then leave (toggle_shop).
--   Shops are named by the ante whose streams they draw (predict.lua header):
--   the shop after ante A's Boss comes after ease_ante, so it is "ante A+1
--   shop 1". Antes 1-2 played = 6 shops: ante 1 shops 1-2, ante 2 shops 1-3,
--   ante 3 shop 1. -> "check: golden_shop <seed> ante <a> shop <s> ok" each.
-- After the last seed: "check: golden_shop all 10 seeds match".
-- On any mismatch both values are logged and the scenario fails.
-- The run's first shop pack is vanilla's forced Buffoon, whose _1/_2 art
-- variant is unseeded math.random (cosmetic): either key is accepted for it.
-- Speed: vsync off, GAMESPEED 64, and extra Game:update passes per frame
-- (journal/2026-09-23-scripting-balatro-fast.md). Generation is keyed by the
-- seed's streams, never by time or frame count.
local state = require('bhcore.sim.state')
local predict = require('bhcore.sim.predict')

local SEEDS = {
  {'E67DHZM3', 1}, {'7LB2WVPK', 1}, {'SHOPGLD1', 1}, {'ZQ9Y8XW6', 1}, {'HNM4KD2P', 1},
  {'R2D2C3P9', 1}, {'PACKS4ME', 1}, {'GOLDST8K', 8}, {'QWERTY12', 8}, {'MNB5VCX4', 8},
}
local LAST_ANTE = 2 -- antes played in full; the Boss's shop is ante LAST_ANTE+1 shop 1
local REROLLS = 2
local SHOTS = {E67DHZM3 = true} -- screenshots for one seed only

local plan = {}   -- seed -> predict.plan result
local seen = {}   -- seed -> per-seed scratch for the multi-frame step
local P_CARD_KEY = nil

local function fail(ctx, seed, what, want, got)
  ctx.log(string.format('MISMATCH %s %s: predicted %s, real %s', seed, what, tostring(want), tostring(got)))
  ctx.assert(false, seed..': '..what..' mismatch (predicted '..tostring(want)..', real '..tostring(got)..')')
end

-- A live Card as a comparable record (the predict card shape).
local function real_rec(c)
  if not P_CARD_KEY then
    P_CARD_KEY = {}
    for k, v in pairs(G.P_CARDS) do P_CARD_KEY[v] = k end
  end
  local set = c.config.center.set
  return {key = c.config.center.key, edition = c.edition and c.edition.type or nil,
    eternal = c.ability.eternal and true or false, perishable = c.ability.perishable and true or false,
    rental = c.ability.rental and true or false, seal = c.seal,
    front = (set == 'Default' or set == 'Enhanced') and P_CARD_KEY[c.config.card] or nil}
end

local function pred_rec(p)
  local s = p.stickers or {}
  return {key = p.key, edition = p.edition, eternal = s.eternal and true or false,
    perishable = s.perishable and true or false, rental = s.rental and true or false,
    seal = p.seal, front = p.front}
end

local function fmt(r)
  local st = (r.eternal and 'E' or '')..(r.perishable and 'P' or '')..(r.rental and 'R' or '')
  local out = r.key
  if r.edition then out = out..'/'..r.edition end
  if st ~= '' then out = out..'['..st..']' end
  if r.front then out = out..'@'..r.front end
  if r.seal then out = out..'+'..r.seal..'seal' end
  return out
end

local function fmt_list(list)
  local out = {}
  for i, r in ipairs(list) do out[i] = fmt(r) end
  return table.concat(out, ' ')
end

-- Compares a predicted card list with the live cards of an area, in order.
local function compare_cards(ctx, seed, what, want, cards)
  local w, g = {}, {}
  for i, p in ipairs(want) do w[i] = pred_rec(p) end
  for i, c in ipairs(cards) do g[i] = real_rec(c) end
  local fw, fg = fmt_list(w), fmt_list(g)
  ctx.log(string.format('%s %s: predicted %s; real %s', seed, what, fw, fg))
  if fw ~= fg then fail(ctx, seed, what, fw, fg) end
  return #g
end

local function pack_key_ok(want, got)
  if want.forced then return got == 'p_buffoon_normal_1' or got == 'p_buffoon_normal_2' end
  return want.key == got
end

local function run_ready(seed)
  return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
    and G.GAME.pseudorandom and G.GAME.pseudorandom.seed == seed
    and G.GAME.round_resets.blind_tags and G.GAME.round_resets.blind_tags.Big ~= nil
    and not G.CONTROLLER.locks.load
end

-- The blind-select panel for the blind on deck, once its button is live.
local function select_button()
  local kind = G.GAME.blind_on_deck
  local box = G.blind_select_opts and kind and G.blind_select_opts[string.lower(kind)]
  local btn = box and box:get_UIE_by_ID('select_blind_button')
  if btn and btn.config.button == 'select_blind' then return btn, kind end
end

local TURBO = 8
local function turbo()
  for _ = 1, TURBO do G:update(1/20) end
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

-- Plays antes 1..LAST_ANTE by the policy, checking every shop on the way.
-- Done in the shop after ante LAST_ANTE's Boss, once that shop is checked.
local function play_step(seed)
  return function(ctx)
    turbo()
    local s = seen[seed]
    s.play = s.play or {phase = 'select', frames = 0, shops = {}}
    local p = s.play
    -- Frames (each TURBO+1 game updates) since the phase began: events advance
    -- per update, so a frame count settles as well as wall time and wastes none.
    p.frames = p.frames + 1
    local function go(phase) p.phase, p.frames = phase, 0 end
    local waited = p.frames

    if p.phase == 'select' then
      if G.STATE ~= G.STATES.BLIND_SELECT or waited < 2 then return false end
      local btn, kind = select_button()
      if not btn then return false end
      p.kind = kind
      G.FUNCS.select_blind(btn)
      go('play')
    elseif p.phase == 'play' then
      if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or waited < 2
        or G.CONTROLLER.locks.frame then return false end
      G.GAME.blind.chips = 1
      G.GAME.blind.chip_text = number_format(1)
      for i = 1, #G.hand.cards do
        if #G.hand.highlighted >= math.min(5, G.hand.config.highlighted_limit or 5) then break end
        if not G.hand.cards[i].highlighted then G.hand:add_to_highlighted(G.hand.cards[i]) end
      end
      ctx.assert(#G.hand.highlighted > 0, seed..': no cards highlighted')
      G.FUNCS.play_cards_from_highlighted()
      go('cash_out')
    elseif p.phase == 'cash_out' then
      if G.STATE ~= G.STATES.ROUND_EVAL or waited < 2 then return false end
      if not ctx.click('cash_out') then return false end
      go('shop')
    elseif p.phase == 'shop' then
      -- The shop is built by a delayed event; packs are the last cards placed.
      if not shop_settled() or waited < 2 or #G.shop_booster.cards ~= 2
        or #G.shop_jokers.cards ~= G.GAME.shop.joker_max then return false end
      local a = G.GAME.round_resets.ante
      p.shops[a] = (p.shops[a] or 0) + 1
      local n = p.shops[a]
      p.ante, p.n = a, n
      p.label = 'ante '..a..' shop '..n
      p.shop = plan[seed][a] and plan[seed][a].shops[n]
      ctx.assert(p.shop, seed..': no prediction for '..p.label)
      G.GAME.dollars = 999
      if SHOTS[seed] and n == 1 then ctx.shot('shop_ante_'..a) end
      compare_cards(ctx, seed, p.label..' row', p.shop.cards, G.shop_jokers.cards)
      local want, got = {}, {}
      for i = 1, 2 do
        local c = G.shop_booster.cards[i]
        want[i] = p.shop.packs[i].key..(p.shop.packs[i].forced and '(forced)' or '')
        got[i] = c.config.center.key
        ctx.assert(c.ability.booster_pos == i, seed..': booster slot order')
        if not pack_key_ok(p.shop.packs[i], got[i]) then
          fail(ctx, seed, p.label..' pack '..i, want[i], got[i])
        end
      end
      ctx.log(string.format('%s %s packs: predicted %s; real %s', seed, p.label,
        table.concat(want, ' '), table.concat(got, ' ')))
      p.rerolled, p.opened = 0, 0
      go('reroll')
    elseif p.phase == 'reroll' then
      if not shop_settled() or waited < 2 then return false end
      if p.rerolled >= REROLLS then go('open'); return false end
      p.rerolled = p.rerolled + 1
      p.old_row = {G.shop_jokers.cards[1], G.shop_jokers.cards[2]}
      G.FUNCS.reroll_shop()
      go('rerolled')
    elseif p.phase == 'rerolled' then
      if not shop_settled() or waited < 2 or #G.shop_jokers.cards ~= G.GAME.shop.joker_max
        or G.shop_jokers.cards[1] == p.old_row[1] then return false end
      compare_cards(ctx, seed, p.label..' reroll '..p.rerolled, p.shop.rerolls[p.rerolled].cards, G.shop_jokers.cards)
      go('reroll')
    elseif p.phase == 'open' then
      if not shop_settled() or waited < 2 then return false end
      if p.opened >= 2 then go('leave'); return false end
      local slot = p.opened + 1
      local booster
      for _, c in ipairs(G.shop_booster.cards) do
        if c.ability.booster_pos == slot then booster = c end
      end
      ctx.assert(booster, seed..': '..p.label..' booster '..slot..' missing')
      p.opened = slot
      p.pack = p.shop.packs[slot]
      G.FUNCS.use_card({config = {ref_table = booster, button = 'use_card'}})
      go('pack')
    elseif p.phase == 'pack' then
      if not in_pack_state() or not G.pack_cards or not G.pack_cards.cards
        or #G.pack_cards.cards < p.pack.size or waited < 3 then return false end
      if SHOTS[seed] and not p.pack_shot then p.pack_shot = true; ctx.shot('pack_'..p.pack.kind) end
      compare_cards(ctx, seed, p.label..' pack '..p.pack.index..' ('..p.pack.kind..') contents',
        plan[seed][p.ante].pack_contents[p.pack.index], G.pack_cards.cards)
      go('skip')
    elseif p.phase == 'skip' then
      if waited < 2 then return false end
      if ctx.click('skip_booster') then go('closing') end
    elseif p.phase == 'closing' then
      if G.booster_pack or not shop_settled() or waited < 3 then return false end
      go('open')
    elseif p.phase == 'leave' then
      ctx.log('check: golden_shop '..seed..' '..p.label..' ok')
      if p.kind == 'Boss' and p.ante > LAST_ANTE then return true end
      if not ctx.click('toggle_shop') then return false end
      go('select')
    end
    return false
  end
end

local steps = {
  {name = 'speed up', run = function(ctx)
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    return true
  end},
}

for _, sd in ipairs(SEEDS) do
  local seed, stake = sd[1], sd[2]
  steps[#steps + 1] = {name = 'predict and start '..seed, run = function(ctx)
    local before = STR_PACK(G.GAME)
    local S = state.fresh(seed, {stake = stake, deck = 'b_red'})
    plan[seed] = predict.plan(S, {antes = LAST_ANTE + 1, shops_per_ante = 3, rerolls = REROLLS, open_packs = true})
    ctx.assert(STR_PACK(G.GAME) == before, 'prediction touched the live G.GAME')
    seen[seed] = {}
    ctx.start_run{seed = seed, stake = stake}
    return true
  end}
  steps[#steps + 1] = {name = 'ready '..seed, timeout = 20, run = function(ctx)
    if not run_ready(seed) then return false end
    ctx.assert(G.GAME.stake == stake and G.GAME.selected_back.name == 'Red Deck',
      seed..': not stake '..stake..' Red Deck')
    return true
  end}
  steps[#steps + 1] = {name = 'play '..seed, timeout = 60, run = play_step(seed)}
end

steps[#steps + 1] = {name = 'all seeds', run = function(ctx)
  ctx.log('check: golden_shop all '..#SEEDS..' seeds match')
  return true
end}

return steps
