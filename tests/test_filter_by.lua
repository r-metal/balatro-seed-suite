-- seedfinder.filter / seedfinder.route: "by ante N" on voucher and tag clauses
-- (T-313a, idea 5). A by clause must equal the OR of the plain per-ante
-- clauses 1..N, report the first ante that holds, draw each per-ante stream
-- at most once per S, sit in a group like any member, round-trip through
-- STR_PACK, and route at its found ante. Runs on the stub world of
-- tests/test_filter.lua (world() below is a copy of it); the reference for a
-- by clause is the plain clause at each ante, evaluated alone on its own
-- copy of the same seed.
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

-- A fresh S per seed: one world, copied and reseeded (cheaper than world()).
local function seeder(state, base)
  return function(seed)
    local T = state.copy(base)
    T.game.pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)}
    return T
  end
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

local function count(log, key)
  local n = 0
  for _, k in ipairs(log) do if k == key then n = n + 1 end end
  return n
end

local function first(log, key)
  for i, k in ipairs(log) do if k == key then return i end end
  return math.huge
end

local function nkeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function F(clauses, extra)
  local f = {name = 'test', clauses = clauses}
  for k, v in pairs(extra or {}) do f[k] = v end
  return f
end

local function grp(...) return {kind = 'group', clauses = {...}} end

local function copy(c)
  local out = {}
  for k, v in pairs(c) do out[k] = v end
  return out
end

-- c at one ante, without by: the plain clause the by clause is the OR of.
local function plain_at(c, a)
  local p = copy(c)
  p.by, p.ante = nil, a
  return p
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

-- Checks a by clause against the plain clauses 1..N on one seed: ok equals
-- their OR, the found ante is the first plain one that holds, and the hit's
-- details are that plain clause's plus ante (and the tag's blind).
local function check_by(filter, at, c, seed, where)
  local ok, d = filter.eval(at(seed), F({c}))
  local r = d.results[1]
  local found, plain
  for a = 1, c.ante do
    local pok, pd = filter.eval(at(seed), F({plain_at(c, a)}))
    if pok and not found then found, plain = a, pd.results[1] end
  end
  H.eq(ok, found ~= nil, where..': by = the OR of antes 1..'..c.ante)
  H.eq(r.ok, ok, where..': ok')
  if not found then
    H.eq(nkeys(r), 1, where..': a miss carries only ok')
    return nil
  end
  H.eq(r.ante, found, where..': the first ante that holds')
  local want = copy(plain)
  want.ante = found
  if c.kind == 'tag' then
    local blind = c.blind or 'any'
    want.blind = (blind ~= 'Big' and plain.small == c.key) and 'Small' or 'Big'
    if blind == 'Small' then H.eq(want.blind, 'Small', where) end
    if blind == 'Big' then H.eq(want.blind, 'Big', where) end
  end
  deep_eq(r, want, where..' details')
  return found, r
end

------------------------------------------------------------------------------

H.test('validate: by is a boolean, on voucher and tag clauses (and members) only', function()
  world()
  local filter = mods()
  local V = {kind = 'voucher', ante = 3, key = 'v_hone'}
  local T = {kind = 'tag', ante = 2, blind = 'Big', key = 'tag_juggle'}
  for _, v in ipairs{true, false} do
    local cv, ct = copy(V), copy(T)
    cv.by, ct.by = v, v
    H.eq(filter.validate(F({cv, ct})), true, 'by = '..tostring(v))
    H.eq(filter.validate(F({grp(cv, ct)})), true, 'by = '..tostring(v)..' in a group')
  end
  local bad = {1, 'yes', 0, {}}
  for _, v in ipairs(bad) do
    local cv = copy(V); cv.by = v
    local ok, err = filter.validate(F({{kind = 'boss', ante = 1, key = 'bl_hook'}, cv}))
    H.eq(ok, nil, 'by = '..tostring(v))
    H.ok(err:find('clause 2 (voucher): by must be a boolean', 1, true), tostring(err))
    local ct = copy(T); ct.by = v
    ok, err = filter.validate(F({grp({kind = 'boss', ante = 1, key = 'bl_hook'}, ct)}))
    H.eq(ok, nil, 'member by = '..tostring(v))
    H.ok(err:find('clause 1, member 2 (tag): by must be a boolean', 1, true), tostring(err))
  end
end)

