-- Auto-checkpoints (T-121): SaveSlots saves "Auto A<n>" at each new ante's blind
-- select, prunes per run and per run count, and a checkpoint rewinds the run.
--   1. Start seeded run AUTOCKP1 (stake 1) and save a player slot "Mine" from its
--      first snapshot (it must survive every prune below).
--   2. Play antes 1-3 with forced wins (each blind's chips set to 1, first five cards
--      played; no skips, buys or rerolls) up to ante 4's blind select. Exactly one
--      checkpoint per ante 1..4 under the run's run id, named "Auto A<n>" and holding
--      ante n. -> "check: one checkpoint per ante"
--   3. Rewind: load "Auto A2" with checkpoint.load_run (what the Load button calls).
--      The run is back at ante 2 with the same run id, and loading adds no
--      checkpoint. -> "check: rewind restores ante"
--   4. Call the save path (checkpoint.auto_save) for 10 antes' worth of snapshots:
--      the run keeps its newest 8, "Auto A3".."Auto A10". -> "check: pruned to 8"
--   5. Start runs AUTOCKP2..4, each checkpointing its ante 1: only the 3 newest run
--      ids keep checkpoints, and "Mine" is still there. -> "check: 3 runs kept"
-- Speed: vsync off, GAMESPEED 64, extra Game:update passes while playing (see
-- journal/2026-09-23-scripting-balatro-fast.md).
local store = require('saveslots.store')
local checkpoint = require('saveslots.checkpoint')

local SEED = 'AUTOCKP1'
local LAST_ANTE = 4 -- play antes 1-3, stop at ante 4's blind select
local S = {}

local function run_ready(seed)
  return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
    and G.GAME.pseudorandom and G.GAME.pseudorandom.seed == seed
    and not G.CONTROLLER.locks.load
end

