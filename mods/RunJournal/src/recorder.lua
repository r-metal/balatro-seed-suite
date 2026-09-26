-- runjournal.recorder: one record per run, on disk. Contract: docs/contracts-0.2.md
-- § RunJournal.
--
-- Layout (bhcore.fs, relative to the save directory):
--   <profile>/runjournal/<file>.jkr   one record each. <file> is the run_id with ':'
--                                     written as '_' (a ':' is not a legal Windows file
--                                     name character, and the game runs under Proton);
--                                     the record itself carries the real run_id.
--   <profile>/runjournal/index.jkr    {version = 1, runs = {entry, ...}}, oldest first.
--                                     entry = {run_id, file, seed, deck, stake,
--                                     started_at, ended_at?, won?, final_ante,
--                                     final_round, jokers = {keys at the end}}. It is a
--                                     cache of the records: when it is missing or
--                                     corrupt it is rebuilt from the record files.
--
-- Record: {run_id, seed, deck, stake, started_at, ended_at?, won?, final_ante,
--   final_round, antes = {[a] = {dollars_start, dollars_end, blinds = {{kind, key,
--   skipped, tag?, hands = {{hand, chips, mult, score}}, won}}}}, jokers_seen = {{key,
--   ...} at each shop_enter}, origin = {filter_name?}}. Additive fields: jokers_final
--   (the joker keys at run_end), loads (how many times a loaded run continued it).
--   dollars_start is the money when the ante's first blind is chosen (run start for a
--   new run's ante 1); dollars_end is the money after the ante's last round, including
--   its cash-out when there was one (the next shop_enter).
--
-- API
--   recorder.install()          Subscribes to bh-core events. Idempotent.
--   recorder.current()          The live record (nil outside a run). Don't mutate.
--   recorder.list()             Index entries (copies), newest first.
--   recorder.read(run_id)       The record, or nil, err.
--   recorder.save(record)       Writes a record and its index entry (run_id,
--                               seed and started_at required): true | nil, err. The
--                               T-125 UI scenario seeds synthetic records with it.
--   recorder.delete(run_id)     Drops a record and its index entry: true | nil, err.
--   recorder.dir()              '<profile>/runjournal'.
--   recorder.set_origin(o)      The next new run's record gets origin = {filter_name =
--                               o.filter_name} (SeedFinder's Play calls it before it
--                               starts the run). nil clears it.
--
-- Events (bh-core only; nothing hooks vanilla here)
--   run_start       new run: a fresh record (not written until its first round_end or
--                   shop_enter). Loaded run: continue the newest unfinished record with
--                   the same seed, read from disk; a new record when there is none.
--   blind_selected  opens a blind entry in the ante; hand_scored appends to it.
--   blind_skipped   a closed blind entry with skipped = true and the tag.
--   round_end       closes the open blind (won), sets dollars_end, final ante/round.
--                   Written. On a boss win ante_change has already fired (see
--                   bhcore/events.lua): the payload's ante is the round's own.
--   shop_enter      appends the joker keys to jokers_seen, dollars_end of the ante
--                   of the round just cashed out. Written.
--   run_end         ended_at, won, final ante/round, jokers_final. Written. An endless
--                   run that was won and then lost stays won.
-- Writes happen only in those three handlers, never per frame. A write failure is
-- printed and the in-memory record is kept; the next write retries.
local fs = require('bhcore.fs')

local recorder = {}

local INDEX_VERSION = 1
local installed = false
local rec = nil          -- the live record
local open_blind = nil   -- the blind entry hand_scored appends to
local last_round_ante = nil
local pending_origin = nil -- set_origin's table, for the next new run

local function dir() return tostring(G.SETTINGS.profile)..'/runjournal' end
local function index_path() return dir()..'/index.jkr' end
local function file_of(run_id) return (tostring(run_id):gsub('[^%w_%-]', '_')) end
local function record_path(run_id) return dir()..'/'..file_of(run_id)..'.jkr' end

local function copy(t)
  if type(t) ~= 'table' then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

