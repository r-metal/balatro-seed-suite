-- seedfinder.odds: sample counts each clause alone and the full filter once,
-- and estimate turns counts into rates, the independence product ('all') or
-- 1 - prod(1 - r) ('any'), the joint rate, expected seeds per hit, the
-- bottleneck clause and an honest confidence. Sampled on the stub world of
-- tests/test_filter.lua (its world() helper, copied verbatim), with the
-- reference counts taken from bhcore.sim.predict by hand.
local H = ...

local function center(key, t)
  t.key = key
  t.config = t.config or {}
  return t
end

local TAGS = {'tag_uncommon', 'tag_juggle', 'tag_charm', 'tag_economy', 'tag_ethereal'}

-- A stub world shaped like tests/test_predict_shop.lua's, with the tags,
-- legendaries and packs the filter clauses name.
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
    center('j_perkeo', {name = 'Perkeo', set = 'Joker', rarity = 4, order = 8, eternal_compat = true, perishable_compat = true}),
    center('c_fool', {name = 'The Fool', set = 'Tarot', order = 1, consumeable = true}),
    center('c_magician', {name = 'The Magician', set = 'Tarot', order = 2, consumeable = true}),
    center('c_strength', {name = 'Strength', set = 'Tarot', order = 3, consumeable = true}),
    center('c_hermit', {name = 'The Hermit', set = 'Tarot', order = 4, consumeable = true}),
    center('c_empress', {name = 'The Empress', set = 'Tarot', order = 5, consumeable = true}),
    center('c_emperor', {name = 'The Emperor', set = 'Tarot', order = 6, consumeable = true}),
    center('c_pluto', {name = 'Pluto', set = 'Planet', order = 1, consumeable = true, config = {hand_type = 'High Card'}}),
    center('c_mercury', {name = 'Mercury', set = 'Planet', order = 2, consumeable = true, config = {hand_type = 'Pair'}}),
    center('c_familiar', {name = 'Familiar', set = 'Spectral', order = 1, consumeable = true}),
    center('c_grim', {name = 'Grim', set = 'Spectral', order = 2, consumeable = true}),
    center('c_soul', {name = 'The Soul', set = 'Spectral', order = 17, consumeable = true, hidden = true}),
    center('c_black_hole', {name = 'Black Hole', set = 'Spectral', order = 18, consumeable = true, hidden = true}),
    center('c_base', {name = 'Default Base', set = 'Default', order = 1}),
    center('m_bonus', {name = 'Bonus', set = 'Enhanced', order = 2}),
    center('v_overstock_norm', {name = 'Overstock', set = 'Voucher', order = 1, unlocked = true}),
    center('v_grabber', {name = 'Grabber', set = 'Voucher', order = 2, unlocked = true}),
    center('v_hone', {name = 'Hone', set = 'Voucher', order = 3, unlocked = true}),
    center('b_red', {name = 'Red Deck', set = 'Back', order = 1}),
  }
  local boosters = {
    center('p_arcana_normal_1', {order = 1, name = 'Arcana Pack', weight = 1, kind = 'Arcana', set = 'Booster', config = {extra = 3, choose = 1}}),
    center('p_arcana_mega_1', {order = 2, name = 'Mega Arcana Pack', weight = 0.25, kind = 'Arcana', set = 'Booster', config = {extra = 5, choose = 2}}),
    center('p_arcana_mega_2', {order = 3, name = 'Mega Arcana Pack', weight = 0.25, kind = 'Arcana', set = 'Booster', config = {extra = 5, choose = 2}}),
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
  for i, k in ipairs(o.tags or TAGS) do
    tags[i] = {key = k, min_ante = k == 'tag_ethereal' and not o.ethereal_any and 2 or nil}
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
    bl_wall = {key = 'bl_wall', boss = {min = 2, max = 10}},
  }
  G.handlist = {'Pair', 'High Card'}
  G.jokers = {cards = {}, config = {card_limit = 5}}
  G.consumeables = {cards = {}, config = {card_limit = 2}}
  G.playing_cards = {}
  G.GAME = {live = true, pseudorandom = {seed = 'LIVE'}, round_resets = {ante = 5}}
  local seed = o.seed or 'FILTSEED'
  local game = {
    round_resets = {ante = 1}, win_ante = 8,
    pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)},
    used_jokers = {}, used_vouchers = {}, banned_keys = {}, pool_flags = {},
    bosses_used = {bl_hook = 0, bl_club = 0, bl_wall = 0},
    hands = {['High Card'] = {played = 0, visible = true}, Pair = {played = 0, visible = true}},
    modifiers = {}, edition_rate = 1, shop = {joker_max = 2},
    joker_rate = 20, tarot_rate = 4, planet_rate = 4, playing_card_rate = 0, spectral_rate = 0,
  }
  return {game = game, all_unlocked = false}
