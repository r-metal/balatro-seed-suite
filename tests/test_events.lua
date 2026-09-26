-- events.lua: subscription, error isolation, idempotent install, sim_depth
-- suppression, and "exactly once" for every event. Stubs the vanilla functions
-- it wraps (just enough state for each); nothing here runs the game.
local H = ...

-- A world of stub vanilla functions that record their calls and mimic the bits
-- of vanilla behaviour the hooks rely on.
local function world()
  local w = {calls = {}, queue = {}}
  local function called(name, ...) w.calls[#w.calls + 1] = {name = name, n = select('#', ...), ...} end
  G.GAME = {
    round = 0, dollars = 4, chips = 0, stake = 1, blind_on_deck = 'Small',
    round_resets = {ante = 1, blind_tags = {Small = 'tag_economy', Big = 'tag_foil'}},
    current_round = {dollars = 0}, pseudorandom = {seed = 'SEED1'},
    selected_back_key = {key = 'b_red', name = 'Red Deck'},
  }
  G.STATE_COMPLETE = false
  G.E_MANAGER = {add_event = function(_, ev) w.queue[#w.queue + 1] = ev end}
  Event = function(cfg) return cfg end
  function w.flush()  -- run queued events in order, like EventManager:update
    while #w.queue > 0 do
      local ev = table.remove(w.queue, 1)
      ev.func()
    end
  end
  Game = {}
  Game.start_run = function(self, args)
    called('start_run', self, args)
    G.GAME.pseudorandom.seed = args and args.seed or 'RANDOM'
    return 'start_run result'
  end
  Game.update_round_eval = function(self, dt) called('update_round_eval', self, dt); G.STATE_COMPLETE = true end
  Game.update_game_over = function(self, dt) called('update_game_over', self, dt); G.STATE_COMPLETE = true end
  Game.update_shop = function(self, dt) called('update_shop', self, dt); G.STATE_COMPLETE = true end
  G.FUNCS.select_blind = function(e) called('select_blind', e) end
  G.FUNCS.skip_blind = function(e)
    called('skip_blind', e)
    if e and e.has_tag then
      G.GAME.blind_on_deck = G.GAME.blind_on_deck == 'Small' and 'Big' or 'Boss'
    end
  end
  G.FUNCS.evaluate_play = function(e)
    called('evaluate_play', e)
    G.GAME.last_hand_played = 'Pair'
    hand_chips, mult = 32, 2.5
  end
  G.FUNCS.cash_out = function(e) called('cash_out', e) end
  end_round = function() called('end_round') end
  ease_ante = function(mod)
    called('ease_ante', mod)
    G.E_MANAGER:add_event(Event({func = function()
      G.GAME.round_resets.ante = G.GAME.round_resets.ante + (mod or 0); return true
    end}))
  end
  win_game = function() called('win_game') end
  local ev = require('bhcore.events')
  -- Record every event.
  w.got = {}
  function w.listen()
    for name in pairs(ev.NAMES) do
      ev.on(name, function(p) w.got[#w.got + 1] = {name = name, p = p} end)
    end
  end
  function w.count(name)
    local n = 0
    for _, g in ipairs(w.got) do if g.name == name then n = n + 1 end end
    return n
  end
  function w.last(name)
    for i = #w.got, 1, -1 do if w.got[i].name == name then return w.got[i].p end end
  end
  return w, ev
end

H.test('on/off: handler gets the payload, stops after off, off is idempotent', function()
  local w, ev = world()
  ev.install()
  local seen = {}
  local tok = ev.on('run_end', function(p) seen[#seen + 1] = p end)
  win_game()
  H.eq(#seen, 1, 'fired once')
  H.eq(seen[1].won, true, 'won')
  H.eq(seen[1].seed, 'SEED1', 'seed')
  ev.off(tok)
  ev.off(tok)
  G.GAME.round_resets.ante = 1
  Game.start_run({}, {}) -- resets per-run state, so a second win would fire
  win_game()
  H.eq(#seen, 1, 'not called after off')
  H.eq(#w.calls, 3, 'originals still called')
end)

H.test('on rejects unknown names and non-functions', function()
  local _, ev = world()
  H.ok(not pcall(ev.on, 'round_ended', function() end), 'unknown name errors')
  H.ok(not pcall(ev.on, 'round_end', 'nope'), 'non-function errors')
end)

H.test('a handler error is isolated and printed with [bh-core]', function()
  local w, ev = world()
  ev.install()
  local printed = {}
  local old_print = print
  print = function(s) printed[#printed + 1] = tostring(s) end
  local second = 0
  ev.on('run_start', function() error('boom') end)
  ev.on('run_start', function() second = second + 1 end)
  local ok, res = pcall(Game.start_run, {}, {seed = 'X'})
  print = old_print
  H.ok(ok, 'the game call does not break')
  H.eq(res, 'start_run result', 'original result returned')
  H.eq(second, 1, 'next handler still ran')
  H.eq(#printed, 1, 'one line printed')
  H.ok(printed[1]:find('[bh-core]', 1, true) and printed[1]:find('boom', 1, true), printed[1])
end)

H.test('install twice wraps once', function()
  local w, ev = world()
  local orig = Game.start_run
  ev.install()
  local wrapped = Game.start_run
  ev.install()
  H.ok(Game.start_run ~= orig, 'wrapped')
  H.eq(Game.start_run, wrapped, 'second install is a no-op')
  w.listen()
  Game.start_run({}, {})
  ease_ante(1); w.flush()
  H.eq(w.count('run_start'), 1)
  H.eq(w.count('ante_change'), 1)
  H.eq(#w.calls, 2, 'originals called once each')
end)

H.test('nothing fires or is recorded while BHCore.sim_depth > 0', function()
  local w, ev = world()
  ev.install()
  w.listen()
  BHCore = {sim_depth = 1}
  Game.start_run({}, {})
  G.blind_select = {}
  G.FUNCS.select_blind({config = {ref_table = {key = 'bl_small'}}})
  G.FUNCS.evaluate_play()
  end_round()
  G.round_eval = {}
  G.FUNCS.cash_out()
  ease_ante(1)
  win_game()
  H.eq(#w.queue, 1, 'only vanilla queued an event')
  w.flush()
  H.eq(#w.got, 0, 'no events inside the sandbox')
  H.eq(#w.calls, 7, 'originals still called')
  BHCore.sim_depth = 0
  Game.update_round_eval({}); Game.update_shop({})
  H.eq(#w.got, 0, 'no pending round or shop was recorded in the sandbox')
  win_game()
  H.eq(w.count('run_end'), 1, 'fires again once depth is 0')
end)

H.test('run_start: new and loaded runs, args passed through', function()
  local w, ev = world()
  ev.install()
  w.listen()
  local g, args = {}, {seed = 'ABC', stake = 1}
  H.eq(Game.start_run(g, args), 'start_run result')
  H.eq(w.calls[1][1], g, 'self'); H.eq(w.calls[1][2], args, 'args')
  local p = w.last('run_start')
  H.eq(p.seed, 'ABC'); H.eq(p.stake, 1); H.eq(p.deck, 'b_red'); H.eq(p.loaded, false); H.eq(p.ante, 1)
  Game.start_run(g, {savetext = {}})
  H.eq(w.last('run_start').loaded, true, 'loaded')
  Game.start_run(g, nil)
  H.eq(w.last('run_start').loaded, false, 'nil args')
  H.eq(w.count('run_start'), 3)
end)

H.test('blind_selected: once per selection, only with a blind select panel', function()
  local w, ev = world()
  ev.install()
  w.listen()
  local e = {config = {ref_table = {key = 'bl_big'}}}
  G.GAME.blind_on_deck = 'Big'
  G.FUNCS.select_blind(e)
  H.eq(w.count('blind_selected'), 0, 'no panel: vanilla does nothing')
  G.blind_select = {}
  G.FUNCS.select_blind(e)
  G.FUNCS.select_blind(e) -- double click before vanilla's event bumps the round
  H.eq(w.count('blind_selected'), 1)
  local p = w.last('blind_selected')
  H.eq(p.blind, 'bl_big'); H.eq(p.kind, 'Big'); H.eq(p.ante, 1)
  G.GAME.round = 1; G.GAME.blind_on_deck = 'Boss'
  G.FUNCS.select_blind({config = {ref_table = {key = 'bl_hook'}}})
  H.eq(w.count('blind_selected'), 2, 'next selection fires')
  H.eq(w.last('blind_selected').kind, 'Boss')
  H.eq(#w.calls, 4, 'original called every time')
end)

H.test('blind_skipped: fires with the tag only when vanilla skipped', function()
  local w, ev = world()
  ev.install()
  w.listen()
  G.FUNCS.skip_blind({has_tag = false})
  H.eq(w.count('blind_skipped'), 0, 'no tag container: no skip')
  G.FUNCS.skip_blind({has_tag = true})
  H.eq(w.count('blind_skipped'), 1)
  local p = w.last('blind_skipped')
  H.eq(p.kind, 'Small'); H.eq(p.tag, 'tag_economy'); H.eq(p.ante, 1)
  G.FUNCS.skip_blind({has_tag = true})
  H.eq(w.last('blind_skipped').kind, 'Big')
  H.eq(w.last('blind_skipped').tag, 'tag_foil')
end)

H.test('hand_scored: final chips/mult, score and running total', function()
  local w, ev = world()
  ev.install()
  w.listen()
  G.GAME.chips = 100; G.GAME.round = 2
  G.FUNCS.evaluate_play('e')
  H.eq(w.calls[1][1], 'e', 'argument passed through')
  local p = w.last('hand_scored')
  H.eq(p.hand, 'Pair'); H.eq(p.chips, 32); H.eq(p.mult, 2.5)
  H.eq(p.score, 80); H.eq(p.total, 180); H.eq(p.ante, 1); H.eq(p.round, 2)
end)

H.test('round_end won: repeated end_round calls give one event, on round eval', function()
  local w, ev = world()
  ev.install()
  w.listen()
  G.GAME.round = 3
  end_round(); end_round(); end_round()
  H.eq(w.count('round_end'), 0, 'outcome not known yet')
  G.GAME.dollars = 9
  G.STATE_COMPLETE = false
  Game.update_round_eval({}, 0.016)
  Game.update_round_eval({}, 0.016)
  H.eq(w.count('round_end'), 1)
  local p = w.last('round_end')
  H.eq(p.won, true); H.eq(p.ante, 1); H.eq(p.round, 3); H.eq(p.dollars, 9)
  G.STATE_COMPLETE = false
  Game.update_round_eval({}, 0.016) -- e.g. a loaded save in ROUND_EVAL
  H.eq(w.count('round_end'), 1, 'no end_round, no event')
end)

H.test('game over: round_end lost, then run_end lost, once', function()
  local w, ev = world()
  ev.install()
  w.listen()
  G.GAME.round = 4
  end_round()
  G.STATE_COMPLETE = false
  Game.update_game_over({}, 0.016)
  Game.update_game_over({}, 0.016)
  H.eq(#w.got, 2)
  H.eq(w.got[1].name, 'round_end'); H.eq(w.got[1].p.won, false); H.eq(w.got[1].p.round, 4)
  H.eq(w.got[2].name, 'run_end'); H.eq(w.got[2].p.won, false); H.eq(w.got[2].p.seed, 'SEED1')
  G.STATE_COMPLETE = false
  Game.update_game_over({}, 0.016)
  H.eq(w.count('run_end'), 1, 'one game over per run')
end)

H.test('shop_enter: once after cash out, not after a booster pack closes', function()
  local w, ev = world()
  ev.install()
  w.listen()
  G.STATE_COMPLETE = false
  Game.update_shop({}) -- a shop without a cash out (loaded save)
  H.eq(w.count('shop_enter'), 0)
  G.FUNCS.cash_out({}) -- no round_eval: vanilla does nothing
  G.round_eval = {}
  G.GAME.dollars = 10; G.GAME.current_round.dollars = 7; G.GAME.round = 2
  G.FUNCS.cash_out({})
  H.eq(w.count('shop_enter'), 0, 'not open yet')
  G.STATE_COMPLETE = false
  Game.update_shop({}); Game.update_shop({})
  H.eq(w.count('shop_enter'), 1)
  local p = w.last('shop_enter')
  H.eq(p.dollars, 17, 'payout included'); H.eq(p.round, 2); H.eq(p.ante, 1)
  G.STATE_COMPLETE = false -- back from a booster pack
  Game.update_shop({})
  H.eq(w.count('shop_enter'), 1)
end)

H.test('ante_change: after vanilla applies it, never for a zero delta', function()
  local w, ev = world()
  ev.install()
  w.listen()
  ease_ante(0); ease_ante(nil)
  w.flush()
  H.eq(w.count('ante_change'), 0, 'zero delta')
  ease_ante(1)
  H.eq(w.count('ante_change'), 0, 'queued, not fired at call time')
  H.eq(#w.queue, 2, 'our event sits right behind vanilla')
  H.eq(w.queue[2].blocking, false)
  w.flush()
  local p = w.last('ante_change')
  H.eq(p.from, 1); H.eq(p.to, 2)
  ease_ante(-1); w.flush()
  p = w.last('ante_change')
  H.eq(p.from, 2); H.eq(p.to, 1)
  H.eq(w.count('ante_change'), 2)
end)

H.test('run_end won: once per run even if win_game is called again', function()
  local w, ev = world()
  ev.install()
  w.listen()
  win_game(); win_game()
  H.eq(w.count('run_end'), 1)
  H.eq(w.last('run_end').won, true)
  G.STATE_COMPLETE = false
  Game.update_game_over({}) -- endless mode game over later
  H.eq(w.count('run_end'), 2)
  H.eq(w.last('run_end').won, false)
end)

H.test('unsubscribing from inside a handler skips nobody', function()
  local w, ev = world()
  ev.install()
  local order = {}
  local t1
  t1 = ev.on('run_start', function() order[#order + 1] = 1; ev.off(t1) end)
  ev.on('run_start', function() order[#order + 1] = 2 end)
  Game.start_run({}, {})
  Game.start_run({}, {})
  H.eq(table.concat(order, ','), '1,2,2')
end)
