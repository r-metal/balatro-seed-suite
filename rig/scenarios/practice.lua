-- Practice composer (T-122): compose a run in the composer overlay, start it, and get
-- a `kind = 'practice'` slot that loads back as exactly that run.
--   1. Auto-checkpoints off (slot counts matter). Blueprint and Blue Deck are locked
--      on the rig's fresh profile, so this throwaway profile gets them unlocked.
--   2. Main menu -> Save Slots -> "New practice". Through the composer's own cycles and
--      buttons: Blue Deck, stake 2, ante 3, $50, jokers Blueprint, Mime, Baron (the
--      joker search: letter cycle, then name cycle, then Add), 1 Tarot (The Empress),
--      Pair at level 3. Start practice run.
--   3. The slot appears at the run's first blind-select autosave: exactly one practice
--      slot, `kind = 'practice'`, meta.practice = the choices, and the live run already
--      matches. -> "check: practice slot created"
--   4. Start an unrelated run, then Load the practice slot through the Save Slots
--      overlay: deck, stake, ante, dollars, joker keys in order, the Tarot and the
--      Pair level all match. -> "check: practice run matches composer"
-- Voucher (T-122b): the composer draws the practice seed with generate_starting_seed;
-- the scenario wraps it for that one call and, before the run starts, predicts the
-- ante-3 voucher with predict.voucher(state.fresh(seed), 3). The live run, the stored
-- slot and the loaded run all show that voucher, not ante 1's.
-- -> "check: practice voucher matches ante"
-- Screenshots: saveslots_menu, composer_default, composer_filled, practice_run,
-- practice_slot, practice_loaded.
local store = require('saveslots.store')
local practice = require('saveslots.practice')
local state = require('bhcore.sim.state')
local predict = require('bhcore.sim.predict')

local WANT = {
  deck = 'b_blue', stake = 2, ante = 3, dollars = 50,
  jokers = {'j_blueprint', 'j_mime', 'j_baron'},
  consumables = {'c_empress'},
  hand = 'Pair', level = 3,
}
local OTHER_SEED = 'PLAINRUN'
local S = {}

local function name_of(set, key) return localize({type = 'name_text', set = set, key = key}) end

-- The option_cycle arrow of the cycle whose callback is `cb` (disabled arrows included).
local function find_arrow(cb, dir)
  local found
  local function walk(n)
    if found or type(n) ~= 'table' then return end
    local c = n.config
    if c and type(c.ref_table) == 'table' and c.ref_table.opt_callback == cb and c.ref_value == dir then
      found = n
      return
    end
    for _, ch in ipairs(n.children or {}) do walk(ch) end
  end
  walk(G.OVERLAY_MENU and G.OVERLAY_MENU.UIRoot)
  return found
end

-- Clicks the cycle's right arrow until it shows `want` (every click rebuilds the composer).
local function cycle_to(ctx, cb, want)
  for _ = 1, 300 do
    local a = find_arrow(cb, 'r')
    ctx.assert(a, 'no cycle '..cb)
    local rt = a.config.ref_table
    if rt.options[rt.current_option] == want then return end
    ctx.assert(a.config.button == 'option_cycle', cb..' is disabled and shows '..tostring(rt.options[rt.current_option]))
    G.FUNCS.option_cycle(a)
  end
  error(cb..' never showed '..tostring(want))
end

local function add_joker_by_search(ctx, key)
  local name = name_of('Joker', key)
  cycle_to(ctx, 'practice_letter', name:sub(1, 1):upper())
  cycle_to(ctx, 'practice_joker', name)
  ctx.assert(ctx.click('practice_add_joker'), 'no Add button for jokers')
end

local function keys_of(area)
  local t = {}
  for i, c in ipairs(area and area.cards or {}) do t[i] = c.config.center.key end
  return table.concat(t, ',')
end

