-- The Save Slots overlay and its button callbacks. Contract: docs/SPEC.md.
--
-- Layout (modelled on vanilla G.UIDEF.challenge_list + challenge_list_page +
-- G.FUNCS.change_challenge_description)
--   left    the kind filter cycle (0.2: All / Saves / Checkpoints / Practice /
--           Hunts / Favorites), name input, "Save current run" (runs only), the
--           paged slot list (PAGE_SIZE rows, favorites first then newest first,
--           coloured by kind, a gold dot on favorites) and the page cycle
--   right   preview.build(run, summary) for the selected slot, action buttons
--           below it: Load, Overwrite (runs only), Rename, Delete. While a target
--           or notes edit is open, the preview is replaced by the editor (same
--           outer size) and the buttons by Save / Cancel.
--   meta    (0.2) a column beside the preview: the slot's kind with the
--           Favorite / Unfavorite toggle, target and notes with an Edit button
--           each, and a hunt's filter name. Below it,
--           level with the action row, "New practice" opens the practice
--           composer (practice.lua) and "Import code" (0.3) reads a share code.
--   share   (0.3, D3) "Share" beside Favorite copies the slot's share code
--           (sharecode.encode) to the clipboard and shows it, truncated, on a
--           line under the buttons. "Import code" decodes the clipboard into a
--           panel in the preview's place: seed / deck / stake / notes, with
--           Play / Cancel in the action row (or the decode error and Cancel).
--   The list, the preview, the buttons and the meta column are UIBoxes inside
--   G.UIT.O nodes ('saveslots_list', 'saveslots_detail', 'saveslots_actions',
--   'saveslots_meta'), swapped in place like the challenge list does. Any
--   mutation rebuilds the whole overlay instead, keeping the filter, the page
--   and the selection (module state below).
--
-- API
--   ui.install()               Registers G.FUNCS.saveslots_*. Runs once.
--   G.FUNCS.saveslots_open(e)  Opens the overlay; `e` may be nil. Its Back
--                              button returns to the pause menu in a run and
--                              closes the overlay on the main menu.
--
-- Buttons (G.FUNCS names, so the smoke rig can ctx.click them)
--   saveslots_save_new    saves checkpoint.get() as a new slot named after the input
--   saveslots_select      row click; e.config.ref_table.id is the slot id
--   saveslots_page        page cycle callback
--   saveslots_load        checkpoint.load_run(store.read(selected))
--   saveslots_overwrite   store.save(checkpoint.get(), nil, selected)
--   saveslots_rename      store.rename(selected, input text); ignored when empty
--   saveslots_delete      first press arms ("Confirm delete"), second deletes.
--                         Every other action disarms it.
--   saveslots_kind_cycle  the kind filter's arrows (see kind_cycle for why they
--                         aren't 'option_cycle'); saveslots_kind is its callback
--   saveslots_edit_target / saveslots_edit_notes
--                         open the editor for the selected slot, its text input
--                         already hooked (TARGET_MAX / NOTES_MAX chars)
--   saveslots_edit_save   store.set_meta(selected, {<field> = text}); Return in
--                         the input does the same. '' clears the field.
--   saveslots_favorite    toggles store meta.favorite on the selected slot
--   saveslots_practice    (registered by practice.lua) opens the practice composer
--   saveslots_edit_cancel closes the editor. So does selecting a row, paging or
--                         filtering; Esc only releases the input (vanilla).
--   saveslots_share       copies sharecode.encode{seed, deck, stake, notes, filter =
--                         meta.origin.filter, route = meta.route} of the selected
--                         slot to the clipboard
--   saveslots_import      decodes the clipboard with sharecode.decode into the
--                         import panel; a bad code shows the error (cancel sound)
--   saveslots_import_play starts an unseeded run on the code's seed, deck, stake
--   saveslots_import_cancel closes the import panel (as leaving the editor does)
--
-- Rules this file keeps
--   * Disk only through store/checkpoint. Never G.ARGS.save_run (docs/SPEC.md
--     "Traps"): with no checkpoint yet, saving is refused with an alert.
--   * Brainstorm import (D4) runs on the first open whose import call succeeds.
--     A failure (nil, err or a raise) alerts and is retried on the next open;
--     so does a partial import (n, err: the store left its flag unset).
--   * The selected slot is read with store.read before preview.build; an
--     unreadable slot (or a preview error) shows "Preview unavailable" and the
--     list stays usable. After an overwrite the page follows the slot (page 1).
--   * The right column is DETAIL_W wide in every state; the message panel and
--     the (framed) preview panel share one DETAIL_W x DETAIL_H outer size; the
--     action row fits inside it.
--   * The game font (m6x11plus) has no '·' or '—' glyphs, so row and alert
--     text use plain ASCII separators.
--   * attention_text boxes are drawn before the overlay in Game:draw, so an
--     alert raised with the overlay up is re-homed as the overlay's `alert`
--     child, which UIBox:draw paints last (see alert()).
--   * Only one 'option_cycle' button and one 'select_text_input' may precede
--     the page cycle and the name input in the tree: 0.1.0 callers (and the
--     ui_flow scenario) find them as the first of their kind. Hence the renamed
--     kind-cycle arrows, and the meta inputs existing only in the editor.
--   * vanilla text_input_key turns '0' into 'o'; the meta inputs inherit that.
--   * The clipboard goes through vanilla's pair (copy_seed / paste_seed,
--     button_callbacks.lua:940 and 1816): G.CLIPBOARD when G.F_LOCAL_CLIPBOARD is
--     set, love.system's clipboard otherwise, so the rig can drive both ends.
--   * Import's Play is unseeded, like the Finder's: vanilla start_run marks any run
--     given a seed as `seeded` (game.lua:2163). The Game:start_run wrap installed
--     here clears it once start_run returns, only for the seed Play just started
--     (`unseed`), and never for a loaded savetext. The truncated code ends in
--     '...': the game font has no ellipsis glyph.
local store = require('saveslots.store')
local checkpoint = require('saveslots.checkpoint')
local preview = require('saveslots.preview')
local sharecode = require('saveslots.sharecode')

local ui = {}

