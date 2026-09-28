-- seedfinder.ui: the Seed Finder overlay, its Options/pause button and the Play
-- screen's "Find" tab. Contract: docs/contracts-0.2.md § SeedFinder "UI".
--
-- Entry points (both wrap vanilla, call the original with every argument and change
-- only what comes back; no vanilla body is copied)
--   create_UIBox_options   a "Seed Finder" button sharing vanilla's "Customize Deck"
--                          (customize_deck) row, half width each, on the main menu and
--                          in the pause menu alike: a seeded run's pause menu is out of
--                          vertical room (journal/2026-09-23-oracle-and-ui-traps.md), so
--                          no new row. RunJournal shares the Stats row, SaveSlots goes
--                          after Settings, SeedOracle before New Run: each keys on its
--                          own anchor, so every wrap order gives the same menu.
--   G.UIDEF.run_setup      on the main menu only, a "Find" tab after SaveSlots' "Saves"
--                          tab (after Continue without SaveSlots). Same technique as
--                          saveslots.entry: create_tabs is wrapped for the duration of
--                          run_setup and the tab goes into its args before the original
--                          runs. Either wrap order ends New Run, Continue, Saves, Find,
--                          Challenges.
--
-- Overlay (create_UIBox_generic_options; Back returns to where it was opened from:
-- Options, the pause menu or the Play screen)
--   Filter panel   the saved filters (a cycle, New, Delete, Rename, Save as); deck,
--                  stake, match (all/any clauses) and "All unlocked". Deck and stake follow
--                  vanilla's run-setup rule: only unlocked decks, stakes up to one
--                  above the deck's best win (all of them on an all-unlocked
--                  profile). Then the clause list (at most MAX_CLAUSES rows: kind,
--                  ante, an extra field, key, remove) and "Add clause". Keys come
--                  from the G.P_* pools with localized names (jokers sorted by name). The extra field is
--                  the blind for a tag (Any/Small/Big),
--                  the rerolls for a shop joker, the Soul's index for a legendary;
--                  soul_in_pack's key cycle picks the pack and the source. A
--                  filter's name is generated from its clauses ("Charm Tag + Soul
--                  in Arcana", cut at NAME_MAX) until the player types one: then
--                  `named` is true (an additive field, kept in filters.jkr; sane()
--                  keeps it only as a boolean) and clause edits leave the name
--                  alone. A typed name is trimmed and capped at NAME_MAX (30); an
--                  empty or blank one clears `named`, and the generated name comes
--                  back at once. Hits, Save as hunt (origin.filter_name, and the
--                  filter in the share code) and RunJournal's per-filter stats all
--                  read f.name, so they carry a typed name unchanged.
--   Name editor    Rename opens it in the deck/stake/mode row's place (same
--                  height): "Name", a text input (bh_digits, so a typed '0' stays
--                  '0': BHCore.install_digits; extended corpus; NAME_MAX letters)
--                  prefilled with a typed name, or empty with the generated name as
--                  its prompt; then Save and Cancel. It is hooked when it opens, so
--                  typing goes straight in; Return in it saves, as Save does.
--                  Cancel keeps the old name (nothing is written until a save).
--                  Save as puts a deep copy of the current filter (no table shared,
--                  `named` copied) right after it, makes the copy current and opens
--                  the editor on it; cancelling that keeps the copy. The editor
--                  closes, and its text-input hook is released at once, whenever
--                  its box goes away: the filter cycle, New, Delete, Save as,
--                  ui.set_filter, Start, Play, and leaving or reopening the overlay
--                  (no key press lands on a removed input). A clause edit rebuilds
--                  the panel with the editor still open and hooked.
--   Search panel   workers (1..8), Start / Cancel, live Scanned / Rate / Hits / Per M
--                  (verified plus pending hits per million scanned, engine.poll's
--                  hits_per_million, while a search runs) and a status line; Odds
--                  and its lines; then the hits, PAGE per page (a page cycle; the
--                  search stops at MAX_HITS), each with its route cost ("A1 R0":
--                  the ante the route ends in, its rerolls), Play, Route and Save
--                  as hunt. Hits are listed cheapest route first (route.rank);
--                  each new hit's details come from filter.eval_seed on this
--                  thread once (MAX_HITS caps them: never a scan), and the list
--                  is re-sorted only when it grows, so a row never moves between
--                  rebuilds. Row ids keep the hit's index in ui.search().found.
--                  The Find tab shows the three cheapest the same way.
--   Odds           the button samples ODDS_SAMPLE seeds of the current filter on
--                  the workers (engine.sample, a worker job; never on an edit, never
--                  on this thread) and, once done, shows odds.estimate's figure:
--                  "about 1 in N seeds, ~T at R" (N and T to two significant
--                  digits: 38M, 10 min), the bottleneck clause by its generated
--                  label, and "(extrapolated)" when the estimate says so. R is the
--                  last search's rate, or else the sample's own seeds/s times
--                  (clauses + 1), since a sample evaluates every clause alone and the
--                  whole filter once more. A clause that never passed says so
--                  instead, over both lines: "clause k never passed in 20,000
--                  seeds: | it may be impossible or locked (<label>)". The lines clear (and a running sample is cancelled) as
--                  soon as the filter differs from the one sampled, its name aside
--                  (a rename keeps them).
--   Width          the overlay keeps one width whatever it shows (T-316): the clause
--                  rows and hit rows fit inside their panels' minw, and the status and
--                  odds lines are held by maxw. A row wider than its panel's minw
--                  would widen the whole overlay the moment it appeared. The filter
--                  row (cycle + four buttons) and the name editor's row fit FILTER_W
--                  too: a long name is shrunk to the filter cycle's width, and the
--                  editor's input is wide enough for NAME_MAX of the widest letter.
--   Every edit is written to <profile>/seedfinder/filters.jkr (bhcore.fs) at once.
--
-- Play (a hit)       refuses (status line + the cancel sound) a filter whose deck or
--                    stake this profile hasn't unlocked (one from filters.jkr can
--                    be); otherwise cancels a running search, tells RunJournal the filter's name
--                    (recorder.set_origin), and starts a run on the hit's seed with
--                    the filter's deck (G.GAME.viewed_back, as vanilla's run setup
--                    does) and stake. The run is unseeded, as Brainstorm's reroll
--                    makes it: vanilla's start_run marks any run given a seed as
--                    `seeded` (game.lua:2163), which keeps it out of unlocks, stats
--                    and high scores, so the Game:start_run wrap clears the flag
--                    once start_run returns, for that seed's run only.
-- Route (a hit)      replaces the overlay (or the Play screen) with the hit's Route
--                    panel: the seed, route.build(filter, details) grouped by
--                    ante (each step's text, word-wrapped to the panel), and the
--                    cost line. details come from filter.eval_seed on this thread
--                    for that one seed, when the panel opens (never a scan). Play
--                    is the row's Play; Back returns to the overlay, or to the
--                    Play screen's Find tab when the row was there.
-- Save as hunt       Play, then the new run's first autosave (SaveSlots' checkpoint
--                    snapshot, D6: never save.jkr, never a forced save_run) goes to
--                    store.save(snapshot, 'Hunt <seed>', nil, {kind = 'hunt', origin =
--                    {kind = 'finder', filter_name, filter}}). It waits for bh-core's
--                    run_start of that seed first, because until then checkpoint.get()
--                    still returns the previous run's snapshot.
--
-- Driving: one ticker event (no_delete, non-blocking, pause_force, 'other' queue)
-- runs while the overlay is up, a search runs or a hunt waits. It polls the engine
-- every frame, updates the live texts and rebuilds the filter or results panel a
-- frame after a change (never inside the clicked element's own callback).
--
-- API
--   ui.install()          wraps the entry points and registers G.FUNCS. Once.
--   ui.open(from)         opens the overlay; from = 'options' | 'pause' | 'play'.
--   ui.is_open()          whether the overlay is up.
--   ui.current()          the filter being edited (a live table; don't mutate it).
--   ui.search()           {filter, found = {seed...}, scanned, rate, done, running,
--                          cancelled, error, handle, order, costs} of the last
--                          search, or nil. found is in scan order; order lists
--                          found's indices cheapest route first, costs[i] is
--                          found[i]'s route cost (nil without a route).
--                          handle is its engine handle, kept after the search ends
--                          (engine.alive(handle) says whether its threads exited;
--                          nil for hits given by ui.set_results).
--   ui.hunt()             the pending or last hunt: {seed, state = 'waiting'|'saved'|
--                          'failed', id?, err?}, or nil.
--   ui.save_filters()     writes the filters now: true | nil, err.
--   ui.set_results(f, seeds) shows seeds as the finished hits of a search for a
--                          copy of f (cancelling any running search), so a pinned
--                          seed gets the hit rows without a scan. true | nil, err.
--   ui.route()            the Route panel's state while it is up: {i, seed, filter,
--                          route, err, from = 'overlay'|'tab'}, or nil. route is
--                          route.build's result, nil with err when it has none.
--   ui.odds()             the Odds state for the current filter: {filter, n, done,
--                          counts, estimate, rate, lines = {text...}, err, sample}, or nil
--                          (never pressed, or cleared by a filter change). counts is
--                          the engine's tallies (odds' counts shape); estimate is
--                          engine.poll's odds.estimate once done; lines is what the
--                          panel shows (one sentence may run over both); sample is the engine handle, kept after the
--                          job ends (engine.alive(sample) says whether it exited).
--   ui.set_filter(f)      replaces the filter being edited with a copy of f (as a
--                          filter from disk is taken: sane), renamed (unless f.named),
--                          saved and redrawn; an open name editor closes. true | nil, err.
--   ui.round_count(n), ui.round_time(secs) the Odds line's rounding, as text.
-- Buttons (G.FUNCS names, for ctx.click; ids in brackets)
--   seedfinder_open (Options/pause/Find tab), seedfinder_cycle (every cycle arrow:
--   [seedfinder_<cycle>_l|_r], cycles: filter, deck, stake, mode, workers, c<i>_kind,
--   c<i>_ante, c<i>_extra, c<i>_key, hits_page), seedfinder_add, seedfinder_remove
--   [seedfinder_remove_<i>], seedfinder_new, seedfinder_delete, seedfinder_rename
--   [seedfinder_rename], seedfinder_save_as [seedfinder_save_as], in the name editor
--   seedfinder_name_save [seedfinder_name_save] and seedfinder_name_cancel
--   [seedfinder_name_cancel] (its input: the only 'text_input' in the Filter panel;
--   Return calls seedfinder_name_return), seedfinder_start,
--   seedfinder_cancel, seedfinder_odds, seedfinder_play [seedfinder_play_<i>, seedfinder_tabplay_<i>],
--   seedfinder_hunt [seedfinder_hunt_<i>], seedfinder_route [seedfinder_route_<i>,
--   seedfinder_tabroute_<i>]; in the Route panel seedfinder_play
--   [seedfinder_route_play] and the generic Back (seedfinder_route_back). Live
--   text ids: seedfinder_scanned, seedfinder_rate, seedfinder_hits, seedfinder_hpm,
--   seedfinder_status; the Odds lines: seedfinder_odds_<k> (k = 1, 2). Route panel text ids: seedfinder_route_title, one per
--   wrapped line of step k: seedfinder_step_<k>_<line>, seedfinder_route_cost.
--
-- The game font (m6x11plus) has no '·' or '—' glyphs: plain ASCII only.
local filter = require('seedfinder.filter')
local engine = require('seedfinder.engine')
local route = require('seedfinder.route')
local fs = require('bhcore.fs')

