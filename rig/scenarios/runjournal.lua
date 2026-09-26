-- RunJournal (T-123): a real seeded run is recorded, a loaded save continues its
-- record, and the export round-trips.
--   1. Start seeded run RJOURNAL1 (stake 1). Add a Joker (vanilla create_card +
--      add_to_deck + emplace) so every shop sees one.
--   2. Ante 1: skip the Small Blind (its tag noted from the UI), select the Big Blind
--      and play two hands (the first can't reach an unreachable target, the second
--      wins with the target forced to 1), cash out, shop; Boss won the same way.
--   3. Ante 2: Small won, shop. At the Big Blind's blind select, load the game's own
--      snapshot (SaveSlots' checkpoint.load_run, what Continue/Load do). The recorder
--      keeps the same run_id and every blind recorded so far.
--      -> "check: loaded run continues record"
--   4. Ante 2 Big and Boss won; ante 3 Small lost with one hand left: game over.
--      The record on disk holds antes 1-3 with each blind, the skip tag, hands with
--      score > 0, jokers_seen, won = false and final_ante = 3; stats() counts it.
--      -> "check: record complete"
--   5. Export CSV and JSON, parse both back, find the run. -> "check: export round-trips"
-- Speed: vsync off, GAMESPEED 64, extra Game:update passes (journal: scripting fast).
-- Screenshots: skip, shop, loaded, game_over.
local recorder = require('runjournal.recorder')
local stats = require('runjournal.stats')
local checkpoint = require('saveslots.checkpoint')

local SEED = 'RJOURNAL1'
local S = {hands = 0}

local function turbo()
  for _ = 1, 4 do G:update(1/20) end
end

local function panel()
  local kind = G.GAME.blind_on_deck
  local box = G.blind_select_opts and kind and G.blind_select_opts[string.lower(kind)]
  return box, kind
end

local PACKS = {'TAROT_PACK', 'PLANET_PACK', 'SPECTRAL_PACK', 'STANDARD_PACK', 'BUFFOON_PACK'}

-- A skip tag can open a booster pack on the spot: skip it once it is up.
local function in_pack(ctx)
  for _, st in ipairs(PACKS) do
    if G.STATE == G.STATES[st] then
      S.pack_since = S.pack_since or love.timer.getTime()
      if not S.pack_skipped and G.booster_pack and love.timer.getTime() - S.pack_since > 1 then
        S.pack_skipped = ctx.click('skip_booster')
      end
      return true
    end
  end
  S.pack_since, S.pack_skipped = nil, nil
  return false
end

local function select_blind(kind)
  return {name = 'select '..kind, timeout = 30, run = function(ctx)
    turbo()
    if in_pack(ctx) then return false end
    if G.STATE ~= G.STATES.BLIND_SELECT or not G.blind_select or ctx.step_time() < 0.3 then return false end
    local box, on_deck = panel()
    if on_deck ~= kind then return false end
    local btn = box and box:get_UIE_by_ID('select_blind_button')
    if not (btn and btn.config.button == 'select_blind') then return false end
    G.FUNCS.select_blind(btn)
    return true
  end}
end

-- Plays up to five cards against `target`, with `hands_left` forced when given.
local function play(label, target, hands_left)
  return {name = 'play '..label, timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or ctx.step_time() < 0.2
      or G.CONTROLLER.locks.frame then return false end
    if S.last_hl and G.GAME.current_round.hands_left >= S.last_hl then return false end
    G.GAME.blind.chips = target
    G.GAME.blind.chip_text = number_format(target)
    if hands_left then G.GAME.current_round.hands_left = hands_left end
    for i = 1, #G.hand.cards do
      if #G.hand.highlighted >= math.min(5, G.hand.config.highlighted_limit or 5) then break end
      if not G.hand.cards[i].highlighted then G.hand:add_to_highlighted(G.hand.cards[i]) end
    end
    ctx.assert(#G.hand.highlighted > 0, 'no cards highlighted')
    -- The next play in this round waits until this one has been spent.
    S.last_hl = target > 1 and G.GAME.current_round.hands_left or nil
    G.FUNCS.play_cards_from_highlighted()
    S.hands = S.hands + 1
    return true
  end}
end

local function cash_out()
  return {name = 'cash out', timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.ROUND_EVAL or ctx.step_time() < 0.2 then return false end
    return ctx.click('cash_out')
  end}
end

local function shop(label)
  return {name = 'shop', timeout = 30, run = function(ctx)
    turbo()
    -- Leaving before the shop's delayed event lands crashes it (game.lua:3090).
    if G.STATE ~= G.STATES.SHOP or not G.shop or ctx.step_time() < 0.3
      or not (G.shop_booster and #G.shop_booster.cards == 2) then return false end
    if label then ctx.shot(label) end
    return ctx.click('toggle_shop')
  end}
end

local function win_blind(kind, label)
  return {select_blind(kind), play(kind, 1), cash_out(), shop(label)}
end

-- A small JSON decoder, independent of stats.json (no \u escapes needed here).
local function json_decode(s)
  local i = 1
  local function ws() i = s:find('[^ \t\r\n]', i) or #s + 1 end
  local value
  local function str()
    local out, j = {}, i + 1
    while true do
      local c = s:sub(j, j)
      if c == '"' then i = j + 1; return table.concat(out) end
      if c == '' then error('unterminated string') end
      if c == '\\' then
        local e = s:sub(j + 1, j + 1)
        out[#out + 1] = ({n = '\n', t = '\t', r = '\r', b = '\b', f = '\f'})[e] or e
        j = j + 2
      else out[#out + 1] = c; j = j + 1 end
    end
  end
  function value()
    ws()
    local c = s:sub(i, i)
    if c == '{' or c == '[' then
      local obj, t, close = c == '{', {}, c == '{' and '}' or ']'
      i = i + 1; ws()
      if s:sub(i, i) == close then i = i + 1; return t end
      while true do
        ws()
        if obj then
          local k = str(); ws()
          assert(s:sub(i, i) == ':', 'expected : at '..i); i = i + 1
          t[k] = value()
        else
          t[#t + 1] = value()
        end
        ws()
        local d = s:sub(i, i); i = i + 1
        if d == close then return t end
        assert(d == ',', 'expected , at '..(i - 1))
      end
    elseif c == '"' then return str()
    elseif s:sub(i, i + 3) == 'true' then i = i + 4; return true
    elseif s:sub(i, i + 4) == 'false' then i = i + 5; return false
    elseif s:sub(i, i + 3) == 'null' then i = i + 4; return nil
    end
    local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', i)
    assert(num and #num > 0, 'bad JSON value at '..i)
    i = i + #num
    return tonumber(num)
  end
  local v = value(); ws()
  assert(i > #s, 'trailing data at '..i)
  return v
end

local function csv_split(line)
  local row = {}
  for field in (line..','):gmatch('([^,]*),') do row[#row + 1] = field end
  return row
end

local function blinds_of(r, a)
  return r.antes[a] and r.antes[a].blinds or {}
end

local function describe(r)
  local out = {}
  for a = 1, 3 do
    for _, b in ipairs(blinds_of(r, a)) do
      out[#out + 1] = string.format('A%d %s(%s)%s h%d %s', a, tostring(b.kind), tostring(b.key),
        b.skipped and ' skip:'..tostring(b.tag) or '', #(b.hands or {}), tostring(b.won))
    end
  end
  return table.concat(out, '; ')
end

local steps = {
  {name = 'speed up', run = function()
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    return true
  end},
  {name = 'start '..SEED, run = function(ctx)
    ctx.start_run{seed = SEED, stake = 1}
    return true
  end},
  {name = 'blind select', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
      and G.GAME.pseudorandom.seed == SEED and ctx.step_time() > 1
  end},
  {name = 'add a joker', run = function(ctx)
    local card = create_card('Joker', G.jokers, nil, nil, nil, nil, 'j_joker')
    card:add_to_deck()
    G.jokers:emplace(card)
    local r = recorder.current()
    ctx.assert(r and r.seed == SEED and r.run_id:sub(1, #SEED + 1) == SEED..':', 'no live record for '..SEED)
    S.run_id = r.run_id
    ctx.log('run id '..S.run_id)
    return true
  end},
  {name = 'skip small', timeout = 20, run = function(ctx)
    turbo()
    if not G.blind_select or ctx.step_time() < 0.5 then return false end
    local box, kind = panel()
    ctx.assert(kind == 'Small', 'Small is not on deck: '..tostring(kind))
    local tag = box and box:get_UIE_by_ID('tag_Small')
    local btn = tag and tag.children[2]
    if not (btn and btn.config.button == 'skip_blind') then return false end
    local container = box:get_UIE_by_ID('tag_container')
    S.skip_tag = container and container.config.ref_table and container.config.ref_table.key
    ctx.shot('skip')
    G.FUNCS.skip_blind(btn)
    return true
  end},
  select_blind('Big'),
  play('Big (miss)', 1e12),
  play('Big (win)', 1),
  cash_out(),
  shop('shop'),
}

local function add(list) for _, s in ipairs(list) do steps[#steps + 1] = s end end

add(win_blind('Boss'))
add(win_blind('Small'))

add({
  {name = 'ante 2 Big snapshot', timeout = 20, run = function(ctx)
    turbo()
    local snap = checkpoint.get()
    if G.STATE ~= G.STATES.BLIND_SELECT or not snap or snap.STATE ~= G.STATES.BLIND_SELECT
      -- The snapshot's blind_on_deck still says Small here; its blind_states don't.
      or snap.GAME.round_resets.ante ~= 2 or snap.GAME.round_resets.blind_states.Small ~= 'Defeated'
      or G.GAME.blind_on_deck ~= 'Big'
      or ctx.step_time() < 0.5 then return false end
    local r = recorder.current()
    ctx.assert(r.run_id == S.run_id, 'record changed before the load')
    S.before = {a1 = #blinds_of(r, 1), a2 = #blinds_of(r, 2), shops = #r.jokers_seen}
    ctx.log('before load: '..describe(r))
    ctx.assert(checkpoint.load_run(STR_UNPACK(STR_PACK(snap))), 'load_run failed')
    return true
  end},
  {name = 'loaded', timeout = 20, run = function(ctx)
    turbo()
    if not (G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select
      and G.GAME.round_resets.ante == 2 and not G.CONTROLLER.locks.load) or ctx.step_time() < 1 then
      return false
    end
    ctx.shot('loaded')
    local r = recorder.current()
    ctx.assert(r and r.run_id == S.run_id, 'loaded run got another record: '..tostring(r and r.run_id))
    ctx.assert(r.loads == 1, 'loads = '..tostring(r.loads))
    ctx.assert(#blinds_of(r, 1) == S.before.a1 and #blinds_of(r, 2) == S.before.a2
      and #r.jokers_seen == S.before.shops, 'the loaded record lost entries: '..describe(r))
    ctx.assert(#recorder.list() == 1, 'the load made a second record')
    ctx.log('check: loaded run continues record')
    return true
  end},
})

add(win_blind('Big'))
add(win_blind('Boss'))

add({
  select_blind('Small'),
  play('Small (lose)', 1e12, 1),
  {name = 'game over', timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.GAME_OVER or not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.shot('game_over')
    return true
  end},
  {name = 'record complete', run = function(ctx)
    local r = recorder.read(S.run_id)
    ctx.assert(r, 'no record on disk for '..S.run_id)
    ctx.log('record: '..describe(r))
    ctx.assert(r.seed == SEED and r.deck == 'b_red' and r.stake == 1, 'run fields')
    ctx.assert(r.won == false and type(r.ended_at) == 'number', 'outcome: won '..tostring(r.won))
    ctx.assert(r.final_ante == 3, 'final_ante '..tostring(r.final_ante))
    ctx.assert(r.final_round == G.GAME.round, 'final_round '..tostring(r.final_round))
    local want = {{'Small', 'Big', 'Boss'}, {'Small', 'Big', 'Boss'}, {'Small'}}
    for a, kinds in ipairs(want) do
      local bl = blinds_of(r, a)
      ctx.assert(#bl == #kinds, 'ante '..a..' has '..#bl..' blinds')
      ctx.assert(type(r.antes[a].dollars_start) == 'number' and type(r.antes[a].dollars_end) == 'number',
        'ante '..a..' dollars')
      for i, kind in ipairs(kinds) do
        local b = bl[i]
        ctx.assert(b.kind == kind and type(b.key) == 'string', 'ante '..a..' blind '..i..' is '..tostring(b.kind))
        if a == 1 and i == 1 then
          ctx.assert(b.skipped == true and b.tag == S.skip_tag and #b.hands == 0,
            'skip entry: tag '..tostring(b.tag)..' vs UI '..tostring(S.skip_tag))
        else
          ctx.assert(b.skipped == false and #b.hands >= 1, 'ante '..a..' '..kind..' has no hands')
          for _, h in ipairs(b.hands) do
            ctx.assert(type(h.hand) == 'string' and h.score > 0 and h.score == math.floor(h.chips * h.mult),
              'hand '..tostring(h.hand)..' score '..tostring(h.score))
          end
          ctx.assert(b.won == not (a == 3), 'ante '..a..' '..kind..' won = '..tostring(b.won))
        end
      end
    end
    ctx.assert(#blinds_of(r, 1)[2].hands == 2, 'Big played two hands')
    local hands = 0
    for a = 1, 3 do for _, b in ipairs(blinds_of(r, a)) do hands = hands + #b.hands end end
    ctx.assert(hands == S.hands, hands..' hands recorded, '..S.hands..' played')
    ctx.assert(#r.jokers_seen == 5, #r.jokers_seen..' shops in jokers_seen')
    for i, keys in ipairs(r.jokers_seen) do
      local has = false
      for _, k in ipairs(keys) do has = has or k == 'j_joker' end
      ctx.assert(has, 'shop '..i..' did not see j_joker')
    end
    local s = stats({seed = SEED})
    ctx.assert(s.runs == 1 and s.wins == 0 and s.win_rate == 0, 'stats runs/wins')
    ctx.assert(s.by_deck.b_red and s.by_deck.b_red.runs == 1 and s.by_stake[1].runs == 1, 'stats by deck/stake')
    ctx.assert(s.by_joker.j_joker and s.by_joker.j_joker.runs == 1, 'stats by joker')
    ctx.log('check: record complete')
    return true
  end},
  {name = 'export', run = function(ctx)
    local csv_path, err = RunJournal.export('csv')
    ctx.assert(csv_path, 'csv export failed: '..tostring(err))
    local text = love.filesystem.read(csv_path)
    local lines = {}
    for line in text:gmatch('[^\n]+') do lines[#lines + 1] = line end
    ctx.assert(#lines == 2, 'csv has '..#lines..' lines')
    local head, row = csv_split(lines[1]), csv_split(lines[2])
    ctx.assert(#head == #stats.CSV_COLUMNS and #row == #head, 'csv columns '..#head..'/'..#row)
    local col = {}
    for i, name in ipairs(head) do col[name] = row[i] end
    ctx.assert(col.run_id == S.run_id and col.seed == SEED and col.won == 'false' and col.final_ante == '3',
      'csv row: '..lines[2])
    ctx.assert(col.hands_played == tostring(S.hands) and col.blinds_skipped == '1', 'csv counts: '..lines[2])

    local json_path, jerr = RunJournal.export('json')
    ctx.assert(json_path, 'json export failed: '..tostring(jerr))
    local doc = json_decode(love.filesystem.read(json_path))
    ctx.assert(doc.version == 1 and #doc.runs == 1, 'json runs')
    local j, r = doc.runs[1], recorder.read(S.run_id)
    ctx.assert(j.run_id == S.run_id and j.won == false and j.final_ante == 3, 'json fields')
    for a = 1, 3 do
      local jb, rb = j.antes[tostring(a)].blinds, r.antes[a].blinds
      ctx.assert(#jb == #rb, 'json ante '..a..' blinds')
      for i = 1, #rb do
        ctx.assert(jb[i].kind == rb[i].kind and jb[i].key == rb[i].key and #jb[i].hands == #rb[i].hands,
          'json ante '..a..' blind '..i)
        for k = 1, #rb[i].hands do
          ctx.assert(jb[i].hands[k].score == rb[i].hands[k].score, 'json hand score')
        end
      end
    end
    ctx.assert(j.antes['1'].blinds[1].tag == S.skip_tag, 'json skip tag')
    ctx.assert(#j.jokers_seen == #r.jokers_seen, 'json jokers_seen')
    ctx.log('exports: '..csv_path..', '..json_path)
    ctx.log('check: export round-trips')
    return true
  end},
})

return steps
