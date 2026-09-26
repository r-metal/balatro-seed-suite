-- RunJournal (T-123): the recorder driven through bh-core events, its storage through
-- bhcore.fs (records + self-healing index), stats and CSV/JSON export. Stubs the
-- vanilla functions bhcore.events wraps; nothing here runs the game.
local H = ...

-- A world installed the way RunJournal's init does it: bh-core events, then the
-- recorder. The stubs move just the state the events read.
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
    G.GAME.round_resets.ante = run and run.ante or 1
    G.GAME.round = run and run.round or 0
    G.GAME.dollars = run and run.dollars or 4
    G.GAME.blind_on_deck = run and run.on_deck or 'Small'
    G.STATE = run and run.state or G.STATES.BLIND_SELECT
    G.GAME.blind = run and run.blind and {config = {blind = {key = run.blind}}} or nil
  end
  for _, k in ipairs({'update_round_eval', 'update_game_over', 'update_shop'}) do Game[k] = function() end end
  G.FUNCS.select_blind = function()
    G.GAME.round = G.GAME.round + 1
    G.STATE = G.STATES.SELECTING_HAND
  end
  G.FUNCS.skip_blind = function()
    local on = G.GAME.blind_on_deck
    G.GAME.blind_on_deck = on == 'Small' and 'Big' or 'Boss'
  end
  G.FUNCS.evaluate_play = function() end
  G.FUNCS.cash_out = function() end
  end_round, win_game = function() end, function() end
  ease_ante = function(mod)
    G.E_MANAGER:add_event(Event({func = function()
      G.GAME.round_resets.ante = G.GAME.round_resets.ante + mod; return true
    end}))
  end
  love.filesystem.createDirectory('1')
  BHCore = {sim_depth = 0}
  RunJournal = {}
  require('bhcore.events').install()
  local rec = require('runjournal.recorder')
  rec.install()
  local stats = require('runjournal.stats')

  function w.start(seed, savetext) Game.start_run({}, {seed = seed, savetext = savetext}) end
  function w.select(key)
    G.blind_select = true
    G.FUNCS.select_blind({config = {ref_table = {key = key or G.GAME.round_resets.blind_choices[G.GAME.blind_on_deck]}}})
    G.blind_select = nil
  end
  function w.skip() G.FUNCS.skip_blind({}) end
  function w.hand(name, chips, m)
    G.GAME.last_hand_played = name
    hand_chips, mult = chips, m
    G.FUNCS.evaluate_play()
  end
  -- end_round, then the outcome's first state. A boss win eases the ante in the
  -- queue before the round-eval frame, as vanilla does.
  function w.win(boss)
    end_round()
    if boss then ease_ante(1); w.flush() end
    G.STATE_COMPLETE = false
    Game.update_round_eval(G)
    G.STATE_COMPLETE = true
    G.GAME.current_round.dollars = 5
  end
  function w.lose()
    end_round()
    G.STATE_COMPLETE = false
    Game.update_game_over(G)
    G.STATE_COMPLETE = true
  end
  function w.shop(jokers)
    G.round_eval = true
    G.FUNCS.cash_out()
    G.round_eval = nil
    G.GAME.dollars = G.GAME.dollars + G.GAME.current_round.dollars
    G.jokers.cards = {}
    for i, k in ipairs(jokers or {}) do G.jokers.cards[i] = {config = {center = {key = k}}} end
    G.STATE_COMPLETE = false
    Game.update_shop(G)
    G.STATE_COMPLETE = true
    G.GAME.blind_on_deck = G.GAME.blind_on_deck == 'Small' and 'Big'
      or G.GAME.blind_on_deck == 'Big' and 'Boss' or 'Small'
  end
  return w, rec, stats
end

-- Counts love.filesystem.write calls made by fn.
local function writes(fn)
  local n, orig = 0, love.filesystem.write
  love.filesystem.write = function(...) n = n + 1; return orig(...) end
  fn()
  love.filesystem.write = orig
  return n
end

