-- seedfinder.route: a Finder hit's eval details as play steps. The route is
-- the filter's own policy (seedfinder.filter header: Policies, Chained antes)
-- read back in play order; it adds nothing the policy does not assume, and it
-- draws no stream: every card it names comes from the details.
--
-- API
--   route.build(f, details) -> {steps = {step, ...}, cost = {ante, rerolls, dollars}},
--     or nil, err ('not a hit' when details is not a hit for f; the filter's
--     own validate error for an invalid f). details is filter.eval(S, f)'s.
--   step = {ante, when = 'Small'|'Big'|'Boss'|'shop',
--           action = 'skip'|'play'|'open_pack'|'reroll'|'use_soul'|'buy'|'redeem',
--           slot, index, key, text}
--     skip      a blind skipped: its tag is taken (a tag clause), or it is a
--               Charm/Ethereal blind a from_tag clause skips; key = the tag.
--               A tag that gives a pack is followed by that pack's open_pack.
--     play      a blind played (not skipped) so its shop comes up; the ante is
--               the blind's own (the shop after the Boss of A-1 draws ante A).
--     reroll    index = the reroll's number within its shop; key/slot name the
--               clause's card when it shows up on that reroll.
--     open_pack when = the blind for a tag pack (free, opened at the skip), or
--               'shop' for a shop pack bought and opened (slot = its shop slot;
--               key nil when the details do not say which pack it is). index is
--               the Soul's position in the pack when the route takes it, or
--               the joker's when a joker clause found it there: take = that
--               joker's key.
--     use_soul  the Soul just taken, used before the next Soul the route needs
--               (no Soul rolls while one exists, common_events.lua:2090).
--     buy       the pack a 'pack' clause found, bought (and opened) as the last
--               step of its ante; left out when a later step of that ante would
--               draw after it.
--     redeem    a voucher bought (key = the voucher) in its ante's first shop,
--               straight after the play step that opens it and before that
--               shop's rerolls and packs: a voucher clause's own, or the
--               tier-1 a tier-2 clause needs (seedfinder.filter header:
--               voucher clauses are bought).
--   route.rank(f, hits) -> the hits sorted by route cost, cheapest first, and
--     costs (costs[k] = the route cost of the k-th, nil when it has no route),
--     or nil, err for an invalid f. hits = {{seed, details}...} (or {seed =,
--     details =}); the entries themselves are returned, not copied. Order: fewer
--     antes, then fewer rerolls, then fewer known dollars (unknown dollars after
--     known at equal ante and rerolls), then the hits' own (scan) order. A hit
--     with no route (details nil or not a hit for f) goes last.
--   cost.ante is the ante the route ends in; cost.rerolls the rerolls it makes;
--   cost.dollars the rerolls at vanilla's base price ($5, +$1 per reroll within
--   a shop) plus every shop pack and voucher bought at G.P_CENTERS[key].cost,
--   or nil when a pack's key or a cost is unknown. Tag packs are free.
--   Discounts (Clearance Sale, Reroll Surplus, ...) are not modelled.
--
-- Texts are written to sit under an "Ante N" heading (the Finder's Route panel
-- groups steps by st.ante): no step repeats "Ante N:". A Soul the route uses
-- before its next one is taken by its open_pack step and used by the use_soul
-- step that follows; only the use_soul step says so.
--
-- What is routed: every clause in mode 'all' but the excluded ones, the
-- clause that hit in mode 'any'. For an any-of group that is the member that
-- hit (its details' hit), routed like that clause on its own; the other
-- members add nothing, though their needs still shape the walk the route
-- replays (needs and chained antes come from every plain clause of f, group
-- members included, as the filter's walk does). A walked ante's skips are
-- read off the details' skips, and a tag pack's cards off its tag_packs (a
-- from_tag member there may never have been evaluated).
-- A tag clause adds its skip (seedfinder.filter header: tag clauses are
-- taken): "Skip the Small Blind (Investment Tag).", then the pack a pack tag
-- opens, closed with nothing taken. It is listed even after the ante's last
-- target, and in an ante the walk never reached. A by tag clause skips at the
-- ante and blind its details found it (details.ante, details.blind) and
-- counts that ante, not N.
-- boss / legendary clauses add no step (the filter assumes no action for
-- them); their antes still count toward cost.ante. A boss clause with by
-- (T-375) counts the ante its details found it in (details.ante), not N: the
-- route never rerolls a boss. Skips the eval assumed of an unwalked ante 1
-- (details.skips[1]: both blinds, placing the forced Buffoon) are listed too.
-- A voucher clause is bought (seedfinder.filter header): the route replays
-- every purchase the eval's walk made (details.bought) up to the route's last
-- ante, a voucher clause's own and the tier-1 a tier-2 clause needs alike,
-- each as a redeem step in its ante's first shop (the Boss's, or at ante 1
-- the first blind played), whether or not the walk walked that ante: "Shop
-- after the Small Blind: buy the Overstock voucher (Overstock Plus needs
-- it)." Purchases past that ante shape nothing the route needs. A voucher
-- clause counts its ante toward cost.ante, a by one ("by ante N", T-313a)
-- the ante its details found it in (details.ante), not N. A Hieroglyph
-- clause adds no step: the filter never buys it.
-- An excluded clause (exclude = true, T-375, a must-not) adds no step and no
-- cost: it is not routed, and its ante (or N) does not count toward
-- cost.ante. Only its needs remain, as the filter's walk drew them (a
-- non-final shop of a routed ante still makes the R rerolls and opens the
-- packs an excluded shop_joker, joker, pack or soul_in_pack clause asked of
-- that ante, and an excluded from_tag clause still chains its ante), so the
-- shops the route plays are the filter's walk, the one the must-not was
-- judged on. A filter of excluded clauses alone routes to no step, at ante 1.
-- A sticker = 'none' clause is routed as without it: its details name the
-- clean copy, and the route plays up to that copy.
-- A joker clause ("by ante N") is routed at the ante its details name, not N:
-- that ante is replayed like a shop_joker's (a row hit) or a shop Soul's (a
-- Buffoon pack hit: all R rerolls, then the packs up to its slot, and the
-- joker taken from that pack). Earlier antes add no step: every shop stream is
-- keyed by ante, so how they are played does not move the hit's ante. Taking
-- the joker puts it in used_jokers; a later draw that lands on it resamples,
-- so only a later step that would show that same joker again can differ.
-- An ante with a shop clause is replayed from its first shop up to the last
-- one a routed clause needs, under the policy the filter walked (its needs
-- come from every clause of f, not just the routed ones: the walk drew them):
-- per shop R rerolls (the most any shop_joker clause at that ante asks for)
-- then, when a soul_in_pack shop clause is at that ante, every pack in slot
-- order. The last shop stops once the routed clauses have what they need
-- (a shop_joker at reroll r needs r rerolls; a shop Soul needs all R, since
-- packs are opened while the shop's final row sits in used_jokers and so
-- shapes the pack pools, and its packs up to its slot). A chained ante interleaves the tag-pack skips with the shops in the
-- filter's order: the Boss's shop, then Small, then Big.
local filter = require('seedfinder.filter')

