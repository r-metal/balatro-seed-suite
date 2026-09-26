-- Runs every tests/test_*.lua. Prints failures and a tally; VERBOSE=1 lists passes.
local root = arg[0]:match('^(.*)/tests/') or '.'
package.path = root..'/tests/?.lua;'..package.path
local H = require('harness')

local only = arg[1]
local p = io.popen('ls '..root..'/tests/test_*.lua 2>/dev/null')
local files = {}
for f in p:lines() do files[#files+1] = f end
p:close()

local ran = 0
for _, f in ipairs(files) do
  if not only or f:find(only, 1, true) then
    ran = ran + 1
    local chunk, err = loadfile(f)
    if not chunk then
      H.results.fail = H.results.fail + 1
      H.results.failures[#H.results.failures+1] = f..': '..err
    else
      local ok, e = pcall(chunk, H)
      if not ok then
        H.results.fail = H.results.fail + 1
        H.results.failures[#H.results.failures+1] = f..': '..tostring(e)
      end
    end
  end
end

for _, f in ipairs(H.results.failures) do print('FAIL '..f) end
print(string.format('unit: %d passed, %d failed, %d files', H.results.pass, H.results.fail, ran))
if only and ran == 0 then print('unit: no test file matches '..only); os.exit(1) end
os.exit(H.results.fail == 0 and ran > 0 and 0 or 1)
