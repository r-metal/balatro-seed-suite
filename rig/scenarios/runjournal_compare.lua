-- RunJournal same-seed comparison (T-330): one seed played twice to different depths
-- shows up in the overlay's Same seed tab, compared ante by ante.
--   1. Run A, seed RJCOMPARE1 (stake 1): ante 1 won (Small, Big, Boss, each won with
--      the target forced to 1, as runjournal.lua does), ante 2 Small lost with one
--      hand left: game over.
--   2. Run B, the same seed: antes 1 and 2 won, ante 3 Small lost: game over.
--      Both records are on disk; stats.by_seed groups them, stats.compare gives 3
--      rows diverging at ante 2 (A lost, B won). -> "check: two runs of one seed"
--   3. Main menu, Options, Run Journal, Same seed tab: the seed's button is there,
--      the table's money and best-hand cells match stats.compare's rows, and the
--      divergence line names ante 2. The overlay fits the room at the Overview's size.
--      -> "check: same seed view matches compare"
-- Speed: vsync off, GAMESPEED 64, extra Game:update passes. Screenshots: game_over_a,
-- game_over_b, same_seed.
local recorder = require('runjournal.recorder')
local stats = require('runjournal.stats')
local ui = require('runjournal.ui')

local SEED = 'RJCOMPARE1'
local S = {}

local function turbo()
  for _ = 1, 4 do G:update(1/20) end
end

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function select_blind(kind)
  return {name = 'select '..kind, timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.BLIND_SELECT or not G.blind_select or ctx.step_time() < 0.3 then return false end
    local on_deck = G.GAME.blind_on_deck
    local box = G.blind_select_opts and on_deck and G.blind_select_opts[string.lower(on_deck)]
    if on_deck ~= kind then return false end
    local btn = box and box:get_UIE_by_ID('select_blind_button')
    if not (btn and btn.config.button == 'select_blind') then return false end
    G.FUNCS.select_blind(btn)
    return true
  end}
end

