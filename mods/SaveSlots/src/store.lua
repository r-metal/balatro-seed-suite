-- Named saves on disk: <profile>/saveslots/<id>.jkr + index.jkr. Contract: docs/SPEC.md.
--
-- Layout (D7), all through love.filesystem, relative to the save directory:
--   <profile>/saveslots/<id>.jkr   one run each, same compressed format as save.jkr
--                                  (a slot file can be dropped in as save.jkr by hand)
--   <profile>/saveslots/index.jkr  {version=1, imported_brainstorm=bool,
--                                   slots={[id]={name, saved_at, summary, origin?}}}
--   origin = 'brainstorm:<k>' marks a copy of saveState<k>. It is additive: indexes
--   without it load as they are, and entries without it are the player's own slots.
--   meta (0.2, docs/contracts-0.2.md § SaveSlots 0.2) is additive the same way:
--   {kind = 'save'|'checkpoint'|'practice'|'hunt', target?, notes?, run_id?, origin?,
--   favorite?, ...}. favorite = true pins the slot in the overlay; false clears it. An entry without it (every 0.1.0 index) is kind 'save'. The index version
--   stays 1, so a 0.1.0 build reads a 0.2 index as it is and ignores meta.
--
-- API (every function returns nil, err on failure, leaving what list/read return as it
-- was; none of them raise):
--   store.list(filter?)           -> {{id, name, saved_at, summary, meta}, ...}, newest
--                                    first. meta is a copy, kind always set. filter =
--                                    {kind = k} keeps only the entries of that kind;
--                                    {favorite = true} only the favorites (both combine).
--   store.read(id)                -> run table (the savetext for G:start_run) | nil, err
--   store.save(run, name, id?, meta?)
--                                 -> id. No id: new slot. With id: overwrite run, summary
--                                    and saved_at; the name changes only if `name` is
--                                    non-empty, and the slot keeps its meta. `meta` is
--                                    merged in like set_meta (a bad one: nil, err, and
--                                    nothing is written).
--   store.set_meta(id, meta)      -> true | nil, err. Merges meta's fields into the
--                                    entry's; every other field (and the rest of the
--                                    entry) is kept. target and notes are trimmed and
--                                    capped (TARGET_MAX, NOTES_MAX); '' clears one.
--   store.prune_checkpoints(per_run, runs)
--                                 -> number deleted | nil/number, err. Auto-checkpoints
--                                    (T-121): among kind 'checkpoint' entries with a
--                                    run_id, keeps the newest `per_run` of each run_id
--                                    and only the `runs` run_ids whose newest checkpoint
--                                    is newest; deletes the rest. Nothing else is ever
--                                    touched (player saves, practice, hunts, checkpoints
--                                    without a run_id, favorites). A failed delete is skipped and
--                                    reported in err next to the count.
--   store.rename(id, name)        -> true | nil, err
--   store.delete(id)              -> true | nil, err
--   store.summarize(run)          -> {deck, stake, ante, round, dollars, seed, state,
--                                    hands, discards, version, jokers}
--   store.import_brainstorm()     -> number imported[, err]; copies Brainstorm's saveState1-5.jkr
--                                    once per profile (D4), never touching the originals.
--                                    err is set whenever the flag is left unset (retry).
--
-- Names are trimmed and capped at NAME_MAX chars; an empty name on a new slot becomes
-- "<deck> A<ante> R<round>". Ids are tostring(os.time()), suffixed _2, _3... when taken.
-- A rebuilt index (see rebuild_index) loses meta along with names: its slots are 'save'.
local store = {}

local INDEX_VERSION = 1
local NAME_MAX = 24
local BRAINSTORM_SLOTS = 5
local TARGET_MAX, NOTES_MAX = 24, 60
store.KINDS = {'save', 'checkpoint', 'practice', 'hunt'}
store.TARGET_MAX, store.NOTES_MAX = TARGET_MAX, NOTES_MAX
local KIND_SET = {}
for _, k in ipairs(store.KINDS) do KIND_SET[k] = true end

