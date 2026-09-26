-- checkpoint.lua: snapshot tracking (D6) and load_run (D3).
-- Stubs the vanilla save_run / Game / G.FUNCS it wraps; nothing here runs the game.
local H = ...

-- A world with stub vanilla functions that record their calls.
local function world()
  local w = {saves = 0, starts = {}, fn_starts = {}, exits = 0}
  save_run = function()
    w.saves = w.saves + 1
    if G.F_NO_SAVING == true then return end
    G.culled_table = H.fake_run{ante = w.saves}
    G.ARGS.save_run = G.culled_table
  end
  Game = {}
  Game.start_run = function(self, args) w.starts[#w.starts+1] = {self = self, args = args} end
  G.FUNCS.start_run = function(e, args) w.fn_starts[#w.fn_starts+1] = {e = e, args = args} end
  G.FUNCS.exit_overlay_menu = function() w.exits = w.exits + 1; G.OVERLAY_MENU = nil end
  love.filesystem.createDirectory('1')
  local cp = require('saveslots.checkpoint')
  return w, cp
end

H.test('no snapshot before the first save_run', function()
  local _, cp = world()
  cp.install()
  H.eq(cp.get(), nil)
end)

H.test('save_run records G.culled_table as the snapshot', function()
  local w, cp = world()
  cp.install()
  save_run()
  H.eq(w.saves, 1, 'original called')
  H.eq(cp.get(), G.culled_table)
  save_run()
  H.eq(cp.get().GAME.round_resets.ante, 2, 'latest save wins')
end)

H.test('F_NO_SAVING is respected', function()
  local w, cp = world()
  cp.install()
  G.F_NO_SAVING = true
  G.culled_table = H.fake_run{ante = 9} -- a leftover table must not be picked up
  save_run()
  H.eq(w.saves, 1, 'original still called')
  H.eq(cp.get(), nil)
end)

H.test('start_run without savetext clears a stale snapshot', function()
  local w, cp = world()
  cp.install()
  save_run()
  H.ok(cp.get(), 'snapshot from the previous run')
  local g = {}
  Game.start_run(g, {})
  H.eq(cp.get(), nil, 'stale snapshot cleared')
  H.eq(G.ARGS.save_run ~= nil, true, 'G.ARGS.save_run stays stale (vanilla), and get() ignores it')
  H.eq(#w.starts, 1, 'original called')
  H.eq(w.starts[1].self, g, 'self passed through')
  Game.start_run(g, nil)
  H.eq(cp.get(), nil, 'nil args also clears')
  H.eq(#w.starts, 2)
end)

H.test('start_run with savetext stores a deep copy before the original runs', function()
  local w, cp = world()
  local seen
  local stub = Game.start_run
  Game.start_run = function(self, args) seen = cp.get(); return stub(self, args) end
  cp.install()
  local run = H.fake_run{ante = 5}
  Game.start_run({}, {savetext = run})
  H.eq(#w.starts, 1, 'original called')
  H.eq(w.starts[1].args.savetext, run, 'original gets the same table')
  H.ok(seen and seen.GAME.round_resets.ante == 5, 'snapshot set before the original ran')
  local snap = cp.get()
  H.ok(snap ~= run, 'not the same table')
  run.GAME.round_resets.ante = 99
  run.cardAreas.jokers.cards[1].save_fields.center = 'j_mutated'
  H.eq(snap.GAME.round_resets.ante, 5, 'snapshot unchanged by mutation')
  H.eq(snap.cardAreas.jokers.cards[1].save_fields.center, 'j_joker')
end)

H.test('double install does not double-wrap', function()
  local w, cp = world()
  cp.install()
  local s1, g1 = save_run, Game.start_run
  cp.install()
  H.eq(save_run, s1, 'save_run wrapped once')
  H.eq(Game.start_run, g1, 'start_run wrapped once')
  save_run()
  H.eq(w.saves, 1, 'original save_run runs once per call')
  Game.start_run({}, {})
  H.eq(#w.starts, 1, 'original start_run runs once per call')
end)

H.test('load_run writes save.jkr, closes the overlay and starts with savetext', function()
  local w, cp = world()
  cp.install()
  local run = H.fake_run{ante = 4, seed = 'LOADME'}
  G.SAVED_GAME = {stale = true}
  G.OVERLAY_MENU = {}
  local ok, err = cp.load_run(run)
  H.eq(ok, true, tostring(err))
  H.eq(STR_UNPACK(get_compressed('1/save.jkr')).GAME.pseudorandom.seed, 'LOADME', 'save.jkr written')
  H.eq(G.SAVED_GAME, nil, 'G.SAVED_GAME cleared')
  H.eq(w.exits, 1, 'overlay closed')
  H.eq(#w.fn_starts, 1, 'G.FUNCS.start_run called')
  H.eq(w.fn_starts[1].e, nil)
  H.eq(w.fn_starts[1].args.savetext, run)
end)

H.test('load_run without an overlay does not try to close one', function()
  local w, cp = world()
  cp.install()
  G.OVERLAY_MENU = nil
  H.eq(cp.load_run(H.fake_run()), true)
  H.eq(w.exits, 0)
  H.eq(#w.fn_starts, 1)
end)

H.test('load_run uses the current profile', function()
  local _, cp = world()
  cp.install()
  G.SETTINGS.profile = 2
  love.filesystem.createDirectory('2')
  H.eq(cp.load_run(H.fake_run{ante = 6}), true)
  H.ok(love._files['2/save.jkr'], 'profile 2 save.jkr written')
  H.eq(love._files['1/save.jkr'], nil, 'profile 1 untouched')
end)

H.test('load_run refuses nil and non-tables without side effects', function()
  local w, cp = world()
  cp.install()
  for _, bad in ipairs({false, 'text', 42}) do
    local ok, err = cp.load_run(bad)
    H.eq(ok, nil); H.eq(err, 'no run')
  end
  local ok, err = cp.load_run(nil)
  H.eq(ok, nil); H.eq(err, 'no run')
  H.eq(love._files['1/save.jkr'], nil, 'nothing written')
  H.eq(#w.fn_starts, 0, 'no run started')
end)