local function joker_keys()
  local out = {}
  local cards = G.jokers and G.jokers.cards
  if type(cards) ~= 'table' then return out end
  for _, c in ipairs(cards) do
    local key = c.config and c.config.center and c.config.center.key
    if key then out[#out + 1] = key end
  end
  return out
end

local function entry_of(r)
  local jokers = r.jokers_final or r.jokers_seen and r.jokers_seen[#r.jokers_seen] or {}
  return {
    run_id = r.run_id, file = file_of(r.run_id), seed = r.seed, deck = r.deck,
    stake = r.stake, started_at = r.started_at, ended_at = r.ended_at, won = r.won,
    final_ante = r.final_ante, final_round = r.final_round, jokers = copy(jokers),
  }
end

-- Every readable record file, as index entries, oldest first.
local function rebuild_index()
  local runs = {}
  local ok, items = pcall(love.filesystem.getDirectoryItems, dir())
  if not ok or type(items) ~= 'table' then items = {} end
  for _, name in ipairs(items) do
    local base = name:match('^(.*)%.jkr$')
    if base and base ~= 'index' then
      local r = fs.read_table(dir()..'/'..name)
      if type(r) == 'table' and r.run_id and file_of(r.run_id) == base then
        runs[#runs + 1] = entry_of(r)
      end
    end
  end
  table.sort(runs, function(a, b)
    if (a.started_at or 0) ~= (b.started_at or 0) then return (a.started_at or 0) < (b.started_at or 0) end
    return tostring(a.run_id) < tostring(b.run_id)
  end)
  return {version = INDEX_VERSION, runs = runs}
end

local function read_index()
  local idx = fs.read_table(index_path())
  if type(idx) == 'table' and type(idx.runs) == 'table' then return idx end
  return rebuild_index()
end

local function find_entry(idx, run_id)
  for i, e in ipairs(idx.runs) do
    if e.run_id == run_id then return i, e end
  end
end

local function write_record(r)
  fs.ensure_dir(dir())
  local ok, err = fs.write_table(record_path(r.run_id), r)
  if not ok then return nil, err end
  local idx = read_index()
  local i = find_entry(idx, r.run_id)
  idx.runs[i or #idx.runs + 1] = entry_of(r)
  return fs.write_table(index_path(), idx)
end

local function persist(why)
  if not rec then return end
  local ok, err = write_record(rec)
  if not ok then print('[RunJournal] '..why..': write failed: '..tostring(err)) end
end

local function ante_entry(a)
  a = a or 1
  local e = rec.antes[a]
  if not e then
    e = {dollars_start = G.GAME and G.GAME.dollars, blinds = {}}
    rec.antes[a] = e
  end
  return e
end

-- The ante's first blind choice fixes dollars_start (after the previous shop).
local function add_blind(a, blind)
  local e = ante_entry(a)
  if #e.blinds == 0 and G.GAME then e.dollars_start = G.GAME.dollars end
  e.blinds[#e.blinds + 1] = blind
  return blind
end

local function new_record(p)
  local now = os.time()
  local origin = {}
  if pending_origin then origin.filter_name = pending_origin.filter_name end
  pending_origin = nil
  -- Two runs of one seed started within a second would share an id: take the next one.
  local t = now
  while fs.exists(record_path(tostring(p.seed)..':'..tostring(t))) do t = t + 1 end
  return {
    run_id = tostring(p.seed)..':'..tostring(t), seed = p.seed, deck = p.deck,
    stake = p.stake, started_at = now, final_ante = p.ante or 1, final_round = 0,
    antes = {[p.ante or 1] = {dollars_start = G.GAME and G.GAME.dollars, blinds = {}}},
    jokers_seen = {}, origin = origin,
  }
end

-- The newest unfinished record with this seed, from disk.
local function unfinished(seed)
  local idx = read_index()
  for i = #idx.runs, 1, -1 do
    local e = idx.runs[i]
    if e.seed == seed and not e.ended_at then
      local r = fs.read_table(record_path(e.run_id))
      if type(r) == 'table' and r.run_id == e.run_id then return r end
    end
  end
end

-- A loaded run in the middle of a round: hands go to its open blind entry.
local function reopen_blind()
  local e = rec.antes[G.GAME.round_resets.ante]
  local last = e and e.blinds[#e.blinds]
  if last and not last.skipped and last.won == nil then return last end
  if G.STATE == G.STATES.SELECTING_HAND or G.STATE == G.STATES.HAND_PLAYED
    or G.STATE == G.STATES.DRAW_TO_HAND then
    local b = G.GAME.blind
    local key = b and b.config and b.config.blind and b.config.blind.key
    return add_blind(G.GAME.round_resets.ante,
      {kind = G.GAME.blind_on_deck, key = key, skipped = false, hands = {}})
  end
end

local function on_run_start(p)
  open_blind, last_round_ante = nil, nil
  rec = p.loaded and unfinished(p.seed) or nil
  if rec then
    rec.loads = (rec.loads or 0) + 1
    rec.antes = rec.antes or {}
    rec.jokers_seen = rec.jokers_seen or {}
    ante_entry(p.ante)
    open_blind = reopen_blind()
  else
    rec = new_record(p)
  end
end

local function on_blind_selected(p)
  if not rec then return end
  open_blind = add_blind(p.ante, {kind = p.kind, key = p.blind, skipped = false, hands = {}})
end

local function on_blind_skipped(p)
  if not rec then return end
  local choices = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices
  add_blind(p.ante, {kind = p.kind, key = choices and choices[p.kind], skipped = true, tag = p.tag,
    hands = {}})
  open_blind = nil
end

local function on_hand_scored(p)
  if not rec then return end
  if not open_blind then
    open_blind = add_blind(p.ante, {kind = G.GAME.blind_on_deck, skipped = false, hands = {}})
  end
  local hands = open_blind.hands
  hands[#hands + 1] = {hand = p.hand, chips = p.chips, mult = p.mult, score = p.score}
end

local function on_round_end(p)
  if not rec then return end
  if open_blind then open_blind.won = p.won end
  open_blind = nil
  ante_entry(p.ante).dollars_end = p.dollars
  last_round_ante = p.ante
  rec.final_ante, rec.final_round = p.ante, p.round
  persist('round_end')
end

local function on_shop_enter(p)
  if not rec then return end
  rec.jokers_seen[#rec.jokers_seen + 1] = joker_keys()
  ante_entry(last_round_ante or p.ante).dollars_end = p.dollars
  persist('shop_enter')
end

local function on_ante_change(p)
  if rec then ante_entry(p.to) end
end

local function on_run_end(p)
  if not rec then return end
  rec.ended_at = os.time()
  rec.won = rec.won == true or p.won == true
  rec.final_ante, rec.final_round = p.ante, p.round
  rec.jokers_final = joker_keys()
  persist('run_end')
end

function recorder.install()
  if installed then return end
  installed = true
  local events = require('bhcore.events')
  events.on('run_start', on_run_start)
  events.on('blind_selected', on_blind_selected)
  events.on('blind_skipped', on_blind_skipped)
  events.on('hand_scored', on_hand_scored)
  events.on('round_end', on_round_end)
  events.on('shop_enter', on_shop_enter)
  events.on('ante_change', on_ante_change)
  events.on('run_end', on_run_end)
  -- runjournal.export(fmt) per the contract; stats itself is callable.
  if type(RunJournal) == 'table' and RunJournal.export == nil then
    RunJournal.export = function(fmt) return require('runjournal.stats').export(fmt) end
  end
end

function recorder.current() return rec end

function recorder.set_origin(o)
  pending_origin = type(o) == 'table' and {filter_name = o.filter_name} or nil
end
function recorder.dir() return dir() end

function recorder.list()
  local runs = read_index().runs
  local out = {}
  for i = #runs, 1, -1 do out[#out + 1] = copy(runs[i]) end
  return out
end

function recorder.read(run_id)
  if type(run_id) ~= 'string' then return nil, 'bad run id' end
  local r, err = fs.read_table(record_path(run_id))
  if not r then return nil, err end
  if r.run_id ~= run_id then return nil, 'record holds another run' end
  return r
end

function recorder.save(r)
  if type(r) ~= 'table' or type(r.run_id) ~= 'string' or r.seed == nil
    or type(r.started_at) ~= 'number' then
    return nil, 'bad record'
  end
  r.antes = r.antes or {}
  r.jokers_seen = r.jokers_seen or {}
  r.origin = r.origin or {}
  return write_record(r)
end

function recorder.delete(run_id)
  if type(run_id) ~= 'string' then return nil, 'bad run id' end
  if not fs.drop(record_path(run_id)) then return nil, 'could not remove the record' end
  local idx = read_index()
  local i = find_entry(idx, run_id)
  if i then
    table.remove(idx.runs, i)
    return fs.write_table(index_path(), idx)
  end
  return true
end

return recorder
