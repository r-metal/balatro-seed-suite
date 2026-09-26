-- Jokers by ante N (T-311): a joker clause's hit, played in the real game by
-- its route steps, shows the joker where the details say (invariant 7).
--   1. Per pinned hit, filter.eval_seed(F, seed) holds; its details are the
--      prediction and route.build(F, details) the steps. The joker clause is
--      routed at the ante its details name (2 here, for a clause "by ante 3").
--   2. Start the run (Red Deck, stake 1, the seed) and execute the route's
--      steps and nothing else. The only glue is the game's own: a blind the
--      route has no step for is played (Select, chips set to 1, one card
--      played, cash out) and its shop left untouched, since the route names
--      no step before the hit's ante (every shop stream is keyed by ante).
--        play      the step's blind at the step's ante; its shop comes up
--        reroll    reroll_shop ($999 given); with a key, the card in the
--                  step's slot must be that joker
--        open_pack buy and open the shop pack in the step's slot; with take,
--                  the card at index must be that joker, and it is taken (it
--                  lands in G.jokers); otherwise the pack is skipped
--   3. Where: the shop the joker shows up in is the details' (ante, shop
--      count within the ante, the blind it follows), and for a row hit the
--      reroll count within that shop is the details' reroll.
--      -> "check: finder_joker <seed> ok" per hit, "check: finder_joker all".
-- Seeds were found offline (invariant 8: no scan here) by a scratch rig script
-- under systemd-run MemoryMax=6G over FJOKER1..FJOKER11: ante 1 then ante 2
-- walked with rerolls 2 and every pack opened, each joker seen there tried as
-- the clause key, keeping hits whose route rerolls and opens packs in earlier
-- shops of the ante before the hit.
--   FJOKER1  Bull, from 'buffoon', rerolls 2: ante 2, shop 2 (after the
--            Small), Jumbo Buffoon in slot 2, card 3. Route: the Boss shop's 2
--            rerolls and both packs, then the Small shop's 2 rerolls, slot 1,
--            slot 2 (taken).
--   FJOKER2  Four Fingers, from 'both', rerolls 2: ante 2, shop 3 (after the
--            Big), reroll 1, slot 2. Route: the Boss and Small shops' 2
--            rerolls and both packs each, then the Big shop's 1 reroll.
-- Mechanics copied from finder_route.lua (itself from finder_chain.lua).
local filter = require('seedfinder.filter')
local route = require('seedfinder.route')

local function F(c)
  return {name = 'joker', deck = 'b_red', stake = 1, mode = 'all', clauses = {c}}
end

local HITS = {
  {seed = 'FJOKER1', f = F({kind = 'joker', ante = 3, key = 'j_bull', rerolls = 2, from = 'buffoon'})},
  {seed = 'FJOKER2', f = F({kind = 'joker', ante = 3, key = 'j_four_fingers', rerolls = 2, from = 'both'})},
}

local P -- the hit being played

local function select_button()
  local kind = G.GAME.blind_on_deck
  local box = G.blind_select_opts and kind and G.blind_select_opts[string.lower(kind)]
  local btn = box and box:get_UIE_by_ID('select_blind_button')
  if btn and btn.config.button == 'select_blind' then return btn, kind end
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

local function holds(key)
  for _, c in ipairs(G.jokers and G.jokers.cards or {}) do
    if c.config.center.key == key then return true end
  end
  return false
end

-- The shop the route is in is the details' shop: same ante, same count within
-- the ante, same blind before it.
local function at_hit_shop(ctx, where)
  local h = P.hit
  ctx.assert(G.GAME.round_resets.ante == h.ante and P.ante_shops == h.shop and P.after == h.after,
    string.format('%s: %s at ante %d shop %d after %s, the details say ante %d shop %d after %s', P.seed, where,
      G.GAME.round_resets.ante, P.ante_shops, tostring(P.after), h.ante, h.shop, h.after))
end

