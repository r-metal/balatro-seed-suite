-- Written by the wave-3b store verifier (independent of the implementer); adopted by the
-- orchestrator as the T-002c gate. Orchestrator-owned: implementers may not edit this file.
local H = ...
local real_time = os.time
local reset = H.reset
H.reset = function() reset(); os.time = function() return 1700000000 end end
local function names(l) local o = {} for i, e in ipairs(l) do o[i] = e.name end return table.concat(o, ',') end
for _, st in ipairs{'tmpjunk-only', 'mainjunk-only', 'tmp-only-good'} do
 for _, how in ipairs{'fail', 'tear'} do
  H.test('V3e '..st..' overwrite with a single failing staging write ('..how..') leaves list unchanged', function()
    local s = require('saveslots.store')
    local a = s.save(H.fake_run{ante = 1}, 'a')
    local p = '1/saveslots/'..a..'.jkr'
    if st == 'tmpjunk-only' then love.filesystem.remove(p); love.filesystem.write(p..'.tmp', 'Zjunk{')
    elseif st == 'mainjunk-only' then love.filesystem.write(p, 'Zjunk{')
    else love.filesystem.write(p..'.tmp', love.filesystem.read(p)); love.filesystem.remove(p) end
    local before = names(s.list())
    local r0 = s.read(a)
    local w = love.filesystem.write
    local n = 0
    love.filesystem.write = function(q, d)
      if q == p..'.tmp' and n == 0 then n = 1; if how == 'tear' then w(q, d:sub(1, 5)) end return false, 'disk full' end
      return w(q, d)
    end
    local r, err = s.save(H.fake_run{ante = 9}, 'x', a)
    love.filesystem.write = w
    if os.getenv("VERBOSE") == "1" then print(st, how, 'save ->', r, err, 'list before', before, 'after', names(s.list())) end
    if not r then
      H.eq(names(s.list()), before, 'list unchanged')
      H.eq(s.read(a) and s.read(a).GAME.round_resets.ante, r0 and r0.GAME.round_resets.ante)
    end
  end)
 end
end
H.reset = reset
os.time = real_time
