-- Golden vouchers: bhcore.sim.predict's voucher draws and shops after a
-- voucher purchase against the real game, on 10 seeds (the filter's voucher
-- clauses are bought: seedfinder.filter header, Policies; GitHub issue #1).
-- The prediction is made from state.fresh(seed) before the run exists. The
-- profile is the rig's new one with every voucher unlocked (a new profile has
-- no tier-2 voucher), read by the prediction and the run alike.
--
-- Policy: no skips; buy every voucher on offer (but Hieroglyph and
-- Petroglyph: state.REWINDS) in its ante's first shop, right after entering;
-- REROLLS rerolls per shop; open both packs, take nothing.
--   1. Seeds: for each TARGETS entry {voucher, deck, stake}, the first GV<i>
--      whose policy buys that voucher by ante 2, so every later shop shows
--      what it changes. Tier-2 vouchers (Overstock Plus, Glow Up, the
--      Tycoons, Illusion, Omen Globe) need their tier-1 bought first; Zodiac
--      starts with three tier-1s. -> "check: golden_vouchers seeds <list>"
--   2. predict: the voucher of each ante drawn with what was bought below it
--      redeemed (predict.voucher's used); each ante walked by
--      predict.ante_walk with its purchase (policy.voucher).
--   3. play antes 1-2 and the shop after ante 2's Boss (ante 3 shop 1). In
--      every shop: the voucher on offer is the predicted one until bought (and
--      none after); the purchase is made through use_card; then the row
--      (key, edition, stickers, front/seal) equals the walk's (Overstock's
--      slot filled at once), both packs' keys, each reroll's row, and each
--      pack's contents opened through use_card -> Card:open, skipped with
--      nothing taken. A Celestial pack opened with Telescope redeemed is not
--      compared: its first card is the planet of the hand played most, which
--      depends on play (predict.lua's Telescope note; no Finder clause reads
--      a Celestial pack). -> "check: golden_vouchers <seed> ante <a> shop
--      <s> ok" each, "check: golden_vouchers <seed> bought <key>" each.
-- After the last seed: "check: golden_vouchers all 10 seeds match".
local state = require('bhcore.sim.state')
local predict = require('bhcore.sim.predict')

local TARGETS = {
  {'v_overstock_plus', 'b_red', 1}, {'v_glow_up', 'b_red', 1}, {'v_tarot_tycoon', 'b_red', 1},
  {'v_planet_tycoon', 'b_red', 1}, {'v_illusion', 'b_red', 1}, {'v_omen_globe', 'b_red', 1},
  {'v_magic_trick', 'b_red', 1}, {'v_overstock_plus', 'b_red', 8},
  {'v_overstock_plus', 'b_zodiac', 1}, {'v_tarot_tycoon', 'b_zodiac', 1},
}
local LAST_ANTE = 2
local REROLLS = 2
local SEARCH = 40000

local chosen = {}  -- TARGETS index -> {seed, deck, stake}
local plan = {}    -- TARGETS index -> per-ante {voucher, buy, used, shops}
local seen = {}
local P_CARD_KEY = nil

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function rewinds(key)
  local v = G.P_CENTERS[key]
  return v and state.REWINDS[v.name]
end

-- Antes 1..LAST_ANTE+1 under the policy: each ante's voucher and purchase,
-- the vouchers redeemed by its shops, and (walk) its shops.
local function predict_run(seed, deck, stake, walk)
  local V = state.fresh(seed, {stake = stake, deck = deck})
  local W = walk and state.copy(V)
  local used, out = copy(V.game.used_vouchers or {}), {}
  for a = 1, LAST_ANTE + 1 do
    local v = predict.voucher(V, a, copy(used))
    local buy = not rewinds(v) and v or nil
    if buy then used[v] = true end
    out[a] = {voucher = v, buy = buy, used = copy(used)}
    if walk then
      out[a].shops = predict.ante_walk(W, a, {rerolls = REROLLS, open = true, voucher = buy}).shops
    end
  end
  return out
end

