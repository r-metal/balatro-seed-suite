# What Steamodded changes under the suite

**The one that cost the most: Steamodded's RNG goes random while the game is paused.**
`lovely/fixes.toml` ("Fix prng calls on collection advancing seeds") adds
`if G.SETTINGS.paused and key ~= 'to_do' then return math.random() end` to `pseudoseed`.
Every overlay pauses the game, so the Oracle (open over the run) and the Finder's
main-thread check (the Finder is an overlay too) simulated with an unseeded RNG. The
Oracle showed random tags, bosses and Vouchers, and the check rejected every correct worker
hit. That looked like a bug about searching mid-run, because the rig's direct engine calls
never paused (a headless run only paused once it lost focus). The workers never read the
flag. Fix: `sim.sandbox` sets `G.SETTINGS.paused = false` while it runs (next to the
existing `G.OVERLAY_MENU = nil`), and scenario `lovely_paused_sim` pins it. Lesson: the
simulator has to model the game's state, and that includes UI flags that game code reads.

Found by running the suite next to Steamodded 26.829.0 in the real-lovely rig
(`rig/lovely-rig.sh`, the real lovely injector's Linux build on native LÖVE).

- **lovely patches worker threads too.** lovely hooks `luaL_loadbuffer` in every Lua state,
  so a `love.thread` that loads `functions/common_events.lua` gets Steamodded's patched copy.
  That copy indexes `SMODS`, which a worker doesn't have, so every Seed Finder search died
  with "attempt to index global 'SMODS'". lovely only patches a chunk whose name is a patch
  target (`patch/table.rs` `needs_patching`), so the workers now read the file and load it
  under a name no mod targets (`@vanilla/<path>`). That gives them pure vanilla code.
- **The round's Voucher is a list.** Steamodded keeps `current_round.voucher` as
  `{'v_x', spawn = {v_x = true}}` and its shop reads `.spawn`. Reads go through
  `BHCore.round_voucher()`, and writes through `BHCore.roll_round_voucher()`.
- **Bosses are Steamodded's own.** `lovely/weights.toml` bypasses `get_new_boss()`, and
  `SMODS.reset_blind_choices` picks the boss again at run start. So even ante 1's boss can
  differ from vanilla's for the same seed. Skip tags and Vouchers matched: 695 Finder hits
  re-checked under Steamodded, and none was rejected.
- **The same cards, other editions.** The golden suites, run under the real Steamodded with
  editions and bosses left out of the comparison, matched on all 255 predictions: tags,
  Vouchers, 20 Soul legendaries, 83 pack contents, and 68 shop rows and rerolls. Editions
  differ: a Mad Joker and a Five of Hearts came out Foil where vanilla has none. 0.3.1
  refused card predictions under Steamodded; 0.3.2 makes them and leaves editions out.
- **The `effect` error is Pokermon's, not Steamodded's.** `SMODS.get_card_areas('individual')`
  reads `G.GAME.selected_back.effect`, and the simulator keeps the deck in the saved-run form
  (`'MANUAL_REPLACE'`). This only fired with Pokermon loaded. Content mods switch the
  predictions off anyway. Steamodded's own create/open/reroll hooks run on actions in the
  live game (opening a pack, a reroll), which the simulator never performs.
- **Steamodded prototypes have metatables.** The vanilla booster packs become objects of its
  classes, so the Finder's projection (which dropped any table with a metatable) lost every
  pack and the Booster pool. The projection now copies each prototype's own fields.
- **Content mods mark what they add.** Steamodded sets `original_mod` on every prototype a
  mod adds, and `mod` on the vanilla ones a mod takes over. `BHCore.env()` reads those marks
  to tell a content mod (Pokermon) from Steamodded alone.
- **Five vanilla decks carry a function (found 2026-09-28).** Steamodded takes ownership of
  Zodiac, Painted, Anaglyph, Plasma and Erratic (`game_object.lua`, `stake_mod`) to set their
  unlock stake, and `take_ownership` copies its table's fields onto the center, including an
  `inject` function. `STR_PACK` errors on a function in a table's own fields (it only turns
  nested Objects into `"MANUAL_REPLACE"`), so `state.fresh`'s `STR_UNPACK(STR_PACK(center))`
  failed on those decks. It now makes a plain-data copy that drops functions.
- **Cards need `ability.card_limit` (found 2026-09-28).** Steamodded's `set_ability` adds
  `card_limit` and `extra_slots_used` to every card's `ability`, and its `set_edition`,
  seal and enhancement code does arithmetic on them. A save made before Steamodded was
  installed has neither, so the Save Slots preview, which copies the saved `ability` onto a
  fresh card, failed on any card with an edition. Fields the save lacks now keep the fresh
  card's value.
- **Pack states.** Steamodded opens every pack in `G.STATES.SMODS_BOOSTER_OPENED` (999) and
  uses `G.GAME.pack_size` for the number of picks, so the golden scenarios accept that state
  and count the cards shown instead.
