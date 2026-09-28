-- seedoracle.ui: the Seed Oracle overlay and its entry points. Contract:
-- docs/contracts-0.2.md § SeedOracle.
--
-- API
--   ui.install()               wraps the entry points below. Runs once.
--   ui.open(from_pause)        opens the overlay for the live run (a no-op
--                              outside a run or inside a sim). Back returns to
--                              the pause menu when `from_pause`. In a blind
--                              daily it shows the lock note instead and
--                              returns false (Daily lock, below).
--   ui.close()                 closes the overlay, or the lock note, the way
--                              its Back button would.
--   ui.is_open()               whether the Oracle overlay is up.
--   ui.locked()                whether the live run is a blind daily.
--   ui.lock_shown()            whether the lock note is up.
--   G.FUNCS.seedoracle_open(e) the Options/pause button.
--
-- Entry points (both wrap vanilla, call the original with every argument and
-- change only what comes back; no vanilla body is copied)
--   create_UIBox_options   in a run, a "Seed Oracle" button goes right before
--                          "New Run" (the restart button). The button list is
--                          found by walking the definition for the node whose
--                          rows hold the Settings button. SaveSlots' wrapper
--                          puts its button right after Settings, so the two
--                          coexist in either wrap order.
--   Controller:key_press_update   ctrl+o (either ctrl) toggles the overlay (or
--                          the lock note) in a run, unless a text input has
--                          the keyboard or another overlay is up.
--
-- Daily lock (T-377): while G.GAME.bh_daily (seedfinder.daily: {date, mode},
--   saved with the run) has mode 'blind', both entry points open a small note
--   instead of the overlay: "Daily blind run: the Oracle is locked" (a
--   create_UIBox_generic_options with id seedoracle_locked; its Back returns to
--   the pause menu when opened from there). Nothing is predicted for it
--   (oracle.get is not called). The check is at open time only: a 'routed'
--   daily and every other run open the Oracle as before.
--
-- Overlay: one tab per ante (current + next 2), as create_tabs tabs. A tab has
--   the stable row (skip tags, boss, voucher, the Soul's legendary) and the
--   conditional rows (the shop with its rerolls, and each pack slot next to
--   what the 1st/2nd pack opened holds, if opened before rerolling). The
--   boss is a static chip with its name and vanilla description (boss_chip: no vanilla helper fits). Every item carries a badge: "stable", "if..." (conditional: if
--   nothing else consumes the stream first) or "changed in this run". The
--   model comes from seedoracle.oracle; a tab reads it when it is built, so a
--   tab switch never runs a prediction by itself (oracle.get throttles).
--   Left of the conditional rows, the what-if controls (T-322): "Skip Small",
--   "Skip Big" (greyed out once that blind is played, skipped or in play) and
--   "Rerolls" cycling 0..oracle.WHATIF_REROLLS, per ante. When this ante is at
--   the default choice (no skips, 0 rerolls) and no earlier ante skips a
--   blind, the conditional rows are the model's, as before. Otherwise (an
--   earlier ante's skip counts too, T-326) they are oracle.whatif(ante): one
--   row per shop that
--   would happen, titled by the blind it follows, with its rerolls and packs
--   (contents opened after the rerolls, the walk's order), then the tag packs
--   the skips open; every one badged "if...". Cards shrink to fit the room.
--   Divergence (T-323): while oracle.divergence() holds a record (the first
--   mismatch of this ante), a red banner above the tabs reads "Prediction
--   broke at ante A shop S: expected X, saw Y (likely: <cause>)", with what
--   was compared on a second line. The tabs are the model recomputed from
--   the live state (the detector invalidated it once).
--
-- Display-only cards (the SaveSlots preview technique, written fresh here)
--   * Cards, CardAreas, tag and blind Sprites are live objects registered in
--     G.I the moment they are built. Every one made for a tab is tracked; if
--     building raises part-way, all of them are removed and the tab shows the
--     error instead, so nothing strays onto the screen.
--   * Building writes to the live run: Card:set_ability marks
--     G.GAME.used_jokers when no overlay is up (a ctrl+o open), To Do List
--     draws from G.GAME.pseudorandom, and Tag:init bumps G.GAME.tag_tally.
--     Every build runs under `guarded`, which puts those three back.
--   * Removal: the cards go with the overlay (UIBox -> CardArea -> Card), and
--     vanilla removes the overlay while G.OVERLAY_MENU is still set, so
--     Card:remove never clears used_jokers. The cards never get
--     added_to_deck or queue_negative_removal, so removal never touches the
--     live joker/consumable limits.
local oracle = require('seedoracle.oracle')

local M = {}

local SCALE = 0.52          -- display cards, as a fraction of G.CARD_W/H
local ROOT_ID = 'seedoracle_root'
local BADGES = {
  stable = {'stable', 'GREEN'},
  conditional = {'if...', 'ORANGE'},
  unrerolled = {'if opened before rerolling', 'ORANGE'},
  changed = {'changed in this run', 'RED'},
  unverified = {'unverified', 'ORANGE'},  -- Steamodded picks bosses its own way
}
local NOTE = 'if...: if nothing else consumes the stream first'
local LOCK_ID = 'seedoracle_locked'
local LOCKED_MSG = 'Daily blind run: the Oracle is locked'

local installed = false
local from_pause = false
local chosen = nil          -- the ante of the tab to show on (re)render

local function in_run()
  return G.STAGE == G.STAGES.RUN and type(G.GAME) == 'table' and G.GAME.pseudorandom ~= nil
end

local function in_sim()
  return BHCore ~= nil and (BHCore.sim_depth or 0) > 0
end

function M.is_open()
  return G.OVERLAY_MENU ~= nil and G.OVERLAY_MENU ~= true
    and G.OVERLAY_MENU:get_UIE_by_ID(ROOT_ID) ~= nil
end

-- Daily lock (header).
function M.locked()
  local d = type(G.GAME) == 'table' and G.GAME.bh_daily
  return type(d) == 'table' and d.mode == 'blind'
end

function M.lock_shown()
  return G.OVERLAY_MENU ~= nil and G.OVERLAY_MENU ~= true
    and G.OVERLAY_MENU:get_UIE_by_ID(LOCK_ID) ~= nil
end

-- Runs fn with the live-run fields that building display objects writes put
-- back afterwards, whether fn returns or raises.
local function guarded(fn, ...)
  local game = G.GAME
  local saved = {}
  for _, k in ipairs{'used_jokers', 'pseudorandom'} do
    if type(game[k]) == 'table' then
      local copy = {}
      for kk, vv in pairs(game[k]) do copy[kk] = vv end
      saved[k] = copy
    end
  end
  local tally = game.tag_tally
  local res = {pcall(fn, ...)}
  for k, copy in pairs(saved) do
    local t = game[k]
    for kk in pairs(t) do if copy[kk] == nil then t[kk] = nil end end
    for kk, vv in pairs(copy) do t[kk] = vv end
  end
  game.tag_tally = tally
  if not res[1] then error(res[2], 0) end
  return unpack(res, 2)
end

local function text(s, scale, colour, extra)
  local cfg = {text = s, scale = scale, colour = colour or G.C.UI.TEXT_LIGHT, shadow = true}
  for k, v in pairs(extra or {}) do cfg[k] = v end
  return {n=G.UIT.T, config = cfg}
end

local function row(nodes, cfg)
  cfg = cfg or {}
  cfg.align = cfg.align or 'cm'
  return {n=G.UIT.R, config = cfg, nodes = nodes}
end

local function badge(kind)
  local b = BADGES[kind] or BADGES.conditional
  return row({
    {n=G.UIT.C, config={align = 'cm', r = 0.08, padding = 0.04, minw = 0.9, colour = G.C[b[2]]}, nodes={
      text(b[1], 0.27, G.C.UI.TEXT_LIGHT),
    }},
  }, {padding = 0.03})
end

local function loc_name(set, key)
  local ok, s = pcall(localize, {type = 'name_text', set = set, key = key})
  if ok and type(s) == 'string' and s ~= 'ERROR' then return s end
  return tostring(key)
end

-- A display-only Card from a prediction record.
local function display_card(rec, track, scale)
  local center = rec and G.P_CENTERS[rec.key]
  if not center then return nil end
  local front = rec.front and G.P_CARDS[rec.front] or nil
  local c = track(Card(0, 0, G.CARD_W*scale, G.CARD_H*scale, front, center,
    {bypass_discovery_center = true, bypass_discovery_ui = true, bypass_lock = true}))
  if rec.edition then c:set_edition({[rec.edition] = true}, true, true) end
  if rec.seal then c:set_seal(rec.seal, true, true) end
  local st = rec.stickers or {}
  if st.eternal then c.ability.eternal = true end
  if st.perishable then
    c.ability.perishable = true
    c.ability.perish_tally = G.GAME.perishable_rounds
  end
  if st.rental then c.ability.rental = true end
  return c
end

-- A title_2 CardArea holding the records' cards. `what` tags it for tests.
-- `scale` (default SCALE) sizes the cards.
local function card_row(recs, slots, what, ante, track, scale)
  scale = scale or SCALE
  local w = G.CARD_W*scale*math.max(slots, 1)*1.02
  local area = track(CardArea(0, 0, w, G.CARD_H*scale, {card_limit = math.max(slots, 1),
    card_w = G.CARD_W*scale, type = 'title_2', highlight_limit = 0}))
  area.seedoracle = {what = what, ante = ante}
  for _, rec in ipairs(recs or {}) do
    local c = display_card(rec, track, scale)
    if c then area:emplace(c) end
  end
  return {n=G.UIT.O, config={object = area}}
end

local function tag_sprite(key, slot, track)
  if not (key and G.P_TAGS[key]) then return text('?', 0.5) end
  local tag = Tag(key, true)
  local node, sprite = tag:generate_UI(0.9)
  track(sprite)
  sprite.seedoracle = {what = 'tag_'..slot, key = key}
  return node
end

-- The boss chip. No vanilla helper builds a chip for an arbitrary blind:
-- create_UIBox_blind_choice (UI_definitions.lua:1485) reads the live run's
-- round_resets.blind_choices and writes blind_states and orbital_choices (a
-- 'orbital' pseudoseed draw); create_UIBox_round_scores_row('defeated_by')
-- reads G.GAME.blind; the collection and challenge screens build theirs
-- inline. So this is a minimal one of its own: a static AnimatedSprite (no
-- hover, no popup), with the name and the vanilla description (localize
-- 'raw_descriptions') shown next to it instead of in a hover popup.
local function boss_chip(key, track)
  local blind = key and G.P_BLINDS[key]
  if not blind then return text('?', 0.5) end
  local s = track(AnimatedSprite(0, 0, 1.1, 1.1, G.ANIMATION_ATLAS['blind_chips'], blind.pos))
  s:define_draw_steps({{shader = 'dissolve', shadow_height = 0.05}, {shader = 'dissolve'}})
  s.states.hover.can = false
  s.states.drag.can = false
  s.states.collide.can = false
  s.seedoracle = {what = 'boss', key = key}
  return {n=G.UIT.O, config={object = s}}
end

-- The boss's description lines, as vanilla words them.
local function boss_lines(key)
  local blind = key and G.P_BLINDS[key]
  if not blind then return {} end
  local ok, lines = pcall(localize, {type = 'raw_descriptions', key = key, set = 'Blind', vars = blind.vars})
  if not ok or type(lines) ~= 'table' then return {} end
  local out = {}
  for i, line in ipairs(lines) do
    -- The Wheel's text starts at " in 7": the game puts the odds in front.
    if i == 1 and key == 'bl_wheel' then line = tostring(G.GAME.probabilities.normal or 1)..line end
    out[i] = line
  end
  return out
end

local function boss_desc(key)
  local blind = key and G.P_BLINDS[key]
  local lines = boss_lines(key)
  if not blind or #lines == 0 then return nil end
  local rows = {}
  for i, line in ipairs(lines) do rows[i] = row({text(line, 0.3, G.C.WHITE)}, {maxw = 2.6}) end
  return row({
    {n=G.UIT.C, config={id = 'seedoracle_boss_desc', align = 'cm', r = 0.08, padding = 0.05, minw = 2.6,
      colour = mix_colours(blind.boss_colour or G.C.GREY, G.C.GREY, 0.4)}, nodes = rows},
  })
end

-- One labelled box of the stable row.
-- `extra` (optional) goes between the name and the badge.
local function stable_box(label, object, name, kind, extra)
  local nodes = {
    row({text(label, 0.32, G.C.UI.TEXT_LIGHT)}),
    row({object}, {minh = G.CARD_H*SCALE + 0.05}),
    row({text(name, 0.3, G.C.WHITE)}, {maxw = 2.2}),
  }
  if extra then nodes[#nodes + 1] = extra end
  nodes[#nodes + 1] = badge(kind)
  return {n=G.UIT.C, config={align = 'cm', padding = 0.06, r = 0.1, colour = G.C.L_BLACK, minw = 2.35, minh = 2.45}, nodes = nodes}
end

local function stable_row(rec, track)
  local soul_box
  if rec.soul then
    local soul_name = rec.soul.key and loc_name('Joker', rec.soul.key) or '?'
    if rec.soul.edition then soul_name = soul_name..' ('..rec.soul.edition..')' end
    soul_box = stable_box('The Soul makes', card_row({{key = rec.soul.key, edition = rec.soul.edition}}, 1, 'soul', rec.ante, track),
      soul_name, rec.soul.badge)
  end
  return row({
    stable_box('Small Blind tag', tag_sprite(rec.tags.small.key, 'small', track), loc_name('Tag', rec.tags.small.key), rec.tags.small.badge),
    stable_box('Big Blind tag', tag_sprite(rec.tags.big.key, 'big', track), loc_name('Tag', rec.tags.big.key), rec.tags.big.badge),
    stable_box('Boss', boss_chip(rec.boss.key, track), loc_name('Blind', rec.boss.key), rec.boss.badge,
      boss_desc(rec.boss.key)),
    stable_box('Voucher', card_row({{key = rec.voucher.key}}, 1, 'voucher', rec.ante, track),
      loc_name('Voucher', rec.voucher.key), rec.voucher.badge),
    soul_box,
  }, {padding = 0.06})
end

-- A captioned group inside a conditional box.
local function group(caption, node)
  return {n=G.UIT.C, config={align = 'cm', padding = 0.04, r = 0.1, colour = G.C.UI.TRANSPARENT_DARK}, nodes={
    row({text(caption, 0.28, G.C.UI.TEXT_LIGHT)}),
    row({node}),
  }}
end

local function cond_box(title, nodes, kind)
  local inner = {}
  for _, n in ipairs(nodes) do inner[#inner + 1] = n end
  return {n=G.UIT.C, config={align = 'cm', padding = 0.06, r = 0.1, colour = G.C.L_BLACK}, nodes={
    {n=G.UIT.C, config={align = 'cm', padding = 0.04}, nodes={
      row({text(title, 0.34, G.C.UI.TEXT_LIGHT, {vert = true})}),
    }},
    {n=G.UIT.C, config={align = 'cm', padding = 0.04}, nodes={
      row(inner, {padding = 0.02}),
      badge(kind or 'conditional'),
    }},
  }}
end

local function shop_rows(rec, track)
  local shop = rec.shop
  if not shop then
    return {row({
      {n=G.UIT.C, config={align = 'cm', r = 0.1, padding = 0.2, colour = G.C.L_BLACK, minw = 6, minh = 1.2}, nodes={
        text(rec.shop_note or 'No shop predicted', 0.4, G.C.UI.TEXT_LIGHT),
      }},
    }, {padding = 0.06})}
  end
  local slots = math.max(#shop.cards, 2)
  local groups = {group(shop.live and 'On the shelf' or 'Cards', card_row(shop.cards, slots, 'shop', rec.ante, track))}
  for r, cards in ipairs(shop.rerolls) do
    groups[#groups + 1] = group('Reroll '..r, card_row(cards, slots, 'reroll'..r, rec.ante, track))
  end
  local out = {row({cond_box(shop.title, groups)}, {padding = 0.06})}

  -- Pack contents follow opening order, not the slot: contents[i] is what the
  -- i-th pack opened holds, whichever slot it is.
  local ordinal = {'1st', '2nd', '3rd'}
  local packs = {}
  for i, p in ipairs(shop.packs) do
    local name = G.P_CENTERS[p.key] and G.P_CENTERS[p.key].name or tostring(p.key)
    packs[#packs + 1] = cond_box('Pack '..i, {
      group(name, card_row({{key = p.key}}, 1, 'pack'..i, rec.ante, track)),
      group((ordinal[i] or i..'th')..' opened holds', card_row(shop.contents[i], math.min(p.size or 3, 4), 'contents'..i, rec.ante, track)),
    }, 'unrerolled')
  end
  if #packs > 0 then out[#out + 1] = row(packs, {padding = 0.06}) end
  return out
end

-- What-if (oracle.lua header: What-if). The controls: one button per choice,
-- G.FUNCS.seedoracle_whatif with ref_table = {ante, field}; a skip whose
-- blind is no longer ahead is greyed out and has no button.
local function whatif_button(ante, field, label, colour, enabled)
  return row({
    {n=G.UIT.C, config={id = 'seedoracle_whatif_'..field, align = 'cm', minw = 2.2, minh = 0.42, r = 0.08,
      padding = 0.05, hover = enabled, shadow = enabled,
      colour = enabled and colour or G.C.UI.BACKGROUND_INACTIVE,
      button = enabled and 'seedoracle_whatif' or nil, ref_table = {ante = ante, field = field}}, nodes={
      text(label, 0.3, enabled and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE),
    }},
  }, {padding = 0.03})
end

local function whatif_controls(ante)
  local c = oracle.choice(ante)
  local nodes = {row({text('What if', 0.32, G.C.UI.TEXT_LIGHT)})}
  for _, blind in ipairs{'Small', 'Big'} do
    local ahead = oracle.ahead(ante, blind)
    local label = 'Skip '..blind..': '..(not ahead and '-' or c.skip[blind] and 'on' or 'off')
    nodes[#nodes + 1] = whatif_button(ante, blind, label, c.skip[blind] and G.C.GREEN or G.C.RED, ahead)
  end
  nodes[#nodes + 1] = whatif_button(ante, 'rerolls', 'Rerolls: '..c.rerolls, G.C.FILTER, true)
  return {n=G.UIT.C, config={align = 'cm', padding = 0.06, r = 0.1, colour = G.C.L_BLACK}, nodes = nodes}
end

-- The card scale that fits the what-if rows into about the room the model's
-- rows take today: `rows` rows; a row is `slots` card slots wide in `groups`
-- captioned groups inside `boxes` titled boxes (measured off the rig's shots:
-- ~0.35 per group and ~0.8 per box of padding and titles, ~0.9 of height per
-- row besides the cards).
local WHATIF_W, WHATIF_H = 17, 5.3
local function whatif_scale(rows, width)
  local by_h = (WHATIF_H - 0.9*rows)/(G.CARD_H*math.max(rows, 1))
  local s = math.min(SCALE, by_h)
  for _, w in ipairs(width) do
    s = math.min(s, (WHATIF_W - 0.35*w.groups - 0.8*w.boxes)/(G.CARD_W*1.02*math.max(w.slots, 1)))
  end
  return math.max(0.24, s)
end

-- The what-if rows: one row per shop (the row and its rerolls, then its
-- packs), then a row of the tag packs the skips open. Areas are tagged
-- shop<i>, shop<i>_reroll<r>, shop<i>_pack<j>, shop<i>_contents<j>,
-- tagpack<k> and tagpack<k>_contents.
local function whatif_rows(rec, wi, track)
  local function note(msg)
    return row({
      {n=G.UIT.C, config={align = 'cm', r = 0.1, padding = 0.2, colour = G.C.L_BLACK, minw = 6, minh = 1.2}, nodes={
        text(msg, 0.4, G.C.UI.TEXT_LIGHT),
      }},
    }, {padding = 0.06})
  end
  if wi.error then return {note('The what-if could not be predicted: '..wi.error)} end
  local R = wi.choice.rerolls
  local width = {}
  for _, shop in ipairs(wi.shops) do
    local w = {slots = math.max(#(shop.cards or {}), 2)*(1 + R), groups = 1 + R, boxes = 1}
    for _, p in ipairs(shop.packs) do
      w.slots, w.groups, w.boxes = w.slots + 1 + math.min(p.size or 3, 4), w.groups + 2, w.boxes + 1
    end
    width[#width + 1] = w
  end
  if #wi.tag_packs + #wi.no_pack > 0 then
    local w = {slots = 0, groups = #wi.no_pack, boxes = #wi.tag_packs + #wi.no_pack}
    for _, tp in ipairs(wi.tag_packs) do w.slots, w.groups = w.slots + 1 + #(tp.cards or {}), w.groups + 2 end
    width[#width + 1] = w
  end
  local s = whatif_scale(#width, width)
  local out = {}
  local ordinal = {'1st', '2nd', '3rd'}
  for i, shop in ipairs(wi.shops) do
    local w = math.max(#(shop.cards or {}), 2)
    local id = 'shop'..i
    local cgroups = {group(shop.live and 'On the shelf' or 'Cards', card_row(shop.cards, w, id, rec.ante, track, s))}
    for r, cards in ipairs(shop.rerolls) do
      cgroups[#cgroups + 1] = group('Reroll '..r, card_row(cards, w, id..'_reroll'..r, rec.ante, track, s))
    end
    local boxes = {cond_box(shop.title, cgroups)}
    for j, p in ipairs(shop.packs) do
      local name = G.P_CENTERS[p.key] and G.P_CENTERS[p.key].name or tostring(p.key)
      boxes[#boxes + 1] = cond_box('Pack '..j, {
        group(name, card_row({{key = p.key}}, 1, id..'_pack'..j, rec.ante, track, s)),
        group((ordinal[j] or j..'th')..' opened holds',
          card_row(shop.contents[j], math.min(p.size or 3, 4), id..'_contents'..j, rec.ante, track, s)),
      })
    end
    out[#out + 1] = row(boxes, {padding = 0.04})
  end
  local tagged = {}
  for k, tp in ipairs(wi.tag_packs) do
    local name = G.P_CENTERS[tp.pack] and G.P_CENTERS[tp.pack].name or tostring(tp.pack)
    tagged[#tagged + 1] = cond_box('Skip '..tp.blind, {
      group(loc_name('Tag', tp.tag)..' opens', card_row({{key = tp.pack}}, 1, 'tagpack'..k, rec.ante, track, s)),
      group(name..' holds', card_row(tp.cards, math.max(#(tp.cards or {}), 1), 'tagpack'..k..'_contents',
        rec.ante, track, s)),
    })
  end
  for _, np in ipairs(wi.no_pack) do
    tagged[#tagged + 1] = cond_box('Skip '..np.blind, {
      group(loc_name('Tag', np.tag), text('no pack', 0.3, G.C.UI.TEXT_LIGHT)),
    })
  end
  if #tagged > 0 then out[#out + 1] = row(tagged, {padding = 0.04}) end
  if #out == 0 then out[1] = note('No shop left in this ante') end
  return out
end

local function find_rec(model, ante)
  for _, rec in ipairs(model and model.antes or {}) do
    if rec.ante == ante then return rec end
  end
end

local function message_root(msg)
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.CLEAR, minw = 8, minh = 3}, nodes={
    row({text(msg, 0.4, G.C.UI.TEXT_LIGHT)}, {maxw = 12}),
  }}
end

-- Removes tracked objects newest first, each under pcall.
local function remove_made(made)
  for i = #made, 1, -1 do
    local obj = made[i]
    local gone = obj.removed or (obj.is and obj:is(CardArea) and obj.cards == nil)
    if not gone then pcall(obj.remove, obj) end
    made[i] = nil
  end
end

local function tab_root(ante)
  chosen = ante
  local model = oracle.get()
  local rec = find_rec(model, ante)
  if model and model.off then return message_root(model.off) end
  if model and model.error then return message_root('The Oracle could not predict this run: '..model.error) end
  if not rec then return message_root('Ante '..tostring(ante)..' is behind the run now: reopen the Oracle') end
  local wi = oracle.whatif(ante)
  local made = {}
  local function track(obj) made[#made + 1] = obj; return obj end
  local ok, res = pcall(guarded, function()
    local cond = wi and whatif_rows(rec, wi, track) or shop_rows(rec, track)
    return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.CLEAR, padding = 0.02}, nodes = {
      stable_row(rec, track),
      row(rec.soul and {whatif_controls(ante), {n=G.UIT.C, config={align = 'cm'}, nodes = cond}}
        or {{n=G.UIT.C, config={align = 'cm'}, nodes = cond}}),  -- no what-if without shop predictions
    }}
  end)
  if ok then return res end
  guarded(remove_made, made)
  print('[SeedOracle] overlay failed: '..tostring(res))
  return message_root('The Oracle could not draw this ante')
end

-- The divergence banner (header: Divergence), or nil.
local function divergence_banner()
  local d = oracle.divergence()
  if not d then return nil end
  return row({
    {n=G.UIT.C, config={id = 'seedoracle_diverge', align = 'cm', r = 0.1, padding = 0.08, colour = G.C.RED}, nodes={
      row({text(string.format('Prediction broke at ante %d shop %d: expected %s, saw %s (likely: %s)',
        d.ante, d.shop, d.expected, d.got, d.likely), 0.32, G.C.UI.TEXT_LIGHT)}, {maxw = 17}),
      row({text('('..d.what..'; the tabs below are recomputed from the run as it is now)', 0.26,
        G.C.UI.TEXT_LIGHT)}, {maxw = 17}),
    }},
  }, {padding = 0.02})
end

local function overlay_def(model)
  local tabs = {}
  for _, rec in ipairs(model.antes) do
    tabs[#tabs + 1] = {
      label = localize('k_ante')..' '..rec.ante..(rec.current and ' (now)' or ''),
      chosen = rec.ante == chosen,
      tab_definition_function = tab_root,
      tab_definition_function_args = rec.ante,
    }
  end
  if #tabs == 0 then
    tabs[1] = {label = 'Oracle', chosen = true, tab_definition_function = message_root,
      tab_definition_function_args = model.off or model.error or 'Nothing to predict'}
  end
  local found = false
  for _, t in ipairs(tabs) do found = found or t.chosen end
  if not found then tabs[1].chosen = true end
  local contents = {
    row({
      text('Seed Oracle', 0.55, G.C.UI.TEXT_LIGHT),
      text('   '..localize('b_seed')..': '..tostring(model.seed), 0.4, G.C.FILTER),
    }, {id = ROOT_ID, padding = 0.02}),
  }
  -- Under Steamodded or content mods, say what the predictions can't be trusted for.
  local notice = BHCore.env_notice()
  if notice then contents[#contents + 1] = row({text(notice, 0.3, G.C.ORANGE)}, {padding = 0.02}) end
  local banner = divergence_banner()
  if banner then contents[#contents + 1] = banner end
  contents[#contents + 1] = row({create_tabs{tabs = tabs, snap_to_nav = true, scale = 0.9, text_scale = 0.4,
    colour = G.C.BOOSTER}})
  if not model.off then contents[#contents + 1] = row({text(NOTE, 0.28, G.C.UI.TEXT_LIGHT)}) end
  return create_UIBox_generic_options{
    back_func = from_pause and 'options' or 'exit_overlay_menu',
    padding = 0.05,
    contents = contents,
  }
end

-- Rebuilds the chosen tab in place (vanilla change_tab on its tab button).
local function rerender()
  local label = localize('k_ante')..' '..tostring(chosen)
  for _, suffix in ipairs{' (now)', ''} do
    local but = G.OVERLAY_MENU:get_UIE_by_ID('tab_but_'..label..suffix)
    if but then G.FUNCS.change_tab(but); return true end
  end
  return false
end

-- Re-renders the chosen tab once the throttle lets a held-back recompute run.
local function refresh_later()
  G.E_MANAGER:add_event(Event({
    trigger = 'after', delay = oracle.THROTTLE + 0.05, timer = 'REAL', pause_force = true,
    blocking = false, blockable = false,
    func = function()
      if not M.is_open() then return true end
      local _, pending = oracle.get()
      if pending then refresh_later(); return true end
      rerender()
      return true
    end,
  }))
end

-- The lock note (header: Daily lock), in place of the overlay.
local function show_locked()
  G.SETTINGS.paused = true
  G.FUNCS.overlay_menu{definition = create_UIBox_generic_options{
    back_func = from_pause and 'options' or 'exit_overlay_menu',
    contents = {
      row({text(LOCKED_MSG, 0.5, G.C.UI.TEXT_LIGHT)}, {id = LOCK_ID, padding = 0.15}),
      row({text('A routed daily, or any other run, opens it', 0.32, G.C.UI.TEXT_LIGHT)}, {padding = 0.05}),
    },
  }}
end

function M.open(pause)
  if not in_run() or in_sim() then return false end
  if M.locked() then
    from_pause = pause and true or false
    show_locked()
    return false
  end
  local model, pending = oracle.get()
  if not model then return false end
  from_pause = pause and true or false
  chosen = model.ante
  G.SETTINGS.paused = true
  guarded(function() G.FUNCS.overlay_menu{definition = overlay_def(model)} end)
  if pending then refresh_later() end
  return true
end

function M.close()
  if not (M.is_open() or M.lock_shown()) then return end
  if from_pause then G.FUNCS.options() else G.FUNCS.exit_overlay_menu() end
end

-- The node whose rows hold the Settings button, and that row's index.
local function options_list(node)
  if type(node) ~= 'table' or type(node.nodes) ~= 'table' then return nil end
  for _, child in pairs(node.nodes) do
    if type(child) == 'table' and type(child.nodes) == 'table' then
      for _, inner in pairs(child.nodes) do
        if type(inner) == 'table' and type(inner.config) == 'table' and inner.config.button == 'settings' then
          return node
        end
      end
    end
  end
  for _, child in pairs(node.nodes) do
    local found = options_list(child)
    if found then return found end
  end
end

local function row_button(child)
  if type(child) ~= 'table' or type(child.nodes) ~= 'table' then return nil end
  for _, inner in pairs(child.nodes) do
    if type(inner) == 'table' and type(inner.config) == 'table' and inner.config.button then
      return inner.config.button
    end
  end
end

local function add_button(t)
  if G.STAGE ~= G.STAGES.RUN then return t end
  local list = options_list(t)
  if not list then return t end
  -- Vanilla leaves nil holes for options that don't apply; keep the order and
  -- build a dense list with the button before New Run (else at the end).
  local nodes, placed = {}, false
  local button = UIBox_button{label = {'Seed Oracle'}, button = 'seedoracle_open', minw = 5}
  for i = 1, table.maxn(list.nodes) do
    local child = list.nodes[i]
    if child ~= nil then
      local b = row_button(child)
      if b == 'seedoracle_open' then return t end
      if b == 'setup_run' and not placed then nodes[#nodes + 1] = button; placed = true end
      nodes[#nodes + 1] = child
    end
  end
  if not placed then nodes[#nodes + 1] = button end
  list.nodes = nodes
  return t
end

function M.install()
  if installed then return end
  installed = true

  local orig_options = create_UIBox_options
  create_UIBox_options = function(...)
    return add_button(orig_options(...))
  end

  G.FUNCS.seedoracle_open = function(e)
    M.open(true)
  end

  -- A what-if control: flips a skip or steps the reroll cycle 0..max, then
  -- rebuilds the tab (which re-predicts it on a copy; oracle.whatif).
  G.FUNCS.seedoracle_whatif = function(e)
    local ref = e and e.config and e.config.ref_table
    if not (ref and M.is_open()) then return end
    local c = oracle.choice(ref.ante)
    if ref.field == 'rerolls' then
      oracle.set_choice(ref.ante, 'rerolls', (c.rerolls + 1) % (oracle.WHATIF_REROLLS + 1))
    elseif oracle.ahead(ref.ante, ref.field) then
      oracle.set_choice(ref.ante, ref.field, not c.skip[ref.field])
    end
    chosen = ref.ante
    rerender()
  end

  local orig_key = Controller.key_press_update
  Controller.key_press_update = function(self, key, ...)
    local r = orig_key(self, key, ...)
    if key == 'o' and not self.locks.frame and not self.text_input_hook
        and (self.held_keys['lctrl'] or self.held_keys['rctrl']) and in_run() then
      if M.is_open() or M.lock_shown() then
        M.close()
      elseif not G.OVERLAY_MENU then
        M.open(false)
      end
    end
    return r
  end
end

return M
