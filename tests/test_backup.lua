-- saveslots.backup (0.4, T-374): profile backups and restore. Contract: the header of
-- mods/SaveSlots/src/backup.lua (copied into docs/contracts-0.2.md at close-out).
-- The clock is stubbed (os.time); Game, G.FUNCS.load_profile, G.FILE_HANDLER and the
-- save thread's channel are stubs shaped like vanilla's. The harness's in-memory
-- love.filesystem lists files only, so getDirectoryItems is widened here to list the
-- sub-folders too, as LÖVE's does.
local H = ...

local real_time = os.time
local now
local function clock(t) now = t; os.time = function() return now end end
local T0 = 1790000000     -- a fixed moment; days are T0 + k*86400

local PROFILE_1 = {career_stats = {c_rounds = 3, c_wins = 1}, high_scores = {furthest_ante = {amt = 4}}}
local META_1 = {unlocked = {j_joker = true}, discovered = {j_joker = true}, alerted = {}}
local PROFILE_2 = {career_stats = {c_rounds = 9, c_wins = 2}, high_scores = {furthest_ante = {amt = 6}}}
local META_2 = {unlocked = {j_joker = true, j_mr_bones = true}, discovered = {j_joker = true}, alerted = {}}

local function packed(t) return love.data.compress('string', 'deflate', STR_PACK(t), 1) end
local function put(name, t) love.filesystem.write('1/'..name, packed(t)) end
local function bytes(path) return love._files[path] end
local function unpacked(path) return STR_UNPACK(get_compressed(path)) end

