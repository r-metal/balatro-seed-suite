# What Steamodded changes under the suite

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
- **Making a card runs Steamodded's scoring hooks.** They read
  `G.GAME.selected_back.effect.center`. The simulator keeps the deck in the saved-run form
  (`'MANUAL_REPLACE'`), so predicting a shop, pack or Soul failed. Worse, the hooks iterate
  live card areas (`G.jokers`, `G.vouchers`), so they could reach the real run. Under
  Steamodded the suite therefore predicts nothing that makes a card.
- **Content mods mark what they add.** Steamodded sets `original_mod` on every prototype a
  mod adds, and `mod` on the vanilla ones a mod takes over. `BHCore.env()` reads those marks
  to tell a content mod (Pokermon) from Steamodded alone.
