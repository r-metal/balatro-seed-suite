-- Share codes in the Save Slots overlay (0.3, D3), in a real run.
--   1. With G.F_LOCAL_CLIPBOARD on (vanilla's own switch for copy_seed/paste_seed),
--      start run A on a pinned seed, wait for its autosave, save "Shared" through
--      the overlay and give it notes (store.set_meta).
--   2. Select it and press Share: G.CLIPBOARD decodes (sharecode.decode) to the
--      slot's seed, deck, stake and notes, and the meta column shows the code,
--      truncated with '...'.
--   3. Start a different run B. Put the code back with one character changed and
--      press Import code: the panel shows the decode error, no Play, and the
--      cancel sound plays.
--   4. Restore the code, Import again: seed / deck / stake / notes shown with Play.
--      Play starts run A's seed on its deck and stake, unseeded (run A itself was
--      seeded: vanilla marks every run started with a seed).
-- Screenshots: share, import_error, import.
local store = require('saveslots.store')
local checkpoint = require('saveslots.checkpoint')
local sharecode = require('saveslots.sharecode')

local SEED = 'SHARE7Q'
-- No '0' anywhere: vanilla's text_input_key turns it into 'o'.
local NOTES = 'Skip the first Small Blind, buy the Charm pack'

local S = {sounds = {}}

local function uie(id) return G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID(id) end

local function sub_uie(box_id, id)
  local node = uie(box_id)
  local box = node and node.config.object
  return box and box.get_UIE_by_ID and box:get_UIE_by_ID(id)
end

local function text_of(box_id, id)
  local n = sub_uie(box_id, id)
  return n and n.config.text
end

local function type_name(ctx, text)
  ctx.assert(ctx.click('select_text_input'), 'name input not found')
  for _ = 1, 30 do G.FUNCS.text_input_key({key = 'backspace'}) end
  for i = 1, #text do G.FUNCS.text_input_key({key = text:sub(i, i)}) end
  G.FUNCS.text_input_key({key = 'return'})
end

-- The code with one base64 character (past the 'BHS1:' prefix) changed.
local function corrupt(code)
  local i = #sharecode.PREFIX + 3
  local c = code:sub(i, i)
  return code:sub(1, i - 1)..(c == 'A' and 'B' or 'A')..code:sub(i + 1)
end

