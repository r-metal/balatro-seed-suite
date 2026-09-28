-- seedfinder.daily: the day's seed, deck and stake, and starting it (T-377).
-- The locked answers (SWARM_TASKS.md, Research picks): the UTC date picks the
-- seed and the deck (any vanilla deck; Red when the profile hasn't unlocked
-- it), White Stake, seeded like vanilla (so it counts for no unlock or high
-- score), and two modes: 'blind' (the Oracle locked for that run, SeedOracle
-- ui.lua) and 'routed'.
--
-- API
--   daily.today(t?)        {date = 'YYYY-MM-DD', seed, deck, stake = 1} for the UTC
--                          day of `t` (seconds, default os.time()). The same for
--                          every player on the same UTC day: a pure function of
--                          the date (below), never math.random.
--   daily.deck_for(profile?, t?)
--                          the day's deck key, or 'b_red' and the reason when
--                          the profile hasn't unlocked it: deck, reason (nil
--                          when the day's deck is used). `profile` is a
--                          G.PROFILES entry or its number, default the current
--                          one. A deck is unlocked when its G.P_CENTERS entry is
--                          (the loaded profile's unlocks, game.lua:748) or the
--                          profile has all_unlocked: the Finder's rule (ui.lua,
--                          deck_unlocked).
--   daily.play(mode, t?)   mode 'blind' | 'routed'. Starts a run on the day's
--                          seed, deck_for's deck and stake 1 the way vanilla's
--                          seeded run setup does (G.GAME.viewed_back, then
--                          G.FUNCS.start_run(nil, {seed, stake})), and leaves it
--                          `seeded`. Before the run starts it tells RunJournal
--                          set_origin{kind = 'daily', date, mode} (pcall, as
--                          Finder Play does; the Journal keeps those fields from
--                          T-370 on). A deck fallback is printed with its reason.
--                          Returns true, {date, seed, deck, stake, mode, reason},
--                          or nil, err for a bad mode.
--   daily.DECKS            the 15 vanilla decks, in vanilla's collection order
--                          (the `order` field, game.lua:628-642): the list the
--                          day's deck is picked from. Never `pairs` order.
--   daily.ALPHABET         vanilla's seed alphabet, 1-9 A-N P-Z (random_string,
--                          misc_functions.lua:270, has no 0 and no O): 34 chars.
--   daily.hash(s)          the 32-bit hash below, as a number in [0, 2^32).
--   daily.install()        wraps Game.start_run (once).
--
-- The hash. hash(s) = fmix32(fnv1a32(s)):
--   * fnv1a32: FNV-1a, 32 bits (offset basis 2166136261, prime 16777619) over
--     the bytes of s;
--   * fmix32: MurmurHash3's 32-bit finalizer (h ^= h >> 16; h *= 0x85ebca6b;
--     h ^= h >> 13; h *= 0xc2b2ae35; h ^= h >> 16), so dates a day apart come
--     out unrelated.
--   seed[i] = ALPHABET[hash('bh-daily/<date>/seed/<i>') % 34 + 1], i = 1..8
--   deck    = DECKS[hash('bh-daily/<date>/deck') % 15 + 1]
--   The arithmetic is plain Lua numbers, exact because every intermediate stays
--   below 2^53 (a 32x32 product is split in 16-bit halves); no bit library, so
--   another tool can reproduce the day's seed from this description alone.
--   tests/test_daily.lua pins the hash against an independent implementation
--   and three dates against their seed and deck: changing any of this changes
--   every player's daily.
--
-- bh_daily. The Game.start_run wrap sets G.GAME.bh_daily = {date, mode} right
-- after start_run returns, for the run daily.play started only (its seed, not
-- a loaded save). It lives in G.GAME, so it saves with the run and a Continue
-- brings it back. bh-core's run_start fires inside start_run, before it is set.
local M = {}

M.DECKS = {
  'b_red', 'b_blue', 'b_yellow', 'b_green', 'b_black',
  'b_magic', 'b_nebula', 'b_ghost', 'b_abandoned', 'b_checkered',
  'b_zodiac', 'b_painted', 'b_anaglyph', 'b_plasma', 'b_erratic',
}
M.ALPHABET = '123456789ABCDEFGHIJKLMNPQRSTUVWXYZ'
local FALLBACK = 'b_red'
local SEED_LEN = 8

