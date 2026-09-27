-- seedfinder.engine: scans seeds against a filter on love.thread workers and
-- reports only hits re-checked on the main thread. Contract:
-- docs/contracts-0.2.md § SeedFinder "Engine"; thread code: seedfinder.worker;
-- design: docs/research/worker-spike.md.
--
-- API
--   engine.start(f, opts) -> handle. Raises on an invalid filter or when
--     threads are unavailable. opts:
--       workers    1..8 (default min(4, cores - 1), at least 1)
--       max_seeds  seeds to scan (default 10,000,000); with `seeds`, #seeds
--       stop_after stop once this many verified hits are found (default none)
--       start      index of the first seed in worker.seed_at's sequence
--                  (default random), so each search covers new seeds
--       seeds      an explicit list of seed strings to scan instead
--       worker_filter  (test hook) the filter the workers run; the main-thread
--                  re-check always uses f. Lets a test prove that candidates
--                  failing f are dropped.
--   engine.poll(h) -> {scanned, rate, found = {seed...}, done, total,
--     candidates, rejected, pending, hits_per_million, workers, error}. Call it every frame: it
--     collects worker replies, keeps their queues full and re-checks
--     candidates (a few ms per call at most). rate is seeds/s since start.
--     found holds only seeds for which filter.eval(state.fresh(seed, ...), f)
--     is true on the main thread, in the order they were verified.
--     hits_per_million = worker hits the re-check has not rejected (verified
--     plus pending) per million seeds scanned; 0 before the first chunk.
--   engine.sample(f, n, opts) -> handle. An odds job (seedfinder.odds): the
--     workers evaluate every clause of f alone and the whole filter on n
--     seeds and send back counts; nothing is re-checked, nothing is found.
--     Raises like start. opts: workers, start (default SAMPLE_BASE), seeds
--     (an explicit list instead; n is then #seeds). poll(h) on it returns the
--     fields above (found empty) plus counts = the tallies so far (odds'
--     counts shape) and, once done with counts.n > 0, estimate =
--     odds.estimate(counts). A cancelled sample is done with partial counts.
--   engine.cancel(h) -> stops the scan: workers stop within a few seeds and
--     exit; unverified candidates are dropped, never reported.
--   engine.alive(h)  -> how many of the handle's threads are still running.
--   engine.seed_at(i) -> seed i of the scan sequence (seedfinder.worker).
--   engine.SAMPLE_BASE -> the first index samples read by default. seed_at is
--     periodic in i with period 2^31 - 1 (and inexact past ~1.8e11), so a
--     base like 2^40 would alias index 512, inside the searches' range.
--     Searches start in [0, 2^30] and scan 10M by default; samples start at
--     1.5 * 2^30, leaving ~537M indices before the sequence wraps to 0.
--   engine.projection() -> the STR_PACK prototype projection sent to workers.
--
-- Soundness: a worker's hit is only a candidate. Nothing reaches `found`
-- until the main thread's own filter.eval_seed agrees (candidates it rejects
-- are counted in `rejected`). h.reported keeps every raw candidate seed, for
-- diagnostics and tests.
--
-- What each worker gets, once, at start (roadmap T3):
--   * a STR_PACK projection of the prototypes after boot (so the live
--     profile's unlocked/discovered flags are in it): P_CENTERS, P_TAGS,
--     P_BLINDS and P_CARDS as plain data (functions, objects and cycles
--     dropped), P_CENTER_POOLS / P_JOKER_RARITY_POOLS as ordered key lists,
--     G.handlist, and the template Game:init_game_object() returns;
--   * the bh-core sim modules, seedfinder.filter and seedfinder.odds as string.dump'ed
--     package.preload loaders (the same module files, never a copy);
--   * the filter, serialized.
-- Seeds are dispatched in chunks of CHUNK indices, QUEUE chunks deep per
-- worker; cancellation stops dispatching and raises a shared stop flag.
local worker = require('seedfinder.worker')
local filter = require('seedfinder.filter')
local odds = require('seedfinder.odds')

local M = {}

M.CHUNK = 500
M.QUEUE = 2
M.DEFAULT_MAX = 10000000
M.RECHECK_BUDGET = 0.004 -- seconds of main-thread re-checking per poll
M.SAMPLE_BASE = 3 * 2 ^ 29 -- 1.5 * 2^30: past every search's default range

M.MODULES = {'bhcore.sim.sandbox', 'bhcore.sim.card', 'bhcore.sim.state', 'bhcore.sim.predict',
  'seedfinder.filter', 'seedfinder.odds'}

local serial = 0

function M.seed_at(i) return worker.seed_at(i) end

------------------------------------------------------------------------------
-- What the workers are sent

-- Plain data only: strings, numbers, booleans and tables without metatables,
-- minus cycles. What STR_PACK can carry and the sim reads.
local function plain(v, onpath)
  local t = type(v)
  if t == 'string' or t == 'number' or t == 'boolean' then return v end
  if t ~= 'table' or getmetatable(v) ~= nil or onpath[v] then return nil end
  onpath[v] = true
  local out = {}
  for k, x in pairs(v) do
    local tk = type(k)
    if tk == 'string' or tk == 'number' then out[k] = plain(x, onpath) end
  end
  onpath[v] = nil
  return out
end

-- A prototype table: its own plain fields. Steamodded turns prototypes into objects of
-- its classes (with metatables), which plain() would drop whole, taking the Booster
-- pool with them; their own fields (key, set, config, kind, weight...) are plain data.
local function protos(map)
  local out = {}
  for k, v in pairs(map or {}) do
    if type(k) == 'string' and type(v) == 'table' then
      local o = {}
      for f, x in pairs(v) do
        if type(f) == 'string' or type(f) == 'number' then o[f] = plain(x, {[v] = true}) end
      end
      out[k] = o
    end
  end
  return out
end

function M.projection()
  local d = {centers = protos(G.P_CENTERS), tags = protos(G.P_TAGS), blinds = protos(G.P_BLINDS),
    cards = plain(G.P_CARDS, {}), handlist = plain(G.handlist or {}, {}),
    template = plain(Game.init_game_object(G), {}), pools = {}, rarity = {}}
  local function keys(list)
    local out = {}
    for i, v in ipairs(list) do
      if type(v) ~= 'table' or not (v.key and (d.centers[v.key] or d.tags[v.key])) then return nil end
      out[i] = v.key
    end
    return out
  end
  -- Pools whose members are not centers or tags (Seal, Stake) are read by no
  -- generation primitive and are left out.
  for name, list in pairs(G.P_CENTER_POOLS) do d.pools[name] = keys(list) end
  for r, list in pairs(G.P_JOKER_RARITY_POOLS) do d.rarity[r] = keys(list) end
  return STR_PACK(d)
end

local function module_code()
  local out = {}
  for _, name in ipairs(M.MODULES) do
    local loader = package.preload[name]
    assert(type(loader) == 'function', 'seedfinder.engine: no loader for '..name)
    local ok, code = pcall(string.dump, loader)
    assert(ok, 'seedfinder.engine: cannot dump '..name..': '..tostring(code))
    out[name] = code
  end
  return out
end

local function default_workers()
  local cores = love.system and love.system.getProcessorCount and love.system.getProcessorCount() or 2
  return math.max(1, math.min(4, cores - 1))
end

------------------------------------------------------------------------------
-- Handle

-- Starts the threads for a search (sample = nil) or an odds job.
local function launch(f, opts, sample)
  local ok, err = filter.validate(f)
  if not ok then error(err, 3) end
  assert(love and love.thread, 'seedfinder.engine: love.thread unavailable')
  local n = opts.workers or default_workers()
  assert(type(n) == 'number' and n >= 1 and n <= 8 and n % 1 == 0, 'seedfinder.engine: workers must be 1..8')
  local wf = opts.worker_filter or f
  local wf_str, werr = filter.serialize(wf)
  if not wf_str then error(werr, 3) end

  serial = serial + 1
  local id = 'seedfinder_'..serial
  local h = {f = f, workers = {}, found = {}, reported = {}, queue = {}, scanned = 0, rejected = 0,
    candidates = 0, next_job = 1, t0 = love.timer.getTime(), stop_after = opts.stop_after,
    stop = love.thread.getChannel(id..'_stop'), sample = sample}
  if sample then
    local _, counts = odds.counter(f)
    h.counts = counts
  end
  h.stop:clear()
  if opts.seeds then
    h.seeds = opts.seeds
    h.total = #opts.seeds
    h.cursor, h.last = 1, #opts.seeds
  else
    h.total = opts.max_seeds or M.DEFAULT_MAX
    h.cursor = opts.start or (sample and M.SAMPLE_BASE) or love.math.random(0, 2 ^ 30)
    h.last = h.cursor + h.total - 1
  end

  local init = {cmd = 'init', vanilla = worker.VANILLA, data = M.projection(), modules = module_code(),
    filter = wf_str, seeds = worker.SEEDS_SOURCE}
  for i = 1, n do
    local w = {id = i, inflight = 0, jobs = {}}
    w.inbox = love.thread.getChannel(id..'_in_'..i)
    w.outbox = love.thread.getChannel(id..'_out_'..i)
    w.inbox:clear(); w.outbox:clear()
    w.thread = love.thread.newThread(worker.SOURCE)
    w.thread:start(id..'_in_'..i, id..'_out_'..i, id..'_stop')
    w.inbox:push(init)
    h.workers[i] = w
  end
  return h
end

function M.start(f, opts)
  return launch(f, opts or {})
end

function M.sample(f, n, opts)
  opts = opts or {}
  if not opts.seeds then
    assert(type(n) == 'number' and n >= 1 and n % 1 == 0, 'seedfinder.engine: sample size must be a positive integer')
    opts = {workers = opts.workers, start = opts.start, max_seeds = n}
  end
  return launch(f, opts, true)
end

-- Queues the next chunk on w, or returns false when every seed is dispatched.
local function dispatch(h, w)
  if h.cursor > h.last then return false end
  local from = h.cursor
  local to = math.min(h.last, from + M.CHUNK - 1)
  h.cursor = to + 1
  local job = {id = h.next_job}
  h.next_job = h.next_job + 1
  if h.seeds then
    local list = {}
    for i = from, to do list[#list + 1] = h.seeds[i] end
    job.cmd, job.seeds = h.sample and 'sample' or 'list', list
  else
    job.cmd, job.from, job.to = h.sample and 'sample' or 'range', from, to
  end
  w.inbox:push(job)
  w.inflight = w.inflight + 1
  return true
end

local function shutdown(h)
  h.stop:push(true)
  for _, w in ipairs(h.workers) do
    w.inbox:clear()
    w.inbox:push{cmd = 'quit'}
  end
end

local function finish(h, err)
  if h.done then return end
  h.done, h.t_end = true, love.timer.getTime()
  h.error = h.error or err
  shutdown(h)
end

local function collect(h, w)
  local terr = w.thread:getError()
  if terr then finish(h, 'worker '..w.id..': '..terr); return end
  while true do
    local msg = w.outbox:pop()
    if not msg then return end
    if msg.kind == 'error' then finish(h, 'worker '..w.id..': '..tostring(msg.msg)); return end
    if msg.kind == 'ready' then
      w.ready, w.ready_ms = true, msg.ms
    elseif msg.kind == 'done' then
      w.inflight = w.inflight - 1
      h.scanned = h.scanned + msg.n
      for _, seed in ipairs(msg.hits or {}) do
        h.candidates = h.candidates + 1
        h.reported[#h.reported + 1] = seed
        h.queue[#h.queue + 1] = seed
      end
    elseif msg.kind == 'counts' then
      w.inflight = w.inflight - 1
      h.scanned = h.scanned + msg.n
      local c = h.counts
      c.n, c.full = c.n + msg.n, c.full + msg.full
      for i, k in ipairs(msg.clauses) do c.clauses[i] = c.clauses[i] + k end
    end
  end
end

local function recheck(h)
  local t0 = love.timer.getTime()
  local i = 1
  while i <= #h.queue do
    local seed = h.queue[i]
    i = i + 1
    if filter.eval_seed(h.f, seed) then
      h.found[#h.found + 1] = seed
      if h.stop_after and #h.found >= h.stop_after then break end
    else
      h.rejected = h.rejected + 1
    end
    if love.timer.getTime() - t0 > M.RECHECK_BUDGET then break end
  end
  local rest = {}
  for j = i, #h.queue do rest[#rest + 1] = h.queue[j] end
  h.queue = rest
end

function M.poll(h)
  if not h.done then
    for _, w in ipairs(h.workers) do
      collect(h, w)
      if h.done then break end
      while w.inflight < M.QUEUE and dispatch(h, w) do end
    end
  end
  if not h.cancelled and not h.error then
    recheck(h)
    if h.stop_after and #h.found >= h.stop_after then
      h.queue = {}
      finish(h)
    elseif not h.done and h.cursor > h.last and #h.queue == 0 then
      local busy = false
      for _, w in ipairs(h.workers) do busy = busy or w.inflight > 0 end
      if not busy then finish(h) end
    end
  end
  local now = h.t_end or love.timer.getTime()
  local secs = now - h.t0
  local p = {scanned = h.scanned, rate = secs > 0 and h.scanned / secs or 0, found = h.found, done = h.done or false,
    total = h.total, candidates = h.candidates, rejected = h.rejected, pending = #h.queue,
    hits_per_million = h.scanned > 0 and (h.candidates - h.rejected) * 1e6 / h.scanned or 0,
    workers = #h.workers, error = h.error}
  if h.sample then
    p.counts = h.counts
    if p.done and not h.error and h.counts.n > 0 then p.estimate = assert(odds.estimate(h.counts)) end
  end
  return p
end

function M.cancel(h)
  if h.done and h.cancelled then return end
  h.cancelled = true
  h.queue = {}
  finish(h)
end

function M.alive(h)
  local n = 0
  for _, w in ipairs(h.workers) do
    if w.thread:isRunning() then n = n + 1 end
  end
  return n
end

return M
