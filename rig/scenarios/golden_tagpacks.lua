-- Golden tag packs (T-324a): the Meteor, Standard and Buffoon tags' packs,
-- opened at the skip, against bhcore.sim.predict.ante_walk(..., {pack_tags =
-- predict.ALL_TAG_PACKS}). The reference is always the real run; the
-- prediction is made from state.fresh(seed) before that run exists.
--
-- Per seed (Red Deck, stake 1): ante 1 is played without skips, ante 2 skips
-- the blinds whose tag gives a pack, with the policy {skip = ..., rerolls =
-- REROLLS, open = true, pack_tags = ALL_TAG_PACKS} at both antes:
--   1. predict: fresh(seed), then ante_walk(S, 1, policy1) and ante_walk(S, 2,
--      policy2) on the same S (the walk draws each ante's tags itself).
--   2. play the real run through ante 2 as golden_walk does: at each blind
--      select compare the ante's tags; a skipped blind uses the real Skip
--      button and its tag's pack (Tag:apply_to_run 'new_blind_choice',
--      tag.lua:224-282) opens at once, is compared card for card with the
--      walk's tag pack (key, edition, stickers; Standard: rank and suit
--      (front), enhancement (key), edition, seal) and closed with nothing
--      taken; every other blind is won with chips 1, then cash out and shop:
--      compare the row, both pack keys, REROLLS rerolls, open each pack in
--      slot order and compare its contents, close, leave. Stop at ante 2's
--      Boss blind select and check that every predicted shop and tag pack
--      showed up.
--   -> "check: golden_tagpacks <seed> <policy> ok" per seed, then
--      "check: golden_tagpacks all 6 seeds match".
-- Seeds were found offline (invariant 8: no scan here) by a scratch rig script
-- under systemd-run MemoryMax=6G over GTAG1..GTAG4000, the way golden_walk's
-- were: ante 2 walked three ways, tag packs at the skip (the claim), at the
-- end of the ante after every shop, and at its start before the Boss shop;
-- kept seeds where a wrong order changes the walk's output, because a shop
-- pack of the same kind in ante 2 draws the tag pack's streams ('pl1' and
-- soul_Planet; 'stdset'/'sta'/'standard_edition'/'stdseal'; 'buf',
-- 'packetper', 'edibuf'). Only pack tags are skipped: the walk does not model
-- the others.
--   GTAG68    skip Small (Meteor): Boss shop opens a Celestial, then Meteor's
--             Mega Celestial, then a Big shop with a Mega Celestial (end and
--             start orders differ)
--   GTAG57    skip Small (Standard): Boss and Big shops open three Jumbo
--             Standards around it (end and start orders differ)
--   GTAG1581  skip Small (Buffoon): a Buffoon pack in the Boss shop and in the
--             Big shop (end and start orders differ)
--   GTAG38    skip Big (Buffoon): Small shop opens two Buffoon packs before it
--             (start order differs)
--   GTAG4     skip both (Meteor, Standard): no Small or Big shop; the Boss
--             shop's two Mega Standards come first (start order differs)
--   GTAG518   skip both (Buffoon, Ethereal): the Buffoon pack holds a Foil
--             j_golden (an 'edibuf'2 edition), then the Spectral pack (from a
--             second scan over GTAG1..GTAG6000 for Buffoon tag packs holding
--             an edition joker)
-- The Meteor pack's _1/_2 art variant and the forced Buffoon's are unseeded
-- math.random (cosmetic): the pack is checked by its kind and size.
-- GTAG68's ante 1 Boss is The Psychic: that hand plays five cards (the only
-- change from golden_walk's mechanics; hand play draws no shop stream).
-- Mechanics copied from golden_walk.lua (itself from finder_chain.lua and
-- golden_shop.lua).
local state = require('bhcore.sim.state')
local predict = require('bhcore.sim.predict')