local function fail(ctx, seed, what, want, got)
  ctx.log(string.format('MISMATCH %s %s: predicted %s, real %s', seed, what, tostring(want), tostring(got)))
  ctx.assert(false, seed..': '..what..' mismatch (predicted '..tostring(want)..', real '..tostring(got)..')')
end

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

local function compare_cards(ctx, seed, what, want, cards)
  local w, g = {}, {}
  for i, p in ipairs(want) do w[i] = pred_rec(p) end
  for i, c in ipairs(cards) do g[i] = real_rec(c) end
  local fw, fg = fmt_list(w), fmt_list(g)
  ctx.log(string.format('%s %s: predicted %s; real %s', seed, what, fw, fg))
  if fw ~= fg then fail(ctx, seed, what, fw, fg) end
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
  return G.STATE == G.STATES.SHOP and G.shop and G.shop_booster and G.shop_jokers and G.shop_vouchers
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

local function play_step(i)
  return function(ctx)
    turbo()
    local seed = chosen[i].seed
    local s = seen[i]
    s.play = s.play or {phase = 'select', frames = 0, shops = {}, bought = {}}
    local p = s.play
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
      for k = 1, #G.hand.cards do
        if #G.hand.highlighted >= math.min(5, G.hand.config.highlighted_limit or 5) then break end
        if not G.hand.cards[k].highlighted then G.hand:add_to_highlighted(G.hand.cards[k]) end
      end
      G.FUNCS.play_cards_from_highlighted()
      go('cash_out')
    elseif p.phase == 'cash_out' then
      if G.STATE ~= G.STATES.ROUND_EVAL or waited < 2 then return false end
      if not ctx.click('cash_out') then return false end
      go('shop')
    elseif p.phase == 'shop' then
      if not shop_settled() or waited < 2 or #G.shop_booster.cards ~= 2
        or #G.shop_jokers.cards ~= G.GAME.shop.joker_max then return false end
      local a = G.GAME.round_resets.ante
      p.shops[a] = (p.shops[a] or 0) + 1
      local n = p.shops[a]
      p.ante, p.n = a, n
      p.label = 'ante '..a..' shop '..n
      p.rec = plan[i][a]
      p.shop = p.rec and p.rec.shops[n]
      ctx.assert(p.shop, seed..': no prediction for '..p.label)
      G.GAME.dollars = 999
      local offered = G.shop_vouchers.cards[1] and G.shop_vouchers.cards[1].config.center.key
      local want = not p.bought[a] and p.rec.voucher or nil
      if offered ~= want then fail(ctx, seed, p.label..' voucher', want, offered) end
      if n == 1 and p.rec.buy then
        G.FUNCS.use_card({config = {ref_table = G.shop_vouchers.cards[1]}})
        go('buying')
      else
        go('compare')
      end
    elseif p.phase == 'buying' then
      if not shop_settled() or waited < 4 or #G.shop_vouchers.cards > 0
        or #G.shop_jokers.cards < G.GAME.shop.joker_max then return false end
      ctx.assert(G.GAME.used_vouchers[p.rec.buy], seed..': '..p.rec.buy..' not redeemed')
      p.bought[p.ante] = true
      ctx.log('check: golden_vouchers '..seed..' bought '..p.rec.buy)
      go('compare')
    elseif p.phase == 'compare' then
      if not shop_settled() or waited < 2 then return false end
      compare_cards(ctx, seed, p.label..' row', p.shop.cards, G.shop_jokers.cards)
      local want, got = {}, {}
      for k = 1, 2 do
        local c = G.shop_booster.cards[k]
        want[k] = p.shop.packs[k].key..(p.shop.packs[k].forced and '(forced)' or '')
        got[k] = c.config.center.key
        if not pack_key_ok(p.shop.packs[k], got[k]) then fail(ctx, seed, p.label..' pack '..k, want[k], got[k]) end
      end
      p.rerolled, p.opened = 0, 0
      go('reroll')
    elseif p.phase == 'reroll' then
      if not shop_settled() or waited < 2 then return false end
      if p.rerolled >= REROLLS then go('open'); return false end
      p.rerolled = p.rerolled + 1
      p.old_row = G.shop_jokers.cards[1]
      G.FUNCS.reroll_shop()
      go('rerolled')
    elseif p.phase == 'rerolled' then
      if not shop_settled() or waited < 2 or #G.shop_jokers.cards ~= G.GAME.shop.joker_max
        or G.shop_jokers.cards[1] == p.old_row then return false end
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
      p.pack_size = booster.config.center.config.extra
      G.FUNCS.use_card({config = {ref_table = booster, button = 'use_card'}})
      go('pack')
    elseif p.phase == 'pack' then
      if not in_pack_state() or not G.pack_cards or not G.pack_cards.cards
        or #G.pack_cards.cards < p.pack_size or waited < 3 then return false end
      local what = p.label..' pack '..p.opened..' ('..p.pack.kind..') contents'
      if p.pack.kind == 'Celestial' and p.rec.used.v_telescope then
        ctx.log(seed..' '..what..': not compared (Telescope redeemed)')
      else
        compare_cards(ctx, seed, what, p.shop.contents[p.opened], G.pack_cards.cards)
      end
      go('skip')
    elseif p.phase == 'skip' then
      if waited < 2 then return false end
      if ctx.click('skip_booster') then go('closing') end
    elseif p.phase == 'closing' then
      if G.booster_pack or not shop_settled() or waited < 3 then return false end
      go('open')
    elseif p.phase == 'leave' then
      ctx.log('check: golden_vouchers '..seed..' '..p.label..' ok')
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
    SaveSlots.settings.auto_checkpoints = false
    for _, v in ipairs(G.P_CENTER_POOLS.Voucher) do v.unlocked = true end
    return true
  end},
  {name = 'choose seeds', timeout = 60, run = function(ctx)
    local names = {}
    for i, t in ipairs(TARGETS) do
      local key, deck, stake = t[1], t[2], t[3]
      for n = 1, SEARCH do
        local seed = 'GV'..n
        local run = predict_run(seed, deck, stake, false)
        local at
        for a = 1, LAST_ANTE do if run[a].buy == key then at = a end end
        if at then chosen[i] = {seed = seed, deck = deck, stake = stake}; break end
      end
      ctx.assert(chosen[i], 'no seed buys '..key..' by ante '..LAST_ANTE..' in '..SEARCH)
      names[i] = chosen[i].seed..'('..key..', '..deck..', stake '..stake..')'
    end
    ctx.log('check: golden_vouchers seeds '..table.concat(names, ' '))
    return true
  end},
}

