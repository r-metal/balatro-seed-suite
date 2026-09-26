# 0.2.0 feature contracts (locked; the orchestrator amends them with a recorded reason)

Last updated: 2026-09-23. bh-core contracts live in docs/bh-core.md; this file covers the feature mods and new bh-core pieces.

## bhcore.fs: verified storage (T-124, extracted from SaveSlots' store)

`require('bhcore.fs')`. These are the proven write/read primitives from `mods/SaveSlots/src/store.lua`, **moved, not rewritten**:
- `fs.write_table(path, t)` → `true` or `nil, err`: STR_PACK + deflate, staged `.tmp`, read-back verification, `.tmp` snapshot/restore (the T-002c semantics).
- `fs.read_table(path)` → `t` or `nil, err`, with the verified `.tmp` fallback.
- `fs.remove(path)` → whether the path is gone; `fs.exists(path)`; `fs.ensure_dir(path)`.
- SaveSlots' store keeps its public API and requires `bhcore.fs` for the primitives. **Every existing store test passes unchanged**, including the adopted adv, crash and tmpjunk suites.

## SaveSlots 0.2 (T-120, T-121, T-122)

*Dependency:* since 0.2, SaveSlots requires bh-core (`require('bhcore.init')` in its init, for events and fs). Install both.

Additive to the 0.1.0 store contract (docs/SPEC.md); 0.1.0 indexes and slots load unchanged (roadmap T6).
- Index entries gain an optional `meta` table: `{kind = 'save'|'checkpoint'|'practice'|'hunt', target = string?, notes = string?, run_id = string?, origin = {kind = 'finder', filter_name, filter}?}`. `kind` defaults to `'save'`.
- `store.set_meta(id, meta)` → `true` or `nil, err`. It merges the fields and keeps everything else.
- `store.list(filter?)`: with `filter = {kind = …}`, only matching entries. Entries carry `meta` (a copy).
- `store.save(run, name, id?, meta?)`: the extra `meta` is additive.
- **Auto-checkpoints (T-121):** the first autosave snapshot after reaching blind select at a new ante (bh-core `ante_change`, then the next checkpoint snapshot, plus run start at ante 1) is saved as `kind = 'checkpoint'`, `run_id = <seed>..':'..<run start os.time>`, named `"Auto A<ante>"`. It keeps the newest **8 per run_id** (older ones are deleted) and **3 runs** in total. It's toggleable (`SaveSlots.settings.auto_checkpoints`, default on) and never runs inside the sim.
- *(Amended after wave C:)* auto-checkpoints are on by default. The Play-tab "recent saves" leave them out, and smoke scenarios that test player slots set `SaveSlots.settings.auto_checkpoints = false` first.
- **UI:** a kind filter cycle over the list (All / Saves / Checkpoints / Practice / Hunts); the detail panel shows target and notes with edit buttons (text input, 24 chars for the target, 60 for notes) and the origin filter's name for hunts.
- **Practice (T-122):** a composer overlay (from the Save Slots screen: "New practice…") with: deck, stake, ante (1–8), money, up to 5 jokers (picked from the unlocked jokers, searchable by first letter), up to 2 consumables, hand levels for the 3 most-played poker hands. **Create** starts a real run (vanilla `start_run`) on a practice seed, applies the choices with vanilla functions (`add_to_deck`/`emplace`, `ease_dollars`, `ease_ante`, `level_up_hand`), waits for the next autosave, and stores it as `kind = 'practice'` with the composer choices in `meta.practice`.

## RunJournal (T-123, T-125): new mod `mods/RunJournal`, modules `runjournal.*`

- Subscribes to bh-core events only. Per run it writes `<profile>/runjournal/<file>.jkr` (bhcore.fs) plus `index.jkr`, where `run_id = <seed>..':'..<start os.time>`. *(Amended after wave D: the file name replaces `:` with `_` because `:` is illegal on Windows/Proton, and the time part of the id is bumped past a same-second collision; `started_at` keeps the real time.)* A loaded run continues its record (match the seed and the latest unfinished record).
- Record: `{run_id, seed, deck, stake, started_at, ended_at?, won?, final_ante, final_round, antes = {[a] = {dollars_start, dollars_end, blinds = {{kind, key, skipped, tag?, hands = {{hand, chips, mult, score}}, won}}}}, jokers_seen = {keys at each shop_enter}, origin = {filter_name?}}`. Writes happen at `round_end`, `shop_enter` and `run_end`, never per frame.
- `runjournal.stats(filter?)` → `{runs, wins, win_rate, by_deck = {...}, by_stake = {...}, by_joker = {[key] = {runs, wins}}}`. "Build archetype" in 0.2.0 means the joker set at the run's end, grouped by any user-selected joker key.
- `runjournal.export(fmt)` with `fmt = 'csv'|'json'` writes `<profile>/runjournal/export-<os.time>.<fmt>` and returns the path. CSV has one row per run.
- UI (T-125): a "Run Journal" button in Options/pause, and an overlay with the stats summary, per-deck/stake tables, a joker lookup, the list of recent runs, and Export buttons.

