-- UI flow: the Save Slots overlay end to end in a real run.
--   1. Brainstorm import failure: a stubbed import fails twice; each open alerts
--      and the second open retries (the flag doesn't latch on failure). Then a
--      stubbed partial import (1, 'partial') alerts and is retried the same way.
--   2. Start run A, wait for its first autosave, save it as "Alpha".
--   3. Start a *different* run B, then load Alpha with save.jkr deleted first:
--      the loaded seed must be A's (not B's), and Load must have written save.jkr.
--   4. Rename to "Beta", delete with the two-press confirm.
--   5. 10 slots over two pages; overwrite a page-2 slot, which then shows on
--      page 1, selected. Corrupt a slot file: its preview says "Preview unavailable".
-- Every state also checks the right column keeps one width, the panel keeps one
-- outer size (message or preview), and the action row stays inside the panel.
-- Screenshots: import_failed, import_partial, empty, saved, confirm, final, pages, page2,
-- overwrite, unreadable.
local store = require('saveslots.store')
local checkpoint = require('saveslots.checkpoint')

-- Types into the overlay's name input through the real text-input path:
-- click the input, send the keys, press return (which releases the hook).
local function type_name(ctx, text)
  ctx.assert(ctx.click('select_text_input'), 'name input not found')
  ctx.assert(G.CONTROLLER.text_input_hook, 'name input did not take the hook')
  for _ = 1, 30 do G.FUNCS.text_input_key({key = 'backspace'}) end
  for i = 1, #text do G.FUNCS.text_input_key({key = text:sub(i, i)}) end
  G.FUNCS.text_input_key({key = 'return'})
  ctx.assert(G.CONTROLLER.text_input_hook == nil, 'return did not release the name input')
end

-- The text of the alert ui.lua re-homed onto the overlay, or nil.
local function overlay_alert_text()
  local box = G.OVERLAY_MENU and G.OVERLAY_MENU.children.alert
  if not box or box.REMOVED or not box.UIRoot then return nil end
  local node = box.UIRoot.children[1]
  local dt = node and node.config and node.config.object
  local s = dt and dt.config and dt.config.string
  if type(s) == 'table' then s = s[1] end
  if type(s) == 'table' then s = s.string end
  return type(s) == 'string' and s or nil
end

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID(id) end

-- Layout invariants: the right column is one width in every state, and the
-- action row is no wider than the panel above it.
local layout = {}
local function check_layout(ctx, label)
  local right, detail, actions = uie('saveslots_right'), uie('saveslots_detail'), uie('saveslots_actions')
  ctx.assert(right and detail and actions, label..': right column nodes missing')
  local panel = detail.config.object and detail.config.object.T
  local row = actions.config.object and actions.config.object.UIRoot
  ctx.assert(panel and row, label..': detail or action box missing')
  local rw = row.children and #row.children > 0 and row.T.w or 0
  ctx.log(string.format('layout %s: right %.2f, panel %.2fx%.2f, actions %.2f', label, right.T.w, panel.w, panel.h, rw))
  layout.right = layout.right or right.T.w
  ctx.assert(math.abs(right.T.w - layout.right) < 0.01,
    string.format('%s: right column width %.2f, was %.2f', label, right.T.w, layout.right))
  layout.pw, layout.ph = layout.pw or panel.w, layout.ph or panel.h
  ctx.assert(math.abs(panel.w - layout.pw) < 0.01 and math.abs(panel.h - layout.ph) < 0.01,
    string.format('%s: panel %.2fx%.2f, was %.2fx%.2f', label, panel.w, panel.h, layout.pw, layout.ph))
  ctx.assert(rw <= panel.w + 0.01, string.format('%s: action row %.2f wider than panel %.2f', label, rw, panel.w))
end

local saved = {}    -- the slot "Alpha": id, seed, ante, dollars
local fresh = {}    -- run B, started between saving and loading
local imports = {calls = 0}

local function read_save_jkr()
  local path = G.SETTINGS.profile..'/save.jkr'
  if not love.filesystem.getInfo(path) then return nil end
  local ok, str = pcall(get_compressed, path)
  if not ok or type(str) ~= 'string' then return nil end
  local ok2, t = pcall(STR_UNPACK, str)
  return ok2 and type(t) == 'table' and t or nil
end