-- Runs P.route.steps in the live run, one phase per frame.
local function play_route(ctx)
  turbo()
  P.frames = P.frames + 1
  local function go(phase) P.phase, P.frames = phase, 0 end
  local st = P.route.steps[P.k]

  if P.phase == 'wait_run' then
    if not (G.STATE == G.STATES.BLIND_SELECT and G.GAME.pseudorandom.seed == P.seed and select_button())
      or P.frames < 3 then return false end
    ctx.assert(G.GAME.stake == 1 and G.GAME.selected_back.name == 'Red Deck', P.seed..': not a stake-1 Red Deck run')
    go('next')
  elseif P.phase == 'next' then
    if not st then go('done'); return false end
    ctx.log(string.format('%s step %d: ante %d %s %s: %s', P.seed, P.k, st.ante, st.when, st.action, st.text))
    go(st.action)

  -- play: the step's blind at the step's ante; any blind before it is glue.
  elseif P.phase == 'play' then
    if G.STATE == G.STATES.SHOP then
      if shop_settled() and P.frames > 2 and ctx.click('toggle_shop') then P.frames = 0 end
      return false
    end
    if G.STATE ~= G.STATES.BLIND_SELECT or P.frames < 3 then return false end
    local btn, kind = select_button()
    if not btn then return false end
    local ante = G.GAME.round_resets.ante
    local ord = {Small = 1, Big = 2, Boss = 3}
    ctx.assert(ante < st.ante or (ante == st.ante and ord[kind] <= ord[st.when]),
      P.seed..' step '..P.k..': passed the step\'s blind (ante '..ante..' '..tostring(kind)..')')
    P.glue = not (ante == st.ante and kind == st.when)
    if P.glue then ctx.log(string.format('%s glue: play ante %d %s', P.seed, ante, kind)) end
    P.blind = kind
    G.FUNCS.select_blind(btn)
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
    -- The shops of ante A: after the Boss of A-1, then the Small and Big of A.
    local ante = G.GAME.round_resets.ante
    if ante ~= P.shop_ante then P.shop_ante, P.ante_shops = ante, 0 end
    P.ante_shops = P.ante_shops + 1
    P.after, P.rerolls = P.blind, 0
    ctx.log(string.format('%s shop: ante %d #%d after %s, row %s, packs %s', P.seed, ante, P.ante_shops, P.blind,
      table.concat(keys(G.shop_jokers.cards), ' '), table.concat(keys(G.shop_booster.cards), ' ')))
    if P.glue then go('play') else P.k = P.k + 1; go('next') end

  elseif P.phase == 'reroll' then
    if not shop_settled() or P.frames < 2 then return false end
    G.GAME.dollars = 999
    G.FUNCS.reroll_shop()
    go('rerolled')
  elseif P.phase == 'rerolled' then
    if not shop_settled() or P.frames < 3 then return false end
    P.rerolls = P.rerolls + 1
    ctx.assert(P.rerolls == st.index, P.seed..' step '..P.k..': reroll '..P.rerolls..', the step says '..st.index)
    ctx.log(string.format('%s reroll %d: %s', P.seed, P.rerolls, table.concat(keys(G.shop_jokers.cards), ' ')))
    if st.key then
      local c = G.shop_jokers.cards[st.slot]
      ctx.assert(c and c.config.center.key == st.key, P.seed..' step '..P.k..': reroll '..st.index..' slot '..st.slot
        ..' holds '..tostring(c and c.config.center.key)..', the step says '..st.key)
      at_hit_shop(ctx, 'the joker')
      ctx.assert(P.hit.reroll == P.rerolls and P.hit.index == st.slot, P.seed..': reroll/slot differ from the details')
      P.seen = true
      ctx.log(string.format('check: %s %s in the row after reroll %d, slot %d', P.seed, st.key, P.rerolls, st.slot))
      ctx.shot(P.seed..'_row')
    end
    P.k = P.k + 1
    go('next')

  -- open_pack: buy and open the shop pack in the step's slot.
  elseif P.phase == 'open_pack' then
    if not shop_settled() or P.frames < 2 then return false end
    ctx.assert(st.when == 'shop', P.seed..' step '..P.k..': a tag pack is not in this route')
    local booster
    for _, c in ipairs(G.shop_booster.cards) do
      if c.ability.booster_pos == st.slot then booster = c end
    end
    ctx.assert(booster, P.seed..' step '..P.k..': no shop pack in slot '..tostring(st.slot))
    local key = booster.config.center.key
    ctx.assert(st.key == nil or st.key == key, P.seed..' step '..P.k..': slot '..st.slot..' holds '..key
      ..', the step says '..tostring(st.key))
    G.FUNCS.use_card({config = {ref_table = booster, button = 'use_card'}})
    go('pack')
  elseif P.phase == 'pack' then
    if not pack_dealt() or P.frames < 3 then return false end
    local got = keys(G.pack_cards.cards)
    ctx.log(string.format('%s step %d pack slot %d: %s', P.seed, P.k, st.slot, table.concat(got, ' ')))
    if st.take then
      ctx.assert(got[st.index] == st.take, string.format('%s step %d: card %d of the pack is %s, not %s',
        P.seed, P.k, st.index, tostring(got[st.index]), st.take))
      at_hit_shop(ctx, 'the Buffoon pack')
      ctx.assert(P.hit.pack_slot == st.slot and P.hit.index == st.index, P.seed..': pack slot/index differ from the details')
      ctx.log(string.format('check: %s %s is card %d of the slot-%d pack', P.seed, st.take, st.index, st.slot))
      ctx.shot(P.seed..'_pack')
      go('take')
    else
      go('close')
    end
  elseif P.phase == 'take' then
    -- One frame after the shot is drawn.
    if P.frames < 2 or G.CONTROLLER.locks.frame then return false end
    G.FUNCS.use_card({config = {ref_table = G.pack_cards.cards[st.index], button = 'use_card'}})
    go('taken')
  elseif P.phase == 'taken' then
    if G.CONTROLLER.locks.use or G.CONTROLLER.locks.frame or P.frames < 3 then return false end
    if not holds(st.take) then return false end
    P.seen = true
    ctx.log('check: '..P.seed..' '..st.take..' taken into the jokers')
    if G.booster_pack and G.pack_cards and in_pack_state() then go('close') else go('closing') end
  elseif P.phase == 'close' then
    if P.frames < 2 or G.CONTROLLER.locks.frame then return false end
    if ctx.click('skip_booster') then go('closing') end
  elseif P.phase == 'closing' then
    if G.booster_pack or P.frames < 3 or not shop_settled() then return false end
    P.k = P.k + 1
    go('next')

  elseif P.phase == 'done' then
    ctx.assert(P.seen, P.seed..': the joker never showed up where the route said')
    ctx.log(string.format('check: finder_joker %s ok (%d steps)', P.seed, #P.route.steps))
    return true
  else
    error(P.seed..' step '..P.k..': unexpected action '..tostring(P.phase))
  end
  return false
end

local steps = {
  {name = 'speed up', run = function(ctx)
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    SaveSlots.settings.auto_checkpoints = false
    return true
  end},
  {name = 'hits', run = function(ctx)
    for _, h in ipairs(HITS) do
      local ok, d = filter.eval_seed(h.f, h.seed)
      ctx.assert(ok, h.seed..': the filter does not hold')
      h.hit = d.results[1]
      local r, err = route.build(h.f, d)
      ctx.assert(r, h.seed..': route.build: '..tostring(err))
      h.route = r
      ctx.assert(r.cost.ante == h.hit.ante, h.seed..': the route ends at ante '..r.cost.ante..', the hit is at '..h.hit.ante)
      ctx.log(string.format('hit %s: %s at ante %d shop %d after %s, reroll %s, pack slot %s, index %d; cost %d rerolls',
        h.seed, h.f.clauses[1].key, h.hit.ante, h.hit.shop, h.hit.after, tostring(h.hit.reroll),
        tostring(h.hit.pack_slot), h.hit.index, r.cost.rerolls))
      for k, st in ipairs(r.steps) do
        ctx.log(string.format('route %d: ante %d %s %s slot %s index %s key %s take %s: %s', k, st.ante, st.when,
          st.action, tostring(st.slot), tostring(st.index), tostring(st.key), tostring(st.take), st.text))
      end
    end
    ctx.assert(HITS[1].hit.pack_slot and HITS[1].hit.ante >= 2, 'hit 1 is not a Buffoon hit at ante >= 2')
    ctx.assert(HITS[2].hit.reroll and HITS[2].hit.reroll >= 1, 'hit 2 is not a shop hit after rerolls')
    return true
  end},
}

for h = 1, #HITS do
  steps[#steps + 1] = {name = 'start hit '..h, run = function(ctx)
    local hit = HITS[h]
    P = {seed = hit.seed, hit = hit.hit, route = hit.route, k = 1, phase = 'wait_run', frames = 0,
      ante_shops = 0}
    if G.GAME then G.GAME.viewed_back = Back(G.P_CENTERS.b_red) end
    ctx.start_run{seed = hit.seed, stake = 1}
    return true
  end}
  steps[#steps + 1] = {name = 'play hit '..h, timeout = 120, run = play_route}
end

steps[#steps + 1] = {name = 'all', run = function(ctx)
  ctx.log('check: finder_joker all')
  return true
end}

return steps
