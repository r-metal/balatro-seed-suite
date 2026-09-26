# Driving Balatro fast in scripts: GAMESPEED doesn't do it

(From T-103's golden_stable scenario.)
- `GAMESPEED` barely speeds up a scripted run. Card movement uses `real_dt` capped at 1/20 (`game.lua:2619-2626`), and many events wait on card positions, so even at 600+ fps a blind round took ~3.5 s at GAMESPEED 16 or 64. What works: call `G:update(1/20)` a few extra times per frame. That cut a round to ~0.3 s, and 10 seeds × 3 antes run in ~48 s.
- The shop is populated by a nested delayed event that reads `G.shop` (`game.lua:3090`). Leaving the shop before it runs crashes (`attempt to index field shop`). Wait until `#G.shop_booster.cards == 2`: packs are placed last.
- `G.E_MANAGER.queues.base` keeps one event during blind select, so "queue empty" can't be used as an idle signal.
- The voucher `end_round` draws for the next ante (`state_events.lua:263`) does **not** exclude an unbought voucher from the previous shop, because `G.shop_vouchers` is empty by then. The same voucher can show up two antes in a row (seed R2D2C3P9: Hieroglyph in antes 2 and 3).