local PAGE_SIZE = 8
local NAME_MAX = 24
local LIST_W = 4.6       -- left column width
local ROW_H = 0.62
-- The right column is this size in every state (message, preview, error), sized
-- to preview.build's panel, and the action row is kept inside DETAIL_W.
local DETAIL_W, DETAIL_H = 8, 7.3
local ACTION_W = 1.7     -- one action button; 4 of them + gaps fit in DETAIL_W
local META_W = 3.4       -- the meta column beside the preview, DETAIL_H high
local META_CHARS = 17    -- meta text wraps at this many chars per line
local CODE_CHARS = 18    -- the share code line shows this many chars, then '...'

-- The kind filter's options, in cycle order. kind = nil lists everything.
local FILTERS = {
  {label = 'All', empty = 'No saves yet'},
  {label = 'Saves', kind = 'save', empty = 'No saves yet'},
  {label = 'Checkpoints', kind = 'checkpoint', empty = 'No checkpoints yet'},
  {label = 'Practice', kind = 'practice', empty = 'No practice runs yet'},
  {label = 'Hunts', kind = 'hunt', empty = 'No hunts yet'},
  {label = 'Favorites', favorite = true, empty = 'No favorites yet'},
}
local KIND_LABEL = {save = 'Save', checkpoint = 'Checkpoint', practice = 'Practice', hunt = 'Hunt'}
local function kind_colour(kind)
  if kind == 'checkpoint' then return G.C.FILTER end
  if kind == 'practice' then return G.C.GREEN end
  if kind == 'hunt' then return G.C.PURPLE end
  return G.C.RED
end
local EDIT = {
  target = {title = 'Edit target', prompt = 'Target', max = store.TARGET_MAX, scale = 0.4},
  notes = {title = 'Edit notes', prompt = 'Notes', max = store.NOTES_MAX, scale = 0.3},
}

-- Survives rebuilds (and closing the overlay) for the rest of the session.
-- `name` is the text input's ref_table/ref_value; `edit_text` the editor's.
-- `kind` indexes FILTERS; `editing` is nil, 'target' or 'notes'. `share` is the
-- last code copied, {id, code}; `import` the open import panel, {t = decoded} or
-- {err = message}.
local state = {name = '', page = 1, selected = nil, confirm_delete = nil, kind = 1,
  editing = nil, edit_text = '', share = nil, import = nil}
local unseed = nil       -- the seed Import's Play started, until its start_run clears `seeded`
local imported = false   -- set only once an import fully succeeded; a failure or partial retries next open
local installed = false

local function in_run() return G.STAGE == G.STAGES.RUN end

local function filter() return FILTERS[state.kind] or FILTERS[1] end

local function is_favorite(slot) return slot.meta and slot.meta.favorite == true end

