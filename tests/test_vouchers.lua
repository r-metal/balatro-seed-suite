-- Voucher clauses are bought (seedfinder.filter header: Policies, voucher
-- clauses; GitHub issue #1, "Seed finder unable to find secondary vouchers").
-- A tier-2 voucher only enters the pool once its tier-1 is redeemed
-- (get_current_pool, common_events.lua:1990-2002), and 0.4.0 bought nothing,
-- so a tier-2 clause never held. Covers the sim side (state.redeem,
-- predict.voucher's used, ante_walk's purchase in its first shop), the
-- filter's purchases against the policy replayed by hand with predict's
-- primitives, and the route's redeem steps. Runs on vanilla's own RNG and
-- pool primitives over the stub world of tests/test_filter.lua with vanilla's
-- tier-1/tier-2 voucher pairs added (game.lua:592-624). The real-game
-- reference is rig/scenarios/finder_voucher.lua.
local H = ...

local function center(key, t)
  t.key = key
  t.config = t.config or {}
  return t
end

local TAGS = {'tag_uncommon', 'tag_juggle', 'tag_charm', 'tag_economy', 'tag_ethereal'}

local OVERSTOCK, PLUS, HONE, GLOW, HIERO, PETRO = 'v_overstock_norm', 'v_overstock_plus', 'v_hone', 'v_glow_up',
  'v_hieroglyph', 'v_petroglyph'

local function world(o)
  o = o or {}
  BHCore = {}
  dofile(H.root..'/build/game/functions/misc_functions.lua')
  dofile(H.root..'/build/game/functions/common_events.lua')
  local list = {
    center('j_joker', {name = 'Joker', set = 'Joker', rarity = 1, order = 1, eternal_compat = true, perishable_compat = true}),
    center('j_greedy_joker', {name = 'Greedy Joker', set = 'Joker', rarity = 1, order = 2, eternal_compat = true, perishable_compat = true}),
    center('j_lusty_joker', {name = 'Lusty Joker', set = 'Joker', rarity = 1, order = 3, eternal_compat = true, perishable_compat = true}),
    center('j_ceremonial', {name = 'Ceremonial Dagger', set = 'Joker', rarity = 2, order = 4, eternal_compat = true, perishable_compat = false}),
    center('j_blueprint', {name = 'Blueprint', set = 'Joker', rarity = 3, order = 5, eternal_compat = true, perishable_compat = true}),
    center('j_caino', {name = 'Caino', set = 'Joker', rarity = 4, order = 6, eternal_compat = true, perishable_compat = true}),
    center('j_yorick', {name = 'Yorick', set = 'Joker', rarity = 4, order = 7, eternal_compat = true, perishable_compat = true}),
    center('c_fool', {name = 'The Fool', set = 'Tarot', order = 1, consumeable = true}),
    center('c_magician', {name = 'The Magician', set = 'Tarot', order = 2, consumeable = true}),
    center('c_strength', {name = 'Strength', set = 'Tarot', order = 3, consumeable = true}),
    center('c_hermit', {name = 'The Hermit', set = 'Tarot', order = 4, consumeable = true}),
    center('c_pluto', {name = 'Pluto', set = 'Planet', order = 1, consumeable = true, config = {hand_type = 'High Card'}}),
    center('c_mercury', {name = 'Mercury', set = 'Planet', order = 2, consumeable = true, config = {hand_type = 'Pair'}}),
    center('c_familiar', {name = 'Familiar', set = 'Spectral', order = 1, consumeable = true}),
    center('c_grim', {name = 'Grim', set = 'Spectral', order = 2, consumeable = true}),
    center('c_soul', {name = 'The Soul', set = 'Spectral', order = 17, consumeable = true, hidden = true}),
    center('c_black_hole', {name = 'Black Hole', set = 'Spectral', order = 18, consumeable = true, hidden = true}),
    center('c_base', {name = 'Default Base', set = 'Default', order = 1}),
    center('m_bonus', {name = 'Bonus', set = 'Enhanced', order = 2}),
    -- Vanilla's pairs (game.lua:592-624): tier-2 locked on a new profile.
    center(OVERSTOCK, {name = 'Overstock', set = 'Voucher', order = 1, unlocked = true, cost = 10}),
    center(PLUS, {name = 'Overstock Plus', set = 'Voucher', order = 2, unlocked = false, cost = 10, requires = {OVERSTOCK}}),
    center(HONE, {name = 'Hone', set = 'Voucher', order = 5, unlocked = true, cost = 10, config = {extra = 2}}),
    center(GLOW, {name = 'Glow Up', set = 'Voucher', order = 6, unlocked = false, cost = 10, config = {extra = 4}, requires = {HONE}}),
    center('v_grabber', {name = 'Grabber', set = 'Voucher', order = 13, unlocked = true, cost = 10, config = {extra = 1}}),
    center(HIERO, {name = 'Hieroglyph', set = 'Voucher', order = 27, unlocked = true, cost = 10, config = {extra = 1}}),
    center(PETRO, {name = 'Petroglyph', set = 'Voucher', order = 28, unlocked = false, cost = 10, config = {extra = 1}, requires = {HIERO}}),
    center('b_red', {name = 'Red Deck', set = 'Back', order = 1}),
  }
  local boosters = {
    center('p_arcana_normal_1', {order = 1, name = 'Arcana Pack', weight = 1, kind = 'Arcana', set = 'Booster', config = {extra = 3, choose = 1}}),
    center('p_arcana_mega_1', {order = 2, name = 'Mega Arcana Pack', weight = 0.25, kind = 'Arcana', set = 'Booster', config = {extra = 5, choose = 2}}),
    center('p_celestial_normal_1', {order = 4, name = 'Celestial Pack', weight = 1, kind = 'Celestial', set = 'Booster', config = {extra = 3, choose = 1}}),
    center('p_spectral_normal_1', {order = 5, name = 'Spectral Pack', weight = 0.6, kind = 'Spectral', set = 'Booster', config = {extra = 2, choose = 1}}),
    center('p_buffoon_normal_1', {order = 6, name = 'Buffoon Pack', weight = 0.6, kind = 'Buffoon', set = 'Booster', config = {extra = 2, choose = 1}}),
    center('p_buffoon_normal_2', {order = 7, name = 'Buffoon Pack', weight = 0.6, kind = 'Buffoon', set = 'Booster', config = {extra = 2, choose = 1}}),
  }
  local P = {}
  for _, c in ipairs(list) do P[c.key] = c end
  for _, c in ipairs(boosters) do P[c.key] = c end
  G.P_CENTERS = P
  local function pool(set)
    local out = {}
    for _, c in pairs(P) do if c.set == set then out[#out + 1] = c end end
    table.sort(out, function(a, b) return a.order < b.order end)
    return out
  end
  local tags = {}
  G.P_TAGS = {}
  for i, k in ipairs(TAGS) do
    tags[i] = {key = k, min_ante = k == 'tag_ethereal' and 2 or nil}
    G.P_TAGS[k] = tags[i]
  end
  G.P_CENTER_POOLS = {Joker = pool('Joker'), Tarot = pool('Tarot'), Planet = pool('Planet'),
    Spectral = pool('Spectral'), Enhanced = pool('Enhanced'), Voucher = pool('Voucher'),
    Booster = pool('Booster'), Tag = tags}
  G.P_JOKER_RARITY_POOLS = {{}, {}, {}, {}}
  for _, c in ipairs(G.P_CENTER_POOLS.Joker) do table.insert(G.P_JOKER_RARITY_POOLS[c.rarity], c) end
  G.P_CARDS = {H_2 = {suit = 'Hearts', value = '2'}, S_A = {suit = 'Spades', value = 'Ace'}}
  G.P_BLINDS = {
    bl_small = {key = 'bl_small'}, bl_big = {key = 'bl_big'},
    bl_hook = {key = 'bl_hook', boss = {min = 1, max = 10}},
    bl_club = {key = 'bl_club', boss = {min = 1, max = 10}},
  }
  G.handlist = {'Pair', 'High Card'}
  G.jokers = {cards = {}, config = {card_limit = 5}}
  G.consumeables = {cards = {}, config = {card_limit = 2}}
  G.playing_cards = {}
  G.GAME = {live = true, pseudorandom = {seed = 'LIVE'}, round_resets = {ante = 5}}
  local seed = o.seed or 'VOUCHSEED'
  local game = {
    round_resets = {ante = 1}, win_ante = 8,
    pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)},
    used_jokers = {}, used_vouchers = {}, banned_keys = {}, pool_flags = {},
    bosses_used = {bl_hook = 0, bl_club = 0},
    hands = {['High Card'] = {played = 0, visible = true}, Pair = {played = 0, visible = true}},
    modifiers = {}, edition_rate = 1, shop = {joker_max = 2},
    joker_rate = 20, tarot_rate = 4, planet_rate = 4, playing_card_rate = 0, spectral_rate = 0,
  }
  return {game = game, all_unlocked = o.locked ~= true}
