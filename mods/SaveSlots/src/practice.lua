-- Practice scenario composer. Contract: docs/contracts-0.2.md § SaveSlots 0.2 "Practice".
--
-- What this module is for
--   Compose a run (deck, stake, ante, money, jokers, consumables, hand levels), start
--   it as a real run, and keep it as a `kind = 'practice'` slot. The run is never
--   written by hand: vanilla `start_run` builds it, vanilla functions apply the
--   choices, and the slot is the next snapshot vanilla's own autosave takes (D6).
--
-- API
--   practice.install()        Registers the composer's G.FUNCS and wraps Game.start_run
--                             and save_run (both call the original). Runs once.
--   practice.open()           Opens the composer overlay (G.FUNCS.saveslots_practice,
--                             the "New practice" button of the Save Slots screen).
--   practice.choices()        A copy of the composer's current choices:
--                             {deck, stake, ante, dollars, jokers = {key..}, consumables =
--                             {key..}, hands = {{hand, level}..}}.
--   practice.validate(c)      A cleaned copy of choices `c`, or nil, err.
--   practice.create(c)        Validates, then starts the run on a fresh practice seed.
--                             Returns true, or nil, err. The slot appears at the run's
--                             first blind-select autosave (see practice.last()).
--   practice.last()           {id = slot id} once the last create was stored, {err = ..}
--                             when storing failed, {pending = true} while waiting; nil
--                             before any create.
--   Pools (what the composer offers): practice.decks(), practice.jokers(),
--   practice.consumables(set), practice.top_hands(); each returns {{key, name}..}
--   (top_hands: the 3 poker hand names).
--
-- How create works
--   1. Picks the deck the way the run-setup screen does (`G.GAME.viewed_back`) and
--      calls G.FUNCS.start_run with the stake and a `generate_starting_seed()` seed.
--      Passing a seed makes the run `seeded`, so vanilla keeps it out of high scores,
--      career stats and unlocks, as it does for any seeded run.
--   2. Right after Game:start_run returns (inside start_run's event, before the first
--      Game:update_blind_select queues its save_run), the choices are applied with
--      vanilla functions: ease_ante, then the new ante's voucher, tags and boss in the
--      order vanilla rolls them after a boss (state_events.lua:263 end_round's voucher,
--      button_callbacks.lua:2951-2952 cash_out's tags, :2954 reset_blinds' boss),
--      ease_dollars(instant), add_joker (jokers in order, then consumables; it is what
--      challenge runs use: Card + add_to_deck + emplace), level_up_hand(instant).
--   3. The first save_run after that whose snapshot is at BLIND_SELECT, on the practice
--      seed and at the composed ante, is stored through store.save with
--      meta = {kind = 'practice', practice = <choices>}. Nothing here calls save_run.
--
-- Traps
--   * The ante's blind amounts are read from `round_resets.blind_ante` (UI_definitions
--     create_UIBox_blind_choice), which ease_ante leaves alone, so it is set too.
--   * ease_ante applies in an event; get_new_boss and the 'Voucher'..ante and
--     'Tag'..ante streams read the ante, so the voucher/tag/boss re-roll is queued
--     behind it. Without the voucher draw the run keeps ante 1's shop voucher
--     (start_run's draw). Both run before the blind-select autosave, which is queued
--     a frame later by Game:update_blind_select.
--   * Composer cards are live Card objects. Card:set_ability writes G.GAME.used_jokers
--     (when no overlay is up) and To Do List draws from G.GAME.pseudorandom, so the
--     cards are built under guard_live_run and a composer opened mid-run never changes
--     the run being played (same technique as preview.lua).
--   * The game font (m6x11plus) has no '·' or '—' glyphs: labels are plain ASCII.
local store = require('saveslots.store')
local checkpoint = require('saveslots.checkpoint')

local practice = {}

practice.MAX_JOKERS = 5
practice.MAX_CONSUMABLES = 2
practice.MAX_ANTE = 8
practice.MAX_LEVEL = 15
practice.MONEY = {0, 4, 5, 10, 15, 20, 25, 30, 40, 50, 75, 100, 150, 200, 300, 500}
practice.CONSUMABLE_SETS = {'Tarot', 'Planet', 'Spectral'}
-- When the profile has played fewer than 3 hands, these fill the hand-level rows.
local FALLBACK_HANDS = {'Pair', 'Two Pair', 'Flush', 'High Card', 'Three of a Kind', 'Straight'}

local CARD_SCALE = 0.6
local COL_H = 7.2   -- every column of the composer is this tall
local START_H = 0.9 -- the Start button's row, under the hand levels
local PLATE_W = 6.7 -- the card groups' inner plate (5 jokers at CARD_SCALE)

local installed = false
local pending = nil  -- {choices, seed, applied} between create and the stored slot
local last = nil     -- see practice.last()

-- The composer's state; survives closing it for the rest of the session. `letter`
-- and `joker` are the joker search cycles, `cset`/`cons` the consumable ones.
local state = nil

local function copy(t) return STR_UNPACK(STR_PACK(t)) end

local function in_sim()
  return type(BHCore) == 'table' and (BHCore.sim_depth or 0) > 0
end

local function loc_name(set, key)
  local ok, s = pcall(localize, {type = 'name_text', set = set, key = key})
  if ok and type(s) == 'string' and s ~= 'ERROR' then return s end
  local c = G.P_CENTERS[key]
  return c and c.name or key
end

local function by_name(a, b)
  if a.name ~= b.name then return a.name < b.name end
  return a.key < b.key
end

-- pools -----------------------------------------------------------------------

function practice.decks()
  local out = {}
  for _, c in ipairs(G.P_CENTER_POOLS.Back or {}) do
    if c.unlocked ~= false then out[#out+1] = {key = c.key, name = loc_name('Back', c.key)} end
  end
  return out
end

function practice.jokers()
  local out = {}
  for _, c in ipairs(G.P_CENTER_POOLS.Joker or {}) do
    if c.unlocked ~= false then out[#out+1] = {key = c.key, name = loc_name('Joker', c.key)} end
  end
  table.sort(out, by_name)
  return out
end

function practice.consumables(set)
  local out = {}
  for _, c in ipairs(G.P_CENTER_POOLS[set] or {}) do
    if c.unlocked ~= false then out[#out+1] = {key = c.key, name = loc_name(set, c.key)} end
  end
  return out
end

-- The profile's 3 most-played poker hands (hand_usage, misc_functions.lua set_hand_usage),
-- topped up from FALLBACK_HANDS.
function practice.top_hands()
  local usage = G.PROFILES[G.SETTINGS.profile].hand_usage or {}
  local list = {}
  for _, u in pairs(usage) do
    if type(u) == 'table' and type(u.order) == 'string' and G.GAME.hands and G.GAME.hands[u.order] then
      list[#list+1] = {hand = u.order, count = tonumber(u.count) or 0}
    end
  end
  table.sort(list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.hand < b.hand
  end)
  local out, seen = {}, {}
  for _, u in ipairs(list) do
    if #out < 3 then out[#out+1] = u.hand; seen[u.hand] = true end
  end
  for _, h in ipairs(FALLBACK_HANDS) do
    if #out < 3 and not seen[h] then out[#out+1] = h; seen[h] = true end
  end
  return out
end

-- choices ---------------------------------------------------------------------

local function unlocked_center(key, sets)
  local c = type(key) == 'string' and G.P_CENTERS[key]
  return c and sets[c.set] and c.unlocked ~= false and c or nil
end

function practice.validate(c)
  if type(c) ~= 'table' then return nil, 'choices must be a table' end
  local out = {}
  if not unlocked_center(c.deck, {Back = true}) then return nil, 'bad deck '..tostring(c.deck) end
  out.deck = c.deck
  local stakes = #(G.P_CENTER_POOLS.Stake or {})
  if type(c.stake) ~= 'number' or c.stake % 1 ~= 0 or c.stake < 1 or c.stake > stakes then
    return nil, 'bad stake '..tostring(c.stake)
  end
  out.stake = c.stake
  if type(c.ante) ~= 'number' or c.ante % 1 ~= 0 or c.ante < 1 or c.ante > practice.MAX_ANTE then
    return nil, 'bad ante '..tostring(c.ante)
  end
  out.ante = c.ante
  if type(c.dollars) ~= 'number' or c.dollars % 1 ~= 0 or c.dollars < 0 or c.dollars > 1e6 then
    return nil, 'bad dollars '..tostring(c.dollars)
  end
  out.dollars = c.dollars
  out.jokers, out.consumables, out.hands = {}, {}, {}
  if type(c.jokers or {}) ~= 'table' or #(c.jokers or {}) > practice.MAX_JOKERS then return nil, 'too many jokers' end
  for i, k in ipairs(c.jokers or {}) do
    if not unlocked_center(k, {Joker = true}) then return nil, 'bad joker '..tostring(k) end
    out.jokers[i] = k
  end
  if type(c.consumables or {}) ~= 'table' or #(c.consumables or {}) > practice.MAX_CONSUMABLES then
    return nil, 'too many consumables'
  end
  for i, k in ipairs(c.consumables or {}) do
    if not unlocked_center(k, {Tarot = true, Planet = true, Spectral = true}) then
      return nil, 'bad consumable '..tostring(k)
    end
    out.consumables[i] = k
  end
  if type(c.hands or {}) ~= 'table' then return nil, 'bad hands' end
  for _, h in ipairs(c.hands or {}) do
    if type(h) ~= 'table' or type(h.hand) ~= 'string' or not (G.GAME.hands and G.GAME.hands[h.hand]) then
      return nil, 'bad hand '..tostring(type(h) == 'table' and h.hand or h)
    end
    if type(h.level) ~= 'number' or h.level % 1 ~= 0 or h.level < 1 or h.level > practice.MAX_LEVEL then
      return nil, 'bad level for '..h.hand
    end
    out.hands[#out.hands+1] = {hand = h.hand, level = h.level}
  end
  return out
end

local function default_state()
  local decks = practice.decks()
  local hands = {}
  for i, h in ipairs(practice.top_hands()) do hands[i] = {hand = h, level = 1} end
  return {deck = decks[1] and decks[1].key or 'b_red', stake = 1, ante = 1, dollars = 4,
    jokers = {}, consumables = {}, hands = hands, letter = 1, joker = 1, cset = 1, cons = 1}
end

local function get_state()
  state = state or default_state()
  return state
end

function practice.choices()
  local s = get_state()
  return copy({deck = s.deck, stake = s.stake, ante = s.ante, dollars = s.dollars,
    jokers = s.jokers, consumables = s.consumables, hands = s.hands})
end

function practice.last() return last and copy(last) or nil end

-- create ------------------------------------------------------------------------

function practice.create(c)
  local clean, err = practice.validate(c)
  if not clean then return nil, err end
  local seed = generate_starting_seed()
  pending = {choices = clean, seed = seed, applied = false}
  last = {pending = true}
  -- The run-setup screen's way of choosing the deck (Game:start_run reads viewed_back).
  G.GAME.viewed_back = Back(G.P_CENTERS[clean.deck])
  if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() end
  G.FUNCS.start_run(nil, {stake = clean.stake, seed = seed})
  return true
end

-- Applies `c` to the run Game:start_run just built. Vanilla functions only.
local function apply(c)
  local rr = G.GAME.round_resets
  if c.ante > 1 then
    ease_ante(c.ante - 1)
    rr.blind_ante = c.ante
    G.E_MANAGER:add_event(Event({trigger = 'immediate', func = function()
      BHCore.roll_round_voucher()
      rr.blind_tags.Small = get_next_tag_key()
      rr.blind_tags.Big = get_next_tag_key()
      rr.blind_choices.Boss = get_new_boss()
      return true
    end}))
  end
  if c.dollars ~= G.GAME.dollars then ease_dollars(c.dollars - G.GAME.dollars, true) end
  for _, k in ipairs(c.jokers) do add_joker(k, nil, true) end
  for _, k in ipairs(c.consumables) do add_joker(k, nil, true) end
  for _, h in ipairs(c.hands) do
    local cur = G.GAME.hands[h.hand].level
    if h.level ~= cur then level_up_hand(nil, h.hand, true, h.level - cur) end
  end
end

local function run_name(c)
  return 'Practice A'..c.ante..' '..loc_name('Back', c.deck)
end

-- Called after every save_run: stores the first qualifying snapshot.
local function maybe_store()
  if not (pending and pending.applied) or in_sim() then return end
  local run = checkpoint.get()
  local game = type(run) == 'table' and run.GAME
  if not (game and game.pseudorandom and game.pseudorandom.seed == pending.seed) then return end
  if run.STATE ~= G.STATES.BLIND_SELECT or game.round_resets.ante ~= pending.choices.ante then return end
  local c = pending.choices
  pending = nil
  local id, err = store.save(run, run_name(c), nil, {kind = 'practice', practice = c})
  if id then
    last = {id = id}
  else
    last = {err = tostring(err)}
    print('[SaveSlots] practice slot not saved: '..tostring(err))
  end
  attention_text({text = id and 'Practice run saved' or 'Practice save failed', scale = 0.7, hold = 2,
    major = G.play, align = 'cm', offset = {x = 0, y = -2.7}, colour = G.C.WHITE, silent = true})
end

-- composer UI ---------------------------------------------------------------------

-- Card:set_ability writes to the live run (see Traps); undo those writes.
local function guard_live_run(fn)
  local game = type(G.GAME) == 'table' and G.GAME or {}
  local saved = {}
  for _, k in ipairs{'used_jokers', 'pseudorandom'} do
    if type(game[k]) == 'table' then
      local t = {}
      for kk, vv in pairs(game[k]) do t[kk] = vv end
      saved[k] = t
    end
  end
  local ok, res = pcall(fn)
  for k, t in pairs(saved) do
    local live = game[k]
    for kk in pairs(live) do if t[kk] == nil then live[kk] = nil end end
    for kk, vv in pairs(t) do live[kk] = vv end
  end
  if not ok then error(res, 0) end
  return res
end

-- Jokers grouped by the first letter of their name: {letters = {'A'..}, [letter] = {..}}.
local function joker_index()
  local idx = {letters = {}}
  for _, j in ipairs(practice.jokers()) do
    local l = j.name:sub(1, 1):upper()
    if not idx[l] then idx[l] = {}; idx.letters[#idx.letters+1] = l end
    idx[l][#idx[l]+1] = j
  end
  table.sort(idx.letters)
  return idx
end

local function clamp(i, n) return math.max(1, math.min(i or 1, math.max(n, 1))) end

local function index_of(list, pred)
  for i, v in ipairs(list) do if pred(v) then return i end end
end

local function cycle(args)
  return create_option_cycle({id = args.id, label = args.label, options = args.options,
    current_option = args.current, opt_callback = args.callback, w = args.w or 3.4, h = 0.6,
    scale = args.scale or 0.8, colour = G.C.RED, no_pips = true, text_scale = args.text_scale})
end

local function small_button(label, fn, colour, w)
  return UIBox_button({label = {label}, button = fn, colour = colour, minw = w or 1.4, minh = 0.55,
    scale = 0.38, col = true})
end

local function panel(title, nodes, minw, minh)
  local rows = {{n=G.UIT.R, config={align = 'cm', padding = 0.03}, nodes={
    {n=G.UIT.T, config={text = title, scale = 0.45, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
  }}}
  for _, n in ipairs(nodes) do rows[#rows+1] = n end
  return {n=G.UIT.C, config={align = 'tm', padding = 0.1, r = 0.1, colour = G.C.BLACK, minw = minw,
    minh = minh or COL_H}, nodes = rows}
end

-- A labelled row of display cards (the preview.lua group shape).
local function card_group(label, keys, limit, track)
  local area = track(CardArea(0, 0, limit*CARD_SCALE*G.CARD_W*1.05, 0.6*G.CARD_H, {card_limit = limit,
    card_w = CARD_SCALE*G.CARD_W, type = 'title_2', highlight_limit = 0}))
  for _, k in ipairs(keys) do
    local card = Card(0, 0, G.CARD_W*CARD_SCALE, G.CARD_H*CARD_SCALE, nil, G.P_CENTERS[k],
      {bypass_discovery_center = true, bypass_discovery_ui = true, bypass_lock = true})
    track(card)
    area:emplace(card)
  end
  local count = #keys
  if count == 0 then area:remove() end
  return {n=G.UIT.R, config={align = 'cm', padding = 0.05, colour = G.C.L_BLACK, r = 0.1}, nodes={
    {n=G.UIT.C, config={align = 'cm', minw = 0.4}, nodes={
      {n=G.UIT.T, config={text = label, scale = 0.32, colour = G.C.UI.TEXT_LIGHT, vert = true, shadow = true}},
    }},
    -- One plate width for every group, so the jokers and consumables rows line up.
    {n=G.UIT.C, config={align = 'cm', minh = 0.6*G.CARD_H + 0.1, minw = PLATE_W, r = 0.1,
        colour = G.C.UI.TRANSPARENT_DARK}, nodes={
      count > 0 and {n=G.UIT.O, config={object = area}}
        or {n=G.UIT.T, config={text = localize('k_none'), scale = 0.45, colour = G.C.UI.TEXT_LIGHT}},
    }},
  }}
end

local function row(nodes, padding)
  return {n=G.UIT.R, config={align = 'cm', padding = padding or 0.05}, nodes=nodes}
end

local function count_text(n, max)
  return {n=G.UIT.T, config={text = n..'/'..max, scale = 0.35, colour = G.C.UI.TEXT_LIGHT}}
end

local function composer_def(track)
  local s = get_state()

  -- run column
  local decks = practice.decks()
  local deck_i = index_of(decks, function(d) return d.key == s.deck end) or 1
  s.deck = decks[deck_i] and decks[deck_i].key or s.deck
  local deck_names = {}
  for i, d in ipairs(decks) do deck_names[i] = d.name end
  local stakes = {}
  for i, c in ipairs(G.P_CENTER_POOLS.Stake) do stakes[i] = loc_name('Stake', c.key) end
  local antes = {}
  for i = 1, practice.MAX_ANTE do antes[i] = tostring(i) end
  local money = {}
  for i, m in ipairs(practice.MONEY) do money[i] = localize('$')..m end
  local money_i = index_of(practice.MONEY, function(m) return m == s.dollars end) or 1
  s.dollars = practice.MONEY[money_i]

  local back = G.P_CENTERS[s.deck]
  local back_sprite = back and track(Sprite(0, 0, G.CARD_W*0.7, G.CARD_H*0.7, G.ASSET_ATLAS['centers'], back.pos))
  local stake_sprite = track(get_stake_sprite(s.stake, 0.5))

  local run_col = panel('Run', {
    row({
      back_sprite and {n=G.UIT.O, config={object = back_sprite}} or nil,
      {n=G.UIT.C, config={align = 'cm', padding = 0.05}, nodes={
        {n=G.UIT.O, config={object = stake_sprite}},
      }},
    }, 0.1),
    cycle({id = 'practice_deck', label = 'Deck', options = deck_names, current = deck_i, callback = 'practice_deck'}),
    cycle({id = 'practice_stake', label = 'Stake', options = stakes, current = s.stake, callback = 'practice_stake'}),
    cycle({id = 'practice_ante', label = localize('k_ante'), options = antes, current = s.ante,
      callback = 'practice_ante'}),
    cycle({id = 'practice_money', label = localize('k_money'), options = money, current = money_i,
      callback = 'practice_money'}),
  }, 4.2)

  -- jokers and consumables column
  local jidx = joker_index()
  s.letter = clamp(s.letter, #jidx.letters)
  local letter = jidx.letters[s.letter]
  local in_letter = letter and jidx[letter] or {}
  s.joker = clamp(s.joker, #in_letter)
  local joker_names = {}
  for i, j in ipairs(in_letter) do joker_names[i] = j.name end
  if #joker_names == 0 then joker_names[1] = localize('k_none') end

  local cset = practice.CONSUMABLE_SETS
  s.cset = clamp(s.cset, #cset)
  local cons = practice.consumables(cset[s.cset])
  s.cons = clamp(s.cons, #cons)
  local cons_names = {}
  for i, c in ipairs(cons) do cons_names[i] = c.name end
  if #cons_names == 0 then cons_names[1] = localize('k_none') end
  local set_labels = {}
  for i, k in ipairs(cset) do set_labels[i] = localize('k_'..k:lower()) end

  local full_j = #s.jokers >= practice.MAX_JOKERS
  local full_c = #s.consumables >= practice.MAX_CONSUMABLES
  local cards_col = panel('Cards', {
    card_group(localize('k_jokers_cap'), s.jokers, practice.MAX_JOKERS, track),
    row({
      cycle({id = 'practice_letter', options = jidx.letters[1] and jidx.letters or {'-'}, current = s.letter,
        callback = 'practice_letter', w = 0.7}),
      cycle({id = 'practice_joker', options = joker_names, current = s.joker, callback = 'practice_joker', w = 3.2}),
    }, 0),
    row({
      small_button(full_j and 'Full' or 'Add', full_j and 'practice_nop' or 'practice_add_joker',
        full_j and G.C.UI.BACKGROUND_INACTIVE or G.C.GREEN),
      {n=G.UIT.C, config={align = 'cm', minw = 0.9}, nodes={count_text(#s.jokers, practice.MAX_JOKERS)}},
      small_button('Remove', 'practice_remove_joker', G.C.RED),
    }),
    card_group(localize('k_cap_consumables'), s.consumables, practice.MAX_CONSUMABLES, track),
    row({
      cycle({id = 'practice_cset', options = set_labels, current = s.cset, callback = 'practice_cset', w = 1.6}),
      cycle({id = 'practice_cons', options = cons_names, current = s.cons, callback = 'practice_cons', w = 2.4}),
    }, 0),
    row({
      small_button(full_c and 'Full' or 'Add', full_c and 'practice_nop' or 'practice_add_cons',
        full_c and G.C.UI.BACKGROUND_INACTIVE or G.C.GREEN),
      {n=G.UIT.C, config={align = 'cm', minw = 0.9}, nodes={count_text(#s.consumables, practice.MAX_CONSUMABLES)}},
      small_button('Remove', 'practice_remove_cons', G.C.RED),
    }),
  }, 7.4)

  -- hand levels column
  local levels = {}
  for i = 1, practice.MAX_LEVEL do levels[i] = 'Level '..i end
  local hand_nodes = {
    row({{n=G.UIT.T, config={text = 'Your most played hands', scale = 0.3, colour = G.C.UI.TEXT_INACTIVE}}}),
  }
  for i, h in ipairs(s.hands) do
    hand_nodes[#hand_nodes+1] = cycle({id = 'practice_hand_'..i, label = localize(h.hand, 'poker_hands'),
      options = levels, current = h.level, callback = 'practice_hand_'..i, w = 2.6})
  end
  -- The hand levels panel is shortened by START_H so Start sits under it, level with
  -- the other columns' bottoms.
  local hands_col = {n=G.UIT.C, config={align = 'tm'}, nodes={
    {n=G.UIT.R, config={align = 'tm'}, nodes={panel('Hand levels', hand_nodes, 3.8, COL_H - START_H)}},
    {n=G.UIT.R, config={align = 'bm', minh = START_H}, nodes={
      UIBox_button({id = 'practice_create', label = {'Start practice', 'run'}, button = 'practice_create',
        colour = G.C.GREEN, minw = 3.8, minh = START_H - 0.1, scale = 0.42}),
    }},
  }}

  return create_UIBox_generic_options({
    back_func = 'saveslots_open',
    contents = {
      {n=G.UIT.R, config={align = 'cm', padding = 0.02}, nodes={
        {n=G.UIT.T, config={text = 'New practice run', scale = 0.6, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
      }},
      {n=G.UIT.R, config={align = 'tm', padding = 0.05}, nodes={run_col, cards_col, hands_col}},
    },
  })
end

-- (Re)builds the composer. `animate` = false snaps it into place (after a change).
local function open(animate)
  local made = {}
  local function track(obj) made[#made+1] = obj; return obj end
  local def = guard_live_run(function()
    local ok, res = pcall(composer_def, track)
    if not ok then
      for i = #made, 1, -1 do pcall(made[i].remove, made[i]) end
      error(res, 0)
    end
    return res
  end)
  G.SETTINGS.paused = true
  G.FUNCS.overlay_menu{definition = def}
  if not animate and G.OVERLAY_MENU then G.OVERLAY_MENU:hard_set_VT() end
end

function practice.open() open(true) end

-- Registers every composer button and cycle callback.
local function install_funcs()
  local function changed() open(false) end

  G.FUNCS.saveslots_practice = function(e) practice.open() end
  G.FUNCS.practice_nop = function(e) end

  G.FUNCS.practice_deck = function(args)
    local d = practice.decks()[args.to_key]
    if d then get_state().deck = d.key end
    changed()
  end
  G.FUNCS.practice_stake = function(args) get_state().stake = args.to_key; changed() end
  G.FUNCS.practice_ante = function(args) get_state().ante = args.to_key; changed() end
  G.FUNCS.practice_money = function(args)
    get_state().dollars = practice.MONEY[args.to_key] or 0
    changed()
  end
  G.FUNCS.practice_letter = function(args)
    local s = get_state()
    s.letter, s.joker = args.to_key, 1
    changed()
  end
  G.FUNCS.practice_joker = function(args) get_state().joker = args.to_key; changed() end
  G.FUNCS.practice_cset = function(args)
    local s = get_state()
    s.cset, s.cons = args.to_key, 1
    changed()
  end
  G.FUNCS.practice_cons = function(args) get_state().cons = args.to_key; changed() end
  for i = 1, 3 do
    G.FUNCS['practice_hand_'..i] = function(args)
      local h = get_state().hands[i]
      if h then h.level = args.to_key end
      changed()
    end
  end

  G.FUNCS.practice_add_joker = function(e)
    local s = get_state()
    local jidx = joker_index()
    local letter = jidx.letters[s.letter]
    local j = letter and jidx[letter][s.joker]
    if j and #s.jokers < practice.MAX_JOKERS then s.jokers[#s.jokers+1] = j.key end
    changed()
  end
  G.FUNCS.practice_remove_joker = function(e)
    local s = get_state()
    s.jokers[#s.jokers] = nil
    changed()
  end
  G.FUNCS.practice_add_cons = function(e)
    local s = get_state()
    local c = practice.consumables(practice.CONSUMABLE_SETS[s.cset])[s.cons]
    if c and #s.consumables < practice.MAX_CONSUMABLES then s.consumables[#s.consumables+1] = c.key end
    changed()
  end
  G.FUNCS.practice_remove_cons = function(e)
    local s = get_state()
    s.consumables[#s.consumables] = nil
    changed()
  end

  G.FUNCS.practice_create = function(e)
    local ok, err = practice.create(practice.choices())
    if not ok then
      print('[SaveSlots] practice create refused: '..tostring(err))
      attention_text({text = 'Cannot start: '..tostring(err), scale = 0.5, hold = 2, major = G.ROOM_ATTACH,
        align = 'tm', offset = {x = 0, y = 0.15}, colour = G.C.WHITE, silent = true})
    end
  end
end

function practice.install()
  if installed then return end
  installed = true
  install_funcs()

  local orig_start_run = Game.start_run
  Game.start_run = function(self, args, ...)
    local ret = {orig_start_run(self, args, ...)}
    if pending and not in_sim() then
      local seed = G.GAME and G.GAME.pseudorandom and G.GAME.pseudorandom.seed
      if pending.applied or (args and args.savetext) or seed ~= pending.seed then
        -- Another run started before the practice run was stored: drop it.
        pending = nil
        last = {err = 'practice run replaced before its autosave'}
      else
        pending.applied = true
        apply(pending.choices)
      end
    end
    return unpack(ret)
  end

  local orig_save_run = save_run
  save_run = function(...)
    local ret = {orig_save_run(...)}
    local ok, err = pcall(maybe_store)
    if not ok then print('[SaveSlots] practice store failed: '..tostring(err)) end
    return unpack(ret)
  end
end

return practice
