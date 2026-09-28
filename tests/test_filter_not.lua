-- seedfinder.filter / seedfinder.route: must-not clauses (exclude), Boss "by
-- ante N" and sticker = 'none' (T-375, research pick [7]). An excluded clause
-- must equal the negation of its positive form and draw exactly what that
-- form draws; a boss by clause must equal the OR of the plain boss clauses
-- 1..N and draw the global 'boss' stream once per ante; sticker = 'none' must
-- skip a stickered copy and go on to the next one within the clause's budget,
-- and change nothing below Black Stake. Runs on the stub world of
-- tests/test_filter.lua (world() below is a copy of it, plus The Plant and
-- the Black-and-up stake modifiers on request); the reference is the positive
-- clause, the plain per-ante clause or a hand predict.ante_walk on a copy of
-- the same seed.
local H = ...

local function center(key, t)
  t.key = key
  t.config = t.config or {}
  return t
end

local TAGS = {'tag_uncommon', 'tag_juggle', 'tag_charm', 'tag_economy', 'tag_ethereal'}

-- The stub world of tests/test_filter.lua, with The Plant as a fourth boss
-- (min ante 1 here, so "no Plant by ante 3" can fail) and, with o.stake8, the
-- sticker modifiers state.fresh gives stakes 4, 7 and 8 (sim/state.lua).
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
    center('p_arcana_normal_1', {order = 1, name = 'Arcana Pack', weight = 1, kind = 'Arcana', set = 'Booster', config = {extra = 3, choose = 1}, cost = 4}),
    center('p_arcana_mega_1', {order = 2, name = 'Mega Arcana Pack', weight = 0.25, kind = 'Arcana', set = 'Booster', config = {extra = 5, choose = 2}, cost = 8}),
    center('p_arcana_mega_2', {order = 3, name = 'Mega Arcana Pack', weight = 0.25, kind = 'Arcana', set = 'Booster', config = {extra = 5, choose = 2}, cost = 8}),
    center('p_celestial_normal_1', {order = 4, name = 'Celestial Pack', weight = 1, kind = 'Celestial', set = 'Booster', config = {extra = 3, choose = 1}, cost = 4}),
    center('p_spectral_normal_1', {order = 5, name = 'Spectral Pack', weight = 0.6, kind = 'Spectral', set = 'Booster', config = {extra = 2, choose = 1}, cost = 4}),
    center('p_buffoon_normal_1', {order = 6, name = 'Buffoon Pack', weight = 0.6, kind = 'Buffoon', set = 'Booster', config = {extra = 2, choose = 1}, cost = 4}),
    center('p_buffoon_normal_2', {order = 7, name = 'Buffoon Pack', weight = 0.6, kind = 'Buffoon', set = 'Booster', config = {extra = 2, choose = 1}, cost = 4}),
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
    bl_plant = {key = 'bl_plant', boss = {min = 1, max = 10}},
    bl_wall = {key = 'bl_wall', boss = {min = 2, max = 10}},
  }
  G.handlist = {'Pair', 'High Card'}
  G.jokers = {cards = {}, config = {card_limit = 5}}
  G.consumeables = {cards = {}, config = {card_limit = 2}}
  G.playing_cards = {}
  G.GAME = {live = true, pseudorandom = {seed = 'LIVE'}, round_resets = {ante = 5}}
  local seed = o.seed or 'FILTSEED'
  local modifiers = {}
  if o.stake8 then
    modifiers.enable_eternals_in_shop = true
    modifiers.enable_perishables_in_shop = true
    modifiers.enable_rentals_in_shop = true
  end
  local game = {
    round_resets = {ante = 1}, win_ante = 8, stake = o.stake8 and 8 or 1,
    pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)},
    used_jokers = {}, used_vouchers = {}, banned_keys = {}, pool_flags = {},
    bosses_used = {bl_hook = 0, bl_club = 0, bl_plant = 0, bl_wall = 0},
    hands = {['High Card'] = {played = 0, visible = true}, Pair = {played = 0, visible = true}},
    modifiers = modifiers, edition_rate = o.edition_rate or 1, shop = {joker_max = 2},
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

local function drew(log, pat)
  for _, k in ipairs(log) do if k:find(pat) then return true end end
  return false
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

-- c as a must-not.
local function ex(c)
  local out = copy(c)
  out.exclude = true
  return out
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

local function clean(x)
  local s = x.stickers
  return not (s.eternal or s.perishable or s.rental)
end

-- Checks ex(c) against c on one seed: the result is the negation, the draws
-- are the same, and the details are {ok = true} alone on a hit, the positive
-- form's details (ok = false) on a miss. Returns whether the positive held.
local function check_not(filter, at, c, seed, where)
  local plog, pok, pd = streams(function() return filter.eval(at(seed), F({c})) end)
  local xlog, xok, xd = streams(function() return filter.eval(at(seed), F({ex(c)})) end)
  H.eq(xok, not pok, where..': exclude = not the positive form')
  H.eq(xd.checked, 1, where)
  deep_eq(xlog, plog, where..': the same draws')
  local r = xd.results[1]
  H.eq(r.ok, xok, where..': ok')
  if pok then
    local want = copy(pd.results[1])
    want.ok = false
    deep_eq(r, want, where..': the positive details (why not)')
  else
    H.eq(nkeys(r), 1, where..': a holding must-not carries only ok')
  end
  return pok
