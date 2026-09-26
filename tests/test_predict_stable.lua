-- sim/predict.lua stable streams: tags, boss, voucher, legendaries.
-- Runs vanilla's own RNG and pool primitives (build/game misc_functions.lua and
-- common_events.lua, loaded as they are) against a small synthetic prototype
-- world, so what is tested is predict's wiring: which primitive, which ante,
-- which order, what S keeps, and that the live G.GAME is never touched.
-- The golden reference against the real game is rig/scenarios/golden_stable.lua.
local H = ...

local function load_vanilla()
  dofile(H.root..'/build/game/functions/misc_functions.lua')
  dofile(H.root..'/build/game/functions/common_events.lua')
end

-- Prototype data shaped like vanilla's (only the fields the primitives read).
local function world()
  load_vanilla()
  BHCore = {}
  local legends = {'j_caino', 'j_triboulet', 'j_yorick', 'j_chicot', 'j_perkeo'}
  G.P_CENTERS, G.P_JOKER_RARITY_POOLS = {}, {{}, {}, {}, {}}
  for i, k in ipairs(legends) do
    local c = {key = k, set = 'Joker', rarity = 4, name = k, unlocked = false, order = i}
    G.P_CENTERS[k] = c
    G.P_JOKER_RARITY_POOLS[4][i] = c
  end
  for i, k in ipairs{'j_joker', 'j_greedy'} do
    local c = {key = k, set = 'Joker', rarity = 1, name = k, unlocked = true, order = i}
    G.P_CENTERS[k] = c
    G.P_JOKER_RARITY_POOLS[1][i] = c
  end
  G.P_CENTERS.e_negative = {key = 'e_negative', set = 'Edition', discovered = false}
  G.P_CENTERS.e_foil = {key = 'e_foil', set = 'Edition', discovered = true}
  local vouchers = {
    {key = 'v_overstock_norm', set = 'Voucher', unlocked = true},
    {key = 'v_overstock_plus', set = 'Voucher', unlocked = true, requires = {'v_overstock_norm'}},
    {key = 'v_grabber', set = 'Voucher', unlocked = true},
    {key = 'v_hone', set = 'Voucher', unlocked = true},
  }
  local tags = {
    {key = 'tag_uncommon'}, {key = 'tag_rare'}, {key = 'tag_juggle'},
    {key = 'tag_negative', requires = 'e_negative', min_ante = 2},
    {key = 'tag_foil', requires = 'e_foil'},
    {key = 'tag_top_up', min_ante = 2},
  }
  for _, v in ipairs(vouchers) do G.P_CENTERS[v.key] = v end
  G.P_CENTER_POOLS = {Voucher = vouchers, Tag = tags}
  G.P_TAGS = {}
  for _, t in ipairs(tags) do G.P_TAGS[t.key] = t end
  G.P_BLINDS = {
    bl_small = {key = 'bl_small'}, bl_big = {key = 'bl_big'},
    bl_hook = {key = 'bl_hook', boss = {min = 1, max = 10}},
    bl_club = {key = 'bl_club', boss = {min = 1, max = 10}},
    bl_wall = {key = 'bl_wall', boss = {min = 2, max = 10}},
    bl_final_bell = {key = 'bl_final_bell', boss = {showdown = true, min = 10, max = 10}},
  }
  G.jokers = {cards = {}, config = {card_limit = 5}}
  G.consumeables = {cards = {}, config = {card_limit = 2}}
  G.playing_cards = {}
  G.GAME = {live = true, pseudorandom = {seed = 'LIVE'}, round_resets = {ante = 5}}
end

local function sim_state(seed)
  local g = {
    round_resets = {ante = 1}, used_jokers = {}, used_vouchers = {}, pool_flags = {},
    banned_keys = {}, hands = {}, win_ante = 8, edition_rate = 1,
    bosses_used = {bl_hook = 0, bl_club = 0, bl_wall = 0, bl_final_bell = 0},
    pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)},
  }
  return {game = g, all_unlocked = false}
end

local function mods()
  return require('bhcore.sim.predict'), require('bhcore.sim.state')
end

-- Runs fn with G.GAME = a copy of S's game: vanilla called directly, the reference.
local function direct(S, fn)
  local _, state = mods()
  local T = state.copy(S)
  local live = G.GAME
  G.GAME = T.game
  local ok, a, b = pcall(fn)
  G.GAME = live
  assert(ok, a)
  return a, b, T
