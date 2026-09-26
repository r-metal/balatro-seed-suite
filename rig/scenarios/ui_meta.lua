-- UI meta (SaveSlots 0.2): target/notes, the kind filter and 0.1.0 indexes, in a real run.
--   1. Start run A, wait for its autosave, save "Alpha" and "Bravo" through the overlay.
--   2. Alpha: set the target through the editor's text input + Return; set the notes
--      + the Save button; start a target edit and Cancel it (nothing changes). The
--      index on disk, store.list and the meta column all agree -> meta round-trips.
--   3. Make Bravo a checkpoint and add a hunt (store API: T-121/T-113 create those),
--      then step the kind filter through All / Saves / Checkpoints / Practice / Hunts
--      / Favorites
--      and check the rows shown each time; a hunt shows its filter name.
--   4. Start run B (seed LEGACY42), write a 0.1.0 index by hand (every entry without
--      meta, plus a "Legacy" slot holding run B), start run C, then list, filter and
--      Load "Legacy" through the overlay: run C becomes LEGACY42.
-- Layout: the right column and the meta column keep one size in every state, the
-- overlay fits the room, and 0.1.0 callers still find the page cycle and the name
-- input first. Screenshots: editor_target, meta_set, filter_checkpoints,
-- filter_practice, filter_hunts, legacy.
local store = require('saveslots.store')
local checkpoint = require('saveslots.checkpoint')

local LEGACY_SEED = 'LEGACY42'
local TARGET = 'Win at ante 8'
-- No '0' anywhere: vanilla's text_input_key turns it into 'o'.
local NOTES = 'Skip the Small Blind for Charm, then reroll twice'

local S = {}   -- ids and seeds across steps

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

-- Types into the hooked input through the real key path (no return).
local function type_keys(ctx, text)
  ctx.assert(G.CONTROLLER.text_input_hook, 'no text input is hooked')
  for _ = 1, 70 do G.FUNCS.text_input_key({key = 'backspace'}) end
  for i = 1, #text do G.FUNCS.text_input_key({key = text:sub(i, i)}) end
end

local function type_name(ctx, text)
  ctx.assert(ctx.click('select_text_input'), 'name input not found')
  local hook = G.CONTROLLER.text_input_hook
  ctx.assert(hook and hook.config.ref_table.prompt_text == 'Save name', 'first text input is not the name input')
  type_keys(ctx, text)
  G.FUNCS.text_input_key({key = 'return'})
end

-- Clicks the kind filter's right arrow.
local function kind_next(ctx)
  local found
  for _, dir in ipairs({'r'}) do
    local box = G.OVERLAY_MENU
    local function walk(n)
      if found or type(n) ~= 'table' then return end
      if n.config and n.config.button == 'saveslots_kind_cycle' and n.config.ref_value == dir then found = n; return end
      for _, c in ipairs(n.children or {}) do walk(c) end
    end
    walk(box and box.UIRoot)
  end
  ctx.assert(found, 'kind filter arrow not found')
  G.FUNCS[found.config.button](found)
end

local function disk_index()
  local t = STR_UNPACK(get_compressed(G.SETTINGS.profile..'/saveslots/index.jkr'))
  return t
end

-- The first line of a meta block, or its "none" text.
local function meta_text(field)
  local n = sub_uie('saveslots_meta', 'saveslots_meta_'..field..'_1')
    or sub_uie('saveslots_meta', 'saveslots_meta_'..field..'_none')
  return n and n.config.text
end

