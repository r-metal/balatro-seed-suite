-- saveslots.sharecode: encode/decode round trips (with and without love's
-- compressor), checksum and version rejection, the schema, size limits, and
-- hostile packed strings that must never run. The harness's love.data.compress
-- is an identity stub ('Z'..s), so the 'z' path is exercised for framing only.
local H = ...

local function sc() return require('saveslots.sharecode') end

-- A code with a hand-built body: `body` goes in raw (flag 'r') and the
-- checksum is correct, so only the body's content decides the outcome.
local function forge(body, prefix, flag)
  local m = sc()
  local head = (prefix or m.PREFIX)..m.base64((flag or 'r')..body)
  return head..'.'..m.checksum(head)
end

local function deep_eq(a, b, where)
  where = where or 't'
  if type(a) ~= 'table' or type(b) ~= 'table' then
    H.eq(a, b, where)
    return
  end
  for k, v in pairs(a) do deep_eq(v, b[k], where..'.'..tostring(k)) end
  for k in pairs(b) do H.ok(a[k] ~= nil, where..'.'..tostring(k)..' only on the right') end
end

local function sample()
  return {
    seed = 'ABCD1234', deck = 'b_red', stake = 5,
    notes = 'Skip "Small" for\nCharm -> Soul\\Perkeo, $4 left. ünïcode',
    route = {
      {ante = 1, blind = 'Small', action = 'skip', tag = 'tag_charm'},
      {ante = 1, blind = 'Big', action = 'play'},
      {ante = 2, action = 'shop', reroll = 0, slot = 2, key = 'j_blueprint', buy = true},
    },
    filter = {name = 'perkeo', stake = 5, deck = 'b_red', antes = 2, mode = 'all',
      clauses = {{kind = 'legendary', index = 1, key = 'j_perkeo'},
                 {kind = 'tag', ante = 1, blind = 'Small', key = 'tag_charm'}}},
  }
end

H.test('round trip through love.data (flag z) keeps every field', function()
  local m = sc()
  local t = sample()
  local code = assert(m.encode(t))
  H.eq(code:sub(1, 5), 'BHS1:')
  H.ok(code:match('^BHS1:[%w+/=]+%.%x%x%x%x%x%x%x%x$'), 'shape: '..code)
  H.eq(m.unbase64(code:match(':(.-)%.')):sub(1, 1), 'z', 'compressed when love exists')
  deep_eq(assert(m.decode(code)), t)
  -- Minimal slot: only the required fields, and clipboard whitespace.
  local min = {seed = '7', deck = 'b_black', stake = 1}
  deep_eq(assert(m.decode('  \n'..assert(m.encode(min))..'\r\n ')), min)
end)

H.test('without love the code is raw (flag r) and decodes with or without love', function()
  local m = sc()
  local keep = love
  love = nil
  local t = sample()
  local code = assert(m.encode(t))
  H.eq(m.unbase64(code:match(':(.-)%.')):sub(1, 1), 'r', 'raw when love is missing')
  deep_eq(assert(m.decode(code)), t, 'no love')
  love = keep
  deep_eq(assert(m.decode(code)), t, 'raw code in a love world')
  -- A compressed code can't be read without love: a clean error, not a raise.
  local z = assert(m.encode(t))
  love = nil
  local r, err = m.decode(z)
  love = keep
  H.eq(r, nil)
  H.ok(err:find('love'), err)
end)

H.test('a tampered body or checksum is rejected', function()
  local m = sc()
  local code = assert(m.encode(sample()))
  local head, sum = code:match('^(.-)%.(%x+)$')
  -- Flip one base64 char in the body.
  local i = #head - 3
  local ch = head:sub(i, i) == 'A' and 'B' or 'A'
  local r, err = m.decode(head:sub(1, i - 1)..ch..head:sub(i + 1)..'.'..sum)
  H.eq(r, nil); H.ok(err:find('checksum'), err)
  -- Change the checksum itself.
  local bad = (sum:sub(1, 1) == '0' and '1' or '0')..sum:sub(2)
  r, err = m.decode(head..'.'..bad)
  H.eq(r, nil); H.ok(err:find('checksum'), err)
  -- Drop it.
  r, err = m.decode(head)
  H.eq(r, nil); H.ok(err:find('checksum'), err)
end)