-- The slots the list shows: store.list under the current filter, favorites pinned
-- first (each group keeps store.list's newest-first order).
local function list_slots()
  local all = store.list({kind = filter().kind, favorite = filter().favorite})
  local out = {}
  for _, s in ipairs(all) do if is_favorite(s) then out[#out+1] = s end end
  for _, s in ipairs(all) do if not is_favorite(s) then out[#out+1] = s end end
  return out
end

local function find_slot(slots, id)
  for i, s in ipairs(slots) do
    if s.id == id then return s, i end
  end
end

local function page_count(slots) return math.max(1, math.ceil(#slots/PAGE_SIZE)) end

-- Keeps page/selection valid against the current list (after a delete, say).
local function clamp_state(slots)
  if state.selected and not find_slot(slots, state.selected) then state.selected = nil end
  state.page = math.min(math.max(1, state.page or 1), page_count(slots))
end

-- Moves the page to wherever the selected slot sits now (after an overwrite the
-- slot is the newest of its group; after a favorite toggle it changed group).
local function page_to_selected(slots)
  if not state.selected then return end
  local _, i = find_slot(slots, state.selected)
  if i then state.page = math.ceil(i/PAGE_SIZE) end
end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

-- An on-screen message in the style of vanilla attention_text (as Brainstorm's
-- saveManagerAlert uses it, but our own). attention_text builds its box in an
-- event; the follow-up event moves it above the overlay and forgets it once
-- attention_text's own fade-out removes it.
local function alert(text)
  local args = {
    text = text,
    scale = 0.55,
    hold = 2.2,
    colour = G.C.WHITE,
    -- with the overlay up: in the strip of backdrop above the panel
    major = G.OVERLAY_MENU and G.ROOM_ATTACH or (in_run() and G.play or G.title_top),
    align = G.OVERLAY_MENU and 'tm' or 'cm',
    offset = {x = 0, y = G.OVERLAY_MENU and 0.15 or -3.5},
    silent = true,
  }
  attention_text(args)
  local homed = nil
  G.E_MANAGER:add_event(Event({
    blockable = false, blocking = false,
    func = function()
      local box, ov = args.AT, G.OVERLAY_MENU
      if not box then return false end
      if not homed then
        if box.REMOVED or not ov then return true end
        if ov.children.alert and ov.children.alert ~= box then ov.children.alert:remove() end
        box.attention_text = nil
        box.parent = ov
        ov.children.alert = box
        homed = ov
        return false
      end
      if box.REMOVED or homed.REMOVED then
        if homed.children.alert == box then homed.children.alert = nil end
        return true
      end
      return false
    end
  }))
  play_sound('other1', 0.76, 0.4)
end

-- One list row: the name over "A<ante> $<dollars>   <MM-DD HH:MM>", styled
-- like UIBox_button so `chosen = 'vert'` draws the challenge-list marker.
local function slot_row(slot)
  local sm = slot.summary or {}
  local meta = 'A'..tostring(sm.ante or '?')..'  $'..tostring(sm.dollars or '?')
  local when = slot.saved_at and slot.saved_at > 0 and os.date('%m-%d %H:%M', slot.saved_at) or ''
  local name_nodes = {}
  if is_favorite(slot) then
    -- A gold dot, not a star: the game font has no star glyph.
    -- (A column in a row is stretched to the row's height, so the dot sits in one.)
    name_nodes[1] = {n=G.UIT.C, config={align = 'cm'}, nodes={
      {n=G.UIT.R, config={id = 'saveslots_fav_'..slot.id, minw = 0.16, minh = 0.16, r = 0.08, colour = G.C.GOLD}, nodes={}},
    }}
    name_nodes[2] = {n=G.UIT.B, config={w = 0.1, h = 0.1}}
  end
  name_nodes[#name_nodes+1] = {n=G.UIT.T, config={text = slot.name or '?', scale = 0.36,
    colour = G.C.UI.TEXT_LIGHT, shadow = true}}
  return {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
    {n=G.UIT.C, config={id = 'saveslots_row_'..slot.id, align = 'cm', minw = LIST_W - 0.2, minh = ROW_H,
        padding = 0.04, r = 0.1, hover = true, shadow = true, colour = kind_colour(slot.meta and slot.meta.kind),
        button = 'saveslots_select', ref_table = {id = slot.id},
        chosen = (state.selected == slot.id) and 'vert' or nil}, nodes={
      {n=G.UIT.R, config={align = 'cm', maxw = LIST_W - 0.4}, nodes=name_nodes},
      {n=G.UIT.R, config={align = 'cm', maxw = LIST_W - 0.4}, nodes={
        {n=G.UIT.T, config={text = meta, scale = 0.28, colour = G.C.UI.TEXT_LIGHT}},
        {n=G.UIT.B, config={w = 0.25, h = 0.1}},
        {n=G.UIT.T, config={text = when, scale = 0.28, colour = G.C.JOKER_GREY}},
      }},
    }},
  }}
end

local function list_page_def(slots)
  local rows = {}
  local first = (state.page - 1)*PAGE_SIZE
  for i = first + 1, math.min(#slots, first + PAGE_SIZE) do
    rows[#rows+1] = slot_row(slots[i])
  end
  if #rows == 0 then
    rows[1] = {n=G.UIT.R, config={align = 'cm', padding = 0.1}, nodes={
      {n=G.UIT.T, config={text = filter().empty, scale = 0.4, colour = G.C.UI.TEXT_LIGHT}},
    }}
  end
  return {n=G.UIT.ROOT, config={align = 'tm', padding = 0.05, colour = G.C.CLEAR}, nodes=rows}
end

-- Same footprint and colour as preview.build's panel, so the column doesn't jump.
local function message_def(text)
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.BLACK, minw = DETAIL_W, minh = DETAIL_H, r = 0.1}, nodes={
    {n=G.UIT.R, config={align = 'cm', padding = 0.2, maxw = DETAIL_W - 0.4}, nodes={
      {n=G.UIT.T, config={id = 'saveslots_detail_msg', text = text, scale = 0.4, colour = G.C.UI.TEXT_LIGHT}},
    }},
  }}
end

-- preview.build's ROOT framed in the message panel's outer size, so selecting
-- a slot, an unreadable slot or nothing never resizes the panel. A nested ROOT
-- would reset its origin (engine/ui.lua calculate_xywh), so it becomes a column.
local function panel_def(def)
  local inner = {}
  for k, v in pairs(def) do inner[k] = v end
  inner.n = G.UIT.C
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.BLACK, minw = DETAIL_W, minh = DETAIL_H, r = 0.1}, nodes={inner}}
end

-- Word-wraps `text` into lines of at most `n` chars (a longer word is cut).
local function wrap(text, n)
  local lines, cur = {}, ''
  for word in tostring(text or ''):gmatch('%S+') do
    while #word > n do
      if cur ~= '' then lines[#lines+1] = cur; cur = '' end
      lines[#lines+1] = word:sub(1, n)
      word = word:sub(n + 1)
    end
    if cur == '' then cur = word
    elseif #cur + 1 + #word <= n then cur = cur..' '..word
    else lines[#lines+1] = cur; cur = word end
  end
  if cur ~= '' then lines[#lines+1] = cur end
  return lines
end

-- The target/notes editor, in the preview's place and outer size. Its input is
-- the only 'select_text_input' in this box; editor_hook() hooks it on open.
local function editor_def(slot)
  local ed = EDIT[state.editing]
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.BLACK, minw = DETAIL_W, minh = DETAIL_H, r = 0.1}, nodes={
    {n=G.UIT.C, config={align = 'cm', padding = 0.15}, nodes={
      {n=G.UIT.R, config={align = 'cm'}, nodes={
        {n=G.UIT.T, config={text = ed.title, scale = 0.6, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
      }},
      {n=G.UIT.R, config={align = 'cm', maxw = DETAIL_W - 0.6}, nodes={
        {n=G.UIT.T, config={text = slot.name or '?', scale = 0.4, colour = G.C.JOKER_GREY}},
      }},
      {n=G.UIT.R, config={align = 'cm', padding = 0.1}, nodes={
        create_text_input({w = DETAIL_W - 0.8, h = 0.6, max_length = ed.max, extended_corpus = true,
          text_scale = ed.scale, ref_table = state, ref_value = 'edit_text', prompt_text = ed.prompt,
          callback = function() G.FUNCS.saveslots_edit_return() end}),
      }},
      {n=G.UIT.R, config={align = 'cm'}, nodes={
        {n=G.UIT.T, config={text = 'Up to '..ed.max..' characters. Enter saves, an empty '..ed.prompt:lower()
          ..' clears it.', scale = 0.3, colour = G.C.UI.TEXT_LIGHT}},
      }},
    }},
  }}
end

-- One labelled block of the meta column: a small title, the text (wrapped, or
-- `none` greyed out) on a dark plate, and an optional Edit button.
local function meta_block(id, title, text, none, fn)
  local lines = text and wrap(text, META_CHARS) or {}
  local rows = {}
  for i, l in ipairs(lines) do
    rows[i] = {n=G.UIT.R, config={align = 'cm', maxw = META_W - 0.4}, nodes={
      {n=G.UIT.T, config={id = id..'_'..i, text = l, scale = 0.34, colour = G.C.WHITE, shadow = true}},
    }}
  end
  if #rows == 0 then
    rows[1] = {n=G.UIT.R, config={align = 'cm'}, nodes={
      {n=G.UIT.T, config={id = id..'_none', text = none, scale = 0.32, colour = G.C.UI.TEXT_INACTIVE}},
    }}
  end
  local nodes = {
    {n=G.UIT.R, config={align = 'cm'}, nodes={
      {n=G.UIT.T, config={text = title, scale = 0.32, colour = G.C.UI.TEXT_LIGHT}},
    }},
    {n=G.UIT.R, config={align = 'cm', padding = 0.08, r = 0.1, minw = META_W - 0.3, minh = 0.5,
        colour = G.C.UI.TRANSPARENT_DARK}, nodes={
      {n=G.UIT.C, config={align = 'cm'}, nodes=rows},
    }},
  }
  if fn then
    nodes[#nodes+1] = {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
      UIBox_button({label = {'Edit'}, button = fn, colour = G.C.GREEN, minw = 1.4, minh = 0.45, scale = 0.34}),
    }}
  end
  return {n=G.UIT.R, config={align = 'cm', padding = 0.06, r = 0.1, colour = G.C.L_BLACK, minw = META_W - 0.2}, nodes={
    {n=G.UIT.C, config={align = 'cm'}, nodes=nodes},
  }}
end

-- The last share code copied for `slot`, cut to CODE_CHARS: a line under the
-- Favorite / Share buttons (an empty row when there is none, so nothing moves).
local function share_line(slot)
  local code = state.share and state.share.id == slot.id and state.share.code
  if not code then return {n=G.UIT.R, config={align = 'cm'}, nodes={}} end
  local shown = #code > CODE_CHARS and code:sub(1, CODE_CHARS)..'...' or code
  return {n=G.UIT.R, config={align = 'cm', padding = 0.03, maxw = META_W - 0.4}, nodes={
    {n=G.UIT.T, config={id = 'saveslots_meta_code', text = shown, scale = 0.3, colour = G.C.UI.TEXT_LIGHT}},
  }}
end

-- The meta column for the selected slot (or an empty panel), always META_W x DETAIL_H.
local function meta_def(slot)
  local nodes = {}
  if slot then
    local m = slot.meta or {}
    local kind = m.kind or 'save'
    -- A label, not a pill: a coloured box here would read as another button.
    nodes[#nodes+1] = {n=G.UIT.R, config={align = 'cm', padding = 0.06, r = 0.1, colour = G.C.L_BLACK,
        minw = META_W - 0.2}, nodes={
      {n=G.UIT.C, config={align = 'cm'}, nodes={
        {n=G.UIT.R, config={align = 'cm'}, nodes={
          {n=G.UIT.T, config={text = 'Kind', scale = 0.32, colour = G.C.UI.TEXT_LIGHT}},
        }},
        {n=G.UIT.R, config={align = 'cm'}, nodes={
          -- lightened: the row colours are too dark for text on the L_BLACK plate
          {n=G.UIT.T, config={id = 'saveslots_meta_kind', text = KIND_LABEL[kind] or tostring(kind), scale = 0.45,
            colour = lighten(kind_colour(kind), 0.3), shadow = true}},
        }},
        {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
          UIBox_button({id = 'saveslots_favorite', label = {m.favorite == true and 'Unfavorite' or 'Favorite'},
            button = 'saveslots_favorite', colour = m.favorite == true and darken(G.C.GOLD, 0.3) or G.C.GOLD,
            minw = 1.5, minh = 0.45, scale = 0.32, col = true}),
          {n=G.UIT.B, config={w = 0.1, h = 0.1}},
          UIBox_button({id = 'saveslots_share', label = {'Share'}, button = 'saveslots_share', colour = G.C.BLUE,
            minw = 1.3, minh = 0.45, scale = 0.32, col = true}),
        }},
        share_line(slot),
      }},
    }}
    local editable = not state.editing
    nodes[#nodes+1] = meta_block('saveslots_meta_target', 'Target', m.target, 'No target',
      editable and 'saveslots_edit_target' or nil)
    nodes[#nodes+1] = meta_block('saveslots_meta_notes', 'Notes', m.notes, 'No notes',
      editable and 'saveslots_edit_notes' or nil)
    if kind == 'hunt' then
      local origin = type(m.origin) == 'table' and m.origin or {}
      nodes[#nodes+1] = meta_block('saveslots_meta_hunt', 'Hunt filter',
        type(origin.filter_name) == 'string' and origin.filter_name or nil, 'Unknown')
    end
  else
    nodes[1] = {n=G.UIT.R, config={align = 'cm'}, nodes={
      {n=G.UIT.T, config={text = 'Details', scale = 0.4, colour = G.C.UI.TEXT_INACTIVE}},
    }}
  end
  return {n=G.UIT.ROOT, config={align = slot and 'tm' or 'cm', colour = G.C.BLACK, minw = META_W, minh = DETAIL_H,
      r = 0.1, padding = 0.1}, nodes=nodes}
end

-- Share codes -------------------------------------------------------------------

local function name_of(set, key)
  if key == nil then return '?' end
  local ok, s = pcall(localize, {type = 'name_text', set = set, key = key})
  if ok and type(s) == 'string' and s ~= '' and s ~= 'ERROR' then return s end
  return tostring(key)
end

-- Vanilla's run-setup rule, as the Finder applies it (UI_definitions.lua:5465-5468,
-- button_callbacks.lua:2058): a deck the profile has unlocked, and a stake up to one
-- above the highest it has won with that deck (all of them on an all-unlocked profile).
local function locked_reason(deck, stake)
  local p = G.PROFILES and G.PROFILES[G.SETTINGS.profile]
  local all = p and p.all_unlocked or false
  local b = G.P_CENTERS[deck]
  if not (b and b.set == 'Back') then return 'Unknown deck '..tostring(deck) end
  if not (b.unlocked or all) then return name_of('Back', deck)..' is locked' end
  local n = #G.P_CENTER_POOLS.Stake
  local max = n
  if not all then
    local ok, won = pcall(get_deck_win_stake, deck)
    max = math.max(1, math.min(n, (ok and tonumber(won) or 0) + 1))
  end
  if stake > max then
    return name_of('Stake', (G.P_CENTER_POOLS.Stake[stake] or {}).key)..' is locked for '..name_of('Back', deck)
  end
end

-- Vanilla's clipboard pair (copy_seed / paste_seed): the rig sets F_LOCAL_CLIPBOARD.
local function clipboard_write(text)
  if G.F_LOCAL_CLIPBOARD then G.CLIPBOARD = text else love.system.setClipboardText(text) end
end

local function clipboard_read()
  local ok, text = pcall(function()
    return (G.F_LOCAL_CLIPBOARD and G.CLIPBOARD or love.system.getClipboardText()) or ''
  end)
  return ok and type(text) == 'string' and text or ''
end

-- The share code of a slot: seed and stake from its summary, the deck key from the
-- run itself (the summary only has the deck's display name).
local function slot_code(slot)
  local run, err = store.read(slot.id)
  if not run then return nil, 'this save could not be read ('..tostring(err)..')' end
  local sm, m = slot.summary or {}, slot.meta or {}
  local back = type(run.BACK) == 'table' and run.BACK or {}
  local origin = type(m.origin) == 'table' and m.origin or {}
  return sharecode.encode({
    seed = sm.seed, deck = back.key, stake = sm.stake, notes = m.notes,
    filter = origin.filter, route = m.route,
  })
end

-- One "Label  value" line of the import panel.
local function import_line(id, label, value)
  return {n=G.UIT.R, config={align = 'cm', padding = 0.04, maxw = DETAIL_W - 0.6}, nodes={
    {n=G.UIT.T, config={text = label..': ', scale = 0.4, colour = G.C.UI.TEXT_LIGHT}},
    {n=G.UIT.T, config={id = id, text = value, scale = 0.4, colour = G.C.WHITE, shadow = true}},
  }}
end

-- The import panel, in the preview's place and outer size: the decoded code, or
-- the decode error.
local function import_def()
  local imp = state.import
  local rows = {
    {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
      {n=G.UIT.T, config={text = 'Import code', scale = 0.6, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
    }},
  }
  if imp.t then
    local t = imp.t
    rows[#rows+1] = import_line('saveslots_import_seed', 'Seed', t.seed)
    rows[#rows+1] = import_line('saveslots_import_deck', 'Deck', name_of('Back', t.deck))
    rows[#rows+1] = import_line('saveslots_import_stake', 'Stake',
      name_of('Stake', (G.P_CENTER_POOLS.Stake[t.stake] or {}).key))
    rows[#rows+1] = {n=G.UIT.R, config={align = 'cm', padding = 0.04}, nodes={
      {n=G.UIT.T, config={text = 'Notes', scale = 0.36, colour = G.C.UI.TEXT_LIGHT}},
    }}
    local lines = t.notes and t.notes ~= '' and wrap(t.notes, 40) or {}
    local notes = {}
    for i, l in ipairs(lines) do
      notes[i] = {n=G.UIT.R, config={align = 'cm', maxw = DETAIL_W - 1}, nodes={
        {n=G.UIT.T, config={id = 'saveslots_import_notes_'..i, text = l, scale = 0.34, colour = G.C.WHITE, shadow = true}},
      }}
    end
    if #notes == 0 then
      notes[1] = {n=G.UIT.R, config={align = 'cm'}, nodes={
        {n=G.UIT.T, config={id = 'saveslots_import_notes_none', text = 'No notes', scale = 0.32,
          colour = G.C.UI.TEXT_INACTIVE}},
      }}
    end
    rows[#rows+1] = {n=G.UIT.R, config={align = 'cm', padding = 0.1, r = 0.1, minw = DETAIL_W - 1.2, minh = 0.6,
        colour = G.C.UI.TRANSPARENT_DARK}, nodes={
      {n=G.UIT.C, config={align = 'cm'}, nodes=notes},
    }}
    local extra = {}
    if t.route then extra[#extra+1] = 'a route' end
    if t.filter then extra[#extra+1] = 'a filter' end
    if #extra > 0 then
      rows[#rows+1] = {n=G.UIT.R, config={align = 'cm', padding = 0.04}, nodes={
        {n=G.UIT.T, config={text = 'Also carries '..table.concat(extra, ' and '), scale = 0.3,
          colour = G.C.UI.TEXT_INACTIVE}},
      }}
    end
    rows[#rows+1] = {n=G.UIT.R, config={align = 'cm', padding = 0.04}, nodes={
      {n=G.UIT.T, config={text = 'Play starts an unseeded run on this seed', scale = 0.3, colour = G.C.UI.TEXT_LIGHT}},
    }}
  else
    rows[#rows+1] = {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
      {n=G.UIT.T, config={text = 'The clipboard holds no valid share code', scale = 0.36, colour = G.C.UI.TEXT_LIGHT}},
    }}
    for i, l in ipairs(wrap(imp.err, 40)) do
      rows[#rows+1] = {n=G.UIT.R, config={align = 'cm', maxw = DETAIL_W - 1}, nodes={
        {n=G.UIT.T, config={id = i == 1 and 'saveslots_import_error' or 'saveslots_import_error_'..i, text = l,
          scale = 0.4, colour = lighten(G.C.RED, 0.2), shadow = true}},
      }}
    end
  end
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.BLACK, minw = DETAIL_W, minh = DETAIL_H, r = 0.1}, nodes={
    {n=G.UIT.C, config={align = 'cm', padding = 0.15}, nodes=rows},
  }}
