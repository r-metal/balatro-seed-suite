-- RunJournal run flags (T-370): which runs are seeded, Finder, challenge, daily or
-- endless, on the record and its index entry, so stats can leave runs out without
-- reading every record. The recorder driven through bh-core events with stubbed
-- vanilla functions (as test_runjournal.lua does); nothing here runs the game.
local H = ...

-- A world installed the way RunJournal's init does it: bh-core events, then the
-- recorder. start_run marks a run given a seed as `seeded` and sets the challenge id,
-- as vanilla does (game.lua:2064, 2163); a loaded run brings both back from its save.
local function world()
  local w = {queue = {}}
  G.GAME = {
    round = 0, dollars = 4, chips = 0, stake = 1, blind_on_deck = 'Small',
    round_resets = {ante = 1, blind_tags = {Small = 'tag_charm', Big = 'tag_economy'},
      blind_choices = {Small = 'bl_small', Big = 'bl_big', Boss = 'bl_hook'}},
    current_round = {dollars = 0}, hands = {},
    pseudorandom = {seed = 'SEED1'}, selected_back_key = {key = 'b_red'},
  }
  G.STATE = G.STATES.MENU
  G.jokers = {cards = {}}
  G.E_MANAGER = {add_event = function(_, ev) w.queue[#w.queue + 1] = ev end}
  Event = function(cfg) return cfg end
  function w.flush()
    while #w.queue > 0 do table.remove(w.queue, 1).func() end
  end
  Game = {}
  Game.start_run = function(_, args)
    local run = args and args.savetext
    G.GAME.pseudorandom.seed = run and run.seed or (args and args.seed) or 'RANDOM'
    G.GAME.seeded = run and run.seeded or (not run and args and args.seed ~= nil) or nil
    G.GAME.challenge = run and run.challenge or (args and args.challenge and args.challenge.id) or nil
    G.GAME.won = run and run.won or nil
    G.GAME.round_resets.ante = run and run.ante or 1
    G.GAME.round = run and run.round or 0
    G.GAME.dollars = run and run.dollars or 4
    G.GAME.blind_on_deck = run and run.on_deck or 'Small'
    G.STATE = run and run.state or G.STATES.BLIND_SELECT
  end
  for _, k in ipairs({'update_round_eval', 'update_game_over', 'update_shop'}) do Game[k] = function() end end
  G.FUNCS.select_blind = function()
    G.GAME.round = G.GAME.round + 1
    G.STATE = G.STATES.SELECTING_HAND
  end
  G.FUNCS.skip_blind = function() end
  G.FUNCS.evaluate_play = function() end
  G.FUNCS.cash_out = function() end
  end_round, win_game = function() end, function() end
  ease_ante = function() end
  love.filesystem.createDirectory('1')
  BHCore = {sim_depth = 0}
  RunJournal = {}
  local events = require('bhcore.events')
  events.install()
  local rec = require('runjournal.recorder')
  rec.install()
  -- What run_start saw, to prove the trap: seeded is still true there for a Finder Play.
  events.on('run_start', function() w.seen_seeded = G.GAME.seeded end)

  -- SeedFinder's (and Import's) Game:start_run wrap, installed after bh-core's: it
  -- clears `seeded` once start_run returns, for the seed its Play started only.
  local unseed = nil
  local inner = Game.start_run
  Game.start_run = function(self, args, ...)
    local want = unseed
    unseed = nil
    local ret = inner(self, args, ...)
    if want and type(args) == 'table' and args.seed == want and not args.savetext then G.GAME.seeded = nil end
    return ret
  end

  function w.start(seed, savetext, challenge)
    Game.start_run({}, {seed = seed, savetext = savetext, challenge = challenge})
  end
  -- The Finder's Play: set_origin with the filter's name, then an unseeded run.
  function w.finder_play(seed, name)
    rec.set_origin({filter_name = name})
    unseed = seed
    w.start(seed)
  end
  function w.select()
    G.blind_select = true
    G.FUNCS.select_blind({config = {ref_table = {key = G.GAME.round_resets.blind_choices[G.GAME.blind_on_deck]}}})
    G.blind_select = nil
  end
  function w.win()
    end_round()
    G.STATE_COMPLETE = false
    Game.update_round_eval(G)
    G.STATE_COMPLETE = true
  end
  function w.lose()
    end_round()
    G.STATE_COMPLETE = false
    Game.update_game_over(G)
    G.STATE_COMPLETE = true
  end
  function w.shop()
    G.round_eval = true
    G.FUNCS.cash_out()
    G.round_eval = nil
    G.STATE_COMPLETE = false
    Game.update_shop(G)
    G.STATE_COMPLETE = true
  end
  return w, rec
end

local function entry(rec, run_id)
  for _, e in ipairs(rec.list()) do
    if e.run_id == run_id then return e end
  end
end

-- Counts love.filesystem.write calls made by fn.
local function writes(fn)
  local n, orig = 0, love.filesystem.write
  love.filesystem.write = function(...) n = n + 1; return orig(...) end
  fn()
  love.filesystem.write = orig
  return n
end

local FLAGS = {'seeded', 'challenge', 'endless', 'finder', 'daily'}

H.test('seeded is set by the first write, not at run_start, and refreshed on every write', function()
  local w, rec = world()
  w.start('SEED1')
  H.eq(w.seen_seeded, true, 'vanilla marks a run given a seed')
  H.eq(rec.current().seeded, nil, 'nothing at run_start')
  w.select(); w.win()
  local id = rec.current().run_id
  H.eq(rec.read(id).seeded, true, 'record after round_end')
  H.eq(entry(rec, id).seeded, true, 'index entry after round_end')
  -- Refreshed on the next write (shop_enter), whatever the flag says by then.
  G.GAME.seeded = nil
  w.shop()
  H.eq(rec.read(id).seeded, false, 'refreshed by shop_enter')
  H.eq(entry(rec, id).seeded, false)
  G.GAME.seeded = true
  w.select(); w.lose()
  H.eq(rec.read(id).seeded, true, 'refreshed by round_end/run_end')
end)

H.test('a Finder Play clears seeded after start_run: the record says false', function()
  local w, rec = world()
  w.finder_play('FSEED1', 'Perkeo A1')
  H.eq(w.seen_seeded, true, 'run_start still saw seeded = true (the trap)')
  H.eq(G.GAME.seeded, nil, 'the wrap cleared it after start_run')
  H.eq(rec.current().seeded, nil, 'nothing recorded at run_start')
  w.select(); w.win()
  local id = rec.current().run_id
  local r = rec.read(id)
  H.eq(r.seeded, false, 'record')
  H.eq(r.origin.filter_name, 'Perkeo A1')
  local e = entry(rec, id)
  H.eq(e.seeded, false); H.eq(e.finder, true); H.eq(e.daily, false)
  w.shop()
  H.eq(rec.read(id).seeded, false, 'still false after shop_enter')
end)

H.test('the challenge id is recorded; a normal run has none', function()
  local w, rec = world()
  w.start(nil, nil, {id = 'c_omelette_1'})
  H.eq(rec.current().challenge, 'c_omelette_1', 'from run_start')
  w.select(); w.win()
  local id = rec.current().run_id
  H.eq(rec.read(id).challenge, 'c_omelette_1')
  H.eq(entry(rec, id).challenge, 'c_omelette_1')
  H.eq(entry(rec, id).seeded, false, 'a challenge run is not seeded')
  w.start('SEED2'); w.select(); w.win()
  local plain = rec.current().run_id
  H.eq(rec.read(plain).challenge, nil)
  H.eq(entry(rec, plain).challenge, nil)
end)

H.test('endless is set only by a round after the win', function()
  local w, rec = world()
  w.start('SEED1'); w.select(); w.win()
  local id = rec.current().run_id
  H.eq(rec.read(id).endless, false, 'false before a win')
  H.eq(entry(rec, id).endless, false)
  -- The winning round: win_game (run_end won) can fire before its round_end does.
  w.shop(); w.select()
  end_round()
  win_game()
  G.STATE_COMPLETE = false
  Game.update_round_eval(G)
  G.STATE_COMPLETE = true
  H.eq(rec.read(id).won, true)
  H.eq(rec.read(id).endless, false, 'the winning round itself is not endless')
  -- And after its round_end.
  w.shop(); w.select(); w.win()
  H.eq(rec.read(id).endless, true, 'a round after the win')
  H.eq(entry(rec, id).endless, true, 'index entry')
  w.shop(); w.select(); w.lose()
  local r = rec.read(id)
  H.eq(r.endless, true, 'stays endless'); H.eq(r.won, true, 'stays won')

  -- win_game after the winning round's round_end: no endless until the next round.
  w.start('SEED2'); w.select(); w.win()
  win_game()
  local id2 = rec.current().run_id
  H.eq(rec.read(id2).endless, false, 'win_game alone is not endless')
  w.shop(); w.select(); w.win()
  H.eq(rec.read(id2).endless, true)

  -- A lost run, and a run loaded already won (its next round is past the win).
  w.start('SEED3'); w.select(); w.win(); w.shop(); w.select(); w.lose()
  H.eq(rec.read(rec.current().run_id).endless, false, 'lost without a win')
  w.start('SEED4', {seed = 'SEED4', won = true, ante = 9, round = 25, state = G.STATES.BLIND_SELECT})
  H.eq(rec.current().endless, false, 'not before a round')
  w.select(); w.win()
  H.eq(rec.read(rec.current().run_id).endless, true, 'loaded past its win')
end)

H.test('set_origin keeps filter_name, kind, date and mode, and drops junk', function()
  local w, rec = world()
  rec.set_origin({kind = 'daily', date = '2026-09-28', mode = 'blind', filter_name = 'F',
    other = 1, seed = 'X', [1] = 'y'})
  w.start('DAY1')
  local o = rec.current().origin
  H.eq(o.kind, 'daily'); H.eq(o.date, '2026-09-28'); H.eq(o.mode, 'blind'); H.eq(o.filter_name, 'F')
  local n = 0
  for _ in pairs(o) do n = n + 1 end
  H.eq(n, 4, 'nothing else kept')
  -- Non-strings and values outside the sets are dropped.
  rec.set_origin({kind = 'bogus', date = '28/09/2026', mode = 5, filter_name = 42, extra = 'y'})
  w.start('DAY2')
  H.eq(next(rec.current().origin), nil, 'every junk field dropped')
  rec.set_origin({kind = 'import', mode = 'routed', date = true})
  w.start('DAY3')
  o = rec.current().origin
  H.eq(o.kind, 'import'); H.eq(o.mode, 'routed'); H.eq(o.date, nil)
  -- Only the next new run gets it; nil clears it; a non-table clears it.
  w.start('DAY4')
  H.eq(next(rec.current().origin), nil, 'consumed by the run before')
  rec.set_origin({kind = 'finder'}); rec.set_origin(nil)
  w.start('DAY5')
  H.eq(next(rec.current().origin), nil, 'nil clears')
  rec.set_origin({kind = 'finder'}); rec.set_origin('daily')
  w.start('DAY6')
  H.eq(next(rec.current().origin), nil, 'a non-table clears')
end)

H.test('the index entry carries every flag; the index version stays 1', function()
  local w, rec = world()
  local ids = {}
  -- Finder (unseeded), daily blind (seeded), challenge, endless, plain seeded.
  w.finder_play('FIND1', 'Soul A1'); w.select(); w.win(); ids.finder = rec.current().run_id
  rec.set_origin({kind = 'daily', date = '2026-09-28', mode = 'blind'})
  w.start('DAILY1'); w.select(); w.win(); ids.daily = rec.current().run_id
  w.start(nil, nil, {id = 'c_city_1'}); w.select(); w.win(); ids.challenge = rec.current().run_id
  w.start('ENDLESS1'); w.select(); w.win(); win_game(); w.shop(); w.select(); w.win()
  ids.endless = rec.current().run_id
  w.start('PLAIN1'); w.select(); w.win(); ids.plain = rec.current().run_id
  local want = {
    finder = {seeded = false, endless = false, finder = true, daily = false},
    daily = {seeded = true, endless = false, finder = false, daily = true},
    challenge = {seeded = false, challenge = 'c_city_1', endless = false, finder = false, daily = false},
    endless = {seeded = true, endless = true, finder = false, daily = false},
    plain = {seeded = true, endless = false, finder = false, daily = false},
  }
  for label, flags in pairs(want) do
    local e = entry(rec, ids[label])
    H.ok(e, 'no entry for '..label)
    for _, k in ipairs(FLAGS) do H.eq(e[k], flags[k], label..'.'..k) end
    H.eq(e.origin, nil, label..': entries carry no origin table')
  end
  H.eq(require('bhcore.fs').read_table('1/runjournal/index.jkr').version, 1, 'index version')
end)

H.test('a rebuilt index derives the flags from the records', function()
  local w, rec = world()
  w.finder_play('FIND1', 'Soul A1'); w.select(); w.win()
  local finder = rec.current().run_id
  rec.set_origin({kind = 'daily', date = '2026-09-28', mode = 'routed'})
  w.start('DAILY1'); w.select(); w.win()
  local daily = rec.current().run_id
  w.start(nil, nil, {id = 'c_city_1'}); w.select(); w.win(); win_game(); w.shop(); w.select(); w.win()
  local ch = rec.current().run_id
  local before = {}
  for _, e in ipairs(rec.list()) do before[e.run_id] = e end
  love.filesystem.remove('1/runjournal/index.jkr')
  local list = rec.list()
  H.eq(#list, 3, 'rebuilt from the records')
  for _, e in ipairs(list) do
    for _, k in ipairs(FLAGS) do H.eq(e[k], before[e.run_id][k], e.run_id..' '..k) end
  end
  H.eq(entry(rec, finder).finder, true); H.eq(entry(rec, daily).daily, true)
  H.eq(entry(rec, ch).challenge, 'c_city_1'); H.eq(entry(rec, ch).endless, true)
  -- A corrupt index too.
  love.filesystem.write('1/runjournal/index.jkr', 'garbage')
  H.eq(entry(rec, daily).daily, true)
  H.eq(entry(rec, daily).seeded, true)
end)

H.test('an old record and index without the flags load unchanged, as normal runs', function()
  local _, rec = world()
  local fs = require('bhcore.fs')
  fs.ensure_dir('1/runjournal')
  local old = {run_id = 'OLD1:100', seed = 'OLD1', deck = 'b_red', stake = 1, started_at = 100,
    ended_at = 200, won = false, final_ante = 2, final_round = 5, antes = {}, jokers_seen = {},
    origin = {}}
  assert(fs.write_table('1/runjournal/OLD1_100.jkr', old))
  local old_entry = {run_id = 'OLD1:100', file = 'OLD1_100', seed = 'OLD1', deck = 'b_red', stake = 1,
    started_at = 100, ended_at = 200, won = false, final_ante = 2, final_round = 5, jokers = {}}
  assert(fs.write_table('1/runjournal/index.jkr', {version = 1, runs = {old_entry}}))
  local packed_index = STR_PACK(fs.read_table('1/runjournal/index.jkr'))
  local packed_record = STR_PACK(fs.read_table('1/runjournal/OLD1_100.jkr'))
  local list, r
  H.eq(writes(function()
    list = rec.list()
    r = rec.read('OLD1:100')
  end), 0, 'reading writes nothing')
  H.eq(#list, 1)
  for _, k in ipairs(FLAGS) do H.eq(list[1][k], nil, 'old entry: no '..k) end
  H.eq(r.seeded, nil); H.eq(r.endless, nil); H.eq(r.challenge, nil)
  H.eq(STR_PACK(fs.read_table('1/runjournal/index.jkr')), packed_index, 'index unchanged on disk')
  H.eq(STR_PACK(fs.read_table('1/runjournal/OLD1_100.jkr')), packed_record, 'record unchanged on disk')
  -- Rebuilt from the old record: every flag reads as a normal run.
  love.filesystem.remove('1/runjournal/index.jkr')
  local e = rec.list()[1]
  H.eq(e.seeded, false); H.eq(e.endless, false); H.eq(e.challenge, nil)
  H.eq(e.finder, false); H.eq(e.daily, false)
  H.eq(STR_PACK(fs.read_table('1/runjournal/OLD1_100.jkr')), packed_record, 'rebuilding leaves the record alone')
end)

H.test('a Finder origin gives finder = true, a daily one daily = true', function()
  local w, rec = world()
  w.finder_play('FIND1', 'Perkeo A1'); w.select(); w.win()
  local e = entry(rec, rec.current().run_id)
  H.eq(e.finder, true, 'filter_name alone counts as kind finder'); H.eq(e.daily, false)
  rec.set_origin({kind = 'finder'}); w.start('FIND2'); w.select(); w.win()
  e = entry(rec, rec.current().run_id)
  H.eq(e.finder, true, 'kind finder'); H.eq(e.daily, false)
  rec.set_origin({kind = 'import'}); w.start('IMP1'); w.select(); w.win()
  e = entry(rec, rec.current().run_id)
  H.eq(e.finder, false, 'import is no Finder run'); H.eq(e.daily, false)
  -- Synthetic records through save(): the entry reads the record's origin.
  assert(rec.save({run_id = 'SYN:1', seed = 'SYN', started_at = 1, origin = {filter_name = 'Hunt'}}))
  assert(rec.save({run_id = 'SYN:2', seed = 'SYN', started_at = 2, origin = {kind = 'daily', date = '2026-09-28'}}))
  assert(rec.save({run_id = 'SYN:3', seed = 'SYN', started_at = 3}))
  H.eq(entry(rec, 'SYN:1').finder, true); H.eq(entry(rec, 'SYN:1').daily, false)
  H.eq(entry(rec, 'SYN:2').daily, true); H.eq(entry(rec, 'SYN:2').finder, false)
  H.eq(entry(rec, 'SYN:3').finder, false); H.eq(entry(rec, 'SYN:3').daily, false)
  H.eq(entry(rec, 'SYN:3').seeded, false, 'save() does not invent seeded')
end)

H.test('a loaded run keeps its seeded value', function()
  local w, rec = world()
  -- A Finder run (recorded unseeded), saved and continued: the save has no `seeded`.
  w.finder_play('FIND1', 'Perkeo A1'); w.select(); w.win(); w.shop()
  local id = rec.current().run_id
  H.eq(rec.read(id).seeded, false)
  w.start('FIND1', {seed = 'FIND1', ante = 1, round = 1, on_deck = 'Big', state = G.STATES.BLIND_SELECT})
  H.eq(rec.current().run_id, id, 'continues its record')
  H.eq(rec.current().seeded, false, 'kept at load')
  w.select(); w.win()
  H.eq(rec.read(id).seeded, false, 'still false after the next write')
  H.eq(rec.read(id).origin.filter_name, 'Perkeo A1', 'origin kept')
  -- A seeded run, continued: its save says seeded.
  w.start('SEED9'); w.select(); w.win(); w.shop()
  local sid = rec.current().run_id
  w.start('SEED9', {seed = 'SEED9', seeded = true, ante = 1, round = 1, on_deck = 'Big',
    state = G.STATES.BLIND_SELECT})
  H.eq(rec.current().run_id, sid)
  H.eq(rec.current().seeded, true, 'kept at load')
  w.select(); w.win()
  H.eq(rec.read(sid).seeded, true)
  H.eq(entry(rec, sid).seeded, true)
end)
