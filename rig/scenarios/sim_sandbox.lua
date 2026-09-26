-- Sim sandbox (T-102): bhcore.sim.state + bhcore.sim.sandbox against the real game.
--   1. In a live seeded run: pack G.GAME, run 500 sandboxed rounds of
--      get_next_tag_key / get_new_boss / get_pack('shop_pack') / poll_edition
--      against state.capture(), then check the live pack is byte-identical, the
--      sim streams advanced, and no Card, event or area leaked.
--      -> "check: live G.GAME untouched"
--   2. For 5 seeds: state.fresh(seed), then in the sandbox draw what
--      Game:start_run draws before the player sees anything (boss, voucher,
--      Small tag, Big tag, game.lua:2177-2180). Then start a real run with that
--      seed and compare against the run's own blind_tags (and boss, voucher).
--      The prediction is made before the real run exists.
--      -> "check: fresh(seed) tags match real run"
--   3. An error inside a nested all_unlocked sandbox.run: the live G.GAME,
--      areas, unlock flags and sim_depth are all back.
--      -> "check: restored after error"
local state = require('bhcore.sim.state')
local sandbox = require('bhcore.sim.sandbox')

local LIVE_SEED = 'SBXLIVE1'
local SEEDS = {'7LB2WVPK', 'SIMTAGS1', 'ZQ9Y8XW6', 'HNM4KD2P', 'BALATRO3'}
local AREAS = {'jokers', 'consumeables', 'playing_cards', 'deck', 'hand',
  'shop_jokers', 'shop_vouchers', 'shop_booster'}

local function queued_events()
  local n = 0
  for _, q in pairs(G.E_MANAGER.queues) do n = n + #q end
  return n
end

local function unlock_flags()
  local out = {}
  for k, c in pairs(G.P_CENTERS) do out[k] = tostring(c.unlocked)..'/'..tostring(c.discovered) end
  return out
end

local function run_ready(seed)
  return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
    and G.GAME.pseudorandom and G.GAME.pseudorandom.seed == seed
    and G.GAME.round_resets.blind_tags and G.GAME.round_resets.blind_tags.Big ~= nil
end

-- What start_run draws, in its order, for a fresh state. Returns a table.
local function predict_start(seed)
  local S = state.fresh(seed, {stake = 1, deck = 'b_red'})
  local ok, res = sandbox.run(S, function()
    local boss = get_new_boss()
    local voucher = get_next_voucher_key()
    local small = get_next_tag_key()
    local big = get_next_tag_key()
    return {boss = boss, voucher = voucher, small = small, big = big}
  end)
  assert(ok, res)
  return res
end