end

-- The right-hand panel as a live UIBox. preview.build (and building its
-- definition into a UIBox) is guarded: any error shows a message instead, and
-- the list stays usable.
local function detail_box(slots, parent)
  local cfg = {offset = {x = 0, y = 0}, align = 'cm', parent = parent}
  if state.import then return UIBox{definition = import_def(), config = cfg} end
  local slot = state.selected and find_slot(slots, state.selected)
  if not slot then
    local text = #slots == 0 and ((filter().favorite or filter().kind and filter().kind ~= 'save') and filter().empty
      or in_run() and 'Save the current run to create a slot' or 'No saves yet')
      or 'Select a save'
    return UIBox{definition = message_def(text), config = cfg}
  end
  if state.editing then return UIBox{definition = editor_def(slot), config = cfg} end
  local run, err = store.read(slot.id)
  if not run then
    print('[SaveSlots] slot '..tostring(slot.id)..' unreadable: '..tostring(err))
    return UIBox{definition = message_def('Preview unavailable'), config = cfg}
  end
  local ok, box = pcall(function()
    local def = preview.build(run, slot.summary)
    if type(def) ~= 'table' then error('preview.build returned '..type(def)) end
    return UIBox{definition = panel_def(def), config = cfg}
  end)
  if ok then return box end
  print('[SaveSlots] preview failed: '..tostring(box))
  return UIBox{definition = message_def('Preview unavailable'), config = cfg}
