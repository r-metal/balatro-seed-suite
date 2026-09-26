-- bhcore.fs: verified storage primitives. Contract: docs/contracts-0.2.md § bhcore.fs.
--
-- Moved, not rewritten, from SaveSlots' store (T-002c semantics; T-124). Every path is
-- relative to the save directory, through love.filesystem, which is looked up on every
-- call (tests swap it, and fault injection wraps love.filesystem.write).
--
-- Tables are stored in save.jkr's format (STR_PACK + deflate), read with vanilla's
-- get_compressed, so a file written here can be read by the game and vice versa.
--
-- API (none of them raise):
--   fs.write_table(path, t)  -> true | nil, err. Staged through <path>.tmp and read back;
--                               exact: after nil, err, read_table returns what it did.
--   fs.read_table(path)      -> t | nil, err. The file, else its verified .tmp twin.
--   fs.remove(path)          -> true when <path> is gone afterwards (existed or not).
--   fs.drop(path)            -> true when both <path> and <path>.tmp are gone.
--   fs.exists(path)          -> true when <path> is on disk (file or directory).
--   fs.ensure_dir(path)      -> true when directory <path> exists afterwards.
-- Lower level, for callers that manage their own rollback (SaveSlots' store):
--   fs.tmp_path(path), fs.load_table(path) (no .tmp fallback), fs.read_bytes(path),
--   fs.put_raw(path, bytes|nil), fs.committed_bytes(path), fs.write_data(path, bytes).
local fs = {}

-- Every file is written to <path>.tmp first; see write_data.
local function tmp_path(path) return path..'.tmp' end

-- The directory part of <path>, or nil for a file at the save directory's root.
local function parent(path) return path:match('^(.*)/[^/]*$') end

-- Reads and unpacks a compressed (or plain) .jkr file. Never raises.
local function load_table(path)
  if not love.filesystem.getInfo(path) then return nil, 'missing file' end
  local ok, str = pcall(get_compressed, path)
  if not ok or type(str) ~= 'string' then return nil, 'unreadable file' end
  local ok2, t = pcall(STR_UNPACK, str)
  if not ok2 then return nil, 'corrupt file: '..tostring(t) end
  if type(t) ~= 'table' then return nil, 'corrupt file: not a table' end
  return t
end

-- The file, or else its verified .tmp twin: a crash while rewriting the real file
-- leaves it torn, but the .tmp next to it is complete (write_data checked it).
local function load_committed(path)
  local t, err = load_table(path)
  if t then return t end
  t = load_table(tmp_path(path))
  if t then return t end
  return nil, err
end

local function read_bytes(path)
  local ok, s = pcall(love.filesystem.read, path)
  return ok and type(s) == 'string' and s or nil
end

-- True when <path> is gone afterwards (whether or not it existed).
local function remove(path)
  if love.filesystem.getInfo(path) then pcall(love.filesystem.remove, path) end
  return not love.filesystem.getInfo(path)
end

-- Puts raw bytes back exactly (nil = the file must not exist), without the .tmp dance:
-- used only to restore a copy that was unreadable anyway. Checked by reading back.
local function put_raw(path, bytes)
  if not bytes then
    if remove(path) then return true end
    return nil, 'could not remove '..path
  end
  local ok, res = pcall(love.filesystem.write, path, bytes)
  if ok and res and read_bytes(path) == bytes then return true end
  return nil, 'could not restore '..path
end

-- The bytes a reader of <path> gets now (nil when neither copy is readable).
local function committed_bytes(path)
  if load_table(path) then return read_bytes(path) end
  if load_table(tmp_path(path)) then return read_bytes(tmp_path(path)) end
end

-- love.filesystem.write returns false, err on failure (and vanilla compress_and_save
-- throws that away), so every write goes through here and is checked, then read back.
local function write_verified(path, data)
  local ok, res, werr = pcall(love.filesystem.write, path, data)
  if not ok then return nil, tostring(res) end
  if not res then return nil, tostring(werr or 'love.filesystem.write returned false') end
  if read_bytes(path) ~= data or not load_table(path) then return nil, 'read-back mismatch' end
  return true
end

-- True when directory <path> exists afterwards. love's createDirectory makes parents too.
local function ensure_dir(path)
  if type(path) ~= 'string' or path == '' then return true end
  pcall(love.filesystem.createDirectory, path)
  local info = love.filesystem.getInfo(path)
  return info ~= nil and (info.type == nil or info.type == 'directory')
end

-- Writes already-compressed bytes to <path>, creating its directory on first write.
-- love.filesystem has no rename, and write truncates before writing, so a crash at
-- any point tears whatever file is being written. Hence: write <path>.tmp and verify
-- it, then rewrite <path> and verify it, then drop the .tmp. Until the .tmp is gone
-- one of the two is always complete, and load_committed reads whichever is.
--
-- The result is exact: after true, load_committed(path) returns the new content;
-- after nil, err, it returns what it did before the call. So:
--   * A torn <path> whose .tmp is the committed copy is healed from it first, since
--     staging would overwrite that .tmp.
--   * A failed or torn staging write puts the previous .tmp bytes back (or removes a
--     .tmp that did not exist before), even unreadable ones: they may be what lists
--     the slot.
--   * A failed final rewrite puts the previous bytes back (or removes a file that did
--     not exist before) and the .tmp back likewise. When <path> can't be put back and is left
--     torn or absent, or the .tmp can't be dropped, the verified .tmp is what readers
--     get, and then the write did commit: the result says what a reader sees.
local function write_data(path, data)
  local d = parent(path)
  if d then love.filesystem.createDirectory(d) end
  local tmp = tmp_path(path)
  local ok, err
  if not load_table(path) and load_table(tmp) then
    ok, err = write_verified(path, read_bytes(tmp))
    if not ok then return nil, 'write failed: '..err end
  end
  local prev, prev_tmp = read_bytes(path), read_bytes(tmp)
  ok, err = write_verified(tmp, data)
  if not ok then
    -- A failed or torn staging write must not change what was there, not even an
    -- unreadable .tmp (it is what keeps a .tmp-only slot listed): put its bytes back.
    local rok, rerr = put_raw(tmp, prev_tmp)
    return nil, 'write failed: '..err..(rok and '' or '; '..rerr)
  end
  ok, err = write_verified(path, data)
  if ok then remove(tmp); return true end
  if prev then write_verified(path, prev) else remove(path) end
  -- The .tmp may only go while <path> is readable or absent; otherwise it is the copy.
  -- It goes back to what it was (its previous bytes, or gone), so the slot's files
  -- are as they were before the call.
  if load_table(path) or not love.filesystem.getInfo(path) then put_raw(tmp, prev_tmp) end
  if committed_bytes(path) == data then return true end
  return nil, 'write failed: '..err
end

-- Writes a table in save.jkr's format. Guarded: love.data.compress(nil) crashes (see
-- Traps in docs/SPEC.md), so only tables get this far.
local function write_table(path, t)
  if type(t) ~= 'table' then return nil, 'nothing to write' end
  local ok, data = pcall(function() return love.data.compress('string', 'deflate', STR_PACK(t), 1) end)
  if not ok or type(data) ~= 'string' then return nil, 'write failed: '..tostring(data) end
  return write_data(path, data)
end

-- Removes both copies. True only when neither is left.
local function drop(path)
  local a = remove(path)
  local b = remove(tmp_path(path))
  return a and b
end

local function exists(path)
  return type(path) == 'string' and love.filesystem.getInfo(path) ~= nil
end

fs.tmp_path = tmp_path
fs.load_table = load_table
fs.read_table = function(path)
  if type(path) ~= 'string' then return nil, 'bad path' end
  return load_committed(path)
end
fs.read_bytes = read_bytes
fs.remove = remove
fs.put_raw = put_raw
fs.committed_bytes = committed_bytes
fs.write_data = write_data
fs.write_table = function(path, t)
  if type(path) ~= 'string' or path == '' then return nil, 'bad path' end
  return write_table(path, t)
end
fs.drop = drop
fs.exists = exists
-- Exported with a type check: the internal helper treats '' as the save root (always
-- present), which callers passing nil or a number must not mistake for success.
function fs.ensure_dir(path)
  if type(path) ~= 'string' then return nil, 'bad path' end
  return ensure_dir(path)
end

return fs