-- This run id's checkpoints, newest first.
local function autos(rid)
  local out = {}
  for _, e in ipairs(store.list({kind = 'checkpoint'})) do
    if e.meta.run_id == rid then out[#out + 1] = e end
  end
  return out
end

local function find(list, name)
  for _, e in ipairs(list) do if e.name == name then return e end end
end

local function names(list)
  local t = {}
  for i, e in ipairs(list) do t[i] = e.name end
  return table.concat(t, ', ')
end

local function turbo()
  for _ = 1, 4 do G:update(1/20) end
end

local function select_button()
  local kind = G.GAME.blind_on_deck
  local box = G.blind_select_opts and kind and G.blind_select_opts[string.lower(kind)]
  local btn = box and box:get_UIE_by_ID('select_blind_button')
  if btn and btn.config.button == 'select_blind' then return btn end
end

-- Waits for a new run's ante-1 checkpoint. Returns it once there.
local function first_auto(seed)
  if not run_ready(seed) then return nil end
  local rid = checkpoint.run_id()
  if not (rid and rid:sub(1, #seed + 1) == seed..':') then return nil end
  return find(autos(rid), 'Auto A1'), rid
end

local steps = {
  {name = 'speed up', run = function()
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    return true
  end},
  {name = 'start '..SEED, run = function(ctx)
    ctx.assert(SaveSlots.settings.auto_checkpoints == true, 'auto_checkpoints not on by default')
    ctx.start_run{seed = SEED, stake = 1}
    return true
  end},
  {name = 'ante 1 checkpoint', timeout = 20, run = function(ctx)
    local a1, rid = first_auto(SEED)
    if not a1 then return false end
    S.rid = rid
    S.mine = store.save(checkpoint.get(), 'Mine')
    ctx.assert(S.mine, 'could not save the player slot')
    ctx.log('run id '..rid..'; player slot '..S.mine)
    ctx.shot('ante1_blind_select')
    return true
  end},
  {name = 'play antes 1-3', timeout = 90, run = function(ctx)
    turbo()
    S.play = S.play or {phase = 'select', t = 0}
    local p = S.play
    local now = love.timer.getTime()
    local waited = now - p.t
    local function go(phase) p.phase, p.t = phase, now end
    if p.phase == 'select' then
      if G.STATE ~= G.STATES.BLIND_SELECT or waited < 0.05 then return false end
      if G.GAME.round_resets.ante == LAST_ANTE then
        return find(autos(S.rid), 'Auto A'..LAST_ANTE) ~= nil
      end
      local btn = select_button()
      if not btn then return false end
      G.FUNCS.select_blind(btn)
      go('play')
    elseif p.phase == 'play' then
      if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or waited < 0.05
        or G.CONTROLLER.locks.frame then return false end
      G.GAME.blind.chips = 1
      G.GAME.blind.chip_text = number_format(1)
      for i = 1, #G.hand.cards do
        if #G.hand.highlighted >= math.min(5, G.hand.config.highlighted_limit or 5) then break end
        if not G.hand.cards[i].highlighted then G.hand:add_to_highlighted(G.hand.cards[i]) end
      end
      ctx.assert(#G.hand.highlighted > 0, 'no cards highlighted')
      G.FUNCS.play_cards_from_highlighted()
      go('cash_out')
    elseif p.phase == 'cash_out' then
      if G.STATE ~= G.STATES.ROUND_EVAL or waited < 0.05 then return false end
      if not ctx.click('cash_out') then return false end
      go('shop')
    elseif p.phase == 'shop' then
      -- Leaving before the shop's delayed event lands crashes it (game.lua:3090).
      if G.STATE ~= G.STATES.SHOP or not G.shop or waited < 0.05
        or not (G.shop_booster and #G.shop_booster.cards == 2) then return false end
      if not ctx.click('toggle_shop') then return false end
      go('select')
    end
    return false
  end},
  {name = 'one checkpoint per ante', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end -- a stray second save would land by now
    ctx.shot('ante4_blind_select')
    local list = autos(S.rid)
    ctx.log('checkpoints of '..S.rid..': '..names(list))
    ctx.assert(#list == LAST_ANTE, 'expected '..LAST_ANTE..' checkpoints, got '..#list..': '..names(list))
    for a = 1, LAST_ANTE do
      local n = 0
      for _, e in ipairs(list) do
        if e.name == 'Auto A'..a then
          n = n + 1
          local run = store.read(e.id)
          ctx.assert(run and run.GAME.round_resets.ante == a, e.name..' does not hold ante '..a)
          ctx.assert(run.STATE == G.STATES.BLIND_SELECT, e.name..' is not a blind-select snapshot')
          ctx.assert(run.GAME.pseudorandom.seed == SEED, e.name..' is another seed')
          S['A'..a] = e.id
        end
      end
      ctx.assert(n == 1, n..' checkpoints named Auto A'..a)
    end
    ctx.log('check: one checkpoint per ante')
    return true
  end},
  {name = 'rewind to Auto A2', run = function(ctx)
    ctx.assert(checkpoint.load_run(store.read(S.A2)), 'load_run failed')
    return true
  end},
  {name = 'rewound', timeout = 20, run = function(ctx)
    if not run_ready(SEED) or G.GAME.round_resets.ante ~= 2 then return false end
    S.at = S.at or love.timer.getTime()
    if love.timer.getTime() - S.at < 1 then return false end -- let its autosave run
    ctx.shot('rewound_ante2')
    ctx.assert(G.GAME.round_resets.ante == 2, 'ante is '..tostring(G.GAME.round_resets.ante))
    local want = store.read(S.A2).GAME.round
    ctx.assert(G.GAME.round == want, 'round is '..tostring(G.GAME.round)..', Auto A2 has '..tostring(want))
    ctx.assert(checkpoint.run_id() == S.rid, 'run id changed: '..tostring(checkpoint.run_id()))
    local list = autos(S.rid)
    ctx.assert(#list == LAST_ANTE, 'loading made a checkpoint: '..names(list))
    ctx.log('check: rewind restores ante')
    return true
  end},
  {name = 'prune per run', run = function(ctx)
    local base = checkpoint.get()
    ctx.assert(base, 'no snapshot')
    for a = 1, 10 do
      local run = STR_UNPACK(STR_PACK(base))
      run.GAME.round_resets.ante = a
      local id, err = checkpoint.auto_save(run)
      ctx.assert(id, 'auto_save failed: '..tostring(err))
    end
    local list = autos(S.rid)
    ctx.log('after 10 more: '..names(list))
    ctx.assert(#list == 8, 'expected 8, got '..#list)
    for i, e in ipairs(list) do
      ctx.assert(e.name == 'Auto A'..(11 - i), 'newest 8 not kept: '..names(list))
    end
    ctx.assert(store.read(S.mine), 'player slot evicted')
    ctx.log('check: pruned to 8')
    return true
  end},
}

for r = 2, 4 do
  local seed = 'AUTOCKP'..r
  steps[#steps + 1] = {name = 'start '..seed, run = function(ctx)
    ctx.start_run{seed = seed, stake = 1}
    return true
  end}
  steps[#steps + 1] = {name = seed..' checkpoint', timeout = 20, run = function(ctx)
    local a1, rid = first_auto(seed)
    if not a1 then return false end
    S.rids = S.rids or {S.rid}
    S.rids[#S.rids + 1] = rid
    return true
  end}
end

steps[#steps + 1] = {name = '3 runs kept', run = function(ctx)
  local by, n = {}, 0
  for _, e in ipairs(store.list({kind = 'checkpoint'})) do
    local rid = e.meta.run_id
    if not by[rid] then n = n + 1; by[rid] = 0 end
    by[rid] = by[rid] + 1
  end
  ctx.log('checkpoint runs: '..n..'; first run has '..tostring(by[S.rid] or 0))
  ctx.assert(n == 3, 'expected 3 runs with checkpoints, got '..n)
  ctx.assert(by[S.rid] == nil, 'the oldest run kept checkpoints')
  for r = 2, 4 do ctx.assert(by[S.rids[r]] == 1, 'run '..r..' lost its checkpoint') end
  ctx.assert(store.read(S.mine), 'player slot evicted')
  local saves = store.list({kind = 'save'})
  ctx.assert(#saves == 1 and saves[1].name == 'Mine', 'player saves changed')
  ctx.log('check: 3 runs kept')
  return true
end}

return steps