end

-- `label` is a string, or a list of lines drawn smaller (a long label in a
-- button this narrow would otherwise be squeezed to an unreadable size).
local function button(label, fn, colour, id)
  local lines = type(label) == 'table' and label or {label}
  return UIBox_button({id = id, label = lines, button = fn, colour = colour, col = true,
    minw = ACTION_W, minh = 0.66, scale = #lines > 1 and 0.3 or 0.4})
end

local function actions_def(slots)
  local nodes = {}
  if state.import then
    if state.import.t then nodes[1] = button('Play', 'saveslots_import_play', G.C.BLUE) end
    nodes[#nodes+1] = button('Cancel', 'saveslots_import_cancel', G.C.RED)
  elseif state.editing and state.selected and find_slot(slots, state.selected) then
    nodes[1] = button('Save', 'saveslots_edit_save', G.C.GREEN)
    nodes[2] = button('Cancel', 'saveslots_edit_cancel', G.C.RED)
  elseif state.selected and find_slot(slots, state.selected) then
    nodes[#nodes+1] = button('Load', 'saveslots_load', G.C.BLUE)
    if in_run() then nodes[#nodes+1] = button('Overwrite', 'saveslots_overwrite', G.C.ORANGE) end
    nodes[#nodes+1] = button('Rename', 'saveslots_rename', G.C.GREEN)
    local armed = state.confirm_delete == state.selected
    nodes[#nodes+1] = button(armed and {'Confirm', 'delete'} or 'Delete', 'saveslots_delete',
      armed and darken(G.C.RED, 0.25) or G.C.RED, 'saveslots_delete')
  end
  return {n=G.UIT.ROOT, config={align = 'cm', padding = 0.08, colour = G.C.CLEAR, minh = 0.8}, nodes=nodes}
end

-- The kind filter. Its arrows get their own button name, forwarding to vanilla's
-- option_cycle: it sits above the page cycle, and 'option_cycle' must keep
-- finding the page cycle first (see Rules). The controller clicks cycle
-- arrows by position (focused.children[1]/[3]), not by name, so pads still work.
local function kind_cycle()
  local labels = {}
  for i, f in ipairs(FILTERS) do labels[i] = f.label end
  local t = create_option_cycle({id = 'saveslots_kind', scale = 0.8, h = 0.3, w = 3.2, options = labels,
    opt_callback = 'saveslots_kind', current_option = state.kind, colour = G.C.RED, no_pips = true})
  local function retarget(node)
    if type(node) ~= 'table' then return end
    if node.config and node.config.button == 'option_cycle' then node.config.button = 'saveslots_kind_cycle' end
    for _, child in ipairs(node.nodes or {}) do retarget(child) end
  end
  retarget(t)
  return t
end

local function overlay_def(slots)
  local pages = {}
  for i = 1, page_count(slots) do
    pages[i] = localize('k_page')..' '..i..'/'..page_count(slots)
  end

  local left = {
    {n=G.UIT.R, config={align = 'cm'}, nodes={kind_cycle()}},
    {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
      create_text_input({w = LIST_W - 0.2, max_length = NAME_MAX, extended_corpus = true,
        ref_table = state, ref_value = 'name', prompt_text = 'Save name'}),
    }},
  }
  if in_run() then
    left[#left+1] = {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
      UIBox_button({label = {'Save current run'}, button = 'saveslots_save_new', colour = G.C.GREEN,
        minw = LIST_W - 0.2, minh = 0.6, scale = 0.42}),
    }}
  end
  left[#left+1] = {n=G.UIT.R, config={align = 'tm', minh = PAGE_SIZE*(ROW_H + 0.14) + 0.1, minw = LIST_W}, nodes={
    {n=G.UIT.O, config={id = 'saveslots_list', object = Moveable()}},
  }}
  left[#left+1] = {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
    create_option_cycle({id = 'saveslots_page', scale = 0.8, h = 0.3, w = 2.8, options = pages,
      cycle_shoulders = true, opt_callback = 'saveslots_page', current_option = state.page,
      colour = G.C.RED, no_pips = true, focus_args = {snap_to = true}}),
  }}

  return create_UIBox_generic_options({
    back_func = in_run() and 'options' or 'exit_overlay_menu',
    contents = {
      {n=G.UIT.C, config={align = 'tm', padding = 0.05}, nodes=left},
      {n=G.UIT.C, config={id = 'saveslots_right', align = 'tm', padding = 0.05, minw = DETAIL_W}, nodes={
        {n=G.UIT.R, config={align = 'cm', minw = DETAIL_W, minh = DETAIL_H}, nodes={
          {n=G.UIT.O, config={id = 'saveslots_detail', object = Moveable()}},
        }},
        {n=G.UIT.R, config={align = 'cm'}, nodes={
          {n=G.UIT.O, config={id = 'saveslots_actions', object = Moveable()}},
        }},
      }},
      {n=G.UIT.C, config={align = 'tm', padding = 0.05}, nodes={
        {n=G.UIT.R, config={align = 'cm', minw = META_W, minh = DETAIL_H}, nodes={
          {n=G.UIT.O, config={id = 'saveslots_meta', object = Moveable()}},
        }},
        -- 0.2: the practice composer (practice.lua registers the callback). Beside the
        -- action row, so the overlay doesn't grow.
        {n=G.UIT.R, config={align = 'cm', padding = 0.08, minh = 0.8}, nodes={
          UIBox_button({id = 'saveslots_practice', label = {'New practice'}, button = 'saveslots_practice',
            colour = G.C.GREEN, minw = (META_W - 0.3)/2, minh = 0.66, scale = 0.34, col = true}),
          {n=G.UIT.B, config={w = 0.1, h = 0.1}},
          UIBox_button({id = 'saveslots_import', label = {'Import code'}, button = 'saveslots_import',
            colour = G.C.BLUE, minw = (META_W - 0.3)/2, minh = 0.66, scale = 0.34, col = true}),
        }},
      }},
    },
  })
end

-- Swaps the UIBox inside one of our G.UIT.O slots, as change_challenge_list_page does.
local function swap(id, make)
  local ov = G.OVERLAY_MENU
  local node = ov and ov:get_UIE_by_ID(id)
  if not node then return end
  if node.config.object then node.config.object:remove() end
  node.config.object = make(node)
  ov:recalculate()
end

local function refresh_detail(slots)
  swap('saveslots_detail', function(node) return detail_box(slots, node) end)
end

local function refresh_list(slots)
  swap('saveslots_list', function(node)
    return UIBox{definition = list_page_def(slots), config = {offset = {x = 0, y = 0}, align = 'cm', parent = node}}
  end)
end

local function refresh_meta(slots)
  swap('saveslots_meta', function(node)
    local slot = state.selected and find_slot(slots, state.selected)
    return UIBox{definition = meta_def(slot), config = {offset = {x = 0, y = 0}, align = 'cm', parent = node}}
  end)
end

local function refresh_actions(slots)
  swap('saveslots_actions', function(node)
    return UIBox{definition = actions_def(slots), config = {offset = {x = 0, y = 0}, align = 'cm', parent = node}}
  end)
end

-- (Re)builds the whole overlay from state. `animate` = false snaps it into
-- place, so a rebuild after a mutation doesn't slide in from below again.
-- The hook on the editor's input, taken on open so typing goes straight in.
local function editor_hook()
  local node = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('saveslots_detail')
  local box = node and node.config.object
  local input = box and box.get_UIE_by_ID and box:get_UIE_by_ID('text_input')
  if input then G.FUNCS.select_text_input(input) end
end

local function open(animate)
  local slots = list_slots()
  state.share = nil   -- any rebuild follows a change that could make the code stale
  clamp_state(slots)
  if not state.selected then state.editing = nil end
  G.SETTINGS.paused = true
  G.FUNCS.overlay_menu{definition = overlay_def(slots)}
  if not animate and G.OVERLAY_MENU then G.OVERLAY_MENU:hard_set_VT() end
  refresh_list(slots)
  refresh_detail(slots)
  refresh_actions(slots)
  refresh_meta(slots)
  if state.editing then editor_hook() end
end

local function selected_slot()
  local slots = list_slots()
  return state.selected and find_slot(slots, state.selected), slots
end

-- Drops the text-input hook if it points into a box that is going away (the
-- editor), so no key press lands on a removed input.
local function release_editor_hook()
  local hook = G.CONTROLLER and G.CONTROLLER.text_input_hook
  if not hook then return end
  local node = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('saveslots_detail')
  local box = node and node.config.object
  if hook.REMOVED or (box and hook.UIBox == box) then G.CONTROLLER.text_input_hook = nil end
end

-- Leaves edit mode (without saving) and closes the import panel. Returns true
-- when either was open.
local function close_editor()
  local was_import = state.import ~= nil
  state.import = nil
  if not state.editing then return was_import end
  release_editor_hook()
  state.editing = nil
  state.edit_text = ''
  return true
end

function ui.install()
  if installed then return end
  installed = true

  G.FUNCS.saveslots_open = function(e)
    local import_err = nil
    if not imported then
      local ok, n, err = pcall(store.import_brainstorm)
      if ok and type(n) == 'number' then
        if n > 0 then state.page = 1 end
        if err == nil then
          imported = true
        elseif tostring(err):find('^partial') then
          -- n, 'partial: …': some copies failed; the flag stays unset for a retry.
          import_err = 'Some Brainstorm slots could not be imported'
          print('[SaveSlots] Brainstorm import partial ('..n..' imported): '..tostring(err))
        else
          -- Every copy was made; only the flag write failed. Nothing to tell the player:
          -- the next open finds the copies and sets the flag.
          print('[SaveSlots] Brainstorm import done, flag not saved: '..tostring(err))
        end
      else
        import_err = 'Brainstorm import failed - will retry'
        print('[SaveSlots] Brainstorm import failed: '..tostring(ok and (err or 'no result') or n))
      end
    end
    state.confirm_delete = nil
    close_editor()
    open(true)
    if import_err then alert(import_err) end
  end

  G.FUNCS.saveslots_select = function(e)
    local id = e and e.config and e.config.ref_table and e.config.ref_table.id
    if not id or not G.OVERLAY_MENU then return end
    state.confirm_delete = nil
    local was_editing = close_editor()
    if state.selected == id and not was_editing then refresh_actions(list_slots()); return end
    local old = state.selected and G.OVERLAY_MENU:get_UIE_by_ID('saveslots_row_'..state.selected)
    if old then old.config.chosen = nil end
    e.config.chosen = 'vert'
    state.selected = id
    local slots = list_slots()
    refresh_detail(slots)
    refresh_actions(slots)
    refresh_meta(slots)
  end

  G.FUNCS.saveslots_page = function(args)
    if not (args and args.cycle_config) then return end
    state.page = args.cycle_config.current_option
    state.confirm_delete = nil
    local was_editing = close_editor()
    local slots = list_slots()
    clamp_state(slots)
    refresh_list(slots)
    refresh_actions(slots)
    if was_editing then refresh_detail(slots); refresh_meta(slots) end
  end

  -- The kind filter: vanilla's cycle behind our own button name (kind_cycle).
  G.FUNCS.saveslots_kind_cycle = function(e) return G.FUNCS.option_cycle(e) end

  -- A new filter changes the page count, so the overlay is rebuilt. The selection
  -- survives only if the filter still lists it (clamp_state).
  G.FUNCS.saveslots_kind = function(args)
    if not (args and args.cycle_config) then return end
    state.kind = args.cycle_config.current_option
    state.page = 1
    state.confirm_delete = nil
    close_editor()
    open(false)
  end

  G.FUNCS.saveslots_save_new = function(e)
    state.confirm_delete = nil
    close_editor()
    local run = in_run() and checkpoint.get()
    if not run then
      alert('Nothing to save yet - play until the next autosave')
      return
    end
    local name = trim(state.name)
    local id, err = store.save(run, name)
    if not id then
      alert('Save failed: '..tostring(err))
      return
    end
    state.name = ''
    state.selected = id
    state.page = 1
    -- A new slot is a plain save: a filter that hides those would hide it.
    if filter().favorite or (filter().kind and filter().kind ~= 'save') then state.kind = 1 end
    open(false)
    local slot = find_slot(store.list(), id)
    alert('Saved '..(slot and slot.name or ''))
  end

  G.FUNCS.saveslots_load = function(e)
    state.confirm_delete = nil
    local slot = selected_slot()
    if not slot then return end
    local run = store.read(slot.id)
    local ok, err = run and checkpoint.load_run(run)
    if not ok then
      refresh_actions(list_slots())
      alert(run and ('Load failed: '..tostring(err)) or 'This save could not be read')
    end
  end

  G.FUNCS.saveslots_overwrite = function(e)
    state.confirm_delete = nil
    local slot = selected_slot()
    if not slot or not in_run() then return end
    local run = checkpoint.get()
    if not run then
      refresh_actions(list_slots())
      alert('Nothing to save yet - play until the next autosave')
      return
    end
    local id, err = store.save(run, nil, slot.id)
    -- saved_at is refreshed, so the slot is now the newest: follow it to its page.
    if id then page_to_selected(list_slots()) end
    open(false)
    alert(id and ('Overwrote '..slot.name) or ('Save failed: '..tostring(err)))
  end

  G.FUNCS.saveslots_rename = function(e)
    state.confirm_delete = nil
    local slot = selected_slot()
    local name = trim(state.name)
    if not slot or name == '' then
      refresh_actions(list_slots())
      return
    end
    local ok, err = store.rename(slot.id, name)
    if ok then state.name = '' end
    open(false)
    alert(ok and ('Renamed to '..name) or ('Rename failed: '..tostring(err)))
  end

  G.FUNCS.saveslots_delete = function(e)
    local slot, slots = selected_slot()
    if not slot then return end
    if state.confirm_delete ~= slot.id then
      state.confirm_delete = slot.id
      refresh_actions(slots)
      return
    end
    state.confirm_delete = nil
    local ok, err = store.delete(slot.id)
    if ok then state.selected = nil end
    open(false)
    alert(ok and ('Deleted '..slot.name) or ('Delete failed: '..tostring(err)))
  end

  -- Pins/unpins the selected slot. The list reorders (favorites first), so the page
  -- follows the slot; under the Favorites filter an unfavorited slot drops out.
  G.FUNCS.saveslots_favorite = function(e)
    local slot = selected_slot()
    if not slot then return end
    state.confirm_delete = nil
    close_editor()
    local fav = not is_favorite(slot)
    local ok, err = store.set_meta(slot.id, {favorite = fav})
    if ok then page_to_selected(list_slots()) end
    open(false)
    alert(ok and ((fav and 'Favorited ' or 'Unfavorited ')..slot.name) or ('Favorite failed: '..tostring(err)))
  end

  -- Target / notes. The editor opens in the preview's place, its input hooked.
  local function edit(field)
    local slot = selected_slot()
    if not slot or not G.OVERLAY_MENU then return end
    state.confirm_delete = nil
    release_editor_hook()
    state.import = nil
    state.editing = field
    state.edit_text = type(slot.meta) == 'table' and type(slot.meta[field]) == 'string' and slot.meta[field] or ''
    local slots = list_slots()
    refresh_detail(slots)
    refresh_actions(slots)
    refresh_meta(slots)
    editor_hook()
  end
  G.FUNCS.saveslots_edit_target = function(e) edit('target') end
  G.FUNCS.saveslots_edit_notes = function(e) edit('notes') end

  -- Writes the editor's text to the selected slot. Returns the alert to show.
  local function commit()
    local field, slot = state.editing, selected_slot()
    if not (field and slot) then return nil end
    local text = trim(state.edit_text)
    local ok, err = store.set_meta(slot.id, {[field] = text})
    local label = EDIT[field].prompt
    if not ok then return 'Save failed: '..tostring(err) end
    if text == '' then return label..' cleared' end
    return label..' saved'
  end

  G.FUNCS.saveslots_edit_save = function(e)
    local msg = commit()
    close_editor()
    open(false)
    if msg then alert(msg) end
  end

  -- Return in the editor's input (create_text_input's callback). Vanilla still
  -- touches the hooked input after this returns, so the rebuild waits a frame.
  G.FUNCS.saveslots_edit_return = function()
    local msg = commit()
    state.editing = nil
    state.edit_text = ''
    G.E_MANAGER:add_event(Event({
      blockable = false, blocking = false,
      func = function()
        if G.OVERLAY_MENU and not state.editing then
          open(false)
          if msg then alert(msg) end
        end
        return true
      end
    }))
  end

  G.FUNCS.saveslots_edit_cancel = function(e)
    close_editor()
    open(false)
  end

  -- Share codes (0.3, D3) ---------------------------------------------------------

  G.FUNCS.saveslots_share = function(e)
    local slot = selected_slot()
    if not slot or not G.OVERLAY_MENU then return end
    state.confirm_delete = nil
    local code, err = slot_code(slot)
    if not code then
      refresh_actions(list_slots())
      alert('Share failed: '..tostring(err):gsub('^sharecode: ', ''))
      play_sound('cancel')
      return
    end
    clipboard_write(code)
    state.share = {id = slot.id, code = code}
    local slots = list_slots()
    refresh_meta(slots)
    refresh_actions(slots)
    alert('Share code copied')
  end

  G.FUNCS.saveslots_import = function(e)
    if not G.OVERLAY_MENU then return end
    state.confirm_delete = nil
    close_editor()
    local t, err = sharecode.decode(clipboard_read())
    state.import = t and {t = t} or {err = tostring(err)}
    local slots = list_slots()
    refresh_detail(slots)
    refresh_actions(slots)
    refresh_meta(slots)
    if not t then play_sound('cancel') end
  end

  G.FUNCS.saveslots_import_cancel = function(e)
    close_editor()
    open(false)
  end

  -- An unseeded run on the code's seed, deck and stake, as the Finder's Play starts
  -- one (the Game:start_run wrap below clears `seeded`).
  G.FUNCS.saveslots_import_play = function(e)
    local t = state.import and state.import.t
    if not t then return end
    local locked = locked_reason(t.deck, t.stake)
    if locked then
      alert('Cannot play: '..locked)
      play_sound('cancel')
      return
    end
    state.import = nil
    if G.GAME then G.GAME.viewed_back = Back(G.P_CENTERS[t.deck]) end
    if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() end
    unseed = t.seed
    G.FUNCS.start_run(nil, {seed = t.seed, stake = t.stake})
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
end

return ui
