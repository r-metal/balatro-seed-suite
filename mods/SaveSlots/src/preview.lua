-- Preview panel for one save: stats + cards. Contract: docs/SPEC.md.
--
-- API
--   preview.build(run, summary) -> a G.UIT.ROOT definition. `run` is a table shaped
--                                  like save_run() output (store.read, checkpoint.get),
--                                  `summary` is store.summarize(run). Never raises on
--                                  odd data: missing fields show as "?".
--
-- Layout follows vanilla G.UIDEF.challenge_description: a stats block (deck back
-- sprite, deck, stake, ante/round/$/hands/discards, seed, "Saved at", version), then
-- the jokers, consumables and vouchers as small `title_2` CardAreas that can't be
-- highlighted. Empty groups say localize('k_none').
--
-- Cards
--   Built fresh from G.P_CENTERS[save_fields.center] with the bypass_discovery flags,
--   then given a deep copy of the saved `ability` (so tooltips and eternal/perishable/
--   rental stickers match the save), the saved edition and `pinned`. Centers missing
--   from G.P_CENTERS (a removed mod) are skipped. Vouchers come from
--   run.GAME.used_vouchers, ordered like the collection.
--
-- Traps
--   * Never Card:load a preview card: it resizes to full card size and expects the
--     save's run to be the live one.
--   * Nothing here touches G.jokers / G.consumeables. Card:set_ability does write to
--     the live run, though: it marks G.GAME.used_jokers when no overlay is up and
--     To Do List draws from G.GAME.pseudorandom. build() puts both back afterwards,
--     so previewing never changes the run being played.
--   * Removing a card can write to the live run too: a copied
--     ability.queue_negative_removal would shrink the LIVE joker/consumable slot
--     limit when the preview closes. make_card strips REMOVAL_FLAGS (audit there)
--     from the copy; cards are still removed the normal way.
--   * Preview cards are live Card objects; a few jokers recompute tooltip numbers
--     from the current run while displayed (docs/SPEC.md "Traps", accepted).
--   * CardAreas, Cards and the back Sprite register themselves in G.I.* the moment
--     they're constructed and draw until removed. If build() raises part-way, nothing
--     owns them yet, so build() tracks every object it makes and removes them all
--     before re-raising. Otherwise they'd draw as stray cards over the game.
local preview = {}

local JOKER_SIZE = 0.6
local TEXT = 0.36
-- Outer size of the panel in every case (full, empty, bogus), so the column it sits
-- in never jumps. Must match ui.lua's DETAIL_W, DETAIL_H (ui.lua requires this
-- module, so the numbers can't be shared by require).
local PANEL_W, PANEL_H = 8, 7.3

-- Saved `ability` fields that make Card:remove touch the live run. A preview card
-- must drop them after the deep copy, since removing it has to be side-effect free.
-- Audit of build/game/card.lua (vanilla 1.0.1):
--   Card:remove        queue_negative_removal: decrements the LIVE
--                      G.jokers/G.consumeables.config.card_limit (set by
--                      remove_from_deck(from_debuff) on a debuffed negative card).
--                      ability.name: clears G.GAME.used_jokers[k] when no overlay is
--                      up. Not a flag (tooltips need it); the preview is only
--                      removed while its overlay is up, and build() is guarded.
--   remove_from_deck   every branch (h_size, d_size, Credit Card, Chaos, Turtle Bean,
--                      Oops, To the Moon, Troubadour, Stuntman, negative edition)
--                      is behind the card-level `added_to_deck`, not in `ability`.
--                      A fresh Card has it nil; make_card keeps it nil.
--   set_ability        reads the old ability's bonus/forced_selection/perma_bonus,
--                      but only runs in the Card constructor, before the copy.
--   set_edition        the negative branch bumps card_limit only if added_to_deck.
local REMOVAL_FLAGS = {'queue_negative_removal'}

local function deep_copy(t)
  return STR_UNPACK(STR_PACK(t))
end

local function num(v)
  return type(v) == 'number' and tostring(v) or '?'
end

-- 'BLIND_SELECT' -> 'Blind select'
local function humanize(state)
  if type(state) ~= 'string' or state == '' then return '?' end
  local s = state:lower():gsub('_', ' ')
  return s:sub(1, 1):upper()..s:sub(2)
end

-- The back's center: by the saved key, else by the saved name (the key is only in
-- newer saves, and summaries carry just the name).
local function back_center(run, summary)
  local back = type(run.BACK) == 'table' and run.BACK or {}
  local c = type(back.key) == 'string' and G.P_CENTERS[back.key]
  if c and c.set == 'Back' then return back.key, c end
  local name = back.name or summary.deck
  for k, v in pairs(G.P_CENTERS) do
    if v.set == 'Back' and v.name == name then return k, v end
  end
end

