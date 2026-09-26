-- sim/state.lua and sim/sandbox.lua: the G.GAME swap, restores, nesting,
-- sim_depth, the all_unlocked flip, capture/copy/fresh.
-- Stubs the vanilla primitives they touch (Game.init_game_object, Back,
-- pseudohash, Object, P_CENTERS); the real thing runs in rig/scenarios/sim_sandbox.lua.
local H = ...

-- Stub class with Object's `is`, so STR_PACK turns instances into "MANUAL_REPLACE".
local function stub_object_class()
  Object = {}
  Object.__index = Object
  function Object:is(T)
    local mt = getmetatable(self)
    while mt do
      if mt == T then return true end
      mt = getmetatable(mt)
    end
    return false
  end
end

-- A full-precision double, like vanilla pseudohash output (not its formula).
local function fake_hash(s)
  local n = 0
  for i = 1, #s do n = (n * 31 + s:byte(i)) % 1000003 end
  return (n / 1000003) + 1 / 3 * 1e-7
end

local function world()
  stub_object_class()
  BHCore = {}
  pseudohash = fake_hash
  G.P_CENTERS = {
    j_joker = {key = 'j_joker', set = 'Joker', unlocked = true, discovered = true},
    j_locked = {key = 'j_locked', set = 'Joker', unlocked = false, discovered = false},
    e_foil = {key = 'e_foil', set = 'Edition', discovered = false}, -- no `unlocked` field
    b_red = {key = 'b_red', set = 'Back', name = 'Red Deck', config = {discards = 1}},
    b_zodiac = {key = 'b_zodiac', set = 'Back', name = 'Zodiac Deck', config = {vouchers = {'v_tarot_merchant'}}},
  }
  G.jokers = {cards = {{id = 1}}, config = {card_limit = 7}}
  G.consumeables = {cards = {}, config = {card_limit = 3}}
  G.playing_cards = {{config = {center = {key = 'm_glass'}}}}
  G.deck, G.hand, G.shop_jokers = nil, nil, nil
  G.shop_vouchers = {cards = {{config = {center = {key = 'v_grabber'}}}}, config = {card_limit = 1}}
  G.shop_booster = nil
  G.GAME = {live = true, dollars = 9, round_resets = {ante = 3},
    pseudorandom = {seed = 'LIVE', hashed_seed = fake_hash('LIVE'), Tag3 = 0.1234567890123},
    selected_back = setmetatable({name = 'Red Deck'}, Object), used_jokers = {j_joker = true}}
  G.E_MANAGER = {queued = 0}
  function G.E_MANAGER:add_event() self.queued = self.queued + 1 end

  Game = {}
  function Game.init_game_object(self)
    return {
      stake = 1, modifiers = {}, dollars = 0, base_reroll_cost = 5, used_vouchers = {},
      starting_params = {dollars = 4, discards = 3, hands = 4, reroll_cost = 5},
      round_resets = {ante = 1, hands = 1, discards = 1, reroll_cost = 1},
      current_round = {reroll_cost = 5}, pseudorandom = {}, bosses_used = {bl_hook = 0},
    }
  end
  -- Back: data effects on G.GAME plus a queued event, like vanilla's apply_to_run.
  Back = setmetatable({}, {__call = function(cls, center)
    return setmetatable({center = center}, {__index = cls})
  end})
  function Back:apply_to_run()
    local c = self.center.config
    if c.discards then G.GAME.starting_params.discards = G.GAME.starting_params.discards + c.discards end
    for _, v in ipairs(c.vouchers or {}) do
      G.GAME.used_vouchers[v] = true
      G.E_MANAGER:add_event({func = function() G.GAME.tarot_rate = 9.6 end})
    end
  end

  return require('bhcore.sim.state'), require('bhcore.sim.sandbox')
end

-- Structural equality. STR_PACK strings of two equal tables can differ: pairs()
-- order depends on each table's insertion history.
local function deep_eq(a, b)
  if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
  for k, v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- Asserts inside fn are caught by sandbox.run's pcall: surface them.