end

H.test('tags(S, 1) is get_next_tag_key twice at ante 1 and advances Tag1', function()
  world()
  local predict = mods()
  local S = sim_state('TAGSEED1')
  local ws, wb = direct(S, function() return get_next_tag_key(), get_next_tag_key() end)
  local t = predict.tags(S, 1)
  H.eq(t.small, ws, 'small')
  H.eq(t.big, wb, 'big')
  H.ok(S.game.pseudorandom.Tag1 ~= nil, 'Tag1 stream advanced in S')
  H.eq(S.game.round_resets.ante, 1, 'ante left at 1')
end)

H.test('tags honour min_ante and requires-discovered, per ante', function()
  world()
  local predict = mods()
  for i = 1, 60 do
    local S = sim_state('MINANTE'..i)
    local t1 = predict.tags(S, 1)
    for _, k in ipairs{t1.small, t1.big} do
      H.ok(k ~= 'tag_top_up' and k ~= 'tag_negative', 'ante-1 tag '..k..' is min_ante 2')
    end
    local t2 = predict.tags(S, 2)
    H.ok(t2.small ~= 'tag_negative' and t2.big ~= 'tag_negative', 'tag_negative needs e_negative discovered')
    H.eq(S.game.round_resets.ante, 2, 'ante now 2')
    H.ok(S.game.pseudorandom.Tag2 ~= nil, 'Tag2 stream used')
  end
end)

H.test('boss is the global stream: ascending antes, bosses_used, showdown', function()
  world()
  local predict = mods()
  local S = sim_state('BOSSSEED')
  local b1 = predict.boss(S, 1)
  local b2 = predict.boss(S, 2)
  H.ok(b1 == 'bl_hook' or b1 == 'bl_club', 'ante 1 boss eligible: '..b1)
  H.ok(b2 ~= b1, 'least-used filter: ante 2 differs from ante 1')
  H.eq(S.game.bosses_used[b1], 1, 'bosses_used bumped')
  -- The same calls on vanilla directly give the same sequence.
  local T = sim_state('BOSSSEED')
  local r1, r2 = direct(T, function()
    G.GAME.round_resets.ante = 1
    local a = get_new_boss()
    G.GAME.round_resets.ante = 2
    return a, get_new_boss()
  end)
  H.eq(b1, r1, 'ante 1 vs vanilla')
  H.eq(b2, r2, 'ante 2 vs vanilla')
  H.eq(predict.boss(S, 8), 'bl_final_bell', 'ante 8 is a showdown')
end)

H.test('voucher follows used_vouchers and tier-2 requires', function()
  world()
  local predict = mods()
  for i = 1, 40 do
    local S = sim_state('VOUCH'..i)
    S.game.used_vouchers = {v_grabber = true}
    local v = predict.voucher(S, 1)
    H.ok(v ~= 'v_grabber', 'used voucher offered')
    H.ok(v ~= 'v_overstock_plus', 'tier 2 without its tier 1')
    H.ok(S.game.pseudorandom.Voucher1 ~= nil, 'Voucher1 stream used')
  end
  local S = sim_state('VOUCHREF')
  local want = direct(S, function() G.GAME.round_resets.ante = 3; return get_next_voucher_key() end)
  H.eq(predict.voucher(S, 3), want, 'ante 3 vs vanilla')
end)

H.test('per-ante tag and voucher streams are independent of call order', function()
  world()
  local predict = mods()
  local A, B = sim_state('ORDER1'), sim_state('ORDER1')
  local ta, va = predict.tags(A, 2), predict.voucher(A, 2)
  local vb = predict.voucher(B, 2)
  local tb = predict.tags(B, 2)
  H.eq(ta.small, tb.small); H.eq(ta.big, tb.big); H.eq(va, vb)
end)

