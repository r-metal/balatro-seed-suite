-- RunJournal jokers offered (T-372a): bh-core's shop_reroll event and the record's
-- offered = {[joker key] = count}. Stubs the vanilla functions bhcore.events wraps, with
-- an event queue that keeps engine/event.lua's blocking rules, a shop that is stocked
-- in a nested event (game.lua:3081-3114) and a reroll shaped like vanilla's
-- (button_callbacks.lua:2855); nothing here runs the game.
local H = ...

local CENTERS = {
  j_joker = {set = 'Joker'}, j_baron = {set = 'Joker'}, j_mime = {set = 'Joker'},
  j_egg = {set = 'Joker'}, c_fool = {set = 'Tarot'}, c_pluto = {set = 'Planet'},
  c_base = {set = 'Default'}, p_buffoon_normal_1 = {set = 'Booster'},
  v_overstock_norm = {set = 'Voucher'},
}

local function card(key) return {config = {center = {key = key, set = CENTERS[key].set}}} end
local function area(keys)
  local a = {cards = {}}
  for i, k in ipairs(keys or {}) do a.cards[i] = card(k) end
  return a
end

-- A world installed the way RunJournal's init does it: bh-core events, then the
-- recorder. `w.rows` holds the rows vanilla will stock next, in order (the shop's
-- entry row, then each reroll's).
local function world(opts)
  opts = opts or {}
  local w = {queue = {}, rows = {}, reroll_args = {}, saves = 0}
  G.GAME = {
    round = 0, dollars = 4, chips = 0, stake = 1, blind_on_deck = 'Small',
    round_resets = {ante = 1, blind_tags = {Small = 'tag_charm', Big = 'tag_economy'},
      blind_choices = {Small = 'bl_small', Big = 'bl_big', Boss = 'bl_hook'}},
    current_round = {dollars = 0, reroll_cost = 5}, hands = {}, shop = {joker_max = 2},
    pseudorandom = {seed = 'SEED1'}, selected_back_key = {key = 'b_red'},
  }
  G.P_CENTERS = CENTERS
  G.STATE = G.STATES.MENU
  G.jokers = {cards = {}}
  G.CONTROLLER = {locks = {}}
  G.E_MANAGER = {add_event = function(_, ev) w.queue[#w.queue + 1] = ev end}
  Event = function(cfg)
    local ev = {}
    for k, v in pairs(cfg) do ev[k] = v end
    if ev.blocking == nil then ev.blocking = true end
    if ev.blockable == nil then ev.blockable = true end
    return ev
  end
  -- One EventManager:update pass: an event is handled unless an earlier blocking one
  -- was met in this pass and it is blockable; it leaves once its func returns true. An
  -- 'after' event waits one pass first (its delay).
  function w.pass()
    local blocked, i = false, 1
    while i <= #w.queue do
      local ev, done = w.queue[i], false
      if not blocked or not ev.blockable then
        if ev.trigger == 'after' and not ev.waited then ev.waited = true
        else done = ev.func() == true end
        if ev.blocking then blocked = true end
      end
      if done then table.remove(w.queue, i) else i = i + 1 end
    end
  end
  function w.settle(max)
    for _ = 1, max or 50 do
      if #w.queue == 0 then return end
      w.pass()
    end
  end
  local function stock()
    G.shop_jokers.cards = area(table.remove(w.rows, 1)).cards
  end
  Game = {}
  Game.start_run = function(_, args)
    local run = args and args.savetext
    G.GAME.pseudorandom.seed = run and run.seed or (args and args.seed) or 'RANDOM'
    G.GAME.round_resets.ante = run and run.ante or 1
    G.GAME.round = run and run.round or 0
    G.GAME.dollars = run and run.dollars or 4
    G.STATE = run and run.state or G.STATES.BLIND_SELECT
    G.shop, G.shop_jokers = nil, nil
    if run and run.shop then
      G.shop, G.shop_jokers = {}, area(run.shop)
    end
  end
  for _, k in ipairs({'update_round_eval', 'update_game_over'}) do Game[k] = function() end end
  -- The shelf is made empty on the first frame and stocked in a nested event.
  Game.update_shop = function()
    if G.STATE_COMPLETE then return end
    local exists = G.shop ~= nil
    G.shop = G.shop or {}
    if not exists then
      G.shop_jokers = area()
      G.shop_vouchers = area({'v_overstock_norm'})
      G.shop_booster = area({'p_buffoon_normal_1'})
    end
    G.E_MANAGER:add_event(Event({func = function()
      G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.2, blockable = false, func = function()
        if not exists then stock() end
        return true
      end}))
      return true
    end}))
    G.STATE_COMPLETE = true
  end
  G.FUNCS.select_blind = function() G.GAME.round = G.GAME.round + 1 end
  G.FUNCS.skip_blind = function() end
  G.FUNCS.evaluate_play = function() end
  G.FUNCS.cash_out = function() end
  end_round, win_game = function() end, function() end
  ease_ante = function() end
  if not opts.no_reroll then
    -- Vanilla's order: pay (a queued ease_dollars), refill in an event, a 0.3 s delay
    -- whose nested event releases the lock, then save_run.
    G.FUNCS.reroll_shop = function(...)
      w.reroll_args[#w.reroll_args + 1] = {n = select('#', ...), ...}
      G.CONTROLLER.locks.shop_reroll = true
      local cost = G.GAME.current_round.reroll_cost
      G.E_MANAGER:add_event(Event({trigger = 'immediate', func = function()
        G.GAME.dollars = G.GAME.dollars - cost; return true
      end}))
      G.E_MANAGER:add_event(Event({trigger = 'immediate', func = function()
        G.shop_jokers.cards = {}
        stock()
        return true
      end}))
      G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.3, func = function()
        G.E_MANAGER:add_event(Event({func = function() G.CONTROLLER.locks.shop_reroll = false; return true end}))
        return true
      end}))
      G.E_MANAGER:add_event(Event({func = function() w.saves = w.saves + 1; return true end}))
    end
  end
  love.filesystem.createDirectory('1')
  BHCore = {sim_depth = 0}
  RunJournal = {}
  local ev = require('bhcore.events')
  ev.install()
  local rec = require('runjournal.recorder')
  rec.install()

  function w.start(seed, savetext) Game.start_run({}, {seed = seed, savetext = savetext}) end
  function w.win()
    G.blind_select = true
    G.FUNCS.select_blind({config = {ref_table = {key = 'bl_small'}}})
    G.blind_select = nil
    end_round()
    G.STATE_COMPLETE = false
    Game.update_round_eval(G)
    G.STATE_COMPLETE = true
  end
  -- Cash out into a new shop whose entry row is `row`; the shelf is not settled.
  function w.open_shop(row)
    G.shop = nil
    w.rows[#w.rows + 1] = row
    G.round_eval = true
    G.FUNCS.cash_out({})
    G.round_eval = nil
    G.STATE = G.STATES.SHOP
    G.STATE_COMPLETE = false
    Game.update_shop(G)
  end
  function w.enter(row) w.open_shop(row); w.settle() end
  function w.reroll(row)
    w.rows[#w.rows + 1] = row
    G.FUNCS.reroll_shop({config = {button = 'reroll_shop'}})
    w.settle()
  end
  -- Every shop_reroll payload, with the shop row and the lock at that moment.
  w.got = {}
  function w.listen()
    ev.on('shop_reroll', function(p)
      local live = {}
      for i, c in ipairs(G.shop_jokers.cards) do live[i] = c.config.center.key end
      w.got[#w.got + 1] = {p = p, live = table.concat(live, ','),
        locked = G.CONTROLLER.locks.shop_reroll, saves = w.saves}
    end)
  end
  return w, rec, ev
end

-- Counts love.filesystem.write calls made by fn.
local function writes(fn)
  local n, orig = 0, love.filesystem.write
  love.filesystem.write = function(...) n = n + 1; return orig(...) end
  fn()
  love.filesystem.write = orig
  return n
end

-- `t` as 'key=n' pairs, sorted ('-' for nil).
local function counts(t)
  if t == nil then return '-' end
  local out = {}
  for k, n in pairs(t) do out[#out + 1] = k..'='..tostring(n) end
  table.sort(out)
  return table.concat(out, ' ')
end

H.test('shop_reroll: once per reroll, behind vanilla refill and save, with the new row', function()
  local w, _, ev = world()
  w.listen()
  w.start('SEED1'); w.win(); w.enter({'j_joker', 'c_fool'})
  G.GAME.dollars = 20
  local e = {config = {button = 'reroll_shop'}}
  w.rows[#w.rows + 1] = {'j_baron', 'c_pluto'}
  G.FUNCS.reroll_shop(e)
  H.eq(w.reroll_args[1][1], e, 'the original gets the element'); H.eq(w.reroll_args[1].n, 1)
  H.eq(#w.got, 0, 'queued, not fired at the click')
  H.eq(#w.queue, 5, 'our event sits right behind vanilla\'s four')
  H.eq(w.queue[5].blocking, false, 'non-blocking'); H.eq(w.queue[5].blockable, true, 'blockable')
  w.settle()
  H.eq(#w.got, 1, 'one event')
  local g = w.got[1]
  H.eq(table.concat(g.p.cards, ','), 'j_baron,c_pluto', 'cards: the new row, every set')
  H.eq(g.live, 'j_baron,c_pluto', 'the row on the shelf when it fired')
  H.eq(g.p.dollars, 15, 'dollars after the cost'); H.eq(g.p.ante, 1); H.eq(g.p.round, 1)
  H.eq(g.saves, 1, 'after vanilla save_run'); H.eq(g.locked, true, 'before the lock is released')
  H.eq(G.CONTROLLER.locks.shop_reroll, false, 'vanilla released the lock afterwards')
  -- A second click queued before the first settled: two events, each with its own row.
  w.rows[#w.rows + 1] = {'j_mime', 'j_egg'}
  w.rows[#w.rows + 1] = {'c_fool', 'j_joker'}
  G.FUNCS.reroll_shop(e); G.FUNCS.reroll_shop(e)
  w.settle()
  H.eq(#w.got, 3)
  H.eq(table.concat(w.got[2].p.cards, ','), 'j_mime,j_egg'); H.eq(w.got[2].live, 'j_mime,j_egg')
  H.eq(table.concat(w.got[3].p.cards, ','), 'c_fool,j_joker'); H.eq(w.got[3].live, 'c_fool,j_joker')
  H.eq(#w.reroll_args, 3, 'the original ran once per call')
  H.ok(w.got[2].p.cards ~= w.got[3].p.cards, 'a fresh cards table per event')
  H.ok(ev.ALL.shop_reroll and not ev.NAMES.shop_reroll, 'shop_reroll is in ALL, not in the frozen NAMES')
end)

H.test('offered counts the entry row and two rerolls, and is written', function()
  local w, rec = world()
  w.start('SEED1'); w.win()
  w.enter({'j_joker', 'j_baron'})
  H.eq(counts(rec.current().offered), 'j_baron=1 j_joker=1', 'entry row')
  w.reroll({'j_joker', 'j_mime'})
  w.reroll({'j_baron', 'j_joker'})
  local r = rec.current()
  H.eq(counts(r.offered), 'j_baron=2 j_joker=3 j_mime=1', 'entry + two rerolls')
  H.eq(counts(rec.read(r.run_id).offered), 'j_baron=2 j_joker=3 j_mime=1', 'on disk')
  -- The next shop adds to the same table.
  G.shop = nil; w.win(); w.enter({'j_egg', 'j_joker'})
  H.eq(counts(rec.read(r.run_id).offered), 'j_baron=2 j_egg=1 j_joker=4 j_mime=1', 'second shop')
  H.eq(#r.jokers_seen, 2, 'jokers_seen still once per shop_enter')
end)

H.test('non-Joker cards are skipped: Tarots, Planets, playing cards, vouchers, boosters', function()
  local w, rec = world()
  w.listen()
  w.start('SEED1'); w.win()
  w.enter({'c_fool', 'j_joker'})
  w.reroll({'c_pluto', 'c_base'})
  H.eq(table.concat(w.got[1].p.cards, ','), 'c_pluto,c_base', 'the event carries every set')
  w.reroll({'c_fool', 'c_pluto'})
  H.eq(counts(rec.current().offered), 'j_joker=1', 'only the Joker, not the voucher or booster slots')
end)

H.test('the entry row waits for the stocked shelf, writes once, and gives up on a gone shop', function()
  local w, rec = world()
  w.start('SEED1'); w.win()
  local n = writes(function() w.open_shop({'j_joker', 'j_mime'}) end)
  H.ok(n > 0, 'shop_enter still writes at once')
  H.eq(rec.current().offered, nil, 'the shelf is empty when shop_enter fires')
  local passes, left = 0, 0
  n = writes(function()
    repeat w.pass(); passes = passes + 1 until #G.shop_jokers.cards > 0 or passes > 10
  end)
  H.ok(#G.shop_jokers.cards == 2 and passes > 1, 'vanilla stocked it in a later pass')
  H.eq(n, 0, 'no write while waiting')
  H.eq(rec.current().offered, nil, 'the wait sits ahead of the stocking event: not counted yet')
  n = writes(function() w.pass() end)
  H.eq(counts(rec.current().offered), 'j_joker=1 j_mime=1')
  H.ok(n > 0, 'the count is written')
  H.eq(#w.queue, 0, 'the wait is over')
  H.eq(writes(function() for _ = 1, 10 do w.pass() end end), 0, 'no write per frame')
  -- A shop left before it was stocked: nothing counted, the wait ends.
  G.shop = nil; w.win()
  w.open_shop({'j_baron', 'j_egg'})
  w.pass()
  G.shop = nil
  H.eq(writes(function() w.settle() end), 0, 'nothing written')
  for _ = 1, 3 do left = left + #w.queue; w.pass() end
  H.eq(left, 0, 'no wait left in the queue')
  H.eq(counts(rec.current().offered), 'j_joker=1 j_mime=1', 'the gone shop added nothing')
end)

H.test('a loaded run continues its offered table', function()
  local w, rec = world()
  w.start('SEED1'); w.win()
  w.enter({'j_joker', 'j_baron'})
  w.reroll({'j_joker', 'c_fool'})
  local id = rec.current().run_id
  -- Continue from a save sitting in that shop, with the rerolled row on the shelf.
  w.start('SEED1', {seed = 'SEED1', ante = 1, round = 1, dollars = 9, state = G.STATES.SHOP,
    shop = {'j_joker', 'c_fool'}})
  local r = rec.current()
  H.eq(r.run_id, id, 'same record'); H.eq(r.loads, 1)
  H.eq(counts(r.offered), 'j_baron=1 j_joker=2', 'kept from disk')
  w.reroll({'j_mime', 'j_baron'})
  H.eq(counts(rec.read(id).offered), 'j_baron=2 j_joker=2 j_mime=1', 'adds to the same table')
end)

H.test('an old record without offered loads and gains it at its next shop', function()
  local w, rec = world()
  assert(rec.save({run_id = 'OLD1:5', seed = 'OLD1', deck = 'b_red', stake = 1, started_at = 5,
    final_ante = 1, final_round = 1, antes = {[1] = {dollars_start = 4, blinds = {
      {kind = 'Small', key = 'bl_small', skipped = false, won = true, hands = {}}}}},
    jokers_seen = {}, origin = {}}))
  H.eq(rec.read('OLD1:5').offered, nil, 'saved without offered')
  w.start('OLD1', {seed = 'OLD1', ante = 1, round = 1, dollars = 9, state = G.STATES.BLIND_SELECT})
  local r = rec.current()
  H.eq(r.run_id, 'OLD1:5', 'continued'); H.eq(r.loads, 1)
  H.eq(r.offered, nil, 'not rewritten on load')
  H.eq(#rec.list(), 1)
  w.win(); w.enter({'j_egg', 'c_pluto'})
  H.eq(counts(rec.read('OLD1:5').offered), 'j_egg=1', 'only what came after the load')
  H.eq(#rec.read('OLD1:5').antes[1].blinds, 2, 'the old blinds kept')
end)

H.test('shop_reroll is not emitted inside the sim sandbox', function()
  local w, rec = world()
  w.listen()
  w.start('SEED1'); w.win(); w.enter({'j_joker', 'j_baron'})
  BHCore.sim_depth = 1
  w.rows[#w.rows + 1] = {'j_mime', 'j_egg'}
  G.FUNCS.reroll_shop()
  H.eq(#w.queue, 4, 'only vanilla queued events')
  w.settle()
  H.eq(#w.reroll_args, 1, 'the original still ran')
  H.eq(#w.got, 0, 'no event')
  H.eq(counts(rec.current().offered), 'j_baron=1 j_joker=1', 'nothing counted')
  BHCore.sim_depth = 0
  w.reroll({'j_mime', 'c_fool'})
  H.eq(#w.got, 1, 'fires again once depth is 0')
  H.eq(counts(rec.current().offered), 'j_baron=1 j_joker=1 j_mime=1')
end)

H.test('a shop_reroll handler error does not break the reroll', function()
  local w, rec, ev = world()
  local printed, after = {}, 0
  ev.on('shop_reroll', function() error('boom') end)
  ev.on('shop_reroll', function() after = after + 1 end)
  w.start('SEED1'); w.win(); w.enter({'j_joker', 'c_fool'})
  G.GAME.dollars = 20
  local old_print = print
  print = function(s) printed[#printed + 1] = tostring(s) end
  local ok, err = pcall(w.reroll, {'j_baron', 'j_mime'})
  print = old_print
  H.ok(ok, 'the reroll does not raise: '..tostring(err))
  H.eq(after, 1, 'the next handler still ran')
  H.eq(counts(rec.current().offered), 'j_baron=1 j_joker=1 j_mime=1', 'the recorder still counted')
  H.eq(G.shop_jokers.cards[1].config.center.key, 'j_baron', 'vanilla refilled the row')
  H.eq(G.GAME.dollars, 15, 'paid'); H.eq(w.saves, 1, 'saved')
  H.eq(G.CONTROLLER.locks.shop_reroll, false, 'the lock was released')
  H.eq(#w.queue, 0)
  H.eq(#printed, 1, 'one line printed')
  H.ok(printed[1]:find('[bh-core]', 1, true) and printed[1]:find('shop_reroll', 1, true)
    and printed[1]:find('boom', 1, true), printed[1])
end)

H.test('events.NAMES stays the 0.2.0 eight; on() takes ALL', function()
  local _, _, ev = world()
  local n, all = 0, 0
  for _ in pairs(ev.NAMES) do n = n + 1 end
  for name in pairs(ev.ALL) do all = all + 1 end
  H.eq(n, 8, 'NAMES'); H.eq(all, 9, 'ALL')
  for name in pairs(ev.NAMES) do H.ok(ev.ALL[name], name..' in ALL') end
  local tok = ev.on('shop_reroll', function() end)
  H.eq(tok.name, 'shop_reroll')
  ev.off(tok)
  H.ok(not pcall(ev.on, 'shop_rerolled', function() end), 'unknown names still error')
end)

H.test('a world without reroll_shop installs, and the other events still fire', function()
  local w, rec = world({no_reroll = true})
  H.eq(G.FUNCS.reroll_shop, nil, 'nothing wrapped into existence')
  w.start('SEED1'); w.win(); w.enter({'j_joker', 'j_baron'})
  H.eq(#rec.current().jokers_seen, 1, 'shop_enter fired')
  H.eq(counts(rec.current().offered), 'j_baron=1 j_joker=1')
end)