local function loc_name(set, key)
  local ok, s = pcall(localize, {type = 'name_text', set = set, key = key})
  if ok and type(s) == 'string' and s ~= 'ERROR' then return s end
end

local function stake_name(stake)
  local pool = G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake
  local center = type(stake) == 'number' and pool and pool[stake]
  return center and loc_name('Stake', center.key) or ('Stake '..num(stake))
end

-- A preview card: fresh from the center, then the saved ability/edition/pinned on top.
local function make_card(saved, track)
  local key = type(saved) == 'table' and type(saved.save_fields) == 'table' and saved.save_fields.center
  local center = type(key) == 'string' and G.P_CENTERS[key]
  if not center then return nil end
  local card = Card(0, 0, G.CARD_W*JOKER_SIZE, G.CARD_H*JOKER_SIZE, nil, center,
    {bypass_discovery_center = true, bypass_discovery_ui = true, bypass_lock = true})
  track(card)
  if type(saved.ability) == 'table' then
    card.ability = deep_copy(saved.ability)
    for _, flag in ipairs(REMOVAL_FLAGS) do card.ability[flag] = nil end
  end
  card.added_to_deck = nil
  if type(saved.edition) == 'table' then card:set_edition(saved.edition, true, true) end
  card.pinned = saved.pinned
  return card
end

local function card_area(w, limit, spread, track)
  return track(CardArea(0, 0, w, 0.6*G.CARD_H, {card_limit = limit,
    card_w = JOKER_SIZE*G.CARD_W, type = 'title_2', spread = spread, highlight_limit = 0}))
end

local function saved_cards(run, area)
  local a = type(run.cardAreas) == 'table' and run.cardAreas[area]
  return type(a) == 'table' and type(a.cards) == 'table' and a.cards or {}, a
end

local function saved_limit(a, default)
  local cfg = type(a) == 'table' and type(a.config) == 'table' and a.config or {}
  return type(cfg.card_limit) == 'number' and cfg.card_limit or default
end

-- One labelled group, the challenge_description column shape.
-- An empty area is removed here: it never joins the UI tree, so nothing else would.
local function group(label, label_scale, area, count, minw)
  if count == 0 then area:remove() end
  return {n=G.UIT.C, config={align = "cm", padding = 0.05, colour = G.C.L_BLACK, r = 0.1}, nodes={
    {n=G.UIT.T, config={text = label, scale = label_scale, colour = G.C.UI.TEXT_LIGHT, vert = true, shadow = true}},
    {n=G.UIT.C, config={align = "cm", minh = 0.6*G.CARD_H, minw = minw, r = 0.1, colour = G.C.UI.TRANSPARENT_DARK}, nodes={
      count > 0 and {n=G.UIT.O, config={object = area}}
        or {n=G.UIT.T, config={text = localize('k_none'), scale = 0.5, colour = G.C.UI.TEXT_LIGHT}},
    }},
  }}
end

