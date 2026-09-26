-- sim.card differential (T-105): bhcore.sim.card against vanilla create_card,
-- in the real game.
-- Each case: S = state.capture() of the live run; predict the case's cards with
-- card.create / card.shop_card inside sandbox.run(S); then make the same cards
-- with the real vanilla function (create_card, create_card_for_shop) on the
-- live run. Compare key, edition, stickers (and front/seal for playing cards),
-- then every G.GAME.pseudorandom entry against S.game.pseudorandom, and
-- used_jokers. Then the real cards are removed the vanilla way (Card:remove)
-- and the sim releases them (card.release); used_jokers must agree again.
-- A case holds several cards at once where vanilla does (a pack, a shop row),
-- so the in-pack used_jokers exclusion is exercised.
--
-- Areas: create_card only compares its area with G.shop_jokers and
-- G.pack_cards. The run sits at blind select, where those do not exist, so the
-- real calls get scratch CardAreas installed as G.shop_jokers / G.pack_cards
-- for the duration of the call (the 'other' area is a third scratch area; the
-- Soul uses G.jokers in vanilla, which is draw-identical and would also run
-- discovery). Vanilla Card:open's own draws around create_card (omen_globe,
-- stdset, standard_edition, stdseal/stdsealtype, card.lua:1731-1771) are made
-- through the vanilla primitives on each side; only the card creation differs.
--
-- Runs: White stake and Gold stake (eternal/perishable/rental stickers).
-- Per ante (1..ANTES, set on the live run for the step): shop rows through the
-- vanilla type roll (Illusion on some antes), Buffoon, Arcana (Omen Globe on
-- some antes), Celestial, Spectral and Standard pack contents, forced keys.
-- Then: Showman held (a real Showman in G.jokers, a stand-in in the sim),
-- the Soul's legendary, and antes chosen so that Soul / Black Hole rolls hit.
--   -> "check: sim.card matches vanilla for <N> draws"
--   -> "check: pseudorandom post-state identical"
local state = require('bhcore.sim.state')
local sandbox = require('bhcore.sim.sandbox')
local card = require('bhcore.sim.card')

local RUNS = {
  {seed = 'SIMCARD1', stake = 1, label = 'White'},
  {seed = 'SIMCARD8', stake = 8, label = 'Gold'},
}
local ANTES = 16

local total = {draws = 0, cases = 0, pr_checked = 0}
local seen = {soul = 0, black_hole = 0, eternal = 0, perishable = 0, rental = 0,
  edition = 0, seal = 0, showman_dups = 0, legendary = 0, forced = 0, resample = 0,
  shop_types = {}}

---------------------------------------------------------------------------
-- ops: what a case creates. Shared helpers use only vanilla primitives and
-- read G.GAME, which is S.game inside the sandbox and the live run outside.

local function omen_spectral()
  return G.GAME.used_vouchers.v_omen_globe and pseudorandom('omen_globe') > 0.8
end

local function std_type()
  return (pseudorandom(pseudoseed('stdset'..G.GAME.round_resets.ante)) > 0.6) and 'Enhanced' or 'Base'
end

local function std_after()
  local ante = G.GAME.round_resets.ante
  local edition = poll_edition('standard_edition'..ante, 2, true)
  local seal
  if pseudorandom(pseudoseed('stdseal'..ante)) > 1 - 0.02 * 10 then
    local t = pseudorandom(pseudoseed('stdsealtype'..ante))
    seal = t > 0.75 and 'Red' or t > 0.5 and 'Blue' or t > 0.25 and 'Gold' or 'Purple'
  end
  return edition, seal
end

local function edition_name(e)
  if not e then return 'none' end
  for _, k in ipairs{'negative', 'polychrome', 'holo', 'foil'} do if e[k] then return k end end
  return 'none'
end

