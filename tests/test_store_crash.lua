-- Written by the wave-3b store verifier (independent of the implementer); adopted by the
-- orchestrator as the T-002c gate. Orchestrator-owned: implementers may not edit this file.
local H = ...
local real_time = os.time
local reset = H.reset
H.reset = function() reset(); os.time = function() return 1700000000 end end
local function names(l) local o = {} for i, e in ipairs(l) do o[i] = e.name end return table.concat(o, ',') end
local function bs(k, run) love.filesystem.createDirectory('1'); compress_and_save('1/saveState'..k..'.jkr', run) end

-- Crash (process dies) partway through writing path matching `pred`: half the bytes land.
local function crash_during(pred, fn)
  local w = love.filesystem.write
  love.filesystem.write = function(p, d)
    if pred(p) then w(p, d:sub(1, math.floor(#d/2))); coroutine.yield('crashed') end
    return w(p, d)
  end
  local co = coroutine.create(fn)
  local ok, res = coroutine.resume(co)
  love.filesystem.write = w
  return coroutine.status(co), ok, res
end

H.test('CRASH during the Brainstorm copy staging: next import still imports saveState1', function()
  local s = require('saveslots.store')
  bs(1, H.fake_run{ante = 1})
  local st = crash_during(function(p) return p:match('^1/saveslots/%d+%.jkr%.tmp$') end, function() return s.import_brainstorm() end)
  H.eq(st, 'suspended', 'crash simulated')
  -- restart
  package.loaded['saveslots.store'] = nil
  s = require('saveslots.store')
  local l = s.list()
  if os.getenv("VERBOSE") == "1" then print('after crash list:', names(l), l[1] and tostring(s.read(l[1].id))) end
  local n = s.import_brainstorm()
  if os.getenv("VERBOSE") == "1" then print('import after crash ->', n) end
  local readable = 0
  for _, e in ipairs(s.list()) do if s.read(e.id) then readable = readable + 1 end end
  if os.getenv("VERBOSE") == "1" then print('list:', names(s.list()), 'readable', readable) end
  H.eq(readable, 1, 'saveState1 must end up imported as a readable slot')
end)

H.test('CRASH during the Brainstorm copy final rewrite', function()
  local s = require('saveslots.store')
  bs(1, H.fake_run{ante = 1})
  local st = crash_during(function(p) return p:match('^1/saveslots/%d+%.jkr$') end, function() return s.import_brainstorm() end)
  package.loaded['saveslots.store'] = nil
  s = require('saveslots.store')
  s.import_brainstorm()
  local readable = 0
  for _, e in ipairs(s.list()) do if s.read(e.id) then readable = readable + 1 end end
  H.eq(readable, 1)
  H.eq(#s.list(), 1)
end)

H.test('CRASH during new-slot staging leaves nothing listed', function()
  local s = require('saveslots.store')
  s.save(H.fake_run{ante = 1}, 'a')
  os.time = function() return 1700000100 end
  crash_during(function(p) return p:match('1700000100%.jkr%.tmp$') end, function() return s.save(H.fake_run{ante = 9}, 'b') end)
  package.loaded['saveslots.store'] = nil
  s = require('saveslots.store')
  H.eq(names(s.list()), 'a')
  love.filesystem.remove('1/saveslots/index.jkr')
  H.eq(#s.list(), 1, names(s.list()))
end)
H.reset = reset
os.time = real_time
