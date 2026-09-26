-- seedfinder.worker: the code a Seed Finder love.thread runs, as a string, plus
-- the seed sequence both threads share. Contract: docs/contracts-0.2.md
-- § SeedFinder "Engine"; approach: docs/research/worker-spike.md.
--
-- Requiring this module on the main thread only defines strings; nothing runs.
-- seedfinder.engine starts the threads and speaks the protocol below.
--
-- API
--   worker.SOURCE        the thread's Lua code (love.thread.newThread(SOURCE)).
--                        Thread args: inbox, outbox and stop channel names.
--   worker.SEEDS_SOURCE  a chunk returning seed_at(i): seed i (integer >= 0) of
--                        the scan sequence, 8 characters of vanilla's seed
--                        alphabet (random_string: 1-9, A-N, P-Z). A pure
--                        function of i, so index ranges split freely.
--   worker.seed_at(i)    that function, loaded on the calling thread.
--   worker.VANILLA       the vanilla files the thread loads, in order.
--
-- Protocol (Channel messages are tables; LÖVE 11.5 carries nested tables)
--   main -> inbox  {cmd = 'init', vanilla = VANILLA, data = <STR_PACK projection>, modules =
--                   {[name] = <string.dump of package.preload[name]>},
--                   filter = <filter.serialize>, seeds = SEEDS_SOURCE}
--                  {cmd = 'range', id, from, to}   scan seed_at(from..to)
--                  {cmd = 'list', id, seeds = {...}} scan these seeds
--                  {cmd = 'sample', id, from, to} or {cmd = 'sample', id, seeds}
--                                  tally seedfinder.odds counts over them
--                  {cmd = 'quit'}
--   outbox -> main {kind = 'ready', ms}  after init
--                  {kind = 'done', id, n = <seeds evaluated>, hits = {seed...},
--                   stopped = true when the stop channel cut it short}
--                  {kind = 'counts', id, n, mode, clauses = {[i] = passes},
--                   full, stopped}  a 'sample' job's odds.counter tallies
--                   (each clause alone, then the whole filter, per seed)
--                  {kind = 'error', msg}  the thread returns after this
--   stop channel   anything on it (never popped) makes every job stop within
--                  STOP_EVERY seeds; the thread then waits for 'quit'.
--
-- What the thread runs (T-104's design, now with the real sim):
--   * vanilla's own files, unmodified, through love.filesystem.load (PhysFS is
--     shared with threads): the class base, STR_PACK, Event, the RNG and pool
--     primitives, Back and Card (the voucher decks' Card.apply_to_run).
--   * bh-core's sim modules and seedfinder.filter as the SAME module files the
--     main thread runs: their package.preload loaders, string.dump'ed on the
--     main thread and loaded as package.preload here. Nothing is forked.
--   * a stub G with the prototype projection installed (pools rebuilt from
--     ordered key lists, so pool order and pool->center identity are exact),
--     and a Game whose init_game_object returns a deep copy of the main
--     thread's Game:init_game_object() result (roadmap T3: game.lua is never
--     loaded here). state.fresh then runs as it does on the main thread:
--     stake rules, Back:apply_to_run, and hashed_seed = pseudohash(seed)
--     computed in this thread (journal/2026-09-23-str-pack-float-precision.md:
--     hashed seeds never travel through STR_PACK).
--   * per seed: filter.eval_seed(f, seed) = filter.eval(state.fresh(seed), f).
--   * sample jobs: seedfinder.odds (shipped the same way) counts each clause
--     as a one-clause filter and the whole filter once, per seed.
--   Every hit it reports is a candidate; the engine re-checks it on the main
--   thread before reporting it.
local M = {}

M.VANILLA = {
  'engine/object.lua', 'engine/string_packer.lua', 'engine/event.lua',
  'engine/node.lua', 'engine/moveable.lua',
  'functions/misc_functions.lua', 'functions/common_events.lua',
  'back.lua', 'card.lua',
}

