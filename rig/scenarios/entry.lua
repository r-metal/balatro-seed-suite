-- Entry points (D2): the "Save Slots" button in the main-menu Options and the
-- in-run pause menu, and the Play screen's "Saves" tab quick-loading a slot.
-- Screenshots: options.png (main-menu Options), pause.png (pause menu),
-- play_tab.png (Play screen on the Saves tab), play_tab_empty.png (the
-- same tab before any save).
--
-- The quick load is proved against a decoy: after Gamma is saved, a second
-- run B (its own seed, dollars and ante) is started and autosaved, so
-- save.jkr and G.SAVED_GAME hold B when the quick load is clicked. Loading
-- Continue instead of the slot would then produce B's state, not Gamma's.
local store = require('saveslots.store')
local checkpoint = require('saveslots.checkpoint')

local saved = {}
local decoy = {seed = 'SLOTDCOY', dollars = 313, ante = 2}

-- First live UIElement (overlay included, nested boxes too) whose text is `text`.
local function find_text(text)
  local hit
  local function walk(e)
    if hit then return end
    if e.config and e.config.text == text then hit = e; return end
    for _, c in ipairs(e.children or {}) do walk(c) end
    if e.config and e.config.object and e.config.object.UIRoot then walk(e.config.object.UIRoot) end
  end
  if G.OVERLAY_MENU then walk(G.OVERLAY_MENU.UIRoot) end
  return hit
end

-- save.jkr on disk, decoded, or nil.
local function disk_save()
  local raw = get_compressed(G.SETTINGS.profile..'/save.jkr')
  return raw and STR_UNPACK(raw) or nil
end

local function run_state(t)
  local g = t and t.GAME
  if not g then return nil end
  return {seed = g.pseudorandom and g.pseudorandom.seed, dollars = g.dollars,
    ante = g.round_resets and g.round_resets.ante}
end

local function fmt(st)
  if not st then return 'nil' end
  return 'seed '..tostring(st.seed)..' $'..tostring(st.dollars)..' ante '..tostring(st.ante)
end