return {
  -- Player-slot scenario: auto-checkpoints (on by default since 0.2) would add
  -- 'Auto A<n>' slots and break the slot counts this scenario asserts.
  {name = 'no auto-checkpoints', run = function(ctx) SaveSlots.settings.auto_checkpoints = false; return true end},
  -- 1. Brainstorm import failure (main menu, before anything latches the import)
  {name = 'stub failing import', run = function(ctx)
    imports.orig = store.import_brainstorm
    store.import_brainstorm = function()
      imports.calls = imports.calls + 1
      return nil, 'x'
    end
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'import failure alerted', timeout = 5, run = function(ctx)
    local text = overlay_alert_text()
    if not text or ctx.step_time() < 0.6 then return false end
    ctx.assert(text:find('Brainstorm import failed', 1, true), 'unexpected alert: '..text)
    ctx.shot('import_failed')
    ctx.assert(imports.calls == 1, 'import called '..imports.calls..' times on first open')
    ctx.assert(ctx.find_button('exit_overlay_menu', 'overlay_menu_back_button'), 'Back should close the overlay on the menu')
    return true
  end},
  {name = 'close after the shot', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    G.FUNCS.exit_overlay_menu()
    return true
  end},
  {name = 'import retried', run = function(ctx)
    if G.OVERLAY_MENU or ctx.step_time() < 0.3 then return false end
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'import retry alerted', timeout = 5, run = function(ctx)
    local text = overlay_alert_text()
    if not text then return false end
    ctx.assert(imports.calls == 2, 'failed import was not retried on the next open (calls '..imports.calls..')')
    ctx.assert(text:find('Brainstorm import failed', 1, true), 'unexpected alert on retry: '..text)
    ctx.log('check: brainstorm import failure alerted')
    G.FUNCS.exit_overlay_menu()
    return true
  end},
  -- 1b. Partial import: n, err (the store left its flag unset) alerts and retries too.
  {name = 'stub partial import', run = function(ctx)
    if G.OVERLAY_MENU or ctx.step_time() < 0.3 then return false end
    imports.calls = 0
    store.import_brainstorm = function()
      imports.calls = imports.calls + 1
      return 1, 'partial'
    end
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'partial import alerted', timeout = 5, run = function(ctx)
    local text = overlay_alert_text()
    if not text or ctx.step_time() < 1.2 then return false end
    ctx.assert(text:find('Some Brainstorm slots could not be imported', 1, true), 'unexpected partial alert: '..text)
    ctx.assert(imports.calls == 1, 'partial import called '..imports.calls..' times on open')
    ctx.shot('import_partial')
    return true
  end},
  {name = 'close after the partial shot', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    G.FUNCS.exit_overlay_menu()
    return true
  end},
  {name = 'partial import retried', run = function(ctx)
    if G.OVERLAY_MENU or ctx.step_time() < 0.3 then return false end
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'partial retry alerted', timeout = 5, run = function(ctx)
    local text = overlay_alert_text()
    if not text then return false end
    ctx.assert(imports.calls == 2, 'partial import was latched: next open did not retry (calls '..imports.calls..')')
    ctx.assert(text:find('Some Brainstorm slots could not be imported', 1, true), 'unexpected alert on partial retry: '..text)
    ctx.log('check: partial brainstorm import alerted and retried')
    -- The real import from here on, counted: it must run once more and then latch.
    imports.calls = 0
    store.import_brainstorm = function(...)
      imports.calls = imports.calls + 1
      return imports.orig(...)
    end
    G.FUNCS.exit_overlay_menu()
    return true
  end},

  -- 2. Run A and the slot "Alpha"
  {name = 'start run', run = function(ctx)
    if G.OVERLAY_MENU then return false end
    ctx.start_run{}
    return true
  end},
  {name = 'first autosave', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and checkpoint.get() ~= nil
  end},
  {name = 'open overlay', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    ctx.assert(type(G.FUNCS.saveslots_open) == 'function', 'saveslots_open not registered')
    ctx.assert(#store.list() == 0, 'fresh profile should have no slots')
    G.FUNCS.saveslots_open()
    ctx.assert(imports.calls == 1, 'import not retried after the failures (calls '..imports.calls..')')
    return true
  end},
  {name = 'empty shot', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    ctx.assert(ctx.find_button('saveslots_save_new'), 'Save current run button missing in a run')
    ctx.assert(ctx.find_button('options', 'overlay_menu_back_button'), 'Back should return to the pause menu in a run')
    check_layout(ctx, 'empty')
    ctx.shot('empty')
    return true
  end},
  {name = 'save Alpha', run = function(ctx)
    type_name(ctx, 'Alpha')
    ctx.assert(ctx.click('saveslots_save_new'), 'saveslots_save_new not found')
    local list = store.list()
    ctx.assert(#list == 1, 'expected 1 slot, got '..#list)
    ctx.assert(list[1].name == 'Alpha', 'slot name is '..tostring(list[1].name))
    saved.id = list[1].id
    saved.seed = list[1].summary.seed
    saved.ante = list[1].summary.ante
    saved.dollars = list[1].summary.dollars
    ctx.assert(saved.seed ~= nil and saved.ante ~= nil, 'summary has no seed/ante')
    ctx.assert(saved.seed == G.GAME.pseudorandom.seed, 'slot seed is not the running seed')
    return true
  end},
  {name = 'saved shot', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1.2 then return false end
    ctx.assert(ctx.find_button('saveslots_select'), 'no row for the new slot')
    check_layout(ctx, 'saved')
    ctx.shot('saved')
    return true
  end},

  -- 3. A different run B, then load Alpha over it
  {name = 'start run B', run = function(ctx)
    fresh.prev = G.GAME
    ctx.start_run{}
    return true
  end},
  {name = 'run B autosave', timeout = 20, run = function(ctx)
    if not (G.GAME ~= fresh.prev and G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT
      and checkpoint.get() ~= nil) then return false end
    fresh.game = G.GAME
    fresh.seed = G.GAME.pseudorandom.seed
    ctx.assert(fresh.seed ~= saved.seed, 'run B got the same seed as Alpha; the load check would be vacuous')
    return true
  end},
  {name = 'open and select Alpha', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    G.FUNCS.saveslots_open()
    ctx.assert(imports.calls == 1, 'import ran again after it succeeded (calls '..imports.calls..')')
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..saved.id), 'Alpha row not found')
    ctx.assert(ctx.find_button('saveslots_load'), 'Load button missing after selecting')
    return true
  end},
  {name = 'load without save.jkr', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local path = G.SETTINGS.profile..'/save.jkr'
    if love.filesystem.getInfo(path) then love.filesystem.remove(path) end
    ctx.assert(not love.filesystem.getInfo(path), 'could not delete save.jkr before loading')
    ctx.assert(ctx.click('saveslots_load'), 'saveslots_load not found')
    -- load_run writes save.jkr synchronously, before the game can autosave.
    local t = read_save_jkr()
    ctx.assert(t, 'save.jkr missing or unreadable right after Load')
    local seed = type(t.GAME) == 'table' and type(t.GAME.pseudorandom) == 'table' and t.GAME.pseudorandom.seed
    ctx.assert(seed == saved.seed, 'save.jkr holds seed '..tostring(seed)..', slot has '..tostring(saved.seed))
    ctx.log('check: save.jkr written by load')
    return true
  end},
  {name = 'loaded', timeout = 20, run = function(ctx)
    if not (G.GAME ~= fresh.game and G.STAGE == G.STAGES.RUN and G.GAME.round_resets) then return false end
    local seed = G.GAME.pseudorandom and G.GAME.pseudorandom.seed
    ctx.assert(seed == saved.seed, 'loaded seed '..tostring(seed)..' ~= saved '..tostring(saved.seed)
      ..' (run B was '..tostring(fresh.seed)..')')
    ctx.assert(G.GAME.round_resets.ante == saved.ante and G.GAME.dollars == saved.dollars,
      'loaded ante/dollars differ from the slot')
    ctx.log('check: loaded seed matches')
    return true
  end},

  -- 4. Rename and delete
  {name = 'reopen', run = function(ctx)
    if ctx.step_time() < 1.5 then return false end
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'rename to Beta', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.assert(ctx.click('saveslots_select'), 'row not found after reopening')
    type_name(ctx, 'Beta')
    ctx.assert(ctx.click('saveslots_rename'), 'saveslots_rename not found')
    local list = store.list()
    ctx.assert(#list == 1 and list[1].id == saved.id, 'rename changed the slot set')
    ctx.assert(list[1].name == 'Beta', 'name after rename is '..tostring(list[1].name))
    return true
  end},
  {name = 'delete, first press', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(ctx.click('saveslots_delete'), 'Delete button not found')
    ctx.assert(#store.list() == 1, 'first delete press must only arm the confirm')
    return true
  end},
  {name = 'confirm shot', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    check_layout(ctx, 'confirm')
    ctx.shot('confirm')
    return true
  end},
  {name = 'delete, second press', run = function(ctx)
    ctx.assert(ctx.click('saveslots_delete'), 'Confirm delete button not found')
    ctx.assert(#store.list() == 0, 'slot still listed after confirming delete')
    return true
  end},
  {name = 'final shot', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1.2 then return false end
    check_layout(ctx, 'final')
    ctx.shot('final')
    return true
  end},

  -- 5. Paging: 10 slots fill page 1 with the 8 newest and spill 2 onto page 2.
  {name = 'fill two pages', run = function(ctx)
    for i = 1, 10 do
      ctx.assert(store.save(checkpoint.get(), 'Slot '..i), 'store.save failed for slot '..i)
    end
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'full page shot', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    local list = store.list()
    ctx.assert(#list == 10, 'expected 10 slots, got '..#list)
    ctx.assert(uie('saveslots_row_'..list[8].id), 'page 1 misses the 8th newest slot')
    ctx.assert(not uie('saveslots_row_'..list[9].id), 'page 1 shows a 9th row')
    ctx.shot('pages')
    return true
  end},
  {name = 'page 2', run = function(ctx)
    ctx.assert(ctx.click('option_cycle'), 'page cycle not found')
    return true
  end},
  {name = 'page 2 shot', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local list = store.list()
    ctx.assert(ctx.find_button('saveslots_select'), 'no rows on page 2')
    ctx.assert(uie('saveslots_row_'..list[9].id), 'page 2 does not show the 9th newest slot')
    ctx.assert(not uie('saveslots_row_'..list[1].id), 'page 2 still shows the newest slot')
    ctx.shot('page2')
    return true
  end},
  -- Overwrite the oldest slot (page 2). Its saved_at becomes now, so it must be
  -- listed first. Wait for the clock to pass every saved_at so it can't tie.
  {name = 'overwrite on page 2', timeout = 5, run = function(ctx)
    local list = store.list()
    if os.time() <= list[1].saved_at then return false end
    local target = list[10]
    saved.over = target.id
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..target.id), 'page-2 row not found')
    ctx.assert(ctx.click('saveslots_overwrite'), 'Overwrite button not found')
    local after = store.list()
    ctx.assert(after[1].id == target.id, 'overwritten slot is not the newest')
    return true
  end},
  {name = 'overwrite follows to page 1', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    local list = store.list()
    local row = uie('saveslots_row_'..saved.over)
    ctx.assert(row, 'overwritten slot is not on the shown page')
    ctx.assert(uie('saveslots_row_'..list[8].id) and not uie('saveslots_row_'..list[9].id),
      'the shown page is not page 1')
    ctx.assert(row.config.chosen == 'vert', 'overwritten slot is not marked in the list')
    ctx.assert(ctx.find_button('saveslots_load'), 'overwritten slot is no longer selected')
    ctx.assert(not uie('saveslots_detail_msg'), 'overwritten slot shows a message, not its preview')
    ctx.log('check: overwrite selects page 1')
    check_layout(ctx, 'overwrite')
    ctx.shot('overwrite')
    return true
  end},
  -- An unreadable slot: garbage in its file (and no .tmp twin to fall back on).
  {name = 'corrupt a slot', run = function(ctx)
    local target = store.list()[3]
    saved.bad = target.id
    local path = G.SETTINGS.profile..'/saveslots/'..target.id..'.jkr'
    ctx.assert(love.filesystem.getInfo(path), 'slot file not at '..path)
    ctx.assert(not love.filesystem.getInfo(path..'.tmp'), 'unexpected .tmp twin')
    ctx.assert(love.filesystem.write(path, 'not a save file {{{'), 'could not corrupt '..path)
    ctx.assert(store.read(target.id) == nil, 'store.read still reads the corrupted slot')
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..target.id), 'row of the corrupted slot not found')
    return true
  end},
  {name = 'unreadable shot', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local msg = uie('saveslots_detail_msg')
    ctx.assert(msg, 'no message in the preview area for an unreadable slot')
    ctx.assert(msg.config.text == 'Preview unavailable', 'preview area says '..tostring(msg.config.text))
    ctx.assert(uie('saveslots_row_'..store.list()[1].id), 'list unusable after the preview failed')
    ctx.log('check: unreadable slot shows Preview unavailable')
    check_layout(ctx, 'unreadable')
    ctx.shot('unreadable')
    return true
  end},
}
