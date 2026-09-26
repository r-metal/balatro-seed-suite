-- Events: every bhcore.events event fires exactly once per occurrence, with the
-- right payload, in a real seeded run.
--   1. Subscribe to every event, start a seeded run.
--   2. Skip the Small Blind, select the Big Blind, play a hand (the chips needed
--      forced to 1), cash out into the shop.
--   3. Next round: select the Boss, play a forced win (ante 1 -> 2), cash out.
--   4. Select the ante-2 Small Blind with one hand left and an unreachable
--      target, play it: the round is lost and the run ends.
-- Payloads are checked against state read independently of the hooks (the UI's
-- tag, the blind the game set, G.GAME.chips once eased, the shop's dollars).
-- Screenshots: skip, shop, game_over.
local events = require('bhcore.events')

local SEED = 'EVENTS1'
local got = {}      -- name -> array of payloads, in order
local order = {}    -- names, in firing order
local seen = {}     -- independent observations, for the payload checks

local function count(name) return got[name] and #got[name] or 0 end

-- The blind-select panel for the blind on deck, once vanilla's
-- blind_choice_handler has made its buttons live.
local function panel()
  local kind = G.GAME.blind_on_deck
  local box = G.blind_select_opts and kind and G.blind_select_opts[string.lower(kind)]
  return box, kind
end

local function select_on_deck(ctx)
  -- A skip tag can open a booster pack on the spot (this seed's Charm Tag does).
  local packs = {G.STATES.TAROT_PACK, G.STATES.PLANET_PACK, G.STATES.SPECTRAL_PACK,
    G.STATES.STANDARD_PACK, G.STATES.BUFFOON_PACK}
  for _, st in ipairs(packs) do
    if G.STATE == st then
      seen.pack_since = seen.pack_since or ctx.step_time()
      if not seen.pack_skipped and G.booster_pack and ctx.step_time() - seen.pack_since > 1.5 then
        seen.pack_skipped = ctx.click('skip_booster')
      end
      return false
    end
  end
  seen.pack_since, seen.pack_skipped = nil, nil
  if G.STATE ~= G.STATES.BLIND_SELECT or not G.blind_select or ctx.step_time() < 1 then return false end
  local box, kind = panel()
  local btn = box and box:get_UIE_by_ID('select_blind_button')
  if not (btn and btn.config.button == 'select_blind') then return false end
  seen['select_'..kind] = btn.config.ref_table and btn.config.ref_table.key
  G.FUNCS.select_blind(btn)
  return true
end

-- Waits for the hand, highlights up to five cards, sets the target, plays.
local function play_hand(ctx, target, hands_left)
  if G.STATE ~= G.STATES.SELECTING_HAND or ctx.step_time() < 1 or #G.hand.cards == 0 then return false end
  seen.blind_set = seen.blind_set or {}
  seen.blind_set[#seen.blind_set + 1] = G.GAME.round_resets.blind and G.GAME.round_resets.blind.key
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
end

local function cash_out(ctx)
  if G.STATE ~= G.STATES.ROUND_EVAL then return false end
  return ctx.click('cash_out')
end

local function in_shop(label)
  return function(ctx)
    if G.STATE ~= G.STATES.SHOP or not G.shop or ctx.step_time() < 2 then return false end
    seen.shop_dollars = seen.shop_dollars or {}
    seen.shop_dollars[#seen.shop_dollars + 1] = G.GAME.dollars
    if label then ctx.shot(label) end
    return true
  end
end

local function next_round(ctx)
  if G.STATE ~= G.STATES.SHOP then return false end
  return ctx.click('toggle_shop')
end

local function expect(ctx, cond, what)
  ctx.assert(cond, 'payload mismatch: '..what)
end

return {
  {name = 'subscribe', run = function(ctx)
    G.SETTINGS.GAMESPEED = 4
    for name in pairs(events.NAMES) do
      got[name] = {}
      events.on(name, function(p)
        got[name][#got[name] + 1] = p
        order[#order + 1] = name
        if name == 'round_end' then
          seen.round_end_chips = seen.round_end_chips or {}
          seen.round_end_chips[#got[name]] = G.GAME.chips
        elseif name == 'ante_change' then
          seen.ante_at_change = G.GAME.round_resets.ante
        end
      end)
    end
    ctx.start_run{seed = SEED}
    return true
  end},
  {name = 'blind select', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
  end},

  -- 2. Ante 1: skip Small, beat Big, shop
  {name = 'skip small', run = function(ctx)
    if not G.blind_select or ctx.step_time() < 1.5 then return false end
    local box, kind = panel()
    ctx.assert(kind == 'Small', 'Small is not on deck: '..tostring(kind))
    local tag = box and box:get_UIE_by_ID('tag_Small')
    local btn = tag and tag.children[2]
    if not (btn and btn.config.button == 'skip_blind') then return false end
    local container = box:get_UIE_by_ID('tag_container')
    seen.skip_tag = container and container.config.ref_table and container.config.ref_table.key
    ctx.shot('skip')
    G.FUNCS.skip_blind(btn)
    return true
  end},
  {name = 'select big', timeout = 15, run = select_on_deck},
  {name = 'play big', timeout = 20, run = function(ctx) return play_hand(ctx, 1) end},
  {name = 'cash out big', timeout = 30, run = cash_out},
  {name = 'shop 1', timeout = 20, run = in_shop('shop')},
  {name = 'next round', run = next_round},

  -- 3. Ante 1 Boss: forced win, ante 1 -> 2
  {name = 'select boss', timeout = 20, run = function(ctx)
    if G.GAME.blind_on_deck ~= 'Boss' then return false end
    seen.boss_choice = G.GAME.round_resets.blind_choices.Boss
    return select_on_deck(ctx)
  end},
  {name = 'play boss', timeout = 20, run = function(ctx) return play_hand(ctx, 1) end},
  {name = 'cash out boss', timeout = 30, run = cash_out},
  {name = 'shop 2', timeout = 20, run = in_shop()},
  {name = 'next ante', run = next_round},

  -- 4. Ante 2 Small: lose the round, and the run
  {name = 'select small', timeout = 20, run = function(ctx)
    if G.GAME.blind_on_deck ~= 'Small' then return false end
    return select_on_deck(ctx)
  end},
  {name = 'play to lose', timeout = 20, run = function(ctx) return play_hand(ctx, 1e9, 1) end},
  {name = 'game over', timeout = 30, run = function(ctx)
    if G.STATE ~= G.STATES.GAME_OVER or not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    ctx.shot('game_over')
    return true
  end},

  {name = 'counts', run = function(ctx)
    ctx.log('events in order: '..table.concat(order, ' '))
    local want = {run_start = 1, blind_skipped = 1, blind_selected = 3, hand_scored = 3,
      round_end = 3, shop_enter = 2, ante_change = 1, run_end = 1}
    for name in pairs(events.NAMES) do
      ctx.assert(count(name) == want[name],
        string.format('%s fired %d times, expected %d', name, count(name), want[name] or -1))
    end
    ctx.log('check: events fired once each')
    return true
  end},
  {name = 'payloads', run = function(ctx)
    local rs = got.run_start[1]
    expect(ctx, rs.seed == SEED and G.GAME.pseudorandom.seed == SEED, 'run_start.seed '..tostring(rs.seed))
    expect(ctx, rs.stake == 1 and rs.deck == 'b_red' and rs.loaded == false and rs.ante == 1, 'run_start fields')

    local sk = got.blind_skipped[1]
    expect(ctx, sk.ante == 1 and sk.kind == 'Small', 'blind_skipped ante/kind')
    expect(ctx, type(seen.skip_tag) == 'string' and sk.tag == seen.skip_tag,
      'blind_skipped.tag '..tostring(sk.tag)..' vs UI '..tostring(seen.skip_tag))

    local bs = got.blind_selected
    local want_bs = {{1, 'Big', 'bl_big'}, {1, 'Boss', seen.boss_choice}, {2, 'Small', 'bl_small'}}
    for i, w in ipairs(want_bs) do
      expect(ctx, bs[i].ante == w[1] and bs[i].kind == w[2] and bs[i].blind == w[3],
        string.format('blind_selected[%d] = %s/%s/%s', i, tostring(bs[i].ante), tostring(bs[i].kind), tostring(bs[i].blind)))
      expect(ctx, seen.blind_set[i] == bs[i].blind, 'blind_selected['..i..'] vs the blind the game set: '..tostring(seen.blind_set[i]))
    end
    expect(ctx, seen.select_Big == 'bl_big', 'Big button ref')

    local hs, re = got.hand_scored, got.round_end
    for i = 1, 3 do
      local h = hs[i]
      expect(ctx, type(h.hand) == 'string' and G.GAME.hands[h.hand] ~= nil, 'hand_scored['..i..'].hand '..tostring(h.hand))
      expect(ctx, h.chips > 0 and h.mult > 0 and h.score == math.floor(h.chips * h.mult), 'hand_scored['..i..'] score')
      expect(ctx, h.total == h.score, 'hand_scored['..i..'].total (first hand of the round)')
      expect(ctx, h.round == re[i].round and h.ante == re[i].ante, 'hand_scored['..i..'] round/ante vs round_end')
      expect(ctx, seen.round_end_chips[i] == h.total,
        string.format('hand_scored[%d].total %s vs G.GAME.chips %s', i, tostring(h.total), tostring(seen.round_end_chips[i])))
    end
    expect(ctx, re[1].won == true and re[2].won == true and re[3].won == false, 'round_end.won')
    expect(ctx, re[1].ante == 1 and re[2].ante == 1 and re[3].ante == 2, 'round_end.ante')
    expect(ctx, re[1].round < re[2].round and re[2].round < re[3].round, 'round_end.round increases')
    for i = 1, 3 do expect(ctx, type(re[i].dollars) == 'number', 'round_end.dollars') end

    local sh = got.shop_enter
    for i = 1, 2 do
      expect(ctx, sh[i].round == re[i].round, 'shop_enter['..i..'].round')
      expect(ctx, sh[i].dollars == seen.shop_dollars[i],
        string.format('shop_enter[%d].dollars %s vs shop %s', i, tostring(sh[i].dollars), tostring(seen.shop_dollars[i])))
    end
    expect(ctx, sh[1].ante == 1 and sh[2].ante == 2, 'shop_enter.ante')

    local ac = got.ante_change[1]
    expect(ctx, ac.from == 1 and ac.to == 2 and seen.ante_at_change == 2, 'ante_change 1 -> 2')

    local rn = got.run_end[1]
    expect(ctx, rn.won == false and rn.ante == 2 and rn.round == re[3].round and rn.seed == SEED, 'run_end fields')
    expect(ctx, order[#order - 1] == 'round_end' and order[#order] == 'run_end', 'round_end before run_end')
    ctx.log('check: payloads match')
    return true
  end},
}
