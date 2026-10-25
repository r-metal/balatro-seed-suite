-- Voucher clauses are bought (seedfinder.filter header: Policies, voucher
-- clauses; GitHub issue #1, tier-2 vouchers never found): a tier-2 voucher
-- only shows once its tier-1 is bought, and what a purchase changes shows in
-- every shop after it. The filter: Overstock Plus by ante 5 and Hone by ante
-- 5, Red Deck, White Stake, on the rig's new profile with every voucher
-- unlocked (a new profile has no tier-2 voucher; its locked jokers stay
-- locked, so the filter reads the profile, not All unlocked).
--   1. The first FVOUCH<i> seed that is a hit. Its route buys Overstock,
--      Overstock Plus and Hone, each as a redeem step in its ante's first
--      shop, Overstock's saying Overstock Plus needs it.
--      -> "check: hit <seed>"
--   2. The seed is played in the real game: every blind played (chips set to
--      1, five cards), and in every shop up to the route's last ante:
--        - the voucher on offer is the one predicted for the ante
--          (predict.voucher with the purchases below it redeemed) until it is
--          bought, and none after;
--        - a redeem step's voucher is bought (use_card); then the row is
--          predict.ante_walk's for the ante with that purchase (Overstock's
--          and Overstock Plus's new slot filled at once, Hone's editions);
--        - one reroll, whose row is the walk's too.
--      -> "check: shop <ante>.<s>" per shop, "check: bought <key>" per
--         purchase, "check: route played"
-- Under Steamodded (rig/lovely-rig.sh --smods) rows are compared by key only:
-- it makes vanilla's cards but rolls editions its own way (README,
-- Compatibility), and the Finder ignores editions there.
local filter = require('seedfinder.filter')
local route = require('seedfinder.route')
local predict = require('bhcore.sim.predict')

local F = {name = 'vouchers', deck = 'b_red', stake = 1, all_unlocked = false, mode = 'all', clauses = {
  {kind = 'voucher', ante = 5, key = 'v_overstock_plus', by = true},
  {kind = 'voucher', ante = 5, key = 'v_hone', by = true},
}}

local S = {}

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function edition_name(e)
  if type(e) ~= 'table' then return nil end
  for _, name in ipairs{'negative', 'polychrome', 'holo', 'foil'} do
    if e[name] then return name end
  end
end

-- A row as 'key/edition' words (keys only under Steamodded): predicted cards
-- carry edition = <name>, real ones an edition table.
local function fmt(cards, real)
  local out = {}
  for i, c in ipairs(cards or {}) do
    local key = real and c.config.center.key or c.key
    local ed = real and edition_name(c.edition) or (not real and c.edition) or nil
    if SMODS then ed = nil end
    out[i] = key..(ed and '/'..ed or '')
  end
  return table.concat(out, ' ')
end

-- What every ante up to last should show: its voucher, drawn with the
-- purchases below it redeemed, and its shops walked with its own purchase.
local function expected(seed, bought, last)
  local V, W = filter.fresh(F, seed), filter.fresh(F, seed)
  local used, out = {}, {}
  for a = 1, last do
    local v = predict.voucher(V, a, copy(used))
    if bought[a] then
      assert(bought[a] == v, 'ante '..a..': the eval bought '..bought[a]..', the draw is '..v)
      used[v] = true
    end
    local w = predict.ante_walk(W, a, {rerolls = 1, open = false, voucher = bought[a]})
    out[a] = {voucher = v, shops = w.shops}
  end
  return out
end

local function select_button()
  local kind = G.GAME.blind_on_deck
  local box = G.blind_select_opts and kind and G.blind_select_opts[string.lower(kind)]
  local btn = box and box:get_UIE_by_ID('select_blind_button')
  if btn and btn.config.button == 'select_blind' then return btn, kind end
end

local function shop_settled()
  return G.STATE == G.STATES.SHOP and G.shop and G.shop_booster and G.shop_jokers and G.shop_vouchers
    and not G.CONTROLLER.locks.shop_reroll and not G.CONTROLLER.locks.use
    and not G.CONTROLLER.locks.toggle_shop
end

local function turbo() for _ = 1, 8 do G:update(1/20) end end

