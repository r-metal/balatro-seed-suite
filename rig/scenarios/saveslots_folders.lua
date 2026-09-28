-- Save Slots folders and search (0.3.4), in a real run, through real buttons and keys.
--   1. Run A (seed MNQW1357): save "Alpha", "Bravo", "Charlie" through the overlay.
--      Run B (seed QZJX2468): save "Delta". Bravo becomes a hunt with a target, notes
--      and (later) a folder: the tallest meta column.
--   2. Folder editor: Alpha's folder typed ("perkeo 20", Return; the 0 is kept), then
--      Bravo's picked from the existing folders (one click, then Save).
--   3. Folder cycle: "perkeo 20" lists Alpha and Bravo, Unfiled lists Charlie and
--      Delta, and it combines with the kind cycle.
--   4. Search box: typed key by key through G.FUNCS.text_input_key. The list follows
--      each key while the input stays hooked and the overlay stays the same UIBox; by
--      name, by seed, and a no-match message.
--   5. Clearing the folder: Bravo, then Alpha (the last one): the cycle drops the
--      folder and falls back to All folders.
-- Layout: the overlay's outer panel keeps one size in every state (no folder, the
-- folder editor, a search, the cycle on a folder) and fits the room; the right
-- column, the detail panel and the meta column keep theirs; 0.1.0 callers still find
-- the page cycle and the name input first. A stress tail (14 folders, the widest
-- FOLDER_MAX name, a full-length query and name) keeps that size too.
-- Screenshots: folders_editor, folders_cycle, folders_search (and folders_tallest,
-- folders_many, folders_wide).
local store = require('saveslots.store')
local checkpoint = require('saveslots.checkpoint')
local sharecode = require('saveslots.sharecode')

local SEED_A, SEED_B = 'MNQW1357', 'QZJX2468'
local FOLDER = 'perkeo 20'
-- Bravo's meta at full length (TARGET_MAX 24; notes that wrap to 6 lines, past the
-- meta column's 4-line cap). No 'al' in either: the name search below types "al"
-- and expects Alpha alone.
local TARGET = 'Win with Perkeo by A8 ok'
local NOTES = 'Reroll: Blueprint, Brainstorm, Perkeo, Triboulet, Chicot!'
local NOTES_SHOWN = 'Reroll: Blueprint, Brainstorm, Perkeo,...'
local HUNT_FILTER = 'Charm Tag + Soul in A1-2'
local WIDE = string.rep('W', 16)   -- FOLDER_MAX of the widest glyph

local S = {}   -- ids and state across steps

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID(id) end

-- The UIBox inside one of ui.lua's G.UIT.O slots.
local function sub_box(id)
  local node = uie(id)
  return node and node.config.object
end

local function sub_uie(box_id, id)
  local box = sub_box(box_id)
  return box and box.get_UIE_by_ID and box:get_UIE_by_ID(id)
end

local function key(k) G.FUNCS.text_input_key({key = k}) end

-- Types into the hooked input through the real key path (no return).
local function type_keys(ctx, text, clear)
  ctx.assert(G.CONTROLLER.text_input_hook, 'no text input is hooked')
  for _ = 1, clear or 0 do key('backspace') end
  for i = 1, #text do key(text:sub(i, i)) end
end

local function type_name(ctx, text)
  ctx.assert(ctx.click('select_text_input'), 'name input not found')
  local hook = G.CONTROLLER.text_input_hook
  ctx.assert(hook and hook.config.ref_table.prompt_text == 'Save name', 'first text input is not the name input')
  type_keys(ctx, text, 30)
  key('return')
end

-- Clicks the right arrow of the cycle whose arrows call `button`.
local function cycle_next(ctx, button, dir)
  local found
  local function walk(n)
    if found or type(n) ~= 'table' then return end
    if n.config and n.config.button == button and n.config.ref_value == (dir or 'r') then found = n; return end
    for _, c in ipairs(n.children or {}) do walk(c) end
  end
  walk(G.OVERLAY_MENU and G.OVERLAY_MENU.UIRoot)
  ctx.assert(found, button..' arrow not found')
  G.FUNCS[found.config.button](found)
