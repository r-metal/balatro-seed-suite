-- RunJournal jokers offered (T-372a): bh-core's shop_reroll event and the record's
-- offered counts, in a real seeded run.
--   1. Subscribe to shop_reroll (each payload kept with G.shop_jokers' keys and
--      G.GAME.dollars read live as it fires), start seeded run SEED (stake 1).
--   2. Select the Small Blind, win it (its target forced to 1), cash out. In the first
--      shop, once the shelf is placed, note the entry row (key and set of every card in
--      G.shop_jokers) and set G.GAME.dollars to 50.
--   3. Reroll twice through the real Reroll button (ctx.click('reroll_shop'), the
--      element vanilla's can_reroll arms), each once the previous one has settled
--      (the reroll lock released), noting each rerolled row the same way.
--      -> "check: reroll event once per reroll": 2 events, each payload's cards equal
--         to G.shop_jokers' keys at that moment and to the settled row; ante, round,
--         and dollars = the money before the click minus the reroll cost.
--      -> "check: offered counts match the shop": the live record's offered, and the
--         record on disk, equal the Joker-set cards (card.ability.set) of the entry
--         row plus both rerolled rows. SEED is pinned so those 6 cards hold Jokers
--         and a non-Joker (a Tarot or Planet), so the skip is exercised too.
--   4. Open the Seed Oracle with ctrl+o in that shop: it recomputes, and its model of
--      "this shop" holds the simulator's rerolls (made on a copy, in the sandbox).
--      Close it and let the queue run.
--      -> "check: sim does not emit": still 2 shop_reroll events, offered unchanged,
--         the shelf unchanged.
-- Speed: vsync off, GAMESPEED 64, extra Game:update passes (journal: scripting fast).
-- Screenshots: shop_entry, shop_reroll2, oracle.
local events = require('bhcore.events')
local recorder = require('runjournal.recorder')
local oracle = require('seedoracle.oracle')
local oui = require('seedoracle.ui')

local SEED = 'OFFERED1'
local S = {got = {}, rows = {}}

local function turbo()
  for _ = 1, 4 do G:update(1/20) end
end

local function hotkey()
  G.CONTROLLER.held_keys['lctrl'] = true
  G.CONTROLLER:key_press_update('o', 0)
  G.CONTROLLER.held_keys['lctrl'] = nil
end

-- The shelf as it stands: {keys = {...}, sets = {...}}, in slot order.
local function row()
  local out = {keys = {}, sets = {}}
  for i, c in ipairs(G.shop_jokers.cards) do
    out.keys[i] = c.config.center.key
    out.sets[i] = c.ability.set
  end
  return out
end

-- The shop is placed and idle: shelf stocked, packs out, no reroll in flight.
local function shop_ready()
  return G.STATE == G.STATES.SHOP and G.shop and G.shop_jokers and G.shop_booster
    and #G.shop_booster.cards == 2 and #G.shop_jokers.cards == G.GAME.shop.joker_max
    and not G.CONTROLLER.locks.toggle_shop and not G.CONTROLLER.locks.shop_reroll
    and not G.CONTROLLER.locks.use
end

-- `t` as sorted 'key=n' pairs ('-' for nil).
local function counts(t)
  if type(t) ~= 'table' then return '-' end
  local out = {}
  for k, n in pairs(t) do out[#out + 1] = k..'='..tostring(n) end
  table.sort(out)
  return table.concat(out, ' ')
end

local function reroll(n)
  return {name = 'reroll '..n, run = function(ctx)
    turbo()
    if not shop_ready() or ctx.step_time() < 0.3 then return false end
    S.before = {dollars = G.GAME.dollars, cost = G.GAME.current_round.reroll_cost, events = #S.got}
    ctx.assert(S.before.events == n - 1, 'shop_reroll events before reroll '..n..': '..S.before.events)
    return ctx.click('reroll_shop')
  end}
end

local function rerolled(n, label)
  return {name = 'rerolled '..n, timeout = 20, run = function(ctx)
    turbo()
    if ctx.step_time() > 5 and not S.waited then
      -- Once, for a timeout's log: what the wait is stuck on.
      S.waited = true
      ctx.log(string.format('still waiting: events %d, state %s, shop %s, row %d/%s, locks %s %s %s',
        #S.got, tostring(G.STATE), tostring(G.shop ~= nil), G.shop_jokers and #G.shop_jokers.cards or -1,
        tostring(G.GAME.shop and G.GAME.shop.joker_max), tostring(G.CONTROLLER.locks.shop_reroll),
        tostring(G.CONTROLLER.locks.use), tostring(G.CONTROLLER.locks.toggle_shop)))
    end
    if #S.got < n or not shop_ready() or ctx.step_time() < 0.3 then return false end
    local g = S.got[n]
    g.want_dollars = S.before.dollars - S.before.cost
    S.rows[n + 1] = row()
    ctx.log(string.format('reroll %d row: %s (%s)', n, table.concat(S.rows[n + 1].keys, ' '),
      table.concat(S.rows[n + 1].sets, ' ')))
    if label then ctx.shot(label) end
    return true
  end}
end

return {
  {name = 'subscribe', run = function(ctx)
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    love.mouse.setPosition(4, 4)
    events.on('shop_reroll', function(p)
      S.got[#S.got + 1] = {p = p, live = table.concat(row().keys, ' '), dollars = G.GAME.dollars}
    end)
    ctx.start_run{seed = SEED}
    return true
  end},
  {name = 'blind select', timeout = 20, run = function(ctx)
    turbo()
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
      and ctx.step_time() > 0.3
  end},
  {name = 'select small', timeout = 20, run = function(ctx)
    turbo()
    local box = G.blind_select_opts and G.blind_select_opts.small
    local btn = box and box:get_UIE_by_ID('select_blind_button')
    if not (btn and btn.config.button == 'select_blind') then return false end
    G.FUNCS.select_blind(btn)
    return true
  end},
  {name = 'play small', timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or ctx.step_time() < 0.2
      or G.CONTROLLER.locks.frame then return false end
    G.GAME.blind.chips = 1
    G.GAME.blind.chip_text = number_format(1)
    for i = 1, math.min(5, #G.hand.cards) do G.hand:add_to_highlighted(G.hand.cards[i]) end
    ctx.assert(#G.hand.highlighted > 0, 'no cards highlighted')
    G.FUNCS.play_cards_from_highlighted()
    return true
  end},
  {name = 'cash out', timeout = 30, run = function(ctx)
    turbo()
    if G.STATE ~= G.STATES.ROUND_EVAL or ctx.step_time() < 0.2 then return false end
    return ctx.click('cash_out')
  end},
  {name = 'first shop', timeout = 30, run = function(ctx)
    turbo()
    if not shop_ready() or ctx.step_time() < 0.5 then return false end
    S.rows[1] = row()
    ctx.log(string.format('entry row: %s (%s)', table.concat(S.rows[1].keys, ' '),
      table.concat(S.rows[1].sets, ' ')))
    G.GAME.dollars = 50
    ctx.shot('shop_entry')
    return true
  end},
  reroll(1),
  rerolled(1),
  reroll(2),
  rerolled(2, 'shop_reroll2'),

  {name = 'events', run = function(ctx)
    ctx.assert(#S.got == 2, 'shop_reroll fired '..#S.got..' times for 2 rerolls')
    for n = 1, 2 do
      local g, want = S.got[n], S.rows[n + 1]
      local cards = type(g.p.cards) == 'table' and table.concat(g.p.cards, ' ') or tostring(g.p.cards)
      ctx.log(string.format('event %d: cards %s, live %s, ante %s, round %s, dollars %s',
        n, cards, g.live, tostring(g.p.ante), tostring(g.p.round), tostring(g.p.dollars)))
      ctx.assert(cards == g.live, 'event '..n..': cards '..cards..' vs the shelf as it fired '..g.live)
      ctx.assert(cards == table.concat(want.keys, ' '), 'event '..n..': cards vs the settled row')
      ctx.assert(#g.p.cards == G.GAME.shop.joker_max, 'event '..n..': a full row')
      ctx.assert(g.p.ante == G.GAME.round_resets.ante and g.p.round == G.GAME.round, 'event '..n..': ante/round')
      ctx.assert(g.p.dollars == g.dollars and g.p.dollars == g.want_dollars,
        string.format('event %d: dollars %s, live %s, want %s', n, tostring(g.p.dollars),
          tostring(g.dollars), tostring(g.want_dollars)))
    end
    ctx.assert(S.rows[2].keys[1] ~= nil and table.concat(S.rows[1].keys, ' ') ~= table.concat(S.rows[2].keys, ' '),
      'the first reroll changed nothing on the shelf')
    ctx.log('check: reroll event once per reroll')
    return true
  end},
  {name = 'offered', run = function(ctx)
    local want, jokers, others = {}, 0, 0
    for _, r in ipairs(S.rows) do
      for i, key in ipairs(r.keys) do
        if r.sets[i] == 'Joker' then
          want[key] = (want[key] or 0) + 1
          jokers = jokers + 1
        else
          others = others + 1
        end
      end
    end
    ctx.log(string.format('shop rows: %d Jokers, %d other cards; want %s', jokers, others, counts(want)))
    ctx.assert(#S.rows == 3 and jokers > 0 and others > 0,
      'SEED no longer shows Jokers and a non-Joker in its three rows')
    local live = recorder.current()
    ctx.assert(live and live.seed == SEED, 'no live record for '..SEED)
    local disk = recorder.read(live.run_id)
    ctx.log('record offered: live '..counts(live.offered)..', disk '..counts(disk and disk.offered))
    ctx.assert(counts(live.offered) == counts(want), 'live record offered '..counts(live.offered))
    ctx.assert(disk and counts(disk.offered) == counts(want), 'record on disk offered '..counts(disk and disk.offered))
    S.offered = counts(live.offered)
    ctx.log('check: offered counts match the shop')
    return true
  end},

  {name = 'open the oracle', run = function(ctx)
    turbo()
    if not shop_ready() or G.OVERLAY_MENU then return false end
    S.computes = oracle.stats.computes
    S.shelf = table.concat(row().keys, ' ')
    hotkey()
    return oui.is_open()
  end},
  {name = 'oracle computed', timeout = 20, run = function(ctx)
    if not oui.is_open() or ctx.step_time() < 0.6 then return false end
    if oracle.stats.computes <= S.computes then return false end
    local model = oracle.get()
    local cur = model and model.antes and model.antes[1]
    local shop = cur and cur.shop
    ctx.assert(shop and shop.title == 'This shop', 'the Oracle does not show this shop')
    ctx.assert(type(shop.rerolls) == 'table' and #shop.rerolls > 0 and #shop.rerolls[1] > 0,
      'the Oracle model holds no simulated rerolls')
    ctx.log(string.format('oracle: %d computes, %d simulated rerolls of this shop',
      oracle.stats.computes - S.computes, #shop.rerolls))
    ctx.shot('oracle')
    return true
  end},
  {name = 'close the oracle', run = function(ctx)
    hotkey()
    return true
  end},
  {name = 'sim does not emit', timeout = 20, run = function(ctx)
    if oui.is_open() or G.OVERLAY_MENU then return false end
    turbo()
    if ctx.step_time() < 1 or not shop_ready() then return false end
    ctx.assert(#S.got == 2, 'shop_reroll fired '..(#S.got - 2)..' more times after the Oracle')
    ctx.assert(counts(recorder.current().offered) == S.offered,
      'offered changed: '..counts(recorder.current().offered)..' vs '..S.offered)
    ctx.assert(table.concat(row().keys, ' ') == S.shelf, 'the shelf changed')
    ctx.log('check: sim does not emit')
    return true
  end},
}