end

local function mods()
  return require('seedfinder.odds'), require('seedfinder.filter'),
    require('bhcore.sim.predict'), require('bhcore.sim.state')
end

-- One stub world, re-seeded per seed (the stub has no Game.init_game_object,
-- so filter.fresh cannot build it): at(seed) is a fresh S for that seed.
local function seeder(base, state)
  return function(seed)
    local T = state.copy(base)
    T.game.pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)}
    return T
  end
end

local function F(clauses, extra)
  local f = {name = 'odds', clauses = clauses}
  for k, v in pairs(extra or {}) do f[k] = v end
  return f
end

local function seeds(prefix, n)
  local out = {}
  for i = 1, n do out[i] = prefix..i end
  return out
end

local function near(a, b, msg)
  if math.abs(a - b) > 1e-12 then error((msg or 'near')..': expected '..tostring(b)..', got '..tostring(a), 2) end
end

local CHARM = {kind = 'tag', ante = 1, blind = 'Small', key = 'tag_charm'}
local HOOK = {kind = 'boss', ante = 1, key = 'bl_hook'}

------------------------------------------------------------------------------

H.test('sample: single-clause and full-filter counts on 2,000 seeds match a direct predict count', function()
  local odds, filter, predict, state = mods()
  local at = seeder(world(), state)
  local list = seeds('ODDS', 2000)
  local want = {0, 0}
  local both, either = 0, 0
  for _, seed in ipairs(list) do
    local charm = predict.tags(at(seed), 1).small == 'tag_charm'
    local hook = predict.boss(at(seed), 1) == 'bl_hook'
    if charm then want[1] = want[1] + 1 end
    if hook then want[2] = want[2] + 1 end
    if charm and hook then both = both + 1 end
    if charm or hook then either = either + 1 end
  end
  H.ok(want[1] > 200 and want[1] < 800, 'Charm Small is neither rare nor certain: '..want[1])
  H.ok(want[2] > 600 and want[2] < 1400, 'Hook ante 1 is about half: '..want[2])
  local function eval(f1, seed) return (filter.eval(at(seed), f1)) end
  local live, before = G.GAME, STR_PACK(G.GAME)
  local c = odds.sample(F({CHARM, HOOK}), list, eval)
  H.ok(G.GAME == live and STR_PACK(G.GAME) == before, 'live G.GAME untouched')
  H.eq(c.n, 2000); H.eq(c.mode, 'all')
  H.eq(c.clauses[1], want[1], 'Charm Small count')
  H.eq(c.clauses[2], want[2], 'Hook count')
  H.eq(c.full, both, 'full filter count')
  local e = odds.estimate(c)
  near(e.per_clause[1], want[1] / 2000, 'rate 1')
  near(e.per_clause[2], want[2] / 2000, 'rate 2')
  near(e.joint, both / 2000, 'joint')
  near(e.expected_seeds, 2000 / both, 'expected seeds')
  H.eq(e.confidence, 'measured')
  H.eq(e.bottleneck, want[1] <= want[2] and 1 or 2)
  local ca = odds.sample(F({CHARM, HOOK}, {mode = 'any'}), list, eval)
  H.eq(ca.mode, 'any')
  H.eq(ca.clauses[1], want[1]); H.eq(ca.clauses[2], want[2])
  H.eq(ca.full, either, 'any-mode full count')
end)

