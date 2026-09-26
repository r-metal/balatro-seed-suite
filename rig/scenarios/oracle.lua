-- Oracle (T-110, T-110b): the Seed Oracle overlay against the live run and the
-- simulator. Everything asserted is read back from the overlay on screen
-- (the display-only cards, tag and blind sprites it drew), never from the
-- mod's model.
--   1. Start a seeded run (SEED, Red Deck, stake 1) and open the Oracle with
--      ctrl+o at the first blind select. Ante 1's tags/boss/voucher must be
--      the live run's; antes 2 and 3 must be plan(state.fresh(SEED))'s. The
--      ante-1 tab's shop cards and packs must equal predict.shop/packs on a
--      fresh state.capture() of the run. The boss is a static chip (no
--      hover closure) from the blind_chips atlas at the boss's position, with
--      its name and vanilla description -> "check: boss chip rendered".
--      Close it (ctrl+o again).
--   2. Play the Small blind (selected, chips needed set to 1, won with the
--      first five cards), cash out: the real shop's cards (key + edition) and
--      packs equal what the overlay showed -> "check: overlay matched the
--      real shop". The run's first pack is vanilla's forced Buffoon with an
--      unseeded art variant, so _1/_2 are both accepted for it.
--      The Oracle opened in that shop shows the same pack contents as at the
--      blind select. Then, before any reroll, each pack is opened in slot
--      order (use_card -> Card:open), its cards compared with the contents
--      the overlay showed, and skipped -> "check: pack contents match real
--      opens".
--      Play on to the Boss shop (ante 2): the Oracle opened there shows the
--      shelf as "On the shelf" (screenshot only). Then at ante 2's blind
--      select, the Oracle's ante-2 tab must show the live ante-2
--      tags/boss/voucher, equal to plan(fresh)'s -> "check: overlay shows the
--      plan".
--   3. Open the pause menu, snapshot STR_PACK(G.GAME), the joker/consumable
--      limits and the live Card/CardArea/Sprite counts, open the Oracle from
--      its pause-menu button, visit every tab, go Back to the pause menu:
--      all of it unchanged, and no recompute ran while it sat open ->
--      "check: no live side effects".
-- Screenshots: oracle_ante1.png, oracle_first_shop.png, oracle_ante2_tab.png, oracle_ante3_tab.png,
-- oracle_in_shop.png, oracle_ante2.png, pause_menu.png, oracle_from_pause.png.
-- Speed: vsync off, GAMESPEED 64, extra G:update passes while playing
-- (journal/2026-09-23-scripting-balatro-fast.md), frame-count waits.
local state = require('bhcore.sim.state')
local predict = require('bhcore.sim.predict')
local oracle = require('seedoracle.oracle')
local ui = require('seedoracle.ui')

-- Its first shop's packs hold different cards when opened before and after
-- the 2 rerolls (both packs; a T-110b probe of random seeds), so the
-- open-before-rerolling check tells the two policies apart.
local SEED = 'KZGQ3DQA'
local TURBO = 8

local plan            -- plan(state.fresh(SEED))
local shown_shop      -- what the overlay showed for the first shop
local pause_before    -- snapshot taken with the pause menu up
local computes_open   -- oracle.stats.computes once the overlay was up

local function turbo()
  for _ = 1, TURBO do G:update(1/20) end
end

local function hotkey()
  G.CONTROLLER.held_keys['lctrl'] = true
  G.CONTROLLER:key_press_update('o', 0)
  G.CONTROLLER.held_keys['lctrl'] = nil
end

local function card_rec(c)
  return {key = c.config.center.key, edition = c.edition and c.edition.type or nil,
    front = c.config.card_key, seal = c.seal}
end