local function with_folders()
  local files = love._files
  love.filesystem.getDirectoryItems = function(p)
    local out, seen, prefix = {}, {}, (p == '' and '' or p..'/')
    for k in pairs(files) do
      if k:sub(1, #prefix) == prefix then
        local head = k:sub(#prefix + 1):match('^[^/]+')
        if head and not seen[head] then seen[head] = true; out[#out+1] = head end
      end
    end
    table.sort(out)
    return out
  end
end

-- Every test: a fresh world at T0 on the main menu, profile 1, Game and load_profile
-- stubbed. Game (a global) and the clock are put back afterwards, pass or fail.
local calls
local function T(name, fn)
  H.test(name, function()
    local prev_game = Game
    clock(T0)
    with_folders()
    G.STAGE = G.STAGES.MAIN_MENU
    calls = {}
    G.FUNCS.load_profile = function(reset) calls[#calls+1] = {reset = reset, focused = G.focused_profile} end
    Game = {
      load_profile = function(self, p) G.SETTINGS.profile = p or 1 end,
      update = function(self, dt) end,
    }
    local ok, err = xpcall(fn, debug.traceback)
    Game = prev_game
    os.time = real_time
    if not ok then error(err, 0) end
  end)
end

local function backup() return require('saveslots.backup') end
local function kinds(list)
  local out = {}
  for i, b in ipairs(list) do out[i] = b.kind end
  return table.concat(out, ',')
end
local function ids(list)
  local out = {}
  for i, b in ipairs(list) do out[i] = b.id end
  return table.concat(out, ',')
end
local function stamp(t) return os.date('%Y%m%d-%H%M%S', t) end

T('take copies both files byte for byte', function()
  put('profile.jkr', PROFILE_1); put('meta.jkr', META_1)
  local b = backup()
  local id = b.take('manual')
  H.eq(id, stamp(T0)..'-manual', 'id is <stamp>-<kind>')
  local dir = '1/saveslots/backups/'..id
  H.eq(bytes(dir..'/profile.jkr'), bytes('1/profile.jkr'), 'profile.jkr copied')
  H.eq(bytes(dir..'/meta.jkr'), bytes('1/meta.jkr'), 'meta.jkr copied')
  H.eq(bytes(dir..'/profile.jkr.tmp'), nil, 'no staging copy left')
  local l = b.list()
  H.eq(#l, 1)
  H.eq(l[1].id, id); H.eq(l[1].kind, 'manual'); H.eq(l[1].taken_at, T0)
  H.eq(l[1].sizes.profile, #bytes('1/profile.jkr')); H.eq(l[1].sizes.meta, #bytes('1/meta.jkr'))
  H.eq(l[1].size, #bytes('1/profile.jkr') + #bytes('1/meta.jkr'))
  H.eq(bytes('1/profile.jkr'), packed(PROFILE_1), 'the source is untouched')
  local nothing, err = b.take('weekly')
  H.eq(nothing, nil); H.ok(err, 'an unknown kind is refused')
end)

T('a missing meta.jkr is skipped and the backup says so', function()
  put('profile.jkr', PROFILE_1)
  local b = backup()
  local id = b.take('auto')
  H.ok(id, 'backed up')
  local l = b.list()
  H.eq(l[1].sizes.profile, #bytes('1/profile.jkr'))
  H.eq(l[1].sizes.meta, nil, 'meta not held')
  H.eq(l[1].size, #bytes('1/profile.jkr'))
  H.eq(bytes('1/saveslots/backups/'..id..'/meta.jkr'), nil)
  -- neither file: nothing to back up, and no folder is left
  love.filesystem.remove('1/profile.jkr')
  clock(T0 + 5)
  local none, err = b.take('manual')
  H.eq(none, nil); H.eq(err, b.NOTHING)
  H.eq(#b.list(), 1)
  H.eq(love.filesystem.getInfo('1/saveslots/backups/'..stamp(T0 + 5)..'-manual'), nil, 'no empty folder')
end)

T('the auto backup is once per calendar day', function()
  put('profile.jkr', PROFILE_1); put('meta.jkr', META_1)
  local b = backup()
  b.install()
  Game.load_profile(G, 1)
  H.eq(kinds(b.list()), 'auto', 'first load of the day')
  H.eq(unpacked('1/saveslots/backups/last_auto.jkr').date, os.date('%Y-%m-%d', T0), 'marker holds the day')
  clock(T0 + 3600)
  Game.load_profile(G, 1)
  b.step()
  H.eq(#b.list(), 1, 'a second load the same day adds none')
  clock(T0 + 86400)
  Game.load_profile(G, 1)
  H.eq(kinds(b.list()), 'auto,auto', 'the next day adds one')
  H.eq(b.list()[1].taken_at, T0 + 86400)
  -- a new day with no load takes nothing (it is the load that counts)
  clock(T0 + 2*86400)
  b.step()
  H.eq(#b.list(), 2)
end)

T('a fresh profile gets its auto backup once it has files', function()
  local b = backup()
  b.install()
  Game.load_profile(G, 1)            -- a fresh profile: no files yet
  H.eq(#b.list(), 0)
  H.eq(love.filesystem.getInfo('1/saveslots/backups/last_auto.jkr'), nil, 'still due')
  put('meta.jkr', META_1)            -- the game's first save
  Game.update(G, 0.016)              -- same second: not retried yet
  H.eq(#b.list(), 0)
  clock(T0 + 1)
  Game.update(G, 0.016)
  local l = b.list()
  H.eq(kinds(l), 'auto')
  H.eq(l[1].sizes.meta, #bytes('1/meta.jkr')); H.eq(l[1].sizes.profile, nil)
  clock(T0 + 2)
  Game.update(G, 0.016)
  H.eq(#b.list(), 1, 'taken once')
end)

T('the auto backup waits for a save the game has pending', function()
  put('profile.jkr', PROFILE_1); put('meta.jkr', META_1)
  local pushed, read = {}, {}
  G.FILE_HANDLER = {progress = true, update_queued = true}
  G.SAVE_MANAGER = {channel = {
    push = function(self, v) pushed[#pushed+1] = v; return #pushed end,
    hasRead = function(self, i) return read[i] == true end,
  }}
  local b = backup()
  b.install()
  Game.load_profile(G, 1)
  H.eq(#b.list(), 0, 'not while a save is pending')
  H.eq(G.FILE_HANDLER.force, true)
  G.FILE_HANDLER.progress, G.FILE_HANDLER.last_sent_time = nil, 1   -- the game pushed it
  Game.update(G, 0.016)
  H.eq(#b.list(), 0, 'not while the save thread may be writing')
  H.eq(#pushed, 1)
  read[1] = true
  Game.update(G, 0.016)
  H.eq(kinds(b.list()), 'auto', 'taken once the thread has caught up')
  Game.update(G, 0.016)
  H.eq(#pushed, 1, 'idle: nothing more is sent to the save thread')
end)

T('keep 7 prunes only automatic backups', function()
  put('profile.jkr', PROFILE_1); put('meta.jkr', META_1)
  local b = backup()
  b.install()
  local manual_1 = b.take('manual')
  for day = 1, 9 do
    clock(T0 + day*86400)
    Game.load_profile(G, 1)
    if day == 4 then H.ok(b.take('manual'), 'second manual') end
  end
  local l = b.list()
  local autos, manuals = 0, 0
  for _, e in ipairs(l) do
    if e.kind == 'auto' then autos = autos + 1 else manuals = manuals + 1 end
  end
  H.eq(autos, 7, 'the newest 7 autos'); H.eq(manuals, 2, 'manuals are never pruned')
  H.eq(b.list()[#l].id, manual_1, 'the oldest manual is kept')
  for _, e in ipairs(l) do
    if e.kind == 'auto' then H.ok(e.taken_at >= T0 + 3*86400, 'an auto from day '..((e.taken_at - T0)/86400)..' was kept') end
  end
end)

T('list is newest first; a taken stamp is suffixed', function()
  put('profile.jkr', PROFILE_1)
  local b = backup()
  local a = b.take('auto')
  local m2 = b.take('manual')
  local m3 = b.take('manual')
  H.eq(a, stamp(T0)..'-auto')
  H.eq(m2, stamp(T0)..'_2-manual', 'same second, other kind: suffixed too')
  H.eq(m3, stamp(T0)..'_3-manual')
  clock(T0 + 60)
  local later = b.take('auto')
  H.eq(ids(b.list()), table.concat({later, m3, m2, a}, ','))
  H.ok(b.valid_id(m3)); H.ok(not b.valid_id(stamp(T0)..'_1-manual')); H.ok(not b.valid_id('../1-manual'))
  H.ok(not b.valid_id(stamp(T0)..'2-manual')); H.ok(not b.valid_id(stamp(T0)..'-weekly'))
  -- a folder without a manifest (a take cut short) is not listed, and the next take sweeps it
  love.filesystem.write('1/saveslots/backups/'..stamp(T0 + 90)..'-manual/profile.jkr', packed(PROFILE_1))
  love.filesystem.createDirectory('1/saveslots/backups/'..stamp(T0 + 90)..'-manual')
  H.eq(#b.list(), 4)
  clock(T0 + 120)
  b.take('manual')
  H.eq(bytes('1/saveslots/backups/'..stamp(T0 + 90)..'-manual/profile.jkr'), nil, 'partial folder swept')
end)

T('delete removes a backup and nothing else', function()
  put('profile.jkr', PROFILE_1); put('meta.jkr', META_1)
  local b = backup()
  local a = b.take('manual')
  clock(T0 + 1)
  local c = b.take('manual')
  H.ok(b.delete(a))
  H.eq(ids(b.list()), c)
  for path in pairs(love._files) do
    H.ok(not path:find(a, 1, true), 'left behind: '..path)
  end
  H.eq(love.filesystem.getInfo('1/saveslots/backups/'..a), nil, 'folder gone')
  H.eq(bytes('1/profile.jkr'), packed(PROFILE_1), 'profile untouched')
  local ok, err = b.delete(a)
  H.eq(ok, nil); H.ok(err, 'a deleted id is refused')
  ok, err = b.delete('../../1')
  H.eq(ok, nil); H.ok(err, 'a bad id is refused')
  H.eq(#b.list(), 1)
end)

T('restore refuses mid-run', function()
  put('profile.jkr', PROFILE_1); put('meta.jkr', META_1)
  local b = backup()
  local id = b.take('manual')
  put('profile.jkr', PROFILE_2); put('meta.jkr', META_2)
  G.STAGE = G.STAGES.RUN
  local done
  local ok, err = b.restore(id, function(...) done = {...} end)
  H.eq(ok, nil); H.eq(err, b.MAIN_MENU_ONLY)
  local can, why = b.can_restore()
  H.eq(can, nil); H.eq(why, b.MAIN_MENU_ONLY)
  H.eq(bytes('1/profile.jkr'), packed(PROFILE_2), 'profile untouched')
  H.eq(bytes('1/meta.jkr'), packed(META_2), 'meta untouched')
  H.eq(#calls, 0, 'no reload'); H.eq(done, nil, 'no callback')
  H.eq(#b.list(), 1, 'no safety backup')
  G.STAGE = G.STAGES.MAIN_MENU
  ok, err = b.restore('20990101-000000-auto')
  H.eq(ok, nil); H.ok(err, 'an unknown backup is refused')
end)

T('a restore target\'s files equal the backup, then the profile reloads', function()
  put('profile.jkr', PROFILE_1); put('meta.jkr', META_1)
  local b = backup()
  b.install()
  Game.load_profile(G, 1)            -- the boot load: today's auto backup
  clock(T0 + 10)
  local id = b.take('manual')
  put('profile.jkr', PROFILE_2); put('meta.jkr', META_2)
  local before_p, before_m = bytes('1/profile.jkr'), bytes('1/meta.jkr')
  clock(T0 + 30)
  local done
  H.ok(b.restore(id, function(ok, err) done = {ok = ok, err = err} end))
  local dir = '1/saveslots/backups/'..id
  H.eq(bytes('1/profile.jkr'), bytes(dir..'/profile.jkr'), 'profile.jkr is the backup\'s')
  H.eq(bytes('1/meta.jkr'), bytes(dir..'/meta.jkr'), 'meta.jkr is the backup\'s')
  H.eq(bytes('1/profile.jkr.tmp'), nil); H.eq(bytes('1/meta.jkr.tmp'), nil)
  -- the safety copy: the files as they were, kind manual
  local l = b.list()
  H.eq(kinds(l), 'manual,manual,auto')
  H.eq(l[1].reason, 'before restore'); H.eq(l[2].reason, nil)
  H.eq(bytes('1/saveslots/backups/'..l[1].id..'/profile.jkr'), before_p)
  H.eq(bytes('1/saveslots/backups/'..l[1].id..'/meta.jkr'), before_m)
  -- vanilla's profile switch with a data reset, on this profile
  H.eq(#calls, 1); H.eq(calls[1].reset, true); H.eq(calls[1].focused, 1)
  H.eq(done, nil, 'not done before the reload')
  local busy, why = b.can_restore()
  H.eq(busy, nil); H.ok(why, 'a second restore waits for the first')
  -- the reload lands: load_profile ran and the main menu is up
  Game.load_profile(G, 1)
  b.step()
  H.eq(done, nil, 'the main menu is not up yet')
  G.MAIN_MENU_UI = {}
  b.step()
  H.ok(done and done.ok, 'on_done(true)')
  H.ok(b.can_restore(), 'free again')
  H.eq(#b.list(), 3, 'the reload takes no automatic backup: the day already has one')
end)

T('a restore of a backup without meta.jkr drops it', function()
  put('profile.jkr', PROFILE_1)
  local b = backup()
  local id = b.take('manual')
  put('profile.jkr', PROFILE_2); put('meta.jkr', META_2)
  clock(T0 + 1)
  H.ok(b.restore(id))
  H.eq(bytes('1/profile.jkr'), packed(PROFILE_1))
  H.eq(love.filesystem.getInfo('1/meta.jkr'), nil, 'meta.jkr dropped: the backup had none')
end)

T('restore waits for the game\'s pending save to reach the disk', function()
  put('profile.jkr', PROFILE_1); put('meta.jkr', META_1)
  local b = backup()
  local id = b.take('manual')
  put('profile.jkr', PROFILE_2)
  -- vanilla's queue: a progress save is pending; the save thread reads requests in order
  local pushed, read = {}, {}
  G.FILE_HANDLER = {progress = true, update_queued = true, last_sent_time = 1}
  G.SAVE_MANAGER = {channel = {
    push = function(self, v) pushed[#pushed+1] = v; return #pushed end,
    hasRead = function(self, i) return read[i] == true end,
  }}
  clock(T0 + 1)
  H.ok(b.restore(id))
  H.eq(bytes('1/profile.jkr'), packed(PROFILE_2), 'nothing written while a save is pending')
  H.eq(G.FILE_HANDLER.force, true, 'the pending save is pushed now')
  H.eq(#pushed, 0)
  -- Game:update pushed it (and the thread writes the in-memory profile)
  G.FILE_HANDLER.progress, G.FILE_HANDLER.force, G.FILE_HANDLER.last_sent_time = nil, false, 2
  b.step()
  H.eq(#pushed, 1, 'a no-op request follows it'); H.eq(pushed[1].type, 'saveslots_sync')
  b.step()
  H.eq(#pushed, 1, 'one at a time'); H.eq(bytes('1/profile.jkr'), packed(PROFILE_2), 'not yet read')
  -- another push after ours: it needs one more round
  G.FILE_HANDLER.last_sent_time = 3
  read[1] = true
  b.step()
  H.eq(#pushed, 2); H.eq(#calls, 0)
  read[2] = true
  b.step()
  H.eq(bytes('1/profile.jkr'), bytes('1/saveslots/backups/'..id..'/profile.jkr'), 'written once settled')
  H.eq(#calls, 1)
end)

T('a failed write puts the profile back and does not reload', function()
  put('profile.jkr', PROFILE_1); put('meta.jkr', META_1)
  local b = backup()
  local id = b.take('manual')
  put('profile.jkr', PROFILE_2); put('meta.jkr', META_2)
  local before_p, before_m = bytes('1/profile.jkr'), bytes('1/meta.jkr')
  local write, failed = love.filesystem.write, false
  love.filesystem.write = function(p, s)
    if p == '1/meta.jkr.tmp' and not failed then failed = true; return false, 'disk full' end
    return write(p, s)
  end
  clock(T0 + 1)
  local done
  H.ok(b.restore(id, function(ok, err) done = {ok = ok, err = err} end))
  H.ok(failed, 'the fault fired')
  H.ok(done and done.ok == false and done.err:find('meta.jkr', 1, true), 'on_done(false, err): '..tostring(done and done.err))
  H.eq(bytes('1/profile.jkr'), before_p, 'profile.jkr put back')
  H.eq(bytes('1/meta.jkr'), before_m, 'meta.jkr as it was')
  H.eq(#calls, 0, 'no reload')
  H.ok(b.can_restore(), 'free again')
end)
