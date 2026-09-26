# Building a Card for display writes to the live run

Creating `Card(...)` objects for a preview panel isn't side-effect free:
- `Card:set_ability` sets `G.GAME.used_jokers[key] = true` whenever no overlay is up. That changes future pools **and the Soul gating** (see [soul-roll-gating](2026-09-23-soul-roll-gating.md)).
- Some jokers (e.g. To Do List) draw from `G.GAME.pseudorandom` when they're built, which advances the live run's RNG streams.
- Every `CardArea` registers in `G.I.CARDAREA`, and `Game:draw` renders every parentless area. If building throws after areas exist, they leak and draw as stray cards at (0,0).

SaveSlots' `preview.build` snapshots and restores `used_jokers` and `pseudorandom`, and (T-005b) tears down the areas on error. A seed oracle must sandbox far more than this.

**Update (wave 3b review):** *removing* a display card has live side effects too. `Card:remove` (`card.lua:4733`) decrements the **live** `G.jokers`/`G.consumeables.config.card_limit` when `ability.queue_negative_removal` is set. Vanilla sets that flag on a debuffed Negative card (`card.lua:689`), and `Card:save` persists it. So a preview that deep-copies a saved ability can shrink your real joker slots every time the preview closes. Copying `ability` wholesale is the trap: strip the removal-path flags.