local function meta_lines(field)
  local out, i = {}, 1
  while true do
    local n = sub_uie('saveslots_meta', 'saveslots_meta_'..field..'_'..i)
    if not n then break end
    out[#out+1] = n.config.text
    i = i + 1
  end
  return table.concat(out, ' ')
end

-- One size for the right column, the preview/editor panel and the meta column in
-- every state; the whole overlay inside the room; 0.1.0 lookups unchanged.
local layout = {}
local function check_layout(ctx, label)
  local right, detail, meta = uie('saveslots_right'), sub_box('saveslots_detail'), sub_box('saveslots_meta')
  ctx.assert(right and detail and meta, label..': overlay nodes missing')
  -- The panel's extent: the kind cycle at the top left, the meta column at the right,
  -- the Back button at the bottom (UIElement T is in room units).
  local top, back, mcol = uie('saveslots_kind'), uie('overlay_menu_back_button'), uie('saveslots_meta')
  ctx.assert(top and back and mcol, label..': kind cycle, Back or meta column missing')
  local box = {x1 = top.T.x, y1 = top.T.y, x2 = mcol.T.x + mcol.T.w, y2 = back.T.y + back.T.h}
  ctx.log(string.format('layout %s: right %.2f, panel %.2fx%.2f, meta %.2fx%.2f, content x %.2f..%.2f y %.2f..%.2f in room %.2fx%.2f',
    label, right.T.w, detail.T.w, detail.T.h, meta.T.w, meta.T.h, box.x1, box.x2, box.y1, box.y2, G.ROOM.T.w, G.ROOM.T.h))
  for k, v in pairs({right = right.T.w, pw = detail.T.w, ph = detail.T.h, mw = meta.T.w, mh = meta.T.h}) do
    layout[k] = layout[k] or v
    ctx.assert(math.abs(v - layout[k]) < 0.01, string.format('%s: %s is %.2f, was %.2f', label, k, v, layout[k]))
  end
  ctx.assert(box.x1 >= 0 and box.y1 >= 0 and box.x2 <= G.ROOM.T.w and box.y2 <= G.ROOM.T.h,
    label..': the overlay does not fit the room')
  -- (With one page the page cycle is disabled and has no button at all.)
  local cyc = ctx.find_button('option_cycle')
  ctx.assert(not cyc or cyc.config.ref_table.opt_callback == 'saveslots_page',
    label..': the first option_cycle is not the page cycle')
  local input = ctx.find_button('select_text_input')
  ctx.assert(input and input.children[1].children[1].config.ref_table.prompt_text == 'Save name',
    label..': the first text input is not the name input')
end

local function rows_shown(ids)
  local out = {}
  for name, id in pairs(ids) do out[name] = uie('saveslots_row_'..id) ~= nil end
  return out
end

local function expect_rows(ctx, label, want)
  local arrow = ctx.find_button('saveslots_kind_cycle')
  local shown = arrow and arrow.config.ref_table.current_option_val
  ctx.assert(shown == label:match('^(%S+)'), 'kind filter shows '..tostring(shown)..', expected '..label)
  local got = rows_shown({alpha = S.alpha, bravo = S.bravo, hunt = S.hunt})
  for name, shown in pairs(got) do
    ctx.assert(shown == (want[name] == true),
      string.format('filter %s: %s is %s', label, name, shown and 'shown' or 'hidden'))
  end
end

return {
  -- Player-slot scenario: auto-checkpoints (on by default since 0.2) would add
  -- 'Auto A<n>' slots and break the slot counts this scenario asserts.
  {name = 'no auto-checkpoints', run = function(ctx) SaveSlots.settings.auto_checkpoints = false; return true end},
  -- 1. Run A, two slots
  {name = 'start run A', run = function(ctx)
    ctx.start_run{}
    return true
  end},
  {name = 'run A autosave', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and checkpoint.get() ~= nil
  end},
  {name = 'save Alpha and Bravo', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    G.FUNCS.saveslots_open()
    type_name(ctx, 'Alpha')
    ctx.assert(ctx.click('saveslots_save_new'), 'Save current run not found')
    type_name(ctx, 'Bravo')
    ctx.assert(ctx.click('saveslots_save_new'), 'Save current run not found')
    local list = store.list()
    ctx.assert(#list == 2, 'expected 2 slots, got '..#list)
    for _, e in ipairs(list) do
      S[e.name:lower()] = e.id
      ctx.assert(e.meta and e.meta.kind == 'save', e.name..' is not kind save')
    end
    ctx.assert(S.alpha and S.bravo, 'Alpha/Bravo not listed by name')
    return true
  end},

  -- 2. Target and notes through the editor
  {name = 'edit target', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    check_layout(ctx, 'saved')
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.alpha), 'Alpha row not found')
    ctx.assert(meta_text('target') == 'No target', 'fresh slot shows target '..tostring(meta_text('target')))
    ctx.assert(ctx.click('saveslots_edit_target'), 'Edit target button not found')
    local hook = G.CONTROLLER.text_input_hook
    ctx.assert(hook and hook.UIBox == sub_box('saveslots_detail'), 'the editor input was not hooked on open')
    ctx.assert(hook.config.ref_table.max_length == 24, 'target input max_length '..tostring(hook.config.ref_table.max_length))
    ctx.assert(ctx.find_button('saveslots_edit_save') and ctx.find_button('saveslots_edit_cancel'),
      'Save/Cancel missing while editing')
    ctx.assert(not ctx.find_button('saveslots_load'), 'Load still offered while editing')
    type_keys(ctx, TARGET)
    return true
  end},
  {name = 'editor shot', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    check_layout(ctx, 'editor_target')
    ctx.shot('editor_target')
    return true
  end},
  {name = 'return commits the target', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    G.FUNCS.text_input_key({key = 'return'})
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'return did not release the editor input')
    local e = store.list()
    local a
    for _, x in ipairs(e) do if x.id == S.alpha then a = x end end
    ctx.assert(a and a.meta.target == TARGET, 'target after return: '..tostring(a and a.meta.target))
    return true
  end},
  {name = 'target shown', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(not uie('saveslots_detail') or not sub_uie('saveslots_detail', 'text_input'), 'editor still open after return')
    ctx.assert(meta_lines('target') == TARGET, 'meta column shows target '..tostring(meta_lines('target')))
    ctx.assert(ctx.find_button('saveslots_load'), 'actions not back after the edit')
    return true
  end},
  {name = 'edit notes with the Save button', run = function(ctx)
    ctx.assert(ctx.click('saveslots_edit_notes'), 'Edit notes button not found')
    local hook = G.CONTROLLER.text_input_hook
    ctx.assert(hook and hook.config.ref_table.max_length == 60, 'notes input not hooked with 60 chars')
    type_keys(ctx, NOTES)
    ctx.assert(ctx.click('saveslots_edit_save'), 'Save button not found')
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'Save left the removed input hooked')
    return true
  end},
  {name = 'cancel changes nothing', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.assert(ctx.click('saveslots_edit_target'), 'Edit target button not found')
    ctx.assert(G.CONTROLLER.text_input_hook.config.ref_table.ref_table.edit_text == TARGET,
      'editor does not start from the current target')
    type_keys(ctx, 'Throwaway')
    ctx.assert(ctx.click('saveslots_edit_cancel'), 'Cancel button not found')
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'Cancel left the removed input hooked')
    return true
  end},
  {name = 'meta round-trips', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1.2 then return false end
    local e = disk_index().slots[S.alpha]
    ctx.assert(e and e.meta, 'no meta in the index on disk')
    ctx.assert(e.meta.target == TARGET, 'disk target '..tostring(e.meta.target))
    ctx.assert(e.meta.notes == NOTES, 'disk notes '..tostring(e.meta.notes))
    ctx.assert(e.name == 'Alpha', 'meta edits changed the name')
    ctx.assert(disk_index().slots[S.bravo].meta == nil, 'Bravo got meta it was never given')
    ctx.assert(meta_lines('target') == TARGET, 'meta column target '..meta_lines('target'))
    ctx.assert(meta_lines('notes') == NOTES, 'meta column notes '..meta_lines('notes'))
    ctx.assert(meta_text('kind') == nil and sub_uie('saveslots_meta', 'saveslots_meta_kind').config.text == 'Save',
      'kind label is not Save')
    check_layout(ctx, 'meta_set')
    ctx.shot('meta_set')
    ctx.log('check: meta round-trips')
    return true
  end},

  -- 3. Kind filter
  {name = 'make a checkpoint and a hunt', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    ctx.assert(store.set_meta(S.bravo, {kind = 'checkpoint', run_id = 'X:1'}), 'set_meta checkpoint failed')
    S.hunt = store.save(checkpoint.get(), 'Charm hunt', nil,
      {kind = 'hunt', origin = {kind = 'finder', filter_name = 'Charm + Soul', filter = {name = 'Charm + Soul'}}})
    ctx.assert(S.hunt, 'hunt slot not saved')
    G.FUNCS.exit_overlay_menu()
    return true
  end},
  {name = 'reopen', run = function(ctx)
    if G.OVERLAY_MENU or ctx.step_time() < 0.3 then return false end
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'filter: all', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.8 then return false end
    expect_rows(ctx, 'All', {alpha = true, bravo = true, hunt = true})
    kind_next(ctx)
    return true
  end},
  {name = 'filter: saves', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    expect_rows(ctx, 'Saves', {alpha = true})
    kind_next(ctx)
    return true
  end},
  {name = 'filter: checkpoints', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    expect_rows(ctx, 'Checkpoints', {bravo = true})
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.bravo), 'Bravo row not found')
    return true
  end},
  {name = 'checkpoint shot', run = function(ctx)
    if ctx.step_time() < 0.8 then return false end
    ctx.assert(sub_uie('saveslots_meta', 'saveslots_meta_kind').config.text == 'Checkpoint', 'Bravo kind label')
    check_layout(ctx, 'filter_checkpoints')
    ctx.shot('filter_checkpoints')
    return true
  end},
  {name = 'to practice', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    kind_next(ctx)
    return true
  end},
  {name = 'filter: practice', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    expect_rows(ctx, 'Practice', {})
    ctx.assert(sub_uie('saveslots_list', 'saveslots_row_'..S.bravo) == nil, 'selection kept under a filter hiding it')
    ctx.assert(not ctx.find_button('saveslots_load'), 'actions offered with nothing listed')
    ctx.shot('filter_practice')
    return true
  end},
  {name = 'to hunts', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    kind_next(ctx)
    return true
  end},
  {name = 'filter: hunts', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    expect_rows(ctx, 'Hunts', {hunt = true})
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.hunt), 'hunt row not found')
    return true
  end},
  {name = 'hunt shot', run = function(ctx)
    if ctx.step_time() < 0.8 then return false end
    ctx.assert(meta_lines('hunt') == 'Charm + Soul', 'hunt filter shows '..tostring(meta_lines('hunt')))
    check_layout(ctx, 'filter_hunts')
    ctx.shot('filter_hunts')
    return true
  end},
  {name = 'favorites (none)', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    kind_next(ctx)
    return true
  end},
  {name = 'wrap around', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    expect_rows(ctx, 'Favorites', {})
    kind_next(ctx)
    return true
  end},
  {name = 'filter wraps to all', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    expect_rows(ctx, 'All (wrapped)', {alpha = true, bravo = true, hunt = true})
    ctx.log('check: kind filter')
    G.FUNCS.exit_overlay_menu()
    return true
  end},

  -- 4. A 0.1.0 index
  {name = 'start run B', run = function(ctx)
    if G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    S.prev = G.GAME
    ctx.start_run{seed = LEGACY_SEED}
    return true
  end},
  {name = 'run B autosave', timeout = 20, run = function(ctx)
    if not (G.GAME ~= S.prev and G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT) then return false end
    local run = checkpoint.get()
    if not (run and run.GAME and run.GAME.pseudorandom.seed == LEGACY_SEED) then return false end
    S.legacy_run = run
    return true
  end},
  {name = 'write a 0.1.0 index', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    local dir = G.SETTINGS.profile..'/saveslots'
    S.legacy = '1600000000'
    ctx.assert(love.filesystem.write(dir..'/'..S.legacy..'.jkr',
      love.data.compress('string', 'deflate', STR_PACK(S.legacy_run), 1)), 'could not write the legacy slot')
    -- The 0.1.0 entry shape: {name, saved_at, summary, origin?}. Every meta goes.
    local old = disk_index()
    local idx = {version = 1, imported_brainstorm = true, slots = {}}
    for id, e in pairs(old.slots) do
      idx.slots[id] = {name = e.name, saved_at = e.saved_at, summary = e.summary, origin = e.origin}
    end
    idx.slots[S.legacy] = {name = 'Legacy', saved_at = 1600000000, summary = store.summarize(S.legacy_run)}
    if love.filesystem.getInfo(dir..'/index.jkr.tmp') then love.filesystem.remove(dir..'/index.jkr.tmp') end
    ctx.assert(love.filesystem.write(dir..'/index.jkr', love.data.compress('string', 'deflate', STR_PACK(idx), 1)),
      'could not write the 0.1.0 index')
    S.prev = G.GAME
    ctx.start_run{}
    return true
  end},
  {name = 'run C autosave', timeout = 20, run = function(ctx)
    if not (G.GAME ~= S.prev and G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT
      and checkpoint.get() ~= nil) then return false end
    S.c_game = G.GAME
    ctx.assert(G.GAME.pseudorandom.seed ~= LEGACY_SEED, 'run C got the legacy seed; the load check would be vacuous')
    return true
  end},
  {name = 'open the 0.1.0 index', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    local list = store.list()
    ctx.assert(#list == 4, 'expected 4 slots from the 0.1.0 index, got '..#list)
    for _, e in ipairs(list) do
      ctx.assert(e.meta.kind == 'save' and e.meta.target == nil, e.name..' has meta from nowhere')
    end
    ctx.assert(#store.list({kind = 'save'}) == 4 and #store.list({kind = 'checkpoint'}) == 0,
      'kind filter on a 0.1.0 index')
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'legacy listed and selected', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    -- The filter is still where step 3 left it (All); page 1 holds all four rows.
    ctx.assert(uie('saveslots_row_'..S.legacy) or sub_uie('saveslots_list', 'saveslots_row_'..S.legacy),
      'Legacy row not shown')
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.legacy), 'Legacy row not clickable')
    return true
  end},
  {name = 'legacy shot', run = function(ctx)
    if ctx.step_time() < 0.8 then return false end
    ctx.assert(sub_uie('saveslots_meta', 'saveslots_meta_kind').config.text == 'Save', 'Legacy kind label')
    ctx.assert(meta_text('target') == 'No target' and meta_text('notes') == 'No notes', 'Legacy shows meta')
    ctx.assert(not uie('saveslots_detail_msg') and not sub_uie('saveslots_detail', 'saveslots_detail_msg'),
      'Legacy preview unavailable')
    check_layout(ctx, 'legacy')
    ctx.shot('legacy')
    return true
  end},
  {name = 'load legacy', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    ctx.assert(ctx.click('saveslots_load'), 'Load not found')
    return true
  end},
  {name = 'legacy loaded', timeout = 20, run = function(ctx)
    if not (G.GAME ~= S.c_game and G.STAGE == G.STAGES.RUN and G.GAME.pseudorandom) then return false end
    ctx.assert(G.GAME.pseudorandom.seed == LEGACY_SEED, 'loaded seed '..tostring(G.GAME.pseudorandom.seed))
    ctx.assert(disk_index().version == 1, 'index version changed')
    ctx.log('check: 0.1.0 index loads')
    return true
  end},
}