H.test('validate: by on any other kind is refused, with the clause path', function()
  world()
  local filter = mods()
  -- (boss takes `by` since T-375: Boss by ante N, so it left this list)
  local others = {
    {kind = 'legendary', index = 1},
    {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
    {kind = 'shop_joker', ante = 1, key = 'j_joker'},
    {kind = 'pack', ante = 1, key_prefix = 'p_'},
    {kind = 'joker', ante = 2, key = 'j_blueprint'},
  }
  for _, c in ipairs(others) do
    for _, v in ipairs{true, false} do
      local b = copy(c); b.by = v
      local ok, err = filter.validate(F({{kind = 'tag', ante = 1, key = 'tag_juggle'}, b}))
      H.eq(ok, nil, c.kind..' by = '..tostring(v))
      H.ok(err:find('clause 2 ('..c.kind..'): by is for voucher, tag and boss clauses only', 1, true), tostring(err))
      ok, err = filter.validate(F({grp({kind = 'tag', ante = 1, key = 'tag_juggle'}, b)}))
      H.eq(ok, nil, c.kind..' member by')
      H.ok(err:find('clause 1, member 2 ('..c.kind..'): by is', 1, true), tostring(err))
    end
  end
  -- A group takes no by of its own.
  local g = grp({kind = 'voucher', ante = 1, key = 'v_hone'}, {kind = 'tag', ante = 1, key = 'tag_juggle'})
  g.by = true
  local ok, err = filter.validate(F({g}))
  H.eq(ok, nil); H.ok(err:find('clause 1 (group): unknown field by', 1, true), tostring(err))
  -- by still counts toward antes: N must be within f.antes.
  ok, err = filter.validate(F({{kind = 'voucher', ante = 4, key = 'v_hone', by = true}}, {antes = 3}))
  H.eq(ok, nil); H.ok(err:find('ante must be an integer 1..3', 1, true), tostring(err))
end)

H.test('voucher by ante N equals the OR of the plain voucher clauses 1..N (300 seeds)', function()
  local filter, _, state = mods()
  local at = seeder(state, world())
  local seen = {}
  for i = 1, 300 do
    local seed = 'VBY'..i
    local c = {kind = 'voucher', ante = 3, key = ({'v_hone', 'v_grabber', 'v_overstock_norm'})[i % 3 + 1], by = true}
    local a = check_by(filter, at, c, seed, seed)
    seen[a or 0] = true
  end
  for a = 0, 3 do H.ok(seen[a], a == 0 and 'saw a miss' or 'saw a hit found at ante '..a) end
end)

H.test('tag by ante N equals the OR of the plain tag clauses 1..N, for Small, Big and any (300 seeds each)', function()
  local filter, _, state = mods()
  local at = seeder(state, world())
  for _, blind in ipairs{'Small', 'Big', 'any'} do
    local seen, blinds = {}, {}
    for i = 1, 300 do
      local seed = 'TBY'..blind..i
      local c = {kind = 'tag', ante = 3, blind = blind, key = 'tag_juggle', by = true}
      local a, r = check_by(filter, at, c, seed, seed)
      seen[a or 0] = true
      if r then blinds[r.blind] = true end
    end
    for a = 0, 3 do H.ok(seen[a], blind..': '..(a == 0 and 'saw a miss' or 'saw a hit found at ante '..a)) end
    if blind == 'any' then H.ok(blinds.Small and blinds.Big, 'any: found on a Small and on a Big') end
  end
  -- blind defaults to any; min_ante holds (no Ethereal Tag at ante 1).
  for i = 1, 60 do
    local seed = 'TBYE'..i
    check_by(filter, at, {kind = 'tag', ante = 2, key = 'tag_economy', by = true}, seed, seed)
    local a = check_by(filter, at, {kind = 'tag', ante = 3, key = 'tag_ethereal', by = true}, seed, seed)
    H.ok(a ~= 1, seed..': no Ethereal Tag at ante 1')
  end
end)

H.test('a by hit reports the first ante that holds and draws no later ante', function()
  local filter, predict, state = mods()
  local at = seeder(state, world())
  -- Seeds whose ante-1 draw misses and ante-2 draw holds, with ante 3 holding
  -- too where one exists: the hit is ante 2, and ante 3 is never drawn.
  local vfound, tfound, both = 0, 0, 0
  for i = 1, 400 do
    local seed = 'FIRST'..i
    local v = {}
    for a = 1, 3 do v[a] = predict.voucher(at(seed), a) end
    if v[1] ~= v[2] then
      local c = {kind = 'voucher', ante = 3, key = v[2], by = true}
      local log, ok, d = streams(function() return filter.eval(at(seed), F({c})) end)
      H.eq(ok, true, seed); H.eq(d.results[1].ante, 2, seed); H.eq(d.results[1].key, v[2], seed)
      H.eq(count(log, 'Voucher1'), 1, seed); H.eq(count(log, 'Voucher2'), 1, seed)
      H.eq(count(log, 'Voucher3'), 0, seed..': stopped at ante 2')
      if v[3] == v[2] then both = both + 1 end
      vfound = vfound + 1
    end
    -- Tags: Big-only hit at ante 1 (Small differs) says Big; Small and Big
    -- both holding says Small.
    local t = predict.tags(at(seed), 1)
    local log, ok, d = streams(function()
      return filter.eval(at(seed), F({{kind = 'tag', ante = 3, key = t.big, by = true}}))
    end)
    H.eq(ok, true, seed); H.eq(d.results[1].ante, 1, seed)
    H.eq(d.results[1].blind, t.small == t.big and 'Small' or 'Big', seed)
    H.eq(count(log, 'Tag1'), 2, seed); H.eq(count(log, 'Tag2'), 0, seed); H.eq(count(log, 'Tag3'), 0, seed)
    if t.small == t.big then tfound = tfound + 1 end
  end
  H.ok(vfound > 20 and both > 0, 'voucher seeds: '..vfound..', ante 3 holding too: '..both)
  H.ok(tfound > 0, 'a seed with the same tag on both blinds: '..tfound)
end)

H.test('each per-ante stream is drawn at most once per S, by clauses and plain ones sharing it', function()
  local filter, predict, state = mods()
  local at = seeder(state, world())
  local walked = 0
  for i = 1, 100 do
    local seed = 'ONCE'..i
    local v3 = predict.voucher(at(seed), 3)
    local t2 = predict.tags(at(seed), 2)
    -- Every entry holds (mode all, so each is drawn): a plain voucher at 3
    -- and a by voucher that reads 1..3, a plain tag at 2 and a by tag member
    -- that reads 1..2, and a group whose from_tag member makes ante 2 a
    -- chained ante (a walk that takes its skips from the same tag draw).
    local f = F({
      {kind = 'voucher', ante = 3, key = v3},
      {kind = 'voucher', ante = 3, key = v3, by = true},
      {kind = 'tag', ante = 2, blind = 'Big', key = t2.big},
      grp({kind = 'tag', ante = 3, key = t2.big, by = true}, {kind = 'boss', ante = 3, key = 'bl_wall'}),
      grp({kind = 'soul_in_pack', ante = 2, pack = 'arcana', from_tag = true}, {kind = 'pack', ante = 2, key_prefix = 'p_'}),
    })
    local log, ok, d = streams(function() return filter.eval(at(seed), f) end)
    H.eq(ok, true, seed); H.eq(d.checked, 5, seed)
    for a = 1, 3 do
      local nv, nt = count(log, 'Voucher'..a), count(log, 'Tag'..a)
      H.ok(nv <= 1, seed..': Voucher'..a..' drawn '..nv)
      H.ok(nt == 0 or nt == 2, seed..': Tag'..a..' drawn '..nt..' (a draw is Small then Big)')
    end
    H.eq(count(log, 'Voucher3'), 1, seed); H.eq(count(log, 'Tag2'), 2, seed)
    H.eq(count(log, 'Tag3'), 0, seed..': the by tag stops by ante 2')
    if count(log, 'shop_pack2') > 0 then walked = walked + 1 end
    -- The by clauses alone on a fresh S agree with their results beside the rest.
    local _, alone = filter.eval(at(seed), F({f.clauses[2]}))
    deep_eq(d.results[2], alone.results[1], seed..' voucher by')
    _, alone = filter.eval(at(seed), F({f.clauses[4].clauses[1]}))
    deep_eq(d.results[4].results[1], alone.results[1], seed..' tag by member')
  end
  H.ok(walked > 0, 'ante 2 walked on some seeds: '..walked)
end)

H.test('order: a by clause stays in its kind\'s class, with N as its ante for ties', function()
  local filter, predict, state = mods()
  local at = seeder(state, world())
  -- A seed with a voucher no ante 1..3 shows.
  local seed, miss
  for i = 1, 400 do
    seed = 'ORDER'..i
    local v = {}
    for a = 1, 3 do v[a] = predict.voucher(at(seed), a) end
    for _, k in ipairs{'v_hone', 'v_grabber', 'v_overstock_norm'} do
      if k ~= v[1] and k ~= v[2] and k ~= v[3] then miss = k end
    end
    if miss then break end
  end
  H.ok(miss, 'a seed with a voucher no ante 1..3 shows')
  local by3 = {kind = 'voucher', ante = 3, key = miss, by = true}
  local by1 = {kind = 'voucher', ante = 1, key = miss, by = true}
  local p2 = {kind = 'voucher', ante = 2, key = miss}
  -- Ties by N: the plain ante-2 clause runs before a by-3, after a by-1.
  local ok, d = filter.eval(at(seed), F({by3, p2}))
  H.eq(ok, false); H.eq(d.checked, 1); H.eq(d.results[1], nil); H.eq(d.results[2].ok, false)
  ok, d = filter.eval(at(seed), F({p2, by1}))
  H.eq(ok, false); H.eq(d.checked, 1); H.eq(d.results[1], nil); H.eq(d.results[2].ok, false)
  -- Class: written most expensive first, every entry holding, the by tag
  -- (N = 3) runs before a boss at ante 1, which runs before the by voucher
  -- (N = 3), which runs before the legendary.
  local t1 = predict.tags(at(seed), 1)
  local f = F({{kind = 'legendary', index = 1},
    {kind = 'voucher', ante = 3, key = predict.voucher(at(seed), 1), by = true},
    {kind = 'boss', ante = 1, key = predict.boss(at(seed), 1)},
    {kind = 'tag', ante = 3, key = t1.small, by = true}})
  local log
  log, ok, d = streams(function() return filter.eval(at(seed), f) end)
  H.eq(ok, true); H.eq(d.checked, 4)
  H.eq(d.results[4].ante, 1); H.eq(d.results[2].ante, 1)
  H.ok(first(log, 'Tag1') < first(log, 'boss') and first(log, 'boss') < first(log, 'Voucher1')
    and first(log, 'Voucher1') < first(log, 'Joker4'), table.concat(log, ' '))
  H.eq(count(log, 'Voucher2') + count(log, 'Tag2'), 0, 'both by clauses stopped at ante 1')
end)

H.test('idea 5: a group of Voucher by ante 3 or Joker by ante 3 equals either member alone (200 seeds)', function()
  local filter, _, state = mods()
  local at = seeder(state, world())
  local V = {kind = 'voucher', ante = 3, key = 'v_hone', by = true}
  local J = {kind = 'joker', ante = 3, key = 'j_blueprint'}
  local g = grp(V, J)
  local f = F({g})
  H.eq(filter.validate(f), true)
  local seen = {}
  for i = 1, 200 do
    local seed = 'IDEA5_'..i
    local ok, d = filter.eval(at(seed), f)
    local vok, vd = filter.eval(at(seed), F({V}))
    local jok, jd = filter.eval(at(seed), F({J}))
    H.eq(ok, vok or jok, seed..': the group holds iff a member does alone')
    local r = d.results[1]
    H.eq(r.ok, ok, seed)
    -- The voucher member runs first (its class), and a hit there ends the group.
    deep_eq(r.results[1], vd.results[1], seed..' voucher member')
    if vok then
      H.eq(r.hit, 1, seed); H.eq(r.results[2], nil, seed..': the joker member not reached')
    else
      deep_eq(r.results[2], jd.results[1], seed..' joker member')
      H.eq(r.hit, jok and 2 or nil, seed)
    end
    seen[r.hit or 0] = true
  end
  H.ok(seen[1] and seen[2] and seen[0], 'saw a voucher hit, a joker hit and a miss')
  -- The same idea written the other way round, and 'any' of the two plain
  -- entries, agree on every seed.
  local f2, fa = F({grp(J, V)}), F({V, J}, {mode = 'any'})
  for i = 1, 60 do
    local seed = 'IDEA5_'..i
    local ok = filter.eval(at(seed), f)
    H.eq(filter.eval(at(seed), f2), ok, seed..' reversed')
    H.eq(filter.eval(at(seed), fa), ok, seed..' mode any')
  end
end)

H.test('serialize / deserialize round-trip by (true and false), in clauses and group members', function()
  local filter, _, state = mods()
  local at = seeder(state, world())
  local f = F({
    {kind = 'voucher', ante = 3, key = 'v_hone', by = true},
    {kind = 'tag', ante = 2, blind = 'Small', key = 'tag_juggle', by = false},
    grp({kind = 'voucher', ante = 3, key = 'v_grabber', by = true}, {kind = 'joker', ante = 3, key = 'j_blueprint'},
      {kind = 'tag', ante = 3, blind = 'Big', key = 'tag_charm', by = true}),
  }, {mode = 'any', stake = 2})
  local s = assert(filter.serialize(f))
  local back = assert(filter.deserialize(s))
  deep_eq(back, f, 'round-trip')
  H.eq(back.clauses[1].by, true); H.eq(back.clauses[2].by, false); H.eq(back.clauses[3].clauses[3].by, true)
  for i = 1, 20 do
    local seed = 'SER'..i
    local ok1, d1 = filter.eval(at(seed), f)
    local ok2, d2 = filter.eval(at(seed), back)
    H.eq(ok1, ok2, seed); deep_eq(d1, d2, seed)
  end
  -- A packed by of the wrong type is refused on load.
  local bad = s:gsub('%["by"%]=true', '["by"]=1', 1)
  H.ok(bad ~= s, 'the packed string names by')
  local none, err = filter.deserialize(bad)
  H.eq(none, nil); H.ok(err:find('by must be a boolean', 1, true), tostring(err))
end)

H.test('by = false and no by are the same clause: same result, same plain details (no ante, no blind)', function()
  local filter, _, state = mods()
  local at = seeder(state, world())
  for i = 1, 100 do
    local seed = 'NOBY'..i
    for _, c in ipairs{{kind = 'voucher', ante = 2, key = 'v_hone'}, {kind = 'tag', ante = 2, key = 'tag_juggle'},
      {kind = 'tag', ante = 3, blind = 'Big', key = 'tag_charm'}} do
      local off = copy(c); off.by = false
      local ok1, d1 = filter.eval(at(seed), F({c}))
      local ok2, d2 = filter.eval(at(seed), F({off}))
      H.eq(ok1, ok2, seed); deep_eq(d1, d2, seed..' '..c.kind)
      H.eq(d1.results[1].ante, nil, seed..': a plain clause reports no ante')
      H.eq(d1.results[1].blind, nil, seed..': a plain tag reports no blind')
    end
  end
end)

H.test('a by clause beside a legendary: the Soul\'s edition reads N, wherever the by clause stopped', function()
  local filter, predict, state = mods()
  local base = world()
  base.game.edition_rate = 10
  local at = seeder(state, base)
  local function leg(seed, ante)
    local T = at(seed)
    T.game.round_resets.ante = ante
    return predict.legendaries(T, 2)[1]
  end
  local early, moved = 0, 0
  for i = 1, 150 do
    local seed = 'BYLEG'..i
    local want3 = leg(seed, 3)
    if want3.edition ~= leg(seed, 1).edition then moved = moved + 1 end
    local V = {kind = 'voucher', ante = 3, key = predict.voucher(at(seed), 1), by = true}
    local LE = {kind = 'legendary', index = 1}
    local ok, d = filter.eval(at(seed), F({V, LE}))
    H.eq(ok, true, seed); H.eq(d.results[1].ante, 1, seed..': found at ante 1')
    H.eq(d.results[2].key, want3.key, seed); H.eq(d.results[2].edition, want3.edition, seed..': edition of ante 3')
    -- The plain voucher at N reads the same legendary.
    local _, dp = filter.eval(at(seed), F({{kind = 'voucher', ante = 3, key = 'v_hone'}, LE}, {mode = 'any'}))
    if dp.results[2] then H.eq(dp.results[2].edition, want3.edition, seed..' plain') end
    early = early + 1
  end
  H.ok(early > 0 and moved > 0, 'the ante moves the edition on some seeds: '..moved)
end)

H.test('route: a by hit adds no step; cost.ante is the found ante, not N', function()
  local filter, predict, state = mods()
  local R = route()
  local at = seeder(state, world())
  local found = {}
  for i = 1, 200 do
    local seed = 'RBY'..i
    for _, c in ipairs{{kind = 'voucher', ante = 3, key = 'v_hone', by = true},
      {kind = 'tag', ante = 3, blind = 'Small', key = 'tag_juggle', by = true}} do
      local f = F({c})
      local ok, d = filter.eval(at(seed), f)
      if ok then
        local r = assert(R.build(f, d))
        H.eq(#r.steps, 0, seed..': no step for a '..c.kind)
        H.eq(r.cost.ante, d.results[1].ante, seed..' '..c.kind..': cost.ante = the found ante')
        H.eq(r.cost.rerolls, 0); H.eq(r.cost.dollars, 0)
        found[d.results[1].ante] = true
        -- Beside a plain boss at ante 2 ('all'): the route ends at the later.
        local T = at(seed)
        predict.boss(T, 1)
        local fb = F({c, {kind = 'boss', ante = 2, key = predict.boss(T, 2)}})
        local okb, db = filter.eval(at(seed), fb)
        H.eq(okb, true, seed)
        H.eq(assert(R.build(fb, db)).cost.ante, math.max(2, d.results[1].ante), seed..': the later of the boss and the found ante')
      end
    end
    -- Idea 5's group, hit by its voucher member: the found ante counts.
    local g = F({grp({kind = 'voucher', ante = 3, key = 'v_grabber', by = true}, {kind = 'joker', ante = 3, key = 'j_blueprint'})})
    local okg, dg = filter.eval(at(seed), g)
    if okg and dg.results[1].hit == 1 then
      local r = assert(R.build(g, dg))
      H.eq(#r.steps, 0); H.eq(r.cost.ante, dg.results[1].results[1].ante, seed..' group')
    end
  end
  H.ok(found[1] and found[2] and found[3], 'hits found at antes 1, 2 and 3')
  -- Rank: a hit found at ante 1 before one found at ante 3 (same N).
  local f = F({{kind = 'voucher', ante = 3, key = 'v_hone', by = true}})
  local d1 = {checked = 1, results = {{ok = true, ante = 1, key = 'v_hone'}}}
  local d3 = {checked = 1, results = {{ok = true, ante = 3, key = 'v_hone'}}}
  local ranked, costs = R.rank(f, {{'LATE', d3}, {'EARLY', d1}})
  H.eq(ranked[1][1], 'EARLY'); H.eq(costs[1].ante, 1); H.eq(costs[2].ante, 3)
  -- Details that name no ante (or one past N) build no route.
  local r, err = R.build(f, {checked = 1, results = {{ok = true, key = 'v_hone'}}})
  H.eq(r, nil); H.ok(err:find('names no ante', 1, true), tostring(err))
  r, err = R.build(f, {checked = 1, results = {{ok = true, ante = 4, key = 'v_hone'}}})
  H.eq(r, nil); H.ok(err:find('names no ante', 1, true), tostring(err))
  -- Without by, the clause's own ante counts, as before.
  local fp = F({{kind = 'voucher', ante = 3, key = 'v_hone'}})
  H.eq(assert(R.build(fp, {checked = 1, results = {{ok = true, key = 'v_hone'}}})).cost.ante, 3)
end)

H.test('odds.sample counts a by clause and an idea-5 group as one clause each, unchanged', function()
  local filter, _, state = mods()
  local odds = require('seedfinder.odds')
  local at = seeder(state, world())
  local function eval(f1, seed) return filter.eval(at(seed), f1) end
  local V = {kind = 'voucher', ante = 3, key = 'v_hone', by = true}
  local g = grp({kind = 'tag', ante = 2, blind = 'Big', key = 'tag_juggle', by = true}, {kind = 'boss', ante = 1, key = 'bl_hook'})
  local f = F({V, g})
  local seeds = {}
  for i = 1, 80 do seeds[i] = 'BYODDS'..i end
  local counts = odds.sample(f, seeds, eval)
  H.eq(#counts.clauses, 2)
  local want, full = {0, 0}, 0
  for _, seed in ipairs(seeds) do
    if eval(F({V}), seed) then want[1] = want[1] + 1 end
    if eval(F({g}), seed) then want[2] = want[2] + 1 end
    if eval(f, seed) then full = full + 1 end
  end
  H.eq(counts.clauses[1], want[1]); H.eq(counts.clauses[2], want[2]); H.eq(counts.full, full)
  H.ok(want[1] > 0 and want[1] < #seeds, 'the by clause both holds and misses: '..want[1])
end)
