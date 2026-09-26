-- sim/predict.lua ante_walk: one ante in play order under skip / reroll /
-- open choices, including the Charm and Ethereal tag packs. The walk must equal
-- predict's primitives called by hand in the order predict.lua's header
-- documents (Ante walk), for every skip combination. Runs on vanilla's own RNG
-- and pool primitives (misc_functions.lua and common_events.lua from
-- build/game) over the stub prototype set of test_predict_shop.lua plus the
-- two pack-giving tags (and, with world{megas = true}, the Meteor, Standard and
-- Buffoon tags behind policy.pack_tags, T-324a). The golden references against
-- the real game are rig/scenarios/golden_walk.lua and golden_tagpacks.lua.
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
    center('c_familiar', {name = 'Familiar', set = 'Spectral', order = 1, consumeable = true}),
    center('c_grim', {name = 'Grim', set = 'Spectral', order = 2, consumeable = true}),
    center('c_incantation', {name = 'Incantation', set = 'Spectral', order = 3, consumeable = true}),
    center('c_soul', {name = 'The Soul', set = 'Spectral', order = 17, consumeable = true, hidden = true}),
    center('c_black_hole', {name = 'Black Hole', set = 'Spectral', order = 18, consumeable = true, hidden = true}),
    center('c_base', {name = 'Default Base', set = 'Default', order = 1}),
    center('m_bonus', {name = 'Bonus', set = 'Enhanced', order = 2}),
  }
  -- Boosters as vanilla has them (game.lua:665-694), a subset.
  local boosters = {
    center('p_arcana_normal_1', {order = 1, name = 'Arcana Pack', weight = 1, kind = 'Arcana', set = 'Booster', config = {extra = 3, choose = 1}}),
    center('p_arcana_mega_1', {order = 2, name = 'Mega Arcana Pack', weight = 0.25, kind = 'Arcana', set = 'Booster', config = {extra = 5, choose = 2}}),
    center('p_celestial_normal_1', {order = 3, name = 'Celestial Pack', weight = 1, kind = 'Celestial', set = 'Booster', config = {extra = 3, choose = 1}}),
    center('p_spectral_normal_1', {order = 5, name = 'Spectral Pack', weight = 0.3, kind = 'Spectral', set = 'Booster', config = {extra = 2, choose = 1}}),
    center('p_buffoon_normal_1', {order = 6, name = 'Buffoon Pack', weight = 0.6, kind = 'Buffoon', set = 'Booster', config = {extra = 2, choose = 1}}),
    center('p_buffoon_normal_2', {order = 7, name = 'Buffoon Pack', weight = 0.6, kind = 'Buffoon', set = 'Booster', config = {extra = 2, choose = 1}}),
  }
  if o.megas then
    -- The packs the Meteor, Standard and Buffoon tags open (T-324a).
    boosters[#boosters + 1] = center('p_celestial_mega_1', {order = 8, name = 'Mega Celestial Pack', weight = 0.25, kind = 'Celestial', set = 'Booster', config = {extra = 5, choose = 2}})
    boosters[#boosters + 1] = center('p_standard_mega_1', {order = 9, name = 'Mega Standard Pack', weight = 0.25, kind = 'Standard', set = 'Booster', config = {extra = 5, choose = 2}})
    boosters[#boosters + 1] = center('p_buffoon_mega_1', {order = 10, name = 'Mega Buffoon Pack', weight = 0.15, kind = 'Buffoon', set = 'Booster', config = {extra = 4, choose = 2}})
  end
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
  local tags = {{key = 'tag_uncommon', order = 1}, {key = 'tag_charm', order = 2}, {key = 'tag_juggle', order = 3},
    {key = 'tag_ethereal', order = 4, min_ante = 2}}
  if o.megas then
    for i, k in ipairs{'tag_meteor', 'tag_standard', 'tag_buffoon'} do tags[#tags + 1] = {key = k, order = 4 + i} end
  end
  G.P_TAGS = {}
  for _, t in ipairs(tags) do G.P_TAGS[t.key] = t end
  G.P_CENTER_POOLS = {Joker = pool('Joker'), Tarot = pool('Tarot'), Planet = pool('Planet'),
    Spectral = pool('Spectral'), Enhanced = pool('Enhanced'), Voucher = {},
    Booster = pool('Booster'), Tag = tags}
  G.P_JOKER_RARITY_POOLS = {{}, {}, {}, {}}
  for _, c in ipairs(G.P_CENTER_POOLS.Joker) do table.insert(G.P_JOKER_RARITY_POOLS[c.rarity], c) end
  G.P_CARDS = {H_2 = {suit = 'Hearts', value = '2'}, S_A = {suit = 'Spades', value = 'Ace'}}
  G.P_BLINDS = {bl_small = {key = 'bl_small'}, bl_big = {key = 'bl_big'}, bl_hook = {key = 'bl_hook', boss = {min = 1, max = 10}}}
  G.handlist = {'Pair', 'High Card'}
  G.jokers = {cards = {}, config = {card_limit = 5}}
  G.consumeables = {cards = {}, config = {card_limit = 2}}
  G.playing_cards = {}
  G.GAME = {live = true, pseudorandom = {seed = 'LIVE'}, round_resets = {ante = 5}}
  local seed = o.seed or 'WALKSEED'
  local game = {
    round_resets = {ante = 1}, win_ante = 8,
    pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)},
    used_jokers = {}, used_vouchers = {}, banned_keys = {}, pool_flags = {},
    bosses_used = {bl_hook = 0},
    hands = {['High Card'] = {played = 0, visible = true}, Pair = {played = 0, visible = true}},
    modifiers = {}, edition_rate = 1, shop = {joker_max = 2},
    joker_rate = 20, tarot_rate = 4, planet_rate = 4, playing_card_rate = 0, spectral_rate = 2,
  }
  return {game = game, all_unlocked = true}
end

local function mods()
  return require('bhcore.sim.predict'), require('bhcore.sim.state')
end

local function streams(fn)
  local real = pseudoseed
  local log = {}
  pseudoseed = function(k, p) log[#log + 1] = k; return real(k, p) end
  local ok, a, b = pcall(fn)
  pseudoseed = real
  assert(ok, a)
  return log, a, b
end

local function fmt(cards)
  local out = {}
  for i, c in ipairs(cards or {}) do
    out[i] = c.key..(c.edition and '/'..c.edition or '')..(c.front and '@'..c.front or '')
      ..(c.stickers and c.stickers.eternal and '[E]' or '')
  end
  return table.concat(out, ' ')
end

local function used(S)
  local n = {}
  for k, v in pairs(S.game.used_jokers) do if v then n[#n + 1] = k end end
  table.sort(n)
  return table.concat(n, ' ')
end

-- The walk as the header spells it, with the primitives called by hand on T.
local function by_hand(predict, T, a, tags, skip, R, open, pack_of)
  pack_of = pack_of or predict.TAG_PACKS
  local out = {shops = {}, tag_packs = {}}
  local i = 0
  local function shop(after)
    local s = {after = after, cards = predict.shop(T, a), packs = predict.packs(T, a, 2), rerolls = {}, contents = {}}
    for r = 1, R do s.rerolls[r] = predict.reroll(T, a) end
    for j, p in ipairs(s.packs) do
      i = i + 1
      p.index = i
      if open then s.contents[j] = predict.pack_contents(T, p.key, a) end
    end
    predict.leave_shop(T)
    out.shops[#out.shops + 1] = s
  end
  if a > 1 then shop('Boss') end
  for _, blind in ipairs{'Small', 'Big'} do
    local tag = blind == 'Small' and tags.small or tags.big
    if not skip[blind] then shop(blind)
    elseif pack_of[tag] then
      out.tag_packs[#out.tag_packs + 1] = {blind = blind, tag = tag, pack = pack_of[tag],
        cards = predict.pack_contents(T, pack_of[tag], a)}
    end
  end
  return out
end

local function same_walk(w, h, what)
  H.eq(#w.shops, #h.shops, what..' shop count')
  for s, shop in ipairs(h.shops) do
    local ws = w.shops[s]
    local lbl = what..' shop '..s
    H.eq(ws.after, shop.after, lbl..' after')
    H.eq(fmt(ws.cards), fmt(shop.cards), lbl..' row')
    H.eq(#ws.rerolls, #shop.rerolls, lbl..' reroll count')
    for r = 1, #shop.rerolls do H.eq(fmt(ws.rerolls[r].cards), fmt(shop.rerolls[r]), lbl..' reroll '..r) end
    for j = 1, 2 do
      H.eq(ws.packs[j].key, shop.packs[j].key, lbl..' pack '..j)
      H.eq(ws.packs[j].index, shop.packs[j].index, lbl..' pack index '..j)
      H.eq(fmt(ws.contents[j]), fmt(shop.contents[j]), lbl..' pack '..j..' contents')
    end
  end
  H.eq(#w.tag_packs, #h.tag_packs, what..' tag pack count')
  for k, tp in ipairs(h.tag_packs) do
    local wt = w.tag_packs[k]
    H.eq(wt.blind, tp.blind, what..' tag pack blind'); H.eq(wt.tag, tp.tag); H.eq(wt.pack, tp.pack)
    H.eq(fmt(wt.cards), fmt(tp.cards), what..' tag pack '..k..' cards')
  end
end

local COMBOS = {
  {Small = false, Big = false}, {Small = true, Big = false},
  {Small = false, Big = true}, {Small = true, Big = true},
}
local function combo_name(c) return (c.Small and 'S' or '-')..(c.Big and 'B' or '-') end

H.test('ante_walk equals the primitives by hand, every skip combination, antes 1 and 2', function()
  local predict, state = mods()
  local n = 0
  for _, tags in ipairs{{small = 'tag_charm', big = 'tag_ethereal'}, {small = 'tag_juggle', big = 'tag_charm'},
      {small = 'tag_uncommon', big = 'tag_juggle'}} do
    for _, skip in ipairs(COMBOS) do
      for _, R in ipairs{0, 2} do
        local S = world{seed = 'WALK'..n}
        n = n + 1
        local T = state.copy(S)
        for a = 1, 2 do
          local what = combo_name(skip)..' '..tags.small..'/'..tags.big..' R'..R..' ante '..a
          local w = predict.ante_walk(S, a, {skip = skip, rerolls = R, open = true, tags = tags})
          same_walk(w, by_hand(predict, T, a, tags, skip, R, true), what)
          H.eq(w.tags.small, tags.small)
        end
        H.eq(used(S), '', 'every shop left, every pack closed')
      end
    end
  end
end)

H.test('ante_walk: tag packs open at the skip, between the shops, on ante-a streams', function()
  local predict = mods()
  local S = world{seed = 'ORDER'}
  S.game.first_shop_buffoon = true
  local log, w = streams(function()
    return predict.ante_walk(S, 2, {skip = {Small = true}, open = false, tags = {small = 'tag_charm', big = 'tag_juggle'}})
  end)
  H.eq(#w.shops, 2, 'Boss shop and Big shop')
  H.eq(w.shops[1].after, 'Boss'); H.eq(w.shops[2].after, 'Big')
  H.eq(#w.tag_packs, 1); H.eq(w.tag_packs[1].pack, 'p_arcana_mega_1'); H.eq(#w.tag_packs[1].cards, 5)
  -- Shop packs stay shut here, so every Tarotar12 draw is the Charm pack's:
  -- Boss shop row, its packs, the Charm pack, then the Big shop.
  local marks = {}
  for _, k in ipairs(log) do
    local m = (k == 'cdt2' and 'row') or (k == 'shop_pack2' and 'pack') or (k == 'Tarotar12' and 'tarot')
    if m and marks[#marks] ~= m then marks[#marks + 1] = m end
  end
  H.eq(table.concat(marks, ' '), 'row pack tarot row pack', 'Boss shop; Charm; then the Big shop')
  for _, k in ipairs(log) do H.ok(not k:find('^Tag'), 'tags given: none drawn ('..k..')') end
  -- Ethereal gives a Spectral Pack.
  local e = predict.ante_walk(world(), 2, {skip = {Big = true}, tags = {small = 'tag_juggle', big = 'tag_ethereal'}})
  H.eq(e.tag_packs[1].pack, 'p_spectral_normal_1'); H.eq(e.tag_packs[1].blind, 'Big'); H.eq(#e.tag_packs[1].cards, 2)
end)

H.test('ante_walk draws tags(S, a) once when the policy has none', function()
  local predict, state = mods()
  for i = 1, 8 do
    local S = world{seed = 'TAGS'..i}
    local T = state.copy(S)
    local log, w = streams(function() return predict.ante_walk(S, 2, {skip = {Small = true, Big = true}}) end)
    local t = predict.tags(T, 2)
    H.eq(w.tags.small, t.small); H.eq(w.tags.big, t.big)
    local n = 0
    for _, k in ipairs(log) do if k:find('^Tag2') and not k:find('_resample') then n = n + 1 end end
    H.eq(n, 2, 'Tag2 drawn twice: Small then Big')
    same_walk(w, by_hand(predict, T, 2, t, {Small = true, Big = true}, 0, true), 'drawn tags '..i)
  end
end)

H.test('ante_walk: a skipped blind without a pack tag has no shop and no pack', function()
  local predict = mods()
  local S = world()
  local log, w = streams(function()
    return predict.ante_walk(S, 1, {skip = {Small = true, Big = true}, tags = {small = 'tag_uncommon', big = 'tag_juggle'}})
  end)
  H.eq(#w.shops, 0); H.eq(#w.tag_packs, 0)
  H.eq(#log, 0, 'nothing drawn')
  H.eq(S.game.first_shop_buffoon, nil, 'the forced Buffoon is still to come')
end)

H.test('ante_walk: the forced Buffoon lands in the run\'s first shop, whichever that is', function()
  local predict = mods()
  -- No skips: plan's place, ante 1 shop 1 slot 1.
  local S = world()
  local w = predict.ante_walk(S, 1, {tags = {small = 'tag_juggle', big = 'tag_juggle'}})
  H.eq(w.shops[1].packs[1].forced, true); H.eq(w.shops[1].after, 'Small')
  H.eq(w.shops[2].packs[1].forced, nil)
  -- Both ante-1 blinds skipped: the shop after Boss 1 (ante 2 shop 1).
  local T = world()
  local w1 = predict.ante_walk(T, 1, {skip = {Small = true, Big = true}, tags = {small = 'tag_charm', big = 'tag_juggle'}})
  H.eq(#w1.shops, 0); H.eq(#w1.tag_packs, 1)
  local w2 = predict.ante_walk(T, 2, {tags = {small = 'tag_juggle', big = 'tag_juggle'}})
  H.eq(w2.shops[1].after, 'Boss'); H.eq(w2.shops[1].packs[1].forced, true)
  H.eq(w2.shops[1].packs[1].key, 'p_buffoon_normal_1')
end)

H.test('ante_walk equals plan when nothing is skipped', function()
  local predict = mods()
  local p = predict.plan(world{seed = 'PLANWALK'}, {antes = 3, rerolls = 1})
  local S = world{seed = 'PLANWALK'}
  for a = 1, 3 do
    local w = predict.ante_walk(S, a, {rerolls = 1, tags = p[a].tags})
    H.eq(#w.shops, #p[a].shops, 'ante '..a..' shops')
    for s, shop in ipairs(p[a].shops) do
      H.eq(fmt(w.shops[s].cards), fmt(shop.cards), 'ante '..a..' shop '..s..' row')
      H.eq(fmt(w.shops[s].rerolls[1].cards), fmt(shop.rerolls[1].cards), 'reroll')
      for j, pk in ipairs(shop.packs) do
        H.eq(w.shops[s].packs[j].key, pk.key)
        H.eq(w.shops[s].packs[j].index, pk.index)
        H.eq(fmt(w.shops[s].contents[j]), fmt(p[a].pack_contents[pk.index]), 'contents '..pk.index)
      end
    end
  end
end)

H.test('ante_walk: cards = false draws pack keys only, the same keys', function()
  local predict = mods()
  local A = predict.ante_walk(world{seed = 'KEYS'}, 2, {rerolls = 3, open = false, tags = {small = 'tag_juggle', big = 'tag_charm'},
    skip = {Big = true}})
  local log, B = streams(function()
    return predict.ante_walk(world{seed = 'KEYS'}, 2, {cards = false, open = false, tags = {small = 'tag_juggle', big = 'tag_charm'},
      skip = {Big = true}})
  end)
  for _, k in ipairs(log) do H.ok(k ~= 'cdt2' and not k:find('sho2$'), 'no shop row draw: '..k) end
  H.eq(#B.shops, 2)
  for s = 1, 2 do
    H.eq(B.shops[s].cards, nil)
    for j = 1, 2 do H.eq(B.shops[s].packs[j].key, A.shops[s].packs[j].key, 'shop '..s..' pack '..j) end
  end
  H.eq(fmt(B.tag_packs[1].cards) ~= '', true, 'the tag pack is still opened')
end)

H.test('ante_walk: bad input raises; the live G.GAME is untouched', function()
  local predict = mods()
  local W = world()
  local live = G.GAME
  local before = STR_PACK(G.GAME)
  predict.ante_walk(W, 2, {skip = {Small = true}, rerolls = 1})
  H.ok(G.GAME == live, 'G.GAME swapped back')
  H.eq(STR_PACK(G.GAME), before, 'live pack')
  H.eq(BHCore.sim_depth, 0, 'sim_depth')
  H.ok(not pcall(predict.ante_walk, {}, 1), 'not a sim state')
  H.ok(not pcall(predict.ante_walk, world(), 0), 'ante 0')
  H.ok(not pcall(predict.ante_walk, world(), 1, {rerolls = -1}), 'negative rerolls')
  H.ok(not pcall(predict.ante_walk, world(), 1, {cards = false}), 'open without cards')
  H.ok(not pcall(predict.ante_walk, world(), 1, {tags = {small = 'tag_charm'}}), 'half a tag pair')
end)

-- T-324a: the Meteor, Standard and Buffoon tags behind policy.pack_tags.
local function full(cards)
  local out = {}
  for i, c in ipairs(cards or {}) do
    out[i] = fmt{c}..'|'..tostring(c.set)..'|'..tostring(c.seal)
      ..'|'..(c.stickers.perishable and 'P' or '')..(c.stickers.rental and 'R' or '')
  end
  return table.concat(out, ' ')
end

H.test('ante_walk: pack_tags defaults to TAG_PACKS; TAG_PACKS is still Charm and Ethereal', function()
  local predict, state = mods()
  local n = 0
  for k, v in pairs(predict.TAG_PACKS) do n = n + 1; H.eq(predict.ALL_TAG_PACKS[k], v, k) end
  H.eq(n, 2, 'TAG_PACKS size')
  H.eq(predict.TAG_PACKS.tag_charm, 'p_arcana_mega_1'); H.eq(predict.TAG_PACKS.tag_ethereal, 'p_spectral_normal_1')
  for _, tags in ipairs{{small = 'tag_meteor', big = 'tag_standard'}, {small = 'tag_buffoon', big = 'tag_charm'}} do
    for _, skip in ipairs(COMBOS) do
      local S = world{seed = 'DEF'..combo_name(skip), megas = true}
      local T = state.copy(S)
      local log, w = streams(function() return predict.ante_walk(S, 2, {skip = skip, tags = tags}) end)
      local log2, w2 = streams(function() return predict.ante_walk(T, 2, {skip = skip, tags = tags, pack_tags = predict.TAG_PACKS}) end)
      same_walk(w, w2, 'default vs TAG_PACKS '..combo_name(skip))
      H.eq(table.concat(log, ' '), table.concat(log2, ' '), 'same draws')
      for _, tp in ipairs(w.tag_packs) do H.eq(tp.tag, 'tag_charm', 'only Charm opens by default') end
    end
  end
end)

H.test('ante_walk: each ALL_TAG_PACKS tag opens its pack at the skip, equal to pack_contents by hand', function()
  local predict, state = mods()
  H.eq(predict.ALL_TAG_PACKS.tag_meteor, 'p_celestial_mega_1')
  H.eq(predict.ALL_TAG_PACKS.tag_standard, 'p_standard_mega_1')
  H.eq(predict.ALL_TAG_PACKS.tag_buffoon, 'p_buffoon_mega_1')
  local sizes = {tag_meteor = 5, tag_standard = 5, tag_buffoon = 4}
  local n = 0
  for _, tags in ipairs{{small = 'tag_meteor', big = 'tag_standard'}, {small = 'tag_standard', big = 'tag_buffoon'},
      {small = 'tag_buffoon', big = 'tag_meteor'}} do
    for _, skip in ipairs(COMBOS) do
      local S = world{seed = 'ALL'..n, megas = true}
      n = n + 1
      local T = state.copy(S)
      for a = 1, 2 do
        local what = combo_name(skip)..' '..tags.small..'/'..tags.big..' ante '..a
        local w = predict.ante_walk(S, a, {skip = skip, tags = tags, pack_tags = predict.ALL_TAG_PACKS})
        local h = by_hand(predict, T, a, tags, skip, 0, true, predict.ALL_TAG_PACKS)
        same_walk(w, h, what)
        for k, tp in ipairs(h.tag_packs) do
          H.eq(#w.tag_packs[k].cards, sizes[tp.tag], what..' size')
          H.eq(full(w.tag_packs[k].cards), full(tp.cards), what..' '..tp.tag..' card for card')
        end
      end
      H.eq(used(S), '', 'every pack closed')
    end
  end
  -- The Standard pack is playing cards; the Buffoon pack is jokers.
  local w = predict.ante_walk(world{seed = 'KINDS', megas = true}, 1, {skip = {Small = true, Big = true},
    tags = {small = 'tag_standard', big = 'tag_buffoon'}, pack_tags = {tag_standard = true, tag_buffoon = true}})
  H.eq(#w.tag_packs, 2)
  for _, c in ipairs(w.tag_packs[1].cards) do H.ok(c.front and G.P_CARDS[c.front], 'standard front '..tostring(c.front)) end
  for _, c in ipairs(w.tag_packs[2].cards) do H.eq(c.set, 'Joker', 'buffoon card '..c.key) end
end)

H.test('ante_walk: a Buffoon Tag pack is not the forced first Buffoon; bad pack_tags raise', function()
  local predict = mods()
  local S = world{megas = true}
  local log = streams(function()
    return predict.ante_walk(S, 1, {skip = {Small = true, Big = true}, tags = {small = 'tag_buffoon', big = 'tag_juggle'},
      pack_tags = predict.ALL_TAG_PACKS})
  end)
  for _, k in ipairs(log) do H.ok(not k:find('^shop_pack'), 'no get_pack draw: '..k) end
  H.eq(S.game.first_shop_buffoon, nil, 'the forced Buffoon is still to come')
  local w = predict.ante_walk(S, 2, {tags = {small = 'tag_juggle', big = 'tag_juggle'}})
  H.eq(w.shops[1].packs[1].forced, true)
  H.ok(not pcall(predict.ante_walk, world(), 1, {pack_tags = {tag_juggle = true}}), 'a tag with no pack')
  H.ok(not pcall(predict.ante_walk, world(), 1, {pack_tags = 'tag_meteor'}), 'not a set')
  -- A falsy entry is simply off.
  local off = predict.ante_walk(world{megas = true}, 1, {skip = {Small = true}, tags = {small = 'tag_charm', big = 'tag_juggle'},
    pack_tags = {tag_charm = false}})
  H.eq(#off.tag_packs, 0)
end)