-- skip is ante 2's; ante 1 skips nothing.
local SEEDS = {
  {seed = 'GTAG68', skip = {Small = true, Big = false}},
  {seed = 'GTAG57', skip = {Small = true, Big = false}},
  {seed = 'GTAG1581', skip = {Small = true, Big = false}},
  {seed = 'GTAG38', skip = {Small = false, Big = true}},
  {seed = 'GTAG4', skip = {Small = true, Big = true}},
  {seed = 'GTAG518', skip = {Small = true, Big = true}},
}
local LAST_ANTE = 2
local REROLLS = 1
local SHOTS = {GTAG57 = true}
local PACK_STATE = {Arcana = 'TAROT_PACK', Celestial = 'PLANET_PACK', Spectral = 'SPECTRAL_PACK',
  Standard = 'STANDARD_PACK', Buffoon = 'BUFFOON_PACK'}

local walks = {} -- seed -> {[ante] = ante_walk result}
local P -- the seed being played
local P_CARD_KEY = nil

local function policy_name(skip)
  return (skip.Small and 'S' or '-')..(skip.Big and 'B' or '-')
end

local function fail(ctx, seed, what, want, got)
  ctx.log(string.format('MISMATCH %s %s: predicted %s, real %s', seed, what, tostring(want), tostring(got)))
  ctx.assert(false, seed..': '..what..' mismatch (predicted '..tostring(want)..', real '..tostring(got)..')')
end

-- A live Card as a comparable record (the predict card shape).
local function real_rec(c)
  if not P_CARD_KEY then
    P_CARD_KEY = {}
    for k, v in pairs(G.P_CARDS) do P_CARD_KEY[v] = k end
  end
  local set = c.config.center.set
  return {key = c.config.center.key, edition = c.edition and c.edition.type or nil,
    eternal = c.ability.eternal and true or false, perishable = c.ability.perishable and true or false,
    rental = c.ability.rental and true or false, seal = c.seal,
    front = (set == 'Default' or set == 'Enhanced') and P_CARD_KEY[c.config.card] or nil}
end

local function pred_rec(p)
  local s = p.stickers or {}
  return {key = p.key, edition = p.edition, eternal = s.eternal and true or false,
    perishable = s.perishable and true or false, rental = s.rental and true or false,
    seal = p.seal, front = p.front}
end

local function fmt(r)
  local st = (r.eternal and 'E' or '')..(r.perishable and 'P' or '')..(r.rental and 'R' or '')
  local out = r.key
  if r.edition then out = out..'/'..r.edition end
  if st ~= '' then out = out..'['..st..']' end
  if r.front then out = out..'@'..r.front end
  if r.seal then out = out..'+'..r.seal..'seal' end
  return out
end

local function fmt_list(list)
  local out = {}
  for i, r in ipairs(list) do out[i] = fmt(r) end
  return table.concat(out, ' ')
end

-- Compares a predicted card list with the live cards of an area, in order.
local function compare_cards(ctx, seed, what, want, cards)
  local w, g = {}, {}
  for i, p in ipairs(want) do w[i] = pred_rec(p) end
  for i, c in ipairs(cards) do g[i] = real_rec(c) end
  local fw, fg = fmt_list(w), fmt_list(g)
  ctx.log(string.format('%s %s: predicted %s; real %s', seed, what, fw, fg))
  if fw ~= fg then fail(ctx, seed, what, fw, fg) end
end

-- Only the run's forced first Buffoon picks its _1/_2 art with unseeded
-- math.random (common_events.lua:1947); every other shop pack key is a seeded
-- shop_pack draw and must match exactly (as golden_shop checks it).
local function pack_key_ok(want, got)
  if want.forced then return got == 'p_buffoon_normal_1' or got == 'p_buffoon_normal_2' end
  return want.key == got
end

local function select_button()
  local kind = G.GAME.blind_on_deck
  local box = G.blind_select_opts and kind and G.blind_select_opts[string.lower(kind)]
  local btn = box and box:get_UIE_by_ID('select_blind_button')
  if btn and btn.config.button == 'select_blind' then return btn, kind end