M.SEEDS_SOURCE = [==[
local ALPHA = '123456789ABCDEFGHIJKLMNPQRSTUVWXYZ'
return function(i)
  local st = (i * 48271 + 11) % 2147483647
  local out = {}
  for c = 1, 8 do
    st = (st * 16807) % 2147483647
    local k = st % 34 + 1
    out[c] = ALPHA:sub(k, k)
  end
  return table.concat(out)
end
]==]

function M.seed_at(i)
  M._seed_at = M._seed_at or assert(loadstring(M.SEEDS_SOURCE, '=seedfinder.seeds'))()
  return M._seed_at(i)
end

M.SOURCE = [==[
-- seedfinder worker thread (source: seedfinder.worker)
local in_name, out_name, stop_name = ...
require 'love.filesystem'
require 'love.timer'
local inbox = love.thread.getChannel(in_name)
local outbox = love.thread.getChannel(out_name)
local stop = love.thread.getChannel(stop_name)
local STOP_EVERY = 32

local function deep_copy(t)
  if type(t) ~= 'table' then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = deep_copy(v) end
  return out
end

-- Stub G: what the loaded primitives and the sim read. Areas are swapped in
-- by sim.sandbox for each call; FORCE_TAG / FORCE_BOSS stay nil.
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

local filter, f, seed_at

local function init(msg)
  local t0 = love.timer.getTime()
  for _, path in ipairs(msg.vanilla) do
    local chunk, err = love.filesystem.load(path)
    if not chunk then error('load '..path..': '..tostring(err), 0) end
    chunk()
  end
  install(msg.data)
  for name, code in pairs(msg.modules) do
    package.preload[name] = assert(loadstring(code, '='..name))
  end
  -- sim.sandbox counts its depth on BHCore; the full bh-core (events hooks)
  -- belongs to the main thread only.
  BHCore = {sim_depth = 0, worker = true}
  filter = require('seedfinder.filter')
  local err
  f, err = filter.deserialize(msg.filter)
  if not f then error(err, 0) end
  seed_at = assert(loadstring(msg.seeds, '=seedfinder.seeds'))()
  outbox:push{kind = 'ready', ms = (love.timer.getTime() - t0) * 1000}
end

local function scan(job)
  local hits, n = {}, 0
  local list = job.seeds
  local from, to = job.from, job.to
  if list then from, to = 1, #list end
  for i = from, to do
    if n % STOP_EVERY == 0 and stop:getCount() > 0 then
      outbox:push{kind = 'done', id = job.id, n = n, hits = hits, stopped = true}
      return
    end
    local seed = list and list[i] or seed_at(i)
    if filter.eval_seed(f, seed) then hits[#hits + 1] = seed end
    n = n + 1
  end
  outbox:push{kind = 'done', id = job.id, n = n, hits = hits}
end

local function counts_msg(job, counts, stopped)
  return {kind = 'counts', id = job.id, n = counts.n, mode = counts.mode, clauses = counts.clauses,
    full = counts.full, stopped = stopped}
end

local function sample(job)
  local add, counts = require('seedfinder.odds').counter(f)
  local list = job.seeds
  local from, to = job.from, job.to
  if list then from, to = 1, #list end
  for i = from, to do
    if counts.n % STOP_EVERY == 0 and stop:getCount() > 0 then
      outbox:push(counts_msg(job, counts, true))
      return
    end
    add(list and list[i] or seed_at(i))
  end
  outbox:push(counts_msg(job, counts))
end

while true do
  local msg = inbox:demand()
  if msg.cmd == 'quit' then return end
  local ok, err = pcall(function()
    if msg.cmd == 'init' then init(msg)
    elseif msg.cmd == 'range' or msg.cmd == 'list' then
      if stop:getCount() > 0 then
        outbox:push{kind = 'done', id = msg.id, n = 0, hits = {}, stopped = true}
      else
        scan(msg)
      end
    elseif msg.cmd == 'sample' then
      if stop:getCount() > 0 then
        local _, counts = require('seedfinder.odds').counter(f)
        outbox:push(counts_msg(msg, counts, true))
      else
        sample(msg)
      end
    else error('unknown command '..tostring(msg.cmd), 0) end
  end)
  if not ok then
    outbox:push{kind = 'error', msg = tostring(err)}
    return
  end
end
]==]

return M
