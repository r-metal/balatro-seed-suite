-- seedfinder.route: filter.eval details -> play steps + cost. The details come
-- from filter.eval on the stub world of tests/test_filter.lua (world() below is
-- a copy of it). Every route is also replayed step by step on bhcore.sim.predict
-- (a copy of the same state): each Soul, card and pack a step names must be
-- where the step says, drawn in the step order. Seeds are pinned (found offline
-- by scanning RCHAIN1.. / RBRANCH1.. on this world).
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


local function route() return require('seedfinder.route') end

local function F(clauses, extra)
  local f = {name = 'test', clauses = clauses}
  for k, v in pairs(extra or {}) do f[k] = v end
  return f
end

local function actions(r)
  local out = {}
  for i, st in ipairs(r.steps) do out[i] = st.action..'/'..st.when end
  return table.concat(out, ' ')
end

-- Plays r's steps on T through predict, in order, and checks what each names.
-- Mirrors filter.lua's walk: a shop draws its row and its 2 packs on entry,
-- rerolls, opens packs in slot order, and releases its row on leaving; the
-- run's forced first Buffoon is spent before the first shop past ante 1.
local function replay(predict, T, r)
  local shop -- {ante, packs}
  local function leave()
    if shop then predict.leave_shop(T); shop = nil end
  end
  local souls = 0
  for i, st in ipairs(r.steps) do
    local where = 'step '..i..' ('..st.text..')'
    if st.action == 'play' then
      leave()
      local a = st.when == 'Boss' and st.ante + 1 or st.ante
      if a > 1 and not T.game.first_shop_buffoon then predict.packs(T, 1, 1) end
      predict.shop(T, a)
      shop = {ante = a, packs = predict.packs(T, a, 2)}
    elseif st.action == 'skip' then
      leave()
    elseif st.action == 'reroll' then
      H.ok(shop and shop.ante == st.ante, where..': in a shop')
      local row = predict.reroll(T, st.ante)
      if st.key then H.eq(row[st.slot].key, st.key, where) end
    elseif st.action == 'open_pack' then
      local key = st.key
      if st.when == 'shop' then
        H.ok(shop and shop.ante == st.ante, where..': in a shop')
        if key then H.eq(shop.packs[st.slot].key, key, where) end
        key = shop.packs[st.slot].key
      end
      local cards = predict.pack_contents(T, key, st.ante)
      if st.take then
        -- A joker clause's Buffoon hit: the joker named, at index.
        H.eq(cards[st.index].key, st.take, where)
      elseif st.index then
        H.eq(cards[st.index].key, 'c_soul', where)
        souls = souls + 1
      end
    elseif st.action == 'buy' then
      H.ok(shop and shop.ante == st.ante, where..': in a shop')
      H.eq(shop.packs[st.slot].key, st.key, where)
    elseif st.action == 'use_soul' then
      H.ok(souls > 0, where..': a Soul was taken')
    else
      error(where..': unknown action')
    end
  end
  leave()
  return souls
end

