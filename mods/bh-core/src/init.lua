-- bh-core: shared library for the suite. Contracts: docs/bh-core.md.
if BHCore then return BHCore end

BHCore = {VERSION = '0.3.3'}

-- True when this bh-core serves a mod built for major.minor `want` ('0.3'). Before 1.0
-- a minor release may change the contracts, so both parts must match.
function BHCore.compat(want)
  return BHCore.VERSION:match('^%d+%.%d+') == want
end
-- The round's voucher: vanilla keeps its key; Steamodded keeps a list
-- ({'v_x', spawn = {v_x = true}}) and its shop reads .spawn. Read and roll it either way.
function BHCore.round_voucher()
  local v = G.GAME.current_round and G.GAME.current_round.voucher
  if type(v) == 'table' then return v[1] end
  return v
end

function BHCore.roll_round_voucher()
  G.GAME.current_round.voucher = SMODS and SMODS.get_next_vouchers and SMODS.get_next_vouchers()
    or get_next_voucher_key()
end

-- What else changes the game. Predictions are proven against the unmodded game only:
--   smods    Steamodded is loaded. It picks bosses with its own weighted pools
--            (lovely/weights.toml bypasses get_new_boss, SMODS.reset_blind_choices
--            re-picks at run start) and rolls editions its own way; which card
--            appears matches vanilla (golden suites under rig/lovely-rig.sh --smods).
--   content  names of mods that add or take over cards, tags, blinds or seals
--            (Steamodded marks them with original_mod / mod). They change the pools,
--            so predictions don't apply.
-- Computed once the prototypes exist (the first call after the game has loaded).
function BHCore.env()
  if BHCore._env then return BHCore._env end
  local e, seen = {smods = SMODS ~= nil, content = {}}, {}
  for _, protos in ipairs{G.P_CENTERS, G.P_TAGS, G.P_BLINDS, G.P_SEALS} do
    for _, p in pairs(protos or {}) do
      local m = type(p) == 'table' and (p.original_mod or p.mod)
      local name = type(m) == 'table' and (m.name or m.id)
      if name and not seen[name] then seen[name] = true; e.content[#e.content + 1] = tostring(name) end
    end
  end
  table.sort(e.content)
  if G.P_CENTERS and next(G.P_CENTERS) then BHCore._env = e end
  return e
end

-- One line for the Oracle and the Finder, or nil in an unmodded game.
function BHCore.env_notice()
  local e = BHCore.env()
  if #e.content > 0 then
    local who = #e.content > 1 and e.content[1]..' and '..(#e.content - 1)..' more change'
      or e.content[1]..' changes'
    return who..' the card pools: predictions don\'t apply'
  elseif e.smods then
    return 'Steamodded: editions and bosses are unverified'
  end
  return nil
end

BHCore.events = require('bhcore.events')
BHCore.events.install()

return BHCore
