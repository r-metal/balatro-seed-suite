-- RunJournal Run Info history (T-373): the "History" tab in vanilla's Run Info shows this
-- run's antes from the live record, in a real run played through the real UI.
--   1. Start seeded run RJRUNINFO at Red Stake (stake 2), so vanilla's Run Info has all
--      four of its tabs (Stake appears above White Stake): the widest vanilla tab row.
--   2. Ante 1: skip the Small Blind (its tag noted from the blind select UI), win Big and
--      the Boss (its key noted from the blind choices when it is selected), shop.
--   3. Ante 2: select the Small Blind and wait for the hand.
--   4. Open Run Info with the HUD's Run Info button (UIElement:click, as a player's
--      press; vanilla's pause menu has no Run Info entry). Poker Hands is open: note the
--      overlay panel's w/h.
--      -> "check: history tab present": the tabs read Poker Hands, Blinds, Vouchers,
--         Stake with the game's own builders, then History, last. The Stake builder is
--         the one the game's own run_info names (the function runinfo.install wrapped,
--         called with create_tabs stubbed): vanilla's G.UIDEF.current_stake, or under
--         Steamodded its G.UIDEF.SMODS_current_stake (one of those two, and without
--         Steamodded vanilla's). That list must be exactly the four, the first three
--         with vanilla's builders.
--   5. Press the History tab. Its cells, read back by text id:
--      -> "check: skip shows its tag": ante 1 Small = Skipped + the tag's localized name
--      -> "check: boss beaten shown": ante 1 Boss = the boss's localized name + Beaten
--      -> "check: current blind marked": ante 2 Small = Small Blind + Current, and ante
--         2's Big and Boss cells are blank (nothing upcoming is shown)
--      -> "check: size unchanged": the panel's w/h equal the Poker Hands ones (0.01) and
--         fit G.ROOM. The same builder at the same size keeps that size too with a
--         12-ante endless record (newest 8 rows + "+4 earlier"), a record met at ante 3
--         and sent back to it (a second row for its second pass, "Recorded from ante 3")
--         and no record ("No history recorded for this run").
-- Loaders: runs under vanilla's rig (rig/smoke.sh) and real lovely with or without
-- Steamodded (rig/lovely-rig.sh --smods). Steamodded opens the Charm Tag's pack in its
-- own state (SMODS_BOOSTER_OPENED), which the pack skip also waits on. Its boss draw is
-- not vanilla's and changes between launches (RJRUNINFO's ante 1 boss: The Goad in
-- vanilla; The Hook, Pillar, Club, Head and Manacle seen under Steamodded 26.829), so
-- the boss is read from the run. Its Run Info tabs: Poker Hands, Blinds, Vouchers,
-- Stake, History.
-- Speed: vsync off, GAMESPEED 64, extra Game:update passes (as scenario runjournal).
--   6. Rig-only look at the 8-row layout: the endless record's tab swapped in through
--      vanilla's change_tab; the panel keeps its size.
-- Screenshots: runinfo_history (Run Info with History open), runinfo_endless (step 6).
local runinfo = require('runjournal.runinfo')
local recorder = require('runjournal.recorder')

local SEED = 'RJRUNINFO'
local STAKE = 2
local S = {}

local function turbo()
  for _ = 1, 4 do G:update(1/20) end
end

local function panel()
  local kind = G.GAME.blind_on_deck
  local box = G.blind_select_opts and kind and G.blind_select_opts[string.lower(kind)]
  return box, kind
end

-- Steamodded opens every booster (its own Booster objects, the vanilla ones included) in
-- one state of its own, SMODS_BOOSTER_OPENED (tools/smods-*/lovely/booster.toml, Card:open);
-- G.STATES has no such key without it.
local PACKS = {'TAROT_PACK', 'PLANET_PACK', 'SPECTRAL_PACK', 'STANDARD_PACK', 'BUFFOON_PACK',
  'SMODS_BOOSTER_OPENED'}

