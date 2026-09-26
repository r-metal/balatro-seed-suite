-- Native shop diff (T-342): native/build/libbhsim.so's conditional streams
-- (bh_shop_batch: shops with rerolls, shop packs, pack contents, tag packs)
-- against bhcore.sim.predict, loaded through LuaJIT FFI inside the real game.
-- Glue: native/lua/bhsim.lua (bhsim.shop, shop_walk, shop_record, shop_diff);
-- the port and the vanilla lines it mirrors: native/src/bhsim.c.
--
--   1. Golden seeds, main thread, live G (the real prototypes): the 10
--      golden_shop seeds (stake 1, or 8 for its Gold seeds) and the 4
--      golden_walk seeds (stake 1), Red Deck, antes 1-3, under every skip
--      policy (none, Small, Big, both) x rerolls 0 and 2, the same policy at
--      every ante: predict.ante_walk(S, a, policy) per ante vs the port. With
--      no skips, predict.plan(S, {antes = 3, rerolls = R}) is compared as well
--      (its shops are the walk's, its tags drawn in the stable order). One seed
--      a frame; STR_PACK(G.GAME) is byte-identical across the step
--      (invariant 6).
--   2. 200,000 seeds, seedfinder.worker.seed_at(0 .. 199,999), Red Deck,
--      antes 1-3, each at stake 1 AND stake 8 (eternal, perishable, rental
--      stickers), on love.thread workers (invariant 8: nothing scans on the
--      main thread). Seed i walks under policy i % 8 (skip = i % 4: none,
--      Small, Big, both; rerolls 0 for i % 8 < 4, else 2). Each worker loads
--      vanilla and the sim as the Finder's workers do (seedfinder.worker's
--      file list, engine.projection, the sim modules' own loaders), builds a
--      C context per stake from a fresh run of that config, and per chunk runs
--      the Lua walk and the C walk and compares them field by field.
-- Compared per card: key, edition, front, seal, eternal / perishable /
-- rental; per pack: key, forced (the run's first Buffoon), index; per shop:
-- which blind it follows; per tag pack: blind, tag, pack. A seed counts as
-- one difference per differing field.
-- Logs "native_diff_shop: <N> seeds, <D> differences" for the workers' run,
-- the Lua and native rates per thread and the speedup; any difference fails
-- with the first few.
local state = require('bhcore.sim.state')
local sandbox = require('bhcore.sim.sandbox')
local predict = require('bhcore.sim.predict')
local engine = require('seedfinder.engine')
local worker = require('seedfinder.worker')

local ANTES = 3
local TOTAL = 200000
local FIRST = 0          -- seed_at index of the first seed
local JOB = 500          -- seeds per worker job
local QUEUE = 2          -- jobs in flight per worker
local STAKES = {1, 8}
local MODULES = {'bhcore.sim.sandbox', 'bhcore.sim.card', 'bhcore.sim.state', 'bhcore.sim.predict'}
-- golden_shop.lua's and golden_walk.lua's seeds (their scenarios play them).
local GOLDEN = {
  {'E67DHZM3', 1}, {'7LB2WVPK', 1}, {'SHOPGLD1', 1}, {'ZQ9Y8XW6', 1}, {'HNM4KD2P', 1},
  {'R2D2C3P9', 1}, {'PACKS4ME', 1}, {'GOLDST8K', 8}, {'QWERTY12', 8}, {'MNB5VCX4', 8},
  {'GWALK1', 1}, {'GWALK6425', 1}, {'GWALK5852', 1}, {'GWALK3616', 1},
}

-- The policies, the Lua reference walk and the comparison, shared by both
-- threads: loaded here with loadstring and sent to the workers as source.
local SHARED = [==[
local bhsim = ...
local W = {}

W.SKIPS = {{Small = false, Big = false}, {Small = true, Big = false}, {Small = false, Big = true},
  {Small = true, Big = true}}

-- Policy p (0..7): skip p % 4, rerolls 0 for p < 4, else 2.
function W.policy(p)
  return {skip = W.SKIPS[p % 4 + 1], rerolls = p < 4 and 0 or 2}
end

function W.policy_name(pol)
  return (pol.skip.Small and 'S' or '-')..(pol.skip.Big and 'B' or '-')..' r'..pol.rerolls
end

-- predict.ante_walk for antes 1..antes on a fresh run of seed.
function W.lua_walk(state, predict, seed, antes, opts, pol)
  local S = state.fresh(seed, opts)
  local out = {}
  for a = 1, antes do out[a] = predict.ante_walk(S, a, pol) end
  return out
end

-- Lua walks (a list, one per seed) vs one bh_shop_batch output: the count of
-- differing fields and up to 3 descriptions.
function W.compare(ctx, seeds, lua, out, antes, label)
  local diffs, first = 0, {}
  for i, seed in ipairs(seeds) do
    for a = 1, antes do
      local d = bhsim.shop_diff(lua[i][a], bhsim.shop_record(ctx, out, i, a), ('%s %s ante %d'):format(seed, label, a))
      diffs = diffs + #d
      for _, line in ipairs(d) do
        if #first < 3 then first[#first + 1] = line end
      end
    end
  end
  return diffs, first
end

-- The C context for (deck, stake), stable and shop data, built from a fresh
-- run of that config inside the sandbox.
function W.context(state, sandbox, lib, antes, opts, tag_packs)
  local S = state.fresh('AAAAAAAA', opts)
  local ok, ctx = sandbox.run(S, function()
    return bhsim.shop(bhsim.context(lib, antes), tag_packs)
  end)
  if not ok then error(ctx, 0) end
  return ctx
end

return W
]==]

local WORKER = [==[
-- native_diff_shop worker thread (source: rig/scenarios/native_diff_shop.lua)
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

local state, predict, sandbox, bhsim, lib, W, seed_at, ctxs, antes, stakes

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
  W = assert(loadstring(shared_src, '=native_diff_shop.shared'))(bhsim)
  seed_at = assert(loadstring(msg.seeds, '=seedfinder.seeds'))()
  antes, stakes = msg.antes, msg.stakes
  ctxs = {}
  for _, stake in ipairs(stakes) do
    ctxs[stake] = W.context(state, sandbox, lib, antes, {deck = 'b_red', stake = stake}, predict.TAG_PACKS)
  end
  outbox:push{kind = 'ready'}
end

local function job(msg)
  local by_policy = {}
  for i = msg.from, msg.to do
    local p = i % 8
    by_policy[p] = by_policy[p] or {}
    local list = by_policy[p]
    list[#list + 1] = seed_at(i)
  end
  local lua_t, native_t, diffs, first = 0, 0, 0, {}
  for _, stake in ipairs(stakes) do
    local opts, ctx = {deck = 'b_red', stake = stake}, ctxs[stake]
    for p = 0, 7 do
      local seeds = by_policy[p]
      if seeds then
        local pol = W.policy(p)
        local t0 = now()
        local lua = {}
        for i, seed in ipairs(seeds) do lua[i] = W.lua_walk(state, predict, seed, antes, opts, pol) end
        local t1 = now()
        local out = bhsim.shop_walk(ctx, seeds, antes, pol)
        local t2 = now()
        lua_t, native_t = lua_t + (t1 - t0), native_t + (t2 - t1)
        local d, f = W.compare(ctx, seeds, lua, out, antes, 'stake '..stake..' '..W.policy_name(pol))
        diffs = diffs + d
        for _, line in ipairs(f) do if #first < 3 then first[#first + 1] = line end end
      end
    end
  end
  outbox:push{kind = 'done', n = msg.to - msg.from + 1, walks = (msg.to - msg.from + 1) * #stakes,
    diffs = diffs, first = first, lua = lua_t, native = native_t}
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
    assert(type(loader) == 'function', 'native_diff_shop: no loader for '..name)
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

-- predict.plan's ante record in ante_walk's shape (no skips: the shops follow
-- Small and Big, and from ante 2 the Boss of the ante before first).
local AFTER = {[1] = {'Small', 'Big'}, other = {'Boss', 'Small', 'Big'}}
local function plan_as_walk(rec)
  local after = AFTER[rec.ante] or AFTER.other
  local walk = {tags = {small = rec.tags.small, big = rec.tags.big}, shops = {}, tag_packs = {}}
  for s, shop in ipairs(rec.shops) do
    local contents = {}
    for j, p in ipairs(shop.packs) do contents[j] = rec.pack_contents[p.index] end
    walk.shops[s] = {after = after[s], cards = shop.cards, rerolls = shop.rerolls, packs = shop.packs,
      contents = contents}
  end
  return walk
end

return {
  {name = 'load the .so', run = function(ctx)
    R.root = root_of(ctx.out)
    R.bhsim = dofile(R.root..'/native/lua/bhsim.lua')
    R.lib = R.bhsim.load(R.root)
    R.W = assert(loadstring(SHARED, '=native_diff_shop.shared'))(R.bhsim)
    ctx.log('native_diff_shop: loaded '..R.root..'/native/build/libbhsim.so in '..tostring(jit and jit.version)
      ..', %.13f ties '..(R.bhsim.TIES_AWAY and 'away from zero' or 'to even'))
    return true
  end},

  {name = 'golden seeds, main thread, live G', timeout = 60, run = function(ctx)
    if not R.gold then
      R.gold = {i = 0, walks = 0, plans = 0, diffs = 0, first = {}, ctxs = {}, pack = STR_PACK(G.GAME)}
    end
    local M = R.gold
    M.i = M.i + 1
    local seed, stake = GOLDEN[M.i][1], GOLDEN[M.i][2]
    local opts = {deck = 'b_red', stake = stake}
    M.ctxs[stake] = M.ctxs[stake] or R.W.context(state, sandbox, R.lib, ANTES, opts, predict.TAG_PACKS)
    local cctx = M.ctxs[stake]
    local function add(d)
      M.diffs = M.diffs + #d
      for _, line in ipairs(d) do
        if #M.first < 5 then M.first[#M.first + 1] = line; ctx.log('native_diff_shop: golden: '..line) end
      end
    end
    for p = 0, 7 do
      local pol = R.W.policy(p)
      local label = 'stake '..stake..' '..R.W.policy_name(pol)
      local out = R.bhsim.shop_walk(cctx, {seed}, ANTES, pol)
      local walk = R.W.lua_walk(state, predict, seed, ANTES, opts, pol)
      M.walks = M.walks + 1
      for a = 1, ANTES do
        add(R.bhsim.shop_diff(walk[a], R.bhsim.shop_record(cctx, out, 1, a), ('%s %s ante %d'):format(seed, label, a)))
      end
      if not pol.skip.Small and not pol.skip.Big then
        local plan = predict.plan(state.fresh(seed, opts), {antes = ANTES, rerolls = pol.rerolls, open_packs = true})
        M.plans = M.plans + 1
        for a = 1, ANTES do
          add(R.bhsim.shop_diff(plan_as_walk(plan[a]), R.bhsim.shop_record(cctx, out, 1, a),
            ('%s %s plan ante %d'):format(seed, label, a)))
        end
      end
    end
    if M.i < #GOLDEN then return false end
    ctx.log(('native_diff_shop: golden: %d seeds, %d walks x %d antes, %d plans, %d differences'):format(
      #GOLDEN, M.walks, ANTES, M.plans, M.diffs))
    ctx.assert(M.diffs == 0, 'golden: '..M.diffs..' differences; first: '..table.concat(M.first, '; '))
    ctx.assert(STR_PACK(G.GAME) == M.pack, 'STR_PACK(G.GAME) changed across the golden diff')
    return true
  end},

  {name = 'start workers', timeout = 30, run = function(ctx)
    if not R.workers then
      local n = workers_wanted()
      local init = {cmd = 'init', vanilla = worker.VANILLA, data = engine.projection(), modules = module_code(),
        seeds = worker.SEEDS_SOURCE, antes = ANTES, stakes = STAKES}
      R.workers, R.cursor, R.last = {}, FIRST, FIRST + TOTAL - 1
      R.n, R.walks, R.diffs, R.first, R.lua, R.native = 0, 0, 0, {}, 0, 0
      for i = 1, n do
        local w = {id = i, inflight = 0}
        local inn, outn = 'native_diff_shop_in_'..i, 'native_diff_shop_out_'..i
        w.inbox, w.outbox = love.thread.getChannel(inn), love.thread.getChannel(outn)
        w.inbox:clear(); w.outbox:clear()
        w.thread = love.thread.newThread(WORKER)
        w.thread:start(inn, outn, R.root, SHARED)
        w.inbox:push(init)
        R.workers[i] = w
      end
      ctx.log('native_diff_shop: '..n..' workers')
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

  {name = '200k seeds on the workers', timeout = 100, run = function(ctx)
    local busy = false
    for _, w in ipairs(R.workers) do
      local terr = w.thread:getError()
      if terr then stop_workers(); error('worker '..w.id..': '..terr, 0) end
      while true do
        local msg = w.outbox:pop()
        if not msg then break end
        if msg.kind == 'error' then stop_workers(); error('worker '..w.id..': '..msg.msg, 0) end
        w.inflight = w.inflight - 1
        R.n, R.walks, R.diffs = R.n + msg.n, R.walks + msg.walks, R.diffs + msg.diffs
        R.lua, R.native = R.lua + msg.lua, R.native + msg.native
        for _, line in ipairs(msg.first) do
          if #R.first < 5 then R.first[#R.first + 1] = line; ctx.log('native_diff_shop: '..line) end
        end
      end
      while w.inflight < QUEUE and dispatch(w) do end
      busy = busy or w.inflight > 0
    end
    if R.n > 0 and math.floor(R.n / 50000) ~= math.floor((R.last_logged or 0) / 50000) then
      R.last_logged = R.n
      ctx.log(('native_diff_shop: %d seeds, %d differences so far'):format(R.n, R.diffs))
    end
    if busy then return false end
    R.wall = love.timer.getTime() - R.t0
    stop_workers()
    return true
  end},

  {name = 'verdict', run = function(ctx)
    local lua_rate, native_rate = R.walks / R.lua, R.walks / R.native
    ctx.log(('native_diff_shop: %d seeds, %d differences'):format(R.n, R.diffs))
    ctx.log(('native_diff_shop: %d walks (stakes %s, antes 1-%d), lua %.0f walks/s per thread, native %.0f walks/s per thread, speedup %.1fx'):format(
      R.walks, table.concat(STAKES, ' and '), ANTES, lua_rate, native_rate, native_rate / lua_rate))
    ctx.log(('native_diff_shop: %d workers, %.1f s wall, %.0f walks/s aggregate (both walks + compare)'):format(
      #R.workers, R.wall, R.walks / R.wall))
    ctx.assert(R.n == TOTAL, 'scanned '..R.n..' of '..TOTAL)
    ctx.assert(R.diffs == 0, R.diffs..' differences; first: '..table.concat(R.first, '; '))
    return true
  end},
}
