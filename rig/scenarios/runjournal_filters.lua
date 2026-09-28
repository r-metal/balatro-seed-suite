-- RunJournal stats filters (T-371): the filter bar, the Jokers tab and the six-tab
-- overlay's size, all through the overlay's own buttons (UIElement:click).
--   1. Seed 10 synthetic records through recorder.save (as runjournal_ui does): 3
--      normal, 2 seeded, 2 Finder, 1 challenge, 1 daily (seeded too), all finished,
--      plus an endless reload (normal, ended but unfinished), over Red and Blue
--      decks and 15 jokers. Open the Journal from Options.
--   2. Overview under the default filter: Runs 3, Wins 2, Unfinished 1 (the endless
--      reload). -> "check: default hides non-normal runs"
--   3. Seeded on: Runs 5; then Finder on: Runs 7, Wins 3.
--      -> "check: toggles bring runs back"
--   4. The deck cycle's right arrow picks Blue Deck: Runs 3 (the Blue runs among the
--      seven), the joker lookup follows it, and the Decks/Stakes tab has a Blue row
--      only. The left arrow goes back to All decks. -> "check: deck filter"
--   5. Jokers tab: every joker of the seven runs (13) over its two pages, Blueprint
--      at 3 runs, 2 wins, 67%, held 2, lifespan 2.5 (hand-counted from RECORDS).
--      -> "check: jokers tab lists all"
--   6. The sort cycle to Win rate: row 1 is Baron at 100% (four jokers win every
--      run; Baron is first by name). -> "check: sort by win rate"
--   7. Runs, Same seed and Hunts tabs. Every state above kept one outer size, the
--      tab row sits inside the overlay, the overlay is no wider than the five-tab
--      one was (15.74: x 2.13..17.87 in runjournal_ui) and fits G.ROOM.
--      -> "check: size unchanged"
-- Screenshots: filters_overview, filters_deck, filters_tables, filters_jokers,
-- filters_jokers_p2, filters_sorted.
local recorder = require('runjournal.recorder')
local stats = require('runjournal.stats')
local ui = require('runjournal.ui')

local T0 = 1789500000
-- kind: nil (normal), 'seeded', 'finder', 'challenge', 'daily', 'reload' (an endless
-- run reloaded: a new record, ended without a win).
local RECORDS = {
  {id = 'RJFN1', deck = 'b_red', stake = 1, won = true,
    seen = {{'j_joker', 'j_popcorn'}, {'j_joker', 'j_popcorn', 'j_blueprint'}, {'j_joker', 'j_blueprint'}},
    final = {'j_joker', 'j_blueprint', 'j_baron'}},
  {id = 'RJFN2', deck = 'b_blue', stake = 2, won = false,
    seen = {{'j_mime'}, {'j_mime', 'j_joker'}}, final = {'j_joker', 'j_mime'}},
  {id = 'RJFN3', deck = 'b_red', stake = 2, won = true,
    seen = {{'j_dna'}, {'j_dna', 'j_baron'}, {'j_dna', 'j_baron', 'j_mime'}}, final = {'j_baron', 'j_mime', 'j_dna'}},
  {id = 'RJFS1', kind = 'seeded', deck = 'b_red', stake = 1, won = false,
    seen = {{'j_blueprint'}, {'j_blueprint', 'j_brainstorm'}, {'j_blueprint', 'j_brainstorm'}},
    final = {'j_blueprint', 'j_brainstorm'}},
  {id = 'RJFS2', kind = 'seeded', deck = 'b_blue', stake = 1, won = false,
    seen = {{'j_cavendish'}}, final = {'j_cavendish', 'j_gros_michel'}},
  {id = 'RJFF1', kind = 'finder', deck = 'b_blue', stake = 1, won = true,
    seen = {}, final = {'j_blueprint', 'j_hanging_chad', 'j_photograph'}},
  {id = 'RJFF2', kind = 'finder', deck = 'b_red', stake = 3, won = false,
    seen = {{'j_supernova'}}, final = {'j_supernova', 'j_ride_the_bus'}},
  {id = 'RJFC1', kind = 'challenge', deck = 'b_red', stake = 1, won = false,
    seen = {{'j_egg'}}, final = {'j_egg'}},
  {id = 'RJFD1', kind = 'daily', deck = 'b_blue', stake = 1, won = true,
    seen = {}, final = {'j_triboulet'}},
  {id = 'RJFE1', kind = 'reload', deck = 'b_red', stake = 1, won = false,
    seen = {{'j_joker'}}, final = {'j_joker'}},
}
-- The seven runs Seeded + Finder show, hand-counted from RECORDS: {runs, wins, held}.
local SEVEN = {
  j_joker = {2, 1, 2}, j_popcorn = {0, 0, 1}, j_blueprint = {3, 2, 2}, j_baron = {2, 2, 1},
  j_mime = {2, 1, 2}, j_dna = {1, 1, 1}, j_brainstorm = {1, 0, 1}, j_cavendish = {1, 0, 1},
  j_gros_michel = {1, 0, 0}, j_hanging_chad = {1, 1, 0}, j_photograph = {1, 1, 0},
  j_supernova = {1, 0, 1}, j_ride_the_bus = {1, 0, 0},
}
local JOKER_ROWS = 8     -- ui.lua's rows per page