H.test('sample: each clause runs alone under the run settings; the full filter once per seed', function()
  local odds = mods()
  local f = F({CHARM, HOOK, {kind = 'legendary', index = 1}},
    {stake = 3, deck = 'b_red', all_unlocked = true, antes = 2, mode = 'any'})
  local calls = {}
  local c = odds.sample(f, {'A', 'B'}, function(f1, seed)
    calls[#calls + 1] = {f = f1, seed = seed}
    return f1 == f or f1.clauses[1] == HOOK
  end)
  H.eq(#calls, 2 * 4, 'three clauses + the full filter, per seed')
  for i, call in ipairs(calls) do
    local k = (i - 1) % 4 + 1
    H.eq(call.seed, i <= 4 and 'A' or 'B')
    if k == 4 then
      H.ok(call.f == f, 'the full filter itself, last')
    else
      local s = call.f
      H.ok(s ~= f and #s.clauses == 1 and s.clauses[1] == f.clauses[k], 'clause '..k..' alone')
      H.eq(s.mode, 'all'); H.eq(s.stake, 3); H.eq(s.deck, 'b_red')
      H.eq(s.all_unlocked, true); H.eq(s.antes, 2)
      H.ok(require('seedfinder.filter').validate(s), 'the one-clause filter is valid')
    end
  end
  H.eq(c.n, 2); H.eq(c.mode, 'any'); H.eq(c.full, 2)
  H.eq(c.clauses[1], 0); H.eq(c.clauses[2], 2); H.eq(c.clauses[3], 0)
end)

H.test('sample: filter.eval_seed is the default evaluator; bad input raises', function()
  local odds, filter = mods()
  local real, seen = filter.eval_seed, {}
  filter.eval_seed = function(f1, seed) seen[#seen + 1] = seed; return true end
  local ok, c = pcall(odds.sample, F({CHARM}), {'S1', 'S2'})
  filter.eval_seed = real
  H.ok(ok, c)
  H.eq(#seen, 4); H.eq(c.clauses[1], 2); H.eq(c.full, 2)
  H.ok(not pcall(odds.sample, {name = 'bad', clauses = {}}, {'S1'}), 'invalid filter raises')
  H.ok(not pcall(odds.sample, F({CHARM}), {}), 'empty seed list raises')
end)

H.test('estimate all: the independence product, the joint rate and expected seeds', function()
  local odds = mods()
  local e = odds.estimate{n = 1000, mode = 'all', clauses = {500, 200, 100}, full = 20}
  near(e.per_clause[1], 0.5); near(e.per_clause[2], 0.2); near(e.per_clause[3], 0.1)
  near(e.independent, 0.5 * 0.2 * 0.1, 'product')
  near(e.joint, 0.02, 'observed joint')
  near(e.expected_seeds, 50, 'from the joint rate')
  H.eq(e.confidence, 'measured'); H.eq(e.bottleneck, 3)
  H.eq(#e.never, 0); H.eq(e.reason, nil); H.eq(e.n, 1000); H.eq(e.full, 20)
  -- No full pass: the product carries the estimate, flagged as such.
  local x = odds.estimate{n = 1000, mode = 'all', clauses = {500, 200, 100}, full = 0}
  H.eq(x.joint, nil)
  near(x.expected_seeds, 1 / 0.01, 'from the product')
  H.eq(x.confidence, 'extrapolated')
end)

H.test('estimate any: 1 - prod(1 - r), and confidence needs 5 joint passes', function()
  local odds = mods()
  local e = odds.estimate{n = 1000, mode = 'any', clauses = {100, 200}, full = 0}
  near(e.independent, 1 - 0.9 * 0.8, 'any-mode formula')
  H.eq(e.joint, nil)
  near(e.expected_seeds, 1 / 0.28)
  H.eq(e.confidence, 'extrapolated'); H.eq(e.bottleneck, 1)
  local thin = odds.estimate{n = 1000, mode = 'any', clauses = {100, 200}, full = 4}
  near(thin.joint, 0.004); near(thin.expected_seeds, 250)
  H.eq(thin.confidence, 'extrapolated', '4 passes are not a measurement')
  H.eq(odds.estimate{n = 1000, mode = 'any', clauses = {100, 200}, full = 5}.confidence, 'measured')
end)

H.test('estimate: a clause that never passed gives math.huge and is named', function()
  local odds = mods()
  local e = odds.estimate{n = 1000, mode = 'all', clauses = {300, 0, 50}, full = 0}
  H.eq(e.expected_seeds, math.huge); H.eq(e.independent, 0)
  H.eq(#e.never, 1); H.eq(e.never[1], 2); H.eq(e.bottleneck, 2)
  H.ok(e.reason and e.reason:find('clause 2 never passed in 1000 seeds', 1, true), tostring(e.reason))
  H.eq(e.confidence, 'extrapolated')
  -- any: one dead clause is survivable, all dead is not.
  local some = odds.estimate{n = 1000, mode = 'any', clauses = {0, 10}, full = 0}
  near(some.expected_seeds, 100); H.eq(some.never[1], 1); H.eq(some.reason, nil)
  local none = odds.estimate{n = 1000, mode = 'any', clauses = {0, 0}, full = 0}
  H.eq(none.expected_seeds, math.huge); H.eq(#none.never, 2)
  H.ok(none.reason:find('clause 1 never passed', 1, true), none.reason)
end)

H.test('sample + estimate: a locked clause (a min-ante-2 boss at ante 1) never passes', function()
  local odds, filter, _, state = mods()
  local at = seeder(world(), state)
  local c = odds.sample(F({CHARM, {kind = 'boss', ante = 1, key = 'bl_wall'}}), seeds('LOCK', 200),
    function(f1, seed) return (filter.eval(at(seed), f1)) end)
  H.ok(c.clauses[1] > 0, 'Charm passes somewhere'); H.eq(c.clauses[2], 0); H.eq(c.full, 0)
  local e = odds.estimate(c)
  H.eq(e.expected_seeds, math.huge); H.eq(e.bottleneck, 2); H.eq(e.never[1], 2)
  H.ok(e.reason:find('clause 2', 1, true), e.reason)
end)

H.test('estimate: bottleneck is the lowest rate, the first on a tie; malformed counts are refused', function()
  local odds = mods()
  H.eq(odds.estimate{n = 100, mode = 'all', clauses = {40, 10, 30, 10}, full = 1}.bottleneck, 2)
  H.eq(odds.estimate{n = 100, mode = 'any', clauses = {90, 95, 80}, full = 99}.bottleneck, 3)
  H.eq(odds.estimate{n = 100, mode = 'all', clauses = {7}, full = 7}.bottleneck, 1)
  for _, bad in ipairs{
    'x', {mode = 'all', clauses = {1}, full = 0}, {n = 0, mode = 'all', clauses = {0}, full = 0},
    {n = 10, mode = 'some', clauses = {1}, full = 0}, {n = 10, mode = 'all', clauses = {}, full = 0},
    {n = 10, mode = 'all', clauses = {11}, full = 0}, {n = 10, mode = 'all', clauses = {1.5}, full = 0},
    {n = 10, mode = 'all', clauses = {1}, full = -1},
  } do
    local e, err = odds.estimate(bad)
    H.ok(e == nil and type(err) == 'string', 'refused: '..tostring(err))
  end
end)
