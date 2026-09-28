-- bh-core: shared library for the suite. Contracts: docs/bh-core.md.
if BHCore then return BHCore end

BHCore = {VERSION = '0.3.4'}

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

-- Digits in text inputs. Vanilla's text_input_key types 'o' for '0' in every input
-- (button_callbacks.lua:970: seeds have no zero). An input made with
-- create_text_input{bh_digits = true, ...} keeps a typed '0': the wrap lets vanilla
-- type its 'o', puts '0' in that letter, and lets vanilla's own cursor pass
-- (TRANSPOSE_TEXT_INPUT(0)) rebuild the text from the letters. Other inputs, and a
-- '0' typed with caps (vanilla's 'O'), are left to vanilla. Idempotent; each mod UI
-- that needs it calls it from its install.
function BHCore.install_digits()
  if BHCore._digits or not (G and G.FUNCS and G.FUNCS.text_input_key) then return end
  local orig = G.FUNCS.text_input_key
  BHCore._digits = true
  G.FUNCS.text_input_key = function(args)
    local hook = G.CONTROLLER and G.CONTROLLER.text_input_hook
    local cfg = hook and hook.config and hook.config.ref_table
    local text = type(cfg) == 'table' and cfg.bh_digits and cfg.text
    if not (text and type(args) == 'table' and args.key == '0') then return orig(args) end
    -- The letter goes in at the cursor, which vanilla's TRANSPOSE_TEXT_INPUT(0) places
    -- after min(the 'position' child's index - 1, the text's length) letters. Not
    -- text.current_position: vanilla computes it from the text before the rebuild.
    -- Steamodded (and HandyBalatro, which copies the patch) prefix the child ids with
    -- the input's id ('text_input_position'), so match the suffix too.
    local at
    for i, c in ipairs(hook.children or {}) do
      local id = c.config and c.config.id
      if type(id) == 'string' and (id == 'position' or id:sub(-9) == '_position') then
        at = math.min(i - 1, #(text.ref_table[text.ref_value] or '')) + 1
        break
      end
    end
    local len = #(text.ref_table[text.ref_value] or '')
    local ret = orig(args)
    -- (a full input types nothing, and the 'o' at the cursor is an old one)
    if at and text.letters[at] == 'o' and #(text.ref_table[text.ref_value] or '') == len + 1 then
      text.letters[at] = '0'
      TRANSPOSE_TEXT_INPUT(0)
    end
    return ret
  end
end

BHCore.events = require('bhcore.events')
BHCore.events.install()

return BHCore