local TWO32 = 4294967296
local installed = false
local pending = nil     -- {seed, date, mode} of the run daily.play queued

-- 32-bit helpers on non-negative integers below 2^32.
local function bxor(a, b)
  local r, p = 0, 1
  for _ = 1, 32 do
    local x, y = a % 2, b % 2
    if x ~= y then r = r + p end
    a, b, p = (a - x)/2, (b - y)/2, p*2
  end
  return r
end

local function shr(a, n) return math.floor(a/2^n) end

local function mul(a, b)
  local hi, lo = math.floor(a/65536), a % 65536
  return ((hi*b) % 65536*65536 + lo*b) % TWO32
end

local function fnv1a32(s)
  local h = 2166136261
  for i = 1, #s do h = mul(bxor(h, s:byte(i)), 16777619) end
  return h
end

local function fmix32(h)
  h = bxor(h, shr(h, 16))
  h = mul(h, 0x85ebca6b)
  h = bxor(h, shr(h, 13))
  h = mul(h, 0xc2b2ae35)
  return bxor(h, shr(h, 16))
end

function M.hash(s) return fmix32(fnv1a32(tostring(s))) end

function M.today(t)
  local date = os.date('!%Y-%m-%d', tonumber(t) or os.time())
  local chars, n = {}, #M.ALPHABET
  for i = 1, SEED_LEN do
    local k = M.hash('bh-daily/'..date..'/seed/'..i) % n + 1
    chars[i] = M.ALPHABET:sub(k, k)
  end
  local deck = M.DECKS[M.hash('bh-daily/'..date..'/deck') % #M.DECKS + 1]
  return {date = date, seed = table.concat(chars), deck = deck, stake = 1}
end

local function deck_name(key)
  if type(localize) == 'function' then
    local ok, s = pcall(localize, {type = 'name_text', set = 'Back', key = key})
    if ok and type(s) == 'string' and s ~= '' and s ~= 'ERROR' then return s end
  end
  local c = G.P_CENTERS and G.P_CENTERS[key]
  return c and c.name or tostring(key)
end

function M.deck_for(profile, t)
  local key = M.today(t).deck
  if type(profile) ~= 'table' then
    profile = G.PROFILES and G.PROFILES[profile or (G.SETTINGS and G.SETTINGS.profile)] or nil
  end
  local center = G.P_CENTERS and G.P_CENTERS[key]
  if center and (center.unlocked or (profile and profile.all_unlocked)) then return key end
  if not center then return FALLBACK, deck_name(key)..' is not in this game: playing '..deck_name(FALLBACK) end
  return FALLBACK, deck_name(key)..' is locked on this profile: playing '..deck_name(FALLBACK)
end

function M.play(mode, t)
  if mode ~= 'blind' and mode ~= 'routed' then return nil, 'mode must be blind or routed' end
  local day = M.today(t)
  local deck, reason = M.deck_for(nil, t)
  if reason then print('[SeedFinder] daily '..day.date..': '..reason) end
  if type(RunJournal) == 'table' and RunJournal.recorder and RunJournal.recorder.set_origin then
    pcall(RunJournal.recorder.set_origin, {kind = 'daily', date = day.date, mode = mode})
  end
  local back = G.P_CENTERS and G.P_CENTERS[deck]
  if G.GAME and back then G.GAME.viewed_back = Back(back) end
  if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() end
  pending = {seed = day.seed, date = day.date, mode = mode}
  G.FUNCS.start_run(nil, {seed = day.seed, stake = day.stake})
  return true, {date = day.date, seed = day.seed, deck = deck, stake = day.stake, mode = mode, reason = reason}
end

function M.install()
  if installed then return end
  installed = true

  local orig_start_run = Game.start_run
  Game.start_run = function(self, args, ...)
    local want = pending
    pending = nil
    local ret = orig_start_run(self, args, ...)
    if want and type(args) == 'table' and args.seed == want.seed and not args.savetext
        and type(self.GAME) == 'table' then
      self.GAME.bh_daily = {date = want.date, mode = want.mode}
    end
    return ret
  end
end

return M
