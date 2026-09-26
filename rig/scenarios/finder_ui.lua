-- Finder UI (T-113, T-113c): the Seed Finder overlay driven through its buttons only.
--   0. The isolated profile unlocks Blue and Yellow Deck and records a stake-2 win
--      with Blue; every other deck but Red stays locked. The flags are set the way
--      a loaded profile has them (as practice.lua does): vanilla unlock_card would
--      also queue an "Unlocked!" overlay for the next run start.
--   1. Main menu: Options holds Seed Finder in the Customize Deck row, next to
--      Save Slots, Run Journal and the rest. Play -> the Find tab sits after Saves
--      and opens the Seed Finder.
--   2. The deck cycle offers exactly the unlocked decks; Red offers White Stake
--      only, Blue up to Green Stake (one above its best win), and going back to Red
--      from a Blue-only stake falls back to White.
--      -> "check: only unlocked decks and stakes"
--      The Charm Tag + Soul filter is built with clicks: a Boss clause first, then
--      Add clause, cycle the key to Charm Tag and the blind to Small; Add clause,
--      cycle its kind to Soul in pack (Arcana, tag skip); then the Boss clause's X
--      removes it and leaves the other two. -> "check: clause removed"
--      The model and filters.jkr must hold exactly that filter.
--      -> "check: filter built through UI"
--   3. Workers cycled to 4, Start; at >= 10 hits, Cancel: within 1 s every engine
--      thread has exited and the scanned count stays put. -> "check: cancel stops
--      workers". Page 2 of the hits fits the room. -> "check: results page 2 fits".
--      With hits shown the overlay keeps the x extent it had with the empty filter
--      and with the built one (T-316, 0.01). -> "check: overlay width unchanged by hits"
--      Play refuses the hit once its filter says a locked deck, then a locked stake.
--   4. Play on the first hit: the run has that seed, unseeded (stake and deck of the filter)
--      and the Small Blind's tag is the Charm Tag; the real Skip button opens the
--      Mega Arcana, which holds c_soul (when the Big tag is a Charm too, the Soul
--      may be in the Big pack: the Small pack is closed and Big skipped as well, see
--      the step). -> "check: hit plays and delivers"
--   5. Close the pack; the pause menu holds every suite button, fits the room and
--      opens the Seed Finder; Save as hunt on the SECOND hit, while the first hit's
--      run (and its checkpoint) is live, starts the second seed and its first
--      autosave becomes a kind 'hunt' slot with origin.filter_name.
--      -> "check: saved as hunt". The slot's run is the second hit's, not the
--      snapshot that was live before. -> "check: hunt holds the hit's run"
--   6. New filter with the widest key label (Delayed Gratification) still fits the
--      room; Delete brings the Charm filter back. Save Slots lists the hunt.
-- Screenshots: options_menu, find_tab, finder_empty, filter_built, searching,
-- cancelled, results_page2, play_refused, soul_pack, pause_menu, finder_pause, long_label, hunt_in_saveslots.
local ui = require('seedfinder.ui')
local filter = require('seedfinder.filter')
local engine = require('seedfinder.engine')
local fs = require('bhcore.fs')
local store = require('saveslots.store')

local S = {}

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU ~= true and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function name_of(set, key)
  return localize{type = 'name_text', set = set, key = key}
end

-- The value a cycle shows, read from its right arrow's ref_table (the cycle's args).
local function cycle_value(id)
  local arrow = uie('seedfinder_'..id..'_r')
  return arrow and arrow.config.ref_table.current_option_val
end

-- Clicks a cycle's right arrow until it shows `want` (one click per frame).
-- `want` is a string, or a function giving it (localized names exist only once the
-- game is up).
local function cycle_to(id, want, timeout)
  local label = type(want) == 'string' and want or '<localized>'
  return {name = 'cycle '..id..' to '..label, timeout = timeout or 20, run = function(ctx)
    if type(want) == 'function' then want = want() end
    local v = cycle_value(id)
    if v == want then ctx.log('cycle '..id..' = '..want); return true end
    if v == nil or G.CONTROLLER.locks.frame then return false end
    ctx.click('seedfinder_cycle', 'seedfinder_'..id..'_r')
    return false
  end}