-- A HUD-style pill: small label over a value in a coloured box.
local function pill(label, value, colour)
  return {n=G.UIT.C, config={align = "cm", padding = 0.03}, nodes={
    {n=G.UIT.C, config={align = "cm", minw = 1.05, padding = 0.05, r = 0.1, colour = G.C.UI.TRANSPARENT_DARK}, nodes={
      {n=G.UIT.R, config={align = "cm"}, nodes={
        {n=G.UIT.T, config={text = label, scale = 0.28, colour = G.C.UI.TEXT_LIGHT}},
      }},
      {n=G.UIT.R, config={align = "cm", minw = 0.9, padding = 0.03, r = 0.08, colour = colour}, nodes={
        {n=G.UIT.T, config={text = value, scale = 0.4, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
      }},
    }},
  }}
end

local function line(label, value)
  return {n=G.UIT.R, config={align = "cl", padding = 0.02}, nodes={
    {n=G.UIT.T, config={text = label, scale = 0.33, colour = G.C.UI.TEXT_LIGHT}},
    {n=G.UIT.T, config={text = value, scale = 0.35, colour = G.C.WHITE, shadow = true}},
  }}
end

local function stats(run, summary, track)
  local back_key, back = back_center(run, summary)
  local sprite = back and track(Sprite(0, 0, 0.85*G.CARD_W*JOKER_SIZE*1.4, 0.85*G.CARD_H*JOKER_SIZE*1.4,
    G.ASSET_ATLAS['centers'], back.pos))
  local deck = (back_key and loc_name('Back', back_key)) or summary.deck or '?'
  local dollars = type(summary.dollars) == 'number' and localize('$')..summary.dollars or '?'

  return {n=G.UIT.R, config={align = "cm", padding = 0.1, r = 0.1, colour = G.C.L_BLACK}, nodes={
    sprite and {n=G.UIT.C, config={align = "cm", padding = 0.05}, nodes={
      {n=G.UIT.O, config={object = sprite}},
    }} or nil,
    {n=G.UIT.C, config={align = "cl", padding = 0.05}, nodes={
      {n=G.UIT.R, config={align = "cl"}, nodes={
        {n=G.UIT.T, config={text = deck, scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
      }},
      {n=G.UIT.R, config={align = "cl"}, nodes={
        {n=G.UIT.T, config={text = stake_name(summary.stake), scale = TEXT, colour = G.C.FILTER, shadow = true}},
      }},
      {n=G.UIT.R, config={align = "cl", padding = 0.02}, nodes={
        pill(localize('k_ante'), num(summary.ante), G.C.FILTER),
        pill(localize('k_round'), num(summary.round), G.C.RED),
        pill(localize('k_money'), dollars, G.C.MONEY),
        pill(localize('k_hud_hands'), num(summary.hands), G.C.BLUE),
        pill(localize('k_hud_discards'), num(summary.discards), G.C.RED),
      }},
      line('Seed: ', tostring(summary.seed or '?')),
      line('Saved at: ', humanize(summary.state)),
      line('Version: ', tostring(summary.version or '?')),
    }},
  }}
end

-- Card:set_ability writes to the live run (see Traps); undo those writes.
local function guard_live_run(fn)
  local game = type(G.GAME) == 'table' and G.GAME or {}
  local saved = {}
  for _, k in ipairs{'used_jokers', 'pseudorandom'} do
    if type(game[k]) == 'table' then
      local copy = {}
      for kk, vv in pairs(game[k]) do copy[kk] = vv end
      saved[k] = copy
    end
  end
  local ok, res = pcall(fn)
  for k, copy in pairs(saved) do
    local t = game[k]
    for kk in pairs(t) do if copy[kk] == nil then t[kk] = nil end end
    for kk, vv in pairs(copy) do t[kk] = vv end
  end
  if not ok then error(res, 0) end
  return res
end

-- Removes every tracked object, newest first: cards before the areas holding them.
-- Each removal is pcalled so a failing one can't hide the error being re-raised.
local function remove_made(made)
  for i = #made, 1, -1 do
    local obj = made[i]
    local gone = obj.removed or (obj.is and obj:is(CardArea) and obj.cards == nil)
    if not gone then pcall(obj.remove, obj) end
    made[i] = nil
  end
end

-- The panel itself. `track` must see every Card/CardArea/Sprite made here.
local function root(run, summary, track)
  local joker_saves, joker_area = saved_cards(run, 'jokers')
  local jokers = card_area(10*JOKER_SIZE, saved_limit(joker_area, 5), false, track)
  for _, s in ipairs(joker_saves) do
    local card = make_card(s, track)
    if card then jokers:emplace(card) end
  end

  local cons_saves, cons_area = saved_cards(run, 'consumeables')
  local consumeables = card_area(3*JOKER_SIZE, saved_limit(cons_area, 2), true, track)
  for _, s in ipairs(cons_saves) do
    local card = make_card(s, track)
    if card then consumeables:emplace(card) end
  end

  local keys = {}
  local used = type(run.GAME) == 'table' and type(run.GAME.used_vouchers) == 'table' and run.GAME.used_vouchers or {}
  for k, v in pairs(used) do
    if v and G.P_CENTERS[k] then keys[#keys+1] = k end
  end
  table.sort(keys, function(a, b)
    local oa, ob = G.P_CENTERS[a].order or 0, G.P_CENTERS[b].order or 0
    if oa ~= ob then return oa < ob end
    return a < b
  end)
  local vouchers = card_area(5*JOKER_SIZE, math.max(#keys, 1), true, track)
  for _, k in ipairs(keys) do
    vouchers:emplace(make_card({save_fields = {center = k}}, track))
  end

  return {n=G.UIT.ROOT, config={align = "cm", padding = 0.1, r = 0.1, colour = G.C.BLACK,
      minw = PANEL_W, minh = PANEL_H}, nodes={
    stats(run, summary, track),
    {n=G.UIT.R, config={align = "cm", padding = 0.05}, nodes={
      group(localize('k_jokers_cap'), 0.5, jokers, #jokers.cards, 6.3),
    }},
    {n=G.UIT.R, config={align = "cm", padding = 0.05}, nodes={
      group(localize('k_cap_consumables'), 0.3, consumeables, #consumeables.cards, 2.2),
      group(localize('k_vouchers_cap'), 0.33, vouchers, #vouchers.cards, 3.3),
    }},
  }}
end

function preview.build(run, summary)
  run = type(run) == 'table' and run or {}
  summary = type(summary) == 'table' and summary or {}
  local made = {}
  local function track(obj)
    made[#made+1] = obj
    return obj
  end
  -- Cleanup runs inside guard_live_run: Card:remove also writes G.GAME.used_jokers.
  return guard_live_run(function()
    local ok, res = pcall(root, run, summary, track)
    if not ok then
      remove_made(made)
      error(res, 0)
    end
    return res
  end)
end

return preview