-- Paths are computed on every call: the profile isn't known at require time and can
-- change when the player switches profiles.
local function dir() return tostring(G.SETTINGS.profile)..'/saveslots' end
local function index_path() return dir()..'/index.jkr' end
local function slot_path(id) return dir()..'/'..id..'.jkr' end

-- The verified write/read primitives live in bh-core (moved there in T-124, unchanged):
-- every file is staged through <path>.tmp and read back; see bhcore.fs's write_data.
local fs = require('bhcore.fs')
local tmp_path, load_table, load_committed = fs.tmp_path, fs.load_table, fs.read_table
local read_bytes, remove, put_raw = fs.read_bytes, fs.remove, fs.put_raw
local committed_bytes, write_data, write_table = fs.committed_bytes, fs.write_data, fs.write_table

-- Ids end up in file paths, so only accept the shape new_id() produces.
local function valid_id(id) return type(id) == 'string' and id:match('^%d+[_%d]*$') ~= nil end

-- Removes both copies of a slot. True only when neither is left.
local function drop_slot(id) return fs.drop(slot_path(id)) end

-- What stands in for a slot file that must stop being a run but can't be removed. It
-- fails to unpack, so read() refuses it and a rebuild skips it, like any corrupt slot.
-- A tombstone is not a slot: slot_exists, slot_ids_on_disk and new_id look past it, and
-- list() removes it once removal works again (sweep_tombstones).
local TOMBSTONE = 'saveslots: discarded slot'

