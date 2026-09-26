-- Preview: a run with 3 jokers (one foil + eternal), 1 consumable and 1 voucher is
-- saved, then preview.build renders it inside an overlay. Asserts the card counts by
-- walking the overlay's CardAreas, and that the foil joker kept its edition and
-- eternal sticker. A second run table with an unknown joker center
-- and an unknown voucher must build without error. Leak check: preview.build is made
-- to raise part-way (once after every area, card and sprite exists, once while a card
-- is half-built), and every CardArea/Card/Sprite it made must be gone afterwards.
-- Slot limits: a run whose joker and consumable are negative with
-- ability.queue_negative_removal set is previewed and closed, and the live
-- G.jokers/G.consumeables card_limit must be unchanged. Panel size: full, bogus,
-- empty and nothing-at-all runs all lay out to ui.lua's DETAIL_W x DETAIL_H.
-- Screenshots: preview.png, preview_hover.png (tooltip of the foil joker),
-- preview_bogus.png, preview_after_leak.png (the run with nothing stray on it),
-- preview_negative.png, preview_empty.png.
local preview = require('saveslots.preview')
local store = require('saveslots.store')

-- Counts the preview cards under a UIBox by set: jokers, consumables, vouchers.
local function count_cards(box)
  local n = {joker = 0, consumable = 0, voucher = 0, areas = 0}
  local function walk(node)
    if type(node) ~= 'table' then return end
    local obj = node.config and node.config.object
    if type(obj) == 'table' and obj.is then
      if obj:is(CardArea) then
        n.areas = n.areas + 1
        for _, c in ipairs(obj.cards or {}) do
          if c.ability.set == 'Joker' then n.joker = n.joker + 1
          elseif c.ability.consumeable then n.consumable = n.consumable + 1
          elseif c.ability.set == 'Voucher' then n.voucher = n.voucher + 1 end
        end
      elseif obj:is(UIBox) then
        walk(obj.UIRoot)
      end
    end
    for _, child in ipairs(node.children or {}) do walk(child) end
  end
  walk(box.UIRoot)
  return n
end

-- The first preview card with center `key` under the UIBox.
local function find_preview_card(box, key)
  local found
  local function walk(node)
    if found or type(node) ~= 'table' then return end
    local obj = node.config and node.config.object
    if type(obj) == 'table' and obj.is and obj:is(CardArea) then
      for _, c in ipairs(obj.cards or {}) do
        if c.config.center_key == key then found = c; return end
      end
    end
    for _, child in ipairs(node.children or {}) do walk(child) end
  end
  walk(box.UIRoot)
  return found
end

-- True if some text node under the UIBox reads exactly `text`.
local function has_text(box, text)
  local function walk(node)
    if type(node) ~= 'table' then return false end
    if node.config and node.config.text == text then return true end
    for _, child in ipairs(node.children or {}) do
      if walk(child) then return true end
    end
    return false
  end
  return walk(box.UIRoot)
end

local function open_preview(run)
  local def = preview.build(run, store.summarize(run))
  assert(def.n == G.UIT.ROOT, 'preview.build did not return a ROOT')
  def.n = G.UIT.R
  G.FUNCS.overlay_menu{definition = create_UIBox_generic_options{contents = {def}}}
end

local function add_joker(key, edition, eternal)
  local card = create_card('Joker', G.jokers, nil, nil, nil, nil, key)
  if edition then card:set_edition(edition, true, true) end
  if eternal then card:set_eternal(true) end
  card:add_to_deck()
  G.jokers:emplace(card)
end

