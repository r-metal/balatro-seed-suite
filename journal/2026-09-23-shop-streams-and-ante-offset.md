# The shop after a Boss belongs to the next ante's streams

(From T-106, predict shops/packs.)
- `ease_ante` runs in `end_round` **before** the shop, so the shop after ante A's Boss draws the `cdt`/`shop_pack`/pack streams of ante **A+1** and shows the A+1 voucher. So ante 1 has only 2 "stream shops" and later antes have 3. Keying shop predictions by the blind's ante is off by one for every Boss shop.
- Every shop stream is keyed by ante only, so "the first N shops of ante A" means "the first N stream positions". That's exact however many blinds were skipped, as long as skip tags don't draw from shop streams.
- `Card:remove` releases `used_jokers` **by name**, checking only `G.jokers`/`G.consumeables` (`card.lua:4742-4748`). So closing a pack that holds a card with the same key as a shop card (possible through the empty-pool fallback) clears that key even though the shop still shows it. The sim reproduces this quirk.
- For scripted runs, wall-time settle waits were the bottleneck, not game updates. Counting frames per phase instead cut the 10-seed shop suite from 98 s to 57 s. `G.FUNCS.use_card({config={ref_table=booster}})` opens a pack headless, and `skip_booster` closes it. Wait for `G.booster_pack == nil` and the controller locks before the next one.
