-- seedoracle.oracle: the Oracle's model -- what the current seed will show in
-- the current ante and the next two. Contract: docs/contracts-0.2.md
-- § SeedOracle (with the wave-C amendment).
--
-- API
--   oracle.install()   subscribes to the bh-core events. Runs once.
--   oracle.get()       model, pending: the model for the live run, recomputed
--                      first when an event invalidated it and the throttle
--                      allows; nil outside a run or inside a sim. `pending`
--                      is true when the throttle held back a recompute (ask
--                      again after THROTTLE seconds). See Model.
--   oracle.invalidate()  marks the model stale (the events call it).
--   oracle.stats       {computes = n, stable_plans = n, whatifs = n,
--                      whatif_live = n}: how often each source actually ran
--                      (smoke checks and the throttle use it). whatif_live
--                      counts live-model computes or invalidations made while
--                      a what-if walk runs: it must stay 0 (invariant 6).
--
-- Two sources (the amendment: predict.plan is only valid on a fresh S)
--   stable       tags, boss, voucher and the Soul's legendary per ante, from
--                predict.plan(state.fresh(seed, {stake, deck})). Cached per
--                (seed, stake, deck); recomputed only when a later ante than
--                the cached plan covers is asked for. plan() rejects
--                shops_per_ante = 0, so it runs with 1 shop and no packs
--                opened; those shops are discarded (they come after the
--                stable draws of the ante and never feed them).
--   conditional  shops, rerolls, packs and pack contents, from
--                state.capture() of the live run through predict.shop /
--                reroll / packs / pack_contents / leave_shop, in the game's
--                order (predict.lua header), on one S for antes A..A+2:
--                  * in a shop (G.shop exists): "this shop". Its live cards
--                    are put in S.game.bh_shop, so reroll() releases them the
--                    way reroll_shop does; the contents of every pack still on
--                    the shelf (on the copy), REROLLS rerolls, leave_shop.
--                  * otherwise, when a Small or Big blind of ante A is not
--                    yet Defeated/Skipped, "next shop": the next position of
--                    ante A's streams.
--                  * for A+1 and A+2, the first shop drawing that ante's
--                    streams (the Boss shop of the ante before; see
--                    journal/2026-09-23-shop-streams-and-ante-offset.md).
--                Each shop: shop(S, a), packs(S, a, 2), then the pack
--                contents on state.copy(S) taken BEFORE the rerolls (pack by
--                pack in slot order: what the packs hold if opened with the
--                row as shown, before rerolling), then REROLLS rerolls on S,
--                then leave_shop(S). So the chain into later antes is "reroll
--                REROLLS times, open nothing" (pack streams are keyed by ante
--                and a skipped pack releases its cards, so opening packs moves
--                nothing a later ante draws).
--                Everything here is labelled 'conditional' ("if nothing else
--                consumes the stream first").
--
-- Model
--   {seed, stake, deck, ante = A, antes = {rec(A), rec(A+1), rec(A+2)}, error?}
--   rec = {ante, current = bool,
--          tags = {small = item, big = item}, boss = item, voucher = item,
--          soul = item (+ edition),
--          shop = {title = 'This shop'|'Next shop', cards = {card...},
--                  rerolls = {{card...}...}, packs = {pack...},
--                  contents = {[slot] = {card...}}} or nil,  (contents:
--                  if opened before rerolling)
--          shop_note = string or nil}
--   item = {key, badge = 'stable'|'conditional'|'changed'}
--   card = predict's card record {key, set, edition, stickers, front, seal}
--   For the current ante, tags/boss/voucher show the LIVE values (they are
--   the truth); a live value that differs from the plan gets 'changed'. Once
--   a live boss differs, every later boss is 'conditional' for the rest of
--   the run (the 'boss' stream has moved). Once the run owns a voucher,
--   later vouchers are 'conditional' (used_vouchers feeds the pool).
--
-- Throttle: at most one recompute per THROTTLE seconds (love.timer), and
--   never while BHCore.sim_depth > 0. The events invalidate, and so does a
--   change of `moment()` (shop left, reroll, purchase, pack opened: nothing
--   in bh-core fires for those). Either way the work runs
--   when the overlay asks (get), so no prediction ever runs per frame and a
--   shop is read after its cards are placed, not on its first frame.
--
-- What-if (T-322). Per ante, a choice {skip = {Small, Big}, rerolls = 0..5}
-- that re-predicts that ante's shops and tag packs with predict.ante_walk on
-- state.capture() (invariant 6: never the live state). Choices reset when the
-- run changes (run_start, or another seed/stake/deck).
--   oracle.choice(a)            -> {skip = {Small, Big}, rerolls}: ante a's.
--   oracle.set_choice(a, field, value)  field 'Small'|'Big' (bool) or
--                                  'rerolls' (0..WHATIF_REROLLS).
--   oracle.ahead(a, blind)      -> whether skipping `blind` of ante a is still
--                                  a choice (current ante: Select/Upcoming).
--   oracle.whatif(a)            -> nil when every ante from the current one
--                                  up to a is at the default choice (the tab
--                                  shows the model, as before T-322). When an
--                                  earlier ante skips a blind still ahead, ante
--                                  a walks even at its own default (T-326: the
--                                  forced first Buffoon and every shop follow
--                                  those skips; the model's rows do not);
--                                  otherwise, and then,
--                                  {ante, choice, shops = {shop...},
--                                   tag_packs = {{blind, tag, pack, cards}...},
--                                   no_pack = {{blind, tag}...}, error?}
--     shop = {title, after = 'Boss'|'Small'|'Big', cards, rerolls = {{card...}
--             ...}, packs, contents = {[slot] = {card...}}, live = bool}
--     contents are opened in the walk's order: after the rerolls, slot by slot.
--   The walk: S = state.capture() (the shelf on screen put in S.game.bh_shop,
--   as above). Antes before `a` are walked first with their own skips, no
--   rerolls, nothing opened and no shop rows drawn (cards = false: pack keys
--   only, which spends the run's forced first Buffoon where it lands; every
--   other shop and pack stream is keyed by ante). Ante a is walked with its
--   choice. A whole ante goes through predict.ante_walk (with the tags the
--   tab shows); the current ante is usually part-played, and ante_walk always
--   starts at the Boss shop, so the rest of it is walked from where the run
--   stands in ante_walk's own order with the same primitives: the shelf on
--   screen (if any), then each blind still ahead, Small first, its shop or,
--   when skipped, the pack its tag opens (predict.TAG_PACKS). Cached per
--   (moment, ante a's choice, and the skips of every ante from the current
--   one up to a-1: those walks move the forced first Buffoon, e.g. skipping
--   both ante-1 blinds moves it into ante 2's Boss shop; their rerolls are
--   not read). oracle.stats.whatifs counts the walks that ran.
--
-- Divergence (T-323). A tracker S mirrors the run under the model's policy
-- and checks each prediction against the real game as it happens:
--   oracle.divergence()   -> nil, or the first mismatch of this ante:
--                            {ante, shop, what, expected, got, likely,
--                             expected_keys = {key...}, got_keys = {key...}}
--                            (expected/got: card names joined by ", "; what:
--                            'shop row' | 'packs' | 'reroll <k>' |
--                            'pack <slot> contents'; shop: the ante's shop
--                            count, the Boss shop of ante A-1 being ante A's
--                            1st, as in predict).
--   S is state.capture() of the run (the anchor), taken at run start and
--   again once after each divergence, when the game is settled (no pack open,
--   a shop's shelf placed; a shelf on screen goes in S.game.bh_shop as above).
--   Then, never touching the live run and never inside a sim:
--     shop_enter (bh-core)  once the shelf is placed: predict.shop(S, a) and
--                           predict.packs(S, a, 2) against the shelf and the
--                           packs (the forced first Buffoon's _1/_2 art is
--                           unseeded, so either is accepted).
--     G.FUNCS.reroll_shop   the k-th reroll of the shop, k <= REROLLS (the
--                           rerolls the model shows): once refilled, against
--                           predict.reroll(S, a). Later rerolls are not
--                           predicted: they are recorded, not mirrored.
--     Card:open             a shop pack (booster_pos): once its cards are
--                           out, against predict.pack_contents(S, key, a).
--   So S follows exactly the draws the policy makes (enter, the model's
--   rerolls, packs opened and skipped, exit) and nothing else. What the
--   player does besides is recorded as an action since the anchor: a card
--   bought (buy_from_shop), sold (sell_card) or taken from a pack; a
--   Tarot/Spectral used and a voucher bought (use_card); an unpredicted
--   reroll; a skip (bh-core blind_skipped). Every hook calls the original
--   with all its arguments and changes nothing it returns.
--   On the first mismatch: the record, with `likely` the first cause found in
--   this order: a card bought, sold or taken (used_jokers changed), a
--   Tarot/Spectral used, a Soul held (in the consumable slots now), a voucher
--   bought, an unpredicted reroll, a skip; else 'unknown'. Then one
--   invalidate() (the model recomputes from the live state on its next get)
--   and one re-anchor. A later mismatch in the same ante re-anchors again but
--   keeps the first record; ante_change and run_start clear it.
--   oracle.stats: checks (comparisons made), divergences, anchors.
local events = require('bhcore.events')
local state = require('bhcore.sim.state')
local predict = require('bhcore.sim.predict')

local M = {}

M.THROTTLE = 0.5
M.TABS = 3
M.REROLLS = 2
M.MIN_PLAN = 8
M.WHATIF_REROLLS = 5
M.stats = {computes = 0, stable_plans = 0, whatifs = 0, whatif_live = 0, checks = 0, divergences = 0, anchors = 0}

local installed = false
local dirty = true
local last_at = nil
local model = nil
local stable = nil        -- {key, antes, plan}
local boss_moved = false  -- a live boss differed from the plan in this run
local choices = nil       -- {key = run_key(), [ante] = choice}
local whatifs = {}        -- ante -> {at = cache key, res = whatif result}
local in_whatif = 0       -- > 0 while a what-if walk runs (stats.whatif_live)

local function now()
  return love and love.timer and love.timer.getTime() or os.clock()
end

local function in_sim()
  return BHCore ~= nil and (BHCore.sim_depth or 0) > 0
end

local function in_run()
  return G and G.STAGES and G.STAGE == G.STAGES.RUN and type(G.GAME) == 'table'
    and type(G.GAME.pseudorandom) == 'table' and type(G.GAME.pseudorandom.seed) == 'string'
    and type(G.GAME.round_resets) == 'table'
end

local function deck_key()
  local b = G.GAME.selected_back_key
  return type(b) == 'table' and type(b.key) == 'string' and b.key or 'b_red'
end

local function run_key()
  return G.GAME.pseudorandom.seed..'|'..tostring(G.GAME.stake or 1)..'|'..deck_key()
end

local function stable_plan(antes)
  local key = run_key()
  if stable and stable.key == key and stable.antes >= antes then return stable.plan end
  local S = state.fresh(G.GAME.pseudorandom.seed, {stake = G.GAME.stake or 1, deck = deck_key()})
  local plan = predict.plan(S, {antes = antes, shops_per_ante = 1, open_packs = false})
  if not (stable and stable.key == key) then boss_moved = false end
  stable = {key = key, antes = antes, plan = plan}
  M.stats.stable_plans = M.stats.stable_plans + 1
  return plan
end

local function item(key, badge) return {key = key, badge = badge} end

-- The live value of a current-ante field against the plan's.
local function live_item(live, planned)
  if live == nil then return item(planned, 'stable') end
  return item(live, live == planned and 'stable' or 'changed')
end

local function owns_voucher()
  return next(G.GAME.used_vouchers or {}) ~= nil
end

local function stable_rec(plan, a, A)
  local p = plan[a]
  local rec = {ante = a, current = a == A}
  if a == A then
    local rr = G.GAME.round_resets
    local tags = rr.blind_tags or {}
    rec.tags = {small = live_item(tags.Small, p.tags.small), big = live_item(tags.Big, p.tags.big)}
    rec.boss = live_item(rr.blind_choices and rr.blind_choices.Boss, p.boss)
    if rec.boss.badge == 'changed' then boss_moved = true end
    rec.voucher = live_item(G.GAME.current_round and G.GAME.current_round.voucher, p.voucher)
  else
    rec.tags = {small = item(p.tags.small, 'stable'), big = item(p.tags.big, 'stable')}
    rec.boss = item(p.boss, boss_moved and 'conditional' or 'stable')
    rec.voucher = item(p.voucher, owns_voucher() and 'conditional' or 'stable')
  end
  rec.soul = {key = p.soul and p.soul.key, edition = p.soul and p.soul.edition, badge = 'stable'}
  return rec
end

local function card_key(c)
  return c and c.config and c.config.center and c.config.center.key
end

-- One shop on S under the policy: rows, packs, rerolls, contents, exit.
-- `live` = {packs = {pack...}} for the shop already on screen (no new draw).
local function shop_on(S, a, live)
  local shop = {rerolls = {}, contents = {}}
  if live then
    shop.title, shop.cards, shop.packs, shop.live = 'This shop', live.cards, live.packs, true
  else
    shop.title = 'Next shop'
    shop.cards = predict.shop(S, a)
    shop.packs = predict.packs(S, a, 2)
  end
  -- The packs are opened on a copy taken before the rerolls, so their
  -- contents are what they hold with the row as shown.
  local opened = state.copy(S)
  for i, p in ipairs(shop.packs) do
    shop.contents[i] = predict.pack_contents(opened, p.key, a)
  end
  for r = 1, M.REROLLS do shop.rerolls[r] = predict.reroll(S, a) end
  predict.leave_shop(S)
  return shop
end

-- The shop on screen: its cards as records, its unopened packs in slot order.
local function live_shop(S)
  local cards, keys, packs = {}, {}, {}
  for _, c in ipairs(G.shop_jokers and G.shop_jokers.cards or {}) do
    local k = card_key(c)
    if k then
      keys[#keys + 1] = k
      cards[#cards + 1] = {key = k, set = c.config.center.set, edition = c.edition and c.edition.type or nil,
        stickers = {eternal = c.ability.eternal or false, perishable = c.ability.perishable or false,
          rental = c.ability.rental or false}}
    end
  end
  local boosters = {}
  for _, c in ipairs(G.shop_booster and G.shop_booster.cards or {}) do boosters[#boosters + 1] = c end
  table.sort(boosters, function(x, y) return (x.ability.booster_pos or 0) < (y.ability.booster_pos or 0) end)
  for _, c in ipairs(boosters) do
    local center = c.config.center
    packs[#packs + 1] = {key = center.key, kind = center.kind, size = center.config.extra, choose = center.config.choose}
  end
  S.game.bh_shop = keys
  return {cards = cards, packs = packs}
end

local function shops_left(A)
  local st = G.GAME.round_resets.blind_states or {}
  local n = 0
  for _, kind in ipairs{'Small', 'Big'} do
    if st[kind] ~= 'Defeated' and st[kind] ~= 'Skipped' then n = n + 1 end
  end
  return n
end

local function conditional(recs, A)
  local S = state.capture()
  local live
  if G.shop and G.shop_jokers then
    live = live_shop(S)
  end
  for _, rec in ipairs(recs) do
    local a = rec.ante
    if a == A and live then
      rec.shop = shop_on(S, a, live)
    elseif a == A and shops_left(A) == 0 then
      rec.shop_note = 'No shop left in this ante'
    else
      rec.shop = shop_on(S, a)
    end
  end
end

local function compute()
  local A = G.GAME.round_resets.ante
  local plan = stable_plan(math.max(M.MIN_PLAN, A + M.TABS - 1))
  local out = {seed = G.GAME.pseudorandom.seed, stake = G.GAME.stake or 1, deck = deck_key(), ante = A, antes = {}}
  for a = A, A + M.TABS - 1 do out.antes[#out.antes + 1] = stable_rec(plan, a, A) end
  conditional(out.antes, A)
  return out
end

-- What the conditional half reads, as a string. Leaving a shop, a reroll, a
-- purchase or an opened pack fires no bh-core event but moves the shelf or
-- the streams; a model whose moment differs is stale. Only get() computes it,
-- so this costs one STR_PACK of two small tables per overlay open or tab.
local function moment()
  local g = G.GAME
  local n = function(area) return area and area.cards and #area.cards or -1 end
  return table.concat({g.round_resets.ante, g.round or 0, tostring(g.blind_on_deck), G.shop and 'shop' or '-',
    n(G.shop_jokers), n(G.shop_booster), n(G.jokers), n(G.consumeables),
    STR_PACK(g.pseudorandom), STR_PACK(g.used_jokers or {})}, '|')
end

function M.invalidate()
  if in_whatif > 0 then M.stats.whatif_live = M.stats.whatif_live + 1 end
  dirty = true
end

function M.get()
  if not in_run() or in_sim() then return nil end
  local t = now()
  local stale = model == nil or model.seed ~= G.GAME.pseudorandom.seed
  local at = moment()
  if model and model.moment ~= at then dirty = true end
  if dirty or stale then
    if stale or last_at == nil or t - last_at >= M.THROTTLE then
      last_at = t
      dirty = false
      M.stats.computes = M.stats.computes + 1
      if in_whatif > 0 then M.stats.whatif_live = M.stats.whatif_live + 1 end
      local ok, res = pcall(compute)
      if ok then
        model = res
        model.moment = at
      else
        print('[SeedOracle] prediction failed: '..tostring(res))
        model = {seed = G.GAME.pseudorandom.seed, ante = G.GAME.round_resets.ante, antes = {}, error = tostring(res),
          moment = at}
      end
    end
  end
  return model, dirty
end

-- What-if (header: What-if).

local function run_choices()
  local key = run_key()
  if not (choices and choices.key == key) then
    choices, whatifs = {key = key}, {}
  end
  return choices
end

function M.choice(a)
  local c = run_choices()
  c[a] = c[a] or {skip = {Small = false, Big = false}, rerolls = 0}
  return c[a]
end

function M.set_choice(a, field, value)
  if not in_run() then return end
  local c = M.choice(a)
  if field == 'Small' or field == 'Big' then
    c.skip[field] = value and true or false
  elseif field == 'rerolls' then
    assert(type(value) == 'number' and value >= 0 and value <= M.WHATIF_REROLLS and value % 1 == 0,
      'oracle.set_choice: bad rerolls '..tostring(value))
    c.rerolls = value
  else
    error('oracle.set_choice: unknown field '..tostring(field))
  end
end

local function blind_ahead(st)
  return st ~= 'Defeated' and st ~= 'Skipped' and st ~= 'Current'
end

function M.ahead(a, blind)
  if not in_run() then return false end
  local A = G.GAME.round_resets.ante
  if a ~= A then return a > A end
  return blind_ahead((G.GAME.round_resets.blind_states or {})[blind])
end

local function is_default(c)
  return not c.skip.Small and not c.skip.Big and c.rerolls == 0
end

-- Whether an ante before `a` (from the current one A) skips a blind the walk
-- would honour: any blind of a later ante, a blind of A still ahead.
local function earlier_skips(a)
  local A = G.GAME.round_resets.ante
  local st = G.GAME.round_resets.blind_states or {}
  for b = A, a - 1 do
    local cb = M.choice(b)
    for _, blind in ipairs{'Small', 'Big'} do
      if cb.skip[blind] and (b > A or blind_ahead(st[blind])) then return true end
    end
  end
  return false
end

-- One shop of a part-played ante, in ante_walk's order: row, packs, rerolls,
-- the packs opened in slot order, exit. `live` = the shelf on screen.
local function rest_shop(S, a, after, pol, live)
  local shop = {after = after, rerolls = {}, contents = {}}
  if live then
    shop.cards, shop.packs, shop.live = live.cards, live.packs, true
  else
    if pol.cards then shop.cards = predict.shop(S, a) end
    shop.packs = predict.packs(S, a, 2)
  end
  if pol.cards then
    for r = 1, pol.rerolls do shop.rerolls[r] = {cards = predict.reroll(S, a)} end
  end
  if pol.open then
    for j, p in ipairs(shop.packs) do shop.contents[j] = predict.pack_contents(S, p.key, a) end
  end
  if pol.cards or live then predict.leave_shop(S) end
  return shop
end

-- The rest of the current ante A from where the run stands (header: What-if).
local function rest_walk(S, A, pol, tags, live)
  local st = G.GAME.round_resets.blind_states or {}
  local walk = {shops = {}, tag_packs = {}}
  if live then
    local after = st.Big == 'Defeated' and 'Big' or st.Small == 'Defeated' and 'Small' or 'Boss'
    walk.shops[1] = rest_shop(S, A, after, pol, live)
  end
  for _, blind in ipairs{'Small', 'Big'} do
    local s = st[blind]
    if s == 'Current' then
      walk.shops[#walk.shops + 1] = rest_shop(S, A, blind, pol)
    elseif blind_ahead(s) then
      if pol.skip[blind] then
        local tag = blind == 'Small' and tags.small or tags.big
        local pack = predict.TAG_PACKS[tag]
        walk.tag_packs[#walk.tag_packs + 1] = {blind = blind, tag = tag, pack = pack,
          cards = pack and predict.pack_contents(S, pack, A) or nil}
      else
        walk.shops[#walk.shops + 1] = rest_shop(S, A, blind, pol)
      end
    end
  end
  return walk
end

local function rec_tags(a)
  local A = G.GAME.round_resets.ante
  if a == A then
    local t = G.GAME.round_resets.blind_tags or {}
    if t.Small and t.Big then return {small = t.Small, big = t.Big} end
  end
  for _, rec in ipairs(model and model.antes or {}) do
    if rec.ante == a then return {small = rec.tags.small.key, big = rec.tags.big.key} end
  end
  local p = stable_plan(math.max(M.MIN_PLAN, a))
  return {small = p[a].tags.small, big = p[a].tags.big}
end

local function walk_ante(S, b, A, pol, live)
  local tags = rec_tags(b)
  local st = G.GAME.round_resets.blind_states or {}
  local whole = b > A or (b == 1 and not live and blind_ahead(st.Small) and blind_ahead(st.Big))
  local walk
  if whole then
    walk = predict.ante_walk(S, b, {skip = {Small = pol.skip.Small, Big = pol.skip.Big},
      rerolls = pol.rerolls, open = pol.open, cards = pol.cards, tags = tags})
  else
    walk = rest_walk(S, b, pol, tags, live)
  end
  -- Skipped blinds whose tag opens no pack (ante_walk leaves them out).
  walk.no_pack = {}
  for _, blind in ipairs{'Small', 'Big'} do
    local tag = blind == 'Small' and tags.small or tags.big
    if pol.skip[blind] and (b > A or blind_ahead(st[blind])) and not predict.TAG_PACKS[tag] then
      walk.no_pack[#walk.no_pack + 1] = {blind = blind, tag = tag}
    end
  end
  return walk
end

local TITLES = {Boss = 'After the Boss', Small = 'After Small', Big = 'After Big'}

local function whatif_compute(a, c)
  local A = G.GAME.round_resets.ante
  local S = state.capture()
  local live
  if G.shop and G.shop_jokers then live = live_shop(S) end
  local walk
  for b = A, a do
    local cb = b == a and c or M.choice(b)
    local pol = b == a and {skip = cb.skip, rerolls = cb.rerolls, open = true, cards = true}
      or {skip = cb.skip, rerolls = 0, open = false, cards = false}
    walk = walk_ante(S, b, A, pol, b == A and live or nil)
  end
  local out = {ante = a, choice = {skip = {Small = c.skip.Small, Big = c.skip.Big}, rerolls = c.rerolls},
    shops = {}, tag_packs = walk.tag_packs, no_pack = walk.no_pack}
  for i, s in ipairs(walk.shops) do
    local rerolls = {}
    for r, rr in ipairs(s.rerolls) do rerolls[r] = rr.cards end
    out.shops[i] = {title = s.live and 'This shop' or TITLES[s.after], after = s.after, cards = s.cards,
      rerolls = rerolls, packs = s.packs, contents = s.contents, live = s.live}
  end
  return out
end

function M.whatif(a)
  if not in_run() or in_sim() then return nil end
  if a < G.GAME.round_resets.ante then return nil end
  local c = M.choice(a)
  if is_default(c) and not earlier_skips(a) then return nil end
  -- The key holds everything whatif_compute reads: the moment, this ante's
  -- choice and the skips of every earlier ante it walks (A..a-1).
  local key = {moment(), tostring(c.skip.Small), tostring(c.skip.Big), c.rerolls}
  for b = G.GAME.round_resets.ante, a - 1 do
    local cb = M.choice(b)
    key[#key + 1] = b..':'..tostring(cb.skip.Small)..','..tostring(cb.skip.Big)
  end
  local at = table.concat(key, '|')
  local cached = whatifs[a]
  if cached and cached.at == at then return cached.res end
  M.stats.whatifs = M.stats.whatifs + 1
  in_whatif = in_whatif + 1
  local ok, res = pcall(whatif_compute, a, c)
  in_whatif = in_whatif - 1
  if not ok then
    print('[SeedOracle] what-if failed: '..tostring(res))
    res = {ante = a, choice = c, shops = {}, tag_packs = {}, no_pack = {}, error = tostring(res)}
  end
  whatifs[a] = {at = at, res = res}
  return res
end

-- Divergence (header: Divergence).

local track = nil   -- {key, S, need_anchor, shop = {ui, ante, index, rerolls}, pending, actions}
local broke = nil   -- the first mismatch of this ante

local PACK_STATES = {'TAROT_PACK', 'PLANET_PACK', 'SPECTRAL_PACK', 'STANDARD_PACK', 'BUFFOON_PACK'}
local CAUSES = {'used_jokers', 'consumable', 'soul', 'voucher', 'reroll', 'skip'}

local function pack(...) return {n = select('#', ...), ...} end

local function new_track()
  track = {key = run_key(), need_anchor = true, actions = {}}
end

local function in_pack()
  for _, s in ipairs(PACK_STATES) do
    if G.STATE == G.STATES[s] then return true end
  end
  return false
end

local function center_name(key)
  local c = key and G.P_CENTERS[key]
  local ok, s = pcall(localize, {type = 'name_text', set = c and c.set, key = key})
  if ok and type(s) == 'string' and s ~= 'ERROR' then return s end
  return c and c.name or tostring(key)
end

local function card_name(r)
  local name = center_name(r.key)
  if r.front then name = name..' '..r.front end
  if r.edition then name = name..' ('..r.edition..')' end
  return name
end

-- A live Card as a prediction record.
local function live_rec(c)
  local ab = c.ability or {}
  return {key = card_key(c), edition = c.edition and c.edition.type or nil, front = c.config.card_key,
    seal = c.seal, stickers = {eternal = ab.eternal or false, perishable = ab.perishable or false,
      rental = ab.rental or false}}
end

local function sig(list)
  local out = {}
  for i, r in ipairs(list) do
    local st = r.stickers or {}
    out[i] = tostring(r.key)..'/'..tostring(r.edition)..'@'..tostring(r.front)..'+'..tostring(r.seal)
      ..(st.eternal and 'E' or '')..(st.perishable and 'P' or '')..(st.rental and 'R' or '')
  end
  return table.concat(out, ' ')
end

local function recs_of(area)
  local out = {}
  for i, c in ipairs(area and area.cards or {}) do out[i] = live_rec(c) end
  return out
end

local function act(kind, text)
  if track and not track.need_anchor then
    track.actions[#track.actions + 1] = {kind = kind, text = text}
  end
end

local function likely()
  local held = {}
  for _, c in ipairs(G.consumeables and G.consumeables.cards or {}) do
    if card_key(c) == 'c_soul' then held[#held + 1] = {kind = 'soul', text = 'holding The Soul'} end
  end
  for _, kind in ipairs(CAUSES) do
    for _, list in ipairs{track.actions, held} do
      for _, a in ipairs(list) do
        if a.kind == kind then return a.text end
      end
    end
  end
  return 'unknown'
end

local function shop_index(a)
  local st = G.GAME.round_resets.blind_states or {}
  local d = 0
  for _, kind in ipairs{'Small', 'Big'} do
    if st[kind] == 'Defeated' then d = d + 1 end
  end
  return (a > 1 and 1 or 0) + d
end

local function keys_of(list)
  local out = {}
  for i, r in ipairs(list) do out[i] = r.key end
  return out
end

local function names_of(list, name)
  local out = {}
  for i, r in ipairs(list) do out[i] = name(r) end
  return #out > 0 and table.concat(out, ', ') or 'nothing'
end

local function diverge(what, want, got, name)
  local shop = track.shop
  M.stats.divergences = M.stats.divergences + 1
  if not broke then
    broke = {ante = shop.ante, shop = shop.index, what = what, expected = names_of(want, name),
      got = names_of(got, name), likely = likely(), expected_keys = keys_of(want), got_keys = keys_of(got)}
  end
  print(string.format('[SeedOracle] prediction broke at ante %d shop %d (%s): expected %s, saw %s (likely: %s)',
    shop.ante, shop.index, what, names_of(want, name), names_of(got, name), likely()))
  track.need_anchor, track.pending = true, nil
  M.invalidate()
end

-- Compares; on a mismatch, diverges. Returns whether they matched.
local function check(what, want, got, name, cmp)
  M.stats.checks = M.stats.checks + 1
  local same
  if cmp then same = cmp(want, got) else same = sig(want) == sig(got) end
  if not same then diverge(what, want, got, name or card_name) end
  return same
end

local function pack_name(r) return center_name(r.key) end

local function same_packs(want, got)
  if #want ~= #got then return false end
  for i, w in ipairs(want) do
    local g = got[i].key
    local ok = w.key == g or (w.forced and (g == 'p_buffoon_normal_1' or g == 'p_buffoon_normal_2'))
    if not ok then return false end
  end
  return true
end

local function live_packs()
  local boosters = {}
  for _, c in ipairs(G.shop_booster and G.shop_booster.cards or {}) do boosters[#boosters + 1] = c end
  table.sort(boosters, function(x, y) return (x.ability.booster_pos or 0) < (y.ability.booster_pos or 0) end)
  local out = {}
  for i, c in ipairs(boosters) do out[i] = {key = card_key(c)} end
  return out
end

local function shelf_placed()
  local j, b = G.shop_jokers, G.shop_booster
  return G.shop and j and b and #j.cards >= (G.GAME.shop and G.GAME.shop.joker_max or 2) and #b.cards >= 2
end

local function reroll_settled()
  return G.shop and G.shop_jokers and not G.CONTROLLER.locks.shop_reroll
    and #G.shop_jokers.cards >= (G.GAME.shop and G.GAME.shop.joker_max or 2)
end

local function try_anchor()
  if in_pack() then return end
  if G.shop then
    local j, b = G.shop_jokers, G.shop_booster
    if G.STATE ~= G.STATES.SHOP or not (j and b) or G.CONTROLLER.locks.shop_reroll or G.CONTROLLER.locks.use then
      return
    end
    local same = track.shop and track.shop.ui == G.shop
    if not same and #j.cards + #b.cards == 0 then return end  -- the shelf is not placed yet
    track.S = state.capture()
    live_shop(track.S)
    if not same then
      local a = G.GAME.round_resets.ante
      track.shop = {ui = G.shop, ante = a, index = shop_index(a), rerolls = 0}
    end
  else
    local s = G.STATES
    if G.STATE ~= s.BLIND_SELECT and G.STATE ~= s.SELECTING_HAND and G.STATE ~= s.ROUND_EVAL then return end
    track.S = state.capture()
    track.shop = nil
  end
  track.need_anchor, track.pending, track.actions = false, nil, {}
  M.stats.anchors = M.stats.anchors + 1
end

local function poll()
  if not track or in_sim() or not in_run() then return end
  if track.key ~= run_key() then new_track() end
  if track.need_anchor then return try_anchor() end
  local p = track.pending
  if not p then return end
  local S = track.S
  if p.kind == 'enter' then
    if G.shop ~= p.ui then track.pending = nil; return end
    if not shelf_placed() then return end
    track.pending = nil
    local a = G.GAME.round_resets.ante
    track.shop = {ui = G.shop, ante = a, index = shop_index(a), rerolls = 0}
    local cards = predict.shop(S, a)
    local packs = predict.packs(S, a, 2)
    if check('shop row', cards, recs_of(G.shop_jokers)) then
      check('packs', packs, live_packs(), pack_name, same_packs)
    end
  elseif p.kind == 'reroll' then
    if not track.shop or G.shop ~= track.shop.ui then track.pending = nil; return end
    if not reroll_settled() then return end
    track.pending = nil
    check('reroll '..p.n, predict.reroll(S, track.shop.ante), recs_of(G.shop_jokers))
  elseif p.kind == 'pack' then
    if G.STATE == G.STATES.SHOP or not in_pack() then
      if G.STATE == G.STATES.SHOP then track.pending = nil end
      return
    end
    if not (G.pack_cards and G.pack_cards.cards and #G.pack_cards.cards >= p.size) then return end
    track.pending = nil
    check('pack '..p.slot..' contents', predict.pack_contents(S, p.key, track.shop.ante), recs_of(G.pack_cards))
  end
end

-- Runs fn under pcall; a failure turns the detector off until the next run.
local function safely(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    print('[SeedOracle] divergence check failed: '..tostring(err))
    track = nil
  end
end

-- Whether the tracker follows the shop on screen.
local function tracking_shop()
  return track and not track.need_anchor and track.shop and G.shop ~= nil and track.shop.ui == G.shop
end

function M.divergence()
  if not in_run() or not broke then return nil end
  if broke.ante ~= G.GAME.round_resets.ante then return nil end
  return broke
end

local function hook(tbl, key, before)
  local orig = tbl[key]
  assert(type(orig) == 'function', 'seedoracle.oracle: vanilla '..key..' missing')
  tbl[key] = function(...)
    if track and not in_sim() and in_run() then safely(poll); safely(before, ...) end
    return orig(...)
  end
end

local function install_detector()
  events.on('run_start', function()
    broke = nil
    new_track()
  end)
  events.on('ante_change', function() broke = nil end)
  events.on('shop_enter', function()
    if track and not track.need_anchor and G.shop then track.pending = {kind = 'enter', ui = G.shop} end
  end)
  events.on('blind_skipped', function(p)
    act('skip', 'skipped the '..tostring(p.kind)..' Blind ('..center_name(p.tag)..')')
  end)

  local orig_update = Game.update
  assert(type(orig_update) == 'function', 'seedoracle.oracle: vanilla Game:update missing')
  -- The checks wait for the game's queued events (shelf placed, reroll
  -- refilled, pack cards out): polled after every frame, a no-op unless a
  -- check or an anchor is pending.
  Game.update = function(...)
    local out = pack(orig_update(...))
    if track and not in_sim() then safely(poll) end
    return unpack(out, 1, out.n)
  end

  hook(G.FUNCS, 'reroll_shop', function()
    if not tracking_shop() then return end
    local shop = track.shop
    shop.rerolls = shop.rerolls + 1
    if shop.rerolls > M.REROLLS then
      act('reroll', 'rerolled '..shop.rerolls..' times')
    else
      track.pending = {kind = 'reroll', n = shop.rerolls}
    end
  end)
  hook(G.FUNCS, 'buy_from_shop', function(e)
    local c = e and e.config and e.config.ref_table
    if type(c) == 'table' and c.config and c.config.center then act('used_jokers', 'bought '..center_name(card_key(c))) end
  end)
  hook(G.FUNCS, 'sell_card', function(e)
    local c = e and e.config and e.config.ref_table
    if type(c) == 'table' and c.config and c.config.center then act('used_jokers', 'sold '..center_name(card_key(c))) end
  end)
  hook(G.FUNCS, 'use_card', function(e)
    local c = e and e.config and e.config.ref_table
    if not (type(c) == 'table' and c.ability and c.config and c.config.center) then return end
    local set, name = c.ability.set, center_name(card_key(c))
    if set == 'Voucher' then act('voucher', 'bought '..name)
    elseif set == 'Tarot' or set == 'Spectral' then act('consumable', 'used '..name)
    elseif set == 'Joker' then act('used_jokers', 'took '..name..' from a pack')
    end
  end)
  hook(Card, 'open', function(self)
    if not (tracking_shop() and self.ability and self.ability.set == 'Booster' and self.ability.booster_pos) then return end
    track.pending = {kind = 'pack', key = card_key(self), slot = self.ability.booster_pos, size = self.ability.extra}
  end)
end

function M.install()
  if installed then return end
  installed = true
  events.on('run_start', function()
    model, stable, boss_moved, last_at = nil, nil, false, nil
    choices, whatifs = nil, {}
    dirty = true
  end)
  for _, name in ipairs{'shop_enter', 'blind_selected', 'blind_skipped', 'ante_change'} do
    events.on(name, M.invalidate)
  end
  install_detector()
end

return M
