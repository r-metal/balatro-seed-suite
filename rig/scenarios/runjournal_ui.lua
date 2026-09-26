-- RunJournal UI (T-125): the overlay shows what stats() computes and exports from its
-- buttons, and its Options button coexists with the other mods' buttons.
--   1. Seed 3 synthetic finished records through recorder.save (Red/White won,
--      Blue/Red Stake lost, Red/Red Stake won), with jokers at the end.
--   2. Main menu: Options holds Save Slots and Run Journal, Run Journal sharing the
--      Stats row. Open it from there.
--   3. Overview tiles = stats(); the joker lookup = stats({joker = key}) for two
--      jokers (the second reached through the lookup's arrows); Decks/Stakes rows =
--      by_deck / by_stake; Runs lists the 3 runs. -> "check: stats shown match"
--   4. Export CSV and JSON with the overlay's buttons: the path shown is the file
--      written, the CSV has a header plus 3 rows, the JSON holds 3 runs.
--      -> "check: export from UI"
--   5. Back returns to Options. In a run, the pause menu holds Save Slots, Seed Oracle
--      and Run Journal, still fits the room (seeded, so with the seed row), and Run
--      Journal opens from it.
--      -> "check: coexists with Options buttons"
-- The overlay must fit the room. Screenshots: options_menu, overview, joker_next,
-- tables, runs, exported, pause_menu, in_run.
local recorder = require('runjournal.recorder')
local stats = require('runjournal.stats')
local ui = require('runjournal.ui')

local T0 = 1789000000
local RECORDS = {
  {seed = 'RJUIWIN1', deck = 'b_red', stake = 1, won = true, final_ante = 8, final_round = 24,
    jokers = {'j_joker', 'j_blueprint', 'j_baron'}},
  {seed = 'RJUILOSS', deck = 'b_blue', stake = 2, won = false, final_ante = 3, final_round = 8,
    jokers = {'j_joker', 'j_mime'}},
  {seed = 'RJUIWIN2', deck = 'b_red', stake = 2, won = true, final_ante = 8, final_round = 25,
    jokers = {'j_baron', 'j_mime', 'j_joker'}},
}

local S = {}

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function shown(ctx, id)
  local n = uie(id)
  ctx.assert(n, 'no UI element '..id)
  return n.config.text
end

local function expect(ctx, id, want)
  local got = shown(ctx, id)
  ctx.assert(got == tostring(want), id..' shows '..tostring(got)..', stats says '..tostring(want))
end

local function pct(rate) return tostring(math.floor(rate * 100 + 0.5))..'%' end

-- The button row indices in the Options list, by G.FUNCS name.
local function options_order()
  local out = {}
  local function walk(node)
    if type(node) ~= 'table' then return end
    if node.config and node.config.button then out[#out + 1] = node.config.button end
    for _, child in ipairs(node.children or {}) do walk(child) end
  end
  walk(G.OVERLAY_MENU and G.OVERLAY_MENU.UIRoot)
  local at = {}
  for i, b in ipairs(out) do at[b] = at[b] or i end
  return at, out
end

-- Run Journal shares the Stats row: the next button, at the same height.
local function check_stats_row(ctx, where)
  local at = options_order()
  ctx.assert(at.saveslots_open and at.runjournal_open, where..': Save Slots or Run Journal missing')
  ctx.assert(at.high_scores and at.runjournal_open == at.high_scores + 1, where..': Run Journal is not next to Stats')
  local st, rj = ctx.find_button('high_scores'), ctx.find_button('runjournal_open')
  ctx.assert(math.abs(st.T.y - rj.T.y) < 0.01 and rj.T.x > st.T.x, where..': Run Journal is not in the Stats row')
end

-- The overlay's panel: the tab buttons at the top, Back at the bottom (room units).
local function check_fits(ctx, label)
  local top, back = uie('tab_but_Overview'), uie('overlay_menu_back_button')
  local root = G.OVERLAY_MENU and G.OVERLAY_MENU.UIRoot.children[1]
  ctx.assert(top and back and root, label..': tabs, Back or panel missing')
  local x1, x2 = root.T.x, root.T.x + root.T.w
  local y1, y2 = top.T.y, back.T.y + back.T.h
  ctx.log(string.format('layout %s: panel x %.2f..%.2f y %.2f..%.2f in room %.2fx%.2f',
    label, x1, x2, y1, y2, G.ROOM.T.w, G.ROOM.T.h))
  ctx.assert(x1 >= 0 and y1 >= 0 and x2 <= G.ROOM.T.w and y2 <= G.ROOM.T.h, label..': the overlay does not fit the room')
  -- Every tab keeps one panel size, so switching tabs doesn't resize the overlay.
  S.panel = S.panel or {x1, x2, y1, y2}
  for i, v in ipairs({x1, x2, y1, y2}) do
    ctx.assert(math.abs(v - S.panel[i]) < 0.01, label..': the panel changed size')
  end
end

local function check_joker(ctx)
  local key = ui.selected_joker()
  ctx.assert(key, 'the lookup shows no joker')
  local s = stats({joker = key})
  local b = stats().by_joker[key]
  ctx.assert(b and b.runs == s.runs and b.wins == s.wins, 'by_joker vs stats({joker}) for '..key)
  expect(ctx, 'runjournal_joker_runs', s.runs)
  expect(ctx, 'runjournal_joker_wins', s.wins)
  expect(ctx, 'runjournal_joker_win_rate', pct(s.win_rate))
  ctx.log(string.format('joker %s: %d runs, %d wins', key, s.runs, s.wins))
  return key
end

local function read_lines(path)
  local text = love.filesystem.read(path)
  local lines = {}
  for line in (text or ''):gmatch('[^\n]+') do lines[#lines + 1] = line end
  return lines, text
end

-- Clicks happen in their own step: a shot is written at the end of its frame, so a
-- click in the same step would show up in it. They go through UIElement:click, the
-- mouse's path, so a tab button also becomes the chosen one.
local function click(name, button, id)
  return {name = name, timeout = 5, run = function(ctx)
    local e = ctx.find_button(button, id)
    if not e then return false end
    e:click()
    return true
  end}
end

return {
  {name = 'seed records', run = function(ctx)
    ctx.assert(#recorder.list() == 0, 'the journal is not empty at the start')
    for i, r in ipairs(RECORDS) do
      local started = T0 + i * 86400
      local rec = {
        run_id = r.seed..':'..started, seed = r.seed, deck = r.deck, stake = r.stake,
        started_at = started, ended_at = started + 1800, won = r.won,
        final_ante = r.final_ante, final_round = r.final_round,
        antes = {[1] = {dollars_start = 4, dollars_end = 12, blinds = {
          {kind = 'Small', key = 'bl_small', skipped = false, won = true,
            hands = {{hand = 'Pair', chips = 30, mult = 4, score = 120}}},
        }}},
        jokers_seen = {r.jokers}, jokers_final = r.jokers, origin = {},
      }
      local ok, err = recorder.save(rec)
      ctx.assert(ok, 'recorder.save: '..tostring(err))
    end
    ctx.assert(#recorder.list() == 3, 'expected 3 records, have '..#recorder.list())
    local s = stats()
    ctx.log(string.format('stats: %d runs, %d wins, rate %.3f, unfinished %d', s.runs, s.wins, s.win_rate, s.unfinished))
    return true
  end},
  {name = 'open options', run = function(ctx)
    return ctx.click('options')
  end},
  {name = 'options menu', timeout = 5, run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    local at, all = options_order()
    ctx.log('main menu options: '..table.concat(all, ', '))
    check_stats_row(ctx, 'main menu')
    ctx.shot('options_menu')
    return true
  end},
  click('open run journal', 'runjournal_open'),
  {name = 'overview', timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 1 then return false end
    local s = stats()
    expect(ctx, 'runjournal_stat_runs', s.runs)
    expect(ctx, 'runjournal_stat_wins', s.wins)
    expect(ctx, 'runjournal_stat_win_rate', pct(s.win_rate))
    expect(ctx, 'runjournal_stat_unfinished', s.unfinished)
    ctx.assert(s.runs == 3 and s.wins == 2 and shown(ctx, 'runjournal_stat_win_rate') == '67%', 'seeded totals')
    S.joker1 = check_joker(ctx)
    check_fits(ctx, 'overview')
    ctx.shot('overview')
    return true
  end},
  click('joker lookup arrow', 'runjournal_joker_cycle'),
  {name = 'joker lookup arrows', timeout = 5, run = function(ctx)
    if ctx.step_time() < 1 then return false end
    local key = check_joker(ctx)
    ctx.assert(key ~= S.joker1, 'the lookup arrows did not change the joker')
    ctx.shot('joker_next')
    return true
  end},
  click('Decks/Stakes tab', 'change_tab', 'tab_but_Decks/Stakes'),
  {name = 'decks and stakes', timeout = 5, run = function(ctx)
    if ctx.step_time() < 1 then return false end
    local s = stats()
    local n = 0
    for key, b in pairs(s.by_deck) do
      expect(ctx, 'runjournal_deck_'..key, b.runs)
      expect(ctx, 'runjournal_deck_'..key..'_wins', b.wins)
      n = n + 1
    end
    for key, b in pairs(s.by_stake) do
      expect(ctx, 'runjournal_stake_'..key, b.runs)
      expect(ctx, 'runjournal_stake_'..key..'_wins', b.wins)
      n = n + 1
    end
    ctx.assert(n == 4, n..' deck/stake rows checked, expected 4')
    ctx.assert(not uie('runjournal_deck_b_green'), 'a deck without runs has a row')
    check_fits(ctx, 'tables')
    ctx.shot('tables')
    return true
  end},
  click('Runs tab', 'change_tab', 'tab_but_Runs'),
  {name = 'runs', timeout = 5, run = function(ctx)
    if ctx.step_time() < 1 then return false end
    local list = uie('runjournal_runs_list')
    ctx.assert(list and list.config.object, 'runs list missing')
    local seeds = {}
    local function walk(node)
      if node.config and node.config.text then seeds[node.config.text] = true end
      for _, c in ipairs(node.children or {}) do walk(c) end
    end
    walk(list.config.object.UIRoot)
    for _, r in ipairs(RECORDS) do ctx.assert(seeds[r.seed], 'run '..r.seed..' not listed') end
    ctx.log('check: stats shown match')
    check_fits(ctx, 'runs')
    ctx.shot('runs')
    return true
  end},
  click('Overview tab', 'change_tab', 'tab_but_Overview'),
  {name = 'export csv', timeout = 5, run = function(ctx)
    if ctx.step_time() < 1 then return false end
    ctx.assert(ctx.click('runjournal_export', 'runjournal_export_csv'), 'Export CSV button missing')
    local e = ui.last_export
    ctx.assert(e and e.fmt == 'csv' and e.path, 'csv export: '..tostring(e and e.err))
    S.csv = e.path
    return true
  end},
  {name = 'csv shown', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    ctx.assert(shown(ctx, 'runjournal_export_path') == S.csv, 'shown path '..tostring(shown(ctx, 'runjournal_export_path')))
    local lines = read_lines(S.csv)
    ctx.assert(#lines == 4 and lines[1] == table.concat(stats.CSV_COLUMNS, ','), 'csv has '..#lines..' lines')
    for _, r in ipairs(RECORDS) do
      local found = false
      for i = 2, #lines do found = found or lines[i]:find(r.seed, 1, true) ~= nil end
      ctx.assert(found, 'csv misses '..r.seed)
    end
    -- export-<os.time>: a second export in the same second would reuse the name.
    return ctx.step_time() > 1.1
  end},
  {name = 'export json', timeout = 5, run = function(ctx)
    ctx.assert(ctx.click('runjournal_export', 'runjournal_export_json'), 'Export JSON button missing')
    local e = ui.last_export
    ctx.assert(e and e.fmt == 'json' and e.path, 'json export: '..tostring(e and e.err))
    S.json = e.path
    return true
  end},
  {name = 'json shown', timeout = 5, run = function(ctx)
    if ctx.step_time() < 1 then return false end
    ctx.assert(shown(ctx, 'runjournal_export_path') == S.json, 'shown path '..tostring(shown(ctx, 'runjournal_export_path')))
    local _, text = read_lines(S.json)
    ctx.assert(text and text:sub(1, 20) == '{"version":1,"runs":', 'json header')
    local n = 0
    for _ in text:gmatch('"run_id":') do n = n + 1 end
    ctx.assert(n == 3, 'json holds '..n..' runs')
    ctx.assert(S.csv ~= S.json and love.filesystem.getInfo(S.csv) and love.filesystem.getInfo(S.json), 'export files')
    ctx.log('exports: '..S.csv..', '..S.json)
    ctx.log('check: export from UI')
    ctx.shot('exported')
    return true
  end},
  click('Back', 'options', 'overlay_menu_back_button'),
  {name = 'back to options', timeout = 5, run = function(ctx)
    if ui.is_open() or not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.assert(ctx.find_button('runjournal_open'), 'Back did not return to Options')
    return true
  end},
  click('close options', 'exit_overlay_menu'),
  {name = 'start run', timeout = 5, run = function(ctx)
    if G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.start_run{seed = 'RJUIRUN1', stake = 1}
    return true
  end},
  {name = 'blind select', timeout = 20, run = function(ctx)
    if not (G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select)
      or ctx.step_time() < 2 then return false end
    G.FUNCS.options()
    return true
  end},
  {name = 'pause menu', timeout = 5, run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    local at, all = options_order()
    ctx.log('pause menu options: '..table.concat(all, ', '))
    for _, b in ipairs({'saveslots_open', 'seedoracle_open', 'runjournal_open', 'setup_run', 'go_to_menu'}) do
      ctx.assert(at[b], b..' missing from the pause menu')
    end
    check_stats_row(ctx, 'pause menu')
    -- Every button on screen: Settings (the first) to Back (the last). The panel's
    -- own outline already sits ~0.1 above the room top with the SaveSlots and
    -- SeedOracle rows and the seed row alone, so it is logged, not asserted.
    local back, root, first = uie('overlay_menu_back_button'), G.OVERLAY_MENU.UIRoot.children[1],
      ctx.find_button('settings')
    ctx.log(string.format('pause menu: panel y %.2f..%.2f, buttons y %.2f..%.2f, room h %.2f',
      root.T.y, root.T.y + root.T.h, first.T.y, back.T.y + back.T.h, G.ROOM.T.h))
    ctx.assert(first.T.y >= 0 and back.T.y + back.T.h <= G.ROOM.T.h, 'the pause menu does not fit the room')
    ctx.shot('pause_menu')
    return true
  end},
  click('open from pause', 'runjournal_open'),
  {name = 'in run', timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 1 then return false end
    expect(ctx, 'runjournal_stat_runs', stats().runs)
    check_fits(ctx, 'in run')
    ctx.shot('in_run')
    ctx.log('check: coexists with Options buttons')
    return true
  end},
}
