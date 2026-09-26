-- Auto-checkpoints (T-121): checkpoint.lua's arming on bh-core run_start/ante_change,
-- the save path (checkpoint.auto_save) and store.prune_checkpoints. Stubs the vanilla
-- functions bhcore.events and checkpoint wrap; nothing here runs the game.
local H = ...

-- A world installed the way SaveSlots' init does it: bh-core events first, then
-- checkpoint. save_run builds a fake run from G.STATE and the live ante.
local function world()
  local w = {queue = {}, saves = 0}
  G.GAME = {
    round = 0, dollars = 4, chips = 0, stake = 1, blind_on_deck = 'Small',
    round_resets = {ante = 1, blind_tags = {}}, current_round = {dollars = 0},
    pseudorandom = {seed = 'SEED1'}, selected_back_key = {key = 'b_red'},
  }
  G.STATE = G.STATES.MENU
  G.E_MANAGER = {add_event = function(_, ev) w.queue[#w.queue + 1] = ev end}
  Event = function(cfg) return cfg end
  function w.flush()
    while #w.queue > 0 do table.remove(w.queue, 1).func() end
  end
  save_run = function()
    w.saves = w.saves + 1
    if G.F_NO_SAVING == true then return end
    G.culled_table = H.fake_run{ante = G.GAME.round_resets.ante, seed = G.GAME.pseudorandom.seed,
      state = G.STATE}
    G.ARGS.save_run = G.culled_table
  end
  Game = {}
  Game.start_run = function(_, args)
    local run = args and args.savetext
    G.GAME.pseudorandom.seed = run and run.GAME.pseudorandom.seed or (args and args.seed) or 'RANDOM'
    G.GAME.round_resets.ante = run and run.GAME.round_resets.ante or 1
  end
  for _, k in ipairs({'update_round_eval', 'update_game_over', 'update_shop'}) do Game[k] = function() end end
  for _, k in ipairs({'select_blind', 'skip_blind', 'evaluate_play', 'cash_out'}) do G.FUNCS[k] = function() end end
  G.FUNCS.start_run = function() end
  end_round, win_game = function() end, function() end
  ease_ante = function(mod)
    G.E_MANAGER:add_event(Event({func = function()
      G.GAME.round_resets.ante = G.GAME.round_resets.ante + mod; return true
    end}))
  end
  love.filesystem.createDirectory('1')
  SaveSlots = {}
  BHCore = {sim_depth = 0}
  require('bhcore.events').install()
  local cp = require('saveslots.checkpoint')
  cp.install()
  local store = require('saveslots.store')
  -- The game's autosave at a given state.
  function w.autosave(state)
    G.STATE = G.STATES[state]
    save_run()
  end
  function w.next_ante()
    ease_ante(1)
    w.flush()
  end
  return w, cp, store
end

local function checkpoints(store)
  return store.list({kind = 'checkpoint'})
end

H.test('a new run checkpoints its first blind select as "Auto A1", once', function()
  local w, cp, store = world()
  Game.start_run({}, {seed = 'SEED1'})
  H.ok(cp.run_id():match('^SEED1:%d+$'), 'run id is seed:time, got '..tostring(cp.run_id()))
  w.autosave('SHOP')
  H.eq(#checkpoints(store), 0, 'a non-blind-select snapshot is not a checkpoint')
  w.autosave('BLIND_SELECT')
  local list = checkpoints(store)
  H.eq(#list, 1)
  H.eq(list[1].name, 'Auto A1')
  H.eq(list[1].meta.run_id, cp.run_id())
  H.eq(store.read(list[1].id).GAME.round_resets.ante, 1, 'holds ante 1')
  w.autosave('BLIND_SELECT') -- e.g. after skipping the Small Blind
  H.eq(#checkpoints(store), 1, 'one per ante')
  H.eq(w.saves, 3, 'every save_run still reaches the original')
end)

H.test('ante_change arms the next blind-select snapshot, holding the new ante', function()
  local w, cp, store = world()
  Game.start_run({}, {seed = 'SEED1'})
  w.autosave('BLIND_SELECT')
  for a = 2, 3 do
    w.autosave('SELECTING_HAND')
    w.next_ante()
    w.autosave('ROUND_EVAL')
    w.autosave('SHOP')
    H.eq(#checkpoints(store), a - 1, 'nothing before blind select')
    w.autosave('BLIND_SELECT')
    w.autosave('BLIND_SELECT')
  end
  local list = checkpoints(store)
  H.eq(#list, 3)
  for _, e in ipairs(list) do
    local ante = store.read(e.id).GAME.round_resets.ante
    H.eq(e.name, 'Auto A'..ante, 'named after the ante it holds')
    H.eq(e.meta.run_id, cp.run_id(), 'same run id')
  end
end)

H.test('a loaded run is not checkpointed on load and continues its run id', function()
  local w, cp, store = world()
  Game.start_run({}, {seed = 'SEED1'})
  w.autosave('BLIND_SELECT')
  w.next_ante()
  w.autosave('BLIND_SELECT')
  local rid = cp.run_id()
  local a1 = checkpoints(store)[2]
  H.eq(a1.name, 'Auto A1')
  -- Another run in between, then rewind to Auto A1.
  Game.start_run({}, {seed = 'OTHER'})
  w.autosave('BLIND_SELECT')
  H.ok(cp.run_id() ~= rid, 'another seed, another run id')
  Game.start_run({}, {savetext = store.read(a1.id)})
  H.eq(cp.run_id(), rid, 'the rewind continues SEED1\'s run id')
  H.eq(G.GAME.round_resets.ante, 1)
  w.autosave('BLIND_SELECT')
  H.eq(#checkpoints(store), 3, 'loading makes no checkpoint')
  w.next_ante()
  w.autosave('BLIND_SELECT')
  local list = checkpoints(store)
  H.eq(#list, 4)
  H.eq(list[1].name, 'Auto A2')
  H.eq(list[1].meta.run_id, rid)
end)

H.test('a loaded run with no checkpoints for its seed gets a new run id', function()
  local w, cp = world()
  Game.start_run({}, {savetext = H.fake_run{seed = 'FRESH123', ante = 4}})
  H.ok(cp.run_id():match('^FRESH123:%d+$'), tostring(cp.run_id()))
  w.next_ante()
  w.autosave('BLIND_SELECT')
  local list = require('saveslots.store').list({kind = 'checkpoint'})
  H.eq(#list, 1)
  H.eq(list[1].name, 'Auto A5')
end)

H.test('auto_checkpoints = false turns it off; it defaults to on', function()
  local w, cp, store = world()
  H.eq(SaveSlots.settings.auto_checkpoints, true, 'default on')
  SaveSlots.settings.auto_checkpoints = false
  Game.start_run({}, {seed = 'SEED1'})
  w.autosave('BLIND_SELECT')
  w.next_ante()
  w.autosave('BLIND_SELECT')
  H.eq(#checkpoints(store), 0)
  local id, err = cp.auto_save(H.fake_run{})
  H.eq(id, nil); H.eq(err, 'disabled')
  SaveSlots.settings.auto_checkpoints = true
  w.next_ante()
  w.autosave('BLIND_SELECT')
  H.eq(#checkpoints(store), 1, 'back on at the next ante')
end)

H.test('nothing is checkpointed inside the sim, and the arm survives it', function()
  local w, cp, store = world()
  Game.start_run({}, {seed = 'SEED1'})
  BHCore.sim_depth = 1
  w.autosave('BLIND_SELECT')
  H.eq(#checkpoints(store), 0, 'no checkpoint in the sim')
  local id, err = cp.auto_save(H.fake_run{})
  H.eq(id, nil); H.eq(err, 'in sim')
  BHCore.sim_depth = 0
  w.autosave('BLIND_SELECT')
  local list = checkpoints(store)
  H.eq(#list, 1)
  H.eq(list[1].name, 'Auto A1')
end)

H.test('F_NO_SAVING: no snapshot, no checkpoint', function()
  local w, _, store = world()
  Game.start_run({}, {seed = 'SEED1'})
  G.F_NO_SAVING = true
  w.autosave('BLIND_SELECT')
  H.eq(#checkpoints(store), 0)
  G.F_NO_SAVING = false
  w.autosave('BLIND_SELECT')
  H.eq(#checkpoints(store), 1)
end)

H.test('a failing store never breaks save_run', function()
  local w, cp, store = world()
  Game.start_run({}, {seed = 'SEED1'})
  local write = love.filesystem.write
  love.filesystem.write = function() return false, 'disk full' end
  local said, real_print = {}, print
  print = function(msg) said[#said + 1] = msg end
  w.autosave('BLIND_SELECT')
  print = real_print
  H.ok(said[1] and said[1]:match('^%[SaveSlots%] auto%-checkpoint failed'), 'the failure is printed')
  H.eq(cp.get(), G.culled_table, 'the snapshot is still tracked')
  love.filesystem.write = write
  H.eq(#checkpoints(store), 0)
end)

H.test('10 antes on the save path keep the newest 8 of the run', function()
  local w, cp, store = world()
  Game.start_run({}, {seed = 'SEED1'})
  for a = 1, 10 do
    H.ok(cp.auto_save(H.fake_run{ante = a, seed = 'SEED1', state = G.STATES.BLIND_SELECT}))
  end
  local list = checkpoints(store)
  H.eq(#list, 8)
  for i, e in ipairs(list) do H.eq(e.name, 'Auto A'..(11 - i), 'newest first') end
  H.eq(w.saves, 0, 'auto_save never calls save_run')
end)

H.test('at most 3 runs keep checkpoints; the oldest run goes whole', function()
  local w, cp, store = world()
  local rids = {}
  for r = 1, 4 do
    Game.start_run({}, {seed = 'RUN'..r})
    rids[r] = cp.run_id()
    w.autosave('BLIND_SELECT')
    w.next_ante()
    w.autosave('BLIND_SELECT')
  end
  local by = {}
  for _, e in ipairs(checkpoints(store)) do by[e.meta.run_id] = (by[e.meta.run_id] or 0) + 1 end
  H.eq(by[rids[1]], nil, 'oldest run pruned')
  for r = 2, 4 do H.eq(by[rids[r]], 2, 'run '..r..' kept') end
end)

H.test('pruning never evicts saves, practice, hunts or run-less checkpoints', function()
  local _, cp, store = world()
  local keep = {
    store.save(H.fake_run{}, 'Mine'),
    store.save(H.fake_run{}, 'Practice', nil, {kind = 'practice'}),
    store.save(H.fake_run{}, 'Hunt', nil, {kind = 'hunt', run_id = 'X:1'}),
    store.save(H.fake_run{}, 'Manual cp', nil, {kind = 'checkpoint'}),
  }
  for r = 1, 5 do
    Game.start_run({}, {seed = 'RUN'..r})
    for a = 1, 9 do H.ok(cp.auto_save(H.fake_run{ante = a})) end
  end
  local ids = {}
  for _, e in ipairs(store.list()) do ids[e.id] = e end
  for _, id in ipairs(keep) do H.ok(ids[id], 'kept '..tostring(id)) end
  H.eq(#store.list(), 4 + 3 * 8)
end)

H.test('prune_checkpoints never deletes a favorite, nor counts it', function()
  local _, _, store = world()
  local fav = store.save(H.fake_run{}, 'old', nil, {kind = 'checkpoint', run_id = 'A:1', favorite = true})
  for _ = 1, 3 do H.ok(store.save(H.fake_run{}, 'A', nil, {kind = 'checkpoint', run_id = 'A:1'})) end
  H.ok(store.save(H.fake_run{}, 'B', nil, {kind = 'checkpoint', run_id = 'B:1', favorite = true}))
  H.eq(store.prune_checkpoints(2, 1), 1, 'only the oldest plain A checkpoint goes')
  local left = {}
  for _, e in ipairs(checkpoints(store)) do left[e.id] = e end
  H.ok(left[fav], 'favorite kept')
  H.eq(#checkpoints(store), 4, 'A keeps 2 plain + its favorite; B (favorite only) is untouched')
end)

H.test('prune_checkpoints ranks runs by their newest checkpoint', function()
  local _, _, store = world()
  -- Oldest to newest: A, B, A, C, D. Newest per run: D, C, A, (B).
  for _, rid in ipairs({'A:1', 'B:1', 'A:1', 'C:1', 'D:1'}) do
    H.ok(store.save(H.fake_run{}, rid, nil, {kind = 'checkpoint', run_id = rid}))
  end
  H.eq(store.prune_checkpoints(8, 3), 1)
  local left = {}
  for _, e in ipairs(checkpoints(store)) do left[e.meta.run_id] = (left[e.meta.run_id] or 0) + 1 end
  H.eq(left['B:1'], nil); H.eq(left['A:1'], 2); H.eq(left['C:1'], 1); H.eq(left['D:1'], 1)
  H.eq(store.prune_checkpoints(1, 3), 1, 'A drops its older one')
  local n, err = store.prune_checkpoints('8', 3)
  H.eq(n, nil); H.eq(err, 'bad limits')
end)
