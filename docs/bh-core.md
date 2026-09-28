# bh-core: contracts (locked for 0.2.0)

Last updated: 2026-09-23. Research behind these: docs/research/sim-feasibility.md.
Plan: docs/ROADMAP-0.2.0.md.

Module names are `bhcore.*` (see `mods/bh-core/lovely.toml`). `BHCore` is the global set by `bhcore.init`. Any mod that uses bh-core does `require('bhcore.init')` in its own init.

## events

`require('bhcore.events')`
- `events.install()` is idempotent. It wraps vanilla functions (after the original, calling it with every argument) so that each event below fires **exactly once per occurrence**, and never during a sim sandbox call (`BHCore.sim_depth > 0`).
- `events.on(name, fn)` returns a token. `events.off(token)`.
- A handler error is caught (`pcall`) and printed with `[bh-core]`, and never breaks the game or the other handlers.

| name | fires when | payload (one table) |
|---|---|---|
| `run_start` | a run starts or is loaded (`Game:start_run`) | `{seed, stake, deck, loaded = bool, ante}` |
| `blind_selected` | the player selects a blind | `{ante, blind = key, kind = 'Small'/'Big'/'Boss'}` |
| `blind_skipped` | the player skips a blind | `{ante, kind, tag = key}` |
| `hand_scored` | a played hand has finished scoring | `{ante, round, hand = name, chips, mult, score, total}` |
| `round_end` | a blind ends | `{ante, round, won = bool, dollars}` |
| `shop_enter` | the shop opens | `{ante, round, dollars}` |
| `ante_change` | the ante changes | `{from, to}` |
| `run_end` | game over or win | `{won = bool, ante, round, seed}` |
| `shop_reroll` *(added in 0.4.0, T-372a)* | the shop is rerolled (the Reroll button, `G.FUNCS.reroll_shop`), once the new cards are in the shop's card slots | `{ante, round, dollars, cards = {key, ...}}`: `cards` holds the center keys of `G.shop_jokers`' cards after the reroll, in slot order, whatever their set; `dollars` is after the reroll's cost |

*(Added in 0.4.0, T-372a:)* `events.NAMES` stays the eight 0.2.0 events (code that subscribes to every name in it and counts each one relies on that); `events.ALL` is NAMES plus the events added since, and `events.on` takes any name in ALL. `shop_enter` fires before vanilla stocks the shop's card slots (they are filled in a nested event once the shop has slid in, game.lua:3081-3114): a reader of the entry row waits for it.

## Text inputs (0.3.4)