-- The live run against WANT. Returns nil when it matches, else what differs.
local function mismatch()
  local g = G.GAME
  local diffs = {}
  local function want(ok, what) if not ok then diffs[#diffs+1] = what end end
  want(g.selected_back and g.selected_back.name == G.P_CENTERS[WANT.deck].name,
    'deck '..tostring(g.selected_back and g.selected_back.name))
  want(g.stake == WANT.stake, 'stake '..tostring(g.stake))
  want(g.round_resets.ante == WANT.ante, 'ante '..tostring(g.round_resets.ante))
  want(g.dollars == WANT.dollars, 'dollars '..tostring(g.dollars))
  want(keys_of(G.jokers) == table.concat(WANT.jokers, ','), 'jokers '..keys_of(G.jokers))
  want(keys_of(G.consumeables) == table.concat(WANT.consumables, ','), 'consumables '..keys_of(G.consumeables))
  want(g.hands[WANT.hand].level == WANT.level, WANT.hand..' level '..tostring(g.hands[WANT.hand].level))
  return diffs[1] and table.concat(diffs, '; ') or nil
end

-- The run's shop voucher against the prediction made before the run.
local function voucher_mismatch(game, where)
  local v = game.current_round and game.current_round.voucher
  if v ~= S.voucher then return where..' voucher '..tostring(v)..' ~= predicted '..tostring(S.voucher) end
end

local function at_blind_select(seed)
  return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
    and G.GAME.pseudorandom and G.GAME.pseudorandom.seed == seed and not G.CONTROLLER.locks.load
end

return {
  {name = 'setup', run = function(ctx)
    SaveSlots.settings.auto_checkpoints = false
    -- Fixture: the rig's fresh (throwaway) profile has Blueprint and Blue Deck locked,
    -- and the composer only offers unlocked ones.
    G.P_CENTERS.j_blueprint.unlocked = true
    G.P_CENTERS.b_blue.unlocked = true
    return true
  end},
  {name = 'open Save Slots', run = function(ctx)
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'Save Slots up', timeout = 5, run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    ctx.assert(ctx.find_button('saveslots_practice'), 'no New practice button')
    ctx.shot('saveslots_menu')
    return true
  end},
  {name = 'open composer', run = function(ctx)
    return ctx.click('saveslots_practice')
  end},
  {name = 'composer defaults', timeout = 5, run = function(ctx)
    if not ctx.find_button('practice_create') or ctx.step_time() < 1 then return false end
    ctx.shot('composer_default')
    local c = practice.choices()
    ctx.assert(c.ante == 1 and #c.jokers == 0 and #c.consumables == 0 and #c.hands == 3,
      'unexpected defaults')
    local names = {}
    for i, h in ipairs(c.hands) do names[i] = h.hand end
    ctx.log('composer defaults: deck '..c.deck..', hands '..table.concat(names, ', '))
    return true
  end},
  {name = 'compose', run = function(ctx)
    cycle_to(ctx, 'practice_deck', name_of('Back', WANT.deck))
    cycle_to(ctx, 'practice_stake', name_of('Stake', G.P_CENTER_POOLS.Stake[WANT.stake].key))
    cycle_to(ctx, 'practice_ante', tostring(WANT.ante))
    cycle_to(ctx, 'practice_money', localize('$')..WANT.dollars)
    for _, k in ipairs(WANT.jokers) do add_joker_by_search(ctx, k) end
    cycle_to(ctx, 'practice_cset', localize('k_tarot'))
    cycle_to(ctx, 'practice_cons', name_of('Tarot', WANT.consumables[1]))
    ctx.assert(ctx.click('practice_add_cons'), 'no Add button for consumables')
    local slot
    for i, h in ipairs(practice.choices().hands) do if h.hand == WANT.hand then slot = i end end
    ctx.assert(slot, WANT.hand..' is not one of the composer hands')
    cycle_to(ctx, 'practice_hand_'..slot, 'Level '..WANT.level)
    local c = practice.choices()
    ctx.assert(c.deck == WANT.deck and c.stake == WANT.stake and c.ante == WANT.ante and c.dollars == WANT.dollars,
      'composer run choices wrong')
    ctx.assert(table.concat(c.jokers, ',') == table.concat(WANT.jokers, ','), 'composer jokers: '..table.concat(c.jokers, ','))
    ctx.assert(table.concat(c.consumables, ',') == table.concat(WANT.consumables, ','), 'composer consumables wrong')
    return true
  end},
  {name = 'composer filled', timeout = 5, run = function(ctx)
    if ctx.step_time() < 1 then return false end
    ctx.shot('composer_filled')
    return true
  end},
  {name = 'start practice run', run = function(ctx)
    -- Predict from the seed the composer is about to use, before its run exists.
    local orig = generate_starting_seed
    generate_starting_seed = function(...)
      generate_starting_seed = orig
      orig(...)
      -- Fixed seed whose ante-1 and ante-3 vouchers differ (v_seed_money vs
      -- v_crystal_ball at Blue/stake 2), so the voucher check below can fail.
      local seed = 'CKC39ZKM'
      local opts = {deck = WANT.deck, stake = WANT.stake}
      S.voucher = predict.voucher(state.fresh(seed, opts), WANT.ante)
      S.voucher1 = predict.voucher(state.fresh(seed, opts), 1)
      S.predicted_seed = seed
      return seed
    end
    local ok = ctx.click('practice_create')
    generate_starting_seed = orig
    ctx.assert(ok, 'no Start button')
    ctx.assert(S.voucher, 'the composer did not draw its seed with generate_starting_seed')
    ctx.assert(S.voucher1 ~= S.voucher, 'fixed seed no longer discriminates ante-1 vs ante-3 vouchers')
    return true
  end},
  {name = 'practice slot created', timeout = 30, run = function(ctx)
    local last = practice.last()
    ctx.assert(last and not last.err, 'practice create failed: '..tostring(last and last.err))
    if not last.id then return false end
    S.id = last.id
    S.seed = G.GAME.pseudorandom.seed
    ctx.assert(S.seed == S.predicted_seed, 'run seed '..S.seed..' is not the predicted '..S.predicted_seed)
    local list = store.list({kind = 'practice'})
    ctx.assert(#list == 1 and list[1].id == S.id, 'expected one practice slot, got '..#list)
    ctx.assert(#store.list() == 1, 'other slots were made: '..#store.list())
    local e = list[1]
    ctx.assert(e.meta.kind == 'practice', 'kind is '..tostring(e.meta.kind))
    local p = e.meta.practice
    ctx.assert(type(p) == 'table' and p.deck == WANT.deck and p.stake == WANT.stake and p.ante == WANT.ante
      and p.dollars == WANT.dollars and table.concat(p.jokers, ',') == table.concat(WANT.jokers, ','),
      'meta.practice does not hold the choices')
    local run = store.read(S.id)
    ctx.assert(run and run.STATE == G.STATES.BLIND_SELECT, 'slot is not a blind-select snapshot')
    ctx.assert(run.GAME.pseudorandom.seed == S.seed and run.GAME.seeded, 'slot is not the seeded practice run')
    ctx.log('practice slot '..S.id..' "'..e.name..'" seed '..S.seed..' ante '..tostring(e.summary.ante)
      ..' $'..tostring(e.summary.dollars)..' jokers '..tostring(e.summary.jokers))
    ctx.log('check: practice slot created')
    local vd = voucher_mismatch(run.GAME, 'slot')
    ctx.assert(not vd, vd)
    return true
  end},
  {name = 'practice run live', timeout = 10, run = function(ctx)
    if not at_blind_select(S.seed) or ctx.step_time() < 1.5 then return false end
    local diff = mismatch()
    ctx.assert(not diff, 'live practice run differs: '..tostring(diff))
    local vd = voucher_mismatch(G.GAME, 'live')
    ctx.assert(not vd, vd)
    ctx.shot('practice_run')
    return true
  end},
  {name = 'start '..OTHER_SEED, run = function(ctx)
    ctx.start_run{seed = OTHER_SEED, stake = 1}
    return true
  end},
  {name = OTHER_SEED..' up', timeout = 20, run = function(ctx)
    if not at_blind_select(OTHER_SEED) or ctx.step_time() < 1.5 then return false end
    ctx.assert(mismatch(), 'the other run already matches')
    G.FUNCS.saveslots_open()
    return true
  end},
  {name = 'select practice slot', timeout = 5, run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.assert(ctx.click('saveslots_select'), 'no slot row')
    return true
  end},
  {name = 'practice slot shown', timeout = 5, run = function(ctx)
    if ctx.step_time() < 1 then return false end
    ctx.shot('practice_slot')
    return true
  end},
  {name = 'load practice slot', run = function(ctx)
    ctx.assert(ctx.click('saveslots_load'), 'no Load button')
    return true
  end},
  {name = 'practice run loaded', timeout = 20, run = function(ctx)
    if not at_blind_select(S.seed) or ctx.step_time() < 1.5 then return false end
    local diff = mismatch()
    ctx.assert(not diff, 'loaded run differs from the composer: '..tostring(diff))
    ctx.log('loaded: '..G.GAME.selected_back.name..', stake '..G.GAME.stake..', ante '..G.GAME.round_resets.ante
      ..', $'..G.GAME.dollars..', jokers '..keys_of(G.jokers)..', consumables '..keys_of(G.consumeables)
      ..', '..WANT.hand..' level '..G.GAME.hands[WANT.hand].level)
    ctx.shot('practice_loaded')
    ctx.log('check: practice run matches composer')
    local vd = voucher_mismatch(G.GAME, 'loaded')
    ctx.assert(not vd, vd)
    ctx.log('practice voucher: ante '..WANT.ante..' '..S.voucher..' (predicted before the run; ante 1 was '
      ..S.voucher1..(S.voucher1 == S.voucher and ', same key for this seed' or '')..')')
    ctx.log('check: practice voucher matches ante')
    return true
  end},
}
