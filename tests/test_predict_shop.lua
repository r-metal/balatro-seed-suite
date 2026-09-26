-- sim/predict.lua conditional streams: shop, reroll, packs, pack_contents,
-- leave_shop and plan, plus the legendary path now routed through sim.card.
-- Runs on vanilla's own RNG and pool primitives (misc_functions.lua and
-- common_events.lua loaded from build/game) over a small stub prototype set,
-- so what is tested is predict's wiring: which streams, in which order, what
-- is released when, and that the live G.GAME is never touched. Expected stream
-- sequences are read off the vanilla lines cited in predict.lua's header.
-- The golden reference against the real game is rig/scenarios/golden_shop.lua.
local H = ...

local function center(key, t)
  t.key = key
  t.config = t.config or {}
  return t
end

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
    center('j_caino', {name = 'Caino', set = 'Joker', rarity = 4, order = 6, unlocked = false, eternal_compat = true, perishable_compat = true}),
    center('j_yorick', {name = 'Yorick', set = 'Joker', rarity = 4, order = 7, eternal_compat = true, perishable_compat = true}),
    center('c_fool', {name = 'The Fool', set = 'Tarot', order = 1, consumeable = true}),
    center('c_magician', {name = 'The Magician', set = 'Tarot', order = 2, consumeable = true}),
    center('c_strength', {name = 'Strength', set = 'Tarot', order = 3, consumeable = true}),
    center('c_hermit', {name = 'The Hermit', set = 'Tarot', order = 4, consumeable = true}),
    center('c_empress', {name = 'The Empress', set = 'Tarot', order = 5, consumeable = true}),
    center('c_emperor', {name = 'The Emperor', set = 'Tarot', order = 6, consumeable = true}),
    center('c_pluto', {name = 'Pluto', set = 'Planet', order = 1, consumeable = true, config = {hand_type = 'High Card'}}),
    center('c_mercury', {name = 'Mercury', set = 'Planet', order = 2, consumeable = true, config = {hand_type = 'Pair'}}),
    center('c_venus', {name = 'Venus', set = 'Planet', order = 3, consumeable = true, config = {hand_type = 'Three of a Kind'}}),
    center('c_familiar', {name = 'Familiar', set = 'Spectral', order = 1, consumeable = true}),
    center('c_grim', {name = 'Grim', set = 'Spectral', order = 2, consumeable = true}),
    center('c_soul', {name = 'The Soul', set = 'Spectral', order = 17, consumeable = true, hidden = true}),
    center('c_black_hole', {name = 'Black Hole', set = 'Spectral', order = 18, consumeable = true, hidden = true}),
    center('c_base', {name = 'Default Base', set = 'Default', order = 1}),
    center('m_bonus', {name = 'Bonus', set = 'Enhanced', order = 2}),
    center('m_mult', {name = 'Mult', set = 'Enhanced', order = 3}),
    center('v_overstock_norm', {name = 'Overstock', set = 'Voucher', order = 1, unlocked = true}),
    center('v_grabber', {name = 'Grabber', set = 'Voucher', order = 2, unlocked = true}),
    center('v_hone', {name = 'Hone', set = 'Voucher', order = 3, unlocked = true}),
  }
  -- Boosters as vanilla has them (game.lua:665-694), a subset.
  local boosters = {
    center('p_arcana_normal_1', {order = 1, name = 'Arcana Pack', weight = 1, kind = 'Arcana', set = 'Booster', config = {extra = 3, choose = 1}}),
    center('p_arcana_mega_1', {order = 2, name = 'Mega Arcana Pack', weight = 0.25, kind = 'Arcana', set = 'Booster', config = {extra = 5, choose = 2}}),
    center('p_celestial_normal_1', {order = 3, name = 'Celestial Pack', weight = 1, kind = 'Celestial', set = 'Booster', config = {extra = 3, choose = 1}}),
    center('p_standard_normal_1', {order = 4, name = 'Standard Pack', weight = 1, kind = 'Standard', set = 'Booster', config = {extra = 3, choose = 1}}),
    center('p_spectral_normal_1', {order = 5, name = 'Spectral Pack', weight = 0.3, kind = 'Spectral', set = 'Booster', config = {extra = 2, choose = 1}}),
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
  local tags = {{key = 'tag_uncommon'}, {key = 'tag_rare'}, {key = 'tag_juggle'}, {key = 'tag_top_up', min_ante = 2}}
  G.P_TAGS = {}
  for _, t in ipairs(tags) do G.P_TAGS[t.key] = t end
  G.P_CENTER_POOLS = {Joker = pool('Joker'), Tarot = pool('Tarot'), Planet = pool('Planet'),
    Spectral = pool('Spectral'), Enhanced = pool('Enhanced'), Voucher = pool('Voucher'),
    Booster = pool('Booster'), Tag = tags}
  G.P_JOKER_RARITY_POOLS = {{}, {}, {}, {}}
  for _, c in ipairs(G.P_CENTER_POOLS.Joker) do table.insert(G.P_JOKER_RARITY_POOLS[c.rarity], c) end
  G.P_CARDS = {H_2 = {suit = 'Hearts', value = '2'}, S_A = {suit = 'Spades', value = 'Ace'},
    D_K = {suit = 'Diamonds', value = 'King'}}
  G.P_BLINDS = {
    bl_small = {key = 'bl_small'}, bl_big = {key = 'bl_big'},
    bl_hook = {key = 'bl_hook', boss = {min = 1, max = 10}},
    bl_club = {key = 'bl_club', boss = {min = 1, max = 10}},
    bl_wall = {key = 'bl_wall', boss = {min = 2, max = 10}},
  }
  G.handlist = {'Three of a Kind', 'Pair', 'High Card'}
  G.jokers = {cards = {}, config = {card_limit = 5}}
  G.consumeables = {cards = {}, config = {card_limit = 2}}
  G.playing_cards = {}
  G.GAME = {live = true, pseudorandom = {seed = 'LIVE'}, round_resets = {ante = 5}}
  local seed = o.seed or 'SHOPSEED'
  local game = {
    round_resets = {ante = 1}, win_ante = 8,
    pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)},
    used_jokers = {}, used_vouchers = o.vouchers or {}, banned_keys = {}, pool_flags = {},
    bosses_used = {bl_hook = 0, bl_club = 0, bl_wall = 0},
    hands = {['High Card'] = {played = 0, visible = true}, Pair = {played = 0, visible = true},
      ['Three of a Kind'] = {played = 0, visible = true}},
    modifiers = o.modifiers or {}, edition_rate = 1, shop = {joker_max = 2},
    joker_rate = 20, tarot_rate = 4, planet_rate = 4, playing_card_rate = 0, spectral_rate = 0,
  }
  return {game = game, all_unlocked = false}
