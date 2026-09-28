-- seedfinder.filter: validate / eval / serialize, cheapest-first
-- short-circuiting, every clause kind, and the Charm/Ethereal tag packs.
-- Runs on vanilla's own RNG and pool primitives (misc_functions.lua and
-- common_events.lua from build/game) over a small stub prototype set. The
-- reference for every clause is bhcore.sim.predict called by hand, in the
-- order documented in predict.lua, on a copy of the same state: eval must
-- read exactly those streams. The real-game reference is
-- rig/scenarios/finder_filter.lua.
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
  return require('seedfinder.filter'), require('bhcore.sim.predict'), require('bhcore.sim.state')
end

-- Every stream key pseudoseed advances while fn runs.
local function streams(fn)
  local real = pseudoseed
  local log = {}
  pseudoseed = function(k, p) log[#log + 1] = k; return real(k, p) end
  local ok, a, b = pcall(fn)
  pseudoseed = real
  assert(ok, a)
  return log, a, b
end

local function drew(log, pat)
  for _, k in ipairs(log) do if k:find(pat) then return true end end
  return false
end

local function F(clauses, extra)
  local f = {name = 'test', clauses = clauses}
  for k, v in pairs(extra or {}) do f[k] = v end
  return f
end

local function deep_eq(a, b, path)
  path = path or 'f'
  if type(a) ~= type(b) then error(path..': '..type(a)..' vs '..type(b), 2) end
  if type(a) ~= 'table' then
    if a ~= b then error(path..': '..tostring(a)..' vs '..tostring(b), 2) end
    return
  end
  for k, v in pairs(a) do deep_eq(v, b[k], path..'.'..tostring(k)) end
  for k in pairs(b) do if a[k] == nil then error(path..'.'..tostring(k)..' missing', 2) end end
end

local EVERY_KIND = {
  {kind = 'tag', ante = 1, blind = 'Small', key = 'tag_charm'},
  {kind = 'boss', ante = 2, key = 'bl_wall'},
  {kind = 'voucher', ante = 1, key = 'v_hone'},
  {kind = 'legendary', index = 2, key = 'j_perkeo'},
  {kind = 'legendary', index = 1},
  {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
  {kind = 'soul_in_pack', ante = 2, pack = 'spectral'},
  {kind = 'shop_joker', ante = 2, key = 'j_blueprint', rerolls = 3},
  {kind = 'pack', ante = 1, key_prefix = 'p_arcana'},
}

------------------------------------------------------------------------------

H.test('validate accepts every clause kind and the defaults', function()
  world()
  local filter = mods()
  H.eq(filter.validate(F(EVERY_KIND, {stake = 8, deck = 'b_red', antes = 3, mode = 'any', all_unlocked = true})), true)
  H.eq(filter.validate(F({{kind = 'tag', ante = 1, key = 'tag_juggle'}})), true, 'blind defaults to any')
  H.eq(filter.validate(F({{kind = 'pack', ante = 1, key_prefix = 'p_'}})), true, 'any pack')
end)

H.test('validate rejects bad filter fields', function()
  world()
  local filter = mods()
  local tag = {kind = 'tag', ante = 1, key = 'tag_charm'}
  local bad = {
    {'x', 'not a table'},
    {{clauses = {tag}}, 'name'},
    {F({tag}, {stake = 9}), 'stake'},
    {F({tag}, {stake = 1.5}), 'stake'},
    {F({tag}, {deck = 'b_nope'}), 'deck'},
    {F({tag}, {mode = 'some'}), 'mode'},
    {F({tag}, {all_unlocked = 1}), 'all_unlocked'},
    {F({}), 'at least one clause'},
    {F({tag}, {antes = 0}), 'antes'},
    {F({tag, [3] = tag}), 'list'},
  }
  for _, b in ipairs(bad) do
    local ok, err = filter.validate(b[1])
    H.eq(ok, nil, b[2])
    H.ok(type(err) == 'string' and err:find(b[2], 1, true), 'err mentions '..b[2]..': '..tostring(err))
  end
end)

H.test('validate rejects bad clauses, naming the clause', function()
  world()
  local filter = mods()
  local bad = {
    {{kind = 'nope', ante = 1}, 'unknown kind'},
    {{kind = 'tag', ante = 1, key = 'tag_charm', extra = 1}, 'unknown field'},
    {{kind = 'tag', ante = 0, key = 'tag_charm'}, 'ante'},
    {{kind = 'tag', ante = 1.5, key = 'tag_charm'}, 'ante'},
    {{kind = 'tag', ante = 1, blind = 'Boss', key = 'tag_charm'}, 'blind'},
    {{kind = 'tag', ante = 1, key = 'tag_missing'}, 'unknown tag'},
    {{kind = 'boss', ante = 1, key = 'bl_small'}, 'unknown boss'},
    {{kind = 'voucher', ante = 1, key = 'v_nope'}, 'unknown voucher'},
    {{kind = 'legendary', index = 3}, 'index'},
    {{kind = 'legendary', index = 1, key = 'j_joker'}, 'legendary'},
    {{kind = 'soul_in_pack', ante = 1, pack = 'celestial'}, 'pack'},
    {{kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = 'yes'}, 'from_tag'},
    {{kind = 'shop_joker', ante = 1, key = 'j_nope'}, 'unknown card'},
    {{kind = 'shop_joker', ante = 1, key = 'j_joker', rerolls = -1}, 'rerolls'},
    {{kind = 'pack', ante = 1, key_prefix = 'arcana'}, 'key_prefix'},
  }
  for _, b in ipairs(bad) do
    local ok, err = filter.validate(F({{kind = 'tag', ante = 1, key = 'tag_charm'}, b[1]}))
    H.eq(ok, nil, b[2])
    H.ok(err:find('clause 2', 1, true) and err:find(b[2], 1, true), 'err: '..tostring(err))
  end
  local ok, err = filter.validate(F({{kind = 'tag', ante = 3, key = 'tag_charm'}}, {antes = 2}))
  H.eq(ok, nil); H.ok(err:find('1..2', 1, true), 'ante bounded by antes: '..err)
end)

H.test('serialize / deserialize round-trip through STR_PACK', function()
  world()
  local filter = mods()
  local f = F(EVERY_KIND, {stake = 4, deck = 'b_red', antes = 2, mode = 'all'})
  local s = assert(filter.serialize(f))
  H.eq(s:sub(1, 6), 'return')
  deep_eq(filter.deserialize(s), f)
  deep_eq(filter.deserialize(STR_PACK(f)), f, 'plain STR_PACK output')
  local n, err = filter.serialize(F({}))
  H.eq(n, nil); H.ok(err:find('clause'), err)
end)

H.test('deserialize rejects junk, invalid filters and code, in an empty environment', function()
  world()
  local filter = mods()
  H.eq(filter.deserialize(42), nil)
  H.eq(filter.deserialize('{}'), nil, 'not a return chunk')
  H.eq(filter.deserialize('return {'), nil, 'syntax error')
  H.eq(filter.deserialize('return {name = "x", clauses = {}}'), nil, 'invalid filter')
  local ran = false
  _G.__filter_probe = function() ran = true end
  local f, err = filter.deserialize('return {name = __filter_probe(), clauses = {}}')
  _G.__filter_probe = nil
  H.eq(f, nil); H.ok(err, 'error returned')
  H.eq(ran, false, 'globals are not reachable from a packed filter')
end)

H.test('tag clause: Small, Big and any against predict.tags', function()
  local filter, predict, state = mods()
  for i = 1, 20 do
    local S = world{seed = 'TAG'..i}
    local want = predict.tags(state.copy(S), 2)
    local small = filter.eval(state.copy(S), F({{kind = 'tag', ante = 2, blind = 'Small', key = want.small}}))
    local big = filter.eval(state.copy(S), F({{kind = 'tag', ante = 2, blind = 'Big', key = want.big}}))
    local any, d = filter.eval(state.copy(S), F({{kind = 'tag', ante = 2, key = want.big}}))
    H.ok(small and big and any, 'seed TAG'..i)
    H.eq(d.results[1].small, want.small); H.eq(d.results[1].big, want.big)
    local other = want.small == 'tag_juggle' and 'tag_economy' or 'tag_juggle'
    if want.big ~= other then
      H.eq(filter.eval(state.copy(S), F({{kind = 'tag', ante = 2, blind = 'Small', key = want.big}})), want.small == want.big,
        'Small does not look at Big')
    end
  end
end)

H.test('boss clause draws the global boss stream 1..A in order; voucher per ante', function()
  local filter, predict, state = mods()
  for i = 1, 10 do
    local S = world{seed = 'BOSS'..i}
    local T = state.copy(S)
    local b1, b2, b3 = predict.boss(T, 1), predict.boss(T, 2), predict.boss(T, 3)
    local v3 = predict.voucher(state.copy(S), 3)
    local ok, d = filter.eval(state.copy(S), F({{kind = 'boss', ante = 3, key = b3}, {kind = 'voucher', ante = 3, key = v3}}))
    H.ok(ok, 'boss 3 + voucher 3')
    H.eq(d.results[1].key, b3); H.eq(d.results[2].key, v3)
    -- Two boss clauses share one draw per ante.
    local ok2 = filter.eval(state.copy(S), F({{kind = 'boss', ante = 2, key = b2}, {kind = 'boss', ante = 1, key = b1}}))
    H.ok(ok2, 'bosses 1 and 2 from one stream walk')
  end
end)

H.test('legendary clause: index 1 and 2 from Joker4; key nil matches any', function()
  local filter, predict, state = mods()
  local S = world{seed = 'LEGEND'}
  local want = predict.legendaries(state.copy(S), 2)
  local ok, d = filter.eval(state.copy(S), F({{kind = 'legendary', index = 1, key = want[1].key},
    {kind = 'legendary', index = 2, key = want[2].key}}))
  H.ok(ok, 'both legendaries')
  H.eq(d.results[2].key, want[2].key); H.eq(d.results[2].edition, want[2].edition)
  H.ok(filter.eval(state.copy(S), F({{kind = 'legendary', index = 2}})), 'any legendary')
  local other = want[1].key == 'j_caino' and 'j_yorick' or 'j_caino'
  H.eq(filter.eval(state.copy(S), F({{kind = 'legendary', index = 1, key = other}})), false)
end)

H.test('mode all short-circuits at the first false clause, cheapest first', function()
  local filter, predict, state = mods()
  local S = world{seed = 'SHORT'}
  local tags = predict.tags(state.copy(S), 1)
  local miss = tags.small == 'tag_juggle' and 'tag_economy' or 'tag_juggle'
  if tags.big == miss then miss = 'tag_uncommon' end
  -- Written most expensive first: the tag still runs first and ends it.
  local f = F({{kind = 'shop_joker', ante = 2, key = 'j_joker', rerolls = 2},
    {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
    {kind = 'legendary', index = 1}, {kind = 'boss', ante = 2, key = 'bl_wall'},
    {kind = 'tag', ante = 1, blind = 'Small', key = miss}})
  local T = state.copy(S)
  local log, ok, d = streams(function() return filter.eval(T, f) end)
  H.eq(ok, false)
  H.eq(d.checked, 1, 'one clause evaluated')
  H.ok(d.results[5] and d.results[5].ok == false, 'the tag clause')
  H.eq(d.results[1], nil, 'shop clause never evaluated')
  H.ok(not drew(log, '^boss$') and not drew(log, '^cdt') and not drew(log, 'Joker4') and not drew(log, 'soul_'),
    'no stream past Tag1 drawn: '..table.concat(log, ' '))
end)

H.test('mode any stops at the first true clause; all needs every clause', function()
  local filter, predict, state = mods()
  local S = world{seed = 'ANYMODE'}
  local tags = predict.tags(state.copy(S), 1)
  local hit = {kind = 'tag', ante = 1, blind = 'Small', key = tags.small}
  local shop = {kind = 'shop_joker', ante = 1, key = 'j_joker'}
  local log, ok, d = streams(function() return filter.eval(state.copy(S), F({shop, hit}, {mode = 'any'})) end)
  H.eq(ok, true); H.eq(d.checked, 1)
  H.ok(not drew(log, '^cdt'), 'shop not walked')
  -- all: the tag holds, so the shop clause decides.
  local want = false
  local T = state.copy(S)
  for _ = 1, 2 do
    for _, c in ipairs(predict.shop(T, 1)) do if c.key == 'j_joker' then want = true end end
    predict.packs(T, 1, 2)
    predict.leave_shop(T)
  end
  local ok2, d2 = filter.eval(state.copy(S), F({shop, hit}))
  H.eq(ok2, want); H.eq(d2.checked, 2)
end)

-- A seed whose ante-1 Charm pack(s) hold the Soul, with a Charm-only tag pool.
local function charm_soul_seed()
  local _, predict, state = mods()
  for i = 1, 4000 do
    local S = world{seed = 'CHARM'..i, tags = {'tag_charm'}}
    local T = state.copy(S)
    predict.tags(T, 1)
    local a = predict.pack_contents(T, 'p_arcana_mega_1', 1)
    local b = predict.pack_contents(T, 'p_arcana_mega_1', 1)
    for _, set in ipairs{a, b} do
      for _, c in ipairs(set) do if c.key == 'c_soul' then return 'CHARM'..i, a, b end end
    end
  end
  error('no Charm Soul seed in 4000')
end

H.test('soul_in_pack from_tag: Charm packs are Mega Arcana, Small then Big, on ante-A streams', function()
  local filter, _, state = mods()
  local seed, a, b = charm_soul_seed()
  local S = world{seed = seed, tags = {'tag_charm'}}
  local f = F({{kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true}})
  local log, ok, d = streams(function() return filter.eval(state.copy(S), f) end)
  H.eq(ok, true, seed)
  local r = d.results[1]
  H.eq(#r.packs, 2, 'both blinds carry a Charm Tag')
  H.eq(r.packs[1].blind, 'Small'); H.eq(r.packs[2].blind, 'Big')
  H.eq(r.packs[1].pack, 'p_arcana_mega_1'); H.eq(r.packs[1].tag, 'tag_charm')
  for i = 1, 5 do H.eq(r.packs[1].cards[i], a[i].key, 'Small pack card '..i); H.eq(r.packs[2].cards[i], b[i].key, 'Big pack card '..i) end
  local first = r.packs[1].soul and 1 or 2
  H.eq(r.blind, first == 1 and 'Small' or 'Big', 'the blind to skip')
  H.eq(r.packs[first].cards[r.index], 'c_soul', 'index names the Soul')
  H.ok(drew(log, '^soul_Tarot1$') and drew(log, '^Tarotar11$'), 'ante-1 Arcana streams')
  H.ok(not drew(log, '^cdt') and not drew(log, 'shop_pack'), 'no shop drawn')
  -- A spectral clause does not match Charm packs.
  H.eq(filter.eval(state.copy(S), F({{kind = 'soul_in_pack', ante = 1, pack = 'spectral', from_tag = true}})), false)
end)

H.test('soul_in_pack from_tag: no pack-opening tag means false with no pack drawn; Ethereal is a Spectral pack', function()
  local filter, predict, state = mods()
  local S = world{seed = 'NOCHARM', tags = {'tag_juggle', 'tag_economy'}}
  local log, ok, d = streams(function()
    return filter.eval(state.copy(S), F({{kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true}}))
  end)
  H.eq(ok, false); H.eq(#d.results[1].packs, 0)
  H.ok(not drew(log, 'soul_') and not drew(log, 'Tarot'), 'no pack opened')
  -- Ethereal at ante 2 (its min_ante): the Spectral Pack, 2 cards, 'spe' on ante 2.
  local found = false
  for i = 1, 3000 do
    local E = world{seed = 'ETH'..i, tags = {'tag_ethereal'}}
    local T = state.copy(E)
    predict.tags(T, 2)
    local x = predict.pack_contents(T, 'p_spectral_normal_1', 2)
    local y = predict.pack_contents(T, 'p_spectral_normal_1', 2)
    local soul = false
    for _, c in ipairs{x[1], x[2], y[1], y[2]} do if c.key == 'c_soul' then soul = true end end
    local elog, got, ed = streams(function()
      return filter.eval(state.copy(E), F({{kind = 'soul_in_pack', ante = 2, pack = 'spectral', from_tag = true}}))
    end)
    H.eq(got, soul, 'ETH'..i)
    H.eq(ed.results[1].packs[1].pack, 'p_spectral_normal_1')
    H.eq(ed.results[1].packs[1].cards[2], x[2].key)
    H.ok(drew(elog, '^Spectralspe2$'), 'ante-2 spectral stream')
    if soul then found = true; break end
  end
  H.ok(found, 'an Ethereal Soul seed within 3000')
end)

H.test('shop_joker and pack clauses read the plan policy shops, with the Boss-shop ante offset', function()
  local filter, predict, state = mods()
  for i = 1, 15 do
    local S = world{seed = 'SHOP'..i}
    local p = predict.plan(state.copy(S), {antes = 2, shops_per_ante = 3, rerolls = 1, open_packs = false})
    H.eq(#p[1].shops, 2); H.eq(#p[2].shops, 3)
    -- Ante 2 shop 1 is the Boss-of-ante-1 shop: the first ante-2 stream position.
    local c = p[2].shops[3].rerolls[1].cards[2]
    local ok, d = filter.eval(state.copy(S), F({{kind = 'shop_joker', ante = 2, key = c.key, rerolls = 1}}))
    H.eq(ok, true, 'SHOP'..i)
    local r = d.results[1]
    local where = p[2].shops[r.shop]
    local row = r.reroll == 0 and where.cards or where.rerolls[r.reroll].cards
    H.eq(row[r.slot].key, c.key, 'details point at the card')
    -- The first match: nothing earlier in shop order.
    for s = 1, r.shop - 1 do
      for _, x in ipairs(p[2].shops[s].cards) do H.ok(x.key ~= c.key, 'earlier shop') end
      for _, x in ipairs(p[2].shops[s].rerolls[1].cards) do H.ok(x.key ~= c.key, 'earlier reroll') end
    end
    -- Rerolls share the ante's stream with the next shop's row, so rerolls = 0
    -- is the plan with no rerolls, not the entering rows above.
    local p0 = predict.plan(state.copy(S), {antes = 2, shops_per_ante = 3, rerolls = 0, open_packs = false})
    local seen0 = false
    for _, sh in ipairs(p0[2].shops) do for _, x in ipairs(sh.cards) do if x.key == c.key then seen0 = true end end end
    H.eq(filter.eval(state.copy(S), F({{kind = 'shop_joker', ante = 2, key = c.key}})), seen0, 'rerolls = 0')
    -- Pack keys: ante 2's 6 packs; ante 1 shop 1 slot 1 is the forced Buffoon.
    local pk = p[2].shops[2].packs[2].key
    local okp, dp = filter.eval(state.copy(S), F({{kind = 'pack', ante = 2, key_prefix = pk}}))
    H.eq(okp, true)
    H.eq(p[2].shops[dp.results[1].shop].packs[dp.results[1].slot].key:sub(1, #pk), pk)
    local _, d1 = filter.eval(state.copy(S), F({{kind = 'pack', ante = 1, key_prefix = 'p_buffoon'}}))
    H.eq(d1.results[1].shop, 1); H.eq(d1.results[1].slot, 1); H.eq(d1.results[1].pack, 'p_buffoon_normal_1')
  end
end)

H.test('soul_in_pack in shops opens every pack of the ante in plan order', function()
  local filter, predict, state = mods()
  local hits = 0
  for i = 1, 400 do
    local S = world{seed = 'SPACK'..i}
    local p = predict.plan(state.copy(S), {antes = 2, shops_per_ante = 3, rerolls = 0, open_packs = true})
    local want
    for _, rec in ipairs{p[2]} do
      for s, sh in ipairs(rec.shops) do
        for j, pk in ipairs(sh.packs) do
          if not want and pk.kind == 'Arcana' then
            for k, c in ipairs(rec.pack_contents[pk.index]) do
              if c.key == 'c_soul' then want = {shop = s, slot = j, index = k} end
            end
          end
        end
      end
    end
    local ok, d = filter.eval(state.copy(S), F({{kind = 'soul_in_pack', ante = 2, pack = 'arcana'}}))
    H.eq(ok, want ~= nil, 'SPACK'..i)
    if want then
      hits = hits + 1
      H.eq(d.results[1].shop, want.shop); H.eq(d.results[1].slot, want.slot); H.eq(d.results[1].index, want.index)
    end
  end
  H.ok(hits > 0, 'at least one shop Soul in 400 seeds')
end)

-- The chained playthrough of ante a by hand (filter.lua header: Chained antes):
-- (a > 1) the Boss's shop, then per blind its tag pack at the skip or its shop.
local function chained_ref(predict, T, a)
  local TAGP = {tag_charm = 'p_arcana_mega_1', tag_ethereal = 'p_spectral_normal_1'}
  local tags = predict.tags(T, a)
  local shops, packs = {}, {}
  local function shop(after)
    predict.shop(T, a)
    local ps = predict.packs(T, a, 2)
    local contents = {}
    for j, p in ipairs(ps) do contents[j] = predict.pack_contents(T, p.key, a) end
    predict.leave_shop(T)
    shops[#shops + 1] = {packs = ps, contents = contents, after = after}
  end
  -- The run's forced first Buffoon pack is spent in the first shop walked.
  if a > 1 then predict.packs(T, 1, 1); shop('Boss') end
  for _, blind in ipairs{'Small', 'Big'} do
    local key = blind == 'Small' and tags.small or tags.big
    if TAGP[key] then
      local cards = predict.pack_contents(T, TAGP[key], a)
      local keys = {}
      for i, c in ipairs(cards) do keys[i] = c.key end
      packs[#packs + 1] = {blind = blind, pack = TAGP[key], cards = keys}
    else
      shop(blind)
    end
  end
  return shops, packs
end

H.test('chained ante: Charm blinds skipped, their packs opened in play order with the shops', function()
  local filter, predict, state = mods()
  local mixed, both = 0, 0
  for i = 1, 60 do
    local S = world{seed = 'CHAIN'..i, tags = {'tag_charm', 'tag_juggle'}}
    for _, a in ipairs{1, 2} do
      local shopc = {kind = 'soul_in_pack', ante = a, pack = 'arcana'}
      local tagc = {kind = 'soul_in_pack', ante = a, pack = 'arcana', from_tag = true}
      local shops, packs = chained_ref(predict, state.copy(S), a)
      local want_tag, want_shop = false, nil
      for _, p in ipairs(packs) do for _, k in ipairs(p.cards) do if k == 'c_soul' then want_tag = true end end end
      for si, sh in ipairs(shops) do
        for j, p in ipairs(sh.packs) do
          if not want_shop and p.kind == 'Arcana' then
            for ci, c in ipairs(sh.contents[j]) do
              if c.key == 'c_soul' and not want_shop then want_shop = {shop = si, slot = j, index = ci, after = sh.after} end
            end
          end
        end
      end
      local _, d = filter.eval(state.copy(S), F({tagc, shopc}, {mode = 'any', antes = 2}))
      -- 'any' evaluates the tag clause first; check both through 'all' orderings too.
      local _, dA = filter.eval(state.copy(S), F({shopc, tagc}))
      H.eq(dA.results[2].ok, want_tag, 'CHAIN'..i..' ante '..a..' tag Soul')
      H.eq(#dA.results[2].packs, #packs, 'tag packs opened')
      for k, p in ipairs(packs) do
        H.eq(dA.results[2].packs[k].blind, p.blind)
        deep_eq(dA.results[2].packs[k].cards, p.cards, 'CHAIN'..i..' tag pack '..k)
      end
      if want_tag then
        H.eq(dA.results[1].ok, want_shop ~= nil, 'CHAIN'..i..' ante '..a..' shop Soul after the skips')
        if want_shop then
          for _, k in ipairs{'shop', 'slot', 'index', 'after'} do H.eq(dA.results[1][k], want_shop[k], k) end
        end
      end
      H.ok(d.results[1] ~= nil, 'tag clause ran')
      if #packs == 1 then mixed = mixed + 1 elseif #packs == 2 then both = both + 1 end
    end
  end
  H.ok(mixed > 0 and both > 0, 'saw one-skip and two-skip antes: '..mixed..', '..both)
end)

H.test('chained ante 1 with both blinds Charm: no ante-1 shop is left', function()
  local filter, _, state = mods()
  local S = world{seed = 'CHAINBOTH', tags = {'tag_charm'}}
  local _, d = filter.eval(state.copy(S), F({{kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
    {kind = 'pack', ante = 1, key_prefix = 'p_'}}, {mode = 'any'}))
  H.eq(#d.results[1].packs, 2)
  if not d.results[1].ok then H.eq(d.results[2].ok, false, 'no shop, so no pack') end
end)

H.test('chained ante 1 with both blinds skipped: the forced first Buffoon lands in ante 2\'s Boss shop', function()
  local filter, predict, state = mods()
  local checked = 0
  for i = 1, 40 do
    local S = world{seed = 'FORCEDBUF'..i, tags = {'tag_charm'}}
    local f = F({{kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
      {kind = 'pack', ante = 1, key_prefix = 'p_'},
      {kind = 'pack', ante = 2, key_prefix = 'p_buffoon_normal'}}, {mode = 'any'})
    local _, d = filter.eval(state.copy(S), f)
    if not d.results[1].ok then
      -- By hand: ante 1 has no shop (both Charm blinds skipped), so the run's
      -- first shop is ante 2's, after the Boss, and it holds the forced Buffoon.
      local T = state.copy(S)
      predict.ante_walk(T, 1, {skip = {Small = true, Big = true}, open = false, cards = false})
      local w2 = predict.ante_walk(T, 2, {open = false, cards = false})
      H.eq(w2.shops[1].after, 'Boss')
      H.ok(w2.shops[1].packs[1].forced, 'FORCEDBUF'..i..': the hand chain puts the forced Buffoon in ante 2')
      H.eq(d.results[2].ok, false, 'no ante-1 shop')
      H.eq(d.results[3].ok, true, 'FORCEDBUF'..i..': the forced Buffoon in ante 2\'s Boss shop')
      H.eq(d.results[3].shop, 1); H.eq(d.results[3].slot, 1)
      checked = checked + 1
    end
  end
  H.ok(checked >= 20, 'seeds without an ante-1 Soul: '..checked)
end)

H.test('tag packs and shop packs at different antes stay separate branches', function()
  local filter, _, state = mods()
  for i = 1, 20 do
    local S = world{seed = 'BRANCH'..i, tags = {'tag_charm'}}
    local shop = {kind = 'soul_in_pack', ante = 2, pack = 'arcana'}
    local tagp = {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true}
    local okS, dS = filter.eval(state.copy(S), F({shop}))
    local okT, dT = filter.eval(state.copy(S), F({tagp}))
    local _, dA = filter.eval(state.copy(S), F({tagp, shop}))
    H.eq(dA.results[1].ok, okT)
    deep_eq(dA.results[1].packs, dT.results[1].packs, 'tag packs')
    if okT then
      H.eq(dA.results[2].ok, okS, 'shop result unchanged by the tag packs')
      if okS then H.eq(dA.results[2].slot, dS.results[1].slot) end
    end
  end
end)

H.test('legendaries run on a copy when later clauses read S', function()
  local filter, predict, state = mods()
  local S = world{seed = 'LEGCOPY', tags = {'tag_charm'}}
  local _, ref = filter.eval(state.copy(S), F({{kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true}}))
  local T = state.copy(S)
  local _, d = filter.eval(T, F({{kind = 'legendary', index = 1}, {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true}}))
  H.eq(T.game.pseudorandom.Joker4, nil, 'Joker4 untouched in S')
  deep_eq(d.results[2].packs, ref.results[1].packs, 'pack contents as without the legendary clause')
  H.ok(predict.legendaries(state.copy(S), 1)[1].key == d.results[1].key)
end)

H.test('eval raises on an invalid filter; the live G.GAME is untouched', function()
  local filter = mods()
  local S = world()
  H.ok(not pcall(filter.eval, S, F({})), 'invalid filter raises')
  H.ok(not pcall(filter.eval, {}, F({{kind = 'tag', ante = 1, key = 'tag_charm'}})), 'not a sim state')
  local T = world{seed = 'LIVE1', tags = {'tag_charm'}}
  local live, before = G.GAME, STR_PACK(G.GAME)
  filter.eval(T, F(EVERY_KIND, {antes = 2}))
  H.ok(G.GAME == live and STR_PACK(G.GAME) == before, 'live G.GAME untouched')
  H.eq(BHCore.sim_depth or 0, 0, 'sim_depth back to 0')
end)

-- The filter's walk is predict.ante_walk (T-321): its details, rebuilt from a
-- hand ante_walk call on a copy of the same state.
local function walk_expect(walk)
  local packs, tag_hit, shop_hit = {}, nil, nil
  for i, p in ipairs(walk.tag_packs) do
    local keys, soul = {}, nil
    for k, c in ipairs(p.cards) do
      keys[k] = c.key
      if c.key == 'c_soul' and not soul then soul = k end
    end
    packs[i] = {blind = p.blind, tag = p.tag, pack = p.pack, kind = 'arcana', cards = keys, soul = soul}
    if soul and not tag_hit then tag_hit = {blind = p.blind, tag = p.tag, pack = p.pack, index = soul} end
  end
  for s, sh in ipairs(walk.shops) do
    for j, p in ipairs(sh.packs) do
      if not shop_hit and p.kind == 'Arcana' then
        for ci, c in ipairs(sh.contents[j] or {}) do
          if c.key == 'c_soul' and not shop_hit then
            shop_hit = {shop = s, slot = j, pack = p.key, index = ci, after = sh.after}
          end
        end
      end
    end
  end
  local t = {ok = tag_hit ~= nil, packs = packs}
  for k, v in pairs(tag_hit or {}) do t[k] = v end
  local sh = {ok = shop_hit ~= nil}
  for k, v in pairs(shop_hit or {}) do sh[k] = v end
  return t, sh
end

H.test('filter results equal a hand predict.ante_walk, chained and non-chained', function()
  local filter, predict, state = mods()
  local hits, i = {chained = 0, separate = 0}, 0
  -- Every seed is compared; the loop runs until both policies have hit (a
  -- Soul's index / after / blind is then checked too), 30 seeds at least.
  while i < 30 or (hits.chained == 0 or hits.separate == 0) and i < 2000 do
    i = i + 1
    local S = world{seed = 'WALK'..i, tags = {'tag_charm', 'tag_juggle'}}
    -- Chained ante 2: the Charm blinds skipped, their packs between the shops.
    local T = state.copy(S)
    local tags = predict.tags(T, 2)
    predict.packs(T, 1, 1)
    local w = predict.ante_walk(T, 2, {tags = tags, skip = {Small = predict.TAG_PACKS[tags.small] ~= nil,
      Big = predict.TAG_PACKS[tags.big] ~= nil}})
    local want_tag, want_shop = walk_expect(w)
    local _, d = filter.eval(state.copy(S), F({{kind = 'soul_in_pack', ante = 2, pack = 'arcana', from_tag = true},
      {kind = 'soul_in_pack', ante = 2, pack = 'arcana'}}, {mode = 'any'}))
    deep_eq(d.results[1], want_tag, 'WALK'..i..' chained tag')
    if not want_tag.ok then deep_eq(d.results[2], want_shop, 'WALK'..i..' chained shop') end
    if want_tag.ok or want_shop.ok then hits.chained = hits.chained + 1 end
    -- Non-chained: the ante-2 tag packs on their own branch (both blinds
    -- skipped), the ante-1 shops unskipped on S.
    local A = state.copy(S)
    local wt = predict.ante_walk(A, 2, {skip = {Small = true, Big = true}, cards = false, open = false})
    local B = state.copy(S)
    local ws = predict.ante_walk(B, 1, {})
    local tag_ref = walk_expect(wt)
    local _, shop_ref = walk_expect(ws)
    local _, e = filter.eval(state.copy(S), F({{kind = 'soul_in_pack', ante = 2, pack = 'arcana', from_tag = true},
      {kind = 'soul_in_pack', ante = 1, pack = 'arcana'}}, {mode = 'any'}))
    deep_eq(e.results[1], tag_ref, 'WALK'..i..' separate tag')
    if not tag_ref.ok then deep_eq(e.results[2], shop_ref, 'WALK'..i..' separate shop') end
    if tag_ref.ok or shop_ref.ok then hits.separate = hits.separate + 1 end
  end
  H.ok(hits.chained > 0 and hits.separate > 0, 'saw hits: '..hits.chained..' chained, '..hits.separate..' separate')
end)

------------------------------------------------------------------------------
-- Editions (T-310): an optional edition on shop_joker and legendary clauses.

local EDITIONS = {'foil', 'holo', 'polychrome', 'negative', 'any'}

H.test('validate accepts every edition on shop_joker and legendary; rejects unknown names', function()
  world()
  local filter = mods()
  for _, e in ipairs(EDITIONS) do
    H.eq(filter.validate(F({{kind = 'shop_joker', ante = 1, key = 'j_joker', edition = e}})), true, 'shop_joker '..e)
    H.eq(filter.validate(F({{kind = 'legendary', index = 1, key = 'j_caino', edition = e}})), true, 'legendary '..e)
    H.eq(filter.validate(F({{kind = 'legendary', index = 2, edition = e}})), true, 'legendary edition alone '..e)
  end
  local bad = {
    {{kind = 'shop_joker', ante = 1, key = 'j_joker', edition = 'shiny'}, 'unknown edition'},
    {{kind = 'shop_joker', ante = 1, key = 'j_joker', edition = 'Foil'}, 'unknown edition'},
    {{kind = 'shop_joker', ante = 1, key = 'j_joker', edition = 1}, 'unknown edition'},
    {{kind = 'legendary', index = 1, edition = 'e_foil'}, 'unknown edition'},
    {{kind = 'shop_joker', ante = 1, edition = 'foil'}, 'unknown card'},
    {{kind = 'tag', ante = 1, key = 'tag_charm', edition = 'foil'}, 'unknown field'},
    {{kind = 'pack', ante = 1, key_prefix = 'p_', edition = 'foil'}, 'unknown field'},
  }
  for _, b in ipairs(bad) do
    local ok, err = filter.validate(F({{kind = 'tag', ante = 1, key = 'tag_charm'}, b[1]}))
    H.eq(ok, nil, b[2])
    H.ok(err:find('clause 2', 1, true) and err:find(b[2], 1, true), 'err: '..tostring(err))
  end
end)

H.test('serialize / deserialize round-trip the edition field', function()
  world()
  local filter = mods()
  local f = F({{kind = 'shop_joker', ante = 2, key = 'j_blueprint', rerolls = 3, edition = 'negative'},
    {kind = 'legendary', index = 1, edition = 'any'}, {kind = 'legendary', index = 2, key = 'j_perkeo', edition = 'polychrome'}})
  local s = assert(filter.serialize(f))
  local g = assert(filter.deserialize(s))
  deep_eq(g, f)
  H.eq(g.clauses[1].edition, 'negative'); H.eq(g.clauses[2].edition, 'any')
  H.eq(filter.deserialize(s:gsub("'negative'", "'shiny'"):gsub('"negative"', '"shiny"')), nil, 'unknown edition rejected on load')
end)

-- The first (shop, reroll, slot) of an ante walk whose card has key and matches
-- edition, by hand (header: <edition>).
local function edition_scan(walk, key, edition)
  for s, sh in ipairs(walk.shops) do
    local rows = {sh.cards}
    for r, row in ipairs(sh.rerolls) do rows[r + 1] = row.cards end
    for r, row in ipairs(rows) do
      for slot, c in ipairs(row) do
        local ed = edition == nil or (edition == 'any' and c.edition ~= nil) or c.edition == edition
        if c.key == key and ed then return {shop = s, reroll = r - 1, slot = slot} end
      end
    end
  end
end

H.test('shop_joker edition: every edition value against a hand predict.ante_walk', function()
  local filter, predict, state = mods()
  local R = 5
  local seen, i = {}, 0
  local function all_seen()
    for _, e in ipairs(EDITIONS) do if not seen[e] then return false end end
    return true
  end
  -- Seeds until each value has matched a predicted card, 1500 at most.
  while not all_seen() and i < 1500 do
    i = i + 1
    local S = world{seed = 'EDSHOP'..i}
    local walk = predict.ante_walk(state.copy(S), 1, {rerolls = R})
    local keys = {}
    for _, sh in ipairs(walk.shops) do
      local rows = {sh.cards}
      for _, row in ipairs(sh.rerolls) do rows[#rows + 1] = row.cards end
      for _, row in ipairs(rows) do
        for _, c in ipairs(row) do if c.edition then keys[c.key] = true end end
      end
    end
    for key in pairs(keys) do
      for _, e in ipairs(EDITIONS) do
        local want = edition_scan(walk, key, e)
        local ok, d = filter.eval(state.copy(S), F({{kind = 'shop_joker', ante = 1, key = key, rerolls = R, edition = e}}))
        H.eq(ok, want ~= nil, 'EDSHOP'..i..' '..key..' '..e)
        if want then
          seen[e] = true
          for _, k in ipairs{'shop', 'reroll', 'slot'} do H.eq(d.results[1][k], want[k], 'EDSHOP'..i..' '..e..' '..k) end
        end
      end
      -- No edition: the first card with that key, base or not.
      local want = edition_scan(walk, key, nil)
      local _, d = filter.eval(state.copy(S), F({{kind = 'shop_joker', ante = 1, key = key, rerolls = R}}))
      for _, k in ipairs{'shop', 'reroll', 'slot'} do H.eq(d.results[1][k], want[k], 'EDSHOP'..i..' no edition '..k) end
    end
  end
  for _, e in ipairs(EDITIONS) do H.ok(seen[e], 'saw a '..e..' shop joker within '..i..' seeds') end
end)

H.test('legendary edition: edition alone, with a key, any, and a base legendary', function()
  local filter, predict, state = mods()
  local ed, base
  for i = 1, 3000 do
    local S = world{seed = 'LEGED'..i}
    local want = predict.legendaries(state.copy(S), 1)[1]
    if want.edition and not ed then ed = {S = S, want = want} end
    if not want.edition and not base then base = {S = S, want = want} end
    if ed and base then break end
  end
  H.ok(ed and base, 'an edition legendary and a base one within 3000 seeds')
  local S, want = ed.S, ed.want
  local ok, d = filter.eval(state.copy(S), F({{kind = 'legendary', index = 1, edition = want.edition}}))
  H.ok(ok, 'edition alone: the Soul makes a '..want.edition..' legendary')
  H.eq(d.results[1].key, want.key); H.eq(d.results[1].edition, want.edition)
  H.ok(filter.eval(state.copy(S), F({{kind = 'legendary', index = 1, edition = 'any'}})), 'any')
  H.ok(filter.eval(state.copy(S), F({{kind = 'legendary', index = 1, key = want.key, edition = want.edition}})), 'key + edition')
  local other = want.edition == 'foil' and 'holo' or 'foil'
  H.eq(filter.eval(state.copy(S), F({{kind = 'legendary', index = 1, edition = other}})), false, 'wrong edition')
  local okey = want.key == 'j_caino' and 'j_yorick' or 'j_caino'
  H.eq(filter.eval(state.copy(S), F({{kind = 'legendary', index = 1, key = okey, edition = want.edition}})), false, 'wrong key')
  -- A base legendary: any edition fails, no edition holds.
  H.eq(filter.eval(state.copy(base.S), F({{kind = 'legendary', index = 1, edition = 'any'}})), false, 'base is not any')
  H.ok(filter.eval(state.copy(base.S), F({{kind = 'legendary', index = 1, key = base.want.key}})), 'base, no edition')
end)

------------------------------------------------------------------------------
-- Jokers by ante N (T-311): {kind = 'joker', ante, key, rerolls, from, edition}.

H.test('validate: joker clause fields, from values, defaults; legendaries and non-jokers refused', function()
  world()
  local filter = mods()
  H.eq(filter.validate(F({{kind = 'joker', ante = 3, key = 'j_blueprint'}})), true, 'defaults')
  for _, from in ipairs{'shop', 'buffoon', 'both'} do
    H.eq(filter.validate(F({{kind = 'joker', ante = 2, key = 'j_joker', rerolls = 20, from = from, edition = 'foil'}})),
      true, from)
  end
  local bad = {
    {{kind = 'joker', ante = 1, key = 'j_joker', from = 'pack'}, 'from must be shop, buffoon or both'},
    {{kind = 'joker', ante = 1, key = 'j_caino'}, 'is a legendary'},
    {{kind = 'joker', ante = 1, key = 'c_fool'}, 'unknown joker'},
    {{kind = 'joker', ante = 1, key = 'j_nope'}, 'unknown joker'},
    {{kind = 'joker', ante = 1}, 'unknown joker'},
    {{kind = 'joker', ante = 1, key = 'j_joker', rerolls = 21}, 'rerolls must be'},
    {{kind = 'joker', ante = 1, key = 'j_joker', rerolls = 1.5}, 'rerolls must be'},
    {{kind = 'joker', ante = 1, key = 'j_joker', edition = 'shiny'}, 'unknown edition'},
    {{kind = 'joker', ante = 1, key = 'j_joker', slot = 1}, 'unknown field'},
    {{kind = 'joker', key = 'j_joker'}, 'ante must be'},
  }
  for _, b in ipairs(bad) do
    local ok, err = filter.validate(F({{kind = 'tag', ante = 1, key = 'tag_charm'}, b[1]}))
    H.eq(ok, nil, b[2])
    H.ok(err:find('clause 2 (joker)', 1, true) and err:find(b[2], 1, true), 'err: '..tostring(err))
  end
  local f = F({{kind = 'joker', ante = 4, key = 'j_ceremonial', rerolls = 2, from = 'buffoon', edition = 'any'},
    {kind = 'shop_joker', ante = 2, key = 'j_joker'}})
  local g = assert(filter.deserialize(assert(filter.serialize(f))))
  deep_eq(g, f)
  H.eq(g.antes, nil); H.eq(filter.validate(g), true)
end)

-- The joker clause by hand: walk antes 1..n in order (n = the clause ante),
-- each with the merged policy {rerolls = R, open = opens}, and take the first
-- match in play order: shop, row (entering, rerolls), then Buffoon packs.
local function joker_ref(predict, T, c, R, opens)
  local from = c.from or 'both'
  local found
  for a = 1, c.ante do
    local w = predict.ante_walk(T, a, {rerolls = R, open = opens})
    for s, sh in ipairs(w.shops) do
      if found then break end
      if from ~= 'buffoon' then
        local rows = {sh.cards}
        for r = 1, c.rerolls or 0 do rows[r + 1] = sh.rerolls[r].cards end
        for r, row in ipairs(rows) do
          for slot, x in ipairs(row) do
            if not found and x.key == c.key and (c.edition == nil or x.edition == c.edition
              or (c.edition == 'any' and x.edition ~= nil)) then
              found = {ok = true, ante = a, shop = s, after = sh.after, reroll = r - 1, index = slot}
            end
          end
        end
      end
      if from ~= 'shop' and not found then
        for j, p in ipairs(sh.packs) do
          if p.kind == 'Buffoon' then
            for k, x in ipairs(sh.contents[j]) do
              if not found and x.key == c.key and (c.edition == nil or x.edition == c.edition
                or (c.edition == 'any' and x.edition ~= nil)) then
                found = {ok = true, ante = a, shop = s, after = sh.after, pack_slot = j, pack = p.key, index = k}
              end
            end
          end
        end
      end
    end
    if found then return found, w end
  end
  return {ok = false}
end

H.test('joker clause: shop, buffoon and both against a hand ante_walk over antes 1..N', function()
  local filter, predict, state = mods()
  local keys = {'j_joker', 'j_greedy_joker', 'j_lusty_joker', 'j_ceremonial', 'j_blueprint'}
  local seen = {shop_reroll = 0, buffoon_late = 0, miss = 0, first_ante = 0}
  for i = 1, 40 do
    local S = world{seed = 'JOKER'..i}
    for _, from in ipairs{'shop', 'buffoon', 'both'} do
      for _, key in ipairs(keys) do
        local c = {kind = 'joker', ante = 2, key = key, rerolls = 2, from = from}
        local want = joker_ref(predict, state.copy(S), c, 2, from ~= 'shop')
        local ok, d = filter.eval(state.copy(S), F({c}))
        H.eq(ok, want.ok, 'JOKER'..i..' '..from..' '..key)
        deep_eq(d.results[1], want, 'JOKER'..i..' '..from..' '..key)
        if want.ok and want.reroll and want.reroll > 0 then seen.shop_reroll = seen.shop_reroll + 1 end
        if want.ok and want.pack_slot and want.ante == 2 then seen.buffoon_late = seen.buffoon_late + 1 end
        if want.ok and want.ante == 1 then seen.first_ante = seen.first_ante + 1 end
        if not want.ok then seen.miss = seen.miss + 1 end
      end
    end
  end
  for k, v in pairs(seen) do H.ok(v > 0, 'saw '..k..': '..v) end
end)

H.test('joker clause: the forced first Buffoon counts; edition narrows; both = the earlier of shop and buffoon', function()
  local filter, predict, state = mods()
  local forced, ed = 0, 0
  for i = 1, 60 do
    local S = world{seed = 'JFORCE'..i}
    local w = predict.ante_walk(state.copy(S), 1, {})
    local first = w.shops[1].packs[1]
    H.eq(first.forced, true, 'ante 1 shop 1 slot 1 is the forced Buffoon')
    local x = w.shops[1].contents[1][1]
    local _, d = filter.eval(state.copy(S), F({{kind = 'joker', ante = 1, key = x.key, from = 'buffoon'}}))
    local r = d.results[1]
    H.eq(r.ok, true)
    if r.pack_slot == 1 and r.shop == 1 then
      forced = forced + 1
      H.eq(r.pack, 'p_buffoon_normal_1'); H.eq(r.after, 'Small'); H.eq(r.reroll, nil)
    end
    -- An edition the card lacks turns a match into the next one or a miss.
    local other = x.edition == 'foil' and 'holo' or 'foil'
    local c = {kind = 'joker', ante = 1, key = x.key, from = 'buffoon', edition = other}
    local _, de = filter.eval(state.copy(S), F({c}))
    deep_eq(de.results[1], (joker_ref(predict, state.copy(S), c, 0, true)), 'JFORCE'..i..' edition')
    if x.edition then ed = ed + 1 end
    -- both: the shop hit when the row shows it no later than the pack.
    local cb = {kind = 'joker', ante = 1, key = x.key}
    local _, ds = filter.eval(state.copy(S), F({{kind = 'joker', ante = 1, key = x.key, from = 'shop'}}))
    local _, db = filter.eval(state.copy(S), F({cb}))
    local s = ds.results[1]
    if s.ok and s.shop <= r.shop then deep_eq(db.results[1], s, 'JFORCE'..i..' both = shop') else deep_eq(db.results[1], r, 'JFORCE'..i..' both = buffoon') end
  end
  H.ok(forced > 0, 'a forced-Buffoon hit: '..forced)
end)

H.test('joker clause merges with a shop_joker at the same ante: one walk, R and open shared', function()
  local filter, predict, state = mods()
  local both_hit = 0
  for i = 1, 60 do
    local S = world{seed = 'JMERGE'..i}
    local w = predict.ante_walk(state.copy(S), 1, {rerolls = 3, open = true})
    -- Row targets from the merged walk: the entering row of ante-2 shop 1 via a hand walk.
    local T = state.copy(S)
    predict.ante_walk(T, 1, {rerolls = 3, open = true})
    local w2 = predict.ante_walk(T, 2, {rerolls = 3, open = true})
    local sj = {kind = 'shop_joker', ante = 2, key = w2.shops[2].cards[1].key}
    -- A joker from the ante-1 half of the walk (a later ante's may hit too).
    local jkey = 'j_blueprint'
    for _, row in ipairs{w.shops[2].rerolls[2].cards, w.shops[1].rerolls[3].cards, w.shops[2].cards} do
      for _, x in ipairs(row) do if x.set == 'Joker' then jkey = x.key end end
    end
    local jk = {kind = 'joker', ante = 2, key = jkey, rerolls = 3}
    local streams_seen = 0
    local log, ok, d = streams(function() return filter.eval(state.copy(S), F({sj, jk})) end)
    for _, k in ipairs(log) do if k == 'shop_pack2' then streams_seen = streams_seen + 1 end end
    H.eq(streams_seen, 6, 'ante 2 packs drawn once: 3 shops x 2')
    H.eq(ok, true, 'JMERGE'..i)
    -- shop_joker reads the entering rows of the R = 3 walk (header: rerolls
    -- move the next shop's row), the first one holding its key.
    local want_sj
    for s, sh in ipairs(w2.shops) do
      for slot, x in ipairs(sh.cards) do
        if not want_sj and x.key == sj.key then want_sj = {ok = true, shop = s, reroll = 0, slot = slot} end
      end
    end
    deep_eq(d.results[1], want_sj, 'JMERGE'..i..' shop_joker')
    deep_eq(d.results[2], (joker_ref(predict, state.copy(S), jk, 3, true)), 'JMERGE'..i..' joker')
    -- The same shop_joker alone keeps its old (R = 0, no packs) result.
    local _, alone = filter.eval(state.copy(S), F({sj}))
    local T0 = state.copy(S)
    predict.packs(T0, 1, 1)
    local w0 = predict.ante_walk(T0, 2, {open = false})
    local want0 = {ok = false}
    for s, sh in ipairs(w0.shops) do
      for slot, x in ipairs(sh.cards) do
        if not want0.ok and x.key == sj.key then want0 = {ok = true, shop = s, reroll = 0, slot = slot} end
      end
    end
    deep_eq(alone.results[1], want0, 'JMERGE'..i..' shop_joker alone')
    if d.results[2].ante == 1 then both_hit = both_hit + 1 end
  end
  H.ok(both_hit > 0, 'a joker hit in the ante-1 half of the shared walk: '..both_hit)
end)

H.test('joker clause is evaluated last; a chained ante skips its pack-tag blinds for it too', function()
  local filter, predict, state = mods()
  -- Last: a failing tag clause means no shop stream is drawn.
  local S = world{seed = 'JLAST'}
  local tags = predict.tags(state.copy(S), 1)
  local miss = tags.small == 'tag_juggle' and 'tag_economy' or 'tag_juggle'
  local log, ok, d = streams(function()
    return filter.eval(state.copy(S), F({{kind = 'joker', ante = 3, key = 'j_joker'},
      {kind = 'tag', ante = 1, blind = 'Small', key = miss}}))
  end)
  H.eq(ok, false); H.eq(d.checked, 1); H.eq(d.results[1], nil)
  H.ok(not drew(log, '^cdt') and not drew(log, '^shop_pack'), 'no shop drawn')
  -- Chained: from_tag at ante 1 makes ante 1 a chained ante for the joker walk.
  local chained = 0
  for i = 1, 40 do
    local C = world{seed = 'JCHAIN'..i, tags = {'tag_charm', 'tag_juggle'}}
    local jk = {kind = 'joker', ante = 1, key = 'j_joker', from = 'both'}
    local tg = {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true}
    local T = state.copy(C)
    local t = predict.tags(T, 1)
    local skip = {Small = predict.TAG_PACKS[t.small] ~= nil, Big = predict.TAG_PACKS[t.big] ~= nil}
    local w = predict.ante_walk(T, 1, {tags = t, skip = skip})
    local want = {ok = false}
    for s, sh in ipairs(w.shops) do
      for slot, x in ipairs(sh.cards) do
        if not want.ok and x.key == 'j_joker' then want = {ok = true, ante = 1, shop = s, after = sh.after, reroll = 0, index = slot} end
      end
      for j, p in ipairs(sh.packs) do
        if not want.ok and p.kind == 'Buffoon' then
          for k, x in ipairs(sh.contents[j]) do
            if not want.ok and x.key == 'j_joker' then
              want = {ok = true, ante = 1, shop = s, after = sh.after, pack_slot = j, pack = p.key, index = k}
            end
          end
        end
      end
    end
    local _, dc = filter.eval(state.copy(C), F({jk, tg}, {mode = 'any'}))
    if not dc.results[2].ok then
      deep_eq(dc.results[1], want, 'JCHAIN'..i)
      if (skip.Small or skip.Big) and want.ok then chained = chained + 1 end
    end
  end
  H.ok(chained > 0, 'a joker hit on a chained ante: '..chained)
end)

------------------------------------------------------------------------------
-- Any-of groups (T-312): {kind = 'group', clauses = {plain clause, ...}}.

local function grp(...) return {kind = 'group', clauses = {...}} end

H.test('group: validate accepts 2..MAX_GROUP plain members of every kind; antes counts the members', function()
  world()
  local filter = mods()
  H.eq(filter.MAX_GROUP, 6)
  local tag = {kind = 'tag', ante = 1, key = 'tag_charm'}
  local sj5 = {kind = 'shop_joker', ante = 5, key = 'j_joker'}
  H.eq(filter.validate(F({grp(tag, sj5)})), true, 'a group as the only clause')
  -- Every plain kind as a member, six at a time, beside a plain clause, both modes.
  local kinds = {}
  for i, c in ipairs(EVERY_KIND) do kinds[i] = c end
  kinds[#kinds + 1] = {kind = 'joker', ante = 2, key = 'j_blueprint', rerolls = 1, from = 'buffoon', edition = 'foil'}
  for s = 1, #kinds - 5 do
    local g = {kind = 'group', clauses = {}}
    for k = s, s + 5 do g.clauses[#g.clauses + 1] = kinds[k] end
    for _, mode in ipairs{'all', 'any'} do
      H.eq(filter.validate(F({tag, g}, {mode = mode, antes = 3})), true, 'members '..s..'..'..(s + 5)..' '..mode)
    end
  end
  -- antes defaults to the highest ante, members included, and bounds them.
  H.eq(filter.validate(F({tag, grp(tag, sj5)})), true, 'antes from a member')
  local ok, err = filter.validate(F({tag, grp(tag, sj5)}, {antes = 4}))
  H.eq(ok, nil)
  H.ok(err:find('clause 2, member 2 (shop_joker): ante must be an integer 1..4', 1, true), err)
  -- plain_clauses: members in their group's place, written order.
  local a, b = {kind = 'boss', ante = 1, key = 'bl_hook'}, {kind = 'voucher', ante = 1, key = 'v_hone'}
  local p = filter.plain_clauses(F({tag, grp(a, b), sj5}))
  H.eq(#p, 4)
  H.ok(p[1] == tag and p[2] == a and p[3] == b and p[4] == sj5, 'plain clauses in order')
end)

H.test('group: validate rejects nesting, empty, singleton and oversize groups, and bad members by path', function()
  world()
  local filter = mods()
  local tag = {kind = 'tag', ante = 1, key = 'tag_charm'}
  local big = {kind = 'tag', ante = 1, blind = 'Big', key = 'tag_juggle'}
  local seven = {kind = 'group', clauses = {}}
  for i = 1, 7 do seven.clauses[i] = tag end
  local bad = {
    {grp(tag, grp(tag, big)), 'clause 2, member 2: a group cannot hold a group'},
    {grp(grp(tag, big), tag), 'clause 2, member 1: a group cannot hold a group'},
    {{kind = 'group', clauses = {}}, 'clause 2 (group): needs 2..6 members, has 0'},
    {grp(tag), 'clause 2 (group): needs 2..6 members, has 1'},
    {seven, 'clause 2 (group): needs 2..6 members, has 7'},
    {{kind = 'group'}, 'clause 2 (group): clauses must be a list'},
    {{kind = 'group', clauses = 'x'}, 'clause 2 (group): clauses must be a list'},
    {{kind = 'group', clauses = {tag, big, [4] = tag}}, 'clause 2 (group): clauses must be a list'},
    {{kind = 'group', clauses = {tag, big}, ante = 1}, 'clause 2 (group): unknown field ante'},
    {grp(tag, big, {kind = 'tag', ante = 1, key = 'tag_missing'}), 'clause 2, member 3 (tag): unknown tag tag_missing'},
    {grp(tag, 'x'), 'clause 2, member 2: not a table'},
    {grp(tag, {kind = 'nope', ante = 1}), 'clause 2, member 2: unknown kind nope'},
    {grp(tag, {kind = 'joker', ante = 1, key = 'j_caino'}), 'clause 2, member 2 (joker): j_caino is a legendary'},
    {grp(tag, {kind = 'shop_joker', ante = 1, key = 'j_joker', rerolls = 21}), 'clause 2, member 2 (shop_joker): rerolls must be'},
    {grp(tag, {kind = 'tag', ante = 1, key = 'tag_charm', extra = 1}), 'clause 2, member 2 (tag): unknown field extra'},
  }
  for _, b in ipairs(bad) do
    local ok, err = filter.validate(F({tag, b[1]}))
    H.eq(ok, nil, b[2])
    H.ok(type(err) == 'string' and err:find(b[2], 1, true), 'err: '..tostring(err))
  end
  -- A group is refused inside a group even when it is the first clause.
  local ok, err = filter.validate(F({grp(grp(tag, big), big)}))
  H.eq(ok, nil); H.ok(err:find('clause 1, member 1: a group cannot hold a group', 1, true), tostring(err))
end)

H.test('group: serialize / deserialize round-trip; a nested group is refused on load', function()
  world()
  local filter = mods()
  local f = F({{kind = 'boss', ante = 2, key = 'bl_wall'},
    grp({kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
      {kind = 'joker', ante = 3, key = 'j_blueprint', rerolls = 2, from = 'shop', edition = 'foil'},
      {kind = 'legendary', index = 1})}, {mode = 'all', stake = 2})
  local s = assert(filter.serialize(f))
  local g = assert(filter.deserialize(s))
  deep_eq(g, f)
  H.eq(g.clauses[2].kind, 'group'); H.eq(#g.clauses[2].clauses, 3)
  H.eq(filter.validate(g), true)
  local tag = {kind = 'tag', ante = 1, key = 'tag_charm'}
  local nested = F({grp(tag, grp(tag, tag))})
  local n, err = filter.serialize(nested)
  H.eq(n, nil); H.ok(err:find('member 2', 1, true), tostring(err))
  local l, lerr = filter.deserialize(STR_PACK(nested))
  H.eq(l, nil); H.ok(lerr:find('member 2', 1, true), tostring(lerr))
end)

-- A group's details against its members evaluated alone (the same state):
-- it holds iff some member holds alone; hit is the first member in `order`
-- (the evaluation order) that holds alone; every member up to it reads what it
-- reads alone; none after it is evaluated.
local function check_group(filter, state, S, g, order, where)
  local ok, d = filter.eval(state.copy(S), F({g}))
  local r = d.results[1]
  local any, hit = false, nil
  for _, m in ipairs(order) do
    local alone_ok, alone = filter.eval(state.copy(S), F({g.clauses[m]}))
    any = any or alone_ok
    if hit then
      H.eq(r.results[m], nil, where..': member '..m..' after the hit')
    else
      deep_eq(r.results[m], alone.results[1], where..' member '..m)
      if alone_ok then hit = m end
    end
  end
  H.eq(ok, any, where)
  H.eq(r.ok, ok, where..' ok'); H.eq(r.hit, hit, where..' hit')
  H.eq(d.checked, 1)
  return hit
end

H.test('group: eval equals any of its members evaluated alone (tag + shop_joker + soul_in_pack, 200 seeds)', function()
  local filter, _, state = mods()
  -- Members written most expensive first. The Soul member: from a Charm tag
  -- pack in one group, from the ante-1 shops in the other.
  local G1 = grp({kind = 'shop_joker', ante = 2, key = 'j_blueprint', rerolls = 2},
    {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
    {kind = 'tag', ante = 1, blind = 'Big', key = 'tag_juggle'})
  local G2 = grp({kind = 'soul_in_pack', ante = 1, pack = 'arcana'},
    {kind = 'tag', ante = 2, blind = 'Small', key = 'tag_economy'},
    {kind = 'shop_joker', ante = 2, key = 'j_ceremonial', rerolls = 1})
  local seen = {{}, {}}
  for i = 1, 200 do
    local S = world{seed = 'GROUP'..i, tags = {'tag_charm', 'tag_juggle', 'tag_economy'}}
    local h1 = check_group(filter, state, S, G1, {3, 2, 1}, 'GROUP'..i..' G1')
    local h2 = check_group(filter, state, S, G2, {2, 1, 3}, 'GROUP'..i..' G2')
    seen[1][h1 or 0], seen[2][h2 or 0] = true, true
  end
  for gi = 1, 2 do
    for m = 0, 3 do H.ok(seen[gi][m], 'G'..gi..': saw '..(m == 0 and 'a miss' or 'member '..m..' as the hit')) end
  end
end)

H.test('group: members run cheapest first and stop at the first hit; the group sorts as its cheapest member', function()
  local filter, predict, state = mods()
  local S = world{seed = 'GORDER'}
  local tags, v1 = predict.tags(state.copy(S), 1), predict.voucher(state.copy(S), 1)
  local legend = predict.legendaries(state.copy(S), 1)[1].key
  local miss = (tags.small == 'tag_juggle') and 'tag_economy' or 'tag_juggle'
  local vmiss = v1 == 'v_hone' and 'v_grabber' or 'v_hone'
  local lmiss = legend == 'j_caino' and 'j_yorick' or 'j_caino'
  -- MAX_GROUP members, written most expensive first. The from_tag member
  -- never holds (no Ethereal Tag before ante 2).
  local function six(tag, voucher, leg)
    return grp({kind = 'joker', ante = 2, key = 'j_joker'},
      {kind = 'shop_joker', ante = 1, key = 'j_joker', rerolls = 1},
      {kind = 'soul_in_pack', ante = 1, pack = 'spectral', from_tag = true},
      {kind = 'legendary', index = 1, key = leg},
      {kind = 'voucher', ante = 1, key = voucher},
      {kind = 'tag', ante = 1, blind = 'Small', key = tag})
  end
  local function members(r)
    local n = 0
    for _ in pairs(r.results) do n = n + 1 end
    return n
  end
  local function first(log, pat)
    for i, k in ipairs(log) do if k:find(pat) then return i end end
  end
  -- The tag holds: nothing past 'Tag1' is drawn.
  local log, ok, d = streams(function() return filter.eval(state.copy(S), F({six(tags.small, vmiss, lmiss)})) end)
  H.eq(ok, true); H.eq(d.results[1].hit, 6); H.eq(members(d.results[1]), 1)
  H.ok(drew(log, '^Tag1$') and not drew(log, '^Voucher') and not drew(log, 'Joker4') and not drew(log, '^cdt')
    and not drew(log, 'shop_pack'), 'only the tag drawn: '..table.concat(log, ' '))
  -- The tag misses, the voucher holds.
  log, ok, d = streams(function() return filter.eval(state.copy(S), F({six(miss, v1, lmiss)})) end)
  H.eq(ok, true); H.eq(d.results[1].hit, 5); H.eq(members(d.results[1]), 2)
  H.eq(d.results[1].results[6].ok, false)
  H.ok(first(log, '^Tag1$') < first(log, '^Voucher1$'), 'tag before voucher')
  H.ok(not drew(log, 'Joker4') and not drew(log, '^cdt'), 'nothing past the voucher: '..table.concat(log, ' '))
  -- Then the legendary, drawn on a copy of S since later members read S.
  local T = state.copy(S)
  log, ok, d = streams(function() return filter.eval(T, F({six(miss, vmiss, legend)})) end)
  H.eq(ok, true); H.eq(d.results[1].hit, 4); H.eq(members(d.results[1]), 3)
  H.eq(T.game.pseudorandom.Joker4, nil, 'Joker4 untouched in S')
  H.ok(not drew(log, '^cdt') and not drew(log, 'shop_pack'), 'no shop walked')
  -- Nothing cheap holds: the shop members run last, in class order.
  log, ok, d = streams(function() return filter.eval(state.copy(S), F({six(miss, vmiss, lmiss)})) end)
  local r = d.results[1]
  for m = 3, 6 do H.eq(r.results[m].ok, false, 'member '..m..' evaluated and missed') end
  H.ok(r.results[2] or r.results[1], 'a shop member evaluated')
  H.ok(first(log, '^Tag1$') < first(log, '^Voucher1$') and first(log, '^Voucher1$') < first(log, 'Joker4')
    and first(log, 'Joker4') < first(log, '^cdt1$'), 'tag, voucher, legendary, then the shop: '..table.concat(log, ' '))
  if r.hit == 2 then H.eq(r.results[1], nil, 'the joker member after the shop_joker hit') end
  -- Top level: the group sorts as its tag, ahead of a boss clause written
  -- first; when every member misses, 'all' ends before the boss is drawn.
  local f = F({{kind = 'boss', ante = 1, key = 'bl_wall'},
    grp({kind = 'legendary', index = 1, key = lmiss}, {kind = 'tag', ante = 1, blind = 'Small', key = miss})})
  log, ok, d = streams(function() return filter.eval(state.copy(S), f) end)
  H.eq(ok, false); H.eq(d.checked, 1); H.eq(d.results[1], nil, 'boss never evaluated')
  H.eq(d.results[2].results[1].ok, false); H.eq(d.results[2].results[2].ok, false); H.eq(d.results[2].hit, nil)
  H.ok(first(log, '^Tag1$') < first(log, 'Joker4') and not drew(log, '^boss$'), table.concat(log, ' '))
  -- Ties by ante: a group whose cheapest member is an ante-2 tag runs after
  -- an ante-1 tag clause.
  local f2 = F({grp({kind = 'voucher', ante = 1, key = v1}, {kind = 'tag', ante = 2, key = 'tag_juggle'}),
    {kind = 'tag', ante = 1, blind = 'Small', key = miss}})
  local ok2, d2 = filter.eval(state.copy(S), f2)
  H.eq(ok2, false); H.eq(d2.checked, 1); H.eq(d2.results[1], nil, 'the group waits for the ante-1 tag')
end)

H.test('group: members share one walk; a one-group filter equals its members in mode any', function()
  local filter, _, state = mods()
  local g = grp({kind = 'joker', ante = 2, key = 'j_greedy_joker', rerolls = 1, from = 'buffoon'},
    {kind = 'soul_in_pack', ante = 1, pack = 'arcana'},
    {kind = 'shop_joker', ante = 1, key = 'j_blueprint', rerolls = 3})
  local seen = {}
  for i = 1, 60 do
    local S = world{seed = 'GMERGE'..i}
    local log, ok, d = streams(function() return filter.eval(state.copy(S), F({g})) end)
    local oka, da = filter.eval(state.copy(S), F(g.clauses, {mode = 'any'}))
    H.eq(ok, oka, 'GMERGE'..i)
    local r = d.results[1]
    for m = 1, 3 do
      if da.results[m] then deep_eq(r.results[m], da.results[m], 'GMERGE'..i..' member '..m)
      else H.eq(r.results[m], nil, 'GMERGE'..i..' member '..m..' not evaluated') end
      if da.results[m] and da.results[m].ok then H.eq(r.hit, m) end
    end
    -- Ante 1 is walked once for both shop members (R = 3, packs opened), ante
    -- 2 once more when the joker member runs.
    local p1, p2 = 0, 0
    for _, k in ipairs(log) do
      if k == 'shop_pack1' then p1 = p1 + 1 elseif k == 'shop_pack2' then p2 = p2 + 1 end
    end
    H.eq(p1, 3, 'GMERGE'..i..': ante 1 walked once (2 shops x 2 packs, the forced Buffoon undrawn)')
    local j = r.results[1]
    H.ok(p2 == ((j and (not j.ok or j.ante == 2)) and 6 or 0), 'GMERGE'..i..': ante 2 walked once, only for the joker: '..p2)
    seen[r.hit or 0] = true
  end
  H.ok(seen[3] and seen[0], 'saw a shop_joker hit and a miss')
  H.ok(seen[1], 'saw the joker member as the hit')
end)

H.test('group: a chained ante is walked for a from_tag member never reached; details.tag_packs records it', function()
  local filter, predict, state = mods()
  local f = F({grp({kind = 'tag', ante = 1, blind = 'Big', key = 'tag_juggle'},
      {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true}),
    {kind = 'pack', ante = 1, key_prefix = 'p_'}})
  local found = 0
  for i = 1, 200 do
    local S = world{seed = 'GCHAIN'..i, tags = {'tag_charm', 'tag_juggle'}}
    local t = predict.tags(state.copy(S), 1)
    if t.small == 'tag_charm' and t.big == 'tag_juggle' then
      local ok, d = filter.eval(state.copy(S), f)
      H.eq(ok, true, 'GCHAIN'..i)
      H.eq(d.results[1].hit, 1); H.eq(d.results[1].results[2], nil, 'the from_tag member not reached')
      -- By hand: the Charm Small skipped (its pack opened), the Big's shop the
      -- ante's only one, holding the run's forced Buffoon.
      local T = state.copy(S)
      local w = predict.ante_walk(T, 1, {tags = predict.tags(T, 1), skip = {Small = true, Big = false},
        cards = false, open = false})
      H.eq(#w.shops, 1); H.eq(w.shops[1].after, 'Big')
      H.eq(d.results[2].shop, 1); H.eq(d.results[2].slot, 1); H.eq(d.results[2].pack, w.shops[1].packs[1].key)
      local tp = d.tag_packs and d.tag_packs[1]
      H.ok(tp, 'GCHAIN'..i..': tag packs recorded for chained ante 1')
      H.eq(#tp, 1); H.eq(tp[1].blind, 'Small'); H.eq(tp[1].tag, 'tag_charm'); H.eq(tp[1].pack, 'p_arcana_mega_1')
      for k, c in ipairs(w.tag_packs[1].cards) do H.eq(tp[1].cards[k], c.key, 'card '..k) end
      found = found + 1
      if found >= 3 then break end
    end
  end
  H.ok(found > 0, 'a Charm Small / Juggle Big seed in 200')
  -- Separate branches record nothing: no ante here is chained.
  local _, d = filter.eval(world{seed = 'GCHAIN1', tags = {'tag_charm', 'tag_juggle'}},
    F({{kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true}, {kind = 'pack', ante = 2, key_prefix = 'p_'}}))
  H.eq(d.tag_packs, nil)
end)

H.test('group: odds.sample counts a group as one clause', function()
  local filter, _, state = mods()
  local odds = require('seedfinder.odds')
  local base = world()
  local function at(seed)
    local T = state.copy(base)
    T.game.pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)}
    return T
  end
  local function eval(f1, seed) return filter.eval(at(seed), f1) end
  local g = grp({kind = 'tag', ante = 1, blind = 'Small', key = 'tag_juggle'},
    {kind = 'shop_joker', ante = 1, key = 'j_greedy_joker'})
  local v = {kind = 'voucher', ante = 1, key = 'v_hone'}
  local f = F({g, v})
  local seeds = {}
  for i = 1, 60 do seeds[i] = 'GODDS'..i end
  local counts = odds.sample(f, seeds, eval)
  H.eq(#counts.clauses, 2, 'the group is one clause')
  local want = {0, 0}
  local full = 0
  for _, seed in ipairs(seeds) do
    if eval(F({g}), seed) then want[1] = want[1] + 1 end
    if eval(F({v}), seed) then want[2] = want[2] + 1 end
    if eval(f, seed) then full = full + 1 end
  end
  H.eq(counts.clauses[1], want[1]); H.eq(counts.clauses[2], want[2]); H.eq(counts.full, full)
  H.ok(want[1] > 0 and want[1] < #seeds, 'the group both holds and misses: '..want[1])
  local est = assert(odds.estimate(counts))
  H.ok(est.expected_seeds > 0)
end)

-- The Soul's edition reads 'edisou'..A. A group can walk shops, draw tag
-- packs on S, or end before a boss / voucher member is drawn, all ahead of a
-- legendary step; A is fixed by f (header: legendaries), so the step reads
-- what a plain clause in its place reads, whichever members ran. Editions are
-- made common (edition_rate 10) so a wrong ante shows.
H.test('group: a legendary edition reads the same ante whichever members ran or walked (300 seeds)', function()
  local filter, predict, state = mods()
  local function leg(S, ante)
    local T = state.copy(S)
    T.game.round_resets.ante = ante
    return predict.legendaries(T, 2)[1]
  end
  local function same(r, want, where)
    H.ok(r, where..': evaluated')
    H.eq(r.key, want.key, where..' key'); H.eq(r.edition, want.edition, where..' edition')
  end
  local function first(log, pat)
    for i, k in ipairs(log) do if k:find(pat) then return i end end
    return math.huge
  end
  local walk3 = {kind = 'pack', ante = 3, key_prefix = 'p_'}
  local moved, reached3, seen = 0, 0, {}
  for i = 1, 300 do
    local w = 'GLEG'..i
    local S = world{seed = w}
    S.game.edition_rate = 10
    local want1, want2 = leg(S, 1), leg(S, 2)
    if want1.edition ~= leg(S, 3).edition then moved = moved + 1 end
    local LE = {kind = 'legendary', index = 1, edition = want1.edition or 'foil'}
    local alone_ok = filter.eval(state.copy(S), F({LE}))
    local miss = predict.tags(state.copy(S), 1).small == 'tag_juggle' and 'tag_economy' or 'tag_juggle'
    local tag1 = {kind = 'tag', ante = 1, blind = 'Small', key = miss}
    -- (1) The group's tag misses and its pack member walks antes 1..3 before
    -- the top-level legendary: it reads as it does alone, drawn before the
    -- walk moved S.
    local log, ok, d = streams(function() return filter.eval(state.copy(S), F({grp(tag1, walk3), LE})) end)
    H.eq(d.results[1].hit, 2, w..' (1): the walk ran')
    H.ok(first(log, '^Joker4$') < first(log, '^shop_pack3$'), w..' (1) legendaries before the walk: '..table.concat(log, ' '))
    same(d.results[2], want1, w..' (1)')
    H.eq(ok, alone_ok, w..' (1) ok')
    -- (2) A legendary member of a second group, after that walk: the group
    -- holds iff a member holds alone, and reads as it does on its own.
    local G2 = grp(LE, {kind = 'pack', ante = 2, key_prefix = 'p_celestial'})
    ok, d = filter.eval(state.copy(S), F({grp(tag1, walk3), G2}))
    same(d.results[2].results[1], want1, w..' (2)')
    local g_ok, gd = filter.eval(state.copy(S), F({G2}))
    deep_eq(d.results[2], gd.results[1], w..' (2) details')
    H.eq(ok, g_ok, w..' (2) ok')
    H.eq(g_ok, alone_ok or filter.eval(state.copy(S), F({G2.clauses[2]})), w..' (2) any member alone')
    -- (3) No shop needs: the from_tag member's packs are drawn on S itself
    -- (ante 3) before the legendary ('any': reached when the group misses).
    log, ok, d = streams(function()
      return filter.eval(state.copy(S), F({grp(tag1, {kind = 'soul_in_pack', ante = 3, pack = 'arcana', from_tag = true}), LE},
        {mode = 'any'}))
    end)
    H.ok(first(log, '^Joker4$') < first(log, '^shop_pack3$'), w..' (3) legendaries before the tag packs: '..table.concat(log, ' '))
    if d.results[2] then
      same(d.results[2], want1, w..' (3)')
      reached3 = reached3 + 1
    end
    -- (4) The tag member at ante 3 ends the group before the boss member is
    -- drawn, or misses and the boss holds: A is the boss's ante (1) either way.
    local G4 = grp({kind = 'tag', ante = 3, key = 'tag_juggle'},
      {kind = 'boss', ante = 1, key = predict.boss(state.copy(S), 1)})
    ok, d = filter.eval(state.copy(S), F({G4, LE}))
    same(d.results[2], want1, w..' (4)')
    H.eq(ok, alone_ok, w..' (4) ok')
    seen[d.results[1].hit] = true
    -- (5) A above 1: a voucher member at ante 2 fixes A = 2 whether or not the
    -- walk runs, as a plain voucher clause in its place does.
    local vmiss = predict.voucher(state.copy(S), 2) == 'v_hone' and 'v_grabber' or 'v_hone'
    local V2 = {kind = 'voucher', ante = 2, key = vmiss}
    ok, d = filter.eval(state.copy(S), F({grp(V2, walk3), LE}))
    H.eq(d.results[1].hit, 2, w..' (5): the walk ran')
    same(d.results[2], want2, w..' (5)')
    local _, dp = filter.eval(state.copy(S), F({V2, LE}, {mode = 'any'}))
    same(dp.results[2], want2, w..' (5) plain')
  end
  H.ok(moved > 0, 'the ante moves the Soul edition on some seeds: '..moved)
  H.ok(reached3 > 0, '(3) reached')
  H.ok(seen[1] and seen[2], '(4) held by the tag and by the boss')
end)

H.test('group: odds.sample counts agree with full evals for a legendary edition after a group walk', function()
  local filter, _, state = mods()
  local odds = require('seedfinder.odds')
  local base = world()
  local function eval(f1, seed)
    local T = state.copy(base)
    T.game.pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)}
    T.game.edition_rate = 10
    return filter.eval(T, f1)
  end
  -- The group always holds (every ante-3 shop has packs), by its tag or by
  -- the walk: the full filter passes exactly when the legendary does.
  local f = F({grp({kind = 'tag', ante = 1, blind = 'Small', key = 'tag_juggle'}, {kind = 'pack', ante = 3, key_prefix = 'p_'}),
    {kind = 'legendary', index = 1, edition = 'any'}})
  local seeds = {}
  for i = 1, 120 do seeds[i] = 'GLODDS'..i end
  local counts = odds.sample(f, seeds, eval)
  H.eq(counts.clauses[1], #seeds, 'the group always holds')
  H.eq(counts.full, counts.clauses[2], 'full = the legendary alone')
  H.ok(counts.clauses[2] > 0 and counts.clauses[2] < #seeds, 'the legendary both holds and misses: '..counts.clauses[2])
end)