-- The objects the Oracle drew in the tab on screen, by their seedoracle tag.
-- `objs` holds the tagged sprites themselves; `boss_desc` the text of the
-- boss description box.
local function shown()
  local out = {areas = {}, objs = {}}
  local e = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('tab_contents')
  local box = e and e.config.object
  if not box then return out end
  local function walk(node)
    if type(node) ~= 'table' then return end
    local obj = node.config and node.config.object
    local so = type(obj) == 'table' and obj.seedoracle
    if so then
      if so.key then
        out[so.what] = so.key
        out.objs[so.what] = obj
      else
        local list = {}
        for _, c in ipairs(obj.cards or {}) do list[#list + 1] = card_rec(c) end
        out.areas[so.what] = list
      end
    end
    if node.config and node.config.id == 'seedoracle_boss_desc' then
      local lines = {}
      local function texts(n)
        if n.config and n.config.text then lines[#lines + 1] = n.config.text end
        for _, child in pairs(n.children or {}) do texts(child) end
      end
      texts(node)
      out.boss_desc = table.concat(lines, ' / ')
    end
    if node.config and node.config.text then
      out.texts = out.texts or {}
      out.texts[node.config.text] = true
    end
    for _, child in pairs(node.children or {}) do walk(child) end
  end
  walk(box.UIRoot)
  return out
end

local function fmt(list)
  local out = {}
  for i, r in ipairs(list or {}) do
    out[i] = r.key..(r.edition and '/'..r.edition or '')..(r.front and '@'..r.front or '')
      ..(r.seal and '+'..r.seal or '')
  end
  return table.concat(out, ' ')
end

local function eq(ctx, what, want, got)
  ctx.log(string.format('%s: expected %s, shown %s', what, tostring(want), tostring(got)))
  ctx.assert(want == got, what..': expected '..tostring(want)..', got '..tostring(got))
end

local function tab_button(ante)
  for _, suffix in ipairs{' (now)', ''} do
    local b = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('tab_but_'..localize('k_ante')..' '..ante..suffix)
    if b then return b end
  end
end

-- Asserts the stable row of the tab on screen.
local function check_stable(ctx, ante, want)
  local s = shown()
  eq(ctx, 'ante '..ante..' small tag', want.small, s.tag_small)
  eq(ctx, 'ante '..ante..' big tag', want.big, s.tag_big)
  eq(ctx, 'ante '..ante..' boss', want.boss, s.boss)
  eq(ctx, 'ante '..ante..' voucher', want.voucher, (s.areas.voucher or {})[1] and s.areas.voucher[1].key)
  return s
end

local function live_stable()
  local rr = G.GAME.round_resets
  return {small = rr.blind_tags.Small, big = rr.blind_tags.Big, boss = rr.blind_choices.Boss,
    voucher = G.GAME.current_round.voucher}
end

local function plan_stable(a)
  local p = plan[a]
  return {small = p.tags.small, big = p.tags.big, boss = p.boss, voucher = p.voucher}
end

local function blind_select_ready()
  return G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil and not G.CONTROLLER.locks.load
    and G.GAME.round_resets.blind_tags and G.GAME.round_resets.blind_tags.Big ~= nil
end

local function shop_ready()
  return G.STATE == G.STATES.SHOP and G.shop and G.shop_jokers and G.shop_booster
    and #G.shop_booster.cards == 2 and #G.shop_jokers.cards == G.GAME.shop.joker_max
    and not G.CONTROLLER.locks.toggle_shop and not G.CONTROLLER.locks.shop_reroll
end

local function select_button()
  local kind = G.GAME.blind_on_deck
  local box = G.blind_select_opts and kind and G.blind_select_opts[string.lower(kind)]
  local btn = box and box:get_UIE_by_ID('select_blind_button')
  if btn and btn.config.button == 'select_blind' then return btn, kind end
end

-- Plays blinds by the policy until the shop after the blind `until_kind`,
-- then calls on_shop(ctx) once and returns true when that shop is settled.
local function play_to_shop(until_kind, on_shop)
  local p
  return function(ctx)
    p = p or {phase = 'select', frames = 0}
    turbo()
    p.frames = p.frames + 1
    local function go(phase) p.phase, p.frames = phase, 0 end
    if p.phase == 'select' then
      if G.STATE == G.STATES.SHOP and shop_ready() and p.frames >= 2 then
        ctx.click('toggle_shop') -- left over from an earlier step
        p.frames = 0
        return false
      end
      if not blind_select_ready() or p.frames < 2 then return false end
      local btn, kind = select_button()
      if not btn then return false end
      p.kind = kind
      G.FUNCS.select_blind(btn)
      go('play')
    elseif p.phase == 'play' then
      if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or p.frames < 2
        or G.CONTROLLER.locks.frame then return false end
      G.GAME.blind.chips = 1
      G.GAME.blind.chip_text = number_format(1)
      for i = 1, #G.hand.cards do
        if #G.hand.highlighted >= math.min(5, G.hand.config.highlighted_limit or 5) then break end
        if not G.hand.cards[i].highlighted then G.hand:add_to_highlighted(G.hand.cards[i]) end
      end
      G.FUNCS.play_cards_from_highlighted()
      go('cash_out')
    elseif p.phase == 'cash_out' then
      if G.STATE ~= G.STATES.ROUND_EVAL or p.frames < 2 then return false end
      if ctx.click('cash_out') then go('shop') end
    elseif p.phase == 'shop' then
      if not shop_ready() or p.frames < 2 then return false end
      if p.kind == until_kind then
        if on_shop then on_shop(ctx) end
        return true
      end
      if ctx.click('toggle_shop') then go('select') end
    end
    return false
  end
end

-- The boss chip on the tab on screen: vanilla's blind_chips sprite at the
-- boss's position, with no hover of its own, and its name and description.
local function check_boss_chip(ctx, key)
  local s = shown()
  local chip = s.objs.boss
  local blind = G.P_BLINDS[key]
  ctx.assert(chip ~= nil and blind ~= nil, 'no boss chip for '..tostring(key))
  ctx.assert(chip.is and chip:is(AnimatedSprite), 'the boss chip is not an AnimatedSprite')
  ctx.assert(chip.atlas == G.ANIMATION_ATLAS['blind_chips'], 'the boss chip is not from blind_chips')
  eq(ctx, 'boss chip atlas row', blind.pos.y, chip.animation.y)
  ctx.assert(rawget(chip, 'hover') == nil and rawget(chip, 'stop_hover') == nil,
    'the boss chip carries a hover closure')
  ctx.assert(not chip.states.hover.can and chip.states.visible, 'the boss chip is hoverable or hidden')
  ctx.assert(chip.T.w > 0.5 and chip.VT.x >= 0 and chip.VT.x + chip.VT.w <= G.ROOM.T.w,
    'the boss chip is not laid out on screen')
  local name = localize{type = 'name_text', key = key, set = 'Blind'}
  ctx.assert(s.texts and s.texts[name], 'the boss name '..name..' is not shown')
  local lines = localize{type = 'raw_descriptions', key = key, set = 'Blind', vars = blind.vars}
  if key == 'bl_wheel' then lines[1] = tostring(G.GAME.probabilities.normal)..lines[1] end
  eq(ctx, 'boss description', table.concat(lines, ' / '), s.boss_desc)
  ctx.log('check: boss chip rendered ('..key..')')
end

local PACK_STATES
local function in_pack_state()
  PACK_STATES = PACK_STATES or {[G.STATES.TAROT_PACK] = true, [G.STATES.PLANET_PACK] = true,
    [G.STATES.SPECTRAL_PACK] = true, [G.STATES.STANDARD_PACK] = true, [G.STATES.BUFFOON_PACK] = true}
  return PACK_STATES[G.STATE]
end

local function shop_settled()
  return G.STATE == G.STATES.SHOP and G.shop and G.shop_booster and G.shop_jokers
    and not G.CONTROLLER.locks.shop_reroll and not G.CONTROLLER.locks.use
    and not G.CONTROLLER.locks.toggle_shop
end

-- In the first shop, before any reroll: opens each pack in slot order and
-- compares what it holds with what the overlay showed, skips it, and leaves
-- the shop once both are done.
local function open_packs()
  local p
  return function(ctx)
    p = p or {phase = 'open', frames = 0, opened = 0}
    turbo()
    p.frames = p.frames + 1
    local function go(phase) p.phase, p.frames = phase, 0 end
    if p.phase == 'open' then
      if G.OVERLAY_MENU or not shop_settled() or p.frames < 2 then return false end
      if p.opened >= 2 then go('leave'); return false end
      ctx.assert(G.GAME.current_round.reroll_cost_increase == 0, 'the shop was rerolled before the packs')
      local slot = p.opened + 1
      local booster
      for _, c in ipairs(G.shop_booster.cards) do
        if c.ability.booster_pos == slot then booster = c end
      end
      ctx.assert(booster, 'first shop: pack '..slot..' missing')
      p.opened, p.size = slot, booster.config.center.config.extra
      G.GAME.dollars = math.max(G.GAME.dollars, 50)
      G.FUNCS.use_card({config = {ref_table = booster, button = 'use_card'}})
      go('pack')
    elseif p.phase == 'pack' then
      if not in_pack_state() or not G.pack_cards or not G.pack_cards.cards
        or #G.pack_cards.cards < p.size or p.frames < 3 then return false end
      if p.opened == 1 then ctx.shot('first_pack_open') end
      local real = {}
      for i, c in ipairs(G.pack_cards.cards) do real[i] = card_rec(c) end
      eq(ctx, 'pack '..p.opened..' contents (opened before rerolling)',
        fmt(shown_shop.contents[p.opened]), fmt(real))
      go('skip')
    elseif p.phase == 'skip' then
      if p.frames < 2 then return false end
      if ctx.click('skip_booster') then go('closing') end
    elseif p.phase == 'closing' then
      if G.booster_pack or not shop_settled() or p.frames < 3 then return false end
      go('open')
    elseif p.phase == 'leave' then
      ctx.log('check: pack contents match real opens')
      if ctx.click('toggle_shop') then return true end
    end
    return false
  end
end

local function wait_open(ctx, frames)
  return ui.is_open() and ctx.step_time() > 0.6
end

return {
  {name = 'speed up', run = function(ctx)
    ctx.assert(type(SeedOracle) == 'table' and SeedOracle.VERSION == BHCore.VERSION, 'SeedOracle not loaded')
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    -- The headless cursor sits mid-screen, where its hover popup would cover
    -- the boss chip in every shot: park it in a corner.
    love.mouse.setPosition(4, 4)
    if SaveSlots and SaveSlots.settings then SaveSlots.settings.auto_checkpoints = false end
    return true
  end},
  {name = 'plan and start', run = function(ctx)
    plan = predict.plan(state.fresh(SEED, {stake = 1, deck = 'b_red'}), {antes = 3, shops_per_ante = 1, open_packs = false})
    ctx.start_run{seed = SEED, stake = 1}
    return true
  end},
  {name = 'blind select', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.GAME.pseudorandom.seed == SEED and blind_select_ready()
      and ctx.step_time() > 1
  end},

  -- 1. The plan, read off the overlay.
  {name = 'open with ctrl+o', run = function(ctx)
    ctx.assert(not ui.is_open(), 'Oracle open before the hotkey')
    hotkey()
    ctx.assert(ui.is_open(), 'ctrl+o did not open the Oracle')
    return true
  end},
  {name = 'ante 1 tab', run = function(ctx)
    if not wait_open(ctx) then return false end
    ctx.shot('oracle_ante1')
    check_stable(ctx, 1, live_stable())
    -- The first shop, from the live stream positions.
    local S = state.capture()
    local want_cards = predict.shop(S, 1)
    local want_packs = predict.packs(S, 1, 2)
    local s = shown()
    eq(ctx, 'first shop cards', fmt(want_cards), fmt(s.areas.shop))
    local packs = {s.areas.pack1 and s.areas.pack1[1], s.areas.pack2 and s.areas.pack2[1]}
    eq(ctx, 'first shop packs', want_packs[1].key..' '..want_packs[2].key,
      tostring(packs[1] and packs[1].key)..' '..tostring(packs[2] and packs[2].key))
    ctx.assert(#(s.areas.reroll1 or {}) == 2 and #(s.areas.reroll2 or {}) == 2, 'rerolls not shown')
    ctx.assert(#(s.areas.contents1 or {}) > 0 and #(s.areas.contents2 or {}) > 0, 'pack contents not shown')
    shown_shop = {cards = s.areas.shop, packs = {packs[1].key, packs[2].key}, forced = want_packs[1].forced,
      contents = {s.areas.contents1, s.areas.contents2}}
    -- What the old policy (contents after the 2 rerolls) would have shown,
    -- for the record: when it differs, the open-before-rerolling check below
    -- tells the two apart.
    local R = state.capture()
    predict.shop(R, 1)
    local rp = predict.packs(R, 1, 2)
    for _ = 1, 2 do predict.reroll(R, 1) end
    local differs = 0
    for i = 1, 2 do
      local after = fmt(predict.pack_contents(R, rp[i].key, 1))
      if after ~= fmt(shown_shop.contents[i]) then differs = differs + 1 end
      ctx.log(string.format('pack %d contents after 2 rerolls would be %s (%s)', i, after,
        after == fmt(shown_shop.contents[i]) and 'same' or 'differs'))
    end
    -- Without a difference, 'pack contents match real opens' can't tell the
    -- before-reroll policy (T-110b) from the old after-reroll one.
    ctx.assert(differs > 0, 'this seed cannot discriminate the pack-contents policy; pick another')
    check_boss_chip(ctx, G.GAME.round_resets.blind_choices.Boss)
    return true
  end},
  -- Screenshots land at the end of the frame: switch tabs a frame later.
  {name = 'to ante 2 tab', run = function(ctx)
    G.FUNCS.change_tab(tab_button(2))
    return true
  end},
  {name = 'ante 2 tab', run = function(ctx)
    if ctx.step_time() < 0.4 then return false end
    ctx.shot('oracle_ante2_tab')
    check_stable(ctx, 2, plan_stable(2))
    return true
  end},
  {name = 'to ante 3 tab', run = function(ctx)
    G.FUNCS.change_tab(tab_button(3))
    return true
  end},
  {name = 'ante 3 tab', run = function(ctx)
    if ctx.step_time() < 0.4 then return false end
    ctx.shot('oracle_ante3_tab')
    check_stable(ctx, 3, plan_stable(3))
    return true
  end},
  {name = 'close with ctrl+o', run = function(ctx)
    hotkey()
    ctx.assert(not ui.is_open() and not G.OVERLAY_MENU, 'ctrl+o did not close the Oracle')
    return true
  end},

  -- 2. The real first shop.
  {name = 'play to the first shop', timeout = 30, run = play_to_shop('Small', function(ctx)
    local real = {}
    for i, c in ipairs(G.shop_jokers.cards) do
      real[i] = {key = c.config.center.key, edition = c.edition and c.edition.type or nil}
    end
    eq(ctx, 'real shop cards', fmt(shown_shop.cards), fmt(real))
    local slots = {}
    for _, c in ipairs(G.shop_booster.cards) do slots[c.ability.booster_pos] = c.config.center.key end
    for i = 1, 2 do
      local want, got = shown_shop.packs[i], slots[i]
      local ok = want == got or (i == 1 and shown_shop.forced and (got == 'p_buffoon_normal_1' or got == 'p_buffoon_normal_2'))
      ctx.log(string.format('real shop pack %d: shown %s, real %s', i, tostring(want), tostring(got)))
      ctx.assert(ok, 'pack '..i..': shown '..tostring(want)..', real '..tostring(got))
    end
    ctx.log('check: overlay matched the real shop')
  end)},
  {name = 'open in the first shop', run = function(ctx)
    if not shop_settled() then return false end
    hotkey()
    return ui.is_open()
  end},
  {name = 'first shop contents', run = function(ctx)
    if not wait_open(ctx) then return false end
    ctx.shot('oracle_first_shop')
    local s = shown()
    for i = 1, 2 do
      eq(ctx, 'first shop pack '..i..' contents, in the shop vs at the blind select',
        fmt(shown_shop.contents[i]), fmt(s.areas['contents'..i]))
    end
    return true
  end},
  {name = 'close in the first shop', run = function(ctx)
    hotkey()
    return true
  end},
  {name = 'open the packs before rerolling', timeout = 30, run = open_packs()},
  {name = 'play to the boss shop', timeout = 40, run = play_to_shop('Boss')},
  {name = 'open in the shop', run = function(ctx)
    ctx.assert(G.GAME.round_resets.ante == 2, 'not in ante 2 after the Boss')
    hotkey()
    return ui.is_open()
  end},
  {name = 'shop shot', run = function(ctx)
    if not wait_open(ctx) then return false end
    local s = shown()
    local live = {}
    for i, c in ipairs(G.shop_jokers.cards) do live[i] = {key = c.config.center.key, edition = c.edition and c.edition.type or nil} end
    eq(ctx, 'boss shop on the shelf', fmt(live), fmt(s.areas.shop))
    ctx.shot('oracle_in_shop')
    return true
  end},
  {name = 'close in the shop', run = function(ctx)
    hotkey()
    return true
  end},
  {name = 'leave the boss shop', timeout = 20, run = function(ctx)
    if ui.is_open() or G.OVERLAY_MENU then return false end
    turbo()
    if G.STATE == G.STATES.SHOP and shop_ready() then ctx.click('toggle_shop'); return false end
    return G.GAME.round_resets.ante == 2 and blind_select_ready() and ctx.step_time() > 0.5
  end},
  {name = 'open at ante 2', run = function(ctx)
    hotkey()
    return ui.is_open()
  end},
  {name = 'ante 2 is now', run = function(ctx)
    if not wait_open(ctx) then return false end
    ctx.shot('oracle_ante2')
    local live = live_stable()
    check_stable(ctx, 2, live)
    local want = plan_stable(2)
    for _, k in ipairs{'small', 'big', 'boss', 'voucher'} do
      eq(ctx, 'ante 2 live '..k..' vs plan(fresh)', want[k], live[k])
    end
    -- Not the Boss shop the Oracle last saw: the next ante-2 shop.
    local S = state.capture()
    eq(ctx, 'ante 2 next shop cards', fmt(predict.shop(S, 2)), fmt(shown().areas.shop))
    ctx.log('check: overlay shows the plan')
    return true
  end},
  {name = 'close at ante 2', run = function(ctx)
    hotkey()
    return true
  end},

  -- 3. From the pause menu: nothing leaks into the run.
  {name = 'pause menu', run = function(ctx)
    if G.OVERLAY_MENU then return false end
    G.FUNCS.options()
    return true
  end},
  {name = 'snapshot', run = function(ctx)
    if ctx.step_time() < 0.6 or not ctx.find_button('seedoracle_open') then return false end
    ctx.assert(ctx.find_button('saveslots_open') ~= nil, 'the Save Slots button is gone from the pause menu')
    ctx.shot('pause_menu')
    return true
  end},
  {name = 'open from the pause menu', run = function(ctx)
    pause_before = {game = STR_PACK(G.GAME), jokers = G.jokers.config.card_limit,
      cons = G.consumeables.config.card_limit, cards = #G.I.CARD, areas = #G.I.CARDAREA, sprites = #G.I.SPRITE}
    ctx.assert(ctx.click('seedoracle_open'), 'no Seed Oracle button')
    return true
  end},
  {name = 'visit every tab', run = function(ctx)
    if not wait_open(ctx) then return false end
    computes_open = oracle.stats.computes
    for a = 3, 2, -1 do G.FUNCS.change_tab(tab_button(a)) end
    return true
  end},
  {name = 'from pause shot', run = function(ctx)
    if ctx.step_time() < 0.4 then return false end
    ctx.shot('oracle_from_pause')
    return true
  end},
  {name = 'sit open', run = function(ctx)
    return ctx.step_time() > 1
  end},
  {name = 'back to pause', run = function(ctx)
    ctx.assert(oracle.stats.computes == computes_open, 'the Oracle recomputed while it sat open')
    ctx.assert(ctx.click('options'), 'no Back button to the pause menu')
    return true
  end},
  {name = 'compare', run = function(ctx)
    if ctx.step_time() < 0.6 or not ctx.find_button('seedoracle_open') then return false end
    ctx.assert(STR_PACK(G.GAME) == pause_before.game, 'G.GAME changed')
    eq(ctx, 'joker limit', pause_before.jokers, G.jokers.config.card_limit)
    eq(ctx, 'consumable limit', pause_before.cons, G.consumeables.config.card_limit)
    eq(ctx, 'live cards', pause_before.cards, #G.I.CARD)
    eq(ctx, 'card areas', pause_before.areas, #G.I.CARDAREA)
    eq(ctx, 'sprites', pause_before.sprites, #G.I.SPRITE)
    ctx.log('check: no live side effects')
    G.FUNCS.exit_overlay_menu()
    return true
  end},
}
