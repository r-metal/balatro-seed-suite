-- Finder names (T-360): a filter name the player types, and Save as, through the
-- Filter panel's real buttons and the real key path (G.FUNCS.text_input_key, as
-- ui_meta.lua types).
--   1. Options -> Seed Finder on a fresh profile; Add clause twice. Rename opens the
--      name editor in the deck/stake/mode row's place, its input hooked, empty, the
--      generated name as its prompt. Type "Perkeo 20 run", Return: the name is
--      that (the 0 kept) and named is true. -> "check: name typed with digits"
--      (shots names_editor, names_saved)
--   2. Add clause, cycle clause 1's key: the name stays. -> "check: name survives
--      clause edit"
--   3. filters.jkr holds it with named = true. -> "check: name on disk"
--   4. Rename (prefilled with the name), type another, Cancel: the name stays.
--      -> "check: cancel keeps old name"
--   5. Rename, then New: the hook is gone with the editor. The new filter gets the
--      same clauses (ui.set_filter): its name is the generated one; Delete goes back.
--      Rename, clear the text, Save: named is gone and the name is that generated
--      one. -> "check: empty name restores generated"
--   6. Rename, 30 of the font's widest letter typed, Cancel; Rename, a 30-char name,
--      Return: the cycle shows it. Save as, Return: one more filter, the copy
--      current right after the original, the same clauses and name, no table
--      shared. -> "check: save as copies" (shot names_copy)
--   7. The copy's clause 1 key cycled; the filter cycle back to the original: its
--      clauses are as before. -> "check: copy is independent"
--   8. The overlay root's x extent and the Filter panel's width are the same, 0.01,
--      with the editor closed, open (empty, and with 30 of the widest letter: the
--      editor row stays inside the panel), with the 30-char name in the cycle and
--      after Save as; the panel's height too, once it has clauses (the editor
--      takes the deck row's height); it fits G.ROOM each time.
--      -> "check: width unchanged"
--   9. Rename, then the filter cycle's arrow: text_input_hook is nil, and stays nil
--      once the panel is rebuilt without the editor. -> "check: hook released"
--      Then Start and Back with the editor open release it too (a Start is
--      cancelled at once), and a reopened overlay has no editor.
-- Screenshots: names_editor, names_saved, names_copy.
local ui = require('seedfinder.ui')
local fs = require('bhcore.fs')

local NAME = 'Perkeo 20 run'
local LONG = 'Perkeo 20 run with Hone and XY'   -- 30 characters
local S = {widths = {}}

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU ~= true and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function filter_box()
  local node = uie('seedfinder_filter')
  return node and node.config.object
end

-- The name editor's input args while it is hooked (create_text_input's args), else nil.
local function hooked_editor()
  local hook = G.CONTROLLER.text_input_hook
  local args = hook and hook.config and hook.config.ref_table
  if not (args and args.bh_digits and args.max_length == 30 and hook.UIBox == filter_box()) then return nil end
  return args
end

local function editor_shown()
  local box = filter_box()
  return box and box:get_UIE_by_ID('text_input') ~= nil
end

local function cycle_value(id)
  local arrow = uie('seedfinder_'..id..'_r')
  return arrow and arrow.config.ref_table.current_option_val
end

local function filters() return fs.read_table(G.SETTINGS.profile..'/seedfinder/filters.jkr') end

local function deep(v)
  if type(v) ~= 'table' then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deep(x) end
  return out
end