local function play(ctx)
  turbo()
  local P = S.play
  P.frames = P.frames + 1
  local function go(ph) P.phase, P.frames = ph, 0 end
  if P.phase == 'wait_run' then
    if not (G.STATE == G.STATES.BLIND_SELECT and G.GAME.pseudorandom.seed == S.seed and select_button())
      or P.frames < 3 then return false end
    go('blind')
  elseif P.phase == 'blind' then
    if G.STATE ~= G.STATES.BLIND_SELECT or P.frames < 3 or G.CONTROLLER.locks.skip_blind then return false end
    local btn = select_button()
    if not btn then return false end
    G.FUNCS.select_blind(btn)
    go('hand')
  elseif P.phase == 'hand' then
    if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or P.frames < 2
      or G.CONTROLLER.locks.frame then return false end
    G.GAME.blind.chips = 1
    G.GAME.blind.chip_text = number_format(1)
    for i = 1, math.min(5, #G.hand.cards) do G.hand:add_to_highlighted(G.hand.cards[i]) end
    G.FUNCS.play_cards_from_highlighted()
    go('cash_out')
  elseif P.phase == 'cash_out' then
    if G.STATE ~= G.STATES.ROUND_EVAL or P.frames < 2 then return false end
    if ctx.click('cash_out') then go('shop') end
  elseif P.phase == 'shop' then
    if not shop_settled() or P.frames < 3 then return false end
    local a = G.GAME.round_resets.ante
    P.shop_i[a] = (P.shop_i[a] or 0) + 1
    local s = P.shop_i[a]
    local e = S.want[a]
    ctx.assert(e and e.shops[s], ('ante %d shop %d: past the route (last ante %d)'):format(a, s, S.last))
    P.a, P.s, P.e = a, s, e.shops[s]
    local offered = G.shop_vouchers.cards[1] and G.shop_vouchers.cards[1].config.center.key
    local want = not P.redeemed[a] and e.voucher or nil
    ctx.assert(offered == want, ('ante %d shop %d: the voucher on offer is %s, predicted %s')
      :format(a, s, tostring(offered), tostring(want)))
    G.GAME.dollars = 999
    if P.e.voucher then
      ctx.assert(offered == P.e.voucher, 'ante '..a..': the purchase is not on offer')
      ctx.log(('ante %d shop %d: buying %s; row %s'):format(a, s, offered, fmt(G.shop_jokers.cards, true)))
      G.FUNCS.use_card({config = {ref_table = G.shop_vouchers.cards[1]}})
      go('bought')
    else
      go('row')
    end
  elseif P.phase == 'bought' then
    if not shop_settled() or P.frames < 4 or #G.shop_vouchers.cards > 0
      or #G.shop_jokers.cards < G.GAME.shop.joker_max then return false end
    ctx.assert(G.GAME.used_vouchers[P.e.voucher], P.e.voucher..' not redeemed')
    P.redeemed[P.a] = true
    P.n_bought = P.n_bought + 1
    ctx.log('check: bought '..P.e.voucher)
    go('row')
  elseif P.phase == 'row' then
    if not shop_settled() or P.frames < 2 then return false end
    local got, want = fmt(G.shop_jokers.cards, true), fmt(P.e.cards)
    ctx.assert(got == want, ('ante %d shop %d row: %s, predicted %s'):format(P.a, P.s, got, want))
    G.GAME.dollars = 999
    G.FUNCS.reroll_shop()
    go('rerolled')
  elseif P.phase == 'rerolled' then
    if not shop_settled() or P.frames < 3 then return false end
    local got, want = fmt(G.shop_jokers.cards, true), fmt(P.e.rerolls[1].cards)
    ctx.assert(got == want, ('ante %d shop %d reroll: %s, predicted %s'):format(P.a, P.s, got, want))
    ctx.log(('check: shop %d.%d (%s)'):format(P.a, P.s, want))
    if P.a == S.last and P.redeemed[P.a] then go('done'); return false end
    if ctx.click('toggle_shop') then go('blind') end
  elseif P.phase == 'done' then
    ctx.assert(P.n_bought == S.n_bought, P.n_bought..' of '..S.n_bought..' purchases made')
    ctx.log(('route played: %d purchases where the route said, %d antes of shops as predicted')
      :format(P.n_bought, S.last))
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
    -- The profile the filter and the run both read: tier-2 vouchers unlocked.
    for _, v in ipairs(G.P_CENTER_POOLS.Voucher) do v.unlocked = true end
    return true
  end},
  {name = 'eval', timeout = 60, run = function(ctx)
    local seed, d
    for i = 1, 5000 do
      local ok, det = filter.eval_seed(F, 'FVOUCH'..i)
      if ok then seed, d = 'FVOUCH'..i, det; break end
    end
    ctx.assert(seed, 'no hit in 5000 seeds')
    local r = assert(route.build(F, d))
    local keys, n = {}, 0
    for a, k in pairs(d.bought) do keys[k] = a; n = n + 1 end
    ctx.assert(n == 3 and keys.v_overstock_norm and keys.v_overstock_plus and keys.v_hone,
      seed..': the walk should buy Overstock, Overstock Plus and Hone')
    ctx.assert(keys.v_overstock_norm < keys.v_overstock_plus, seed..': Overstock after Overstock Plus')
    local redeems = 0
    for k, st in ipairs(r.steps) do
      ctx.log(('route %d: ante %d %s %s key %s: %s'):format(k, st.ante, st.when, st.action, tostring(st.key), st.text))
      if st.action == 'redeem' then
        redeems = redeems + 1
        ctx.assert(d.bought[st.ante] == st.key, 'route '..k..': redeem '..st.key..' at ante '..st.ante)
        if st.key == 'v_overstock_norm' then
          ctx.assert(st.text:find('(Overstock Plus needs it)', 1, true), 'route '..k..': '..st.text)
        end
      end
    end
    ctx.assert(redeems == 3, redeems..' redeem steps')
    S.seed, S.last, S.n_bought = seed, r.cost.ante, n
    S.want = expected(seed, d.bought, S.last)
    ctx.log('check: hit '..seed)
    return true
  end},
  {name = 'start', run = function(ctx)
    ctx.start_run{seed = S.seed, stake = 1}
    S.play = {phase = 'wait_run', frames = 0, shop_i = {}, redeemed = {}, n_bought = 0}
    return true
  end},
  {name = 'play the route', timeout = 240, run = play},
}