local function is_tombstone(path)
  local info = love.filesystem.getInfo(path)
  if not info or (info.size and info.size ~= #TOMBSTONE) then return false end
  return read_bytes(path) == TOMBSTONE
end

-- A file that is there and is not a tombstone.
local function live_file(path)
  return love.filesystem.getInfo(path) ~= nil and not is_tombstone(path)
end

local function slot_exists(id)
  return live_file(slot_path(id)) or live_file(tmp_path(slot_path(id)))
end

-- Makes sure no run is readable from slot <id> any more: drop its files, or, when a
-- file can't be removed, overwrite it with the tombstone. Returns true only when both
-- files are gone; otherwise nil, err, and `unreadable` says whether the slot at least
-- reads as nothing now (every tombstone that was needed held).
local function discard_slot(id)
  if drop_slot(id) then return true end
  local errs = {}
  for _, p in ipairs({slot_path(id), tmp_path(slot_path(id))}) do
    if load_table(p) then
      local ok, err = put_raw(p, TOMBSTONE)
      if not ok then errs[#errs+1] = err end
    end
  end
  local unreadable = not load_committed(slot_path(id))
  local msg = 'could not remove slot '..id
  if unreadable then msg = msg..' (left unreadable)'
  else msg = msg..' (still readable'..(errs[1] and ': '..table.concat(errs, '; ') or '')..')' end
  return nil, msg, unreadable
end

-- Removes the tombstones left by discard_slot once the filesystem lets it. Best effort:
-- one that still can't go stays a tombstone, which is harmless.
local function sweep_tombstones()
  local ok, items = pcall(love.filesystem.getDirectoryItems, dir())
  if not ok or type(items) ~= 'table' then return end
  for _, f in ipairs(items) do
    local id = type(f) == 'string' and (f:match('^(.-)%.jkr$') or f:match('^(.-)%.jkr%.tmp$'))
    if valid_id(id) and is_tombstone(dir()..'/'..f) then remove(dir()..'/'..f) end
  end
end

-- The slot's files as they are now, for restore_slot.
local function snapshot_slot(id)
  local path = slot_path(id)
  return {committed = committed_bytes(path), main = read_bytes(path), tmp = read_bytes(tmp_path(path))}
end

-- Puts a slot back so read() returns what it did when `snap` was taken. A readable slot
-- goes through write_data (exact: on failure the slot still reads as it does now). A
-- slot with nothing readable (missing, or unreadable files) gets its raw files back.
local function restore_slot(id, snap)
  local path = slot_path(id)
  if snap.committed then
    local ok, err = write_data(path, snap.committed)
    if not ok then return nil, err end
    if committed_bytes(path) ~= snap.committed then return nil, 'restored slot reads back wrong' end
    return true
  end
  local ok, err = put_raw(path, snap.main)
  if not ok then return nil, err end
  return put_raw(tmp_path(path), snap.tmp)
end

local function fresh_index() return {version = INDEX_VERSION, imported_brainstorm = false, slots = {}} end

local function write_index(idx) return write_table(index_path(), idx) end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

-- Trimmed, capped name, or nil when nothing is left.
local function clean_name(name)
  local s = trim(name):sub(1, NAME_MAX)
  s = trim(s)
  return s ~= '' and s or nil
end

local function default_name(summary)
  return clean_name((summary.deck or 'Run')..' A'..tostring(summary.ante or '?')
    ..' R'..tostring(summary.round or '?'))
end

-- meta ----------------------------------------------------------------------

local function finite(n) return n == n and n ~= math.huge and n ~= -math.huge end

-- A copy of a meta value that STR_PACK writes back readably: strings, booleans, finite
-- numbers and tables of them keyed by strings or finite numbers. A NaN or inf would
-- pack as a bare `nan`/`inf` and make the whole index unreadable, so anything else is
-- refused (nil, err) rather than stored.
local function copy_value(v, depth)
  local t = type(v)
  if t == 'string' or t == 'boolean' then return v end
  if t == 'number' then
    if finite(v) then return v end
    return nil, 'numbers must be finite'
  end
  if t ~= 'table' then return nil, 'cannot store a '..t end
  if depth > 16 then return nil, 'nested too deep' end
  local out = {}
  for k, x in pairs(v) do
    if not (type(k) == 'string' or (type(k) == 'number' and finite(k))) then
      return nil, 'bad key '..tostring(k)
    end
    local c, err = copy_value(x, depth + 1)
    if c == nil then return nil, err end
    out[k] = c
  end
  return out
end

-- Trimmed text capped at `max` chars; '' when nothing is left (the caller clears it).
local function clean_text(s, max) return trim(trim(s):sub(1, max)) end

-- Checks and copies a meta table given to save/set_meta. Returns the copy, with target
-- and notes cleaned ('' meaning "clear this one"), or nil, err.
local function clean_meta(meta)
  if type(meta) ~= 'table' then return nil, 'meta must be a table' end
  local m, err = copy_value(meta, 1)
  if not m then return nil, 'bad meta: '..tostring(err) end
  if m.kind ~= nil and not KIND_SET[m.kind] then return nil, 'bad kind '..tostring(m.kind) end
  for field, max in pairs({target = TARGET_MAX, notes = NOTES_MAX}) do
    if m[field] ~= nil then
      if type(m[field]) ~= 'string' then return nil, field..' must be a string' end
      m[field] = clean_text(m[field], max)
    end
  end
  if m.run_id ~= nil and type(m.run_id) ~= 'string' then return nil, 'run_id must be a string' end
  if m.origin ~= nil and type(m.origin) ~= 'table' then return nil, 'origin must be a table' end
  if m.favorite ~= nil and type(m.favorite) ~= 'boolean' then return nil, 'favorite must be a boolean' end
  return m
end

-- `base` (an entry's meta, possibly nil or junk from disk) with `m`'s fields merged in.
-- A cleared target/notes and favorite = false are dropped. Returns nil when nothing is left, so an entry that
-- never had meta keeps the 0.1.0 shape.
local function merge_meta(base, m)
  local out = type(base) == 'table' and (copy_value(base, 1) or {}) or {}
  for k, v in pairs(m or {}) do
    if ((k == 'target' or k == 'notes') and v == '') or (k == 'favorite' and v == false) then out[k] = nil
    else out[k] = v end
  end
  return next(out) and out or nil
end

-- What list() hands out for an entry: a copy, always with a kind.
local function public_meta(e)
  local m = type(e.meta) == 'table' and copy_value(e.meta, 1) or {}
  if type(m.kind) ~= 'string' then m.kind = 'save' end
  return m
end

local function brainstorm_path(k) return tostring(G.SETTINGS.profile)..'/saveState'..k..'.jkr' end

local function brainstorm_name(k) return 'Brainstorm slot '..k end
local function brainstorm_origin(k) return 'brainstorm:'..k end

-- The same table, value for value. Only a rebuild uses it, to tell which slot files
-- are exact copies of a saveState file; the import never matches on run contents.
local function deep_equal(a, b, depth)
  if a == b then return true end
  if type(a) ~= 'table' or type(b) ~= 'table' or (depth or 0) > 64 then return false end
  for k, v in pairs(a) do
    if not deep_equal(v, b[k], (depth or 0) + 1) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

-- Orders ids that share a saved_at: "1700_10" after "1700_9" after "1700".
local function id_key(id)
  local base, suffix = id:match('^(%d+)_(%d+)$')
  return tonumber(base or id) or 0, tonumber(suffix) or 1
end

local function file_time(path)
  local info = love.filesystem.getInfo(path)
  local mt = info and tonumber(info.modtime)
  return (mt and mt > 0) and mt or os.time()
end

-- {[id]=true} for every <id>.jkr or <id>.jkr.tmp in the slot directory (tombstones aside).
local function slot_ids_on_disk()
  local ids = {}
  local ok, items = pcall(love.filesystem.getDirectoryItems, dir())
  if not ok or type(items) ~= 'table' then return ids end
  for _, f in ipairs(items) do
    local id = type(f) == 'string' and (f:match('^(.-)%.jkr$') or f:match('^(.-)%.jkr%.tmp$'))
    if valid_id(id) and not is_tombstone(dir()..'/'..f) then ids[id] = true end
  end
  return ids
end

-- The index is only a cache of names and summaries; the slot files are the truth.
-- Rebuild it from every <id>.jkr (or its .tmp twin) in the directory, never deleting
-- anything. Names and origins are lost with the index. A slot file that is an exact
-- copy of saveState<k> gets its identity back ("Brainstorm slot <k>", origin
-- brainstorm:<k>), each k going to one slot at most, oldest id first; every other slot
-- is the player's own and gets the default name. imported_brainstorm can't be known,
-- so it is set whenever any slot file exists: skipping a Brainstorm import the player
-- never got is recoverable by hand, while re-importing duplicates (against D4) is what
-- we avoid.
local function rebuild_index()
  local idx = fresh_index()
  local ids = slot_ids_on_disk()
  if not next(ids) then return idx, false end
  local bs = {}
  for k = 1, BRAINSTORM_SLOTS do bs[k] = load_table(brainstorm_path(k)) end
  local order = {}
  for id in pairs(ids) do order[#order+1] = id end
  table.sort(order, function(a, b)
    local ab, as = id_key(a)
    local bb, bs_ = id_key(b)
    if ab ~= bb then return ab < bb end
    return as < bs_
  end)
  for _, id in ipairs(order) do
    local run = load_committed(slot_path(id))
    if run then
      local summary = store.summarize(run)
      local entry = {name = default_name(summary), summary = summary}
      for k = 1, BRAINSTORM_SLOTS do
        if bs[k] and deep_equal(bs[k], run) then
          entry.name, entry.origin, bs[k] = brainstorm_name(k), brainstorm_origin(k), nil
          break
        end
      end
      local at = love.filesystem.getInfo(slot_path(id)) and slot_path(id) or tmp_path(slot_path(id))
      entry.saved_at = file_time(at)
      idx.slots[id] = entry
    end
  end
  idx.imported_brainstorm = true
  return idx, true
end

-- A missing, corrupt or foreign-version index is rebuilt from the slot files, and
-- the rebuilt one is written back (best effort) when there was anything to find.
local function read_index()
  local idx = load_committed(index_path())
  if idx and idx.version == INDEX_VERSION and type(idx.slots) == 'table' then return idx end
  local rebuilt, found = rebuild_index()
  if found then write_index(rebuilt) end
  return rebuilt
end

-- tostring(os.time()), made unique against the index and the directory. Within one
-- second the suffix only grows past the highest one listed, so a slot saved after a
-- delete in the same second (auto-checkpoint pruning does exactly that) still sorts as
-- the newest: list() breaks saved_at ties by id.
local function new_id(idx)
  local base = tostring(os.time())
  local id, n = base, 1
  for other in pairs(idx.slots) do
    local b, k = id_key(tostring(other))
    if tostring(b) == base and valid_id(other) and k > n then n = k end
  end
  if n > 1 then id = base..'_'..n end
  while idx.slots[id] or slot_exists(id) do
    n = n + 1
    id = base..'_'..n
  end
  return id
end

local function state_name(state)
  for k, v in pairs(G.STATES or {}) do
    if v == state then return k end
  end
end

function store.summarize(run)
  if type(run) ~= 'table' then return {} end
  local game = type(run.GAME) == 'table' and run.GAME or {}
  local resets = type(game.round_resets) == 'table' and game.round_resets or {}
  local areas = type(run.cardAreas) == 'table' and run.cardAreas or {}
  local jokers = type(areas.jokers) == 'table' and type(areas.jokers.cards) == 'table'
    and #areas.jokers.cards or 0
  return {
    deck = type(run.BACK) == 'table' and run.BACK.name or nil,
    stake = game.stake,
    ante = resets.ante,
    round = game.round,
    dollars = game.dollars,
    seed = type(game.pseudorandom) == 'table' and game.pseudorandom.seed or nil,
    state = state_name(run.STATE),
    hands = resets.hands,
    discards = resets.discards,
    version = run.VERSION,
    jokers = jokers,
  }
end

function store.list(filter)
  sweep_tombstones()
  local idx = read_index()
  local kind = type(filter) == 'table' and filter.kind or nil
  local fav_only = type(filter) == 'table' and filter.favorite == true
  local out, pruned = {}, false
  for id, e in pairs(idx.slots) do
    if valid_id(id) and type(e) == 'table' and slot_exists(id) then
      local meta = public_meta(e)
      if (kind == nil or meta.kind == kind) and (not fav_only or meta.favorite == true) then
        out[#out+1] = {id = id, name = e.name, saved_at = e.saved_at or 0, summary = e.summary or {},
          meta = meta}
      end
    else
      idx.slots[id] = nil
      pruned = true
    end
  end
  if pruned then write_index(idx) end
  table.sort(out, function(a, b)
    if a.saved_at ~= b.saved_at then return a.saved_at > b.saved_at end
    local ab, as = id_key(a.id)
    local bb, bs = id_key(b.id)
    if ab ~= bb then return ab > bb end
    return as > bs
  end)
  return out
end

function store.read(id)
  if not valid_id(id) then return nil, 'bad id' end
  return load_committed(slot_path(id))
end

-- Every summary field equal: the index entry describes exactly the run a read returns.
local function same_summary(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' then return false end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  return true
end

-- Writes the slot for save() and updates its entry in `idx` (not yet on disk). An
-- overwrite keeps the entry's origin and meta (`meta`, already cleaned, is merged in):
-- the slot is still the copy of that saveState, the same checkpoint, the same hunt.
local function put(idx, run, name, id, meta)
  local entry = id and idx.slots[id]
  if id and not entry then return nil, 'no such slot' end
  id = id or new_id(idx)
  -- On failure write_table leaves the slot as it was: a new id gets no file at all.
  local ok, err = write_table(slot_path(id), run)
  if not ok then return nil, err end
  local summary = store.summarize(run)
  idx.slots[id] = {
    name = clean_name(name) or (entry and entry.name) or default_name(summary),
    saved_at = os.time(),
    summary = summary,
    origin = entry and entry.origin or nil,
    meta = merge_meta(entry and entry.meta, meta),
  }
  return id
end

function store.save(run, name, id, meta)
  if type(run) ~= 'table' then return nil, 'no run' end
  if id ~= nil and not valid_id(id) then return nil, 'bad id' end
  local m
  if meta ~= nil then
    local err
    m, err = clean_meta(meta)
    if not m then return nil, err end
  end
  local idx = read_index()
  -- An overwrite is all-or-nothing: keep what the slot holds now (readable, unreadable,
  -- .tmp-only or missing), to put it back if the index can't be updated to match.
  local snap = id and idx.slots[id] and snapshot_slot(id)
  local new, err = put(idx, run, name, id, m)
  if not new then return nil, err end
  local ok, werr = write_index(idx)
  if ok then return new end
  -- write_index failing means the index on disk is still the old one (see write_data),
  -- so the slot's files must go back to matching it. A new slot is discarded, so the
  -- caller's nil means "no slot" and a later rebuild doesn't resurrect it.
  local rok, rerr
  if id then rok, rerr = restore_slot(id, snap) else rok, rerr = discard_slot(new) end
  if rok then return nil, werr end
  -- The rollback failed too. Whatever the slot holds now, the index must describe it:
  -- list it as it reads (the overwrite's entry, with the summary of what is on disk),
  -- else make the slot read as nothing so the stale entry is pruned or shown unreadable.
  if id then
    local cur = load_committed(slot_path(id))
    local fixed = false
    if cur then
      idx.slots[id].summary = store.summarize(cur)
      fixed = write_index(idx)
    end
    local e = not fixed and cur and read_index().slots[id]
    if cur and not fixed and not (e and same_summary(e.summary, store.summarize(cur))) then
      local _, derr = discard_slot(id)
      if derr then rerr = rerr..'; '..derr end
    end
  end
  return nil, 'rollback failed: '..tostring(rerr)..' (after '..tostring(werr)..')'
end

function store.prune_checkpoints(per_run, runs)
  if type(per_run) ~= 'number' or type(runs) ~= 'number' then return nil, 'bad limits' end
  local kept, rank, nruns, doomed = {}, {}, 0, {}
  -- list() is newest first, so a run_id is ranked by its newest checkpoint.
  for _, e in ipairs(store.list({kind = 'checkpoint'})) do
    local rid = e.meta.run_id
    if type(rid) == 'string' and e.meta.favorite ~= true then
      if rank[rid] == nil then
        nruns = nruns + 1
        rank[rid], kept[rid] = nruns, 0
      end
      if rank[rid] > runs or kept[rid] >= per_run then
        doomed[#doomed+1] = e.id
      else
        kept[rid] = kept[rid] + 1
      end
    end
  end
  local n, errs = 0, {}
  for _, id in ipairs(doomed) do
    local ok, err = store.delete(id)
    if ok then n = n + 1 else errs[#errs+1] = id..': '..tostring(err) end
  end
  if errs[1] then return n, 'could not delete '..table.concat(errs, '; ') end
  return n
end

function store.rename(id, name)
  local idx = read_index()
  local e = valid_id(id) and idx.slots[id]
  if not e then return nil, 'no such slot' end
  local clean = clean_name(name)
  if not clean then return nil, 'empty name' end
  e.name = clean
  return write_index(idx)
end

function store.set_meta(id, meta)
  local m, err = clean_meta(meta)
  if not m then return nil, err end
  local idx = read_index()
  local e = valid_id(id) and idx.slots[id]
  if type(e) ~= 'table' or not slot_exists(id) then return nil, 'no such slot' end
  e.meta = merge_meta(e.meta, m)
  return write_index(idx)
end

function store.delete(id)
  local idx = read_index()
  if not (valid_id(id) and idx.slots[id]) then return nil, 'no such slot' end
  -- Index first: if it can't be written, nothing has changed. A file whose removal
  -- then fails is tombstoned, so a later rebuild can't bring the deleted run back, and
  -- the delete has committed. When the run can be neither removed nor tombstoned it
  -- still reads, so its entry goes back into the index and the delete fails.
  local e = idx.slots[id]
  idx.slots[id] = nil
  local ok, err = write_index(idx)
  if not ok then return nil, err end
  local dok, derr, unreadable = discard_slot(id)
  if dok or unreadable then return true end
  local cur = load_committed(slot_path(id))
  if cur then e.summary = store.summarize(cur) end
  idx.slots[id] = e
  local rok, rerr = write_index(idx)
  if not rok then derr = derr..'; could not list it again: '..tostring(rerr) end
  return nil, derr
end

-- The index entries that are saveState<k>'s copy: named exactly "Brainstorm slot <k>" or
-- carrying origin brainstorm:<k>, in id order. Identity only: another slot holding the
-- same run (the player's own save, another saveState taken at the same point) never
-- counts.
local function copies_of(idx, k)
  local name, origin = brainstorm_name(k), brainstorm_origin(k)
  local ids = {}
  for id, e in pairs(idx.slots) do
    -- origin wins over the name: a renamed copy of another saveState never counts here.
    if valid_id(id) and type(e) == 'table' and (e.origin == origin or (e.origin == nil and e.name == name)) then
      ids[#ids+1] = id
    end
  end
  table.sort(ids, function(a, b)
    local ab, as = id_key(a)
    local bb, bs = id_key(b)
    if ab ~= bb then return ab < bb end
    return as < bs
  end)
  return ids
end

-- saveState<k> is imported when one of its copies actually reads. A copy torn by a
-- crash (a listed entry whose files don't unpack) doesn't count: it is returned as the
-- id to write the copy into again, so a retry repairs it instead of adding a second
-- "Brainstorm slot <k>".
local function imported(idx, k, claimed)
  local ids = copies_of(idx, k)
  for _, id in ipairs(ids) do
    if load_committed(slot_path(id)) then return true end
  end
  -- An entry can match two saveStates (renamed "Brainstorm slot 2" with origin 1), so
  -- never hand out an id another saveState already claimed in this pass.
  for _, id in ipairs(ids) do
    if not claimed[id] then return false, id end
  end
  return false
end

-- D4: copy Brainstorm's <profile>/saveState1..5.jkr in once. The originals are only
-- ever read. In three steps, so that no copy can ever sit on disk unlisted:
--   1. the index is written with an entry (name, summary, origin) for each copy about
--      to be made. If that fails, nothing has changed: nil, err.
--   2. each copy is written. An entry whose copy fails goes back to what it was: a new
--      one is dropped (write_table leaves no file for a new id), a reused one (a torn
--      copy being repaired) keeps its old entry and its unreadable files. Either way the
--      flag stays unset for a retry.
--   3. the index is written again with the flag. If that fails, the index from step 1
--      is what readers get: every copy made is listed, and a failed one is an entry
--      without a readable file, which list() prunes or shows unreadable and imported()
--      doesn't count. The next call repairs it or finds the copies and sets the flag.
-- A crash anywhere leaves the same states. Unreadable saveState files are skipped for
-- good.
--
-- Returns the number of copies made. Whenever the flag is left unset, a second value
-- says why ('partial: 1 of 2 failed', or the index write error), so a caller can tell
-- the player and retry; the count is still the first value.
function store.import_brainstorm()
  local idx = read_index()
  if idx.imported_brainstorm then return 0 end
  local todo, claimed = {}, {}
  for k = 1, BRAINSTORM_SLOTS do
    local path = brainstorm_path(k)
    local done, reuse = imported(idx, k, claimed)
    local run = not done and load_table(path)
    if run then
      local id = reuse or new_id(idx)
      local old = idx.slots[id]
      idx.slots[id] = {name = old and old.name or brainstorm_name(k), saved_at = file_time(path),
        summary = store.summarize(run), origin = brainstorm_origin(k)}
      claimed[id] = true
      todo[#todo+1] = {id = id, run = run, old = old}
    end
  end
  if todo[1] then
    local ok, err = write_index(idx)
    if not ok then return nil, err end
  end
  local n, failed = 0, 0
  for _, t in ipairs(todo) do
    if write_table(slot_path(t.id), t.run) then
      n = n + 1
    else
      idx.slots[t.id] = t.old
      failed = failed + 1
    end
  end
  idx.imported_brainstorm = failed == 0
  local ok, err = write_index(idx)
  if not ok and not todo[1] then return nil, err end
  if failed > 0 then
    local msg = 'partial: '..failed..' of '..#todo..' failed'
    if not ok then msg = msg..'; '..tostring(err) end
    return n, msg
  end
  if not ok then return n, 'import done, but the index was not updated: '..tostring(err) end
  return n
end

return store