-- Index of the row (in the button list) holding `button`, walking the live
-- overlay: proves placement, not only presence.
local function button_order(ctx)
  local order = {}
  local function walk(e)
    if e.config and e.config.button and e.config.button ~= 'exit_overlay_menu' then order[#order + 1] = e.config.button end
    for _, c in ipairs(e.children or {}) do walk(c) end
  end
  walk(G.OVERLAY_MENU.UIRoot)
  return order
end

local function index_of(list, v)
  for i, x in ipairs(list) do if x == v then return i end end
end

return {
  -- Player-slot scenario: auto-checkpoints (on by default since 0.2) would add
  -- 'Auto A<n>' slots and break the slot counts this scenario asserts.
  {name = 'no auto-checkpoints', run = function(ctx) SaveSlots.settings.auto_checkpoints = false; return true end},
  -- 1. Main-menu Options
  {name = 'open options', run = function(ctx)
    ctx.assert(ctx.find_button('saveslots_quickload') == nil, 'quick load visible before Play was opened')
    ctx.assert(ctx.click('options'), 'Options button not found')
    return true
  end},
  {name = 'options shot', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    ctx.assert(ctx.find_button('saveslots_open'), 'Save Slots button missing from main-menu Options')
    local order = button_order(ctx)
    ctx.assert(order[#order] == 'saveslots_open', 'Save Slots should be last on the main menu, order: '..table.concat(order, ','))
    ctx.log('options order: '..table.concat(order, ','))
    ctx.shot('options')
    return true
  end},
  {name = 'close options', run = function(ctx)
    ctx.assert(ctx.click('exit_overlay_menu'), 'Back button not found in Options')
    return true
  end},
  {name = 'options closed', run = function(ctx)
    return G.OVERLAY_MENU == nil
  end},

  -- 1b. Play screen before any save: the Saves tab says so (beyond the task's steps)
  {name = 'open play, empty', run = function(ctx)
    ctx.assert(ctx.click('setup_run'), 'Play button not found')
    return true
  end},
  {name = 'saves tab, empty', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    local tab = ctx.find_button('change_tab', 'tab_but_Saves')
    ctx.assert(tab, 'Saves tab missing on the main menu')
    tab:click()
    return true
  end},
  {name = 'empty tab shot', run = function(ctx)
    if ctx.step_time() < 0.8 then return false end
    ctx.assert(ctx.find_button('saveslots_quickload') == nil, 'quick load shown with no saves')
    ctx.assert(ctx.find_button('saveslots_open'), 'Open Save Slots missing on the empty Saves tab')
    local empty = find_text('No saves yet')
    ctx.assert(empty, 'no "No saves yet" text on the empty Saves tab')
    ctx.assert(empty.config.colour == G.C.UI.TEXT_LIGHT, '"No saves yet" is not drawn in G.C.UI.TEXT_LIGHT')
    ctx.shot('play_tab_empty')
    return true
  end},
  {name = 'close play', run = function(ctx)
    ctx.assert(ctx.click('exit_overlay_menu'), 'Back button not found on the Play screen')
    return true
  end},
  {name = 'play closed', run = function(ctx)
    return G.OVERLAY_MENU == nil
  end},

  -- 2. In a run: save Gamma, pause menu, back to the main menu
  {name = 'start run', run = function(ctx)
    ctx.start_run{}
    return true
  end},
  {name = 'first autosave', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and checkpoint.get() ~= nil
  end},
  {name = 'save Gamma', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    -- Make the slot distinguishable from a fresh run so the quick load is provable.
    G.GAME.dollars = 77
    save_run()
    local id = store.save(checkpoint.get(), 'Gamma')
    ctx.assert(id, 'store.save failed')
    local list = store.list()
    ctx.assert(#list == 1 and list[1].name == 'Gamma', 'expected one slot named Gamma')
    saved.id = id
    saved.ante = list[1].summary.ante
    saved.dollars = list[1].summary.dollars
    saved.seed = list[1].summary.seed
    ctx.assert(saved.dollars == 77, 'slot dollars are '..tostring(saved.dollars)..', expected 77')
    G.FUNCS.options()
    return true
  end},
  {name = 'pause shot', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    ctx.assert(ctx.find_button('saveslots_open'), 'Save Slots button missing from the pause menu')
    local order = button_order(ctx)
    local s = index_of(order, 'settings')
    ctx.assert(s and order[s + 1] == 'saveslots_open', 'Save Slots should follow Settings in a run, order: '..table.concat(order, ','))
    ctx.log('pause order: '..table.concat(order, ','))
    ctx.shot('pause')
    return true
  end},
  {name = 'go to menu', run = function(ctx)
    G.FUNCS.go_to_menu()
    return true
  end},
  {name = 'main menu', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.MAIN_MENU and G.MAIN_MENU_UI ~= nil and ctx.step_time() > 1.5
  end},

  -- 2b. Decoy run B, autosaved, so Continue (save.jkr / G.SAVED_GAME) is B
  {name = 'start decoy run', run = function(ctx)
    ctx.assert(decoy.seed ~= saved.seed, 'decoy seed collides with Gamma')
    ctx.start_run{seed = decoy.seed}
    return true
  end},
  {name = 'decoy autosave', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and checkpoint.get() ~= nil
      and G.GAME.pseudorandom.seed == decoy.seed
  end},
  {name = 'save decoy', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    G.GAME.dollars = decoy.dollars
    G.GAME.round_resets.ante = decoy.ante
    save_run()
    G.FILE_HANDLER.force = true
    return true
  end},
  {name = 'decoy on disk', timeout = 10, run = function(ctx)
    local st = run_state(disk_save())
    return st and st.seed == decoy.seed and st.dollars == decoy.dollars and st.ante == decoy.ante
  end},
  {name = 'decoy to menu', run = function(ctx)
    G.FUNCS.go_to_menu()
    return true
  end},
  {name = 'menu after decoy', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.MAIN_MENU and G.MAIN_MENU_UI ~= nil and ctx.step_time() > 1.5
  end},
  {name = 'decoy still on disk', run = function(ctx)
    local st = run_state(disk_save())
    ctx.assert(st and st.seed == decoy.seed and st.dollars == decoy.dollars and st.ante == decoy.ante,
      'save.jkr should hold decoy B, holds '..fmt(st))
    ctx.log('decoy B on disk: '..fmt(st)..'; Gamma slot: '..fmt(saved))
    return true
  end},

  -- 3. Play screen, Saves tab, quick load
  {name = 'open play', run = function(ctx)
    ctx.assert(ctx.click('setup_run'), 'Play button not found')
    return true
  end},
  {name = 'saves tab', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    -- run_setup loaded Continue's save: it must be the decoy, not Gamma.
    local cont = run_state(G.SAVED_GAME)
    ctx.assert(cont and cont.seed == decoy.seed and cont.dollars == decoy.dollars and cont.ante == decoy.ante,
      'G.SAVED_GAME should hold decoy B, holds '..fmt(cont))
    -- Vanilla tabs untouched, Saves right after Continue.
    local order = {}
    for _, label in ipairs{localize('b_new_run'), localize('b_continue'), 'Saves', localize('b_challenges')} do
      order[#order + 1] = ctx.find_button('change_tab', 'tab_but_'..label)
      ctx.assert(order[#order], 'tab missing: '..label)
    end
    for i = 2, #order do
      ctx.assert(order[i - 1].T.x < order[i].T.x, 'tabs out of order at '..i)
    end
    ctx.assert(ctx.find_button('saveslots_quickload') == nil, 'quick load visible outside the Saves tab')
    -- A real click, so the tab's chosen state flips like a player's click.
    order[3]:click()
    return true
  end},
  {name = 'play_tab shot', run = function(ctx)
    if ctx.step_time() < 0.8 then return false end
    local q = ctx.find_button('saveslots_quickload')
    ctx.assert(q, 'no saveslots_quickload button on the Saves tab')
    ctx.assert(q.config.ref_table and q.config.ref_table.id == saved.id, 'quick load points at the wrong slot')
    ctx.assert(ctx.find_button('saveslots_open'), 'Open Save Slots button missing on the Saves tab')
    ctx.shot('play_tab')
    return true
  end},
  -- Beyond the task's steps: an unreadable slot keeps the Play screen up and
  -- says so on the tab instead of failing silently.
  {name = 'quick load, unreadable', run = function(ctx)
    local read = store.read
    store.read = function() return nil, 'forced' end
    local ok, err = pcall(ctx.click, 'saveslots_quickload')
    store.read = read
    ctx.assert(ok, tostring(err))
    ctx.assert(err == true, 'saveslots_quickload not found')
    return true
  end},
  {name = 'unreadable message', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    ctx.assert(G.OVERLAY_MENU and G.STAGE == G.STAGES.MAIN_MENU, 'Play screen closed on a failed quick load')
    local found = false
    local function walk(e)
      if e.config and e.config.text == 'This save could not be read' then found = true end
      for _, c in ipairs(e.children or {}) do walk(c) end
      if e.config and e.config.object and e.config.object.UIRoot then walk(e.config.object.UIRoot) end
    end
    walk(G.OVERLAY_MENU.UIRoot)
    ctx.assert(found, 'no "This save could not be read" message on the Saves tab')
    ctx.assert(ctx.find_button('saveslots_quickload'), 'quick load button gone after the failed load')
    ctx.log('check: unreadable quick load reported on the tab')
    return true
  end},
  {name = 'quick load', run = function(ctx)
    ctx.assert(ctx.click('saveslots_quickload'), 'saveslots_quickload not found')
    return true
  end},
  {name = 'loaded', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.OVERLAY_MENU == nil and G.GAME.round_resets ~= nil
      and ctx.step_time() > 0.5
  end},
  {name = 'loaded check', run = function(ctx)
    local st = run_state(G)
    ctx.assert(st.seed == saved.seed and st.dollars == saved.dollars and st.ante == saved.ante,
      'quick load gave '..fmt(st)..', expected Gamma '..fmt(saved))
    ctx.assert(st.seed ~= decoy.seed and st.dollars ~= decoy.dollars and st.ante ~= decoy.ante,
      'quick load gave the Continue run B: '..fmt(st))
    ctx.log('check: quick load matched ante '..tostring(saved.ante)..' $'..tostring(saved.dollars)..' seed '..tostring(saved.seed))
    ctx.log('check: quickload loads the slot, not Continue')
    return true
  end},
}