end

local function mods()
  return require('seedfinder.filter'), require('bhcore.sim.predict'), require('bhcore.sim.state')
end

local function route() return require('seedfinder.route') end

-- A fresh S per seed: one world, copied and reseeded.
local function seeder(state, base)
  return function(seed)
    local T = state.copy(base)
    T.game.pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)}
    return T
  end
end

local function F(clauses, extra)
  local f = {name = 'test', clauses = clauses, all_unlocked = true}
  for k, v in pairs(extra or {}) do f[k] = v end
  return f
end

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function fmt(cards)
  local out = {}
  for i, c in ipairs(cards or {}) do out[i] = c.key..(c.edition and '/'..c.edition or '') end
  return table.concat(out, ' ')
end

-- Vanilla's own draw with used_vouchers = used.
local function vanilla_voucher(S, a, used)
  local sandbox = require('bhcore.sim.sandbox')
  local res = {sandbox.run(S, function()
    G.GAME.round_resets.ante = a
    G.GAME.used_vouchers = used
    return get_next_voucher_key()
  end)}
  assert(res[1], res[2])
  return res[2]
end

-- The policy replayed by hand for one tier-2 clause (key `tier2`, its
-- tier-1 `tier1`) at ante N, plain or by: antes ascending, each drawn with
-- the purchases below it; the tier-1 bought at its first offer below N, the
-- tier-2 where the clause holds. Returns the ante it held at (or nil) and the
-- purchases {[a] = key}.
local function replay(predict, T, tier1, tier2, N, by)
  local used, bought = {}, {}
  for a = 1, N do
    local v = predict.voucher(T, a, copy(used))
    if v == tier2 and (by or a == N) then
      bought[a] = v
      return a, bought
    end
    if v == tier1 and a < N then used[v], bought[a] = true, v end
  end
  return nil, bought