local M = {}

local MAX_CLAUSES = 6
local MAX_HITS = 64       -- the search stops there
local PAGE = 8            -- hits per page of the results list
local MAX_ANTE = 8
local MAX_REROLLS = 5
local NAME_MAX = 30
local ROOT_ID = 'seedfinder_root'
local FILTER_W, SEARCH_W = 11.6, 6.2
local ODDS_SAMPLE = 20000 -- seeds per Odds press
local HALF_W = 2.45       -- the Customize Deck / Seed Finder pair: 2 x 2.45 + 0.1 = vanilla's 5
local TAB_W, TAB_H = 6.4, 5.2
local ROW2_H = 0.82       -- the deck/stake/mode row, and the name editor in its place
local ROUTE_W = 11        -- the Route panel; its step lines wrap at ROUTE_W - 1

local installed = false
local from = 'options'
local store = nil         -- {profile, filters = {f...}, current = i}
local search = nil        -- see ui.search()
local handle = nil        -- the engine handle of the running search
local hunt = nil          -- see ui.hunt()
local unseed = nil        -- the seed Play started, until its start_run clears `seeded`
local ticking = false
local dirty = {}          -- panels to rebuild on the next tick
local workers = nil
local page = 1            -- the results list's page
local shown = nil         -- see ui.route()
local odds_job = nil      -- see ui.odds(); plus handle, the engine handle while it runs
local editor = nil        -- the name editor while open: {filter, text}; text is its input's ref_value
-- Live text (UIT.T ref_table/ref_value).
local live = {scanned = '0', rate = '-', hits = '0', hpm = '-', status = ''}

-- Names -------------------------------------------------------------------------

local function name_of(set, key)
  if key == nil then return '?' end
  local ok, s = pcall(localize, {type = 'name_text', set = set, key = key})
  if ok and type(s) == 'string' and s ~= '' and s ~= 'ERROR' then return s end
  return tostring(key)
end

local function by_order(list)
  table.sort(list, function(a, b)
    local x, y = a.order or 0, b.order or 0
    if x ~= y then return x < y end
    return tostring(a.key) < tostring(b.key)
  end)
  return list
end

