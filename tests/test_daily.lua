-- seedfinder.daily (T-377): the day's seed and deck from the UTC date, the
-- locked-deck fallback, and daily.play's run setup against stubs of the vanilla
-- functions it calls (G.FUNCS.start_run, Game.start_run, Back). Nothing here runs
-- the game; rig/scenarios/daily_run.lua plays it for real.
local H = ...

local DAY = 86400
-- 2026-09-29 00:00:00 UTC. In any timezone west of UTC (UTC-3, say) the
-- local date at this second is still the 28th, so a local-time date would fail
-- the boundary case.
local MIDNIGHT = 1790640000
local NOON_28 = MIDNIGHT - DAY/2

-- The documented order (daily.lua header: vanilla's collection order).
local DECKS = {
  'b_red', 'b_blue', 'b_yellow', 'b_green', 'b_black',
  'b_magic', 'b_nebula', 'b_ghost', 'b_abandoned', 'b_checkered',
  'b_zodiac', 'b_painted', 'b_anaglyph', 'b_plasma', 'b_erratic',
}

local function daily() return require('seedfinder.daily') end

-- G.P_CENTERS with the 15 decks (only Red unlocked, as on a fresh profile) and
-- one profile.
local function decks_world(unlocked)
  G.P_CENTERS = {}
  for i, k in ipairs(DECKS) do
    local name = k:sub(3, 3):upper()..k:sub(4)..' Deck'
    G.P_CENTERS[k] = {key = k, name = name, set = 'Back', order = i, unlocked = k == 'b_red' or (unlocked or {})[k]}
  end
  G.PROFILES = {[1] = {}}
  G.SETTINGS.profile = 1
end

H.test('today(): stable within a UTC day, a new seed and date the next day', function()
  local d = daily()
  local a, b = d.today(NOON_28), d.today(NOON_28 + 3600)
  H.eq(a.date, '2026-09-28', 'date')
  H.eq(b.seed, a.seed, 'same day, same seed')
  H.eq(b.deck, a.deck, 'same day, same deck')
  H.eq(a.stake, 1, 'White Stake')
  H.eq(#a.seed, 8, 'seed length')
  local again = d.today(NOON_28)
  H.eq(again.seed, a.seed, 'a second call')
  local n = d.today(NOON_28 + DAY)
  H.eq(n.date, '2026-09-29', 'next date')
  H.ok(n.seed ~= a.seed, 'the next day has another seed')
  -- No argument means now.
  local now = os.time()
  local x, y = d.today(), d.today(now)
  H.ok(x.date == y.date and x.seed == y.seed or os.time() ~= now, 'today() is today(os.time())')
end)

H.test('the seed uses only vanilla\'s alphabet (no 0, no O), and all of it; every deck comes up', function()
  local d = daily()
  H.eq(d.ALPHABET, '123456789ABCDEFGHIJKLMNPQRSTUVWXYZ', 'alphabet')
  local chars, decks = {}, {}
  for i = 0, 399 do
    local t = d.today(NOON_28 + i*DAY)
    H.ok(t.seed:match('^[1-9A-NP-Z]+$') and #t.seed == 8, t.date..': bad seed '..t.seed)
    H.ok(not t.seed:find('[0O]'), t.date..': 0 or O in '..t.seed)
    for c in t.seed:gmatch('.') do chars[c] = true end
    decks[t.deck] = true
  end
  for c in d.ALPHABET:gmatch('.') do H.ok(chars[c], 'never drew '..c..' in 400 days') end
  for _, k in ipairs(DECKS) do H.ok(decks[k], 'never picked '..k..' in 400 days') end
end)

H.test('the date boundary is UTC midnight, not local midnight', function()
  local d = daily()
  H.eq(d.today(MIDNIGHT - 1).date, '2026-09-28', 'one second before')
  H.eq(d.today(MIDNIGHT).date, '2026-09-29', 'at midnight UTC')
  H.eq(d.today(MIDNIGHT).seed, d.today(MIDNIGHT + DAY - 1).seed, 'the whole UTC day')
  H.ok(d.today(MIDNIGHT - 1).seed ~= d.today(MIDNIGHT).seed, 'the seed changes at midnight UTC')
  for _, t in ipairs{MIDNIGHT - 1, MIDNIGHT, MIDNIGHT + 12345} do
    H.eq(d.today(t).date, os.date('!%Y-%m-%d', t), 'date of '..t)
  end
end)

-- Golden values: every player's daily depends on them. They were computed by an
-- independent Python implementation of the documented hash (FNV-1a 32 +
-- MurmurHash3 fmix32), which the Lua one matches.
H.test('the hash and the deck order are fixed: three dates -> seed and deck', function()
  local d = daily()
  H.eq(#d.DECKS, 15, 'deck count')
  for i, k in ipairs(DECKS) do H.eq(d.DECKS[i], k, 'DECKS['..i..']') end
  -- FNV-1a's published vectors pass through fmix32: '' -> 0x811c9dc5, 'a' -> 0xe40c292c.
  H.eq(d.hash(''), 2872998923, 'hash("")')
  H.eq(d.hash('a'), 444641715, 'hash("a")')
  H.eq(d.hash('foobar'), 202221276, 'hash("foobar")')
  local golden = {
    {1790596800, '2026-09-28', '9CWQP4Y9', 'b_anaglyph'},
    {1798761600, '2027-01-01', '4UXJ4HJ7', 'b_blue'},
    {1907712000, '2030-06-15', 'DRXKXD6L', 'b_magic'},
  }
  for _, g in ipairs(golden) do
    local t = d.today(g[1])
    H.eq(t.date, g[2], 'date')
    H.eq(t.seed, g[3], g[2]..' seed')
    H.eq(t.deck, g[4], g[2]..' deck')
  end
end)

H.test('today() leaves math.random\'s state alone and never calls it', function()
  local d = daily()
  math.randomseed(4242)
  local want = {}
  for i = 1, 5 do want[i] = math.random() end
  math.randomseed(4242)
  local got = {math.random()}
  local r, rs = math.random, math.randomseed
  math.random = function() error('daily called math.random') end
  math.randomseed = function() error('daily called math.randomseed') end
  local ok, err = pcall(function()
    for i = 0, 30 do d.today(NOON_28 + i*DAY) end
    decks_world()
    d.deck_for()
  end)
  math.random, math.randomseed = r, rs
  H.ok(ok, tostring(err))
  for i = 2, 5 do got[i] = math.random() end
  for i = 1, 5 do H.eq(got[i], want[i], 'draw '..i) end
end)

H.test('deck_for: the day\'s deck when unlocked; Red with the reason when locked', function()
  local d = daily()
  local t = NOON_28  -- the Anaglyph Deck
  decks_world()
  local deck, why = d.deck_for(nil, t)
  H.eq(deck, 'b_red', 'locked deck falls back')
  H.ok(type(why) == 'string' and why:find('Anaglyph Deck', 1, true) and why:find('locked', 1, true),
    'reason names the deck: '..tostring(why))
  H.eq(d.deck_for(1, t), 'b_red', 'a profile number')
  G.PROFILES[1].all_unlocked = true
  deck, why = d.deck_for(nil, t)
  H.eq(deck, 'b_anaglyph', 'all_unlocked profile')
  H.eq(why, nil, 'no reason')
  decks_world({b_anaglyph = true})
  deck, why = d.deck_for(G.PROFILES[1], t)
  H.eq(deck, 'b_anaglyph', 'unlocked deck')
  H.eq(why, nil, 'no reason')
  -- A day whose deck is Red is never a fallback.
  decks_world()
  local red
  for i = 0, 200 do
    if d.today(NOON_28 + i*DAY).deck == 'b_red' then red = NOON_28 + i*DAY; break end
  end
  H.ok(red, 'no Red day in 200')
  deck, why = d.deck_for(nil, red)
  H.eq(deck, 'b_red', 'Red day')
  H.eq(why, nil, 'Red day has no reason')
end)

-- daily.play against stubs: vanilla's G.FUNCS.start_run queues G:start_run,
-- which here runs at once and marks a seeded run the way game.lua:2163 does.
local function play_world()
  local w = {starts = {}, origins = {}}
  decks_world()
  Game = {}
  Game.start_run = function(self, args)
    args = args or {}
    w.starts[#w.starts + 1] = args
    if args.savetext then
      self.GAME = args.savetext.GAME
      return
    end
    local back = self.GAME and self.GAME.viewed_back
    self.GAME = {pseudorandom = {seed = args.seed or 'RANDOM'}, stake = args.stake or 1,
      selected_back_key = G.P_CENTERS[back and back.key or 'b_red']}
    if args.seed then self.GAME.seeded = true end
  end
  G.GAME = {}
  G.FUNCS.start_run = function(e, args) Game.start_run(G, args) end
  G.FUNCS.exit_overlay_menu = function() G.OVERLAY_MENU = nil end
  Back = function(center) return {key = center.key, name = center.name} end
  RunJournal = {recorder = {set_origin = function(o)
    w.origins[#w.origins + 1] = {o = o, started = #w.starts}
  end}}
  w.printed = {}
  w.print = print
  print = function(s) w.printed[#w.printed + 1] = s end
  return w
end

H.test('play: seeded run on the day\'s seed, deck and stake 1; bh_daily set; the origin told first', function()
  local d = daily()
  local w = play_world()
  local ok, err = pcall(function()
    d.install()
    d.install()  -- once
    local day = d.today()
    G.PROFILES[1].all_unlocked = true
    G.OVERLAY_MENU = {}
    local okp, info = d.play('blind')
    H.ok(okp, 'play refused')
    H.eq(G.OVERLAY_MENU, nil, 'the overlay was closed')
    H.eq(#w.starts, 1, 'one start_run')
    H.eq(w.starts[1].seed, day.seed, 'seed')
    H.eq(w.starts[1].stake, 1, 'stake')
    H.eq(G.GAME.pseudorandom.seed, day.seed, 'run seed')
    H.eq(G.GAME.selected_back_key.key, day.deck, 'deck (viewed_back)')
    H.eq(G.GAME.seeded, true, 'the run stays seeded')
    H.eq(G.GAME.bh_daily.date, day.date, 'bh_daily.date')
    H.eq(G.GAME.bh_daily.mode, 'blind', 'bh_daily.mode')
    H.eq(info.deck, day.deck, 'info deck')
    H.eq(info.reason, nil, 'no fallback')
    H.eq(#w.origins, 1, 'set_origin once')
    H.eq(w.origins[1].started, 0, 'set_origin before the run starts')
    local o = w.origins[1].o
    H.ok(o.kind == 'daily' and o.date == day.date and o.mode == 'blind', 'origin fields')
    -- A loaded save, or a run on another seed, is not stamped.
    G.GAME.bh_daily = nil
    Game.start_run(G, {seed = 'ABCDEFGH'})
    H.eq(G.GAME.bh_daily, nil, 'another run')
    local saved = {GAME = {pseudorandom = {seed = day.seed}, bh_daily = {date = day.date, mode = 'blind'}}}
    Game.start_run(G, {savetext = saved})
    H.eq(G.GAME.bh_daily.mode, 'blind', 'a Continue keeps what the save holds')
  end)
  print = w.print
  H.ok(ok, tostring(err))
end)

H.test('play: routed mode, the Red fallback logged, bad modes refused, no RunJournal is fine', function()
  local d = daily()
  local w = play_world()
  local ok, err = pcall(function()
    d.install()
    local t = NOON_28 -- the Anaglyph Deck, locked here
    local okp, info = d.play('routed', t)
    H.ok(okp, 'play refused')
    H.eq(G.GAME.pseudorandom.seed, d.today(t).seed, 'seed')
    H.eq(G.GAME.selected_back_key.key, 'b_red', 'fallback deck')
    H.eq(G.GAME.bh_daily.mode, 'routed', 'mode')
    H.ok(info.reason and info.reason:find('Anaglyph Deck', 1, true), 'reason returned')
    H.ok(w.printed[1] and w.printed[1]:find('locked', 1, true), 'reason printed: '..tostring(w.printed[1]))
    local bad, e = d.play('peek')
    H.eq(bad, nil, 'bad mode')
    H.ok(type(e) == 'string', 'bad mode error')
    H.eq(#w.starts, 1, 'a bad mode starts nothing')
    RunJournal = nil
    H.ok(d.play('blind', t), 'play without RunJournal')
    H.eq(G.GAME.bh_daily.mode, 'blind', 'mode without RunJournal')
  end)
  print = w.print
  H.ok(ok, tostring(err))
end)
