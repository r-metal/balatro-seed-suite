-- The Save Slots overlay and its button callbacks. Contract: docs/SPEC.md.
--
-- Layout (modelled on vanilla G.UIDEF.challenge_list + challenge_list_page +
-- G.FUNCS.change_challenge_description)
--   left    the kind filter cycle (0.2: All / Saves / Checkpoints / Practice /
--           Hunts / Favorites) and beside it the folder cycle (0.3.4: All folders /
--           each folder in use / Unfiled; the two AND together), the name input
--           with "Save" beside it (runs only), the search input (0.3.4), the paged
--           slot list (PAGE_SIZE rows, favorites first then newest first, coloured
--           by kind, a gold dot on favorites) and the page cycle
--   right   preview.build(run, summary) for the selected slot, action buttons
--           below it: Load, Overwrite (runs only), Rename, Delete. While a target,
--           notes or folder edit is open, the preview is replaced by the editor
--           (same outer size) and the buttons by Save / Cancel. The folder editor
--           also offers the folders in use as buttons (up to PICK_MAX): one click
--           puts that name in its input.
--   meta    (0.2) a column beside the preview: the slot's kind with the
--           Favorite / Unfavorite toggle, target, notes and (0.3.4) folder, each
--           with an Edit button beside its title, and a hunt's filter name. Below
--           it, level with the action row, "New practice" opens the practice
--           composer (practice.lua), "Import code" (0.3) reads a share code and
--           "Backups" (0.4) opens the backups panel; three to a row, the two longer
--           labels on two lines, so the row keeps its 0.3.4 width.
--   search  (0.3.4) the list follows the search text as it is typed: store.list's
--           query (name, seed, deck, notes, target, folder; a plain substring,
--           any case), ANDed with the kind and folder cycles. A new query goes back
--           to page 1; with no match the list says No saves match "<q>".
--   share   (0.3, D3) "Share" beside Favorite copies the slot's share code
--           (sharecode.encode) to the clipboard and shows it, truncated, on a
--           line under the buttons. "Import code" decodes the clipboard into a
--           panel in the preview's place: seed / deck / stake / notes, with
--           Play / Cancel in the action row (or the decode error and Cancel).
--   backups (0.4, T-374; saveslots.backup does the work) a panel in the preview's
--           place and outer size, opened like the import panel: this profile's
--           backups, newest first, BACKUP_ROWS a page (a page cycle past that), one
--           row each: date and time, kind (Automatic / Manual / Before restore) and
--           the size of what it holds (", no unlocks" when it has no meta.jkr), and a
--           message line. The action row: Back up now, and on a selected backup
--           Restore and Delete (each arms "Confirm ..." first, as Delete does for a
--           slot), and Close. Restore works from the main menu only: elsewhere its
--           press says so and arms nothing. A restore reloads the profile (vanilla's
--           profile switch takes the overlay down with the old main menu), then the
--           overlay is built again with the panel open and "Profile restored".
--   The list, the preview, the buttons, the meta column, the page cycle and the
--   search input are UIBoxes inside G.UIT.O nodes ('saveslots_list',
--   'saveslots_detail', 'saveslots_actions', 'saveslots_meta', 'saveslots_pages',
--   'saveslots_search'), swapped in place like the challenge list does. Any
--   mutation rebuilds the whole overlay instead, keeping the filters, the search
--   text, the page and the selection (module state below). Typing a search is
--   not a mutation: it swaps the list and the page cycle only (a rebuild would
--   drop the search input's hook mid-word).
--
-- API
--   ui.install()               Registers G.FUNCS.saveslots_*. Runs once.
--   G.FUNCS.saveslots_open(e)  Opens the overlay; `e` may be nil. Its Back
--                              button returns to the pause menu in a run and
--                              closes the overlay on the main menu.
--
-- Buttons (G.FUNCS names, so the smoke rig can ctx.click them)
--   saveslots_save_new    ("Save") saves checkpoint.get() as a new slot named after
--                         the input
--   saveslots_select      row click; e.config.ref_table.id is the slot id
--   saveslots_page        page cycle callback
--   saveslots_load        checkpoint.load_run(store.read(selected))
--   saveslots_overwrite   store.save(checkpoint.get(), nil, selected)
--   saveslots_rename      store.rename(selected, input text); ignored when empty
--   saveslots_delete      first press arms ("Confirm delete"), second deletes.
--                         Every other action disarms it.
--   saveslots_kind_cycle  the kind filter's arrows (see own_cycle for why they
--                         aren't 'option_cycle'); saveslots_kind is its callback
--   saveslots_folder_cycle the folder filter's arrows, likewise; saveslots_folder
--                         is its callback. When its folder has no slot left, it
--                         falls back to All folders.
--   saveslots_edit_target / saveslots_edit_notes / saveslots_edit_folder
--                         open the editor for the selected slot, its text input
--                         already hooked (TARGET_MAX / NOTES_MAX / FOLDER_MAX chars)
--   saveslots_folder_pick a folder button in the folder editor; e.config.ref_table.folder
--                         goes into the input (still hooked), Save or Return files it
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
--   saveslots_backups     (0.4) opens the backups panel (closing the editor or import)
--   saveslots_backup_select a backup row; e.config.ref_table.id is the backup id
--   saveslots_backup_now  backup.take('manual') once the game's pending profile save
--                         is on disk (backup.when_settled); selects the new backup
--   saveslots_backup_restore first press arms ("Confirm restore"), second calls
--                         backup.restore. Off the main menu it arms nothing and the
--                         panel says why. Any other panel action disarms it.
--   saveslots_backup_delete first press arms ("Confirm delete"), second deletes
--   saveslots_backups_close closes the panel
--   saveslots_backups_page_cycle / saveslots_backups_page the panel's page cycle
--                         (renamed arrows, as the kind cycle's)
--   saveslots_search_watch (a func, run every frame on the search row) swaps the
--                         list and the page cycle when the search text changed;
--                         saveslots_cursor is the name and search inputs' cursor
--                         (see steady_input)
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
--     kind-, folder- and backups-page-cycle arrows, the search input after the name
--     input, and the meta inputs existing only in the editor.
--   * One text input per UIBox: vanilla registers one element per draw_layer per
--     box, so a second input in a box hides the first. The search input has its
--     own box; the editor's input lives in the detail box. The name and search
--     inputs' cursors blink only while their own input is hooked (steady_input).
--   * vanilla text_input_key turns '0' into 'o'. ui.install calls
--     BHCore.install_digits(), and every input here (name, target, notes, folder,
--     search) sets bh_digits = true, so a typed '0' stays a '0'.
--   * The overlay keeps one outer size in every state (it fits the room: 0.3.4
--     used its spare width for the folder cycle and the search input, as its
--     height was already the room's). The meta column stays DETAIL_H for a hunt
--     with a target, notes, a folder and a share line (line caps in meta_def).
--     Neither a FOLDER_MAX folder in the cycle nor a full search widens the left
--     column, and the name input beside Save has room for NAME_MAX letters.
--   * The clipboard goes through vanilla's pair (copy_seed / paste_seed,
--     button_callbacks.lua:940 and 1816): G.CLIPBOARD when G.F_LOCAL_CLIPBOARD is
--     set, love.system's clipboard otherwise, so the rig can drive both ends.
--   * Import's Play is unseeded, like the Finder's: vanilla start_run marks any run
--     given a seed as `seeded` (game.lua:2163). The Game:start_run wrap installed
--     here clears it once start_run returns, only for the seed Play just started
--     (`unseed`), and never for a loaded savetext. The truncated code ends in
--     '...': the game font has no ellipsis glyph.
--   * Backups (0.4) never touch profile files here: saveslots.backup does, through
--     bhcore.fs. The panel keeps the detail panel's DETAIL_W x DETAIL_H in every
--     state (BACKUP_ROWS rows, the page cycle's row and the message line are
--     always reserved), so opening it never resizes the overlay.
local store = require('saveslots.store')
local checkpoint = require('saveslots.checkpoint')
local preview = require('saveslots.preview')
local sharecode = require('saveslots.sharecode')
local backup = require('saveslots.backup')

local ui = {}

local PAGE_SIZE = 8
local NAME_MAX = 24
-- Left column width. 0.3.4 widened it (from 4.6) to put the kind and folder cycles
-- side by side and the Save button beside the name input: the overlay already
-- filled the room's height, and had width to spare.
local LIST_W = 5.8
local SAVE_W = 1.0       -- "Save" beside the name input (runs only); the input keeps
                         -- LIST_W - 0.3 - SAVE_W, room for NAME_MAX average letters
local ROW_H = 0.62
-- The right column is this size in every state (message, preview, error), sized
-- to preview.build's panel, and the action row is kept inside DETAIL_W.
local DETAIL_W, DETAIL_H = 8, 7.3
local ACTION_W = 1.7     -- one action button; 4 of them + gaps fit in DETAIL_W
local META_W = 3.4       -- the meta column beside the preview, DETAIL_H high
local META_BUTTON_W = (META_W - 0.2)/3  -- New practice / Import code / Backups under it
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
  folder = {title = 'Edit folder', prompt = 'Folder', max = store.FOLDER_MAX, scale = 0.4},
}
local SEARCH_MAX = 20        -- the search input's length: even 20 of the widest letter fit LIST_W
local PICK_MAX = 12          -- existing folders offered as buttons in the folder editor
local PICK_COLS = 3

-- Survives rebuilds (and closing the overlay) for the rest of the session.
-- `name` is the text input's ref_table/ref_value; `edit_text` the editor's;
-- `query` the search input's. `kind` indexes FILTERS; `folder` is the folder
-- cycle's choice: nil (All folders), false (Unfiled) or a folder name. `editing`
-- is nil, 'target', 'notes' or 'folder'. `share` is the last code copied, {id,
-- code}; `import` the open import panel, {t = decoded} or {err = message};
-- `backups` the open backups panel, {page, selected, confirm_restore,
-- confirm_delete, msg, busy} (ids are backup ids).
local state = {name = '', page = 1, selected = nil, confirm_delete = nil, kind = 1,
  folder = nil, query = '', editing = nil, edit_text = '', share = nil, import = nil, backups = nil}
local shown_query = nil  -- the query the list was last built for (the search watch compares)
local unseed = nil       -- the seed Import's Play started, until its start_run clears `seeded`
local imported = false   -- set only once an import fully succeeded; a failure or partial retries next open
local installed = false

local function in_run() return G.STAGE == G.STAGES.RUN end

local function filter() return FILTERS[state.kind] or FILTERS[1] end

local function is_favorite(slot) return slot.meta and slot.meta.favorite == true end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

-- The search text as store.list matches it ('' when blank).
local function query() return trim(state.query) end

-- True when the folder cycle or the search box narrows the list.
local function narrowed() return state.folder ~= nil or query() ~= '' end

-- The slots the list shows: store.list under the current filter, folder and
-- search, favorites pinned first (each group keeps store.list's newest-first order).
local function list_slots()
  local all = store.list({kind = filter().kind, favorite = filter().favorite, folder = state.folder,
    query = state.query})
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
    -- Plain ASCII quotes: the game font has no curly ones.
    local text = query() ~= '' and 'No saves match "'..query()..'"'
      or state.folder ~= nil and 'Nothing matches these filters' or filter().empty
    rows[1] = {n=G.UIT.R, config={align = 'cm', padding = 0.1, maxw = LIST_W - 0.3}, nodes={
      {n=G.UIT.T, config={id = 'saveslots_list_empty', text = text, scale = 0.4, colour = G.C.UI.TEXT_LIGHT}},
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

-- The folder editor's extra rows: the folders already in use as buttons, so one
-- click puts a name in the input (saveslots_folder_pick). At most PICK_MAX; the
-- rest are typed.
local function folder_picks()
  local folders = store.folders()
  local rows = {
    {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
      {n=G.UIT.T, config={text = #folders > 0 and 'Existing folders' or 'No folders yet: type a name to make one',
        scale = 0.32, colour = G.C.UI.TEXT_LIGHT}},
    }},
  }
  local row
  for i = 1, math.min(#folders, PICK_MAX) do
    if (i - 1) % PICK_COLS == 0 then
      row = {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={}}
      rows[#rows+1] = row
    end
    local chosen = folders[i] == trim(state.edit_text)
    row.nodes[#row.nodes+1] = UIBox_button({id = 'saveslots_folder_pick_'..i, label = {folders[i]},
      button = 'saveslots_folder_pick', ref_table = {folder = folders[i]},
      colour = chosen and darken(G.C.BLUE, 0.3) or G.C.BLUE, minw = 2.3, minh = 0.5, scale = 0.32, col = true})
  end
  if #folders > PICK_MAX then
    rows[#rows+1] = {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
      {n=G.UIT.T, config={text = (#folders - PICK_MAX)..' more: type the name', scale = 0.3,
        colour = G.C.UI.TEXT_INACTIVE}},
    }}
  end
  return rows
end

-- The target/notes/folder editor, in the preview's place and outer size. Its
-- input is the only 'select_text_input' in this box; editor_hook() hooks it on open.
local function editor_def(slot)
  local ed = EDIT[state.editing]
  local rows = {
    {n=G.UIT.R, config={align = 'cm'}, nodes={
      {n=G.UIT.T, config={text = ed.title, scale = 0.6, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
    }},
    {n=G.UIT.R, config={align = 'cm', maxw = DETAIL_W - 0.6}, nodes={
      {n=G.UIT.T, config={text = slot.name or '?', scale = 0.4, colour = G.C.JOKER_GREY}},
    }},
    {n=G.UIT.R, config={align = 'cm', padding = 0.1}, nodes={
      create_text_input({w = DETAIL_W - 0.8, h = 0.6, max_length = ed.max, extended_corpus = true,
        bh_digits = true, text_scale = ed.scale, ref_table = state, ref_value = 'edit_text', prompt_text = ed.prompt,
        callback = function() G.FUNCS.saveslots_edit_return() end}),
    }},
    {n=G.UIT.R, config={align = 'cm'}, nodes={
      {n=G.UIT.T, config={text = 'Up to '..ed.max..' characters. Enter saves, an empty '..ed.prompt:lower()
        ..' clears it.', scale = 0.3, colour = G.C.UI.TEXT_LIGHT}},
    }},
  }
  if state.editing == 'folder' then
    for _, r in ipairs(folder_picks()) do rows[#rows+1] = r end
  end
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.BLACK, minw = DETAIL_W, minh = DETAIL_H, r = 0.1}, nodes={
    {n=G.UIT.C, config={align = 'cm', padding = 0.15}, nodes=rows},
  }}
end

-- One labelled block of the meta column: a small title (with an Edit button
-- beside it when `fn` is given; 0.3.4 moved it up from under the plate, so a hunt
-- with a target, notes and a folder still fits DETAIL_H), then the text on a dark
-- plate: wrapped, at most `max_lines` lines (the last one then ends in '...'), or
-- `none` greyed out.
local function meta_block(id, title, text, none, fn, max_lines)
  local lines = text and wrap(text, META_CHARS) or {}
  if max_lines and #lines > max_lines then
    local last = lines[max_lines]
    lines = {unpack(lines, 1, max_lines)}
    lines[max_lines] = (#last + 3 <= META_CHARS and last or last:sub(1, META_CHARS - 3))..'...'
  end
  local rows = {}
  for i, l in ipairs(lines) do
    -- (maxw: what fits inside the plate below, so wide glyphs never widen the column)
    rows[i] = {n=G.UIT.R, config={align = 'cm', maxw = META_W - 0.48}, nodes={
      {n=G.UIT.T, config={id = id..'_'..i, text = l, scale = 0.34, colour = G.C.WHITE, shadow = true}},
    }}
  end
  if #rows == 0 then
    rows[1] = {n=G.UIT.R, config={align = 'cm'}, nodes={
      {n=G.UIT.T, config={id = id..'_none', text = none, scale = 0.32, colour = G.C.UI.TEXT_INACTIVE}},
    }}
  end
  -- The title stays centred: an empty column the Edit button's width balances it.
  local EDIT_W = 0.9
  local header = {
    {n=G.UIT.C, config={align = 'cm', minw = META_W - 0.4 - (fn and 2*EDIT_W or 0)}, nodes={
      {n=G.UIT.T, config={text = title, scale = 0.32, colour = G.C.UI.TEXT_LIGHT}},
    }},
  }
  if fn then
    table.insert(header, 1, {n=G.UIT.C, config={minw = EDIT_W}, nodes={}})
    header[3] = UIBox_button({label = {'Edit'}, button = fn, colour = G.C.GREEN, minw = EDIT_W, minh = 0.36,
      scale = 0.3, col = true})
  end
  local nodes = {
    {n=G.UIT.R, config={align = 'cm'}, nodes=header},
    -- (META_W - 0.32: with the block's padding, as wide as the empty column's content,
    -- so the column is META_W with or without a slot selected)
    {n=G.UIT.R, config={align = 'cm', padding = 0.08, r = 0.1, minw = META_W - 0.32, minh = 0.5,
        colour = G.C.UI.TRANSPARENT_DARK}, nodes={
      {n=G.UIT.C, config={align = 'cm'}, nodes=rows},
    }},
  }
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
    -- Line caps keep the tallest column (a hunt with all four, and a share line)
    -- inside DETAIL_H: a target (24 chars) and a folder (16) never need more; 60
    -- chars of notes wrap to 4 lines unless long words waste the ends, and a filter
    -- name to 2. The editor shows the full text.
    nodes[#nodes+1] = meta_block('saveslots_meta_target', 'Target', m.target, 'No target',
      editable and 'saveslots_edit_target' or nil, 2)
    nodes[#nodes+1] = meta_block('saveslots_meta_notes', 'Notes', m.notes, 'No notes',
      editable and 'saveslots_edit_notes' or nil, 4)
    nodes[#nodes+1] = meta_block('saveslots_meta_folder', 'Folder', type(m.folder) == 'string' and m.folder or nil,
      'No folder', editable and 'saveslots_edit_folder' or nil, 1)
    if kind == 'hunt' then
      local origin = type(m.origin) == 'table' and m.origin or {}
      nodes[#nodes+1] = meta_block('saveslots_meta_hunt', 'Hunt filter',
        type(origin.filter_name) == 'string' and origin.filter_name or nil, 'Unknown', nil, 2)
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

-- Profile backups (0.4, T-374) ---------------------------------------------------

local BACKUP_ROWS = 7              -- backups per page of the panel
local BACKUP_ROW_W, BACKUP_ROW_H = DETAIL_W - 1, 0.5
local own_cycle                    -- (defined with the kind cycle, below)

-- "812 B", "14.2 KB".
local function size_text(bytes)
  bytes = tonumber(bytes) or 0
  if bytes < 1024 then return bytes..' B' end
  return string.format('%.1f KB', bytes/1024)
end

-- The size of what a backup holds, and which file it lacks (a fresh profile's).
local function holds_text(b)
  local s = size_text(b.size)
  if not b.sizes.meta then return s..', no unlocks' end
  if not b.sizes.profile then return s..', unlocks only' end
  return s
end

local function backup_kind_text(b)
  if b.reason == 'before restore' then return 'Before restore' end
  return b.kind == 'auto' and 'Automatic' or 'Manual'
end

-- One backup: date and time, kind and size, styled like a slot row (a click selects
-- it; `chosen` draws the challenge-list marker).
local function backup_row(b)
  local when = b.taken_at > 0 and os.date('%Y-%m-%d  %H:%M', b.taken_at) or '?'
  return {n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
    {n=G.UIT.C, config={id = 'saveslots_backup_'..b.id, align = 'cm', minw = BACKUP_ROW_W, minh = BACKUP_ROW_H,
        padding = 0.04, r = 0.1, hover = true, shadow = true, colour = b.kind == 'auto' and G.C.BLUE or G.C.GREEN,
        button = 'saveslots_backup_select', ref_table = {id = b.id},
        chosen = (state.backups.selected == b.id) and 'vert' or nil}, nodes={
      -- three columns and two gaps: 2.3 + 0.1 + 1.9 + 0.1 + 2.1, a margin inside BACKUP_ROW_W
      {n=G.UIT.C, config={align = 'cm', minw = 2.3, maxw = 2.3}, nodes={
        {n=G.UIT.T, config={text = when, scale = 0.34, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
      }},
      {n=G.UIT.B, config={w = 0.1, h = 0.1}},
      {n=G.UIT.C, config={align = 'cm', minw = 1.9, maxw = 1.9}, nodes={
        {n=G.UIT.T, config={text = backup_kind_text(b), scale = 0.32, colour = G.C.UI.TEXT_LIGHT}},
      }},
      {n=G.UIT.B, config={w = 0.1, h = 0.1}},
      {n=G.UIT.C, config={align = 'cm', minw = 2.1, maxw = 2.1}, nodes={
        {n=G.UIT.T, config={text = holds_text(b), scale = 0.32, colour = G.C.UI.TEXT_LIGHT}},
      }},
    }},
  }}
end

-- The backups panel, in the preview's place and outer size: a title, what a backup
-- holds, a page of rows (always BACKUP_ROWS high), the page cycle's row and the
-- message line (both reserved when empty), so it never changes size.
local function backups_def()
  local bk = state.backups
  local list = backup.list()
  local pages = math.max(1, math.ceil(#list/BACKUP_ROWS))
  bk.page = math.min(math.max(1, bk.page or 1), pages)
  local rows = {}
  for i = (bk.page - 1)*BACKUP_ROWS + 1, math.min(#list, bk.page*BACKUP_ROWS) do
    rows[#rows+1] = backup_row(list[i])
  end
  if #rows == 0 then
    rows[1] = {n=G.UIT.R, config={align = 'cm', padding = 0.1}, nodes={
      {n=G.UIT.T, config={id = 'saveslots_backups_empty', text = 'No backups yet', scale = 0.4,
        colour = G.C.UI.TEXT_LIGHT}},
    }}
  end
  local cycle = {}
  if pages > 1 then
    local opts = {}
    for i = 1, pages do opts[i] = localize('k_page')..' '..i..'/'..pages end
    cycle[1] = own_cycle({id = 'saveslots_backups_pages', scale = 0.6, h = 0.3, w = 2.6, options = opts,
      opt_callback = 'saveslots_backups_page', current_option = bk.page, colour = G.C.BLUE, no_pips = true},
      'saveslots_backups_page_cycle', 0.05)
  end
  local msg = {}
  if bk.msg then
    msg[1] = {n=G.UIT.T, config={id = 'saveslots_backups_msg', text = bk.msg, scale = 0.34, colour = G.C.WHITE,
      shadow = true}}
  end
  local function line(text)
    return {n=G.UIT.R, config={align = 'cm', maxw = DETAIL_W - 0.6}, nodes={
      {n=G.UIT.T, config={text = text, scale = 0.3, colour = G.C.UI.TEXT_LIGHT}},
    }}
  end
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.BLACK, minw = DETAIL_W, minh = DETAIL_H, r = 0.1}, nodes={
    {n=G.UIT.C, config={align = 'cm', padding = 0.08}, nodes={
      {n=G.UIT.R, config={align = 'cm'}, nodes={
        {n=G.UIT.T, config={text = 'Profile backups', scale = 0.55, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
      }},
      line('Progress, unlocks and stats of this profile. Save slots are not in them.'),
      line('One is made the first time the profile loads each day; the last '..backup.KEEP_AUTO..' are kept.'),
      {n=G.UIT.R, config={align = 'tm', minh = BACKUP_ROWS*(BACKUP_ROW_H + 0.14), minw = BACKUP_ROW_W + 0.2}, nodes={
        {n=G.UIT.C, config={align = 'tm'}, nodes=rows},
      }},
      {n=G.UIT.R, config={align = 'cm', minh = 0.5}, nodes=cycle},
      {n=G.UIT.R, config={align = 'cm', minh = 0.36, maxw = DETAIL_W - 0.4}, nodes=msg},
    }},
  }}
end

-- The right-hand panel as a live UIBox. preview.build (and building its
-- definition into a UIBox) is guarded: any error shows a message instead, and
-- the list stays usable.
local function detail_box(slots, parent)
  local cfg = {offset = {x = 0, y = 0}, align = 'cm', parent = parent}
  if state.backups then return UIBox{definition = backups_def(), config = cfg} end
  if state.import then return UIBox{definition = import_def(), config = cfg} end
  local slot = state.selected and find_slot(slots, state.selected)
  if not slot then
    local text = #slots == 0 and (narrowed() and 'Nothing matches these filters'
      or (filter().favorite or filter().kind and filter().kind ~= 'save') and filter().empty
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

-- The selected backup, when it is still listed.
local function selected_backup()
  local bk = state.backups
  if not (bk and bk.selected) then return nil end
  for _, b in ipairs(backup.list()) do
    if b.id == bk.selected then return b end
  end
end

local function actions_def(slots)
  local nodes = {}
  if state.backups then
    local bk = state.backups
    nodes[1] = button({'Back up', 'now'}, 'saveslots_backup_now', G.C.GREEN, 'saveslots_backup_now')
    if selected_backup() then
      local armed = bk.confirm_restore == bk.selected
      nodes[#nodes+1] = button(armed and {'Confirm', 'restore'} or 'Restore', 'saveslots_backup_restore',
        armed and darken(G.C.BLUE, 0.25) or G.C.BLUE, 'saveslots_backup_restore')
      armed = bk.confirm_delete == bk.selected
      nodes[#nodes+1] = button(armed and {'Confirm', 'delete'} or 'Delete', 'saveslots_backup_delete',
        armed and darken(G.C.RED, 0.25) or G.C.RED, 'saveslots_backup_delete')
    end
    nodes[#nodes+1] = button('Close', 'saveslots_backups_close', G.C.RED, 'saveslots_backups_close')
  elseif state.import then
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

-- The kind and folder cycles share one row (see LIST_W): their scale, and the
-- folder cycle's width before scaling.
local CYCLE_SCALE, FOLDER_CYCLE_W = 0.6, 3.7

-- A vanilla option cycle whose arrows call `button` (forwarding to vanilla's
-- option_cycle) instead of 'option_cycle'. The kind and folder cycles sit above
-- the page cycle, and 'option_cycle' must keep finding the page cycle first (see
-- Rules). The controller clicks cycle arrows by position
-- (focused.children[1]/[3]), not by name, so pads still work.
-- `pad` replaces the cycle's own padding (0.1), to fit two cycles in one row.
function own_cycle(args, button, pad)
  local t = create_option_cycle(args)
  local function retarget(node)
    if type(node) ~= 'table' then return end
    if node.config and node.config.button == 'option_cycle' then node.config.button = button end
    if pad and node.config and node.config.id == args.id then node.config.padding = pad end
    for _, child in ipairs(node.nodes or {}) do retarget(child) end
  end
  retarget(t)
  return t
end

-- The kind filter.
local function kind_cycle()
  local labels = {}
  for i, f in ipairs(FILTERS) do labels[i] = f.label end
  return own_cycle({id = 'saveslots_kind', scale = CYCLE_SCALE, h = 0.3, w = 2.6, options = labels,
    opt_callback = 'saveslots_kind', current_option = state.kind, colour = G.C.RED, no_pips = true},
    'saveslots_kind_cycle', 0.05)
end

-- The folder filter (0.3.4): All folders, each folder in use (store.folders), then
-- Unfiled. `folders` rides along in the cycle's args, so the callback maps the
-- option index back to a folder even when a folder is named like a fixed option.
-- A label wider than the cycle (FOLDER_MAX wide glyphs) is scaled down to fit, the
-- way DynaText:init applies its own maxw (create_option_cycle cannot pass one), so
-- no folder widens the column. Every change rebuilds the overlay, so the label is
-- sized once per build.
local function folder_cycle(folders)
  local opts, cur = {'All folders'}, 1
  for i, f in ipairs(folders) do
    opts[i + 1] = f
    if state.folder == f then cur = i + 1 end
  end
  opts[#opts + 1] = 'Unfiled'
  if state.folder == false then cur = #opts end
  local t = own_cycle({id = 'saveslots_folder', scale = CYCLE_SCALE, h = 0.3, w = FOLDER_CYCLE_W, options = opts,
    opt_callback = 'saveslots_folder', current_option = cur, colour = G.C.BLUE, no_pips = true,
    folders = folders}, 'saveslots_folder_cycle', 0.05)
  local maxw = FOLDER_CYCLE_W*CYCLE_SCALE - 0.1
  local function cap(node)
    if type(node) ~= 'table' then return end
    local obj = node.config and node.config.object
    if getmetatable(obj) == DynaText and obj.config.W > maxw then
      obj.config.maxw = maxw
      obj.scale = obj.scale*maxw/obj.config.W
      obj:update_text(true)
    end
    for _, child in ipairs(node.nodes or {}) do cap(child) end
  end
  cap(t)
  return t
end

-- create_text_input(args) for an input that shares the screen with another (the
-- name and search inputs). Vanilla's cursor ('position', func 'flash') blinks in
-- every input whenever any input is hooked, and changes its width then, which
-- lays the input's box out again: two cursors show, and in a nested box (the
-- search's) the letters end up misplaced. Here the cursor keeps one width and
-- blinks only while its own input is hooked (saveslots_cursor), and the prompt is
-- set before the first layout, which then has it.
local function steady_input(args)
  local t = create_text_input(args)
  local function walk(node)
    if type(node) ~= 'table' then return end
    -- 'position' in vanilla; '<id>_position' under Steamodded and HandyBalatro
    local id = node.config and node.config.id
    if type(id) == 'string' and (id == 'position' or id:sub(-9) == '_position') then
      node.config.func = 'saveslots_cursor'
    end
    for _, child in ipairs(node.nodes or {}) do walk(child) end
  end
  walk(t)
  if args.text.ref_table[args.text.ref_value] == '' then args.current_prompt_text = args.prompt_text end
  return t
end

-- The search input, in its own box ('saveslots_search'), after the name input in
-- the tree (0.1.0 callers click the first text input, see Rules). Its own box:
-- vanilla keeps one element per draw_layer per UIBox (UIElement:set_values) and a
-- text input draws on layers 1 and 2, so a second input in the overlay's box
-- would stop the name input from being drawn.
local function search_def()
  return {n=G.UIT.ROOT, config={align = 'cm', padding = 0, colour = G.C.CLEAR}, nodes={
    steady_input({w = LIST_W - 0.2, max_length = SEARCH_MAX, extended_corpus = true, bh_digits = true,
      ref_table = state, ref_value = 'query', prompt_text = 'Search'}),
  }}
end

-- The page cycle, in its own box ('saveslots_pages'), so a search can refresh it
-- without rebuilding the overlay.
local function pages_def(slots)
  local pages = {}
  for i = 1, page_count(slots) do
    pages[i] = localize('k_page')..' '..i..'/'..page_count(slots)
  end
  return {n=G.UIT.ROOT, config={align = 'cm', padding = 0, colour = G.C.CLEAR}, nodes={
    create_option_cycle({id = 'saveslots_page', scale = 0.8, h = 0.3, w = 2.8, options = pages,
      cycle_shoulders = true, opt_callback = 'saveslots_page', current_option = state.page,
      colour = G.C.RED, no_pips = true, focus_args = {snap_to = true}}),
  }}
end

local function overlay_def(slots, folders)
  -- The name input, and in a run the Save button beside it (saves the run as a new
  -- slot named after the input).
  local name_row = {
    steady_input({w = LIST_W - 0.2 - (in_run() and SAVE_W + 0.1 or 0), max_length = NAME_MAX,
      extended_corpus = true, bh_digits = true, ref_table = state, ref_value = 'name', prompt_text = 'Save name'}),
  }
  if in_run() then
    name_row[2] = {n=G.UIT.B, config={w = 0.1, h = 0.1}}
    name_row[3] = UIBox_button({id = 'saveslots_save_new', label = {'Save'}, button = 'saveslots_save_new',
      colour = G.C.GREEN, minw = SAVE_W, minh = 0.6, scale = 0.42, col = true})
  end
  local left = {
    {n=G.UIT.R, config={align = 'cm'}, nodes={
      {n=G.UIT.C, config={align = 'cm'}, nodes={kind_cycle()}},
      {n=G.UIT.C, config={align = 'cm'}, nodes={folder_cycle(folders)}},
    }},
    {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes=name_row},
    -- The search input's box (search_def). The watch refreshes the list as its
    -- text changes (saveslots_search_watch).
    {n=G.UIT.R, config={align = 'cm', padding = 0.05, func = 'saveslots_search_watch'}, nodes={
      {n=G.UIT.O, config={id = 'saveslots_search', object = Moveable()}},
    }},
  }
  left[#left+1] = {n=G.UIT.R, config={align = 'tm', minh = PAGE_SIZE*(ROW_H + 0.14) + 0.1, minw = LIST_W}, nodes={
    {n=G.UIT.O, config={id = 'saveslots_list', object = Moveable()}},
  }}
  left[#left+1] = {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
    {n=G.UIT.O, config={id = 'saveslots_pages', object = Moveable()}},
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
        -- 0.2: the practice composer (practice.lua registers the callback), 0.3 Import
        -- code, 0.4 Backups. Beside the action row, so the overlay doesn't grow. The
        -- row keeps 0.3.4's width: a row's padding goes around and between its
        -- children (engine/ui.lua calculate_xywh), so two buttons of (META_W - 0.3)/2,
        -- a 0.1 gap and four paddings of 0.08 made META_W + 0.12; three buttons of
        -- (META_W - 0.2)/3 with the four paddings as gaps make the same. The longer
        -- labels take two lines, and a label may use all but 0.1 of its button
        -- (UIBox_button's own maxw leaves 0.2, which squeezes "practice").
        {n=G.UIT.R, config={align = 'cm', padding = 0.08, minh = 0.8}, nodes={
          UIBox_button({id = 'saveslots_practice', label = {'New', 'practice'}, button = 'saveslots_practice',
            colour = G.C.GREEN, minw = META_BUTTON_W, maxw = META_BUTTON_W - 0.1, minh = 0.66, scale = 0.3, col = true}),
          UIBox_button({id = 'saveslots_import', label = {'Import', 'code'}, button = 'saveslots_import',
            colour = G.C.BLUE, minw = META_BUTTON_W, maxw = META_BUTTON_W - 0.1, minh = 0.66, scale = 0.3, col = true}),
          UIBox_button({id = 'saveslots_backups', label = {'Backups'}, button = 'saveslots_backups',
            colour = G.C.ORANGE, minw = META_BUTTON_W, maxw = META_BUTTON_W - 0.1, minh = 0.66, scale = 0.3, col = true}),
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
  shown_query = state.query
  swap('saveslots_list', function(node)
    return UIBox{definition = list_page_def(slots), config = {offset = {x = 0, y = 0}, align = 'cm', parent = node}}
  end)
end

local function refresh_search()
  swap('saveslots_search', function(node)
    return UIBox{definition = search_def(), config = {offset = {x = 0, y = 0}, align = 'cm', parent = node}}
  end)
end

local function refresh_pages(slots)
  swap('saveslots_pages', function(node)
    return UIBox{definition = pages_def(slots), config = {offset = {x = 0, y = 0}, align = 'cm', parent = node}}
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
  -- The folder cycle falls back to All folders once its folder has no slot left.
  local folders = store.folders()
  if type(state.folder) == 'string' then
    local kept = false
    for _, f in ipairs(folders) do kept = kept or f == state.folder end
    if not kept then state.folder = nil end
  end
  local slots = list_slots()
  state.share = nil   -- any rebuild follows a change that could make the code stale
  clamp_state(slots)
  if not state.selected then state.editing = nil end
  G.SETTINGS.paused = true
  shown_query = state.query
  G.FUNCS.overlay_menu{definition = overlay_def(slots, folders)}
  if not animate and G.OVERLAY_MENU then G.OVERLAY_MENU:hard_set_VT() end
  refresh_search()
  refresh_list(slots)
  refresh_pages(slots)
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

-- Leaves edit mode (without saving) and closes the import and backups panels.
-- Returns true when any of them was open.
local function close_editor()
  local was_panel = state.import ~= nil or state.backups ~= nil
  state.import = nil
  state.backups = nil
  if not state.editing then return was_panel end
  release_editor_hook()
  state.editing = nil
  state.edit_text = ''
  return true
end

function ui.install()
  if installed then return end
  installed = true
  -- Typed '0's stay '0' in the inputs made with bh_digits (every input here).
  if BHCore and BHCore.install_digits then BHCore.install_digits() end

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

  -- The folder filter (0.3.4), rebuilt like the kind filter. Option 1 is All
  -- folders, the last is Unfiled, and the ones between are cycle_config.folders.
  G.FUNCS.saveslots_folder_cycle = function(e) return G.FUNCS.option_cycle(e) end
  G.FUNCS.saveslots_folder = function(args)
    local cfg = args and args.cycle_config
    if not cfg then return end
    local i = cfg.current_option
    if i == 1 then state.folder = nil
    elseif i == #cfg.options then state.folder = false
    else state.folder = (cfg.folders or {})[i - 1] end
    state.page = 1
    state.confirm_delete = nil
    close_editor()
    open(false)
  end

  -- The name and search inputs' cursor: blinks as vanilla's flash
  -- (button_callbacks.lua G.FUNCS.flash) does, but only while its own input is
  -- hooked (the hook is the cursor's parent), and never changes its width (see
  -- steady_input).
  G.FUNCS.saveslots_cursor = function(e)
    local hook = G.CONTROLLER.text_input_hook
    if hook and hook == e.parent and math.floor(G.TIMERS.REAL*2)%2 == 0 then
      e.config.colour[4] = 1
    else
      e.config.colour[4] = 0
    end
  end

  -- The search box (0.3.4). Runs every frame on the search row: when the text
  -- changed, only the list and the page cycle are swapped (page 1), never the whole
  -- overlay, which would drop the input's hook mid-word. A selection the search
  -- hides is dropped, as a filter drops it, and only then are the detail, actions
  -- and meta boxes swapped too. With nothing selected the detail is a message
  -- ("Select a save" or "Nothing matches these filters"), swapped to follow.
  G.FUNCS.saveslots_search_watch = function(e)
    if state.query == shown_query or not G.OVERLAY_MENU or e.UIBox ~= G.OVERLAY_MENU then return end
    state.page = 1
    local slots = list_slots()
    refresh_list(slots)
    refresh_pages(slots)
    if state.selected and not find_slot(slots, state.selected) then
      state.selected = nil
      state.confirm_delete = nil
      close_editor()
      refresh_detail(slots)
      refresh_actions(slots)
      refresh_meta(slots)
    elseif not state.selected then
      refresh_detail(slots)
    end
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
    state.backups = nil
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
  G.FUNCS.saveslots_edit_folder = function(e) edit('folder') end

  -- A folder button in the folder editor: its name goes into the input (the
  -- editor box is rebuilt with it and hooked again); Save or Return then files it.
  G.FUNCS.saveslots_folder_pick = function(e)
    local f = e and e.config and e.config.ref_table and e.config.ref_table.folder
    if state.editing ~= 'folder' or type(f) ~= 'string' or not G.OVERLAY_MENU then return end
    release_editor_hook()
    state.edit_text = f
    refresh_detail(list_slots())
    editor_hook()
  end

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

  -- Profile backups (0.4, T-374) -------------------------------------------------

  -- The panel lives in the detail box, its buttons in the action row.
  local function refresh_backups()
    local slots = list_slots()
    refresh_detail(slots)
    refresh_actions(slots)
  end

  -- A panel message: on its message line and as an alert.
  local function backups_say(bk, text, cancel)
    bk.msg = text
    if G.OVERLAY_MENU and state.backups == bk then
      refresh_backups()
      alert(text)
    end
    if cancel then play_sound('cancel') end
  end

  G.FUNCS.saveslots_backups = function(e)
    if not G.OVERLAY_MENU then return end
    state.confirm_delete = nil
    close_editor()
    state.backups = {page = 1}
    local slots = list_slots()
    refresh_detail(slots)
    refresh_actions(slots)
    refresh_meta(slots)
  end

  G.FUNCS.saveslots_backups_close = function(e)
    close_editor()
    open(false)
  end

  G.FUNCS.saveslots_backup_select = function(e)
    local bk = state.backups
    local id = e and e.config and e.config.ref_table and e.config.ref_table.id
    if not (bk and id and G.OVERLAY_MENU) then return end
    bk.selected, bk.confirm_restore, bk.confirm_delete, bk.msg = id, nil, nil, nil
    refresh_backups()
  end

  G.FUNCS.saveslots_backups_page_cycle = function(e) return G.FUNCS.option_cycle(e) end
  G.FUNCS.saveslots_backups_page = function(args)
    local bk = state.backups
    if not (bk and args and args.cycle_config) then return end
    bk.page = args.cycle_config.current_option
    bk.confirm_restore, bk.confirm_delete = nil, nil
    refresh_backups()
  end

  -- Waits for the game's pending profile save (backup.when_settled), so the copy has
  -- what the game still held in memory; usually a frame or two.
  G.FUNCS.saveslots_backup_now = function(e)
    local bk = state.backups
    if not (bk and G.OVERLAY_MENU) or bk.busy then return end
    bk.confirm_restore, bk.confirm_delete, bk.busy = nil, nil, true
    bk.msg = 'Backing up'
    refresh_backups()
    backup.when_settled(function()
      bk.busy = nil
      local id, err = backup.take('manual')
      if id then bk.selected, bk.page = id, 1 end
      backups_say(bk, id and 'Backed up' or err == backup.NOTHING and 'Nothing to back up yet'
        or 'Backup failed: '..tostring(err), not id)
    end)
  end

  -- After the reload the overlay is gone (vanilla's profile switch removes it with
  -- the old main menu): it is built again with the panel open.
  local function restored(ok, err)
    local bk = state.backups or {page = 1}
    state.backups = bk
    bk.selected, bk.confirm_restore, bk.confirm_delete, bk.busy = nil, nil, nil, nil
    if ok then
      bk.page = 1
      state.confirm_delete = nil
      open(false)
    end
    backups_say(bk, ok and 'Profile restored' or 'Restore failed: '..tostring(err), not ok)
  end

  G.FUNCS.saveslots_backup_restore = function(e)
    local bk = state.backups
    if not (bk and selected_backup() and G.OVERLAY_MENU) then return end
    bk.confirm_delete = nil
    local can, why = backup.can_restore()
    if not can then
      bk.confirm_restore = nil
      return backups_say(bk, (tostring(why):gsub('^%l', string.upper)), true)
    end
    if bk.confirm_restore ~= bk.selected then
      bk.confirm_restore = bk.selected
      bk.msg = 'Press again to restore. Your current progress is backed up first.'
      return refresh_backups()
    end
    -- Busy before the call: a failure can come back through `restored` at once.
    bk.confirm_restore, bk.busy, bk.msg = nil, true, 'Restoring'
    local ok, err = backup.restore(bk.selected, restored)
    if not ok then
      bk.busy = nil
      return backups_say(bk, 'Restore failed: '..tostring(err), true)
    end
    if bk.busy then refresh_backups() end
  end

  G.FUNCS.saveslots_backup_delete = function(e)
    local bk = state.backups
    local b = selected_backup()
    if not (b and G.OVERLAY_MENU) then return end
    bk.confirm_restore = nil
    if bk.confirm_delete ~= b.id then
      bk.confirm_delete = b.id
      return refresh_actions(list_slots())
    end
    bk.confirm_delete = nil
    local ok, err = backup.delete(b.id)
    if ok then bk.selected = nil end
    backups_say(bk, ok and 'Backup deleted' or 'Delete failed: '..tostring(err), not ok)
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
