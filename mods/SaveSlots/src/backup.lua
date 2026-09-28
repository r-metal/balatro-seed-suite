-- saveslots.backup: profile backups and restore (0.4, T-374). Research pick [16];
-- decisions in SWARM_TASKS.md § Research picks: one automatic backup the first time a
-- profile loads each day (the newest 7 kept) plus "Back up now"; restore from the main
-- menu only, two presses (ui.lua), and the profile reloads at once.
--
-- What a backup holds: the profile's progress files, <profile>/profile.jkr (stats, high
-- scores, deck wins, challenges) and <profile>/meta.jkr (unlocks, discoveries, alerts),
-- copied byte for byte. Never save.jkr, Save Slots' own slots or the Journal.
--
-- Layout, through love.filesystem relative to the save directory; every write goes
-- through bhcore.fs (staged .tmp, read back and unpacked before it counts):
--   <profile>/saveslots/backups/<id>/profile.jkr   copies of the profile's files; a
--   <profile>/saveslots/backups/<id>/meta.jkr      source that doesn't exist (a fresh
--                                                  profile) is skipped
--   <profile>/saveslots/backups/<id>/backup.jkr    the manifest, written last: {version
--                                                  = 1, kind, taken_at, n, sizes =
--                                                  {profile = bytes, meta = bytes},
--                                                  reason?}. sizes has a key per file
--                                                  held. A folder without a readable
--                                                  manifest is not a backup (a take cut
--                                                  short); the next take sweeps it.
--   <profile>/saveslots/backups/last_auto.jkr      the marker: {date = 'YYYY-MM-DD'} of
--                                                  the last automatic backup
--   id = <stamp>-<kind>, stamp = os.date('%Y%m%d-%H%M%S'); when a backup (of either
--   kind) already has that stamp it is suffixed: <stamp>_<n>-<kind>, n = 2, 3...
--   store.lua's slot scan only takes <digits>.jkr, so it never sees this folder.
--
-- API (none of them raise; failures are nil, err)
--   backup.take(kind[, reason])  -> id | nil, err. kind = 'auto' | 'manual'. Copies
--                                   what exists of the two files now; err NOTHING
--                                   ('nothing to back up yet') when neither does.
--                                   `reason` (a short string) lands in the manifest:
--                                   restore's safety copy says 'before restore'.
--   backup.list()                -> {{id, kind, taken_at, n, sizes, size, reason}, ...},
--                                   newest first (taken_at, then n). size = the bytes
--                                   held in all; sizes.profile / sizes.meta are nil for
--                                   a file the backup does not hold.
--   backup.delete(id)            -> true | nil, err. Removes the folder and its files.
--   backup.can_restore()         -> true | nil, MAIN_MENU_ONLY ('restore works from the
--                                   main menu only'), or 'a restore is already running'.
--   backup.restore(id[, on_done]) -> true | nil, err. Refused unless can_restore() and
--                                   the backup is listed. Then, once settled (below):
--                                     1. a 'manual' safety backup of the current files
--                                        (reason 'before restore'; skipped only when
--                                        there is nothing to back up; if it fails the
--                                        restore stops, nothing written);
--                                     2. the backup's files written over the profile's
--                                        through bhcore.fs, a file it doesn't hold
--                                        dropped; any failure puts the safety copy back;
--                                     3. vanilla's own profile switch with a data reset:
--                                        G.focused_profile = G.SETTINGS.profile, then
--                                        G.FUNCS.load_profile(true).
--                                   on_done(true) runs once the profile has reloaded and
--                                   the main menu is back; on_done(false, err) when step
--                                   1 or 2 failed (the files are then as they were: the
--                                   profile is untouched), or when the reload has not
--                                   landed after RELOAD_TIMEOUT seconds.
--   backup.when_settled(fn)      Runs fn() once the game's pending profile writes are
--                                on disk: at once when nothing is pending, else from a
--                                later frame. "Back up now" goes through it, so the
--                                copy has the progress the game still held in memory.
--   backup.settled()             -> true when no profile write is pending or in flight
--                                (asks the game to push a pending one; see below).
--   backup.step()                The per-frame driver (install() runs it after every
--                                Game:update): due automatic backups, when_settled
--                                callbacks, and a restore's reload.
--   backup.install()             Wraps Game:load_profile and Game:update (after the
--                                original, with all its arguments). Runs once.
--   backup.valid_id(id)          -> whether `id` has the shape take() makes.
--   backup.KEEP_AUTO = 7, backup.FILES, backup.MAIN_MENU_ONLY, backup.NOTHING.
--
-- Automatic backups: after every Game:load_profile (the boot load and each profile
-- switch) the profile is due when its marker is not today (local calendar day). A due
-- profile is backed up once settled (so no save of the game's is half written; at boot
-- that is after the session's first save, which rewrites the files from what was just
-- loaded); a fresh profile, which has no files until that save, is retried once a
-- second from step(). After an automatic backup the marker is set and the automatic
-- ones past the newest KEEP_AUTO are deleted; manual backups are never pruned. A
-- failed automatic backup retries a minute later.
--
-- Why restore is not "write the files" (build/game/game.lua, button_callbacks.lua):
--   * Game:save_progress (game.lua:1193) snapshots the in-memory profile and the P_*
--     unlock flags, and Game:update (game.lua:2686) pushes them to the save thread
--     (engine/save_manager.lua), which rewrites profile.jkr from memory and only ever
--     adds keys to meta.jkr. Files written under a running profile are undone by the
--     next save, and a save still queued would land on top of the restore.
--   * Game:load_profile (game.lua:845) merges the file's keys into the in-memory
--     profile; it doesn't replace it.
--   * G.FUNCS.load_profile(true) (button_callbacks.lua:227) empties the memory copy
--     (G.PROFILES[focused] = {}; the files are untouched), reloads it from the files,
--     rebuilds the P_* tables from meta.jkr (Game:init_item_prototypes), and returns to
--     the main menu. So the restore writes the files first and then reloads through it.
--   Settling: a pending save (G.FILE_HANDLER.progress / .settings) is pushed now
--   (G.FILE_HANDLER.force, vanilla's own flag), then a no-op request goes to the save
--   thread's channel; the thread handles requests one at a time and ignores unknown
--   types, so once it has read ours (Channel:hasRead) every earlier write is complete.
--   A push after ours (FILE_HANDLER.last_sent_time moved) sends another.
local fs = require('bhcore.fs')

local M = {}

M.KEEP_AUTO = 7
M.FILES = {{key = 'profile', name = 'profile.jkr'}, {key = 'meta', name = 'meta.jkr'}}
M.MAIN_MENU_ONLY = 'restore works from the main menu only'
M.NOTHING = 'nothing to back up yet'
local BUSY = 'a restore is already running'
local MANIFEST = 'backup.jkr'
local KINDS = {auto = true, manual = true}
local RETRY_FAILED = 60   -- seconds before a failed automatic backup is tried again
local RELOAD_TIMEOUT = 30 -- seconds a restore waits for the profile to reload

-- Paths are computed on every call: the profile can change at any load.
local function profile_dir() return tostring(G.SETTINGS.profile) end
local function root() return profile_dir()..'/saveslots/backups' end
local function marker_path() return root()..'/last_auto.jkr' end
local function backup_dir(id) return root()..'/'..id end

-- Ids end up in paths: only the shape take() makes.
local function parse_id(id)
  if type(id) ~= 'string' then return nil end
  local stamp, rest = id:match('^(%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d)(.*)$')
  if not stamp then return nil end
  local n, kind = rest:match('^_([1-9]%d*)%-(%a+)$')
  if n then
    n = tonumber(n)
    if n < 2 then return nil end
  else
    n, kind = 1, rest:match('^%-(%a+)$')
  end
  if not KINDS[kind] then return nil end
  return stamp, n, kind
end
M.valid_id = function(id) return parse_id(id) ~= nil end

local function is_dir(path)
  local info = love.filesystem.getInfo(path)
  return info ~= nil and (info.type == nil or info.type == 'directory')
end

local function items(path)
  local ok, t = pcall(love.filesystem.getDirectoryItems, path)
  return ok and type(t) == 'table' and t or {}
end

-- Removes a backup folder: every file in it (and each .tmp twin), then the folder.
local function remove_dir(path)
  for _, f in ipairs(items(path)) do fs.drop(path..'/'..f) end
  for _, f in ipairs(M.FILES) do fs.drop(path..'/'..f.name) end
  fs.drop(path..'/'..MANIFEST)
  return fs.remove(path)
end

local function read_manifest(id)
  local m = fs.read_table(backup_dir(id)..'/'..MANIFEST)
  if type(m) ~= 'table' or not KINDS[m.kind] or type(m.sizes) ~= 'table' then return nil end
  return m
end

-- Folders under backups/ shaped like an id: {id = {stamp, n, kind}}.
local function folders()
  local out = {}
  for _, f in ipairs(items(root())) do
    local stamp, n, kind = parse_id(f)
    if stamp and is_dir(backup_dir(f)) then out[f] = {stamp = stamp, n = n, kind = kind} end
  end
  return out
end

function M.list()
  local out = {}
  for id, p in pairs(folders()) do
    local m = read_manifest(id)
    if m and m.kind == p.kind then
      local sizes, size = {}, 0
      for _, f in ipairs(M.FILES) do
        local s = tonumber(m.sizes[f.key])
        if s then sizes[f.key] = s; size = size + s end
      end
      out[#out+1] = {id = id, kind = m.kind, taken_at = tonumber(m.taken_at) or 0, n = p.n,
        sizes = sizes, size = size, reason = type(m.reason) == 'string' and m.reason or nil}
    end
  end
  table.sort(out, function(a, b)
    if a.taken_at ~= b.taken_at then return a.taken_at > b.taken_at end
    if a.n ~= b.n then return a.n > b.n end
    return a.id > b.id
  end)
  return out
end

local function find(id)
  for _, b in ipairs(M.list()) do if b.id == id then return b end end
end

-- A take cut short leaves a folder with no manifest; it is never listed. Swept here.
local function sweep_partial()
  for id in pairs(folders()) do
    if not read_manifest(id) then remove_dir(backup_dir(id)) end
  end
end

function M.take(kind, reason)
  if not KINDS[kind] then return nil, 'unknown backup kind '..tostring(kind) end
  local held = {}
  for _, f in ipairs(M.FILES) do
    local src = profile_dir()..'/'..f.name
    if love.filesystem.getInfo(src) then
      local bytes = fs.read_bytes(src)
      if not bytes then return nil, 'could not read '..f.name end
      held[#held+1] = {f = f, bytes = bytes}
    end
  end
  if #held == 0 then return nil, M.NOTHING end
  sweep_partial()
  local t = os.time()
  local stamp = os.date('%Y%m%d-%H%M%S', t)
  local n, base = 1, stamp
  while fs.exists(backup_dir(base..'-auto')) or fs.exists(backup_dir(base..'-manual')) do
    n = n + 1
    base = stamp..'_'..n
  end
  local id = base..'-'..kind
  local dir = backup_dir(id)
  if not fs.ensure_dir(dir) then return nil, 'could not create '..dir end
  local sizes = {}
  for _, h in ipairs(held) do
    local ok, err = fs.write_data(dir..'/'..h.f.name, h.bytes)
    if not ok then
      remove_dir(dir)
      return nil, h.f.name..' could not be copied ('..tostring(err)..')'
    end
    sizes[h.f.key] = #h.bytes
  end
  local manifest = {version = 1, kind = kind, taken_at = t, n = n, sizes = sizes,
    reason = type(reason) == 'string' and reason or nil}
  local ok, err = fs.write_table(dir..'/'..MANIFEST, manifest)
  if not ok then
    remove_dir(dir)
    return nil, 'manifest could not be written ('..tostring(err)..')'
  end
  return id
end

function M.delete(id)
  if not parse_id(id) then return nil, 'bad backup id' end
  local dir = backup_dir(id)
  if not fs.exists(dir) then return nil, 'no such backup' end
  if remove_dir(dir) then return true end
  return nil, 'could not remove backup '..id
end

-- Deletes the automatic backups past the newest KEEP_AUTO. Manual ones are kept.
local function prune()
  local autos = 0
  for _, b in ipairs(M.list()) do
    if b.kind == 'auto' then
      autos = autos + 1
      if autos > M.KEEP_AUTO then M.delete(b.id) end
    end
  end
end

-- Settling ---------------------------------------------------------------------

local sync = nil   -- the no-op request in the save thread's channel: {id, sent}
local waiting = {} -- when_settled callbacks, in order

function M.settled()
  local fh = G.FILE_HANDLER
  if fh and (fh.progress or fh.settings) then
    fh.force = true   -- vanilla's own flag: Game:update pushes it this frame
    sync = nil
    return false
  end
  local ch = G.SAVE_MANAGER and G.SAVE_MANAGER.channel
  if not (ch and ch.push and ch.hasRead) then return true end
  local sent = fh and fh.last_sent_time
  if sync and sync.sent == sent then
    if not ch:hasRead(sync.id) then return false end
    sync = nil
    return true
  end
  sync = {id = ch:push({type = 'saveslots_sync'}), sent = sent}
  return false
end

local function run_waiting()
  local fns = waiting
  waiting = {}
  for _, fn in ipairs(fns) do
    local ok, err = pcall(fn)
    if not ok then print('[SaveSlots] backup: '..tostring(err)) end
  end
end

function M.when_settled(fn)
  waiting[#waiting+1] = fn
  if M.settled() then run_waiting() end
end

-- Automatic backups --------------------------------------------------------------

local due = nil        -- the profile an automatic backup is due for
local next_try = 0     -- os.time() before which step() doesn't retry it

local function today() return os.date('%Y-%m-%d', os.time()) end

local function try_auto()
  if due ~= G.SETTINGS.profile then due = nil; return end
  local id, err = M.take('auto')
  if not id then
    -- A fresh profile has no files until its first save: try again in a second.
    next_try = os.time() + (err == M.NOTHING and 1 or RETRY_FAILED)
    if err ~= M.NOTHING then print('[SaveSlots] automatic backup failed: '..tostring(err)) end
    return
  end
  due = nil
  local ok, merr = fs.write_table(marker_path(), {date = today()})
  if not ok then print('[SaveSlots] backup marker not saved: '..tostring(merr)) end
  prune()
end

-- After a profile loads: due unless it already has today's automatic backup. It is
-- taken once settled: at once when nothing is pending, else from step().
local function profile_loaded()
  local m = fs.read_table(marker_path())
  if type(m) == 'table' and m.date == today() then due = nil; return end
  due = G.SETTINGS.profile
  next_try = 0
  if M.settled() then try_auto() end
end

-- Restore ------------------------------------------------------------------------

local restoring = nil  -- {id, on_done, phase = 'settle' | 'reload', reloaded, started}

local function on_main_menu()
  return G.STAGES ~= nil and G.STAGE == G.STAGES.MAIN_MENU
end

function M.can_restore()
  if restoring then return nil, BUSY end
  if not on_main_menu() then return nil, M.MAIN_MENU_ONLY end
  return true
end

local function finish(ok, err)
  local r = restoring
  restoring = nil
  if r and r.on_done then
    local cok, cerr = pcall(r.on_done, ok, err)
    if not cok then print('[SaveSlots] restore callback: '..tostring(cerr)) end
  end
end

-- Writes `src_dir`'s copies over the profile's files: a file it holds is written, one
-- it doesn't hold is dropped. `sizes` says which it holds.
local function put_files(src_dir, sizes)
  for _, f in ipairs(M.FILES) do
    local dst = profile_dir()..'/'..f.name
    if sizes[f.key] then
      local bytes = fs.read_bytes(src_dir..'/'..f.name)
      if not bytes then return nil, 'could not read the backup\'s '..f.name end
      local ok, err = fs.write_data(dst, bytes)
      if not ok then return nil, f.name..' could not be written ('..tostring(err)..')' end
    elseif not fs.drop(dst) then
      return nil, f.name..' could not be removed'
    end
  end
  return true
end

-- The restore proper, once the game's writes have settled.
local function commit()
  local r = restoring
  if not r then return end
  if not on_main_menu() then return finish(false, M.MAIN_MENU_ONLY) end
  local b = find(r.id)
  if not b then return finish(false, 'no such backup') end
  local safety, serr = M.take('manual', 'before restore')
  if not safety and serr ~= M.NOTHING then
    return finish(false, 'the safety backup failed ('..tostring(serr)..')')
  end
  local ok, err = put_files(backup_dir(b.id), b.sizes)
  if not ok then
    -- Back to how it was: the safety copy, or no files when there was nothing to copy.
    local undo = safety and find(safety)
    local rok
    if safety then rok = undo and put_files(backup_dir(safety), undo.sizes)
    else rok = put_files(nil, {}) end
    return finish(false, err..(rok and '' or '; the profile could not be put back'))
  end
  r.phase, r.reloaded, r.started = 'reload', false, os.time()
  G.focused_profile = G.SETTINGS.profile
  G.FUNCS.load_profile(true)
end

function M.restore(id, on_done)
  local ok, err = M.can_restore()
  if not ok then return nil, err end
  if not parse_id(id) or not find(id) then return nil, 'no such backup' end
  restoring = {id = id, on_done = on_done, phase = 'settle'}
  M.when_settled(commit)
  return true
end

-- Driver -------------------------------------------------------------------------

function M.step()
  local auto = due and os.time() >= next_try
  if (auto or #waiting > 0) and M.settled() then
    if auto then try_auto() end
    run_waiting()
  end
  local r = restoring
  if r and r.phase == 'reload' then
    if r.reloaded and on_main_menu() and G.MAIN_MENU_UI and not G.screenwipe then
      finish(true)
    elseif os.time() - r.started > RELOAD_TIMEOUT then
      finish(false, 'the profile did not reload')
    end
  end
end

local installed = false
function M.install()
  if installed then return end
  installed = true
  if not Game then return end
  local orig_load_profile = Game.load_profile
  if orig_load_profile then
    Game.load_profile = function(self, ...)
      local ret = orig_load_profile(self, ...)
      if restoring and restoring.phase == 'reload' then restoring.reloaded = true end
      local ok, err = pcall(profile_loaded)
      if not ok then print('[SaveSlots] backup: '..tostring(err)) end
      return ret
    end
  end
  local orig_update = Game.update
  if orig_update then
    Game.update = function(self, ...)
      local ret = orig_update(self, ...)
      local ok, err = pcall(M.step)
      if not ok then print('[SaveSlots] backup: '..tostring(err)) end
      return ret
    end
  end
end

return M
