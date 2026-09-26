# Balatro's generation code builds real Cards, so a simulator can't just call it


- `create_card` (`common_events.lua:2082`) constructs a `Card`, which needs sprites and atlases, writes `G.GAME.used_jokers`, bumps `G.sort_id`/`G.ID`, and can trigger discover/unlock (profile writes). `create_card_for_shop` and pack `Card:open` also queue events and touch live Tags.
- These are safe to call directly: `get_current_pool`, `get_next_tag_key`, `get_next_voucher_key`, `get_new_boss`, `get_pack`, `poll_edition`. So a Seed Oracle core has to re-implement **only** `create_card`'s *draw order*, Card-free, and check it against vanilla in-game. It must not re-implement the RNG.
- RNG state is one float per key string in `G.GAME.pseudorandom`, advanced independently. Cloning it is cheap and exact. `pseudorandom` reseeds `math.random` from a float and draws once, which only reproduces under LuaJIT (fine: `love.thread` workers are LuaJIT too).
- Streams with no ante in the key, like `boss` and `Joker4` (the Soul's legendary), carry across antes. Shops use a stream per **ante**, not per shop, so skipping a blind or rerolling shifts later shops in the same ante. Every pack of a type in an ante shares one stream, including packs granted by tags.
- Every unseeded `math.random` in generation is cosmetic: `_1`/`_2` pack art variants, and `discard_pos`.