end

------------------------------------------------------------------------------
-- Validation

H.test('validate: exclude is a boolean on a top-level clause of a mode-all filter only, with the path', function()
  world()
  local filter = mods()
  local every = {
    {kind = 'tag', ante = 1, key = 'tag_juggle'},
    {kind = 'boss', ante = 2, key = 'bl_plant', by = true},
    {kind = 'voucher', ante = 1, key = 'v_hone'},
    {kind = 'legendary', index = 1},
    {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
    {kind = 'shop_joker', ante = 1, key = 'j_joker', sticker = 'none'},
    {kind = 'pack', ante = 1, key_prefix = 'p_buffoon'},
    {kind = 'joker', ante = 2, key = 'j_blueprint'},
  }
  local head = {kind = 'tag', ante = 1, key = 'tag_charm'}
  for _, c in ipairs(every) do
    for _, v in ipairs{true, false} do
      local x = copy(c); x.exclude = v
      H.eq(filter.validate(F({head, x})), true, c.kind..' exclude = '..tostring(v))
      H.eq(filter.validate(F({head, x}, {mode = 'all'})), true, c.kind..' mode all')
      -- In a group: refused, either value.
      local ok, err = filter.validate(F({head, grp({kind = 'boss', ante = 1, key = 'bl_hook'}, x)}))
      H.eq(ok, nil, c.kind..' member exclude = '..tostring(v))
      H.ok(err:find('clause 2, member 2 ('..c.kind..'): exclude cannot be on a group member', 1, true), tostring(err))
      -- In mode any: refused, either value.
      ok, err = filter.validate(F({head, x}, {mode = 'any'}))
      H.eq(ok, nil, c.kind..' mode any exclude = '..tostring(v))
      H.ok(err:find('clause 2 ('..c.kind..'): exclude needs mode all', 1, true), tostring(err))
    end
    for _, v in ipairs{1, 'yes', 0, {}} do
      local x = copy(c); x.exclude = v
      local ok, err = filter.validate(F({head, x}))
      H.eq(ok, nil, c.kind..' exclude = '..tostring(v))
      H.ok(err:find('clause 2 ('..c.kind..'): exclude must be a boolean', 1, true), tostring(err))
    end
  end
  -- A group takes no exclude of its own.
  local g = grp({kind = 'voucher', ante = 1, key = 'v_hone'}, {kind = 'tag', ante = 1, key = 'tag_juggle'})
  g.exclude = true
  local ok, err = filter.validate(F({g}))
  H.eq(ok, nil); H.ok(err:find('clause 1 (group): unknown field exclude', 1, true), tostring(err))
  -- No exclude anywhere: mode any and groups are as before.
  H.eq(filter.validate(F({head, every[3]}, {mode = 'any'})), true)
end)

H.test('validate: sticker is none, on shop_joker and joker clauses (and members) only', function()
  world()
  local filter = mods()
  local SJ = {kind = 'shop_joker', ante = 1, key = 'j_joker', rerolls = 2, sticker = 'none'}
  local JK = {kind = 'joker', ante = 2, key = 'j_blueprint', from = 'buffoon', edition = 'foil', sticker = 'none'}
  H.eq(filter.validate(F({SJ, JK})), true)
  H.eq(filter.validate(F({grp(SJ, JK)})), true, 'in a group')
  H.eq(filter.validate(F({SJ, JK}, {mode = 'any'})), true, 'mode any')
  H.eq(filter.validate(F({ex(SJ), JK})), true, 'excluded')
  for _, v in ipairs{'eternal', 'None', true, 1, {}} do
    local x = copy(SJ); x.sticker = v
    local ok, err = filter.validate(F({JK, x}))
    H.eq(ok, nil, 'sticker = '..tostring(v))
    H.ok(err:find('clause 2 (shop_joker): sticker must be none', 1, true), tostring(err))
    local y = copy(JK); y.sticker = v
    ok, err = filter.validate(F({grp(SJ, y)}))
    H.eq(ok, nil, 'member sticker = '..tostring(v))
    H.ok(err:find('clause 1, member 2 (joker): sticker must be none', 1, true), tostring(err))
  end
  local others = {
    {kind = 'tag', ante = 1, key = 'tag_juggle'},
    {kind = 'boss', ante = 1, key = 'bl_hook'},
    {kind = 'voucher', ante = 1, key = 'v_hone'},
    {kind = 'legendary', index = 1},
    {kind = 'soul_in_pack', ante = 1, pack = 'arcana'},
    {kind = 'pack', ante = 1, key_prefix = 'p_'},
  }
  for _, c in ipairs(others) do
    local x = copy(c); x.sticker = 'none'
    local ok, err = filter.validate(F({SJ, x}))
    H.eq(ok, nil, c.kind)
    H.ok(err:find('clause 2 ('..c.kind..'): sticker is for shop_joker and joker clauses only', 1, true), tostring(err))
  end
end)

H.test('validate: boss takes by (a boolean), in clauses and members, and it counts toward antes', function()
  world()
  local filter = mods()
  for _, v in ipairs{true, false} do
    local b = {kind = 'boss', ante = 3, key = 'bl_plant', by = v}
    H.eq(filter.validate(F({b})), true, 'by = '..tostring(v))
    H.eq(filter.validate(F({grp(b, {kind = 'tag', ante = 1, key = 'tag_juggle'})})), true, 'member by = '..tostring(v))
    H.eq(filter.validate(F({ex(b)})), true, 'excluded by = '..tostring(v))
  end
  for _, v in ipairs{1, 'yes', {}} do
    local ok, err = filter.validate(F({{kind = 'tag', ante = 1, key = 'tag_juggle'}, {kind = 'boss', ante = 2, key = 'bl_hook', by = v}}))
    H.eq(ok, nil, 'by = '..tostring(v))
    H.ok(err:find('clause 2 (boss): by must be a boolean', 1, true), tostring(err))
  end
  local ok, err = filter.validate(F({{kind = 'boss', ante = 4, key = 'bl_hook', by = true}}, {antes = 3}))
  H.eq(ok, nil); H.ok(err:find('ante must be an integer 1..3', 1, true), tostring(err))
  -- Still no by on the kinds that never took it.
  ok, err = filter.validate(F({{kind = 'pack', ante = 1, key_prefix = 'p_', by = true}}))
  H.eq(ok, nil); H.ok(err:find('clause 1 (pack): by is for voucher, tag and boss clauses only', 1, true), tostring(err))
end)

------------------------------------------------------------------------------
-- exclude = not the positive form

H.test('an excluded tag clause equals not its positive form (300 seeds; plain and by)', function()
  local filter, _, state = mods()
  local at = seeder(state, world())
  local seen = {}
  for i = 1, 300 do
    local seed = 'NTAG'..i
    local blind = ({'Small', 'Big', 'any'})[i % 3 + 1]
    local c = {kind = 'tag', ante = 1 + i % 2, blind = blind, key = ({'tag_juggle', 'tag_charm'})[i % 2 + 1]}
    seen[check_not(filter, at, c, seed, seed..' plain')] = true
    local b = copy(c); b.ante, b.by = 3, true
    seen['by'..tostring(check_not(filter, at, b, seed, seed..' by'))] = true
  end
  H.ok(seen[true] and seen[false] and seen.bytrue and seen.byfalse, 'saw the positive form hold and fail, plain and by')
end)

H.test('an excluded boss clause equals not its positive form (300 seeds; plain and by)', function()
  local filter, _, state = mods()
  local at = seeder(state, world())
  local seen = {}
  for i = 1, 300 do
    local seed = 'NBOSS'..i
    local key = ({'bl_plant', 'bl_hook', 'bl_club', 'bl_wall'})[i % 4 + 1]
    local c = {kind = 'boss', ante = 1 + i % 3, key = key}
    if key == 'bl_wall' then c.ante = 2 end
    seen[check_not(filter, at, c, seed, seed..' plain')] = true
    local b = copy(c); b.ante, b.by = 3, true
    seen['by'..tostring(check_not(filter, at, b, seed, seed..' by'))] = true
  end
  H.ok(seen[true] and seen[false] and seen.bytrue and seen.byfalse, 'saw the positive form hold and fail, plain and by')
end)

H.test('an excluded voucher clause equals not its positive form (300 seeds; plain and by)', function()
  local filter, _, state = mods()
  local at = seeder(state, world())
  local seen = {}
  for i = 1, 300 do
    local seed = 'NVOU'..i
    local c = {kind = 'voucher', ante = 1 + i % 3, key = ({'v_hone', 'v_grabber', 'v_overstock_norm'})[i % 3 + 1]}
    seen[check_not(filter, at, c, seed, seed..' plain')] = true
    local b = copy(c); b.ante, b.by = 2, true
    seen['by'..tostring(check_not(filter, at, b, seed, seed..' by'))] = true
  end
  H.ok(seen[true] and seen[false] and seen.bytrue and seen.byfalse, 'saw the positive form hold and fail, plain and by')
end)

H.test('an excluded shop_joker clause equals not its positive form (300 seeds; rerolls, editions, stickers)', function()
  local filter, _, state = mods()
  local plain = seeder(state, world())
  local black = seeder(state, world{stake8 = true})
  local keys = {'j_joker', 'j_greedy_joker', 'j_ceremonial', 'j_blueprint', 'c_fool'}
  local seen = {}
  for i = 1, 300 do
    local seed = 'NSHOP'..i
    local c = {kind = 'shop_joker', ante = 1 + i % 2, key = keys[i % #keys + 1], rerolls = i % 3}
    if i % 5 == 0 then c.edition = 'any' end
    seen[check_not(filter, plain, c, seed, seed)] = true
    local s = copy(c); s.sticker = 'none'
    seen['s'..tostring(check_not(filter, black, s, seed, seed..' stake 8 sticker none'))] = true
  end
  H.ok(seen[true] and seen[false] and seen.strue and seen.sfalse, 'saw the positive form hold and fail')
end)

H.test('an excluded clause keeps its class: it runs in cost order and ends an all at its positive hit', function()
  local filter, predict, state = mods()
  local at = seeder(state, world())
  local ended, went_on = 0, 0
  for i = 1, 120 do
    local seed = 'NORDER'..i
    local t1 = predict.tags(at(seed), 1)
    local v1 = predict.voucher(at(seed), 1)
    -- Written most expensive first: the excluded shop_joker still runs after
    -- the tag and voucher (classes 1 and 3), and a must-not on the tag that
    -- is there (its positive holds) ends the eval before anything else.
    local SJ = {kind = 'shop_joker', ante = 1, key = 'j_blueprint', rerolls = 1}
    local log, ok, d = streams(function()
      return filter.eval(at(seed), F({ex(SJ), {kind = 'voucher', ante = 1, key = v1}, ex({kind = 'tag', ante = 1, key = t1.small})}))
    end)
    H.eq(ok, false, seed); H.eq(d.checked, 1, seed)
    H.eq(d.results[1], nil, seed); H.eq(d.results[2], nil, seed)
    H.eq(d.results[3].ok, false); H.eq(d.results[3].small, t1.small, seed..': why not')
    H.ok(not drew(log, '^Voucher') and not drew(log, '^cdt'), seed..': nothing drawn past the tag')
    ended = ended + 1
    -- A tag the ante lacks: the must-not holds, the voucher runs, then the shop.
    local miss
    for _, k in ipairs(TAGS) do if k ~= t1.small and k ~= t1.big and k ~= 'tag_ethereal' then miss = k end end
    log, ok, d = streams(function()
      return filter.eval(at(seed), F({ex(SJ), {kind = 'voucher', ante = 1, key = v1}, ex({kind = 'tag', ante = 1, key = miss})}))
    end)
    local _, sj = filter.eval(at(seed), F({SJ}))
    H.eq(ok, not sj.results[1].ok, seed); H.eq(d.checked, 3, seed)
    deep_eq(d.results[3], {ok = true}, seed..' tag')
    H.eq(d.results[2].ok, true, seed)
    H.ok(drew(log, '^cdt1$'), seed..': the shop walked')
    if ok then went_on = went_on + 1 end
  end
  H.ok(ended > 0 and went_on > 0, 'seeds: '..ended..' ended at the tag, '..went_on..' hits')
end)

------------------------------------------------------------------------------
-- Boss by ante N

H.test('boss by ante N equals the OR of the plain boss clauses 1..N and reports the first ante (300 seeds)', function()
  local filter, _, state = mods()
  local at = seeder(state, world())
  local seen = {}
  for i = 1, 300 do
    local seed = 'BBY'..i
    local c = {kind = 'boss', ante = 3, key = ({'bl_plant', 'bl_hook', 'bl_club', 'bl_wall'})[i % 4 + 1], by = true}
    local found, plain
    for a = 1, 3 do
      local pc = copy(c); pc.by, pc.ante = nil, a
      local pok, pd = filter.eval(at(seed), F({pc}))
      if pok and not found then found, plain = a, pd.results[1] end
    end
    local ok, d = filter.eval(at(seed), F({c}))
    H.eq(ok, found ~= nil, seed..': by = the OR of antes 1..3')
    local r = d.results[1]
    if found then
      deep_eq(r, {ok = true, ante = found, key = plain.key}, seed..' details')
    else
      deep_eq(r, {ok = false}, seed..': a miss carries only ok')
    end
    seen[found or 0] = true
  end
  for a = 0, 3 do H.ok(seen[a], a == 0 and 'saw a miss' or 'saw a hit found at ante '..a) end
end)

H.test('boss by draws the boss stream once per ante, in order, shared with plain boss clauses', function()
  local filter, predict, state = mods()
  local at = seeder(state, world())
  local stopped = 0
  for i = 1, 150 do
    local seed = 'BONCE'..i
    local T = at(seed)
    local b = {}
    for a = 1, 4 do b[a] = predict.boss(T, a) end
    local K = b[2]
    local first
    for a = 1, 3 do if b[a] == K and not first then first = a end end
    -- Alone: bosses 1..the found ante (N on a miss), each once.
    local c = {kind = 'boss', ante = 3, key = K, by = true}
    local log, ok, d = streams(function() return filter.eval(at(seed), F({c})) end)
    H.eq(ok, true, seed); H.eq(d.results[1].ante, first, seed)
    H.eq(count(log, 'boss'), first, seed..': drew bosses 1..'..first)
    if first < 3 then stopped = stopped + 1 end
    -- A miss draws 1..N once (4 bosses, 3 antes: one is never drawn).
    local miss
    for _, k in ipairs{'bl_hook', 'bl_club', 'bl_plant', 'bl_wall'} do
      if k ~= b[1] and k ~= b[2] and k ~= b[3] then miss = k end
    end
    local none = {kind = 'boss', ante = 3, key = miss, by = true}
    log, ok = streams(function() return filter.eval(at(seed), F({none})) end)
    H.eq(ok, false, seed); H.eq(count(log, 'boss'), 3, seed..': a miss draws 1..3 once')
    -- Beside plain boss clauses (every entry holds, so each is drawn): a plain
    -- boss at 2 before the by 3 (ties by ante), a by 3 of the ante-3 boss, the
    -- miss as a must-not, and a plain boss at 4: every ante is drawn once.
    local f = F({{kind = 'boss', ante = 4, key = b[4]}, c, {kind = 'boss', ante = 2, key = b[2]},
      {kind = 'boss', ante = 3, key = b[3], by = true}, ex(none)})
    log, ok, d = streams(function() return filter.eval(at(seed), f) end)
    H.eq(ok, true, seed); H.eq(d.checked, 5, seed)
    H.eq(count(log, 'boss'), 4, seed..': 4 antes, 4 draws')
    H.eq(d.results[1].key, b[4], seed); H.eq(d.results[2].ante, first, seed)
    H.eq(d.results[3].key, b[2], seed)
    local f3
    for a = 1, 3 do if b[a] == b[3] and not f3 then f3 = a end end
    H.eq(d.results[4].ante, f3, seed); H.eq(d.results[4].key, b[3], seed)
    -- The by clause's result beside the rest equals its result alone.
    local _, alone = filter.eval(at(seed), F({c}))
    deep_eq(d.results[2], alone.results[1], seed..' by beside plain')
  end
  H.ok(stopped > 0, 'a by clause stopped before N: '..stopped)
end)

H.test('boss by beside a legendary: the Soul\'s edition reads N, wherever the boss clause stopped', function()
  local filter, predict, state = mods()
  local at = seeder(state, world{edition_rate = 10})
  local moved = 0
  for i = 1, 150 do
    local seed = 'BLEG'..i
    local function leg(ante)
      local T = at(seed)
      T.game.round_resets.ante = ante
      return predict.legendaries(T, 2)[1]
    end
    local want = leg(3)
    if want.edition ~= leg(1).edition then moved = moved + 1 end
    local B = {kind = 'boss', ante = 3, key = predict.boss(at(seed), 1), by = true}
    local LE = {kind = 'legendary', index = 1}
    local ok, d = filter.eval(at(seed), F({B, LE}))
    H.eq(ok, true, seed); H.eq(d.results[1].ante, 1, seed)
    H.eq(d.results[2].key, want.key, seed); H.eq(d.results[2].edition, want.edition, seed..': edition of ante 3')
  end
  H.ok(moved > 0, 'the ante moves the edition on some seeds: '..moved)
end)

------------------------------------------------------------------------------
-- The research examples

H.test('"no Plant by ante 3" with a positive clause: the positive AND NOT the Plant (300 seeds)', function()
  local filter, _, state = mods()
  local R = route()
  local at = seeder(state, world())
  local NP = {kind = 'boss', ante = 3, key = 'bl_plant', by = true, exclude = true}
  local plant = copy(NP); plant.exclude = nil
  local SJ = {kind = 'shop_joker', ante = 1, key = 'j_joker', rerolls = 1}
  local f = F({SJ, NP})
  local seen = {hit = 0, plant = 0, no_joker = 0}
  for i = 1, 300 do
    local seed = 'NOPLANT'..i
    local pok, pd = filter.eval(at(seed), F({plant}))
    local sok, sd = filter.eval(at(seed), F({SJ}))
    local ok, d = filter.eval(at(seed), f)
    H.eq(ok, sok and not pok, seed)
    if pok then
      -- The boss class runs first: the Plant ends the eval, and says where.
      H.eq(d.checked, 1, seed); H.eq(d.results[1], nil, seed)
      deep_eq(d.results[2], {ok = false, ante = pd.results[1].ante, key = 'bl_plant'}, seed..' why not')
      seen.plant = seen.plant + 1
    else
      deep_eq(d.results[2], {ok = true}, seed)
      deep_eq(d.results[1], sd.results[1], seed..' shop_joker')
      if ok then
        -- The route is the shop_joker's alone; the must-not's N is no cost.
        local r = assert(R.build(f, d))
        deep_eq(r, assert(R.build(F({SJ}), sd)), seed..' route')
        H.eq(r.cost.ante, 1, seed)
        seen.hit = seen.hit + 1
      else
        seen.no_joker = seen.no_joker + 1
      end
    end
  end
  for k, v in pairs(seen) do H.ok(v > 0, 'saw '..k..': '..v) end
end)

-- The first (shop, reroll, slot) of an ante walk whose card is key and clean
-- (sticker none) or any copy (sticker nil), by hand.
local function shop_scan(walk, key, R, sticker)
  for s, sh in ipairs(walk.shops) do
    local rows = {sh.cards}
    for r = 1, R do rows[r + 1] = sh.rerolls[r].cards end
    for r, row in ipairs(rows) do
      for slot, x in ipairs(row) do
        if x.key == key and (sticker == nil or clean(x)) then return {ok = true, shop = s, reroll = r - 1, slot = slot} end
      end
    end
  end
  return {ok = false}
end

H.test('sticker none at stake 8, shop_joker: a stickered copy is skipped for a clean later one within the rerolls', function()
  local filter, predict, state = mods()
  local at = seeder(state, world{stake8 = true})
  local R = 4
  local keys = {'j_joker', 'j_greedy_joker', 'j_lusty_joker', 'j_blueprint'}
  local seen = {later = 0, all_stickered = 0, first_clean = 0, stickered = 0}
  for i = 1, 150 do
    local seed = 'STK'..i
    local w = predict.ante_walk(at(seed), 1, {rerolls = R, open = false})
    for _, sh in ipairs(w.shops) do
      for _, row in ipairs({sh.cards, sh.rerolls[1].cards}) do
        for _, x in ipairs(row) do if x.set == 'Joker' and not clean(x) then seen.stickered = seen.stickered + 1 end end
      end
    end
    for _, key in ipairs(keys) do
      local c = {kind = 'shop_joker', ante = 1, key = key, rerolls = R, sticker = 'none'}
      local any = copy(c); any.sticker = nil
      local want, first = shop_scan(w, key, R, 'none'), shop_scan(w, key, R, nil)
      local ok, d = filter.eval(at(seed), F({c}))
      local aok, ad = filter.eval(at(seed), F({any}))
      H.eq(ok, want.ok, seed..' '..key)
      deep_eq(d.results[1], want, seed..' '..key..' sticker none')
      deep_eq(ad.results[1], first, seed..' '..key..' any')
      if want.ok and (want.shop ~= first.shop or want.reroll ~= first.reroll or want.slot ~= first.slot) then
        seen.later = seen.later + 1
      elseif aok and not ok then
        seen.all_stickered = seen.all_stickered + 1
      elseif ok then
        seen.first_clean = seen.first_clean + 1
      end
    end
  end
  for k, v in pairs(seen) do H.ok(v > 0, 'saw '..k..': '..v) end
end)

-- The joker clause by hand (tests/test_filter.lua's joker_ref), with a
-- clean-card test when c.sticker is 'none'.
local function joker_ref(predict, T, c, R, opens)
  local from = c.from or 'both'
  local function match(x) return x.key == c.key and (c.sticker == nil or clean(x)) end
  for a = 1, c.ante do
    local w = predict.ante_walk(T, a, {rerolls = R, open = opens})
    for s, sh in ipairs(w.shops) do
      if from ~= 'buffoon' then
        local rows = {sh.cards}
        for r = 1, c.rerolls or 0 do rows[r + 1] = sh.rerolls[r].cards end
        for r, row in ipairs(rows) do
          for slot, x in ipairs(row) do
            if match(x) then return {ok = true, ante = a, shop = s, after = sh.after, reroll = r - 1, index = slot} end
          end
        end
      end
      if from ~= 'shop' then
        for j, p in ipairs(sh.packs) do
          if p.kind == 'Buffoon' then
            for k, x in ipairs(sh.contents[j]) do
              if match(x) then return {ok = true, ante = a, shop = s, after = sh.after, pack_slot = j, pack = p.key, index = k} end
            end
          end
        end
      end
    end
  end
  return {ok = false}
end

H.test('sticker none at stake 8, joker by ante N: rows and Buffoon packs skip stickered copies', function()
  local filter, predict, state = mods()
  local at = seeder(state, world{stake8 = true})
  local keys = {'j_joker', 'j_greedy_joker', 'j_ceremonial', 'j_blueprint'}
  local seen = {moved = 0, pack = 0, lost = 0}
  for i = 1, 40 do
    local seed = 'STKJ'..i
    for _, from in ipairs{'shop', 'buffoon', 'both'} do
      for _, key in ipairs(keys) do
        local c = {kind = 'joker', ante = 2, key = key, rerolls = 2, from = from, sticker = 'none'}
        local any = copy(c); any.sticker = nil
        local want = joker_ref(predict, at(seed), c, 2, from ~= 'shop')
        local first = joker_ref(predict, at(seed), any, 2, from ~= 'shop')
        local ok, d = filter.eval(at(seed), F({c}))
        H.eq(ok, want.ok, seed..' '..from..' '..key)
        deep_eq(d.results[1], want, seed..' '..from..' '..key)
        if want.ok and not (want.ante == first.ante and want.shop == first.shop and want.index == first.index
          and want.reroll == first.reroll and want.pack_slot == first.pack_slot) then
          seen.moved = seen.moved + 1
        end
        if want.ok and want.pack_slot then seen.pack = seen.pack + 1 end
        if first.ok and not want.ok then seen.lost = seen.lost + 1 end
      end
    end
  end
  for k, v in pairs(seen) do H.ok(v > 0, 'saw '..k..': '..v) end
end)

H.test('sticker none below Black Stake behaves exactly as without it (stake 1; shop_joker and joker)', function()
  local filter, predict, state = mods()
  local at = seeder(state, world())
  local keys = {'j_joker', 'j_greedy_joker', 'j_ceremonial', 'j_blueprint'}
  local hits = 0
  for i = 1, 150 do
    local seed = 'STK1_'..i
    -- No sticker at all on this stake's cards.
    local w = predict.ante_walk(at(seed), 1, {rerolls = 2})
    for _, sh in ipairs(w.shops) do
      for _, x in ipairs(sh.cards) do H.ok(clean(x), seed..': a stickered card at stake 1') end
    end
    for _, key in ipairs(keys) do
      for _, c in ipairs{{kind = 'shop_joker', ante = 1 + i % 2, key = key, rerolls = 3, sticker = 'none'},
        {kind = 'joker', ante = 2, key = key, rerolls = 1, sticker = 'none'}} do
        local any = copy(c); any.sticker = nil
        local log1, ok1, d1 = streams(function() return filter.eval(at(seed), F({c}, {stake = 1})) end)
        local log2, ok2, d2 = streams(function() return filter.eval(at(seed), F({any}, {stake = 1})) end)
        H.eq(ok1, ok2, seed); deep_eq(d1, d2, seed..' '..c.kind..' '..key); deep_eq(log1, log2, seed..' draws')
        if ok1 then hits = hits + 1 end
      end
    end
  end
  H.ok(hits > 0, 'hits: '..hits)
end)

------------------------------------------------------------------------------
-- Route, serialize, odds

H.test('route: excluded clauses add no step and no cost; the route is the positive clauses\' alone', function()
  local filter, _, state = mods()
  local R = route()
  local at = seeder(state, world())
  local compared, only = 0, 0
  local keys = {'j_joker', 'j_greedy_joker', 'j_ceremonial', 'j_blueprint'}
  for i = 1, 120 do
    local seed = 'NROUTE'..i
    for _, key in ipairs(keys) do
      local SJ = {kind = 'shop_joker', ante = 2, key = key, rerolls = 2}
      local pok, pd = filter.eval(at(seed), F({SJ}))
      -- Must-nots whose needs do not change the walk: per-ante and boss
      -- streams, and a shop_joker at the same ante asking no more rerolls.
      local other = key == 'j_joker' and 'j_lusty_joker' or 'j_joker'
      local f = F({SJ, ex({kind = 'voucher', ante = 3, key = 'v_hone', by = true}),
        ex({kind = 'boss', ante = 3, key = 'bl_plant', by = true}), ex({kind = 'tag', ante = 3, key = 'tag_uncommon'}),
        ex({kind = 'shop_joker', ante = 2, key = other, rerolls = 1})})
      local ok, d = filter.eval(at(seed), f)
      if ok then
        H.eq(pok, true, seed)
        deep_eq(d.results[1], pd.results[1], seed..' the same walk')
        local r = assert(R.build(f, d))
        deep_eq(r, assert(R.build(F({SJ}), pd)), seed..' '..key..' route')
        H.eq(r.cost.ante, 2, seed..': the must-nots at ante 3 cost nothing')
        compared = compared + 1
      end
    end
    -- Must-nots alone: a hit with no step, at ante 1, free.
    local fx = F({ex({kind = 'boss', ante = 3, key = 'bl_plant', by = true}), ex({kind = 'joker', ante = 2, key = 'j_blueprint'})})
    local ok, d = filter.eval(at(seed), fx)
    if ok then
      deep_eq(assert(R.build(fx, d)), {steps = {}, cost = {ante = 1, rerolls = 0, dollars = 0}}, seed..' must-nots alone')
      only = only + 1
    else
      local r, err = R.build(fx, d)
      H.eq(r, nil); H.eq(err, 'not a hit')
    end
  end
  H.ok(compared > 0 and only > 0, 'routes compared: '..compared..', must-not-only hits: '..only)
  -- Hand-built details: an excluded clause's result is never read, whatever
  -- it holds (no buy step for the pack it names, no Soul taken).
  local f = F({{kind = 'shop_joker', ante = 1, key = 'j_joker'}, ex({kind = 'pack', ante = 1, key_prefix = 'p_buffoon'}),
    ex({kind = 'soul_in_pack', ante = 1, pack = 'arcana'})})
  local d = {checked = 3, results = {{ok = true, shop = 1, reroll = 0, slot = 1},
    {ok = true, shop = 1, slot = 2, pack = 'p_buffoon_normal_1'}, {ok = true, shop = 1, slot = 1, pack = 'p_arcana_normal_1', index = 2}}}
  local r = assert(R.build(f, d))
  H.eq(#r.steps, 1); H.eq(r.steps[1].action, 'play'); H.eq(r.cost.dollars, 0); H.eq(r.cost.rerolls, 0)
  -- A failed must-not is no hit.
  d.results[2].ok = false
  local none, err = R.build(f, d)
  H.eq(none, nil); H.eq(err, 'not a hit')
  -- An excluded from_tag clause still chains its ante: the route skips the
  -- pack-tag blinds before its target shop and takes nothing from the packs.
  local cat = seeder(state, world{tags = {'tag_charm', 'tag_juggle'}})
  local chained = 0
  for i = 1, 60 do
    local seed = 'NCHAIN'..i
    local fc = F({{kind = 'shop_joker', ante = 2, key = 'j_joker', rerolls = 1},
      ex({kind = 'soul_in_pack', ante = 2, pack = 'arcana', from_tag = true})})
    local cok, cd = filter.eval(cat(seed), fc)
    if cok then
      H.ok(cd.tag_packs and cd.tag_packs[2], seed..': ante 2 chained')
      local rc = assert(R.build(fc, cd))
      for _, st in ipairs(rc.steps) do
        if st.action == 'skip' then chained = chained + 1 end
        if st.action == 'open_pack' then H.eq(st.index, nil, seed..': nothing taken') end
      end
    end
  end
  H.ok(chained > 0, 'a route skipped a pack-tag blind for an excluded from_tag clause: '..chained)
end)

H.test('serialize / deserialize round-trip exclude, boss by and sticker; bad values refused on load', function()
  local filter, _, state = mods()
  local at = seeder(state, world{stake8 = true})
  local f = F({
    {kind = 'shop_joker', ante = 1, key = 'j_joker', rerolls = 2, sticker = 'none'},
    {kind = 'boss', ante = 3, key = 'bl_plant', by = true, exclude = true},
    {kind = 'voucher', ante = 2, key = 'v_hone', exclude = false},
    grp({kind = 'joker', ante = 2, key = 'j_blueprint', sticker = 'none', edition = 'any'}, {kind = 'boss', ante = 2, key = 'bl_hook', by = true}),
    {kind = 'tag', ante = 1, key = 'tag_charm', exclude = true},
  }, {stake = 8})
  local s = assert(filter.serialize(f))
  local back = assert(filter.deserialize(s))
  deep_eq(back, f, 'round-trip')
  H.eq(back.clauses[2].exclude, true); H.eq(back.clauses[3].exclude, false); H.eq(back.clauses[4].clauses[1].sticker, 'none')
  for i = 1, 30 do
    local seed = 'NSER'..i
    local ok1, d1 = filter.eval(at(seed), f)
    local ok2, d2 = filter.eval(at(seed), back)
    H.eq(ok1, ok2, seed); deep_eq(d1, d2, seed)
  end
  local bad = s:gsub('%["exclude"%]=true', '["exclude"]=1', 1)
  H.ok(bad ~= s, 'the packed string names exclude')
  local none, err = filter.deserialize(bad)
  H.eq(none, nil); H.ok(err:find('exclude must be a boolean', 1, true), tostring(err))
  bad = s:gsub('"none"', '"eternal"', 1)
  H.ok(bad ~= s, 'the packed string names the sticker')
  none, err = filter.deserialize(bad)
  H.eq(none, nil); H.ok(err:find('sticker must be none', 1, true), tostring(err))
  -- The same filter in mode any is invalid (its must-nots), so it never packs.
  local fa = F(f.clauses, {mode = 'any'})
  none, err = filter.serialize(fa)
  H.eq(none, nil); H.ok(err:find('exclude needs mode all', 1, true), tostring(err))
end)

H.test('odds.sample counts an excluded clause as its own one-clause filter, unchanged', function()
  local filter, _, state = mods()
  local odds = require('seedfinder.odds')
  local at = seeder(state, world())
  local function eval(f1, seed) return filter.eval(at(seed), f1) end
  local NP = {kind = 'boss', ante = 3, key = 'bl_plant', by = true, exclude = true}
  local plant = copy(NP); plant.exclude = nil
  local SJ = {kind = 'shop_joker', ante = 1, key = 'j_joker', rerolls = 1}
  local f = F({SJ, NP})
  local seeds = {}
  for i = 1, 120 do seeds[i] = 'NODDS'..i end
  local counts = odds.sample(f, seeds, eval)
  H.eq(#counts.clauses, 2)
  local sj, pl, full = 0, 0, 0
  for _, seed in ipairs(seeds) do
    if eval(F({SJ}), seed) then sj = sj + 1 end
    if eval(F({plant}), seed) then pl = pl + 1 end
    if eval(f, seed) then full = full + 1 end
  end
  H.eq(counts.clauses[1], sj); H.eq(counts.clauses[2], #seeds - pl, 'the must-not passes where the Plant is absent')
  H.eq(counts.full, full)
  H.ok(pl > 0 and pl < #seeds, 'the Plant both shows and does not: '..pl)
  local est = assert(odds.estimate(counts))
  H.eq(est.per_clause[2], (#seeds - pl) / #seeds)
end)
