-- Game event hooks for the suite. Contract: docs/bh-core.md § events.
--
-- API
--   events.install()      Wraps the vanilla functions below. Idempotent: later
--                         calls are no-ops.
--   events.on(name, fn)   Subscribes `fn(payload)` to one of `events.ALL`.
--                         Returns a token. Unknown names are an error.
--   events.off(token)     Unsubscribes. Safe to call twice, or from a handler.
--   events.NAMES          The 0.2.0 events, frozen: code that subscribes to
--                         every name in it and counts each one (the `events`
--                         scenario) relies on it never growing.
--   events.ALL            NAMES plus the events added since (0.4.0:
--                         shop_reroll).
--
-- Every hook calls the original with all its arguments first (invariant 3) and
-- never copies a vanilla body (invariant 2). Nothing fires, and no pending
-- state is recorded, while `BHCore.sim_depth > 0` (a sim sandbox call).
-- Handlers run in subscription order, each under pcall; an error is printed
-- with `[bh-core]` and the next handler still runs.
--
-- Where each event comes from (vanilla build/game, 1.0.1o)
--   run_start       `Game:start_run` (game.lua:2018), after it returns. Covers
--                   new runs and loaded ones (Continue passes `args.savetext`).
--                   Also resets this module's per-run bookkeeping.
--   blind_selected  `G.FUNCS.select_blind` (button_callbacks.lua:2513). Only
--                   when `G.blind_select` exists (vanilla's own guard). The
--                   key is (round, blind_on_deck): vanilla bumps the round in a
--                   queued event, so a second click in the same frame is not a
--                   second selection.
--   blind_skipped   `G.FUNCS.skip_blind` (button_callbacks.lua:2740). Only when
--                   the call moved `G.GAME.blind_on_deck` on (vanilla skips only
--                   when the panel has a tag container).
--   hand_scored     `G.FUNCS.evaluate_play` (state_events.lua:571), after it
--                   returns. Scoring is synchronous there: the globals
--                   `hand_chips` and `mult` hold the final values, and
--                   `G.GAME.chips` is only eased to `chips + floor(hand_chips *
--                   mult)` later by an event (state_events.lua:1044), so
--                   `total` is computed from the value read before the call.
--   round_end       `end_round` (state_events.lua:87) marks a round as ending,
--                   capturing ante/round. Vanilla decides the outcome inside a
--                   queued event, and `Game:update_selecting_hand` can call
--                   end_round on several frames in a row (game.lua:3057), so the
--                   event fires from the first state the outcome leads to:
--                   won  = the first `Game:update_round_eval` frame
--                          (game.lua:3302, `not G.STATE_COMPLETE`);
--                   lost = the first `Game:update_game_over` frame (game.lua:3581).
--                   "won" means the run goes on (Mr. Bones' save counts). A
--                   loaded save sitting in ROUND_EVAL fires nothing: no
--                   end_round happened in this session.
--   shop_enter      `G.FUNCS.cash_out` (button_callbacks.lua:2912) marks the shop
--                   as pending; it fires on the first `Game:update_shop` frame
--                   (game.lua:3072). update_shop also restarts after every
--                   booster pack closes, which must not count. `dollars`
--                   includes the cash-out payout (`G.GAME.current_round.dollars`,
--                   which vanilla adds through a queued ease_dollars).
--                   The shelf is not stocked yet: vanilla fills G.shop_jokers
--                   in a nested event once the shop has slid in (game.lua:
--                   3081-3114). A reader of the shop row waits for it.
--   shop_reroll     `G.FUNCS.reroll_shop` (button_callbacks.lua:2855), the
--   (0.4.0)         Reroll button. Vanilla empties and refills G.shop_jokers
--                   inside a queued event, then queues a 0.3 s delay and a
--                   save_run, so this queues its own event right behind them
--                   (non-blocking, blockable: it runs only once all three are
--                   done) and fires with the row as it is then: `cards` = the
--                   center keys of G.shop_jokers' cards, in slot order, every
--                   set (Jokers, Tarots, Planets, playing cards). ante and
--                   round are read at the click, dollars at the firing (the
--                   reroll's cost already paid). The controller lock vanilla
--                   sets at the click is released by an event queued behind
--                   ours, so the player cannot buy from the new row before it
--                   fires. Only wrapped when G.FUNCS.reroll_shop exists (a
--                   world without a shop, like the 0.2.0 unit stubs, gets no
--                   shop_reroll).
--   ante_change     `ease_ante(mod)` (common_events.lua:191). Vanilla applies
--                   the change in a queued event, so this queues its own event
--                   right behind it and fires with the applied ante. `mod` of
--                   0 or nil is no change and fires nothing. Callers: boss win
--                   in end_round, Hieroglyph/Petroglyph (card.lua:1958).
--   run_end         won:  `win_game` (state_events.lua:1), once per run
--                         (vanilla guards it with win_notified; the debug
--                         DT_win_game can call it again). Endless mode can
--                         still end in a game over later: that fires once more,
--                         with won = false.
--                   lost: the first `Game:update_game_over` frame, after the
--                         pending round_end. Covers end_round's game over,
--                         zero hand size (state_events.lua:358) and
--                         DT_lose_game.
--
-- Traps
--   * `ease_ante`'s own event is created unpaused, so it waits out a pause; ours
--     is created at the same moment, sits right behind it in the same queue,
--     and is non-blocking but blockable: it can never run before vanilla's.
--   * A round's outcome must not be read from an event queued in end_round:
--     update_game_over pauses the game, and an event created unpaused is then
--     skipped forever (engine/event.lua:50).
local events = {}

events.NAMES = {
  run_start = true, blind_selected = true, blind_skipped = true, hand_scored = true,
  round_end = true, shop_enter = true, ante_change = true, run_end = true,
}

-- NAMES plus the events added since 0.2.0 (NAMES itself stays frozen, see API).
events.ALL = {shop_reroll = true}
for name in pairs(events.NAMES) do events.ALL[name] = true end

local handlers = {}  -- name -> array of tokens, in subscription order
for name in pairs(events.ALL) do handlers[name] = {} end

local installed = false
-- Per-run bookkeeping, reset by run_start.
local pending_round = nil   -- {ante, round} between end_round and its outcome
local pending_shop = nil    -- {ante, round, dollars} between cash_out and the shop
local last_selected = nil   -- 'round:kind' of the last blind_selected
local run_ended = {}        -- [won] = true once that run_end fired

local function in_sim()
  return BHCore ~= nil and (BHCore.sim_depth or 0) > 0
end

local function emit(name, payload)
  if in_sim() then return end
  local list = handlers[name]
  -- Copy, so a handler that subscribes or unsubscribes doesn't skip anyone.
  local snapshot = {}
  for i = 1, #list do snapshot[i] = list[i] end
  for _, token in ipairs(snapshot) do
    if token.active then
      local ok, err = pcall(token.fn, payload)
      if not ok then print('[bh-core] events: '..name..' handler failed: '..tostring(err)) end
    end
  end
end

function events.on(name, fn)
  assert(events.ALL[name], 'bhcore.events: unknown event '..tostring(name))
  assert(type(fn) == 'function', 'bhcore.events: handler must be a function')
  local token = {name = name, fn = fn, active = true}
  local list = handlers[name]
  list[#list + 1] = token
  return token
end

function events.off(token)
  if type(token) ~= 'table' or not token.active then return end
  token.active = false
  local list = handlers[token.name]
  for i = #list, 1, -1 do
    if list[i] == token then table.remove(list, i) end
  end
end

local function ante() return G.GAME.round_resets.ante end

-- The center keys of the shop's card slots, in slot order (a fresh table).
local function shop_keys()
  local out = {}
  local cards = G.shop_jokers and G.shop_jokers.cards
  if type(cards) ~= 'table' then return out end
  for _, c in ipairs(cards) do
    local key = c.config and c.config.center and c.config.center.key
    if key then out[#out + 1] = key end
  end
  return out
end

local function end_run(won)
  if run_ended[won] then return end
  run_ended[won] = true
  emit('run_end', {won = won, ante = ante(), round = G.GAME.round, seed = G.GAME.pseudorandom.seed})
end

local function flush_round(won)
  local p = pending_round
  if not p then return end
  pending_round = nil
  emit('round_end', {ante = p.ante, round = p.round, won = won, dollars = G.GAME.dollars})
end

local function pack(...) return {n = select('#', ...), ...} end

-- Wraps `tbl[key]` with before(...) -> ctx and after(ctx, ...), returning the
-- original's results unchanged.
local function wrap(tbl, key, before, after)
  local orig = tbl[key]
  assert(type(orig) == 'function', 'bhcore.events: vanilla '..key..' missing')
  tbl[key] = function(...)
    local ctx = (not in_sim()) and before and before(...) or nil
    local out = pack(orig(...))
    if ctx ~= nil and not in_sim() then after(ctx, ...) end
    return unpack(out, 1, out.n)
  end
end

function events.install()
  if installed then return end
  installed = true

  wrap(Game, 'start_run', function(_, args) return {loaded = type(args) == 'table' and args.savetext ~= nil} end,
    function(ctx)
      pending_round, pending_shop, last_selected, run_ended = nil, nil, nil, {}
      local back = G.GAME.selected_back_key
      emit('run_start', {
        seed = G.GAME.pseudorandom.seed, stake = G.GAME.stake,
        deck = type(back) == 'table' and back.key or back,
        loaded = ctx.loaded, ante = ante(),
      })
    end)

  wrap(G.FUNCS, 'select_blind', function(e)
    if not G.blind_select then return end
    local kind = G.GAME.blind_on_deck
    local key = tostring(G.GAME.round)..':'..tostring(kind)
    if key == last_selected then return end
    local ref = e and e.config and e.config.ref_table
    return {kind = kind, key = key, ante = ante(), blind = type(ref) == 'table' and ref.key or nil}
  end, function(ctx)
    last_selected = ctx.key
    emit('blind_selected', {ante = ctx.ante, blind = ctx.blind, kind = ctx.kind})
  end)

  wrap(G.FUNCS, 'skip_blind', function()
    local kind = G.GAME.blind_on_deck or 'Small'
    return {kind = kind, ante = ante(), tag = G.GAME.round_resets.blind_tags and G.GAME.round_resets.blind_tags[kind]}
  end, function(ctx)
    if G.GAME.blind_on_deck == ctx.kind then return end -- vanilla did not skip
    emit('blind_skipped', {ante = ctx.ante, kind = ctx.kind, tag = ctx.tag})
  end)

  wrap(G.FUNCS, 'evaluate_play', function() return {chips0 = G.GAME.chips or 0} end,
    function(ctx)
      local c, m = hand_chips or 0, mult or 0
      local score = math.floor(c * m)
      emit('hand_scored', {
        ante = ante(), round = G.GAME.round, hand = G.GAME.last_hand_played,
        chips = c, mult = m, score = score, total = ctx.chips0 + score,
      })
    end)

  wrap(_G, 'end_round', function()
    if pending_round then return end
    return {ante = ante(), round = G.GAME.round}
  end, function(ctx) pending_round = ctx end)

  wrap(Game, 'update_round_eval', function() return not G.STATE_COMPLETE or nil end,
    function() flush_round(true) end)

  wrap(Game, 'update_game_over', function() return not G.STATE_COMPLETE or nil end,
    function()
      flush_round(false)
      end_run(false)
    end)

  wrap(G.FUNCS, 'cash_out', function()
    if not G.round_eval then return end
    return {ante = ante(), round = G.GAME.round,
      dollars = (G.GAME.dollars or 0) + (G.GAME.current_round.dollars or 0)}
  end, function(ctx) pending_shop = ctx end)

  wrap(Game, 'update_shop', function() return (pending_shop and not G.STATE_COMPLETE) or nil end,
    function()
      local p = pending_shop
      pending_shop = nil
      emit('shop_enter', {ante = p.ante, round = p.round, dollars = p.dollars})
    end)

  if type(G.FUNCS.reroll_shop) == 'function' then
    wrap(G.FUNCS, 'reroll_shop', function() return {ante = ante(), round = G.GAME.round} end,
      function(ctx)
        G.E_MANAGER:add_event(Event({
          trigger = 'immediate', blocking = false,
          func = function()
            emit('shop_reroll', {ante = ctx.ante, round = ctx.round, dollars = G.GAME.dollars,
              cards = shop_keys()})
            return true
          end,
        }))
      end)
  end

  wrap(_G, 'ease_ante', function(mod)
    if not mod or mod == 0 then return end
    return mod
  end, function(mod)
    G.E_MANAGER:add_event(Event({
      trigger = 'immediate', blocking = false,
      func = function()
        local to = ante()
        emit('ante_change', {from = to - mod, to = to})
        return true
      end,
    }))
  end)

  wrap(_G, 'win_game', function() return true end, function() end_run(true) end)
end

return events
