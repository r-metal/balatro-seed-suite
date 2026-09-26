-- bhcore.sim.card: a Card-free twin of vanilla create_card. Contract:
-- docs/bh-core.md § sim.card. Callable only inside sandbox.run.
--
-- API
--   card.create(args) -> {key, set, type, name, edition = {<kind> = true} or nil,
--                         stickers = {eternal, perishable, rental}, front = <P_CARDS key> or nil}
--     args = {type, area = 'shop'|'pack'|'other', legendary, rarity, soulable,
--             forced_key, key_append}; the create_card arguments, with the
--     area reduced to what create_card compares it against.
--   card.release(key)   the used_jokers half of Card:remove.
--   card.shop_type()    create_card_for_shop's card-type roll -> type string or nil.
--   card.shop_card()    card.shop_type() + create + the Illusion edition, i.e.
--                       create_card_for_shop(G.shop_jokers) without its tags.
--
-- What is mirrored (vanilla 1.0.1o, build/game; written from the call order,
-- not copied):
--   create_card               functions/common_events.lua:2082-2154
--     soul / black hole rolls   :2088-2100  (one 'soul_'..type..ante draw per
--                                           gate; a Spectral draws that stream
--                                           twice and Black Hole wins)
--     forced key / Base         :2102-2110  (no pool draw; set taken from the center)
--     pool draw + resamples     :2112-2118  (vanilla get_current_pool and
--                                           pseudorandom_element, called as-is)
--     playing-card front        :2123       ('front'..append..ante)
--     Card() side effects       card.lua:223-354, Card:set_ability:
--                                 To Do List draws 'to_do' once (:312-321);
--                                 every P_CENTERS key sharing the center's name
--                                 goes into used_jokers unless G.OVERLAY_MENU (:349-354)
--     stickers                  :2131-2147, with Card:set_eternal / set_perishable /
--                                 set_rental (card.lua:506-523): eternal_compat and
--                                 perishable_compat gate, eternal blocks perishable;
--                                 'etperpoll'/'packetper' always drawn in shop/pack,
--                                 'ssjr'/'packssjr' only with rentals enabled
--     edition                   :2149       (vanilla poll_edition, 'edi'..append..ante)
--   Card:remove used_jokers     card.lua:4742-4748 (release)
--   create_card_for_shop        functions/UI_definitions.lua:763-796 (shop_type,
--                               shop_card): 'cdt'..ante; with v_illusion one
--                               'illusion' draw while the type list is built, and
--                               for Base/Enhanced two more after the card
--                               (edition). Tags (store_joker_create/modify) and
--                               the tutorial's forced shop are the caller's job.
--
-- Held cards
--   Showman (find_joker) and release's "is a copy still held" read G.jokers and
--   G.consumeables, which sandbox.run swaps for empty stubs. To model held
--   cards, put stand-ins such as {ability = {name = 'Showman'}} into those
--   stubs' .cards inside the sandbox call.
--
-- Not reproduced (no draws): sprites, sort ids, discovery/unlock, materialize,
-- check_for_unlock, sounds. None of them touch G.GAME.pseudorandom.
local M = {}

local function in_sandbox()
  assert(BHCore and (BHCore.sim_depth or 0) > 0, 'bhcore.sim.card: call inside sandbox.run')
end

local function showman_held()
  return next(find_joker('Showman')) ~= nil
end

-- create_card's "not (used and not Showman)" gate.
local function available(key)
  return not (G.GAME.used_jokers[key] and not showman_held())
end

-- Card:set_ability's used_jokers write: by name, not by key.
local function mark_used(center)
  if G.OVERLAY_MENU then return end
  for k, v in pairs(G.P_CENTERS) do
    if v.name == center.name then G.GAME.used_jokers[k] = true end
  end
end

