-- Round trip (phase 3 acceptance): save a run with state through the pause
-- menu, go to the main menu, quick-load it from the Play screen's Saves tab,
-- and check the loaded run and save.jkr match what was saved.
--   1. Start run R (fixed seed). At blind select add $40, one ante and two
--      jokers (j_joker, then j_egg: not alphabetical, so order is checked)
--      through vanilla functions. Select the blind, play one card against a
--      lowered blind, cash out: entering the shop runs vanilla's own
--      save_run(), which is the snapshot saved (state SHOP).
--   2. Pause (HUD Options) -> Save Slots -> name "RT" -> Save current run.
--   3. Record ante, dollars, joker keys and seed from checkpoint.get() and
--      check the slot on disk holds the same.
--   4. Pause -> Main menu. Then a decoy run D (other seed, ante 1, other
--      dollars, no jokers) is autosaved and left, so save.jkr and Continue
--      hold D: loading Continue instead of the slot would fail every check.
--      Play -> Saves tab -> quick-load "RT".
--   5. The live run matches RT (ante, dollars, joker keys in order, seed) and
--      save.jkr holds RT (D3).
--   6. Pause -> Main menu -> Play: Continue offers RT, not D.
-- Every save/load under test goes through a UI button (ctx.click); store and
-- checkpoint are only read for assertions.
-- Screenshots: shop, saved, play_tab, loaded, continue.
local store = require('saveslots.store')
local checkpoint = require('saveslots.checkpoint')

local SEED = 'RTRIP001'
local JOKERS = {'j_joker', 'j_egg'}
local decoy = {seed = 'RTDECOY1', dollars = 211}

local rt = {}   -- id, ante, dollars, jokers, seed as recorded from the checkpoint

-- Types into the overlay's name input through the real text-input path (as ui_flow does).
local function type_name(ctx, text)
  ctx.assert(ctx.click('select_text_input'), 'name input not found')
  ctx.assert(G.CONTROLLER.text_input_hook, 'name input did not take the hook')
  for _ = 1, 30 do G.FUNCS.text_input_key({key = 'backspace'}) end
  for i = 1, #text do G.FUNCS.text_input_key({key = text:sub(i, i)}) end
  G.FUNCS.text_input_key({key = 'return'})
  ctx.assert(G.CONTROLLER.text_input_hook == nil, 'return did not release the name input')
end

-- {ante, dollars, jokers = {keys in order}, seed} of a save_run()-shaped table.
local function saved_state(t)
  local g = t and t.GAME
  if not g then return nil end
  local keys = {}
  local area = t.cardAreas and t.cardAreas.jokers
  for i, c in ipairs(area and area.cards or {}) do keys[i] = c.save_fields and c.save_fields.center end
  return {ante = g.round_resets and g.round_resets.ante, dollars = g.dollars, jokers = keys,
    seed = g.pseudorandom and g.pseudorandom.seed}
end

-- The same fields from the live run.
local function live_state()
  local keys = {}
  for i, c in ipairs(G.jokers and G.jokers.cards or {}) do keys[i] = c.config.center.key end
  return {ante = G.GAME.round_resets.ante, dollars = G.GAME.dollars, jokers = keys,
    seed = G.GAME.pseudorandom.seed}
end

local function fmt(st)
  if not st then return 'nil' end
  return string.format('ante %s $%s seed %s jokers [%s]', tostring(st.ante), tostring(st.dollars),
    tostring(st.seed), table.concat(st.jokers or {}, ','))
end

local function same(a, b)
  if not (a and b) then return false end
  if a.ante ~= b.ante or a.dollars ~= b.dollars or a.seed ~= b.seed then return false end
  if #a.jokers ~= #b.jokers then return false end
  for i = 1, #a.jokers do if a.jokers[i] ~= b.jokers[i] then return false end end
  return true
end

-- save.jkr on disk, decoded, or nil.
local function disk_save()
  local raw = get_compressed(G.SETTINGS.profile..'/save.jkr')
  return raw and STR_UNPACK(raw) or nil
end

local function add_joker(key)
  local card = create_card('Joker', G.jokers, nil, nil, nil, nil, key)
  card:add_to_deck()
  G.jokers:emplace(card)
end

-- Vanilla shows unlock notices as overlays: resuming a saved run unlocks
-- Throwback ("Continue a saved run from the main menu"), and the notice pops
-- up a few seconds into the loaded run. A player dismisses it with its own
-- Continue button; so does this. Returns true while a notice is up or was
-- dismissed less than a second ago.
local seen = {at = 0, dismissed = -math.huge}
local function dismiss_unlock(ctx)
  local now = love.timer.getTime()
  if not (G.OVERLAY_MENU and ctx.find_button('continue_unlock')) then
    return now - seen.dismissed < 1
  end
  -- Let the notice's own REAL-timer events run first: continue_unlock flushes
  -- the event queue after closing the overlay, and one of them indexes it.
  if seen.box ~= G.OVERLAY_MENU then seen.box, seen.at = G.OVERLAY_MENU, now end
  if now - seen.at > 1.5 then
    ctx.log('dismissed a vanilla unlock notice')
    ctx.click('continue_unlock')
    seen.dismissed = now
  end
  return true