local function same(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- Whether a and b share any table (the copy must share none with its original).
local function shares(a, b)
  local seen = {}
  local function mark(t) if type(t) == 'table' and not seen[t] then seen[t] = true; for _, x in pairs(t) do mark(x) end end end
  mark(a)
  local found = false
  local function look(t) if type(t) == 'table' then if seen[t] then found = true end; for _, x in pairs(t) do look(x) end end end
  look(b)
  return found
end

-- Types into the hooked input through the real key path (no return).
local function type_keys(ctx, text)
  ctx.assert(G.CONTROLLER.text_input_hook, 'no text input is hooked')
  for _ = 1, 40 do G.FUNCS.text_input_key({key = 'backspace'}) end
  for i = 1, #text do G.FUNCS.text_input_key({key = text:sub(i, i)}) end
end

local function click(label, button, id, wait)
  return {name = label, timeout = 10, run = function(ctx)
    if wait and not wait() then return false end
    if G.CONTROLLER.locks.frame or ctx.step_time() < 0.2 then return false end
    return ctx.click(button, id)
  end}
end

-- Clicks Rename and waits for the editor's input to be hooked.
local function rename(label, after)
  return {name = label, timeout = 10, run = function(ctx)
    if not S.renamed then
      if G.CONTROLLER.locks.frame or ctx.step_time() < 0.3 then return false end
      ctx.assert(ctx.click('seedfinder_rename'), 'Rename not found')
      S.renamed = true
      return false
    end
    local args = hooked_editor()
    if not args or ctx.step_time() < 0.6 then return false end
    ctx.assert(uie('seedfinder_name_save') and uie('seedfinder_name_cancel'), label..': no Save / Cancel')
    ctx.assert(not uie('seedfinder_deck_r'), label..': the deck row is still there')
    S.renamed = nil
    if after then after(ctx, args) end
    return true
  end}
end

-- The overlay root's x extent and the Filter panel's width, logged and held equal
-- to the first state's, and the panel's height to the first state's with clauses
-- (the empty filter's placeholder row is 0.02 taller than two clause rows); the
-- overlay fits the room.
local function measure(ctx, label)
  local root = G.OVERLAY_MENU.UIRoot.children[1]
  local back = uie('overlay_menu_back_button')
  local x1, x2, y1, y2 = root.T.x, root.T.x + root.T.w, root.T.y, back.T.y + back.T.h
  local fw, fh = filter_box().T.w, filter_box().T.h
  ctx.log(('layout %s: overlay x %.2f..%.2f y %.2f..%.2f, filter panel %.2fx%.2f, room %.2fx%.2f')
    :format(label, x1, x2, y1, y2, fw, fh, G.ROOM.T.w, G.ROOM.T.h))
  ctx.assert(x1 >= 0 and y1 >= -0.2 and x2 <= G.ROOM.T.w and y2 <= G.ROOM.T.h, label..': the overlay does not fit the room')
  local w0 = S.widths[1]
  if w0 then
    ctx.assert(math.abs(x1 - w0.x1) <= 0.01 and math.abs(x2 - w0.x2) <= 0.01, ('%s: overlay x %.2f..%.2f, %s was %.2f..%.2f')
      :format(label, x1, x2, w0.label, w0.x1, w0.x2))
    ctx.assert(math.abs(fw - w0.fw) <= 0.01, ('%s: filter panel w %.2f, %s was %.2f'):format(label, fw, w0.label, w0.fw))
  end
  if #ui.current().clauses > 0 then
    S.fh = S.fh or {h = fh, label = label}
    ctx.assert(math.abs(fh - S.fh.h) <= 0.01, ('%s: filter panel h %.2f, %s was %.2f'):format(label, fh, S.fh.label, S.fh.h))
  end
  S.widths[#S.widths + 1] = {label = label, x1 = x1, x2 = x2, fw = fw}
end

-- The editor row fits the panel: Cancel's right edge inside the Filter panel.
local function editor_fits(ctx, label)
  local cancel, box = uie('seedfinder_name_cancel'), filter_box()
  local input = box:get_UIE_by_ID('text_input')
  ctx.log(('layout %s: input w %.2f, Cancel right %.2f, panel right %.2f'):format(label, input.T.w,
    cancel.T.x + cancel.T.w, box.T.x + box.T.w))
  ctx.assert(cancel.T.x + cancel.T.w <= box.T.x + box.T.w - 0.1, label..': the editor row overflows the Filter panel')
end

-- The widest character a player can type into the input (extended corpus): letters,
-- digits, space, - = , . and the shifted symbols the corpus takes (vanilla maps
-- shift + 1..9 - = , / to them; not shift + '.', which its pattern find turns into
-- '!'). Returns the key press {key, caps} and the char.
local function widest()
  local font, best, bw = G.LANG.font.FONT, nil, -1
  local function try(ch, key, caps)
    if font:getWidth(ch) > bw then best, bw = {key = key, caps = caps, char = ch}, font:getWidth(ch) end
  end
  for ch in ('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -=,.'):gmatch('.') do try(ch, ch, false) end
  local lower, upper = '123456789-=,/', '!@#$%^&*(_+<?'
  local corpus = ' 0!$&()<>?:{}+-=,.[]_'
  for i = 1, #lower do
    local ch = upper:sub(i, i)
    if corpus:find(ch, 1, true) then try(ch, lower:sub(i, i), true) end
  end
  return best
end

return {
  -- 1. The typed name
  click('open options', 'options'),
  click('open finder', 'seedfinder_open', nil, function() return G.OVERLAY_MENU end),
  {name = 'finder open', timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 1 then return false end
    ctx.assert(#ui.current().clauses == 0 and not ui.current().named, 'a fresh profile starts with an unnamed empty filter')
    ctx.assert(not editor_shown(), 'the editor is open on a fresh overlay')
    measure(ctx, 'editor closed')
    return true
  end},
  click('add clause 1', 'seedfinder_add'),
  click('add clause 2', 'seedfinder_add', nil, function() return #ui.current().clauses == 1 end),
  {name = 'two clauses', timeout = 5, run = function(ctx)
    if #ui.current().clauses ~= 2 or not uie('seedfinder_c2_kind_r') or ctx.step_time() < 0.5 then return false end
    measure(ctx, 'editor closed, two clauses')
    return true
  end},
  rename('rename', function(ctx, args)
    local f = ui.current()
    ctx.assert(#f.clauses == 2, 'expected two clauses')
    ctx.assert(args.ref_table.text == '', 'an unnamed filter\'s editor is not empty: '..tostring(args.ref_table.text))
    ctx.assert(args.prompt_text == f.name, 'the prompt is not the generated name: '..tostring(args.prompt_text))
    S.generated2 = f.name
    measure(ctx, 'editor open')
    editor_fits(ctx, 'editor open')
    type_keys(ctx, NAME)
    ctx.assert(args.ref_table.text == NAME, 'typed '..NAME..', the input holds '..tostring(args.ref_table.text))
  end),
  {name = 'editor shot', run = function(ctx)
    if ctx.step_time() < 0.4 then return false end
    ctx.assert(hooked_editor(), 'the editor lost its hook')
    ctx.shot('names_editor')
    return true
  end},
  {name = 'return saves', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    G.FUNCS.text_input_key({key = 'return'})
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'Return left the input hooked')
    local f = ui.current()
    ctx.assert(f.name == NAME and f.named == true, ('after Return: name "%s", named %s'):format(f.name, tostring(f.named)))
    ctx.log('check: name typed with digits ('..f.name..')')
    return true
  end},
  {name = 'name shown', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.6 then return false end
    ctx.assert(not editor_shown() and uie('seedfinder_deck_r'), 'the editor is still open after Return')
    ctx.assert(cycle_value('filter') == '1. '..NAME, 'the filter cycle shows '..tostring(cycle_value('filter')))
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'an input is hooked after the rebuild')
    ctx.shot('names_saved')
    return true
  end},

  -- 2. A clause edit keeps it
  click('add clause 3', 'seedfinder_add'),
  click('cycle clause 1 key', 'seedfinder_cycle', 'seedfinder_c1_key_r', function() return #ui.current().clauses == 3 end),
  {name = 'name survives clause edit', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local f = ui.current()
    ctx.assert(#f.clauses == 3 and f.clauses[1].key ~= f.clauses[2].key, 'clause 1 key not cycled')
    ctx.assert(f.name == NAME and f.named == true, 'a clause edit changed the name to '..tostring(f.name))
    ctx.assert(cycle_value('filter') == '1. '..NAME, 'the filter cycle shows '..tostring(cycle_value('filter')))
    ctx.log('check: name survives clause edit')
    -- 3. On disk
    local disk = filters()
    local d = disk and disk.filters and disk.filters[disk.current]
    ctx.assert(d and d.name == NAME and d.named == true and #d.clauses == 3,
      'filters.jkr holds '..tostring(d and d.name)..' named '..tostring(d and d.named))
    ctx.log('check: name on disk')
    return true
  end},

  -- 4. Cancel
  rename('rename then cancel', function(ctx, args)
    ctx.assert(args.ref_table.text == NAME, 'the editor is not prefilled with the typed name: '..tostring(args.ref_table.text))
    type_keys(ctx, 'Throwaway 9')
    ctx.assert(ctx.click('seedfinder_name_cancel'), 'Cancel not found')
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'Cancel left the input hooked')
  end),
  {name = 'cancel keeps old name', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local f = ui.current()
    ctx.assert(not editor_shown(), 'the editor is still open after Cancel')
    ctx.assert(f.name == NAME and f.named == true, 'Cancel changed the name to '..tostring(f.name))
    ctx.assert(filters().filters[1].name == NAME, 'Cancel changed the name on disk')
    ctx.log('check: cancel keeps old name')
    return true
  end},

  -- 5. The generated name, from a fresh filter with the same clauses
  rename('rename then new', function(ctx)
    S.clauses = deep(ui.current().clauses)
    ctx.assert(ctx.click('seedfinder_new'), 'New not found')
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'New left the editor hooked')
  end),
  {name = 'fresh filter, same clauses', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(not editor_shown() and G.CONTROLLER.text_input_hook == nil, 'the editor survived New')
    ctx.assert(#ui.current().clauses == 0, 'New did not make an empty filter')
    ctx.assert(ui.set_filter({name = 'fresh', deck = 'b_red', stake = 1, mode = 'all', all_unlocked = false,
      clauses = deep(S.clauses)}))
    local g = ui.current()
    ctx.assert(not g.named and g.name ~= 'fresh', 'a fresh filter kept the name it was given')
    S.generated = g.name
    ctx.log('generated name for the same clauses: '..S.generated)
    return true
  end},
  click('delete the fresh filter', 'seedfinder_delete'),
  rename('rename then clear', function(ctx, args)
    ctx.assert(ui.current().name == NAME, 'Delete did not go back to the named filter')
    type_keys(ctx, '')
    type_keys(ctx, '   ')   -- blank is empty
    ctx.assert(ctx.click('seedfinder_name_save'), 'Save not found')
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'Save left the input hooked')
    local f = ui.current()
    ctx.assert(f.named == nil, 'an empty name left named = '..tostring(f.named))
    ctx.assert(f.name == S.generated, ('the name is "%s", a fresh filter gets "%s"'):format(f.name, S.generated))
  end),
  {name = 'empty name restores generated', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(not editor_shown(), 'the editor is still open after Save')
    ctx.assert(cycle_value('filter') == '1. '..S.generated, 'the filter cycle shows '..tostring(cycle_value('filter')))
    local d = filters().filters[1]
    ctx.assert(d.named == nil and d.name == S.generated, 'filters.jkr: '..tostring(d.name)..' named '..tostring(d.named))
    ctx.log('check: empty name restores generated ('..S.generated..')')
    return true
  end},

  -- 6. Widths with the widest text, a 30-char name, and Save as
  rename('rename, widest text', function(ctx)
    local w = widest()
    type_keys(ctx, '')
    for _ = 1, 30 do G.FUNCS.text_input_key({key = w.key, caps = w.caps}) end
    ctx.log('widest character "'..w.char..'" x30: '..hooked_editor().ref_table.text)
  end),
  {name = 'widest text measured', run = function(ctx)
    if ctx.step_time() < 0.4 then return false end
    ctx.assert(#hooked_editor().ref_table.text == 30, 'the input does not hold 30 letters')
    measure(ctx, 'editor open, 30 widest letters')
    editor_fits(ctx, 'editor open, 30 widest letters')
    ctx.assert(ctx.click('seedfinder_name_cancel'), 'Cancel not found')
    return true
  end},
  rename('rename, 30-char name', function(ctx)
    ctx.assert(#LONG == 30, 'LONG is not 30 characters')
    type_keys(ctx, LONG..'extra')   -- max_length stops at 30
    G.FUNCS.text_input_key({key = 'return'})
    ctx.assert(ui.current().name == LONG and ui.current().named, 'the 30-char name was not kept: '..ui.current().name)
  end),
  {name = '30-char name in the cycle', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.6 then return false end
    ctx.assert(not editor_shown() and cycle_value('filter') == '1. '..LONG, 'the cycle shows '..tostring(cycle_value('filter')))
    measure(ctx, '30-char name in the cycle')
    S.before = {n = #filters().filters, current = filters().current, orig = deep(ui.current())}
    S.orig_table = ui.current()
    return ctx.click('seedfinder_save_as')
  end},
  {name = 'save as opens the editor on the copy', timeout = 5, run = function(ctx)
    local args = hooked_editor()
    if not args or ctx.step_time() < 0.6 then return false end
    ctx.assert(args.ref_table.text == LONG, 'the copy\'s editor holds '..tostring(args.ref_table.text))
    G.FUNCS.text_input_key({key = 'return'})
    return true
  end},
  {name = 'save as copies', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.6 then return false end
    local disk, cur = filters(), ui.current()
    ctx.assert(#disk.filters == S.before.n + 1, ('%d filters after Save as, %d before'):format(#disk.filters, S.before.n))
    ctx.assert(disk.current == S.before.current + 1, 'the copy is not current right after the original')
    ctx.assert(cur ~= S.orig_table and same(cur.clauses, S.before.orig.clauses), 'the copy\'s clauses differ')
    ctx.assert(cur.name == LONG and cur.named == true, 'the copy is '..tostring(cur.name)..' named '..tostring(cur.named))
    ctx.assert(not shares(S.orig_table, cur), 'the copy shares a table with its original')
    ctx.assert(cycle_value('filter') == (S.before.current + 1)..'. '..LONG, 'the cycle shows '..tostring(cycle_value('filter')))
    ctx.log('check: save as copies')
    measure(ctx, 'after Save as')
    ctx.log(('check: width unchanged (%d states, overlay x %.2f..%.2f)'):format(#S.widths, S.widths[1].x1, S.widths[1].x2))
    ctx.shot('names_copy')
    return true
  end},

  -- 7. The copy is independent
  click('cycle the copy\'s clause 1', 'seedfinder_cycle', 'seedfinder_c1_key_r'),
  {name = 'back to the original', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(not same(ui.current().clauses, S.before.orig.clauses), 'the copy\'s clause did not change')
    return ctx.click('seedfinder_cycle', 'seedfinder_filter_l')
  end},
  {name = 'copy is independent', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(filters().current == S.before.current and ui.current() == S.orig_table, 'the cycle is not on the original')
    ctx.assert(same(ui.current().clauses, S.before.orig.clauses), 'editing the copy changed the original: '
      ..STR_PACK(ui.current().clauses))
    ctx.assert(same(filters().filters[S.before.current].clauses, S.before.orig.clauses), 'the original changed on disk')
    ctx.log('check: copy is independent')
    return true
  end},

  -- 8. The filter cycle releases the hook
  rename('rename then cycle', function(ctx)
    type_keys(ctx, 'Lost')
    ctx.assert(ctx.click('seedfinder_cycle', 'seedfinder_filter_r'), 'the filter cycle arrow not found')
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'the filter cycle left the editor hooked')
  end),
  {name = 'hook released', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(not editor_shown() and G.CONTROLLER.text_input_hook == nil, 'the editor or its hook survived the cycle')
    ctx.assert(filters().current == S.before.current + 1, 'the cycle did not move to the copy')
    ctx.assert(S.orig_table.name == LONG, 'the cycled-away editor renamed the original')
    ctx.log('check: hook released')
    return true
  end},
  rename('rename then start', function(ctx)
    ctx.assert(ctx.click('seedfinder_start'), 'Start not found')
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'Start left the editor hooked')
  end),
  click('cancel the search', 'seedfinder_cancel'),
  {name = 'start closed the editor', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(not editor_shown() and G.CONTROLLER.text_input_hook == nil, 'the editor survived Start')
    ctx.assert(ui.search() and not ui.search().running, 'the search did not stop')
    return true
  end},
  rename('rename then back', function(ctx)
    ctx.assert(ctx.click('options', 'overlay_menu_back_button'), 'Back not found')
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'Back left the editor hooked')
  end),
  {name = 'left the overlay', timeout = 5, run = function(ctx)
    if ui.is_open() or ctx.step_time() < 0.5 then return false end
    ctx.assert(G.CONTROLLER.text_input_hook == nil, 'an input is hooked after Back')
    return ctx.click('seedfinder_open')
  end},
  {name = 'reopened without the editor', timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 0.8 then return false end
    ctx.assert(not editor_shown() and G.CONTROLLER.text_input_hook == nil, 'the reopened overlay has the editor')
    measure(ctx, 'reopened')
    return true
  end},
}
