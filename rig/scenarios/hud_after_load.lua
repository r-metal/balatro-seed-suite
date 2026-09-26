-- Blind HUD after a mid-blind load. Vanilla's Blind:load brings the blind panel
-- on screen only when the blind pays dollars, so resuming a $0 blind (Small Blind
-- at Red stake and up) left it at start_run's offset.y = -10. SaveSlots'
-- checkpoint hook puts it back.
--   1. Seeded run HUDLOAD1 at stake 2, select the Small Blind ($0 reward), wait for
--      the hand: the panel is on screen (offset.y 0).
--   2. Load that run's own mid-blind snapshot with checkpoint.load_run: the panel is
--      on screen again. -> "check: HUD after load"
local checkpoint = require('saveslots.checkpoint')
local SEED = 'HUDLOAD1'
local snap

local function select_btn()
  local opt = G.blind_select_opts and G.blind_select_opts[string.lower(G.GAME.blind_on_deck or '')]
  local b = opt and opt:get_UIE_by_ID('select_blind_button')
  if b and b.config.button == 'select_blind' then return b end
end

local function dealt(ctx)
  return G.STATE == G.STATES.SELECTING_HAND and #G.hand.cards > 0 and G.GAME.pseudorandom.seed == SEED
    and ctx.step_time() > 2
end

return {
  {name = 'start', run = function(ctx)
    SaveSlots.settings.auto_checkpoints = false
    ctx.start_run{seed = SEED, stake = 2}
    return true
  end},
  {name = 'blind select', timeout = 20, run = function(ctx)
    return G.STATE == G.STATES.BLIND_SELECT and select_btn() and ctx.step_time() > 1
  end},
  {name = 'select small', run = function(ctx) G.FUNCS.select_blind(select_btn()); return true end},
  {name = 'dealt', timeout = 15, run = function(ctx)
    if not dealt(ctx) then return false end
    ctx.assert(G.GAME.blind.dollars == 0, 'Small Blind pays $'..tostring(G.GAME.blind.dollars)..' at stake 2')
    ctx.assert(G.HUD_blind.alignment.offset.y == 0, 'blind HUD off screen before the load')
    snap = checkpoint.get()
    ctx.assert(snap and snap.STATE == G.STATES.SELECTING_HAND, 'no mid-blind snapshot')
    return true
  end},
  {name = 'load', run = function(ctx) return checkpoint.load_run(snap) end},
  {name = 'check: HUD after load', timeout = 20, run = function(ctx)
    if not dealt(ctx) then return false end
    ctx.assert(G.HUD_blind.alignment.offset.y == 0,
      'blind HUD off screen after the load (offset.y '..tostring(G.HUD_blind.alignment.offset.y)..')')
    ctx.shot('after_load')
    return true
  end},
}