function M.create(args)
  in_sandbox()
  assert(type(args) == 'table' and args.type, 'card.create: args.type required')
  local game = G.GAME
  local ante = game.round_resets.ante
  local banned = game.banned_keys or {}
  local t, forced, append = args.type, args.forced_key, args.key_append

  if not forced and args.soulable and not banned['c_soul'] then
    if (t == 'Tarot' or t == 'Spectral' or t == 'Tarot_Planet') and available('c_soul') then
      if pseudorandom('soul_'..t..ante) > 0.997 then forced = 'c_soul' end
    end
    if (t == 'Planet' or t == 'Spectral') and available('c_black_hole') then
      if pseudorandom('soul_'..t..ante) > 0.997 then forced = 'c_black_hole' end
    end
  end
  if t == 'Base' then forced = 'c_base' end

  local center
  if forced and not banned[forced] then
    center = G.P_CENTERS[forced]
    assert(center, 'card.create: unknown forced_key '..tostring(forced))
    if center.set ~= 'Default' then t = center.set end
  else
    local pool, pool_key = get_current_pool(t, args.rarity, args.legendary, append)
    local key = pseudorandom_element(pool, pseudoseed(pool_key))
    local it = 1
    while key == 'UNAVAILABLE' do
      it = it + 1
      key = pseudorandom_element(pool, pseudoseed(pool_key..'_resample'..it))
    end
    center = G.P_CENTERS[key]
  end

  local front
  if t == 'Base' or t == 'Enhanced' then
    local _, fkey = pseudorandom_element(G.P_CARDS, pseudoseed('front'..(append or '')..ante))
    front = fkey
  end

  -- Card(): set_ability's draw, then its used_jokers write.
  if center.name == 'To Do List' then pseudoseed('to_do') end
  mark_used(center)

  local st = {eternal = false, perishable = false, rental = false}
  local edition
  if t == 'Joker' then
    local mods = game.modifiers or {}
    local function set_eternal()
      st.eternal = (center.eternal_compat and not st.perishable) and true or false
    end
    if mods.all_eternal then set_eternal() end
    if args.area == 'shop' or args.area == 'pack' then
      local pack = args.area == 'pack'
      local poll = pseudorandom((pack and 'packetper' or 'etperpoll')..ante)
      if mods.enable_eternals_in_shop and poll > 0.7 then
        set_eternal()
      elseif mods.enable_perishables_in_shop and poll > 0.4 and poll <= 0.7 then
        st.perishable = (center.perishable_compat and not st.eternal) and true or false
      end
      if mods.enable_rentals_in_shop and pseudorandom((pack and 'packssjr' or 'ssjr')..ante) > 0.7 then
        st.rental = true
      end
    end
    edition = poll_edition('edi'..(append or '')..ante)
  end

  return {key = center.key or forced, set = center.set, type = t, name = center.name,
    edition = edition, stickers = st, front = front}
end

function M.release(key)
  in_sandbox()
  local center = G.P_CENTERS[key]
  if not center or G.OVERLAY_MENU then return end
  for k, v in pairs(G.P_CENTERS) do
    if v.name == center.name and not next(find_joker(center.name, true)) then
      G.GAME.used_jokers[k] = nil
    end
  end
end

function M.shop_type()
  in_sandbox()
  local game = G.GAME
  local ante = game.round_resets.ante
  local spectral = game.spectral_rate or 0
  local total = game.joker_rate + game.tarot_rate + game.planet_rate + game.playing_card_rate + spectral
  local polled = pseudorandom(pseudoseed('cdt'..ante)) * total
  -- The playing-card entry's type is decided while the list is built, so the
  -- Illusion draw happens whatever the roll lands on.
  local playing = (game.used_vouchers['v_illusion'] and pseudorandom(pseudoseed('illusion')) > 0.6)
    and 'Enhanced' or 'Base'
  local check = 0
  for _, v in ipairs{
    {'Joker', game.joker_rate}, {'Tarot', game.tarot_rate}, {'Planet', game.planet_rate},
    {playing, game.playing_card_rate}, {'Spectral', spectral},
  } do
    if polled > check and polled <= check + v[2] then return v[1] end
    check = check + v[2]
  end
  return nil
end

function M.shop_card()
  local t = M.shop_type()
  if not t then return nil end
  local c = M.create{type = t, area = 'shop', key_append = 'sho'}
  if (t == 'Base' or t == 'Enhanced') and G.GAME.used_vouchers['v_illusion']
      and pseudorandom(pseudoseed('illusion')) > 0.8 then
    local poll = pseudorandom(pseudoseed('illusion'))
    if poll > 1 - 0.15 then c.edition = {polychrome = true}
    elseif poll > 0.5 then c.edition = {holo = true}
    else c.edition = {foil = true} end
  end
  return c
end

return M