-- Live instance counts of what preview.build creates.
local function instances()
  return {areas = #G.I.CARDAREA, cards = #G.I.CARD, sprites = #G.I.SPRITE}
end

-- Calls preview.build with `plant` installed, which must make it raise with
-- 'planted'. Returns the stray counts per kind and how many areas existed when it
-- raised (so a raise before anything was built can't pass as "no leak").
local function build_with_error(ctx, run, plant)
  local before = instances()
  local at_raise
  local unplant = plant(function() at_raise = instances() end)
  local ok, err = pcall(preview.build, run, store.summarize(run))
  unplant()
  ctx.assert(not ok, 'the planted error never fired')
  ctx.assert(tostring(err):find('planted', 1, true), 'unexpected error: '..tostring(err))
  local after = instances()
  return {areas = after.areas - before.areas, cards = after.cards - before.cards,
    sprites = after.sprites - before.sprites}, at_raise.areas - before.areas
end

-- The UIBox's laid-out size for preview.build's ROOT, then the box is removed.
local function panel_size(run)
  local box = UIBox{definition = preview.build(run, store.summarize(run)), config = {offset = {x = 0, y = 0}, align = 'cm'}}
  local w, h = box.T.w, box.T.h
  box:remove()
  return w, h
end

local function slot_limits()
  return G.jokers.config.card_limit, G.consumeables.config.card_limit
end

local saved_run
local limits_before

return {
  {name = 'start run', run = function(ctx)
    ctx.start_run{}
    return true
  end},
  {name = 'blind select', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
  end},
  {name = 'give cards', run = function(ctx)
    add_joker('j_joker', {foil = true}, true)
    add_joker('j_greedy_joker')
    add_joker('j_blueprint')
    local tarot = create_card('Tarot', G.consumeables, nil, nil, nil, nil, 'c_fool')
    tarot:add_to_deck()
    G.consumeables:emplace(tarot)
    G.GAME.used_vouchers.v_overstock_norm = true
    return true
  end},
  {name = 'settle and save', timeout = 10, run = function(ctx)
    if ctx.step_time() < 1.5 or not G.STATE_COMPLETE then return false end
    save_run()
    saved_run = G.culled_table
    ctx.assert(type(saved_run) == 'table', 'save_run produced no G.culled_table')
    ctx.assert(#saved_run.cardAreas.jokers.cards == 3, 'saved run has '..#saved_run.cardAreas.jokers.cards..' jokers')
    return true
  end},
  {name = 'open preview', run = function(ctx)
    local live_jokers, live_cons = #G.jokers.cards, #G.consumeables.cards
    open_preview(saved_run)
    ctx.assert(#G.jokers.cards == live_jokers and #G.consumeables.cards == live_cons,
      'preview.build changed the live run\'s card areas')
    return true
  end},
  {name = 'preview up', run = function(ctx)
    -- park the cursor in a corner so no card pops a tooltip over the stats
    love.mouse.setPosition(love.graphics.getWidth() - 2, love.graphics.getHeight() - 2)
    if not G.OVERLAY_MENU or ctx.step_time() < 1.5 then return false end
    local n = count_cards(G.OVERLAY_MENU)
    ctx.log(('preview: %d jokers, %d consumables, %d vouchers in %d areas'):format(n.joker, n.consumable, n.voucher, n.areas))
    ctx.assert(n.joker == 3, 'expected 3 jokers, got '..n.joker)
    ctx.assert(n.consumable == 1, 'expected 1 consumable, got '..n.consumable)
    ctx.assert(n.voucher == 1, 'expected 1 voucher, got '..n.voucher)
    ctx.assert(has_text(G.OVERLAY_MENU, 'Blind select'), '"Saved at" state missing')
    ctx.shot('preview')
    return true
  end},
  {name = 'hover foil joker', run = function(ctx)
    local card = find_preview_card(G.OVERLAY_MENU, 'j_joker')
    ctx.assert(card, 'preview j_joker not found')
    ctx.assert(card.edition and card.edition.foil, 'preview j_joker lost its foil edition')
    ctx.assert(card.ability.eternal, 'preview j_joker lost its eternal sticker')
    card:hover()
    return true
  end},
  {name = 'hover shot', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.shot('preview_hover')
    return true
  end},
  {name = 'close preview', run = function(ctx)
    ctx.assert(ctx.click('exit_overlay_menu'), 'Back button not found')
    return true
  end},
  {name = 'bogus centers', run = function(ctx)
    if G.OVERLAY_MENU then return false end
    local run = STR_UNPACK(STR_PACK(saved_run))
    run.cardAreas.jokers.cards[1].save_fields.center = 'j_does_not_exist'
    run.GAME.used_vouchers.v_does_not_exist = true
    run.BACK = {name = 'No Such Deck'}
    open_preview(run)
    return true
  end},
  {name = 'bogus preview up', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    local n = count_cards(G.OVERLAY_MENU)
    ctx.assert(n.joker == 2 and n.consumable == 1 and n.voucher == 1,
      ('bogus run: expected 2/1/1, got %d/%d/%d'):format(n.joker, n.consumable, n.voucher))
    ctx.shot('preview_bogus')
    return true
  end},
  {name = 'close bogus preview', run = function(ctx)
    ctx.assert(ctx.click('exit_overlay_menu'), 'Back button not found')
    return true
  end},
  {name = 'overlay gone', run = function(ctx)
    return G.OVERLAY_MENU == nil
  end},
  {name = 'leak check', run = function(ctx)
    -- 1. raise after every area, card and the back sprite exist (the first group label)
    local late, late_areas = build_with_error(ctx, saved_run, function(mark)
      local orig = localize
      localize = function(args, ...)
        if args == 'k_jokers_cap' then mark(); error('planted: localize', 0) end
        return orig(args, ...)
      end
      return function() localize = orig end
    end)
    ctx.assert(late_areas == 3, 'expected 3 areas alive at the late raise, got '..late_areas)
    -- 2. raise inside make_card: the foil joker is built but not yet in its area
    local mid, mid_areas = build_with_error(ctx, saved_run, function(mark)
      local orig = Card.set_edition
      Card.set_edition = function(self, ...)
        mark(); error('planted: set_edition', 0)
      end
      return function() Card.set_edition = orig end
    end)
    ctx.assert(mid_areas == 1, 'expected 1 area alive at the mid raise, got '..mid_areas)
    ctx.log(('leak check: late raise left %d areas, %d cards, %d sprites; mid raise left %d areas, %d cards, %d sprites')
      :format(late.areas, late.cards, late.sprites, mid.areas, mid.cards, mid.sprites))
    -- every kind in every case on its own: a +1 and a -1 must not cancel out
    for _, case in ipairs{{'late', late}, {'mid', mid}} do
      for _, kind in ipairs{'areas', 'cards', 'sprites'} do
        local d = case[2][kind]
        ctx.assert(d == 0, ('%s raise: %d stray %s after a failed preview.build'):format(case[1], d, kind))
      end
    end
    ctx.assert(#G.jokers.cards == 3 and #G.consumeables.cards == 1, 'the failed build touched the live run')
    ctx.log('leak check: 0 stray')
    return true
  end},
  {name = 'after leak shot', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.shot('preview_after_leak')
    return true
  end},
  {name = 'queued negative removal', run = function(ctx)
    -- A save taken while a negative joker/consumable was debuffed carries
    -- ability.queue_negative_removal = true; Card:remove acts on it against the
    -- LIVE G.jokers/G.consumeables limits. Removing the preview must not.
    local run = STR_UNPACK(STR_PACK(saved_run))
    for _, area in ipairs{'jokers', 'consumeables'} do
      local c = run.cardAreas[area].cards[1]
      c.ability.queue_negative_removal = true
      c.edition = {negative = true}
    end
    local j, c = slot_limits()
    limits_before = {j, c}
    ctx.log(('live slot limits before: jokers %d, consumables %d'):format(j, c))
    open_preview(run)
    return true
  end},
  {name = 'negative preview up', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1.5 then return false end
    local card = find_preview_card(G.OVERLAY_MENU, 'j_joker')
    ctx.assert(card and card.edition and card.edition.negative, 'preview j_joker lost its negative edition')
    ctx.assert(card.ability.queue_negative_removal == nil, 'preview j_joker kept queue_negative_removal')
    local tarot = find_preview_card(G.OVERLAY_MENU, 'c_fool')
    ctx.assert(tarot and tarot.edition and tarot.edition.negative, 'preview c_fool lost its negative edition')
    ctx.assert(tarot.ability.queue_negative_removal == nil, 'preview c_fool kept queue_negative_removal')
    ctx.shot('preview_negative')
    return true
  end},
  {name = 'close negative preview', run = function(ctx)
    ctx.assert(ctx.click('exit_overlay_menu'), 'Back button not found')
    return true
  end},
  {name = 'live slot limits', run = function(ctx)
    if G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    -- and once more without an overlay: build, lay out, remove
    local run = STR_UNPACK(STR_PACK(saved_run))
    run.cardAreas.jokers.cards[1].ability.queue_negative_removal = true
    run.cardAreas.jokers.cards[1].edition = {negative = true}
    panel_size(run)
    local j, c = slot_limits()
    ctx.log(('live slot limits after: jokers %d, consumables %d'):format(j, c))
    ctx.assert(j == limits_before[1], ('removing the preview changed the live joker limit: %d -> %d'):format(limits_before[1], j))
    ctx.assert(c == limits_before[2], ('removing the preview changed the live consumable limit: %d -> %d'):format(limits_before[2], c))
    ctx.assert(#G.jokers.cards == 3 and #G.consumeables.cards == 1, 'the preview touched the live run')
    ctx.log('check: live slot limits unchanged')
    return true
  end},
  {name = 'fixed panel size', run = function(ctx)
    -- full, bogus and empty runs all lay out to the same outer size
    local bogus = STR_UNPACK(STR_PACK(saved_run))
    bogus.cardAreas.jokers.cards[1].save_fields.center = 'j_does_not_exist'
    bogus.BACK = {name = 'No Such Deck'}
    local empty = STR_UNPACK(STR_PACK(saved_run))
    empty.cardAreas.jokers.cards, empty.cardAreas.consumeables.cards = {}, {}
    empty.GAME.used_vouchers = {}
    local sizes = {}
    for _, case in ipairs{{'full', saved_run}, {'bogus', bogus}, {'empty', empty}, {'nothing', {}}} do
      local w, h = panel_size(case[2])
      sizes[#sizes+1] = ('%s %.2fx%.2f'):format(case[1], w, h)
      ctx.assert(math.abs(w - 8) < 0.01 and math.abs(h - 7.3) < 0.01,
        ('%s run: panel is %.2fx%.2f, expected 8x7.3 (ui.lua DETAIL_W x DETAIL_H)'):format(case[1], w, h))
    end
    ctx.log('panel size: '..table.concat(sizes, ', '))
    open_preview(empty)
    return true
  end},
  {name = 'empty preview shot', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    ctx.shot('preview_empty')
    return true
  end},
  {name = 'close empty preview', run = function(ctx)
    ctx.assert(ctx.click('exit_overlay_menu'), 'Back button not found')
    return true
  end},
  {name = 'closed', run = function(ctx)
    return G.OVERLAY_MENU == nil
  end},
}
