# Traps met building the Oracle, RunJournal and practice UIs

- **Building a `Tag` for display bumps `G.GAME.tag_tally`** (`Tag:init`). Display code has to guard `tag_tally` along with `used_jokers` and `pseudorandom`.
- **No game event fires when you leave a shop, reroll, buy or open a pack.** A cached prediction keyed only on bh-core events goes stale. The Oracle keys its cache on a "moment" signature: ante, round, blind on deck, in-shop, area counts, and a pack of `pseudorandom` + `used_jokers`.
- **The SaveSlots snapshot taken at the Big Blind's blind select still says `blind_on_deck == 'Small'`.** Read `round_resets.blind_states` instead.
- **`G.booster_pack` is the pack's UIBox, not the Card.** Read `G.STATE`, `G.GAME.pack_size` and `pack_choices`.
- **`:` is illegal in Windows file names**, and the game runs under Proton, so run ids go into file names with `:` → `_`.
- **The pause menu is short on vertical room.** vanilla + Save Slots + the seed row + Seed Oracle + another full-width row pushed Settings and Back off-screen (11.93 in an 11.5 room). New buttons have to share rows.
- On a fresh profile only Red Deck is unlocked, so any deck picker is disabled in the rig unless the scenario unlocks decks.