end

-- Main menu up with nothing over it.
local function main_menu_up(ctx)
  if G.STAGE ~= G.STAGES.MAIN_MENU or dismiss_unlock(ctx) then return false end
  return G.MAIN_MENU_UI ~= nil and G.OVERLAY_MENU == nil and ctx.step_time() > 1.5
end

return {
  -- Player-slot scenario: auto-checkpoints (on by default since 0.2) would add
  -- 'Auto A<n>' slots and break the slot counts this scenario asserts.
  {name = 'no auto-checkpoints', run = function(ctx) SaveSlots.settings.auto_checkpoints = false; return true end},
  -- 1. Run R into the shop
  {name = 'start run', run = function(ctx)
    ctx.start_run{seed = SEED}
    return true
  end},
  {name = 'blind select', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
      and G.GAME.pseudorandom.seed == SEED and ctx.step_time() > 1
  end},
  {name = 'add state', run = function(ctx)
    ease_dollars(40, true)
    ease_ante(1)
    for _, k in ipairs(JOKERS) do add_joker(k) end
    return true
  end},
  {name = 'select blind', timeout = 10, run = function(ctx)
    if ctx.step_time() < 1 or #G.jokers.cards < #JOKERS then return false end
    local opt = G.blind_select_opts and G.blind_select_opts[string.lower(G.GAME.blind_on_deck)]
    local b = opt and opt:get_UIE_by_ID('select_blind_button')
    if not (b and b.config.button == 'select_blind') then return false end
    G.FUNCS.select_blind(b)
    return true
  end},
  {name = 'hand dealt', timeout = 15, run = function(ctx)
    if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or ctx.step_time() < 1 then return false end
    -- Any hand wins: the round ends through vanilla's own evaluate/end_round path.
    G.GAME.blind.chips = 1
    G.GAME.blind.chip_text = number_format(1)
    G.hand:add_to_highlighted(G.hand.cards[1])
    return true
  end},
  {name = 'play hand', timeout = 5, run = function(ctx)
    return ctx.click('play_cards_from_highlighted')
  end},
  {name = 'cash out', timeout = 20, run = function(ctx)
    if G.STATE ~= G.STATES.ROUND_EVAL or ctx.step_time() < 1 then return false end
    return ctx.click('cash_out')
  end},
  {name = 'shop autosave', timeout = 20, run = function(ctx)
    local snap = checkpoint.get()
    if not (G.STATE == G.STATES.SHOP and G.shop and snap and snap.STATE == G.STATES.SHOP) then return false end
    if ctx.step_time() < 3 then return false end   -- let the price tags land
    ctx.shot('shop')
    return true
  end},

  -- 2. Pause -> Save Slots -> "RT" -> Save
  {name = 'pause', run = function(ctx)
    ctx.assert(#store.list() == 0, 'slots exist before the round trip')
    ctx.assert(ctx.click('options'), 'HUD Options button not found')
    return true
  end},
  {name = 'open save slots', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.8 then return false end
    ctx.assert(ctx.click('saveslots_open'), 'Save Slots button missing from the pause menu')
    return true
  end},
  {name = 'save RT', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.8 then return false end
    -- 3. What is being saved: the checkpoint at the moment of the click.
    local snap = checkpoint.get()
    ctx.assert(snap and snap.STATE == G.STATES.SHOP, 'checkpoint is not the shop autosave')
    local st = saved_state(snap)
    ctx.assert(st.ante == 2, 'checkpoint ante '..tostring(st.ante)..', expected 2')
    ctx.assert(st.seed == SEED, 'checkpoint seed '..tostring(st.seed))
    ctx.assert(#st.jokers == 2 and st.jokers[1] == JOKERS[1] and st.jokers[2] == JOKERS[2],
      'checkpoint jokers ['..table.concat(st.jokers, ',')..']')
    ctx.assert(st.dollars >= 44, 'checkpoint dollars '..tostring(st.dollars)..', expected at least 44')
    type_name(ctx, 'RT')
    ctx.assert(ctx.click('saveslots_save_new'), 'Save current run button not found')
    for k, v in pairs(st) do rt[k] = v end
    return true
  end},
  {name = 'saved', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    local list = store.list()
    ctx.assert(#list == 1 and list[1].name == 'RT', 'expected one slot named RT, got '..#list)
    rt.id = list[1].id
    local on_disk = saved_state(store.read(rt.id))
    ctx.assert(same(on_disk, rt), 'slot holds '..fmt(on_disk)..', checkpoint was '..fmt(rt))
    ctx.assert(list[1].summary.state == 'SHOP', 'slot summary state '..tostring(list[1].summary.state))
    ctx.log('check: RT saved from the checkpoint: '..fmt(rt))
    ctx.shot('saved')
    return true
  end},

  -- 4. Back through the pause menu to the main menu
  {name = 'back to pause', run = function(ctx)
    ctx.assert(ctx.click('options'), 'Back button not found in Save Slots')
    return true
  end},
  {name = 'main menu button', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.8 then return false end
    return ctx.click('go_to_menu')
  end},
  {name = 'main menu', timeout = 20, run = main_menu_up},

  -- Decoy run D, autosaved, so save.jkr / Continue is D
  {name = 'start decoy', run = function(ctx)
    ctx.start_run{seed = decoy.seed}
    return true
  end},
  {name = 'decoy autosave', timeout = 20, run = function(ctx)
    if not (G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and checkpoint.get() ~= nil
      and G.GAME.pseudorandom.seed == decoy.seed and ctx.step_time() > 1) then return false end
    G.GAME.dollars = decoy.dollars
    save_run()
    G.FILE_HANDLER.force = true
    return true
  end},
  {name = 'decoy on disk', timeout = 10, run = function(ctx)
    local st = saved_state(disk_save())
    return st and st.seed == decoy.seed and st.dollars == decoy.dollars
  end},
  {name = 'decoy to menu', run = function(ctx)
    G.FUNCS.go_to_menu()
    return true
  end},
  {name = 'menu after decoy', timeout = 20, run = main_menu_up},

  -- Play -> Saves -> quick-load RT
  {name = 'open play', run = function(ctx)
    ctx.assert(ctx.click('setup_run'), 'Play button not found')
    return true
  end},
  {name = 'saves tab', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    local cont = saved_state(G.SAVED_GAME)
    ctx.assert(cont and cont.seed == decoy.seed, 'Continue should hold decoy D before the load, holds '..fmt(cont))
    local tab = ctx.find_button('change_tab', 'tab_but_Saves')
    ctx.assert(tab, 'Saves tab missing')
    tab:click()
    return true
  end},
  {name = 'play_tab shot', run = function(ctx)
    if ctx.step_time() < 0.8 then return false end
    local q = ctx.find_button('saveslots_quickload')
    ctx.assert(q, 'no quick-load button on the Saves tab')
    ctx.assert(q.config.ref_table and q.config.ref_table.id == rt.id, 'first quick load is not RT')
    ctx.shot('play_tab')
    return true
  end},
  {name = 'quick load RT', run = function(ctx)
    ctx.assert(ctx.click('saveslots_quickload'), 'saveslots_quickload not found')
    return true
  end},

  -- 5. The loaded run is RT, and so is save.jkr (D3)
  {name = 'loaded', timeout = 20, run = function(ctx)
    if G.STAGE ~= G.STAGES.RUN or dismiss_unlock(ctx) then return false end
    -- The shop slides in and the unlock notice arrives ~2.5 s after the load:
    -- wait past both before checking and shooting.
    return G.OVERLAY_MENU == nil and G.STATE == G.STATES.SHOP and G.shop ~= nil
      and ctx.step_time() > 5
  end},
  {name = 'loaded check', run = function(ctx)
    local st = live_state()
    ctx.assert(same(st, rt), 'loaded '..fmt(st)..', expected RT '..fmt(rt))
    ctx.assert(st.seed ~= decoy.seed, 'loaded the Continue run D')
    local disk = saved_state(disk_save())
    ctx.assert(same(disk, rt), 'save.jkr holds '..fmt(disk)..', expected RT '..fmt(rt))
    ctx.log('check: loaded run matches RT: '..fmt(st))
    ctx.log('check: save.jkr holds RT (D3)')
    ctx.shot('loaded')
    return true
  end},

  -- 6. Menu -> Play: Continue offers RT
  {name = 'pause after load', run = function(ctx)
    ctx.assert(ctx.click('options'), 'HUD Options button not found')
    return true
  end},
  {name = 'menu after load', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.8 then return false end
    return ctx.click('go_to_menu')
  end},
  {name = 'menu up', timeout = 20, run = main_menu_up},
  {name = 'open play again', run = function(ctx)
    ctx.assert(ctx.click('setup_run'), 'Play button not found')
    return true
  end},
  {name = 'continue tab', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    local tab = ctx.find_button('change_tab', 'tab_but_'..localize('b_continue'))
    ctx.assert(tab, 'Continue tab missing')
    tab:click()
    return true
  end},
  {name = 'continue check', run = function(ctx)
    if ctx.step_time() < 0.8 then return false end
    local cont = saved_state(G.SAVED_GAME)
    ctx.assert(same(cont, rt), 'Continue offers '..fmt(cont)..', expected RT '..fmt(rt))
    ctx.log('check: Continue offers RT')
    ctx.shot('continue')
    return true
  end},
}
