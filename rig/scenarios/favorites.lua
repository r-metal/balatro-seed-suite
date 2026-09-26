-- Favorites (SaveSlots): pin a slot through the meta column's toggle, in a real run.
--   1. Start a run, wait for its autosave, save "One", "Two", "Three" (newest first:
--      Three, Two, One).
--   2. Select One, press Favorite: it moves to the top of the list with a gold dot,
--      the index on disk has meta.favorite, and the button reads Unfavorite.
--   3. Step the kind filter to Favorites: only One is shown; select it again.
--   4. Unfavorite it there: the list is empty, and meta.favorite is gone from disk.
-- Screenshots: favorite_all, favorite_filter.
local store = require('saveslots.store')
local checkpoint = require('saveslots.checkpoint')

local S = {}

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function sub_uie(box_id, id)
  local node = uie(box_id)
  local box = node and node.config.object
  return box and box.get_UIE_by_ID and box:get_UIE_by_ID(id)
end

local function type_name(ctx, text)
  ctx.assert(ctx.click('select_text_input'), 'name input not found')
  for _ = 1, 30 do G.FUNCS.text_input_key({key = 'backspace'}) end
  for i = 1, #text do G.FUNCS.text_input_key({key = text:sub(i, i)}) end
  G.FUNCS.text_input_key({key = 'return'})
end

local function kind_next(ctx)
  local found
  local function walk(n)
    if found or type(n) ~= 'table' then return end
    if n.config and n.config.button == 'saveslots_kind_cycle' and n.config.ref_value == 'r' then found = n; return end
    for _, c in ipairs(n.children or {}) do walk(c) end
  end
  walk(G.OVERLAY_MENU and G.OVERLAY_MENU.UIRoot)
  ctx.assert(found, 'kind filter arrow not found')
  G.FUNCS[found.config.button](found)
end

local function row_y(name) local r = uie('saveslots_row_'..S[name]); return r and r.T.y end

local function button_label(ctx)
  local b = sub_uie('saveslots_meta', 'saveslots_favorite')
  ctx.assert(b, 'favorite button not found')
  local t
  local function walk(n)
    if t or type(n) ~= 'table' then return end
    if n.config and n.config.text then t = n.config.text; return end
    for _, c in ipairs(n.children or {}) do walk(c) end
  end
  walk(b)
  return t
end

local function disk_fav(id)
  local idx = STR_UNPACK(get_compressed(G.SETTINGS.profile..'/saveslots/index.jkr'))
  local e = idx.slots[id]
  return e and e.meta and e.meta.favorite
end

return {
  {name = 'no auto-checkpoints', run = function(ctx) SaveSlots.settings.auto_checkpoints = false; return true end},
  {name = 'start run', run = function(ctx) ctx.start_run{}; return true end},
  {name = 'autosave', timeout = 20, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and checkpoint.get() ~= nil
  end},
  {name = 'save three', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    G.FUNCS.saveslots_open()
    for _, n in ipairs({'One', 'Two', 'Three'}) do
      type_name(ctx, n)
      ctx.assert(ctx.click('saveslots_save_new'), 'Save current run not found')
    end
    for _, e in ipairs(store.list()) do S[e.name:lower()] = e.id end
    ctx.assert(S.one and S.two and S.three, 'slots not listed by name')
    return true
  end},
  {name = 'favorite One', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.assert(row_y('three') < row_y('one'), 'newest-first order expected before favoriting')
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.one), 'One row not found')
    ctx.assert(button_label(ctx) == 'Favorite', 'button reads '..tostring(button_label(ctx)))
    ctx.assert(not uie('saveslots_fav_'..S.one), 'dot shown before favoriting')
    ctx.assert(ctx.click('saveslots_favorite'), 'favorite button not clickable')
    return true
  end},
  {name = 'One pinned', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.assert(disk_fav(S.one) == true, 'meta.favorite not on disk')
    ctx.assert(row_y('one') < row_y('three') and row_y('three') < row_y('two'), 'One is not pinned first')
    ctx.assert(uie('saveslots_fav_'..S.one), 'gold dot missing on One')
    ctx.assert(not uie('saveslots_fav_'..S.two), 'gold dot on Two')
    ctx.assert(button_label(ctx) == 'Unfavorite', 'button reads '..tostring(button_label(ctx)))
    local meta, back = uie('saveslots_meta'), uie('overlay_menu_back_button')
    ctx.assert(meta.T.x + meta.T.w <= G.ROOM.T.w and back.T.y + back.T.h <= G.ROOM.T.h, 'overlay does not fit the room')
    ctx.shot('favorite_all')
    return true
  end},
  {name = 'to Favorites', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    for _ = 1, 5 do kind_next(ctx) end
    return true
  end},
  {name = 'favorites filter', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.assert(uie('saveslots_row_'..S.one), 'One missing under Favorites')
    ctx.assert(not uie('saveslots_row_'..S.two) and not uie('saveslots_row_'..S.three), 'non-favorites shown')
    -- The Checkpoints filter on the way here dropped the selection.
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.one), 'One row not clickable')
    return true
  end},
  {name = 'favorites shot', run = function(ctx)
    if ctx.step_time() < 0.5 then return false end
    ctx.shot('favorite_filter')
    return true
  end},
  {name = 'unfavorite', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    ctx.assert(ctx.click('saveslots_favorite'), 'unfavorite button not found')
    return true
  end},
  {name = 'unfavorited', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.5 then return false end
    ctx.assert(disk_fav(S.one) == nil, 'meta.favorite still on disk')
    ctx.assert(not uie('saveslots_row_'..S.one), 'One still under Favorites')
    local msg = sub_uie('saveslots_detail', 'saveslots_detail_msg')
    ctx.assert(msg and msg.config.text == 'No favorites yet', 'empty text: '..tostring(msg and msg.config.text))
    return true
  end},
}
