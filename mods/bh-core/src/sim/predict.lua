-- bhcore.sim.predict: what a seed generates, read off a sim state S by calling
-- vanilla's Card-free primitives, and bhcore.sim.card for every card, inside
-- sim.sandbox (roadmap T1). Contract: docs/bh-core.md § sim.predict.
--
-- API
--   Stable streams
--   predict.tags(S, ante)       -> {small = key, big = key}
--   predict.boss(S, ante)       -> blind key
--   predict.voucher(S, ante)    -> voucher key
--   predict.legendaries(S, n)   -> {{key = 'j_...', edition = 'foil'|'holo'|
--                                  'polychrome'|'negative'|nil}, ...}, n of them:
--                                  the jokers the next n Souls used would make.
--   Conditional streams (cards are {key, set, edition = <name> or nil,
--   stickers = {eternal, perishable, rental}, front = <P_CARDS key> or nil,
--   seal = 'Red'|'Blue'|'Gold'|'Purple' or nil})
--   predict.shop(S, ante, n)    -> n shop cards (default G.GAME.shop.joker_max):
--                                  entering a shop. Releases whatever an earlier
--                                  shop left in S first (that shop's exit).
--   predict.reroll(S, ante)     -> the refilled row after one reroll.
--   predict.packs(S, ante, n)   -> n shop packs (default 2): {{key, kind, size,
--                                  choose, forced = true when it is the run's
--                                  forced first Buffoon}, ...}.
--   predict.pack_contents(S, pack_key, ante) -> the cards that pack shows when
--                                  opened now; released again on return (the
--                                  pack closed with nothing taken).
--   predict.leave_shop(S)       -> nil: the shop's exit, releasing its cards.
--   predict.plan(S, opts)       -> ante records, every call above in the
--                                  game's order (see Plan).
--   predict.ante_walk(S, a, policy) -> one ante's shops and tag packs in play
--                                  order under skip / reroll / open choices
--                                  (see Ante walk).
-- Each call sets S.game.round_resets.ante to `ante` (legendaries uses S's ante
-- as it stands), advances S's streams exactly as the game would, and must be
-- made in the game's order below. Errors raised inside the sandbox are
-- re-raised; the live run is untouched either way (sim.sandbox guarantee).
-- The cards of the shop in progress are kept in S.game.bh_shop (a list of
-- keys, deep-copied with S; vanilla never reads it) so reroll and leave_shop
-- can release them.
--
-- Order contract: what the game draws, and when
--   Ante 1, Game:start_run (game.lua:2177-2180), in this order:
--     boss ('boss'), voucher ('Voucher1'), Small tag, Big tag ('Tag1' twice).
--   Ante A -> A+1, after the Boss of ante A is beaten:
--     end_round queues ease_ante(1) (state_events.lua:248), then in a later
--     event draws the voucher for the NEW ante (state_events.lua:263,
--     'Voucher'..A+1); cash_out then draws the Small and Big tags
--     (button_callbacks.lua:2951-2952, 'Tag'..A+1) and reset_blinds draws the
--     boss (button_callbacks.lua:2954 -> common_events.lua:2333, 'boss').
--   So a run goes: boss1 voucher1 tags1 | voucher2 tags2 boss2 | voucher3 ...
--   What that means for callers:
--     * 'boss' has no ante in its key and get_new_boss bumps
--       G.GAME.bosses_used (least-used filter), so boss(S, a) must be called
--       exactly once per ante, in ascending ante order, and once more for
--       every boss reroll the player makes (not modelled here).
--     * 'Tag'..A and 'Voucher'..A are per-ante streams nothing else draws, so
--       relative to each other and to the boss their order does not matter;
--       each must still be called once per ante (a second call is the next
--       draw of that stream, e.g. a revisited ante).
--     * The Soul's joker comes from 'Joker4' (global, no ante). Nothing else
--       draws it, so legendaries(S, n) can be called at any point; it records
--       the keys in S.game.used_jokers, so a later call continues the sequence
--       the way holding the earlier legendaries would.
--   Shops. The shop after a blind reads G.GAME.round_resets.ante as it is
--   then, and the Boss's shop comes after ease_ante: so "the shops of ante A"
--   here are the ones drawing ante-A streams, i.e. the shop after the Boss of
--   ante A-1 and those after the Small and Big blinds of ante A. Ante 1 has at
--   most 2 (no shop precedes its Small blind); every later ante has 3.
--   Inside one shop (game.lua:3111-3163), in this order:
--     shop(S, a): joker_max x create_card_for_shop (UI_definitions.lua:742-799):
--       'cdt'..A type roll ('illusion' too with Illusion), then create_card's
--       draws with append 'sho' (sim.card.shop_card);
--     packs(S, a, 2): 2 x get_pack('shop_pack') ('shop_pack'..A,
--       common_events.lua:1944-1961). The run's first call instead returns a
--       Buffoon Pack with no draw (first_shop_buffoon); its _1/_2 art variant
--       is unseeded math.random (cosmetic), reported as p_buffoon_normal_1
--       with forced = true.
--     reroll(S, a) per reroll (button_callbacks.lua:2855-2891): every shop card
--       is removed first (Card:remove, releasing used_jokers), then joker_max
--       cards are made, continuing the same 'cdt'..A / '...sho'..A streams.
--     pack_contents(S, key, a) per pack opened (Card:open, card.lua:1715-1768),
--       made while the shop's cards are still in used_jokers:
--       Arcana    'omen_globe' (Omen Globe only) -> Spectral 'ar2' or Tarot
--                 'ar1', soulable;
--       Celestial Planet 'pl1', soulable; with Telescope card 1 is the most
--                 played hand's planet as a forced key (no soul roll, no pool
--                 draw);
--       Spectral  Spectral 'spe', soulable (two 'soul_Spectral'..A draws);
--       Standard  'stdset'..A picks Enhanced/Base, create_card 'sta', then
--                 poll_edition('standard_edition'..A, 2, no negative),
--                 'stdseal'..A and, on a hit, 'stdsealtype'..A;
--       Buffoon   Joker 'buf' (rarity, pool, 'packetper'/'packssjr', 'edibuf').
--     leave_shop(S): G.shop:remove() removes the unbought cards (Card:remove).
--   Every shop and pack stream is keyed by ante only, never by shop: the up to
--   3 shops of an ante, their rerolls and every pack of a kind opened in the
--   ante (tag packs too) share one position counter per stream. A later ante's
--   streams are independent of how many shops an earlier ante had.
--
-- Plan: predict.plan(S, {antes = N, shops_per_ante = 1..3, rerolls = 0,
--   open_packs = true}) -> {{ante, tags = {small, big}, boss, voucher,
--   soul = {key, edition}, shops = {{cards, packs, rerolls = {{cards}...}}...},
--   pack_contents = {[i] = {cards...}}, certainty = {<field> = ...}}...}
--   S must be a run at Game:start_run before its first generation
--   (state.fresh). The policy: no skips, no purchases, no Souls used, no boss
--   rerolls, no tags held. Per ante it calls, in the game's order: (ante 1)
--   boss, voucher, tags, or (ante A > 1) voucher, tags, boss; then for each of
--   the ante's first min(shops_per_ante, 2 or 3) shops: shop, packs(2),
--   `rerolls` rerolls, then with open_packs each pack in slot order through
--   pack_contents, then leave_shop. shops_per_ante < the ante's count is exact
--   for any choice of skipped blinds (the streams count shops, not blinds),
--   as long as the skip tags themselves do not reach the shop. Pack i of the
--   ante is shop ceil(i/2)'s slot 2-(i%2); packs[j].index names it.
--   soul is the joker a Soul used during that ante would make (predicted on a
--   copy of S: under the policy no Soul is used, so S's 'Joker4' is untouched).
--
-- Certainty (roadmap T4). plan labels each field in record.certainty (and in
-- the field itself when it is a table):
--   tags: stable. Their pool depends on the ante (min_ante) and on profile
--     discovery of each tag's `requires` (S.all_unlocked, or the live profile).
--     Ante 1's tags are 'conditional' while G.SETTINGS.tutorial_progress has
--     forced_tags: start_run then uses those instead (game.lua:2179-2180).
--   boss: stable without rerolls (Director's Cut, Retcon, Boss Tag draw 'boss').
--   voucher: the draw index is stable; the key is conditional on
--     S.game.used_vouchers (purchases, tier-2 `requires`) and profile unlocks.
--     (A tutorial forced_voucher replaces ante 1's, game.lua:2178.)
--   legendaries / soul: the key sequence is stable while no legendary leaves
--     play (Card:remove clears used_jokers) and Showman is not held. The
--     edition uses 'edisou'..A of the ante the Soul is used in.
--   shops, packs, pack_contents: conditional on the declared policy (every
--     reroll, purchase, skip, held joker/consumable, voucher, tag and rate
--     change moves them). A tutorial forced_shop replaces the first shop cards
--     (UI_definitions.lua:743-751): not modelled, labelled by the conditional.
--   Deck effects applied by events (Magic, Zodiac, Nebula...: rates, slots,
--   vouchers) are not in a state.fresh() S; see docs/bh-core.md § sim.state.
--
-- Ante walk: predict.ante_walk(S, a, {skip = {Small = bool, Big = bool},
--   rerolls = R (0), open = bool (true), cards = bool (true),
--   tags = {small, big} or nil, pack_tags = set of tag keys (TAG_PACKS)}) ->
--   {tags = {small, big},
--    shops = {{after = 'Boss'|'Small'|'Big', cards, rerolls = {{cards}...},
--              packs, contents = {[slot] = {cards...}}}...},
--    tag_packs = {{blind, tag, pack, cards}...}}
--   One ante as it is played, drawing on S in the game's order: (a > 1) the
--   shop after the Boss of ante a-1 (it comes after ease_ante, so it draws
--   ante-a streams); then per blind, Small first, either its skip or its shop.
--   A skipped blind has no shop. Skipping a blind whose tag gives a pack opens
--   that pack at the skip (skip_blind -> Tag:apply_to_run 'new_blind_choice',
--   button_callbacks.lua:2772-2777 -> tag.lua:206-282, Card:open on ante-a
--   streams), closed with nothing taken. predict.ALL_TAG_PACKS:
--     Charm Tag    -> p_arcana_mega_1 (its _1/_2 art variant is unseeded
--                     math.random with the same config);
--     Meteor Tag   -> p_celestial_mega_1 (same);
--     Ethereal Tag -> p_spectral_normal_1;
--     Standard Tag -> p_standard_mega_1;
--     Buffoon Tag  -> p_buffoon_mega_1 (Card:open, not get_pack: the run's
--                     forced first Buffoon is untouched).
--   policy.pack_tags is the set of tags whose pack the walk opens (any table
--   whose keys are tag keys with a truthy value, ALL_TAG_PACKS itself
--   included; a key outside ALL_TAG_PACKS raises). The default is
--   predict.TAG_PACKS, Charm and Ethereal only: every other tag is skipped
--   without a pack, which for Meteor, Standard and Buffoon means the walk is
--   conditional on the player leaving their pack's draws alone (the real
--   game opens it). Tags that act on later shops or the jokers (Uncommon, Rare,
--   edition tags, Top-up, Double, Boss...) are not modelled: a walk that skips
--   one is conditional on it. Each shop: shop (unless cards = false), packs(2),
--   R rerolls, then with open every pack in slot order through pack_contents,
--   then leave_shop. cards = false draws pack keys only (no 'cdt' / 'sho'
--   draws; the pack streams do not depend on them) and requires open = false,
--   since pack contents exclude the row's cards. Shop pack j carries index,
--   its position among the ante's shop packs in this walk.
--   Tags: policy.tags when the caller has drawn them already; otherwise the
--   walk draws tags(S, a) itself ('Tag'..a is a per-ante stream nothing else
--   draws, so its place in the order is free; it must not be drawn twice).
--   Boss and voucher are not drawn. The run's forced first Buffoon lands in
--   whichever shop is the run's first: plan's ante 1 shop 1, or, when ante 1's
--   Small and Big are both skipped, the shop after its Boss (ante 2 shop 1).
--   A caller walking ante a > 1 without having walked the earlier antes decides
--   where it went (seedfinder.filter spends it with packs(S, 1, 1)).
--   Checked against the real game by rig/scenarios/golden_walk.lua (Charm,
--   Ethereal) and rig/scenarios/golden_tagpacks.lua (Meteor, Standard,
--   Buffoon under pack_tags = ALL_TAG_PACKS).
--
-- The Soul (card.lua:1415-1421) is create_card('Joker', G.jokers, legendary,
-- ..., 'sou'): legendaries() calls sim.card with those arguments.
local sandbox = require('bhcore.sim.sandbox')
local card = require('bhcore.sim.card')
local state = require('bhcore.sim.state')

local M = {}

local function check(S, ante, who)
  assert(type(S) == 'table' and type(S.game) == 'table', 'predict.'..who..': not a sim state')
  if ante ~= nil then
    assert(type(ante) == 'number' and ante >= 1 and ante % 1 == 0, 'predict.'..who..': bad ante '..tostring(ante))
  end
end

local function check_n(n, who)
  assert(n == nil or (type(n) == 'number' and n >= 0 and n % 1 == 0), 'predict.'..who..': bad n '..tostring(n))
end

local function run(S, fn, ...)
  local res = {sandbox.run(S, fn, ...)}
  if not res[1] then error(res[2], 3) end
  return unpack(res, 2)
end

local function at_ante(ante)
  G.GAME.round_resets.ante = ante
end

function M.tags(S, ante)
  check(S, ante, 'tags')
  return run(S, function()
    at_ante(ante)
    local small = get_next_tag_key()
    local big = get_next_tag_key()
    return {small = small, big = big}
  end)
end

function M.boss(S, ante)
  check(S, ante, 'boss')
  return run(S, function()
    at_ante(ante)
    return get_new_boss()
  end)
end

function M.voucher(S, ante)
  check(S, ante, 'voucher')
  return run(S, function()
    at_ante(ante)
    return get_next_voucher_key()
  end)
end

local function edition_name(e)
  if type(e) ~= 'table' then return nil end
  for _, name in ipairs{'negative', 'polychrome', 'holo', 'foil'} do
    if e[name] then return name end
  end
end

-- A sim.card result as a plain prediction record.
local function record(c)
  local s = c.stickers or {}
  return {key = c.key, set = c.set, edition = edition_name(c.edition), front = c.front, seal = c.seal,
    stickers = {eternal = s.eternal or false, perishable = s.perishable or false, rental = s.rental or false}}
end

function M.legendaries(S, n)
  check(S, nil, 'legendaries')
  assert(type(n) == 'number' and n >= 0 and n % 1 == 0, 'predict.legendaries: bad n '..tostring(n))
  return run(S, function()
    G.GAME.used_jokers = G.GAME.used_jokers or {}
    local out = {}
    for i = 1, n do
      local c = card.create{type = 'Joker', area = 'other', legendary = true, key_append = 'sou'}
      out[i] = {key = c.key, edition = edition_name(c.edition)}
    end
    return out
  end)
end

-- Shop bookkeeping inside the sandbox: G.GAME is S.game there.
local function shop_keys()
  G.GAME.bh_shop = G.GAME.bh_shop or {}
  return G.GAME.bh_shop
end

-- Card:remove on every card of the shop row, last first (reroll_shop's loop).
local function release_shop()
  local keys = shop_keys()
  for i = #keys, 1, -1 do
    card.release(keys[i])
    keys[i] = nil
  end
end

local function fill_shop(n)
  local keys, out = shop_keys(), {}
  for _ = 1, n do
    local c = card.shop_card()
    if c then
      keys[#keys + 1] = c.key
      out[#out + 1] = record(c)
    end
  end
  return out
end

local function joker_max()
  return (G.GAME.shop and G.GAME.shop.joker_max) or 2
end

function M.shop(S, ante, n)
  check(S, ante, 'shop')
  check_n(n, 'shop')
  return run(S, function()
    at_ante(ante)
    G.GAME.used_jokers = G.GAME.used_jokers or {}
    release_shop()
    return fill_shop(n or joker_max())
  end)
end

function M.reroll(S, ante)
  check(S, ante, 'reroll')
  return run(S, function()
    at_ante(ante)
    release_shop()
    return fill_shop(joker_max())
  end)
end

function M.leave_shop(S)
  check(S, nil, 'leave_shop')
  run(S, release_shop)
end

function M.packs(S, ante, n)
  check(S, ante, 'packs')
  check_n(n, 'packs')
  return run(S, function()
    at_ante(ante)
    local out = {}
    for i = 1, n or 2 do
      local forced = not G.GAME.first_shop_buffoon and not G.GAME.banned_keys['p_buffoon_normal_1']
      local center = get_pack('shop_pack')
      local key = forced and 'p_buffoon_normal_1' or center.key
      local c = G.P_CENTERS[key]
      out[i] = {key = key, kind = c.kind, size = c.config.extra, choose = c.config.choose,
        forced = forced or nil}
    end
    return out
  end)
end

-- Telescope's forced first planet: the most played visible hand's planet.
local function telescope_planet()
  local best, tally = nil, 0
  for _, h in ipairs(G.handlist or {}) do
    local hand = G.GAME.hands[h]
    if hand and hand.visible and hand.played > tally then best, tally = h, hand.played end
  end
  if not best then return nil end
  local planet
  for _, v in pairs(G.P_CENTER_POOLS.Planet) do
    if v.config.hand_type == best then planet = v.key end
  end
  return planet
end

local SEALS = {{0.75, 'Red'}, {0.5, 'Blue'}, {0.25, 'Gold'}}

local function standard_card(ante)
  local t = pseudorandom(pseudoseed('stdset'..ante)) > 0.6 and 'Enhanced' or 'Base'
  local c = card.create{type = t, area = 'pack', soulable = true, key_append = 'sta'}
  c.edition = poll_edition('standard_edition'..ante, 2, true)
  if pseudorandom(pseudoseed('stdseal'..ante)) > 1 - 0.02 * 10 then
    local roll = pseudorandom(pseudoseed('stdsealtype'..ante))
    c.seal = 'Purple'
    for _, s in ipairs(SEALS) do
      if roll > s[1] then c.seal = s[2]; break end
    end
  end
  return c
end

local function pack_card(name, i, ante)
  local vouchers = G.GAME.used_vouchers or {}
  if name:find('Arcana') then
    if vouchers.v_omen_globe and pseudorandom('omen_globe') > 0.8 then
      return card.create{type = 'Spectral', area = 'pack', soulable = true, key_append = 'ar2'}
    end
    return card.create{type = 'Tarot', area = 'pack', soulable = true, key_append = 'ar1'}
  elseif name:find('Celestial') then
    local forced = vouchers.v_telescope and i == 1 and telescope_planet() or nil
    return card.create{type = 'Planet', area = 'pack', soulable = true, forced_key = forced, key_append = 'pl1'}
  elseif name:find('Spectral') then
    return card.create{type = 'Spectral', area = 'pack', soulable = true, key_append = 'spe'}
  elseif name:find('Standard') then
    return standard_card(ante)
  elseif name:find('Buffoon') then
    return card.create{type = 'Joker', area = 'pack', soulable = true, key_append = 'buf'}
  end
  error('predict.pack_contents: not a booster kind: '..tostring(name))
end

function M.pack_contents(S, pack_key, ante)
  check(S, ante, 'pack_contents')
  local center = G.P_CENTERS and G.P_CENTERS[pack_key]
  assert(type(center) == 'table' and center.set == 'Booster', 'predict.pack_contents: not a pack '..tostring(pack_key))
  return run(S, function()
    at_ante(ante)
    G.GAME.used_jokers = G.GAME.used_jokers or {}
    local out, keys = {}, {}
    for i = 1, center.config.extra do
      local c = pack_card(center.name, i, ante)
      keys[i] = c.key
      out[i] = record(c)
    end
    -- The pack closes with nothing taken: its cards are removed.
    for i = #keys, 1, -1 do card.release(keys[i]) end
    return out
  end)
end

local function tutorial()
  local t = G and G.SETTINGS and G.SETTINGS.tutorial_progress
  return type(t) == 'table' and t or {}
end

function M.plan(S, opts)
  check(S, nil, 'plan')
  opts = opts or {}
  local antes = opts.antes or 1
  local per = opts.shops_per_ante or 3
  local rerolls = opts.rerolls or 0
  local open = opts.open_packs ~= false
  local cards = opts.cards ~= false  -- false: tags, boss and voucher only, nothing that makes a card
  assert(type(antes) == 'number' and antes >= 1 and antes % 1 == 0, 'predict.plan: bad antes '..tostring(antes))
  assert(type(per) == 'number' and per >= 1 and per <= 3 and per % 1 == 0, 'predict.plan: shops_per_ante is 1..3')
  assert(type(rerolls) == 'number' and rerolls >= 0 and rerolls % 1 == 0, 'predict.plan: bad rerolls')
  local tut = tutorial()

  local out = {}
  for a = 1, antes do
    local rec = {ante = a, shops = {}, pack_contents = {}}
    local tags
    if a == 1 then
      rec.boss = M.boss(S, 1)
      rec.voucher = M.voucher(S, 1)
      tags = M.tags(S, 1)
    else
      rec.voucher = M.voucher(S, a)
      tags = M.tags(S, a)
      rec.boss = M.boss(S, a)
    end
    local forced_tags = a == 1 and tut.forced_tags ~= nil
    tags.certainty = forced_tags and 'conditional' or 'stable'
    rec.tags = tags

    if cards then
      local soul_S = state.copy(S)
      soul_S.game.round_resets.ante = a
      rec.soul = M.legendaries(soul_S, 1)[1]
      rec.soul.certainty = 'stable'
    end

    local pack_i = 0
    for s = 1, cards and math.min(per, a == 1 and 2 or 3) or 0 do
      local shop = {cards = M.shop(S, a), rerolls = {}, certainty = 'conditional'}
      shop.packs = M.packs(S, a, 2)
      for r = 1, rerolls do shop.rerolls[r] = {cards = M.reroll(S, a)} end
      for _, p in ipairs(shop.packs) do
        pack_i = pack_i + 1
        p.index = pack_i
        if open then rec.pack_contents[pack_i] = M.pack_contents(S, p.key, a) end
      end
      M.leave_shop(S)
      rec.shops[s] = shop
    end
    rec.certainty = {
      tags = tags.certainty, boss = 'stable', voucher = 'conditional', soul = 'stable',
      shops = 'conditional', packs = 'conditional', pack_contents = 'conditional',
    }
    out[a] = rec
  end
  return out
end

-- The pack a pack-giving tag opens at the skip (header: Ante walk). TAG_PACKS
-- is ante_walk's default pack_tags and seedfinder.filter's skip set, so it
-- stays these two; ALL_TAG_PACKS is every tag that opens a pack at the skip,
-- for callers that opt in with policy.pack_tags (T-324a).
M.TAG_PACKS = {tag_charm = 'p_arcana_mega_1', tag_ethereal = 'p_spectral_normal_1'}
M.ALL_TAG_PACKS = {
  tag_charm = 'p_arcana_mega_1',        -- tag.lua:209-222, 'p_arcana_mega_'..math.random(1,2)
  tag_meteor = 'p_celestial_mega_1',    -- tag.lua:224-237, 'p_celestial_mega_'..math.random(1,2)
  tag_ethereal = 'p_spectral_normal_1', -- tag.lua:239-252
  tag_standard = 'p_standard_mega_1',   -- tag.lua:254-267
  tag_buffoon = 'p_buffoon_mega_1',     -- tag.lua:269-282
}

local function walk_shop(S, a, after, pol, walk)
  local shop = {after = after, rerolls = {}, contents = {}}
  if pol.cards then shop.cards = M.shop(S, a) end
  shop.packs = M.packs(S, a, 2)
  if pol.cards then
    for r = 1, pol.rerolls do shop.rerolls[r] = {cards = M.reroll(S, a)} end
  end
  for j, p in ipairs(shop.packs) do
    walk.pack_i = walk.pack_i + 1
    p.index = walk.pack_i
    if pol.open then shop.contents[j] = M.pack_contents(S, p.key, a) end
  end
  if pol.cards then M.leave_shop(S) end
  return shop
end

function M.ante_walk(S, a, policy)
  check(S, a, 'ante_walk')
  policy = policy or {}
  assert(type(policy) == 'table', 'predict.ante_walk: policy must be a table')
  local skip = policy.skip or {}
  assert(type(skip) == 'table', 'predict.ante_walk: skip must be {Small = bool, Big = bool}')
  local pol = {rerolls = policy.rerolls or 0, open = policy.open ~= false, cards = policy.cards ~= false}
  assert(type(pol.rerolls) == 'number' and pol.rerolls >= 0 and pol.rerolls % 1 == 0,
    'predict.ante_walk: bad rerolls '..tostring(pol.rerolls))
  assert(pol.cards or not pol.open, 'predict.ante_walk: open needs cards (pack contents exclude the row)')
  local pack_tags = policy.pack_tags or M.TAG_PACKS
  assert(type(pack_tags) == 'table', 'predict.ante_walk: pack_tags must be a set of tag keys')
  for tag, on in pairs(pack_tags) do
    assert(not on or M.ALL_TAG_PACKS[tag], 'predict.ante_walk: '..tostring(tag)..' gives no pack')
  end
  local tags = policy.tags
  if tags ~= nil then
    assert(type(tags) == 'table' and type(tags.small) == 'string' and type(tags.big) == 'string',
      'predict.ante_walk: tags must be {small = key, big = key}')
  else
    tags = M.tags(S, a)
  end

  local walk = {tags = {small = tags.small, big = tags.big}, shops = {}, tag_packs = {}, pack_i = 0}
  if a > 1 then walk.shops[1] = walk_shop(S, a, 'Boss', pol, walk) end
  for _, blind in ipairs{'Small', 'Big'} do
    if skip[blind] then
      local tag = blind == 'Small' and tags.small or tags.big
      local pack = pack_tags[tag] and M.ALL_TAG_PACKS[tag]
      if pack then
        walk.tag_packs[#walk.tag_packs + 1] = {blind = blind, tag = tag, pack = pack,
          cards = M.pack_contents(S, pack, a)}
      end
    else
      walk.shops[#walk.shops + 1] = walk_shop(S, a, blind, pol, walk)
    end
  end
  walk.pack_i = nil
  return walk
end

return M