-- Sim side of one op -> comparable record.
local function sim_op(op)
  local r
  if op.kind == 'shop' then
    r = card.shop_card()
  elseif op.kind == 'arcana' then
    if omen_spectral() then
      r = card.create{type = 'Spectral', area = 'pack', soulable = true, key_append = 'ar2'}
    else
      r = card.create{type = 'Tarot', area = 'pack', soulable = true, key_append = 'ar1'}
    end
  elseif op.kind == 'standard' then
    r = card.create{type = std_type(), area = 'pack', soulable = true, key_append = 'sta'}
    local e, s = std_after()
    r.edition, r.seal = e, s
  else
    r = card.create(op.args)
  end
  return {key = r.key, edition = edition_name(r.edition), eternal = r.stickers.eternal,
    perishable = r.stickers.perishable, rental = r.stickers.rental, front = r.front, seal = r.seal}
end

local scratch = {}
local P_CARD_KEY = {}

local function real_area(a)
  return a == 'shop' and scratch.shop or a == 'pack' and scratch.pack or scratch.other
end

-- Real side of one op: vanilla creates a Card on the live run.
local function real_op(op)
  local c
  if op.kind == 'shop' then
    c = create_card_for_shop(G.shop_jokers)
    c.opening = true -- create_shop_card_ui's queued event then leaves it alone
  elseif op.kind == 'arcana' then
    if omen_spectral() then
      c = create_card('Spectral', G.pack_cards, nil, nil, true, true, nil, 'ar2')
    else
      c = create_card('Tarot', G.pack_cards, nil, nil, true, true, nil, 'ar1')
    end
  elseif op.kind == 'standard' then
    c = create_card(std_type(), G.pack_cards, nil, nil, nil, true, nil, 'sta')
    local e, s = std_after()
    c:set_edition(e)
    if s then c:set_seal(s) end
  else
    local a = op.args
    c = create_card(a.type, real_area(a.area), a.legendary, a.rarity, true, a.soulable, a.forced_key, a.key_append)
  end
  local rec = {set = op.kind == 'shop' and c.ability.set or nil, key = c.config.center.key, edition = c.edition and c.edition.type or 'none',
    eternal = c.ability.eternal and true or false, perishable = c.ability.perishable and true or false,
    rental = c.ability.rental and true or false, seal = c.seal}
  if c.config.center.set == 'Default' or c.config.center.set == 'Enhanced' then
    rec.front = P_CARD_KEY[c.config.card]
  end
  return rec, c
end

local function fmt(r)
  return string.format('%s ed=%s e=%s p=%s r=%s front=%s seal=%s', tostring(r.key), r.edition,
    tostring(r.eternal), tostring(r.perishable), tostring(r.rental), tostring(r.front), tostring(r.seal))
end

local function same_rec(a, b)
  return a.key == b.key and a.edition == b.edition and a.eternal == b.eternal and
    a.perishable == b.perishable and a.rental == b.rental and a.front == b.front and a.seal == b.seal
end

