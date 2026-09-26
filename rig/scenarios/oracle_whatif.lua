-- Oracle what-if (T-322): the Oracle's what-if controls against
-- predict.ante_walk, with the live run untouched. Everything asserted is read
-- back from the overlay on screen (the display-only cards it drew), never
-- from the mod's model.
--   1. Start SEED (Red Deck, stake 1): ante 1's Small Blind tag is a Charm
--      Tag. Open the Oracle at the first blind select: the default tab (no
--      skips, 0 rerolls) is the model's, as before T-322: a "Next shop" row
--      with its 2 rerolls and pack contents. Snapshot STR_PACK(G.GAME).
--   2. Click "Skip Small": the tab lists the Charm Tag's Mega Arcana pack
--      with the cards ante_walk(capture, 1, {skip Small}) predicts, and one
--      shop fewer than the no-skip walk (only the shop after Big), whose
--      row, packs and pack contents are the walk's.
--      -> "check: skip small shows the tag pack"
--   3. Click "Rerolls" twice (0 -> 1 -> 2): the shop's 2 rerolls appear,
--      equal to ante_walk with rerolls = 2, pack contents opened after them.
--      -> "check: rerolls shown"
--   4. Switch to the ante 2 tab: its choice is its own (default), but ante
--      1's Skip Small is earlier, so the tab already walks (T-326): ante 2's
--      three shops with no rerolls, equal to the chain (ante 1 skip Small,
--      pack keys only, then ante_walk(S, 2, {})), not the model's "Next shop"
--      row. Click "Rerolls" 5 times: the tab shows ante 2's three
--      shops (after the Boss, Small, Big) with 5 rerolls each, equal to
--      ante_walk(S, 2, {rerolls = 5}) on a capture that first walked ante 1
--      with its choice (skip Small, pack keys only) -> "check: ante 2 walk".
--   5. Earlier antes' choices feed later antes (review repro): with ante 2's
--      walk cached (step 4), switch to the ante 1 tab, click "Skip Big"
--      (Small is already skipped: both ante-1 blinds skipped, so the run's
--      forced first Buffoon moves into ante 2's Boss shop), back to the ante
--      2 tab: it equals a fresh chain on a copy (ante 1 skipping both, pack
--      keys only, then ante_walk(S, 2, {rerolls = 5})), and that chain
--      differs from step 4's (else the repro would prove nothing).
--      -> "check: ante 2 follows ante 1 skips"
--   5b. Click ante 2's "Rerolls" once more (5 -> 0): ante 2 is at its own
--      defaults, and the tab still equals a fresh chain on a copy (ante 1
--      skipping both, then ante_walk(S, 2, {})), which differs from the
--      no-skip chain -> "check: ante 2 default follows ante 1 skips"
--   6. STR_PACK(G.GAME) is byte-identical to the snapshot, and the what-if
--      ran on a copy: oracle.stats.whatifs moved, computes did not (the
--      snapshot waits until the live model has no held-back recompute, so a
--      throttled refresh cannot land in the toggle window), and
--      oracle.stats.whatif_live (live-model computes or invalidations while a
--      what-if walk runs) stays 0. -> "check: no live side effects"
-- Screenshots: whatif_default.png, whatif_skip_small.png, whatif_rerolls2.png,
-- whatif_ante2_rerolls5.png, whatif_ante2_after_ante1_skips.png,
-- whatif_ante2_default_after_ante1_skips.png.
-- SEED is golden_walk's skip-Small seed (ante 1 Charm Tag, pinned there;
-- invariant 8: no scan here).
local state = require('bhcore.sim.state')
local predict = require('bhcore.sim.predict')
local oracle = require('seedoracle.oracle')
local ui = require('seedoracle.ui')

local SEED = 'GWALK6425'

local snapshot       -- STR_PACK(G.GAME) with the default tab up
local computes       -- oracle.stats.computes then
local whatifs        -- oracle.stats.whatifs then
local ante2_rerolls5 -- step 4's walk, to prove step 5 changes it

local function card_rec(c)
  return {key = c.config.center.key, edition = c.edition and c.edition.type or nil,
    front = c.config.card_key, seal = c.seal}
end

