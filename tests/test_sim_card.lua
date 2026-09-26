-- sim/card.lua: the draw order of the create_card twin, stickers, soul gating,
-- used_jokers bookkeeping and the shop type roll.
-- Runs on vanilla's own RNG and pool primitives (misc_functions.lua and
-- common_events.lua loaded from build/game) over a small stub prototype set.
-- The expected stream sequences below are read off common_events.lua:2082-2154;
-- the real-game differential is rig/scenarios/sim_card_diff.lua.
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
  local C = {
    j_joker = center('j_joker', {name = 'Joker', set = 'Joker', rarity = 1, order = 1, eternal_compat = true, perishable_compat = true}),
    j_greedy = center('j_greedy_joker', {name = 'Greedy Joker', set = 'Joker', rarity = 1, order = 2, eternal_compat = true, perishable_compat = true}),
    j_todo = center('j_todo_list', {name = 'To Do List', set = 'Joker', rarity = 1, order = 3, eternal_compat = true, perishable_compat = true}),
    j_gros = center('j_gros_michel', {name = 'Gros Michel', set = 'Joker', rarity = 1, order = 4, eternal_compat = false, perishable_compat = true}),
    j_ceremonial = center('j_ceremonial', {name = 'Ceremonial Dagger', set = 'Joker', rarity = 2, order = 5, eternal_compat = true, perishable_compat = false}),
    j_ring_master = center('j_ring_master', {name = 'Showman', set = 'Joker', rarity = 2, order = 6, eternal_compat = true, perishable_compat = true}),
    j_blueprint = center('j_blueprint', {name = 'Blueprint', set = 'Joker', rarity = 3, order = 7, eternal_compat = true, perishable_compat = true}),
    j_caino = center('j_caino', {name = 'Caino', set = 'Joker', rarity = 4, order = 8, unlocked = false, eternal_compat = true, perishable_compat = true}),
    j_yorick = center('j_yorick', {name = 'Yorick', set = 'Joker', rarity = 4, order = 9, eternal_compat = true, perishable_compat = true}),
    c_fool = center('c_fool', {name = 'The Fool', set = 'Tarot', order = 1, consumeable = true}),
    c_magician = center('c_magician', {name = 'The Magician', set = 'Tarot', order = 2, consumeable = true}),
    c_strength = center('c_strength', {name = 'Strength', set = 'Tarot', order = 3, consumeable = true}),
    c_pluto = center('c_pluto', {name = 'Pluto', set = 'Planet', order = 1, consumeable = true, config = {hand_type = 'High Card'}}),
    c_mercury = center('c_mercury', {name = 'Mercury', set = 'Planet', order = 2, consumeable = true, config = {hand_type = 'Pair'}}),
    c_familiar = center('c_familiar', {name = 'Familiar', set = 'Spectral', order = 1, consumeable = true}),
    c_soul = center('c_soul', {name = 'The Soul', set = 'Spectral', order = 17, consumeable = true, hidden = true}),
    c_black_hole = center('c_black_hole', {name = 'Black Hole', set = 'Spectral', order = 18, consumeable = true, hidden = true}),
    c_base = center('c_base', {name = 'Default Base', set = 'Default', order = 1}),
    m_bonus = center('m_bonus', {name = 'Bonus', set = 'Enhanced', order = 2}),
    m_mult = center('m_mult', {name = 'Mult', set = 'Enhanced', order = 3}),
  }
  -- vanilla keys the table by key
  local P = {}
  for _, c in pairs(C) do P[c.key] = c end
  G.P_CENTERS = P
  local function pool(set)
    local out = {}
    for _, c in pairs(P) do if c.set == set then out[#out + 1] = c end end
    table.sort(out, function(a, b) return a.order < b.order end)
    return out
  end
  G.P_CENTER_POOLS = {Joker = pool('Joker'), Tarot = pool('Tarot'), Planet = pool('Planet'),
    Spectral = pool('Spectral'), Enhanced = pool('Enhanced')}
  G.P_JOKER_RARITY_POOLS = {{}, {}, {}, {}}
  for _, c in ipairs(G.P_CENTER_POOLS.Joker) do table.insert(G.P_JOKER_RARITY_POOLS[c.rarity], c) end
  G.P_CARDS = {H_2 = {suit = 'Hearts', value = '2'}, S_A = {suit = 'Spades', value = 'Ace'},
    D_K = {suit = 'Diamonds', value = 'King'}}
  G.jokers = {cards = {}, config = {card_limit = 5}}
  G.consumeables = {cards = {}, config = {card_limit = 2}}
  local game = {
    round_resets = {ante = o.ante or 1},
    pseudorandom = {seed = o.seed or 'TESTSEED', hashed_seed = pseudohash(o.seed or 'TESTSEED')},
    used_jokers = {}, used_vouchers = o.vouchers or {}, banned_keys = {}, pool_flags = {},
    hands = {['High Card'] = {played = 0, visible = true}, Pair = {played = 0, visible = true}},
    modifiers = o.modifiers or {}, edition_rate = 1,
    joker_rate = 20, tarot_rate = 4, planet_rate = 4, playing_card_rate = 0, spectral_rate = 0,
  }
  local card = require('bhcore.sim.card')
  local sandbox = require('bhcore.sim.sandbox')
  local S = {game = game}
  -- Runs fn in the sandbox, recording every stream key pseudoseed advances.
  local function run(fn)
    local real = pseudoseed
    local log = {}
    pseudoseed = function(k, p) log[#log + 1] = k; return real(k, p) end
    local res = {sandbox.run(S, fn)}
    pseudoseed = real
    if not res[1] then error(res[2], 2) end
    return res[2], log
  end
  return card, run, S
end

local function seq(log) return table.concat(log, ' ') end
-- The draws every card of that kind makes: drops pool resamples (a pool holds
-- UNAVAILABLE slots, e.g. Soul and Black Hole in Spectral) and To Do List's draw.
local function core(log)
  local out = {}
  for _, k in ipairs(log) do
    if not k:find('_resample%d+$') and k ~= 'to_do' then out[#out + 1] = k end
  end
  return seq(out)
end

H.test('create outside sandbox.run is refused', function()
  local card = world()
  local ok, err = pcall(card.create, {type = 'Joker'})
  H.eq(ok, false)
  H.ok(tostring(err):find('sandbox'), tostring(err))
end)

H.test('shop Joker at White stake: rarity, pool, etperpoll, edition; no ssjr', function()
  local card, run = world()
  local c, log = run(function() return card.create{type = 'Joker', area = 'shop', key_append = 'sho'} end)
  local r = log[2]:match('^Joker(%d)sho1$')
  H.ok(r, 'pool key '..seq(log))
  H.eq(seq(log), 'rarity1sho Joker'..r..'sho1 etperpoll1 edisho1')
  H.eq(c.set, 'Joker'); H.eq(G.P_CENTERS[c.key].rarity, tonumber(r))
  H.ok(not c.stickers.eternal and not c.stickers.perishable and not c.stickers.rental, 'no stickers at white')
end)

H.test('Gold stake draws ssjr after etperpoll; packs use packetper/packssjr', function()
  local card, run = world{modifiers = {enable_eternals_in_shop = true,
    enable_perishables_in_shop = true, enable_rentals_in_shop = true}}
  local _, log = run(function() return card.create{type = 'Joker', area = 'shop', key_append = 'sho'} end)
  H.eq(core(log):match('etperpoll.*$'), 'etperpoll1 ssjr1 edisho1')
  local _, log2 = run(function() return card.create{type = 'Joker', area = 'pack', soulable = true, key_append = 'buf'} end)
  local pool = log2[2]:match('^Joker%dbuf1$')
  H.ok(pool, seq(log2))
  H.eq(core(log2), 'rarity1buf '..pool..' packetper1 packssjr1 edibuf1', 'a soulable Joker has no soul roll')
end)

H.test('stickers honour compat flags and never stack eternal with perishable', function()
  local card, run = world{modifiers = {enable_eternals_in_shop = true,
    enable_perishables_in_shop = true, enable_rentals_in_shop = true}}
  local n = {eternal = 0, perishable = 0, rental = 0}
  run(function()
    for _ = 1, 600 do
      local c = card.create{type = 'Joker', area = 'shop', key_append = 'sho'}
      card.release(c.key)
      local s = c.stickers
      H.ok(not (s.eternal and s.perishable), 'eternal and perishable on '..c.key)
      if s.eternal then H.ok(G.P_CENTERS[c.key].eternal_compat, 'eternal on non-compat '..c.key) end
      if s.perishable then H.ok(G.P_CENTERS[c.key].perishable_compat, 'perishable on non-compat '..c.key) end
      for k, v in pairs(s) do if v then n[k] = n[k] + 1 end end
    end
  end)
  H.ok(n.eternal > 60 and n.perishable > 60 and n.rental > 60,
    string.format('stickers seen: e%d p%d r%d', n.eternal, n.perishable, n.rental))
end)

H.test('all_eternal marks compat jokers eternal anywhere, without a sticker poll outside shop/pack', function()
  local card, run = world{modifiers = {all_eternal = true}}
  local c, log = run(function() return card.create{type = 'Joker', area = 'other', forced_key = 'j_joker'} end)
  H.eq(c.stickers.eternal, true)
  H.eq(seq(log), 'edi1', 'forced joker: edition only')
  local g = run(function() return card.create{type = 'Joker', area = 'other', forced_key = 'j_gros_michel'} end)
  H.eq(g.stickers.eternal, false, 'Gros Michel is not eternal_compat')
end)

H.test('soulable Tarot, Planet and Spectral: soul draws and the Spectral double draw', function()
  local card, run = world()
  local _, t = run(function() return card.create{type = 'Tarot', area = 'pack', soulable = true, key_append = 'ar1'} end)
  H.eq(seq(t), 'soul_Tarot1 Tarotar11')
  local _, p = run(function() return card.create{type = 'Planet', area = 'pack', soulable = true, key_append = 'pl1'} end)
  H.eq(seq(p), 'soul_Planet1 Planetpl11')
  local _, s = run(function() return card.create{type = 'Spectral', area = 'pack', soulable = true, key_append = 'spe'} end)
  H.eq(core(s), 'soul_Spectral1 soul_Spectral1 Spectralspe1')
  local _, n = run(function() return card.create{type = 'Tarot', area = 'shop', key_append = 'sho'} end)
  H.eq(core(n), 'Tarotsho1', 'not soulable: no soul roll')
end)

H.test('soul gating: a used Soul skips its roll unless Showman is held', function()
  local card, run, S = world()
  S.game.used_jokers.c_soul = true
  local _, a = run(function() return card.create{type = 'Spectral', area = 'pack', soulable = true, key_append = 'spe'} end)
  H.eq(core(a), 'soul_Spectral1 Spectralspe1', 'black hole roll only')
  local _, b = run(function()
    G.jokers.cards[1] = {ability = {name = 'Showman'}}
    return card.create{type = 'Spectral', area = 'pack', soulable = true, key_append = 'spe'}
  end)
  H.eq(core(b), 'soul_Spectral1 soul_Spectral1 Spectralspe1', 'Showman restores both rolls')
  S.game.banned_keys.c_soul = true
  local _, c = run(function() return card.create{type = 'Planet', area = 'pack', soulable = true, key_append = 'pl1'} end)
  H.eq(core(c), 'Planetpl11', 'banned c_soul skips every soul roll')
end)

H.test('a forced key skips the soul roll and the pool draw (Telescope)', function()
  local card, run, S = world()
  local c, log = run(function()
    return card.create{type = 'Planet', area = 'pack', soulable = true, forced_key = 'c_mercury', key_append = 'pl1'}
  end)
  H.eq(c.key, 'c_mercury'); H.eq(#log, 0, seq(log))
  H.eq(S.game.pseudorandom.Planetpl11, nil, 'Planetpl1 not advanced')
end)

H.test('a Soul hit is forced to c_soul and recorded in used_jokers', function()
  -- pick a seed whose first soul_Tarot1 roll hits (pseudoseed's pure predict mode)
  world()
  local seed
  for i = 1, 20000 do
    if pseudorandom(pseudoseed('soul_Tarot1', 'SOUL'..i)) > 0.997 then seed = 'SOUL'..i; break end
  end
  H.ok(seed, 'no soul seed found')
  local card, run, S = world{seed = seed}
  local c, log = run(function() return card.create{type = 'Tarot', area = 'pack', soulable = true, key_append = 'ar1'} end)
  H.eq(c.key, 'c_soul'); H.eq(c.set, 'Spectral'); H.eq(c.type, 'Spectral')
  H.eq(seq(log), 'soul_Tarot1', 'no pool draw after the forced Soul')
  H.eq(S.game.used_jokers.c_soul, true)
  local _, again = run(function() return card.create{type = 'Tarot', area = 'pack', soulable = true, key_append = 'ar1'} end)
  H.eq(core(again), 'Tarotar11', 'second card of the pack: Soul gated out')
end)

H.test('legendary: rarity still drawn, Joker4 global pool, locked legendaries allowed', function()
  local card, run = world{ante = 3}
  local seen = {}
  local c, log = run(function()
    local first = card.create{type = 'Joker', area = 'other', legendary = true, key_append = 'sou'}
    card.release(first.key)
    for _ = 1, 40 do
      local x = card.create{type = 'Joker', area = 'other', legendary = true, key_append = 'sou'}
      seen[x.key] = true
      card.release(x.key)
    end
    return first
  end)
  H.eq(table.concat({log[1], log[2], log[3]}, ' '), 'rarity3sou Joker4 edisou3')
  H.eq(G.P_CENTERS[c.key].rarity, 4)
  H.ok(seen.j_caino and seen.j_yorick, 'both legendaries, locked Caino included')
end)

H.test('Base and Enhanced cards draw a front; Base is c_base with no pool draw', function()
  local card, run, S = world()
  local b, lb = run(function() return card.create{type = 'Base', area = 'pack', soulable = true, key_append = 'sta'} end)
  H.eq(b.key, 'c_base'); H.eq(b.type, 'Base'); H.ok(G.P_CARDS[b.front], 'front key')
  H.eq(seq(lb), 'frontsta1')
  H.eq(S.game.used_jokers.c_base, true, 'set_ability records even c_base')
  local e, le = run(function() return card.create{type = 'Enhanced', area = 'pack', soulable = true, key_append = 'sta'} end)
  H.eq(e.set, 'Enhanced'); H.ok(G.P_CARDS[e.front])
  H.eq(core(le), 'Enhancedsta1 frontsta1')
  H.eq(e.edition, nil, 'only Jokers poll an edition in create_card')
end)

H.test('To Do List consumes one to_do draw after its pool draw', function()
  local card, run = world()
  local _, log = run(function() return card.create{type = 'Joker', area = 'shop', forced_key = 'j_todo_list', key_append = 'sho'} end)
  H.eq(seq(log), 'to_do etperpoll1 edisho1')
end)

H.test('used_jokers: no duplicates in a pack without Showman, duplicates with it; release', function()
  local card, run, S = world()
  local keys = run(function()
    local out = {}
    for i = 1, 3 do out[i] = card.create{type = 'Tarot', area = 'pack', soulable = true, key_append = 'ar1'}.key end
    return out
  end)
  H.ok(keys[1] ~= keys[2] and keys[2] ~= keys[3] and keys[1] ~= keys[3], 'distinct: '..table.concat(keys, ','))
  H.ok(S.game.used_jokers[keys[1]] and S.game.used_jokers[keys[3]], 'recorded')
  run(function() for _, k in ipairs(keys) do card.release(k) end end)
  H.eq(next(S.game.used_jokers), nil, 'released')
  local dup = run(function()
    G.jokers.cards[1] = {ability = {name = 'Showman'}}
    local seen, d = {}, 0
    for _ = 1, 12 do
      local k = card.create{type = 'Tarot', area = 'pack', soulable = true, key_append = 'ar1'}.key
      if seen[k] then d = d + 1 end
      seen[k] = true
    end
    -- a held copy keeps the key on release
    G.consumeables.cards[1] = {ability = {name = 'The Fool'}}
    card.release('c_fool')
    return d
  end)
  H.ok(dup > 0, 'Showman allows duplicates')
  H.eq(S.game.used_jokers.c_fool, true, 'held Fool keeps its used_jokers entry')
end)

-- Changed after the wave-B review: the sim models the game's state (no overlay while
-- shops and packs generate), not the live UI's. A SeedOracle overlay or pause menu must
-- not disable duplicate exclusion, so a live overlay no longer suppresses used_jokers.
H.test('used_jokers is recorded even while a live overlay menu is up', function()
  local card, run, S = world()
  G.OVERLAY_MENU = {}
  local key
  run(function() key = card.create{type = 'Tarot', area = 'shop', key_append = 'sho'}.key end)
  G.OVERLAY_MENU = nil
  H.eq(S.game.used_jokers[key], true)
end)

H.test('resamples walk _resample2.. until an available key', function()
  local card, run, S = world()
  S.game.used_jokers.c_fool, S.game.used_jokers.c_magician = true, true
  local saw_resample = false
  run(function()
    for _ = 1, 30 do
      local c = card.create{type = 'Tarot', area = 'shop', key_append = 'sho'}
      H.eq(c.key, 'c_strength', 'only Strength is available')
      card.release(c.key)
    end
  end)
  for k in pairs(S.game.pseudorandom) do if k:find('Tarotsho1_resample', 1, true) then saw_resample = true end end
  H.ok(saw_resample, 'resample streams used')
end)

H.test('shop_type: cdt then illusion; Illusion draws twice more for playing cards', function()
  local card, run, S = world{vouchers = {v_illusion = true}}
  S.game.joker_rate, S.game.tarot_rate, S.game.planet_rate, S.game.playing_card_rate = 0, 0, 0, 4
  local t, log = run(function() return card.shop_type() end)
  H.eq(seq(log), 'cdt1 illusion')
  H.ok(t == 'Base' or t == 'Enhanced', tostring(t))
  local eds = 0
  run(function()
    for _ = 1, 200 do
      local c = card.shop_card()
      if c.edition then eds = eds + 1 end
      card.release(c.key)
    end
  end)
  H.ok(S.game.pseudorandom.illusion ~= nil and eds > 10 and eds < 120, 'illusion editions: '..eds)
  local card2, run2, S2 = world()
  S2.game.joker_rate = 0
  local _, log2 = run2(function() return card2.shop_card() end)
  H.eq(log2[1], 'cdt1'); H.ok(log2[2] == 'Tarotsho1' or log2[2] == 'Planetsho1', seq(log2))
end)