end

local function mods()
  return require('bhcore.sim.predict'), require('bhcore.sim.state'), require('bhcore.sim.sandbox')
end

-- Records every stream key pseudoseed advances while fn runs.
local function streams(fn)
  local real = pseudoseed
  local log = {}
  pseudoseed = function(k, p) log[#log + 1] = k; return real(k, p) end
  local ok, a, b = pcall(fn)
  pseudoseed = real
  assert(ok, a)
  return log, a, b
end

local function seq(log) return table.concat(log, ' ') end
-- Drops pool resamples: stub pools hold UNAVAILABLE slots.
local function core(log)
  local out = {}
  for _, k in ipairs(log) do if not k:find('_resample%d+$') then out[#out + 1] = k end end
  return seq(out)
end

local function used(S)
  local n = {}
  for k, v in pairs(S.game.used_jokers) do if v then n[#n + 1] = k end end
  table.sort(n)
  return seq(n)
end

H.test('shop: joker_max cards, each a cdt roll then create_card with append sho', function()
  local S = world()
  local predict = mods()
  local log, cards = streams(function() return predict.shop(S, 1) end)
  H.eq(#cards, 2, 'joker_max cards')
  H.eq(log[1], 'cdt1', 'type roll first: '..seq(log))
  local cdt = 0
  for _, k in ipairs(log) do
    if k == 'cdt1' then cdt = cdt + 1 end
    H.ok(k == 'cdt1' or k:find('sho1', 1, true) or k:find('sho$') or k == 'etperpoll1', 'unexpected stream '..k)
  end
  H.eq(cdt, 2, 'one cdt per slot')
  for _, c in ipairs(cards) do
    H.ok(G.P_CENTERS[c.key], 'key '..tostring(c.key))
    H.ok(S.game.used_jokers[c.key], 'shop card held in used_jokers: '..c.key)
    H.eq(type(c.stickers), 'table')
  end
  H.eq(#S.game.bh_shop, 2, 'shop row recorded in S')
  H.eq(#predict.shop(S, 1, 5), 5, 'explicit n')
end)

H.test('shop cards of one row are distinct (used_jokers), and reroll releases before refilling', function()
  local predict = mods()
  -- Only two jokers exist, in every rarity: a row takes both. If reroll kept the
  -- old row in used_jokers, every pool would be UNAVAILABLE and vanilla's
  -- empty-pool fallback would give j_joker twice.
  for i = 1, 30 do
    local S = world{seed = 'ROW'..i}
    S.game.tarot_rate, S.game.planet_rate = 0, 0
    local two = {G.P_CENTERS.j_joker, G.P_CENTERS.j_greedy_joker}
    G.P_JOKER_RARITY_POOLS = {two, two, two, {}}
    local row = predict.shop(S, 1)
    H.ok(row[1].key ~= row[2].key, 'row distinct')
    local log, rr = streams(function() return predict.reroll(S, 1) end)
    H.eq(#rr, 2)
    H.eq(log[1], 'cdt1', 'reroll continues cdt1')
    H.ok(rr[1].key ~= rr[2].key, 'reroll row distinct: '..rr[1].key..' '..rr[2].key)
    H.eq(used(S), 'j_greedy_joker j_joker', 'used_jokers holds the new row')
  end
end)

H.test('leave_shop and the next shop release the row', function()
  local S = world()
  local predict = mods()
  predict.shop(S, 1)
  H.ok(used(S) ~= '', 'row held')
  predict.leave_shop(S)
  H.eq(used(S), '', 'released on leave')
  H.eq(#S.game.bh_shop, 0)
  local a = predict.shop(S, 1)
  local b = predict.shop(S, 1) -- entering again without leaving: the old row goes first
  H.eq(#S.game.bh_shop, 2, 'only the second row recorded')
  H.ok(a and b)
end)

H.test('packs: the run\'s first pack is the forced Buffoon with no draw; then shop_pack..A', function()
  local S = world()
  local predict = mods()
  local log, p = streams(function() return predict.packs(S, 1) end)
  H.eq(#p, 2)
  H.eq(p[1].key, 'p_buffoon_normal_1'); H.eq(p[1].forced, true); H.eq(p[1].kind, 'Buffoon')
  H.eq(seq(log), 'shop_pack1', 'one draw, for the second pack only')
  H.eq(S.game.first_shop_buffoon, true)
  -- Pack 2 is vanilla get_pack on the same stream position.
  local T = world()
  local want
  do
    local live = G.GAME
    G.GAME = T.game
    T.game.first_shop_buffoon = true
    want = get_pack('shop_pack').key
    G.GAME = live
  end
  H.eq(p[2].key, want, 'pack 2 vs vanilla get_pack')
  H.eq(p[2].forced, nil)
  local log2, q = streams(function() return predict.packs(S, 2, 3) end)
  H.eq(seq(log2), 'shop_pack2 shop_pack2 shop_pack2')
  for _, x in ipairs(q) do H.ok(G.P_CENTERS[x.key].set == 'Booster' and x.size == G.P_CENTERS[x.key].config.extra, x.key) end
end)

H.test('pack_contents: the stream order of every pack kind', function()
  local predict = mods()
  local S = world()
  local log, c = streams(function() return predict.pack_contents(S, 'p_arcana_normal_1', 1) end)
  H.eq(#c, 3)
  H.eq(core(log), 'soul_Tarot1 Tarotar11 soul_Tarot1 Tarotar11 soul_Tarot1 Tarotar11')
  log = streams(function() return predict.pack_contents(S, 'p_celestial_normal_1', 2) end)
  H.eq(core(log), 'soul_Planet2 Planetpl12 soul_Planet2 Planetpl12 soul_Planet2 Planetpl12')
  log = streams(function() return predict.pack_contents(S, 'p_spectral_normal_1', 1) end)
  H.eq(core(log), 'soul_Spectral1 soul_Spectral1 Spectralspe1 soul_Spectral1 soul_Spectral1 Spectralspe1')
  log = streams(function() return predict.pack_contents(S, 'p_buffoon_normal_2', 1) end)
  local r1, r2 = log[2]:match('^Joker(%d)buf1$'), nil
  H.ok(r1, seq(log))
  r2 = log[6] and log[6]:match('^Joker(%d)buf1$')
  H.eq(core(log), 'rarity1buf Joker'..r1..'buf1 packetper1 edibuf1 rarity1buf Joker'..tostring(r2)..'buf1 packetper1 edibuf1')
  local std
  log, std = streams(function() return predict.pack_contents(S, 'p_standard_normal_1', 3) end)
  -- per card: stdset, [Enhancedsta], frontsta, standard_edition, stdseal, [stdsealtype]
  local s = core(log):gsub(' Enhancedsta3', ''):gsub(' stdsealtype3', '')
  H.eq(s, ('stdset3 frontsta3 standard_edition3 stdseal3 '):rep(3):sub(1, -2))
  for _, x in ipairs(std) do
    H.ok(G.P_CARDS[x.front], 'front '..tostring(x.front))
    H.ok(x.edition ~= 'negative', 'standard edition never negative')
  end
end)

H.test('pack_contents: Omen Globe and Telescope', function()
  local predict = mods()
  local S = world{vouchers = {v_omen_globe = true, v_telescope = true}}
  local log = streams(function() return predict.pack_contents(S, 'p_arcana_normal_1', 1) end)
  H.eq(log[1], 'omen_globe', 'Omen Globe draws before each Arcana card: '..seq(log))
  local n = 0
  for _, k in ipairs(log) do if k == 'omen_globe' then n = n + 1 end end
  H.eq(n, 3)
  -- Telescope with no hand played: no forced planet, a normal draw.
  local l1 = streams(function() return predict.pack_contents(S, 'p_celestial_normal_1', 1) end)
  H.eq(l1[1], 'soul_Planet1')
  S.game.hands.Pair.played = 3
  S.game.hands['High Card'].played = 1
  local l2, c = streams(function() return predict.pack_contents(S, 'p_celestial_normal_1', 1) end)
  H.eq(c[1].key, 'c_mercury', 'most played hand\'s planet')
  H.eq(core(l2), 'soul_Planet1 Planetpl11 soul_Planet1 Planetpl11', 'card 1 forced: no soul roll, no pool draw')
end)

H.test('pack_contents exclude the shop row and release their own cards', function()
  local predict = mods()
  for i = 1, 25 do
    local S = world{seed = 'EXCL'..i}
    S.game.joker_rate, S.game.planet_rate = 0, 0 -- the row is Tarots
    local row = predict.shop(S, 1)
    local before = used(S)
    local c = predict.pack_contents(S, 'p_arcana_normal_1', 1)
    for _, x in ipairs(c) do
      for _, r in ipairs(row) do H.ok(x.key ~= r.key, 'pack repeats shop card '..r.key) end
    end
    H.eq(used(S), before, 'pack cards released, shop row kept')
  end
  local ok = pcall(predict.pack_contents, world(), 'j_joker', 1)
  H.ok(not ok, 'not a pack')
end)

H.test('legendaries go through sim.card.create (one twin of create_card)', function()
  local predict = mods()
  local card = require('bhcore.sim.card')
  local S = world()
  S.game.round_resets.ante = 2
  local real, calls = card.create, {}
  card.create = function(a) calls[#calls + 1] = a; return real(a) end
  local log, l = streams(function() return predict.legendaries(S, 2) end)
  card.create = real
  H.eq(#calls, 2)
  H.eq(calls[1].legendary, true); H.eq(calls[1].key_append, 'sou'); H.eq(calls[1].area, 'other'); H.eq(calls[1].type, 'Joker')
  H.eq(core(log), 'rarity2sou Joker4 edisou2 rarity2sou Joker4 edisou2')
  H.ok(l[1].key ~= l[2].key and G.P_CENTERS[l[1].key].rarity == 4, 'distinct legendaries')
  H.ok(l[1].edition == nil or type(l[1].edition) == 'string', 'edition as a name')
end)

H.test('plan: the game\'s call order, shop counts per ante, certainty', function()
  local predict = mods()
  local S = world()
  local log, p = streams(function() return predict.plan(S, {antes = 2, rerolls = 1}) end)
  H.eq(#p, 2)
  H.eq(#p[1].shops, 2, 'ante 1: shops after Small and Big only')
  H.eq(#p[2].shops, 3, 'ante 2: after Boss 1, Small 2, Big 2')
  -- ante 1 opens boss, Voucher1, Tag1 Tag1; ante 2 opens Voucher2, Tag2 Tag2, boss
  local head = {}
  for _, k in ipairs(log) do
    if k == 'boss' or k:find('^Voucher%d') or k:find('^Tag%d') then head[#head + 1] = k:gsub('_resample%d+$', '') end
  end
  H.eq(seq(head), 'boss Voucher1 Tag1 Tag1 Voucher2 Tag2 Tag2 boss')
  -- The soul prediction runs on a copy: S's Joker4 is untouched.
  H.eq(S.game.pseudorandom.Joker4, nil, 'Joker4 not advanced in S')
  H.ok(p[1].soul.key and G.P_CENTERS[p[1].soul.key].rarity == 4, 'soul')
  -- Within a shop: row, packs, reroll, then pack contents; the shop is left.
  local first_pack = nil
  for i, k in ipairs(log) do if k == 'shop_pack1' then first_pack = i; break end end
  H.ok(first_pack, 'shop_pack1 drawn')
  for i = first_pack + 1, #log do
    if log[i] == 'cdt1' then break end
    H.ok(log[i] ~= 'soul_Tarot1', 'pack opened before the reroll')
  end
  for a, rec in ipairs(p) do
    H.eq(rec.certainty.tags, 'stable'); H.eq(rec.tags.certainty, 'stable')
    H.eq(rec.certainty.boss, 'stable'); H.eq(rec.certainty.voucher, 'conditional')
    H.eq(rec.certainty.shops, 'conditional'); H.eq(rec.certainty.pack_contents, 'conditional')
    H.eq(rec.certainty.soul, 'stable')
    for s, shop in ipairs(rec.shops) do
      H.eq(#shop.cards, 2); H.eq(#shop.packs, 2); H.eq(#shop.rerolls, 1); H.eq(#shop.rerolls[1].cards, 2)
      for j, pk in ipairs(shop.packs) do
        H.eq(pk.index, (s - 1) * 2 + j)
        H.eq(#rec.pack_contents[pk.index], pk.size, 'contents of pack '..pk.index..' ante '..a)
      end
    end
  end
  H.eq(p[1].shops[1].packs[1].forced, true, 'first pack of the run is the forced Buffoon')
  H.eq(used(S), '', 'every shop left')
end)

H.test('plan equals the helpers called by hand in the documented order', function()
  local predict, state = mods()
  local S = world{seed = 'PLANEQ'}
  local T = state.copy(S)
  local p = predict.plan(S, {antes = 2, shops_per_ante = 2, rerolls = 2})
  local boss = predict.boss(T, 1)
  local voucher = predict.voucher(T, 1)
  local tags = predict.tags(T, 1)
  H.eq(p[1].boss, boss); H.eq(p[1].voucher, voucher); H.eq(p[1].tags.small, tags.small); H.eq(p[1].tags.big, tags.big)
  local function same(a, b, what)
    H.eq(#a, #b, what..' count')
    for i = 1, #a do
      H.eq(a[i].key, b[i].key, what..' '..i); H.eq(a[i].edition, b[i].edition, what..' edition '..i)
    end
  end
  for a = 1, 2 do
    if a > 1 then
      H.eq(p[a].voucher, predict.voucher(T, a)); predict.tags(T, a); H.eq(p[a].boss, predict.boss(T, a))
    end
    for s = 1, 2 do
      local shop = p[a].shops[s]
      same(shop.cards, predict.shop(T, a), 'ante '..a..' shop '..s)
      local packs = predict.packs(T, a)
      for r = 1, 2 do same(shop.rerolls[r].cards, predict.reroll(T, a), 'reroll '..r) end
      for j, pk in ipairs(packs) do
        H.eq(shop.packs[j].key, pk.key)
        same(p[a].pack_contents[shop.packs[j].index], predict.pack_contents(T, pk.key, a), 'pack '..j)
      end
      predict.leave_shop(T)
    end
  end
end)

H.test('plan: shops_per_ante and open_packs; later antes do not depend on earlier shop counts', function()
  local predict = mods()
  local A = predict.plan(world{seed = 'PERANTE'}, {antes = 3, shops_per_ante = 3})
  local B = predict.plan(world{seed = 'PERANTE'}, {antes = 3, shops_per_ante = 1, open_packs = false})
  H.eq(#B[2].shops, 1); H.eq(next(B[2].pack_contents), nil, 'no packs opened')
  for a = 1, 3 do
    for i = 1, 2 do H.eq(B[a].shops[1].cards[i].key, A[a].shops[1].cards[i].key, 'ante '..a..' shop 1 card '..i) end
    H.eq(B[a].shops[1].packs[2].key, A[a].shops[1].packs[2].key, 'ante '..a..' pack 2')
    H.eq(B[a].boss, A[a].boss); H.eq(B[a].voucher, A[a].voucher)
  end
  H.ok(not pcall(predict.plan, world(), {shops_per_ante = 4}), 'shops_per_ante is 1..3')
  H.ok(not pcall(predict.plan, world(), {antes = 0}), 'antes >= 1')
end)

H.test('plan: a tutorial forcing ante 1 tags makes them conditional', function()
  local predict = mods()
  G.SETTINGS.tutorial_progress = {forced_tags = {'tag_handy', 'tag_garbage'}, forced_voucher = 'v_grabber'}
  local p = predict.plan(world(), {antes = 2, shops_per_ante = 1})
  G.SETTINGS.tutorial_progress = nil
  H.eq(p[1].certainty.tags, 'conditional'); H.eq(p[1].tags.certainty, 'conditional')
  H.eq(p[1].certainty.voucher, 'conditional')
  H.eq(p[2].certainty.tags, 'stable', 'only ante 1 is forced')
  local q = predict.plan(world(), {antes = 1, shops_per_ante = 1})
  H.eq(q[1].certainty.tags, 'stable', 'no tutorial: stable')
end)

H.test('the live G.GAME and areas are untouched, sim_depth back to 0, errors re-raised', function()
  local predict = mods()
  local T = world()
  T.game.first_shop_buffoon = true
  local bad = world()
  local S = world()
  local live, jokers = G.GAME, G.jokers
  local before = STR_PACK(G.GAME)
  predict.plan(S, {antes = 2, rerolls = 1})
  H.ok(G.GAME == live, 'G.GAME swapped back')
  H.eq(STR_PACK(G.GAME), before, 'live pack')
  H.ok(G.jokers == jokers, 'G.jokers restored')
  H.eq(BHCore.sim_depth, 0, 'sim_depth')
  H.ok(not pcall(predict.shop, {}, 1), 'not a sim state')
  H.ok(not pcall(predict.reroll, bad, 0), 'ante 0')
  H.ok(not pcall(predict.packs, bad, 1, -1), 'negative n')
  G.P_CENTER_POOLS.Booster = nil
  local ok = pcall(predict.packs, T, 1)
  H.ok(not ok, 'inner error re-raised')
  H.ok(G.GAME == live, 'G.GAME restored after error')
  H.eq(BHCore.sim_depth, 0, 'sim_depth after error')
end)
