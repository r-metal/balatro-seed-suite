-- Native diff (T-341): native/build/libbhsim.so, the C port of the stable
-- streams, against bhcore.sim.predict on 1,000,000 seeds, loaded through
-- LuaJIT FFI inside the real game. Glue: native/lua/bhsim.lua; the port and
-- the vanilla lines it mirrors: native/src/bhsim.c.
--
--   1. Primitives in the game's own LuaJIT (the C side was written against
--      LuaJIT 2.1's lib_math; LÖVE ships its own build): bh_round13 vs
--      tonumber(string.format('%.13f')) incl. every half-way j/16384,
--      bh_pseudohash vs vanilla pseudohash, bh_randomseed/bh_random vs
--      math.randomseed/math.random.
--   2. Main thread, live G (the real prototypes, not the workers'
--      projection): MAIN_SEEDS seeds per config, Red Deck stake 1 and
--      all_unlocked stake 8, CHUNK_MAIN seeds a frame. STR_PACK(G.GAME) is
--      byte-identical across the step (invariant 6).
--   3. 1,000,000 seeds, seedfinder.worker.seed_at(0 .. 999,999), Red Deck
--      stake 1, on love.thread workers (invariant 8: nothing scans on the
--      main thread). Each worker loads vanilla and the sim exactly as the
--      Finder's workers do (seedfinder.worker's file list, engine.projection,
--      the sim modules' own loaders), builds its C context from that G, and
--      per chunk runs the Lua walk and the C walk and compares them field by
--      field.
-- The walk, per seed: state.fresh, then per ante 1..8 in the game's order
-- (ante 1: boss, voucher, tags; later: voucher, tags, boss), then
-- predict.legendaries(S, 1): the Soul used that ante, earlier Souls held
-- (so antes 6-8 reach Joker4's empty-pool fallback), edition from 'edisou'..a.
-- Logs "native_diff: <N> seeds, <D> differences", the Lua and native rates
-- per thread and the speedup; any difference fails with the first few.
local state = require('bhcore.sim.state')
local sandbox = require('bhcore.sim.sandbox')
local engine = require('seedfinder.engine')
local worker = require('seedfinder.worker')

local ANTES = 8
local TOTAL = 1000000
local FIRST = 0          -- seed_at index of the first seed
local JOB = 2000         -- seeds per worker job
local QUEUE = 2          -- jobs in flight per worker
local MAIN_SEEDS = 500
local CHUNK_MAIN = 50
local MODULES = {'bhcore.sim.sandbox', 'bhcore.sim.card', 'bhcore.sim.state', 'bhcore.sim.predict'}

-- The Lua reference walk and the comparison, shared by both threads: loaded
-- here with loadstring and sent to the workers as source.
local SHARED = [==[
local bhsim = ...
local W = {}

-- predict's walk for one seed: a flat list, 6 strings per ante.
function W.lua_walk(state, predict, seed, antes, opts)
  local S = state.fresh(seed, opts)
  local out, n = {}, 0
  for a = 1, antes do
    local boss, v, t
    if a == 1 then
      boss = predict.boss(S, 1); v = predict.voucher(S, 1); t = predict.tags(S, 1)
    else
      v = predict.voucher(S, a); t = predict.tags(S, a); boss = predict.boss(S, a)
    end
    local l = predict.legendaries(S, 1)[1]
    out[n + 1], out[n + 2], out[n + 3] = t.small, t.big, boss
    out[n + 4], out[n + 5], out[n + 6] = v, l.key, l.edition or 'none'
    n = n + 6
  end
  return out
end

W.FIELDS = {'small', 'big', 'boss', 'voucher', 'legendary', 'edition'}

-- Lua walks (a list of flat lists) vs one bh_stable_batch output: the count
-- of differing fields and up to 3 descriptions.
function W.compare(ctx, seeds, lua, out, antes)
  local diffs, first = 0, {}
  for i, seed in ipairs(seeds) do
    local want = lua[i]
    for a = 1, antes do
      local got = {bhsim.record(ctx, out, i, a)}
      for f = 1, 6 do
        local w = want[(a - 1) * 6 + f]
        if got[f] ~= w then
          diffs = diffs + 1
          if #first < 3 then
            first[#first + 1] = ('%s ante %d %s: native %s, lua %s'):format(seed, a, W.FIELDS[f], tostring(got[f]), tostring(w))
          end
        end
      end
    end
  end
  return diffs, first
end

-- The C context for (deck, stake, all_unlocked): built from a fresh run of
-- that config inside the sandbox, so G.GAME is that run and all_unlocked's
-- flip applies to the pools.
function W.context(state, sandbox, lib, antes, opts)
  local S = state.fresh('AAAAAAAA', opts)
  local ok, ctx = sandbox.run(S, bhsim.context, lib, antes)
  if not ok then error(ctx, 0) end
  return ctx
end

return W
]==]

local WORKER = [==[
-- native_diff worker thread (source: rig/scenarios/native_diff.lua)
local in_name, out_name, root, shared_src = ...
require 'love.filesystem'
require 'love.timer'
local inbox = love.thread.getChannel(in_name)
local outbox = love.thread.getChannel(out_name)
local now = love.timer.getTime

local function deep_copy(t)
  if type(t) ~= 'table' then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = deep_copy(v) end
  return out
end

-- Stub G and projection install: seedfinder.worker's recipe (its SOURCE).
G = {ARGS = {}, SETTINGS = {}, TIMERS = {}, P_CENTERS = {}, P_TAGS = {}, P_BLINDS = {},
  P_CARDS = {}, P_CENTER_POOLS = {}, P_JOKER_RARITY_POOLS = {}, handlist = {}}

local function install(blob)
  local d = STR_UNPACK(blob)
  G.P_CENTERS, G.P_TAGS, G.P_BLINDS, G.P_CARDS = d.centers, d.tags, d.blinds, d.cards
  G.handlist = d.handlist
  local function resolve(list)
    local out = {}
    for i, key in ipairs(list) do out[i] = d.centers[key] or d.tags[key] end
    return out
  end
  G.P_CENTER_POOLS = {}
  for name, list in pairs(d.pools) do G.P_CENTER_POOLS[name] = resolve(list) end
  G.P_JOKER_RARITY_POOLS = {}
  for r, list in pairs(d.rarity) do G.P_JOKER_RARITY_POOLS[r] = resolve(list) end
  local template = d.template
  Game = {init_game_object = function() return deep_copy(template) end}
end

local state, predict, sandbox, bhsim, lib, W, seed_at, ctx, antes, opts

local function init(msg)
  for _, path in ipairs(msg.vanilla) do
    local chunk, err = love.filesystem.load(path)
    if not chunk then error('load '..path..': '..tostring(err), 0) end
    chunk()
  end
  install(msg.data)
  for name, code in pairs(msg.modules) do
    package.preload[name] = assert(loadstring(code, '='..name))
  end
  BHCore = {sim_depth = 0, worker = true}
  state, predict, sandbox = require('bhcore.sim.state'), require('bhcore.sim.predict'), require('bhcore.sim.sandbox')
  bhsim = dofile(root..'/native/lua/bhsim.lua')
  lib = bhsim.load(root)
  W = assert(loadstring(shared_src, '=native_diff.shared'))(bhsim)
  seed_at = assert(loadstring(msg.seeds, '=seedfinder.seeds'))()
  antes, opts = msg.antes, msg.opts
  ctx = W.context(state, sandbox, lib, antes, opts)
  outbox:push{kind = 'ready'}
end

local function job(msg)
  local seeds = {}
  for i = msg.from, msg.to do seeds[#seeds + 1] = seed_at(i) end
  local t0 = now()
  local lua = {}
  for i, seed in ipairs(seeds) do lua[i] = W.lua_walk(state, predict, seed, antes, opts) end
  local t1 = now()
  local out = bhsim.walk(ctx, seeds, antes)
  local t2 = now()
  local diffs, first = W.compare(ctx, seeds, lua, out, antes)
  outbox:push{kind = 'done', n = #seeds, diffs = diffs, first = first, lua = t1 - t0, native = t2 - t1}
end

while true do
  local msg = inbox:demand()
  if msg.cmd == 'quit' then return end
  local ok, err = pcall(function()
    if msg.cmd == 'init' then init(msg) else job(msg) end
  end)
  if not ok then outbox:push{kind = 'error', msg = tostring(err)}; return end
end
]==]

local R = {} -- scenario state

local function root_of(out)
  return (out:gsub('/build/smoke/[^/]+/?$', ''))
end

local function module_code()
  local out = {}
  for _, name in ipairs(MODULES) do
    local loader = package.preload[name]
    assert(type(loader) == 'function', 'native_diff: no loader for '..name)
    out[name] = string.dump(loader)
  end
  return out
end

local function workers_wanted()
  local cores = love.system.getProcessorCount()
  return math.max(1, math.min(8, cores - 2)) -- 8: leave CPU for a game being played
end

local function stop_workers()
  for _, w in ipairs(R.workers or {}) do
    w.inbox:clear()
    w.inbox:push{cmd = 'quit'}
  end
end

local function dispatch(w)
  if R.cursor > R.last then return false end
  local from = R.cursor
  local to = math.min(R.last, from + JOB - 1)
  R.cursor = to + 1
  w.inbox:push{cmd = 'job', from = from, to = to}
  w.inflight = w.inflight + 1
  return true
end

return {
  {name = 'load the .so', run = function(ctx)
    R.root = root_of(ctx.out)
    R.bhsim = dofile(R.root..'/native/lua/bhsim.lua')
    R.lib = R.bhsim.load(R.root)
    R.W = assert(loadstring(SHARED, '=native_diff.shared'))(R.bhsim)
    ctx.log('native_diff: loaded '..R.root..'/native/build/libbhsim.so in '..tostring(jit and jit.version)
      ..', %.13f ties '..(R.bhsim.TIES_AWAY and 'away from zero' or 'to even'))
    return true
  end},

  {name = 'primitives in the game LuaJIT', run = function(ctx)
    local ffi = require('ffi')
    local lib = R.lib
    local bad, n = 0, 0
    local function fail(what) bad = bad + 1; if bad <= 3 then ctx.log('native_diff: primitive differs: '..what) end end
    local xs = {}
    math.randomseed(4242)
    for i = 1, 20000 do xs[i] = math.random() end
    for j = 1, 16383, 2 do xs[#xs + 1] = j / 16384 end
    for _, x in ipairs(xs) do
      n = n + 1
      local want = tonumber(string.format('%.13f', x))
      if lib.bh_round13(x) ~= want then fail(('round13 %.17g'):format(x)) end
    end
    for i = 1, 5000 do
      local s = worker.seed_at(i)..'Tag'..(i % 9)
      n = n + 1
      if lib.bh_pseudohash(s, #s) ~= pseudohash(s) then fail('pseudohash '..s) end
    end
    local rs = ffi.new('bh_prng')
    for i = 1, 10000 do
      local seed = xs[i]
      math.randomseed(seed)
      local w1, w2 = math.random(), math.random(29)
      lib.bh_randomseed(rs, seed)
      local g1, g2 = lib.bh_random(rs), math.floor(lib.bh_random(rs) * 29) + 1
      n = n + 1
      if w1 ~= g1 or w2 ~= g2 then fail(('tw223 seed %.17g'):format(seed)) end
    end
    ctx.assert(bad == 0, ('primitives: %d of %d differ'):format(bad, n))
    ctx.log(('native_diff: primitives %d checked, 0 differ'):format(n))
    return true
  end},

  {name = 'main thread, live G', timeout = 60, run = function(ctx)
    if not R.main then
      R.main = {cfg = 1, i = 0, n = 0, diffs = 0, pack = STR_PACK(G.GAME), lua = 0, native = 0,
        cfgs = {{deck = 'b_red', stake = 1}, {deck = 'b_red', stake = 8, all_unlocked = true}}}
    end
    local M = R.main
    local opts = M.cfgs[M.cfg]
    if not M.ctx then M.ctx = R.W.context(state, sandbox, R.lib, ANTES, opts) end
    local seeds, lua = {}, {}
    for i = M.i + 1, math.min(MAIN_SEEDS, M.i + CHUNK_MAIN) do seeds[#seeds + 1] = worker.seed_at(TOTAL + M.cfg * 10000 + i) end
    local predict = require('bhcore.sim.predict')
    local t0 = love.timer.getTime()
    for i, seed in ipairs(seeds) do lua[i] = R.W.lua_walk(state, predict, seed, ANTES, opts) end
    local t1 = love.timer.getTime()
    local out = R.bhsim.walk(M.ctx, seeds, ANTES)
    M.lua, M.native = M.lua + (t1 - t0), M.native + (love.timer.getTime() - t1)
    local diffs, first = R.W.compare(M.ctx, seeds, lua, out, ANTES)
    for _, line in ipairs(first) do ctx.log('native_diff: main: '..line) end
    M.diffs, M.n, M.i = M.diffs + diffs, M.n + #seeds, M.i + #seeds
    if M.i < MAIN_SEEDS then return false end
    ctx.log(('native_diff: main thread %s stake %d%s: %d seeds, %d differences'):format(opts.deck, opts.stake,
      opts.all_unlocked and ' all_unlocked' or '', M.i, M.diffs))
    ctx.assert(M.diffs == 0, 'main thread: '..M.diffs..' differences')
    if M.cfg < #M.cfgs then
      M.cfg, M.i, M.ctx = M.cfg + 1, 0, nil
      return false
    end
    ctx.assert(STR_PACK(G.GAME) == M.pack, 'STR_PACK(G.GAME) changed across the main-thread diff')
    return true
  end},

  {name = 'start workers', timeout = 30, run = function(ctx)
    if not R.workers then
      local n = workers_wanted()
      local init = {cmd = 'init', vanilla = worker.VANILLA, data = engine.projection(), modules = module_code(),
        seeds = worker.SEEDS_SOURCE, antes = ANTES, opts = {deck = 'b_red', stake = 1}}
      R.workers, R.cursor, R.last = {}, FIRST, FIRST + TOTAL - 1
      R.n, R.diffs, R.first, R.lua, R.native = 0, 0, {}, 0, 0
      for i = 1, n do
        local w = {id = i, inflight = 0}
        local inn, outn = 'native_diff_in_'..i, 'native_diff_out_'..i
        w.inbox, w.outbox = love.thread.getChannel(inn), love.thread.getChannel(outn)
        w.inbox:clear(); w.outbox:clear()
        w.thread = love.thread.newThread(WORKER)
        w.thread:start(inn, outn, R.root, SHARED)
        w.inbox:push(init)
        R.workers[i] = w
      end
      ctx.log('native_diff: '..n..' workers')
    end
    local ready = 0
    for _, w in ipairs(R.workers) do
      local terr = w.thread:getError()
      if terr then stop_workers(); error('worker '..w.id..': '..terr, 0) end
      local msg = w.outbox:pop()
      if msg and msg.kind == 'error' then stop_workers(); error('worker '..w.id..': '..msg.msg, 0) end
      if msg and msg.kind == 'ready' then w.ready = true end
      if w.ready then ready = ready + 1 end
    end
    if ready < #R.workers then return false end
    R.t0 = love.timer.getTime()
    return true
  end},

  -- 240 s: the scan takes 86-93 s while another game loads the machine (the rig is
  -- niced below it), and 100 s timed out in a full barrier on 2026-09-28.
  {name = '1M seeds on the workers', timeout = 240, run = function(ctx)
    local busy = false
    for _, w in ipairs(R.workers) do
      local terr = w.thread:getError()
      if terr then stop_workers(); error('worker '..w.id..': '..terr, 0) end
      while true do
        local msg = w.outbox:pop()
        if not msg then break end
        if msg.kind == 'error' then stop_workers(); error('worker '..w.id..': '..msg.msg, 0) end
        w.inflight = w.inflight - 1
        R.n, R.diffs = R.n + msg.n, R.diffs + msg.diffs
        R.lua, R.native = R.lua + msg.lua, R.native + msg.native
        for _, line in ipairs(msg.first) do
          if #R.first < 5 then R.first[#R.first + 1] = line; ctx.log('native_diff: '..line) end
        end
      end
      while w.inflight < QUEUE and dispatch(w) do end
      busy = busy or w.inflight > 0
    end
    if R.n > 0 and math.floor(R.n / 100000) ~= math.floor((R.last_logged or 0) / 100000) then
      R.last_logged = R.n
      ctx.log(('native_diff: %d seeds, %d differences so far'):format(R.n, R.diffs))
    end
    if busy then return false end
    R.wall = love.timer.getTime() - R.t0
    stop_workers()
    return true
  end},

  {name = 'verdict', run = function(ctx)
    local lua_rate, native_rate = R.n / R.lua, R.n / R.native
    ctx.log(('native_diff: %d seeds, %d differences'):format(R.n, R.diffs))
    ctx.log(('native_diff: lua %.0f seeds/s per thread, native %.0f seeds/s per thread, speedup %.1fx'):format(
      lua_rate, native_rate, native_rate / lua_rate))
    ctx.log(('native_diff: %d workers, %.1f s wall, %.0f seeds/s aggregate (both walks + compare)'):format(
      #R.workers, R.wall, R.n / R.wall))
    ctx.assert(R.n == TOTAL, 'scanned '..R.n..' of '..TOTAL)
    ctx.assert(R.diffs == 0, R.diffs..' differences; first: '..table.concat(R.first, '; '))
    return true
  end},
}
