-- Finder filter (T-111, T-111b): seedfinder.filter against the real game.
-- Five filters are scanned on the main thread (filter.eval_seed over a fixed,
-- generated seed sequence, at most MAX_SEEDS per filter) until each has HITS
-- hits; then every hit is replayed as a real seeded run (Red Deck, stake 1)
-- and each clause the hit claims is checked on what vanilla generated. The
-- sim is never the reference for a hit.
--
-- Filters and how their hits are checked:
--   tag         ante-1 Small tag = Investment: G.GAME.round_resets.blind_tags
--               at the first blind select.
--   tag_boss    ante-1 Big tag = Economy and ante-1 boss = The Hook:
--               blind_tags.Big and blind_choices.Boss at blind select.
--   charm_soul  ante-1 Small tag = Charm and a Soul in a tag pack: the tag is
--               checked at blind select; then the blinds are skipped through
--               the real Skip button (Small, and Big as well when eval's
--               details name the Big blind's pack), vanilla opens the Mega
--               Arcana, and G.pack_cards must hold c_soul at the predicted
--               slot. Any other pack a skip opens is closed unopened
--               (skip_booster), as the from_tag policy assumes.
--   big_charm   ante-1 Big tag = Charm and a Soul in a tag pack (T-111b). The
--               scan runs until BIG_HITS hits have the Soul in the Big blind's
--               pack with no pack tag on the Small blind; those are checked by
--               playing the Small Blind (won as in shop_joker below), leaving
--               its shop untouched, then skipping the Big Blind: its Mega
--               Arcana must hold c_soul at the predicted slot. That differs
--               from the from_tag policy (Small skipped first) only in the
--               Small round and its shop, which draw no 'ar1'/'soul_Tarot'
--               stream (shop Tarots are not soulable, common_events.lua:2088,
--               UI_definitions.lua:776) and release their cards on leaving.
--               A hit whose Small tag also opens a pack is checked as
--               charm_soul (skip both), since then the Big pack is the
--               second draw.
--   shop_joker  Scholar in a shop by ante 2 (mode any over two shop_joker
--               clauses, ante 1 and ante 2, no rerolls): the run is played with
--               the plan policy (no skips, no purchases, no packs opened; each
--               blind won by setting its chips to 1 and playing the first five
--               cards) up to the shop eval names, counted by the ante whose
--               streams it draws (the shop after ante 1's Boss is ante 2 shop
--               1); the card at the predicted slot must be j_scholar.
-- Logs: "scan <filter>: ..." per filter, "check: hit <seed> <filter> ok" per
-- hit, then "check: big-blind charm path verified", "check: <n> hits
-- verified in real runs" and "check: no false positives". Any mismatch logs both sides and fails.
-- Speed: vsync off, GAMESPEED 64 and extra Game:update passes per frame while
-- a run is driven (journal/2026-09-23-scripting-balatro-fast.md); the scan
-- spends at most SCAN_BUDGET seconds per frame. Neither changes generation.
local filter = require('seedfinder.filter')

local HITS = 3
local BIG_HITS = 2
local MAX_SEEDS = 20000
local SCAN_BUDGET = 0.05

local FILTERS = {
  {id = 'tag', f = {name = 'Investment first', clauses = {
    {kind = 'tag', ante = 1, blind = 'Small', key = 'tag_investment'}}}},
  {id = 'tag_boss', f = {name = 'Economy vs Hook', clauses = {
    {kind = 'tag', ante = 1, blind = 'Big', key = 'tag_economy'},
    {kind = 'boss', ante = 1, key = 'bl_hook'}}}},
  {id = 'charm_soul', f = {name = 'Charm Soul', clauses = {
    {kind = 'tag', ante = 1, blind = 'Small', key = 'tag_charm'},
    {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true}}}},
  {id = 'shop_joker', f = {name = 'Scholar by ante 2', mode = 'any', clauses = {
    {kind = 'shop_joker', ante = 1, key = 'j_scholar'},
    {kind = 'shop_joker', ante = 2, key = 'j_scholar'}}}},
  {id = 'big_charm', hits = BIG_HITS, f = {name = 'Big Charm Soul', clauses = {
    {kind = 'tag', ante = 1, blind = 'Big', key = 'tag_charm'},
    {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true}}}},
}

-- A hit is checked on the Big-blind path when its Soul is in the Big blind's
-- pack and the Small blind's tag opens no pack (the Big pack is the first draw).
local function big_path(spec, details)
  if spec.id ~= 'big_charm' then return false end
  for i, c in ipairs(spec.f.clauses) do
    local r = details.results[i]
    if c.kind == 'soul_in_pack' and r and r.ok then
      return r.blind == 'Big' and #r.packs == 1
    end
  end
  return false
end

-- Seed i of filter n: 8 characters from vanilla's seed alphabet (no 0/O).
local ALPHA = '123456789ABCDEFGHIJKLMNPQRSTUVWXYZ'
local function seed_of(n, i)
  local out, x = {}, (i * 2654435761 + n * 104729) % ((#ALPHA) ^ 7)
  for k = 1, 7 do
    local d = x % #ALPHA
    out[k] = ALPHA:sub(d + 1, d + 1)
    x = math.floor(x / #ALPHA)
  end
  return ALPHA:sub(n + 20, n + 20)..table.concat(out)
end

local hits = {}     -- {filter = spec, seed, details}
local verified = 0
local big_verified = 0

local function fail(ctx, seed, what, want, got)
  ctx.log(string.format('MISMATCH %s %s: predicted %s, real %s', seed, what, tostring(want), tostring(got)))
  ctx.assert(false, seed..': '..what..' mismatch (predicted '..tostring(want)..', real '..tostring(got)..')')
end

local function expect(ctx, seed, what, want, got)
  if want ~= got then fail(ctx, seed, what, want, got) end
  ctx.log(string.format('%s %s: predicted %s, real %s', seed, what, tostring(want), tostring(got)))
end

local TURBO = 8
local function turbo()
  for _ = 1, TURBO do G:update(1/20) end
end

local function run_ready(seed)
  return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
    and G.GAME.pseudorandom and G.GAME.pseudorandom.seed == seed
    and G.GAME.round_resets.blind_tags and G.GAME.round_resets.blind_tags.Big ~= nil
    and not G.CONTROLLER.locks.load
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

local PACK_STATES = nil
local function in_pack_state()
  if not PACK_STATES then
    PACK_STATES = {[G.STATES.TAROT_PACK] = true, [G.STATES.PLANET_PACK] = true,
      [G.STATES.SPECTRAL_PACK] = true, [G.STATES.STANDARD_PACK] = true, [G.STATES.BUFFOON_PACK] = true}
  end
  return PACK_STATES[G.STATE]
end

local function shop_settled()
  return G.STATE == G.STATES.SHOP and G.shop and G.shop_booster and G.shop_jokers
    and not G.CONTROLLER.locks.shop_reroll and not G.CONTROLLER.locks.use
    and not G.CONTROLLER.locks.toggle_shop
end

-- The clauses a hit claims: every evaluated clause that came out true.
local function claimed(hit)
  local out = {}
  for i, c in ipairs(hit.spec.f.clauses) do
    local r = hit.details.results[i]
    if r and r.ok then out[#out + 1] = {clause = c, res = r} end
  end
  return out
end

-- Checks the blind-select clauses; returns the from_tag / shop targets.
local function check_blind_select(ctx, hit)
  local seed = hit.seed
  local soul, shop
  for _, cr in ipairs(claimed(hit)) do
    local c, r = cr.clause, cr.res
    if c.kind == 'tag' then
      local rt = G.GAME.round_resets.blind_tags
      if c.blind == 'Small' or c.blind == 'Big' then
        expect(ctx, seed, 'ante 1 '..c.blind..' tag', c.key, rt[c.blind])
      else
        ctx.assert(rt.Small == c.key or rt.Big == c.key, seed..': no '..c.key..' at ante 1')
      end
    elseif c.kind == 'boss' then
      expect(ctx, seed, 'ante 1 boss', c.key, G.GAME.round_resets.blind_choices.Boss)
    elseif c.kind == 'soul_in_pack' then
      soul = {blind = r.blind, index = r.index, pack = r.pack, tag = r.tag, play_small = hit.big}
      for _, pk in ipairs(r.packs) do
        if pk.blind == r.blind then soul.cards = pk.cards end
      end
      expect(ctx, seed, r.blind..' tag (pack source)', r.tag, G.GAME.round_resets.blind_tags[r.blind])
      if hit.big then
        local small = G.GAME.round_resets.blind_tags.Small
        ctx.log(seed..': Small tag '..tostring(small)..' (played, not skipped)')
        ctx.assert(small ~= 'tag_charm' and small ~= 'tag_ethereal', seed..': Small tag opens a pack')
      end
    elseif c.kind == 'shop_joker' then
      shop = shop or {ante = c.ante, shop = r.shop, slot = r.slot, key = c.key}
    else
      ctx.assert(false, 'scenario has no real-game check for '..c.kind)
    end
  end
  return soul, shop
end

-- One hit, replayed in a real run.
local function verify_step(hit)
  return function(ctx)
    local p = hit.p
    p.frames = p.frames + 1
    local function go(phase) p.phase, p.frames = phase, 0 end
    local waited = p.frames
    local seed = hit.seed
    if p.phase ~= 'start' and p.phase ~= 'ready' then turbo() end

    if p.phase == 'start' then
      ctx.start_run{seed = seed, stake = 1}
      go('ready')
    elseif p.phase == 'ready' then
      if not run_ready(seed) or waited < 2 then return false end
      ctx.assert(G.GAME.stake == 1 and G.GAME.selected_back.name == 'Red Deck', seed..': not stake 1 Red Deck')
      p.soul, p.shop = check_blind_select(ctx, hit)
      if p.soul and p.soul.play_small then go('select')
      elseif p.soul then go('skip')
      elseif p.shop then p.shops = {}; go('select')
      else go('done') end
    elseif p.phase == 'done' then
      verified = verified + 1
      if hit.big then big_verified = big_verified + 1 end
      ctx.log('check: hit '..seed..' '..hit.spec.id..' ok')
      return true

    -- charm_soul: skip blinds until the predicted blind's pack is open.
    elseif p.phase == 'skip' then
      if G.STATE ~= G.STATES.BLIND_SELECT or waited < 3 or G.CONTROLLER.locks.skip_blind then return false end
      local kind = G.GAME.blind_on_deck
      ctx.assert(kind == 'Small' or kind == 'Big', seed..': ran past the Big blind')
      ctx.assert(not p.soul.play_small or kind == 'Big', seed..': Small blind still on deck after its round')
      local btn = panel_button(kind, 'skip_blind')
      if not btn then return false end
      p.skipped = kind
      if hit.shot and kind == p.soul.blind then ctx.shot(p.label..'_skip') end
      G.FUNCS.skip_blind(btn)
      go('after_skip')
    elseif p.phase == 'after_skip' then
      if in_pack_state() and G.pack_cards and G.pack_cards.cards and G.booster_pack
        and #G.pack_cards.cards >= (G.GAME.pack_size or 1) and waited >= 3 then
        if p.skipped == p.soul.blind then go('pack') else go('close_other') end
        return false
      end
      -- A skip whose tag opens nothing: back to blind select with the next blind on deck.
      if p.skipped ~= p.soul.blind and G.STATE == G.STATES.BLIND_SELECT and G.GAME.blind_on_deck ~= p.skipped
        and waited >= 20 and not G.CONTROLLER.locks.skip_blind then
        go('skip')
      end
    elseif p.phase == 'close_other' then
      ctx.log(seed..': closing the pack (state '..tostring(G.STATE)..') opened by the '..p.skipped..' skip')
      if ctx.click('skip_booster') then go('closing_other') end
    elseif p.phase == 'closing_other' then
      if G.booster_pack or G.STATE ~= G.STATES.BLIND_SELECT or waited < 3 then return false end
      go('skip')
    elseif p.phase == 'pack' then
      if hit.shot and waited < 12 then return false end -- let the cards materialize for the shot
      local got = {}
      for i, c in ipairs(G.pack_cards.cards) do got[i] = c.config.center.key end
      -- G.booster_pack is the pack's UIBox; Card:open leaves the kind in
      -- G.STATE and the size/choices in G.GAME (card.lua:1693, 1709).
      ctx.log(string.format('%s %s pack (size %d, choose %d): real %s', seed, p.skipped, G.GAME.pack_size,
        G.GAME.pack_choices, table.concat(got, ' ')))
      ctx.assert(G.STATE == G.STATES.TAROT_PACK and G.GAME.pack_size == 5 and G.GAME.pack_choices == 2,
        seed..': not a Mega Arcana')
      expect(ctx, seed, p.skipped..' pack slot '..p.soul.index, 'c_soul', got[p.soul.index])
      expect(ctx, seed, p.skipped..' pack contents', table.concat(p.soul.cards, ' '), table.concat(got, ' '))
      if hit.shot then ctx.shot(p.label..'_soul_pack') end
      go('close')
    elseif p.phase == 'close' then
      if waited < 2 then return false end
      if ctx.click('skip_booster') then go('closing') end
    elseif p.phase == 'closing' then
      if G.booster_pack or waited < 3 then return false end
      go('done')

    -- shop_joker: play by the plan policy up to the predicted shop.
    elseif p.phase == 'select' then
      if G.STATE ~= G.STATES.BLIND_SELECT or waited < 2 then return false end
      local kind = G.GAME.blind_on_deck
      local btn = panel_button(kind, 'select_blind')
      if not btn then return false end
      p.kind = kind
      G.FUNCS.select_blind(btn)
      go('play')
    elseif p.phase == 'play' then
      if G.STATE ~= G.STATES.SELECTING_HAND or #G.hand.cards == 0 or waited < 2
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
      if G.STATE ~= G.STATES.ROUND_EVAL or waited < 2 then return false end
      if not ctx.click('cash_out') then return false end
      go('shop')
    elseif p.phase == 'shop' then
      if not shop_settled() or waited < 2 or #G.shop_booster.cards ~= 2
        or #G.shop_jokers.cards ~= G.GAME.shop.joker_max then return false end
      if p.soul then
        -- big_charm: the Small blind's shop, left as the plan policy leaves it.
        if not ctx.click('toggle_shop') then return false end
        ctx.log(seed..': Small blind won, shop left; skipping the Big blind')
        go('skip')
        return false
      end
      local a = G.GAME.round_resets.ante
      p.shops[a] = (p.shops[a] or 0) + 1
      local row = {}
      for i, c in ipairs(G.shop_jokers.cards) do row[i] = c.config.center.key end
      ctx.log(string.format('%s ante %d shop %d: real %s', seed, a, p.shops[a], table.concat(row, ' ')))
      if a == p.shop.ante and p.shops[a] == p.shop.shop then
        expect(ctx, seed, 'ante '..a..' shop '..p.shops[a]..' slot '..p.shop.slot, p.shop.key, row[p.shop.slot])
        if hit.shot then ctx.shot('shop_joker') end
        go('done')
        return false
      end
      ctx.assert(a <= p.shop.ante, seed..': ran past the predicted shop')
      if not ctx.click('toggle_shop') then return false end
      go('select')
    end
    return false
  end
end

local steps = {
  {name = 'speed up', run = function()
    love.window.setVSync(0)
    G.SETTINGS.GAMESPEED = 64
    return true
  end},
}

for n, spec in ipairs(FILTERS) do
  local scan = {i = 0, found = 0, want = 0, t = 0}
  local need = spec.hits or HITS
  steps[#steps + 1] = {name = 'scan '..spec.id, timeout = 60, run = function(ctx)
    if scan.i == 0 then
      local ok, err = filter.validate(spec.f)
      ctx.assert(ok, spec.id..': '..tostring(err))
      scan.before = STR_PACK(G.GAME)
    end
    local t0 = love.timer.getTime()
    while scan.want < need and scan.i < MAX_SEEDS and love.timer.getTime() - t0 < SCAN_BUDGET do
      scan.i = scan.i + 1
      local seed = seed_of(n, scan.i)
      local ok, details = filter.eval_seed(spec.f, seed)
      if ok then
        scan.found = scan.found + 1
        local big = big_path(spec, details)
        if big or spec.id ~= 'big_charm' then scan.want = scan.want + 1 end
        hits[#hits + 1] = {spec = spec, seed = seed, details = details, big = big,
          p = {phase = 'start', frames = 0, label = spec.id == 'charm_soul' and 'charm' or spec.id},
          shot = scan.want == 1 and (big or spec.id ~= 'big_charm') and not scan.shot}
        scan.shot = scan.shot or hits[#hits].shot
        ctx.log(string.format('scan %s: hit %d = %s%s', spec.id, scan.found, seed,
          spec.id == 'big_charm' and (big and ' (Big path)' or ' (Small pack tag: skip path)') or ''))
      end
    end
    scan.t = scan.t + (love.timer.getTime() - t0)
    if scan.want < need and scan.i < MAX_SEEDS then return false end
    ctx.assert(STR_PACK(G.GAME) == scan.before, 'scan touched the live G.GAME')
    ctx.log(string.format('scan %s: %d hits in %d seeds, %.0f seeds/s', spec.id, scan.found, scan.i, scan.i / scan.t))
    ctx.assert(scan.want >= need, spec.id..': only '..scan.want..' usable hits in '..scan.i..' seeds')
    return true
  end}
end

-- The verify steps are added once the scans know the hits: one step expands
-- into the list on its first run.
steps[#steps + 1] = {name = 'verify hits', timeout = 90, run = function(ctx)
  hits.at = hits.at or 1
  local hit = hits[hits.at]
  if not hit then return true end
  hit.run = hit.run or verify_step(hit)
  if hit.run(ctx) then hits.at = hits.at + 1 end
  return false
end}

steps[#steps + 1] = {name = 'report', run = function(ctx)
  ctx.assert(verified == #hits and verified >= HITS * (#FILTERS - 1) + BIG_HITS, 'verified '..verified..' of '..#hits)
  ctx.assert(big_verified >= BIG_HITS, 'big-blind path: only '..big_verified..' hits verified')
  ctx.log('check: big-blind charm path verified ('..big_verified..' hits: Small played, Big skipped)')
  ctx.log('check: '..verified..' hits verified in real runs')
  ctx.log('check: no false positives')
  return true
end}

return steps
