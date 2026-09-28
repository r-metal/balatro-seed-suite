-- runjournal.runinfo: this run's history as a "History" tab in vanilla's Run Info
-- (T-373). It reads the record shape of docs/contracts-0.2.md § RunJournal.
--
-- Entry point (wraps vanilla, calls the original with every argument and changes only
-- its tab list; no vanilla body is copied)
--   G.UIDEF.run_info   a "History" tab after every tab vanilla builds (Poker Hands,
--                      Blinds, Vouchers, and Stake above White Stake) and any a mod
--                      adds before us. Same technique as seedfinder.ui's Find tab:
--                      create_tabs is wrapped only while run_info runs, and its
--                      outermost call gets the tab appended to args.tabs (after the
--                      last entry ipairs reaches: vanilla's Stake slot is a nil hole
--                      at White Stake) before the original runs with those args.
--
-- Size. create_tabs gives its content area a minh (tab_h = 8) and no minw, so a tab of
--   another size resizes the overlay when it opens. The tab the overlay opens on (Poker
--   Hands) is built inside that same create_tabs call: its UIBox's w/h are read as soon
--   as the call returns, and the History root takes them as minw/minh (the height at
--   least the area's own, tab_h less its padding). Cell widths, row heights and text
--   scales are computed to fit inside that for MAX_ROWS rows, so the overlay keeps the
--   size vanilla gives it whichever tab is open. Vanilla (1.0.1o) builds the same four
--   tabs in a challenge run; a tab another mod adds only widens the tab row, which the
--   content area doesn't depend on. At Red Stake and up the row with History is 15.7 of
--   G.ROOM's 20 wide (rig, 1280x720).
--
-- The tab: one row per ante reached, oldest first, read from recorder.current()
-- (antes -> blinds {kind, key, skipped, tag, won}); nothing is re-derived and nothing is
-- written. Ante | Small | Big | Boss; a cell has two lines, the second on a dark chip:
--   played       the blind's localized name; Beaten (won), Lost (won = false) or
--                Current (the newest blind with no outcome yet: the open one)
--   skipped      "Skipped"; the tag's localized name
--   not reached  blank
-- Only what the record holds is shown, so an upcoming boss never is (multiplayer bans
-- hidden-info tools). An ante that Hieroglyph/Petroglyph sent back gets a row per pass.
-- Past MAX_ROWS rows (endless), the newest MAX_ROWS plus "+N earlier". A record whose
-- first ante is past 1 (a run the Journal met mid-way, when it was loaded) says
-- "Recorded from ante N" on that same footer line. No record at all: "No history
-- recorded for this run".
--
-- API
--   runinfo.install()               wraps G.UIDEF.run_info. Once.
--   runinfo.definition(record, size) the tab's UIBox definition for a record (nil: no
--                                   history) at size {w, h} (the tab's
--                                   tab_definition_function_args; missing fields fall
--                                   back to the natural size). The rig measures it.
--   runinfo.LABEL, runinfo.MAX_ROWS 'History', 8.
-- The tab entry carries runjournal_history = true, and its size table as
-- tab_definition_function_args (filled once create_tabs returns).
-- Text ids (UIT.T, config.text): runjournal_hist_<ante>_<Kind> (line 1) and
--   runjournal_hist_<ante>_<Kind>_sub (line 2), with <ante> written <ante>p<pass> from an
--   ante's second pass on; runjournal_hist_more ("+N earlier"), runjournal_hist_from
--   ("Recorded from ante N"), runjournal_hist_none (no record).
--
-- The game font (m6x11plus) has no '·', '—', curly quotes, ellipsis or stars: plain
-- ASCII only.
local recorder = require('runjournal.recorder')

local M = {}

M.LABEL = 'History'
M.MAX_ROWS = 8

local KINDS = {'Small', 'Big', 'Boss'}
local ORDER = {Small = 1, Big = 2, Boss = 3}
local DEFAULT_KEY = {Small = 'bl_small', Big = 'bl_big'}

