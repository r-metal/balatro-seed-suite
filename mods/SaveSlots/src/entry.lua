-- Entry points: Options/pause button and the Play-screen "Saves" tab. Contract: docs/SPEC.md.
--
-- Decision D2. Both hooks wrap the vanilla builder, call the original and
-- mutate what comes back; no vanilla body is copied here (invariant 2).
--
--   create_UIBox_options   one vanilla function builds both the main-menu
--                          Options overlay and the in-run pause menu. The
--                          "Save Slots" button goes right after Settings in a
--                          run and at the end on the main menu. The button
--                          list is found by walking the definition for the
--                          node holding the Settings button, never by index.
--   G.UIDEF.run_setup      on the main menu only, a "Saves" tab after
--                          Continue. The tab list is a literal passed straight
--                          into create_tabs, whose buttons are built from it
--                          at call time, so create_tabs is wrapped for the
--                          duration of run_setup and the tab is added to its
--                          args before the original runs. New Run, Continue
--                          and Challenges are left exactly as vanilla built them.
--
-- API
--   entry.install()                  wraps both builders. Runs once.
--   G.FUNCS.saveslots_quickload(e)   e.config.ref_table.id is a slot id. Reads
--                                    it and hands it to checkpoint.load_run,
--                                    which closes the overlay before starting
--                                    the run. A slot that can't be read or
--                                    written to save.jkr leaves the overlay up
--                                    and re-renders the tab with the reason.
local store = require('saveslots.store')
local checkpoint = require('saveslots.checkpoint')

local entry = {}

local RECENT = 3                 -- quick-load buttons on the Saves tab
local TAB_LABEL = 'Saves'
local TAB_W, TAB_H = 6.4, 5.2    -- keeps the tab close to the Continue panel's size
local BUTTON_W = 5.6

local installed = false
local tab_error = nil            -- shown once on the next Saves tab render

-- The contents list of the Options definition: the node with a child whose
-- own child is the Settings button (UIBox_button wraps its button in a row).
local function find_button_list(node)
  if type(node) ~= 'table' or type(node.nodes) ~= 'table' then return nil end
  for _, child in pairs(node.nodes) do
    if type(child) == 'table' and type(child.nodes) == 'table' then
      for _, inner in pairs(child.nodes) do
        if type(inner) == 'table' and inner.config and inner.config.button == 'settings' then
          return node, child
        end
      end
    end
  end
  for _, child in pairs(node.nodes) do
    local list, settings = find_button_list(child)
    if list then return list, settings end
  end
end

local function holds_button(child, button)
  if type(child) ~= 'table' or type(child.nodes) ~= 'table' then return false end
  for _, inner in pairs(child.nodes) do
    if type(inner) == 'table' and inner.config and inner.config.button == button then return true end
  end
  return false
end

