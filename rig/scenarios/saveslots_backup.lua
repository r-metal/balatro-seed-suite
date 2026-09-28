-- Save Slots profile backups (0.4, T-374), in the real game through the real buttons.
--   1. Boot: the profile's first load today leaves one automatic backup (the rig's
--      profile is fresh, so it is taken once the game's first save has written files).
--   2. Main menu -> Save Slots -> Backups -> Back up now: one manual backup more.
--   3. Restore brings progress back. A counter (career_stats.c_rounds) is set and
--      saved with a locked joker still locked, and Back up now copies that. Then the
--      counter changes and the joker is unlocked, saved (the files say so). The backup
--      is selected and restored through Restore / Confirm restore: the profile
--      reloads and the overlay comes back with "Profile restored". In memory the
--      counter is the backup's and the joker is locked again, and after the game's
--      next save_progress the files on disk equal the backup's (profile.jkr and
--      meta.jkr unpacked and compared key by key). The safety copy holds the changed
--      state.
--   4. In a run, Restore is refused with the message, arms nothing, writes nothing.
--   5. Layout: the overlay's outer size is the same with the panel open (one backup,
--      a restore armed, after the restore) as without it, on the main menu and in the
--      run, and it fits the room; the meta column's button row, now three buttons, is
--      as wide as 0.3.4's two were; 0.1.0 callers still find the page cycle and the
--      name input first.
--   Stress tail (in the run): a second page of backups, paging, Delete's two presses.
-- Screenshots: backups_panel (a restore armed), backups_restored, backups_refused,
-- backups_pages.
local backup = require('saveslots.backup')

local SEED = 'BKUP2468'
local S = {}   -- ids, keys and bytes across steps

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

local function profile() return G.PROFILES[G.SETTINGS.profile] end
local function path(name) return G.SETTINGS.profile..'/'..name end
local function disk(p) return STR_UNPACK(get_compressed(p)) end
local function backup_file(id, name) return path('saveslots/backups/'..id..'/'..name) end

local function panel_msg()
  local n = sub_uie('saveslots_detail', 'saveslots_backups_msg')
  return n and n.config.text
end

-- The label of a UIBox_button (its first line).
local function label(ctx, button)
  local e = ctx.find_button(button)
  return e and e.children[1] and e.children[1].children[1] and e.children[1].children[1].config.text
end

local function kinds()
  local out = {}
  for _, b in ipairs(backup.list()) do out[b.kind] = (out[b.kind] or 0) + 1 end
  return out
end