local steps = {
  {name = 'start live run', run = function(ctx)
    ctx.start_run{seed = LIVE_SEED, stake = 1}
    return true
  end},
  {name = 'live run up', timeout = 20, run = function(ctx)
    return run_ready(LIVE_SEED) and ctx.step_time() > 1
  end},

  {name = 'sandboxed calls leave the live run untouched', run = function(ctx)
    local live = G.GAME
    local before = STR_PACK(G.GAME)
    local ids = {G.sort_id, G.ID}
    local events = queued_events()
    local areas = {}
    for _, n in ipairs(AREAS) do areas[n] = G[n] end

    local S = state.capture()
    ctx.assert(S.game.pseudorandom.hashed_seed == live.pseudorandom.hashed_seed,
      'capture lost hashed_seed precision')
    local packed_hs = STR_UNPACK(STR_PACK(live)).pseudorandom.hashed_seed
    ctx.log(string.format('capture: hashed_seed live %.17g, STR_PACK round trip %.17g (%s)',
      live.pseudorandom.hashed_seed, packed_hs,
      packed_hs == live.pseudorandom.hashed_seed and 'same' or 'differs; capture keeps the live value'))
    -- Diagnostic only: does the %.14g rounding of a plain STR_PACK copy change draws?
    local raw = {game = STR_UNPACK(STR_PACK(live)), all_unlocked = false}
    local function draws(T)
      local out = {}
      assert(sandbox.run(T, function()
        for j = 1, 200 do out[j] = pseudorandom('sbx_probe', 1, 1000000) end
      end))
      return out
    end
    local a, b = draws(state.copy(S)), draws(raw)
    local diff = 0
    for j = 1, #a do if a[j] ~= b[j] then diff = diff + 1 end end
    ctx.log('capture: '..diff..' of 200 probe draws differ between an exact capture and a plain STR_PACK copy')

    local pr0 = {}
    for k, v in pairs(S.game.pseudorandom) do pr0[k] = v end

    local seen = {}
    local ok, err = sandbox.run(S, function()
      ctx.assert(BHCore.sim_depth == 1, 'sim_depth inside is '..tostring(BHCore.sim_depth))
      ctx.assert(G.GAME == S.game and G.jokers ~= areas.jokers, 'swap not in place')
      for _ = 1, 500 do
        seen[get_next_tag_key()] = true
        seen[get_new_boss()] = true
        local p = get_pack('shop_pack')
        seen[p and p.key or 'nil'] = true
        poll_edition('edi'..G.GAME.round_resets.ante)
      end
    end)
    ctx.assert(ok, 'sandbox.run failed: '..tostring(err))

    ctx.assert(G.GAME == live, 'G.GAME not restored')
    ctx.assert(STR_PACK(G.GAME) == before, 'STR_PACK(G.GAME) changed')
    ctx.assert(G.sort_id == ids[1] and G.ID == ids[2], 'a Card or Node was created')
    ctx.assert(queued_events() == events, 'an event was queued')
    for _, n in ipairs(AREAS) do ctx.assert(G[n] == areas[n], 'G.'..n..' not restored') end
    ctx.assert(BHCore.sim_depth == 0, 'sim_depth is '..tostring(BHCore.sim_depth))

    local advanced = 0
    for k, v in pairs(S.game.pseudorandom) do if pr0[k] ~= v then advanced = advanced + 1 end end
    for _, k in ipairs{'Tag1', 'boss', 'shop_pack1', 'edi1'} do
      ctx.assert(S.game.pseudorandom[k] ~= nil and S.game.pseudorandom[k] ~= pr0[k], 'stream '..k..' did not advance')
    end
    local kinds = 0
    for _ in pairs(seen) do kinds = kinds + 1 end
    ctx.log(string.format('check: live G.GAME untouched (%d bytes packed; 4 x 500 sandboxed calls; %d streams advanced; %d distinct results)',
      #before, advanced, kinds))
    return true
  end},
}

-- Step 2: one predict-then-start pair per seed.
local results = {}
for i, seed in ipairs(SEEDS) do
  steps[#steps + 1] = {name = 'predict and start '..seed, run = function(ctx)
    local before = STR_PACK(G.GAME)
    results[i] = {predicted = predict_start(seed)}
    ctx.assert(STR_PACK(G.GAME) == before, 'fresh() touched the live run')
    ctx.start_run{seed = seed, stake = 1}
    return true
  end}
  steps[#steps + 1] = {name = 'compare '..seed, timeout = 20, run = function(ctx)
    if not (run_ready(seed) and ctx.step_time() > 0.5) then return false end
    local p, rr = results[i].predicted, G.GAME.round_resets
    local real = {small = rr.blind_tags.Small, big = rr.blind_tags.Big,
      boss = rr.blind_choices.Boss, voucher = G.GAME.current_round.voucher}
    ctx.log(string.format('%s: predicted %s/%s boss %s voucher %s; real %s/%s boss %s voucher %s',
      seed, p.small, p.big, p.boss, p.voucher, real.small, real.big, real.boss, real.voucher))
    ctx.assert(G.GAME.stake == 1 and G.GAME.selected_back.name == 'Red Deck', 'real run is not stake 1 Red Deck')
    ctx.assert(p.small == real.small and p.big == real.big, seed..': tags differ')
    ctx.assert(p.boss == real.boss, seed..': boss differs')
    ctx.assert(p.voucher == real.voucher, seed..': voucher differs')
    if i == #SEEDS then
      ctx.log('check: fresh(seed) tags match real run ('..#SEEDS..' seeds; boss and voucher match too)')
    end
    return true
  end}
end

steps[#steps + 1] = {name = 'error inside sandbox.run restores', run = function(ctx)
  local live, before = G.GAME, STR_PACK(G.GAME)
  local flags = unlock_flags()
  local areas = {}
  for _, n in ipairs(AREAS) do areas[n] = G[n] end
  local S = state.capture()
  local locked_inside
  local ok, err = sandbox.run(S, function()
    get_next_tag_key()
    local inner = state.copy(S)
    inner.all_unlocked = true
    return sandbox.run(inner, function()
      locked_inside = 0
      for _, c in pairs(G.P_CENTERS) do if c.unlocked ~= true or c.discovered ~= true then locked_inside = locked_inside + 1 end end
      G.jokers = 'clobbered'
      G.GAME.pseudorandom = {}
      error('sim_sandbox: deliberate failure')
    end)
  end)
  -- the outer call returns the inner call's results: true, false, err
  ctx.assert(ok == true and err == false, 'expected the inner error to be returned')
  local ok2, err2 = sandbox.run(S, function() error('sim_sandbox: outer failure') end)
  ctx.assert(ok2 == false and tostring(err2):find('outer failure'), 'outer error not returned')

  ctx.assert(locked_inside == 0, 'all_unlocked left '..tostring(locked_inside)..' centers locked')
  ctx.assert(G.GAME == live, 'G.GAME not restored')
  ctx.assert(STR_PACK(G.GAME) == before, 'STR_PACK(G.GAME) changed')
  for _, n in ipairs(AREAS) do ctx.assert(G[n] == areas[n], 'G.'..n..' not restored') end
  local now = unlock_flags()
  for k, v in pairs(flags) do ctx.assert(now[k] == v, k..' unlock flags not restored') end
  ctx.assert(BHCore.sim_depth == 0, 'sim_depth is '..tostring(BHCore.sim_depth))
  ctx.log('check: restored after error')
  ctx.shot('after')
  return true
end}

return steps