local CHAIN = {{kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
  {kind = 'soul_in_pack', ante = 1, pack = 'arcana'}}

------------------------------------------------------------------------------

H.test('a non-hit or an invalid filter builds no route', function()
  local filter, predict, state = mods()
  local R = route()
  local S = world{seed = 'NOHIT'}
  local tags = predict.tags(state.copy(S), 1)
  local miss = tags.small == 'tag_juggle' and 'tag_economy' or 'tag_juggle'
  if tags.big == miss then miss = 'tag_uncommon' end
  local hit = {kind = 'tag', ante = 1, blind = 'Small', key = tags.small}
  local lose = {kind = 'tag', ante = 1, blind = 'Small', key = miss}
  local f = F({hit, lose})
  local ok, d = filter.eval(state.copy(S), f)
  H.eq(ok, false)
  local r, err = R.build(f, d)
  H.eq(r, nil); H.eq(err, 'not a hit')
  local fa = F({lose, lose}, {mode = 'any'})
  local oka, da = filter.eval(state.copy(S), fa)
  H.eq(oka, false)
  H.eq(select(2, R.build(fa, da)), 'not a hit', 'any mode, nothing hit')
  H.eq(select(2, R.build(f, nil)), 'not a hit', 'no details')
  -- 'all' details that short-circuited before a clause are not a hit either.
  H.eq(select(2, R.build(F({hit, hit}), {checked = 1, results = {{ok = true}}})), 'not a hit')
  local bad, berr = R.build(F({}), d)
  H.eq(bad, nil); H.ok(berr:find('clause', 1, true), 'invalid filter: '..tostring(berr))
end)

H.test('chained ante 1: Small skipped for its Charm Soul, used before the Big shop Soul', function()
  local filter, predict, state = mods()
  local R = route()
  local S = world{seed = 'RCHAIN39451', tags = {'tag_charm', 'tag_juggle'}}
  local f = F(CHAIN)
  local ok, d = filter.eval(state.copy(S), f)
  H.eq(ok, true, 'pinned seed still hits')
  H.eq(d.results[1].blind, 'Small'); H.eq(d.results[2].after, 'Big')
  local r = assert(R.build(f, d))
  local slot = d.results[2].slot
  local want = 'skip/Small open_pack/Small use_soul/Small play/Big'
  for _ = 1, slot do want = want..' open_pack/shop' end
  H.eq(actions(r), want)
  local skip, open, use = r.steps[1], r.steps[2], r.steps[3]
  H.eq(skip.key, 'tag_charm'); H.eq(skip.ante, 1)
  H.eq(skip.text, 'Skip the Small Blind (Charm Tag).')
  H.eq(open.key, 'p_arcana_mega_1'); H.eq(open.index, d.results[1].index)
  H.eq(open.text, ('The Mega Arcana Pack holds the Soul in slot %d: take it.'):format(d.results[1].index))
  H.eq(use.text, 'Use the Soul now: no Soul rolls while one is held.')
  H.eq(use.key, 'c_soul')
  local last = r.steps[#r.steps]
  H.eq(last.slot, slot); H.eq(last.key, d.results[2].pack); H.eq(last.index, d.results[2].index)
  H.eq(r.cost.ante, 1); H.eq(r.cost.rerolls, 0)
  H.eq(r.cost.dollars, nil, 'stub packs carry no cost')
  H.eq(replay(predict, state.copy(S), r), 2, 'both Souls where the steps say')
end)

H.test('chained ante 1, other shape: the Small shop Soul first, then the Big Charm Soul', function()
  local filter, predict, state = mods()
  local R = route()
  local S = world{seed = 'RCHAIN1460', tags = {'tag_charm', 'tag_juggle'}}
  local f = F(CHAIN)
  local ok, d = filter.eval(state.copy(S), f)
  H.eq(ok, true, 'pinned seed still hits')
  H.eq(d.results[1].blind, 'Big'); H.eq(d.results[2].after, 'Small')
  local r = assert(R.build(f, d))
  -- Every pack of the Small shop is opened (a later step of the ante follows).
  H.eq(actions(r), 'play/Small open_pack/shop open_pack/shop use_soul/shop skip/Big open_pack/Big')
  local soul_step = r.steps[1 + d.results[2].slot]
  H.eq(soul_step.index, d.results[2].index)
  H.ok(soul_step.text:find('take it.', 1, true), soul_step.text)
  H.eq(r.steps[2 + d.results[2].slot].action, 'use_soul', 'the Soul is used by the next step')
  H.eq(r.steps[5].text, 'Skip the Big Blind (Charm Tag).')
  H.ok(r.steps[6].text:find('take it.', 1, true), 'the last Soul is only taken')
  H.eq(replay(predict, state.copy(S), r), 2)
end)

H.test('shop_joker with rerolls: R rerolls per earlier shop, trimmed in the hit shop, priced $5 +$1', function()
  local filter, predict, state = mods()
  local R = route()
  local seen = 0
  for i = 1, 200 do
    local S = world{seed = 'RJOKER'..i}
    local f = F({{kind = 'shop_joker', ante = 2, key = 'j_blueprint', rerolls = 3}})
    local ok, d = filter.eval(state.copy(S), f)
    local h = d.results[1]
    if ok and h.shop > 1 and h.reroll >= 1 then
      seen = seen + 1
      local r = assert(R.build(f, d))
      -- Ante 2's shops: after the ante-1 Boss, the Small, the Big.
      H.eq(r.steps[1].action, 'play'); H.eq(r.steps[1].when, 'Boss'); H.eq(r.steps[1].ante, 1)
      H.eq(r.steps[1].text, 'Play the Boss Blind.')
      local want = 3 * (h.shop - 1) + h.reroll
      H.eq(r.cost.rerolls, want, 'RJOKER'..i)
      H.eq(r.cost.dollars, (h.shop - 1) * (5 + 6 + 7) + (h.reroll * (h.reroll + 9)) / 2)
      H.eq(r.cost.ante, 2)
      local last = r.steps[#r.steps]
      H.eq(last.action, 'reroll'); H.eq(last.index, h.reroll)
      H.eq(last.key, 'j_blueprint'); H.eq(last.slot, h.slot)
      H.ok(last.text:find('Blueprint in slot '..h.slot, 1, true), last.text)
      replay(predict, state.copy(S), r)
      if seen >= 3 then break end
    end
  end
  H.ok(seen >= 1, 'a reroll hit past the first shop in 200 seeds: '..seen)
end)

H.test('any mode routes only the clause that hit', function()
  local filter, predict, state = mods()
  local R = route()
  local S = world{seed = 'RANY'}
  local tags = predict.tags(state.copy(S), 1)
  local miss = tags.small == 'tag_juggle' and 'tag_economy' or 'tag_juggle'
  if tags.big == miss then miss = 'tag_uncommon' end
  -- A tag hit: nothing to do, the ante still counts.
  local f1 = F({{kind = 'shop_joker', ante = 1, key = 'j_joker', rerolls = 2},
    {kind = 'tag', ante = 3, blind = 'Small', key = predict.tags(state.copy(S), 3).small}}, {mode = 'any'})
  local ok1, d1 = filter.eval(state.copy(S), f1)
  H.eq(ok1, true)
  local r1 = assert(R.build(f1, d1))
  H.eq(#r1.steps, 0); H.eq(r1.cost.ante, 3); H.eq(r1.cost.rerolls, 0); H.eq(r1.cost.dollars, 0)
  -- The tag misses, a pack clause hits: only its shop, and it is bought.
  local f2 = F({{kind = 'tag', ante = 1, blind = 'Small', key = miss},
    {kind = 'pack', ante = 1, key_prefix = 'p_buffoon'}}, {mode = 'any'})
  local ok2, d2 = filter.eval(state.copy(S), f2)
  H.eq(ok2, true); H.eq(d2.results[1].ok, false)
  local r2 = assert(R.build(f2, d2))
  H.eq(actions(r2), 'play/Small buy/shop')
  H.eq(r2.steps[1].text, 'Play the Small Blind. In its shop, the Buffoon Pack is in slot 1.')
  H.eq(r2.steps[2].key, 'p_buffoon_normal_1'); H.eq(r2.steps[2].slot, 1)
  H.eq(r2.cost.dollars, nil, 'no cost in the stub')
  G.P_CENTERS.p_buffoon_normal_1.cost = 4
  H.eq(R.build(f2, d2).cost.dollars, 4, 'pack price from G.P_CENTERS')
  replay(predict, state.copy(S), r2)
end)

H.test('separate branches: an ante-1 Charm Soul is used before the ante-2 shop Soul', function()
  local filter, predict, state = mods()
  local R = route()
  local S = world{seed = 'RBRANCH10789', tags = {'tag_charm', 'tag_juggle'}}
  local f = F({{kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
    {kind = 'soul_in_pack', ante = 2, pack = 'arcana'}})
  local ok, d = filter.eval(state.copy(S), f)
  H.eq(ok, true, 'pinned seed still hits')
  local r = assert(R.build(f, d))
  local use, boss
  for i, st in ipairs(r.steps) do
    if st.action == 'use_soul' then use = use or i end
    if st.action == 'play' and st.when == 'Boss' then boss = boss or i end
  end
  H.ok(use and boss and use < boss, 'use_soul before the ante-2 shops: '..actions(r))
  -- The tag packs up to the Soul's, and no further.
  local last_tag = 0
  for i, st in ipairs(r.steps) do if st.ante == 1 and st.when ~= 'Boss' then last_tag = i end end
  H.eq(r.steps[last_tag].action, 'use_soul')
  H.eq(r.steps[last_tag - 1].when, d.results[1].blind)
  H.eq(r.cost.ante, 2)
  H.eq(replay(predict, state.copy(S), r), 2)
end)

H.test('build draws nothing: the details and the live G.GAME are untouched', function()
  local filter, _, state = mods()
  local R = route()
  local S = world{seed = 'RCHAIN39451', tags = {'tag_charm', 'tag_juggle'}}
  local f = F(CHAIN)
  local _, d = filter.eval(state.copy(S), f)
  local before, live = STR_PACK(d), STR_PACK(G.GAME)
  local real = pseudoseed
  local drawn = 0
  pseudoseed = function(...) drawn = drawn + 1; return real(...) end
  local ok, r = pcall(R.build, f, d)
  pseudoseed = real
  H.ok(ok, tostring(r))
  H.eq(drawn, 0, 'no stream drawn')
  H.eq(STR_PACK(d), before, 'details unchanged'); H.eq(STR_PACK(G.GAME), live, 'live G.GAME unchanged')
end)

H.test('texts sit under an Ante heading: no "Ante N:" prefix, a used Soul is said once', function()
  local filter, _, state = mods()
  local R = route()
  local cases = {
    {seed = 'RCHAIN39451', f = F(CHAIN)},
    {seed = 'RCHAIN1460', f = F(CHAIN)},
    {seed = 'RBRANCH10789', f = F({{kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
      {kind = 'soul_in_pack', ante = 2, pack = 'arcana'}})},
  }
  local uses = 0
  for _, c in ipairs(cases) do
    local S = world{seed = c.seed, tags = {'tag_charm', 'tag_juggle'}}
    local ok, d = filter.eval(state.copy(S), c.f)
    H.eq(ok, true, c.seed..' still hits')
    local r = assert(R.build(c.f, d))
    for i, st in ipairs(r.steps) do
      local where = c.seed..' step '..i..': '..st.text
      H.ok(not st.text:find('Ante %d'), where)
      H.ok(not st.text:find('use it', 1, true), where)
      if st.action == 'use_soul' then
        uses = uses + 1
        local prev = r.steps[i - 1]
        H.eq(prev.action, 'open_pack', where)
        H.ok(prev.index and prev.text:find('take it%.$'), c.seed..' step '..(i - 1)..': '..prev.text)
        H.ok(st.text:find('Use the Soul now', 1, true), where)
      end
    end
  end
  H.eq(uses, 3, 'one use_soul per route')
end)

-- Hits of an any-mode filter whose three clauses cost differently: a shop
-- joker (A1, its rerolls, dollars known), a Buffoon pack 2 (A1 R0, dollars from
-- G.P_CENTERS, unknown in the stub), an ante-2 tag (A2 R0 $0).
local RANKF = F({{kind = 'shop_joker', ante = 1, key = 'j_joker', rerolls = 2},
  {kind = 'pack', ante = 1, key_prefix = 'p_buffoon_normal_2'},
  {kind = 'tag', ante = 2, blind = 'Small', key = 'tag_juggle'}}, {mode = 'any'})

local function rank_hits()
  local filter, _, state = mods()
  local hits = {}
  for i = 1, 60 do
    local seed = 'RRANK'..i
    local ok, d = filter.eval(state.copy(world{seed = seed}), RANKF)
    if ok then hits[#hits + 1] = {seed, d} end
  end
  return hits
end

-- Checks out = rank's order of hits: a permutation, cheapest first, scan order
-- on ties, routeless hits last.
local function check_rank(R, hits, out, costs)
  H.eq(#out, #hits, 'a permutation')
  local pos = {}
  for i, h in ipairs(hits) do pos[h] = i end
  local seen = {}
  for k, h in ipairs(out) do
    H.ok(pos[h] and not seen[h], 'entry '..k..' is one of the hits, once'); seen[h] = true
    local r = R.build(RANKF, h.details or h[2])
    H.eq(costs[k] and STR_PACK(costs[k]), r and STR_PACK(r.cost), 'costs['..k..']')
  end
  for k = 2, #out do
    local a, b = costs[k - 1], costs[k]
    local where = ('%s before %s'):format(tostring(out[k - 1][1] or out[k - 1].seed), tostring(out[k][1] or out[k].seed))
    if not a then
      H.ok(not b and pos[out[k - 1]] < pos[out[k]], where..': routeless hits last, in scan order')
    elseif b then
      local ka = {a.ante, a.rerolls, a.dollars and 0 or 1, a.dollars or 0, pos[out[k - 1]]}
      local kb = {b.ante, b.rerolls, b.dollars and 0 or 1, b.dollars or 0, pos[out[k]]}
      local less
      for j = 1, #ka do
        if ka[j] ~= kb[j] then less = ka[j] < kb[j]; break end
      end
      H.ok(less, where..': '..STR_PACK(a)..' vs '..STR_PACK(b))
    end
  end
end

H.test('rank: fewer antes, then rerolls, then known dollars (unknown after), then scan order', function()
  local R = route()
  local hits = rank_hits()
  local kinds = {}
  local R0 = function(c) return c.ante == 1 and c.rerolls == 0 end
  for _, h in ipairs(hits) do
    local c = assert(R.build(RANKF, h[2])).cost
    if c.ante == 2 then kinds.a2 = true end
    if c.ante == 1 and c.rerolls > 0 then kinds.rerolls = true end
    if R0(c) and c.dollars then kinds.known = true end
    if R0(c) and not c.dollars then kinds.unknown = true end
  end
  H.ok(kinds.a2 and kinds.rerolls and kinds.known and kinds.unknown,
    'the sample has every cost shape: '..STR_PACK(kinds)..' in '..#hits..' hits')
  local input = {}
  for i, h in ipairs(hits) do input[i] = h end
  local out, costs = R.rank(RANKF, hits)
  for i, h in ipairs(hits) do H.ok(input[i] == h, 'hits left in place') end
  check_rank(R, hits, out, costs)
  -- Unknown dollars after known: the first A1 R0 hit is one with known dollars.
  for k, c in ipairs(costs) do
    if R0(c) then H.ok(c.dollars ~= nil, 'known dollars first at A1 R0'); break end
  end
  -- The pack's price known: its rows sort after the $0 shop-joker rows at A1 R0.
  G.P_CENTERS.p_buffoon_normal_2.cost = 4
  local out2, costs2 = R.rank(RANKF, hits)
  check_rank(R, hits, out2, costs2)
  for _, c in ipairs(costs2) do H.ok(c.dollars ~= nil, 'every price known now') end
end)

H.test('rank: routeless hits last, both entry shapes, an invalid filter refused', function()
  local R = route()
  local hits = rank_hits()
  local named = {}
  for i, h in ipairs(hits) do named[i] = {seed = h[1], details = h[2]} end
  -- A seed with no details and one whose details are not a hit, up front.
  table.insert(named, 1, {seed = 'NODETAILS'})
  table.insert(named, 2, {seed = 'MISS', details = {checked = 3, results = {{ok = false}, {ok = false}, {ok = false}}}})
  local out, costs = R.rank(RANKF, named)
  check_rank(R, named, out, costs)
  H.eq(out[#out - 1].seed, 'NODETAILS'); H.eq(out[#out].seed, 'MISS')
  H.eq(costs[#out], nil)
  local pos = {}
  local o1 = R.rank(RANKF, hits)
  for k, h in ipairs(o1) do pos[k] = h[1] end
  for k = 1, #o1 do H.eq(out[k].seed, pos[k], 'named and positional entries rank alike') end
  H.eq(#R.rank(RANKF, {}), 0)
  local bad, err = R.rank(F({}), hits)
  H.eq(bad, nil); H.ok(err and err:find('clause', 1, true), tostring(err))
end)

------------------------------------------------------------------------------
-- Jokers by ante N (T-311)

H.test('joker by ante N, shop row: routed at the ante it was found, rerolls trimmed in the hit shop', function()
  local filter, predict, state = mods()
  local R = route()
  local seen = 0
  for i = 1, 300 do
    local S = world{seed = 'RJANTE'..i}
    local f = F({{kind = 'joker', ante = 3, key = 'j_blueprint', rerolls = 2, from = 'shop'}})
    local ok, d = filter.eval(state.copy(S), f)
    local h = d.results[1]
    if ok and h.ante == 2 and h.reroll >= 1 then
      seen = seen + 1
      local r = assert(R.build(f, d))
      H.eq(r.cost.ante, 2, 'ends where the joker is, not at N')
      H.eq(r.cost.rerolls, 2 * (h.shop - 1) + h.reroll, 'RJANTE'..i)
      H.eq(r.steps[1].action, 'play'); H.eq(r.steps[1].when, 'Boss'); H.eq(r.steps[1].ante, 1)
      local last = r.steps[#r.steps]
      H.eq(last.action, 'reroll'); H.eq(last.index, h.reroll)
      H.eq(last.key, 'j_blueprint'); H.eq(last.slot, h.index)
      H.ok(last.text:find('Blueprint in slot '..h.index, 1, true), last.text)
      for _, st in ipairs(r.steps) do H.ok(st.action ~= 'open_pack', 'from shop opens no pack') end
      replay(predict, state.copy(S), r)
      if seen >= 3 then break end
    end
  end
  H.ok(seen >= 1, 'an ante-2 reroll hit in 300 seeds: '..seen)
end)

H.test('joker by ante N, Buffoon pack: all R rerolls, packs up to its slot, the joker taken', function()
  local filter, predict, state = mods()
  local R = route()
  local seen, forced = 0, 0
  for i = 1, 300 do
    local S = world{seed = 'RJBUF'..i}
    local f = F({{kind = 'joker', ante = 3, key = 'j_ceremonial', rerolls = 1, from = 'buffoon'}})
    local ok, d = filter.eval(state.copy(S), f)
    local h = d.results[1]
    if ok and h.ante >= 2 and seen < 3 then
      seen = seen + 1
      local r = assert(R.build(f, d))
      H.eq(r.cost.ante, h.ante)
      H.eq(r.cost.rerolls, 1 * h.shop, 'R rerolls in every shop up to the hit one')
      local last = r.steps[#r.steps]
      H.eq(last.action, 'open_pack'); H.eq(last.when, 'shop')
      H.eq(last.slot, h.pack_slot); H.eq(last.key, h.pack)
      H.eq(last.take, 'j_ceremonial'); H.eq(last.index, h.index)
      H.eq(last.text:match('Ceremonial Dagger is card (%d+): take it%.$'), tostring(h.index), last.text)
      -- Its shop: the reroll comes before the packs (the walk opens them after).
      H.eq(r.steps[#r.steps - h.pack_slot].action, 'reroll')
      replay(predict, state.copy(S), r)
    elseif ok and h.ante == 1 and h.shop == 1 and h.pack_slot == 1 and forced == 0 then
      forced = forced + 1
      local r = assert(R.build(f, d))
      H.eq(r.cost.ante, 1)
      H.eq(actions(r), 'play/Small reroll/shop open_pack/shop')
      H.eq(r.steps[3].key, 'p_buffoon_normal_1'); H.eq(r.steps[3].take, 'j_ceremonial')
      replay(predict, state.copy(S), r)
    end
    if seen >= 3 and forced > 0 then break end
  end
  H.ok(seen >= 1 and forced >= 1, 'Buffoon hits at ante >= 2 and in the forced pack: '..seen..', '..forced)
end)

------------------------------------------------------------------------------
-- Any-of groups (T-312)

local function deep_eq(a, b, path)
  path = path or 'r'
  if type(a) ~= type(b) then error(path..': '..type(a)..' vs '..type(b), 2) end
  if type(a) ~= 'table' then
    if a ~= b then error(path..': '..tostring(a)..' vs '..tostring(b), 2) end
    return
  end
  for k, v in pairs(a) do deep_eq(v, b[k], path..'.'..tostring(k)) end
  for k in pairs(b) do if a[k] == nil then error(path..'.'..tostring(k)..' missing', 2) end end
end

H.test('group: a group hit is routed as the member that hit, on its own', function()
  local filter, predict, state = mods()
  local R = route()
  local sj = {kind = 'shop_joker', ante = 2, key = 'j_blueprint', rerolls = 3}
  local tg = {kind = 'tag', ante = 3, blind = 'Small', key = 'tag_juggle'}
  local f = F({{kind = 'group', clauses = {sj, tg}}})
  local seen = {0, 0}
  for i = 1, 200 do
    local S = world{seed = 'RGROUP'..i}
    local ok, d = filter.eval(state.copy(S), f)
    if ok then
      local m = d.results[1].hit
      local r = assert(R.build(f, d))
      local alone = F({m == 1 and sj or tg})
      local oka, da = filter.eval(state.copy(S), alone)
      H.eq(oka, true, 'RGROUP'..i..': the member holds alone')
      deep_eq(r, assert(R.build(alone, da)), 'RGROUP'..i..' member '..m)
      if m == 2 then
        H.eq(#r.steps, 0); H.eq(r.cost.ante, 3)
      else
        H.eq(r.steps[#r.steps].key, 'j_blueprint')
        replay(predict, state.copy(S), r)
      end
      seen[m] = seen[m] + 1
    else
      H.eq(select(2, R.build(f, d)), 'not a hit', 'RGROUP'..i)
    end
    if seen[1] >= 3 and seen[2] >= 3 then break end
  end
  H.ok(seen[1] > 0 and seen[2] > 0, 'hits on both members: '..seen[1]..', '..seen[2])
  -- A group result that holds but names no member that held is not a hit.
  H.eq(select(2, R.build(f, {checked = 1, results = {{ok = true, results = {}}}})), 'not a hit')
  H.eq(select(2, R.build(f, {checked = 1, results = {{ok = true, hit = 1, results = {{ok = false}}}}})), 'not a hit')
  -- Mode all: a plain clause beside the group is routed too.
  local fa = F({{kind = 'group', clauses = {sj, tg}}, {kind = 'pack', ante = 1, key_prefix = 'p_buffoon'}})
  local both
  for i = 1, 200 do
    local S = world{seed = 'RGROUP'..i}
    local ok, d = filter.eval(state.copy(S), fa)
    if ok and d.results[1].hit == 1 then
      local r = assert(R.build(fa, d))
      H.eq(r.steps[1].ante, 1); H.eq(r.steps[1].when, 'Small', 'the ante-1 pack first')
      H.eq(r.cost.ante, 2)
      replay(predict, state.copy(S), r)
      both = i
      break
    end
  end
  H.ok(both, 'a mode-all hit on the group\'s shop_joker and the pack')
end)

H.test('group: a chained ante is routed from details.tag_packs when its from_tag member was not reached', function()
  local filter, predict, state = mods()
  local R = route()
  local f = F({{kind = 'group', clauses = {{kind = 'tag', ante = 1, blind = 'Big', key = 'tag_juggle'},
      {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true}}},
    {kind = 'pack', ante = 1, key_prefix = 'p_'}})
  local seen = 0
  for i = 1, 200 do
    local S = world{seed = 'RGCHAIN'..i, tags = {'tag_charm', 'tag_juggle'}}
    local t = predict.tags(state.copy(S), 1)
    if t.small == 'tag_charm' and t.big == 'tag_juggle' then
      local ok, d = filter.eval(state.copy(S), f)
      H.eq(ok, true, 'RGCHAIN'..i)
      H.eq(d.results[1].hit, 1); H.eq(d.results[1].results[2], nil, 'the from_tag member not reached')
      local r = assert(R.build(f, d))
      H.eq(actions(r), 'skip/Small open_pack/Small play/Big buy/shop')
      H.eq(r.steps[1].text, 'Skip the Small Blind (Charm Tag).')
      H.eq(r.steps[2].text, 'Open the Mega Arcana Pack and take nothing.')
      H.eq(r.steps[4].slot, 1); H.eq(r.steps[4].key, 'p_buffoon_normal_1')
      H.eq(r.cost.ante, 1); H.eq(r.cost.rerolls, 0)
      replay(predict, state.copy(S), r)
      -- Without the eval's record the chained ante has no skips to read.
      local bare = {checked = d.checked, results = d.results}
      H.eq(select(2, R.build(f, bare)), 'details: no tag packs at chained ante 1')
      seen = seen + 1
      if seen >= 2 then break end
    end
  end
  H.ok(seen > 0, 'a Charm Small / Juggle Big seed in 200')
end)
