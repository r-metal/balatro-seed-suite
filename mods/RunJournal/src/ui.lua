-- runjournal.ui: the Run Journal overlay and its Options/pause button. Contract:
-- docs/contracts-0.2.md § RunJournal "UI".
--
-- Entry point (wraps vanilla, calls the original with every argument and changes
-- only what comes back; no vanilla body is copied)
--   create_UIBox_options   a "Run Journal" button sharing vanilla's "Stats"
--                          (high_scores) row, half width each, on the main menu
--                          and in the pause menu alike: a seeded run's pause
--                          menu with the SaveSlots and SeedOracle rows already
--                          fills the room, so a new row would push Back off
--                          screen. The button list is found by walking the
--                          definition for the node whose rows hold the Settings
--                          button, never by index. SaveSlots goes after Settings,
--                          SeedOracle before New Run: each keys on its own anchor,
--                          so every wrap order gives the same menu.
--
-- Overlay (create_UIBox_generic_options + create_tabs, like vanilla Settings/Stats;
-- Back returns to Options, as vanilla Stats does). Seven tabs (T-378b: Daily after
-- Hunts). Vanilla makes every tab button 2.5 wide; here each is fitted to its label
-- (fit_tabs) so the row stays TAB_ROW_W wide, inside the 14.8 the five 2.5-wide tabs
-- took: the overlay never widened for the Jokers or Daily tab. Labels keep vanilla's
-- tab text scale (0.5) when they all fit, as these seven do (the narrow buttons share
-- one width, the wide ones hug their label); otherwise all shrink by one factor. Six
-- equal buttons (T-371) had drawn 'Decks/Stakes' at about 0.7 of that scale; seven
-- equal ones would draw it at under 0.6, which is why the widths follow the labels.
--   Filter bar     (T-371) at the top of Overview, Decks/Stakes and Jokers: toggles
--                  Seeded, Finder, Challenge and Daily (off: those runs are hidden),
--                  a deck cycle (All decks, then each deck in the index, by name)
--                  and a stake cycle (All stakes, then 1-8). One filter for the
--                  session, starting from stats.DEFAULT_FILTER (normal runs only)
--                  and kept across tabs and opens; a deck no longer in the index
--                  falls back to All. A change recomputes stats(filter) and rebuilds
--                  the tab on screen (bar included, so a cycle's label is refitted).
--                  The Runs, Same seed, Hunts and Daily tabs are not filtered.
--   Overview       Runs / Wins / Win rate / Unfinished tiles, from stats(filter); a
--                  joker lookup (a cycle over every key in by_joker, the 0.2.0 "build
--                  archetype": the joker set at a run's end) with that joker's
--                  runs, wins and win rate, following the filter (the same joker
--                  stays picked while it is in the list); Export CSV / Export JSON
--                  and the path the last export wrote (relative to the game's save
--                  folder). Export writes every run: it ignores the filter.
--   Decks/Stakes   by_deck and by_stake as tables (most runs first; stakes with
--                  their chip sprite). Decks past DECK_ROWS fold into "+N more".
--   Jokers         (T-371) stats.jokers(filter): every joker of the filtered runs,
--                  JOKER_ROWS per page: name, runs, wins, win rate ('-' with no
--                  run held at the end), held, lifespan (mean shops held, '-' when
--                  never held at a shop), and (T-378b) Pick: pick_rate, '-' when no
--                  counted run's record has offered data for it (runs before 0.4.0
--                  never count there). A sort cycle (Runs / Win rate / Lifespan /
--                  Pick rate, highest first, a missing value last, ties by name) and
--                  a page cycle; "No runs match these filters" when empty. Records
--                  are read the first time the tab is built after an open (cached
--                  for the open, as for Hunts).
--   Runs           recorder.list(), newest first, PAGE_SIZE per page with a page
--                  cycle: date, seed, deck, stake, final ante, result.
--   Same seed      stats.by_seed: a button per seed played more than once (newest
--                  first, SEED_ROWS of them, the rest folded into "+N more").
--                  Picking one compares its two newest runs with stats.compare:
--                  one row per ante (money at the ante's end and best hand, A then
--                  B, coloured by the ante's outcome), the ante where the outcomes
--                  first diverge outlined in gold and named under the table. The table
--                  is its own UIBox, rebuilt on a pick; records are read on a pick.
--   Hunts          stats.by_filter: one row per Finder filter the runs were started
--                  from (best win rate first, HUNT_ROWS of them, the rest folded into
--                  "+N more"): runs, wins, win rate, best ante, average ante, the
--                  newest run's date; "No Finder runs yet" when there are none. The
--                  records are read the first time the tab is built after an open.
--   Daily          (T-378b) stats.dailies: every daily-seed run, newest first,
--                  DAILY_ROWS per page with a page cycle: date (the UTC day of the
--                  seed), Blind / Routed, seed, deck, result (Won, 'Ante N' for a run
--                  lost at ante N, Unfinished). Several runs of one date are each
--                  listed. Not filtered (the bar's Daily toggle only decides whether
--                  they count in the other tabs' numbers); "No daily runs yet" when
--                  there are none. Only daily runs' records are read, the first time
--                  the tab is built after an open (the open's cache).
--   The model (recorder.list(), and stats(filter) again on a filter change) is read
--   once per open; nothing here writes records or changes stats semantics. Export
--   goes through RunJournal.export (stats.export). Every tab keeps one outer size
--   (TAB_W x TAB_H) in every filter state.
--
-- API
--   ui.install()               wraps create_UIBox_options, registers G.FUNCS. Once.
--   ui.open()                  opens the overlay (main menu or pause menu).
--   ui.is_open()               whether the Run Journal overlay is up.
--   ui.last_export             {fmt, path?, err?} of the last Export press, or nil.
--   ui.selected_joker()        the joker key the lookup shows, or nil.
--   ui.filter()                a copy of the session's filter ({include, deck?,
--                              stake?}), as stats.compute takes it.
--   ui.jokers()                the Jokers tab's rows (stats.jokers', each with its
--                              shown name), in the order shown; nil before the tab
--                              was built since the last open or filter change.
--   ui.dailies()               stats.dailies' rows the Daily tab shows, newest first;
--                              nil before the tab was built since the last open.
--
-- Buttons (G.FUNCS names, so the smoke rig can ctx.click them)
--   runjournal_open            the Options/pause button
--   runjournal_export          e.config.ref_table.fmt = 'csv' | 'json'; ids
--                              'runjournal_export_csv' / 'runjournal_export_json'
--   runjournal_joker_cycle     the joker lookup's arrows; runjournal_joker is its
--                              callback. Not 'option_cycle', so a ctx.click by name
--                              can't land on the page cycle instead (and vice versa)
--   runjournal_page_cycle      the Runs tab's page arrows; runjournal_page callback
--   runjournal_same_seed       a Same seed button; e.config.ref_table.index is the
--                              group; ids 'runjournal_seed_<seed>'
--   toggle_button              vanilla's toggle, on the filter bar's check boxes:
--                              ids 'runjournal_show_<kind>' (seeded, finder,
--                              challenge, daily)
--   runjournal_fdeck_cycle     the filter bar's deck arrows; runjournal_fdeck callback
--   runjournal_fstake_cycle    its stake arrows; runjournal_fstake callback
--   runjournal_jsort_cycle     the Jokers tab's sort arrows; runjournal_jsort callback
--   runjournal_jpage_cycle     its page arrows; runjournal_jpage callback
--   runjournal_dpage_cycle     the Daily tab's page arrows; runjournal_dpage callback
--   change_tab                 vanilla's, on the tab buttons: ids 'tab_but_<label>'
--                              (Overview, Decks/Stakes, Jokers, Runs, Same seed,
--                              Hunts, Daily)
-- Text ids the scenario reads back: runjournal_stat_{runs,wins,win_rate,unfinished},
--   runjournal_joker_{runs,wins,win_rate}, runjournal_deck_<key>[_wins] and
--   runjournal_stake_<n>[_wins] (a table row's runs / wins cell), runjournal_export_path,
--   runjournal_cmp_{dollars,hand}_{a,b}_<ante> (a comparison cell), runjournal_cmp_diverge,
--   runjournal_hunt_{name,runs,wins,rate,best,avg,date}_<row> (a Hunts cell, rows from 1),
--   runjournal_jk_{name,runs,wins,rate,held,life,pick}_<row> (a Jokers cell, rows from
--   1 on the page shown), runjournal_daily_{date,mode,seed,deck,result}_<row> (a Daily
--   cell, rows from 1 on the page shown), runjournal_daily_none (its empty line).
--   ui.compared()              {seed, a, b (index entries), result = stats.compare's,
--                              or err} the Same seed tab shows, or nil.
--   ui.hunts()                 stats.by_filter's groups the Hunts tab shows, or nil
--                              before the tab was built.
--
-- The game font (m6x11plus) has no '·' or '—' glyphs: plain ASCII only.
local recorder = require('runjournal.recorder')
local stats = require('runjournal.stats')

local M = {}

-- The tab row: the buttons + (n + 1) x 0.15 (vanilla's padding) + 2 x 0.7 (the
-- shoulder pips) = TAB_ROW_W, inside the 14.8 the five 2.5-wide tabs took. TAB_W + 2 x
-- 0.1 (the contents row's padding) fills that 14.8, so the overlay is as wide as with
-- five tabs.
local TAB_W, TAB_H = 14.6, 6.4
local TAB_ROW_W = 14.75
local TAB_TEXT = 0.5       -- create_tabs' label scale (its text_scale default)
local TAB_MARGIN = 0.2     -- a label's room in its button: UIBox_button's maxw is minw - 0.2
local BAR_H = 0.76         -- the filter bar, just over its built height; the body gets TAB_H - BAR_H
local PAGE_SIZE = 7
local DECK_ROWS = 8
local SEED_ROWS = 6
local CMP_ROWS = 8
local HUNT_ROWS = 8
local JOKER_ROWS = 8
local DAILY_ROWS = 7
local TILE_W = 2.9
local PANEL_W, PANEL_H = 6, 3.0   -- the two panels of Overview and of Decks/Stakes
local HALF_W = 2.45        -- the Stats/Run Journal pair: 2 x 2.45 + 0.1 = vanilla's 5

local KIND_LABELS = {seeded = 'Seeded', finder = 'Finder', challenge = 'Challenge', daily = 'Daily'}
local SORTS = {'runs', 'win_rate', 'lifespan', 'pick_rate'}
local SORT_LABELS = {'Sort: Runs', 'Sort: Win rate', 'Sort: Lifespan', 'Sort: Pick rate'}

local installed = false
local open_marker = nil     -- the overlay's root definition while it is ours
local model = nil           -- {stats, runs, decks, stakes, jokers, ...}, rebuilt on open
local state = {page = 1, joker = 1, seed = 1, jpage = 1, sort = 1, dpage = 1}
local filter = nil          -- the session's stats filter: {include, deck?, stake?}
local current_tab = nil     -- the definition function of the tab on screen
local compared = nil        -- the Same seed tab's pair: {seed, a, b, result | err}
-- Live text (UIT.T ref_table/ref_value): the joker lookup and the export line.
local live = {j_runs = '-', j_wins = '-', j_rate = '-', export_head = '', export_path = ''}

-- Names ----------------------------------------------------------------------

local function name_of(set, key)
  if key == nil then return '?' end
  local ok, s = pcall(localize, {type = 'name_text', set = set, key = key})
  if ok and type(s) == 'string' and s ~= '' and s ~= 'ERROR' then return s end
  return tostring(key)
end

local function stake_center(n)
  local pool = G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake
  return type(n) == 'number' and pool and pool[n] or nil
end

local function stake_name(n)
  local c = stake_center(n)
  if c then return name_of('Stake', c.key) end
  return 'Stake '..tostring(n)
end

local function deck_name(key) return name_of('Back', key) end
local function joker_name(key) return name_of('Joker', key) end

local function pct(rate)
  return tostring(math.floor((tonumber(rate) or 0) * 100 + 0.5))..'%'
end

-- Model ------------------------------------------------------------------------

local function sorted_buckets(bucket, name_fn)
  local out = {}
  for key, b in pairs(bucket or {}) do
    out[#out + 1] = {key = key, name = name_fn(key), runs = b.runs, wins = b.wins, win_rate = b.win_rate}
  end
  table.sort(out, function(a, b)
    if a.runs ~= b.runs then return a.runs > b.runs end
    return tostring(a.name) < tostring(b.name)
  end)
  return out
end

local function copy(t)
  if type(t) ~= 'table' then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

local function session_filter()
  if not filter then filter = copy(stats.DEFAULT_FILTER) end
  return filter
end

local function set_joker(i)
  local j = model.jokers[i]
  state.joker = j and i or 1
  j = model.jokers[state.joker]
  live.j_runs = j and tostring(j.runs) or '-'
  live.j_wins = j and tostring(j.wins) or '-'
  live.j_rate = j and pct(j.win_rate) or '-'
end

-- The numbers the filter decides: stats(filter) and its tables. The Jokers tab's rows
-- are recomputed when it is next built. The lookup keeps its joker while listed.
local function refresh()
  local key = model.jokers and model.jokers[state.joker] and model.jokers[state.joker].key
  local ok, s = pcall(stats.compute, session_filter())
  model.stats = ok and s or {runs = 0, wins = 0, win_rate = 0, unfinished = 0, by_deck = {}, by_stake = {}, by_joker = {}}
  model.error = (not ok and tostring(s)) or model.list_error
  if not ok then print('[RunJournal] ui: '..tostring(s)) end
  model.decks = sorted_buckets(model.stats.by_deck, deck_name)
  local stakes = sorted_buckets(model.stats.by_stake, stake_name)
  table.sort(stakes, function(a, b)
    local x, y = tonumber(a.key) or 99, tonumber(b.key) or 99
    if x ~= y then return x < y end
    return tostring(a.key) < tostring(b.key)
  end)
  model.stakes = stakes
  model.jokers = sorted_buckets(model.stats.by_joker, joker_name)
  model.jrows, model.jokers_error = nil, nil
  -- On open (no joker shown yet) the lookup keeps its place, as before T-371.
  local at = key and 1 or math.min(state.joker, math.max(1, #model.jokers))
  for i, j in ipairs(model.jokers) do if key and j.key == key then at = i end end
  set_joker(at)
end

local function build_model()
  local ok2, runs = pcall(recorder.list)
  local m = {runs = ok2 and runs or {}, list_error = not ok2 and tostring(runs) or nil, records = {}}
  if m.list_error then print('[RunJournal] ui: '..m.list_error) end
  -- The deck cycle: every deck in the index, by name. A picked deck gone from it
  -- falls back to All.
  local seen, decks = {}, {}
  for _, e in ipairs(m.runs) do
    if e.deck ~= nil and not seen[e.deck] then
      seen[e.deck] = true
      decks[#decks + 1] = {key = e.deck, name = deck_name(e.deck)}
    end
  end
  table.sort(decks, function(a, b)
    if a.name ~= b.name then return tostring(a.name) < tostring(b.name) end
    return tostring(a.key) < tostring(b.key)
  end)
  m.deck_options = decks
  m.any_finished = false
  for _, e in ipairs(m.runs) do if e.ended_at then m.any_finished = true end end
  local f = session_filter()
  if f.deck ~= nil and not seen[f.deck] then f.deck = nil end
  local ok3, groups = pcall(stats.by_seed, m.runs)
  m.groups = ok3 and groups or {}
  return m
end

local function page_count()
  return math.max(1, math.ceil(#model.runs / PAGE_SIZE))
end

-- A record through the open's cache: each is read at most once per open.
local function cached_read(run_id)
  local r = model.records[run_id]
  if r == nil then
    r = recorder.read(run_id) or false
    model.records[run_id] = r
  end
  return r or nil
end

-- stats.jokers(filter) with shown names, in the sort cycle's order; once per open and
-- filter state.
local function joker_rows()
  if not model.jrows then
    local ok, rows = pcall(stats.jokers, session_filter(), model.runs, cached_read)
    if not ok then print('[RunJournal] ui: jokers: '..tostring(rows)) end
    model.jokers_error = not ok and tostring(rows) or nil
    rows = ok and rows or {}
    for _, r in ipairs(rows) do r.name = joker_name(r.key) end
    model.jrows = stats.sort_jokers(rows, SORTS[state.sort])
  end
  return model.jrows
end

local function joker_pages()
  return math.max(1, math.ceil(#joker_rows() / JOKER_ROWS))
end

-- The empty-table line: nothing recorded yet, or the filter left everything out.
local function none_text()
  return model.any_finished and 'No runs match these filters' or 'No finished runs yet'
end

-- Building blocks ----------------------------------------------------------------

local function text(t, scale, colour, id)
  -- Dark text sits on the light grey panels, where a shadow only smears it.
  return {n=G.UIT.T, config={text = tostring(t), scale = scale, colour = colour or G.C.UI.TEXT_LIGHT,
    shadow = colour ~= G.C.UI.TEXT_DARK, id = id}}
end

local function live_text(key, scale, colour, id)
  return {n=G.UIT.T, config={ref_table = live, ref_value = key, scale = scale,
    colour = colour or G.C.UI.TEXT_LIGHT, shadow = true, id = id}}
end

-- Narrows one of vanilla's UIBox_button rows (the button node and its label rows) to w.
local function narrow(button_node, w)
  button_node.config.minw = w
  for _, label_row in pairs(button_node.nodes or {}) do
    if type(label_row) == 'table' and type(label_row.config) == 'table' then
      label_row.config.minw, label_row.config.maxw = w, w - 0.2
    end
  end
end

-- A retargeted vanilla option cycle (see the header for why).
local function cycle(args, button)
  local t = create_option_cycle(args)
  local function retarget(node)
    if type(node) ~= 'table' then return end
    if node.config and node.config.button == 'option_cycle' then node.config.button = button end
    for _, child in ipairs(node.nodes or {}) do retarget(child) end
  end
  retarget(t)
  return t
end

-- A label over a big number, in a black embossed box (vanilla Stats tiles).
local function tile(label, value, colour, id)
  return {n=G.UIT.C, config={align = 'cm', padding = 0.08}, nodes={
    {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={text(label, 0.38)}},
    {n=G.UIT.R, config={align = 'cm', minw = TILE_W, minh = 1.05, r = 0.1, colour = G.C.BLACK, emboss = 0.05}, nodes={
      text(value, 0.85, colour, id),
    }},
  }}
end

local function small_tile(label, key, colour, id)
  return {n=G.UIT.C, config={align = 'cm', padding = 0.05}, nodes={
    {n=G.UIT.R, config={align = 'cm'}, nodes={text(label, 0.3, G.C.UI.TEXT_LIGHT)}},
    {n=G.UIT.R, config={align = 'cm', minw = 1.45, minh = 0.65, r = 0.1, colour = G.C.BLACK, emboss = 0.05}, nodes={
      live_text(key, 0.5, colour, id),
    }},
  }}
end

-- A titled panel: a darker rounded box holding `nodes` as rows.
local function panel(title, w, h, nodes)
  local rows = {{n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={text(title, 0.42)}}}
  for _, node in ipairs(nodes) do rows[#rows + 1] = node end
  return {n=G.UIT.C, config={align = 'tm', padding = 0.12, r = 0.1, minw = w, minh = h,
    colour = darken(G.C.JOKER_GREY, 0.1), emboss = 0.05}, nodes={
    {n=G.UIT.R, config={align = 'cm', padding = 0.02}, nodes={
      {n=G.UIT.C, config={align = 'tm', minw = w - 0.24}, nodes=rows},
    }},
  }}
end

-- A caption under a panel's contents: dark text on the panel's light grey.
local function caption(t)
  return {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
    {n=G.UIT.T, config={text = t, scale = 0.3, colour = G.C.UI.TEXT_DARK}},
  }}
end

local function message(t, w, h, id)
  return {n=G.UIT.R, config={align = 'cm', minw = w, minh = h or 1, r = 0.1, colour = G.C.BLACK, emboss = 0.05}, nodes={
    text(t, 0.4, G.C.UI.TEXT_INACTIVE, id),
  }}
end

-- Filter bar -----------------------------------------------------------------------

-- The tab on screen, built again from its definition function (as vanilla's
-- change_tab builds a picked one): the bar and the numbers follow the filter.
local function rebuild_tab()
  local node = M.is_open() and current_tab and G.OVERLAY_MENU:get_UIE_by_ID('tab_contents')
  if not node then return end
  if node.config.object then node.config.object:remove() end
  node.config.object = UIBox{definition = current_tab(),
    config = {offset = {x = 0, y = 0}, parent = node, type = 'cm'}}
  node.UIBox:recalculate()
end

local function filter_changed()
  state.jpage = 1
  refresh()
  rebuild_tab()
end

-- Vanilla's check box toggle over filter.include[kind], its box given an id.
local function toggle(kind)
  local t = create_toggle{col = true, label = KIND_LABELS[kind], ref_table = session_filter().include,
    ref_value = kind, w = 0, scale = 0.7, label_scale = 0.32, callback = function() filter_changed() end}
  t.config.padding = 0.06   -- vanilla's 0.1: the bar holds four of them and two cycles
  local function tag(node)
    if type(node) ~= 'table' then return end
    if node.config and node.config.button == 'toggle_button' then node.config.id = 'runjournal_show_'..kind end
    for _, child in ipairs(node.nodes or {}) do tag(child) end
  end
  tag(t)
  return t
end

-- A cycle for the bar: 0.04 around its arrows (vanilla's 0.1 makes the bar taller
-- than BAR_H), in a column so two share the bar. Its label is a DynaText sized once,
-- when built: a long deck name is scaled down to the cycle's width, as SeedFinder
-- does. The bar is rebuilt on every change, so each pick is fitted.
local function bar_cycle(args, button)
  local t = cycle(args, button)
  local maxw = args.w - 0.15   -- create_option_cycle scaled args.w
  local function fit(node)
    if type(node) ~= 'table' then return end
    local obj = node.config and node.config.object
    if node.n == G.UIT.O and obj and obj.is and obj:is(DynaText) and obj.config.W > maxw then
      obj.scale = obj.scale*(maxw/obj.config.W)
      obj:update_text(true)
    end
    for _, child in ipairs(node.nodes or {}) do fit(child) end
  end
  fit(t)
  t.nodes[1].config.padding = 0.04
  return {n=G.UIT.C, config={align = 'cm'}, nodes={t}}
end

local function filter_bar()
  local f = session_filter()
  local decks, deck_at = {'All decks'}, 1
  for i, d in ipairs(model.deck_options) do
    decks[i + 1] = d.name
    if d.key == f.deck then deck_at = i + 1 end
  end
  local stakes = {'All stakes'}
  for n = 1, 8 do stakes[n + 1] = stake_name(n) end
  local nodes = {{n=G.UIT.C, config={minw = 0.1}}, text('Show', 0.32, G.C.UI.TEXT_INACTIVE),
    {n=G.UIT.C, config={minw = 0.05}}}
  -- A gap after each box, so it reads as its own label's and not the next one's.
  for i, kind in ipairs(stats.KINDS) do
    if i > 1 then nodes[#nodes + 1] = {n=G.UIT.C, config={minw = 0.15}} end
    nodes[#nodes + 1] = toggle(kind)
  end
  nodes[#nodes + 1] = {n=G.UIT.C, config={minw = 0.15}}
  nodes[#nodes + 1] = bar_cycle({id = 'runjournal_fdeck', scale = 0.8, h = 0.3, w = 3.2, options = decks,
    opt_callback = 'runjournal_fdeck', current_option = deck_at, colour = G.C.RED, no_pips = true},
    'runjournal_fdeck_cycle')
  nodes[#nodes + 1] = bar_cycle({id = 'runjournal_fstake', scale = 0.8, h = 0.3, w = 2.8, options = stakes,
    opt_callback = 'runjournal_fstake', current_option = (f.stake or 0) + 1, colour = G.C.RED, no_pips = true},
    'runjournal_fstake_cycle')
  nodes[#nodes + 1] = {n=G.UIT.C, config={minw = 0.05}}
  return {n=G.UIT.R, config={align = 'cm', minh = BAR_H}, nodes={
    {n=G.UIT.C, config={align = 'cm', r = 0.1, colour = G.C.BLACK, padding = 0.02, emboss = 0.05}, nodes={
      {n=G.UIT.R, config={align = 'cm'}, nodes=nodes},
    }},
  }}
end

-- A filtered tab: the bar on top, `body` (a column's rows) centred in the rest.
local function filtered_root(body)
  return {n=G.UIT.ROOT, config={align = 'tm', colour = G.C.CLEAR, minw = TAB_W, minh = TAB_H}, nodes={
    {n=G.UIT.C, config={align = 'tm'}, nodes={
      filter_bar(),
      {n=G.UIT.R, config={align = 'cm', minw = TAB_W, minh = TAB_H - BAR_H}, nodes={
        {n=G.UIT.C, config={align = 'cm'}, nodes=body},
      }},
    }},
  }}
end

-- Overview -------------------------------------------------------------------------

local function overview_def()
  local s = model.stats
  local jokers = {}
  if #model.jokers == 0 then
    jokers[#jokers + 1] = message(none_text(), 5.4, 1.6)
  else
    local names = {}
    for i, j in ipairs(model.jokers) do names[i] = j.name end
    jokers[#jokers + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
      cycle({id = 'runjournal_joker', scale = 0.8, h = 0.3, w = 3.6, options = names,
        opt_callback = 'runjournal_joker', current_option = state.joker, colour = G.C.RED,
        no_pips = true}, 'runjournal_joker_cycle'),
    }}
    jokers[#jokers + 1] = {n=G.UIT.R, config={align = 'cm'}, nodes={
      small_tile('Runs', 'j_runs', G.C.UI.TEXT_LIGHT, 'runjournal_joker_runs'),
      small_tile('Wins', 'j_wins', G.C.GREEN, 'runjournal_joker_wins'),
      small_tile('Win rate', 'j_rate', G.C.UI.TEXT_LIGHT, 'runjournal_joker_win_rate'),
    }}
  end
  jokers[#jokers + 1] = caption('Jokers held at the end of a run')

  local export = {
    {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
      UIBox_button({id = 'runjournal_export_csv', label = {'Export CSV'}, button = 'runjournal_export',
        ref_table = {fmt = 'csv'}, colour = G.C.BLUE, minw = 2.3, minh = 0.7, scale = 0.42, col = true}),
      {n=G.UIT.C, config={minw = 0.15}},
      UIBox_button({id = 'runjournal_export_json', label = {'Export JSON'}, button = 'runjournal_export',
        ref_table = {fmt = 'json'}, colour = G.C.BLUE, minw = 2.3, minh = 0.7, scale = 0.42, col = true}),
    }},
    {n=G.UIT.R, config={align = 'cm', minw = 5, minh = 0.9, r = 0.1, colour = G.C.BLACK, emboss = 0.05, padding = 0.05}, nodes={
      {n=G.UIT.C, config={align = 'cm', maxw = 4.8}, nodes={
        {n=G.UIT.R, config={align = 'cm', maxw = 4.8}, nodes={
          live_text('export_head', 0.32, G.C.UI.TEXT_LIGHT, 'runjournal_export_head')}},
        {n=G.UIT.R, config={align = 'cm', maxw = 4.8}, nodes={
          live_text('export_path', 0.32, G.C.JOKER_GREY, 'runjournal_export_path')}},
      }},
    }},
    caption('Every recorded run, one row per run'),
  }

  local body = {
    {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
      tile('Runs', s.runs, G.C.UI.TEXT_LIGHT, 'runjournal_stat_runs'),
      tile('Wins', s.wins, G.C.GREEN, 'runjournal_stat_wins'),
      tile('Win rate', pct(s.win_rate), G.C.UI.TEXT_LIGHT, 'runjournal_stat_win_rate'),
      tile('Unfinished', s.unfinished or 0, G.C.JOKER_GREY, 'runjournal_stat_unfinished'),
    }},
    {n=G.UIT.R, config={align = 'cm', padding = 0.1}, nodes={
      panel('Joker lookup', PANEL_W, PANEL_H, jokers),
      {n=G.UIT.C, config={minw = 0.2}},
      panel('Export', PANEL_W, PANEL_H, export),
    }},
  }
  if model.error then
    body[#body + 1] = {n=G.UIT.R, config={align = 'cm', maxw = TAB_W}, nodes={
      text('Journal unreadable: '..model.error, 0.3, G.C.RED)}}
  end
  return filtered_root(body)
end

-- Decks/Stakes --------------------------------------------------------------------

local COLS = {name = 2.45, runs = 0.8, wins = 0.8, rate = 1.1}  -- + the icon column: fits PANEL_W

local function cell(t, w, colour, align, id, scale)
  return {n=G.UIT.C, config={align = align or 'cm', minw = w, maxw = w}, nodes={
    text(t, scale or 0.36, colour, id)}}
end

local function header_row(first)
  local c = G.C.UI.TEXT_DARK
  return {n=G.UIT.R, config={align = 'cm', padding = 0.02}, nodes={
    {n=G.UIT.C, config={minw = 0.55}},
    cell(first, COLS.name, c, 'cl', nil, 0.32), cell('Runs', COLS.runs, c, nil, nil, 0.32),
    cell('Wins', COLS.wins, c, nil, nil, 0.32), cell('Win rate', COLS.rate, c, nil, nil, 0.32),
  }}
end

local function bucket_row(b, id, icon)
  return {n=G.UIT.R, config={align = 'cm', padding = 0.02}, nodes={
    {n=G.UIT.C, config={align = 'cm', minw = 0.45, minh = 0.42, r = 0.1}, nodes={icon or text('', 0.3)}},
    {n=G.UIT.C, config={align = 'cm', r = 0.1, colour = G.C.BLACK, padding = 0.03}, nodes={
      {n=G.UIT.C, config={minw = 0.1}},
      cell(b.name, COLS.name, G.C.UI.TEXT_LIGHT, 'cl'),
      cell(b.runs, COLS.runs, G.C.UI.TEXT_LIGHT, nil, id),
      cell(b.wins, COLS.wins, G.C.GREEN, nil, id and id..'_wins'),
      cell(pct(b.win_rate), COLS.rate, G.C.UI.TEXT_LIGHT),
    }},
  }}
end

local function tables_def()
  local w, h = PANEL_W, TAB_H - BAR_H - 0.4
  local decks, stakes = {header_row('Deck')}, {header_row('Stake')}
  for i, d in ipairs(model.decks) do
    if i > DECK_ROWS then
      decks[#decks + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
        text('+'..(#model.decks - DECK_ROWS)..' more', 0.32, G.C.UI.TEXT_INACTIVE)}}
      break
    end
    decks[#decks + 1] = bucket_row(d, 'runjournal_deck_'..tostring(d.key))
  end
  for _, st in ipairs(model.stakes) do
    local icon = nil
    if stake_center(st.key) then
      icon = {n=G.UIT.O, config={w = 0.36, h = 0.36, object = get_stake_sprite(st.key, 0.36)}}
    end
    stakes[#stakes + 1] = bucket_row(st, 'runjournal_stake_'..tostring(st.key), icon)
  end
  if #model.decks == 0 then decks[#decks + 1] = message(none_text(), w - 0.4, 0.8) end
  if #model.stakes == 0 then stakes[#stakes + 1] = message(none_text(), w - 0.4, 0.8) end
  return filtered_root({
    {n=G.UIT.R, config={align = 'tm', padding = 0.05}, nodes={
      panel('By deck', w, h, decks),
      {n=G.UIT.C, config={minw = 0.2}},
      panel('By stake', w, h, stakes),
    }},
  })
end

-- Jokers -------------------------------------------------------------------------------

-- Name + six numbers: 10.4, about 10.8 with the spacer and padding, of TAB_W's 14.6.
local JK_COLS = {name = 3.4, runs = 1.1, wins = 1.1, rate = 1.3, held = 1.1, life = 1.3, pick = 1.1}

local function joker_row(i, r)
  local function id(k) return 'runjournal_jk_'..k..'_'..i end
  local life = r.lifespan and string.format('%.1f', r.lifespan) or '-'
  local pick = r.pick_rate and pct(r.pick_rate) or '-'
  return {n=G.UIT.R, config={align = 'cm', padding = 0.02}, nodes={
    {n=G.UIT.C, config={align = 'cm', r = 0.1, colour = G.C.BLACK, padding = 0.03, minh = 0.44}, nodes={
      {n=G.UIT.C, config={minw = 0.1}},
      cell(r.name, JK_COLS.name, G.C.UI.TEXT_LIGHT, 'cl', id('name'), 0.34),
      cell(r.runs, JK_COLS.runs, G.C.UI.TEXT_LIGHT, nil, id('runs'), 0.34),
      cell(r.wins, JK_COLS.wins, G.C.GREEN, nil, id('wins'), 0.34),
      cell(r.runs > 0 and pct(r.win_rate) or '-', JK_COLS.rate, G.C.UI.TEXT_LIGHT, nil, id('rate'), 0.34),
      cell(r.held, JK_COLS.held, G.C.UI.TEXT_LIGHT, nil, id('held'), 0.34),
      cell(life, JK_COLS.life, G.C.UI.TEXT_LIGHT, nil, id('life'), 0.34),
      cell(pick, JK_COLS.pick, r.pick_rate and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE, nil, id('pick'), 0.34),
    }},
  }}
end

local function jokers_def()
  local rows = joker_rows()
  local pages = joker_pages()
  state.jpage = math.min(state.jpage, pages)
  local c = G.C.UI.TEXT_INACTIVE
  local list = {{n=G.UIT.R, config={align = 'cm', padding = 0.02}, nodes={
    {n=G.UIT.C, config={align = 'cm', padding = 0.03}, nodes={
      {n=G.UIT.C, config={minw = 0.1}},
      cell('Joker', JK_COLS.name, c, 'cl', nil, 0.3), cell('Runs', JK_COLS.runs, c, nil, nil, 0.3),
      cell('Wins', JK_COLS.wins, c, nil, nil, 0.3), cell('Win rate', JK_COLS.rate, c, nil, nil, 0.3),
      cell('Held', JK_COLS.held, c, nil, nil, 0.3), cell('Lifespan', JK_COLS.life, c, nil, nil, 0.3),
      cell('Pick', JK_COLS.pick, c, nil, nil, 0.3),
    }},
  }}}
  local first = (state.jpage - 1) * JOKER_ROWS
  local shown = {}
  for i = first + 1, math.min(first + JOKER_ROWS, #rows) do shown[#shown + 1] = joker_row(i - first, rows[i]) end
  if #shown == 0 then shown[1] = message(none_text(), 10.9, 1.2) end
  -- A row's built height (0.44 + 2 x 0.02) per row: 0.5 a row left no room for the
  -- Pick footnote inside TAB_H.
  list[#list + 1] = {n=G.UIT.R, config={align = 'tm', minh = JOKER_ROWS * 0.48}, nodes={
    {n=G.UIT.C, config={align = 'tm'}, nodes=shown},
  }}
  local page_labels = {}
  for i = 1, pages do page_labels[i] = localize('k_page')..' '..i..'/'..pages end
  list[#list + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
    {n=G.UIT.C, config={align = 'cm'}, nodes={
      -- 3.2: 'Sort: Pick rate', the widest label, fits at the cycle's text scale.
      cycle({id = 'runjournal_jsort', scale = 0.8, h = 0.3, w = 3.2, options = SORT_LABELS,
        opt_callback = 'runjournal_jsort', current_option = state.sort, colour = G.C.RED, no_pips = true},
        'runjournal_jsort_cycle')}},
    {n=G.UIT.C, config={minw = 0.3}},
    {n=G.UIT.C, config={align = 'cm'}, nodes={
      cycle({id = 'runjournal_jpage', scale = 0.8, h = 0.3, w = 2.8, options = page_labels,
        opt_callback = 'runjournal_jpage', current_option = state.jpage, colour = G.C.RED, no_pips = true},
        'runjournal_jpage_cycle')}},
  }}
  list[#list + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.02}, nodes={
    text('Runs: held at the end. Held: runs it sat in a shop. Lifespan: shops held, on average',
      0.3, G.C.UI.TEXT_INACTIVE)}}
  list[#list + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.02}, nodes={
    text('Pick: of the runs whose shops offered it, the share that held it (runs from 0.4.0 on)',
      0.3, G.C.UI.TEXT_INACTIVE)}}
  if model.jokers_error then
    list[#list + 1] = {n=G.UIT.R, config={align = 'cm', maxw = TAB_W}, nodes={
      text('Journal unreadable: '..model.jokers_error, 0.3, G.C.RED)}}
  end
  return filtered_root(list)
end

-- Runs -------------------------------------------------------------------------------

local RUN_COLS = {date = 1.9, seed = 1.9, deck = 2.6, stake = 2.3, ante = 1.0, result = 1.6}

local function result_of(e)
  if e.won == true then return 'Won', G.C.GREEN end
  if e.ended_at then return 'Lost', G.C.RED end
  return 'Unfinished', G.C.UI.TEXT_INACTIVE
end

local function run_row(e)
  local result, colour = result_of(e)
  local when = type(e.started_at) == 'number' and os.date('%Y-%m-%d', e.started_at) or '?'
  local icon = stake_center(e.stake) and {n=G.UIT.O, config={w = 0.3, h = 0.3, object = get_stake_sprite(e.stake, 0.3)}}
  return {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
    {n=G.UIT.C, config={align = 'cm', r = 0.1, colour = G.C.BLACK, padding = 0.05, minh = 0.5}, nodes={
      cell(when, RUN_COLS.date, G.C.UI.TEXT_INACTIVE),
      cell(tostring(e.seed or '?'), RUN_COLS.seed, G.C.UI.TEXT_LIGHT),
      cell(deck_name(e.deck), RUN_COLS.deck, G.C.UI.TEXT_LIGHT),
      {n=G.UIT.C, config={align = 'cm', minw = RUN_COLS.stake, maxw = RUN_COLS.stake}, nodes={
        icon or text('', 0.3), {n=G.UIT.C, config={minw = 0.08}}, text(stake_name(e.stake), 0.34),
      }},
      cell('Ante '..tostring(e.final_ante or '?'), RUN_COLS.ante, G.C.UI.TEXT_LIGHT),
      cell(result, RUN_COLS.result, colour),
    }},
  }}
end

local function runs_list_def()
  local rows = {}
  local first = (state.page - 1) * PAGE_SIZE
  for i = first + 1, math.min(first + PAGE_SIZE, #model.runs) do rows[#rows + 1] = run_row(model.runs[i]) end
  if #rows == 0 then rows[1] = message('No runs recorded yet', 10, 1.2) end
  return {n=G.UIT.ROOT, config={align = 'tm', colour = G.C.CLEAR}, nodes={
    {n=G.UIT.C, config={align = 'tm'}, nodes=rows},
  }}
end

local function runs_def()
  local pages = {}
  for i = 1, page_count() do pages[i] = localize('k_page')..' '..i..'/'..page_count() end
  local c = G.C.UI.TEXT_INACTIVE
  local header = {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
    {n=G.UIT.C, config={align = 'cm', padding = 0.05}, nodes={
      cell('Started', RUN_COLS.date, c, nil, nil, 0.32), cell('Seed', RUN_COLS.seed, c, nil, nil, 0.32),
      cell('Deck', RUN_COLS.deck, c, nil, nil, 0.32), cell('Stake', RUN_COLS.stake, c, nil, nil, 0.32),
      cell('Reached', RUN_COLS.ante, c, nil, nil, 0.32), cell('Result', RUN_COLS.result, c, nil, nil, 0.32),
    }},
  }}
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.CLEAR, minw = TAB_W, minh = TAB_H}, nodes={
    {n=G.UIT.C, config={align = 'tm'}, nodes={
      header,
      {n=G.UIT.R, config={align = 'tm', minh = PAGE_SIZE * 0.62 + 0.1}, nodes={
        {n=G.UIT.O, config={id = 'runjournal_runs_list', object = UIBox{definition = runs_list_def(),
          config = {offset = {x = 0, y = 0}, align = 'cm'}}}},
      }},
      {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
        cycle({id = 'runjournal_page', scale = 0.8, h = 0.3, w = 2.8, options = pages,
          cycle_shoulders = true, opt_callback = 'runjournal_page', current_option = state.page,
          colour = G.C.RED, no_pips = true}, 'runjournal_page_cycle'),
      }},
    }},
  }}
end

-- Same seed ----------------------------------------------------------------------------

local CMP_COLS = {ante = 0.9, dollars = 1.2, hand = 2.35}

local function hand_name(h)
  if h == nil then return '-' end
  local ok, s = pcall(localize, h, 'poker_hands')
  if ok and type(s) == 'string' and s ~= '' and s ~= 'ERROR' then return s end
  return tostring(h)
end

local function outcome_colour(o)
  if o == 'won' then return G.C.GREEN end
  if o == 'lost' then return G.C.RED end
  if o == 'open' then return G.C.UI.TEXT_LIGHT end
  return G.C.UI.TEXT_INACTIVE
end

-- The pair the tab shows: the picked group's two newest runs, their records read now.
local function select_group(i)
  local g = model.groups[i]
  state.seed = g and i or 1
  g = model.groups[state.seed]
  if not g then compared = nil; return end
  local a, b = g.runs[#g.runs - 1], g.runs[#g.runs]
  local ok, res, err = pcall(stats.compare, a.run_id, b.run_id)
  if not ok then res, err = nil, res end
  compared = {seed = g.seed, a = a, b = b, result = res, err = res == nil and tostring(err) or nil}
end

local function run_line(tag, e)
  local result, colour = result_of(e)
  local when = type(e.started_at) == 'number' and os.date('%Y-%m-%d %H:%M', e.started_at) or '?'
  return {n=G.UIT.R, config={align = 'cm', padding = 0.02}, nodes={
    cell(tag, 0.5, G.C.UI.TEXT_DARK, nil, nil, 0.34),
    cell(when, 2.4, G.C.UI.TEXT_DARK, 'cl', nil, 0.32),
    cell(deck_name(e.deck), 2.2, G.C.UI.TEXT_DARK, 'cl', nil, 0.32),
    cell('Ante '..tostring(e.final_ante or '?'), 1.2, G.C.UI.TEXT_DARK, nil, nil, 0.32),
    cell(result, 1.6, colour, nil, nil, 0.34),
  }}
end

local function compare_row(r, diverge)
  local n = r.ante
  -- The diverging ante gets a gold outline: a red fill would hide the red 'lost' text.
  local hl = n == diverge
  local function money(v) return v and ('$'..tostring(v)) or '-' end
  return {n=G.UIT.R, config={align = 'cm', padding = 0.02}, nodes={
    {n=G.UIT.C, config={align = 'cm', r = 0.1, colour = G.C.BLACK, padding = 0.03,
      outline = hl and 1.5 or nil, outline_colour = hl and G.C.GOLD or nil}, nodes={
      cell(n, CMP_COLS.ante, G.C.UI.TEXT_LIGHT, nil, nil, 0.34),
      cell(money(r.dollars_a), CMP_COLS.dollars, G.C.MONEY, nil, 'runjournal_cmp_dollars_a_'..n, 0.34),
      cell(money(r.dollars_b), CMP_COLS.dollars, G.C.MONEY, nil, 'runjournal_cmp_dollars_b_'..n, 0.34),
      cell(hand_name(r.best_hand_a), CMP_COLS.hand, outcome_colour(r.outcome_a), nil, 'runjournal_cmp_hand_a_'..n, 0.32),
      cell(hand_name(r.best_hand_b), CMP_COLS.hand, outcome_colour(r.outcome_b), nil, 'runjournal_cmp_hand_b_'..n, 0.32),
    }},
  }}
end

local function diverge_text(res)
  if not res.diverge then return 'Same outcome at every ante', G.C.UI.TEXT_DARK end
  local row
  for _, r in ipairs(res.rows) do if r.ante == res.diverge then row = r end end
  local function say(o) return o == 'open' and 'unfinished' or o or 'not reached' end
  return 'Diverged at ante '..res.diverge..': A '..say(row and row.outcome_a)..', B '
    ..say(row and row.outcome_b), G.C.RED
end

local function compare_def()
  local rows = {}
  local c = compared
  if not c then
    rows[1] = message('No seed played twice yet', 8.2, 1.2)
  elseif not c.result then
    rows[1] = message('Run unreadable: '..tostring(c.err), 8.2, 1.2)
  else
    rows[#rows + 1] = run_line('A', c.a)
    rows[#rows + 1] = run_line('B', c.b)
    local h = G.C.UI.TEXT_DARK
    rows[#rows + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.02}, nodes={
      {n=G.UIT.C, config={align = 'cm', padding = 0.03}, nodes={
        cell('Ante', CMP_COLS.ante, h, nil, nil, 0.3), cell('Money A', CMP_COLS.dollars, h, nil, nil, 0.3),
        cell('Money B', CMP_COLS.dollars, h, nil, nil, 0.3), cell('Best hand A', CMP_COLS.hand, h, nil, nil, 0.3),
        cell('Best hand B', CMP_COLS.hand, h, nil, nil, 0.3),
      }},
    }}
    for i, r in ipairs(c.result.rows) do
      if i > CMP_ROWS then
        rows[#rows + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.02}, nodes={
          text('+'..(#c.result.rows - CMP_ROWS)..' more antes', 0.3, G.C.UI.TEXT_INACTIVE)}}
        break
      end
      rows[#rows + 1] = compare_row(r, c.result.diverge)
    end
    local t, colour = diverge_text(c.result)
    rows[#rows + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
      text(t, 0.34, colour, 'runjournal_cmp_diverge')}}
  end
  return {n=G.UIT.ROOT, config={align = 'tm', colour = G.C.CLEAR}, nodes={
    {n=G.UIT.C, config={align = 'tm'}, nodes=rows},
  }}
end

local function seed_button(i, g)
  return {n=G.UIT.R, config={align = 'cm', padding = 0.04}, nodes={
    UIBox_button({id = 'runjournal_seed_'..tostring(g.seed), label = {tostring(g.seed), #g.runs..' runs'},
      button = 'runjournal_same_seed', ref_table = {index = i},
      colour = i == state.seed and G.C.RED or G.C.BLUE, minw = 2.8, minh = 0.78, scale = 0.34}),
  }}
end

local function same_seed_def()
  local seeds = {}
  for i, g in ipairs(model.groups) do
    if i > SEED_ROWS then
      seeds[#seeds + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
        text('+'..(#model.groups - SEED_ROWS)..' more', 0.32, G.C.UI.TEXT_INACTIVE)}}
      break
    end
    seeds[#seeds + 1] = seed_button(i, g)
  end
  if #seeds == 0 then seeds[1] = message('None yet', 2.8, 0.8) end
  seeds[#seeds + 1] = caption('Seeds played more than once')
  local cmp = {
    {n=G.UIT.R, config={align = 'tm'}, nodes={
      {n=G.UIT.O, config={id = 'runjournal_compare', object = UIBox{definition = compare_def(),
        config = {offset = {x = 0, y = 0}, align = 'cm'}}}},
    }},
  }
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.CLEAR, minw = TAB_W, minh = TAB_H}, nodes={
    {n=G.UIT.R, config={align = 'tm', padding = 0.05}, nodes={
      panel('Seeds', 3.2, TAB_H - 0.4, seeds),
      {n=G.UIT.C, config={minw = 0.2}},
      panel('Newest two runs, ante by ante', 8.6, TAB_H - 0.4, cmp),
    }},
  }}
end

-- Hunts ----------------------------------------------------------------------------------

local HUNT_COLS = {name = 3.6, runs = 1.0, wins = 1.0, rate = 1.3, best = 1.3, avg = 1.3, date = 1.9}

-- stats.by_filter over the open's run list, once per open (it reads every record).
local function hunts()
  if not model.hunts then
    local ok, h = pcall(stats.by_filter, model.runs)
    if not ok then print('[RunJournal] ui: hunts: '..tostring(h)) end
    model.hunts = ok and h or {}
    model.hunts_error = not ok and tostring(h) or nil
  end
  return model.hunts
end

local function hunt_row(i, g)
  local function id(k) return 'runjournal_hunt_'..k..'_'..i end
  local avg = g.avg_ante and string.format('%.1f', g.avg_ante) or '-'
  local when = type(g.newest) == 'number' and os.date('%Y-%m-%d', g.newest) or '?'
  return {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
    {n=G.UIT.C, config={align = 'cm', r = 0.1, colour = G.C.BLACK, padding = 0.05, minh = 0.5}, nodes={
      {n=G.UIT.C, config={minw = 0.1}},
      cell(g.filter_name, HUNT_COLS.name, G.C.UI.TEXT_LIGHT, 'cl', id('name')),
      cell(g.runs, HUNT_COLS.runs, G.C.UI.TEXT_LIGHT, nil, id('runs')),
      cell(g.wins, HUNT_COLS.wins, G.C.GREEN, nil, id('wins')),
      cell(pct(g.win_rate), HUNT_COLS.rate, G.C.UI.TEXT_LIGHT, nil, id('rate')),
      cell(g.best_ante and ('Ante '..g.best_ante) or '-', HUNT_COLS.best, G.C.UI.TEXT_LIGHT, nil, id('best')),
      cell(avg, HUNT_COLS.avg, G.C.UI.TEXT_LIGHT, nil, id('avg')),
      cell(when, HUNT_COLS.date, G.C.UI.TEXT_INACTIVE, nil, id('date')),
    }},
  }}
end

local function hunts_def()
  local list = hunts()
  local c = G.C.UI.TEXT_INACTIVE
  local rows = {{n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
    {n=G.UIT.C, config={align = 'cm', padding = 0.05}, nodes={
      {n=G.UIT.C, config={minw = 0.1}},
      cell('Filter', HUNT_COLS.name, c, 'cl', nil, 0.32), cell('Runs', HUNT_COLS.runs, c, nil, nil, 0.32),
      cell('Wins', HUNT_COLS.wins, c, nil, nil, 0.32), cell('Win rate', HUNT_COLS.rate, c, nil, nil, 0.32),
      cell('Best', HUNT_COLS.best, c, nil, nil, 0.32), cell('Avg ante', HUNT_COLS.avg, c, nil, nil, 0.32),
      cell('Last run', HUNT_COLS.date, c, nil, nil, 0.32),
    }},
  }}}
  for i, g in ipairs(list) do
    if i > HUNT_ROWS then
      rows[#rows + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
        text('+'..(#list - HUNT_ROWS)..' more', 0.32, G.C.UI.TEXT_INACTIVE)}}
      break
    end
    rows[#rows + 1] = hunt_row(i, g)
  end
  if #list == 0 then rows[#rows + 1] = message('No Finder runs yet', 10, 1.2) end
  rows[#rows + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
    text('Runs started from a Seed Finder filter; rates count finished runs', 0.3, G.C.UI.TEXT_INACTIVE)}}
  if model.hunts_error then
    rows[#rows + 1] = {n=G.UIT.R, config={align = 'cm', maxw = TAB_W}, nodes={
      text('Journal unreadable: '..model.hunts_error, 0.3, G.C.RED)}}
  end
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.CLEAR, minw = TAB_W, minh = TAB_H}, nodes={
    {n=G.UIT.C, config={align = 'tm'}, nodes=rows},
  }}
end

-- Daily ------------------------------------------------------------------------------

local DAILY_COLS = {date = 2.2, mode = 1.6, seed = 2.2, deck = 3.2, result = 2.0}

-- stats.dailies over the open's run list, once per open (it reads the daily records).
local function dailies()
  if not model.dailies then
    local ok, d = pcall(stats.dailies, model.runs, cached_read)
    if not ok then print('[RunJournal] ui: dailies: '..tostring(d)) end
    model.dailies = ok and d or {}
    model.dailies_error = not ok and tostring(d) or nil
  end
  return model.dailies
end

local function daily_pages()
  return math.max(1, math.ceil(#dailies() / DAILY_ROWS))
end

-- Won, 'Ante N' for a run lost at ante N, or Unfinished.
local function daily_result(d)
  if d.won == true then return 'Won', G.C.GREEN end
  if d.won == false then return 'Ante '..tostring(d.final_ante or '?'), G.C.RED end
  return 'Unfinished', G.C.UI.TEXT_INACTIVE
end

local MODE_LABELS = {blind = 'Blind', routed = 'Routed'}

local function daily_row(i, d)
  local function id(k) return 'runjournal_daily_'..k..'_'..i end
  local result, colour = daily_result(d)
  return {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
    {n=G.UIT.C, config={align = 'cm', r = 0.1, colour = G.C.BLACK, padding = 0.05, minh = 0.5}, nodes={
      cell(d.date or '?', DAILY_COLS.date, G.C.UI.TEXT_LIGHT, nil, id('date')),
      cell(MODE_LABELS[d.mode] or '-', DAILY_COLS.mode, d.mode == 'blind' and G.C.FILTER or G.C.UI.TEXT_LIGHT, nil, id('mode')),
      cell(tostring(d.seed or '?'), DAILY_COLS.seed, G.C.UI.TEXT_LIGHT, nil, id('seed')),
      cell(deck_name(d.deck), DAILY_COLS.deck, G.C.UI.TEXT_LIGHT, nil, id('deck')),
      cell(result, DAILY_COLS.result, colour, nil, id('result')),
    }},
  }}
end

local function daily_def()
  local list = dailies()
  local pages = daily_pages()
  state.dpage = math.min(state.dpage, pages)
  local c = G.C.UI.TEXT_INACTIVE
  local rows = {}
  local first = (state.dpage - 1) * DAILY_ROWS
  for i = first + 1, math.min(first + DAILY_ROWS, #list) do rows[#rows + 1] = daily_row(i - first, list[i]) end
  if #rows == 0 then rows[1] = message('No daily runs yet', 10, 1.2, 'runjournal_daily_none') end
  local page_labels = {}
  for i = 1, pages do page_labels[i] = localize('k_page')..' '..i..'/'..pages end
  local body = {
    {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
      {n=G.UIT.C, config={align = 'cm', padding = 0.05}, nodes={
        cell('Date', DAILY_COLS.date, c, nil, nil, 0.32), cell('Mode', DAILY_COLS.mode, c, nil, nil, 0.32),
        cell('Seed', DAILY_COLS.seed, c, nil, nil, 0.32), cell('Deck', DAILY_COLS.deck, c, nil, nil, 0.32),
        cell('Result', DAILY_COLS.result, c, nil, nil, 0.32),
      }},
    }},
    {n=G.UIT.R, config={align = 'tm', minh = DAILY_ROWS * 0.62 + 0.1}, nodes={
      {n=G.UIT.C, config={align = 'tm'}, nodes=rows},
    }},
    {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
      cycle({id = 'runjournal_dpage', scale = 0.8, h = 0.3, w = 2.8, options = page_labels,
        opt_callback = 'runjournal_dpage', current_option = state.dpage, colour = G.C.RED, no_pips = true},
        'runjournal_dpage_cycle'),
    }},
    {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
      text('The daily seed: one seed and deck per UTC day, White Stake. Blind: the Oracle was locked',
        0.3, G.C.UI.TEXT_INACTIVE)}},
  }
  if model.dailies_error then
    body[#body + 1] = {n=G.UIT.R, config={align = 'cm', maxw = TAB_W}, nodes={
      text('Journal unreadable: '..model.dailies_error, 0.3, G.C.RED)}}
  end
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.CLEAR, minw = TAB_W, minh = TAB_H}, nodes={
    {n=G.UIT.C, config={align = 'tm'}, nodes=body},
  }}
end

-- Overlay ----------------------------------------------------------------------------

-- A tab whose definition function also notes it as the tab on screen (rebuild_tab).
local function tab(label, fn, chosen)
  local def
  def = function() current_tab = def; return fn() end
  return {label = label, chosen = chosen, tab_definition_function = def}
end

-- The width of `s` drawn at text scale `scale`, in room units, as the layout measures
-- a G.UIT.T (engine/ui.lua, UIBox:calculate_xywh): the font's width times squish,
-- scale and FONTSCALE, over TILESIZE. A rough per-character estimate without a font.
local function text_w(s, scale)
  local font = G.LANG and G.LANG.font
  local ok, w = pcall(function()
    return font.FONT:getWidth(s) * font.squish * scale * font.FONTSCALE / G.TILESIZE
  end)
  if ok and type(w) == 'number' then return w end
  return #s * 0.45 * scale
end

-- Fits create_tabs' buttons (in the 'tab_shoulders' column) to their labels, so the
-- row is TAB_ROW_W wide: the buttons share TAB_ROW_W less the shoulder pips (2 x 0.7)
-- and the column's padding ((n + 1) x 0.15). Each label needs its width at TAB_TEXT
-- plus TAB_MARGIN; when they all fit, the narrow buttons share one width (the largest
-- that still fits) and the wide ones hug their label, so every label keeps TAB_TEXT.
-- When they don't, every label is shrunk by one factor first (the layout scales a
-- label to its row's maxw). Ids and labels stay vanilla's: 'tab_but_<label>'.
local function fit_tabs(node)
  if type(node) ~= 'table' then return end
  if not (node.config and node.config.id == 'tab_shoulders') then
    for _, child in ipairs(node.nodes or {}) do fit_tabs(child) end
    return
  end
  local buttons, need = {}, {}
  for _, b in ipairs(node.nodes or {}) do
    local inner = type(b) == 'table' and b.nodes and b.nodes[1]
    if inner and inner.config and inner.config.button == 'change_tab' then
      local label = inner.config.ref_table and inner.config.ref_table.label or ''
      buttons[#buttons + 1] = inner
      need[#need + 1] = text_w(tostring(label), TAB_TEXT)
    end
  end
  local n = #buttons
  if n == 0 then return end
  local room = TAB_ROW_W - 2 * 0.7 - (n + 1) * 0.15
  local total = 0
  for _, w in ipairs(need) do total = total + w end
  local k = math.min(1, (room - n * TAB_MARGIN) / math.max(total, 0.01))
  local natural, sorted = {}, {}
  for i, w in ipairs(need) do natural[i] = w * k + TAB_MARGIN; sorted[i] = natural[i] end
  table.sort(sorted)
  -- The shared width: buttons 1..j of the sorted list at `level`, the rest at their own.
  local level, rest = 0, 0
  for j = n, 1, -1 do
    local w = (room - rest) / j
    if w >= sorted[j] - 1e-9 then level = w; break end
    rest = rest + sorted[j]
  end
  for i, b in ipairs(buttons) do narrow(b, math.max(level, natural[i])) end
end

local function overlay_def()
  local tabs = create_tabs({tabs = {
    tab('Overview', overview_def, true),
    tab('Decks/Stakes', tables_def),
    tab('Jokers', jokers_def),
    tab('Runs', runs_def),
    tab('Same seed', same_seed_def),
    tab('Hunts', hunts_def),
    tab('Daily', daily_def),
  }, snap_to_nav = true, tab_h = TAB_H, tab_w = TAB_W})
  fit_tabs(tabs)
  local t = create_UIBox_generic_options({back_func = 'options', contents = {tabs}})
  open_marker = t
  return t
end

function M.is_open()
  return G.OVERLAY_MENU ~= nil and open_marker ~= nil and G.OVERLAY_MENU.definition == open_marker
end

function M.compared() return compared end

function M.hunts() return model and model.hunts end

function M.selected_joker()
  local j = model and model.jokers and model.jokers[state.joker]
  return j and j.key
end

function M.filter() return copy(session_filter()) end

function M.jokers() return model and model.jrows end

function M.dailies() return model and model.dailies end

function M.open()
  model = build_model()
  refresh()
  state.page = math.min(state.page, page_count())
  select_group(math.min(state.seed, math.max(1, #model.groups)))
  live.export_head = 'Writes to the save folder'
  live.export_path = ''
  G.SETTINGS.paused = true
  G.FUNCS.overlay_menu{definition = overlay_def()}
  return true
end

-- Options button ------------------------------------------------------------------------

-- The node whose rows hold the Settings button.
local function options_list(node)
  if type(node) ~= 'table' or type(node.nodes) ~= 'table' then return nil end
  for _, child in pairs(node.nodes) do
    if type(child) == 'table' and type(child.nodes) == 'table' then
      for _, inner in pairs(child.nodes) do
        if type(inner) == 'table' and type(inner.config) == 'table' and inner.config.button == 'settings' then
          return node
        end
      end
    end
  end
  for _, child in pairs(node.nodes) do
    local found = options_list(child)
    if found then return found end
  end
end

local function row_button(child)
  if type(child) ~= 'table' or type(child.nodes) ~= 'table' then return nil end
  for _, inner in pairs(child.nodes) do
    if type(inner) == 'table' and type(inner.config) == 'table' and inner.config.button then
      return inner.config.button
    end
  end
end

local function has_button(node, name)
  if type(node) ~= 'table' then return false end
  if type(node.config) == 'table' and node.config.button == name then return true end
  for _, child in pairs(node.nodes or {}) do
    if has_button(child, name) then return true end
  end
  return false
end

-- The pause menu of a seeded run already fills the room with SaveSlots' and
-- SeedOracle's rows, so the button shares vanilla's Stats row instead of adding
-- one: [Stats][Run Journal], each half as wide, the pair as wide as the others.
-- With no Stats row it goes at the end. Vanilla leaves nil holes for options
-- that don't apply; the list is rebuilt dense either way.
local function add_button(t)
  local list = options_list(t)
  if not list or has_button(list, 'runjournal_open') then return t end
  local nodes, placed = {}, false
  for i = 1, table.maxn(list.nodes) do
    local child = list.nodes[i]
    if child ~= nil then
      nodes[#nodes + 1] = child
      if not placed and row_button(child) == 'high_scores' then
        for _, inner in pairs(child.nodes) do
          if type(inner) == 'table' and type(inner.config) == 'table' and inner.config.button == 'high_scores' then
            narrow(inner, HALF_W)
            child.nodes = {
              {n=G.UIT.C, config={align = 'cm'}, nodes={inner}},
              {n=G.UIT.C, config={minw = 0.1}},
              UIBox_button{label = {'Run Journal'}, button = 'runjournal_open', minw = HALF_W, col = true},
            }
            placed = true
            break
          end
        end
      end
    end
  end
  if not placed then
    nodes[#nodes + 1] = UIBox_button{label = {'Run Journal'}, button = 'runjournal_open', minw = 5}
  end
  list.nodes = nodes
  return t
end

function M.install()
  if installed then return end
  installed = true

  local orig_options = create_UIBox_options
  create_UIBox_options = function(...)
    return add_button(orig_options(...))
  end

  G.FUNCS.runjournal_open = function(e) M.open() end

  G.FUNCS.runjournal_export = function(e)
    local fmt = e and e.config and e.config.ref_table and e.config.ref_table.fmt
    if fmt ~= 'csv' and fmt ~= 'json' then return end
    local export = type(RunJournal) == 'table' and RunJournal.export or stats.export
    local ok, path, err = pcall(export, fmt)
    if not ok then path, err = nil, path end
    M.last_export = {fmt = fmt, path = path, err = path == nil and tostring(err) or nil}
    if path then
      live.export_head = 'Saved '..string.upper(fmt)..' to the save folder:'
      live.export_path = tostring(path)
    else
      live.export_head = 'Export failed'
      live.export_path = tostring(err)
      print('[RunJournal] export '..fmt..' failed: '..tostring(err))
    end
  end

  G.FUNCS.runjournal_joker_cycle = function(e) return G.FUNCS.option_cycle(e) end
  G.FUNCS.runjournal_joker = function(args)
    if not (args and args.cycle_config and model) then return end
    set_joker(args.cycle_config.current_option)
  end

  G.FUNCS.runjournal_same_seed = function(e)
    local i = e and e.config and e.config.ref_table and e.config.ref_table.index
    if not (model and model.groups[i]) then return end
    select_group(i)
    local menu = G.OVERLAY_MENU
    if not menu then return end
    for j, g in ipairs(model.groups) do
      local b = menu:get_UIE_by_ID('runjournal_seed_'..tostring(g.seed))
      if b then b.config.colour = j == state.seed and G.C.RED or G.C.BLUE end
    end
    local node = menu:get_UIE_by_ID('runjournal_compare')
    if not node then return end
    if node.config.object then node.config.object:remove() end
    node.config.object = UIBox{definition = compare_def(),
      config = {offset = {x = 0, y = 0}, align = 'cm', parent = node}}
    node.UIBox:recalculate()
  end

  G.FUNCS.runjournal_page_cycle = function(e) return G.FUNCS.option_cycle(e) end
  G.FUNCS.runjournal_page = function(args)
    if not (args and args.cycle_config and model) then return end
    state.page = args.cycle_config.current_option
    local node = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('runjournal_runs_list')
    if not node then return end
    if node.config.object then node.config.object:remove() end
    node.config.object = UIBox{definition = runs_list_def(),
      config = {offset = {x = 0, y = 0}, align = 'cm', parent = node}}
    node.UIBox:recalculate()
  end

  -- The filter bar. Option 1 is All; decks follow model.deck_options, stakes 1-8.
  G.FUNCS.runjournal_fdeck_cycle = function(e) return G.FUNCS.option_cycle(e) end
  G.FUNCS.runjournal_fdeck = function(args)
    if not (args and args.cycle_config and model) then return end
    local d = model.deck_options[args.cycle_config.current_option - 1]
    session_filter().deck = d and d.key or nil
    filter_changed()
  end
  G.FUNCS.runjournal_fstake_cycle = function(e) return G.FUNCS.option_cycle(e) end
  G.FUNCS.runjournal_fstake = function(args)
    if not (args and args.cycle_config and model) then return end
    local n = args.cycle_config.current_option - 1
    session_filter().stake = n >= 1 and n or nil
    filter_changed()
  end

  -- The Jokers tab.
  G.FUNCS.runjournal_jsort_cycle = function(e) return G.FUNCS.option_cycle(e) end
  G.FUNCS.runjournal_jsort = function(args)
    if not (args and args.cycle_config and model) then return end
    state.sort = SORTS[args.cycle_config.current_option] and args.cycle_config.current_option or 1
    state.jpage = 1
    stats.sort_jokers(joker_rows(), SORTS[state.sort])
    rebuild_tab()
  end
  G.FUNCS.runjournal_jpage_cycle = function(e) return G.FUNCS.option_cycle(e) end
  G.FUNCS.runjournal_jpage = function(args)
    if not (args and args.cycle_config and model) then return end
    state.jpage = args.cycle_config.current_option
    rebuild_tab()
  end

  -- The Daily tab.
  G.FUNCS.runjournal_dpage_cycle = function(e) return G.FUNCS.option_cycle(e) end
  G.FUNCS.runjournal_dpage = function(args)
    if not (args and args.cycle_config and model) then return end
    state.dpage = args.cycle_config.current_option
    rebuild_tab()
  end
end

return M