H.test('unknown versions and foreign strings are rejected', function()
  local m = sc()
  local body = STR_PACK({seed = 'ABCD1234', deck = 'b_red', stake = 1})
  H.ok(m.decode(forge(body)), 'the forge itself is valid for BHS1')
  local r, err = m.decode(forge(body, 'BHS2:'))
  H.eq(r, nil); H.ok(err:find('unknown version BHS2'), err)
  r, err = m.decode(forge(body, 'BHS0:'))
  H.eq(r, nil); H.ok(err:find('unknown version'), err)
  for _, s in ipairs({'', 'ABCD1234', 'bhs1:abc.00000000', 'BHS:abc.00000000'}) do
    r, err = m.decode(s)
    H.eq(r, nil, s); H.ok(err:find('not a share code'), s..': '..tostring(err))
  end
  r, err = m.decode(forge(body, nil, 'x'))
  H.eq(r, nil); H.ok(err:find('flag'), err)
  r, err = m.decode(42)
  H.eq(r, nil); H.ok(err:find('not a string'), err)
end)

H.test('injection: a packed string that calls os.execute never runs it', function()
  local m = sc()
  local ran = {}
  local real_exec, real_remove = os.execute, os.remove
  os.execute = function(...) ran[#ran+1] = 'execute'; return 0 end
  os.remove = function(...) ran[#ran+1] = 'remove'; return true end
  _G.PWNED = nil
  local hostile = {
    'return {seed=os.execute("touch /tmp/pwned"),deck="b_red",stake=1,}',
    'return {seed="A",deck="b_red",stake=1,} os.execute("x")',
    'os.execute("x") return {seed="A",deck="b_red",stake=1,}',
    'return {seed=(function() os.execute("x") return "A" end)(),deck="b_red",stake=1,}',
    'return {seed=("A"):rep(3),deck="b_red",stake=1,}',
    'return {seed=_G.os.remove("x"),deck="b_red",stake=1,}',
    -- Long bracket desync: Lua sees [[ " ]] as a string, then live code.
    'return {seed=[[ " ]],deck=os.execute("x"),n=" ]],stake=1,}',
    'return {seed="A",deck="b_red",stake=1,} --[[ " ]] os.execute("x") --"',
    'return {seed="A",deck="b_red",stake=1,} while true do end',
    -- Passes the char filter, but os is nil in the empty environment.
    'return {seed=os.execute,deck="b_red",stake=1,}',
    'return {seed=PWNED,deck="b_red",stake=1,}',
  }
  local results = {}
  for i, body in ipairs(hostile) do
    local ok, r, err = pcall(m.decode, forge(body))
    results[i] = {ok = ok, r = r, err = err}
  end
  -- The same bodies inside a love 'z' frame go through the same checks.
  local ok_z, rz = pcall(m.decode, forge('Z'..hostile[1], nil, 'z'))
  os.execute, os.remove = real_exec, real_remove
  H.eq(#ran, 0, 'no os call ran')
  for i, res in ipairs(results) do
    H.ok(res.ok, 'decode raised on hostile #'..i..': '..tostring(res.r))
    H.eq(res.r, nil, 'hostile #'..i..' decoded')
    H.ok(type(res.err) == 'string', 'hostile #'..i..' has an error')
  end
  H.ok(ok_z and rz == nil, 'z-framed hostile body decoded')
  H.eq(_G.PWNED, nil)
end)

H.test('oversize input is rejected before and after decompression', function()
  local m = sc()
  local code = assert(m.encode(sample()))
  local r, err = m.decode(code..string.rep(' ', m.MAX_CODE - #code + 1))
  H.eq(r, nil); H.ok(err:find('too long'), err)
  r, err = m.decode(string.rep('A', 9000))
  H.eq(r, nil); H.ok(err:find('too long'), err)
  -- A body over MAX_BODY behind a small 'z' frame (the stub inflates 'Z'..s to s).
  love.data.decompress = function() return 'return {'..string.rep(' ', m.MAX_BODY)..'}' end
  r, err = m.decode(forge('Zx', nil, 'z'))
  H.eq(r, nil); H.ok(err:find('too large'), err)
  -- encode refuses to make a code decode would refuse.
  local big = sample()
  big.route = {}
  for i = 1, 400 do big.route[i] = {ante = i, action = 'shop', key = 'j_blueprint', note = 'x'} end
  love = nil
  r, err = m.encode(big)
  H.eq(r, nil); H.ok(err:find('too long'), err)
end)

H.test('fields outside the schema are rejected by encode and decode', function()
  local m = sc()
  local cases = {
    {'extra field', {seed = 'A', deck = 'b_red', stake = 1, dollars = 99}, 'unknown field'},
    {'no seed', {deck = 'b_red', stake = 1}, 'seed'},
    {'long seed', {seed = 'ABCDEFGHI', deck = 'b_red', stake = 1}, 'seed'},
    {'lowercase seed', {seed = 'abcd', deck = 'b_red', stake = 1}, 'seed'},
    {'bad deck', {seed = 'A', deck = 'Red Deck', stake = 1}, 'deck'},
    {'stake 0', {seed = 'A', deck = 'b_red', stake = 0}, 'stake'},
    {'stake 9', {seed = 'A', deck = 'b_red', stake = 9}, 'stake'},
    {'stake 1.5', {seed = 'A', deck = 'b_red', stake = 1.5}, 'stake'},
    {'notes table', {seed = 'A', deck = 'b_red', stake = 1, notes = {}}, 'notes'},
    {'notes too long', {seed = 'A', deck = 'b_red', stake = 1, notes = string.rep('n', 2001)}, 'notes'},
    {'route string', {seed = 'A', deck = 'b_red', stake = 1, route = 'skip'}, 'route'},
    {'route function', {seed = 'A', deck = 'b_red', stake = 1, route = {{f = print}}}, 'function'},
    {'filter too deep', {seed = 'A', deck = 'b_red', stake = 1,
      filter = {{{{{{{{{{x = 1}}}}}}}}}}}, 'deep'},
  }
  for _, c in ipairs(cases) do
    local r, err = m.encode(c[2])
    H.eq(r, nil, 'encode '..c[1]); H.ok(err:find(c[3]), c[1]..': '..tostring(err))
  end
  for _, body in ipairs({
    'return {seed="A",deck="b_red",stake=1,dollars=99,}',
    'return {seed="A",deck="b_red",}',
    'return {seed="A",deck="b_red",stake=1,route={[true]=1,},}',
    'return {1,2,3,}',
    'return "BHS1"',
  }) do
    local r, err = m.decode(forge(body))
    H.eq(r, nil, body); H.ok(type(err) == 'string', body)
  end
  -- With SeedFinder loaded, the filter must pass its own validate.
  package.loaded['seedfinder.filter'] = {validate = function(f)
    if f.clauses then return true end
    return nil, 'filter: no clauses'
  end}
  local r, err = m.encode({seed = 'A', deck = 'b_red', stake = 1, filter = {name = 'x'}})
  package.loaded['seedfinder.filter'] = nil
  H.eq(r, nil); H.ok(err:find('no clauses'), tostring(err))
end)

H.test('base64 and checksum match known vectors and round-trip every byte', function()
  local m = sc()
  local vec = {[''] = '', f = 'Zg==', fo = 'Zm8=', foo = 'Zm9v', foob = 'Zm9vYg==',
    fooba = 'Zm9vYmE=', foobar = 'Zm9vYmFy'}
  for plain, enc in pairs(vec) do
    H.eq(m.base64(plain), enc, plain)
    H.eq(m.unbase64(enc), plain, enc)
  end
  local all = {}
  for i = 0, 255 do all[#all+1] = string.char(i) end
  all = table.concat(all)
  for n = 250, 256 do H.eq(m.unbase64(m.base64(all:sub(1, n))), all:sub(1, n), 'len '..n) end
  for _, bad in ipairs({'Zg=', 'Z===', 'Zg=a', '====', 'Zm9v!A==', 'Zm.v'}) do
    H.eq(m.unbase64(bad), nil, bad)
  end
  H.eq(m.checksum('Wikipedia'), '11e60398', 'Adler-32 reference vector')
end)
