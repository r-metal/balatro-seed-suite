-- bhsim.lua: the LuaJIT FFI side of native/ (T-341 spike, T-342 shops). Loaded
-- with dofile(<root>/native/lua/bhsim.lua); returns the module table. Used by
-- rig/scenarios/native_diff.lua, native_diff_shop.lua (main thread and their
-- workers) and native/test/test_native.lua. Not a mod module yet: the Finder backend that
-- ships it is T-343.
--
-- API
--   bhsim.load(root)           -> lib: ffi.cdef of native/src/bhsim.h (between
--                                 its BHSIM_CDEF markers) + ffi.load of
--                                 native/build/libbhsim.so. Once per Lua state.
--                                 Sets the C side's %.13f tie rule to this
--                                 LuaJIT's (bhsim.TIES_AWAY).
--   bhsim.context(lib, antes)  -> ctx: the pools of G.GAME as it stands, read
--                                 through vanilla get_current_pool, so call it
--                                 with G.GAME = the run to model (inside
--                                 sim.sandbox.run on the main thread, which
--                                 also applies all_unlocked). Any fresh run of
--                                 the same deck, stake and profile gives the
--                                 same context. ctx.keys = {tags, vouchers,
--                                 bosses, legend} (index -> key).
--   bhsim.walk(ctx, seeds, antes) -> out: int16_t[#seeds * antes * 6], see
--                                 bh_stable_batch. Raises on an error code.
--   bhsim.record(ctx, out, i, a) -> small, big, boss, voucher, legendary,
--                                 edition ('none'|'foil'|...) for seed i
--                                 (1-based) at ante a, as keys.
--
-- What the pools are (common_events.lua:1963-2053, called as-is):
--   Tag     get_current_pool('Tag') at each ante 1..antes (min_ante and the
--           profile's `requires` discovery cull differently per ante);
--   Voucher get_current_pool('Voucher'): static under the no-purchase walk;
--   Joker4  get_current_pool('Joker', 4, true): the rarity argument avoids
--           the 'rarity' draw the Soul's own call makes (see bhsim.c);
--           the C side then removes each legendary it hands out (used_jokers).
--   bosses  G.P_BLINDS entries with .boss, sorted by key with Lua's `<`
--           (pseudorandom_element's order for a keyed table), with boss.min,
--           boss.showdown, banned_keys and G.GAME.bosses_used.
-- A 'UNAVAILABLE' pool entry is 0 in the mask; an all-empty pool (vanilla's
-- fallback 1-entry pool) is all zeros and comes back as index -1, which
-- record() maps to vanilla's fallback key.
--
-- Conditional streams (T-342): shops, shop packs, pack contents
--   bhsim.shop(ctx, tag_packs)  adds the shop data of G.GAME as it stands to
--                                 ctx (same rule as context: G.GAME = the run,
--                                 inside sim.sandbox.run). tag_packs =
--                                 predict.TAG_PACKS (tag key -> booster key).
--   bhsim.shop_walk(ctx, seeds, antes, policy) -> out: bh_shop_batch, policy =
--                                 {skip = {Small, Big}, rerolls = R}, the same
--                                 policy at every ante.
--   bhsim.shop_record(ctx, out, i, a) -> seed i's ante a in the shape of
--                                 predict.ante_walk (cards {key, set, edition,
--                                 front, seal, stickers}; packs {key, forced,
--                                 index}).
--   bhsim.shop_diff(want, got, where, into) -> into: one line per field of an
--                                 ante_walk result that differs from got.
-- What the shop data is (read, never written down here):
--   pools    Joker rarity 1-3 (G.P_JOKER_RARITY_POOLS), Tarot, Planet,
--            Spectral, Enhanced (G.P_CENTER_POOLS), each culled by vanilla
--            get_current_pool(type, rarity) with used_jokers emptied: the
--            static mask. Whether used_jokers culls a pool is read off the
--            game too (every key marked used: does the pool still have
--            entries?), and so is its empty-pool fallback key (every key
--            banned: what comes back).
--   centers  every key those pools, the fallbacks, c_soul / c_black_hole /
--            c_base (create_card's literal keys) and Telescope's planet can
--            make; grouped by .name (Card:set_ability and Card:remove write
--            used_jokers by name).
--   boosters G.P_CENTER_POOLS.Booster in order: weight, banned, kind by
--            predict's name:find order, size = config.extra.
--   fronts   G.P_CARDS keys in pseudorandom_element's order.
--   run      rates, joker_max, Illusion / Omen Globe / Telescope, the sticker
--            modifiers, used_jokers, first_shop_buffoon.
local ffi = require('ffi')

local M = {}

M.FIELDS = 6
M.EDITIONS = {[0] = 'none', 'foil', 'holo', 'polychrome', 'negative'}
-- get_current_pool's empty-pool fallbacks (common_events.lua:2039-2048).
M.FALLBACK = {tags = 'tag_handy', vouchers = 'v_blank', legend = 'j_joker'}

local loaded

function M.load(root)
  if loaded then return loaded end
  local f = assert(io.open(root..'/native/src/bhsim.h', 'rb'))
  local h = f:read('*a')
  f:close()
  local cdef = assert(h:match('/%* BHSIM_CDEF_BEGIN %*/(.-)/%* BHSIM_CDEF_END %*/'), 'bhsim.h: no CDEF block')
  ffi.cdef(cdef)
  loaded = ffi.load(root..'/native/build/libbhsim.so')
  -- This LuaJIT's %.13f tie rule (bhsim.c header): 2^-14 = 0.00006103515625.
  local s = string.format('%.13f', 2 ^ -14)
  assert(s == '0.0000610351563' or s == '0.0000610351562', 'bhsim: unexpected %.13f of 2^-14: '..s)
  M.TIES_AWAY = s == '0.0000610351563'
  loaded.bh_set_round_ties(M.TIES_AWAY and 1 or 0)
  return loaded
end

-- A culled pool as a 0/1 mask over its full, ordered list.
local function mask(pool, n, into, offset)
  offset = offset or 0
  local size = 0
  for i = 1, n do if pool[i] ~= nil and pool[i] ~= 'UNAVAILABLE' then size = size + 1 end end
  local full = #pool == n and size > 0
  for i = 1, n do
    into[offset + i - 1] = (full and pool[i] ~= 'UNAVAILABLE') and 1 or 0
  end
end

local function keys_of(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v.key end
  return out
end

function M.context(lib, antes)
  local game = G.GAME
  assert(type(game) == 'table' and game.pseudorandom, 'bhsim.context: no G.GAME')
  local ctx = {lib = lib, keys = {}, antes = antes}
  local c = ffi.gc(lib.bh_new(), lib.bh_free)
  ctx.c = c
  local saved_ante = game.round_resets.ante
  local ok, err = pcall(function()
    assert(lib.bh_set_run(c, game.win_ante, game.edition_rate) == 0, 'bh_set_run')

    local tags = G.P_CENTER_POOLS.Tag
    ctx.keys.tags = keys_of(tags)
    local tok = ffi.new('uint8_t[?]', #tags * antes)
    for a = 1, antes do
      game.round_resets.ante = a
      mask(get_current_pool('Tag'), #tags, tok, (a - 1) * #tags)
    end
    assert(lib.bh_set_tags(c, #tags, antes, tok) == 0, 'bh_set_tags')

    local vouchers = G.P_CENTER_POOLS.Voucher
    ctx.keys.vouchers = keys_of(vouchers)
    local vok = ffi.new('uint8_t[?]', #vouchers)
    mask(get_current_pool('Voucher'), #vouchers, vok)
    assert(lib.bh_set_vouchers(c, #vouchers, vok) == 0, 'bh_set_vouchers')

    local legend = G.P_JOKER_RARITY_POOLS[4]
    ctx.keys.legend = keys_of(legend)
    local lok = ffi.new('uint8_t[?]', #legend)
    mask(get_current_pool('Joker', 4, true), #legend, lok)
    assert(lib.bh_set_legendaries(c, #legend, lok) == 0, 'bh_set_legendaries')

    local bosses = {}
    for k, v in pairs(G.P_BLINDS) do
      if v.boss then bosses[#bosses + 1] = k end
    end
    table.sort(bosses)
    ctx.keys.bosses = bosses
    local n = #bosses
    local bmin, bsd, bok, bused = ffi.new('int[?]', n), ffi.new('uint8_t[?]', n),
      ffi.new('uint8_t[?]', n), ffi.new('int[?]', n)
    for i, k in ipairs(bosses) do
      local b = G.P_BLINDS[k].boss
      local used = game.bosses_used[k]
      assert(type(used) == 'number', 'bhsim.context: bosses_used has no '..k)
      bmin[i - 1], bsd[i - 1] = b.min or 0, b.showdown and 1 or 0
      bok[i - 1], bused[i - 1] = game.banned_keys[k] and 0 or 1, used
    end
    assert(lib.bh_set_bosses(c, n, bmin, bsd, bok, bused) == 0, 'bh_set_bosses')
  end)
  game.round_resets.ante = saved_ante
  if not ok then error(err, 2) end
  return ctx
end

local function key(list, idx, fallback)
  if idx < 0 then return fallback end
  return list[idx + 1]
end

-- bhsim.h's enums (keep in step).
M.SET = {Joker = 1, Tarot = 2, Planet = 3, Spectral = 4, Enhanced = 5, Default = 6}
-- {type, rarity, roll}: get_current_pool's _rarity is the rarity ROLL, not the
-- rarity (1 > 0.95 is rarity 3), so each Joker pool is asked for with a roll
-- that lands on it; the returned key is checked.
M.POOLS = {{'Joker', 1, 0}, {'Joker', 2, 0.8}, {'Joker', 3, 1}, {'Tarot'}, {'Planet'}, {'Spectral'}, {'Enhanced'}}
M.KINDS = {'Arcana', 'Celestial', 'Spectral', 'Standard', 'Buffoon'} -- predict's pack_card order
M.SEALS = {'Red', 'Blue', 'Gold', 'Purple'}
M.CARD = 5
M.FLAGS = {illusion = 1, omen_globe = 2, telescope = 4, all_eternal = 8, eternals = 16,
  perishables = 32, rentals = 64}
M.AFTER = {[0] = 'Boss', 'Small', 'Big'}
M.BLIND = {[0] = 'Small', 'Big'}

-- pseudorandom_element's order for a keyed table (misc_functions.lua:253-268).
local function element_order(t)
  local keys = {}
  for k, v in pairs(t) do keys[#keys + 1] = {k = k, v = v} end
  if keys[1] and type(keys[1].v) == 'table' and keys[1].v.sort_id then
    table.sort(keys, function(a, b) return a.v.sort_id < b.v.sort_id end)
  else
    table.sort(keys, function(a, b) return a.k < b.k end)
  end
  local out = {}
  for i, e in ipairs(keys) do out[i] = e.k end
  return out
end

-- Card:open's Telescope planet (card.lua:1733-1747): the most played visible
-- hand's planet, or nil.
local function telescope_planet(game)
  local best, tally = nil, 0
  for _, h in ipairs(G.handlist or {}) do
    local hand = game.hands and game.hands[h]
    if hand and hand.visible and hand.played > tally then best, tally = h, hand.played end
  end
  if not best then return nil end
  local planet
  for _, v in pairs(G.P_CENTER_POOLS.Planet) do
    if v.config.hand_type == best then planet = v.key end
  end
  return planet
end

local function set_of(list)
  local out = {}
  for _, v in ipairs(list) do out[v.key] = true end
  return out
end

function M.shop(ctx, tag_packs)
  local lib, c, game = ctx.lib, ctx.c, G.GAME
  assert(type(game) == 'table' and game.pseudorandom, 'bhsim.shop: no G.GAME')
  local centers, index = {}, {}
  local function add(key)
    assert(G.P_CENTERS[key], 'bhsim.shop: unknown center '..tostring(key))
    if not index[key] then centers[#centers + 1] = key; index[key] = #centers - 1 end
    return index[key]
  end

  -- Pools: the static mask, the used_jokers cull and the fallback, each read
  -- through get_current_pool with used_jokers / banned_keys swapped.
  local pools = {}
  local used, banned = game.used_jokers, game.banned_keys
  local ok, err = pcall(function()
    for p, def in ipairs(M.POOLS) do
      local t, r, roll = def[1], def[2], def[3]
      local list = r and G.P_JOKER_RARITY_POOLS[r] or G.P_CENTER_POOLS[t]
      local keys = keys_of(list)
      game.used_jokers = {}
      local m = {}
      local pool, pool_key = get_current_pool(t, roll)
      assert(pool_key == t..(r or '')..game.round_resets.ante, 'bhsim.shop: pool key '..tostring(pool_key)..' for '..t..(r or ''))
      mask(pool, #keys, m, 1)
      local live = 0
      for i = 1, #keys do live = live + m[i] end
      game.used_jokers = set_of(list)
      local m2 = {}
      mask(get_current_pool(t, roll), #keys, m2, 1)
      local after = 0
      for i = 1, #keys do after = after + m2[i] end
      game.used_jokers = {}
      local all = {}
      for k in pairs(banned or {}) do all[k] = banned[k] end
      for _, k in ipairs(keys) do all[k] = true end
      game.banned_keys = all
      local fb = get_current_pool(t, roll)
      game.banned_keys = banned
      assert(#fb == 1 and fb[1] ~= 'UNAVAILABLE', 'bhsim.shop: no fallback for pool '..t)
      pools[p] = {keys = keys, mask = m, cull = live == 0 or after < live, fallback = fb[1]}
    end
  end)
  game.used_jokers, game.banned_keys = used, banned
  if not ok then error(err, 2) end
  used, banned = used or {}, banned or {}

  for _, p in ipairs(pools) do
    for _, k in ipairs(p.keys) do add(k) end
    add(p.fallback)
  end
  local soul, black_hole, base = add('c_soul'), add('c_black_hole'), add('c_base')
  local flags = 0
  local vouchers, mods = game.used_vouchers or {}, game.modifiers or {}
  local telescope = -1
  if vouchers.v_illusion then flags = flags + M.FLAGS.illusion end
  if vouchers.v_omen_globe then flags = flags + M.FLAGS.omen_globe end
  if vouchers.v_telescope then
    flags = flags + M.FLAGS.telescope
    local planet = telescope_planet(game)
    if planet then telescope = add(planet) end
  end
  if mods.all_eternal then flags = flags + M.FLAGS.all_eternal end
  if mods.enable_eternals_in_shop then flags = flags + M.FLAGS.eternals end
  if mods.enable_perishables_in_shop then flags = flags + M.FLAGS.perishables end
  if mods.enable_rentals_in_shop then flags = flags + M.FLAGS.rentals end

  -- Centers: groups by name; used_jokers must agree within a group, since the
  -- game only ever writes and clears it a whole name at a time.
  local n = #centers
  local group, set = ffi.new('int[?]', n), ffi.new('uint8_t[?]', n)
  local ecompat, pcompat = ffi.new('uint8_t[?]', n), ffi.new('uint8_t[?]', n)
  local cbanned, cused = ffi.new('uint8_t[?]', n), ffi.new('uint8_t[?]', n)
  local groups, gused, sets = {}, {}, {}
  for i, key in ipairs(centers) do
    local v = G.P_CENTERS[key]
    local name = v.name or key
    if not groups[name] then groups[name] = i - 1 end
    local u = used[key] and true or false
    if gused[name] == nil then gused[name] = u end
    assert(gused[name] == u, 'bhsim.shop: used_jokers splits the name '..name)
    group[i - 1], set[i - 1] = groups[name], M.SET[v.set] or 0
    ecompat[i - 1], pcompat[i - 1] = v.eternal_compat and 1 or 0, v.perishable_compat and 1 or 0
    cbanned[i - 1], cused[i - 1] = banned[key] and 1 or 0, u and 1 or 0
    sets[i] = v.set
  end
  assert(lib.bh_set_centers(c, n, group, set, ecompat, pcompat, cbanned, cused) == 0, 'bh_set_centers')
  for p, pool in ipairs(pools) do
    local k = #pool.keys
    local ctr, okm = ffi.new('int[?]', math.max(k, 1)), ffi.new('uint8_t[?]', math.max(k, 1))
    for i, key in ipairs(pool.keys) do ctr[i - 1], okm[i - 1] = index[key], pool.mask[i] end
    assert(lib.bh_set_pool(c, p - 1, k, ctr, okm, index[pool.fallback], pool.cull and 1 or 0) == 0, 'bh_set_pool')
  end
  assert(lib.bh_set_specials(c, soul, black_hole, base) == 0, 'bh_set_specials')

  local boosters = G.P_CENTER_POOLS.Booster
  local nb = #boosters
  local bw, bok = ffi.new('double[?]', nb), ffi.new('uint8_t[?]', nb)
  local bkind, bsize = ffi.new('uint8_t[?]', nb), ffi.new('uint8_t[?]', nb)
  local bkeys, bindex, buffoon = {}, {}, -1
  for i, v in ipairs(boosters) do
    bkeys[i], bindex[v.key] = v.key, i - 1
    bw[i - 1], bok[i - 1] = v.weight or 1, banned[v.key] and 0 or 1
    local kind = 0
    for kc, name in ipairs(M.KINDS) do
      if kind == 0 and v.name:find(name) then kind = kc end
    end
    bkind[i - 1], bsize[i - 1] = kind, v.config.extra
  end
  -- get_pack's forced first Buffoon (common_events.lua:1945-1948).
  if bindex.p_buffoon_normal_1 and not banned.p_buffoon_normal_1 then buffoon = bindex.p_buffoon_normal_1 end
  assert(lib.bh_set_boosters(c, nb, bw, bok, bkind, bsize, buffoon, game.first_shop_buffoon and 1 or 0) == 0,
    'bh_set_boosters')

  local fronts = element_order(G.P_CARDS)
  local rates = ffi.new('double[5]', game.joker_rate, game.tarot_rate, game.planet_rate,
    game.playing_card_rate, game.spectral_rate or 0)
  local jmax = (game.shop and game.shop.joker_max) or 2
  assert(lib.bh_set_shop(c, rates, jmax, flags, telescope, #fronts) == 0, 'bh_set_shop')

  local tags = ctx.keys.tags
  local tp = ffi.new('int[?]', math.max(#tags, 1))
  for i, key in ipairs(tags) do
    local pack = tag_packs and tag_packs[key]
    tp[i - 1] = pack and assert(bindex[pack], 'bhsim.shop: unknown tag pack '..pack) or -1
  end
  assert(lib.bh_set_tag_packs(c, #tags, tp) == 0, 'bh_set_tag_packs')

  ctx.shop = {centers = centers, sets = sets, boosters = bkeys, sizes = {}, fronts = fronts, joker_max = jmax}
  for i = 1, nb do ctx.shop.sizes[i] = bsize[i - 1] end
  local maxp = 0
  for i = 1, nb do maxp = math.max(maxp, ctx.shop.sizes[i]) end
  ctx.shop.max_pack = maxp
  return ctx
end

function M.shop_walk(ctx, seeds, antes, policy)
  assert(ctx.shop, 'bhsim.shop_walk: call bhsim.shop first')
  policy = policy or {}
  local skip = policy.skip or {}
  local rerolls = policy.rerolls or 0
  local stride = ctx.lib.bh_shop_stride(ctx.c, rerolls)
  assert(stride > 0, 'bhsim.shop_walk: bad rerolls')
  local n = #seeds
  local arr = ffi.new('const char *[?]', math.max(n, 1))
  for i = 1, n do arr[i - 1] = seeds[i] end
  local out = ffi.new('int16_t[?]', math.max(n * antes * stride, 1))
  local rc = ctx.lib.bh_shop_batch(ctx.c, arr, n, antes, (skip.Small and 1 or 0) + (skip.Big and 2 or 0),
    rerolls, out)
  if rc ~= 0 then error('bh_shop_batch: error '..rc, 2) end
  ctx.shop.antes, ctx.shop.rerolls, ctx.shop.stride = antes, rerolls, stride
  return out
end

local function card_at(sh, out, o)
  local ci = out[o]
  if ci < 0 then return nil end
  local st = out[o + 2]
  local front = out[o + 4]
  return {key = sh.centers[ci + 1], set = sh.sets[ci + 1], edition = out[o + 1] > 0 and M.EDITIONS[out[o + 1]] or nil,
    front = front >= 0 and sh.fronts[front + 1] or nil, seal = out[o + 3] > 0 and M.SEALS[out[o + 3]] or nil,
    stickers = {eternal = st % 2 == 1, perishable = math.floor(st / 2) % 2 == 1, rental = math.floor(st / 4) % 2 == 1}}
end

local function cards_at(sh, out, o, n)
  local list = {}
  for j = 0, n - 1 do
    local cd = card_at(sh, out, o + j * M.CARD)
    if cd then list[#list + 1] = cd end
  end
  return list
end

function M.shop_record(ctx, out, i, a)
  local sh = ctx.shop
  local R, jm, mp = sh.rerolls, sh.joker_max, sh.max_pack
  local pack_stride = 2 + mp * M.CARD
  local shop_stride = 1 + jm * (1 + R) * M.CARD + 2 * pack_stride
  local base = ((i - 1) * sh.antes + (a - 1)) * sh.stride
  local tags = ctx.keys.tags
  local rec = {tags = {small = key(tags, out[base], M.FALLBACK.tags), big = key(tags, out[base + 1], M.FALLBACK.tags)},
    shops = {}, tag_packs = {}}
  local pack_i = 0
  for s = 0, 2 do
    local o = base + 2 + s * shop_stride
    if out[o] >= 0 then
      local shop = {after = M.AFTER[out[o]], cards = cards_at(sh, out, o + 1, jm), rerolls = {}, packs = {}, contents = {}}
      for r = 1, R do shop.rerolls[r] = {cards = cards_at(sh, out, o + 1 + r * jm * M.CARD, jm)} end
      for p = 0, 1 do
        local po = o + 1 + jm * (1 + R) * M.CARD + p * pack_stride
        local b = out[po]
        pack_i = pack_i + 1
        shop.packs[p + 1] = {key = sh.boosters[b + 1], forced = out[po + 1] == 1 or nil, index = pack_i}
        shop.contents[p + 1] = cards_at(sh, out, po + 2, sh.sizes[b + 1])
      end
      rec.shops[#rec.shops + 1] = shop
    end
  end
  for t = 0, 1 do
    local o = base + 2 + 3 * shop_stride + t * (3 + mp * M.CARD)
    if out[o] >= 0 then
      local b = out[o + 2]
      rec.tag_packs[#rec.tag_packs + 1] = {blind = M.BLIND[out[o]], tag = key(tags, out[o + 1], M.FALLBACK.tags),
        pack = sh.boosters[b + 1], cards = cards_at(sh, out, o + 3, sh.sizes[b + 1])}
    end
  end
  return rec
end

-- Comparison of an ante_walk result (want) with a shop_record (got).
local CARD_FIELDS = {'key', 'edition', 'front', 'seal'}
local STICKERS = {'eternal', 'perishable', 'rental'}

local function diff_cards(want, got, where, into)
  want, got = want or {}, got or {}
  if #want ~= #got then into[#into + 1] = ('%s: %d cards, native %d'):format(where, #want, #got) end
  for j = 1, math.max(#want, #got) do
    local w, g = want[j] or {}, got[j] or {}
    for _, f in ipairs(CARD_FIELDS) do
      if w[f] ~= g[f] then
        into[#into + 1] = ('%s card %d %s: lua %s, native %s'):format(where, j, f, tostring(w[f]), tostring(g[f]))
      end
    end
    local ws, gs = w.stickers or {}, g.stickers or {}
    for _, f in ipairs(STICKERS) do
      if (ws[f] or false) ~= (gs[f] or false) then
        into[#into + 1] = ('%s card %d %s: lua %s, native %s'):format(where, j, f, tostring(ws[f]), tostring(gs[f]))
      end
    end
  end
end

function M.shop_diff(want, got, where, into)
  into = into or {}
  local function ne(what, w, g)
    if w ~= g then into[#into + 1] = ('%s %s: lua %s, native %s'):format(where, what, tostring(w), tostring(g)) end
  end
  ne('small tag', want.tags.small, got.tags.small)
  ne('big tag', want.tags.big, got.tags.big)
  ne('shops', #want.shops, #got.shops)
  for s = 1, math.max(#want.shops, #got.shops) do
    local w, g = want.shops[s] or {packs = {}, rerolls = {}, contents = {}}, got.shops[s] or {packs = {}, rerolls = {}, contents = {}}
    local at = where..' shop '..s
    ne('shop '..s..' after', w.after, g.after)
    diff_cards(w.cards, g.cards, at..' row', into)
    ne('shop '..s..' rerolls', #w.rerolls, #g.rerolls)
    for r = 1, math.max(#w.rerolls, #g.rerolls) do
      diff_cards((w.rerolls[r] or {}).cards, (g.rerolls[r] or {}).cards, at..' reroll '..r, into)
    end
    for p = 1, 2 do
      local wp, gp = w.packs[p] or {}, g.packs[p] or {}
      ne('shop '..s..' pack '..p..' key', wp.key, gp.key)
      ne('shop '..s..' pack '..p..' forced', wp.forced, gp.forced)
      ne('shop '..s..' pack '..p..' index', wp.index, gp.index)
      diff_cards(w.contents[p], g.contents[p], at..' pack '..p, into)
    end
  end
  ne('tag packs', #want.tag_packs, #got.tag_packs)
  for t = 1, math.max(#want.tag_packs, #got.tag_packs) do
    local w, g = want.tag_packs[t] or {}, got.tag_packs[t] or {}
    ne('tag pack '..t..' blind', w.blind, g.blind)
    ne('tag pack '..t..' tag', w.tag, g.tag)
    ne('tag pack '..t..' pack', w.pack, g.pack)
    diff_cards(w.cards, g.cards, where..' tag pack '..t, into)
  end
  return into
end

function M.walk(ctx, seeds, antes)
  local n = #seeds
  local arr = ffi.new('const char *[?]', math.max(n, 1))
  for i = 1, n do arr[i - 1] = seeds[i] end -- seeds (the Lua strings) stay alive: the table holds them
  local out = ffi.new('int16_t[?]', math.max(n * antes * M.FIELDS, 1))
  local rc = ctx.lib.bh_stable_batch(ctx.c, arr, n, antes, out)
  if rc ~= 0 then error('bh_stable_batch: error '..rc, 2) end
  ctx.antes_used = antes
  return out
end

function M.record(ctx, out, i, a)
  local o = ((i - 1) * ctx.antes_used + (a - 1)) * M.FIELDS
  local k = ctx.keys
  return key(k.tags, out[o], M.FALLBACK.tags), key(k.tags, out[o + 1], M.FALLBACK.tags),
    k.bosses[out[o + 2] + 1], key(k.vouchers, out[o + 3], M.FALLBACK.vouchers),
    key(k.legend, out[o + 4], M.FALLBACK.legend), M.EDITIONS[out[o + 5]]
end

return M