end

-- The folder cycle's args: options and the shown one.
local function folder_cycle(ctx)
  local arrow = ctx.find_button('saveslots_folder_cycle')
  ctx.assert(arrow, 'folder cycle arrows not found (a cycle with one option has none)')
  return arrow.config.ref_table
end

local function kind_shown(ctx)
  local arrow = ctx.find_button('saveslots_kind_cycle')
  return arrow and arrow.config.ref_table.current_option_val
end

local function disk_index()
  return STR_UNPACK(get_compressed(G.SETTINGS.profile..'/saveslots/index.jkr'))
end

local function disk_folder(id)
  local e = disk_index().slots[id]
  return e and e.meta and e.meta.folder
end

local function meta_lines(field)
  local out, i = {}, 1
  while true do
    local n = sub_uie('saveslots_meta', 'saveslots_meta_'..field..'_'..i)
    if not n then break end
    out[#out+1] = n.config.text
    i = i + 1
  end
  if #out == 0 then
    local none = sub_uie('saveslots_meta', 'saveslots_meta_'..field..'_none')
    return none and ('<'..none.config.text..'>') or nil
  end
  return table.concat(out, ' ')
end

-- The search input's clickable node (in the 'saveslots_search' box).
local function search_input() return sub_uie('saveslots_search', 'text_input') end

local function search_hooked()
  local hook = G.CONTROLLER.text_input_hook
  local args = hook and hook.config and hook.config.ref_table
  return args and args.ref_value == 'query' and args.prompt_text == 'Search' and not hook.REMOVED
    and hook.UIBox == sub_box('saveslots_search')
end

local ALL = {'alpha', 'bravo', 'charlie', 'delta'}

-- The list shows exactly the slots in `want` (names), and no others.
local function expect_rows(ctx, label, want)
  local set = {}
  for _, n in ipairs(want) do set[n] = true end
  for _, n in ipairs(ALL) do
    local shown = sub_uie('saveslots_list', 'saveslots_row_'..S[n]) ~= nil
    ctx.assert(shown == (set[n] == true), string.format('%s: %s is %s', label, n, shown and 'shown' or 'hidden'))
  end
end

local function state_query()
  local args = search_input().children[1].children[1].config.ref_table
  return args.text.ref_table[args.text.ref_value]
end

local function list_empty_text()
  local n = sub_uie('saveslots_list', 'saveslots_list_empty')
  return n and n.config.text
end

-- One outer size for the overlay's panel in every state, inside the room; the right
-- column, the detail panel and the meta column keep theirs too; 0.1.0 lookups
-- unchanged. `record` names one of the four states check 9 needs.
local layout, recorded = {}, {}
local function check_layout(ctx, label, record)
  local panel = G.OVERLAY_MENU and G.OVERLAY_MENU.UIRoot.children[1]
  local right, detail, meta = uie('saveslots_right'), sub_box('saveslots_detail'), sub_box('saveslots_meta')
  ctx.assert(panel and right and detail and meta, label..': overlay nodes missing')
  local p = panel.T
  -- The content's extent, as ui_meta measures it: the kind cycle at the top left, the
  -- meta column at the right, the Back button at the bottom (room units).
  local top, back, mcol = uie('saveslots_kind'), uie('overlay_menu_back_button'), uie('saveslots_meta')
  ctx.assert(top and back and mcol, label..': kind cycle, Back or meta column missing')
  local box = {x1 = top.T.x, y1 = top.T.y, x2 = mcol.T.x + mcol.T.w, y2 = back.T.y + back.T.h}
  ctx.log(string.format('layout %s: panel %.2fx%.2f at %.2f,%.2f, content x %.2f..%.2f y %.2f..%.2f in room %.2fx%.2f; right %.2f, detail %.2fx%.2f, meta %.2fx%.2f',
    label, p.w, p.h, p.x, p.y, box.x1, box.x2, box.y1, box.y2, G.ROOM.T.w, G.ROOM.T.h, right.T.w,
    detail.T.w, detail.T.h, meta.T.w, meta.T.h))
  for k, v in pairs({w = p.w, h = p.h, right = right.T.w, dw = detail.T.w, dh = detail.T.h, mw = meta.T.w, mh = meta.T.h}) do
    layout[k] = layout[k] or v
    ctx.assert(math.abs(v - layout[k]) < 0.01, string.format('%s: %s is %.2f, was %.2f', label, k, v, layout[k]))
  end
  ctx.assert(box.x1 >= 0 and box.y1 >= 0 and box.x2 <= G.ROOM.T.w and box.y2 <= G.ROOM.T.h
    and p.w <= G.ROOM.T.w and p.h <= G.ROOM.T.h, label..': the overlay does not fit the room')
  local cyc = ctx.find_button('option_cycle')
  ctx.assert(not cyc or cyc.config.ref_table.opt_callback == 'saveslots_page',
    label..': the first option_cycle is not the page cycle')
  local input = ctx.find_button('select_text_input')
  ctx.assert(input and input.children[1].children[1].config.ref_table.prompt_text == 'Save name',
    label..': the first text input is not the name input')
  if record then recorded[record] = true end
end

return {
  -- Player-slot scenario: auto-checkpoints would add 'Auto A<n>' slots.
  {name = 'no auto-checkpoints', run = function(ctx)
    SaveSlots.settings.auto_checkpoints = false
    G.F_LOCAL_CLIPBOARD = true   -- vanilla's switch for copy_seed/paste_seed: Share stays off the system clipboard
    return true
  end},

  -- 1. Four slots over two seeds
  {name = 'start run A', run = function(ctx) ctx.start_run{seed = SEED_A}; return true end},
  {name = 'run A autosave', timeout = 20, run = function(ctx)
    local run = G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and checkpoint.get()
    return run and run.GAME and run.GAME.pseudorandom.seed == SEED_A
  end},
  {name = 'save Alpha, Bravo, Charlie', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    G.FUNCS.saveslots_open()
    for _, n in ipairs({'Alpha', 'Bravo', 'Charlie'}) do
      type_name(ctx, n)
      ctx.assert(ctx.click('saveslots_save_new'), 'Save current run not found')
    end
    G.FUNCS.exit_overlay_menu()
    return true
  end},
  {name = 'start run B', run = function(ctx)
    if G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    S.prev = G.GAME
    ctx.start_run{seed = SEED_B}
    return true
  end},
  {name = 'run B autosave', timeout = 20, run = function(ctx)
    if not (G.GAME ~= S.prev and G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT) then return false end
    local run = checkpoint.get()
    return run and run.GAME and run.GAME.pseudorandom.seed == SEED_B
  end},
  {name = 'save Delta, make Bravo a hunt', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    G.FUNCS.saveslots_open()
    type_name(ctx, 'Delta')
    ctx.assert(ctx.click('saveslots_save_new'), 'Save current run not found')
    for _, e in ipairs(store.list()) do S[e.name:lower()] = e.id end
    for _, n in ipairs(ALL) do ctx.assert(S[n], n..' not listed') end
    ctx.assert(store.list({query = SEED_B})[1].id == S.delta, 'Delta is not the run B slot')
    -- The Finder's "Save as hunt" makes hunts; the store API stands in for it here.
    ctx.assert(store.set_meta(S.bravo, {kind = 'hunt', target = TARGET, notes = NOTES,
      origin = {kind = 'finder', filter_name = HUNT_FILTER}}), 'hunt meta')   -- (no filter: Share validates one)
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'no folder yet', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    expect_rows(ctx, 'all', ALL)
    ctx.assert(#store.folders() == 0, 'folders before any was set')
    ctx.assert(kind_shown(ctx) == 'All', 'kind cycle shows '..tostring(kind_shown(ctx)))
    local fc = folder_cycle(ctx)
    ctx.assert(#fc.options == 2 and fc.options[1] == 'All folders' and fc.options[2] == 'Unfiled'
      and fc.current_option_val == 'All folders', 'folder cycle with no folders: '..table.concat(fc.options, '|'))
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.bravo), 'Bravo row not found')
    return true
  end},
  {name = 'tallest meta, no folder', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(meta_lines('folder') == '<No folder>', 'Bravo folder block: '..tostring(meta_lines('folder')))
    ctx.assert(meta_lines('notes') == NOTES_SHOWN and meta_lines('target') == TARGET,
      'Bravo meta: '..tostring(meta_lines('target'))..' / '..tostring(meta_lines('notes')))
    check_layout(ctx, 'no folder', 'no folder')
    return true
  end},

  -- 2. The folder editor
  {name = 'edit Alpha folder', run = function(ctx)
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.alpha), 'Alpha row not found')
    ctx.assert(meta_lines('folder') == '<No folder>', 'fresh slot shows folder '..tostring(meta_lines('folder')))
    ctx.assert(ctx.click('saveslots_edit_folder'), 'Edit folder button not found')
    local hook = G.CONTROLLER.text_input_hook
    ctx.assert(hook and hook.UIBox == sub_box('saveslots_detail'), 'the folder input was not hooked on open')
    local args = hook.config.ref_table
    ctx.assert(args.max_length == store.FOLDER_MAX and args.bh_digits == true,
      'folder input: max_length '..tostring(args.max_length)..', bh_digits '..tostring(args.bh_digits))
    ctx.assert(ctx.find_button('saveslots_edit_save') and ctx.find_button('saveslots_edit_cancel'), 'Save/Cancel missing')
    ctx.assert(not ctx.find_button('saveslots_folder_pick'), 'a folder offered to pick with none in use')
    type_keys(ctx, FOLDER, 20)
    ctx.assert(args.text.ref_table[args.text.ref_value] == FOLDER, 'typed '..FOLDER..', input holds '
      ..tostring(args.text.ref_table[args.text.ref_value]))
    return true
  end},
  {name = 'return files Alpha', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    check_layout(ctx, 'folder editor (typed)', 'folder editor')
    key('return')
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'return did not release the folder input')
    return true
  end},
  {name = 'Alpha filed', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(not sub_uie('saveslots_detail', 'text_input'), 'editor still open after return')
    ctx.assert(meta_lines('folder') == FOLDER, 'meta column shows folder '..tostring(meta_lines('folder')))
    ctx.assert(disk_folder(S.alpha) == FOLDER, 'index holds folder '..tostring(disk_folder(S.alpha)))
    ctx.log('check: folder typed in editor')
    return true
  end},
  {name = 'edit Bravo folder', run = function(ctx)
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.bravo), 'Bravo row not found')
    ctx.assert(ctx.click('saveslots_edit_folder'), 'Edit folder button not found')
    local hook = G.CONTROLLER.text_input_hook
    ctx.assert(hook and hook.config.ref_table.ref_table.edit_text == '', 'Bravo editor does not start empty')
    local pick = ctx.find_button('saveslots_folder_pick', 'saveslots_folder_pick_1')
    ctx.assert(pick and pick.config.ref_table.folder == FOLDER, 'no pick button for '..FOLDER)
    ctx.assert(not ctx.find_button('saveslots_folder_pick', 'saveslots_folder_pick_2'), 'a second folder offered')
    ctx.assert(ctx.click('saveslots_folder_pick', 'saveslots_folder_pick_1'), 'pick button not clickable')
    hook = G.CONTROLLER.text_input_hook
    ctx.assert(hook and hook.UIBox == sub_box('saveslots_detail') and not hook.REMOVED, 'input not hooked after the pick')
    local args = hook.config.ref_table
    ctx.assert(args.text.ref_table[args.text.ref_value] == FOLDER, 'the pick did not fill the input')
    ctx.assert(table.concat(args.text.letters) == FOLDER, 'the input shows '..table.concat(args.text.letters))
    return true
  end},
  {name = 'editor shot', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    check_layout(ctx, 'folder editor (picked)', 'folder editor')
    ctx.shot('folders_editor')
    return true
  end},
  {name = 'save Bravo', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    ctx.assert(ctx.click('saveslots_edit_save'), 'Save button not found')
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'Save left the removed input hooked')
    return true
  end},
  {name = 'Bravo filed', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.assert(disk_folder(S.bravo) == FOLDER, 'index holds Bravo folder '..tostring(disk_folder(S.bravo)))
    ctx.assert(meta_lines('folder') == FOLDER, 'meta column shows folder '..tostring(meta_lines('folder')))
    ctx.assert(meta_lines('notes') == NOTES_SHOWN and meta_lines('target') == TARGET and meta_lines('hunt') == HUNT_FILTER,
      'the tallest meta column lost a block')
    check_layout(ctx, 'tallest meta')
    ctx.log('check: folder picked from existing')
    ctx.assert(ctx.click('saveslots_share'), 'Share not found')   -- adds the share line: taller still
    return true
  end},
  {name = 'tallest meta with the share line', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(sub_uie('saveslots_meta', 'saveslots_meta_code'), 'no share line')
    check_layout(ctx, 'tallest meta + share line')
    ctx.shot('folders_tallest')
    return true
  end},

  -- 3. The folder cycle
  {name = 'to perkeo 20', run = function(ctx)
    local fc = folder_cycle(ctx)
    ctx.assert(table.concat(fc.options, '|') == 'All folders|'..FOLDER..'|Unfiled', 'options '..table.concat(fc.options, '|'))
    cycle_next(ctx, 'saveslots_folder_cycle')
    return true
  end},
  {name = 'folder cycle filters', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.8 then return false end
    ctx.assert(folder_cycle(ctx).current_option_val == FOLDER, 'folder cycle shows '..folder_cycle(ctx).current_option_val)
    expect_rows(ctx, FOLDER, {'alpha', 'bravo'})
    ctx.assert(#store.list({folder = FOLDER}) == 2, 'store lists '..#store.list({folder = FOLDER})..' in the folder')
    check_layout(ctx, 'folder cycle', 'folder cycle')
    ctx.shot('folders_cycle')
    ctx.log('check: folder cycle filters')
    return true
  end},
  {name = 'to unfiled', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    cycle_next(ctx, 'saveslots_folder_cycle')
    return true
  end},
  {name = 'unfiled', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(folder_cycle(ctx).current_option_val == 'Unfiled', 'folder cycle shows '..folder_cycle(ctx).current_option_val)
    expect_rows(ctx, 'Unfiled', {'charlie', 'delta'})
    check_layout(ctx, 'unfiled')
    ctx.log('check: unfiled lists the rest')
    cycle_next(ctx, 'saveslots_kind_cycle')   -- All -> Saves
    return true
  end},
  {name = 'unfiled saves', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(kind_shown(ctx) == 'Saves' and folder_cycle(ctx).current_option_val == 'Unfiled',
      'the kind cycle did not keep the folder')
    expect_rows(ctx, 'Unfiled + Saves', {'charlie', 'delta'})
    cycle_next(ctx, 'saveslots_folder_cycle', 'l')   -- Unfiled -> perkeo 20
    return true
  end},
  {name = 'perkeo saves', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(kind_shown(ctx) == 'Saves' and folder_cycle(ctx).current_option_val == FOLDER, 'the folder cycle lost the kind')
    expect_rows(ctx, FOLDER..' + Saves', {'alpha'})
    for _ = 1, 3 do cycle_next(ctx, 'saveslots_kind_cycle') end   -- Saves -> Hunts
    return true
  end},
  {name = 'perkeo hunts', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(kind_shown(ctx) == 'Hunts', 'kind cycle shows '..tostring(kind_shown(ctx)))
    expect_rows(ctx, FOLDER..' + Hunts', {'bravo'})
    cycle_next(ctx, 'saveslots_folder_cycle')   -- perkeo 20 -> Unfiled
    return true
  end},
  {name = 'unfiled hunts', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    expect_rows(ctx, 'Unfiled + Hunts', {})
    ctx.assert(list_empty_text() == 'Nothing matches these filters', 'empty list says '..tostring(list_empty_text()))
    ctx.log('check: folder and kind combine')
    for _ = 1, 2 do cycle_next(ctx, 'saveslots_kind_cycle') end   -- Hunts -> Favorites -> All
    cycle_next(ctx, 'saveslots_folder_cycle')   -- Unfiled -> All folders
    return true
  end},

  -- 4. The search box
  {name = 'search: hook it', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.assert(kind_shown(ctx) == 'All' and folder_cycle(ctx).current_option_val == 'All folders', 'filters not reset')
    expect_rows(ctx, 'before the search', ALL)
    -- Bravo selected: "al" below hides it, and the search drops the selection.
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.bravo), 'Bravo row not found')
    local input = search_input()
    ctx.assert(input, 'search input not found')
    ctx.assert(input.children[1].children[1].config.ref_table.bh_digits == true, 'search input without bh_digits')
    G.FUNCS.select_text_input(input)
    ctx.assert(search_hooked(), 'the search input did not take the hook')
    S.ov = G.OVERLAY_MENU
    key('a')
    ctx.assert(search_hooked(), 'hook lost after a')
    return true
  end},
  {name = 'search: a', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    ctx.assert(search_hooked(), 'hook lost a frame after a')
    expect_rows(ctx, 'search a', ALL)
    key('l')
    ctx.assert(search_hooked(), 'hook lost after l')
    return true
  end},
  {name = 'search: al', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    ctx.assert(search_hooked(), 'hook lost a frame after l')
    expect_rows(ctx, 'search al', {'alpha'})
    local msg = sub_uie('saveslots_detail', 'saveslots_detail_msg')
    ctx.assert(msg and msg.config.text == 'Select a save' and not ctx.find_button('saveslots_load'),
      'the selection the search hid is still shown')
    ctx.assert(G.OVERLAY_MENU == S.ov, 'the overlay was rebuilt while typing')
    for _, k in ipairs({'p', 'h'}) do
      key(k)
      ctx.assert(search_hooked(), 'hook lost after '..k)
    end
    return true
  end},
  {name = 'search: alph', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(search_hooked(), 'hook lost a frame after h')
    expect_rows(ctx, 'search alph', {'alpha'})
    ctx.assert(G.OVERLAY_MENU == S.ov, 'the overlay was rebuilt while typing')
    check_layout(ctx, 'search', 'search')
    ctx.shot('folders_search')
    ctx.log('check: search by name')
    return true
  end},
  {name = 'search: by seed', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    for _ = 1, 4 do key('backspace') end
    ctx.assert(search_hooked(), 'hook lost after backspace')
    for _, k in ipairs({'z', 'j', 'x', '2'}) do
      key(k)
      ctx.assert(search_hooked(), 'hook lost after '..k)
    end
    return true
  end},
  {name = 'search: zjx2', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(search_hooked(), 'hook lost a frame after zjx2')
    expect_rows(ctx, 'search zjx2', {'delta'})
    ctx.assert(G.OVERLAY_MENU == S.ov, 'the overlay was rebuilt while typing')
    ctx.log('check: search by seed')
    for _ = 1, 4 do key('backspace') end
    type_keys(ctx, 'nothing 0')
    ctx.assert(search_hooked(), 'hook lost after nothing 0')
    return true
  end},
  {name = 'search: no match', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    expect_rows(ctx, 'search nothing 0', {})
    ctx.assert(list_empty_text() == 'No saves match "nothing 0"', 'no-match text: '..tostring(list_empty_text()))
    ctx.assert(G.OVERLAY_MENU == S.ov, 'the overlay was rebuilt while typing')
    check_layout(ctx, 'search, no match')
    ctx.log('check: search no match')
    -- The query survives a rebuild: release the input, then step the kind cycle.
    for _ = 1, 9 do key('backspace') end
    type_keys(ctx, 'alph')
    key('return')
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'return did not release the search input')
    cycle_next(ctx, 'saveslots_kind_cycle')
    return true
  end},
  {name = 'query survives a rebuild', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(G.OVERLAY_MENU ~= S.ov, 'the kind cycle did not rebuild the overlay')
    local args = search_input().children[1].children[1].config.ref_table
    ctx.assert(args.text.ref_table[args.text.ref_value] == 'alph', 'the search box lost its text')
    expect_rows(ctx, 'Saves + alph', {'alpha'})
    ctx.log('query kept across a rebuild')
    -- clear it again, through the input
    G.FUNCS.select_text_input(search_input())
    for _ = 1, 4 do key('backspace') end
    key('return')
    for _ = 1, 5 do cycle_next(ctx, 'saveslots_kind_cycle') end   -- Saves -> All
    return true
  end},
  {name = 'size unchanged', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    expect_rows(ctx, 'search cleared', ALL)
    check_layout(ctx, 'search cleared')
    for _, r in ipairs({'no folder', 'folder editor', 'search', 'folder cycle'}) do
      ctx.assert(recorded[r], 'size not measured with '..r)
    end
    ctx.log(string.format('overlay panel %.2fx%.2f in every state', layout.w, layout.h))
    ctx.log('check: size unchanged')
    return true
  end},

  -- A filed slot's share code carries no folder (the schema has no room for one).
  {name = 'share a filed slot', run = function(ctx)
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.alpha), 'Alpha row not found')
    ctx.assert(ctx.click('saveslots_share'), 'Share not found')
    local t = sharecode.decode(G.CLIPBOARD or '')
    ctx.assert(t and t.seed == SEED_A and t.folder == nil, 'share code of a filed slot: '..tostring(G.CLIPBOARD))
    ctx.log('share code has no folder')
    return true
  end},

  -- 5. Clearing the folder
  {name = 'cycle to the folder', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    cycle_next(ctx, 'saveslots_folder_cycle')   -- All folders -> perkeo 20
    return true
  end},
  {name = 'clear Bravo', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(folder_cycle(ctx).current_option_val == FOLDER, 'not on the folder')
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.bravo), 'Bravo row not found')
    ctx.assert(ctx.click('saveslots_edit_folder'), 'Edit folder button not found')
    ctx.assert(G.CONTROLLER.text_input_hook.config.ref_table.ref_table.edit_text == FOLDER,
      'the editor does not start from the current folder')
    type_keys(ctx, '', 20)
    ctx.assert(ctx.click('saveslots_edit_save'), 'Save button not found')
    return true
  end},
  {name = 'Bravo unfiled', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.assert(disk_folder(S.bravo) == nil, 'Bravo still filed on disk: '..tostring(disk_folder(S.bravo)))
    expect_rows(ctx, FOLDER..' after clearing Bravo', {'alpha'})
    ctx.assert(folder_cycle(ctx).current_option_val == FOLDER, 'the cycle left the folder while Alpha is in it')
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.alpha), 'Alpha row not found')
    ctx.assert(ctx.click('saveslots_edit_folder'), 'Edit folder button not found')
    type_keys(ctx, '', 20)
    key('return')
    return true
  end},
  {name = 'folder cleared', timeout = 5, run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.assert(disk_folder(S.alpha) == nil, 'Alpha still filed on disk')
    ctx.assert(#store.folders() == 0, 'store.folders() still lists '..table.concat(store.folders(), ','))
    local fc = folder_cycle(ctx)
    ctx.assert(fc.current_option_val == 'All folders', 'the cycle did not fall back: '..tostring(fc.current_option_val))
    ctx.assert(table.concat(fc.options, '|') == 'All folders|Unfiled', 'the cycle keeps '..table.concat(fc.options, '|'))
    expect_rows(ctx, 'all after clearing', ALL)
    ctx.assert(meta_lines('folder') == '<No folder>', 'Alpha folder block: '..tostring(meta_lines('folder')))
    check_layout(ctx, 'folder cleared')
    ctx.log('check: folder cleared')
    return true
  end},

  -- Stress (no check line of its own): more folders than the editor offers, the
  -- widest FOLDER_MAX name in the cycle, and a full-length query. Same outer size.
  {name = 'many folders', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    local run = checkpoint.get()
    for i = 1, 13 do
      ctx.assert(store.save(run, 'Filler '..i, nil, {folder = string.format('f%02d', i)}), 'filler '..i)
    end
    S.wide = store.save(run, 'Wide', nil, {folder = WIDE})
    ctx.assert(S.wide, 'wide slot')
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'many folders in the editor', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.8 then return false end
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.wide), 'Wide row not found')
    ctx.assert(ctx.click('saveslots_edit_folder'), 'Edit folder button not found')
    ctx.assert(ctx.find_button('saveslots_folder_pick', 'saveslots_folder_pick_12'), 'fewer than 12 folders offered')
    ctx.assert(not ctx.find_button('saveslots_folder_pick', 'saveslots_folder_pick_13'), 'more than 12 folders offered')
    return true
  end},
  {name = 'many folders shot', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    check_layout(ctx, '14 folders in the editor')
    ctx.shot('folders_many')
    return true
  end},
  {name = 'to the widest folder', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    ctx.assert(ctx.click('saveslots_edit_cancel'), 'Cancel not found')
    cycle_next(ctx, 'saveslots_folder_cycle', 'l')   -- All folders -> Unfiled
    cycle_next(ctx, 'saveslots_folder_cycle', 'l')   -- Unfiled -> the last folder
    return true
  end},
  {name = 'widest folder in the cycle', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(folder_cycle(ctx).current_option_val == WIDE, 'cycle shows '..tostring(folder_cycle(ctx).current_option_val))
    ctx.assert(sub_uie('saveslots_list', 'saveslots_row_'..S.wide) and #store.list({folder = WIDE}) == 1, 'Wide not listed alone')
    check_layout(ctx, 'widest folder')
    ctx.shot('folders_wide')
    G.FUNCS.select_text_input(search_input())
    type_keys(ctx, string.rep('W', 30))
    return true
  end},
  {name = 'full-length query', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local q = state_query()
    ctx.assert(#q == 20, 'the search took '..#q..' chars')
    ctx.assert(list_empty_text() == 'No saves match "'..q..'"', 'no-match text '..tostring(list_empty_text()))
    check_layout(ctx, 'full-length query')
    for _ = 1, 20 do key('backspace') end
    key('return')
    -- a full-length name (NAME_MAX, ordinary letters) in the name input
    type_name(ctx, 'Perkeo by ante eight run')
    return true
  end},
  {name = 'full-length name', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(ctx.click('select_text_input'), 'name input not found')
    local args = G.CONTROLLER.text_input_hook.config.ref_table
    ctx.assert(args.text.ref_table[args.text.ref_value] == 'Perkeo by ante eight run', 'name input holds '
      ..tostring(args.text.ref_table[args.text.ref_value]))
    check_layout(ctx, 'full-length name')
    type_keys(ctx, '', 30)
    key('return')
    return true
  end},
}