-- A small, independent JSON decoder (strings without \u escapes are enough here).
local function json_decode(s)
  local i = 1
  local function ws() i = s:find('[^ \t\r\n]', i) or #s + 1 end
  local value
  local function str()
    local out, j = {}, i + 1
    while true do
      local c = s:sub(j, j)
      if c == '"' then i = j + 1; return table.concat(out) end
      if c == '\\' then
        local e = s:sub(j + 1, j + 1)
        out[#out + 1] = ({n = '\n', t = '\t', r = '\r', b = '\b', f = '\f'})[e] or e
        j = j + 2
      elseif c == '' then error('unterminated string')
      else out[#out + 1] = c; j = j + 1 end
    end
  end
  function value()
    ws()
    local c = s:sub(i, i)
    if c == '{' then
      local t = {}; i = i + 1; ws()
      if s:sub(i, i) == '}' then i = i + 1; return t end
      while true do
        ws(); local k = str(); ws()
        assert(s:sub(i, i) == ':', 'expected : at '..i); i = i + 1
        t[k] = value(); ws()
        local d = s:sub(i, i); i = i + 1
        if d == '}' then return t end
        assert(d == ',', 'expected , at '..(i - 1))
      end
    elseif c == '[' then
      local t = {}; i = i + 1; ws()
      if s:sub(i, i) == ']' then i = i + 1; return t end
      while true do
        t[#t + 1] = value(); ws()
        local d = s:sub(i, i); i = i + 1
        if d == ']' then return t end
        assert(d == ',', 'expected , at '..(i - 1))
      end
    elseif c == '"' then return str()
    elseif s:sub(i, i + 3) == 'true' then i = i + 4; return true
    elseif s:sub(i, i + 4) == 'false' then i = i + 5; return false
    elseif s:sub(i, i + 3) == 'null' then i = i + 4; return nil
    else
      local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
      assert(num and #num > 0, 'bad value at '..i)
      i = i + #num
      return tonumber(num)
    end
  end
  local v = value(); ws()
  assert(i > #s, 'trailing data at '..i)
  return v
end

-- A CSV parser that handles quoted fields.
local function csv_parse(text)
  local rows = {}
  for line in text:gmatch('[^\n]+') do
    local row, pos = {}, 1
    while pos <= #line + 1 do
      if line:sub(pos, pos) == '"' then
        local field, j = {}, pos + 1
        while true do
          local c = line:sub(j, j)
          if c == '"' and line:sub(j + 1, j + 1) == '"' then field[#field + 1] = '"'; j = j + 2
          elseif c == '"' then j = j + 1; break
          else field[#field + 1] = c; j = j + 1 end
        end
        row[#row + 1] = table.concat(field)
        pos = j + 1
      else
        local j = line:find(',', pos, true) or #line + 1
        row[#row + 1] = line:sub(pos, j - 1)
        pos = j + 1
      end
    end
    rows[#rows + 1] = row
  end
  return rows
end

-- Plays: skip Small (Charm), Big (2 hands) won, shop with a Joker, Boss won
-- (ante 1 -> 2), shop, ante 2 Small lost.
local function play_run(w)
  w.start('SEED1')
  w.skip()
  w.select()
  w.hand('Pair', 20, 2)
  w.hand('Flush', 50, 4)
  w.win()
  w.shop({'j_joker'})
  w.select()
  w.hand('High Card', 10, 1)
  w.win(true)
  w.shop({'j_joker', 'j_baron'})
  w.select()
  w.hand('Pair', 12, 2)
  w.lose()
end

H.test('a played run is recorded with antes, blinds, hands, skip tag, shops and outcome', function()
  local w, rec = world()
  play_run(w)
  local r = rec.current()
  H.ok(r.run_id:match('^SEED1:%d+$'), 'run_id is seed:time, got '..tostring(r.run_id))
  H.eq(r.seed, 'SEED1'); H.eq(r.deck, 'b_red'); H.eq(r.stake, 1)
  H.eq(r.won, false); H.eq(r.final_ante, 2); H.eq(r.final_round, 3)
  H.ok(type(r.ended_at) == 'number' and type(r.started_at) == 'number', 'timestamps')
  local a1, a2 = r.antes[1], r.antes[2]
  H.eq(#a1.blinds, 3, 'ante 1 blinds')
  local sk = a1.blinds[1]
  H.ok(sk.skipped and sk.kind == 'Small' and sk.tag == 'tag_charm' and sk.key == 'bl_small'
    and #sk.hands == 0 and sk.won == nil, 'skip entry')
  local big = a1.blinds[2]
  H.ok(not big.skipped and big.kind == 'Big' and big.key == 'bl_big' and big.won == true, 'big entry')
  H.eq(#big.hands, 2)
  H.ok(big.hands[2].hand == 'Flush' and big.hands[2].chips == 50 and big.hands[2].mult == 4
    and big.hands[2].score == 200, 'hand fields')
  local boss = a1.blinds[3]
  H.ok(boss.kind == 'Boss' and boss.key == 'bl_hook' and boss.won == true and #boss.hands == 1, 'boss in ante 1')
  H.eq(#a2.blinds, 1)
  H.ok(a2.blinds[1].kind == 'Small' and a2.blinds[1].won == false, 'lost blind')
  H.eq(a1.dollars_start, 4); H.eq(a1.dollars_end, 14, 'ante 1 ends after the boss cash-out')
  H.eq(a2.dollars_start, 14)
  H.eq(#r.jokers_seen, 2)
  H.eq(r.jokers_seen[1][1], 'j_joker'); H.eq(r.jokers_seen[2][2], 'j_baron')
  local disk = rec.read(r.run_id)
  H.ok(disk and disk.won == false and #disk.antes[1].blinds == 3, 'the record is on disk')
  H.ok(not love.filesystem.getInfo('1/runjournal/'..r.run_id..'.jkr'), 'no ":" in the file name')
  H.ok(love.filesystem.getInfo('1/runjournal/'..r.run_id:gsub(':', '_')..'.jkr'), 'file is <seed>_<time>.jkr')
  local list = rec.list()
  H.eq(#list, 1); H.eq(list[1].run_id, r.run_id); H.eq(list[1].won, false)
end)

H.test('writes happen at round_end, shop_enter and run_end only', function()
  local w = world()
  w.start('SEED1')
  H.eq(writes(function() w.skip(); w.select(); w.hand('Pair', 1, 1); w.hand('Pair', 1, 1) end), 0,
    'run_start, skip, select and hands do not write')
  H.ok(writes(function() w.win() end) > 0, 'round_end writes')
  H.ok(writes(function() w.shop() end) > 0, 'shop_enter writes')
  H.eq(writes(function() w.select() end), 0)
  H.ok(writes(function() w.lose() end) > 0, 'run_end writes')
end)

H.test('a loaded run continues the newest unfinished record with its seed', function()
  local w, rec = world()
  w.start('SEED1'); w.select(); w.hand('Pair', 5, 2); w.win(); w.shop({'j_joker'})
  local id = rec.current().run_id
  -- Another seed in between, and a finished run of the same seed older than it.
  w.start('OTHER'); w.select(); w.win()
  w.start('SEED1', {seed = 'SEED1', ante = 1, round = 1, dollars = 9, on_deck = 'Big',
    state = G.STATES.BLIND_SELECT})
  local r = rec.current()
  H.eq(r.run_id, id, 'same record')
  H.eq(r.loads, 1)
  H.eq(#r.antes[1].blinds, 1, 'kept its blinds')
  w.select(); w.hand('Flush', 10, 3); w.win()
  H.eq(#rec.read(id).antes[1].blinds, 2, 'continued on disk')
  H.eq(#rec.list(), 2, 'no new record for the load')
end)

H.test('a load finds no unfinished record: finished ones and other seeds start a new one', function()
  local w, rec = world()
  w.start('SEED1'); w.select(); w.lose()
  local finished = rec.current().run_id
  w.start('SEED1', {seed = 'SEED1', ante = 1, state = G.STATES.BLIND_SELECT})
  H.ok(rec.current().run_id ~= finished, 'not the finished record')
  H.ok(rec.read(finished).ended_at, 'the finished record is intact')
  H.eq(rec.current().ended_at, nil)
  H.eq(rec.current().loads, nil)
end)

H.test('a run loaded mid-round puts its hands in the blind being played', function()
  local w, rec = world()
  w.start('SEED1'); w.select(); w.win(); w.shop()
  local id = rec.current().run_id
  w.start('SEED1', {seed = 'SEED1', ante = 1, round = 2, on_deck = 'Big', blind = 'bl_big',
    state = G.STATES.SELECTING_HAND})
  w.hand('Pair', 10, 2); w.win()
  local r = rec.read(id)
  local b = r.antes[1].blinds[2]
  H.ok(b and b.kind == 'Big' and b.key == 'bl_big' and #b.hands == 1 and b.won == true, 'reopened Big')
end)

H.test('an endless run that was won and later lost stays won', function()
  local w, rec = world()
  w.start('SEED1'); w.select(); w.win()
  win_game()
  H.eq(rec.current().won, true)
  w.shop(); w.select(); w.lose()
  H.eq(rec.read(rec.current().run_id).won, true)
end)

H.test('set_origin tags the next new run only', function()
  local w, rec = world()
  rec.set_origin({filter_name = 'Perkeo A1'})
  w.start('SEED1')
  H.eq(rec.current().origin.filter_name, 'Perkeo A1')
  w.start('SEED2')
  H.eq(rec.current().origin.filter_name, nil)
end)

H.test('the index is rebuilt from the record files when missing or corrupt', function()
  local w, rec = world()
  play_run(w)
  w.start('SEED2'); w.select(); w.win()
  H.eq(#rec.list(), 2)
  love.filesystem.remove('1/runjournal/index.jkr')
  local list = rec.list()
  H.eq(#list, 2, 'rebuilt from records')
  H.eq(list[1].seed, 'SEED2', 'newest first')
  love.filesystem.write('1/runjournal/index.jkr', 'garbage')
  H.eq(#rec.list(), 2, 'corrupt index rebuilt')
end)

-- Three synthetic records through the recorder API.
local function seed_three(rec)
  local function r(id, deck, stake, won, jokers, ended)
    return {run_id = id, seed = id:match('^[^:]+'), deck = deck, stake = stake,
      started_at = tonumber(id:match(':(%d+)$')), ended_at = ended ~= false and 100 or nil,
      won = won, final_ante = won and 8 or 3, final_round = won and 24 or 7,
      antes = {[1] = {dollars_start = 4, dollars_end = 10, blinds = {
        {kind = 'Small', key = 'bl_small', skipped = false, won = true,
          hands = {{hand = 'Pair', chips = 20, mult = 2, score = 40}}}}}},
      jokers_seen = {jokers}, jokers_final = jokers, origin = {}}
  end
  assert(rec.save(r('AAA:1', 'b_red', 1, true, {'j_joker', 'j_baron'})))
  assert(rec.save(r('BBB:2', 'b_blue', 2, false, {'j_joker'})))
  assert(rec.save(r('CCC:3', 'b_red', 2, false, {'j_mime'})))
  assert(rec.save(r('DDD:4', 'b_red', 1, nil, {'j_joker'}, false))) -- unfinished
end

H.test('stats aggregates finished runs by deck, stake and end joker', function()
  local _, rec, stats = world()
  seed_three(rec)
  local s = stats()
  H.eq(s.runs, 3); H.eq(s.wins, 1); H.eq(s.unfinished, 1)
  H.ok(math.abs(s.win_rate - 1/3) < 1e-9, 'win rate')
  H.eq(s.by_deck.b_red.runs, 2); H.eq(s.by_deck.b_red.wins, 1); H.eq(s.by_deck.b_blue.runs, 1)
  H.eq(s.by_stake[1].runs, 1); H.eq(s.by_stake[2].runs, 2); H.eq(s.by_stake[2].wins, 0)
  H.eq(s.by_joker.j_joker.runs, 2); H.eq(s.by_joker.j_joker.wins, 1)
  H.eq(s.by_joker.j_mime.runs, 1); H.eq(s.by_joker.j_baron.wins, 1)
  H.eq(stats.compute().runs, 3, 'compute is the same call')
  H.eq(stats({deck = 'b_red'}).runs, 2)
  H.eq(stats({joker = 'j_joker'}).wins, 1)
  H.eq(stats({won = false}).runs, 2)
  H.eq(stats(function(e) return e.stake == 2 end).runs, 2)
  H.eq(stats({deck = 'b_green'}).win_rate, 0, 'no runs: rate 0')
end)

H.test('export writes CSV and JSON that parse back to the runs', function()
  local w, rec, stats = world()
  seed_three(rec)
  play_run(w)
  local live = rec.current()
  local csv_path = assert(stats.export('csv'))
  H.ok(csv_path:match('^1/runjournal/export%-%d+%.csv$'), 'csv path '..csv_path)
  local rows = csv_parse(love.filesystem.read(csv_path))
  H.eq(#rows, 6, 'header + 5 runs')
  H.eq(table.concat(rows[1], ','), table.concat(stats.CSV_COLUMNS, ','))
  local last = rows[6]
  H.eq(last[1], live.run_id); H.eq(last[2], 'SEED1'); H.eq(last[7], 'false'); H.eq(last[8], '2')
  H.eq(last[10], '3', 'blinds played'); H.eq(last[11], '1', 'skipped'); H.eq(last[12], '4', 'hands')
  H.eq(last[13], 'Flush'); H.eq(last[14], '200'); H.eq(last[15], 'j_joker;j_baron')
  H.eq(rows[5][7], '', 'unfinished run: won is empty')

  local json_path = assert(RunJournal.export('json'))
  H.ok(json_path:match('%.json$'), 'json path')
  local doc = json_decode(love.filesystem.read(json_path))
  H.eq(doc.version, 1); H.eq(#doc.runs, 5)
  local j = doc.runs[5]
  H.eq(j.run_id, live.run_id); H.eq(j.won, false); H.eq(j.final_ante, 2)
  H.eq(#j.antes['1'].blinds, 3); H.eq(j.antes['1'].blinds[1].tag, 'tag_charm')
  H.eq(j.antes['1'].blinds[2].hands[2].score, 200)
  H.eq(j.jokers_seen[2][2], 'j_baron')
  H.eq(stats.export('xml'), nil, 'unknown format refused')
end)

H.test('the JSON encoder escapes strings and keeps floats', function()
  local _, _, stats = world()
  local s = stats.json({a = 'q"\\\n', b = {1, 2.5}, c = {}})
  H.eq(s, '{"a":"q\\"\\\\\\n","b":[1,2.5],"c":[]}')
  H.eq(json_decode(s).a, 'q"\\\n')
end)
