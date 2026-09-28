-- Finder must-not (T-376): the editor for T-375's model, built in the Filter panel
-- with its real buttons only (cycle arrows by their ids, Add clause, the X, the
-- connectors seedfinder_c1_not / seedfinder_c<i>_join, Save as, Cancel, Delete,
-- the match and stake cycles, Start, Cancel). The model is filter.lua's exclude
-- (a must-not: a top-level plain clause of a mode-'all' filter), by on a Boss
-- clause and sticker = 'none' on a joker clause; the rows are a view of f.clauses
-- (ui.lua header, Groups and Must-not).
--   0. The isolated profile records Red Deck wins up to stake 3 (as finder_ui does
--      for Blue), so its stakes go up to Black (4), where stickers start.
--   1. Options -> Seed Finder. Add clause: kind Boss, Ante 3, By ante, key The
--      Plant; row 1's connector (blank) clicked to "not". The model is exactly
--      {kind = 'boss', by = true, ante = 3, key = 'bl_plant', exclude = true}, it
--      validates, filters.jkr holds it and the name is "no The Plant by A3".
--      -> "check: no plant built by clicks"
--   2. The stake cycle to Black Stake: the reroll cycle of a new Joker by ante row
--      offers each count twice ("R0", "R0 clean", ...). Row 2:
--      Joker by ante, By ante 3, Blueprint, "R0 clean": the model has
--      sticker = 'none' and validates. (shot mustnot_built) Save as, Cancel, the
--      copy's row 1 X: the copy alone is named "Blueprint by A3 (clean)"; Delete
--      brings the first filter back. The stake cycle to Green Stake (3): sticker is
--      gone from the model and filters.jkr, and the reroll cycle offers only the
--      plain counts. -> "check: clean joker built by clicks"
--   3. Two tag rows added (rows 3, 4). Row 2's connector, straight under the "not"
--      row, clicked to "or": it can't join the must-not, so it joins row 3 below it
--      ({not Plant, (Blueprint or tag), tag}). Clicked again: that "or" changes
--      nothing now, so it goes on to "not" ({not Plant, not Blueprint, tag, tag}).
--      Then the third row's connector to "or" under the "not" row 2: the must-nots
--      stay top-level and excluded, and the "or" joins row 4 below it ({not Plant,
--      not Blueprint, (tag or tag)}); no group holds an excluded clause, and the
--      rows show not / not / and / or. -> "check: not row not in a group"
--   4. The match cycle to Any clause: no clause keeps exclude, no group is left,
--      the connectors (row 1's too) are gone and the status line says "must-not
--      clauses dropped in Any mode". -> "check: mode any drops must-not"
--   5. Back to All clauses; the Blueprint row and the last tag row removed; row 1
--      (the Plant) set to "not" again: "no The Plant by ante 3" + Uncommon Tag.
--      The Plant's boss.min is 4, so no seed has it by ante 3 and that must-not
--      excludes nothing: the search runs a must-not real seeds break. Row 1 by
--      its buttons: the connector back to blank, Ante 2, By ante, The Hook
--      (boss.min 1), the connector to "not": "no The Hook by ante 2" + Uncommon
--      Tag at ante 1 (any blind), Red Deck, Green Stake. 4 workers, Start; at 20
--      or more hits, Cancel (the search runs on the workers). Each hit re-checked:
--      filter.eval_seed holds with the must-not's result ok, the positive form
--      alone ("The Hook by ante 2") fails, and predict's bosses of antes 1..2 hold
--      no The Hook. The engine's re-check rejected none of the workers'
--      candidates (workers that lost exclude would send seeds it rejects). And
--      the must-not excludes seeds: of a fixed list (the scan sequence's seeds
--      1..200, engine.seed_at; the only seeds evaluated here beyond the hits),
--      the filter holds exactly when the tag clause alone holds and predict puts
--      no The Hook in antes 1..2, and at least one seed has the tag and The Hook,
--      and is rejected by the must-not. -> "check: search respects must-not"
--      (shot mustnot_hits)
--   6. The overlay's x and y extent and the Filter panel's width are equal (0.01)
--      in every state measured: 0 rows, the "not" row, the clean row, 4 rows with
--      two must-nots and a group, mode any, with hits, the widest labels (back at
--      Black Stake: a Shop joker and a Joker by ante with the widest joker names
--      and the widest clean reroll label, a Boss By ante with the widest boss
--      name joined by "not"), 5 and MAX_CLAUSES rows. Every clause row (connector
--      included) lies inside the clause list, which keeps its minw, and its minh
--      with 1..MAX_CLAUSES - 1 rows; no connector is taller than its row
--      (finder_groups' measure, less the Filter panel's own height: a generated
--      name cut at 30 shrinks the filter cycle's label, and the panel by 0.02).
--      -> "check: width unchanged" (shot mustnot_widest)
-- Screenshots: mustnot_built (required), mustnot_blank (row 1's blank connector),
-- mustnot_rows, mustnot_any, mustnot_hits, mustnot_widest.
local ui = require('seedfinder.ui')
local filter = require('seedfinder.filter')
local engine = require('seedfinder.engine')
local predict = require('bhcore.sim.predict')
local fs = require('bhcore.fs')

local MAX_ROWS = 6   -- ui.lua's MAX_CLAUSES
local LIST_W = 11.2  -- the clause list's minw: ui.lua's FILTER_W - 0.4
local LIST_H = 4.16  -- and its minh: 0.66 * MAX_CLAUSES + 0.2
local DROPPED = 'must-not clauses dropped in Any mode'

local S = {widths = {}}

local PLANT = {kind = 'boss', by = true, ante = 3, key = 'bl_plant'}
local NO_PLANT = {kind = 'boss', by = true, ante = 3, key = 'bl_plant', exclude = true}
local BLUEPRINT = {kind = 'joker', ante = 3, key = 'j_blueprint', rerolls = 0, from = 'both'}
local NO_BLUEPRINT = {kind = 'joker', ante = 3, key = 'j_blueprint', rerolls = 0, from = 'both', exclude = true}
local CLEAN = {kind = 'joker', ante = 3, key = 'j_blueprint', rerolls = 0, from = 'both', sticker = 'none'}
local TAG = {kind = 'tag', ante = 1, blind = 'any', key = 'tag_uncommon'}  -- a new row's clause
-- The search's must-not: The Hook's boss.min is 1, so real seeds have it by ante 2.
local HOOK = {kind = 'boss', by = true, ante = 2, key = 'bl_hook'}
local NO_HOOK = {kind = 'boss', by = true, ante = 2, key = 'bl_hook', exclude = true}
local HITS = 20      -- the search is cancelled at this many hits (it stops by itself at 64)
local LIST_N = 200   -- the fixed seeds evaluated here: engine.seed_at(1..LIST_N)

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU ~= true and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function filter_box()
  local node = uie('seedfinder_filter')
  return node and node.config.object
end

local function name_of(set, key) return localize{type = 'name_text', set = set, key = key} end
local function ante_label(a) return localize('k_ante')..' '..a end
local function stake_name(i) return name_of('Stake', G.P_CENTER_POOLS.Stake[i].key) end

-- The value a cycle shows and the labels it offers, from its right arrow's args.
local function cycle_value(id)
  local arrow = uie('seedfinder_'..id..'_r')
  return arrow and arrow.config.ref_table.current_option_val
end
local function cycle_options(id)
  local arrow = uie('seedfinder_'..id..'_r')
  return arrow and arrow.config.ref_table.options
end

-- The text of the first G.UIT.T under an element (a button's label).
local function label_of(id)
  local function find(n)
    if n.config and n.config.text then return n.config.text end
    for _, ch in ipairs(n.children or {}) do
      local t = find(ch)
      if t then return t end
    end
  end
  local node = uie(id)
  return node and find(node)
end

-- Every connector's label, row 1 first ('' for its blank), as "not/and/or".
local function connectors()
  local out = {}
  for i = 1, MAX_ROWS do
    local l = label_of(i == 1 and 'seedfinder_c1_not' or ('seedfinder_c'..i..'_join'))
    if l == nil then break end
    out[i] = l == '' and '_' or l
  end
  return table.concat(out, '/')
end

local function status_text()
  local node = uie('seedfinder_status')
  return node and tostring(node.config.ref_table[node.config.ref_value]) or ''
end

local function same(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function deep(v)
  if type(v) ~= 'table' then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deep(x) end
  return out
end

local function group(...) return {kind = 'group', clauses = {...}} end

local function disk()
  local t = fs.read_table(G.SETTINGS.profile..'/seedfinder/filters.jkr')
  return t and t.filters and t.filters[t.current]
end

local function rows() return #filter.plain_clauses(ui.current()) end

-- A generated name as ui.lua cuts it (NAME_MAX 30).
local function cut(s)
  if #s > 30 then s = s:sub(1, 27)..'...' end
  return s
end

-- The model, the file and validate agree on `want`; the rows show `joins`.
local function model_is(ctx, label, want, joins)
  local f = ui.current()
  ctx.assert(same(f.clauses, want), label..': the model is '..STR_PACK(f.clauses))
  local d = disk()
  ctx.assert(d and same(d.clauses, want), label..': filters.jkr holds '..(d and STR_PACK(d.clauses) or 'nothing'))
  local ok, err = filter.validate(deep(f))
  ctx.assert(ok, label..': filter.validate: '..tostring(err))
  if joins then ctx.assert(connectors() == joins, ('%s: the connectors are %s, want %s'):format(label, connectors(), joins)) end
end

-- The widest of a list of names in the game font.
local function widest(names)
  local font, best, bw = G.LANG.font.FONT, nil, -1
  for _, n in ipairs(names) do
    if font:getWidth(n) > bw then best, bw = n, font:getWidth(n) end
  end
  return best
end
local function widest_joker(legendary)
  local names = {}
  for _, j in ipairs(G.P_CENTER_POOLS.Joker) do
    if legendary or j.rarity ~= 4 then names[#names + 1] = name_of('Joker', j.key) end
  end
  return widest(names)
end
local function widest_boss()
  local names = {}
  for k, b in pairs(G.P_BLINDS) do if b.boss then names[#names + 1] = name_of('Blind', k) end end
  return widest(names)
end
local function widest_clean(id)
  local names = {}
  for _, l in ipairs(cycle_options(id) or {}) do if l:find(' clean', 1, true) then names[#names + 1] = l end end
  return widest(names)
end

local function click(label, button, id, wait)
  return {name = label, timeout = 10, run = function(ctx)
    if wait and not wait() then return false end
    if G.CONTROLLER.locks.frame or ctx.step_time() < 0.2 then return false end
    return ctx.click(button, id)
  end}
end

-- Clicks a cycle's arrow, the shorter way round, until it shows `want` (a string,
-- or a function giving it once the game is up). One click per frame.
local function cycle_to(id, want, timeout)
  return {name = 'cycle '..id, timeout = timeout or 30, run = function(ctx)
    local w = type(want) == 'function' and want() or want
    local v, opts = cycle_value(id), cycle_options(id)
    if v == w then ctx.log('cycle '..id..' = '..w); return true end
    if v == nil or G.CONTROLLER.locks.frame then return false end
    local at, to
    for k, l in ipairs(opts) do
      if l == v then at = k end
      if l == w then to = k end
    end
    ctx.assert(at and to, id..' offers no "'..tostring(w)..'": '..table.concat(opts, ', '))
    local right = (to - at) % #opts
    ctx.click('seedfinder_cycle', 'seedfinder_'..id..(right <= #opts - right and '_r' or '_l'))
    return false
  end}
end

-- Clicks row i's connector once, after the panel has settled.
local function join(i)
  return click('connector '..i, 'seedfinder_join', i == 1 and 'seedfinder_c1_not' or ('seedfinder_c'..i..'_join'))
end

-- The overlay's x extent, the Filter panel's size and every clause row against the
-- clause list: logged, held equal to the first state (the height to the first
-- with clauses), and the overlay fits the room. (finder_groups' measure.)
local function measure(ctx, label)
  local root = G.OVERLAY_MENU.UIRoot.children[1]
  local back = uie('overlay_menu_back_button')
  local x1, x2, y1, y2 = root.T.x, root.T.x + root.T.w, root.T.y, back.T.y + back.T.h
  local box = filter_box()
  local fw, fh = box.T.w, box.T.h
  local list = box:get_UIE_by_ID('seedfinder_clauses')
  ctx.assert(list, label..': no clause list')
  ctx.assert(list.T.w <= LIST_W + 0.01, ('%s: the clause list is %.2f wide, its minw is %.2f'):format(label, list.T.w, LIST_W))
  local n, slack, rh, ch = rows(), math.huge, 0, 0
  for i = 1, n do
    local x = box:get_UIE_by_ID('seedfinder_remove_'..i)
    ctx.assert(x, label..': no X on row '..i)
    local r = x.parent.parent -- the X's button column, then its clause row
    ctx.assert(r.UIT == G.UIT.R, label..': row '..i..' is not where the X says')
    local left, right = r.T.x - list.T.x, list.T.x + list.T.w - (r.T.x + r.T.w)
    ctx.assert(left >= 0.07 and right >= 0.07, ('%s: row %d sticks out of the clause list (left %.2f, right %.2f)')
      :format(label, i, left, right))
    slack = math.min(slack, left + right)
    local function own_h(e) return math.max(e.content_dimensions and e.content_dimensions.h or 0, e.config.minh or 0) end
    local cell, tallest = r.children[1], 0
    for k = 2, #r.children do tallest = math.max(tallest, own_h(r.children[k])) end
    ctx.assert(own_h(cell) <= tallest + 0.001, ('%s: row %d\'s connector is %.2f tall, the rest %.2f'):format(label, i,
      own_h(cell), tallest))
    rh, ch = math.max(rh, r.T.h), math.max(ch, own_h(cell))
  end
  ctx.log(('layout %s: overlay x %.2f..%.2f y %.2f..%.2f, filter panel %.2fx%.2f, list %.2fx%.2f, %d rows, least slack %s,'
    ..' row h %.2f, connector h %.2f'):format(label, x1, x2, y1, y2, fw, fh, list.T.w, list.T.h, n,
    n > 0 and ('%.2f'):format(slack) or '-', rh, ch))
  ctx.assert(x1 >= 0 and y1 >= -0.2 and x2 <= G.ROOM.T.w and y2 <= G.ROOM.T.h, label..': the overlay does not fit the room')
  local w0 = S.widths[1]
  if w0 then
    ctx.assert(math.abs(x1 - w0.x1) <= 0.01 and math.abs(x2 - w0.x2) <= 0.01, ('%s: overlay x %.2f..%.2f, %s was %.2f..%.2f')
      :format(label, x1, x2, w0.label, w0.x1, w0.x2))
    ctx.assert(math.abs(fw - w0.fw) <= 0.01, ('%s: filter panel w %.2f, %s was %.2f'):format(label, fw, w0.label, w0.fw))
    ctx.assert(math.abs(y1 - w0.y1) <= 0.01 and math.abs(y2 - w0.y2) <= 0.01, ('%s: overlay y %.2f..%.2f, %s was %.2f..%.2f')
      :format(label, y1, y2, w0.label, w0.y1, w0.y2))
  end
  -- The list holds its minh with 1..MAX_ROWS - 1 rows. (The Filter panel's own
  -- height is only logged: a generated name cut at 30 shrinks the filter cycle's
  -- label, and with it the panel, by 0.02; the overlay's y extent is held above.)
  if n > 0 and n < MAX_ROWS then
    ctx.assert(list.T.h <= LIST_H + 0.01, ('%s: %d rows grow the clause list to %.2f, its minh is %.2f')
      :format(label, n, list.T.h, LIST_H))
  elseif n > 0 then
    ctx.log(('layout %s: %d rows are %.2f tall, past the list\'s minh %.2f'):format(label, n, list.T.h, LIST_H))
  end
  S.widths[#S.widths + 1] = {label = label, x1 = x1, x2 = x2, y1 = y1, y2 = y2, fw = fw}
end

-- A step that waits for the panel to settle (after a click's rebuild), then runs fn.
local function settled(name, fn, wait)
  return {name = name, timeout = 5, run = function(ctx)
    if (wait and not wait()) or ctx.step_time() < 0.5 or G.CONTROLLER.locks.frame then return false end
    return fn(ctx) ~= false
  end}
end

local steps = {
  -- 0. Red Deck won up to stake 3: its stakes go up to Black (get_deck_win_stake + 1).
  {name = 'red deck wins', timeout = 5, run = function(ctx)
    local usage = G.PROFILES[G.SETTINGS.profile].deck_usage
    usage.b_red = {count = 1, order = G.P_CENTERS.b_red.order, wins = {[1] = 1, [2] = 1, [3] = 1}, losses = {}}
    ctx.assert(get_deck_win_stake('b_red') == 3, 'Red Deck wins not as set')
    return true
  end},
  click('open options', 'options'),
  click('open finder', 'seedfinder_open', nil, function() return G.OVERLAY_MENU end),
  {name = 'finder open', timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 1 then return false end
    local f = ui.current()
    ctx.assert(#f.clauses == 0 and f.deck == 'b_red' and f.stake == 1 and (f.mode or 'all') == 'all',
      'a fresh profile does not start with an empty Red Deck, White Stake, All clauses filter')
    local stakes = cycle_options('stake')
    ctx.assert(#stakes == 4 and stakes[4] == stake_name(4), 'Red Deck offers stakes: '..table.concat(stakes, ', '))
    measure(ctx, '0 rows')
    return true
  end},

  -- 1. No Plant by ante 3
  click('add clause 1', 'seedfinder_add'),
  cycle_to('c1_kind', 'Boss'),
  cycle_to('c1_ante', function() return ante_label(3) end),
  cycle_to('c1_extra', 'By ante'),
  cycle_to('c1_key', function() return name_of('Blind', 'bl_plant') end, 40),
  settled('row 1 connector blank', function(ctx)
    ctx.assert(same(ui.current().clauses, {PLANT}), 'before "not": '..STR_PACK(ui.current().clauses))
    ctx.assert(label_of('seedfinder_c1_not') == '' and not uie('seedfinder_c1_join'),
      'row 1\'s connector is not a blank seedfinder_c1_not: '..tostring(label_of('seedfinder_c1_not')))
    ctx.assert(ui.current().name == 'The Plant by A3', 'the name is '..ui.current().name)
    ctx.shot('mustnot_blank')
  end),
  join(1),
  settled('no plant built by clicks', function(ctx)
    model_is(ctx, 'no plant', {NO_PLANT}, 'not')
    local f = ui.current()
    ctx.assert(f.name == 'no The Plant by A3' and not f.named, 'the name is "'..f.name..'"')
    ctx.log('no plant: '..f.name..' '..STR_PACK(f.clauses))
    ctx.log('check: no plant built by clicks')
    measure(ctx, 'not row')
  end),

  -- 2. A clean Blueprint at Black Stake
  cycle_to('stake', function() return stake_name(4) end),
  click('add clause 2', 'seedfinder_add', nil, function() return ui.current().stake == 4 and rows() == 1 end),
  cycle_to('c2_kind', 'Joker by ante'),
  cycle_to('c2_ante', 'By ante 3'),
  cycle_to('c2_key', function() return name_of('Joker', 'j_blueprint') end, 40),
  settled('clean options at black stake', function(ctx)
    local opts = cycle_options('c2_extra')
    ctx.assert(#opts == 12 and opts[1] == 'R0' and opts[2] == 'R0 clean' and opts[12] == 'R5 clean',
      'at Black Stake the reroll cycle offers: '..table.concat(opts, ', '))
    ctx.log('Black Stake reroll options: '..table.concat(opts, ', '))
  end),
  cycle_to('c2_extra', 'R0 clean'),
  settled('clean joker', function(ctx)
    model_is(ctx, 'clean joker', {NO_PLANT, CLEAN}, 'not/and')
    ctx.assert(ui.current().name == cut('no The Plant by A3 + Blueprint by A3 (clean)'), 'the name is '..ui.current().name)
    measure(ctx, 'clean row')
    ctx.shot('mustnot_built')
  end),
  -- The clean label in full: a copy without the Plant row, then deleted.
  click('save as', 'seedfinder_save_as', 'seedfinder_save_as'),
  click('cancel the name', 'seedfinder_name_cancel', 'seedfinder_name_cancel',
    function() return uie('seedfinder_name_cancel') end),
  click('copy: remove the plant row', 'seedfinder_remove', 'seedfinder_remove_1',
    function() return not uie('seedfinder_name_cancel') and uie('seedfinder_remove_2') end),
  settled('clean label', function(ctx)
    local f = ui.current()
    ctx.assert(same(f.clauses, {CLEAN}), 'the copy holds '..STR_PACK(f.clauses))
    ctx.assert(f.name == 'Blueprint by A3 (clean)', 'the copy is named "'..f.name..'"')
    ctx.log('clean label: '..f.name)
  end),
  click('delete the copy', 'seedfinder_delete'),
  settled('first filter back', function(ctx)
    model_is(ctx, 'after Delete', {NO_PLANT, CLEAN}, 'not/and')
  end, function() return rows() == 2 end),
  cycle_to('stake', function() return stake_name(3) end),
  settled('clean joker built by clicks', function(ctx)
    model_is(ctx, 'Green Stake', {NO_PLANT, BLUEPRINT}, 'not/and')
    local opts = cycle_options('c2_extra')
    ctx.assert(#opts == 6 and cycle_value('c2_extra') == 'No rerolls', 'below Black Stake the reroll cycle shows '
      ..tostring(cycle_value('c2_extra'))..' of '..table.concat(opts, ', '))
    for _, l in ipairs(opts) do ctx.assert(not l:find('clean', 1, true), 'a clean option below Black Stake: '..l) end
    ctx.assert(ui.current().name == cut('no The Plant by A3 + Blueprint by A3'), 'the name is '..ui.current().name)
    ctx.log('check: clean joker built by clicks')
  end, function() return ui.current().stake == 3 end),

  -- 3. A "not" row is never a group member
  click('add clause 3', 'seedfinder_add', nil, function() return rows() == 2 end),
  click('add clause 4', 'seedfinder_add', nil, function() return rows() == 3 end),
  settled('four rows', function(ctx)
    model_is(ctx, 'four rows', {NO_PLANT, BLUEPRINT, TAG, TAG}, 'not/and/and/and')
  end, function() return rows() == 4 and uie('seedfinder_c4_join') end),
  join(2),
  settled('or under the not row joins below', function(ctx)
    model_is(ctx, 'row 2 or', {NO_PLANT, group(BLUEPRINT, TAG), TAG}, 'not/and/or/and')
    ctx.log('row 2\'s "or", straight under the "not" row, joined row 3 below it: '..connectors())
  end),
  join(2),
  settled('row 2 on to not', function(ctx)
    model_is(ctx, 'row 2 not', {NO_PLANT, NO_BLUEPRINT, TAG, TAG}, 'not/not/and/and')
    ctx.log('row 2 clicked again: its "or" changed nothing, so it went on to "not": '..connectors())
  end),
  join(3),
  settled('not row not in a group', function(ctx)
    model_is(ctx, 'row 3 or', {NO_PLANT, NO_BLUEPRINT, group(TAG, TAG)}, 'not/not/and/or')
    for _, e in ipairs(ui.current().clauses) do
      if e.kind == 'group' then
        for m, c in ipairs(e.clauses) do ctx.assert(c.exclude == nil, 'group member '..m..' carries exclude') end
      end
    end
    ctx.log('the third row\'s "or" under the "not" row joined row 4 below it: '..connectors()..' = '..ui.current().name)
    ctx.log('check: not row not in a group')
    measure(ctx, '4 rows, two must-nots and a group')
    ctx.shot('mustnot_rows')
  end),

  -- 4. Any clause
  click('mode any', 'seedfinder_cycle', 'seedfinder_mode_r'),
  settled('mode any drops must-not', function(ctx)
    local f = ui.current()
    ctx.assert(f.mode == 'any' and cycle_value('mode') == 'Any clause', 'the mode is '..tostring(f.mode))
    model_is(ctx, 'mode any', {PLANT, BLUEPRINT, TAG, TAG}, '')
    for i = 1, MAX_ROWS do
      ctx.assert(not uie('seedfinder_c'..i..'_join') and not uie('seedfinder_c1_not'), 'a connector shows under Any clause')
    end
    ctx.assert(status_text() == DROPPED, 'the status line says "'..status_text()..'"')
    ctx.log('status: '..status_text())
    ctx.log('check: mode any drops must-not')
    measure(ctx, 'mode any')
    ctx.shot('mustnot_any')
  end, function() return ui.current().mode == 'any' end),

  -- 5. Search: no The Plant by ante 3 + an ante-1 Uncommon Tag
  click('mode all', 'seedfinder_cycle', 'seedfinder_mode_l'),
  click('remove the blueprint row', 'seedfinder_remove', 'seedfinder_remove_2',
    function() return ui.current().mode == 'all' and uie('seedfinder_c1_not') end),
  settled('blueprint row removed', function(ctx) model_is(ctx, 'blueprint removed', {PLANT, TAG, TAG}, '_/and/and') end),
  click('remove the last tag row', 'seedfinder_remove', 'seedfinder_remove_3', function() return rows() == 3 end),
  join(1),
  settled('plant row before the search', function(ctx)
    model_is(ctx, 'no plant again', {NO_PLANT, TAG}, 'not/and')
  end, function() return rows() == 2 end),
  -- "no The Plant by ante 3" excludes nothing (boss.min 4): row 1 becomes "no The
  -- Hook by ante 2" by its buttons, through its positive form.
  join(1),
  settled('row 1 back to blank', function(ctx)
    model_is(ctx, 'row 1 blank', {PLANT, TAG}, '_/and')
  end, function() return ui.current().clauses[1].exclude == nil end),
  cycle_to('c1_ante', function() return ante_label(HOOK.ante) end),
  cycle_to('c1_extra', 'By ante'),
  cycle_to('c1_key', function() return name_of('Blind', 'bl_hook') end, 40),
  settled('the hook by ante 2', function(ctx)
    model_is(ctx, 'the hook', {HOOK, TAG}, '_/and')
  end, function() return ui.current().clauses[1].key == 'bl_hook' end),
  join(1),
  {name = 'start', timeout = 5, run = function(ctx)
    if rows() ~= 2 or ctx.step_time() < 0.5 or G.CONTROLLER.locks.frame then return false end
    model_is(ctx, 'search filter', {NO_HOOK, TAG}, 'not/and')
    local f = ui.current()
    ctx.assert(f.deck == 'b_red' and f.stake == 3 and f.mode == 'all', 'not Red Deck, Green Stake, All clauses')
    ctx.assert(f.name:sub(1, 17) == 'no The Hook by A2', 'the name is "'..f.name..'"')
    ctx.assert(G.P_BLINDS.bl_hook.boss.min <= HOOK.ante, 'The Hook cannot be a boss by ante '..HOOK.ante)
    return true
  end},
  cycle_to('workers', '4 workers'),
  click('start', 'seedfinder_start'),
  {name = 'twenty hits', timeout = 60, run = function(ctx)
    local s = ui.search()
    if not (s and (#s.found >= HITS or not s.running)) then return false end
    ctx.assert(#s.found >= HITS, 'the search ended with '..#s.found..' hits: '..tostring(s.error))
    ctx.log(('search: %d scanned, %d seeds/s, %d hits'):format(s.scanned or 0, s.rate or 0, #s.found))
    if s.running then ctx.assert(ctx.click('seedfinder_cancel'), 'no Cancel while searching') end
    return true
  end},
  settled('search respects must-not', function(ctx)
    local s = ui.search()
    ctx.assert(same(s.filter.clauses, {NO_HOOK, TAG}), 'the search ran '..STR_PACK(s.filter.clauses))
    ctx.assert(not s.error and #s.found >= HITS, #s.found..' hits: '..tostring(s.error))
    -- The engine's soundness re-check (engine.poll's counters, kept on the search
    -- state): every worker candidate it checked held on this thread.
    ctx.assert(type(s.candidates) == 'number' and type(s.rejected) == 'number',
      'the search state has no candidates / rejected counters')
    ctx.assert(s.rejected == 0, s.rejected..' of '..s.candidates..' worker candidates failed the re-check')
    ctx.assert(s.candidates >= #s.found, s.candidates..' candidates for '..#s.found..' hits')
    -- Every hit: the filter holds with the must-not ok, the positive form fails and
    -- predict puts no The Hook in antes 1..2.
    local positive = {name = 'p', deck = 'b_red', stake = 3, mode = 'all', clauses = {deep(HOOK)}}
    local seen = {}
    for _, seed in ipairs(s.found) do
      local ok, d = filter.eval_seed(s.filter, seed)
      ctx.assert(ok, seed..': eval_seed is false')
      ctx.assert(d.results[1] and d.results[1].ok == true and d.results[2] and d.results[2].ok == true,
        seed..': the must-not or the tag clause did not hold')
      ctx.assert(not filter.eval_seed(positive, seed), seed..': The Hook by ante 2 holds')
      local St, bosses = filter.fresh(s.filter, seed), {}
      for a = 1, HOOK.ante do
        bosses[a] = predict.boss(St, a)
        ctx.assert(bosses[a] ~= 'bl_hook', seed..': The Hook is the ante '..a..' boss')
        seen[bosses[a]] = true
      end
      if seed == s.found[1] then ctx.log(seed..': bosses 1..2 '..table.concat(bosses, ', ')) end
    end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    -- The must-not excludes seeds: a fixed list of LIST_N seeds (no scan), each
    -- judged by the tag clause alone and predict's bosses. The filter holds exactly
    -- when the tag does and The Hook is not a boss by ante 2; seeds with the tag and
    -- The Hook are rejected by the must-not (its result false, the tag's true).
    local tag_only = {name = 't', deck = 'b_red', stake = 3, mode = 'all', clauses = {deep(TAG)}}
    local held, violating = 0, {}
    for i = 1, LIST_N do
      local seed = engine.seed_at(i)
      local St, hook_at = filter.fresh(s.filter, seed), nil
      for a = 1, HOOK.ante do
        if not hook_at and predict.boss(St, a) == 'bl_hook' then hook_at = a end
      end
      local tag = filter.eval_seed(tag_only, seed)
      local ok, d = filter.eval_seed(s.filter, seed)
      ctx.assert(ok == (tag and not hook_at), ('%s: the filter gives %s, the tag %s, The Hook at ante %s')
        :format(seed, tostring(ok), tostring(tag), tostring(hook_at)))
      if ok then held = held + 1 end
      if tag and hook_at then
        ctx.assert(d.results[1] and d.results[1].ok == false and d.results[2] and d.results[2].ok == true,
          seed..': has the tag and The Hook at ante '..hook_at..', but the must-not did not reject it')
        violating[#violating + 1] = seed..' (The Hook at ante '..hook_at..')'
      end
    end
    ctx.assert(#violating >= 1, 'none of '..LIST_N..' fixed seeds has the tag and The Hook by ante 2')
    ctx.log(('search: scanned %d, candidates %d, rejected %d, hits %d; %d hits re-checked (eval_seed, the positive'
      ..' form fails, no The Hook in antes 1..2: %d distinct bosses); The Hook boss.min = %d')
      :format(s.scanned or 0, s.candidates, s.rejected, #s.found, #s.found, n, G.P_BLINDS.bl_hook.boss.min))
    ctx.log(('fixed seeds 1..%d: the filter holds for %d; %d have the tag and The Hook, all rejected: %s')
      :format(LIST_N, held, #violating, table.concat(violating, ', ')))
    ctx.log('check: search respects must-not')
  end, function() local s = ui.search(); return s and not s.running end),
  settled('hits shown', function(ctx)
    measure(ctx, 'with hits')
    ctx.shot('mustnot_hits')
  end, function()
    local s = ui.search()
    local first = s and s.order and s.order[1]
    return first and uie('seedfinder_play_'..first)
  end),

  -- 6. The widest labels at Black Stake, then every row
  cycle_to('stake', function() return stake_name(4) end),
  cycle_to('c2_kind', 'Shop joker'),
  cycle_to('c2_key', function() return widest_joker(true) end, 120),
  cycle_to('c2_extra', function() return widest_clean('c2_extra') end),
  click('add clause 3', 'seedfinder_add', nil, function() return rows() == 2 end),
  cycle_to('c3_kind', 'Joker by ante'),
  cycle_to('c3_key', function() return widest_joker(false) end, 120),
  cycle_to('c3_extra', function() return widest_clean('c3_extra') end),
  click('add clause 4', 'seedfinder_add', nil, function() return rows() == 3 end),
  cycle_to('c4_kind', 'Boss'),
  cycle_to('c4_extra', 'By ante'),
  cycle_to('c4_key', widest_boss, 40),
  join(4),
  join(4),
  settled('widest labels', function(ctx)
    local f = ui.current()
    ctx.assert(connectors() == 'not/and/and/not', 'the connectors are '..connectors())
    ctx.assert(f.clauses[4] and f.clauses[4].exclude and f.clauses[2].sticker == 'none' and f.clauses[3].sticker == 'none',
      'not the widest labels: '..STR_PACK(f.clauses))
    ctx.assert(cycle_value('c2_key') == widest_joker(true) and cycle_value('c3_key') == widest_joker(false)
      and cycle_value('c4_key') == widest_boss(), 'the key cycles do not show the widest names')
    ctx.log(('widest: %s / %s, %s, %s; name %s'):format(widest_joker(true), widest_joker(false),
      widest_clean('c3_extra'), widest_boss(), f.name))
    measure(ctx, 'widest labels')
    ctx.shot('mustnot_widest')
  end, function()
    local c = ui.current().clauses[4]
    return rows() == 4 and c ~= nil and c.exclude == true
  end),
  click('add clause 5', 'seedfinder_add', nil, function() return rows() == 4 end),
  settled('five rows', function(ctx) measure(ctx, '5 rows') end,
    function() return rows() == 5 and uie('seedfinder_c5_kind_r') end),
  click('add clause 6', 'seedfinder_add', nil, function() return rows() == 5 end),
  settled('width unchanged', function(ctx)
    measure(ctx, MAX_ROWS..' rows')
    ctx.assert(#S.widths >= 9, 'only '..#S.widths..' states measured')
    ctx.log(('check: width unchanged (%d states, overlay x %.2f..%.2f)'):format(#S.widths, S.widths[1].x1, S.widths[1].x2))
  end, function() return rows() == MAX_ROWS and uie('seedfinder_c'..MAX_ROWS..'_kind_r') end),
}

return steps
