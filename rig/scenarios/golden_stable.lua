-- Golden stable (T-103): bhcore.sim.predict's stable streams against the real
-- game, on 10 fixed seeds. The reference is always the real run; the
-- prediction is made from state.fresh(seed) before that run exists.
--
-- Per seed (stake 1, Red Deck):
--   1. predict: fresh(seed), then in the game's order (predict.lua header):
--      boss 1, voucher 1, tags 1, legendaries(S, 2), then voucher, tags, boss
--      for antes 2 and 3.
--   2. start the real run; at blind select compare ante 1 against
--      round_resets.blind_tags, round_resets.blind_choices.Boss and
--      current_round.voucher. -> "check: golden_stable <seed> ante 1 ok"
--   3. create two Soul cards the vanilla way (create_card('Spectral', ...,
--      'c_soul')) and use them one at a time through G.FUNCS.use_card; the two
--      jokers they make (key and edition) must equal legendaries(S, 2).
--      -> "check: golden_stable <seed> souls ok"
--   4. play antes 1 to 3 with a fixed policy: no skips, no rerolls, no
--      purchases, no packs opened. Each blind is selected, its chips needed set
--      to 1, and won by playing the first five cards in hand; then cash out,
--      shop, next round. Ante A+1's voucher, tags and boss are drawn when ante
--      A's Boss is beaten (end_round + cash_out), so they are compared in the
--      shop that follows. -> "... ante 2 ok", "... ante 3 ok". The seed is done
--      in the shop after ante 3's Boss.
-- After the last seed: "check: golden_stable all 10 seeds match".
-- On any mismatch both values are logged and the scenario fails.
-- Speed: vsync off, GAMESPEED 64, and while playing, extra Game:update passes
-- per frame (turbo below); otherwise 10 seeds do not fit the rig's 120 s wall
-- clock. None of it changes what the game generates: generation is keyed by
-- the seed's streams, never by time or frame count.
local state = require('bhcore.sim.state')
local predict = require('bhcore.sim.predict')

local SEEDS = {'E67DHZM3', '7LB2WVPK', 'SIMTAGS1', 'ZQ9Y8XW6', 'HNM4KD2P',
  'R2D2C3P9', 'TAGBSVCH', 'LGNDRY77', 'QWERTY12', 'MNB5VCX4'}
local ANTES = 3
local SHOTS = {E67DHZM3 = true} -- screenshots for one seed only

local pred = {}   -- seed -> {antes = {[a] = {small, big, boss, voucher}}, legendaries}
local seen = {}   -- per-seed scratch for the multi-frame steps

local function fail(ctx, seed, what, want, got)
  ctx.log(string.format('MISMATCH %s %s: predicted %s, real %s', seed, what, tostring(want), tostring(got)))
  ctx.assert(false, seed..': '..what..' mismatch (predicted '..tostring(want)..', real '..tostring(got)..')')
end

-- Compares ante `a` against what the live run holds right now.
local function compare_ante(ctx, seed, a)
  local p, rr = pred[seed].antes[a], G.GAME.round_resets
  ctx.assert(rr.ante == a, seed..': live ante is '..tostring(rr.ante)..', expected '..a)
  local real = {small = rr.blind_tags.Small, big = rr.blind_tags.Big,
    boss = rr.blind_choices.Boss, voucher = G.GAME.current_round.voucher}
  ctx.log(string.format('%s ante %d: predicted %s/%s boss %s voucher %s; real %s/%s boss %s voucher %s',
    seed, a, p.small, p.big, p.boss, p.voucher, real.small, real.big, real.boss, real.voucher))
  for _, f in ipairs{'small', 'big', 'boss', 'voucher'} do
    if type(real[f]) ~= 'string' or p[f] ~= real[f] then fail(ctx, seed, 'ante '..a..' '..f, p[f], real[f]) end
  end
  ctx.log('check: golden_stable '..seed..' ante '..a..' ok')
end

local function run_ready(seed)
  return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
    and G.GAME.pseudorandom and G.GAME.pseudorandom.seed == seed
    and G.GAME.round_resets.blind_tags and G.GAME.round_resets.blind_tags.Big ~= nil
    and not G.CONTROLLER.locks.load
end

local function predict_seed(seed)
  local S = state.fresh(seed, {stake = 1, deck = 'b_red'})
  local antes = {}
  -- Ante 1, Game:start_run's order: boss, voucher, Small tag, Big tag.
  local boss = predict.boss(S, 1)
  local voucher = predict.voucher(S, 1)
  local tags = predict.tags(S, 1)
  antes[1] = {small = tags.small, big = tags.big, boss = boss, voucher = voucher}
  -- Both Souls are used during ante 1's blind select.
  local legendaries = predict.legendaries(S, 2)
  -- Ante A+1: end_round's voucher, then cash_out's tags and boss.
  for a = 2, ANTES do
    local v = predict.voucher(S, a)
    local t = predict.tags(S, a)
    local b = predict.boss(S, a)
    antes[a] = {small = t.small, big = t.big, boss = b, voucher = v}
  end
  return {antes = antes, legendaries = legendaries}
end

-- The blind-select panel for the blind on deck, once its button is live.
local function select_button()
  local kind = G.GAME.blind_on_deck
  local box = G.blind_select_opts and kind and G.blind_select_opts[string.lower(kind)]
  local btn = box and box:get_UIE_by_ID('select_blind_button')
  if btn and btn.config.button == 'select_blind' then return btn, kind end
