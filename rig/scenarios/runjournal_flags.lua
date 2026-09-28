-- RunJournal run flags (T-370): the record and its index entry say which runs are
-- seeded, Finder, challenge (daily and endless: tests/test_runjournal_flags.lua),
-- in four real runs started the way a player starts them. Each is played to its
-- first round_end (Small selected, its target forced to 1), where the record is
-- first written; before that, at blind select, the live record has no `seeded`.
--   1. ctx.start_run with seed RJFLAGS1 (stake 1). After round_end the record and
--      its index entry have seeded = true, no Finder/daily/challenge/endless.
--      -> "check: seeded run flagged"
--   2. From that run's shop: pause menu, Seed Finder, Play on the pinned hit
--      FCHAIN91662 (finder_route's filter and seed, given through ui.set_results:
--      no scan). The Finder's Play clears `seeded` after start_run returns, while
--      bh-core's run_start (subscribed here) still sees it true. The record has
--      seeded = false, origin.filter_name, and its entry finder = true.
--      -> "check: finder run unseeded"
--   3. From that run's shop: G.FUNCS.start_challenge_run on vanilla's first
--      challenge (The Omelette; the rig profile has the Challenges tab locked). The
--      record and its entry have its challenge id, seeded = false.
--      -> "check: challenge run flagged"
--   4. From that run's shop: pause menu, New Run, the New Run tab's Play (no seed; every
--      toggle on the tab reads off). Every flag of the record and its entry is false or
--      nil, origin is empty.
--      -> "check: plain run clean"
-- Loaders: runs under vanilla's rig (rig/smoke.sh) and real lovely with or without
-- Steamodded (rig/lovely-rig.sh --smods). Only the driving differs, and by the buttons
-- found, never by loader: Steamodded's New Run tab is its paged run select, where Play
-- is the nav bar's next button pressed through the Deck and Stake pages.
-- Speed: vsync off, GAMESPEED 64, extra Game:update passes. Screenshots: finder_hit,
-- challenge, new_run.
local recorder = require('runjournal.recorder')
local ui = require('seedfinder.ui')