-- The first joker a fresh profile has locked (sorted, so every run picks the same).
local function locked_joker()
  local keys = {}
  for k, v in pairs(G.P_CENTERS) do
    if k:find('^j_') and not v.unlocked and not v.wip and not v.demo then keys[#keys+1] = k end
  end
  table.sort(keys)
  return keys[1]
end

-- Key-by-key equality; the first difference as a path, or nil.
local function diff(a, b, at)
  at = at or ''
  if type(a) ~= 'table' or type(b) ~= 'table' then
    if a ~= b then return at..': '..tostring(a)..' vs '..tostring(b) end
    return nil
  end
  for k, v in pairs(a) do
    local d = diff(v, b[k], at..'.'..tostring(k))
    if d then return d end
  end
  for k, v in pairs(b) do
    if a[k] == nil then return at..'.'..tostring(k)..': nil vs '..tostring(v) end
  end
end

-- One outer size for the overlay's panel with and without the backups panel, per
-- context (main menu / run), inside the room; 0.1.0 lookups unchanged.
local layout, recorded = {}, {}
local function check_layout(ctx, where, label_)
  local panel = G.OVERLAY_MENU and G.OVERLAY_MENU.UIRoot.children[1]
  local right, detail, meta = uie('saveslots_right'), sub_box('saveslots_detail'), sub_box('saveslots_meta')
  ctx.assert(panel and right and detail and meta, label_..': overlay nodes missing')
  local p = panel.T
  local top, back, mcol = uie('saveslots_kind'), uie('overlay_menu_back_button'), uie('saveslots_meta')
  ctx.assert(top and back and mcol, label_..': kind cycle, Back or meta column missing')
  local box = {x1 = top.T.x, y1 = top.T.y, x2 = mcol.T.x + mcol.T.w, y2 = back.T.y + back.T.h}
  ctx.log(string.format('layout %s: panel %.2fx%.2f, content x %.2f..%.2f y %.2f..%.2f in room %.2fx%.2f; right %.2f, detail %.2fx%.2f, meta %.2fx%.2f',
    label_, p.w, p.h, box.x1, box.x2, box.y1, box.y2, G.ROOM.T.w, G.ROOM.T.h, right.T.w,
    detail.T.w, detail.T.h, meta.T.w, meta.T.h))
  layout[where] = layout[where] or {}
  local base = layout[where]
  for k, v in pairs({w = p.w, h = p.h, right = right.T.w, dw = detail.T.w, dh = detail.T.h, mw = meta.T.w, mh = meta.T.h}) do
    base[k] = base[k] or v
    ctx.assert(math.abs(v - base[k]) < 0.01, string.format('%s: %s is %.2f, was %.2f', label_, k, v, base[k]))
  end
  ctx.assert(box.x1 >= 0 and box.y1 >= 0 and box.x2 <= G.ROOM.T.w and box.y2 <= G.ROOM.T.h
    and p.w <= G.ROOM.T.w and p.h <= G.ROOM.T.h, label_..': the overlay does not fit the room')
  -- The buttons under the meta column (New practice, Import code, Backups) keep the
  -- row 0.3.4 had with two: META_W 3.4 + 0.12, so the overlay is the size it was.
  local brow = uie('saveslots_backups') and uie('saveslots_backups').parent.parent
  ctx.assert(brow and math.abs(brow.T.w - 3.52) < 0.01,
    label_..': the meta buttons row is '..tostring(brow and brow.T.w)..' wide, 0.3.4 had 3.52')
  local cyc = ctx.find_button('option_cycle')
  ctx.assert(not cyc or cyc.config.ref_table.opt_callback == 'saveslots_page',
    label_..': the first option_cycle is not the page cycle')
  local input = ctx.find_button('select_text_input')
  ctx.assert(input and input.children[1].children[1].config.ref_table.prompt_text == 'Save name',
    label_..': the first text input is not the name input')
  recorded[label_] = true
end

return {
  {name = 'setup', run = function(ctx)
    SaveSlots.settings.auto_checkpoints = false
    return true
  end},

  -- 1. The automatic backup of the day
  {name = 'auto backup on load', timeout = 15, run = function(ctx)
    local l = backup.list()
    if #l == 0 then return false end
    ctx.assert(#l == 1 and l[1].kind == 'auto', 'one automatic backup expected, got '..#l)
    local m = disk(path('saveslots/backups/last_auto.jkr'))
    ctx.assert(m.date == os.date('%Y-%m-%d'), 'marker date '..tostring(m.date))
    for _, f in ipairs(backup.FILES) do
      if l[1].sizes[f.key] then
        ctx.assert(love.filesystem.read(backup_file(l[1].id, f.name)) ~= nil, f.name..' missing from the backup')
      end
    end
    S.auto = l[1].id
    ctx.log('auto backup '..l[1].id..' holds profile '..tostring(l[1].sizes.profile)..' meta '..tostring(l[1].sizes.meta))
    ctx.log('check: auto backup on load')
    return true
  end},

  -- 2. The panel and Back up now, on the main menu
  {name = 'open Save Slots', run = function(ctx)
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'overlay up', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    check_layout(ctx, 'menu', 'menu, no panel')
    ctx.assert(ctx.click('saveslots_backups'), 'Backups button not found')
    return true
  end},
  {name = 'panel up', run = function(ctx)
    ctx.assert(sub_uie('saveslots_detail', 'saveslots_backup_'..S.auto), 'the automatic backup is not listed')
    ctx.assert(ctx.find_button('saveslots_backup_now'), 'Back up now missing')
    ctx.assert(not ctx.find_button('saveslots_backup_restore'), 'Restore offered with nothing selected')
    check_layout(ctx, 'menu', 'menu, panel with one backup')
    -- The state the backup will hold: a counter and a joker still locked.
    S.key = locked_joker()
    ctx.assert(S.key and not G.P_CENTERS[S.key].unlocked, 'no locked joker on a fresh profile')
    S.rounds = (profile().career_stats.c_rounds or 0) + 7
    profile().career_stats.c_rounds = S.rounds
    G:save_progress()
    return true
  end},
  {name = 'progress saved', run = function(ctx)
    if not backup.settled() then return false end
    ctx.assert(disk(path('profile.jkr')).career_stats.c_rounds == S.rounds, 'counter not on disk')
    ctx.assert(not (disk(path('meta.jkr')).unlocked or {})[S.key], S.key..' unlocked on disk already')
    ctx.assert(ctx.click('saveslots_backup_now'), 'Back up now not found')
    return true
  end},
  {name = 'manual backup', run = function(ctx)
    local k = kinds()
    if not k.manual then return false end
    ctx.assert(k.manual == 1 and k.auto == 1, 'expected 1 auto + 1 manual')
    local l = backup.list()
    ctx.assert(l[1].kind == 'manual', 'the manual backup is not the newest')
    S.manual = l[1].id
    ctx.assert(panel_msg() == 'Backed up', 'panel says '..tostring(panel_msg()))
    ctx.assert(sub_uie('saveslots_detail', 'saveslots_backup_'..S.manual).config.chosen, 'the new backup is not selected')
    ctx.assert(disk(backup_file(S.manual, 'profile.jkr')).career_stats.c_rounds == S.rounds, 'the backup lacks the counter')
    ctx.assert(love.filesystem.read(backup_file(S.manual, 'profile.jkr')) == love.filesystem.read(path('profile.jkr')),
      'profile.jkr not copied byte for byte')
    ctx.assert(love.filesystem.read(backup_file(S.manual, 'meta.jkr')) == love.filesystem.read(path('meta.jkr')),
      'meta.jkr not copied byte for byte')
    ctx.log('check: manual backup')
    -- 3. Change both, through the game's own save.
    profile().career_stats.c_rounds = S.rounds + 5
    G.P_CENTERS[S.key].unlocked = true
    G:save_progress()
    return true
  end},
  {name = 'changed on disk', run = function(ctx)
    if not backup.settled() then return false end
    ctx.assert(disk(path('profile.jkr')).career_stats.c_rounds == S.rounds + 5, 'changed counter not on disk')
    ctx.assert((disk(path('meta.jkr')).unlocked or {})[S.key], 'the unlock is not on disk')
    S.changed_profile = love.filesystem.read(path('profile.jkr'))
    ctx.assert(ctx.click('saveslots_backup_select', 'saveslots_backup_'..S.manual), 'backup row not found')
    ctx.assert(ctx.click('saveslots_backup_restore'), 'Restore not found')
    return true
  end},
  {name = 'restore armed', run = function(ctx)
    ctx.assert(label(ctx, 'saveslots_backup_restore') == 'Confirm', 'first press did not arm: '..tostring(label(ctx, 'saveslots_backup_restore')))
    ctx.assert(backup.can_restore(), 'a restore started on the first press')
    ctx.assert(love.filesystem.read(path('profile.jkr')) == S.changed_profile, 'files written on the first press')
    check_layout(ctx, 'menu', 'menu, restore armed')
    ctx.shot('backups_panel')
    return true
  end},
  {name = 'confirm restore', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    ctx.assert(ctx.click('saveslots_backup_restore'), 'Confirm restore not found')
    ctx.assert(not backup.can_restore(), 'the second press did not start a restore')
    return true
  end},
  {name = 'profile restored', timeout = 30, run = function(ctx)
    if not (G.OVERLAY_MENU and panel_msg() == 'Profile restored') then return false end
    local p = profile()
    ctx.assert(p.career_stats.c_rounds == S.rounds, 'in memory the counter is '..tostring(p.career_stats.c_rounds))
    ctx.assert(not G.P_CENTERS[S.key].unlocked, S.key..' is still unlocked in memory')
    G:save_progress()   -- the game's next save of the restored profile
    return true
  end},
  {name = 'files match the backup', run = function(ctx)
    if not backup.settled() or ctx.step_time() < 0.3 then return false end
    for _, f in ipairs(backup.FILES) do
      local d = diff(disk(path(f.name)), disk(backup_file(S.manual, f.name)))
      ctx.assert(not d, f.name..' differs from the backup at '..tostring(d))
    end
    ctx.assert(disk(path('profile.jkr')).career_stats.c_rounds == S.rounds, 'counter on disk')
    ctx.assert(not (disk(path('meta.jkr')).unlocked or {})[S.key], 'the unlock came back on disk')
    -- the safety copy holds what the restore replaced
    local safety
    for _, b in ipairs(backup.list()) do
      if b.reason == 'before restore' then safety = b end
    end
    ctx.assert(safety and safety.kind == 'manual', 'no safety backup')
    ctx.assert(love.filesystem.read(backup_file(safety.id, 'profile.jkr')) == S.changed_profile, 'the safety copy is not the changed profile')
    ctx.assert((disk(backup_file(safety.id, 'meta.jkr')).unlocked or {})[S.key], 'the safety copy lacks the unlock')
    ctx.assert(sub_uie('saveslots_detail', 'saveslots_backup_'..safety.id), 'the safety copy is not listed')
    check_layout(ctx, 'menu', 'menu, after the restore')
    ctx.log('check: restore brings progress back')
    ctx.shot('backups_restored')
    return true
  end},

  -- 4. In a run
  {name = 'start a run', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    ctx.start_run{seed = SEED}
    return true
  end},
  {name = 'open in the run', timeout = 20, run = function(ctx)
    if not (G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and ctx.step_time() > 1.5) then return false end
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'overlay in the run', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    check_layout(ctx, 'run', 'run, no panel')
    ctx.assert(ctx.click('saveslots_backups'), 'Backups button not found in the run')
    return true
  end},
  {name = 'restore refused', run = function(ctx)
    check_layout(ctx, 'run', 'run, panel')
    S.before = {profile = love.filesystem.read(path('profile.jkr')), meta = love.filesystem.read(path('meta.jkr'))}
    S.count = #backup.list()
    ctx.assert(ctx.click('saveslots_backup_select', 'saveslots_backup_'..S.manual), 'backup row not found')
    ctx.assert(ctx.click('saveslots_backup_restore'), 'Restore not found')
    ctx.assert(panel_msg() == 'Restore works from the main menu only', 'panel says '..tostring(panel_msg()))
    ctx.assert(label(ctx, 'saveslots_backup_restore') == 'Restore', 'Restore armed in a run')
    ctx.assert(ctx.click('saveslots_backup_restore'), 'Restore not found')
    ctx.assert(label(ctx, 'saveslots_backup_restore') == 'Restore', 'Restore armed in a run')
    return true
  end},
  {name = 'nothing restored', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(G.STAGE == G.STAGES.RUN and G.OVERLAY_MENU, 'left the run')
    ctx.assert(backup.can_restore() == nil, 'can_restore in a run')
    ctx.assert(#backup.list() == S.count, 'a backup was taken')
    ctx.assert(love.filesystem.read(path('profile.jkr')) == S.before.profile
      and love.filesystem.read(path('meta.jkr')) == S.before.meta, 'profile files changed')
    ctx.assert(panel_msg() == 'Restore works from the main menu only', 'the message is gone')
    ctx.log('check: restore refused in a run')
    check_layout(ctx, 'run', 'run, restore refused')
    ctx.shot('backups_refused')
    return true
  end},

  -- Stress tail: a second page (its cycle's arrows are renamed, so the page cycle stays
  -- the first 'option_cycle'), paging, and Delete through its two presses.
  {name = 'two pages', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    for _ = 1, 6 do ctx.assert(backup.take('manual'), 'take failed') end
    S.count = #backup.list()
    ctx.assert(S.count > 7, 'expected more than a page, got '..S.count)
    ctx.assert(ctx.click('saveslots_backups'), 'Backups button not found')
    return true
  end},
  {name = 'page 2', run = function(ctx)
    ctx.assert(ctx.find_button('saveslots_backups_page_cycle'), 'no page cycle with '..S.count..' backups')
    check_layout(ctx, 'run', 'run, two pages')
    local l = backup.list()
    ctx.assert(sub_uie('saveslots_detail', 'saveslots_backup_'..l[1].id), 'page 1 lacks the newest')
    ctx.assert(not sub_uie('saveslots_detail', 'saveslots_backup_'..l[8].id), 'page 1 shows an 8th row')
    local arrow
    local function walk(n)
      if arrow or type(n) ~= 'table' then return end
      if n.config and n.config.button == 'saveslots_backups_page_cycle' and n.config.ref_value == 'r' then arrow = n; return end
      for _, c in ipairs(n.children or {}) do walk(c) end
    end
    walk(sub_box('saveslots_detail').UIRoot)
    ctx.assert(arrow, 'page cycle arrow not found')
    G.FUNCS[arrow.config.button](arrow)
    return true
  end},
  {name = 'page 2 shown', run = function(ctx)
    local l = backup.list()
    ctx.assert(sub_uie('saveslots_detail', 'saveslots_backup_'..l[8].id), 'page 2 lacks the 8th backup')
    ctx.assert(not sub_uie('saveslots_detail', 'saveslots_backup_'..l[1].id), 'page 2 shows the newest')
    check_layout(ctx, 'run', 'run, page 2')
    S.victim = l[#l].id
    ctx.assert(ctx.click('saveslots_backup_select', 'saveslots_backup_'..S.victim), 'row on page 2 not found')
    ctx.assert(ctx.click('saveslots_backup_delete'), 'Delete not found')
    ctx.assert(label(ctx, 'saveslots_backup_delete') == 'Confirm', 'first Delete press did not arm')
    ctx.assert(#backup.list() == S.count, 'deleted on the first press')
    return true
  end},
  {name = 'page 2 shot', run = function(ctx)
    if ctx.step_time() < 0.8 then return false end   -- the cycle's label pops in
    ctx.shot('backups_pages')
    return true
  end},
  {name = 'delete', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    ctx.assert(ctx.click('saveslots_backup_delete'), 'Confirm delete not found')
    ctx.assert(#backup.list() == S.count - 1, 'not deleted')
    ctx.assert(not love.filesystem.getInfo(path('saveslots/backups/'..S.victim)), 'folder left behind')
    ctx.assert(panel_msg() == 'Backup deleted', 'panel says '..tostring(panel_msg()))
    check_layout(ctx, 'run', 'run, deleted')
    return true
  end},

  -- 5. The overlay kept its size throughout
  {name = 'size unchanged', run = function(ctx)
    for _, r in ipairs({'menu, no panel', 'menu, panel with one backup', 'menu, restore armed', 'menu, after the restore',
        'run, no panel', 'run, panel', 'run, restore refused', 'run, two pages', 'run, page 2', 'run, deleted'}) do
      ctx.assert(recorded[r], 'size not measured with '..r)
    end
    ctx.assert(math.abs(layout.menu.w - layout.run.w) < 0.01 and math.abs(layout.menu.h - layout.run.h) < 0.01,
      'the overlay is another size in a run')
    ctx.log('check: size unchanged')
    return true
  end},
}