`BHCore.install_digits()` is idempotent; a mod UI calls it from its install. Afterwards an input made with `create_text_input{bh_digits = true, ...}` keeps a typed `'0'` (vanilla's `text_input_key` types `'o'` for it in every input, because seeds have no zero). Inputs without the flag, and a `'0'` typed with caps (`'O'`), behave as in vanilla. It works with vanilla's child ids and with the `<id>_position` ids of Steamodded and HandyBalatro (journal/2026-09-28-text-inputs.md). Scenario: `text_digits`, also in `make lovely-check` under Steamodded and under Handy.

## sim.state

`require('bhcore.sim.state')`. A **sim state** `S` is a plain table:
`{game = <deep copy of a G.GAME>, all_unlocked = bool}`.
- `state.capture()` → S from the live run: a deep copy of G.GAME with **exact floats**. *(Amended after wave A: a plain `STR_UNPACK(STR_PACK(G.GAME))` truncates doubles to 14 significant digits, and `hashed_seed` feeds `math.randomseed` bit-exactly, so 200 of 200 probe draws diverged. Never round-trip sim state through STR_PACK. Use `state.capture`/`state.copy`.)*
- `state.fresh(seed, opts)` → S for a brand-new run with `seed` (string), as `Game:start_run` would set it up **before** its first generation. `opts = {stake = 1, deck = 'b_red', all_unlocked = false}`. It must not touch the live `G.GAME` (build the object via `Game:init_game_object()` inside the sandbox, then apply the seed and hashed seed exactly as `start_run` does).
- `state.copy(S)` → an independent deep copy.
- *Note (wave A):* `fresh()` runs the deck's `apply_to_run` with its queued events sent to a throwaway queue. Deck effects applied through events (Magic, Zodiac, Nebula, … rates and slots) are therefore **not** in a `fresh()` state. Shop prediction must apply them explicitly, or use `capture()` from a real run.

## sim.sandbox

`require('bhcore.sim.sandbox')`
- `sandbox.run(S, fn, ...)` → `ok, ...` (pcall-style). For the duration of `fn` it:
  - makes `G.GAME = S.game`;
  - swaps `G.jokers`, `G.consumeables`, `G.playing_cards`, `G.deck`, `G.hand`, `G.shop_jokers`, `G.shop_vouchers`, `G.shop_booster` for empty stub areas (`{cards = {}, config = {card_limit = <live or default>}}`). *(Amended: `G.playing_cards` is a plain list in vanilla, and pool gates iterate it with `pairs`, so its stub is an empty table whose metatable answers `.cards`/`.config`.)*;
  - when `S.all_unlocked`, treats every center as unlocked and discovered for pool purposes (restore after);
  - increments `BHCore.sim_depth`.
  It **always** restores everything, including on error. It is re-entrant: nested calls share the outer swap.
- **Guarantee:** after any `sandbox.run`, `STR_PACK(G.GAME)` of the live run is byte-identical to before, and no Card, event, sound, alert, discovery, unlock or save happened.

## sim.card

`require('bhcore.sim.card')`. Callable **only inside** `sandbox.run`.
- `card.create(args)` → `{key, set, edition = {…} or nil, stickers = {eternal=, perishable=, rental=}}`. It is a Card-free twin of vanilla `create_card(_type, area, legendary, _rarity, skip_materialize, soulable, forced_key, key_append)` (`common_events.lua:2082-2154`). `args = {type, area = 'shop'|'pack'|'other', legendary, rarity, soulable, forced_key, key_append}`. It makes **the same pseudorandom draws in the same order** as vanilla, including Soul/Black Hole gating, editions, and stake stickers for shop jokers. It records the key in `G.GAME.used_jokers`, as vanilla's `set_ability` does.
- *(Amended after wave B:)* the sandbox hides the live `G.OVERLAY_MENU`, so `card.create` always does vanilla's no-overlay `used_jokers` bookkeeping. `predict.legendaries(S, n)` returns `{{key, edition}…}`.
- `card.release(key)` removes the key from `used_jokers`, as vanilla `Card:remove` does when no copy remains (rerolls, packs closing, selling).

## sim.predict

`require('bhcore.sim.predict')`. Every function takes S, **advances S's streams** exactly as the game would, and must be called in the game's order. Only `plan` guarantees that order.
- `predict.plan(S, {antes = N, shops_per_ante = 1..3, rerolls = 0, open_packs = true})` → an array of ante records:
  `{ante, tags = {small, big}, boss, voucher, shops = {{cards = {…}, packs = {…}, rerolls = {{…}…}}…}, pack_contents = {[pack_index] = {cards…}}, soul = {…}}`.
  Each field carries a `certainty` of `'stable'` or `'conditional'` (T4 in the roadmap).
- Lower-level helpers (`predict.tags`, `boss`, `voucher`, `shop`, `packs`, `pack_contents`) are exported for the Finder's short-circuiting. Their order contract is documented in `predict.lua`'s header.
- *(Added in 0.3.0, T-320:)* `predict.ante_walk(S, a, policy)` → `{tags = {small, big}, shops = {{after, cards, rerolls = {{cards}…}, packs, contents = {[slot] = {cards…}}}…}, tag_packs = {{blind, tag, pack, cards}…}}`. One ante in play order under `policy = {skip = {Small = bool, Big = bool}, rerolls = R (0), open = bool (true), cards = bool (true), tags = {small, big} or nil}`: (a > 1) the shop after the previous Boss (`after = 'Boss'`), then per blind, Small first, its skip or its shop. A skipped blind has no shop; when its tag gives a pack it is opened at the skip, nothing taken: Charm Tag → `p_arcana_mega_1`, Ethereal Tag → `p_spectral_normal_1` (`predict.TAG_PACKS`). Other tags are skipped without a pack and are not modelled. Each shop is `shop`, `packs(2)`, R × `reroll`, then (with `open`) every pack in slot order through `pack_contents`, then `leave_shop`; `cards = false` draws pack keys only and needs `open = false`. The walk draws `tags(S, a)` itself unless `policy.tags` passes the ones the caller drew. Boss and voucher are not drawn. The run's forced first Buffoon lands in the run's first shop, wherever the skips put it. Real-game proof: `rig/scenarios/golden_walk.lua` (4 seeds, every skip combination, antes 1–2, chosen so that opening a tag pack at the end of its ante, or at its start before the Boss's shop, instead of at its skip changes what an Arcana or Spectral pack shows; the position between the Boss's shop and the Small's is not separately distinguished).
- *(Added in 0.3.0, T-324a:)* `predict.ALL_TAG_PACKS` = every tag whose pack opens at the skip (tag.lua:206-282): Charm → `p_arcana_mega_1`, Meteor → `p_celestial_mega_1` (both: the _1/_2 art variant is unseeded `math.random`), Ethereal → `p_spectral_normal_1`, Standard → `p_standard_mega_1`, Buffoon → `p_buffoon_mega_1` (opened by `Card:open`, so the run's forced first Buffoon is untouched). `ante_walk`'s `policy.pack_tags` is the set of tag keys whose pack the walk opens (keys with a truthy value; `ALL_TAG_PACKS` itself works; a key outside it raises). Its default is `predict.TAG_PACKS`, which stays exactly {Charm, Ethereal} because `seedfinder.filter` builds its skip set from it: without the opt-in, a walk that skips a Meteor, Standard or Buffoon Tag is conditional on that pack's draws. Real-game proof: `rig/scenarios/golden_tagpacks.lua` (6 seeds; ante 1 without skips, ante 2 skipping its pack-tag blinds, Small, Big and both; every tag pack compared card for card, Standard packs by rank, suit, enhancement, edition and seal, Buffoon packs by key and edition; five seeds chosen so that a wrong opening order changes a same-kind shop pack in the ante, one for a Foil joker in a Buffoon Tag pack).

## Acceptance (golden seeds)

A prediction type is **shipped** only when `rig/scenarios/golden_*.lua` drives the real game on at least 10 seeds and every predicted field of that type equals what vanilla generated. See T2 in the roadmap.