end

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

local function shop_settled()
  return G.STATE == G.STATES.SHOP and G.shop and G.shop_booster and G.shop_jokers
    and not G.CONTROLLER.locks.shop_reroll and not G.CONTROLLER.locks.use
    and not G.CONTROLLER.locks.toggle_shop
end

local PACK_STATES = nil
local function in_pack_state()
  if not PACK_STATES then
    PACK_STATES = {[G.STATES.TAROT_PACK] = true, [G.STATES.PLANET_PACK] = true,
      [G.STATES.SPECTRAL_PACK] = true, [G.STATES.STANDARD_PACK] = true, [G.STATES.BUFFOON_PACK] = true}
  end
  return PACK_STATES[G.STATE]
end

local function turbo()
  for _ = 1, 8 do G:update(1/20) end
end

local function run_ready(seed)
  return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
    and G.GAME.pseudorandom and G.GAME.pseudorandom.seed == seed
    and G.GAME.round_resets.blind_tags and G.GAME.round_resets.blind_tags.Big ~= nil
    and not G.CONTROLLER.locks.load
end

local function play_seed(ctx)
  turbo()
  local seed = P.seed
  P.frames = P.frames + 1
  local waited = P.frames
  local function go(phase) P.phase, P.frames = phase, 0 end

  if P.phase == 'blind' then
    if G.STATE ~= G.STATES.BLIND_SELECT or waited < 3 or G.CONTROLLER.locks.skip_blind then return false end
    local a, kind = G.GAME.round_resets.ante, G.GAME.blind_on_deck
    if kind == 'Boss' and a == LAST_ANTE then go('done'); return false end
    local w = walks[seed][a]
    ctx.assert(w, seed..': no walk for ante '..a)
    if not P.tags_checked[a] then
      local bt = G.GAME.round_resets.blind_tags
      local want, got = w.tags.small..'/'..w.tags.big, tostring(bt.Small)..'/'..tostring(bt.Big)
      ctx.log(string.format('%s ante %d tags: predicted %s; real %s', seed, a, want, got))
      if want ~= got then fail(ctx, seed, 'ante '..a..' tags', want, got) end
      P.tags_checked[a] = true
    end
    local skip = a == 2 and P.skip or {}
    if kind ~= 'Boss' and skip[kind] then
      local btn = panel_button(kind, 'skip_blind')
      if not btn then return false end
      local tag = G.GAME.round_resets.blind_tags[kind]
      P.skipped, P.ante = kind, a
      ctx.log(seed..' ante '..a..' skip '..kind..' ('..tag..')')
      G.FUNCS.skip_blind(btn)
      ctx.assert(predict.ALL_TAG_PACKS[tag], seed..': skipped a tag the walk does not model: '..tag)
      go('tag_pack')
    else
      local btn = select_button()
      if not btn then return false end
      P.played = kind
      G.FUNCS.select_blind(btn)
      go('play')
    end
  elseif P.phase == 'tag_pack' then
    local tp = P.next_tag_pack(P.ante)
    if not (in_pack_state() and G.pack_cards and G.pack_cards.cards
      and #G.pack_cards.cards >= (tp and #tp.cards or 1)) or waited < 3 then return false end
    ctx.assert(tp and tp.blind == P.skipped, seed..': unexpected tag pack at ante '..P.ante..' '..P.skipped)
    P.tag_seen[P.ante] = (P.tag_seen[P.ante] or 0) + 1
    -- The tag's pack card is not kept anywhere: its kind shows in the state.
    local want_state = G.STATES[PACK_STATE[G.P_CENTERS[tp.pack].kind]]
    ctx.assert(G.STATE == want_state and G.GAME.pack_size == #tp.cards, seed..': the tag pack is not a '..tp.pack)
    if SHOTS[seed] and not P.tag_shot then P.tag_shot = true; ctx.shot('tag_pack') end
    compare_cards(ctx, seed, 'ante '..P.ante..' '..P.skipped..' tag pack ('..tp.pack..')', tp.cards, G.pack_cards.cards)
    P.after_close = 'blind'
    go('close')
  elseif P.phase == 'play' then
    if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or waited < 2
      or G.CONTROLLER.locks.frame then return false end
    G.GAME.blind.chips = 1
    G.GAME.blind.chip_text = number_format(1)
    -- The Psychic (blind.lua debuff h_size_ge = 5) refuses a one-card hand.
    local n = G.GAME.blind.name == 'The Psychic' and math.min(5, #G.hand.cards) or 1
    for i = 1, n do G.hand:add_to_highlighted(G.hand.cards[i]) end
    G.FUNCS.play_cards_from_highlighted()
    go('cash_out')
  elseif P.phase == 'cash_out' then
    if G.STATE ~= G.STATES.ROUND_EVAL or waited < 2 then return false end
    if ctx.click('cash_out') then go('shop') end
  elseif P.phase == 'shop' then
    if not shop_settled() or waited < 2 or #G.shop_booster.cards ~= 2
      or #G.shop_jokers.cards ~= G.GAME.shop.joker_max then return false end
    local a = G.GAME.round_resets.ante
    P.shops[a] = (P.shops[a] or 0) + 1
    local n = P.shops[a]
    P.ante, P.label = a, 'ante '..a..' shop '..n
    P.shop = walks[seed][a] and walks[seed][a].shops[n]
    ctx.assert(P.shop, seed..': no prediction for '..P.label..' (after '..P.played..')')
    if P.shop.after ~= P.played then fail(ctx, seed, P.label..' follows', P.shop.after, P.played) end
    G.GAME.dollars = 999
    if SHOTS[seed] and not P.shop_shot then P.shop_shot = true; ctx.shot('shop') end
    compare_cards(ctx, seed, P.label..' (after '..P.played..') row', P.shop.cards, G.shop_jokers.cards)
    local want, got = {}, {}
    for i = 1, 2 do
      local c = G.shop_booster.cards[i]
      want[i], got[i] = P.shop.packs[i].key, c.config.center.key
      ctx.assert(c.ability.booster_pos == i, seed..': booster slot order')
      if not pack_key_ok(P.shop.packs[i], got[i]) then fail(ctx, seed, P.label..' pack '..i, want[i], got[i]) end
    end
    ctx.log(string.format('%s %s packs: predicted %s; real %s', seed, P.label,
      table.concat(want, ' '), table.concat(got, ' ')))
    P.rerolled, P.opened = 0, 0
    go('reroll')
  elseif P.phase == 'reroll' then
    if not shop_settled() or waited < 2 then return false end
    if P.rerolled >= REROLLS then go('open'); return false end
    P.rerolled = P.rerolled + 1
    P.old_row = G.shop_jokers.cards[1]
    G.FUNCS.reroll_shop()
    go('rerolled')
  elseif P.phase == 'rerolled' then
    if not shop_settled() or waited < 2 or #G.shop_jokers.cards ~= G.GAME.shop.joker_max
      or G.shop_jokers.cards[1] == P.old_row then return false end
    compare_cards(ctx, seed, P.label..' reroll '..P.rerolled, P.shop.rerolls[P.rerolled].cards, G.shop_jokers.cards)
    go('reroll')
  elseif P.phase == 'open' then
    if not shop_settled() or waited < 2 then return false end
    if P.opened >= 2 then go('leave'); return false end
    local slot = P.opened + 1
    local booster
    for _, c in ipairs(G.shop_booster.cards) do
      if c.ability.booster_pos == slot then booster = c end
    end
    ctx.assert(booster, seed..': '..P.label..' booster '..slot..' missing')
    P.opened = slot
    G.FUNCS.use_card({config = {ref_table = booster, button = 'use_card'}})
    go('shop_pack')
  elseif P.phase == 'shop_pack' then
    local pk = P.shop.packs[P.opened]
    if not in_pack_state() or not (G.pack_cards and G.pack_cards.cards)
      or #G.pack_cards.cards < pk.size or waited < 3 then return false end
    compare_cards(ctx, seed, P.label..' pack '..P.opened..' ('..pk.kind..') contents',
      P.shop.contents[P.opened], G.pack_cards.cards)
    P.after_close = 'open'
    go('close')
  elseif P.phase == 'close' then
    if waited < 2 or G.CONTROLLER.locks.frame then return false end
    if ctx.click('skip_booster') then go('closing') end
  elseif P.phase == 'closing' then
    if G.booster_pack or waited < 3 then return false end
    if P.after_close == 'open' and not shop_settled() then return false end
    go(P.after_close)
  elseif P.phase == 'leave' then
    ctx.log('check: golden_tagpacks '..seed..' '..P.label..' ok')
    if ctx.click('toggle_shop') then go('blind') end
  elseif P.phase == 'done' then
    for a = 1, LAST_ANTE do
      local w = walks[seed][a]
      ctx.assert((P.shops[a] or 0) == #w.shops, seed..': ante '..a..' played '..(P.shops[a] or 0)..' of '..#w.shops..' shops')
      ctx.assert((P.tag_seen[a] or 0) == #w.tag_packs, seed..': ante '..a..' opened '..(P.tag_seen[a] or 0)
        ..' of '..#w.tag_packs..' tag packs')
    end
    ctx.log('check: golden_tagpacks '..seed..' '..policy_name(P.skip)..' ok')
    return true
  end
  return false
end

local steps = {
  {name = 'speed up', run = function(ctx)
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    SaveSlots.settings.auto_checkpoints = false
    return true
  end},
}

for _, sd in ipairs(SEEDS) do
  local seed, skip = sd.seed, sd.skip
  steps[#steps + 1] = {name = 'predict and start '..seed, run = function(ctx)
    local before = STR_PACK(G.GAME)
    local S = state.fresh(seed, {stake = 1, deck = 'b_red'})
    walks[seed] = {}
    for a = 1, LAST_ANTE do
      local w = predict.ante_walk(S, a, {skip = a == 2 and skip or {}, rerolls = REROLLS, open = true,
        pack_tags = predict.ALL_TAG_PACKS})
      walks[seed][a] = w
      local tp = {}
      for i, t in ipairs(w.tag_packs) do tp[i] = t.blind..':'..t.tag end
      local sh = {}
      for i, s in ipairs(w.shops) do sh[i] = s.after end
      ctx.log(string.format('walk %s %s ante %d: tags %s/%s; shops after %s; tag packs %s', seed,
        policy_name(skip), a, w.tags.small, w.tags.big, table.concat(sh, ','), table.concat(tp, ',')))
    end
    ctx.assert(STR_PACK(G.GAME) == before, 'prediction touched the live G.GAME')
    P = {seed = seed, skip = skip, phase = 'blind', frames = 0, shops = {}, tag_seen = {}, tags_checked = {},
      next_tag_pack = function(a) return walks[seed][a].tag_packs[(P.tag_seen[a] or 0) + 1] end}
    if G.GAME then G.GAME.viewed_back = Back(G.P_CENTERS.b_red) end
    ctx.start_run{seed = seed, stake = 1}
    return true
  end}
  steps[#steps + 1] = {name = 'ready '..seed, timeout = 20, run = function(ctx)
    if not run_ready(seed) then return false end
    ctx.assert(G.GAME.stake == 1 and G.GAME.selected_back.name == 'Red Deck', seed..': not stake 1 Red Deck')
    return true
  end}
  steps[#steps + 1] = {name = 'play '..seed, timeout = 60, run = play_seed}
end

steps[#steps + 1] = {name = 'all seeds', run = function(ctx)
  ctx.log('check: golden_tagpacks all '..#SEEDS..' seeds match')
  return true
end}

return steps
