-- Worker spike (T-104): can a love.thread worker run vanilla's RNG and pool/tag
-- primitives on a data projection shipped over a Channel? Answers
-- sim-feasibility constraint 7 with running code. Findings: docs/research/worker-spike.md.
--
-- What it does
--   1. Builds a trimmed projection of G.P_CENTERS / G.P_TAGS / G.P_CENTER_POOLS /
--      G.P_JOKER_RARITY_POOLS on the main thread (after boot, so profile
--      unlocked/discovered flags are applied) and STR_PACKs it into one string.
--   2. Starts a worker whose code is the WORKER string below. The worker loads
--      engine/string_packer.lua, functions/misc_functions.lua and
--      functions/common_events.lua unmodified via love.filesystem.load, with a
--      stub G, and rebuilds P_* from the projection.
--   3. Ante-1 Small/Big tags for 50 seeds: worker vs a main-thread replica (a
--      pcall-guarded G.GAME swap calling the live vanilla get_next_tag_key), and
--      vs real seeded start_run for 3 of them.
--   4. Throughput of a tag-only filter over 20,000 generated seeds: one worker,
--      then the same range split across 4 and 8 workers (hit counts must agree),
--      plus a small main-thread baseline.
--   5. math.random state isolation between the main thread and a worker.
-- Nothing here touches bh-core; the engine proper is T-11x.

-- Seed generator shared by both threads (loaded on the main thread with
-- loadstring and pasted in front of the worker code). Seed i is a pure function
-- of i, so any split of an index range gives the same seeds.
local SHARED = [==[
local SEED_ALPHA = '123456789ABCDEFGHIJKLMNPQRSTUVWXYZ'
local function seed_at(i)
  local st = (i * 48271 + 11) % 2147483647
  local out = {}
  for c = 1, 8 do
    st = (st * 16807) % 2147483647
    local k = st % 34 + 1
    out[c] = SEED_ALPHA:sub(k, k)
  end
  return table.concat(out)
end

-- The G.GAME fields the tag path reads (get_current_pool 'Tag' branch,
-- pseudoseed), as vanilla start_run leaves them before the first tag draw.
local function fresh_game(seed)
  return {
    pseudorandom = {seed = seed, hashed_seed = pseudohash(seed)},
    round_resets = {ante = 1},
    pool_flags = {}, banned_keys = {}, used_jokers = {}, used_vouchers = {},
  }
end

local function ante1_tags(seed)
  G.GAME = fresh_game(seed)
  local small = get_next_tag_key()
  local big = get_next_tag_key()
  return small, big
end

local function run_filter(from, to, want)
  local hits = 0
  for i = from, to do
    local s, b = ante1_tags(seed_at(i))
    if s == want or b == want then hits = hits + 1 end
  end
  return hits
end
return seed_at, fresh_game, ante1_tags, run_filter
]==]