end

local function click(label, button, id, wait)
  return {name = label, timeout = 10, run = function(ctx)
    if wait and not wait() then return false end
    if G.CONTROLLER.locks.frame then return false end
    return ctx.click(button, id)
  end}
end

-- Buttons of the live overlay in walk order, and each one's first index.
local function options_order()
  local out = {}
  local function walk(node)
    if type(node) ~= 'table' then return end
    if node.config and node.config.button then out[#out + 1] = node.config.button end
    for _, child in ipairs(node.children or {}) do walk(child) end
  end
  walk(G.OVERLAY_MENU and G.OVERLAY_MENU.UIRoot)
  local at = {}
  for i, b in ipairs(out) do at[b] = at[b] or i end
  return at, out
end

-- Seed Finder shares the Customize Deck row: the next button, at the same height.
local function check_options(ctx, where, needed)
  local at, all = options_order()
  ctx.log(where..' options: '..table.concat(all, ', '))
  for _, b in ipairs(needed) do ctx.assert(at[b], where..': '..b..' missing') end
  local n = 0
  for _, b in ipairs(all) do if b == 'seedfinder_open' then n = n + 1 end end
  ctx.assert(n == 1, where..': Seed Finder appears '..n..' times')
  ctx.assert(at.seedfinder_open == at.customize_deck + 1, where..': Seed Finder is not next to Customize Deck')
  local cd, sf = ctx.find_button('customize_deck'), ctx.find_button('seedfinder_open')
  ctx.assert(math.abs(cd.T.y - sf.T.y) < 0.01 and sf.T.x > cd.T.x, where..': Seed Finder is not in the Customize Deck row')
  local back = uie('overlay_menu_back_button')
  local first = ctx.find_button('settings')
  ctx.log(string.format('%s: buttons y %.2f..%.2f, room h %.2f', where, first.T.y, back.T.y + back.T.h, G.ROOM.T.h))
  ctx.assert(first.T.y >= 0 and back.T.y + back.T.h <= G.ROOM.T.h, where..': Settings or Back is off screen')
end

-- The overlay's panel fits the room. Returns its x extent.
local function check_fits(ctx, label)
  local root = G.OVERLAY_MENU.UIRoot.children[1]
  local back = uie('overlay_menu_back_button')
  local x1, x2, y1, y2 = root.T.x, root.T.x + root.T.w, root.T.y, back.T.y + back.T.h
  ctx.log(string.format('layout %s: panel x %.2f..%.2f y %.2f..%.2f in room %.2fx%.2f',
    label, x1, x2, y1, y2, G.ROOM.T.w, G.ROOM.T.h))
  ctx.assert(x1 >= 0 and y1 >= -0.2 and x2 <= G.ROOM.T.w and y2 <= G.ROOM.T.h, label..': the overlay does not fit the room')
  return x1, x2
end

-- T-316: the overlay keeps the x extent it had before any hit was listed (the
-- empty filter, and the built one) once hits are shown.
local function check_width(ctx, label, x1, x2)
  for _, was in ipairs{S.x_empty, S.x_built} do
    ctx.assert(math.abs(x1 - was[1]) <= 0.01 and math.abs(x2 - was[2]) <= 0.01, string.format(
      '%s: the overlay is x %.2f..%.2f with hits, %.2f..%.2f without (%s)', label, x1, x2, was[1], was[2], was.label))
  end
end

-- The live button `button` inside the blind-select panel of `kind`.
local function panel_button(kind, button)
  local box = G.blind_select_opts and G.blind_select_opts[string.lower(kind)]
  local function walk(node)
    if not node then return end
    if node.config and node.config.button == button then return node end
    for _, ch in pairs(node.children or {}) do
      local found = type(ch) == 'table' and walk(ch)
      if found then return found end
    end
  end
  return box and walk(box.UIRoot)
end

local function at_blind_select(seed)
  return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
    and G.GAME.pseudorandom and G.GAME.pseudorandom.seed == seed
    and G.GAME.round_resets.blind_tags and G.GAME.round_resets.blind_tags.Big ~= nil
    and not G.CONTROLLER.locks.load and not G.OVERLAY_MENU
end

local WANT = {
  {kind = 'tag', ante = 1, blind = 'Small', key = 'tag_charm'},
  {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true},
}

-- The labels a cycle offers.
local function cycle_options(id)
  local arrow = uie('seedfinder_'..id..'_r')
  return arrow and arrow.config.ref_table.options
end

local function status_text()
  local node = uie('seedfinder_status')
  return node and tostring(node.config.ref_table[node.config.ref_value]) or ''
end

local function same_clauses(got)
  if type(got) ~= 'table' or #got ~= #WANT then return false end
  for i, w in ipairs(WANT) do
    local g = got[i]
    for k, v in pairs(w) do if g[k] ~= v then return false end end
    for k in pairs(g) do if w[k] == nil then return false end end
  end
  return true
end

return {
  -- 0. Unlock two decks; a Blue win at stake 2 opens Blue's stakes up to 3
  --    (get_deck_win_stake + 1).
  {name = 'unlock decks', timeout = 5, run = function(ctx)
    for _, k in ipairs{'b_blue', 'b_yellow'} do
      G.P_CENTERS[k].unlocked, G.P_CENTERS[k].discovered = true, true
    end
    local usage = G.PROFILES[G.SETTINGS.profile].deck_usage
    usage.b_blue = {count = 1, order = G.P_CENTERS.b_blue.order, wins = {[1] = 1, [2] = 1}, losses = {}}
    ctx.assert(G.P_CENTERS.b_blue.unlocked and G.P_CENTERS.b_yellow.unlocked, 'the decks are not unlocked')
    ctx.assert(not G.P_CENTERS.b_green.unlocked, 'Green Deck is unlocked on a fresh profile')
    ctx.assert(get_deck_win_stake('b_blue') == 2 and get_deck_win_stake('b_red') == 0, 'deck wins not as set')
    return true
  end},
  -- 1. Main-menu Options and the Find tab.
  click('open options', 'options'),
  {name = 'options menu', timeout = 5, run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    check_options(ctx, 'main menu', {'settings', 'high_scores', 'runjournal_open', 'customize_deck', 'saveslots_open'})
    ctx.shot('options_menu')
    return true
  end},
  click('close options', 'exit_overlay_menu'),
  click('open play', 'setup_run', nil, function() return not G.OVERLAY_MENU end),
  {name = 'play tabs', timeout = 5, run = function(ctx)
    if not uie('tab_but_Find') or ctx.step_time() < 0.5 then return false end
    local tabs = {}
    for _, label in ipairs{'New Run', 'Continue', 'Saves', 'Find', 'Challenges'} do
      local b = uie('tab_but_'..label)
      ctx.assert(b, 'Play screen: no '..label..' tab')
      tabs[#tabs + 1] = b.T.x
    end
    for i = 2, #tabs do ctx.assert(tabs[i] > tabs[i - 1], 'Play screen tabs out of order') end
    return ctx.click('change_tab', 'tab_but_Find')
  end},
  {name = 'find tab', timeout = 5, run = function(ctx)
    if not uie('seedfinder_tab') or ctx.step_time() < 1 then return false end
    ctx.shot('find_tab')
    return true
  end},
  click('open from the Find tab', 'seedfinder_open'),

  -- 2. Build the filter.
  {name = 'finder open', timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 1 then return false end
    local x1, x2 = check_fits(ctx, 'main menu')
    S.x_empty = {x1, x2, label = 'empty filter'}
    ctx.assert(#ui.current().clauses == 0, 'a fresh profile starts with an empty filter')
    ctx.shot('finder_empty')
    local offered = {}
    for _, l in ipairs(cycle_options('deck')) do offered[l] = true end
    local n = 0
    for _, b in ipairs(G.P_CENTER_POOLS.Back) do
      local name = name_of('Back', b.key)
      ctx.assert((offered[name] or false) == (b.unlocked and true or false),
        name..(b.unlocked and ' is unlocked but not offered' or ' is locked but offered'))
      if offered[name] then n = n + 1 end
    end
    ctx.assert(n == 3 and offered[name_of('Back', 'b_blue')] and not offered[name_of('Back', 'b_green')],
      'deck cycle is not Red, Blue and Yellow: '..table.concat(cycle_options('deck'), ', '))
    local stakes = cycle_options('stake')
    ctx.assert(#stakes == 1 and stakes[1] == name_of('Stake', 'stake_white'),
      'Red Deck (no wins) offers stakes: '..table.concat(stakes, ', '))
    ctx.log('decks offered: '..table.concat(cycle_options('deck'), ', ')..'; Red stakes: '..table.concat(stakes, ', '))
    return true
  end},
  cycle_to('deck', function() return name_of('Back', 'b_blue') end),
  {name = 'blue stakes', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local stakes = cycle_options('stake')
    ctx.assert(#stakes == 3 and stakes[3] == name_of('Stake', G.P_CENTER_POOLS.Stake[3].key),
      'Blue Deck (won at stake 2) offers stakes: '..table.concat(stakes, ', '))
    ctx.log('Blue stakes: '..table.concat(stakes, ', '))
    return true
  end},
  cycle_to('stake', function() return name_of('Stake', G.P_CENTER_POOLS.Stake[3].key) end),
  cycle_to('deck', function() return name_of('Back', 'b_red') end),
  {name = 'only unlocked decks and stakes', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local f, stakes = ui.current(), cycle_options('stake')
    ctx.assert(f.deck == 'b_red' and f.stake == 1, 'back on Red the stake is '..tostring(f.stake))
    ctx.assert(#stakes == 1, 'Red Deck offers '..#stakes..' stakes after Blue')
    ctx.log('check: only unlocked decks and stakes')
    return true
  end},
  -- A Boss clause first, removed once the two real ones are built after it.
  click('add clause 1', 'seedfinder_add'),
  cycle_to('c1_kind', 'Boss'),
  click('add clause 2', 'seedfinder_add'),
  cycle_to('c2_key', function() return name_of('Tag', 'tag_charm') end, 30),
  cycle_to('c2_extra', 'Small'),
  click('add clause 3', 'seedfinder_add'),
  cycle_to('c3_kind', 'Soul in pack'),
  cycle_to('c3_key', 'Arcana, tag skip'),
  {name = 'three clauses', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local c = ui.current().clauses
    ctx.assert(#c == 3 and c[1].kind == 'boss' and uie('seedfinder_c3_kind_r'), 'not three clauses, Boss first')
    return ctx.click('seedfinder_remove', 'seedfinder_remove_1')
  end},
  {name = 'clause removed', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local c = ui.current().clauses
    ctx.assert(#c == 2 and same_clauses(c), 'X did not remove the Boss clause alone: '..tostring(STR_PACK(c)))
    ctx.assert(not uie('seedfinder_c3_kind_r') and cycle_value('c1_kind') == 'Skip tag'
      and cycle_value('c2_kind') == 'Soul in pack', 'the clause list still shows the removed clause')
    ctx.log('check: clause removed')
    return true
  end},
  cycle_to('workers', '4 workers'),
  {name = 'filter built', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local f = ui.current()
    ctx.assert(same_clauses(f.clauses), 'the filter is not Charm Tag (Small) + Soul in a tag Arcana: '
      ..tostring(STR_PACK(f.clauses)))
    ctx.assert(f.deck == 'b_red' and f.stake == 1 and f.mode == 'all', 'deck, stake or mode changed')
    local disk = fs.read_table(G.SETTINGS.profile..'/seedfinder/filters.jkr')
    ctx.assert(disk and disk.filters and same_clauses(disk.filters[disk.current].clauses),
      'filters.jkr does not hold the filter')
    S.filter_name = f.name
    local x1, x2 = check_fits(ctx, 'filter built')
    S.x_built = {x1, x2, label = 'filter built'}
    ctx.log('filter: '..f.name..' '..STR_PACK(f.clauses))
    ctx.log('check: filter built through UI')
    ctx.shot('filter_built')
    return true
  end},

  -- 3. Search, then cancel.
  click('start', 'seedfinder_start'),
  -- Hits for this filter come at about one per 1,000 seeds (the search stops by
  -- itself at 64), so Cancel is pressed in the frame after the 10th shows up (a
  -- shot is taken at the end of its frame, so it gets a frame of its own).
  {name = 'ten hits', timeout = 90, run = function(ctx)
    local s = ui.search()
    if not (s and (#s.found >= 10 or not s.running)) then return false end
    ctx.assert(s.running, 'the search stopped by itself before Cancel: '..tostring(s.error)..' / '..#s.found..' hits')
    S.hit, S.hit2 = s.found[1], s.found[2]
    ctx.assert(engine.alive(s.handle) == 4, 'expected 4 live workers, have '..engine.alive(s.handle))
    ctx.log(string.format('search: %d scanned, %d seeds/s, %d hits, first %s', s.scanned, s.rate, #s.found, S.hit))
    ctx.shot('searching')
    return true
  end},
  {name = 'cancel', timeout = 1, run = function(ctx)
    local s = ui.search()
    ctx.assert(s.running, 'the search stopped by itself before Cancel: '..#s.found..' hits')
    ctx.assert(engine.alive(s.handle) == 4, 'workers exited before Cancel')
    ctx.assert(ctx.click('seedfinder_cancel'), 'no Cancel button while searching')
    S.cancel_t, S.handle = love.timer.getTime(), s.handle
    return true
  end},
  -- Every engine thread has returned within 1 s of Cancel (sampled every frame: a
  -- sample later than 1 s with a live thread fails), and then neither the overlay's
  -- count nor the engine's own grows for a second.
  {name = 'cancel stops workers', timeout = 5, run = function(ctx)
    local s, now = ui.search(), love.timer.getTime()
    ctx.assert(s.handle == S.handle, 'the search handle changed')
    if not S.stopped_after then
      local alive = engine.alive(S.handle)
      if alive > 0 then
        ctx.assert(now - S.cancel_t <= 1, string.format('%d worker threads still running %.2f s after Cancel',
          alive, now - S.cancel_t))
        return false
      end
      S.stopped_after, S.stop_t = now - S.cancel_t, now
      S.scanned0, S.engine0 = s.scanned, engine.poll(S.handle).scanned
      return false
    end
    if now - S.stop_t < 1 then return false end
    local p = engine.poll(S.handle)
    ctx.assert(not s.running and s.cancelled and p.done, 'the search is not cancelled')
    ctx.assert(s.scanned == S.scanned0 and p.scanned == S.engine0, string.format(
      'scanned kept growing after Cancel: overlay %d -> %d, engine %d -> %d', S.scanned0, s.scanned, S.engine0, p.scanned))
    ctx.log(string.format('workers all exited %.2f s after Cancel; scanned stays %d', S.stopped_after, s.scanned))
    ctx.log('check: cancel stops workers')
    return true
  end},
  {name = 'cancelled', timeout = 5, run = function(ctx)
    local s = ui.search()
    if s.running or ctx.step_time() < 0.5 then return false end
    ctx.assert(s.cancelled, 'the search ended without Cancel')
    ctx.assert(uie('seedfinder_play_1'), 'no Play button on the first hit')
    ctx.assert(#s.found >= 9 and uie('seedfinder_hits_page_r'), 'fewer than 9 hits, or no page cycle')
    ctx.log('search cancelled after '..s.scanned..' seeds, '..#s.found..' hits: '..table.concat(s.found, ' '))
    ctx.shot('cancelled')
    return ctx.click('seedfinder_cycle', 'seedfinder_hits_page_r')
  end},
  {name = 'results page 2', timeout = 5, run = function(ctx)
    if not uie('seedfinder_play_9') or ctx.step_time() < 1 then return false end
    ctx.assert(not uie('seedfinder_play_1') and uie('seedfinder_hunt_9'), 'page 2 still shows page 1')
    ctx.assert(cycle_value('hits_page'):match('^Page 2/'), 'page cycle says '..tostring(cycle_value('hits_page')))
    local x1, x2 = check_fits(ctx, 'results page 2')
    check_width(ctx, 'results page 2', x1, x2)
    ctx.log(string.format('check: overlay width unchanged by hits (x %.2f..%.2f, without hits %.2f..%.2f)',
      x1, x2, S.x_empty[1], S.x_empty[2]))
    ctx.shot('results_page2')
    ctx.log('check: results page 2 fits')
    return ctx.click('seedfinder_cycle', 'seedfinder_hits_page_l')
  end},
  -- Play refuses a filter this profile can't play (filters.jkr can hold one from
  -- another profile): the live search's filter is pointed at a locked deck, then at
  -- a stake Red Deck hasn't reached, and put back.
  {name = 'play refused: locked deck', timeout = 5, run = function(ctx)
    if not uie('seedfinder_play_1') or ctx.step_time() < 0.5 or G.CONTROLLER.locks.frame then return false end
    ui.search().filter.deck = 'b_green'
    return ctx.click('seedfinder_play', 'seedfinder_play_1')
  end},
  {name = 'play refused: locked stake', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(G.STAGE == G.STAGES.MAIN_MENU and ui.is_open(), 'Play started a locked deck')
    ctx.assert(status_text():find('Green Deck is locked', 1, true), 'no alert: status "'..status_text()..'"')
    ctx.log('locked deck: '..status_text())
    local f = ui.search().filter
    f.deck, f.stake = 'b_red', 2
    return ctx.click('seedfinder_play', 'seedfinder_play_1')
  end},
  {name = 'play refused', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(G.STAGE == G.STAGES.MAIN_MENU and ui.is_open(), 'Play started a locked stake')
    ctx.assert(status_text():find('is locked for', 1, true), 'no alert: status "'..status_text()..'"')
    ctx.log('locked stake: '..status_text())
    ctx.shot('play_refused')
    ui.search().filter.stake = 1
    return true
  end},

  -- 4. Play the first hit.
  click('play hit 1', 'seedfinder_play', 'seedfinder_play_1'),
  -- The filter's Soul clause is soul_in_pack from_tag, whose policy skips every
  -- Charm blind, Small first (filter.lua header): when the Big tag is a Charm Tag
  -- too, the Soul may be in the Big pack. eval's details name the blind (read only
  -- to know which pack to check; the filter itself was built by clicks). The Small
  -- Blind is always skipped first through the real Skip button; a Small pack
  -- without the Soul is closed unopened and Big is skipped too.
  {name = 'hit run', timeout = 30, run = function(ctx)
    if not at_blind_select(S.hit) or ctx.step_time() < 1 then return false end
    ctx.assert(not G.GAME.seeded and G.GAME.stake == 1 and G.GAME.selected_back.name == 'Red Deck',
      'not an unseeded stake-1 Red Deck run')
    ctx.assert(G.GAME.round_resets.blind_tags.Small == 'tag_charm',
      S.hit..': Small tag is '..tostring(G.GAME.round_resets.blind_tags.Small))
    local ok, details = filter.eval_seed(ui.search().filter, S.hit)
    ctx.assert(ok, S.hit..': the filter does not hold for the hit')
    S.soul = details.results[2]
    ctx.log(string.format('%s: Soul predicted in the %s pack, slot %d', S.hit, S.soul.blind, S.soul.index))
    S.phase, S.frames = 'skip', 0
    return true
  end},
  {name = 'hit plays and delivers', timeout = 60, run = function(ctx)
    S.frames = S.frames + 1
    local function go(phase) S.phase, S.frames = phase, 0 end
    if S.phase == 'skip' then
      if G.STATE ~= G.STATES.BLIND_SELECT or S.frames < 3 or G.CONTROLLER.locks.skip_blind then return false end
      local btn = panel_button(G.GAME.blind_on_deck, 'skip_blind')
      if not btn then return false end
      S.skipped = G.GAME.blind_on_deck
      G.FUNCS.skip_blind(btn)
      go('pack')
    elseif S.phase == 'pack' then
      if not (G.STATE == G.STATES.TAROT_PACK and G.pack_cards and G.pack_cards.cards
        and #G.pack_cards.cards >= (G.GAME.pack_size or 1)) then return false end
      -- The headless frame rate is low and dt is capped, so the cards take many frames
      -- to land: extra Game:update passes (as finder_filter does) let them, for the shot.
      S.dealt = (S.dealt or 0) + 1
      if S.dealt < 12 then
        for _ = 1, 8 do G:update(1/20) end
        return false
      end
      S.dealt = nil
      local got, soul = {}, false
      for i, c in ipairs(G.pack_cards.cards) do
        got[i] = c.config.center.key
        soul = soul or got[i] == 'c_soul'
      end
      ctx.log(S.hit..' '..S.skipped..' Mega Arcana: '..table.concat(got, ' '))
      ctx.assert(G.GAME.pack_size == 5 and G.GAME.pack_choices == 2, 'not a Mega Arcana')
      if S.skipped ~= S.soul.blind then
        ctx.assert(S.skipped == 'Small', S.hit..': ran past the '..S.soul.blind..' blind')
        S.after_close = 'skip'
        go('close')
        return false
      end
      ctx.assert(soul and got[S.soul.index] == 'c_soul', S.hit..': no c_soul at slot '..S.soul.index)
      ctx.shot('soul_pack')
      ctx.log('check: hit plays and delivers')
      S.after_close = 'closed'
      go('close')
    elseif S.phase == 'close' then
      -- Skip is enabled once the pack's cards are dealt (a frame or two after the shot).
      if S.frames < 2 or G.CONTROLLER.locks.frame then return false end
      if ctx.click('skip_booster') then go('closing') end
    elseif S.phase == 'closing' then
      if G.booster_pack or S.frames < 3 then return false end
      go(S.after_close)
    elseif S.phase == 'closed' then
      if G.booster_pack or G.STATE ~= G.STATES.BLIND_SELECT or G.CONTROLLER.locks.skip_blind
        or S.frames < 90 then return false end
      return ctx.click('options')
    end
    return false
  end},

  -- 5. Save as hunt from the pause menu.
  {name = 'pause menu', timeout = 5, run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    check_options(ctx, 'pause menu', {'settings', 'saveslots_open', 'seedoracle_open', 'runjournal_open',
      'setup_run', 'go_to_menu', 'customize_deck'})
    ctx.shot('pause_menu')
    return true
  end},
  click('open from pause', 'seedfinder_open'),
  {name = 'finder from pause', timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 1 then return false end
    check_fits(ctx, 'pause')
    ctx.shot('finder_pause')
    S.slots_before = #store.list({kind = 'hunt'})
    return true
  end},
  -- A stale hunt would hold the snapshot live before its run started: that is the
  -- first hit's run, a different seed, so the two can't be confused.
  {name = 'save hit 2 as hunt', timeout = 5, run = function(ctx)
    if G.CONTROLLER.locks.frame then return false end
    local snap = SaveSlots.checkpoint.get()
    ctx.assert(S.hit2 and S.hit2 ~= S.hit, 'no second hit distinct from the first')
    ctx.assert(G.GAME.pseudorandom.seed == S.hit and snap and snap.GAME.pseudorandom.seed == S.hit,
      'the live run and its checkpoint are not the first hit\'s')
    return ctx.click('seedfinder_hunt', 'seedfinder_hunt_2')
  end},
  {name = 'hunt saved', timeout = 30, run = function(ctx)
    local h = ui.hunt()
    ctx.assert(h and h.seed == S.hit2, 'no hunt pending for '..tostring(S.hit2))
    ctx.assert(h.state ~= 'failed', 'hunt failed: '..tostring(h.err))
    if h.state ~= 'saved' or ctx.step_time() < 1 then return false end
    local hunts = store.list({kind = 'hunt'})
    ctx.assert(#hunts == S.slots_before + 1, 'expected one new hunt slot, have '..#hunts)
    local e = hunts[1]
    ctx.assert(e.id == h.id, 'the newest hunt is not the one saved')
    local o = e.meta.origin
    ctx.assert(type(o) == 'table' and o.kind == 'finder' and o.filter_name == S.filter_name
      and type(o.filter) == 'table' and same_clauses(o.filter.clauses), 'hunt origin wrong')
    ctx.log(string.format('hunt slot %s "%s": seed %s, origin %s', e.id, e.name, tostring(e.summary.seed), o.filter_name))
    local run = store.read(e.id)
    local seed = run and run.GAME and run.GAME.pseudorandom and run.GAME.pseudorandom.seed
    ctx.assert(e.summary.seed == S.hit2 and seed == S.hit2, string.format(
      'hunt slot holds %s (summary %s), not the hit %s (the run before was %s)',
      tostring(seed), tostring(e.summary.seed), S.hit2, S.hit))
    ctx.assert(e.summary.ante == 1 and run.STATE == G.STATES.BLIND_SELECT
      and run.GAME.round_resets.blind_states.Small == 'Select', 'hunt slot is not the first blind select of '..S.hit2)
    ctx.assert(G.GAME.pseudorandom.seed == S.hit2, 'the live run is not the hunted hit')
    ctx.log('check: saved as hunt')
    ctx.log('check: hunt holds the hit\'s run')
    return true
  end},
  -- 6. The widest label still fits: a new filter with Delayed Gratification in the
  --    shop, then Delete brings the Charm filter back.
  {name = 'reopen finder', timeout = 10, run = function(ctx)
    if not at_blind_select(S.hit2) or ctx.step_time() < 1 then return false end
    return ctx.click('options')
  end},
  click('finder again', 'seedfinder_open', nil, function() return G.OVERLAY_MENU end),
  click('new filter', 'seedfinder_new', nil, function() return ui.is_open() end),
  click('add clause', 'seedfinder_add', nil, function() return #ui.current().clauses == 0 end),
  cycle_to('c1_kind', 'Shop joker'),
  cycle_to('c1_key', function() return name_of('Joker', 'j_delayed_grat') end, 60),
  {name = 'long label fits', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(ui.current().clauses[1].key == 'j_delayed_grat', 'the clause is not Delayed Gratification')
    check_fits(ctx, 'long label')
    ctx.shot('long_label')
    return true
  end},
  click('delete filter', 'seedfinder_delete'),
  {name = 'charm filter back', timeout = 5, run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.assert(same_clauses(ui.current().clauses), 'Delete did not bring the Charm filter back')
    local disk = fs.read_table(G.SETTINGS.profile..'/seedfinder/filters.jkr')
    ctx.assert(disk and #disk.filters == 1, 'filters.jkr still holds the deleted filter')
    return ctx.click('options')
  end},
  click('save slots', 'saveslots_open', nil, function() return G.OVERLAY_MENU end),
  {name = 'hunt in save slots', timeout = 5, run = function(ctx)
    if ctx.step_time() < 1 then return false end
    ctx.shot('hunt_in_saveslots')
    return true
  end},
}
