# STR_PACK truncates floats, and Balatro's RNG seeds from exact bits

`STR_PACK` writes numbers by plain concatenation (`tostring`, 14 significant digits). `G.GAME.pseudorandom.hashed_seed = pseudohash(seed)` is a full double, and `pseudorandom` feeds `(stream + hashed_seed)/2` into `math.randomseed`, which LuaJIT seeds from the double's **exact bits**. So a sim state made by `STR_UNPACK(STR_PACK(G.GAME))` diverges on every draw: live `0.75449886209827355` vs packed `0.75449886209827`, and 200 of 200 probe draws differed.

The game itself is immune only because `start_run` recomputes `hashed_seed` even when loading a save. Stream states stored after an advance are `%.13f` values and survive the round trip.

- Sim state copies must be real deep copies that keep exact floats (`bhcore.sim.state.capture/copy`).
- A second, related trap: two *equal* tables don't pack to identical bytes, because `pairs()` order depends on insertion history. "Byte-identical `STR_PACK`" is only a valid invariant check for the **same** table packed before and after.
