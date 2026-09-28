-- text_digits: BHCore.install_digits. An input made with bh_digits = true keeps a typed
-- '0' (at the end and with the cursor moved left); the same input without the flag,
-- and a '0' typed with caps, still get vanilla's 'o' / 'O'. Keys go through the real
-- G.FUNCS.text_input_key path.
local S = {text = ''}

local function input_args()
  local hook = G.CONTROLLER.text_input_hook
  return hook and hook.config.ref_table
end

local function type_keys(text)
  for i = 1, #text do G.FUNCS.text_input_key({key = text:sub(i, i)}) end
end

return {
  {name = 'open', run = function(ctx)
    BHCore.install_digits()
    BHCore.install_digits()   -- idempotent: one wrap, not two
    G.FUNCS.overlay_menu{definition = create_UIBox_generic_options{contents = {
      {n=G.UIT.R, config={align = 'cm', padding = 0.1}, nodes={
        create_text_input{w = 4, max_length = 12, extended_corpus = true, bh_digits = true,
          ref_table = S, ref_value = 'text', prompt_text = 'Digits'},
      }},
    }}}
    return true
  end},
  {name = 'type digits', run = function(ctx)
    local input = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID('text_input')
    if not input then return false end
    G.FUNCS.select_text_input(input)
    ctx.assert(input_args() and input_args().bh_digits, 'the flagged input is not hooked')
    type_keys('a0b20')
    ctx.assert(S.text == 'a0b20', 'typed a0b20, got '..S.text)
    -- in the middle: cursor two left, then 0
    G.FUNCS.text_input_key({key = 'left'})
    G.FUNCS.text_input_key({key = 'left'})
    G.FUNCS.text_input_key({key = '0'})
    ctx.assert(S.text == 'a0b020', 'mid-text 0: got '..S.text)
    G.FUNCS.text_input_key({key = '0', caps = true})
    ctx.assert(S.text == 'a0b0O20', 'caps 0 is vanilla O: got '..S.text)
    -- in front of an 'o': the typed letter, not the next 'o', becomes the 0
    for _ = 1, 20 do G.FUNCS.text_input_key({key = 'right'}) end
    type_keys('oo')
    G.FUNCS.text_input_key({key = 'left'})
    G.FUNCS.text_input_key({key = 'left'})
    G.FUNCS.text_input_key({key = '0'})
    ctx.assert(S.text == 'a0b0O200oo', '0 before oo: got '..S.text)
    -- full (max_length 12): nothing is typed and the old 'o' at the cursor stays
    for _ = 1, 20 do G.FUNCS.text_input_key({key = 'right'}) end
    type_keys('xo')
    G.FUNCS.text_input_key({key = 'left'})
    G.FUNCS.text_input_key({key = '0'})
    ctx.assert(S.text == 'a0b0O200ooxo', 'full input: got '..S.text)
    ctx.log('check: digits kept ('..S.text..')')
    return true
  end},
  {name = 'unflagged is vanilla', run = function(ctx)
    input_args().bh_digits = nil
    for _ = 1, 20 do G.FUNCS.text_input_key({key = 'backspace'}) end
    for _ = 1, 20 do G.FUNCS.text_input_key({key = 'delete'}) end
    type_keys('x0')
    ctx.assert(S.text == 'xo', 'unflagged input typed x0, got '..S.text..' (vanilla gives xo)')
    G.FUNCS.text_input_key({key = 'return'})
    ctx.shot('text_digits')
    ctx.log('check: unflagged input unchanged')
    return true
  end},
}