return {
  -- Player-slot scenario: no 'Auto A<n>' slots in the list.
  {name = 'setup', run = function(ctx)
    SaveSlots.settings.auto_checkpoints = false
    G.F_LOCAL_CLIPBOARD = true
    G.CLIPBOARD = nil
    -- Records sounds so the decode error's cancel can be checked.
    local orig = play_sound
    play_sound = function(name, ...)
      S.sounds[#S.sounds+1] = name
      return orig(name, ...)
    end
    return true
  end},

  -- 1. Run A and its slot
  {name = 'start run A', run = function(ctx)
    -- Not the defaults (Red Deck, stake 1): run B is, so Play can only land on
    -- Blue Deck / stake 2 by carrying them over from the code.
    G.GAME.viewed_back = Back(G.P_CENTERS.b_blue)
    ctx.start_run{seed = SEED, stake = 2}
    return true
  end},
  {name = 'run A autosave', timeout = 20, run = function(ctx)
    if not (G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT) then return false end
    local run = checkpoint.get()
    return run and run.GAME and run.GAME.pseudorandom.seed == SEED
  end},
  {name = 'save Shared with notes', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    ctx.assert(G.GAME.seeded, 'run A is not seeded; the unseeded check would be vacuous')
    S.a_deck = G.GAME.selected_back.effect.center.key
    S.a_stake = G.GAME.stake
    G.FUNCS.saveslots_open()
    type_name(ctx, 'Shared')
    ctx.assert(ctx.click('saveslots_save_new'), 'Save current run not found')
    local list = store.list()
    ctx.assert(#list == 1 and list[1].name == 'Shared', 'expected one slot "Shared"')
    S.id = list[1].id
    ctx.assert(store.set_meta(S.id, {notes = NOTES}), 'set_meta notes failed')
    G.FUNCS.exit_overlay_menu()
    return true
  end},
  {name = 'reopen', run = function(ctx)
    if G.OVERLAY_MENU or ctx.step_time() < 0.3 then return false end
    G.FUNCS.saveslots_open()
    return true
  end},

  -- 2. Share
  {name = 'share', run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 0.8 then return false end
    ctx.assert(ctx.click('saveslots_select', 'saveslots_row_'..S.id), 'Shared row not found')
    ctx.assert(text_of('saveslots_meta', 'saveslots_meta_code') == nil, 'a code shown before Share')
    ctx.assert(ctx.click('saveslots_share'), 'Share button not found')
    local code = G.CLIPBOARD
    ctx.assert(type(code) == 'string' and code:sub(1, #sharecode.PREFIX) == sharecode.PREFIX,
      'clipboard holds '..tostring(code))
    local t, err = sharecode.decode(code)
    ctx.assert(t, 'clipboard code does not decode: '..tostring(err))
    ctx.assert(t.seed == SEED, 'code seed '..tostring(t.seed))
    ctx.assert(t.deck == S.a_deck, 'code deck '..tostring(t.deck)..', run A had '..tostring(S.a_deck))
    ctx.assert(t.stake == S.a_stake, 'code stake '..tostring(t.stake))
    ctx.assert(t.notes == NOTES, 'code notes '..tostring(t.notes))
    S.code = code
    ctx.log('share code ('..#code..' bytes): '..code)
    return true
  end},
  {name = 'share shot', run = function(ctx)
    if ctx.step_time() < 0.8 then return false end
    local shown = text_of('saveslots_meta', 'saveslots_meta_code')
    ctx.assert(shown and shown:sub(-3) == '...' and S.code:sub(1, #shown - 3) == shown:sub(1, -4),
      'code line shows '..tostring(shown))
    ctx.shot('share')
    return true
  end},
  {name = 'close', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    G.FUNCS.exit_overlay_menu()
    return true
  end},

  -- 3. Run B, a corrupted code
  {name = 'start run B', run = function(ctx)
    if G.OVERLAY_MENU or ctx.step_time() < 0.3 then return false end
    S.prev = G.GAME
    G.GAME.viewed_back = Back(G.P_CENTERS.b_red); ctx.start_run{}
    return true
  end},
  {name = 'run B autosave', timeout = 20, run = function(ctx)
    if not (G.GAME ~= S.prev and G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT
      and checkpoint.get() ~= nil) then return false end
    ctx.assert(G.GAME.pseudorandom.seed ~= SEED, 'run B got run A\'s seed; the Play check would be vacuous')
    return true
  end},
  {name = 'import a corrupted code', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    G.FUNCS.saveslots_open()
    G.CLIPBOARD = corrupt(S.code)
    ctx.assert(G.CLIPBOARD ~= S.code and #G.CLIPBOARD == #S.code, 'corrupt() changed nothing')
    S.sounds = {}
    ctx.assert(ctx.click('saveslots_import'), 'Import code button not found')
    local cancel = false
    for _, s in ipairs(S.sounds) do if s == 'cancel' then cancel = true end end
    ctx.assert(cancel, 'no cancel sound on a bad code')
    return true
  end},
  {name = 'import error shot', run = function(ctx)
    if ctx.step_time() < 0.8 then return false end
    local err = text_of('saveslots_detail', 'saveslots_import_error')
    ctx.assert(err and err:find('checksum'), 'import error shows '..tostring(err))
    ctx.assert(not ctx.find_button('saveslots_import_play'), 'Play offered for a bad code')
    ctx.assert(ctx.find_button('saveslots_import_cancel'), 'Cancel missing on the error panel')
    ctx.shot('import_error')
    return true
  end},

  -- 4. The real code, Play
  {name = 'import the code', run = function(ctx)
    if ctx.step_time() < 0.2 then return false end
    G.CLIPBOARD = S.code
    ctx.assert(ctx.click('saveslots_import'), 'Import code button not found')
    return true
  end},
  {name = 'import shot', run = function(ctx)
    if ctx.step_time() < 0.8 then return false end
    ctx.assert(text_of('saveslots_detail', 'saveslots_import_error') == nil, 'error shown for a good code')
    ctx.assert(text_of('saveslots_detail', 'saveslots_import_seed') == SEED, 'import seed shows '
      ..tostring(text_of('saveslots_detail', 'saveslots_import_seed')))
    ctx.assert(text_of('saveslots_detail', 'saveslots_import_deck') == 'Blue Deck', 'import deck shows '
      ..tostring(text_of('saveslots_detail', 'saveslots_import_deck')))
    ctx.assert(text_of('saveslots_detail', 'saveslots_import_stake') == 'Red Stake', 'import stake shows '
      ..tostring(text_of('saveslots_detail', 'saveslots_import_stake')))
    local lines, i = {}, 1
    while text_of('saveslots_detail', 'saveslots_import_notes_'..i) do
      lines[#lines+1] = text_of('saveslots_detail', 'saveslots_import_notes_'..i)
      i = i + 1
    end
    ctx.assert(table.concat(lines, ' ') == NOTES, 'import notes show '..table.concat(lines, ' '))
    ctx.assert(ctx.find_button('saveslots_import_play'), 'Play missing')
    ctx.shot('import')
    S.b_game = G.GAME
    return true
  end},
  -- The rig's fresh profile has Blue Deck locked: Play must refuse it, then
  -- start it once the (isolated) profile is all_unlocked.
  {name = 'play refused while locked', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    ctx.assert(ctx.click('saveslots_import_play'), 'Play not found')
    return true
  end},
  {name = 'still here', run = function(ctx)
    if ctx.step_time() < 1 then return false end
    ctx.assert(G.GAME == S.b_game, 'Play started a run on a locked deck')
    G.PROFILES[G.SETTINGS.profile].all_unlocked = true
    return true
  end},
  {name = 'play', run = function(ctx)
    if ctx.step_time() < 0.3 then return false end
    ctx.assert(ctx.click('saveslots_import_play'), 'Play not found')
    return true
  end},
  {name = 'shared seed started unseeded', timeout = 20, run = function(ctx)
    if not (G.GAME ~= S.b_game and G.STAGE == G.STAGES.RUN and G.GAME.pseudorandom
      and G.STATE == G.STATES.BLIND_SELECT) then return false end
    ctx.assert(G.GAME.pseudorandom.seed == SEED, 'Play started seed '..tostring(G.GAME.pseudorandom.seed))
    ctx.assert(not G.GAME.seeded, 'Play started a seeded run')
    ctx.assert(G.GAME.selected_back.effect.center.key == S.a_deck, 'Play deck '
      ..tostring(G.GAME.selected_back.effect.center.key))
    ctx.assert(G.GAME.stake == S.a_stake, 'Play stake '..tostring(G.GAME.stake))
    ctx.log('check: share code round trip, import error, unseeded Play')
    return true
  end},
}