-- The card areas the Oracle drew in the tab on screen, by their seedoracle tag.
local function shown()
  local out = {}
  local e = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('tab_contents')
  local box = e and e.config.object
  if not box then return out end
  local function walk(node)
    if type(node) ~= 'table' then return end
    local obj = node.config and node.config.object
    local so = type(obj) == 'table' and obj.seedoracle
    if so and not so.key then
      local list = {}
      for _, c in ipairs(obj.cards or {}) do list[#list + 1] = card_rec(c) end
      out[so.what] = list
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

local function blind_select_ready()
  return G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil and not G.CONTROLLER.locks.load
    and G.GAME.round_resets.blind_tags and G.GAME.round_resets.blind_tags.Big ~= nil
end

local function live_tags()
  local t = G.GAME.round_resets.blind_tags
  return {small = t.Small, big = t.Big}
end

-- ante_walk on a fresh copy of the live run, ante 1 under the policy.
local function walk(skip_small, rerolls)
  return predict.ante_walk(state.capture(), 1, {skip = {Small = skip_small, Big = false}, rerolls = rerolls,
    tags = live_tags()})
end

-- A fresh chain on a copy: ante 1 under its skips (pack keys only), then
-- ante_walk(S, 2, opts), as oracle.whatif walks ante 2.
local function chain2(skip_small, skip_big, opts)
  local S = state.capture()
  predict.ante_walk(S, 1, {skip = {Small = skip_small, Big = skip_big}, cards = false, open = false,
    tags = live_tags()})
  return predict.ante_walk(S, 2, opts)
end

local function count_shops(s)
  local n = 0
  while s['shop'..(n + 1)] do n = n + 1 end
  return n
end

-- Compares the what-if shops on screen with the walk's, card for card.
local function check_shops(ctx, s, want)
  eq(ctx, 'shops shown', #want.shops, count_shops(s))
  for i, shop in ipairs(want.shops) do
    local id = 'shop'..i
    eq(ctx, id..' (after '..shop.after..') cards', fmt(shop.cards), fmt(s[id]))
    for r, rr in ipairs(shop.rerolls) do
      eq(ctx, id..' reroll '..r, fmt(rr.cards), fmt(s[id..'_reroll'..r]))
    end
    ctx.assert(s[id..'_reroll'..(#shop.rerolls + 1)] == nil, id..': more rerolls shown than chosen')
    for j, p in ipairs(shop.packs) do
      eq(ctx, id..' pack '..j, p.key, s[id..'_pack'..j] and s[id..'_pack'..j][1] and s[id..'_pack'..j][1].key)
      eq(ctx, id..' pack '..j..' contents', fmt(shop.contents[j]), fmt(s[id..'_contents'..j]))
    end
  end
end

-- The shops of a walk as one string (cards, rerolls, pack keys).
local function walk_sig(w)
  local out = {}
  for i, shop in ipairs(w.shops) do
    local packs = {}
    for j, p in ipairs(shop.packs) do packs[j] = p.key end
    local rr = {}
    for r, x in ipairs(shop.rerolls) do rr[r] = fmt(x.cards) end
    out[i] = shop.after..': '..fmt(shop.cards)..' / '..table.concat(rr, ' / ')..' / '..table.concat(packs, ' ')
  end
  return table.concat(out, ' || ')
end

local function tab_button(ante)
  for _, suffix in ipairs{' (now)', ''} do
    local b = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('tab_but_'..localize('k_ante')..' '..ante..suffix)
    if b then return b end
  end
end

local function click(ctx, field)
  ctx.assert(ctx.click('seedoracle_whatif', 'seedoracle_whatif_'..field), 'no what-if control '..field)
end

return {
  {name = 'speed up', run = function(ctx)
    ctx.assert(type(SeedOracle) == 'table', 'SeedOracle not loaded')
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    love.mouse.setPosition(4, 4)
    if SaveSlots and SaveSlots.settings then SaveSlots.settings.auto_checkpoints = false end
    return true
  end},
  {name = 'start', run = function(ctx)
    ctx.start_run{seed = SEED, stake = 1}
    return true
  end},
  {name = 'blind select', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.GAME.pseudorandom.seed == SEED and blind_select_ready()
      and ctx.step_time() > 1
  end},

  -- 1. The default tab.
  {name = 'open', run = function(ctx)
    eq(ctx, 'ante 1 Small Blind tag', 'tag_charm', G.GAME.round_resets.blind_tags.Small)
    ctx.assert(ui.open(false), 'the Oracle did not open')
    return true
  end},
  {name = 'default tab', run = function(ctx)
    if not ui.is_open() or ctx.step_time() < 0.6 then return false end
    ctx.shot('whatif_default')
    local s = shown()
    ctx.assert(s.shop and #s.shop > 0, 'default: no Next shop row')
    ctx.assert(#(s.reroll1 or {}) > 0 and #(s.reroll2 or {}) > 0, 'default: the 2 rerolls are not shown')
    ctx.assert(s.shop1 == nil and s.tagpack1 == nil, 'default: what-if rows shown')
    ctx.assert(ctx.find_button('seedoracle_whatif', 'seedoracle_whatif_Small'), 'no Skip Small control')
    -- Settle the live model first: a recompute the throttle held back (the
    -- run's own, e.g. from the events at blind select) may run whenever the
    -- overlay asks again, and must not land after the snapshot. Paused in
    -- the overlay, nothing else invalidates it.
    local _, pending = oracle.get()
    if pending then return false end
    snapshot = STR_PACK(G.GAME)
    computes, whatifs = oracle.stats.computes, oracle.stats.whatifs
    return true
  end},

  -- 2. Skip Small.
  {name = 'toggle skip small', run = function(ctx)
    click(ctx, 'Small')
    return true
  end},
  {name = 'skip small tab', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local s = shown()
    local want, noskip = walk(true, 0), walk(false, 0)
    ctx.assert(#want.tag_packs == 1, 'the walk opens no Charm pack')
    local tp = want.tag_packs[1]
    eq(ctx, 'tag pack', 'p_arcana_mega_1', tp.pack)
    eq(ctx, 'tag pack shown', tp.pack, s.tagpack1 and s.tagpack1[1] and s.tagpack1[1].key)
    eq(ctx, 'tag pack contents', fmt(tp.cards), fmt(s.tagpack1_contents))
    ctx.assert(#tp.cards > 0, 'the tag pack holds nothing')
    eq(ctx, 'shops: one fewer than without the skip', #noskip.shops - 1, count_shops(s))
    check_shops(ctx, s, want)
    eq(ctx, 'the shop left follows', 'Big', want.shops[1].after)
    ctx.assert(s.shop == nil, 'the default Next shop row is still shown')
    ctx.shot('whatif_skip_small')
    ctx.log('check: skip small shows the tag pack')
    return true
  end},

  -- 3. Rerolls 0 -> 1 -> 2.
  {name = 'reroll 1', run = function(ctx)
    click(ctx, 'rerolls')
    return true
  end},
  {name = 'reroll 2', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    click(ctx, 'rerolls')
    return true
  end},
  {name = 'rerolls tab', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    eq(ctx, 'reroll choice', 2, oracle.choice(1).rerolls)
    local s = shown()
    ctx.assert(#(s.shop1_reroll1 or {}) > 0 and #(s.shop1_reroll2 or {}) > 0, 'the rerolls do not appear')
    local want = walk(true, 2)
    check_shops(ctx, s, want)
    eq(ctx, 'tag pack contents with rerolls', fmt(want.tag_packs[1].cards), fmt(s.tagpack1_contents))
    ctx.shot('whatif_rerolls2')
    ctx.log('check: rerolls shown')
    return true
  end},

  -- 4. Ante 2: its own choice, three shops, 5 rerolls.
  {name = 'to ante 2', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    -- Through the tab button itself, so the tab bar shows ante 2 chosen.
    local b = tab_button(2)
    ctx.assert(b, 'no ante 2 tab')
    b:click()
    return true
  end},
  {name = 'ante 2 default', run = function(ctx)
    if ctx.step_time() < 0.4 then return false end
    local c = oracle.choice(2)
    ctx.assert(not c.skip.Small and not c.skip.Big and c.rerolls == 0, 'ante 2 does not start at the default choice')
    -- Ante 1 skips Small, so ante 2's defaults walk after it (T-326).
    local s = shown()
    ctx.assert(s.shop == nil, 'ante 2 default: the model\'s Next shop row is shown despite ante 1\'s skip')
    check_shops(ctx, s, chain2(true, false, {}))
    ctx.log('check: ante 2 default walks after ante 1 skip small')
    return true
  end},
  {name = 'ante 2 rerolls 5', timeout = 15, run = function(ctx)
    if oracle.choice(2).rerolls == 5 then return true end
    if ctx.step_time() < 0.2*(oracle.choice(2).rerolls + 1) then return false end
    click(ctx, 'rerolls')
    return false
  end},
  {name = 'ante 2 walk', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local S = state.capture()
    predict.ante_walk(S, 1, {skip = {Small = true, Big = false}, cards = false, open = false, tags = live_tags()})
    local want = predict.ante_walk(S, 2, {rerolls = 5})
    eq(ctx, 'ante 2 shops follow', 'Boss Small Big',
      table.concat({want.shops[1].after, want.shops[2].after, want.shops[3].after}, ' '))
    check_shops(ctx, shown(), want)
    ante2_rerolls5 = want
    ctx.shot('whatif_ante2_rerolls5')
    ctx.log('check: ante 2 walk')
    return true
  end},

  -- 5. Ante 1 skips both blinds; ante 2's tab follows.
  {name = 'to ante 1', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    local b = tab_button(1)
    ctx.assert(b, 'no ante 1 tab')
    b:click()
    return true
  end},
  {name = 'ante 1 skip big', run = function(ctx)
    if ctx.step_time() < 0.4 then return false end
    ctx.assert(oracle.choice(1).skip.Small, 'ante 1: Skip Small is not still chosen')
    click(ctx, 'Big')
    return true
  end},
  {name = 'back to ante 2', run = function(ctx)
    if ctx.step_time() < 0.4 then return false end
    ctx.assert(oracle.choice(1).skip.Small and oracle.choice(1).skip.Big, 'ante 1: not both blinds skipped')
    local b = tab_button(2)
    ctx.assert(b, 'no ante 2 tab')
    b:click()
    return true
  end},
  {name = 'ante 2 after ante 1 skips', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    eq(ctx, 'ante 2 reroll choice kept', 5, oracle.choice(2).rerolls)
    local S = state.capture()
    predict.ante_walk(S, 1, {skip = {Small = true, Big = true}, cards = false, open = false, tags = live_tags()})
    local want = predict.ante_walk(S, 2, {rerolls = 5})
    ctx.assert(walk_sig(want) ~= walk_sig(ante2_rerolls5),
      'skipping both ante-1 blinds does not change the ante 2 walk: the repro proves nothing')
    check_shops(ctx, shown(), want)
    ctx.shot('whatif_ante2_after_ante1_skips')
    ctx.log('check: ante 2 follows ante 1 skips')
    return true
  end},
  {name = 'ante 2 rerolls back to 0', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    click(ctx, 'rerolls')
    return true
  end},
  {name = 'ante 2 default after ante 1 skips', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    local c = oracle.choice(2)
    ctx.assert(not c.skip.Small and not c.skip.Big and c.rerolls == 0, 'ante 2 is not at its defaults')
    ctx.assert(oracle.whatif(2) ~= nil, 'oracle.whatif(2) is nil at ante 2 defaults after ante 1 skips')
    local want = chain2(true, true, {})
    ctx.assert(walk_sig(want) ~= walk_sig(chain2(false, false, {})),
      'skipping both ante-1 blinds does not change the ante 2 default walk: the check proves nothing')
    local s = shown()
    ctx.assert(s.shop == nil, 'ante 2 default: the model\'s Next shop row is shown despite ante 1\'s skips')
    check_shops(ctx, s, want)
    ctx.shot('whatif_ante2_default_after_ante1_skips')
    ctx.log('check: ante 2 default follows ante 1 skips')
    return true
  end},

  -- 6. Nothing leaked into the run.
  {name = 'compare', run = function(ctx)
    ctx.assert(STR_PACK(G.GAME) == snapshot, 'G.GAME changed')
    ctx.assert(oracle.stats.whatifs > whatifs, 'no what-if ran')
    eq(ctx, 'model recomputes while toggling', computes, oracle.stats.computes)
    eq(ctx, 'live-model computes/invalidations inside what-if walks', 0, oracle.stats.whatif_live)
    ctx.log('check: no live side effects')
    ui.close()
    return true
  end},
  {name = 'closed', run = function(ctx)
    return not ui.is_open() and ctx.step_time() > 0.3
  end},
}