-- Plays up to five cards against `target`, with `hands_left` forced when given.
local function play(label, target, hands_left)
  return {name = 'play '..label, timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or ctx.step_time() < 0.2
      or G.CONTROLLER.locks.frame then return false end
    G.GAME.blind.chips = target
    G.GAME.blind.chip_text = number_format(target)
    if hands_left then G.GAME.current_round.hands_left = hands_left end
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

local function start(label)
  return {
    {name = 'start '..label, run = function(ctx)
      ctx.start_run{seed = SEED, stake = 1}
      return true
    end},
    {name = label..' blind select', timeout = 20, run = function(ctx)
      turbo()
      if not (G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select
        and G.GAME.pseudorandom.seed == SEED and G.GAME.round_resets.ante == 1) or ctx.step_time() < 1 then
        return false
      end
      local r = recorder.current()
      ctx.assert(r and r.seed == SEED and r.run_id ~= S.a, 'no new live record for '..label)
      S[label] = r.run_id
      ctx.log(label..' run id '..r.run_id)
      return true
    end},
  }
end

local function win_ante()
  local out = {}
  for _, kind in ipairs({'Small', 'Big', 'Boss'}) do
    for _, s in ipairs({select_blind(kind), play(kind, 1), cash_out(), shop()}) do out[#out + 1] = s end
  end
  return out
end

local function lose_small(label)
  return {
    select_blind('Small'),
    play('Small (lose)', 1e12, 1),
    {name = label..' game over', timeout = 30, run = function(ctx)
      turbo()
      if G.STATE ~= G.STATES.GAME_OVER or not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
      ctx.shot('game_over_'..label)
      return true
    end},
  }
end

local steps = {
  {name = 'speed up', run = function()
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    return true
  end},
}

local function add(list) for _, s in ipairs(list) do steps[#steps + 1] = s end end

add(start('a'))
add(win_ante())
add(lose_small('a'))
add(start('b'))
add(win_ante())
add(win_ante())
add(lose_small('b'))

local function money(v) return v and ('$'..tostring(v)) or '-' end
local function hand_name(h)
  if h == nil then return '-' end
  local ok, s = pcall(localize, h, 'poker_hands')
  if ok and type(s) == 'string' and s ~= '' and s ~= 'ERROR' then return s end
  return tostring(h)
end

add({
  {name = 'two runs of one seed', run = function(ctx)
    local a, b = recorder.read(S.a), recorder.read(S.b)
    ctx.assert(a and b, 'records on disk: '..tostring(S.a)..', '..tostring(S.b))
    ctx.assert(a.won == false and a.final_ante == 2, 'run a: won '..tostring(a.won)..' ante '..tostring(a.final_ante))
    ctx.assert(b.won == false and b.final_ante == 3, 'run b: won '..tostring(b.won)..' ante '..tostring(b.final_ante))
    local groups = stats.by_seed()
    ctx.assert(#groups == 1 and groups[1].seed == SEED and #groups[1].runs == 2, 'by_seed: '..#groups..' groups')
    ctx.assert(groups[1].runs[1].run_id == S.a and groups[1].runs[2].run_id == S.b, 'by_seed order')
    local c = assert(stats.compare(S.a, S.b))
    for _, r in ipairs(c.rows) do
      ctx.log(string.format('ante %d: A %s %s %s | B %s %s %s', r.ante, tostring(r.dollars_a),
        tostring(r.best_hand_a), tostring(r.outcome_a), tostring(r.dollars_b), tostring(r.best_hand_b),
        tostring(r.outcome_b)))
    end
    ctx.assert(#c.rows == 3, #c.rows..' compare rows')
    local want = {{'won', 'won'}, {'lost', 'won'}, {nil, 'lost'}}
    for i, w in ipairs(want) do
      local r = c.rows[i]
      ctx.assert(r.ante == i and r.outcome_a == w[1] and r.outcome_b == w[2],
        'ante '..i..' outcomes '..tostring(r.outcome_a)..'/'..tostring(r.outcome_b))
      ctx.assert(type(r.best_hand_b) == 'string' and type(r.dollars_b) == 'number', 'ante '..i..' run b cells')
    end
    ctx.assert(type(c.rows[2].best_hand_a) == 'string' and c.rows[3].dollars_a == nil, 'run a cells')
    ctx.assert(c.diverge == 2, 'diverge '..tostring(c.diverge))
    S.cmp = c
    ctx.log('check: two runs of one seed')
    return true
  end},
  {name = 'main menu', run = function(ctx) return ctx.click('go_to_menu') end},
  {name = 'options', timeout = 20, run = function(ctx)
    if not (G.STAGE == G.STAGES.MAIN_MENU and G.MAIN_MENU_UI) or G.OVERLAY_MENU or ctx.step_time() < 1.5 then
      return false
    end
    G.FUNCS.options()
    return true
  end},
  {name = 'open run journal', timeout = 5, run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    return ctx.click('runjournal_open')
  end},
  {name = 'same seed tab', timeout = 5, run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 0.5 then return false end
    local e = ctx.find_button('change_tab', 'tab_but_Same seed')
    if not e then return false end
    -- The Overview's panel: every tab keeps one size, this one included.
    local root = G.OVERLAY_MENU.UIRoot.children[1]
    S.overview = {root.T.x, root.T.x + root.T.w}
    e:click()
    return true
  end},
  {name = 'same seed view', timeout = 5, run = function(ctx)
    if ctx.step_time() < 1 then return false end
    ctx.assert(ctx.find_button('runjournal_same_seed', 'runjournal_seed_'..SEED), 'no button for '..SEED)
    local shown = ui.compared()
    ctx.assert(shown and shown.seed == SEED and shown.a.run_id == S.a and shown.b.run_id == S.b,
      'the tab compares another pair')
    local function text_of(id)
      local n = uie(id)
      ctx.assert(n, 'no UI element '..id)
      return n.config.text
    end
    for _, r in ipairs(S.cmp.rows) do
      local n = r.ante
      for _, pair in ipairs({
        {'runjournal_cmp_dollars_a_'..n, money(r.dollars_a)}, {'runjournal_cmp_dollars_b_'..n, money(r.dollars_b)},
        {'runjournal_cmp_hand_a_'..n, hand_name(r.best_hand_a)}, {'runjournal_cmp_hand_b_'..n, hand_name(r.best_hand_b)},
      }) do
        local got = text_of(pair[1])
        ctx.assert(got == pair[2], pair[1]..' shows '..tostring(got)..', compare says '..pair[2])
      end
    end
    local d = text_of('runjournal_cmp_diverge')
    ctx.assert(d:find('ante 2', 1, true), 'divergence line: '..tostring(d))
    ctx.log('divergence line: '..d)
    local top, back = uie('tab_but_Overview'), uie('overlay_menu_back_button')
    local root = G.OVERLAY_MENU.UIRoot.children[1]
    local x1, x2, y1, y2 = root.T.x, root.T.x + root.T.w, top.T.y, back.T.y + back.T.h
    ctx.log(string.format('layout same seed: panel x %.2f..%.2f y %.2f..%.2f in room %.2fx%.2f',
      x1, x2, y1, y2, G.ROOM.T.w, G.ROOM.T.h))
    ctx.assert(x1 >= 0 and y1 >= 0 and x2 <= G.ROOM.T.w and y2 <= G.ROOM.T.h, 'the overlay does not fit the room')
    ctx.assert(math.abs(x1 - S.overview[1]) < 0.01 and math.abs(x2 - S.overview[2]) < 0.01,
      string.format('the panel changed size: Overview x %.2f..%.2f', S.overview[1], S.overview[2]))
    ctx.shot('same_seed')
    ctx.log('check: same seed view matches compare')
    return true
  end},
})

return steps