-- A skip tag can open a booster pack on the spot: skip it once it is up.
local function in_pack(ctx)
  for _, st in ipairs(PACKS) do
    if G.STATE == G.STATES[st] then
      S.pack_since = S.pack_since or love.timer.getTime()
      if not S.pack_skipped and G.booster_pack and love.timer.getTime() - S.pack_since > 1 then
        S.pack_skipped = ctx.click('skip_booster')
      end
      return true
    end
  end
  S.pack_since, S.pack_skipped = nil, nil
  return false
end

local function select_blind(kind)
  return {name = 'select '..kind, timeout = 30, run = function(ctx)
    turbo()
    if in_pack(ctx) then return false end
    if G.STATE ~= G.STATES.BLIND_SELECT or not G.blind_select or ctx.step_time() < 0.3 then return false end
    local box, on_deck = panel()
    if on_deck ~= kind then return false end
    local btn = box and box:get_UIE_by_ID('select_blind_button')
    if not (btn and btn.config.button == 'select_blind') then return false end
    if kind == 'Boss' then S.boss = G.GAME.round_resets.blind_choices.Boss end
    G.FUNCS.select_blind(btn)
    return true
  end}
end

-- Plays up to five cards against a target of 1: a sure win.
local function play(kind)
  return {name = 'play '..kind, timeout = 30, run = function(ctx)
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

local function cash_out()
  return {name = 'cash out', timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.ROUND_EVAL or ctx.step_time() < 0.2 then return false end
    return ctx.click('cash_out')
  end}
end

local function shop()
  return {name = 'shop', timeout = 30, run = function(ctx)
    turbo()
    -- Leaving before the shop's delayed event lands crashes it (game.lua:3090).
    if G.STATE ~= G.STATES.SHOP or not G.shop or ctx.step_time() < 0.3
      or not (G.shop_booster and #G.shop_booster.cards == 2) then return false end
    return ctx.click('toggle_shop')
  end}
end

-- A press the way the controller makes one (UIElement:click also moves a tab's
-- "chosen" highlight, which G.FUNCS alone would not).
local function press(ctx, button, id)
  local e = ctx.find_button(button, id)
  if not e then return false end
  e:click()
  return true
end

local function hist(id)
  local e = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('runjournal_hist_'..id)
  return e and e.config.text
end

local function loc_name(set, key)
  return localize{type = 'name_text', set = set, key = key}
end

-- The overlay's visible panel: create_UIBox_generic_options' root is a 5x-room backdrop.
local function panel_size()
  local p = G.OVERLAY_MENU and G.OVERLAY_MENU.UIRoot.children[1]
  return p and {w = p.T.w, h = p.T.h}
end

local function tab_buttons()
  local shoulders = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('tab_shoulders')
  local out = {}
  local function walk(e)
    if e.config and e.config.button == 'change_tab' then out[#out + 1] = e; return end
    for _, c in ipairs(e.children or {}) do walk(c) end
  end
  if shoulders then walk(shoulders) end
  return out
end

-- The tab list the game's own Run Info builds, History aside: the function
-- runinfo.install wrapped (the wrapper's upvalue orig_run_info), called with
-- create_tabs and create_UIBox_generic_options stubbed to hand back the tab list and
-- build nothing. A loader's patches are in it: vanilla's Stake tab is built by
-- G.UIDEF.current_stake, Steamodded's by its G.UIDEF.SMODS_current_stake
-- (tools/smods-*/lovely/stake.toml, unless its config sets vanilla_stake).
local function own_tabs()
  local orig
  for i = 1, 64 do
    local n, v = debug.getupvalue(G.UIDEF.run_info, i)
    if n == nil then break end
    if n == 'orig_run_info' then orig = v; break end
  end
  if type(orig) ~= 'function' then return nil end
  local tabs, generic = create_tabs, create_UIBox_generic_options
  local got
  create_tabs = function(args) got = args; return {} end
  create_UIBox_generic_options = function() return {} end
  local ok, err = pcall(orig)
  create_tabs, create_UIBox_generic_options = tabs, generic
  if not ok then error(err, 0) end
  return got and got.tabs
end

local function uidef_name(fn)
  for k, v in pairs(G.UIDEF) do if v == fn then return 'G.UIDEF.'..k end end
  return tostring(fn)
end

-- Every UIT.T text with an id in a definition (before it becomes a UIBox).
local function def_texts(node, out)
  out = out or {}
  if type(node) ~= 'table' then return out end
  if node.n == G.UIT.T and node.config and node.config.id then out[node.config.id] = node.config.text end
  for _, c in pairs(node.nodes or {}) do def_texts(c, out) end
  return out
end

-- The builder at `size` for `record`: the UIBox's w/h and its text ids.
local function build(record, size)
  local def = runinfo.definition(record, size)
  local texts = def_texts(def)
  local box = UIBox{definition = def, config = {offset = {x = 0, y = 0}}}
  local w, h = box.T.w, box.T.h
  box:remove()
  return w, h, texts
end

-- A 12-ante endless record: antes 1-11 with Small skipped and Big and Boss beaten
-- (long boss and tag names among them), ante 12 with Small beaten and Big open.
local BOSSES = {'bl_hook', 'bl_ox', 'bl_house', 'bl_wall', 'bl_wheel', 'bl_arm', 'bl_club',
  'bl_final_vessel', 'bl_psychic', 'bl_goad', 'bl_water'}
local TAGS = {'tag_investment', 'tag_polychrome', 'tag_ethereal', 'tag_standard', 'tag_negative'}

local function endless_record()
  local antes = {}
  for a = 1, 11 do
    antes[a] = {blinds = {
      {kind = 'Small', key = 'bl_small', skipped = true, tag = TAGS[(a - 1) % #TAGS + 1], hands = {}},
      {kind = 'Big', key = 'bl_big', skipped = false, won = true, hands = {}},
      {kind = 'Boss', key = BOSSES[a], skipped = false, won = true, hands = {}},
    }}
  end
  antes[12] = {blinds = {
    {kind = 'Small', key = 'bl_small', skipped = false, won = true, hands = {}},
    {kind = 'Big', key = 'bl_big', skipped = false, hands = {}},
  }}
  return {run_id = 'synthetic', antes = antes}
end

local function near(a, b) return math.abs(a - b) <= 0.01 end

local steps = {
  {name = 'speed up', run = function()
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    return true
  end},
  {name = 'start '..SEED, run = function(ctx)
    ctx.start_run{seed = SEED, stake = STAKE}
    return true
  end},
  {name = 'blind select', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
      and G.GAME.pseudorandom.seed == SEED and ctx.step_time() > 1
  end},
  {name = 'skip small', timeout = 20, run = function(ctx)
    turbo()
    if not G.blind_select or ctx.step_time() < 0.5 then return false end
    local box, kind = panel()
    ctx.assert(kind == 'Small', 'Small is not on deck: '..tostring(kind))
    local tag = box and box:get_UIE_by_ID('tag_Small')
    local btn = tag and tag.children[2]
    if not (btn and btn.config.button == 'skip_blind') then return false end
    local container = box:get_UIE_by_ID('tag_container')
    S.tag = container and container.config.ref_table and container.config.ref_table.key
    ctx.assert(S.tag, 'no tag on the Small blind panel')
    ctx.log('skip tag '..tostring(S.tag))
    G.FUNCS.skip_blind(btn)
    return true
  end},
  select_blind('Big'), play('Big'), cash_out(), shop(),
  select_blind('Boss'), play('Boss'), cash_out(), shop(),
  select_blind('Small'),
  {name = 'ante 2 hand', timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or ctx.step_time() < 0.5 then return false end
    ctx.assert(G.GAME.round_resets.ante == 2, 'ante '..tostring(G.GAME.round_resets.ante))
    ctx.log('boss '..tostring(S.boss))
    return true
  end},
  {name = 'open run info', run = function(ctx)
    return press(ctx, 'run_info')
  end},
  {name = 'run info up', timeout = 10, run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    local tabs = tab_buttons()
    local labels = {}
    for i, e in ipairs(tabs) do
      labels[i] = tostring(e.config.ref_table and e.config.ref_table.label)..(e.config.chosen and ' (open)' or '')
    end
    ctx.log('tabs: '..table.concat(labels, ', '))
    local own = own_tabs()
    ctx.assert(own, 'no tab list from the game\'s own run_info (runinfo.install\'s orig_run_info)')
    local stake = own[4] and own[4].tab_definition_function
    ctx.assert(type(stake) == 'function', 'the game\'s own Run Info has no Stake tab builder')
    ctx.log('Stake tab builder: '..uidef_name(stake))
    -- A stake builder the game has: without Steamodded, vanilla's alone.
    ctx.assert(stake == G.UIDEF.current_stake or stake == G.UIDEF.SMODS_current_stake,
      'the Stake tab builder is '..uidef_name(stake))
    local want = {
      {localize('b_poker_hands'), create_UIBox_current_hands},
      {localize('b_blinds'), G.UIDEF.current_blinds},
      {localize('b_vouchers'), G.UIDEF.used_vouchers},
      {localize('b_stake'), stake},
    }
    for i, w in ipairs(want) do
      ctx.assert(own[i] and own[i].label == w[1] and own[i].tab_definition_function == w[2],
        'the game\'s own tab '..i..' is '..tostring(own[i] and own[i].label))
    end
    ctx.assert(own[#want + 1] == nil, 'the game\'s own Run Info has more than '..#want..' tabs')
    ctx.assert(#tabs == #want + 1, #tabs..' tabs, want '..(#want + 1))
    for i, w in ipairs(want) do
      local t = tabs[i].config.ref_table
      ctx.assert(t.label == w[1] and t.tab_definition_function == w[2], 'tab '..i..' is '..tostring(t.label))
      ctx.assert(not t.runjournal_history, 'tab '..i..' is ours')
    end
    local last = tabs[#tabs].config.ref_table
    ctx.assert(last.label == runinfo.LABEL and last.runjournal_history, 'last tab is '..tostring(last.label))
    ctx.assert(tabs[1].config.chosen, 'Poker Hands is not the open tab')
    S.size = last.tab_definition_function_args
    ctx.assert(type(S.size) == 'table' and S.size.w and S.size.h, 'History tab has no measured size')
    S.hands_size = panel_size()
    ctx.log(string.format('Poker Hands panel %.3f x %.3f; tab area %.3f x %.3f; room %.3f x %.3f',
      S.hands_size.w, S.hands_size.h, S.size.w, S.size.h, G.ROOM.T.w, G.ROOM.T.h))
    ctx.log('check: history tab present')
    return true
  end},
  {name = 'press History', run = function(ctx)
    return press(ctx, 'change_tab', 'tab_but_'..runinfo.LABEL)
  end},
  {name = 'history shown', timeout = 10, run = function(ctx)
    if not hist('1_Small') or ctx.step_time() < 0.5 then return false end
    ctx.shot('runinfo_history')
    return true
  end},
  {name = 'history cells', run = function(ctx)
    local r = recorder.current()
    ctx.assert(r and r.seed == SEED, 'no live record for '..SEED)
    for _, id in ipairs({'1_Small', '1_Big', '1_Boss', '2_Small'}) do
      ctx.log(id..': '..tostring(hist(id))..' / '..tostring(hist(id..'_sub')))
    end

    local tag_name = loc_name('Tag', S.tag)
    ctx.assert(hist('1_Small') == 'Skipped' and hist('1_Small_sub') == tag_name,
      'ante 1 Small reads '..tostring(hist('1_Small'))..' / '..tostring(hist('1_Small_sub'))..', want Skipped / '..tag_name)
    ctx.log('check: skip shows its tag')

    ctx.assert(hist('1_Big') == loc_name('Blind', 'bl_big') and hist('1_Big_sub') == 'Beaten', 'ante 1 Big')
    ctx.assert(type(S.boss) == 'string' and S.boss ~= 'bl_small' and S.boss ~= 'bl_big', 'boss key '..tostring(S.boss))
    local boss_name = loc_name('Blind', S.boss)
    ctx.assert(hist('1_Boss') == boss_name and hist('1_Boss_sub') == 'Beaten',
      'ante 1 Boss reads '..tostring(hist('1_Boss'))..' / '..tostring(hist('1_Boss_sub'))..', want '..boss_name..' / Beaten')
    ctx.log('check: boss beaten shown')

    ctx.assert(hist('2_Small') == loc_name('Blind', 'bl_small') and hist('2_Small_sub') == 'Current',
      'ante 2 Small reads '..tostring(hist('2_Small'))..' / '..tostring(hist('2_Small_sub')))
    ctx.assert(hist('2_Big') == nil and hist('2_Boss') == nil, 'ante 2 shows a blind not reached: '
      ..tostring(hist('2_Big'))..' / '..tostring(hist('2_Boss')))
    ctx.assert(hist('3_Small') == nil and hist('more') == nil and hist('from') == nil, 'extra rows or notes')
    ctx.log('check: current blind marked')

    local now = panel_size()
    ctx.log(string.format('History panel %.3f x %.3f', now.w, now.h))
    ctx.assert(near(now.w, S.hands_size.w) and near(now.h, S.hands_size.h), string.format(
      'History panel %.3f x %.3f vs Poker Hands %.3f x %.3f', now.w, now.h, S.hands_size.w, S.hands_size.h))
    ctx.assert(now.w <= G.ROOM.T.w and now.h <= G.ROOM.T.h, 'the panel is bigger than the room')
    local box = G.OVERLAY_MENU:get_UIE_by_ID('tab_contents').config.object
    ctx.assert(near(box.T.w, S.size.w) and near(box.T.h, S.size.h), 'tab contents '..box.T.w..' x '..box.T.h)
    local w, h, texts = build(endless_record(), S.size)
    ctx.log(string.format('endless build %.3f x %.3f: %s', w, h, tostring(texts.runjournal_hist_more)))
    ctx.assert(near(w, S.size.w) and near(h, S.size.h), string.format('endless tab %.3f x %.3f', w, h))
    ctx.assert(texts.runjournal_hist_more == '+4 earlier' and texts.runjournal_hist_5_Small == 'Skipped'
      and texts.runjournal_hist_12_Big_sub == 'Current' and not texts.runjournal_hist_12_Boss
      and not texts.runjournal_hist_4_Small, 'endless rows')
    -- Met mid-run at ante 3 (a loaded pre-Journal run), sent back to ante 3 once.
    w, h, texts = build({run_id = 'partial', antes = {[3] = {blinds = {
      {kind = 'Small', key = 'bl_small', skipped = false, won = true, hands = {}},
      {kind = 'Big', key = 'bl_big', skipped = false, won = true, hands = {}},
      {kind = 'Boss', key = 'bl_hook', skipped = false, won = true, hands = {}},
      {kind = 'Small', key = 'bl_small', skipped = false, hands = {}},
    }}}}, S.size)
    ctx.assert(near(w, S.size.w) and near(h, S.size.h), string.format('partial tab %.3f x %.3f', w, h))
    ctx.assert(texts.runjournal_hist_from == 'Recorded from ante 3' and texts.runjournal_hist_3_Boss_sub == 'Beaten'
      and texts.runjournal_hist_3p2_Small_sub == 'Current' and texts.runjournal_hist_3_Small_sub == 'Beaten',
      'partial rows')
    w, h, texts = build(nil, S.size)
    ctx.assert(near(w, S.size.w) and near(h, S.size.h), string.format('no-record tab %.3f x %.3f', w, h))
    ctx.assert(texts.runjournal_hist_none == 'No history recorded for this run', 'no-record text')
    ctx.log('check: size unchanged')
    return true
  end},
  -- A look at the full 8-row layout: the endless record's tab put in place by vanilla's
  -- change_tab (a stand-in button whose tab builds it). Rig-only; the record is untouched.
  {name = 'endless layout', run = function(ctx)
    G.FUNCS.change_tab({UIBox = G.OVERLAY_MENU, config = {ref_table = {
      tab_definition_function = function(s) return runinfo.definition(endless_record(), s) end,
      tab_definition_function_args = S.size}}})
    local now = panel_size()
    ctx.assert(near(now.w, S.hands_size.w) and near(now.h, S.hands_size.h), string.format(
      'endless panel %.3f x %.3f', now.w, now.h))
    return true
  end},
  {name = 'endless shot', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    ctx.shot('runinfo_endless')
    return true
  end},
}

return steps