end

------------------------------------------------------------------------------
-- The sim

H.test('state.redeem: used_vouchers and the rates generation reads; Hieroglyph and Petroglyph refused', function()
  local _, _, state = mods()
  local S = world()
  state.redeem(S, OVERSTOCK)
  H.eq(S.game.used_vouchers[OVERSTOCK], true); H.eq(S.game.shop.joker_max, 3)
  state.redeem(S, PLUS)
  H.eq(S.game.shop.joker_max, 4, 'Overstock Plus adds the fourth slot')
  state.redeem(S, HONE)
  H.eq(S.game.edition_rate, 2)
  state.redeem(S, GLOW)
  H.eq(S.game.edition_rate, 4)
  state.redeem(S, 'v_grabber')
  H.eq(S.game.used_vouchers.v_grabber, true)
  H.eq(S.game.shop.joker_max, 4, 'Grabber changes no draw')
  for _, k in ipairs{HIERO, PETRO} do
    local ok, err = pcall(state.redeem, world(), k)
    H.eq(ok, false, k); H.ok(tostring(err):find('sets the ante back', 1, true), tostring(err))
  end
  H.ok(not pcall(state.redeem, world(), 'j_joker'), 'not a voucher')
  H.eq(state.REWINDS.Hieroglyph, true); H.eq(state.REWINDS.Petroglyph, true)
end)

