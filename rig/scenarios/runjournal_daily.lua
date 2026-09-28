-- RunJournal daily list and pick rate (T-378b): the Daily tab and the Jokers tab's Pick
-- column, through the overlay's own buttons (UIElement:click).
--   1. Main menu, Options, Run Journal with an empty journal: the Daily tab reads "No
--      daily runs yet". Back to Options.
--   2. Seed synthetic records through recorder.save (as runjournal_filters does): two
--      daily runs (2026-09-27 blind and won; 2026-09-28 routed, lost at ante 3), four
--      normal runs whose records carry T-372a's `offered`, and one older normal run
--      without it. Open the Journal again.
--   3. Daily tab: row 1 is the 2026-09-28 routed run ('Ante 3'), row 2 the 2026-09-27
--      blind one ('Won'), with their seeds and decks, under the default filter (which
--      hides daily runs from the numbers, never from this list).
--      -> "check: daily list shows both"
--   4. Jokers tab: Blueprint's Pick reads 25% (offered in 4 runs with offered data,
--      held at a shop in 1; the older run's hold does not count) and Baron's, held only
--      in the older run, reads '-'. The table's rows stay inside the overlay.
--      -> "check: pick rate shown"
--   5. The sort cycle's left arrow wraps to "Sort: Pick rate": row 1 is Egg at 100%
--      (Egg and Mime tie at 100%, Egg first by name), rates never rise down the list
--      and the joker without data is last. -> "check: sort by pick rate"
--   6. Every tab (the seven, and the Jokers tab in both sorts) kept one outer size,
--      no wider than the five-tab 15.74; the tab row's right edge is inside the
--      overlay; every tab label renders at 0.8 or more of vanilla's tab text scale
--      (0.5, create_tabs' default); the overlay fits G.ROOM. -> "check: size unchanged"
-- Screenshots: daily_empty, daily_list, jokers_pick, jokers_pick_sorted.
local recorder = require('runjournal.recorder')
local stats = require('runjournal.stats')
local ui = require('runjournal.ui')

local T0 = 1790521200   -- 2026-09-27 15:00 UTC
local TAB_TEXT = 0.5    -- create_tabs' label scale
local TABS = {'Overview', 'Decks/Stakes', 'Jokers', 'Runs', 'Same seed', 'Hunts', 'Daily'}

-- kind: nil (normal) or 'daily' (seeded, origin {kind = 'daily', date, mode}).
local RECORDS = {
  {id = 'RJDB0927', kind = 'daily', date = '2026-09-27', mode = 'blind', deck = 'b_anaglyph', won = true,
    ante = 8, at = 0, seen = {}, final = {'j_triboulet'}},
  {id = 'RJDR0928', kind = 'daily', date = '2026-09-28', mode = 'routed', deck = 'b_red', won = false,
    ante = 3, at = 86400, seen = {}, final = {'j_egg'}},
  {id = 'RJDN1', won = true, at = 3600,
    seen = {{'j_joker'}, {'j_joker', 'j_blueprint'}}, final = {'j_joker', 'j_blueprint'},
    offered = {j_blueprint = 2, j_joker = 1}},
  {id = 'RJDN2', won = false, at = 7200,
    seen = {{'j_mime'}}, final = {'j_mime'}, offered = {j_blueprint = 1, j_mime = 1, j_joker = 1}},
  {id = 'RJDN3', won = false, at = 10800,
    seen = {{'j_egg'}}, final = {'j_egg'}, offered = {j_blueprint = 1, j_egg = 1}},
  {id = 'RJDN4', won = true, at = 14400,
    seen = {{}}, final = {'j_dna'}, offered = {j_blueprint = 3, j_dna = 1}},
  -- Recorded before 0.4.0: no offered. Its Blueprint hold must not count as a pick.
  {id = 'RJDOLD', won = true, at = -86400,
    seen = {{'j_baron'}, {'j_baron', 'j_blueprint'}}, final = {'j_baron', 'j_blueprint'}},
}
-- Hand-counted from RECORDS (normal runs, the default filter): the Pick cell.
local PICK = {j_blueprint = '25%', j_joker = '50%', j_mime = '100%', j_egg = '100%', j_dna = '0%', j_baron = '-'}

local S = {sizes = {}}

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function shown(ctx, id)
  local n = uie(id)
  ctx.assert(n, 'no UI element '..id)
  return n.config.text
end

local function joker_name(key)
  return localize({type = 'name_text', set = 'Joker', key = key})
end

local function deck_name(key)
  return localize({type = 'name_text', set = 'Back', key = key})
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

-- A step that waits for the overlay to settle, then runs fn(ctx).
local function after(name, fn, wait)
  return {name = name, timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < (wait or 0.6) then return false end
    return fn(ctx) ~= false
  end}
end

-- The overlay's outer panel, the tab row and every tab label; noted for the final check.
local function measure(ctx, label)
  local root = G.OVERLAY_MENU.UIRoot.children[1]
  local row = uie('tab_shoulders')
  ctx.assert(root and row, label..': panel or tab row missing')
  local x1, x2, y1, y2 = root.T.x, root.T.x + root.T.w, root.T.y, root.T.y + root.T.h
  local labels, right = {}, 0
  for _, name in ipairs(TABS) do
    local b = uie('tab_but_'..name)
    ctx.assert(b, label..': no '..name..' tab')
    local t = b.children[1] and b.children[1].children[1]
    ctx.assert(t and t.config.text == name, label..': the '..name..' tab has no label node')
    labels[#labels + 1] = {name = name, scale = t.config.scale, w = b.T.w, tw = t.T.w}
    right = math.max(right, b.T.x + b.T.w)
  end
  ctx.log(string.format('layout %s: panel x %.2f..%.2f y %.2f..%.2f, tab row x %.2f..%.2f, room %.2fx%.2f',
    label, x1, x2, y1, y2, row.T.x, row.T.x + row.T.w, G.ROOM.T.w, G.ROOM.T.h))
  S.sizes[#S.sizes + 1] = {label = label, x1 = x1, x2 = x2, y1 = y1, y2 = y2,
    row = {row.T.x, row.T.x + row.T.w}, right = right, labels = labels}
end

-- The Jokers tab's rows on the page shown: {name = pick text}, and the rows' right edge.
local function page_picks(ctx)
  local out, order, edge = {}, {}, 0
  for i = 1, 8 do
    local name = uie('runjournal_jk_name_'..i)
    if not name then break end
    local pick = uie('runjournal_jk_pick_'..i)
    ctx.assert(pick, 'row '..i..' has no Pick cell')
    out[name.config.text] = pick.config.text
    order[#order + 1] = name.config.text
    local box = pick.parent and pick.parent.parent
    if box then edge = math.max(edge, box.T.x + box.T.w) end
  end
  return out, order, edge
end

return {
  {name = 'open options', run = function(ctx)
    ctx.assert(#recorder.list() == 0, 'the journal is not empty at the start')
    return ctx.click('options')
  end},
  {name = 'open run journal (empty)', timeout = 5, run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    return ctx.click('runjournal_open')
  end},
  tab('Daily'),
  after('no daily runs', function(ctx)
    ctx.assert(shown(ctx, 'runjournal_daily_none') == 'No daily runs yet', 'the empty Daily tab')
    ctx.assert(ui.dailies() and #ui.dailies() == 0, 'ui.dailies() is not empty')
    ctx.assert(uie('runjournal_daily_date_1') == nil, 'a daily row with no daily runs')
    measure(ctx, 'daily empty')
    ctx.shot('daily_empty')
  end),
  {name = 'seed records', run = function(ctx)
    for _, r in ipairs(RECORDS) do
      local started = T0 + r.at
      local rec = {
        run_id = r.id..':'..started, seed = r.id, deck = r.deck or 'b_red', stake = 1,
        started_at = started, ended_at = started + 1800, won = r.won, final_ante = r.ante or 4, final_round = 10,
        antes = {}, jokers_seen = r.seen, jokers_final = r.final, origin = {}, offered = r.offered,
        seeded = r.kind == 'daily',
      }
      if r.kind == 'daily' then rec.origin = {kind = 'daily', date = r.date, mode = r.mode} end
      local ok, err = recorder.save(rec)
      ctx.assert(ok, 'recorder.save: '..tostring(err))
    end
    local daily = 0
    for _, e in ipairs(recorder.list()) do if e.daily == true then daily = daily + 1 end end
    ctx.assert(daily == 2, 'the index flags '..daily..' daily runs, not 2')
    return true
  end},
  click('back to options', 'options', nil, 'overlay_menu_back_button'),
  {name = 'open run journal', timeout = 5, run = function(ctx)
    if not G.OVERLAY_MENU or ui.is_open() or ctx.step_time() < 0.5 then return false end
    return ctx.click('runjournal_open')
  end},
  after('overview', function(ctx)
    ctx.assert(ui.filter().include.daily == false, 'the default filter shows daily runs')
    ctx.assert(shown(ctx, 'runjournal_stat_runs') == '5', 'the Overview counts '..shown(ctx, 'runjournal_stat_runs')
      ..' runs, not the 5 normal ones')
    measure(ctx, 'overview')
  end, 1),
  tab('Daily'),
  after('daily list', function(ctx)
    local list = ui.dailies()
    ctx.assert(list and #list == 2, 'ui.dailies() holds '..tostring(list and #list))
    local want = {
      {date = '2026-09-28', mode = 'Routed', seed = 'RJDR0928', deck = deck_name('b_red'), result = 'Ante 3'},
      {date = '2026-09-27', mode = 'Blind', seed = 'RJDB0927', deck = deck_name('b_anaglyph'), result = 'Won'},
    }
    for i, w in ipairs(want) do
      for _, k in ipairs({'date', 'mode', 'seed', 'deck', 'result'}) do
        local got = shown(ctx, 'runjournal_daily_'..k..'_'..i)
        ctx.assert(got == w[k], string.format('Daily row %d %s shows %s, want %s', i, k, tostring(got), w[k]))
      end
      ctx.log(string.format('daily row %d: %s %s %s %s %s', i, w.date, w.mode, w.seed, w.deck, w.result))
    end
    ctx.assert(uie('runjournal_daily_date_3') == nil, 'a third daily row')
    ctx.assert(uie('runjournal_daily_none') == nil, 'the empty line shows with two daily runs')
    measure(ctx, 'daily')
    ctx.shot('daily_list')
    ctx.log('check: daily list shows both')
  end),
  tab('Jokers'),
  after('jokers pick', function(ctx)
    local picks, order, edge = page_picks(ctx)
    ctx.assert(#order == 6, 'the Jokers tab lists '..#order..' jokers, not the 6 of the normal runs')
    for key, want in pairs(PICK) do
      local got = picks[joker_name(key)]
      ctx.assert(got == want, string.format('%s: Pick shows %s, want %s', key, tostring(got), want))
    end
    local rows = {}
    for _, r in ipairs(ui.jokers()) do rows[r.key] = r end
    ctx.assert(rows.j_blueprint.offered == 4 and rows.j_blueprint.picked == 1,
      string.format('Blueprint offered %s picked %s', tostring(rows.j_blueprint.offered), tostring(rows.j_blueprint.picked)))
    ctx.assert(rows.j_blueprint.runs == 2 and rows.j_blueprint.held == 2, 'the older run still counts in runs and held')
    ctx.assert(rows.j_baron.pick_rate == nil and rows.j_baron.runs == 1, 'Baron has a pick rate or lost its run')
    local root = G.OVERLAY_MENU.UIRoot.children[1]
    ctx.assert(edge > 0 and edge <= root.T.x + root.T.w - 0.2,
      string.format('the Jokers table reaches x %.2f, the panel ends at %.2f', edge, root.T.x + root.T.w))
    ctx.log(string.format('jokers: Blueprint %s, Baron %s, table right edge %.2f in panel ..%.2f',
      picks[joker_name('j_blueprint')], picks[joker_name('j_baron')], edge, root.T.x + root.T.w))
    measure(ctx, 'jokers')
    ctx.shot('jokers_pick')
    ctx.log('check: pick rate shown')
  end),
  click('sort: pick rate', 'runjournal_jsort_cycle', 'l'),
  after('sorted by pick rate', function(ctx)
    local rows = ui.jokers()
    local best = 0
    for _, r in ipairs(rows) do if r.pick_rate and r.pick_rate > best then best = r.pick_rate end end
    ctx.assert(rows[1].pick_rate == best, 'row 1 has pick rate '..tostring(rows[1].pick_rate)..', best is '..best)
    ctx.assert(shown(ctx, 'runjournal_jk_pick_1') == '100%', 'row 1 Pick shows '..shown(ctx, 'runjournal_jk_pick_1'))
    ctx.assert(shown(ctx, 'runjournal_jk_name_1') == joker_name('j_egg'),
      'row 1 is '..shown(ctx, 'runjournal_jk_name_1')..', not Egg (Egg and Mime tie, Egg first by name)')
    for i = 2, #rows do
      local a, b = rows[i - 1].pick_rate, rows[i].pick_rate
      ctx.assert(a ~= nil or b == nil, 'a joker without data sorts before one with data at row '..i)
      if a and b then
        ctx.assert(b < a or (b == a and rows[i].name >= rows[i - 1].name), 'rows '..(i - 1)..' and '..i..' out of order')
      end
    end
    ctx.assert(rows[#rows].key == 'j_baron', 'the joker without data is not last')
    local sorted = {}
    for i, r in ipairs(rows) do sorted[i] = r.name..' '..(r.pick_rate and string.format('%.2f', r.pick_rate) or '-') end
    ctx.log('sorted: '..table.concat(sorted, ', '))
    measure(ctx, 'jokers sorted')
    ctx.shot('jokers_pick_sorted')
    ctx.log('check: sort by pick rate')
  end),
  tab('Decks/Stakes'),
  after('tables tab', function(ctx) measure(ctx, 'tables') end),
  tab('Runs'),
  after('runs tab', function(ctx) measure(ctx, 'runs') end),
  tab('Same seed'),
  after('same seed tab', function(ctx) measure(ctx, 'same seed') end),
  tab('Hunts'),
  after('hunts tab', function(ctx) measure(ctx, 'hunts') end),
  tab('Overview'),
  after('overview again', function(ctx)
    measure(ctx, 'overview again')
    local a = S.sizes[1]
    local low = 1
    for _, s in ipairs(S.sizes) do
      for _, k in ipairs({'x1', 'x2', 'y1', 'y2'}) do
        ctx.assert(math.abs(s[k] - a[k]) < 0.01, string.format('%s: panel %s %.2f, %s had %.2f', s.label, k, s[k], a.label, a[k]))
      end
      ctx.assert(s.row[1] >= s.x1 and s.row[2] <= s.x2 and s.right <= s.x2,
        string.format('%s: the tab row x %.2f..%.2f (last tab to %.2f) leaves the panel x %.2f..%.2f',
          s.label, s.row[1], s.row[2], s.right, s.x1, s.x2))
      ctx.assert(s.x1 >= 0 and s.y1 >= 0 and s.x2 <= G.ROOM.T.w and s.y2 <= G.ROOM.T.h, s.label..': the overlay does not fit the room')
      for _, l in ipairs(s.labels) do
        local r = l.scale / TAB_TEXT
        ctx.assert(r >= 0.8, string.format('%s: the %s tab label renders at %.2f of the tab text scale', s.label, l.name, r))
        low = math.min(low, r)
      end
    end
    ctx.assert(a.x2 - a.x1 <= 15.75, string.format('the overlay is %.2f wide: wider than the five-tab 15.74', a.x2 - a.x1))
    local parts = {}
    for _, l in ipairs(S.sizes[#S.sizes].labels) do
      parts[#parts + 1] = string.format('%s %.2f (label %.2f at %.2f)', l.name, l.w, l.tw, l.scale / TAB_TEXT)
    end
    ctx.log('tabs: '..table.concat(parts, ', '))
    ctx.log(string.format('size: %d states, panel %.2fx%.2f, tab row %.2f wide, smallest label scale %.2f',
      #S.sizes, a.x2 - a.x1, a.y2 - a.y1, a.row[2] - a.row[1], low))
    ctx.log('check: size unchanged')
  end),
}