local function commas(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  return (s:reverse():gsub('(%d%d%d)', '%1,'):gsub(',$', ''):reverse())
end

-- x to two significant digits, as text without a trailing ".0" (38, 3.8, 380).
local function two_digits(x)
  if x >= 10 then
    local mag = 10 ^ (math.floor(math.log10(x)) - 1)
    return tostring(math.floor(x / mag + 0.5) * mag)
  end
  local r = math.floor(x * 10 + 0.5) / 10
  return r % 1 == 0 and tostring(math.floor(r)) or ('%.1f'):format(r)
end

-- A seed count for reading: 81, 740, 1.2K, 38M, 4.1B. Below 100 it is the whole
-- number; above, rounded to two significant digits first, then given the largest
-- suffix it reaches (so 999,600 reads 1M, not 1000K).
function M.round_count(n)
  n = tonumber(n) or 0
  if n < 100 then return tostring(math.floor(n + 0.5)) end
  local mag = 10 ^ (math.floor(math.log10(n)) - 1)
  local r = math.floor(n / mag + 0.5) * mag
  for _, u in ipairs{{1e9, 'B'}, {1e6, 'M'}, {1e3, 'K'}} do
    if r >= u[1] then return two_digits(r / u[1])..u[2] end
  end
  return two_digits(r)
end

-- A duration for reading: 40 s, 10 min, 3.5 h, 12 days.
function M.round_time(secs)
  secs = tonumber(secs) or 0
  if secs < 1 then return 'under 1 s' end -- the Odds line drops its "~" for this one
  if secs < 60 then return two_digits(secs)..' s' end
  if secs < 3600 then return two_digits(secs / 60)..' min' end
  if secs < 48 * 3600 then return two_digits(secs / 3600)..' h' end
  return two_digits(secs / 86400)..' days'
end

-- Clause kinds ----------------------------------------------------------------------

local KINDS = {
  {kind = 'tag', label = 'Skip tag'},
  {kind = 'soul_in_pack', label = 'Soul in pack'},
  {kind = 'boss', label = 'Boss'},
  {kind = 'voucher', label = 'Voucher'},
  {kind = 'legendary', label = 'Soul joker'},
  {kind = 'shop_joker', label = 'Shop joker'},
  {kind = 'pack', label = 'Shop pack'},
}

local SOUL_PACKS = {
  {pack = 'arcana', from_tag = true, label = 'Arcana, tag skip'},
  {pack = 'spectral', from_tag = true, label = 'Spectral, tag skip'},
  {pack = 'arcana', from_tag = false, label = 'Arcana, in shop'},
  {pack = 'spectral', from_tag = false, label = 'Spectral, in shop'},
}

local PACK_KINDS = {{'arcana', 'Arcana'}, {'celestial', 'Celestial'}, {'spectral', 'Spectral'},
  {'standard', 'Standard'}, {'buffoon', 'Buffoon'}}
local PACK_SIZES = {{'', 'Any %s'}, {'_normal', '%s Pack'}, {'_jumbo', 'Jumbo %s'}, {'_mega', 'Mega %s'}}

-- Jokers by their shown (localized) name, so a long cycle is searchable by eye.
local function by_name(set, list)
  for _, e in ipairs(list) do e.name = name_of(set, e.key) end
  table.sort(list, function(a, b)
    local x, y = a.name:lower(), b.name:lower()
    if x ~= y then return x < y end
    return tostring(a.key) < tostring(b.key)
  end)
  return list
end

local pools = {}          -- kind -> {labels, values}, built once the game's prototypes exist

local function key_pool(kind)
  if pools[kind] then return pools[kind] end
  local labels, values = {}, {}
  local function add(v, l) values[#values + 1] = v; labels[#labels + 1] = l end
  if kind == 'tag' then
    local list = {}
    for k, t in pairs(G.P_TAGS) do list[#list + 1] = {key = k, order = t.order} end
    for _, t in ipairs(by_order(list)) do add(t.key, name_of('Tag', t.key)) end
  elseif kind == 'boss' then
    local list = {}
    for k, b in pairs(G.P_BLINDS) do
      if b.boss then list[#list + 1] = {key = k, order = b.order} end
    end
    for _, b in ipairs(by_order(list)) do add(b.key, name_of('Blind', b.key)) end
  elseif kind == 'voucher' then
    for _, v in ipairs(G.P_CENTER_POOLS.Voucher) do add(v.key, name_of('Voucher', v.key)) end
  elseif kind == 'legendary' then
    add(false, 'Any legendary')
    local list = {}
    for _, j in ipairs(G.P_JOKER_RARITY_POOLS[4]) do list[#list + 1] = {key = j.key} end
    for _, j in ipairs(by_name('Joker', list)) do add(j.key, j.name) end
  elseif kind == 'shop_joker' then
    local list = {}
    for _, j in ipairs(G.P_CENTER_POOLS.Joker) do list[#list + 1] = {key = j.key} end
    for _, j in ipairs(by_name('Joker', list)) do add(j.key, j.name) end
  elseif kind == 'soul_in_pack' then
    for i, p in ipairs(SOUL_PACKS) do add(i, p.label) end
  elseif kind == 'pack' then
    for _, pk in ipairs(PACK_KINDS) do
      for _, sz in ipairs(PACK_SIZES) do add('p_'..pk[1]..sz[1], string.format(sz[2], pk[2])) end
    end
  end
  pools[kind] = {labels = labels, values = values}
  return pools[kind]
end

-- The extra field of a clause kind: {field, labels, values}, or nil.
local function extra_of(kind)
  if kind == 'tag' then
    return {field = 'blind', labels = {'Any blind', 'Small', 'Big'}, values = {'any', 'Small', 'Big'}}
  elseif kind == 'shop_joker' then
    local labels, values = {}, {}
    for r = 0, MAX_REROLLS do
      values[#values + 1] = r
      labels[#labels + 1] = r == 0 and 'No rerolls' or (r..(r == 1 and ' reroll' or ' rerolls'))
    end
    return {field = 'rerolls', labels = labels, values = values}
  elseif kind == 'legendary' then
    return {field = 'index', labels = {'1st Soul', '2nd Soul'}, values = {1, 2}}
  end
end

-- A clause of `kind` with every field at its first option (ante kept when given).
local function default_clause(kind, ante)
  local c = {kind = kind}
  if kind ~= 'legendary' then c.ante = ante or 1 end
  local ex = extra_of(kind)
  if ex then c[ex.field] = ex.values[1] end
  local pool = key_pool(kind)
  if kind == 'soul_in_pack' then
    c.pack, c.from_tag = SOUL_PACKS[1].pack, SOUL_PACKS[1].from_tag
  elseif kind == 'pack' then
    c.key_prefix = pool.values[1]
  elseif kind == 'legendary' then
    c.key = nil
  else
    c.key = pool.values[1]
  end
  return c
end

-- The key-cycle value a clause holds.
local function key_value(c)
  if c.kind == 'soul_in_pack' then
    for i, p in ipairs(SOUL_PACKS) do
      if p.pack == c.pack and p.from_tag == (c.from_tag == true) then return i end
    end
    return 1
  elseif c.kind == 'pack' then
    return c.key_prefix
  elseif c.kind == 'legendary' then
    return c.key or false
  end
  return c.key
end

local function set_key(c, v)
  if c.kind == 'soul_in_pack' then
    local p = SOUL_PACKS[v] or SOUL_PACKS[1]
    c.pack, c.from_tag = p.pack, p.from_tag
  elseif c.kind == 'pack' then
    c.key_prefix = v
  elseif c.kind == 'legendary' then
    c.key = v or nil
  else
    c.key = v
  end
end

local function label_for(pool, v)
  for i, x in ipairs(pool.values) do
    if x == v then return pool.labels[i] end
  end
  return tostring(v)
end

local function describe(c)
  if c.kind == 'soul_in_pack' then
    return 'Soul in '..(c.pack == 'spectral' and 'Spectral' or 'Arcana')..(c.from_tag and '' or ' (shop)')
  elseif c.kind == 'legendary' then
    return c.key and name_of('Joker', c.key) or ('Soul '..tostring(c.index))
  end
  return label_for(key_pool(c.kind), key_value(c))
end

-- Filters ---------------------------------------------------------------------------

local function new_filter()
  return {name = 'Empty filter', stake = 1, deck = 'b_red', all_unlocked = false, mode = 'all', clauses = {}}
end

local function copy(v)
  if type(v) ~= 'table' then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

-- A name as the player typed it: trimmed and capped at NAME_MAX ('' for a blank one).
local function clean_name(s)
  s = tostring(s or ''):match('^%s*(.-)%s*$')
  if #s > NAME_MAX then s = s:sub(1, NAME_MAX):match('^(.-)%s*$') end
  return s
end

-- A filter's name comes from its clauses, unless the player typed one (named).
local function rename(f)
  if f.named then return end
  local parts = {}
  for _, c in ipairs(f.clauses) do parts[#parts + 1] = describe(c) end
  local s = #parts > 0 and table.concat(parts, ' + ') or 'Empty filter'
  if #s > NAME_MAX then s = s:sub(1, NAME_MAX - 3)..'...' end
  f.name = s
end

local function profile_path()
  return tostring(G.SETTINGS.profile)..'/seedfinder/filters.jkr'
end

-- A filter from disk, or nil when it isn't one (an empty clause list is kept: it's
-- a filter being built).
local function sane(f)
  if type(f) ~= 'table' or type(f.clauses) ~= 'table' then return nil end
  local g = new_filter()
  for _, k in ipairs{'name', 'stake', 'deck', 'all_unlocked', 'mode'} do
    if f[k] ~= nil then g[k] = f[k] end
  end
  if type(f.named) == 'boolean' then g.named = f.named end
  for i, c in ipairs(f.clauses) do
    if i > MAX_CLAUSES then break end
    g.clauses[#g.clauses + 1] = copy(c)
  end
  local probe = copy(g)
  if #probe.clauses == 0 then probe.clauses = {default_clause('tag')} end
  if not filter.validate(probe) then return nil end
  -- A typed name held as typed (validate made it a string); a blank one is no name.
  if g.named then
    g.name = clean_name(g.name)
    if g.name == '' then g.named = nil; rename(g) end
  end
  return g
end

local function load_filters()
  local profile = G.SETTINGS.profile
  if store and store.profile == profile then return store end
  store = {profile = profile, filters = {}, current = 1}
  local t = fs.read_table(profile_path())
  if type(t) == 'table' and type(t.filters) == 'table' then
    for _, f in ipairs(t.filters) do
      local g = sane(f)
      if g then store.filters[#store.filters + 1] = g end
    end
    if type(t.current) == 'number' then store.current = t.current end
  end
  if #store.filters == 0 then store.filters[1] = new_filter() end
  store.current = math.max(1, math.min(store.current, #store.filters))
  return store
end

function M.save_filters()
  local s = load_filters()
  local ok, err = fs.write_table(profile_path(), {version = 1, current = s.current, filters = s.filters})
  if not ok then print('[SeedFinder] could not save filters: '..tostring(err)) end
  return ok, err
end

function M.current()
  local s = load_filters()
  return s.filters[s.current]
end

-- The name editor ------------------------------------------------------------------

-- Drops the text-input hook when it is the name editor's input (or a removed one),
-- so no key press lands on a box that is going away (saveslots/ui.lua's
-- release_editor_hook).
local function release_editor_hook()
  local hook = G.CONTROLLER and G.CONTROLLER.text_input_hook
  if not hook then return end
  local args = hook.config and hook.config.ref_table
  if hook.REMOVED or (editor and type(args) == 'table' and args.ref_table == editor) then
    G.CONTROLLER.text_input_hook = nil
  end
end

-- Closes the name editor without saving (the name was never touched: Cancel keeps
-- it); the panel redraws without the editor.
local function close_editor()
  if not editor then return end
  release_editor_hook()
  editor = nil
  dirty.filter = true
end

-- Opens the editor on the current filter: prefilled with its name when the player
-- typed it, empty (the generated name as the prompt) otherwise. The panel redraws
-- with it on the next tick, which hooks its input.
local function open_editor()
  close_editor()
  local f = M.current()
  editor = {filter = f, text = f.named and f.name or ''}
  dirty.filter = true
end

-- Hooks the editor's input (the only text input in the filter panel), so typing
-- goes straight in. Called after each rebuild of the panel while the editor is open.
local function hook_editor()
  if not editor then return end
  local node = G.OVERLAY_MENU and G.OVERLAY_MENU ~= true and G.OVERLAY_MENU:get_UIE_by_ID('seedfinder_filter')
  local box = node and node.config.object
  local input = box and box.get_UIE_by_ID and box:get_UIE_by_ID('text_input')
  if input then G.FUNCS.select_text_input(input) end
end

function M.set_filter(f)
  local g = sane(f)
  if not g then return nil, 'not a filter' end
  close_editor()
  local s = load_filters()
  s.filters[s.current] = g
  rename(g)
  M.save_filters()
  dirty.filter = true
  return true
end

-- Every change to the filter goes through here: name, file, and which panel to redraw.
local function changed(redraw)
  local f = M.current()
  rename(f)
  M.save_filters()
  dirty.filter = dirty.filter or redraw
end

-- Save, or Return in the name editor: a typed name sticks (named = true); an empty
-- or blank one clears named, and the generated name comes back at once.
local function commit_name()
  local ed = editor
  if not ed then return end
  close_editor()
  if M.current() ~= ed.filter then return end
  local t = clean_name(ed.text)
  if t == '' then ed.filter.named = nil else ed.filter.name, ed.filter.named = t, true end
  changed(true)
end

-- The ticker ------------------------------------------------------------------------

function M.is_open()
  return G.OVERLAY_MENU ~= nil and G.OVERLAY_MENU ~= true
    and G.OVERLAY_MENU:get_UIE_by_ID(ROOT_ID) ~= nil
end

local function find_tab_open()
  return G.OVERLAY_MENU ~= nil and G.OVERLAY_MENU ~= true
    and G.OVERLAY_MENU:get_UIE_by_ID('seedfinder_tab') ~= nil
end

local function status(msg) live.status = msg or '' end

-- A failure for the status line, which shrinks long text to fit: the message alone,
-- without the chunk names in front of it. The full text goes to the lovely log.
local function brief(what, err)
  err = tostring(err)
  print('[SeedFinder] '..what..': '..err)
  local msg = err:match(':%d+: ([^:]+)$') or err
  if #msg > 48 then msg = msg:sub(1, 45)..'...' end
  return what..': '..msg
end

-- Searching needs the pools the game really uses; content mods change them. Under
-- Steamodded, which card appears matches vanilla but bosses and editions don't (golden
-- suites under rig/lovely-rig.sh --smods), so boss clauses and edition requirements
-- are left out.
local function blocked()
  local e = BHCore.env()
  if #e.content > 0 then return 'Searching is off in this game' end
  if e.smods then
    for _, c in ipairs(M.current().clauses or {}) do
      if c.kind == 'boss' or c.edition then return 'Under Steamodded: no boss or edition clauses' end
    end
  end
end

local tick

local function ensure_ticker()
  if ticking then return end
  ticking = true
  G.E_MANAGER:add_event(Event({
    no_delete = true, blocking = false, blockable = false, pause_force = true,
    timer = 'REAL', trigger = 'immediate',
    func = function()
      local ok, keep = pcall(tick)
      if not ok then print('[SeedFinder] ui tick: '..tostring(keep)) end
      if ok and keep then return false end
      ticking = false
      return true
    end,
  }), 'other')
end

local function replace(id, def)
  local node = G.OVERLAY_MENU and G.OVERLAY_MENU ~= true and G.OVERLAY_MENU:get_UIE_by_ID(id)
  if not node then return end
  if node.config.object then node.config.object:remove() end
  node.config.object = UIBox{definition = def(), config = {offset = {x = 0, y = 0}, align = 'cm', parent = node}}
  node.UIBox:recalculate()
end

local filter_panel_def, results_def, odds_def, default_workers

-- Ranks search.found by route cost (route.rank). Each seed's details are
-- evaluated once, on this thread, the first time it is seen.
local function rank_found()
  local s = search
  s.details = s.details or {}
  local hits = {}
  for i, seed in ipairs(s.found) do
    if s.details[seed] == nil then
      local ok, _, d = pcall(filter.eval_seed, s.filter, seed)
      s.details[seed] = ok and d or false
    end
    hits[i] = {seed, s.details[seed] or nil, i = i}
  end
  local out, costs = route.rank(s.filter, hits)
  s.order, s.costs = {}, {}
  for k, h in ipairs(out or hits) do
    s.order[k] = h.i
    s.costs[h.i] = costs and costs[k] or nil
  end
end

-- The compact route cost of found[i]: "A1 R0", or "-" without a route.
local function short_cost(i)
  local c = search and search.costs and search.costs[i]
  return c and ('A%d R%d'):format(c.ante, c.rerolls) or '-'
end

-- found's index shown at position k of the ranked list.
local function ranked(k)
  return search and search.order and search.order[k] or k
end

local function finish_search(p)
  search.running = false
  handle = nil
  -- One line in the lovely log per search, so a report can say where hits went: found by
  -- the worker threads (candidates) and kept or rejected by the main-thread check.
  print(('[SeedFinder] search ended: scanned %d, candidates %s, rejected %s, hits %d%s'):format(
    search.scanned or 0, tostring(p and p.candidates), tostring(p and p.rejected), #search.found,
    BHCore.env().smods and ' (Steamodded)' or ''))
  if p and p.error then
    search.error = tostring(p.error)
    status(brief('Search failed', search.error))
  elseif #search.found >= MAX_HITS then
    status('Stopped at '..MAX_HITS..' hits')
  elseif search.cancelled then
    status('Cancelled')
  else
    status('Done')
  end
end

local function poll()
  if not handle then return end
  local ok, p = pcall(engine.poll, handle)
  if not ok then p = {error = p, found = search.found, scanned = search.scanned, rate = search.rate, done = true} end
  search.scanned, search.rate = p.scanned or search.scanned, p.rate or search.rate
  if p.found and #p.found ~= #search.found then
    search.found = {}
    for i, s in ipairs(p.found) do search.found[i] = s end
    rank_found()
    dirty.results = true
  end
  live.scanned = commas(search.scanned)
  live.rate = commas(search.rate)..'/s'
  search.candidates, search.rejected = p.candidates, p.rejected
  if not p.error and not p.done and (p.rejected or 0) > 0 then
    status('Searching... '..commas(p.rejected)..' of '..commas(p.candidates or 0)..' found hits failed the check')
  end
  live.hits = tostring(#search.found)
  if type(p.hits_per_million) == 'number' and (search.scanned or 0) > 0 then
    local h = p.hits_per_million
    live.hpm = h >= 100 and commas(h) or ('%.1f'):format(h)
  end
  if p.done or p.error then
    if p.error and not ok then pcall(engine.cancel, handle) end
    finish_search(p)
    dirty.results = true
  end
end

-- Odds -------------------------------------------------------------------------------

-- Whether two filters are the same data. (Not by serialize: its text follows pairs
-- order, which differs between a table and its copy.)
local function same(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- Whether two filters search for the same seeds: the same data, their names aside
-- (a rename changes no hit, so it keeps the Odds lines).
local function same_search(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
  for k, v in pairs(a) do
    if k ~= 'name' and k ~= 'named' and not same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if k ~= 'name' and k ~= 'named' and a[k] == nil then return false end
  end
  return true
end

-- The seeds/s the Odds line reads time at: the last search's, when it searched
-- this very filter, else the sample's own rate times (clauses + 1) (a sample
-- evaluates each clause alone and the whole filter once more per seed).
local function odds_rate(job, p)
  if search and (search.rate or 0) > 0 and same_search(search.filter, job.filter) then return search.rate end
  return (p.rate or 0) * (#job.filter.clauses + 1)
end

-- What the Odds lines say for job.
local function odds_lines(job)
  if job.err then return {job.err} end
  if not job.done then return {'Sampling '..commas(job.n)..' seeds...'} end
  local est = job.estimate
  if not est then return {'No odds: the sample was cut short'} end
  if est.expected_seeds == math.huge then
    -- One sentence over the two lines (joined with a space it reads whole), so
    -- neither is shrunk past reading.
    local k = est.never[1] or est.bottleneck
    return {('clause %d never passed in %s seeds:'):format(k, commas(est.n)),
      'it may be impossible or locked ('..describe(job.filter.clauses[k])..')'}
  end
  local l1 = 'about 1 in '..M.round_count(est.expected_seeds)..' seeds'
  if job.rate > 0 then
    local secs = est.expected_seeds / job.rate
    l1 = l1..(secs < 1 and ', under 1 s' or (', ~'..M.round_time(secs)))..' at '..commas(job.rate)..'/s'
  end
  local b = est.bottleneck
  return {l1, 'bottleneck: clause '..b..', '..describe(job.filter.clauses[b])
    ..(est.confidence == 'extrapolated' and ' (extrapolated)' or '')}
end

local function clear_odds()
  if not odds_job then return end
  if odds_job.handle then pcall(engine.cancel, odds_job.handle) end
  odds_job = nil
  dirty.odds = true
end

local function poll_odds()
  local job = odds_job
  if not (job and job.handle) then return end
  local ok, p = pcall(engine.poll, job.handle)
  if not ok then p = {error = p, done = true} end
  job.counts = p.counts or job.counts
  if p.error then
    job.err = brief('Odds failed', p.error)
    pcall(engine.cancel, job.handle)
  end
  if p.done or p.error then
    job.handle, job.done = nil, true
    job.estimate = p.estimate
    job.rate = odds_rate(job, p)
    job.lines = odds_lines(job)
    dirty.odds = true
  end
end

local function start_odds()
  if odds_job and not odds_job.done then return end
  if blocked() then status(blocked()); return end
  local f = copy(M.current())
  local ok, err = filter.validate(f)
  if not ok then status(#f.clauses == 0 and 'Add a clause first' or tostring(err)); return end
  local ok2, h = pcall(engine.sample, f, ODDS_SAMPLE, {workers = workers or default_workers()})
  if not ok2 then status(brief('Could not sample', h)); return end
  odds_job = {filter = f, n = ODDS_SAMPLE, done = false, handle = h, sample = h, rate = 0}
  odds_job.lines = odds_lines(odds_job)
  dirty.odds = true
  ensure_ticker()
end

function M.odds() return odds_job end

-- Save as hunt: waits for run_start of the seed, then the run's first snapshot.
local function poll_hunt()
  if not (hunt and hunt.state == 'waiting' and hunt.started) then return end
  local cp = type(SaveSlots) == 'table' and SaveSlots.checkpoint
  local snap = cp and cp.get()
  if not (snap and snap.GAME and snap.GAME.pseudorandom and snap.GAME.pseudorandom.seed == hunt.seed) then return end
  local f = hunt.filter
  local id, err = SaveSlots.store.save(snap, 'Hunt '..hunt.seed, nil,
    {kind = 'hunt', origin = {kind = 'finder', filter_name = f.name, filter = copy(f)}})
  if id then
    hunt.state, hunt.id = 'saved', id
    status('Saved hunt '..hunt.seed)
  else
    hunt.state, hunt.err = 'failed', tostring(err)
    status('Hunt not saved: '..hunt.err)
    print('[SeedFinder] hunt not saved: '..hunt.err)
  end
end

tick = function()
  poll()
  poll_hunt()
  poll_odds()
  -- The Odds lines belong to the filter sampled: any edit but a rename clears them.
  if odds_job and not same_search(M.current(), odds_job.filter) then clear_odds() end
  -- Leaving the overlay (Back, Play, a Route panel) takes the name editor with it.
  if editor and not M.is_open() then close_editor() end
  if M.is_open() then
    if dirty.filter then
      dirty.filter = false
      replace('seedfinder_filter', filter_panel_def)
      hook_editor()
    end
    if dirty.results then dirty.results = false; replace('seedfinder_results', results_def) end
    if dirty.odds then dirty.odds = false; replace('seedfinder_odds', odds_def) end
  end
  if find_tab_open() and dirty.results then
    dirty.results = false
    local but = G.OVERLAY_MENU:get_UIE_by_ID('tab_but_Find')
    if but then G.FUNCS.change_tab(but) end
  end
  return M.is_open() or find_tab_open() or handle ~= nil or (hunt ~= nil and hunt.state == 'waiting')
    or (odds_job ~= nil and odds_job.handle ~= nil)
end

-- Building blocks ------------------------------------------------------------------

local function text(t, scale, colour, id)
  return {n=G.UIT.T, config={text = tostring(t), scale = scale, colour = colour or G.C.UI.TEXT_LIGHT,
    shadow = true, id = id}}
end

local function live_text(key, scale, colour, id)
  return {n=G.UIT.T, config={ref_table = live, ref_value = key, scale = scale,
    colour = colour or G.C.UI.TEXT_LIGHT, shadow = true, id = id}}
end

local function row(nodes, cfg)
  cfg = cfg or {}
  cfg.align = cfg.align or 'cm'
  return {n=G.UIT.R, config = cfg, nodes = nodes}
end

local function gap(w) return {n=G.UIT.C, config={minw = w or 0.1}} end

-- A vanilla option cycle whose arrows call seedfinder_cycle with ids <id>_l / <id>_r
-- (so a scenario can click one cycle among many), reporting the chosen value to
-- on_change.
local function cycle(id, labels, values, current, on_change, opts)
  opts = opts or {}
  local cur = 1
  for i, v in ipairs(values) do
    if v == current then cur = i end
  end
  local args = {options = labels, current_option = cur, opt_callback = 'seedfinder_cycle_changed',
    w = opts.w or 2.5, h = opts.h or 0.6, scale = opts.scale or 0.7, text_scale = opts.text_scale,
    colour = opts.colour or (#labels < 2 and G.C.UI.BACKGROUND_INACTIVE) or G.C.RED, no_pips = opts.no_pips ~= false, id = 'seedfinder_'..id}
  local t = create_option_cycle(args)
  args.seedfinder = {values = values, on_change = on_change}
  -- The label is a DynaText sized once, when built: a long one (Delayed
  -- Gratification) would widen the row past the room, so it is scaled down to the
  -- cycle's width the way DynaText's own maxw does. It is only fitted when built,
  -- so a cycle whose labels vary a lot asks for a rebuild on change (opts.refit).
  local maxw = args.w - 0.15
  local function retarget(node)
    if type(node) ~= 'table' then return end
    -- The arrows; a single-option cycle's are disabled (no button) but keep the id,
    -- so its options can still be read through them.
    if node.n == G.UIT.C and node.config and node.config.ref_table == args
      and (node.config.ref_value == 'l' or node.config.ref_value == 'r') then
      if node.config.button == 'option_cycle' then node.config.button = 'seedfinder_cycle' end
      node.config.id = 'seedfinder_'..id..'_'..node.config.ref_value
    end
    local obj = node.config and node.config.object
    if node.n == G.UIT.O and obj and obj.is and obj:is(DynaText) and obj.config.W > maxw then
      obj.scale = obj.scale*(maxw/obj.config.W)
      obj:update_text(true)
    end
    for _, child in ipairs(node.nodes or {}) do retarget(child) end
  end
  retarget(t)
  -- create_option_cycle returns a row; a column lets cycles share one.
  return {n=G.UIT.C, config={align = 'cm'}, nodes={t}}
end

local function button(label, fn, opts)
  opts = opts or {}
  return UIBox_button{label = {label}, button = fn, id = opts.id, ref_table = opts.ref_table,
    colour = opts.colour or G.C.RED, minw = opts.w or 2, minh = opts.h or 0.6, scale = opts.scale or 0.4,
    col = true, func = opts.func}
end

local function panel(title, w, nodes)
  local rows = {row({text(title, 0.42)}, {padding = 0.04})}
  for _, n in ipairs(nodes) do rows[#rows + 1] = n end
  return {n=G.UIT.C, config={align = 'tm', padding = 0.1, r = 0.1, minw = w, colour = G.C.BLACK, emboss = 0.05}, nodes={
    {n=G.UIT.C, config={align = 'tm', minw = w - 0.2}, nodes = rows},
  }}
end

local function caption(t, colour)
  return row({text(t, 0.3, colour or G.C.UI.TEXT_INACTIVE)}, {padding = 0.03})
end

-- The filter panel ------------------------------------------------------------------

-- Vanilla's run-setup rule (UI_definitions.lua:5465-5468, can_start_run at
-- button_callbacks.lua:2058): a deck is offered when the profile has unlocked it,
-- and its stakes go up to one above the highest it has won (get_deck_win_stake),
-- all eight on an all-unlocked profile.
local function profile_all_unlocked()
  local p = G.PROFILES and G.PROFILES[G.SETTINGS.profile]
  return p and p.all_unlocked or false
end

local function deck_unlocked(key)
  local b = G.P_CENTERS[key]
  return b ~= nil and b.set == 'Back' and (b.unlocked and true or profile_all_unlocked())
end

local function max_stake(deck)
  local n = #G.P_CENTER_POOLS.Stake
  if profile_all_unlocked() then return n end
  local ok, won = pcall(get_deck_win_stake, deck)
  return math.max(1, math.min(n, (ok and tonumber(won) or 0) + 1))
end

-- Why a filter can't be played on this profile, or nil.
local function locked_reason(f)
  if not deck_unlocked(f.deck) then return name_of('Back', f.deck)..' is locked' end
  if (f.stake or 1) > max_stake(f.deck) then
    return name_of('Stake', (G.P_CENTER_POOLS.Stake[f.stake] or {}).key)..' is locked for '..name_of('Back', f.deck)
  end
end

-- A stored filter (filters.jkr) can name a deck or stake the profile no longer
-- offers. It stays listed, marked "(locked)", so the cycle shows what the filter
-- really searches with; Play and Save as hunt refuse it.
local function deck_options(current)
  local labels, values = {}, {}
  for _, b in ipairs(G.P_CENTER_POOLS.Back) do
    if deck_unlocked(b.key) or b.key == current then
      values[#values + 1] = b.key
      labels[#labels + 1] = name_of('Back', b.key)..(deck_unlocked(b.key) and '' or ' (locked)')
    end
  end
  return labels, values
end

local function stake_options(deck, current)
  local labels, values = {}, {}
  local max = max_stake(deck)
  for i, s in ipairs(G.P_CENTER_POOLS.Stake) do
    if i <= max or i == current then
      values[#values + 1] = i
      labels[#labels + 1] = name_of('Stake', s.key)..(i <= max and '' or ' (locked)')
    end
  end
  return labels, values
end

local function clause_row(i, c)
  local kinds_l, kinds_v = {}, {}
  for k, d in ipairs(KINDS) do kinds_l[k], kinds_v[k] = d.label, d.kind end
  local antes_l, antes_v = {}, {}
  if c.kind == 'legendary' then
    antes_l, antes_v = {'Any ante'}, {false}
  else
    for a = 1, MAX_ANTE do antes_l[a], antes_v[a] = localize('k_ante')..' '..a, a end
  end
  local ex = extra_of(c.kind)
  local pool = key_pool(c.kind)
  local p = 'c'..i..'_'
  -- The cycles' w plus their arrows and the X must stay inside the clause list's
  -- minw (FILTER_W - 0.4, less its padding): a wider row widens the whole overlay.
  return row({
    cycle(p..'kind', kinds_l, kinds_v, c.kind, function(v)
      local nc = default_clause(v, c.ante)
      for k in pairs(c) do c[k] = nil end
      for k, x in pairs(nc) do c[k] = x end
      changed(true)
    end, {w = 2.2}),
    cycle(p..'ante', antes_l, antes_v, c.kind == 'legendary' and false or c.ante, function(v)
      c.ante = v; changed()
    end, {w = 1.3}),
    ex and cycle(p..'extra', ex.labels, ex.values, c[ex.field], function(v)
      c[ex.field] = v; changed()
    end, {w = 1.6}) or cycle(p..'extra', {'-'}, {false}, false, nil, {w = 1.6}),
    cycle(p..'key', pool.labels, pool.values, key_value(c), function(v)
      set_key(c, v); changed(true)
    end, {w = 2.7}),
    button('X', 'seedfinder_remove', {id = 'seedfinder_remove_'..i, ref_table = {i = i}, w = 0.55, h = 0.5, scale = 0.35}),
  }, {padding = 0.02})
end

-- The name editor's row, in the deck/stake/mode row's place and height: a text
-- input (digits kept, BHCore.install_digits), Save and Cancel. Return saves too. The
-- input's w holds NAME_MAX of the game font's widest typeable letter at NAME_SCALE
-- ('&': finder_names types 30 of it), so no name grows the row past the panel.
local NAME_W, NAME_SCALE = 7.2, 0.36
local function editor_row(f)
  local generated = copy(f)
  generated.named = nil
  rename(generated)
  return row({
    text('Name', 0.36),
    gap(0.12),
    create_text_input{w = NAME_W, max_length = NAME_MAX, extended_corpus = true, bh_digits = true,
      text_scale = NAME_SCALE, ref_table = editor, ref_value = 'text', prompt_text = generated.name,
      callback = function() G.FUNCS.seedfinder_name_return() end},
    gap(0.12),
    button('Save', 'seedfinder_name_save', {id = 'seedfinder_name_save', w = 1.2, h = 0.5, colour = G.C.GREEN}),
    gap(0.06),
    button('Cancel', 'seedfinder_name_cancel', {id = 'seedfinder_name_cancel', w = 1.2, h = 0.5}),
  }, {padding = 0.02, minh = ROW2_H})
end

filter_panel_def = function()
  local s = load_filters()
  local f = M.current()
  local names, idx = {}, {}
  for i, g in ipairs(s.filters) do names[i], idx[i] = i..'. '..g.name, i end
  local deck_l, deck_v = deck_options(f.deck)
  local stake_l, stake_v = stake_options(f.deck, f.stake)
  local rows = {
    -- The cycle's w leaves room for the four buttons inside FILTER_W; a long name
    -- is shrunk to the cycle's width (cycle()).
    row({
      cycle('filter', names, idx, s.current, function(v)
        close_editor()
        s.current = v; M.save_filters(); dirty.filter = true
      end, {w = 6, colour = G.C.BOOSTER}),
      button('New', 'seedfinder_new', {w = 1.05, colour = G.C.BLUE, scale = 0.36}),
      gap(0.06),
      button('Delete', 'seedfinder_delete', {w = 1.15, scale = 0.36}),
      gap(0.06),
      button('Rename', 'seedfinder_rename', {id = 'seedfinder_rename', w = 1.2, colour = G.C.ORANGE, scale = 0.36}),
      gap(0.06),
      button('Save as', 'seedfinder_save_as', {id = 'seedfinder_save_as', w = 1.25, colour = G.C.PURPLE, scale = 0.36}),
    }, {padding = 0.04}),
    editor and editor_row(f) or row({
      -- A deck change rebuilds the panel: its stake cycle offers that deck's stakes.
      cycle('deck', deck_l, deck_v, f.deck, function(v)
        f.deck = v
        f.stake = math.min(f.stake or 1, max_stake(v))
        changed(true)
      end, {w = 2.9}),
      cycle('stake', stake_l, stake_v, f.stake, function(v) f.stake = v; changed() end, {w = 2.9}),
      cycle('mode', {'All clauses', 'Any clause'}, {'all', 'any'}, f.mode or 'all',
        function(v) f.mode = v; changed() end, {w = 2.4}),
    }, {padding = 0.02, minh = ROW2_H}),
    row({
      create_toggle{col = true, label = 'All unlocked', ref_table = f, ref_value = 'all_unlocked', w = 2, scale = 0.8,
        label_scale = 0.35, callback = function() changed() end},
      text('(hits assume every card is unlocked)', 0.28, G.C.UI.TEXT_INACTIVE),
    }, {padding = 0.0}),
  }
  local list = {}
  if #f.clauses == 0 then
    list[1] = row({text('No clauses yet: add one', 0.35, G.C.UI.TEXT_INACTIVE)}, {minh = 0.8})
  end
  for i, c in ipairs(f.clauses) do list[#list + 1] = clause_row(i, c) end
  rows[#rows + 1] = row({
    {n=G.UIT.C, config={align = 'tm', r = 0.1, padding = 0.08, colour = G.C.L_BLACK, minw = FILTER_W - 0.4,
      minh = 0.66*MAX_CLAUSES + 0.2}, nodes = list},
  }, {padding = 0.04})
  rows[#rows + 1] = row({
    button('Add clause', 'seedfinder_add', {w = 3, colour = G.C.GREEN, func = 'seedfinder_can_add'}),
  }, {padding = 0.04})
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.CLEAR}, nodes={
    panel('Filter', FILTER_W, rows),
  }}
end

-- The search panel ------------------------------------------------------------------

-- A live figure in a box of fixed width: maxw shrinks a long one (10,000,000)
-- rather than letting it widen the row.
local STAT_W = 1.3
local function stat(label, key, colour, id)
  return {n=G.UIT.C, config={align = 'cm', padding = 0.04}, nodes={
    row({text(label, 0.3)}),
    row({
      {n=G.UIT.C, config={align = 'cm', minw = STAT_W, maxw = STAT_W, minh = 0.55, r = 0.1, colour = G.C.L_BLACK,
        emboss = 0.05}, nodes={
        live_text(key, 0.36, colour, id),
      }},
    }),
  }}
end

local function hit_row(i, seed)
  return row({
    -- Seed 1.6 + cost 0.7 + buttons 0.8/0.9/1.45 + gaps and padding: 5.77, inside
    -- the results' minw (SEARCH_W - 0.4), so hits never widen the overlay.
    {n=G.UIT.C, config={align = 'cm', minw = 1.6, minh = 0.5, r = 0.1, colour = G.C.L_BLACK}, nodes={
      text(seed, 0.38, G.C.FILTER),
    }},
    {n=G.UIT.C, config={align = 'cm', minw = 0.7, maxw = 0.7, minh = 0.5}, nodes={
      text(short_cost(i), 0.28, G.C.GOLD, 'seedfinder_cost_'..i),
    }},
    button('Play', 'seedfinder_play', {id = 'seedfinder_play_'..i, ref_table = {i = i}, w = 0.8, h = 0.5,
      colour = G.C.BLUE, scale = 0.34}),
    gap(0.04),
    button('Route', 'seedfinder_route', {id = 'seedfinder_route_'..i, ref_table = {i = i, from = 'overlay'},
      w = 0.9, h = 0.5, colour = G.C.PURPLE, scale = 0.34}),
    gap(0.04),
    button('Save as hunt', 'seedfinder_hunt', {id = 'seedfinder_hunt_'..i, ref_table = {i = i}, w = 1.45, h = 0.5,
      colour = G.C.ORANGE, scale = 0.3}),
  }, {padding = 0.03})
end

results_def = function()
  local rows = {}
  if not search or #search.found == 0 then
    rows[1] = row({text(search and search.running and 'Searching...' or 'No hits yet', 0.35, G.C.UI.TEXT_INACTIVE)},
      {minh = 0.8})
  else
    local pages = math.ceil(#search.found / PAGE)
    page = math.max(1, math.min(page, pages))
    rows[#rows + 1] = row({text('Hits for '..search.filter.name, 0.3, G.C.UI.TEXT_INACTIVE)},
      {padding = 0.05, maxw = SEARCH_W - 0.6})
    for k = (page - 1)*PAGE + 1, math.min(page*PAGE, #search.found) do
      local i = ranked(k)
      rows[#rows + 1] = hit_row(i, search.found[i])
    end
    if pages > 1 then
      local labels, values = {}, {}
      for k = 1, pages do labels[k], values[k] = 'Page '..k..'/'..pages, k end
      rows[#rows + 1] = row({
        cycle('hits_page', labels, values, page, function(v) page = v; dirty.results = true end,
          {w = 2.4, colour = G.C.BOOSTER}),
      }, {padding = 0.03})
    end
  end
  -- minh holds a full page (caption, PAGE rows, the page cycle), so the panel is
  -- as tall with hits as without.
  return {n=G.UIT.ROOT, config={align = 'tm', colour = G.C.CLEAR, minw = SEARCH_W - 0.4, minh = 0.56*PAGE + 1.15}, nodes={
    {n=G.UIT.C, config={align = 'tm'}, nodes = rows},
  }}
end

-- The Odds lines, a box of fixed size: each line's maxw shrinks a long one.
odds_def = function()
  local w = SEARCH_W - 0.4
  local rows = {}
  local job = odds_job
  if job then
    local colour = job.err and G.C.RED or (job.done and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE)
    for k, l in ipairs(job.lines) do
      rows[k] = row({text(l, k == 1 and 0.32 or 0.28, k == 1 and colour or G.C.UI.TEXT_INACTIVE, 'seedfinder_odds_'..k)},
        {maxw = w, padding = 0.01})
    end
  else
    rows[1] = row({text('Odds: seeds per hit, from a '..commas(ODDS_SAMPLE)..'-seed sample', 0.28, G.C.UI.TEXT_INACTIVE)},
      {maxw = w, padding = 0.01})
  end
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.CLEAR, minw = w, minh = 0.5}, nodes={
    {n=G.UIT.C, config={align = 'cm'}, nodes = rows},
  }}
end

local function worker_options()
  local l, v = {}, {}
  for n = 1, 8 do l[n], v[n] = n..(n == 1 and ' worker' or ' workers'), n end
  return l, v
end

default_workers = function()
  local ok, cores = pcall(function() return love.system.getProcessorCount() end)
  cores = ok and tonumber(cores) or 2
  return math.max(1, math.min(4, cores - 1))
end

local function search_panel()
  workers = workers or default_workers()
  local wl, wv = worker_options()
  local nodes = {
    row({
      cycle('workers', wl, wv, workers, function(v) workers = v end, {w = 1.7}),
      button('Start', 'seedfinder_start', {w = 1.05, colour = G.C.GREEN, func = 'seedfinder_can_start'}),
      gap(0.05),
      button('Cancel', 'seedfinder_cancel', {w = 1.05, func = 'seedfinder_can_cancel'}),
      gap(0.05),
      button('Odds', 'seedfinder_odds', {w = 0.95, colour = G.C.PURPLE, func = 'seedfinder_can_odds'}),
    }, {padding = 0.04}),
    row({
      stat('Scanned', 'scanned', G.C.UI.TEXT_LIGHT, 'seedfinder_scanned'),
      stat('Rate', 'rate', G.C.UI.TEXT_LIGHT, 'seedfinder_rate'),
      stat('Hits', 'hits', G.C.GREEN, 'seedfinder_hits'),
      stat('Per M', 'hpm', G.C.GREEN, 'seedfinder_hpm'),
    }),
    row({live_text('status', 0.3, G.C.UI.TEXT_LIGHT, 'seedfinder_status')},
      {padding = 0.04, minh = 0.35, maxw = SEARCH_W - 0.4}),
    row({{n=G.UIT.O, config={id = 'seedfinder_odds', object = UIBox{definition = odds_def(),
      config = {offset = {x = 0, y = 0}, align = 'cm'}}}}}),
    row({{n=G.UIT.O, config={id = 'seedfinder_results', object = UIBox{definition = results_def(),
      config = {offset = {x = 0, y = 0}, align = 'cm'}}}}}),
  }
  -- Under Steamodded or content mods, say what the results can't be trusted for.
  local notice = BHCore.env_notice()
  if notice then
    table.insert(nodes, 4, row({text(notice, 0.26, G.C.ORANGE, 'seedfinder_env')},
      {padding = 0.02, maxw = SEARCH_W - 0.4}))
  end
  return panel('Search', SEARCH_W, nodes)
end

local function overlay_def()
  return create_UIBox_generic_options{
    back_func = from == 'play' and 'setup_run' or (from == 'pause' or from == 'options') and 'options' or 'exit_overlay_menu',
    padding = 0.05,
    contents = {
      row({text('Seed Finder', 0.6)}, {id = ROOT_ID, padding = 0.04}),
      row({
        {n=G.UIT.C, config={align = 'tm'}, nodes={
          {n=G.UIT.O, config={id = 'seedfinder_filter', object = UIBox{definition = filter_panel_def(),
            config = {offset = {x = 0, y = 0}, align = 'cm'}}}},
        }},
        gap(0.15),
        {n=G.UIT.C, config={align = 'tm'}, nodes={search_panel()}},
      }, {align = 'tm', padding = 0.04}),
    },
  }
end

function M.open(where)
  from = where or (G.STAGE == G.STAGES.RUN and 'pause' or 'options')
  load_filters()
  close_editor()
  dirty = {}
  G.SETTINGS.paused = true
  G.FUNCS.overlay_menu{definition = overlay_def()}
  ensure_ticker()
  return true
end

function M.search() return search end
function M.hunt() return hunt end

-- Actions ----------------------------------------------------------------------------

local function start_search()
  if handle then return end
  close_editor()
  if blocked() then status(blocked()); return end
  local f = copy(M.current())
  local ok, err = filter.validate(f)
  if not ok then status(#f.clauses == 0 and 'Add a clause first' or tostring(err)); return end
  local ok2, h = pcall(engine.start, f, {workers = workers or default_workers(), stop_after = MAX_HITS})
  if not ok2 then status(brief('Could not start', h)); return end
  handle = h
  search = {filter = f, found = {}, scanned = 0, rate = 0, running = true, handle = h}
  page = 1
  live.scanned, live.rate, live.hits, live.hpm = '0', '-', '0', '0.0'
  status('Searching...')
  dirty.results = true
  ensure_ticker()
end

local function cancel_search()
  if not handle then return end
  if search then search.cancelled = true end
  pcall(engine.cancel, handle)
  poll()
  if handle then
    handle = nil
    finish_search(nil)
  end
  dirty.results = true
end

-- Shows seeds as a finished search's hits (ui.set_results).
function M.set_results(f, seeds)
  local ok, err = filter.validate(f)
  if not ok then return nil, err end
  if type(seeds) ~= 'table' then return nil, 'seeds is not a list' end
  cancel_search()
  search = {filter = copy(f), found = {}, scanned = 0, rate = 0, done = true, running = false}
  for i, s in ipairs(seeds) do search.found[i] = tostring(s) end
  rank_found()
  page = 1
  live.scanned, live.rate, live.hits, live.hpm = '0', '-', tostring(#search.found), '-'
  status('')
  dirty.results = true
  return true
end

local function play(i, as_hunt)
  local seed = search and search.found[i]
  if not seed then return end
  local f = search.filter
  shown = nil
  local locked = locked_reason(f)
  if locked then
    status('Cannot play: '..locked)
    play_sound('cancel')
    return
  end
  status('')
  cancel_search()
  close_editor()
  if type(RunJournal) == 'table' and RunJournal.recorder and RunJournal.recorder.set_origin then
    pcall(RunJournal.recorder.set_origin, {filter_name = f.name})
  end
  if as_hunt then
    if not (type(SaveSlots) == 'table' and SaveSlots.store and SaveSlots.checkpoint) then
      status('Save as hunt needs Save Slots'); return
    end
    hunt = {seed = seed, filter = f, state = 'waiting'}
    status('Waiting for the first autosave of '..seed)
    ensure_ticker()
  end
  local back = G.P_CENTERS[f.deck]
  if G.GAME and back then G.GAME.viewed_back = Back(back) end
  if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() end
  unseed = seed
  G.FUNCS.start_run(nil, {seed = seed, stake = f.stake or 1})
end

-- The Route panel ---------------------------------------------------------------------

local STEP_SCALE = 0.34

-- A text's width in UI units at `scale`, as UIElement sizes a G.UIT.T (engine/ui.lua).
local function text_w(t, scale)
  local font = G.LANG.font
  return font.FONT:getWidth(t)*font.squish*scale*font.FONTSCALE/G.TILESIZE
end

-- t split at spaces into lines no wider than w (a single longer word is its own
-- line; the row's maxw shrinks it).
local function wrap(t, scale, w)
  local lines, cur = {}, nil
  for word in tostring(t):gmatch('%S+') do
    local try = cur and (cur..' '..word) or word
    if cur and text_w(try, scale) > w then
      lines[#lines + 1] = cur
      cur = word
    else
      cur = try
    end
  end
  if cur then lines[#lines + 1] = cur end
  return lines
end

local function cost_text(c)
  return ('Cost: through ante %d, %d %s, %s'):format(c.ante, c.rerolls, c.rerolls == 1 and 'reroll' or 'rerolls',
    c.dollars and ('$'..c.dollars) or '$ unknown (a pack price is not known)')
end

local function route_def()
  local r = shown
  local f = r.filter
  local line_w = ROUTE_W - 1.2
  local list = {}
  if not r.route then
    list[1] = row({text('No route: '..tostring(r.err), 0.35, G.C.RED)}, {minh = 0.8, maxw = line_w})
  else
    -- Steps grouped by ante: a heading, then each step's wrapped lines behind a dash.
    local ante = nil
    for k, st in ipairs(r.route.steps) do
      if st.ante ~= ante then
        ante = st.ante
        list[#list + 1] = row({text(localize('k_ante')..' '..ante, 0.38, G.C.FILTER)},
          {align = 'cl', padding = 0.04})
      end
      local lines = {}
      for j, l in ipairs(wrap(st.text, STEP_SCALE, line_w)) do
        lines[j] = row({text(l, STEP_SCALE, G.C.UI.TEXT_LIGHT, 'seedfinder_step_'..k..'_'..j)},
          {align = 'cl', maxw = line_w})
      end
      list[#list + 1] = row({
        {n=G.UIT.C, config={align = 'tm', minw = 0.3}, nodes={text('-', STEP_SCALE, G.C.UI.TEXT_INACTIVE)}},
        {n=G.UIT.C, config={align = 'cl'}, nodes = lines},
      }, {align = 'cl', padding = 0.02})
    end
  end
  local body = {
    row({text('Route for '..r.seed, 0.55, G.C.UI.TEXT_LIGHT, 'seedfinder_route_title')}, {padding = 0.04}),
    row({text(f.name..', '..name_of('Back', f.deck)..', '
      ..name_of('Stake', (G.P_CENTER_POOLS.Stake[f.stake or 1] or {}).key), 0.3, G.C.UI.TEXT_INACTIVE)},
      {padding = 0.02, maxw = line_w}),
    row({
      {n=G.UIT.C, config={align = 'tl', r = 0.1, padding = 0.12, colour = G.C.L_BLACK, minw = ROUTE_W - 0.4,
        minh = 1}, nodes = list},
    }, {padding = 0.04}),
  }
  if r.route then
    body[#body + 1] = row({text(cost_text(r.route.cost), 0.36, G.C.GOLD, 'seedfinder_route_cost')},
      {padding = 0.04, maxw = line_w})
  end
  body[#body + 1] = row({
    button('Play', 'seedfinder_play', {id = 'seedfinder_route_play', ref_table = {i = r.i}, w = 2.4, h = 0.6,
      colour = G.C.BLUE}),
  }, {padding = 0.06})
  return create_UIBox_generic_options{
    back_func = 'seedfinder_route_back',
    padding = 0.05,
    contents = {
      {n=G.UIT.R, config={align = 'cm', padding = 0.1, r = 0.1, minw = ROUTE_W, colour = G.C.BLACK, emboss = 0.05},
        nodes={{n=G.UIT.C, config={align = 'tm'}, nodes = body}}},
    },
  }
end

local function route_open()
  return G.OVERLAY_MENU ~= nil and G.OVERLAY_MENU ~= true
    and G.OVERLAY_MENU:get_UIE_by_ID('seedfinder_route_title') ~= nil
end

function M.route()
  if shown and route_open() then return shown end
end

-- One seed, evaluated on this thread when the panel opens.
local function open_route(i, where)
  local seed = search and search.found[i]
  if not seed then return end
  local f = search.filter
  local r, err
  local ok, hit_or_err, details = true, nil, search.details and search.details[seed]
  if not details then ok, hit_or_err, details = pcall(filter.eval_seed, f, seed) end
  if ok then
    r, err = route.build(f, details)
  else
    err = tostring(hit_or_err)
  end
  shown = {i = i, seed = seed, filter = f, route = r, err = err, from = where == 'tab' and 'tab' or 'overlay'}
  G.SETTINGS.paused = true
  G.FUNCS.overlay_menu{definition = route_def()}
end

local function close_route()
  local r = shown
  shown = nil
  if r and r.from == 'tab' then
    G.FUNCS.setup_run({config = {}})
    local but = G.OVERLAY_MENU and G.OVERLAY_MENU ~= true and G.OVERLAY_MENU:get_UIE_by_ID('tab_but_Find')
    if but then G.FUNCS.change_tab(but) end
  else
    M.open(from)
  end
end

-- The Find tab ------------------------------------------------------------------------

local function find_tab_def()
  local f = M.current()
  local body = {
    row({text('Seed Finder', 0.5)}, {id = 'seedfinder_tab', padding = 0.05}),
    row({
      {n=G.UIT.C, config={align = 'cm', minw = TAB_W - 0.6, minh = 0.9, r = 0.1, colour = G.C.BLACK, padding = 0.08}, nodes={
        row({text(f.name, 0.4, G.C.UI.TEXT_LIGHT)}, {maxw = TAB_W - 0.8}),
        row({text(#f.clauses..(#f.clauses == 1 and ' clause, ' or ' clauses, ')..name_of('Back', f.deck)..', '
          ..name_of('Stake', (G.P_CENTER_POOLS.Stake[f.stake or 1] or {}).key), 0.3, G.C.UI.TEXT_INACTIVE)},
          {maxw = TAB_W - 0.8}),
      }},
    }, {padding = 0.05}),
  }
  if search and #search.found > 0 then
    body[#body + 1] = caption('Hits for '..search.filter.name, G.C.UI.TEXT_LIGHT)
    for k = 1, math.min(3, #search.found) do
      local i = ranked(k)
      body[#body + 1] = row({
        {n=G.UIT.C, config={align = 'cm', minw = 2.2, minh = 0.55, r = 0.1, colour = G.C.BLACK}, nodes={
          text(search.found[i], 0.4, G.C.FILTER),
        }},
        gap(0.06),
        {n=G.UIT.C, config={align = 'cm', minw = 0.8, maxw = 0.8, minh = 0.55}, nodes={
          text(short_cost(i), 0.32, G.C.GOLD, 'seedfinder_tabcost_'..i),
        }},
        gap(0.06),
        button('Play', 'seedfinder_play', {id = 'seedfinder_tabplay_'..i, ref_table = {i = i}, w = 1.3, h = 0.55,
          colour = G.C.BLUE}),
        gap(0.1),
        button('Route', 'seedfinder_route', {id = 'seedfinder_tabroute_'..i, ref_table = {i = i, from = 'tab'},
          w = 1.3, h = 0.55, colour = G.C.PURPLE}),
      }, {padding = 0.04})
    end
  elseif search and search.running then
    body[#body + 1] = row({live_text('status', 0.35)}, {minh = 1})
  else
    body[#body + 1] = row({text('Build a filter, then search seeds for it', 0.33, G.C.UI.TEXT_INACTIVE)}, {minh = 1})
  end
  body[#body + 1] = row({
    UIBox_button{label = {'Open Seed Finder'}, button = 'seedfinder_open', ref_table = {from = 'play'},
      colour = G.C.RED, minw = TAB_W - 2, minh = 0.8},
  }, {padding = 0.2})
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.CLEAR, minw = TAB_W, minh = TAB_H}, nodes={
    {n=G.UIT.C, config={align = 'cm', padding = 0.1}, nodes = body},
  }}
end

local function is_find_tab(tab) return type(tab) == 'table' and tab.seedfinder == true end

local function add_find_tab(tabs)
  local at = nil
  for i, tab in ipairs(tabs) do
    if is_find_tab(tab) then return end
    if type(tab) == 'table' and (tab.saveslots == true or tab.tab_definition_function_args == 'Continue') then at = i end
  end
  if not at then return end
  table.insert(tabs, at + 1, {
    label = 'Find',
    tab_definition_function = function(...)
      ensure_ticker()
      return find_tab_def(...)
    end,
    seedfinder = true,
  })
end

-- The Options button ------------------------------------------------------------------

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

local function has_button(node, name)
  if type(node) ~= 'table' then return false end
  if type(node.config) == 'table' and node.config.button == name then return true end
  for _, child in pairs(node.nodes or {}) do
    if has_button(child, name) then return true end
  end
  return false
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

-- [Customize Deck][Seed Finder], each half as wide, the pair as wide as the others;
-- with no Customize Deck row, a row at the end. The list is rebuilt dense (vanilla
-- leaves nil holes for options that don't apply).
local function add_button(t)
  local list = options_list(t)
  if not list or has_button(list, 'seedfinder_open') then return t end
  local nodes, placed = {}, false
  for i = 1, table.maxn(list.nodes) do
    local child = list.nodes[i]
    if child ~= nil then
      nodes[#nodes + 1] = child
      if not placed and type(child.nodes) == 'table' then
        for _, inner in pairs(child.nodes) do
          if type(inner) == 'table' and type(inner.config) == 'table' and inner.config.button == 'customize_deck' then
            narrow(inner, HALF_W)
            child.nodes = {
              {n=G.UIT.C, config={align = 'cm'}, nodes={inner}},
              {n=G.UIT.C, config={minw = 0.1}},
              UIBox_button{label = {'Seed Finder'}, button = 'seedfinder_open', minw = HALF_W, col = true},
            }
            placed = true
            break
          end
        end
      end
    end
  end
  if not placed then
    nodes[#nodes + 1] = UIBox_button{label = {'Seed Finder'}, button = 'seedfinder_open', minw = 5}
  end
  list.nodes = nodes
  return t
end

-- Install -----------------------------------------------------------------------------

function M.install()
  if installed then return end
  installed = true
  BHCore.install_digits()   -- the name editor keeps a typed '0'

  local orig_options = create_UIBox_options
  create_UIBox_options = function(...)
    return add_button(orig_options(...))
  end

  local orig_run_setup = G.UIDEF.run_setup
  G.UIDEF.run_setup = function(...)
    if G.STAGE ~= G.STAGES.MAIN_MENU then return orig_run_setup(...) end
    local orig_tabs = create_tabs
    local first = true
    -- Only the outermost call is run_setup's own (see saveslots.entry).
    create_tabs = function(args)
      if first then
        first = false
        if type(args) == 'table' and type(args.tabs) == 'table' then add_find_tab(args.tabs) end
      end
      return orig_tabs(args)
    end
    local ok, t = pcall(orig_run_setup, ...)
    create_tabs = orig_tabs
    if not ok then error(t, 0) end
    return t
  end

  local orig_start_run = Game.start_run
  Game.start_run = function(self, args, ...)
    local want = unseed
    unseed = nil
    local ret = orig_start_run(self, args, ...)
    if want and type(args) == 'table' and args.seed == want and not args.savetext and self.GAME then
      self.GAME.seeded = nil
    end
    return ret
  end

  local ok, events = pcall(require, 'bhcore.events')
  if ok then
    events.on('run_start', function(p)
      if not (hunt and hunt.state == 'waiting') then return end
      if not p.loaded and p.seed == hunt.seed and not hunt.started then
        hunt.started = true
      else
        -- Another run (or a loaded one) took its place: its snapshot isn't the hunt's.
        hunt.state, hunt.err = 'failed', 'another run started first'
        status('Hunt not saved: another run started first')
      end
    end)
  end

  G.FUNCS.seedfinder_open = function(e)
    local r = e and e.config and e.config.ref_table
    M.open(type(r) == 'table' and r.from or nil)
  end

  G.FUNCS.seedfinder_cycle = function(e) return G.FUNCS.option_cycle(e) end
  G.FUNCS.seedfinder_cycle_changed = function(args)
    local sf = args and args.cycle_config and args.cycle_config.seedfinder
    if sf and sf.on_change then sf.on_change(sf.values[args.to_key]) end
  end

  G.FUNCS.seedfinder_add = function(e)
    local f = M.current()
    if #f.clauses >= MAX_CLAUSES then return end
    f.clauses[#f.clauses + 1] = default_clause('tag')
    changed(true)
  end
  G.FUNCS.seedfinder_can_add = function(e)
    if #M.current().clauses >= MAX_CLAUSES then
      e.config.colour = G.C.UI.BACKGROUND_INACTIVE
      e.config.button = nil
    else
      e.config.colour = G.C.GREEN
      e.config.button = 'seedfinder_add'
    end
  end
  G.FUNCS.seedfinder_remove = function(e)
    local i = e and e.config and e.config.ref_table and e.config.ref_table.i
    local f = M.current()
    if type(i) ~= 'number' or not f.clauses[i] then return end
    table.remove(f.clauses, i)
    changed(true)
  end
  G.FUNCS.seedfinder_new = function(e)
    close_editor()
    local s = load_filters()
    s.filters[#s.filters + 1] = new_filter()
    s.current = #s.filters
    changed(true)
  end
  G.FUNCS.seedfinder_delete = function(e)
    close_editor()
    local s = load_filters()
    table.remove(s.filters, s.current)
    if #s.filters == 0 then s.filters[1] = new_filter() end
    s.current = math.max(1, math.min(s.current, #s.filters))
    changed(true)
  end

  -- The name editor: Rename opens it on the current filter; Save as puts a deep copy
  -- (no table shared with the original, named copied) right after the current filter,
  -- makes it current and opens the editor on it. Cancelling keeps the copy.
  G.FUNCS.seedfinder_rename = function(e) open_editor() end
  G.FUNCS.seedfinder_save_as = function(e)
    close_editor()
    local s = load_filters()
    local g = copy(s.filters[s.current])
    table.insert(s.filters, s.current + 1, g)
    s.current = s.current + 1
    changed(true)
    open_editor()
  end
  G.FUNCS.seedfinder_name_save = function(e) commit_name() end
  G.FUNCS.seedfinder_name_cancel = function(e) close_editor() end
  -- Return in the input (create_text_input's callback). Vanilla still touches the
  -- hooked input after this returns; the panel is rebuilt on the next tick.
  G.FUNCS.seedfinder_name_return = function() commit_name() end

  G.FUNCS.seedfinder_start = function(e) start_search() end
  G.FUNCS.seedfinder_cancel = function(e) cancel_search() end
  G.FUNCS.seedfinder_can_start = function(e)
    if handle or #M.current().clauses == 0 then
      e.config.colour = G.C.UI.BACKGROUND_INACTIVE
      e.config.button = nil
    else
      e.config.colour = G.C.GREEN
      e.config.button = 'seedfinder_start'
    end
  end
  G.FUNCS.seedfinder_can_cancel = function(e)
    if handle then
      e.config.colour = G.C.RED
      e.config.button = 'seedfinder_cancel'
    else
      e.config.colour = G.C.UI.BACKGROUND_INACTIVE
      e.config.button = nil
    end
  end

  G.FUNCS.seedfinder_odds = function(e) start_odds() end
  G.FUNCS.seedfinder_can_odds = function(e)
    if (odds_job and not odds_job.done) or #M.current().clauses == 0 then
      e.config.colour = G.C.UI.BACKGROUND_INACTIVE
      e.config.button = nil
    else
      e.config.colour = G.C.PURPLE
      e.config.button = 'seedfinder_odds'
    end
  end

  G.FUNCS.seedfinder_play = function(e)
    local i = e and e.config and e.config.ref_table and e.config.ref_table.i
    if type(i) == 'number' then play(i, false) end
  end
  G.FUNCS.seedfinder_route = function(e)
    local r = e and e.config and e.config.ref_table
    if type(r) == 'table' and type(r.i) == 'number' then open_route(r.i, r.from) end
  end
  G.FUNCS.seedfinder_route_back = function(e) close_route() end
  G.FUNCS.seedfinder_hunt = function(e)
    local i = e and e.config and e.config.ref_table and e.config.ref_table.i
    if type(i) == 'number' then play(i, true) end
  end
end

return M
