-- Finder groups (T-314a): idea 5, "a Voucher or a Joker by ante N", built in the
-- Filter panel with its real buttons only (cycle arrows by their ids, Add clause,
-- the X, the "and" / "or" connector seedfinder_c<i>_join, the match cycle, Back,
-- Start, Cancel). The model is filter.lua's one-level any-of group (T-312); the
-- rows are a view of f.clauses (ui.lua header, Groups).
--   1. Fresh profile, Options -> Seed Finder. Add clause: kind Voucher, Ante 3,
--      By ante, key Telescope. Add clause: kind Joker by ante, By ante 3, key
--      Blueprint; its connector (and) clicked to "or". The model is exactly one
--      group {Voucher by, Joker}, filters.jkr holds it, filter.validate passes,
--      and the generated name is "(Telescope by A3 or Blueprint by A3)" cut at
--      30. -> "check: idea 5 built by clicks" (shot groups_built)
--   2. Back, then Seed Finder again: the same two rows (every cycle's label), the
--      "or" connector on row 2, none on row 1, and the model structurally equal
--      (also through filter.serialize / deserialize).
--      -> "check: group round-trips through the rows"
--   3. Add clause: row 3 is joined by "and"; the model is {group, plain tag}.
--      -> "check: and after a group"
--   4. The Blueprint row's X: the Voucher clause is plain again, no group of one
--      is left, row 2 (the tag) is joined by "and". -> "check: removing a member
--      flattens"
--   5. Row 2 back to Joker by ante 3 / Blueprint and "or" (the group again), then
--      the match cycle to Any clause: no group, the connectors gone, every member
--      kept as a plain clause. Back to All clauses: the rows are joined by "and".
--      -> "check: mode any flattens"
--   6. Row 2's connector to "or" again (idea 5 on the Red Deck), 4 workers, Start;
--      at 3 or more hits, Cancel (the search runs on the workers; nothing scans
--      here). Each hit re-checked with filter.eval_seed: true, the group's hit
--      names a member whose own details hold, and that member alone (a filter of
--      just it) holds for the seed. -> "check: search finds idea 5 hits"
--      (shot groups_hits)
--   7. The overlay's x and y extent and the Filter panel's width are equal (0.01)
--      in every state measured: 0 rows, the group, 3 rows including the group,
--      mode any, with hits, the widest labels (Joker by ante with the widest
--      non-legendary joker name, Voucher By ante, a tag "Small, by ante"), 5 and
--      MAX_CLAUSES rows. So is the panel's height, with 1 to MAX_CLAUSES - 1 rows
--      the list holding its minh: the connector cell is never taller than the
--      rest of its row. (MAX_CLAUSES rows outgrow the minh, 0.66 a row, since it
--      leaves out the list's 0.08 between rows: logged. Before T-314a the rows
--      were 0.78 tall and 5 rows did too.) In each, the clause list keeps its
--      minw and every clause row (connector cell included) lies inside it.
--      -> "check: width unchanged"
-- Screenshots: groups_built, groups_hits.
local ui = require('seedfinder.ui')
local filter = require('seedfinder.filter')
local fs = require('bhcore.fs')

local MAX_ROWS = 6   -- ui.lua's MAX_CLAUSES
local LIST_W = 11.2  -- the clause list's minw: ui.lua's FILTER_W - 0.4
local LIST_H = 4.16  -- and its minh: 0.66 * MAX_CLAUSES + 0.2

local S = {widths = {}}

local VOUCHER = {kind = 'voucher', ante = 3, key = 'v_telescope', by = true}
local JOKER = {kind = 'joker', ante = 3, key = 'j_blueprint', rerolls = 0, from = 'both'}
local IDEA5 = {kind = 'group', clauses = {VOUCHER, JOKER}}

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU ~= true and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function filter_box()
  local node = uie('seedfinder_filter')
  return node and node.config.object
end

local function name_of(set, key) return localize{type = 'name_text', set = set, key = key} end
local function ante_label(a) return localize('k_ante')..' '..a end

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

local function has_group(clauses)
  for _, c in ipairs(clauses) do if c.kind == 'group' then return true end end
  return false
end

local function disk()
  local t = fs.read_table(G.SETTINGS.profile..'/seedfinder/filters.jkr')
  return t and t.filters and t.filters[t.current]
end

local function rows() return #filter.plain_clauses(ui.current()) end

-- The generated name for idea 5, as ui.lua cuts it (NAME_MAX 30).
local function idea5_name()
  local s = ('(%s by A3 or %s by A3)'):format(name_of('Voucher', 'v_telescope'), name_of('Joker', 'j_blueprint'))
  if #s > 30 then s = s:sub(1, 27)..'...' end
  return s
end

-- The widest non-legendary joker name in the game font (the Joker by ante key cycle).
local function widest_joker()
  local font, best, bw = G.LANG.font.FONT, nil, -1
  for _, j in ipairs(G.P_CENTER_POOLS.Joker) do
    if j.rarity ~= 4 then
      local n = name_of('Joker', j.key)
      if font:getWidth(n) > bw then best, bw = n, font:getWidth(n) end
    end
  end
  return best
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

-- The overlay's x extent, the Filter panel's size and every clause row against the
-- clause list: logged, held equal to the first state (the height to the first
-- with clauses), and the overlay fits the room.
local function measure(ctx, label)
  local root = G.OVERLAY_MENU.UIRoot.children[1]
  local back = uie('overlay_menu_back_button')
  local x1, x2, y1, y2 = root.T.x, root.T.x + root.T.w, root.T.y, back.T.y + back.T.h
  local box = filter_box()
  local fw, fh = box.T.w, box.T.h
  local list = box:get_UIE_by_ID('seedfinder_clauses')
  ctx.assert(list, label..': no clause list')
  -- A row wider than the list's minw grows the list around it (then the panel and
  -- the overlay), so the list itself must keep its minw.
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
    -- The connector cell (the row's first child) is never its tallest, so it adds
    -- no height to a row. A row's cells are stretched to its height once laid out
    -- (T.h), so each is compared at its own height: its content's, or its minh.
    local function own_h(e) return math.max(e.content_dimensions and e.content_dimensions.h or 0, e.config.minh or 0) end
    local join, tallest = r.children[1], 0
    for k = 2, #r.children do tallest = math.max(tallest, own_h(r.children[k])) end
    ctx.assert(own_h(join) <= tallest + 0.001, ('%s: row %d\'s connector is %.2f tall, the rest %.2f'):format(label, i,
      own_h(join), tallest))
    rh, ch = math.max(rh, r.T.h), math.max(ch, own_h(join))
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
  end
  -- The panel's height is the list's minh up to MAX_ROWS - 1 rows. MAX_ROWS rows
  -- outgrow it (the minh leaves out the 0.08 between rows) and the Filter panel
  -- grows inside the overlay's height (the Search panel is taller: the y extent
  -- is held below).
  if n > 0 and n < MAX_ROWS then
    ctx.assert(list.T.h <= LIST_H + 0.01, ('%s: %d rows grow the clause list to %.2f, its minh is %.2f')
      :format(label, n, list.T.h, LIST_H))
    S.fh = S.fh or {h = fh, label = label}
    ctx.assert(math.abs(fh - S.fh.h) <= 0.01, ('%s: filter panel h %.2f, %s was %.2f'):format(label, fh, S.fh.label, S.fh.h))
  elseif n > 0 then
    ctx.log(('layout %s: %d rows are %.2f tall, past the list\'s minh %.2f'):format(label, n, list.T.h, LIST_H))
  end
  local y0 = S.widths[1]
  if y0 then
    ctx.assert(math.abs(y1 - y0.y1) <= 0.01 and math.abs(y2 - y0.y2) <= 0.01, ('%s: overlay y %.2f..%.2f, %s was %.2f..%.2f')
      :format(label, y1, y2, y0.label, y0.y1, y0.y2))
  end
  S.widths[#S.widths + 1] = {label = label, x1 = x1, x2 = x2, y1 = y1, y2 = y2, fw = fw}
end

-- Builds row i as idea 5's Joker member: Joker by ante, By ante 3, Blueprint.
local function joker_row(i)
  local p = 'c'..i..'_'
  return {
    cycle_to(p..'kind', 'Joker by ante'),
    cycle_to(p..'ante', 'By ante 3'),
    cycle_to(p..'key', function() return name_of('Joker', 'j_blueprint') end, 40),
  }
end

local steps = {
  click('open options', 'options'),
  click('open finder', 'seedfinder_open', nil, function() return G.OVERLAY_MENU end),
  {name = 'finder open', timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 1 then return false end
    ctx.assert(#ui.current().clauses == 0, 'a fresh profile starts with an empty filter')
    ctx.assert(ui.current().deck == 'b_red' and (ui.current().mode or 'all') == 'all', 'not Red Deck, All clauses')
    measure(ctx, '0 rows')
    return true
  end},

  -- 1. Idea 5 by clicks
  click('add clause 1', 'seedfinder_add'),
  cycle_to('c1_kind', 'Voucher'),
  cycle_to('c1_ante', function() return ante_label(3) end),
  cycle_to('c1_extra', 'By ante'),
  cycle_to('c1_key', function() return name_of('Voucher', 'v_telescope') end, 40),
  click('add clause 2', 'seedfinder_add', nil, function() return rows() == 1 end),
}
for _, s in ipairs(joker_row(2)) do steps[#steps + 1] = s end
for _, s in ipairs{
  {name = 'connect with or', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.3 or G.CONTROLLER.locks.frame then return false end
    ctx.assert(not uie('seedfinder_c1_join'), 'row 1 has a connector')
    ctx.assert(label_of('seedfinder_c2_join') == 'and', 'a new row is joined by '..tostring(label_of('seedfinder_c2_join')))
    ctx.assert(same(ui.current().clauses, {VOUCHER, JOKER}), 'before "or": '..STR_PACK(ui.current().clauses))
    return ctx.click('seedfinder_join', 'seedfinder_c2_join')
  end},
  {name = 'idea 5 built by clicks', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local f = ui.current()
    ctx.assert(same(f.clauses, {IDEA5}), 'the model is not one group {voucher by, joker}: '..STR_PACK(f.clauses))
    ctx.assert(label_of('seedfinder_c2_join') == 'or', 'row 2 shows '..tostring(label_of('seedfinder_c2_join')))
    local d = disk()
    ctx.assert(d and same(d.clauses, {IDEA5}), 'filters.jkr does not hold the group')
    local ok, err = filter.validate(deep(f))
    ctx.assert(ok, 'filter.validate: '..tostring(err))
    ctx.assert(f.name == idea5_name() and not f.named, ('the name is "%s", want "%s"'):format(f.name, idea5_name()))
    ctx.log('idea 5: '..f.name..' '..STR_PACK(f.clauses))
    ctx.log('check: idea 5 built by clicks')
    measure(ctx, 'idea 5 group')
    ctx.shot('groups_built')
    return true
  end},

  -- 2. Close and reopen
  click('back', 'options', 'overlay_menu_back_button'),
  {name = 'left the overlay', timeout = 5, run = function(ctx)
    if ui.is_open() or ctx.step_time() < 0.5 then return false end
    return ctx.click('seedfinder_open')
  end},
  {name = 'group round-trips through the rows', timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 0.8 then return false end
    local want = {
      c1_kind = 'Voucher', c1_ante = ante_label(3), c1_extra = 'By ante', c1_key = name_of('Voucher', 'v_telescope'),
      c2_kind = 'Joker by ante', c2_ante = 'By ante 3', c2_extra = 'No rerolls', c2_key = name_of('Joker', 'j_blueprint'),
    }
    for id, w in pairs(want) do
      ctx.assert(cycle_value(id) == w, ('reopened: %s shows "%s", want "%s"'):format(id, tostring(cycle_value(id)), w))
    end
    ctx.assert(not uie('seedfinder_c3_kind_r') and not uie('seedfinder_c1_join'), 'reopened: a third row, or a connector on row 1')
    ctx.assert(label_of('seedfinder_c2_join') == 'or', 'reopened: row 2 shows '..tostring(label_of('seedfinder_c2_join')))
    local f = ui.current()
    ctx.assert(same(f.clauses, {IDEA5}), 'reopened: the model is '..STR_PACK(f.clauses))
    local back = filter.deserialize(filter.serialize(deep(f)))
    ctx.assert(back and same(back.clauses, {IDEA5}), 'serialize / deserialize changed the group')
    ctx.log('check: group round-trips through the rows')
    return true
  end},

  -- 3. A plain row after the group
  click('add clause 3', 'seedfinder_add', nil, function() return rows() == 2 end),
  {name = 'and after a group', timeout = 5, run = function(ctx)
    if not uie('seedfinder_c3_kind_r') or ctx.step_time() < 0.5 then return false end
    local c = ui.current().clauses
    ctx.assert(#c == 2 and same(c[1], IDEA5) and c[2].kind == 'tag', 'the model is not {group, plain}: '..STR_PACK(c))
    ctx.assert(label_of('seedfinder_c3_join') == 'and' and label_of('seedfinder_c2_join') == 'or',
      'connectors: row 2 '..tostring(label_of('seedfinder_c2_join'))..', row 3 '..tostring(label_of('seedfinder_c3_join')))
    ctx.log('check: and after a group')
    measure(ctx, '3 rows including a group')
    return true
  end},

  -- 4. Removing the Blueprint row
  {name = 'remove the joker row', timeout = 5, run = function(ctx)
    if G.CONTROLLER.locks.frame or ctx.step_time() < 0.2 then return false end
    ctx.assert(cycle_value('c2_key') == name_of('Joker', 'j_blueprint'), 'row 2 is not Blueprint')
    return ctx.click('seedfinder_remove', 'seedfinder_remove_2')
  end},
  {name = 'removing a member flattens', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local c = ui.current().clauses
    ctx.assert(#c == 2 and same(c[1], VOUCHER) and c[2].kind == 'tag' and not has_group(c),
      'after the X: '..STR_PACK(c))
    ctx.assert(cycle_value('c1_kind') == 'Voucher' and cycle_value('c2_kind') == 'Skip tag' and not uie('seedfinder_c3_kind_r'),
      'the rows do not show Voucher, Skip tag')
    ctx.assert(label_of('seedfinder_c2_join') == 'and', 'the tag row is joined by '..tostring(label_of('seedfinder_c2_join')))
    ctx.assert(disk() and not has_group(disk().clauses), 'filters.jkr still holds a group')
    ctx.log('check: removing a member flattens')
    return true
  end},
} do steps[#steps + 1] = s end

-- 5. The group again, then Any clause
for _, s in ipairs(joker_row(2)) do steps[#steps + 1] = s end
for _, s in ipairs{
  click('or again', 'seedfinder_join', 'seedfinder_c2_join'),
  {name = 'group rebuilt', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 or G.CONTROLLER.locks.frame then return false end
    ctx.assert(same(ui.current().clauses, {IDEA5}), 'the group is not rebuilt: '..STR_PACK(ui.current().clauses))
    return ctx.click('seedfinder_cycle', 'seedfinder_mode_r')
  end},
  {name = 'mode any flattens', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local f = ui.current()
    ctx.assert(f.mode == 'any' and cycle_value('mode') == 'Any clause', 'the mode is '..tostring(f.mode))
    ctx.assert(same(f.clauses, {VOUCHER, JOKER}), 'Any clause left '..STR_PACK(f.clauses))
    for i = 1, MAX_ROWS do ctx.assert(not uie('seedfinder_c'..i..'_join'), 'a connector shows under Any clause (row '..i..')') end
    ctx.assert(cycle_value('c2_kind') == 'Joker by ante', 'the joker row is gone')
    ctx.assert(disk() and disk().mode == 'any' and not has_group(disk().clauses), 'filters.jkr still holds a group')
    measure(ctx, 'mode any')
    return ctx.click('seedfinder_cycle', 'seedfinder_mode_l')
  end},
  {name = 'all clauses again', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 or G.CONTROLLER.locks.frame then return false end
    local f = ui.current()
    ctx.assert(f.mode == 'all' and same(f.clauses, {VOUCHER, JOKER}), 'back on All clauses: '..STR_PACK(f.clauses))
    ctx.assert(label_of('seedfinder_c2_join') == 'and', 'back on All clauses row 2 shows '..tostring(label_of('seedfinder_c2_join')))
    ctx.log('check: mode any flattens')
    return true
  end},

  -- 6. Search
  click('or for the search', 'seedfinder_join', 'seedfinder_c2_join'),
  cycle_to('workers', '4 workers'),
  {name = 'start', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 or G.CONTROLLER.locks.frame then return false end
    local f = ui.current()
    ctx.assert(same(f.clauses, {IDEA5}) and f.deck == 'b_red' and f.mode == 'all', 'not idea 5 on the Red Deck: '
      ..STR_PACK(f.clauses))
    return ctx.click('seedfinder_start')
  end},
  {name = 'three hits', timeout = 60, run = function(ctx)
    local s = ui.search()
    if not (s and (#s.found >= 3 or not s.running)) then return false end
    ctx.assert(#s.found >= 3, 'the search ended with '..#s.found..' hits: '..tostring(s.error))
    ctx.log(('search: %d scanned, %d seeds/s, %d hits'):format(s.scanned or 0, s.rate or 0, #s.found))
    if s.running then ctx.assert(ctx.click('seedfinder_cancel'), 'no Cancel while searching') end
    return true
  end},
  {name = 'search finds idea 5 hits', timeout = 10, run = function(ctx)
    local s = ui.search()
    if s.running or ctx.step_time() < 0.5 then return false end
    ctx.assert(same(s.filter.clauses, {IDEA5}), 'the search ran '..STR_PACK(s.filter.clauses))
    local by = {0, 0}
    for _, seed in ipairs(s.found) do
      local ok, d = filter.eval_seed(s.filter, seed)
      ctx.assert(ok, seed..': eval_seed is false')
      local g = d.results[1]
      local m = g and g.hit
      ctx.assert(g and g.ok and (m == 1 or m == 2), seed..': the group names no member')
      ctx.assert(g.results[m] and g.results[m].ok, seed..': member '..m..'\'s details do not hold')
      local alone = {name = 'm', deck = 'b_red', stake = 1, mode = 'all', clauses = {deep(IDEA5.clauses[m])}}
      ctx.assert(filter.eval_seed(alone, seed), seed..': member '..m..' alone does not hold')
      by[m] = by[m] + 1
    end
    ctx.log(('%d hits re-checked: %d by the Voucher, %d by the Joker; first %s'):format(#s.found, by[1], by[2], s.found[1]))
    ctx.log('check: search finds idea 5 hits')
    return true
  end},
  {name = 'hits shown', timeout = 5, run = function(ctx)
    -- Row ids keep the hit's index in found; the list is ranked by route cost.
    local s = ui.search()
    local first = s.order and s.order[1]
    if not (first and uie('seedfinder_play_'..first)) or ctx.step_time() < 1 then return false end
    measure(ctx, 'with hits')
    ctx.shot('groups_hits')
    return true
  end},

  -- 7. The widest labels, then every row
  cycle_to('c2_key', widest_joker, 120),
  click('add clause 3', 'seedfinder_add', nil, function() return rows() == 2 end),
  cycle_to('c3_extra', 'Small, by ante'),
  {name = 'widest labels', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(cycle_value('c2_kind') == 'Joker by ante' and cycle_value('c2_key') == widest_joker()
      and cycle_value('c1_extra') == 'By ante', 'not the widest labels')
    ctx.log('widest joker: '..widest_joker()..'; name '..ui.current().name)
    measure(ctx, 'widest labels')
    return true
  end},
  click('add clause 4', 'seedfinder_add', nil, function() return rows() == 3 end),
  click('add clause 5', 'seedfinder_add', nil, function() return rows() == 4 end),
  {name = 'five rows', timeout = 5, run = function(ctx)
    if rows() ~= 5 or not uie('seedfinder_c5_kind_r') or ctx.step_time() < 0.5 then return false end
    measure(ctx, '5 rows')
    return true
  end},
  click('add clause 6', 'seedfinder_add', nil, function() return rows() == 5 end),
  {name = 'width unchanged', timeout = 5, run = function(ctx)
    if rows() ~= MAX_ROWS or not uie('seedfinder_c'..MAX_ROWS..'_kind_r') or ctx.step_time() < 0.5 then return false end
    measure(ctx, MAX_ROWS..' rows')
    ctx.assert(#S.widths >= 8, 'only '..#S.widths..' states measured')
    ctx.log(('check: width unchanged (%d states, overlay x %.2f..%.2f)'):format(#S.widths, S.widths[1].x1, S.widths[1].x2))
    return true
  end},
} do steps[#steps + 1] = s end

return steps
