# Vanilla RNG code runs unmodified in a love.thread at ~47k seeds/s

(From the T-104 spike; details in docs/research/worker-spike.md.)
- A `love.thread` worker can `love.filesystem.load` `engine/string_packer.lua`, `functions/misc_functions.lua` and `functions/common_events.lua` **unmodified**, because PhysFS is shared with threads. It needs only a stub `G` (`ARGS`, `P_CENTERS`, `P_TAGS`, `P_CENTER_POOLS`, `P_JOKER_RARITY_POOLS`) and a fresh stub `G.GAME` per seed.
- The data projection is 71 KB `STR_PACK`ed. Pools travel as **ordered key lists**, and the worker resolves them back to its own center tables, so order and identity are exact.
- Tag-only filter: ~47k seeds/s per worker, the same speed as the main thread. 4 workers give ~178k/s and 8 give ~250–312k/s. That's two orders of magnitude over the roadmap's 2k/s target, so the pure-Lua Finder is not throughput-bound for cheap filters.
- `math.random` state is per thread, so a worker reseeding doesn't disturb the main thread's draws.
