-- Unit-test harness: plain LuaJIT, no LÖVE. Loads the game's real string_packer
-- from build/game (extracted by `make game-src`) and stubs just enough of love/G.
-- Each test file gets a fresh world via H.reset().
local H = {}

local root = arg and arg[0]:match('^(.*)/tests/') or '.'
H.root = root

-- In-memory love.filesystem, keyed by path relative to the save dir.
local function make_love()
  local files, dirs = {}, {['']=true}
  local fs = {}
  function fs.getInfo(p)
    if files[p] then return {type='file', size=#files[p], modtime=0} end
    if dirs[p] then return {type='directory'} end
  end
  function fs.read(p) return files[p], files[p] and #files[p] or nil end
  function fs.write(p, s) files[p] = s; return true end
  function fs.remove(p)
    if files[p] then files[p] = nil; return true end
    if dirs[p] then dirs[p] = nil; return true end
    return false
  end
  function fs.createDirectory(p) dirs[p] = true; return true end
  function fs.getDirectoryItems(p)
    local out, prefix = {}, (p == '' and '' or p..'/')
    for k in pairs(files) do
      local rest = k:sub(1, #prefix) == prefix and k:sub(#prefix+1)
      if rest and not rest:find('/') then out[#out+1] = rest end
    end
    table.sort(out)
    return out
  end
  return {
    filesystem = fs,
    -- Identity "compression": keeps files readable in test failures.
    data = {
      compress = function(_, _, s) return 'Z'..s end,
      decompress = function(_, _, s) assert(s:sub(1,1) == 'Z', 'not compressed'); return s:sub(2) end,
    },
    _files = files,
  }
end

function H.reset()
  love = make_love()
  G = {
    SETTINGS = {profile = 1},
    STATES = {SELECTING_HAND=1, HAND_PLAYED=2, DRAW_TO_HAND=3, GAME_OVER=4, SHOP=5,
      PLAY_TAROT=6, BLIND_SELECT=7, ROUND_EVAL=8, TAROT_PACK=9, PLANET_PACK=10, MENU=11,
      TUTORIAL=12, SPLASH=13, SANDBOX=14, SPECTRAL_PACK=15, DEMO_CTA=16, STANDARD_PACK=17,
      BUFFOON_PACK=18, NEW_ROUND=19},
    STAGES = {MAIN_MENU=1, RUN=2, SANDBOX=3},
    ARGS = {}, FUNCS = {}, UIDEF = {},
  }
  dofile(root..'/build/game/engine/string_packer.lua')
  for k in pairs(package.loaded) do
    if H.module_paths[k] then package.loaded[k] = nil end
  end
  SaveSlots, BHCore, SeedOracle, SeedFinder, RunJournal = nil, nil, nil, nil, nil
end

-- require('<module>') for every [patches.module] in mods/*/lovely.toml, the same map
-- the smoke rig and lovely build. Parsed with the rig's own toml reader.
local module_paths = {}
do
  package.path = root..'/rig/?.lua;'..package.path
  local toml = require('toml')
  local ls = io.popen('ls -1 '..root..'/mods 2>/dev/null')
  for dir in ls:lines() do
    local f = io.open(root..'/mods/'..dir..'/lovely.toml', 'rb')
    if f then
      local m = toml.parse(f:read('*a'), 'mods/'..dir..'/lovely.toml'); f:close()
      for _, mod in ipairs(m.modules) do module_paths[mod.name] = root..'/mods/'..dir..'/'..mod.source end
    end
  end
  ls:close()
end
H.module_paths = module_paths
table.insert(package.loaders or package.searchers, 2, function(name)
  local path = module_paths[name]
  if not path then return end
  local f, err = loadfile(path)
  if not f then return '\n\t'..tostring(err) end
  return f
end)

-- A minimal but structurally real run table, shaped like save_run() output.
function H.fake_run(o)
  o = o or {}
  return {
    VERSION = o.version or '1.0.1o-FULL',
    STATE = o.state or G.STATES.SHOP,
    BACK = {name = o.deck or 'Red Deck'},
    BLIND = {name = 'Small Blind'},
    tags = {},
    cardAreas = {
      jokers = {config = {card_limit = 5}, cards = o.jokers or {
        {save_fields = {center = 'j_joker'}, ability = {name = 'Joker', set = 'Joker'}},
      }},
      consumeables = {config = {card_limit = 2}, cards = {}},
    },
    GAME = {
      stake = o.stake or 1, round = o.round or 3, dollars = o.dollars or 12,
      round_resets = {ante = o.ante or 2, hands = 4, discards = 3},
      pseudorandom = {seed = o.seed or 'ABCD1234'},
      used_vouchers = o.vouchers or {},
    },
  }
end

-- Tiny assertion kit. Failures are collected, not thrown, so one file reports all.
local results = {pass = 0, fail = 0, failures = {}}
H.results = results
function H.test(name, fn)
  H.reset()
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    results.pass = results.pass + 1
    if os.getenv('VERBOSE') == '1' then print('  ok   '..name) end
  else
    results.fail = results.fail + 1
    results.failures[#results.failures+1] = name..'\n    '..tostring(err):gsub('\n', '\n    ')
  end
end
function H.eq(a, b, msg)
  if a ~= b then error((msg or 'eq')..': expected '..tostring(b)..', got '..tostring(a), 2) end
end
function H.ok(v, msg) if not v then error(msg or 'expected truthy', 2) end end

return H