local WORKER = [==[
local in_name, out_name = ...
require 'love.filesystem'
require 'love.timer'
local inbox = love.thread.getChannel(in_name)
local outbox = love.thread.getChannel(out_name)

-- Stub G: the only globals the loaded primitives touch on the tag path.
G = {ARGS = {}, P_CENTERS = {}, P_TAGS = {}, P_CENTER_POOLS = {}, P_JOKER_RARITY_POOLS = {}}

local t0 = love.timer.getTime()
for _, path in ipairs{'engine/string_packer.lua', 'functions/misc_functions.lua', 'functions/common_events.lua'} do
  local chunk, err = love.filesystem.load(path)
  if not chunk then outbox:push{kind = 'error', msg = 'load '..path..': '..tostring(err)}; return end
  chunk()
end
local load_ms = (love.timer.getTime() - t0) * 1000

local seed_at, fresh_game, ante1_tags, run_filter = assert(loadstring(SHARED_SRC))()

local function install(blob)
  local d = STR_UNPACK(blob)
  G.P_CENTERS, G.P_TAGS = d.centers, d.tags
  local function resolve(list)
    local out = {}
    for i, key in ipairs(list) do out[i] = d.centers[key] or d.tags[key] end
    return out
  end
  G.P_CENTER_POOLS = {}
  for name, list in pairs(d.pools) do G.P_CENTER_POOLS[name] = resolve(list) end
  G.P_JOKER_RARITY_POOLS = {}
  for r, list in pairs(d.rarity) do G.P_JOKER_RARITY_POOLS[r] = resolve(list) end
end

outbox:push{kind = 'ready', load_ms = load_ms, jit = jit and jit.version or 'none',
  has_pseudohash = type(pseudohash) == 'function', has_tag = type(get_next_tag_key) == 'function'}

while true do
  local job = inbox:demand()
  if job.cmd == 'quit' then return end
  local ok, err = pcall(function()
    if job.cmd == 'data' then
      local t = love.timer.getTime()
      install(job.blob)
      outbox:push{kind = 'data', ms = (love.timer.getTime() - t) * 1000, tags = #G.P_CENTER_POOLS.Tag}
    elseif job.cmd == 'tags' then
      local out = {}
      for seed in job.seeds:gmatch('[^,]+') do
        local s, b = ante1_tags(seed)
        out[#out + 1] = seed..'='..s..'/'..b
      end
      outbox:push{kind = 'tags', result = table.concat(out, ',')}
    elseif job.cmd == 'bench' then
      local t = love.timer.getTime()
      local hits = run_filter(job.from, job.to, job.want)
      outbox:push{kind = 'bench', hits = hits, n = job.to - job.from + 1, secs = love.timer.getTime() - t}
    elseif job.cmd == 'rng_a' then
      math.randomseed(555)
      A1 = math.random()
      outbox:push{kind = 'rng_a'}
    elseif job.cmd == 'rng_b' then
      local a2 = math.random()
      math.randomseed(555)
      local e1, e2 = math.random(), math.random()
      outbox:push{kind = 'rng_b', ok = (A1 == e1 and a2 == e2)}
    end
  end)
  if not ok then outbox:push{kind = 'error', msg = tostring(err)} end
end
]==]

local seed_at, fresh_game, ante1_tags, run_filter = assert(loadstring(SHARED))()

local N_TAG_SEEDS, N_REAL = 50, 3
local BENCH_N, BENCH_WANT = 20000, 'tag_charm'
local MAIN_BENCH_N = 2000

local S = {workers = {}}   -- scenario state

-- Trimmed copy of one center: the fields pool, tag, voucher, pack and edition
-- selection read (sim-feasibility §2.1 / §3). Objects and sprites never go in.
local CENTER_FIELDS = {'key', 'set', 'name', 'order', 'rarity', 'unlocked', 'discovered',
  'weight', 'kind', 'requires', 'min_ante', 'enhancement_gate', 'yes_pool_flag',
  'no_pool_flag', 'consumeable', 'skip_pool', 'omit', 'wip', 'demo', 'eternal_compat',
  'perishable_compat', 'cost'}
local function trim(v)
  local t = {}
  for _, f in ipairs(CENTER_FIELDS) do
    local x = v[f]
    if type(x) == 'table' then
      local c = {}
      for kk, vv in pairs(x) do if type(vv) ~= 'table' then c[kk] = vv end end
      x = c
    end
    t[f] = x
  end
  if v.config then
    t.config = {hand_type = v.config.hand_type, softlock = v.config.softlock, type = v.config.type}
  end
  return t
end

local function build_projection()
  local d = {centers = {}, tags = {}, pools = {}, rarity = {}, skipped = {}}
  for k, v in pairs(G.P_CENTERS) do d.centers[k] = trim(v) end
  for k, v in pairs(G.P_TAGS) do d.tags[k] = trim(v) end
  local function keys(list)
    local out = {}
    for i, v in ipairs(list) do
      if not (v.key and (d.centers[v.key] or d.tags[v.key])) then return nil end
      out[i] = v.key
    end
    return out
  end
  for name, list in pairs(G.P_CENTER_POOLS) do
    local ks = keys(list)
    if ks then d.pools[name] = ks else d.skipped[#d.skipped + 1] = name end
  end
  for r, list in pairs(G.P_JOKER_RARITY_POOLS) do d.rarity[r] = keys(list) end
  table.sort(d.skipped)
  return d
end

local function start_worker(i)
  local w = {id = i, inn = 'ws_in_'..i, out = 'ws_out_'..i}
  love.thread.getChannel(w.inn):clear()
  love.thread.getChannel(w.out):clear()
  w.inbox, w.outbox = love.thread.getChannel(w.inn), love.thread.getChannel(w.out)
  -- A code string (not a file name) because it contains newlines.
  w.thread = love.thread.newThread('local SHARED_SRC = '..string.format('%q', SHARED)..'\n'..WORKER)
  w.thread:start(w.inn, w.out)
  S.workers[i] = w
  return w
end

-- Next reply from worker w, or nil; a thread error or an 'error' reply fails the step.
local function poll(ctx, w)
  local err = w.thread:getError()
  ctx.assert(not err, 'worker '..w.id..' died: '..tostring(err))
  local msg = w.outbox:pop()
  if msg and msg.kind == 'error' then ctx.assert(false, 'worker '..w.id..': '..tostring(msg.msg)) end
  return msg
end

-- Main-thread replica: the live vanilla functions on a swapped-in fresh G.GAME,
-- restored whatever happens. No bhcore.sim sandbox (T-102 lands separately).
local function replica(fn)
  local game, pool, force = G.GAME, G.ARGS.TEMP_POOL, G.FORCE_TAG
  G.FORCE_TAG = nil
  local ok, a, b = pcall(fn)
  G.GAME, G.ARGS.TEMP_POOL, G.FORCE_TAG = game, pool, force
  if not ok then error(a, 0) end
  return a, b
end

local function stop_workers()
  for _, w in pairs(S.workers) do
    w.inbox:push{cmd = 'quit'}
    w.thread:wait()
  end
  S.workers = {}
end

local steps = {
  {name = 'projection', run = function(ctx)
    local t = love.timer.getTime()
    local d = build_projection()
    S.blob = STR_PACK(d)
    local pack_ms = (love.timer.getTime() - t) * 1000
    t = love.timer.getTime()
    STR_UNPACK(S.blob)
    local unpack_ms = (love.timer.getTime() - t) * 1000
    local n = 0
    for _ in pairs(d.pools) do n = n + 1 end
    ctx.assert(d.pools.Tag and #d.pools.Tag == 24, 'Tag pool missing from projection')
    ctx.log(('projection: %d bytes, %d pools (skipped: %s), pack %.1f ms, unpack %.1f ms'):format(
      #S.blob, n, table.concat(d.skipped, ' '), pack_ms, unpack_ms))
    -- Can a Channel carry a nested table? (sim-feasibility §3 left it UNVERIFIED)
    local ch = love.thread.getChannel('ws_probe')
    ch:clear()
    local ok, err = pcall(function() ch:push({a = {b = 1}}) end)
    local got = ok and ch:pop()
    ctx.log('channel nested table: '..(ok and (type(got) == 'table' and type(got.a) == 'table' and got.a.b == 1
      and 'carried' or 'push ok, arrived as '..tostring(got and got.a)) or ('refused: '..tostring(err))))
    return true
  end},

  {name = 'worker up', timeout = 10, run = function(ctx)
    local w = S.workers[1] or start_worker(1)
    local msg = poll(ctx, w)
    if not msg then return false end
    ctx.assert(msg.kind == 'ready' and msg.has_pseudohash and msg.has_tag, 'worker not ready: '..tostring(msg.kind))
    ctx.log(('worker loaded vanilla files in %.1f ms (%s)'):format(msg.load_ms, msg.jit))
    w.inbox:push{cmd = 'data', blob = S.blob}
    return true
  end},

  {name = 'worker data', timeout = 10, run = function(ctx)
    local msg = poll(ctx, S.workers[1])
    if not msg then return false end
    ctx.assert(msg.kind == 'data' and msg.tags == 24, 'worker data install: '..tostring(msg.kind))
    ctx.log(('worker installed projection in %.1f ms'):format(msg.ms))
    local seeds = {}
    for i = 1, N_TAG_SEEDS do seeds[i] = seed_at(i) end
    S.seeds = seeds
    S.workers[1].inbox:push{cmd = 'tags', seeds = table.concat(seeds, ',')}
    return true
  end},

  {name = 'worker tags', timeout = 10, run = function(ctx)
    local msg = poll(ctx, S.workers[1])
    if not msg then return false end
    ctx.assert(msg.kind == 'tags', 'unexpected reply '..tostring(msg.kind))
    S.worker_tags = {}
    for seed, s, b in msg.result:gmatch('([^,=]+)=([^/]+)/([^,]+)') do S.worker_tags[seed] = {s, b} end
    local game_before = G.GAME
    local mism, distinct = {}, {}
    S.main_tags = {}
    for _, seed in ipairs(S.seeds) do
      local s, b = replica(function() return ante1_tags(seed) end)
      S.main_tags[seed] = {s, b}
      distinct[s], distinct[b] = true, true
      local w = S.worker_tags[seed]
      if not w or w[1] ~= s or w[2] ~= b then
        mism[#mism + 1] = seed..' main '..s..'/'..b..' worker '..tostring(w and w[1])..'/'..tostring(w and w[2])
      end
    end
    ctx.assert(G.GAME == game_before, 'replica did not restore G.GAME')
    local nd = 0
    for _ in pairs(distinct) do nd = nd + 1 end
    ctx.assert(#mism == 0, #mism..' seeds differ: '..table.concat(mism, '; '))
    ctx.assert(nd >= 5, 'only '..nd..' distinct tags over 50 seeds; the check would be vacuous')
    ctx.log(('replica: %d/%d seeds match worker (%d distinct tags); e.g. %s = %s/%s'):format(
      N_TAG_SEEDS, N_TAG_SEEDS, nd, S.seeds[1], S.main_tags[S.seeds[1]][1], S.main_tags[S.seeds[1]][2]))
    return true
  end},
}

-- Real seeded runs for the first N_REAL seeds: blind-select tags must equal the worker's.
S.real_ok = 0
for i = 1, N_REAL do
  steps[#steps + 1] = {name = 'real run '..i, run = function(ctx)
    ctx.start_run{seed = S.seeds[i]}
    return true
  end}
  steps[#steps + 1] = {name = 'real tags '..i, timeout = 20, run = function(ctx)
    local seed = S.seeds[i]
    if not (G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.GAME.pseudorandom.seed == seed
      and G.GAME.round_resets.blind_tags and G.GAME.round_resets.blind_tags.Big) then return false end
    local bt, w = G.GAME.round_resets.blind_tags, S.worker_tags[seed]
    ctx.assert(bt.Small == w[1] and bt.Big == w[2],
      ('seed %s: real run %s/%s, worker %s/%s'):format(seed, bt.Small, bt.Big, w[1], w[2]))
    ctx.log(('real run %s: %s/%s = worker'):format(seed, bt.Small, bt.Big))
    S.real_ok = S.real_ok + 1
    return true
  end}
  -- Let start_run's screen wipe finish first: go_to_menu mid-wipe indexes a nil G.screenwipe.
  steps[#steps + 1] = {name = 'leave run '..i, run = function(ctx)
    -- 3 s also lets the blind-select panel (with the tags) slide in for the shot.
    if ctx.step_time() < 3 then return false end
    if i == 1 then ctx.shot('real_run') end
    G.FUNCS.go_to_menu()
    return true
  end}
  steps[#steps + 1] = {name = 'menu '..i, timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.MAIN_MENU and G.MAIN_MENU_UI ~= nil and ctx.step_time() > 1
  end}
end

local more = {
  {name = 'tags verdict', run = function(ctx)
    ctx.assert(S.real_ok == N_REAL, 'real runs checked: '..S.real_ok)
    ctx.log(('check: worker tags match main thread (%d seeds replica, %d real start_run)'):format(N_TAG_SEEDS, N_REAL))
    S.workers[1].inbox:push{cmd = 'bench', from = 1, to = BENCH_N, want = BENCH_WANT}
    return true
  end},

  {name = 'bench 1 worker', timeout = 60, run = function(ctx)
    local msg = poll(ctx, S.workers[1])
    if not msg then return false end
    ctx.assert(msg.kind == 'bench' and msg.n == BENCH_N and msg.secs > 0, 'bad bench reply')
    S.bench_hits = msg.hits
    ctx.log(('worker throughput: %d seeds/s (1 worker, filter "ante-1 Small or Big = %s", %d seeds, %d hits, %.3f s)'):format(
      math.floor(msg.n / msg.secs), BENCH_WANT, msg.n, msg.hits, msg.secs))
    ctx.assert(msg.hits > 0 and msg.hits < BENCH_N, 'filter hit count '..msg.hits..' is degenerate')
    return true
  end},

  {name = 'main-thread baseline', run = function(ctx)
    local t = love.timer.getTime()
    local hits = replica(function() return run_filter(1, MAIN_BENCH_N, BENCH_WANT) end)
    local secs = love.timer.getTime() - t
    ctx.log(('main-thread baseline: %d seeds/s (%d seeds, %d hits, %.3f s, blocks the frame)'):format(
      math.floor(MAIN_BENCH_N / secs), MAIN_BENCH_N, hits, secs))
    return true
  end},
}
for _, s in ipairs(more) do steps[#steps + 1] = s end

-- Scaling: the same BENCH_N range split across k workers; hit totals must match.
for _, k in ipairs{4, 8} do
  steps[#steps + 1] = {name = 'spawn '..k, timeout = 15, run = function(ctx)
    if not S.scale then
      stop_workers()
      S.scale = {k = k, ready = 0, done = 0, hits = 0}
      for i = 1, k do start_worker(i) end
    end
    local sc = S.scale
    for _, w in pairs(S.workers) do
      local msg = poll(ctx, w)
      if msg and msg.kind == 'ready' then
        sc.ready = sc.ready + 1
        w.inbox:push{cmd = 'data', blob = S.blob}
      elseif msg and msg.kind == 'data' then
        sc.done = sc.done + 1
      end
    end
    if sc.done < k then return false end
    local per = math.ceil(BENCH_N / k)
    sc.done, sc.t0 = 0, love.timer.getTime()
    for i, w in pairs(S.workers) do
      w.inbox:push{cmd = 'bench', from = (i - 1) * per + 1, to = math.min(i * per, BENCH_N), want = BENCH_WANT}
    end
    return true
  end}
  steps[#steps + 1] = {name = 'bench '..k, timeout = 60, run = function(ctx)
    local sc = S.scale
    for _, w in pairs(S.workers) do
      local msg = poll(ctx, w)
      if msg and msg.kind == 'bench' then
        sc.done, sc.hits = sc.done + 1, sc.hits + msg.hits
        sc.max_secs = math.max(sc.max_secs or 0, msg.secs)
      end
    end
    if sc.done < k then return false end
    local wall = love.timer.getTime() - sc.t0
    ctx.assert(sc.hits == S.bench_hits, ('%d workers found %d hits, 1 worker %d'):format(k, sc.hits, S.bench_hits))
    ctx.log(('scaling: %d workers, %d seeds/s aggregate (wall %.3f s incl. frame polling; slowest worker %.3f s = %d seeds/s), hits agree'):format(
      k, math.floor(BENCH_N / wall), wall, sc.max_secs, math.floor(BENCH_N / sc.max_secs)))
    S.scale = nil
    return true
  end}
end

local tail = {
  {name = 'math.random per thread', timeout = 10, run = function(ctx)
    stop_workers()
    local w = start_worker(1)
    local msg = w.outbox:demand(5)
    ctx.assert(msg and msg.kind == 'ready', 'worker not ready for rng check')
    -- main seeds, draws; worker reseeds its own; main draws again (must be unaffected);
    -- main reseeds; worker draws again (must be unaffected).
    math.randomseed(777)
    local m1 = math.random()
    w.inbox:push{cmd = 'rng_a'}
    ctx.assert(w.outbox:demand(5), 'rng_a timed out')
    local m2 = math.random()
    math.randomseed(999)
    for _ = 1, 10 do math.random() end
    w.inbox:push{cmd = 'rng_b'}
    local r = w.outbox:demand(5)
    ctx.assert(r and r.kind == 'rng_b', 'rng_b timed out')
    math.randomseed(777)
    local f1, f2 = math.random(), math.random()
    local main_ok = (m1 == f1 and m2 == f2)
    ctx.assert(main_ok and r.ok, 'math.random state is shared between threads')
    ctx.log(('check: math.random state is per thread: %s (main unaffected by worker reseed: %s, worker unaffected by main reseed: %s)'):format(
      tostring(main_ok and r.ok), tostring(main_ok), tostring(r.ok)))
    stop_workers()
    return true
  end},
}
for _, s in ipairs(tail) do steps[#steps + 1] = s end

return steps