H.test('predict.voucher: used stands in for used_vouchers, as vanilla draws it; a tier-2 needs its tier-1 there', function()
  local _, predict, state = mods()
  local at = seeder(state, world())
  local plus, own = 0, nil
  for i = 1, 300 do
    local seed = 'PV'..i
    for a = 1, 3 do
      local S = at(seed)
      own = S.game.used_vouchers
      local none = predict.voucher(S, a)
      H.ok(none ~= PLUS and none ~= GLOW and none ~= PETRO, seed..': a tier-2 with nothing redeemed')
      H.eq(none, vanilla_voucher(at(seed), a, {}), seed..' ante '..a)
      local used = {[OVERSTOCK] = true}
      local v = predict.voucher(at(seed), a, used)
      H.eq(v, vanilla_voucher(at(seed), a, copy(used)), seed..' ante '..a..' with Overstock')
      H.ok(v ~= OVERSTOCK, seed..': a redeemed voucher offered')
      if v == PLUS then plus = plus + 1 end
      H.eq(S.game.used_vouchers, own, 'S keeps its own table'); H.eq(next(own), nil, 'and it stays empty')
    end
  end
  H.ok(plus > 20, 'Overstock Plus offered once Overstock is redeemed: '..plus)
  H.ok(not pcall(predict.voucher, world(), 1, 'v_hone'), 'used must be a table')
end)

