# Balatro's Soul roll is gated, and Brainstorm's Souls filter ignores it

**Where:** `functions/common_events.lua` `create_card` (~2088), `card.lua` `Card:set_ability` (~349), `Card:remove` (~4741). Brainstorm `Brainstorm_reroll.lua:77-90`.

- A Tarot/Spectral card rolls `pseudorandom('soul_'.._type..ante) > 0.997` **only if** `not (G.GAME.used_jokers['c_soul'] and not Showman)`.
- `used_jokers[key] = true` is set in `set_ability` for *any* card created while no overlay is up, consumables included. `Card:remove` clears it when no copy remains.
- So while a Soul card exists, later Tarots **don't roll at all**. They don't consume the stream. A 5-card Mega Arcana can hold at most one Soul, and the cards after it don't advance `soul_Tarot<ante>`.
- Brainstorm's "Number of Souls = N" polls the stream 5×N times assuming every poll is consumed, and asks for ≥1 hit per block of 5. That's accurate for N = 1 with a Charm Tag (the free Mega Arcana gets rolls 1–5), and approximate for N ≥ 2.
- Other key-placement facts: the tag filter checks the ante-1 **Small Blind** tag (`Tag1`). The pack filter checks the first *random* `shop_pack1` roll, which is the second pack slot of the first shop, because slot 1 is a forced Buffoon pack that returns before polling (`get_pack`, ~1945). The shop after the Boss is already the next ante, so it uses a different stream.

Implication for 0.2.0's Seed Oracle: simulate by running the real `create_card` on a sandboxed state (gating included), rather than re-deriving the RNG by hand.