local function must(ok, err, ...)
  if not ok then error(err, 2) end
  return err, ...
end

local function flags()
  local out = {}
  for k, c in pairs(G.P_CENTERS) do out[k] = tostring(c.unlocked)..'/'..tostring(c.discovered) end
  return out
end

local function same_flags(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  return true
end

H.test('run swaps G.GAME and the areas, then restores them', function()
  local _, sandbox = world()
  local live, jokers, pc = G.GAME, G.jokers, G.playing_cards
  local S = {game = {sim = true}}
  local seen
  local ok, a, b = sandbox.run(S, function(x, y)
    seen = {game = G.GAME, jokers = G.jokers, pc = G.playing_cards}
    return x + y, 'two'
  end, 1, 2)
  H.eq(ok, true); H.eq(a, 3); H.eq(b, 'two')
  H.eq(seen.game, S.game, 'G.GAME is S.game inside')
  H.ok(seen.jokers ~= jokers and #seen.jokers.cards == 0, 'jokers stubbed and empty')
  H.ok(seen.pc ~= pc, 'playing_cards stubbed')
  H.eq(G.GAME, live); H.eq(G.jokers, jokers); H.eq(G.playing_cards, pc)
  H.eq(G.deck, nil, 'a live nil comes back as nil')
end)

H.test('stub areas keep the live card_limit, else a default', function()
  local _, sandbox = world()
  local got = {}
  must(sandbox.run({game = {}}, function()
    for _, n in ipairs{'jokers', 'consumeables', 'playing_cards', 'deck', 'hand',
        'shop_jokers', 'shop_vouchers', 'shop_booster'} do
      H.eq(#G[n].cards, 0, n..' cards empty')
      got[n] = G[n].config.card_limit
    end
    -- the enhancement gate iterates G.playing_cards as a list: it must see nothing
    local n = 0
    for _ in pairs(G.playing_cards) do n = n + 1 end
    H.eq(n, 0, 'pairs(G.playing_cards) is empty')
    H.eq(#G.playing_cards, 0)
    H.eq(#G.shop_vouchers.cards, 0, 'the live shop voucher is hidden from the voucher pool')
  end))
  H.eq(got.jokers, 7); H.eq(got.consumeables, 3); H.eq(got.shop_vouchers, 1)
  H.eq(got.hand, 8); H.eq(got.deck, 52); H.eq(got.shop_jokers, 2); H.eq(got.shop_booster, 2)
  H.eq(got.playing_cards, 52)
end)

H.test('an error in fn restores everything and returns false, err', function()
  local _, sandbox = world()
  local live, jokers, before = G.GAME, G.jokers, STR_PACK(G.GAME)
  local f0 = flags()
  local ok, err = sandbox.run({game = {}, all_unlocked = true}, function()
    G.GAME.pseudorandom = {x = 1}
    G.jokers = 'clobbered'
    error('boom')
  end)
  H.eq(ok, false); H.ok(tostring(err):find('boom'), 'error message kept: '..tostring(err))
  H.eq(G.GAME, live); H.eq(G.jokers, jokers); H.eq(STR_PACK(G.GAME), before)
  H.ok(same_flags(f0, flags()), 'unlock flags restored')
  H.eq(BHCore.sim_depth, 0)
end)

H.test('sim_depth counts nesting and returns to 0', function()
  local _, sandbox = world()
  local d1, d2
  must(sandbox.run({game = {}}, function()
    d1 = BHCore.sim_depth
    must(sandbox.run({game = {}}, function() d2 = BHCore.sim_depth end))
    H.eq(BHCore.sim_depth, 1, 'back to 1 after the inner call')
  end))
  H.eq(d1, 1); H.eq(d2, 2); H.eq(BHCore.sim_depth, 0)
end)

H.test('nested calls share the outer area swap and put the outer game back', function()
  local _, sandbox = world()
  local live_jokers = G.jokers
  local outer, inner = {game = {name = 'outer'}}, {game = {name = 'inner'}}
  must(sandbox.run(outer, function()
    local stub = G.jokers
    local ok = sandbox.run(inner, function()
      H.eq(G.GAME, inner.game, 'inner game')
      H.eq(G.jokers, stub, 'same stub as the outer call')
      error('inner fails')
    end)
    H.eq(ok, false)
    H.eq(G.GAME, outer.game, 'outer game back after the inner error')
    H.eq(G.jokers, stub, 'outer stub still in place after the inner error')
  end))
  H.eq(G.jokers, live_jokers)
end)

H.test('all_unlocked flips every center inside and restores exact values', function()
  local _, sandbox = world()
  local f0 = flags()
  local inside = {}
  must(sandbox.run({game = {}, all_unlocked = true}, function()
    for k, c in pairs(G.P_CENTERS) do inside[k] = c.unlocked == true and c.discovered == true end
  end))
  for k in pairs(G.P_CENTERS) do H.ok(inside[k], k..' unlocked and discovered inside') end
  H.ok(same_flags(f0, flags()), 'flags restored')
  H.eq(G.P_CENTERS.e_foil.unlocked, nil, 'a missing field stays missing')
  H.eq(G.P_CENTERS.j_locked.unlocked, false)
end)

H.test('all_unlocked = false leaves the profile flags alone; a nested flip is undone', function()
  local _, sandbox = world()
  must(sandbox.run({game = {}}, function()
    H.eq(G.P_CENTERS.j_locked.unlocked, false, 'no flip')
    must(sandbox.run({game = {}, all_unlocked = true}, function()
      H.eq(G.P_CENTERS.j_locked.unlocked, true, 'inner flip')
    end))
    H.eq(G.P_CENTERS.j_locked.unlocked, false, 'inner flip undone on return')
  end))
end)

H.test('capture is a deep copy of G.GAME with Objects replaced', function()
  local state = world()
  local S = state.capture()
  H.eq(S.all_unlocked, false)
  H.ok(S.game ~= G.GAME and S.game.pseudorandom ~= G.GAME.pseudorandom, 'new tables')
  H.eq(S.game.selected_back, 'MANUAL_REPLACE')
  S.game.dollars = 1000
  S.game.pseudorandom.Tag3 = 0.5
  S.game.used_jokers.j_new = true
  H.eq(G.GAME.dollars, 9); H.eq(G.GAME.pseudorandom.Tag3, 0.1234567890123)
  H.eq(G.GAME.used_jokers.j_new, nil)
end)

H.test('capture keeps full-precision numbers that STR_PACK rounds', function()
  local state = world()
  local packed = STR_UNPACK(STR_PACK(G.GAME)).pseudorandom.hashed_seed
  H.ok(packed ~= G.GAME.pseudorandom.hashed_seed, 'precondition: STR_PACK is lossy here')
  local S = state.capture()
  H.eq(S.game.pseudorandom.hashed_seed, G.GAME.pseudorandom.hashed_seed)
end)

H.test('copy is independent and exact', function()
  local state = world()
  local S = state.capture()
  S.all_unlocked = true
  local C = state.copy(S)
  H.eq(C.all_unlocked, true)
  H.ok(deep_eq(C.game, S.game), 'same content')
  H.eq(C.game.pseudorandom.hashed_seed, S.game.pseudorandom.hashed_seed, 'numbers exact')
  C.game.pseudorandom.Tag3 = 0.9
  C.game.round_resets.ante = 8
  H.eq(S.game.pseudorandom.Tag3, 0.1234567890123); H.eq(S.game.round_resets.ante, 3)
end)

H.test('advancing a sim state leaves the live pack byte-identical', function()
  local state, sandbox = world()
  local before = STR_PACK(G.GAME)
  local S = state.capture()
  local ok = sandbox.run(S, function()
    for i = 1, 50 do
      local k = 'Tag'..G.GAME.round_resets.ante
      G.GAME.pseudorandom[k] = (G.GAME.pseudorandom[k] * 1.7 + 0.1) % 1
      G.GAME.used_jokers['j_'..i] = true
    end
  end)
  H.eq(ok, true)
  H.eq(STR_PACK(G.GAME), before)
  H.ok(S.game.pseudorandom.Tag3 ~= G.GAME.pseudorandom.Tag3, 'the sim stream advanced')
end)

H.test('fresh builds a seeded run without touching the live one', function()
  local state = world()
  local live, before = G.GAME, STR_PACK(G.GAME)
  local S = state.fresh('ABCD1234')
  H.eq(G.GAME, live); H.eq(STR_PACK(G.GAME), before); H.eq(BHCore.sim_depth, 0)
  local g = S.game
  H.eq(S.all_unlocked, false)
  H.eq(g.pseudorandom.seed, 'ABCD1234'); H.eq(g.seeded, true)
  H.eq(g.pseudorandom.hashed_seed, fake_hash('ABCD1234'))
  H.eq(g.stake, 1); H.eq(g.modifiers.scaling, nil)
  H.eq(g.starting_params.discards, 4, 'Red Deck +1 discard applied')
  H.eq(g.round_resets.discards, 4); H.eq(g.round_resets.hands, 4); H.eq(g.dollars, 4)
  H.eq(g.selected_back, 'MANUAL_REPLACE'); H.eq(g.selected_back_key.key, 'b_red')
  H.ok(g.selected_back_key ~= G.P_CENTERS.b_red, 'deck center copied, not shared')
  H.eq(type(g.round_resets.blind_tags), 'table')
end)

H.test('fresh applies stake rules and drops the deck\'s events', function()
  local state = world()
  local S = state.fresh('SEED', {stake = 8, deck = 'b_zodiac', all_unlocked = true})
  local g = S.game
  H.eq(S.all_unlocked, true)
  H.eq(g.modifiers.no_blind_reward.Small, true); H.eq(g.modifiers.scaling, 3)
  H.eq(g.modifiers.enable_eternals_in_shop, true); H.eq(g.modifiers.enable_perishables_in_shop, true)
  H.eq(g.modifiers.enable_rentals_in_shop, true)
  H.eq(g.starting_params.discards, 2, 'stake 5 -1 discard')
  H.eq(g.used_vouchers.v_tarot_merchant, true, 'deck voucher recorded')
  H.eq(G.E_MANAGER.queued, 0, 'no event reached the live queue')
  H.eq(g.tarot_rate, nil, 'the dropped event never ran')
end)

H.test('fresh with an unknown deck errors and restores the live run', function()
  local state = world()
  local live, jokers = G.GAME, G.jokers
  local ok, err = pcall(state.fresh, 'SEED', {deck = 'b_nope'})
  H.eq(ok, false); H.ok(tostring(err):find('unknown deck'), tostring(err))
  H.eq(G.GAME, live); H.eq(G.jokers, jokers); H.eq(BHCore.sim_depth, 0)
end)

H.test('fresh inside a sandbox call nests cleanly', function()
  local state, sandbox = world()
  local outer = {game = {name = 'outer'}}
  local tags
  must(sandbox.run(outer, function()
    local S = state.fresh('NEST')
    H.eq(G.GAME, outer.game, 'outer game back after fresh')
    tags = S.game.pseudorandom.seed
  end))
  H.eq(tags, 'NEST'); H.eq(BHCore.sim_depth, 0)
end)

H.test('G.OVERLAY_MENU is nil inside the sandbox and restored after', function()
  world()
  local sandbox = require('bhcore.sim.sandbox')
  local marker = {overlay = true}
  G.OVERLAY_MENU = marker
  local inside
  local ok = sandbox.run({game = {pseudorandom = {}}}, function() inside = G.OVERLAY_MENU end)
  H.ok(ok, 'run ok')
  H.eq(inside, nil, 'overlay hidden from the sim')
  H.eq(G.OVERLAY_MENU, marker, 'overlay restored')
  sandbox.run({game = {pseudorandom = {}}}, function() error('boom') end)
  H.eq(G.OVERLAY_MENU, marker, 'overlay restored after an error')
  G.OVERLAY_MENU = nil
end)