H.test('legendaries: Joker4 sequence, no repeats while held, used_jokers marked', function()
  world()
  local predict = mods()
  local S = sim_state('SOULSEED')
  local l = predict.legendaries(S, 5)
  H.eq(#l, 5)
  local got = {}
  for _, r in ipairs(l) do
    H.ok(G.P_CENTERS[r.key] and G.P_CENTERS[r.key].rarity == 4, 'not a legendary: '..tostring(r.key))
    H.ok(not got[r.key], 'repeat '..r.key)
    got[r.key] = true
    H.ok(S.game.used_jokers[r.key], 'used_jokers not marked for '..r.key)
  end
  -- Continuing on a copy after 2 equals the tail of one call of 5.
  local T = sim_state('SOULSEED')
  local first = predict.legendaries(T, 2)
  local rest = predict.legendaries(T, 3)
  H.eq(first[1].key, l[1].key); H.eq(first[2].key, l[2].key)
  for i = 1, 3 do H.eq(rest[i].key, l[i + 2].key, 'continued '..i) end
  -- Every legendary held: vanilla's empty-pool fallback.
  H.eq(predict.legendaries(S, 1)[1].key, 'j_joker', 'empty legendary pool')
end)

H.test('legendaries draws rarity..A..sou, Joker4 (no ante) and edisou..A', function()
  world()
  local predict = mods()
  local S = sim_state('SOULDRAW')
  S.game.round_resets.ante = 3
  predict.legendaries(S, 1)
  local pr = S.game.pseudorandom
  H.ok(pr.rarity3sou and pr.Joker4 and pr.edisou3, 'expected streams rarity3sou, Joker4, edisou3')
  H.ok(pr.Joker43 == nil and pr.Joker4sou3 == nil, 'Joker4 must not carry the ante or append')
  H.eq(S.game.round_resets.ante, 3, 'legendaries keeps S ante')
  -- Same first key as vanilla's pool draw with the same streams.
  local want = direct(sim_state('SOULDRAW'), function()
    G.GAME.round_resets.ante = 3
    local pool, key = get_current_pool('Joker', nil, true, 'sou')
    local c = pseudorandom_element(pool, pseudoseed(key))
    local it = 1
    while c == 'UNAVAILABLE' do it = it + 1; c = pseudorandom_element(pool, pseudoseed(key..'_resample'..it)) end
    return c
  end)
  local U = sim_state('SOULDRAW'); U.game.round_resets.ante = 3
  H.eq(predict.legendaries(U, 1)[1].key, want, 'vs vanilla pool draw')
end)

H.test('legendaries edition comes from poll_edition', function()
  world()
  local predict = mods()
  local S = sim_state('EDITION1')
  S.game.edition_rate = 1000 -- every poll lands on an edition
  for _, r in ipairs(predict.legendaries(S, 3)) do
    H.ok(r.edition == 'polychrome' or r.edition == 'negative', 'edition '..tostring(r.edition))
  end
  local T = sim_state('EDITION1')
  T.game.edition_rate = 0
  for _, r in ipairs(predict.legendaries(T, 3)) do
    H.ok(r.edition == nil or r.edition == 'negative', 'rate 0 edition '..tostring(r.edition))
  end
end)

H.test('the live G.GAME and areas are untouched, sim_depth back to 0', function()
  world()
  local predict = mods()
  local live, jokers = G.GAME, G.jokers
  local before = STR_PACK(G.GAME)
  local S = sim_state('LIVETEST')
  predict.boss(S, 1); predict.voucher(S, 1); predict.tags(S, 1); predict.legendaries(S, 2)
  H.ok(G.GAME == live, 'G.GAME swapped back')
  H.eq(STR_PACK(G.GAME), before, 'live pack')
  H.ok(G.jokers == jokers, 'G.jokers restored')
  H.eq(BHCore.sim_depth, 0, 'sim_depth')
end)

H.test('errors are raised, and the live run is restored', function()
  world()
  local predict = mods()
  local live = G.GAME
  H.ok(not pcall(predict.tags, {}, 1), 'not a sim state')
  H.ok(not pcall(predict.boss, sim_state('X'), 0), 'ante 0')
  H.ok(not pcall(predict.voucher, sim_state('X'), 1.5), 'fractional ante')
  H.ok(not pcall(predict.legendaries, sim_state('X'), -1), 'negative n')
  G.P_BLINDS = nil -- get_new_boss fails inside the sandbox
  local ok, err = pcall(predict.boss, sim_state('X'), 1)
  H.ok(not ok and tostring(err) ~= '', 'inner error re-raised')
  H.ok(G.GAME == live, 'G.GAME restored after error')
  H.eq(BHCore.sim_depth, 0, 'sim_depth after error')
end)