local ANTE_W = 0.8
local CELL_MAX_W, CELL_MAX_H = 3.0, 0.9
local PAD = 0.04           -- inside an ante row, around and between its cells
local GAP = 0.05           -- the table column's padding, between rows
local EMBOSS = 0.05        -- an ante row's emboss (the parent counts it in the height)
local HEAD_H, FOOT_H = 0.42, 0.34
local SLACK = 0.06         -- kept free on each axis, so rounding never grows the root
local TEXT_MAX, SUB = 0.4, 0.8     -- the name's largest scale; the status line's share of it
local CHIP = {0, 0, 0, 0.35}      -- the status line's backing
local SHADE = 0.65                 -- a blind colour's share when mixed with black

local installed = false

-- Names ----------------------------------------------------------------------------

local function name_of(set, key)
  if key == nil then return '?' end
  local ok, s = pcall(localize, {type = 'name_text', set = set, key = key})
  if ok and type(s) == 'string' and s ~= '' and s ~= 'ERROR' then return s end
  return tostring(key)
end

local function ante_word()
  local ok, s = pcall(localize, 'k_ante')
  if ok and type(s) == 'string' and s ~= '' and s ~= 'ERROR' then return s end
  return 'Ante'
end

-- A blind's panel colour, as vanilla paints blind chips, a shade darker: white names
-- stay legible on the pale bosses (The Water, The Club). Always a P_BLINDS key here:
-- get_blind_main_colour('Boss') would read the live blind choices.
local function blind_colour(key)
  if type(key) == 'string' and G.P_BLINDS and G.P_BLINDS[key] then
    local ok, c = pcall(get_blind_main_colour, key)
    if ok and type(c) == 'table' then return mix_colours(c, G.C.BLACK, SHADE) end
  end
  return G.C.BLACK
end

-- Height of one line of text at scale 1, in tile units (the formula UIBox uses for a
-- UIT.T node), so the rows fit whatever font the language brings.
local function line_unit()
  local f = G.LANG and G.LANG.font
  if not (f and f.FONT and G.TILESIZE) then return 1 end
  return f.FONT:getHeight() * (f.FONTSCALE or 0.1) * (f.TEXT_HEIGHT_SCALE or 1) / G.TILESIZE
end

-- Model ----------------------------------------------------------------------------