local M = {}

M.REROLL_BASE = 5
local SOUL = 'c_soul'

------------------------------------------------------------------------------
-- Names

local function tag_name(key)
  local t = G and G.P_TAGS and G.P_TAGS[key]
  if t and t.name then return t.name end
  local s = (key:gsub('^tag_', ''):gsub('_', ' '))
  s = s:gsub('(%a)(%w*)', function(a, b) return a:upper()..b end)
  return s..' Tag'
end

local function center_name(key)
  local c = key and G and G.P_CENTERS and G.P_CENTERS[key]
  return c and c.name or key
end

local function pack_name(key)
  return key and ('the '..center_name(key)) or 'the pack'
end

local function center_cost(key)
  local c = key and G and G.P_CENTERS and G.P_CENTERS[key]
  return c and type(c.cost) == 'number' and c.cost or nil
end

local BLIND = {Small = 'Small Blind', Big = 'Big Blind', Boss = 'Boss Blind'}

------------------------------------------------------------------------------
-- The filter's walk, from f (mirrors filter.lua's shop_needs / chained_antes,
-- over filter.plain_clauses: group members count)

local function needs_of(f)
  local needs = {}
  local function need(a)
    local n = needs[a] or {rerolls = 0, open = false}
    needs[a] = n
    return n
  end
  local plain = filter.plain_clauses(f)
  for _, c in ipairs(plain) do
    if c.kind == 'joker' then
      for a = 1, c.ante do
        local n = need(a)
        n.rerolls = math.max(n.rerolls, c.rerolls or 0)
        if (c.from or 'both') ~= 'shop' then n.open = true end
      end
    end
    local shop = c.kind == 'shop_joker' or c.kind == 'pack' or (c.kind == 'soul_in_pack' and not c.from_tag)
    if shop then
      local n = need(c.ante)
      if c.kind == 'shop_joker' then
        n.rerolls = math.max(n.rerolls, c.rerolls or 0)
      elseif c.kind == 'soul_in_pack' then
        n.open = true
      end
    end
  end
  for _, c in ipairs(plain) do
    if c.kind == 'soul_in_pack' and c.from_tag and needs[c.ante] then needs[c.ante].chained = true end
  end
  return needs
