-- bhcore.sim.sandbox: run vanilla's Card-free generation primitives against a
-- sim state instead of the live run. Contract: docs/bh-core.md § sim.sandbox.
--
-- API
--   sandbox.run(S, fn, ...)  -> ok, ...   (pcall-style)
--     For the duration of fn(...):
--       G.GAME = S.game;
--       G.jokers, G.consumeables, G.playing_cards, G.deck, G.hand,
--       G.shop_jokers, G.shop_vouchers, G.shop_booster are empty stub areas
--       ({cards = {}, config = {card_limit = <live or default>}});
--       with S.all_unlocked, every G.P_CENTERS entry is unlocked and
--       discovered (pools read `unlocked`, tags read `requires`.discovered);
--       BHCore.sim_depth is incremented.
--     Everything is restored afterwards, on error too.
--
-- Why this is safe (docs/research/sim-feasibility.md §4): the primitives
-- (pseudoseed, get_current_pool, get_next_tag_key, get_new_boss, get_pack,
-- poll_edition, ...) read the global G.GAME on every call, and the sim runs
-- synchronously, so nothing else can observe the swapped state.
--
-- Nesting
--   A nested call shares the outer area stubs (they are not re-swapped), sets
--   G.GAME to its own S.game and puts back the outer one when it returns. The
--   unlock flip is shared too: a nested all_unlocked call flips only when the
--   outer call did not, and then undoes its own flip on return.
--
-- Traps
--   * G.playing_cards is a plain list in vanilla, iterated with pairs() by the
--     enhancement gate (common_events.lua:2014). A literal {cards, config}
--     table there would be iterated as two bogus "cards" and crash the Joker
--     pool build, so its stub is an empty list whose metatable answers
--     .cards / .config: pairs/ipairs/# see nothing, the area fields still read.
--   * pseudorandom() reseeds the global math.random. Cosmetic only (art
--     variants, particles); see sim-feasibility §1.
--   * G.ARGS.TEMP_POOL is vanilla scratch, clobbered by any pool build, live or
--     not. It is not part of G.GAME.
local M = {}

-- Swapped areas and the card_limit used when the live area has none.
local AREAS = {
  {'jokers', 5}, {'consumeables', 2}, {'playing_cards', 52}, {'deck', 52},
  {'hand', 8}, {'shop_jokers', 2}, {'shop_vouchers', 1}, {'shop_booster', 2},
}

local areas_saved = nil -- {name = {live value}} while an outermost call holds the swap
local flip_saved = nil  -- {{center, unlocked, discovered}...} while flipped

local function core()
  if not BHCore then require('bhcore.init') end
  return BHCore
end

local function stub_area(name, default)
  local live = G[name]
  local limit = type(live) == 'table' and type(live.config) == 'table'
    and live.config.card_limit or default
  local area = {cards = {}, config = {card_limit = limit}}
  if name == 'playing_cards' then return setmetatable({}, {__index = area}) end
  return area
end

local function swap_areas(saved)
  for _, a in ipairs(AREAS) do
    saved[a[1]] = {G[a[1]]} -- boxed: a live nil is restored as nil
    G[a[1]] = stub_area(a[1], a[2])
  end
  -- The game generates shops and packs with no overlay up, and vanilla's set_ability/
  -- Card:remove skip used_jokers bookkeeping while one is (card.lua:349, 4741). The
  -- sim must model the game's state, not the live UI's: an Oracle overlay or a pause
  -- menu would otherwise silently disable duplicate exclusion in every prediction.
  saved.OVERLAY_MENU = {G.OVERLAY_MENU}
  G.OVERLAY_MENU = nil
  -- Likewise the pause: Steamodded's pseudoseed returns math.random() while
  -- G.SETTINGS.paused (lovely/fixes.toml, "prng calls on collection advancing seeds"),
  -- and every overlay pauses the game, so a simulation run under the Oracle or the
  -- Finder would draw from an unseeded RNG. Vanilla never reads the flag here.
  if G.SETTINGS then
    saved.paused = G.SETTINGS.paused
    G.SETTINGS.paused = false
  end
end

local function restore_areas(saved)
  local paused = saved.paused
  saved.paused = nil
  for name, box in pairs(saved) do G[name] = box[1] end
  if G.SETTINGS and paused ~= nil then G.SETTINGS.paused = paused end
end

local function flip_unlocks(saved)
  for _, c in pairs(G.P_CENTERS or {}) do
    if type(c) == 'table' then
      saved[#saved + 1] = {c, c.unlocked, c.discovered}
      c.unlocked, c.discovered = true, true
    end
  end
end

local function restore_unlocks(saved)
  for i = #saved, 1, -1 do
    local e = saved[i]
    e[1].unlocked, e[1].discovered = e[2], e[3]
  end
end

local function pack(...) return {n = select('#', ...), ...} end

function M.run(S, fn, ...)
  assert(type(S) == 'table' and type(S.game) == 'table', 'sandbox.run: S.game must be a table')
  assert(type(fn) == 'function', 'sandbox.run: fn must be a function')
  local B = core()
  local prev_game = G.GAME
  local own_areas, own_flip, counted = false, false, false

  -- Set up inside the pcall too, so a failure half-way is still undone below.
  local res = pack(pcall(function(...)
    -- The record is published before it is filled, so a partial swap is undone.
    if not areas_saved then areas_saved, own_areas = {}, true; swap_areas(areas_saved) end
    if S.all_unlocked and not flip_saved then flip_saved, own_flip = {}, true; flip_unlocks(flip_saved) end
    B.sim_depth = (B.sim_depth or 0) + 1; counted = true
    G.GAME = S.game
    return fn(...)
  end, ...))

  G.GAME = prev_game
  if counted then B.sim_depth = B.sim_depth - 1 end
  if own_flip then restore_unlocks(flip_saved); flip_saved = nil end
  if own_areas then restore_areas(areas_saved); areas_saved = nil end
  return unpack(res, 1, res.n)
end

return M