local S = {sizes = {}}

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function shown(ctx, id)
  local n = uie(id)
  ctx.assert(n, 'no UI element '..id)
  return n.config.text
end

local function expect(ctx, id, want)
  local got = shown(ctx, id)
  ctx.assert(got == tostring(want), id..' shows '..tostring(got)..', want '..tostring(want))
end

local function pct(rate) return tostring(math.floor(rate * 100 + 0.5))..'%' end

local function joker_name(key)
  return localize({type = 'name_text', set = 'Joker', key = key})
end

-- The live element with this button (and arrow side 'l' / 'r', or id), searching the
-- overlay and the UIBoxes nested in it.
local function find(button, side, id)
  local found
  local function walk(node)
    if found or type(node) ~= 'table' then return end
    local c = node.config
    if c and c.button == button and (side == nil or c.ref_value == side) and (id == nil or c.id == id) then
      found = node
      return
    end
    for _, child in ipairs(node.children or {}) do walk(child) end
    if c and type(c.object) == 'table' and c.object.UIRoot then walk(c.object.UIRoot) end
  end
  walk(G.OVERLAY_MENU and G.OVERLAY_MENU.UIRoot)
  return found
end

-- Clicks go through UIElement:click (the mouse's path), each in its own step: a shot
-- is drawn at the end of its frame.
local function click(name, button, side, id)
  return {name = name, timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 0.3 then return false end
    local e = find(button, side, id)
    if not e then return false end
    e:click()
    return true
  end}
end

local function tab(label)
  return click(label..' tab', 'change_tab', nil, 'tab_but_'..label)
end

-- The overlay's outer panel, the tab row inside it, the panel inside the room; the
-- size is noted for the final check.
local function measure(ctx, label)
  local root = G.OVERLAY_MENU.UIRoot.children[1]
  local row, back = uie('tab_shoulders'), uie('overlay_menu_back_button')
  ctx.assert(root and row and back, label..': panel, tab row or Back missing')
  local x1, x2, y1, y2 = root.T.x, root.T.x + root.T.w, root.T.y, root.T.y + root.T.h
  ctx.log(string.format('layout %s: panel x %.2f..%.2f y %.2f..%.2f, tab row x %.2f..%.2f, back y %.2f..%.2f, room %.2fx%.2f',
    label, x1, x2, y1, y2, row.T.x, row.T.x + row.T.w, back.T.y, back.T.y + back.T.h, G.ROOM.T.w, G.ROOM.T.h))
  local rightmost = uie('tab_but_Hunts')
  ctx.assert(rightmost, label..': no Hunts tab')
  S.sizes[#S.sizes + 1] = {label = label, x1 = x1, x2 = x2, y1 = y1, y2 = y2,
    row = {row.T.x, row.T.x + row.T.w}, last = rightmost.T.x + rightmost.T.w}
end

-- A step that waits for the overlay to settle, then runs fn(ctx).
local function after(name, fn, wait)
  return {name = name, timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < (wait or 0.6) then return false end
    return fn(ctx) ~= false
  end}
end

local function tiles(ctx, runs, wins, label)
  local s = stats.compute(ui.filter())
  ctx.assert(s.runs == runs and s.wins == wins,
    string.format('%s: stats(filter) gives %d runs %d wins, want %d/%d', label, s.runs, s.wins, runs, wins))
  expect(ctx, 'runjournal_stat_runs', runs)
  expect(ctx, 'runjournal_stat_wins', wins)
  expect(ctx, 'runjournal_stat_win_rate', pct(runs > 0 and wins / runs or 0))
  return s
end

-- The joker lookup shows a joker of the filtered runs, with its filtered numbers.
local function lookup_follows(ctx, s, label)
  local key = ui.selected_joker()
  ctx.assert(key and s.by_joker[key], label..': the lookup shows '..tostring(key)..', not a joker of these runs')
  expect(ctx, 'runjournal_joker_runs', s.by_joker[key].runs)
  expect(ctx, 'runjournal_joker_wins', s.by_joker[key].wins)
end

-- The Jokers tab's rows on the page shown: {name = {runs, wins, rate, held, life}}.
local function page_rows(ctx)
  local out, n = {}, 0
  for i = 1, JOKER_ROWS do
    local name = uie('runjournal_jk_name_'..i)
    if not name then break end
    n = n + 1
    out[name.config.text] = {shown(ctx, 'runjournal_jk_runs_'..i), shown(ctx, 'runjournal_jk_wins_'..i),
      shown(ctx, 'runjournal_jk_rate_'..i), shown(ctx, 'runjournal_jk_held_'..i), shown(ctx, 'runjournal_jk_life_'..i)}
  end
  return out, n
end

return {
  {name = 'seed records', run = function(ctx)
    ctx.assert(#recorder.list() == 0, 'the journal is not empty at the start')
    for i, r in ipairs(RECORDS) do
      local started = T0 + i * 3600
      local rec = {
        run_id = r.id..':'..started, seed = r.id, deck = r.deck, stake = r.stake,
        started_at = started, ended_at = started + 1800, won = r.won, final_ante = 3, final_round = 8,
        antes = {}, jokers_seen = r.seen, jokers_final = r.final, origin = {},
        seeded = r.kind == 'seeded' or r.kind == 'daily', endless = r.kind == 'reload',
      }
      if r.kind == 'finder' then rec.origin = {filter_name = r.id..' hunt'} end
      if r.kind == 'daily' then rec.origin = {kind = 'daily', date = '2026-09-28', mode = 'blind'} end
      if r.kind == 'challenge' then rec.challenge = 'c_omelette_1' end
      local ok, err = recorder.save(rec)
      ctx.assert(ok, 'recorder.save: '..tostring(err))
    end
    local kinds = {}
    for _, e in ipairs(recorder.list()) do
      local k = stats.kind_of(e) or 'normal'
      kinds[k] = (kinds[k] or 0) + 1
    end
    ctx.log(string.format('index kinds: normal %d seeded %d finder %d challenge %d daily %d',
      kinds.normal or 0, kinds.seeded or 0, kinds.finder or 0, kinds.challenge or 0, kinds.daily or 0))
    ctx.assert(kinds.normal == 4 and kinds.seeded == 2 and kinds.finder == 2 and kinds.challenge == 1
      and kinds.daily == 1, 'the index flags are not what was saved')
    return true
  end},
  {name = 'open options', run = function(ctx) return ctx.click('options') end},
  {name = 'open run journal', timeout = 5, run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    return ctx.click('runjournal_open')
  end},
  after('default filter', function(ctx)
    local f = ui.filter()
    for _, k in ipairs(stats.KINDS) do ctx.assert(f.include[k] == false, 'the default shows '..k..' runs') end
    ctx.assert(f.deck == nil and f.stake == nil, 'the default picks a deck or stake')
    local s = tiles(ctx, 3, 2, 'default')
    expect(ctx, 'runjournal_stat_unfinished', 1)
    ctx.assert(stats().runs == 9, 'a bare stats() counts '..stats().runs..' runs, not all 9 finished')
    lookup_follows(ctx, s, 'default')
    for _, k in ipairs(stats.KINDS) do
      ctx.assert(find('toggle_button', nil, 'runjournal_show_'..k), 'no '..k..' toggle')
    end
    measure(ctx, 'overview default')
    ctx.log('check: default hides non-normal runs')
  end, 1),
  click('Seeded on', 'toggle_button', nil, 'runjournal_show_seeded'),
  after('seeded shown', function(ctx)
    ctx.assert(ui.filter().include.seeded == true, 'the toggle did not change the filter')
    tiles(ctx, 5, 2, 'seeded on')
    measure(ctx, 'overview seeded')
  end),
  click('Finder on', 'toggle_button', nil, 'runjournal_show_finder'),
  after('finder shown', function(ctx)
    local s = tiles(ctx, 7, 3, 'seeded + finder on')
    lookup_follows(ctx, s, 'seeded + finder')
    measure(ctx, 'overview seeded finder')
    ctx.shot('filters_overview')
    ctx.log('check: toggles bring runs back')
  end),
  click('deck: next', 'runjournal_fdeck_cycle', 'r'),
  after('blue deck', function(ctx)
    local f = ui.filter()
    ctx.assert(f.deck == 'b_blue', 'the deck cycle picked '..tostring(f.deck))
    local s = tiles(ctx, 3, 1, 'Blue Deck')
    lookup_follows(ctx, s, 'Blue Deck')
    ctx.assert(s.by_deck.b_blue and s.by_deck.b_red == nil, 'by_deck under the deck filter')
    measure(ctx, 'overview blue')
    ctx.shot('filters_deck')
  end),
  tab('Decks/Stakes'),
  after('blue deck table', function(ctx)
    expect(ctx, 'runjournal_deck_b_blue', 3)
    expect(ctx, 'runjournal_deck_b_blue_wins', 1)
    ctx.assert(uie('runjournal_deck_b_red') == nil, 'the Red Deck row shows under the Blue filter')
    ctx.assert(ui.filter().deck == 'b_blue', 'the tab change dropped the deck filter')
    measure(ctx, 'tables blue')
    ctx.shot('filters_tables')
  end),
  click('deck: back to all', 'runjournal_fdeck_cycle', 'l'),
  after('all decks', function(ctx)
    ctx.assert(ui.filter().deck == nil, 'the deck cycle did not go back to All')
    expect(ctx, 'runjournal_deck_b_red', 4)
    expect(ctx, 'runjournal_deck_b_blue', 3)
    measure(ctx, 'tables all')
    ctx.log('check: deck filter')
  end),
  tab('Jokers'),
  after('jokers page 1', function(ctx)
    local rows, n = page_rows(ctx)
    ctx.assert(n == JOKER_ROWS, 'page 1 shows '..n..' rows')
    S.listed = rows
    S.page1 = n
    measure(ctx, 'jokers p1')
    ctx.shot('filters_jokers')
  end),
  click('jokers: next page', 'runjournal_jpage_cycle', 'r'),
  after('jokers page 2', function(ctx)
    local rows, n = page_rows(ctx)
    for name, v in pairs(rows) do
      ctx.assert(not S.listed[name], name..' is on both pages')
      S.listed[name] = v
    end
    local want, count = 0, 0
    for key, w in pairs(SEVEN) do
      want = want + 1
      local got = S.listed[joker_name(key)]
      ctx.assert(got, joker_name(key)..' is not listed')
      ctx.assert(got[1] == tostring(w[1]) and got[2] == tostring(w[2]) and got[4] == tostring(w[3]),
        string.format('%s shows runs %s wins %s held %s, want %d/%d/%d', key, got[1], got[2], got[4], w[1], w[2], w[3]))
    end
    for _ in pairs(S.listed) do count = count + 1 end
    ctx.assert(count == want and want >= 12, count..' jokers listed over the pages, want '..want)
    ctx.assert(#ui.jokers() == want, 'ui.jokers() holds '..#ui.jokers())
    local bp = S.listed[joker_name('j_blueprint')]
    ctx.assert(bp[3] == '67%' and bp[5] == '2.5', 'Blueprint: rate '..bp[3]..' lifespan '..bp[5])
    ctx.assert(S.listed[joker_name('j_gros_michel')][5] == '-', 'a joker never seen at a shop has a lifespan')
    ctx.log(string.format('jokers: %d over 2 pages (%d + %d); Blueprint %s runs %s wins %s held %s lifespan',
      count, S.page1, n, bp[1], bp[2], bp[4], bp[5]))
    measure(ctx, 'jokers p2')
    ctx.shot('filters_jokers_p2')
    ctx.log('check: jokers tab lists all')
  end),
  click('sort: win rate', 'runjournal_jsort_cycle', 'r'),
  after('sorted by win rate', function(ctx)
    local rows = ui.jokers()
    local best = 0
    for _, r in ipairs(rows) do best = math.max(best, r.win_rate) end
    ctx.assert(rows[1].win_rate == best, 'row 1 has rate '..rows[1].win_rate..', best is '..best)
    expect(ctx, 'runjournal_jk_rate_1', pct(best))
    -- Baron, DNA, Hanging Chad and Photograph win every run: Baron is first by name.
    expect(ctx, 'runjournal_jk_name_1', joker_name('j_baron'))
    for i = 2, #rows do
      ctx.assert(rows[i].win_rate < rows[i - 1].win_rate or (rows[i].win_rate == rows[i - 1].win_rate
        and rows[i].name >= rows[i - 1].name), 'rows '..(i - 1)..' and '..i..' out of order')
    end
    measure(ctx, 'jokers sorted')
    ctx.shot('filters_sorted')
    ctx.log('check: sort by win rate')
  end),
  tab('Runs'),
  after('runs tab', function(ctx) measure(ctx, 'runs') end),
  tab('Same seed'),
  after('same seed tab', function(ctx) measure(ctx, 'same seed') end),
  tab('Hunts'),
  after('hunts tab', function(ctx)
    measure(ctx, 'hunts')
    ctx.assert(#ui.hunts() == 2, 'the Hunts tab shows '..#ui.hunts()..' hunts, not both Finder runs')
  end),
  tab('Overview'),
  after('overview again', function(ctx)
    tiles(ctx, 7, 3, 'overview again')
    measure(ctx, 'overview again')
    local a = S.sizes[1]
    for _, s in ipairs(S.sizes) do
      for _, k in ipairs({'x1', 'x2', 'y1', 'y2'}) do
        ctx.assert(math.abs(s[k] - a[k]) < 0.01, string.format('%s: panel %s %.2f, %s had %.2f', s.label, k, s[k], a.label, a[k]))
      end
      ctx.assert(s.row[1] >= s.x1 and s.row[2] <= s.x2 and s.last <= s.x2,
        string.format('%s: the tab row x %.2f..%.2f leaves the panel x %.2f..%.2f', s.label, s.row[1], s.row[2], s.x1, s.x2))
      ctx.assert(s.x1 >= 0 and s.y1 >= 0 and s.x2 <= G.ROOM.T.w and s.y2 <= G.ROOM.T.h, s.label..': the overlay does not fit the room')
    end
    ctx.assert(a.x2 - a.x1 <= 15.75, string.format('the overlay is %.2f wide: wider than the five-tab 15.74', a.x2 - a.x1))
    ctx.log(string.format('size: %d states, panel %.2fx%.2f', #S.sizes, a.x2 - a.x1, a.y2 - a.y1))
    ctx.log('check: size unchanged')
  end),
}