local function diff_tables(live, sim, what)
  local bad = {}
  for k, v in pairs(live) do if sim[k] ~= v then bad[#bad + 1] = string.format('%s[%s] live %.17g sim %s', what, tostring(k), tonumber(v) or 0/0, tostring(sim[k])) end end
  for k, v in pairs(sim) do if live[k] == nil then bad[#bad + 1] = what..'['..tostring(k)..'] only in sim ('..tostring(v)..')' end end
  return bad
end

local function flags_eq(live, sim, what)
  local bad = {}
  for k, v in pairs(live) do if (sim[k] and true) ~= (v and true) then bad[#bad + 1] = what..'.'..k..' live '..tostring(v)..' sim '..tostring(sim[k]) end end
  for k, v in pairs(sim) do if live[k] == nil and v then bad[#bad + 1] = what..'.'..k..' only in sim' end end
  return bad
end

local function count_resamples(pr)
  local n = 0
  for k in pairs(pr) do if type(k) == 'string' and k:find('_resample', 1, true) then n = n + 1 end end
  return n
end

-- One case. c = {label, ops, showman = bool, vouchers = {v_x = true},
-- rates = {playing_card_rate = n, ...}}; vouchers and rates are set on the live
-- run for the case (as Magic Trick / Ghost Deck would) and put back after.
local function run_case(ctx, c)
  local live_vouchers, live_rates = {}, {}
  for v in pairs(c.vouchers or {}) do live_vouchers[v] = {G.GAME.used_vouchers[v]}; G.GAME.used_vouchers[v] = true end
  for k, v in pairs(c.rates or {}) do live_rates[k] = {G.GAME[k]}; G.GAME[k] = v end

  local S = state.capture()
  local before, sort_id = STR_PACK(G.GAME), G.sort_id
  local ok, sim = sandbox.run(S, function()
    if c.showman then G.jokers.cards[1] = {ability = {name = 'Showman'}} end
    local out = {}
    for i, op in ipairs(c.ops) do out[i] = sim_op(op) end
    return out
  end)
  ctx.assert(ok, c.label..': sim failed: '..tostring(sim))
  ctx.assert(STR_PACK(G.GAME) == before, c.label..': the sim changed the live G.GAME')
  ctx.assert(G.sort_id == sort_id, c.label..': the sim created a Card')

  -- real side, with scratch areas as the shop/pack areas
  local saved = {G.shop_jokers, G.pack_cards}
  G.shop_jokers, G.pack_cards = scratch.shop, scratch.pack
  local real, cards = {}, {}
  local rok, rerr = pcall(function()
    for i, op in ipairs(c.ops) do real[i], cards[i] = real_op(op) end
  end)
  G.shop_jokers, G.pack_cards = saved[1], saved[2]
  ctx.assert(rok, c.label..': real call failed: '..tostring(rerr))

  local bad = {}
  for i = 1, #c.ops do
    if not same_rec(real[i], sim[i]) then bad[#bad + 1] = string.format('#%d real %s | sim %s', i, fmt(real[i]), fmt(sim[i])) end
  end
  for _, b in ipairs(diff_tables(G.GAME.pseudorandom, S.game.pseudorandom, 'pseudorandom')) do bad[#bad + 1] = b end
  for _, b in ipairs(flags_eq(G.GAME.used_jokers, S.game.used_jokers, 'used_jokers(held)')) do bad[#bad + 1] = b end

  -- remove the real cards the vanilla way; the sim releases its keys
  for _, cd in ipairs(cards) do cd:remove() end
  local rel_ok, rel_err = sandbox.run(S, function()
    if c.showman then G.jokers.cards[1] = {ability = {name = 'Showman'}} end
    for _, r in ipairs(sim) do card.release(r.key) end
  end)
  ctx.assert(rel_ok, c.label..': release failed: '..tostring(rel_err))
  for _, b in ipairs(flags_eq(G.GAME.used_jokers, S.game.used_jokers, 'used_jokers(released)')) do bad[#bad + 1] = b end

  for v, old in pairs(live_vouchers) do G.GAME.used_vouchers[v] = old[1] end
  for k, old in pairs(live_rates) do G.GAME[k] = old[1] end

  if #bad > 0 then
    for i = 1, math.min(#bad, 20) do ctx.log('MISMATCH '..c.label..': '..bad[i]) end
    error(c.label..': '..#bad..' mismatches (first: '..bad[1]..')')
  end

  -- tallies
  local keys = {}
  for _, r in ipairs(real) do
    if r.key == 'c_soul' then seen.soul = seen.soul + 1 end
    if r.key == 'c_black_hole' then seen.black_hole = seen.black_hole + 1 end
    for _, s in ipairs{'eternal', 'perishable', 'rental'} do if r[s] then seen[s] = seen[s] + 1 end end
    if r.edition ~= 'none' then seen.edition = seen.edition + 1 end
    if r.seal then seen.seal = seen.seal + 1 end
    if r.set then seen.shop_types[r.set] = (seen.shop_types[r.set] or 0) + 1 end
    if c.showman and keys[r.key] then seen.showman_dups = seen.showman_dups + 1 end
    keys[r.key] = true
  end
  total.draws = total.draws + #c.ops
  total.cases = total.cases + 1
  total.pr_checked = total.pr_checked + 1
  return real
end

---------------------------------------------------------------------------
-- case builders

local function rep(n, op)
  local out = {}
  for i = 1, n do out[i] = op end
  return out
end

local function ante_cases(a, label)
  local L = label..' ante '..a
  local cases = {}
  -- shop rows: a fresh row of 2 and three rerolls of it (vanilla removes the
  -- row before regenerating, button_callbacks.lua:2855-2912)
  for r = 1, 4 do
    cases[#cases + 1] = {label = L..' shop row '..r, ops = rep(2, {kind = 'shop'}),
      vouchers = (a % 3 == 0) and {v_illusion = true} or nil,
      rates = (a % 2 == 1) and {playing_card_rate = 4, spectral_rate = 2} or nil}
  end
  cases[#cases + 1] = {label = L..' buffoon', ops = rep(4, {kind = 'create',
    args = {type = 'Joker', area = 'pack', soulable = true, key_append = 'buf'}})}
  cases[#cases + 1] = {label = L..' arcana', ops = rep(5, {kind = 'arcana'}),
    vouchers = (a % 2 == 0) and {v_omen_globe = true} or nil}
  cases[#cases + 1] = {label = L..' celestial', ops = rep(5, {kind = 'create',
    args = {type = 'Planet', area = 'pack', soulable = true, key_append = 'pl1'}})}
  cases[#cases + 1] = {label = L..' spectral', ops = rep(3, {kind = 'create',
    args = {type = 'Spectral', area = 'pack', soulable = true, key_append = 'spe'}})}
  cases[#cases + 1] = {label = L..' standard', ops = rep(5, {kind = 'standard'})}
  -- forced keys: Telescope's first Celestial card, then the rest of the pack
  local tele = {{kind = 'create', args = {type = 'Planet', area = 'pack', soulable = true,
    forced_key = (a % 2 == 0) and 'c_jupiter' or 'c_saturn', key_append = 'pl1'}}}
  for i = 2, 3 do tele[i] = {kind = 'create', args = {type = 'Planet', area = 'pack', soulable = true, key_append = 'pl1'}} end
  cases[#cases + 1] = {label = L..' telescope', ops = tele, forced = true}
  -- a forced Joker in the shop still takes the sticker and edition draws
  cases[#cases + 1] = {label = L..' forced joker', forced = true, ops = {{kind = 'create',
    args = {type = 'Joker', area = 'shop', forced_key = 'j_todo_list', key_append = 'sho'}}}}
  return cases
end

---------------------------------------------------------------------------

local function run_ready(seed)
  return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
    and G.GAME.pseudorandom and G.GAME.pseudorandom.seed == seed
    and G.GAME.round_resets.blind_tags and G.GAME.round_resets.blind_tags.Big ~= nil
end

local function with_ante(a, fn)
  local old = G.GAME.round_resets.ante
  G.GAME.round_resets.ante = a
  local ok, err = pcall(fn)
  G.GAME.round_resets.ante = old
  if not ok then error(err, 0) end
end

local function forced_count(cases)
  local n = 0
  for _, c in ipairs(cases) do if c.forced then n = n + 1 end end
  return n
end

-- Antes whose first draw of 'soul_<type><ante>' (or, for Spectral, the second
-- one, the Black Hole roll) is a hit. Found by running vanilla pseudorandom on
-- a copy of the live state; this only picks the inputs, the expected cards
-- still come from the real game.
local function soul_antes(want)
  local S = state.capture()
  local found = {Tarot = {}, Planet = {}, Spectral = {}, SpectralBH = {}}
  assert(sandbox.run(S, function()
    for a = 100, 60000 do
      local done = true
      for _, t in ipairs{'Tarot', 'Planet', 'Spectral'} do
        local k = 'soul_'..t..a
        local first = pseudorandom(k) > 0.997
        local list = found[t]
        if first and #list < want then list[#list + 1] = a end
        if t == 'Spectral' and not first and pseudorandom(k) > 0.997 and #found.SpectralBH < want then
          found.SpectralBH[#found.SpectralBH + 1] = a
        end
      end
      for _, l in pairs(found) do if #l < want then done = false end end
      if done then break end
    end
  end))
  return found
end

local steps = {}

for ri, R in ipairs(RUNS) do
  steps[#steps + 1] = {name = 'start '..R.label..' run', run = function(ctx)
    ctx.start_run{seed = R.seed, stake = R.stake}
    return true
  end}
  steps[#steps + 1] = {name = R.label..' run up', timeout = 20, run = function(ctx)
    if not (run_ready(R.seed) and ctx.step_time() > 1) then return false end
    ctx.assert(G.GAME.stake == R.stake, 'stake is '..tostring(G.GAME.stake))
    local m = G.GAME.modifiers
    if R.stake == 8 then
      ctx.assert(m.enable_eternals_in_shop and m.enable_perishables_in_shop and m.enable_rentals_in_shop,
        'Gold stake modifiers missing')
    else
      ctx.assert(not m.enable_eternals_in_shop, 'White stake has sticker modifiers')
    end
    if not scratch.shop then
      for k, v in pairs(G.P_CARDS) do P_CARD_KEY[v] = k end
      scratch.shop = CardArea(0, 0, 5 * G.CARD_W, G.CARD_H, {card_limit = 2, type = 'shop'})
      scratch.pack = CardArea(0, 0, 5 * G.CARD_W, G.CARD_H, {card_limit = 5, type = 'consumeable'})
      scratch.other = CardArea(0, 0, 5 * G.CARD_W, G.CARD_H, {card_limit = 5, type = 'joker'})
    end
    ctx.log(string.format('%s run: seed %s stake %d, joker_rate %s tarot %s planet %s playing %s spectral %s',
      R.label, R.seed, G.GAME.stake, tostring(G.GAME.joker_rate), tostring(G.GAME.tarot_rate),
      tostring(G.GAME.planet_rate), tostring(G.GAME.playing_card_rate), tostring(G.GAME.spectral_rate)))
    return true
  end}

  for a = 1, ANTES do
    steps[#steps + 1] = {name = R.label..' ante '..a, run = function(ctx)
      local cases = ante_cases(a, R.label)
      with_ante(a, function()
        for _, c in ipairs(cases) do run_case(ctx, c) end
      end)
      seen.forced = seen.forced + forced_count(cases)
      seen.resample = math.max(seen.resample, count_resamples(G.GAME.pseudorandom))
      return true
    end}
  end

  steps[#steps + 1] = {name = R.label..' showman held', run = function(ctx)
    local sm = create_card('Joker', G.jokers, nil, nil, nil, nil, 'j_ring_master')
    G.jokers:emplace(sm)
    ctx.assert(next(find_joker('Showman')), 'Showman not held')
    local ok, err = pcall(function()
      for a = 1, 4 do
        with_ante(a, function()
          run_case(ctx, {label = R.label..' showman tarot a'..a, showman = true, ops = rep(12,
            {kind = 'create', args = {type = 'Tarot', area = 'pack', soulable = true, key_append = 'ar1'}})})
          run_case(ctx, {label = R.label..' showman buffoon a'..a, showman = true, ops = rep(8,
            {kind = 'create', args = {type = 'Joker', area = 'pack', soulable = true, key_append = 'buf'}})})
          run_case(ctx, {label = R.label..' showman shop a'..a, showman = true, ops = rep(6, {kind = 'shop'})})
        end)
      end
    end)
    sm:remove()
    ctx.assert(ok, tostring(err))
    ctx.assert(not next(find_joker('Showman')), 'Showman still held')
    return true
  end}

  steps[#steps + 1] = {name = R.label..' soul legendary', run = function(ctx)
    for a = 1, 3 do
      with_ante(a, function()
        -- one Soul at a time (used and removed), and a held pair
        for _ = 1, 8 do
          run_case(ctx, {label = R.label..' legendary a'..a, ops = {{kind = 'create',
            args = {type = 'Joker', area = 'other', legendary = true, key_append = 'sou'}}}})
          seen.legendary = seen.legendary + 1
        end
        run_case(ctx, {label = R.label..' legendary pair a'..a, ops = rep(2, {kind = 'create',
          args = {type = 'Joker', area = 'other', legendary = true, key_append = 'sou'}})})
        seen.legendary = seen.legendary + 2
      end)
    end
    return true
  end}

  steps[#steps + 1] = {name = R.label..' soul and black hole hits', run = function(ctx)
    local found = soul_antes(2)
    ctx.log(string.format('%s soul antes: Tarot %s, Planet %s, Spectral %s, Spectral black hole %s', R.label,
      table.concat(found.Tarot, ','), table.concat(found.Planet, ','), table.concat(found.Spectral, ','),
      table.concat(found.SpectralBH, ',')))
    local plan = {
      {'Tarot', 'arcana', nil}, {'Planet', 'create', {type = 'Planet', area = 'pack', soulable = true, key_append = 'pl1'}},
      {'Spectral', 'create', {type = 'Spectral', area = 'pack', soulable = true, key_append = 'spe'}},
      {'SpectralBH', 'create', {type = 'Spectral', area = 'pack', soulable = true, key_append = 'spe'}},
    }
    local soul0, bh0 = seen.soul, seen.black_hole
    for _, p in ipairs(plan) do
      ctx.assert(#found[p[1]] > 0, 'no ante found for '..p[1])
      for _, a in ipairs(found[p[1]]) do
        with_ante(a, function()
          local op = p[2] == 'arcana' and {kind = 'arcana'} or {kind = 'create', args = p[3]}
          local n = p[1] == 'Tarot' and 5 or p[1] == 'Planet' and 5 or 4
          run_case(ctx, {label = R.label..' '..p[1]..' hit a'..a, ops = rep(n, op)})
          -- again with Showman: the Soul stays in the pool of rolls
          local sm = create_card('Joker', G.jokers, nil, nil, nil, nil, 'j_ring_master')
          G.jokers:emplace(sm)
          local ok, err = pcall(run_case, ctx, {label = R.label..' '..p[1]..' hit+showman a'..a, showman = true, ops = rep(n, op)})
          sm:remove()
          ctx.assert(ok, tostring(err))
        end)
      end
    end
    ctx.assert(seen.soul > soul0 and seen.black_hole > bh0, 'no Soul or Black Hole was created')
    return true
  end}
end

steps[#steps + 1] = {name = 'verdict', run = function(ctx)
  for _, a in pairs(scratch) do a:remove() end
  local types = {}
  for k, v in pairs(seen.shop_types) do types[#types + 1] = k..' '..v end
  table.sort(types)
  ctx.log('shop card types (real): '..table.concat(types, ', '))
  ctx.assert(seen.shop_types.Default and seen.shop_types.Enhanced and seen.shop_types.Spectral,
    'shop playing cards / spectrals not exercised')
  ctx.log(string.format('seen: soul %d, black hole %d, stickers e%d p%d r%d, editions %d, seals %d, showman duplicates %d, legendary %d, forced-key cases %d, resample streams %d',
    seen.soul, seen.black_hole, seen.eternal, seen.perishable, seen.rental, seen.edition, seen.seal,
    seen.showman_dups, seen.legendary, seen.forced, seen.resample))
  ctx.assert(seen.eternal > 0 and seen.perishable > 0 and seen.rental > 0, 'Gold stake stickers not exercised')
  ctx.assert(seen.showman_dups > 0, 'Showman duplicates not exercised')
  ctx.assert(seen.seal > 0 and seen.edition > 0, 'editions/seals not exercised')
  ctx.assert(total.draws >= 1200, 'only '..total.draws..' draws')
  ctx.log(string.format('check: sim.card matches vanilla for %d draws (%d cases)', total.draws, total.cases))
  ctx.log(string.format('check: pseudorandom post-state identical (%d cases, every entry compared exactly)', total.pr_checked))
  ctx.shot('after')
  return true
end}

return steps