for i = 1, #TARGETS do
  steps[#steps + 1] = {name = 'predict and start '..i, run = function(ctx)
    local c = chosen[i]
    local before = STR_PACK(G.GAME)
    plan[i] = predict_run(c.seed, c.deck, c.stake, true)
    ctx.assert(STR_PACK(G.GAME) == before, 'prediction touched the live G.GAME')
    local buys = {}
    for a = 1, LAST_ANTE + 1 do buys[a] = tostring(plan[i][a].buy or ('('..plan[i][a].voucher..' not bought)')) end
    ctx.log(c.seed..' buys '..table.concat(buys, ', '))
    seen[i] = {}
    G.GAME.viewed_back = Back(G.P_CENTERS[c.deck])
    ctx.start_run{seed = c.seed, stake = c.stake}
    return true
  end}
  steps[#steps + 1] = {name = 'ready '..i, timeout = 20, run = function(ctx)
    local c = chosen[i]
    if not run_ready(c.seed) then return false end
    ctx.assert(G.GAME.stake == c.stake and G.GAME.selected_back.name == G.P_CENTERS[c.deck].name,
      c.seed..': not stake '..c.stake..' '..G.P_CENTERS[c.deck].name)
    return true
  end}
  steps[#steps + 1] = {name = 'play '..i, timeout = 60, run = play_step(i)}
end

steps[#steps + 1] = {name = 'all seeds', run = function(ctx)
  ctx.log('check: golden_vouchers all '..#TARGETS..' seeds match')
  return true
end}

return steps
