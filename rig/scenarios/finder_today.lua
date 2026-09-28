-- Finder Today (T-378a): the Play screen's Find tab and its "Today" row, driven
-- through the Play screen and the real buttons (setup_run, the Find tab, Open Seed
-- Finder, the cycle arrows, Play blind / Play routed, the pause menu's Seed Oracle).
-- The day is the real UTC date: every comparison reads daily.today() again, and a
-- row built before a UTC midnight is waited on until the ticker redraws it.
--   0. The isolated profile records Red Deck wins up to stake 3 (as finder_mustnot
--      does), so its stakes go up to Black (4). The day's deck stays as the fresh
--      profile has it: locked (unless it is Red Deck, logged).
--   1. Main menu -> Play -> Find. The Today row's date, seed and deck texts equal
--      daily.today()'s date and seed and deck_for()'s deck: Red Deck with the day's
--      deck locked, and the reason (deck_for's, cut before ": playing"), then ", White
--      Stake" and the note "Blind: the Oracle stays locked. Routed: use it.".
--      ui.set_results gives three hits (no scan: pinned seeds, evaluated once each);
--      the row stays as it was. The day's deck unlocked the way daily_run does it
--      (its center's flags) and the Find tab clicked again: the row shows the day's
--      deck and no reason. -> "check: today row shows the day" (shots today_row,
--      today_unlocked)
--   4. The tab's Open Seed Finder; Add clause, kind Joker by ante. At White Stake
--      the extra cycle offers "No rerolls" .. "5 rerolls"; the stake cycle to Black
--      Stake, and it offers "R0", "R0 clean" .. "R5 clean". Each option is clicked
--      to with the right arrow (the panel rebuilds each time) and its DynaText read:
--      it shows that option, its scale is 0.8 or more of the cycle's text scale
--      (create_option_cycle's text_scale) and its width fits the room cycle() fits
--      labels to (the cycle's w less 0.15); the clause holds the rerolls and sticker
--      the label says. -> "check: reroll labels legible" (shot labels_black, at the
--      widest option)
--   2. Back to the Play screen, Find, Play blind: a run on today's seed and deck
--      (unlocked now), stake 1, G.GAME.seeded, bh_daily.mode 'blind'. Pause ->
--      Seed Oracle shows the lock note, not the overlay.
--      -> "check: play blind starts the daily" (shot blind_locked)
--   3. Pause -> Main Menu; the day's deck locked again; Play -> Find: the row shows
--      Red Deck and the reason again. Play routed: bh_daily.mode 'routed', seeded,
--      stake 1, on the deck the row showed (Red); Pause -> Seed Oracle opens the
--      overlay on that seed. -> "check: play routed starts the daily" (shot routed_oracle)
--   5. Every Find tab measured (no hits, three hits, the deck locked and unlocked,
--      a Black Stake joker filter) is TAB_W x TAB_H, 6.40 x 5.20, and the Play
--      screen's panel 15.74 x 8.26: the Find tab's size with no hits before T-378a
--      (three hits grew it to 5.71 then). Every Finder overlay measured (opened from
--      the tab, each reroll label) spans x 0.63..19.37, y 0.10..10.93, as before
--      T-378a (finder_ui, finder_groups and finder_mustnot log the same).
--      -> "check: size unchanged"
-- No scan on this thread: the hits are given by ui.set_results.
-- Screenshots: today_row (required), today_unlocked, labels_black, blind_locked, routed_oracle.
local ui = require('seedfinder.ui')
local daily = require('seedfinder.daily')
local oracle_ui = require('seedoracle.ui')

-- Before T-378a (the probe run on the old ui.lua, 2026-09-28).
local TAB_W, TAB_H = 6.4, 5.2                  -- ui.lua's Find tab minw / minh, with no hits
local PLAY_W, PLAY_H = 15.74, 8.255            -- the Play screen's panel on the Find tab, no hits
local FINDER = {x1 = 0.625, x2 = 19.375, y1 = 0.105, y2 = 10.925}
local MIN_RATIO = 0.8
local NOTE = 'Blind: the Oracle stays locked. Routed: use it.'
local WHITE_LABELS = {'No rerolls', '1 reroll', '2 rerolls', '3 rerolls', '4 rerolls', '5 rerolls'}
local BLACK_LABELS = {'R0', 'R0 clean', 'R1', 'R1 clean', 'R2', 'R2 clean', 'R3', 'R3 clean', 'R4', 'R4 clean',
  'R5', 'R5 clean'}
-- Pinned hits for the tab (any seeds: set_results lists them without a scan).
local F = {name = 'Uncommon Tag', deck = 'b_red', stake = 1, mode = 'all', clauses = {
  {kind = 'tag', ante = 1, blind = 'any', key = 'tag_uncommon'}}}
local SEEDS = {'TODAYAA1', 'TODAYBB2', 'TODAYCC3'}

local S = {tabs = {}, finders = {}, origins = {}}

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU ~= true and G.OVERLAY_MENU:get_UIE_by_ID(id) end
local function idle() return not G.CONTROLLER.locks.frame end
local function name_of(set, key) return localize{type = 'name_text', set = set, key = key} end
local function stake_name(i) return name_of('Stake', G.P_CENTER_POOLS.Stake[i].key) end
local function text_of(id)
  local n = uie(id)
  return n and n.config.text
end

-- The value a cycle shows and the labels it offers, from its right arrow's args.
local function cycle_value(id)
  local arrow = uie('seedfinder_'..id..'_r')
  return arrow and arrow.config.ref_table.current_option_val
end
local function cycle_options(id)
  local arrow = uie('seedfinder_'..id..'_r')
  return arrow and arrow.config.ref_table.options
end

local function same_list(a, b)
  if type(a) ~= 'table' or #a ~= #b then return false end
  for i = 1, #b do if a[i] ~= b[i] then return false end end
  return true
end

local function click(label, button, id, wait)
  return {name = label, timeout = 10, run = function(ctx)
    if wait and not wait() then return false end
    if not idle() or ctx.step_time() < 0.3 then return false end
    return ctx.click(button, id)
  end}
end

-- Clicks a cycle's arrow, the shorter way round, until it shows `want` (a string,
-- or a function giving it once the game is up). One click per frame.
local function cycle_to(id, want, timeout)
  return {name = 'cycle '..id, timeout = timeout or 30, run = function(ctx)
    local w = type(want) == 'function' and want() or want
    local v, opts = cycle_value(id), cycle_options(id)
    if v == w then ctx.log('cycle '..id..' = '..w); return true end
    if v == nil or not idle() then return false end
    local at, to
    for k, l in ipairs(opts) do
      if l == v then at = k end
      if l == w then to = k end
    end
    ctx.assert(at and to, id..' offers no "'..tostring(w)..'": '..table.concat(opts, ', '))
    local right = (to - at) % #opts
    ctx.click('seedfinder_cycle', 'seedfinder_'..id..(right <= #opts - right and '_r' or '_l'))
    return false
  end}
end

-- Sizes ---------------------------------------------------------------------------------

-- The Find tab (tab_contents' box) and the Play screen's panel: the sizes before
-- T-378a; the Today box lies inside the tab.
local function measure_tab(ctx, label)
  local box = uie('tab_contents').config.object
  local panel = G.OVERLAY_MENU.UIRoot.children[1]
  local today = uie('seedfinder_today')
  ctx.assert(today, label..': no Today box')
  ctx.log(('layout %s: Find tab %.3fx%.3f, Play panel %.3fx%.3f, Today box x %.2f..%.2f y %.2f..%.2f in the tab'
    ..' x %.2f..%.2f y %.2f..%.2f'):format(label, box.T.w, box.T.h, panel.T.w, panel.T.h, today.T.x,
    today.T.x + today.T.w, today.T.y, today.T.y + today.T.h, box.T.x, box.T.x + box.T.w, box.T.y, box.T.y + box.T.h))
  ctx.assert(math.abs(box.T.w - TAB_W) <= 0.01 and math.abs(box.T.h - TAB_H) <= 0.01,
    ('%s: the Find tab is %.3fx%.3f, it was %.2fx%.2f'):format(label, box.T.w, box.T.h, TAB_W, TAB_H))
  ctx.assert(math.abs(panel.T.w - PLAY_W) <= 0.01 and math.abs(panel.T.h - PLAY_H) <= 0.01,
    ('%s: the Play panel is %.3fx%.3f, it was %.3fx%.3f'):format(label, panel.T.w, panel.T.h, PLAY_W, PLAY_H))
  ctx.assert(today.T.x >= box.T.x and today.T.x + today.T.w <= box.T.x + box.T.w + 0.001
    and today.T.y >= box.T.y and today.T.y + today.T.h <= box.T.y + box.T.h + 0.001, label..': the Today box leaves the tab')
  S.tabs[#S.tabs + 1] = label
end

-- The Finder overlay's extent (finder_ui's check_fits): the one before T-378a.
local function measure_finder(ctx, label)
  local root = G.OVERLAY_MENU.UIRoot.children[1]
  local back = uie('overlay_menu_back_button')
  local x1, x2, y1, y2 = root.T.x, root.T.x + root.T.w, root.T.y, back.T.y + back.T.h
  ctx.assert(math.abs(x1 - FINDER.x1) <= 0.01 and math.abs(x2 - FINDER.x2) <= 0.01 and math.abs(y1 - FINDER.y1) <= 0.01
    and math.abs(y2 - FINDER.y2) <= 0.01, ('%s: the Finder overlay is x %.3f..%.3f y %.3f..%.3f, it was x %.3f..%.3f'
    ..' y %.3f..%.3f'):format(label, x1, x2, y1, y2, FINDER.x1, FINDER.x2, FINDER.y1, FINDER.y2))
  S.finders[#S.finders + 1] = label
end

-- The Today row ------------------------------------------------------------------------

-- The row against daily.today() and deck_for(), read now. False while the row still
-- shows another day (a UTC midnight: the ticker redraws the tab).
local function check_row(ctx, label)
  local t = os.time()
  local day = daily.today(t)
  local deck, reason = daily.deck_for(nil, t)
  if text_of('seedfinder_today_date') ~= day.date then return false end
  ctx.assert(text_of('seedfinder_today_seed') == day.seed, label..': the row\'s seed is '
    ..tostring(text_of('seedfinder_today_seed'))..', today() says '..day.seed)
  ctx.assert(text_of('seedfinder_today_deck') == name_of('Back', deck), label..': the row\'s deck is '
    ..tostring(text_of('seedfinder_today_deck'))..', deck_for says '..deck)
  ctx.assert(text_of('seedfinder_today_stake') == ', '..stake_name(day.stake) and day.stake == 1,
    label..': the row\'s stake reads '..tostring(text_of('seedfinder_today_stake')))
  ctx.assert(text_of('seedfinder_today_note') == NOTE, label..': the note reads '..tostring(text_of('seedfinder_today_note')))
  local shown = text_of('seedfinder_today_reason')
  if reason then
    ctx.assert(deck == 'b_red' and shown and shown == (reason:match('^(.-): playing ') or reason)
      and shown:find(name_of('Back', day.deck), 1, true), label..': the reason reads '..tostring(shown)
      ..', deck_for says '..reason)
  else
    ctx.assert(shown == nil and deck == day.deck, label..': a reason with the day\'s deck playable: '..tostring(shown))
  end
  for _, b in ipairs{'seedfinder_daily_blind', 'seedfinder_daily_routed'} do
    ctx.assert(ctx.find_button(b, b), label..': no '..b..' button')
  end
  ctx.log(('%s: Today %s %s, %s%s%s'):format(label, day.date, day.seed, text_of('seedfinder_today_deck'),
    text_of('seedfinder_today_stake'), shown and ' ('..shown..')' or ''))
  return {day = day, deck = deck, reason = reason}
end

-- A daily Play button, with today() read on both sides of the click.
local function play_button(mode)
  return {name = 'play '..mode, timeout = 10, run = function(ctx)
    if not idle() or ctx.step_time() < 0.5 then return false end
    local before = daily.today()
    ctx.assert(ctx.click('seedfinder_daily_'..mode, 'seedfinder_daily_'..mode), 'no Play '..mode..' button')
    S[mode] = {before = before, after = daily.today()}
    return true
  end}
end

-- The today() of the day the run was started on (bh_daily.date).
local function day_of(p)
  local d = G.GAME.bh_daily
  local date = type(d) == 'table' and d.date
  if date == p.before.date then return p.before end
  if date == p.after.date then return p.after end
end

local function deck_key()
  local b = G.GAME.selected_back_key
  return type(b) == 'table' and b.key or b
end

-- Vanilla shows unlock cards as overlays; a player dismisses one with its own
-- button, and so does this (daily_run's). True while one is up or was just dismissed.
local unlock = {dismissed = -math.huge}
local function dismiss_unlock(ctx)
  local now = love.timer.getTime()
  if not (G.OVERLAY_MENU and ctx.find_button('continue_unlock')) then
    return now - unlock.dismissed < 1
  end
  if unlock.box ~= G.OVERLAY_MENU then unlock.box, unlock.at = G.OVERLAY_MENU, now end
  if now - unlock.at > 1.5 then
    ctx.log('dismissed a vanilla unlock card')
    ctx.click('continue_unlock')
    unlock.dismissed = now
  end
  return true
end

local function run_ready(ctx, seed)
  if dismiss_unlock(ctx) then return false end
  return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
    and G.GAME.pseudorandom.seed == seed and not G.CONTROLLER.locks.load and G.OVERLAY_MENU == nil
end

-- The daily run p started: today()'s seed (of the day it started on), stake 1,
-- seeded, bh_daily.mode, on `deck`; set_origin got the daily before the run began.
local function check_run(ctx, p, mode, deck)
  local day = day_of(p)
  ctx.assert(day, 'bh_daily.date '..tostring(G.GAME.bh_daily and G.GAME.bh_daily.date)..' is neither '
    ..p.before.date..' nor '..p.after.date)
  ctx.assert(G.GAME.pseudorandom.seed == day.seed, 'seed '..G.GAME.pseudorandom.seed..', today() says '..day.seed)
  ctx.assert(G.GAME.stake == 1, 'stake '..tostring(G.GAME.stake))
  ctx.assert(G.GAME.seeded == true, 'the '..mode..' daily is not seeded')
  ctx.assert(G.GAME.bh_daily.mode == mode, 'bh_daily.mode '..tostring(G.GAME.bh_daily.mode))
  ctx.assert(deck_key() == deck, 'deck '..tostring(deck_key())..', want '..deck)
  local o = S.origins[#S.origins]
  ctx.assert(o and o.o.kind == 'daily' and o.o.mode == mode and o.o.date == day.date and o.stage ~= G.STAGES.RUN,
    'RunJournal set_origin did not get the '..mode..' daily before the run started')
  ctx.log(('%s daily %s: seed %s, %s, stake %d, seeded'):format(mode, day.date, day.seed, deck, G.GAME.stake))
  return day
end

-- Reroll labels ----------------------------------------------------------------------------

-- Row 1's extra cycle: its args (create_option_cycle's) and the DynaText showing
-- its label.
local function extra_label()
  local arrow = uie('seedfinder_c1_extra_r')
  if not arrow then return end
  local args, found = arrow.config.ref_table, nil
  local function walk(n)
    if found or type(n) ~= 'table' then return end
    local o = n.config and n.config.object
    if n.UIT == G.UIT.O and type(o) == 'table' and o.is and o:is(DynaText) and o.config.string
      and o.config.string[1] and o.config.string[1].ref_table == args then found = o; return end
    for _, ch in ipairs(n.children or {}) do walk(ch) end
  end
  walk(arrow.parent)
  return args, found
end

-- Every option of row 1's extra cycle in turn (the right arrow, then the panel's
-- rebuild): the label shows that option at MIN_RATIO or more of the cycle's text
-- scale, inside the room cycle() fits it to, and the clause holds what it says.
local function read_labels(tag, want)
  return {name = 'labels '..tag, timeout = 60, run = function(ctx)
    local st = S.read
    if not st or st.tag ~= tag then
      ctx.assert(same_list(cycle_options('c1_extra'), want), tag..': the extra cycle offers '
        ..table.concat(cycle_options('c1_extra') or {}, ', '))
      ctx.assert(cycle_value('c1_extra') == want[1], tag..': the cycle is on '..tostring(cycle_value('c1_extra')))
      st = {tag = tag, k = 1, at = love.timer.getTime(), widest = nil}
      S.read = st
    end
    local arrow = uie('seedfinder_c1_extra_r')
    if not arrow or arrow == st.clicked or not idle() or love.timer.getTime() - st.at < 0.3 then return false end
    local args, label = extra_label()
    ctx.assert(label, tag..': no DynaText on the extra cycle')
    local l = want[st.k]
    ctx.assert(args.current_option_val == l and label.strings[1] and label.strings[1].string == l,
      ('%s: option %d shows "%s", want "%s"'):format(tag, st.k, tostring(label.strings[1] and label.strings[1].string), l))
    local ratio, room = label.scale/args.text_scale, args.w - 0.15
    ctx.log(('%s "%s": scale %.3f of %.3f (%.2f), w %.3f in %.3f'):format(tag, l, label.scale, args.text_scale, ratio,
      label.config.W, room))
    ctx.assert(ratio >= MIN_RATIO, ('%s: "%s" renders at %.2f of the cycle\'s text scale'):format(tag, l, ratio))
    ctx.assert(label.config.W <= room + 0.001, ('%s: "%s" is %.3f wide in %.3f'):format(tag, l, label.config.W, room))
    local c = ui.current().clauses[1]
    local clean = l:find('clean', 1, true) ~= nil
    ctx.assert(c.kind == 'joker' and c.rerolls == (tag == 'white' and st.k - 1 or math.floor((st.k - 1)/2))
      and (c.sticker == 'none') == clean, tag..': "'..l..'" holds '..STR_PACK(c))
    measure_finder(ctx, tag..' '..l)
    if not st.widest or label.config.W/label.scale > st.widest.w then st.widest = {k = st.k, label = l, w = label.config.W/label.scale} end
    if st.k == #want then
      ctx.log(('%s: %d labels at %.1f or more, the widest "%s"'):format(tag, #want, MIN_RATIO, st.widest.label))
      S.widest = st.widest
      return true
    end
    st.k, st.clicked, st.at = st.k + 1, arrow, love.timer.getTime()
    ctx.click('seedfinder_cycle', 'seedfinder_c1_extra_r')
    return false
  end}
end

return {
  {name = 'setup', run = function(ctx)
    ctx.assert(type(SeedFinder) == 'table' and SeedFinder.daily == daily, 'seedfinder.daily not loaded')
    love.mouse.setPosition(4, 4)
    if SaveSlots and SaveSlots.settings then SaveSlots.settings.auto_checkpoints = false end
    local usage = G.PROFILES[G.SETTINGS.profile].deck_usage
    usage.b_red = {count = 1, order = G.P_CENTERS.b_red.order, wins = {[1] = 1, [2] = 1, [3] = 1}, losses = {}}
    ctx.assert(get_deck_win_stake('b_red') == 3, 'Red Deck wins not as set')
    local rec = type(RunJournal) == 'table' and RunJournal.recorder
    ctx.assert(rec and rec.set_origin, 'RunJournal not loaded')
    local orig = rec.set_origin
    rec.set_origin = function(o, ...)
      S.origins[#S.origins + 1] = {o = o, stage = G.STAGE}
      return orig(o, ...)
    end
    S.deck = daily.today().deck
    local c = G.P_CENTERS[S.deck]
    S.was = {unlocked = c.unlocked, discovered = c.discovered}
    if S.deck == 'b_red' then
      ctx.log('the day\'s deck is Red Deck: no fallback to show today')
    else
      ctx.assert(not c.unlocked, S.deck..' is unlocked on a fresh profile')
    end
    return true
  end},

  -- 1. The Today row, the day's deck locked, then unlocked.
  click('open play', 'setup_run', nil, function() return not G.OVERLAY_MENU and G.STAGE == G.STAGES.MAIN_MENU end),
  click('find tab', 'change_tab', 'tab_but_Find', function() return uie('tab_but_Find') end),
  {name = 'today row, locked', timeout = 10, run = function(ctx)
    if not uie('seedfinder_today') or ctx.step_time() < 0.8 then return false end
    if not check_row(ctx, 'locked') then return false end
    measure_tab(ctx, 'no hits, the day\'s deck locked')
    return true
  end},
  {name = 'three hits', run = function(ctx)
    ctx.assert(ui.set_results(F, SEEDS))
    return true
  end},
  {name = 'today row with hits', timeout = 10, run = function(ctx)
    if not (uie('seedfinder_tabplay_1') and uie('seedfinder_tabplay_2') and uie('seedfinder_tabplay_3'))
      or ctx.step_time() < 0.8 then return false end
    local r = check_row(ctx, 'locked, three hits')
    if not r then return false end
    S.locked_row = r
    measure_tab(ctx, 'three hits, the day\'s deck locked')
    ctx.shot('today_row')
    return true
  end},
  {name = 'unlock the day\'s deck', run = function(ctx)
    local c = G.P_CENTERS[S.deck]
    c.unlocked, c.discovered = true, true
    ctx.assert(daily.deck_for() == S.deck, 'the day\'s deck is not playable once unlocked')
    return true
  end},
  click('find tab again', 'change_tab', 'tab_but_Find'),
  {name = 'today row, unlocked', timeout = 10, run = function(ctx)
    if ctx.step_time() < 0.8 or (S.deck ~= 'b_red' and uie('seedfinder_today_reason')) then return false end
    local r = check_row(ctx, 'unlocked')
    if not r then return false end
    ctx.assert(r.deck == r.day.deck and text_of('seedfinder_today_deck') == name_of('Back', r.day.deck),
      'the unlocked row does not show the day\'s deck')
    measure_tab(ctx, 'three hits, the day\'s deck unlocked')
    ctx.shot('today_unlocked')
    ctx.log('check: today row shows the day')
    return true
  end},

  -- 4. The reroll labels, from the tab's Open Seed Finder.
  click('open seed finder', 'seedfinder_open'),
  {name = 'finder from the tab', timeout = 10, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 1 then return false end
    measure_finder(ctx, 'from the Find tab')
    return true
  end},
  click('add clause', 'seedfinder_add', nil, function() return ui.is_open() end),
  cycle_to('c1_kind', 'Joker by ante'),
  read_labels('white', WHITE_LABELS),
  cycle_to('stake', function() return stake_name(4) end),
  {name = 'black stake', timeout = 10, run = function(ctx)
    if ctx.step_time() < 0.5 or not idle() or #(cycle_options('c1_extra') or {}) ~= #BLACK_LABELS then return false end
    ctx.assert(ui.current().stake == 4, 'the filter is not at Black Stake')
    return true
  end},
  cycle_to('c1_extra', BLACK_LABELS[1]),
  read_labels('black', BLACK_LABELS),
  cycle_to('c1_extra', function() return S.widest.label end),
  {name = 'widest label', timeout = 10, run = function(ctx)
    if ctx.step_time() < 0.5 or not idle() then return false end
    local args, label = extra_label()
    ctx.assert(label and label.strings[1].string == S.widest.label, 'not on the widest label')
    measure_finder(ctx, 'widest label '..S.widest.label)
    ctx.log(('check: reroll labels legible (widest "%s" at %.2f of the text scale)'):format(S.widest.label,
      label.scale/args.text_scale))
    ctx.shot('labels_black')
    return true
  end},
  -- Back in a step of its own: the shot is drawn at the end of the frame above.
  click('back to play', 'setup_run', 'overlay_menu_back_button'),
  click('find tab from the finder', 'change_tab', 'tab_but_Find', function() return uie('tab_but_Find') end),
  {name = 'tab with a joker filter', timeout = 10, run = function(ctx)
    if not uie('seedfinder_today') or ctx.step_time() < 0.8 then return false end
    if not check_row(ctx, 'after the Finder') then return false end
    measure_tab(ctx, 'a Black Stake joker filter, three hits')
    return true
  end},

  -- 2. Play blind.
  play_button('blind'),
  {name = 'blind daily starts', timeout = 20, run = function(ctx)
    if not (run_ready(ctx, S.blind.before.seed) or run_ready(ctx, S.blind.after.seed)) or ctx.step_time() < 1.5 then
      return false
    end
    S.day = check_run(ctx, S.blind, 'blind', daily.deck_for())
    ctx.assert(deck_key() == S.deck, 'the blind daily is not on the day\'s (unlocked) deck')
    return true
  end},
  click('pause', 'options', nil, function() return not G.OVERLAY_MENU end),
  click('seed oracle', 'seedoracle_open', nil, function() return G.OVERLAY_MENU end),
  {name = 'oracle locked', timeout = 10, run = function(ctx)
    if ctx.step_time() < 0.6 then return false end
    ctx.assert(not oracle_ui.is_open(), 'the Oracle overlay opened in a blind daily')
    ctx.assert(oracle_ui.lock_shown(), 'the Seed Oracle button did not show the lock note')
    ctx.shot('blind_locked')
    ctx.log('check: play blind starts the daily')
    return true
  end},
  {name = 'note back', run = function(ctx)
    if not idle() or ctx.step_time() < 0.3 then return false end
    local b = uie('overlay_menu_back_button')
    ctx.assert(b and b.config.button == 'options', 'the note\'s Back does not return to the pause menu')
    G.FUNCS[b.config.button](b)
    return true
  end},

  -- 3. Main menu, the deck locked again, Play routed.
  click('main menu button', 'go_to_menu', nil, function() return G.OVERLAY_MENU end),
  {name = 'main menu', timeout = 20, run = function(ctx)
    if G.STAGE ~= G.STAGES.MAIN_MENU or dismiss_unlock(ctx) then return false end
    if not (G.MAIN_MENU_UI ~= nil and G.OVERLAY_MENU == nil and idle() and ctx.step_time() > 1.5) then return false end
    local c = G.P_CENTERS[S.deck]
    c.unlocked, c.discovered = S.was.unlocked, S.was.discovered
    return true
  end},
  click('open play again', 'setup_run'),
  click('find tab, relocked', 'change_tab', 'tab_but_Find', function() return uie('tab_but_Find') end),
  {name = 'today row, relocked', timeout = 10, run = function(ctx)
    if not uie('seedfinder_today') or ctx.step_time() < 0.8 then return false end
    local r = check_row(ctx, 'relocked')
    if not r then return false end
    S.routed_deck = r.deck
    measure_tab(ctx, 'three hits, relocked, after a run')
    return true
  end},
  play_button('routed'),
  {name = 'routed daily starts', timeout = 20, run = function(ctx)
    if not (run_ready(ctx, S.routed.before.seed) or run_ready(ctx, S.routed.after.seed)) or ctx.step_time() < 1.5
      or not (type(G.GAME.bh_daily) == 'table' and G.GAME.bh_daily.mode == 'routed') then return false end
    local day = check_run(ctx, S.routed, 'routed', S.routed_deck)
    if S.deck ~= 'b_red' then
      ctx.assert(S.routed_deck == 'b_red', 'the relocked row did not show Red Deck')
      ctx.log('routed daily on the row\'s fallback: '..name_of('Back', S.routed_deck))
    end
    if day.date == S.day.date then
      ctx.assert(day.seed == S.day.seed, 'the routed daily\'s seed differs from the blind one\'s on the same day')
    else
      ctx.log('UTC midnight passed between the plays: '..S.day.date..' -> '..day.date)
    end
    return true
  end},
  click('pause (routed)', 'options', nil, function() return not G.OVERLAY_MENU end),
  click('seed oracle (routed)', 'seedoracle_open', nil, function() return G.OVERLAY_MENU end),
  {name = 'routed oracle', timeout = 10, run = function(ctx)
    if not oracle_ui.is_open() or ctx.step_time() < 0.8 then return false end
    ctx.assert(not oracle_ui.lock_shown(), 'the lock note is up in a routed daily')
    local model = SeedOracle.oracle.get()
    ctx.assert(model and model.seed == G.GAME.pseudorandom.seed, 'the Oracle predicts another seed')
    ctx.shot('routed_oracle')
    ctx.log('check: play routed starts the daily')
    return true
  end},
  click('back to pause', 'options'),
  {name = 'close pause', timeout = 10, run = function(ctx)
    if not ctx.find_button('seedoracle_open') or ctx.step_time() < 0.5 or not idle() then return false end
    G.FUNCS.exit_overlay_menu()
    return true
  end},

  -- 5. Sizes.
  {name = 'size unchanged', run = function(ctx)
    ctx.assert(#S.tabs >= 5 and #S.finders >= 20, #S.tabs..' Find tabs and '..#S.finders..' Finder overlays measured')
    ctx.log(('check: size unchanged (Find tab %.2fx%.2f in %d states, Finder overlay x %.2f..%.2f y %.2f..%.2f in %d)')
      :format(TAB_W, TAB_H, #S.tabs, FINDER.x1, FINDER.x2, FINDER.y1, FINDER.y2, #S.finders))
    return true
  end},
}
