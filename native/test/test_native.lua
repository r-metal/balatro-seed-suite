-- native/test/test_native.lua: `make -C native test`. The C port against
-- vanilla's own Lua (build/game, loaded unmodified) under the system luajit.
--
--   1. bh_round13 vs tonumber(string.format('%.13f', x)): random [0, 1)
--      values, every half-way case j/16384 (odd j) and edge values.
--   2. bh_pseudohash vs pseudohash: random strings, bytes 1..255.
--   3. bh_randomseed/bh_random vs math.randomseed/math.random, and
--      math.random(n), over random seeds (LuaJIT's TW223).
--   4. bh_stable_batch vs a Lua walk calling vanilla get_new_boss,
--      get_next_voucher_key, get_next_tag_key, get_current_pool +
--      pseudorandom_element (the Soul) and poll_edition, on SYNTHETIC pools
--      (made-up keys: resamples, min_ante, requires, showdown, a banned key,
--      more Souls than legendaries). The real pools are the rig's job
--      (rig/scenarios/native_diff.lua).
--   5. bh_shop_batch vs bhcore.sim.predict.ante_walk (mods/bh-core, loaded
--      as-is, driving vanilla get_current_pool / get_pack / poll_edition) on
--      SYNTHETIC shop pools: locked and banned entries (resamples), two jokers
--      sharing a name, pool flags, a softlocked planet, Soul / Black Hole in
--      tiny pools (frequent soul rolls), every booster kind, Charm / Ethereal
--      tag packs; every skip policy x rerolls 0 and 2, antes 1-3, a plain
--      config and one with stickers, all_eternal, Illusion, Omen Globe,
--      Telescope, edition_rate 2, banned Black Hole / booster / joker, a used
--      joker and The Soul at the start and the first Buffoon already given,
--      and one with Black Hole used and the forced Buffoon banned. The real pools
--      are rig/scenarios/native_diff_shop.lua's job.
-- Prints one line per group and a tally; exits 1 on any difference.
local ROOT = assert(arg[1], 'usage: luajit native/test/test_native.lua <repo root>')
local bhsim = dofile(ROOT..'/native/lua/bhsim.lua')
local lib = bhsim.load(ROOT)
local ffi = require('ffi')

G = {ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_JOKER_RARITY_POOLS = {}, P_BLINDS = {},
  jokers = {cards = {}}, consumeables = {cards = {}}}
for _, f in ipairs{'functions/misc_functions.lua', 'functions/common_events.lua'} do
  local chunk = loadfile(ROOT..'/build/game/'..f)
  if not chunk then print('native test: build/game missing (make game-src)'); os.exit(1) end
  chunk()
end

local failed, groups = 0, 0
local function report(name, n, bad, first)
  groups = groups + 1
  if bad > 0 then
    failed = failed + 1
    print(('native test FAIL %s: %d of %d differ; first: %s'):format(name, bad, n, first))
  else
    print(('native test ok %s: %d checked'):format(name, n))
  end
end

math.randomseed(1234)
local R = {} -- test inputs drawn up front: the checks below reseed math.random
for i = 1, 200000 do R[i] = math.random() end

-- 1. %.13f
do
  local bad, first, n = 0, nil, 0
  local function check(x)
    n = n + 1
    local want = tonumber(string.format('%.13f', x))
    local got = lib.bh_round13(x)
    if want ~= got then bad = bad + 1; first = first or ('%.17g -> %.17g vs %.17g'):format(x, got, want) end
  end
  for i = 1, #R do check(R[i]) end
  for j = 1, 16383, 2 do check(j / 16384) end
  for _, x in ipairs{0, 1e-14, 4.9999999999999e-14, 5e-14, 5.0000000000001e-14, 0.99999999999995,
    0.9999999999999, 1 - 2 ^ -53, 2 ^ -60, 0.5, 0.25} do check(x) end
  report('round13', n, bad, first)
  -- The other tie rule (LÖVE 11.5's LuaJIT when this host rounds to even, and
  -- the reverse): only the half-way cases move, each to the other neighbour.
  local away = not bhsim.TIES_AWAY
  lib.bh_set_round_ties(away and 1 or 0)
  bad, first, n = 0, nil, 0
  for j = 1, 16383, 2 do
    n = n + 1
    local q = j * 1e13 / 16384 -- exact: an odd multiple of 0.5 below 2^53
    local want = (away and math.floor(q) + 1 or (math.floor(q) % 2 == 0 and math.floor(q) or math.floor(q) + 1)) / 1e13
    local got = lib.bh_round13(j / 16384)
    if got ~= want then bad = bad + 1; first = first or ('%d/16384 -> %.17g vs %.17g'):format(j, got, want) end
  end
  for i = 1, 20000 do
    n = n + 1
    if lib.bh_round13(R[i]) ~= tonumber(string.format('%.13f', R[i])) then bad = bad + 1; first = first or 'non-tie moved' end
  end
  lib.bh_set_round_ties(bhsim.TIES_AWAY and 1 or 0)
  report(away and 'round13_ties_away' or 'round13_ties_even', n, bad, first)
end

-- 2. pseudohash
do
  local bad, first = 0, nil
  local n = 50000
  for i = 1, n do
    local len = 1 + (i % 24)
    local b = {}
    for j = 1, len do b[j] = string.char(1 + math.floor(R[(i * 31 + j) % #R + 1] * 255)) end
    local s = table.concat(b)
    local want, got = pseudohash(s), lib.bh_pseudohash(s, #s)
    if want ~= got then bad = bad + 1; first = first or ('%q: %.17g vs %.17g'):format(s, got, want) end
  end
  report('pseudohash', n, bad, first)
end

-- 3. TW223
do
  local bad, first, n = 0, nil, 0
  local rs = ffi.new('bh_prng')
  for i = 1, 50000 do
    local seed = R[i] * (i % 3 == 0 and 1 or 1e6)
    math.randomseed(seed)
    local w1, w2, w3 = math.random(), math.random(), math.random(37)
    lib.bh_randomseed(rs, seed)
    local g1, g2 = lib.bh_random(rs), lib.bh_random(rs)
    local g3 = math.floor(lib.bh_random(rs) * 37) + 1
    n = n + 3
    if w1 ~= g1 or w2 ~= g2 or w3 ~= g3 then
      bad = bad + 1; first = first or ('seed %.17g: %.17g %.17g %d vs %.17g %.17g %d'):format(seed, g1, g2, g3, w1, w2, w3)
    end
  end
  report('tw223', n, bad, first)
end

-- 4. synthetic walk
local ANTES = 8
local function synthetic(opts)
  local C, P = {}, {}
  local function center(key, t) t.key = key; C[key] = t; return t end
  P.Tag = {}
  for i = 1, 24 do
    local t = center(('tag_t%02d'):format(i), {set = 'Tag'})
    if i % 5 == 0 then t.min_ante = 2 + (i % 3) end
    if i % 7 == 0 then t.requires = ('j_req%d'):format(i) end
    P.Tag[i] = t
  end
  center('j_req7', {set = 'Joker', discovered = true})
  center('j_req14', {set = 'Joker', discovered = false})
  center('j_req21', {set = 'Joker', discovered = true})
  P.Voucher = {}
  for i = 1, 32 do
    local v = center(('v_v%02d'):format(i), {set = 'Voucher', unlocked = i % 9 ~= 0})
    if i % 2 == 0 then v.requires = {('v_v%02d'):format(i - 1)} end
    P.Voucher[i] = v
  end
  local legend = {}
  for i = 1, 5 do legend[i] = center(('j_leg%d'):format(i), {set = 'Joker', rarity = 4, unlocked = false, name = 'leg'..i}) end
  center('j_joker', {set = 'Joker', rarity = 1, name = 'Joker'})
  local blinds = {}
  for i = 1, 20 do
    blinds[('bl_b%02d'):format(i)] = {boss = {min = 1 + (i % 6), showdown = i > 15 or nil}}
  end
  blinds.bl_small, blinds.bl_big = {}, {}
  G.P_CENTERS, G.P_CENTER_POOLS, G.P_BLINDS = C, P, blinds
  G.P_JOKER_RARITY_POOLS = {{}, {}, {}, legend}
  local banned = opts.banned or {}
  return function(seed)
    local used = {}
    for k, v in pairs(blinds) do if v.boss then used[k] = 0 end end
    G.GAME = {win_ante = 8, edition_rate = opts.edition_rate or 1, banned_keys = banned,
      bosses_used = used, pool_flags = {}, used_jokers = {}, used_vouchers = {v_v01 = true},
      round_resets = {ante = 1},
      pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)}}
  end
end

local function soul()
  local pool, key = get_current_pool('Joker', nil, true, 'sou')
  local k = pseudorandom_element(pool, pseudoseed(key))
  local it = 1
  while k == 'UNAVAILABLE' do
    it = it + 1
    k = pseudorandom_element(pool, pseudoseed(key..'_resample'..it))
  end
  G.GAME.used_jokers[k] = true
  local e = poll_edition('edisou'..G.GAME.round_resets.ante)
  local ed = 'none'
  for _, name in ipairs{'negative', 'polychrome', 'holo', 'foil'} do if e and e[name] then ed = name end end
  return k, ed
end

local function lua_walk(seed, fresh)
  fresh(seed)
  local out = {}
  for a = 1, ANTES do
    G.GAME.round_resets.ante = a
    local boss, v, s, b
    if a == 1 then boss = get_new_boss() end
    v = get_next_voucher_key()
    s, b = get_next_tag_key(), get_next_tag_key()
    if a > 1 then boss = get_new_boss() end
    local lk, ed = soul()
    out[a] = {s, b, boss, v, lk, ed}
  end
  return out
end

for _, cfg in ipairs{{name = 'walk', seeds = 2000},
    {name = 'walk_banned_rate2', seeds = 500, edition_rate = 2, banned = {bl_b03 = true, tag_t02 = true, v_v05 = true}}} do
  local fresh = synthetic(cfg)
  fresh('AAAAAAAA')
  local ctx = bhsim.context(lib, ANTES)
  -- An LCG (as the shop group below): the old (i*7 + j*13 + i*j) % 34 formula
  -- had a short period, so 20,000 'seeds' were ~2,000 distinct ones.
  local seeds, seen, x = {}, {}, 20260924
  while #seeds < cfg.seeds do
    local b = {}
    for j = 1, 8 do
      x = (x * 1103515245 + 12345) % 2147483648
      local d = 1 + math.floor(x / 65536) % 34
      b[j] = ('123456789ABCDEFGHIJKLMNPQRSTUVWXYZ'):sub(d, d)
    end
    local seed = table.concat(b)
    if not seen[seed] then seen[seed] = true; seeds[#seeds + 1] = seed end
  end
  local out = bhsim.walk(ctx, seeds, ANTES)
  local bad, first, n = 0, nil, 0
  for i, seed in ipairs(seeds) do
    local want = lua_walk(seed, fresh)
    for a = 1, ANTES do
      local got = {bhsim.record(ctx, out, i, a)}
      for f = 1, 6 do
        n = n + 1
        if got[f] ~= want[a][f] then
          bad = bad + 1
          first = first or ('%s ante %d field %d: %s vs %s'):format(seed, a, f, tostring(got[f]), tostring(want[a][f]))
        end
      end
    end
  end
  report(cfg.name, n, bad, first)
end

-- 5. synthetic shop walk
do
  local SRC = ROOT..'/mods/bh-core/src/sim/'
  for _, m in ipairs{'sandbox', 'card', 'state', 'predict'} do
    package.preload['bhcore.sim.'..m] = assert(loadfile(SRC..m..'.lua'))
  end
  BHCore = {sim_depth = 0}
  local predict = require('bhcore.sim.predict')
  local SANTES = 3

  local function shop_world(opts)
    local C, P = {}, {}
    local function center(key, t) t.key = key; t.config = t.config or {}; C[key] = t; return t end
    local rarity = {{}, {}, {}, {}}
    for r = 1, 3 do
      for i = 1, ({14, 9, 5})[r] do
        local key = ('j_r%d_%02d'):format(r, i)
        local j = center(key, {set = 'Joker', rarity = r, name = key, unlocked = (i % 4 ~= 0),
          eternal_compat = i % 3 ~= 0, perishable_compat = i % 2 == 0})
        rarity[r][i] = j
      end
    end
    rarity[1][2].name, rarity[1][3].name = 'Twin', 'Twin'      -- one used_jokers name
    rarity[1][5].name = 'To Do List'                           -- its 'to_do' draw
    rarity[1][6].no_pool_flag = 'extinct'                      -- culled by pool_flags
    rarity[2][2].yes_pool_flag = 'extinct'                     -- kept by pool_flags
    rarity[1][7].enhancement_gate = 'm_e01'                    -- no playing cards: culled
    rarity[4][1] = center('j_leg1', {set = 'Joker', rarity = 4, name = 'leg1', unlocked = false})
    center('j_joker', {set = 'Joker', rarity = 1, name = 'Joker'})
    P.Tarot, P.Planet, P.Spectral, P.Enhanced = {}, {}, {}, {}
    for i = 1, 8 do P.Tarot[i] = center(('c_t%02d'):format(i), {set = 'Tarot', name = 'tarot'..i, unlocked = i ~= 4}) end
    center('c_strength', {set = 'Tarot', name = 'Strength'})
    local hands = {}
    G.handlist = {'H1', 'H2', 'H3', 'H4', 'H5'}
    for i = 1, 5 do
      P.Planet[i] = center(('c_p%02d'):format(i), {set = 'Planet', name = 'planet'..i,
        config = {hand_type = 'H'..i, softlock = i == 5}})
      hands['H'..i] = {visible = true, played = ({0, 3, 7, 7, 0})[i]}
    end
    center('c_pluto', {set = 'Planet', name = 'Pluto', config = {hand_type = 'H1'}})
    P.Planet[6] = center('c_black_hole', {set = 'Spectral', name = 'Black Hole', hidden = true})
    for i = 1, 4 do P.Spectral[i] = center(('c_s%02d'):format(i), {set = 'Spectral', name = 'spectral'..i}) end
    P.Spectral[5] = center('c_soul', {set = 'Spectral', name = 'The Soul', hidden = true})
    P.Spectral[6] = C.c_black_hole
    center('c_incantation', {set = 'Spectral', name = 'Incantation'})
    for i = 1, 6 do P.Enhanced[i] = center(('m_e%02d'):format(i), {set = 'Enhanced', name = 'enh'..i}) end
    P.Enhanced[6].name = 'Twin'                                -- same name, no used cull for Enhanced
    center('c_base', {set = 'Default', name = 'Default Base'})
    P.Booster = {}
    local packs = {
      {'p_arcana_normal_1', 'Arcana Pack', 4, 3}, {'p_arcana_mega_1', 'Mega Arcana Pack', 0.25, 5},
      {'p_celestial_jumbo_1', 'Jumbo Celestial Pack', 2, 5}, {'p_spectral_normal_1', 'Spectral Pack', 0.6, 2},
      {'p_standard_normal_1', 'Standard Pack', 4, 3}, {'p_standard_mega_1', 'Mega Standard Pack', 0.3, 5},
      {'p_buffoon_normal_1', 'Buffoon Pack', 1.2, 2}, {'p_buffoon_jumbo_1', 'Jumbo Buffoon Pack', 1.2, 4},
    }
    for i, d in ipairs(packs) do
      P.Booster[i] = center(d[1], {set = 'Booster', name = d[2], weight = d[3], kind = d[2]:match('(%a+) Pack$'),
        config = {extra = d[4], choose = 1}})
    end
    P.Tag = {}
    for i, k in ipairs{'tag_charm', 'tag_economy', 'tag_ethereal', 'tag_juggle'} do P.Tag[i] = center(k, {set = 'Tag'}) end
    P.Voucher = {center('v_x1', {set = 'Voucher'}), center('v_x2', {set = 'Voucher'})}
    local cards = {}
    for i = 1, 52 do cards[('%s_%d'):format(({'H', 'C', 'D', 'S'})[i % 4 + 1], i)] = {name = 'card'..i} end
    G.P_CENTERS, G.P_CENTER_POOLS, G.P_CARDS = C, P, cards
    G.P_JOKER_RARITY_POOLS = rarity
    G.P_BLINDS = {bl_b1 = {boss = {min = 1}}, bl_b2 = {boss = {min = 1}}, bl_fin = {boss = {showdown = true}}}
    G.jokers, G.consumeables, G.playing_cards = {cards = {}}, {cards = {}}, {}
    return function(seed)
      local g = {win_ante = 8, edition_rate = opts.edition_rate or 1, banned_keys = opts.banned or {},
        bosses_used = {bl_b1 = 0, bl_b2 = 0, bl_fin = 0}, pool_flags = {extinct = true},
        used_jokers = {}, used_vouchers = opts.vouchers or {}, modifiers = opts.modifiers or {},
        round_resets = {ante = 1}, hands = hands, first_shop_buffoon = opts.first_done,
        joker_rate = 20, tarot_rate = 4, planet_rate = 4, playing_card_rate = opts.playing or 0,
        spectral_rate = opts.spectral or 0, shop = {joker_max = opts.joker_max or 2},
        pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)}}
      for _, k in ipairs(opts.used or {}) do g.used_jokers[k] = true end
      return {game = g, all_unlocked = false}
    end
  end

  local SKIPS = {{}, {Small = true}, {Big = true}, {Small = true, Big = true}}
  for _, cfg in ipairs{
      {name = 'shop_plain', seeds = 150},
      {name = 'shop_vouchers_stickers', seeds = 150, edition_rate = 2, playing = 4, spectral = 2, joker_max = 3,
        vouchers = {v_illusion = true, v_omen_globe = true, v_telescope = true},
        modifiers = {all_eternal = true, enable_eternals_in_shop = true, enable_perishables_in_shop = true,
          enable_rentals_in_shop = true},
        banned = {c_black_hole = true, p_arcana_normal_1 = true, j_r1_01 = true},
        used = {'j_r2_01', 'c_soul'}, first_done = true},
      {name = 'shop_no_eternal', seeds = 100, playing = 4,
        modifiers = {enable_perishables_in_shop = true, enable_rentals_in_shop = true},
        banned = {p_buffoon_normal_1 = true}, used = {'c_black_hole'}},
      -- Many seeds, one policy: enough soul rolls over 0.997 that a gate
      -- ignoring a used Soul / Black Hole shows.
      {name = 'shop_soul_used', seeds = 800, used = {'c_soul'}, policies = 1},
      {name = 'shop_black_hole_used', seeds = 800, used = {'c_black_hole'}, policies = 1}} do
    -- An error (a C error code, a glue assert) is this group's failure; os.exit
    -- below then skips lua_close, whose finalizers may run after the .so is gone.
    local ok, err = pcall(function()
    local fresh = shop_world(cfg)
    local S0 = fresh('AAAAAAAA')
    G.GAME = S0.game
    local ctx = bhsim.shop(bhsim.context(lib, SANTES), predict.TAG_PACKS)
    local seeds, x = {}, #cfg.name
    for i = 1, cfg.seeds do
      local b = {}
      for j = 1, 8 do
        x = (x * 1103515245 + 12345) % 2147483648 -- an LCG: distinct seeds, no short period
        local d = 1 + math.floor(x / 65536) % 34
        b[j] = ('123456789ABCDEFGHIJKLMNPQRSTUVWXYZ'):sub(d, d)
      end
      seeds[i] = table.concat(b)
    end
    local bad, first, n = 0, nil, 0
    for si = 1, cfg.policies or #SKIPS do
      local skip = SKIPS[si]
      for ri = 1, cfg.policies or 2 do
        local rerolls = ({0, 2})[ri]
        local pol = {skip = skip, rerolls = rerolls}
        local out = bhsim.shop_walk(ctx, seeds, SANTES, pol)
        for i, seed in ipairs(seeds) do
          local S = fresh(seed)
          for a = 1, SANTES do
            n = n + 1
            local want = predict.ante_walk(S, a, pol)
            local d = bhsim.shop_diff(want, bhsim.shop_record(ctx, out, i, a),
              ('%s %s%s r%d ante %d'):format(seed, skip.Small and 'S' or '-', skip.Big and 'B' or '-', rerolls, a))
            if #d > 0 then bad = bad + 1; first = first or d[1] end
          end
        end
      end
    end
    report(cfg.name, n, bad, first)
    end)
    if not ok then report(cfg.name, 1, 1, 'error: '..tostring(err)) end
  end
end

print(('native test: %d groups, %d failed'):format(groups, failed))
os.exit(failed == 0 and 0 or 1)