-- One row per pass through an ante, oldest first: {ante, pass, cells = {[kind] =
-- blind}}. A blind whose kind comes at or before the last one placed starts a new pass.
-- Also returns the open blind to mark Current: the newest one with no outcome.
local function build_rows(record)
  local antes = type(record) == 'table' and record.antes
  if type(antes) ~= 'table' then return nil end
  local keys = {}
  for a in pairs(antes) do
    if type(a) == 'number' then keys[#keys + 1] = a end
  end
  if #keys == 0 then return nil end
  table.sort(keys)
  local rows, open = {}, nil
  for _, a in ipairs(keys) do
    local e = antes[a]
    local blinds = type(e) == 'table' and type(e.blinds) == 'table' and e.blinds or {}
    local row = {ante = a, pass = 1, cells = {}}
    rows[#rows + 1] = row
    local top = 0
    for _, b in ipairs(blinds) do
      local o = type(b) == 'table' and ORDER[b.kind]
      if o then
        if o <= top then
          row = {ante = a, pass = row.pass + 1, cells = {}}
          rows[#rows + 1] = row
        end
        row.cells[b.kind] = b
        top = o
        if not b.skipped and b.won == nil then open = b end
      end
    end
  end
  return rows, open
end

-- main line, status line, status colour, cell colour, main colour (nil: light) for a
-- blind entry; nil for a blank cell.
local function lines_of(b, open)
  if not b then return nil end
  if b.skipped then
    return 'Skipped', b.tag and name_of('Tag', b.tag) or '', G.C.UI.TEXT_LIGHT, G.C.BLACK, G.C.BLUE
  end
  local key = b.key or DEFAULT_KEY[b.kind]
  local name = key and name_of('Blind', key) or (b.kind..' Blind')
  if b.won == true then return name, 'Beaten', G.C.GREEN, blind_colour(key) end
  if b.won == false then return name, 'Lost', G.C.RED, blind_colour(key) end
  if b == open then return name, 'Current', G.C.GOLD, blind_colour(key) end
  return name, '', G.C.UI.TEXT_LIGHT, blind_colour(key)
end

-- Layout ---------------------------------------------------------------------------

-- Cell and text sizes that fit MAX_ROWS rows, the header and the footer line in w x h.
local function layout(size)
  local w, h = size and tonumber(size.w), size and tonumber(size.h)
  local cell_w = CELL_MAX_W
  if w then cell_w = math.min(CELL_MAX_W, (w - SLACK - ANTE_W - 5 * PAD - 2 * GAP) / 3) end
  local cell_h = CELL_MAX_H
  if h then
    local per_row = (h - SLACK - GAP - (HEAD_H + GAP) - (FOOT_H + GAP)) / M.MAX_ROWS
    cell_h = math.min(CELL_MAX_H, per_row - GAP - EMBOSS - 2 * PAD)
  end
  local unit = line_unit()
  -- The name line, the status line at SUB of its scale, the chip's padding (2 x 0.02),
  -- the cell's (2 x 0.02) and the gap between the two lines (0.02).
  local text = math.min(TEXT_MAX, (cell_h - 0.1) / ((1 + SUB) * unit))
  return {w = w, h = h, cell_w = cell_w, cell_h = cell_h, text = text,
    sub = text * SUB, head = math.min(0.32, (HEAD_H - 2 * PAD) / unit),
    foot = math.min(0.3, (FOOT_H - 0.02) / unit)}
end

local function text(t, scale, colour, id)
  return {n=G.UIT.T, config={text = tostring(t), scale = scale, colour = colour or G.C.UI.TEXT_LIGHT,
    shadow = true, id = id}}
end

-- A cell: its name line, then its status (or tag) on a dark chip. The maxw rows shrink a
-- long name to the cell instead of widening it.
local function blind_cell(b, open, L, id)
  local main, sub, sub_colour, bg, main_colour = lines_of(b, open)
  if not main then
    return {n=G.UIT.C, config={align = 'cm', minw = L.cell_w, minh = L.cell_h, r = 0.1,
      colour = G.C.UI.TRANSPARENT_DARK}, nodes={}}
  end
  local current = sub == 'Current'
  return {n=G.UIT.C, config={align = 'cm', minw = L.cell_w, maxw = L.cell_w, minh = L.cell_h,
    r = 0.1, padding = 0.02, colour = bg, outline = current and 1.2 or nil,
    outline_colour = current and G.C.GOLD or nil}, nodes={
    {n=G.UIT.R, config={align = 'cm', maxw = L.cell_w - 0.15}, nodes={
      text(main, L.text, main_colour, id)}},
    {n=G.UIT.R, config={align = 'cm', maxw = L.cell_w - 0.2, padding = 0.02, r = 0.08,
      colour = sub ~= '' and CHIP or G.C.CLEAR}, nodes={
      text(sub, L.sub, sub_colour, id..'_sub')}},
  }}
end

local function ante_row(row, open, L)
  local tag = tostring(row.ante)..(row.pass > 1 and ('p'..row.pass) or '')
  local nodes = {
    {n=G.UIT.C, config={align = 'cm', minw = ANTE_W, maxw = ANTE_W, minh = L.cell_h, r = 0.1,
      colour = G.C.BLACK}, nodes={
      text(row.ante, math.min(0.45, L.text * 1.2), G.C.FILTER),
    }},
  }
  for _, kind in ipairs(KINDS) do
    nodes[#nodes + 1] = blind_cell(row.cells[kind], open, L, 'runjournal_hist_'..tag..'_'..kind)
  end
  return {n=G.UIT.R, config={align = 'cm', padding = PAD, r = 0.1, emboss = EMBOSS,
    colour = darken(G.C.JOKER_GREY, 0.1)}, nodes=nodes}
end

local function header_row(L)
  local function head(t, w)
    return {n=G.UIT.C, config={align = 'cm', minw = w, maxw = w, minh = HEAD_H - 2 * PAD}, nodes={
      text(t, L.head, G.C.UI.TEXT_LIGHT)}}
  end
  return {n=G.UIT.R, config={align = 'cm', padding = PAD}, nodes={
    head(ante_word(), ANTE_W), head('Small', L.cell_w), head('Big', L.cell_w), head('Boss', L.cell_w),
  }}
end

-- "+N earlier" and "Recorded from ante N" share one line.
local function footer(notes, L)
  local nodes = {}
  for i, note in ipairs(notes) do
    if i > 1 then nodes[#nodes + 1] = text(', ', L.foot, G.C.JOKER_GREY) end
    nodes[#nodes + 1] = text(note[1], L.foot, G.C.JOKER_GREY, note[2])
  end
  return {n=G.UIT.R, config={align = 'cm'}, nodes=nodes}
end

local function root(L, align, body)
  return {n=G.UIT.ROOT, config={align = align, colour = G.C.CLEAR, padding = 0, minw = L.w,
    minh = L.h}, nodes={
    {n=G.UIT.C, config={align = align, padding = GAP}, nodes=body},
  }}
end

function M.definition(record, size)
  local L = layout(size)
  local rows, open = build_rows(record)
  if not rows then
    return root(L, 'cm', {
      {n=G.UIT.R, config={align = 'cm'}, nodes={
        text('No history recorded for this run', 0.45, G.C.UI.TEXT_LIGHT, 'runjournal_hist_none')}},
    })
  end
  local body = {header_row(L)}
  local first = math.max(1, #rows - M.MAX_ROWS + 1)
  for i = first, #rows do body[#body + 1] = ante_row(rows[i], open, L) end
  local notes = {}
  if first > 1 then notes[#notes + 1] = {'+'..(first - 1)..' earlier', 'runjournal_hist_more'} end
  if rows[1].ante > 1 then
    notes[#notes + 1] = {'Recorded from ante '..rows[1].ante, 'runjournal_hist_from'}
  end
  if #notes > 0 then body[#body + 1] = footer(notes, L) end
  return root(L, 'tm', body)
end

-- Install --------------------------------------------------------------------------

local function find_contents(node)
  if type(node) ~= 'table' then return nil end
  if type(node.config) == 'table' and node.config.id == 'tab_contents' then return node end
  for _, child in pairs(type(node.nodes) == 'table' and node.nodes or {}) do
    local found = find_contents(child)
    if found then return found end
  end
end

-- Appends the History tab; returns the size table its builder reads, or nil when
-- the list already has one.
local function add_history_tab(tabs)
  local n = 0
  while tabs[n + 1] ~= nil do
    n = n + 1
    if type(tabs[n]) == 'table' and tabs[n].runjournal_history then return nil end
  end
  local size = {}
  tabs[n + 1] = {
    label = M.LABEL,
    tab_definition_function = function(s) return M.definition(recorder.current(), s) end,
    tab_definition_function_args = size,
    runjournal_history = true,
  }
  return size
end

-- The opening tab's size, from the UIBox create_tabs just built for it.
local function measure(size, args, t)
  local node = find_contents(t)
  local box = node and node.config.object
  if not (box and box.T and box.T.w and box.T.h) then return end
  size.w = box.T.w
  size.h = math.max(box.T.h, (tonumber(args.tab_h) or 0) - 2 * (tonumber(args.padding) or 0.1))
end

function M.install()
  if installed then return end
  installed = true

  local orig_run_info = G.UIDEF.run_info
  G.UIDEF.run_info = function(...)
    local orig_tabs = create_tabs
    local first = true
    -- Only the outermost call is run_info's own; a tab builder may call create_tabs again.
    create_tabs = function(args, ...)
      if not first then return orig_tabs(args, ...) end
      first = false
      local size = type(args) == 'table' and type(args.tabs) == 'table' and add_history_tab(args.tabs)
      local t = orig_tabs(args, ...)
      if size then measure(size, args, t) end
      return t
    end
    local ok, t = pcall(orig_run_info, ...)
    create_tabs = orig_tabs
    if not ok then error(t, 0) end
    return t
  end
end

return M