end

-- Every evaluated plain clause with its result, group members included:
-- list of {c, r}. An excluded clause is left out: on a hit it holds because
-- its positive form failed, so its result names no card, pack or shop.
local function evaluated(f, details)
  local out = {}
  for i, c in ipairs(f.clauses) do
    local r = details.results[i]
    if c.kind == 'group' then
      local rs = type(r) == 'table' and type(r.results) == 'table' and r.results or {}
      for m, mc in ipairs(c.clauses) do
        if type(rs[m]) == 'table' then out[#out + 1] = {c = mc, r = rs[m]} end
      end
    elseif type(r) == 'table' and not c.exclude then
      out[#out + 1] = {c = c, r = r}
    end
  end
  return out
end

-- The plain clause to route for top-level entry i, when its result holds:
-- {c, r, name}; for a group, the member that hit.
local function hit_of(f, details, i)
  local c, r = f.clauses[i], details.results[i]
  if not (type(r) == 'table' and r.ok) then return nil end
  if c.kind ~= 'group' then return {c = c, r = r, name = 'clause '..i} end
  local m = r.hit
  local mr = type(r.results) == 'table' and r.results[m]
  if not (c.clauses[m] and type(mr) == 'table' and mr.ok) then return nil end
  return {c = c.clauses[m], r = mr, name = 'clause '..i..', member '..m}
end

-- Whether details is a hit for f, and the clauses to route ({c, r, name}).
-- An excluded clause must hold for a hit but is not routed (mode 'all' only:
-- validate refuses exclude in 'any').
local function routed(f, details)
  if type(details) ~= 'table' or type(details.results) ~= 'table' then return nil end
  local out = {}
  if f.mode == 'any' then
    for i = 1, #f.clauses do
      local t = hit_of(f, details, i)
      if t then out[1] = t; return out end
    end
    return nil
  end
  for i = 1, #f.clauses do
    local t = hit_of(f, details, i)
    if not t then return nil end
    if not f.clauses[i].exclude then out[#out + 1] = t end
  end
  return out
end

-- The tag packs the details saw at ante a: the eval's record of a chained
-- ante, else any from_tag clause's there (they all share the same list).
local function tag_packs(f, details, a)
  local walked = type(details.tag_packs) == 'table' and details.tag_packs[a]
  if walked then return walked end
  for _, t in ipairs(evaluated(f, details)) do
    local c, r = t.c, t.r
    if c.kind == 'soul_in_pack' and c.from_tag and c.ante == a and r.packs then return r.packs end
  end
end

-- Pack keys the details name at ante a: known[shop][slot].
local function known_packs(f, details, a)
  local known = {}
  for _, t in ipairs(evaluated(f, details)) do
    local c, r = t.c, t.r
    if c.ante == a and r and r.shop and r.slot and r.pack then
      known[r.shop] = known[r.shop] or {}
      known[r.shop][r.slot] = r.pack
    elseif c.kind == 'joker' and r and r.ante == a and r.shop and r.pack_slot and r.pack then
      known[r.shop] = known[r.shop] or {}
      known[r.shop][r.pack_slot] = r.pack
    end
  end
  return known
end

-- The blind a routed tag clause takes (filter.lua's tag_blind on its
-- details: Small first), and the ante: a by clause's found ante.
local function taken_blind(c, r)
  if c.by then return r.ante, r.blind end
  local blind = c.blind or 'any'
  if (blind == 'Small' or blind == 'any') and r.small == c.key then return c.ante, 'Small' end
  if (blind == 'Big' or blind == 'any') and r.big == c.key then return c.ante, 'Big' end
end

-- Ante a's events in play order: {type = 'tag', blind, tag, pack = <details
-- pack> or nil} or {type = 'shop', after = 'Boss'|'Small'|'Big', shop = s}.
-- skip[blind] = {tag, pack} for each skipped blind; walked: the filter walked
-- the ante's shops (every other blind is played), else only skips happen,
-- and the ante's first shop when a voucher is bought there (buy).
local function events_of(a, walked, skip, buy)
  local ev, s = {}, 0
  local function shop(after) s = s + 1; ev[#ev + 1] = {type = 'shop', after = after, shop = s} end
  if (walked or buy) and a > 1 then shop('Boss') end
  for _, blind in ipairs{'Small', 'Big'} do
    local k = skip[blind]
    if k then
      ev[#ev + 1] = {type = 'tag', blind = blind, tag = k.tag, pack = k.pack}
    elseif walked or (buy and s == 0) then
      shop(blind)
    end
  end
  return ev
end


------------------------------------------------------------------------------
-- Build

function M.build(f, details)
  local valid, verr = filter.validate(f)
  if not valid then return nil, verr end
  local idx = routed(f, details)
  if not idx then return nil, 'not a hit' end
  local needs = needs_of(f)

  -- Routed clauses by ante; the highest ante any of them names. takes[a] =
  -- the blinds a routed tag clause takes there (the player skips for it).
  local by_ante, last_ante, takes = {}, 1, {}
  for _, t in ipairs(idx) do
    local c, r = t.c, t.r
    if c.kind == 'tag' then
      local ta, tb = taken_blind(c, r)
      if not (ta and tb) then return nil, 'details: tag '..t.name..' names no blind' end
      takes[ta] = takes[ta] or {}
      takes[ta][tb] = c.key
    end
    -- A joker clause, or a tag / voucher clause with by, ends where its
    -- details found it (never N in their place when the details name none).
    local found = c.kind == 'joker' or c.by
    local a = c.ante
    if found then a = r.ante end
    if found and not (type(a) == 'number' and a >= 1 and a <= c.ante) then
      return nil, 'details: '..c.kind..' '..t.name..' names no ante'
    end
    if a and a > last_ante then last_ante = a end
    local step_kind = c.kind == 'soul_in_pack' or c.kind == 'shop_joker' or c.kind == 'pack' or c.kind == 'joker'
    if step_kind then
      by_ante[a] = by_ante[a] or {}
      table.insert(by_ante[a], {c = c, r = r})
    end
  end
  -- The walk's purchases up to that ante, and for each tier-1 a routed
  -- tier-2 voucher clause needs, that clause's key.
  local bought, needed_by = {}, {}
  for a, key in pairs(type(details.bought) == 'table' and details.bought or {}) do
    if type(a) == 'number' and a <= last_ante then bought[a] = key end
  end
  for _, t in ipairs(idx) do
    if t.c.kind == 'voucher' then
      for _, r in ipairs(filter.prerequisites(t.c.key)) do needed_by[r] = needed_by[r] or t.c.key end
    end
  end
  local antes, listed = {}, {}
  for a in pairs(by_ante) do antes[#antes + 1] = a; listed[a] = true end
  for a in pairs(takes) do if not listed[a] then antes[#antes + 1] = a; listed[a] = true end end
  for a in pairs(bought) do if not listed[a] then antes[#antes + 1] = a; listed[a] = true end end
  -- An unwalked ante's recorded skips (ante 1's, placing the forced Buffoon).
  for a in pairs(type(details.skips) == 'table' and details.skips or {}) do
    if not listed[a] and not needs[a] then antes[#antes + 1] = a; listed[a] = true end
  end
  table.sort(antes)

  local steps, dollars, rerolls = {}, 0, 0
  local function add(st)
    steps[#steps + 1] = st
    return st
  end

  for _, a in ipairs(antes) do
    local n = needs[a]
    local packs = tag_packs(f, details, a)
    if n and n.chained and not packs then return nil, 'details: no tag packs at chained ante '..a end
    -- A walked ante replays the walk's skips (details.skips: taken tags, and a
    -- chained ante's pack tags); elsewhere the skips are the taken tags and a
    -- separate from_tag branch's pack tags (both its blinds are skipped).
    local walked = n ~= nil and (details.walked == nil or a <= details.walked)
    local skip, must = {}, {} -- must: skips always listed (taken, or recorded)
    local function pack_at(blind)
      for _, q in ipairs(packs or {}) do if q.blind == blind then return q end end
    end
    if walked then
      local sk = type(details.skips) == 'table' and details.skips[a]
      if sk then
        for blind, tag in pairs(sk) do skip[blind] = {tag = tag, pack = pack_at(blind)} end
      elseif n.chained then
        for _, q in ipairs(packs or {}) do skip[q.blind] = {tag = q.tag, pack = q} end
      end
    else
      for _, q in ipairs(packs or {}) do skip[q.blind] = {tag = q.tag, pack = q} end
      for blind, tag in pairs(takes[a] or {}) do skip[blind] = skip[blind] or {tag = tag} end
      -- Skips the eval assumed of an unwalked ante (ante 1's, placing the
      -- forced Buffoon) are replayed even when no routed clause names them.
      local sk = type(details.skips) == 'table' and details.skips[a]
      for blind, tag in pairs(sk or {}) do
        skip[blind] = skip[blind] or {tag = tag}
        must[blind] = true
      end
    end
    for blind in pairs(takes[a] or {}) do must[blind] = true end
    local ev = events_of(a, walked, skip, bought[a] ~= nil)
    local known = known_packs(f, details, a)

    -- What each event must deliver: targets[e] = {soul_slot, reroll, joker, pack...}.
    local want, last = {}, 0
    local function target(e)
      want[e] = want[e] or {jokers = {}, packs = {}}
      if e > last then last = e end
      return want[e]
    end
    -- The ante's voucher is bought in its first shop.
    if bought[a] then
      local e
      for k, x in ipairs(ev) do if x.type == 'shop' then e = k; break end end
      if not e then return nil, 'details: ante '..a..' has no shop to buy '..tostring(bought[a])..' in' end
      target(e).redeem = bought[a]
    end
    -- A taken tag's skip is always listed, even after the ante's last target.
    for e, x in ipairs(ev) do
      if x.type == 'tag' and must[x.blind] then target(e) end
    end
    for _, t in ipairs(by_ante[a] or {}) do
      local c, r = t.c, t.r
      if c.kind == 'soul_in_pack' and c.from_tag then
        for e, x in ipairs(ev) do
          if x.type == 'tag' and x.pack and x.blind == r.blind then target(e).tag_soul = r.index end
        end
      else
        local e
        for k, x in ipairs(ev) do if x.type == 'shop' and x.shop == r.shop then e = k end end
        if not e then return nil, 'details: ante '..a..' has no shop '..tostring(r.shop) end
        local w = target(e)
        if c.kind == 'soul_in_pack' then
          w.soul = w.soul or {}
          w.soul[r.slot] = r.index
          w.open = math.max(w.open or 0, r.slot)
          w.rerolls = math.max(w.rerolls or 0, n.rerolls)
        elseif c.kind == 'shop_joker' then
          table.insert(w.jokers, {key = c.key, reroll = r.reroll, slot = r.slot})
          w.rerolls = math.max(w.rerolls or 0, r.reroll)
        elseif c.kind == 'joker' and r.pack_slot then
          -- Buffoon pack: opened after the shop's R rerolls, like a shop Soul.
          w.take = w.take or {}
          w.take[r.pack_slot] = {key = c.key, index = r.index}
          w.open = math.max(w.open or 0, r.pack_slot)
          w.rerolls = math.max(w.rerolls or 0, n.rerolls)
        elseif c.kind == 'joker' then
          table.insert(w.jokers, {key = c.key, reroll = r.reroll, slot = r.index})
          w.rerolls = math.max(w.rerolls or 0, r.reroll)
        else
          table.insert(w.packs, {slot = r.slot, key = r.pack})
        end
      end
    end

    for e = 1, last do
      local x, w = ev[e], want[e] or {jokers = {}, packs = {}}
      if x.type == 'tag' then
        add{ante = a, when = x.blind, action = 'skip', key = x.tag,
          text = ('Skip the %s (%s).'):format(BLIND[x.blind], tag_name(x.tag))}
        local p = x.pack
        if p then
          local open = add{ante = a, when = x.blind, action = 'open_pack', key = p.pack, index = w.tag_soul}
          if w.tag_soul then
            open.soul = true
            open.text = ('%s holds the Soul in slot %d: take it.'):format((pack_name(p.pack):gsub('^t', 'T')), w.tag_soul)
          else
            open.text = ('Open %s and take nothing.'):format(pack_name(p.pack))
          end
        end
      else
        local final = e == last
        local blind_ante = x.after == 'Boss' and a - 1 or a
        local notes = {}
        for _, j in ipairs(w.jokers) do
          if j.reroll == 0 then notes[#notes + 1] = ('%s is in slot %d'):format(center_name(j.key), j.slot) end
        end
        for _, p in ipairs(w.packs) do
          notes[#notes + 1] = ('%s is in slot %d'):format(pack_name(p.key), p.slot)
        end
        local seen = #notes > 0 and table.concat(notes, '; ') or nil
        local where = x.after == 'Boss' and ('Shop after the ante-%d Boss'):format(a - 1)
          or ('Shop after the %s'):format(BLIND[x.after])
        -- A purchase comes first in its shop, and the row is read after it
        -- (Overstock's new slot is filled at once).
        local text = ('Play the %s.'):format(BLIND[x.after])
        if seen and not w.redeem then text = text..' In its shop, '..seen..'.' end
        add{ante = blind_ante, when = x.after, action = 'play', text = text}
        if w.redeem then
          local t = ('%s: buy the %s voucher'):format(where, center_name(w.redeem))
          if needed_by[w.redeem] then t = t..(' (%s needs it)'):format(center_name(needed_by[w.redeem])) end
          t = t..'.'
          if seen then t = t..' Then '..seen..'.' end
          add{ante = a, when = 'shop', action = 'redeem', key = w.redeem, text = t}
          local cost = center_cost(w.redeem)
          dollars = dollars and cost and dollars + cost or nil
        end

        local nr = final and (w.rerolls or 0) or (n and n.rerolls or 0)
        for k = 1, nr do
          local price = M.REROLL_BASE + k - 1
          local st = add{ante = a, when = 'shop', action = 'reroll', index = k}
          local seen = {}
          for _, j in ipairs(w.jokers) do
            if j.reroll == k then
              st.key, st.slot = st.key or j.key, st.slot or j.slot
              seen[#seen + 1] = ('%s in slot %d'):format(center_name(j.key), j.slot)
            end
          end
          st.text = ('%s: reroll %d ($%d).'):format(where, k, price)
          if #seen > 0 then st.text = st.text..' '..table.concat(seen, ', ')..'.' end
          rerolls = rerolls + 1
          if dollars then dollars = dollars + price end
        end
        local no = n and n.open and (final and (w.open or 0) or 2) or 0
        for slot = 1, no do
          local key = known[x.shop] and known[x.shop][slot]
          local idx_soul = w.soul and w.soul[slot]
          local take = w.take and w.take[slot]
          local st = add{ante = a, when = 'shop', action = 'open_pack', slot = slot, key = key,
            index = idx_soul or (take and take.index)}
          if take then
            st.take = take.key
            st.text = ('%s: buy and open %s in slot %d; %s is card %d: take it.')
              :format(where, pack_name(key), slot, center_name(take.key), take.index)
          elseif idx_soul then
            st.soul = true
            st.text = ('%s: buy and open %s in slot %d; the Soul is card %d: take it.')
              :format(where, pack_name(key), slot, idx_soul)
          else
            st.text = ('%s: buy and open %s in slot %d; take nothing.'):format(where, pack_name(key), slot)
          end
          local cost = center_cost(key)
          dollars = dollars and cost and dollars + cost or nil
        end
        if final then
          for _, p in ipairs(w.packs) do
            if p.slot > no then
              add{ante = a, when = 'shop', action = 'buy', slot = p.slot, key = p.key,
                text = ('%s: buy %s in slot %d.'):format(where, pack_name(p.key), p.slot)}
              local cost = center_cost(p.key)
              dollars = dollars and cost and dollars + cost or nil
            end
          end
        end
      end
    end
  end

  -- A Soul taken is used before the route's next Soul.
  local out, souls = {}, 0
  for _, st in ipairs(steps) do if st.soul then souls = souls + 1 end end
  for _, st in ipairs(steps) do
    local taken = st.soul
    st.soul = nil
    out[#out + 1] = st
    if taken then
      souls = souls - 1
      if souls > 0 then
        out[#out + 1] = {ante = st.ante, when = st.when, action = 'use_soul', key = SOUL,
          text = 'Use the Soul now: no Soul rolls while one is held.'}
      end
    end
  end
  for _, st in ipairs(out) do
    if st.ante > last_ante then last_ante = st.ante end
  end
  return {steps = out, cost = {ante = last_ante, rerolls = rerolls, dollars = dollars}}
end

------------------------------------------------------------------------------
-- Rank

local function cheaper(x, y)
  local a, b = x.cost, y.cost
  if not (a and b) then
    if a or b then return a ~= nil end
    return x.i < y.i
  end
  if a.ante ~= b.ante then return a.ante < b.ante end
  if a.rerolls ~= b.rerolls then return a.rerolls < b.rerolls end
  if (a.dollars == nil) ~= (b.dollars == nil) then return a.dollars ~= nil end
  if a.dollars and a.dollars ~= b.dollars then return a.dollars < b.dollars end
  return x.i < y.i
end

function M.rank(f, hits)
  local valid, verr = filter.validate(f)
  if not valid then return nil, verr end
  local keyed = {}
  for i, h in ipairs(hits or {}) do
    local d = h.details
    if d == nil then d = h[2] end
    local r = M.build(f, d)
    keyed[i] = {hit = h, cost = r and r.cost, i = i}
  end
  table.sort(keyed, cheaper)
  local out, costs = {}, {}
  for k, e in ipairs(keyed) do out[k], costs[k] = e.hit, e.cost end
  return out, costs
end

return M
