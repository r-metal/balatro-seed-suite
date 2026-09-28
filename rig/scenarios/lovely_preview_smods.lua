-- lovely_preview_smods: for the real-lovely rig next to Steamodded
-- (rig/lovely-rig.sh lovely_preview_smods --smods). Save Slots previews a save made
-- before Steamodded was installed: its cards' `ability` has no card_limit or
-- extra_slots_used, which Steamodded's set_ability adds and its set_edition does
-- arithmetic on. Such a save is made here by saving a run with a foil joker and a holo
-- tarot, then dropping those two fields. The preview must build, keep the editions and
-- leave the live slot limits alone; the unstripped save must preview too.
-- Screenshot: preview_smods.png.
local preview = require('saveslots.preview')
local store = require('saveslots.store')

local SMODS_ONLY = {'card_limit', 'extra_slots_used'}

local saved_run

local function strip(run)
  local out = STR_UNPACK(STR_PACK(run))
  for _, area in pairs(out.cardAreas) do
    for _, c in ipairs(area.cards or {}) do
      for _, f in ipairs(SMODS_ONLY) do c.ability[f] = nil end
    end
  end
  return out
end

local function preview_cards(box)
  local out = {}
  local function walk(node)
    if type(node) ~= 'table' then return end
    local obj = node.config and node.config.object
    if type(obj) == 'table' and obj.is then
      if obj:is(CardArea) then
        for _, c in ipairs(obj.cards or {}) do out[c.config.center_key] = c end
      elseif obj:is(UIBox) then
        walk(obj.UIRoot)
      end
    end
    for _, child in ipairs(node.children or {}) do walk(child) end
  end
  walk(box.UIRoot)
  return out
end

local function add(set, area, key, edition)
  local card = create_card(set, area, nil, nil, nil, nil, key)
  card:set_edition(edition, true, true)
  card:add_to_deck()
  area:emplace(card)
end

return {
  {name = 'steamodded present', run = function(ctx)
    BHCore._env = nil
    ctx.assert(BHCore.env().smods, 'Steamodded not detected (run with --smods)')
    return true
  end},
  {name = 'start run', run = function(ctx) ctx.start_run{}; return true end},
  {name = 'blind select', timeout = 30, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
  end},
  {name = 'give cards', run = function(ctx)
    add('Joker', G.jokers, 'j_joker', {foil = true})
    add('Tarot', G.consumeables, 'c_fool', {holo = true})
    return true
  end},
  {name = 'settle and save', timeout = 10, run = function(ctx)
    if ctx.step_time() < 1.5 or not G.STATE_COMPLETE then return false end
    save_run()
    saved_run = G.culled_table
    ctx.assert(type(saved_run) == 'table', 'save_run produced no G.culled_table')
    local j = saved_run.cardAreas.jokers.cards[1]
    ctx.assert(j and j.ability.card_limit ~= nil, 'Steamodded saved no ability.card_limit: the case is not exercised')
    return true
  end},
  {name = 'preview both saves', run = function(ctx)
    local limits = {G.jokers.config.card_limit, G.consumeables.config.card_limit}
    for label, run in pairs{current = saved_run, ['pre-Steamodded'] = strip(saved_run)} do
      local ok, def = pcall(preview.build, run, store.summarize(run))
      ctx.assert(ok, label..' save: '..tostring(def))
      local box = UIBox{definition = def, config = {offset = {x = 0, y = 0}, align = 'cm'}}
      local cards = preview_cards(box)
      ctx.assert(cards.j_joker and cards.j_joker.edition and cards.j_joker.edition.foil, label..': the joker lost its foil')
      ctx.assert(cards.c_fool and cards.c_fool.edition and cards.c_fool.edition.holo, label..': the tarot lost its holo')
      box:remove()
    end
    ctx.assert(G.jokers.config.card_limit == limits[1] and G.consumeables.config.card_limit == limits[2],
      'the live slot limits changed')
    return true
  end},
  {name = 'preview up', run = function(ctx)
    if not G.OVERLAY_MENU then
      local run = strip(saved_run)
      local def = preview.build(run, store.summarize(run))
      def.n = G.UIT.R
      G.FUNCS.overlay_menu{definition = create_UIBox_generic_options{contents = {def}}}
      return false
    end
    if ctx.step_time() < 1.5 then return false end
    ctx.shot('preview_smods')
    return true
  end},
}