local SEED = 'RJFLAGS1'
-- Pinned offline by finder_chain, as finder_route uses it.
local FSEED = 'FCHAIN91662'
local F = {name = 'Flags chain', deck = 'b_red', stake = 1, mode = 'all', clauses = {
  {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
  {kind = 'soul_in_pack', ante = 1, pack = 'arcana'},
}}
local S = {ids = {}}

local function turbo()
  for _ = 1, 4 do G:update(1/20) end
end

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function entry(run_id)
  for _, e in ipairs(recorder.list()) do
    if e.run_id == run_id then return e end
  end
end

local function known(run_id)
  for _, id in pairs(S.ids) do if id == run_id then return true end end
  return false
end

local function flags(t)
  return string.format('seeded %s challenge %s endless %s finder %s daily %s', tostring(t.seeded),
    tostring(t.challenge), tostring(t.endless), tostring(t.finder), tostring(t.daily))
end

local function click(label, button, id, wait)
  return {name = label, timeout = 10, run = function(ctx)
    if wait and not wait() then return false end
    if G.CONTROLLER.locks.frame then return false end
    return ctx.click(button, id)
  end}
end

-- Blind select of a new run that is_it() accepts: note its record, which has no
-- `seeded` yet (never set at run_start).
local function new_run(label, is_it, check)
  return {name = label..' blind select', timeout = 30, run = function(ctx)
    turbo()
    local r = recorder.current()
    if not (G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select
      and G.GAME.round_resets.ante == 1 and r and not known(r.run_id) and is_it())
      or ctx.step_time() < 1 then return false end
    ctx.assert(r.seed == G.GAME.pseudorandom.seed, label..': the live record is for '..tostring(r.seed))
    ctx.assert(r.seeded == nil, label..': seeded recorded at run_start: '..tostring(r.seeded))
    S.ids[label] = r.run_id
    ctx.log(string.format('%s run %s: G.GAME.seeded %s, challenge %s, run_start saw seeded %s', label, r.run_id,
      tostring(G.GAME.seeded), tostring(G.GAME.challenge), tostring(S.seen_seeded)))
    if check then check(ctx, r) end
    return true
  end}
end

local function select_small()
  return {name = 'select Small', timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.BLIND_SELECT or not G.blind_select or ctx.step_time() < 0.3 then return false end
    local box = G.blind_select_opts and G.blind_select_opts.small
    local btn = box and box:get_UIE_by_ID('select_blind_button')
    if G.GAME.blind_on_deck ~= 'Small' or not (btn and btn.config.button == 'select_blind') then return false end
    G.FUNCS.select_blind(btn)
    return true
  end}
end

local function play_win()
  return {name = 'play a hand (target 1)', timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or ctx.step_time() < 0.2
      or G.CONTROLLER.locks.frame then return false end
    G.GAME.blind.chips = 1
    G.GAME.blind.chip_text = number_format(1)
    for i = 1, #G.hand.cards do
      if #G.hand.highlighted >= math.min(5, G.hand.config.highlighted_limit or 5) then break end
      if not G.hand.cards[i].highlighted then G.hand:add_to_highlighted(G.hand.cards[i]) end
    end
    ctx.assert(#G.hand.highlighted > 0, 'no cards highlighted')
    G.FUNCS.play_cards_from_highlighted()
    return true
  end}
end

-- The round's end is on disk (round_end wrote the record): check(ctx, record, entry).
local function written(label, check)
  return {name = label..' written', timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.ROUND_EVAL or ctx.step_time() < 0.3 then return false end
    local id = S.ids[label]
    local r = recorder.read(id)
    if not (r and r.final_round and r.final_round >= 1) then return false end
    local e = entry(id)
    ctx.assert(e, label..': no index entry for '..id)
    ctx.log(label..' record: '..flags(r)..' origin '..tostring(r.origin and r.origin.filter_name)
      ..'/'..tostring(r.origin and r.origin.kind))
    ctx.log(label..' entry:  '..flags(e))
    check(ctx, r, e)
    return true
  end}
end

local function cash_out()
  return {name = 'cash out', timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.ROUND_EVAL or ctx.step_time() < 0.2 then return false end
    return ctx.click('cash_out')
  end}
end

-- The shop is up and settled (leaving before its delayed event lands crashes it,
-- game.lua:3090); the next run starts from here.
local function in_shop()
  return {name = 'shop', timeout = 30, run = function(ctx)
    turbo()
    return G.STATE == G.STATES.SHOP and G.shop and ctx.step_time() > 0.3
      and G.shop_booster and #G.shop_booster.cards == 2 and not G.CONTROLLER.locks.frame
  end}
end

local function pause()
  return {name = 'pause menu', timeout = 10, run = function(ctx)
    if G.OVERLAY_MENU or G.CONTROLLER.locks.frame then return false end
    return ctx.click('options')
  end}
end

local function round(label, check)
  return {select_small(), play_win(), written(label, check), cash_out(), in_shop()}
end

-- The New Run tab's Play, found by what it is. Vanilla's is start_setup_run. Steamodded
-- replaces the tab with its paged run select (tools/smods-*/src/utils/run_select.lua,
-- G.UIDEF.run_select_galdur): the nav bar's next button (id next_selection) turns the
-- pages (Deck, then Stake) and is Play on the last one, where its func
-- (run_select_can_change_page) sets its button to run_select_start_run.
local function setup_play(ctx)
  return ctx.find_button('start_setup_run') or ctx.find_button('run_select_start_run', 'next_selection')
    or ctx.find_button('run_select_change_page', 'next_selection')
end

-- The toggles in the overlay (nested UIBoxes included) that read on, by the ref their
-- button flips (G.FUNCS.toggle_button), and how many toggles there are. The seed toggle
-- is the New Run tab's only one: G.run_setup_seed in vanilla, the nav bar's enable_seed
-- in Steamodded's.
local function toggles_on()
  local on, seen, n = {}, {}, 0
  local function walk(e)
    if type(e) ~= 'table' then return end
    local c = e.config or {}
    local ref = c.button == 'toggle_button' and c.ref_table
    if type(ref) == 'table' and type(ref.ref_table) == 'table' then
      n = n + 1
      if ref.ref_table[ref.ref_value] then on[#on + 1] = tostring(ref.label or ref.ref_value) end
    end
    local obj = c.object
    if type(obj) == 'table' and obj.UIRoot and not seen[obj] then seen[obj] = true; walk(obj.UIRoot) end
    for _, child in pairs(e.children or {}) do walk(child) end
  end
  if G.OVERLAY_MENU then walk(G.OVERLAY_MENU.UIRoot) end
  return on, n
end

-- Presses Play; on a paged run select, the next button first, a page per press, each
-- after the page before has settled (its func renames the button on the next update).
local function press_play()
  return {name = 'play', timeout = 10, run = function(ctx)
    if G.CONTROLLER.locks.frame then return false end
    if ctx.click('start_setup_run') or ctx.click('run_select_start_run', 'next_selection') then return true end
    local now = love.timer.getTime()
    if S.paged and now - S.paged < 0.3 then return false end
    if ctx.click('run_select_change_page', 'next_selection') then
      S.paged = now
      ctx.log('run select: next page')
    end
    return false
  end}
end

local steps = {
  {name = 'speed up', run = function()
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    SaveSlots.settings.auto_checkpoints = false
    require('bhcore.events').on('run_start', function() S.seen_seeded = G.GAME.seeded end)
    return true
  end},

  -- 1. A seeded run.
  {name = 'start '..SEED, run = function(ctx)
    ctx.start_run{seed = SEED, stake = 1}
    return true
  end},
  new_run('seeded', function() return G.GAME.pseudorandom.seed == SEED end, function(ctx)
    ctx.assert(G.GAME.seeded == true, 'a run started with a seed is not seeded')
  end),
}

local function add(list) for _, s in ipairs(list) do steps[#steps + 1] = s end end

add(round('seeded', function(ctx, r, e)
  ctx.assert(r.seeded == true, 'record seeded '..tostring(r.seeded))
  ctx.assert(e.seeded == true, 'entry seeded '..tostring(e.seeded))
  ctx.assert(e.finder == false and e.daily == false and e.challenge == nil and e.endless == false,
    'seeded entry: '..flags(e))
  ctx.assert(recorder.current().seeded == true, 'live record')
  ctx.log('check: seeded run flagged')
end))

-- 2. The Finder's Play on the pinned hit, from the pause menu.
add({
  {name = 'pinned hit', run = function(ctx)
    ctx.assert(ui.set_results(F, {FSEED}))
    ctx.assert(ui.search().found[1] == FSEED and not ui.search().running, 'the pinned hit is not the result')
    return true
  end},
  pause(),
  click('open finder', 'seedfinder_open', nil, function() return G.OVERLAY_MENU end),
  {name = 'hit row', timeout = 10, run = function(ctx)
    if not (ui.is_open() and uie('seedfinder_play_1')) or ctx.step_time() < 1 then return false end
    ctx.shot('finder_hit')
    return true
  end},
  -- Play in a step of its own: the shot above is drawn at the end of its frame.
  click('play the hit', 'seedfinder_play', 'seedfinder_play_1'),
  new_run('finder', function() return G.GAME.pseudorandom.seed == FSEED end, function(ctx, r)
    ctx.assert(not G.GAME.seeded, 'the Finder\'s Play started a seeded run')
    ctx.assert(S.seen_seeded == true, 'run_start did not see seeded = true: the trap this checks is gone')
    ctx.assert(r.origin and r.origin.filter_name == F.name, 'origin '..tostring(r.origin and r.origin.filter_name))
  end),
})
add(round('finder', function(ctx, r, e)
  ctx.assert(r.seeded == false, 'record seeded '..tostring(r.seeded))
  ctx.assert(e.seeded == false and e.finder == true and e.daily == false and e.challenge == nil
    and e.endless == false, 'finder entry: '..flags(e))
  ctx.log('check: finder run unseeded')
end))

-- 3. A vanilla challenge.
add({
  {name = 'start challenge', run = function(ctx)
    S.challenge = G.CHALLENGES[1] and G.CHALLENGES[1].id
    ctx.assert(type(S.challenge) == 'string', 'no vanilla challenge 1')
    G.FUNCS.start_challenge_run({config = {id = 1}})
    return true
  end},
  new_run('challenge', function() return G.GAME.challenge == S.challenge end, function(ctx, r)
    ctx.assert(r.challenge == S.challenge, 'live record challenge '..tostring(r.challenge))
  end),
  {name = 'challenge shot', timeout = 10, run = function(ctx)
    turbo()
    if ctx.step_time() < 1 then return false end
    ctx.shot('challenge')
    return true
  end},
})
add(round('challenge', function(ctx, r, e)
  ctx.assert(r.challenge == S.challenge and e.challenge == S.challenge,
    'challenge: record '..tostring(r.challenge)..', entry '..tostring(e.challenge))
  ctx.assert(r.seeded == false and e.seeded == false and e.finder == false and e.daily == false
    and e.endless == false, 'challenge entry: '..flags(e))
  ctx.log('check: challenge run flagged')
end))

-- 4. A plain run from the Play screen, no seed.
add({
  pause(),
  click('new run', 'setup_run', nil, function() return G.OVERLAY_MENU end),
  {name = 'new run tab', timeout = 10, run = function(ctx)
    if not (setup_play(ctx) and G.SETTINGS.current_setup == 'New Run')
      or ctx.step_time() < 1 then return false end
    ctx.assert(not G.run_setup_seed, 'the seed toggle is on')
    local on, n = toggles_on()
    ctx.log(n..' toggle(s) on the New Run tab, '..#on..' on')
    ctx.assert(n > 0, 'no seed toggle on the New Run tab')
    ctx.assert(#on == 0, 'a toggle on the New Run tab is on: '..table.concat(on, ', '))
    ctx.shot('new_run')
    return true
  end},
  press_play(),
  new_run('plain', function() return not G.GAME.challenge end, function(ctx)
    ctx.assert(not G.GAME.seeded, 'the Play screen started a seeded run')
  end),
})
add(round('plain', function(ctx, r, e)
  ctx.assert(r.seeded == false and r.challenge == nil and r.endless == false, 'plain record: '..flags(r))
  ctx.assert(next(r.origin) == nil, 'plain record has an origin')
  ctx.assert(e.seeded == false and e.challenge == nil and e.endless == false and e.finder == false
    and e.daily == false, 'plain entry: '..flags(e))
  ctx.log('check: plain run clean')
end))

add({
  {name = 'four records', run = function(ctx)
    local n = 0
    for _, e in ipairs(recorder.list()) do if known(e.run_id) then n = n + 1 end end
    ctx.assert(n == 4, n..' of the four runs in the index')
    return true
  end},
})

return steps
