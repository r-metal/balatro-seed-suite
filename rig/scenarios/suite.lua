-- Suite coexistence (T-130): every mod loaded at once (SaveSlots, SeedOracle,
-- RunJournal, SeedFinder on bh-core), driven through the player's buttons.
--   1. Main-menu Options: saveslots_open, runjournal_open and seedfinder_open each
--      appear exactly once; seedoracle_open is absent (the Oracle is in-run only,
--      docs/contracts-0.2.md). Settings and Back stay on screen.
--   2. A seeded run to its first blind select (autosaved), one Save Slots slot
--      saved so the Save Slots overlay has a preview to draw. The pause Options
--      hold all four suite buttons exactly once, on screen.
--      -> "check: every suite button once, menu and pause"
--   3. With no overlay up, snapshot #G.I.CARDAREA, #G.I.CARD and STR_PACK(G.GAME).
--      Then 3 rounds of: Save Slots, the practice composer (from Save Slots), Run
--      Journal, Seed Finder, Seed Oracle, each opened from the pause menu with its
--      button and left with its own Back button, Options closed after. The three
--      values must be unchanged. -> "check: no leaks across suite overlays"
--   4. Back to the main menu, Play: tabs New Run, Continue, Saves, Find, Challenges,
--      each once and in that order. Challenges (unlocked in the rig's profile) opens:
--      its New Challenge button, and the challenge list behind it. Continue restarts
--      the saved run at its seed, ante and dollars (vanilla's first-Continue Joker
--      unlock card is dismissed). -> "check: play tabs intact"
-- Screenshots: options_menu, pause_menu, overlay_<name> (first round of each),
-- play_screen, challenges_tab, challenge_list, continued.
local store = require('saveslots.store')
local checkpoint = require('saveslots.checkpoint')
local journal_ui = require('runjournal.ui')
local finder_ui = require('seedfinder.ui')
local oracle_ui = require('seedoracle.ui')

local SEED = 'SUITE130'
local ROUNDS = 3
local SUITE = {'saveslots_open', 'seedoracle_open', 'runjournal_open', 'seedfinder_open'}

local S = {}

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU ~= true and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function idle() return not G.CONTROLLER.locks.frame end

-- How many live elements of the overlay carry each button.
local function button_counts()
  local n, order = {}, {}
  local function walk(e)
    if type(e) ~= 'table' then return end
    if e.config and e.config.button then
      local b = e.config.button
      if not n[b] then order[#order + 1] = b end
      n[b] = (n[b] or 0) + 1
    end
    for _, c in ipairs(e.children or {}) do walk(c) end
    if e.config and e.config.object and e.config.object.UIRoot then walk(e.config.object.UIRoot) end
  end
  walk(G.OVERLAY_MENU and G.OVERLAY_MENU.UIRoot)
  return n, order
end

local function check_options(ctx, where, want)
  local n, order = button_counts()
  ctx.log(where..' options: '..table.concat(order, ', '))
  for _, b in ipairs(SUITE) do
    ctx.assert((n[b] or 0) == want[b], string.format('%s: %s appears %d times, expected %d', where, b, n[b] or 0, want[b]))
  end
  ctx.assert(n.settings == 1, where..': Settings appears '..tostring(n.settings)..' times')
  local first, back = ctx.find_button('settings'), uie('overlay_menu_back_button')
  ctx.assert(back, where..': no Back button')
  ctx.assert(first.T.y >= 0 and back.T.y + back.T.h <= G.ROOM.T.h,
    string.format('%s: Settings or Back is off screen (y %.2f..%.2f, room h %.2f)', where, first.T.y, back.T.y + back.T.h, G.ROOM.T.h))
end

-- save.jkr holds this run, with the dollars set before the baseline.
local function on_disk()
  local raw = get_compressed(G.SETTINGS.profile..'/save.jkr')
  local t = raw and STR_UNPACK(raw)
  local g = t and t.GAME
  return g and g.pseudorandom and g.pseudorandom.seed == SEED and g.dollars == S.dollars
end

local function at_blind_select()
  return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
    and G.GAME.pseudorandom and G.GAME.pseudorandom.seed == SEED
    and not G.CONTROLLER.locks.load and not G.OVERLAY_MENU
end

local function live()
  return {areas = #G.I.CARDAREA, cards = #G.I.CARD, game = STR_PACK(G.GAME)}
end

-- The Options overlay (menu or pause) is up: it is the one holding Settings.
local function options_up()
  return G.OVERLAY_MENU ~= nil and G.OVERLAY_MENU ~= true and (button_counts().settings or 0) > 0
end

-- Each suite overlay: the buttons to reach it from the pause menu, in order, and
-- how to tell each level is up.
local function saveslots_up() return uie('saveslots_list') ~= nil end
local OVERLAYS = {
  {name = 'saveslots', path = {{'saveslots_open', saveslots_up}}},
  {name = 'practice', path = {{'saveslots_open', saveslots_up},
    {'saveslots_practice', function() return uie('practice_create') ~= nil end}}},
  {name = 'runjournal', path = {{'runjournal_open', journal_ui.is_open}}},
  {name = 'seedfinder', path = {{'seedfinder_open', finder_ui.is_open}}},
  {name = 'seedoracle', path = {{'seedoracle_open', oracle_ui.is_open}}},
}

local steps = {}
local function add(step) steps[#steps + 1] = step end

-- 1. Main-menu Options.
add{name = 'open options', run = function(ctx)
  if G.OVERLAY_MENU or not idle() then return false end
  return ctx.click('options')
end}
add{name = 'main-menu options', timeout = 5, run = function(ctx)
  if not options_up() or ctx.step_time() < 1 then return false end
  check_options(ctx, 'main menu', {saveslots_open = 1, seedoracle_open = 0, runjournal_open = 1, seedfinder_open = 1})
  ctx.shot('options_menu')
  return true
end}
add{name = 'close options', run = function(ctx)
  if not idle() then return false end
  return ctx.click('exit_overlay_menu')
end}

-- 2. A run, a slot, the pause Options.
add{name = 'start run', run = function(ctx)
  if G.OVERLAY_MENU then return false end
  ctx.start_run{seed = SEED}
  return true
end}
add{name = 'first autosave', timeout = 30, run = function(ctx)
  return at_blind_select() and checkpoint.get() ~= nil and ctx.step_time() > 1
end}
add{name = 'save a slot', run = function(ctx)
  -- Distinct dollars, saved to save.jkr, so Continue is provably this run.
  G.GAME.dollars = 57
  save_run()
  G.FILE_HANDLER.force = true
  S.slot = store.save(checkpoint.get(), 'Suite')
  ctx.assert(S.slot, 'store.save failed')
  S.dollars, S.ante = G.GAME.dollars, G.GAME.round_resets.ante
  return ctx.click('options')
end}
add{name = 'pause options', timeout = 5, run = function(ctx)
  if not options_up() or ctx.step_time() < 1 then return false end
  check_options(ctx, 'pause menu', {saveslots_open = 1, seedoracle_open = 1, runjournal_open = 1, seedfinder_open = 1})
  ctx.log('check: every suite button once, menu and pause')
  ctx.shot('pause_menu')
  return true
end}
add{name = 'close pause', run = function(ctx)
  if not idle() then return false end
  return ctx.click('exit_overlay_menu')
end}

-- 3. Open and close every suite overlay ROUNDS times.
add{name = 'baseline', timeout = 5, run = function(ctx)
  if not at_blind_select() or ctx.step_time() < 1 then return false end
  S.before = live()
  ctx.log(string.format('before: %d card areas, %d cards, G.GAME %d bytes', S.before.areas, S.before.cards, #S.before.game))
  return true
end}

local function back(ctx)
  local b = uie('overlay_menu_back_button')
  if not b or not idle() then return false end
  G.FUNCS[b.config.button](b)
  return true
end

for round = 1, ROUNDS do
  for _, o in ipairs(OVERLAYS) do
    local tag = o.name..' #'..round
    add{name = tag..': pause', run = function(ctx)
      if not at_blind_select() or not idle() or ctx.step_time() < 0.1 then return false end
      return ctx.click('options')
    end}
    local up = options_up
    for _, level in ipairs(o.path) do
      local button, prev = level[1], up
      add{name = tag..': '..button, timeout = 5, run = function(ctx)
        if not prev() or not idle() or ctx.step_time() < 0.1 then return false end
        return ctx.click(button)
      end}
      up = level[2]
    end
    local top = up
    add{name = tag..': up', timeout = 10, run = function(ctx)
      if not top() or not idle() or ctx.step_time() < (round == 1 and 1 or 0.2) then return false end
      if round == 1 then ctx.shot('overlay_'..o.name) end
      return true
    end}
    for i = #o.path, 1, -1 do
      local below = i > 1 and o.path[i - 1][2] or options_up
      add{name = tag..': back '..i, timeout = 5, run = back}
      add{name = tag..': below '..i, timeout = 5, run = function(ctx)
        return below() and idle() and ctx.step_time() > 0.1
      end}
    end
    add{name = tag..': close pause', run = function(ctx)
      if not idle() then return false end
      return ctx.click('exit_overlay_menu')
    end}
  end
end

add{name = 'no leaks', timeout = 5, run = function(ctx)
  if not at_blind_select() or ctx.step_time() < 1 then return false end
  local after = live()
  ctx.log(string.format('after %d rounds x %d overlays: %d card areas, %d cards, G.GAME %d bytes',
    ROUNDS, #OVERLAYS, after.areas, after.cards, #after.game))
  ctx.assert(after.areas == S.before.areas, 'G.I.CARDAREA '..S.before.areas..' -> '..after.areas)
  ctx.assert(after.cards == S.before.cards, 'G.I.CARD '..S.before.cards..' -> '..after.cards)
  ctx.assert(after.game == S.before.game, 'STR_PACK(G.GAME) changed across the suite overlays')
  ctx.log('check: no leaks across suite overlays')
  return true
end}

-- 4. The Play screen.
add{name = 'autosave on disk', timeout = 10, run = function(ctx)
  if not on_disk() then return false end
  G.FUNCS.go_to_menu()
  return true
end}
add{name = 'main menu', timeout = 20, run = function(ctx)
  return G.STAGE == G.STAGES.MAIN_MENU and G.MAIN_MENU_UI ~= nil and not G.OVERLAY_MENU and ctx.step_time() > 1.5
end}
add{name = 'open play', run = function(ctx)
  if not idle() then return false end
  -- A fresh profile has Challenges locked (the tab shows only the unlock hint);
  -- unlock them in this isolated profile so the tab and its list are exercised.
  G.PROFILES[G.SETTINGS.profile].challenges_unlocked = #G.CHALLENGES
  return ctx.click('setup_run')
end}

local TABS = {'New Run', 'Continue', 'Saves', 'Find', 'Challenges'}
add{name = 'play tabs', timeout = 5, run = function(ctx)
  if not uie('tab_but_Challenges') or ctx.step_time() < 1 then return false end
  local labels = {localize('b_new_run'), localize('b_continue'), 'Saves', 'Find', localize('b_challenges')}
  local n = button_counts()
  ctx.assert(n.change_tab == #labels, 'Play screen has '..tostring(n.change_tab)..' tabs, expected '..#labels)
  local xs = {}
  for i, label in ipairs(labels) do
    local b = uie('tab_but_'..label)
    ctx.assert(b, 'Play screen: no '..TABS[i]..' tab')
    xs[i] = b.T.x
  end
  for i = 2, #xs do ctx.assert(xs[i] > xs[i - 1], 'Play screen tabs out of order at '..TABS[i]) end
  ctx.log('play tabs: '..table.concat(TABS, ', '))
  ctx.shot('play_screen')
  return true
end}
-- A shot is taken at the end of its frame, so each click gets a frame of its own.
-- Tabs get a real click (UIElement:click), so the chosen marker moves like a player's.
local function click_tab(label)
  local b = idle() and uie('tab_but_'..label)
  if not b then return false end
  b:click()
  return true
end
add{name = 'open challenges', run = function(ctx) return click_tab(localize('b_challenges')) end}
add{name = 'challenges tab', timeout = 5, run = function(ctx)
  if not ctx.find_button('challenge_list') or ctx.step_time() < 0.8 then return false end
  ctx.shot('challenges_tab')
  return true
end}
add{name = 'open challenge list', run = function(ctx)
  return idle() and ctx.click('challenge_list')
end}
add{name = 'challenge list', timeout = 5, run = function(ctx)
  if not uie('challenge_list') or ctx.step_time() < 1 then return false end
  ctx.shot('challenge_list')
  return true
end}
add{name = 'challenge list back', timeout = 5, run = back}
add{name = 'play again', timeout = 5, run = function(ctx)
  if ctx.step_time() < 0.5 then return false end
  return click_tab(localize('b_continue'))
end}
add{name = 'continue', timeout = 5, run = function(ctx)
  if G.SETTINGS.current_setup ~= 'Continue' or not idle() or ctx.step_time() < 0.5 then return false end
  ctx.assert(G.SAVED_GAME and G.SAVED_GAME.GAME.pseudorandom.seed == SEED and G.SAVED_GAME.GAME.dollars == S.dollars,
    'Continue does not hold the '..SEED..' run')
  return ctx.click('start_setup_run')
end}
add{name = 'continued', timeout = 20, run = function(ctx)
  -- Vanilla: the first Continue on a profile unlocks a Joker ("Continue a saved run
  -- from the main menu") and shows its unlock card over the run; dismiss it.
  if ctx.find_button('continue_unlock') then
    if idle() and ctx.step_time() > 0.5 and ctx.click('continue_unlock') then S.unlock = true end
    return false
  end
  if not at_blind_select() or ctx.step_time() < 1 then return false end
  ctx.assert(G.GAME.round_resets.ante == S.ante and G.GAME.dollars == S.dollars,
    string.format('Continue gave ante %s $%s, expected ante %s $%s', G.GAME.round_resets.ante, G.GAME.dollars, S.ante, S.dollars))
  ctx.log(string.format('continued %s at ante %d, $%d%s', SEED, S.ante, S.dollars,
    S.unlock and ' (vanilla unlock card dismissed)' or ''))
  ctx.log('check: play tabs intact')
  ctx.shot('continued')
  return true
end}

return steps
