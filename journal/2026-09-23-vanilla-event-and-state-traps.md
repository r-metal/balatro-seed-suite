# Vanilla event-loop traps found while hooking game events

(From T-101, bh-core events.)
- `Game:update_selecting_hand` (`game.lua:3057`) calls `end_round()` **every frame** while hand, deck and play are all empty. There's no STATE_COMPLETE guard, and end_round only queues a 0.2 s event, so it runs several times per blind. Hook the state it leads to (ROUND_EVAL / GAME_OVER), not the call.
- An `Event` created while unpaused gets `pause_skip` while `G.SETTINGS.paused` is true (`engine/event.lua:50`). `update_game_over` sets paused, so a follow-up event queued in `end_round` never runs on a loss. `EventManager` also lets only one blocking event complete per queue per pass (`event.lua:185`).
- Skipping a blind can open a booster pack on the spot: the Charm Tag opens a Mega Arcana, moving STATE to TAROT_PACK inside blind select. Calling `G.FUNCS.skip_booster` twice crashes (`button_callbacks.lua:2576`, `G.booster_pack` nil).
- Calling `G.FUNCS.go_to_menu()` on the same frame blind select first appears after a seeded `start_run` crashes (`button_callbacks.lua:3134`, `screenwipe` nil). Wait a few seconds first.
- `G.playing_cards` is a plain list, not a CardArea, and the enhancement pool gate iterates it with `pairs` (`common_events.lua:2014`).