-- ante a walked by hand with a purchase of `key` in its first shop: the row
-- (plus any slot the purchase adds: change_shop_size fills it at once,
-- continuing the same streams, and the packs draw others), its packs, the
-- purchase, then R rerolls.
local function walk_by_hand(predict, state, T, a, key, skip, R)
  local out, first = {}, true
  local function shop(after)
    local before = T.game.shop.joker_max
    local add = 0
    if first and key == OVERSTOCK then add = 1 end
    local s = {after = after, cards = predict.shop(T, a, before + add), packs = predict.packs(T, a, 2), rerolls = {}}
    if first then state.redeem(T, key); first = false end
    for r = 1, R do s.rerolls[r] = predict.reroll(T, a) end
    predict.leave_shop(T)
    out[#out + 1] = s
  end
  if a > 1 then shop('Boss') end
  for _, blind in ipairs{'Small', 'Big'} do
    if not skip[blind] then shop(blind) end
  end
  return out
end

H.test('ante_walk: a voucher bought in the first shop; Overstock fills its new slot at once', function()
  local _, predict, state = mods()
  local tags = {small = 'tag_juggle', big = 'tag_uncommon'}
  local n = 0
  for _, key in ipairs{OVERSTOCK, HONE, 'v_grabber'} do
    for _, a in ipairs{1, 2} do
      for _, skip in ipairs{{}, {Small = true}, {Big = true}} do
        for i = 1, 8 do
          n = n + 1
          local S = world{seed = 'AW'..n}
          local T = state.copy(S)
          local w = predict.ante_walk(S, a, {skip = skip, rerolls = 2, open = false, tags = tags, voucher = key})
          local h = walk_by_hand(predict, state, T, a, key, skip, 2)
          local what = key..' ante '..a..' skip '..tostring(skip.Small)..tostring(skip.Big)..' '..n
          H.eq(#w.shops, #h, what)
          for s, shop in ipairs(h) do
            H.eq(w.shops[s].after, shop.after, what)
            H.eq(fmt(w.shops[s].cards), fmt(shop.cards), what..' shop '..s..' row')
            for r = 1, 2 do H.eq(fmt(w.shops[s].rerolls[r].cards), fmt(shop.rerolls[r]), what..' reroll '..r) end
            H.eq(w.shops[s].packs[1].key, shop.packs[1].key, what)
            H.eq(w.shops[s].voucher, s == 1 and key or nil, what..': the purchase is in the first shop only')
          end
          H.eq(#w.shops[1].cards, key == OVERSTOCK and 3 or 2, what..': row after the purchase')
          H.eq(S.game.used_vouchers[key], true, what)
          H.eq(next(S.game.bh_shop or {}), nil, what..': every shop left')
        end
      end
    end
  end
  -- Ante 1 with both blinds skipped has no shop to buy in.
  local ok, err = pcall(predict.ante_walk, world(), 1, {skip = {Small = true, Big = true}, tags = tags, voucher = HONE})
  H.eq(ok, false); H.ok(tostring(err):find('no shop', 1, true), tostring(err))
  H.ok(not pcall(predict.ante_walk, world(), 1, {voucher = 'j_joker', tags = tags}), 'not a voucher')
  -- cards = false: the purchase still holds, no row is drawn for it.
  local S = world()
  local w = predict.ante_walk(S, 2, {cards = false, open = false, tags = tags, voucher = OVERSTOCK})
  H.eq(w.shops[1].cards, nil); H.eq(S.game.shop.joker_max, 3)
end)

------------------------------------------------------------------------------
-- The filter

H.test('a tier-2 voucher clause holds once the walk buys its tier-1 (issue #1), by and plain', function()
  local filter, predict, state = mods()
  local at = seeder(state, world())
  local hits = {by = 0, plain = 0}
  for i = 1, 400 do
    local seed = 'T2'..i
    for _, by in ipairs{true, false} do
      local c = {kind = 'voucher', ante = 4, key = PLUS, by = by or nil}
      local ok, d = filter.eval(at(seed), F({c}))
      local want, bought = replay(predict, at(seed), OVERSTOCK, PLUS, 4, by)
      local where = seed..(by and ' by' or ' plain')
      H.eq(ok, want ~= nil, where)
      if by and ok then H.eq(d.results[1].ante, want, where..': found ante') end
      for a = 1, 4 do H.eq((d.bought or {})[a], bought[a], where..': bought at ante '..a) end
      if ok then
        hits[by and 'by' or 'plain'] = hits[by and 'by' or 'plain'] + 1
        local tier1
        for a, k in pairs(d.bought) do if k == OVERSTOCK then tier1 = a end end
        H.ok(tier1 and tier1 < (by and d.results[1].ante or 4), where..': Overstock bought before Overstock Plus')
      end
    end
  end
  H.ok(hits.by > 10 and hits.plain > 3, 'tier-2 hits: '..hits.by..' by, '..hits.plain..' plain')
  -- Glow Up behind Hone the same way.
  local glow = 0
  for i = 1, 300 do
    local seed = 'GL'..i
    local ok, d = filter.eval(at(seed), F({{kind = 'voucher', ante = 4, key = GLOW, by = true}}))
    local want = replay(predict, at(seed), HONE, GLOW, 4, true)
    H.eq(ok, want ~= nil, seed)
    if ok then glow = glow + 1; H.eq(d.results[1].ante, want, seed) end
  end
  H.ok(glow > 10, 'Glow Up hits: '..glow)
end)

H.test('a locked tier-2 voucher never shows on a profile without it; All unlocked finds it', function()
  local filter, _, state = mods()
  local locked = seeder(state, world{locked = true})
  local open = seeder(state, world())
  local n_locked, n_open = 0, 0
  for i = 1, 300 do
    local seed = 'LK'..i
    local c = {kind = 'voucher', ante = 4, key = PLUS, by = true}
    if filter.eval(locked(seed), F({c}, {all_unlocked = false})) then n_locked = n_locked + 1 end
    if filter.eval(open(seed), F({c})) then n_open = n_open + 1 end
  end
  H.eq(n_locked, 0); H.ok(n_open > 10, 'unlocked hits: '..n_open)
end)

H.test('a voucher is bought once, at the first ante a rule buys it; a later clause on it misses', function()
  local filter, predict, state = mods()
  local at = seeder(state, world())
  local early, late = 0, 0
  for i = 1, 300 do
    local seed = 'ONCE'..i
    local v1 = predict.voucher(at(seed), 1)
    if v1 ~= HIERO then
      -- By ante 3 buys v1 at ante 1, so the plain clause at ante 3 cannot
      -- see it: ante 3's pool leaves it out.
      local ok, d = filter.eval(at(seed), F({{kind = 'voucher', ante = 3, key = v1, by = true},
        {kind = 'voucher', ante = 3, key = v1}}))
      H.eq(ok, false, seed); H.eq(d.bought[1], v1, seed)
      H.ok(d.results[2] == nil or d.results[2].ok == false, seed)
      H.eq(predict.voucher(at(seed), 3, {[v1] = true}) == v1, false, seed)
      early = early + 1
      -- Alone, the plain clause buys nothing below its ante: 0.4.0's draw.
      local okp, dp = filter.eval(at(seed), F({{kind = 'voucher', ante = 3, key = v1}}))
      H.eq(okp, predict.voucher(at(seed), 3) == v1, seed)
      if okp then late = late + 1; H.eq(dp.bought[3], v1, seed); H.eq(dp.bought[1], nil, seed) end
    end
  end
  H.ok(early > 100 and late > 0, early..' seeds bought early, '..late..' plain hits at ante 3')
end)

H.test('ante 1 offers no voucher when both its blinds are taken; one taken blind leaves its shop', function()
  local filter, predict, state = mods()
  local at = seeder(state, world())
  local both, one = 0, 0
  for i = 1, 200 do
    local seed = 'SKIP'..i
    local t, v1 = predict.tags(at(seed), 1), predict.voucher(at(seed), 1)
    if v1 ~= HIERO then
      local V = {kind = 'voucher', ante = 1, key = v1}
      local ok, d = filter.eval(at(seed), F({{kind = 'tag', ante = 1, blind = 'Small', key = t.small},
        {kind = 'tag', ante = 1, blind = 'Big', key = t.big}, V}))
      H.eq(ok, false, seed); H.eq(d.results[3].ok, false, seed); H.eq(d.results[3].key, v1, seed)
      H.eq(d.bought, nil, seed..': nothing bought without a shop')
      both = both + 1
      ok, d = filter.eval(at(seed), F({{kind = 'tag', ante = 1, blind = 'Small', key = t.small}, V}))
      H.eq(ok, true, seed); H.eq(d.bought[1], v1, seed)
      -- Its route buys in the Big Blind's shop, after the skip.
      local r = assert(route().build(F({{kind = 'tag', ante = 1, blind = 'Small', key = t.small}, V}), d))
      local acts = {}
      for k, st in ipairs(r.steps) do acts[k] = st.action..'/'..st.when end
      H.eq(table.concat(acts, ' '), 'skip/Small play/Big redeem/shop', seed)
      H.eq(r.steps[3].text, ('Shop after the Big Blind: buy the %s voucher.'):format(G.P_CENTERS[v1].name), seed)
      one = one + 1
    end
  end
  H.ok(both > 0 and one > 0, both..' / '..one)
end)

H.test('a purchase shapes the walk after it: Overstock\'s third slot in every later shop', function()
  local filter, predict, state = mods()
  local at = seeder(state, world())
  local slot3, ran = 0, 0
  for i = 1, 300 do
    local seed = 'SHAPE'..i
    if predict.voucher(at(seed), 1) == OVERSTOCK then
      ran = ran + 1
      for _, key in ipairs{'j_blueprint', 'j_ceremonial', 'j_joker'} do
        local SJ = {kind = 'shop_joker', ante = 2, key = key, rerolls = 1}
        local ok, d = filter.eval(at(seed), F({{kind = 'voucher', ante = 1, key = OVERSTOCK}, SJ}))
        -- By hand: ante 1 is not walked (no clause needs its shops), so the
        -- purchase is applied to S there, and the forced Buffoon is spent in
        -- ante 1 before ante 2 is walked.
        local T = at(seed)
        state.redeem(T, OVERSTOCK)
        predict.packs(T, 1, 1)
        local w = predict.ante_walk(T, 2, {rerolls = 1, open = false, pack_tags = predict.ALL_TAG_PACKS})
        local want
        for s, shop in ipairs(w.shops) do
          H.eq(#shop.cards, 3, seed..': three slots in ante 2 shop '..s)
          for r, row in ipairs{shop.cards, shop.rerolls[1].cards} do
            for slot, c in ipairs(row) do
              if not want and c.key == key then want = {shop = s, reroll = r - 1, slot = slot} end
            end
          end
        end
        H.eq(ok, want ~= nil, seed..' '..key)
        if want then
          H.eq(d.results[2].shop, want.shop, seed); H.eq(d.results[2].reroll, want.reroll, seed)
          H.eq(d.results[2].slot, want.slot, seed)
          if want.slot == 3 then slot3 = slot3 + 1 end
        end
      end
    end
  end
  H.ok(ran > 30 and slot3 > 0, ran..' seeds with Overstock at ante 1, '..slot3..' hits in slot 3')
end)

H.test('validate refuses Petroglyph; Hieroglyph is seen, never bought; a must-not buys nothing', function()
  local filter, predict, state = mods()
  local at = seeder(state, world())
  local ok, err = filter.validate(F({{kind = 'voucher', ante = 4, key = PETRO, by = true}}))
  H.eq(ok, nil)
  H.ok(err:find('clause 1 (voucher): Petroglyph needs Hieroglyph bought first', 1, true), tostring(err))
  ok, err = filter.validate(F({{kind = 'group', clauses = {{kind = 'voucher', ante = 2, key = 'v_grabber'},
    {kind = 'voucher', ante = 3, key = PETRO}}}}))
  H.ok(err and err:find('member 2 (voucher): Petroglyph', 1, true), tostring(err))
  local findable, needs = filter.voucher_findable(PETRO)
  H.eq(findable, false); H.eq(needs, HIERO)
  H.eq(filter.voucher_findable(PLUS), true); H.eq(filter.voucher_findable(HIERO), true)
  H.eq(table.concat(filter.prerequisites(PLUS), ' '), OVERSTOCK)
  H.eq(#filter.prerequisites(OVERSTOCK), 0)
  local seen, ex = 0, 0
  for i = 1, 200 do
    local seed = 'HIER'..i
    local okh, dh = filter.eval(at(seed), F({{kind = 'voucher', ante = 3, key = HIERO, by = true}}))
    if okh then seen = seen + 1; H.eq(dh.bought, nil, seed..': Hieroglyph is not bought') end
    -- No purchase but the positive clauses': a must-not on Overstock Plus
    -- holds on every seed, since nothing buys Overstock.
    local oke, de = filter.eval(at(seed), F({{kind = 'voucher', ante = 4, key = PLUS, by = true, exclude = true}}))
    H.eq(oke, true, seed); H.eq(de.bought, nil, seed)
    -- Beside a positive Overstock clause it is judged on the walk that buys it.
    local f2 = F({{kind = 'voucher', ante = 4, key = OVERSTOCK, by = true},
      {kind = 'voucher', ante = 4, key = PLUS, by = true, exclude = true}})
    local ok2, d2 = filter.eval(at(seed), f2)
    local want = replay(predict, at(seed), OVERSTOCK, PLUS, 4, true)
    if d2.results[1].ok then
      H.eq(ok2, want == nil, seed); ex = ex + (want and 1 or 0)
    end
  end
  H.ok(seen > 30 and ex > 0, seen..' Hieroglyph hits, '..ex..' must-nots broken by Overstock Plus')
end)

------------------------------------------------------------------------------
-- The route

H.test('route: a tier-2 hit buys its tier-1 first, each a redeem step in its first shop, $10 each', function()
  local filter, _, state = mods()
  local R = route()
  local at = seeder(state, world())
  local n = 0
  for i = 1, 400 do
    local seed = 'RT'..i
    local f = F({{kind = 'voucher', ante = 4, key = PLUS, by = true}})
    local ok, d = filter.eval(at(seed), f)
    if ok then
      n = n + 1
      local r = assert(R.build(f, d))
      local x, y
      for a, k in pairs(d.bought) do if k == OVERSTOCK then x = a else y = a end end
      H.eq(y, d.results[1].ante, seed)
      H.eq(#r.steps, 4, seed)
      local function bought(k, a, key)
        local play, redeem = r.steps[k], r.steps[k + 1]
        H.eq(play.action, 'play', seed); H.eq(play.when, a > 1 and 'Boss' or 'Small', seed)
        H.eq(play.ante, a > 1 and a - 1 or 1, seed)
        H.eq(redeem.action, 'redeem', seed); H.eq(redeem.key, key, seed); H.eq(redeem.ante, a, seed)
        H.eq(redeem.when, 'shop', seed)
        return redeem.text
      end
      local t1 = bought(1, x, OVERSTOCK)
      local t2 = bought(3, y, PLUS)
      local where = x > 1 and ('Shop after the ante-'..(x - 1)..' Boss') or 'Shop after the Small Blind'
      H.eq(t1, where..': buy the Overstock voucher (Overstock Plus needs it).', seed)
      H.ok(t2:find(': buy the Overstock Plus voucher.$'), t2)
      H.eq(r.cost.ante, y, seed); H.eq(r.cost.dollars, 20, seed); H.eq(r.cost.rerolls, 0, seed)
    end
  end
  H.ok(n > 10, 'routed hits: '..n)
end)

H.test('route: in a walked ante the purchase comes first, and the row it reads is after it', function()
  local filter, predict, state = mods()
  local R = route()
  local at = seeder(state, world())
  local n = 0
  for i = 1, 400 do
    local seed = 'RW'..i
    if predict.voucher(at(seed), 2) == OVERSTOCK then
      for _, key in ipairs{'j_blueprint', 'j_ceremonial', 'j_joker'} do
        local f = F({{kind = 'voucher', ante = 2, key = OVERSTOCK}, {kind = 'shop_joker', ante = 2, key = key, rerolls = 1}})
        local ok, d = filter.eval(at(seed), f)
        if ok and d.results[2].shop == 1 and d.results[2].reroll == 0 then
          n = n + 1
          local r = assert(R.build(f, d))
          H.eq(r.steps[1].action, 'play'); H.eq(r.steps[1].text, 'Play the Boss Blind.', seed)
          H.eq(r.steps[2].action, 'redeem'); H.eq(r.steps[2].key, OVERSTOCK)
          H.eq(r.steps[2].text, ('Shop after the ante-1 Boss: buy the Overstock voucher. Then %s is in slot %d.')
            :format(G.P_CENTERS[key].name, d.results[2].slot), seed)
          H.eq(#r.steps, 2, seed..': nothing after the row it needs')
          H.eq(r.cost.dollars, 10)
        end
      end
    end
  end
  H.ok(n > 0, 'hits in the purchase shop: '..n)
  -- Purchases past the route's last ante shape nothing it needs: left out.
  local f = F({{kind = 'voucher', ante = 1, key = OVERSTOCK}})
  local r = assert(R.build(f, {checked = 1, results = {{ok = true, key = OVERSTOCK}},
    bought = {[1] = OVERSTOCK, [3] = HONE}}))
  H.eq(#r.steps, 2); H.eq(r.steps[2].key, OVERSTOCK); H.eq(r.cost.ante, 1); H.eq(r.cost.dollars, 10)
end)