## SeedOracle (T-110): new mod `mods/SeedOracle`, modules `seedoracle.*`

- Opened by an Options/pause button and a hotkey (`o` held with `ctrl`), in a run only. It recomputes on `shop_enter`, `blind_selected`, `blind_skipped` and `ante_change` (throttled: at most once per 0.5 s, and never in the sim).
- *(Amended after wave C: `predict.plan` is only valid on a fresh S, and on a captured mid-run S it silently redraws ante 1.)* There are two sources:
  - **Stable fields** (tags, boss, voucher, Soul legendaries) come from `predict.plan(state.fresh(G.GAME.pseudorandom.seed, {stake, deck}), {antes = 8, shops_per_ante = 1, open_packs = false})` with the shops discarded (plan requires 1..3; shops come after each ante's stable draws, so the stable fields are unaffected), computed once per run. Antes before the current one are hidden. A boss that the live run rerolled (Director's Cut, Retcon, Boss Tag), or any stable field that differs from the live `G.GAME` for the current ante, is shown with a "changed in this run" badge, and later bosses are marked conditional.
  - **Conditional fields** (the current and next shop cards, rerolls, packs, pack contents) come from `state.capture()` of the live run through the lower-level `predict.shop/reroll/packs/pack_contents`, which continue from the live stream positions (these streams are keyed by ante). They are labelled "if nothing else consumes the stream first".
- Overlay: one tab per ante (current + next 2). Each tab shows skip tags, boss, voucher, shop cards (+2 rerolls), packs and pack contents, drawn as real card sprites with the SaveSlots preview technique (display-only cards, no live side effects). The Soul/legendary sequence is marked. Every item shows a **stable** or **if…** (conditional) badge.

## SeedFinder (T-111, T-112, T-113): new mod `mods/SeedFinder`, modules `seedfinder.*`

- **Filter model (T-111):** `{name, stake = 1, deck = 'b_red', all_unlocked = false, antes = N, clauses = {{kind, ante?, ...}}, mode = 'all'|'any'}`. Clause kinds:
  - `tag {ante, blind = 'Small'|'Big'|'any', key}`
  - `boss {ante, key}`
  - `voucher {ante, key}`
  - `legendary {index = 1|2, key?}`
  - `soul_in_pack {ante, pack = 'arcana'|'spectral', from_tag = bool}`. When one ante has a `from_tag` clause and any shop clause, the two are one playthrough: the Charm/Ethereal blinds are skipped (so their shops never happen) and tag packs and shop packs are drawn in play order on the same state, because a tag pack and a shop pack of one kind share the ante's streams. Other antes keep tag packs and shops as separate branches.
  - `shop_joker {ante, key, rerolls = 0..}`
  - `pack {ante, key_prefix}`

  `filter.validate(f)` → `true` or `nil, err`. `filter.eval(S, f)` → `bool, details`. It short-circuits cheapest-first (tags → boss → voucher → legendary → packs → shop). `filter.serialize`/`deserialize` round-trip through STR_PACK (filters hold no floats).
- **Engine (T-112):** `engine.start(f, {workers = 1..8, max_seeds, stop_after = k})` → a handle; `engine.poll(h)` → `{scanned, rate, found = {seed…}, done}`; `engine.cancel(h)`. Workers are love.threads using the T-104 approach, with prototype data sent once. **Soundness:** every seed the workers report is re-checked on the main thread with `filter.eval(state.fresh(seed, …))` before it's reported. Throughput gate: ≥ 2,000 seeds/s for a tag + Soul filter with 4 workers.
- **UI (T-113):** Options/pause "Seed Finder" and the main-menu Play → a "Find" tab. A clause-list builder (add/remove clauses; cycles for kind, ante, key), a start/cancel button with live rate and progress, and a results list with **Play** (starts a run on the seed, unseeded like Brainstorm's reroll so it counts for unlocks and stats) and **Save as hunt** (a SaveSlots `kind = 'hunt'` entry once the run's first autosave exists, with `origin.filter`).