end

-- One Soul: created with vanilla create_card (forced key), used through the
-- vanilla use_card callback. Returns the created card.
local function use_soul()
  local card = create_card('Spectral', G.consumeables, nil, nil, nil, nil, 'c_soul')
  card:add_to_deck()
  G.consumeables:emplace(card)
  G.FUNCS.use_card({config = {ref_table = card, button = 'use_card'}})
  return card
end

local function soul_step(seed)
  return function(ctx)
    local s = seen[seed]
    s.souls = s.souls or {jokers = {}, used = 0}
    local st = s.souls
    local idle = G.STATE == G.STATES.BLIND_SELECT and not G.CONTROLLER.locks.use
    if st.used > #st.jokers then
      -- waiting for the joker from the last Soul
      if #G.jokers.cards < st.used or not idle then return false end
      local new = G.jokers.cards[#G.jokers.cards]
      st.jokers[#st.jokers + 1] = {key = new.config.center.key,
        edition = new.edition and new.edition.type or nil}
      return false
    end
    if st.used < 2 then
      if not idle or ctx.step_time() < 0.3 then return false end
      st.used = st.used + 1
      use_soul()
      return false
    end
    if SHOTS[seed] then ctx.shot('souls') end
    local want = pred[seed].legendaries
    ctx.assert(#G.jokers.cards == 2, seed..': expected 2 jokers, have '..#G.jokers.cards)
    for i = 1, 2 do
      local w, g = want[i], st.jokers[i]
      ctx.log(string.format('%s soul %d: predicted %s (%s); real %s (%s)', seed, i,
        w.key, tostring(w.edition), g.key, tostring(g.edition)))
      if w.key ~= g.key then fail(ctx, seed, 'soul '..i..' joker', w.key, g.key) end
      if w.edition ~= g.edition then fail(ctx, seed, 'soul '..i..' edition', w.edition, g.edition) end
    end
    ctx.log('check: golden_stable '..seed..' souls ok')
    return true
  end
end

-- Fast-forward: extra passes of the real Game:update per rendered frame, each
-- a 1/20 s tick (the largest step vanilla's movement accepts, game.lua:2621).
-- Only animation and event delays shrink; nothing here draws a stream.
local TURBO = 4
local function turbo()
  for _ = 1, TURBO do G:update(1/20) end
end

-- Plays antes 1..ANTES by the fixed policy, comparing each new ante in the
-- shop after its predecessor's Boss. Done in the shop after ante ANTES's Boss.
local function play_step(seed)
  return function(ctx)
    turbo()
    local s = seen[seed]
    s.play = s.play or {phase = 'select', t = 0}
    local p = s.play
    local now = love.timer.getTime()
    local function go(phase) p.phase, p.t = phase, now end
    local waited = now - p.t

    if p.phase == 'select' then
      if G.STATE ~= G.STATES.BLIND_SELECT or waited < 0.05 then return false end
      local btn, kind = select_button()
      if not btn then return false end
      p.kind = kind
      G.FUNCS.select_blind(btn)
      go('play')
    elseif p.phase == 'play' then
      if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or waited < 0.05
        or G.CONTROLLER.locks.frame then return false end
      if SHOTS[seed] and p.kind == 'Boss' and not p.boss_shot then p.boss_shot = true; ctx.shot('boss_'..G.GAME.round_resets.ante) end
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
      if G.STATE ~= G.STATES.ROUND_EVAL or waited < 0.05 then return false end
      if not ctx.click('cash_out') then return false end
      go('shop')
    elseif p.phase == 'shop' then
      -- The shop is built by a delayed event; leaving before it lands crashes
      -- that event (game.lua:3090 reads G.shop). Its packs are the last cards placed.
      if G.STATE ~= G.STATES.SHOP or not G.shop or waited < 0.05
        or not (G.shop_booster and #G.shop_booster.cards == 2) then return false end
      if p.kind == 'Boss' then
        local a = G.GAME.round_resets.ante
        if SHOTS[seed] then ctx.shot('shop_ante_'..a) end
        if a > ANTES then return true end
        compare_ante(ctx, seed, a)
      end
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

for _, seed in ipairs(SEEDS) do
  steps[#steps + 1] = {name = 'predict and start '..seed, run = function(ctx)
    local before = STR_PACK(G.GAME)
    pred[seed] = predict_seed(seed)
    ctx.assert(STR_PACK(G.GAME) == before, 'prediction touched the live G.GAME')
    seen[seed] = {}
    ctx.start_run{seed = seed, stake = 1}
    return true
  end}
  steps[#steps + 1] = {name = 'ante 1 '..seed, timeout = 20, run = function(ctx)
    if not run_ready(seed) then return false end
    ctx.assert(G.GAME.stake == 1 and G.GAME.selected_back.name == 'Red Deck', seed..': not stake 1 Red Deck')
    if SHOTS[seed] then ctx.shot('blind_select_ante_1') end
    compare_ante(ctx, seed, 1)
    return true
  end}
  steps[#steps + 1] = {name = 'souls '..seed, timeout = 20, run = soul_step(seed)}
  steps[#steps + 1] = {name = 'play '..seed, timeout = 60, run = play_step(seed)}
end

steps[#steps + 1] = {name = 'all seeds', run = function(ctx)
  ctx.log('check: golden_stable all '..#SEEDS..' seeds match')
  return true
end}

return steps
