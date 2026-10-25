-- bhcore.sim.state: sim states, the plain-data runs the simulator advances.
-- Contract: docs/bh-core.md § sim.state.
--
-- A sim state S is {game = <a G.GAME-shaped plain table>, all_unlocked = bool}.
--
-- API
--   state.capture()          S from the live run: STR_UNPACK(STR_PACK(G.GAME)),
--                            the same projection the game saves (Objects such
--                            as selected_back, tags and blind become the string
--                            "MANUAL_REPLACE"), with every number put back at
--                            full precision (see Traps).
--   state.fresh(seed, opts)  S for a brand-new run with `seed`, as
--                            Game:start_run has it just before its first
--                            generation (get_new_boss, game.lua:2177).
--                            opts = {stake = 1, deck = 'b_red', all_unlocked = false}.
--                            Built inside sandbox.run: the live G.GAME is never
--                            touched. Errors on an unknown deck.
--   state.copy(S)            an independent deep copy, numbers exact.
--   state.redeem(S, key)     -> S: the voucher `key` redeemed now (Card:redeem,
--                            card.lua:1813-1852): used_vouchers[key], and the
--                            Card:apply_to_run effects generation reads, the
--                            ones fresh applies for a deck's starting vouchers
--                            (rates, shop.joker_max). A shop slot it adds is
--                            not filled here (predict.ante_walk does that for a
--                            purchase in an open shop). Raises for a voucher
--                            in state.REWINDS, and a modded voucher's own
--                            redeem code is not run.
--   state.REWINDS            {[center name] = true}: Hieroglyph and Petroglyph,
--                            whose apply_to_run sets the ante back (ease_ante,
--                            card.lua:1957-1958). The run then replays an ante,
--                            which no sim state or caller models.
--
-- What fresh reproduces from Game:start_run (game.lua:2018-2176), no challenge:
--   Game:init_game_object(); modifiers table; stake; STOP_USE = 0; the stake
--   modifiers (game.lua:2049-2056); the deck's Back:apply_to_run(); round_resets
--   hands/discards/reroll_cost, dollars and reroll costs from starting_params;
--   chips_text; seeded = true; pseudorandom.seed; the zero-state rehash and
--   hashed_seed (game.lua:2162-2168); round_resets.blind_tags = {}.
--   selected_back is "MANUAL_REPLACE" and selected_back_key a plain-data copy
--   of the deck center, what capture() of a vanilla run holds (functions,
--   which Steamodded adds to some decks, are dropped).
-- The deck's queued events are handed to a throwaway queue, never the live
--   E_MANAGER; start_run's own first generation (boss, voucher, tags) runs
--   before them. What they leave that later generation reads is applied from
--   the deck's config instead: its starting vouchers' rates and shop slots
--   (Card.apply_to_run's events: Zodiac's Merchants and Overstock), and its
--   starting consumables in used_jokers (Magic's Fools, Ghost's Hex), held for
--   the rest of the run. Checked against the real game by
--   rig/scenarios/golden_decks.lua. Other event work (Checkered's suits,
--   Crystal Ball's slot) draws nothing and feeds no pool.
--
-- Traps
--   * STR_PACK writes numbers with tostring, i.e. %.14g. pseudorandom's
--     hashed_seed (and any state set straight from pseudohash) is a full
--     double, so a packed copy differs in the last digits, and
--     math.randomseed() on LuaJIT turns that into a different draw. capture()
--     and copy() therefore keep the exact numbers.
local sandbox = require('bhcore.sim.sandbox')

local M = {}

local function is_object(t)
  return type(t) == 'table' and type(t.is) == 'function' and Object ~= nil and t:is(Object)
end

-- Walks a packed copy alongside its source and restores full-precision numbers.
local function exact_numbers(dst, src, seen)
  if seen[dst] then return end
  seen[dst] = true
  for k, v in pairs(dst) do
    local sv = src[k]
    if type(v) == 'number' and type(sv) == 'number' then
      dst[k] = sv
    elseif type(v) == 'table' and type(sv) == 'table' and not is_object(sv) then
      exact_numbers(v, sv, seen)
    end
  end
end

local function deep_copy(t, memo)
  if type(t) ~= 'table' then return t end
  if memo[t] then return memo[t] end
  local out = {}
  memo[t] = out
  for k, v in pairs(t) do out[deep_copy(k, memo)] = deep_copy(v, memo) end
  return setmetatable(out, getmetatable(t))
end

function M.capture()
  assert(G and type(G.GAME) == 'table', 'state.capture: no G.GAME')
  local game = STR_UNPACK(STR_PACK(G.GAME))
  exact_numbers(game, G.GAME, {})
  return {game = game, all_unlocked = false}
end

function M.copy(S)
  assert(type(S) == 'table' and type(S.game) == 'table', 'state.copy: not a sim state')
  return {game = deep_copy(S.game, {}), all_unlocked = S.all_unlocked and true or false}
end

-- game.lua:2049-2056: what each stake adds, cumulatively, to a new run.
local STAKE_RULES = {
  [2] = function(g)
    g.modifiers.no_blind_reward = g.modifiers.no_blind_reward or {}
    g.modifiers.no_blind_reward.Small = true
  end,
  [3] = function(g) g.modifiers.scaling = 2 end,
  [4] = function(g) g.modifiers.enable_eternals_in_shop = true end,
  [5] = function(g) g.starting_params.discards = g.starting_params.discards - 1 end,
  [6] = function(g) g.modifiers.scaling = 3 end,
  [7] = function(g) g.modifiers.enable_perishables_in_shop = true end,
  [8] = function(g) g.modifiers.enable_rentals_in_shop = true end,
}

-- The deck center as STR_UNPACK(STR_PACK(center)) would give it, minus what STR_PACK
-- errors on. Steamodded's take_ownership (zodiac, painted, anaglyph, plasma, erratic)
-- leaves functions such as inject among the center's own fields. Nested Objects become
-- "MANUAL_REPLACE", as STR_PACK writes them; functions and cycles are dropped.
local function packable(v, onpath)
  local t = type(v)
  if t == 'string' or t == 'number' or t == 'boolean' then return v end
  if t ~= 'table' or onpath[v] then return nil end
  onpath[v] = true
  local out = {}
  for k, x in pairs(v) do
    local tk = type(k)
    if tk == 'string' or tk == 'number' then
      if is_object(x) then out[k] = 'MANUAL_REPLACE' else out[k] = packable(x, onpath) end
    end
  end
  onpath[v] = nil
  return out
end

-- A queue that drops everything: the deck's deferred work never reaches the game.
local NULL_EVENTS = {add_event = function() end, clear_queue = function() end}

-- Card:apply_to_run (card.lua:1880-1908): the voucher effects generation reads,
-- each queued as an event in vanilla (and the whole call under Steamodded).
local VOUCHER_EVENTS = {
  ['Overstock'] = function(g) g.shop.joker_max = g.shop.joker_max + 1 end,
  ['Overstock Plus'] = function(g) g.shop.joker_max = g.shop.joker_max + 1 end,
  ['Tarot Merchant'] = function(g, extra) g.tarot_rate = 4 * extra end,
  ['Tarot Tycoon'] = function(g, extra) g.tarot_rate = 4 * extra end,
  ['Planet Merchant'] = function(g, extra) g.planet_rate = 4 * extra end,
  ['Planet Tycoon'] = function(g, extra) g.planet_rate = 4 * extra end,
  ['Hone'] = function(g, extra) g.edition_rate = extra end,
  ['Glow Up'] = function(g, extra) g.edition_rate = extra end,
  ['Magic Trick'] = function(g, extra) g.playing_card_rate = extra end,
  ['Illusion'] = function(g, extra) g.playing_card_rate = extra end,
}

M.REWINDS = {Hieroglyph = true, Petroglyph = true}

function M.redeem(S, key)
  assert(type(S) == 'table' and type(S.game) == 'table', 'state.redeem: not a sim state')
  local v = G.P_CENTERS and G.P_CENTERS[key]
  assert(type(v) == 'table' and v.set == 'Voucher', 'state.redeem: not a voucher '..tostring(key))
  assert(not M.REWINDS[v.name], 'state.redeem: '..tostring(v.name)..' sets the ante back, which the sim does not model')
  local g = S.game
  g.used_vouchers = g.used_vouchers or {}
  g.used_vouchers[key] = true
  local apply = VOUCHER_EVENTS[v.name]
  if apply then apply(g, v.config and v.config.extra) end
  return S
end

-- What the deck's dropped events leave behind that generation reads (they run
-- before the first shop): its starting vouchers' rates and shop slots, and the
-- used_jokers write of its starting consumables (back.lua:184-195 ->
-- create_card -> Card:set_ability, every center sharing the name). The
-- consumables stay held, so nothing a shop or pack makes ever releases them.
local function deck_events(g, center)
  local cfg = center.config or {}
  local vouchers = {cfg.voucher}
  for _, v in pairs(cfg.vouchers or {}) do vouchers[#vouchers + 1] = v end
  for _, key in pairs(vouchers) do
    local v = G.P_CENTERS[key]
    local apply = v and VOUCHER_EVENTS[v.name]
    if apply then apply(g, v.config and v.config.extra) end
  end
  for _, key in ipairs(cfg.consumables or {}) do
    local c = G.P_CENTERS[key]
    if c then
      for k, v in pairs(G.P_CENTERS) do
        if v.name == c.name then g.used_jokers[k] = true end
      end
    end
  end
end

local function apply_back(center)
  local live_events = G.E_MANAGER
  G.E_MANAGER = NULL_EVENTS
  local ok, err = pcall(function() Back(center):apply_to_run() end)
  G.E_MANAGER = live_events
  if not ok then error(err, 0) end
end

local function build(S, seed, stake, deck)
  local center = G.P_CENTERS[deck]
  assert(type(center) == 'table' and center.set == 'Back', 'state.fresh: unknown deck '..tostring(deck))

  local g = Game.init_game_object(G)
  S.game = g
  G.GAME = g -- the sandbox puts the previous G.GAME back
  g.modifiers = g.modifiers or {}
  g.stake = stake
  g.STOP_USE = 0
  g.selected_back = 'MANUAL_REPLACE'
  g.selected_back_key = packable(center, {})

  for level = 2, stake do
    if STAKE_RULES[level] then STAKE_RULES[level](g) end
  end
  apply_back(center)
  g.used_jokers = g.used_jokers or {}
  deck_events(g, center)

  local p = g.starting_params
  g.round_resets.hands = p.hands
  g.round_resets.discards = p.discards
  g.dollars = p.dollars
  g.base_reroll_cost = p.reroll_cost
  g.round_resets.reroll_cost = g.base_reroll_cost
  g.current_round.reroll_cost = g.base_reroll_cost
  g.chips_text = ''

  g.seeded = true
  g.pseudorandom.seed = seed
  for k, v in pairs(g.pseudorandom) do
    if v == 0 then g.pseudorandom[k] = pseudohash(k..seed) end
  end
  g.pseudorandom.hashed_seed = pseudohash(seed)
  g.round_resets.blind_tags = g.round_resets.blind_tags or {}
end

function M.fresh(seed, opts)
  assert(type(seed) == 'string' and seed ~= '', 'state.fresh: seed must be a non-empty string')
  opts = opts or {}
  local stake = opts.stake or 1
  assert(type(stake) == 'number' and stake >= 1, 'state.fresh: bad stake '..tostring(stake))
  local S = {game = {}, all_unlocked = opts.all_unlocked and true or false}
  local ok, err = sandbox.run(S, build, S, seed, stake, opts.deck or 'b_red')
  if not ok then error(err, 2) end
  return S
end

return M
