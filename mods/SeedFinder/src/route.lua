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
--           action = 'skip'|'play'|'open_pack'|'reroll'|'use_soul'|'buy',
--           slot, index, key, text}
--     skip      the blind whose Charm/Ethereal tag opens a pack; key = the tag.
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
--   route.rank(f, hits) -> the hits sorted by route cost, cheapest first, and
--     costs (costs[k] = the route cost of the k-th, nil when it has no route),
--     or nil, err for an invalid f. hits = {{seed, details}...} (or {seed =,
--     details =}); the entries themselves are returned, not copied. Order: fewer
--     antes, then fewer rerolls, then fewer known dollars (unknown dollars after
--     known at equal ante and rerolls), then the hits' own (scan) order. A hit
--     with no route (details nil or not a hit for f) goes last.
--   cost.ante is the ante the route ends in; cost.rerolls the rerolls it makes;
--   cost.dollars the rerolls at vanilla's base price ($5, +$1 per reroll within
--   a shop) plus every shop pack at G.P_CENTERS[key].cost, or nil when a pack's
--   key or cost is unknown. Tag packs are free. Vouchers and discounts are not
--   modelled.
--
-- Texts are written to sit under an "Ante N" heading (the Finder's Route panel
-- groups steps by st.ante): no step repeats "Ante N:". A Soul the route uses
-- before its next one is taken by its open_pack step and used by the use_soul
-- step that follows; only the use_soul step says so.
--
-- What is routed: every clause in mode 'all', the clause that hit in mode
-- 'any'. tag / boss / voucher / legendary clauses add no step (the filter
-- assumes no action for them); their antes still count toward cost.ante.
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

local function pack_cost(key)
  local c = key and G and G.P_CENTERS and G.P_CENTERS[key]
  return c and type(c.cost) == 'number' and c.cost or nil
end

local BLIND = {Small = 'Small Blind', Big = 'Big Blind', Boss = 'Boss Blind'}

------------------------------------------------------------------------------
-- The filter's walk, from f (mirrors filter.lua's shop_needs / chained_antes)

local function needs_of(f)
  local needs = {}
  local function need(a)
    local n = needs[a] or {rerolls = 0, open = false}
    needs[a] = n
    return n
  end
  for _, c in ipairs(f.clauses) do
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
  for _, c in ipairs(f.clauses) do
    if c.kind == 'soul_in_pack' and c.from_tag and needs[c.ante] then needs[c.ante].chained = true end
  end
  return needs
end

-- Whether details is a hit for f, and the clause indices to route.
local function routed(f, details)
  if type(details) ~= 'table' or type(details.results) ~= 'table' then return nil end
  local out = {}
  if f.mode == 'any' then
    for i = 1, #f.clauses do
      local r = details.results[i]
      if r and r.ok then out[1] = i; return out end
    end
    return nil
  end
  for i = 1, #f.clauses do
    local r = details.results[i]
    if not (r and r.ok) then return nil end
    out[i] = i
  end
  return out
end

-- The tag packs the details saw at ante a (every from_tag clause there shares
-- the same list).
local function tag_packs(f, details, a)
  for i, c in ipairs(f.clauses) do
    local r = details.results[i]
    if c.kind == 'soul_in_pack' and c.from_tag and c.ante == a and r and r.packs then return r.packs end
  end
end

-- Pack keys the details name at ante a: known[shop][slot].
local function known_packs(f, details, a)
  local known = {}
  for i, c in ipairs(f.clauses) do
    local r = details.results[i]
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

-- Ante a's events in play order: {type = 'tag', pack = <details pack>} or
-- {type = 'shop', after = 'Boss'|'Small'|'Big', shop = s}.
local function events_of(a, n, packs)
  local ev = {}
  if not n then
    for _, p in ipairs(packs or {}) do ev[#ev + 1] = {type = 'tag', pack = p} end
    return ev
  end
  local s = 0
  local function shop(after) s = s + 1; ev[#ev + 1] = {type = 'shop', after = after, shop = s} end
  if a > 1 then shop('Boss') end
  for _, blind in ipairs{'Small', 'Big'} do
    local p
    if n.chained then
      for _, q in ipairs(packs or {}) do if q.blind == blind then p = q end end
    end
    if p then ev[#ev + 1] = {type = 'tag', pack = p} else shop(blind) end
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

  -- Routed clauses by ante; the highest ante any of them names.
  local by_ante, last_ante = {}, 1
  for _, i in pairs(idx) do
    local c, r = f.clauses[i], details.results[i]
    -- A joker clause ends where its details found it.
    local a = c.kind == 'joker' and r.ante or c.ante
    if c.kind == 'joker' and not (type(a) == 'number' and a >= 1 and a <= c.ante) then
      return nil, 'details: joker clause '..i..' names no ante'
    end
    if a and a > last_ante then last_ante = a end
    local step_kind = c.kind == 'soul_in_pack' or c.kind == 'shop_joker' or c.kind == 'pack' or c.kind == 'joker'
    if step_kind then
      by_ante[a] = by_ante[a] or {}
      table.insert(by_ante[a], {c = c, r = r})
    end
  end
  local antes = {}
  for a in pairs(by_ante) do antes[#antes + 1] = a end
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
    local ev = events_of(a, n, packs)
    local known = known_packs(f, details, a)

    -- What each event must deliver: targets[e] = {soul_slot, reroll, joker, pack...}.
    local want, last = {}, 0
    local function target(e)
      want[e] = want[e] or {jokers = {}, packs = {}}
      if e > last then last = e end
      return want[e]
    end
    for _, t in ipairs(by_ante[a]) do
      local c, r = t.c, t.r
      if c.kind == 'soul_in_pack' and c.from_tag then
        for e, x in ipairs(ev) do
          if x.type == 'tag' and x.pack.blind == r.blind then target(e).tag_soul = r.index end
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
        local p = x.pack
        add{ante = a, when = p.blind, action = 'skip', key = p.tag,
          text = ('Skip the %s (%s).'):format(BLIND[p.blind], tag_name(p.tag))}
        local open = add{ante = a, when = p.blind, action = 'open_pack', key = p.pack, index = w.tag_soul}
        if w.tag_soul then
          open.soul = true
          open.text = ('%s holds the Soul in slot %d: take it.'):format((pack_name(p.pack):gsub('^t', 'T')), w.tag_soul)
        else
          open.text = ('Open %s and take nothing.'):format(pack_name(p.pack))
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
        local text = ('Play the %s.'):format(BLIND[x.after])
        if #notes > 0 then text = text..' In its shop, '..table.concat(notes, '; ')..'.' end
        add{ante = blind_ante, when = x.after, action = 'play', text = text}

        local where = x.after == 'Boss' and ('Shop after the ante-%d Boss'):format(a - 1)
          or ('Shop after the %s'):format(BLIND[x.after])
        local nr = final and (w.rerolls or 0) or n.rerolls
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
        local no = n.open and (final and (w.open or 0) or 2) or 0
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
          local cost = pack_cost(key)
          dollars = dollars and cost and dollars + cost or nil
        end
        if final then
          for _, p in ipairs(w.packs) do
            if p.slot > no then
              add{ante = a, when = 'shop', action = 'buy', slot = p.slot, key = p.key,
                text = ('%s: buy %s in slot %d.'):format(where, pack_name(p.key), p.slot)}
              local cost = pack_cost(p.key)
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
