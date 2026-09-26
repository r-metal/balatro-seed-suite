# Crash-safe saves without rename in LÖVE 11.5

`love.filesystem` (11.5) has no `rename`, and `write` truncates in place, so a crash mid-write leaves a torn file. Vanilla `compress_and_save` also **drops `write`'s return value**, so failed writes look successful.

What SaveSlots' store ended up doing, after two adversarial refutations:
- Write `<file>.tmp`, then read it back and decompress + unpack it to verify. Then write the final path and verify again, then remove the tmp. Readers fall back to a verified `.tmp` if the final file is torn.
- The index is self-healing: rebuild it from `saveslots/*.jkr` when it's missing or corrupt, never "start fresh" (that orphans every slot).
- Rollback on a failed save covers every prior slot state (present, listed but missing, tmp-only, unreadable), and each rollback step's own result is checked.
- Dedup of imports by **identity** (origin/name), never by run contents. Two save-scum states in the same round are legitimately identical in summary.

The independent verifier's suite (`tests/test_store_adv.lua`) found what 34 implementer-written tests didn't. It's now orchestrator-owned and part of the barrier.