-- Vanilla builds the contents with nil holes (options that don't apply to the
-- current stage), which UIBox walks with pairs in index order. Rebuild it as
-- a dense list with the new button in place.
local function add_options_button(t)
  local list, settings = find_button_list(t)
  if not list then return t end
  local old = list.nodes
  for _, child in pairs(old) do
    if holds_button(child, 'saveslots_open') then return t end
  end
  local button = UIBox_button{label = {'Save Slots'}, button = 'saveslots_open', minw = 5}
  local after_settings = G.STAGE == G.STAGES.RUN
  local nodes = {}
  for i = 1, table.maxn(old) do
    local child = old[i]
    if child ~= nil then
      nodes[#nodes + 1] = child
      if after_settings and child == settings then nodes[#nodes + 1] = button; button = nil end
    end
  end
  if button then nodes[#nodes + 1] = button end
  list.nodes = nodes
  return t
end

local function saves_row(slot)
  local sm = slot.summary or {}
  local meta = 'A'..tostring(sm.ante or '?')..' $'..tostring(sm.dollars or '?')
  return {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
    {n=G.UIT.C, config={align = 'cm', minw = BUTTON_W, minh = 0.95, padding = 0.08, r = 0.1,
        hover = true, shadow = true, colour = G.C.BLUE, button = 'saveslots_quickload',
        ref_table = {id = slot.id}, focus_args = {nav = 'wide'}}, nodes={
      {n=G.UIT.R, config={align = 'cm', maxw = BUTTON_W - 0.3}, nodes={
        {n=G.UIT.T, config={text = tostring(slot.name or '?'), scale = 0.45, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
      }},
      {n=G.UIT.R, config={align = 'cm', maxw = BUTTON_W - 0.3}, nodes={
        {n=G.UIT.T, config={text = meta, scale = 0.32, colour = G.C.UI.TEXT_LIGHT}},
      }},
    }},
  }}
end

-- The Saves tab: the RECENT newest slots as quick-load buttons and an
-- "Open Save Slots" button, or "No saves yet".
local function saves_tab_def()
  -- Recent saves are the player's own: auto-checkpoints would crowd them out.
  local slots = {}
  for _, e in ipairs(store.list() or {}) do
    if not (e.meta and e.meta.kind == 'checkpoint') then slots[#slots + 1] = e end
  end
  local body = {}
  if #slots == 0 then
    body[#body + 1] = {n=G.UIT.R, config={align = 'cm', minw = BUTTON_W, minh = 2.2, r = 0.1, colour = G.C.BLACK}, nodes={
      {n=G.UIT.T, config={text = 'No saves yet', scale = 0.5, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
    }}
  else
    body[#body + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.05}, nodes={
      {n=G.UIT.T, config={text = 'Recent saves', scale = 0.4, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
    }}
    for i = 1, math.min(RECENT, #slots) do body[#body + 1] = saves_row(slots[i]) end
  end
  if tab_error then
    body[#body + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.05, maxw = BUTTON_W}, nodes={
      {n=G.UIT.T, config={text = tab_error, scale = 0.32, colour = G.C.RED, shadow = true}},
    }}
    tab_error = nil
  end
  body[#body + 1] = {n=G.UIT.R, config={align = 'cm', padding = 0.2}, nodes={
    UIBox_button{label = {'Open Save Slots'}, button = 'saveslots_open', colour = G.C.RED, minw = BUTTON_W - 1, minh = 0.8},
  }}
  return {n=G.UIT.ROOT, config={align = 'cm', colour = G.C.CLEAR, minw = TAB_W, minh = TAB_H}, nodes={
    {n=G.UIT.C, config={align = 'cm', padding = 0.1}, nodes = body},
  }}
end

local function is_saves_tab(tab) return type(tab) == 'table' and tab.saveslots == true end

local function add_saves_tab(tabs)
  local continue_at = nil
  for i, tab in ipairs(tabs) do
    if is_saves_tab(tab) then return end
    if type(tab) == 'table' and tab.tab_definition_function_args == 'Continue' then continue_at = i end
  end
  if not continue_at then return end
  table.insert(tabs, continue_at + 1, {
    label = TAB_LABEL,
    tab_definition_function = saves_tab_def,
    tab_definition_function_args = nil,
    saveslots = true,
  })
end

-- Re-renders the Saves tab in place (after a failed quick load).
local function refresh_saves_tab()
  local but = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('tab_but_'..TAB_LABEL)
  if but then G.FUNCS.change_tab(but) end
end

function entry.install()
  if installed then return end
  installed = true

  local orig_options = create_UIBox_options
  create_UIBox_options = function(...)
    return add_options_button(orig_options(...))
  end

  local orig_run_setup = G.UIDEF.run_setup
  G.UIDEF.run_setup = function(...)
    if G.STAGE ~= G.STAGES.MAIN_MENU then return orig_run_setup(...) end
    local orig_tabs = create_tabs
    local first = true
    -- Only the outermost call is run_setup's own; tab builders that run inside
    -- it (the chosen tab's content) may call create_tabs again.
    create_tabs = function(args)
      if first then
        first = false
        if type(args) == 'table' and type(args.tabs) == 'table' then add_saves_tab(args.tabs) end
      end
      return orig_tabs(args)
    end
    local ok, t = pcall(orig_run_setup, ...)
    create_tabs = orig_tabs
    if not ok then error(t, 0) end
    return t
  end

  G.FUNCS.saveslots_quickload = function(e)
    local id = e and e.config and e.config.ref_table and e.config.ref_table.id
    if not id then return end
    local run, err = store.read(id)
    if run then
      local ok
      ok, err = checkpoint.load_run(run)
      if ok then return end
      tab_error = 'Load failed: '..tostring(err)
    else
      tab_error = 'This save could not be read'
    end
    refresh_saves_tab()
  end
end

return entry
