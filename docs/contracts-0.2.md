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

### SaveSlots 0.3.4: folders and search (T-361, added 2026-09-28)

Additive, like 0.2. The index version stays 1, and a 0.3.3 build reads an index with folders unchanged (it ignores the field).
- `meta.folder` is an optional string: trimmed and capped at `store.FOLDER_MAX = 16`, and `''` clears it, as with target and notes (`set_meta`, or `save`'s meta). A non-string folder is refused with `nil, err`, and nothing is written. An overwrite and a rename keep it. Folders are local organisation, so share codes never carry them.
- `store.list(filter)` takes two more fields. Every field given is ANDed with `kind` and `favorite`:
  - `folder = '<name>'` keeps only that folder, matched case-sensitively after trimming. `folder = false` (or a blank string) keeps only the slots with no folder. A 0.1.0 entry (no meta) counts as unfiled.
  - `query = '<text>'` keeps the entries whose name, `summary.seed`, `summary.deck`, `meta.notes`, `meta.target` or `meta.folder` contains the text. The match is a case-insensitive plain substring (`string.find(s, q, 1, true)`, never a Lua pattern), and the query is trimmed first. A blank query filters nothing.
- `store.folders()` → the distinct folders of the listed slots, sorted case-insensitively.
- `store.prune_checkpoints` keeps a checkpoint that has a folder, as it keeps a favorite: filing one is an explicit keep.
- **UI:**
  - A folder cycle sits beside the kind cycle: `All folders`, each folder, then `Unfiled`. Its arrows are `saveslots_folder_cycle` and its callback is `saveslots_folder`. It ANDs with the kind cycle, and it falls back to `All folders` once its folder has no slot left.
  - The meta column has a Folder block with Edit (`saveslots_edit_folder`). The editor takes the preview's place: a text input (`FOLDER_MAX`), the folders in use as buttons (`saveslots_folder_pick`, up to 12; one click fills the input), and Save / Cancel. Return saves, and empty clears the folder.
  - A search input sits after the name input. The name input stays the first `select_text_input`, and the page cycle stays the first `option_cycle`. Typing swaps only the list and the page cycle (back to page 1), never the whole overlay. With no match the list reads `No saves match "<q>"`, and the query survives rebuilds for the session.
  - Every text input in the overlay sets `bh_digits = true` (`BHCore.install_digits`, docs/bh-core.md § Text inputs).
  - The overlay keeps one outer size in every state and fits `G.ROOM`.
- Proofs: `tests/test_store_folders.lua` and the `saveslots_folders` scenario.

### SaveSlots 0.4.0: profile backups (T-374, added 2026-09-28)

New module `saveslots.backup`; the full API is in its header. In short:
- **What a backup holds:** the profile's progress files, `<profile>/profile.jkr` and `<profile>/meta.jkr`, copied byte for byte into `<profile>/saveslots/backups/<stamp>-<kind>/`, with a `backup.jkr` manifest written last. A folder without a manifest is no backup, and the next take sweeps it.
- **What it never holds:** save.jkr, Save Slots' own slots or the Journal.
- **When backups are taken:** one `'auto'` backup the first time a profile loads each day, once the game's pending writes are on disk. The newest 7 autos are kept. `'manual'` backups are never pruned.
- **API:** `take(kind[, reason])`, `list()` (newest first), `delete(id)`, `can_restore()`, `restore(id[, on_done])`, `when_settled(fn)`, `settled()`, `step()`, `install()`, `valid_id(id)`. None of them raise.
- **Restore** works from the main menu only, with two presses in the UI. It:
  1. waits for pending profile writes;
  2. takes a `'manual'` safety backup (reason `'before restore'`);
  3. writes the backup's files through bhcore.fs, putting the safety copy back on any failure;
  4. reloads through vanilla's own profile switch with a data reset (`G.focused_profile = G.SETTINGS.profile`, then `G.FUNCS.load_profile(true)`).

  Vanilla's `load_profile` merges file keys into memory, and `save_progress` writes memory back out, so writing the files alone would be undone by the next save.
- **UI:** a **Backups** button beside Import code opens a panel in the preview's place, with a list, **Back up now**, **Restore** (the first press arms "Confirm restore") and **Delete**. The overlay keeps its outer size.
- **Proofs:** `tests/test_backup.lua`, and the `saveslots_backup` scenario. The scenario checks that memory, and the files after the game's next `save_progress`, equal the backup.

## RunJournal (T-123, T-125): new mod `mods/RunJournal`, modules `runjournal.*`

- Subscribes to bh-core events only. Per run it writes `<profile>/runjournal/<file>.jkr` (bhcore.fs) plus `index.jkr`, where `run_id = <seed>..':'..<start os.time>`. *(Amended after wave D: the file name replaces `:` with `_` because `:` is illegal on Windows/Proton, and the time part of the id is bumped past a same-second collision; `started_at` keeps the real time.)* A loaded run continues its record (match the seed and the latest unfinished record).
- Record: `{run_id, seed, deck, stake, started_at, ended_at?, won?, final_ante, final_round, antes = {[a] = {dollars_start, dollars_end, blinds = {{kind, key, skipped, tag?, hands = {{hand, chips, mult, score}}, won}}}}, jokers_seen = {keys at each shop_enter}, origin = {filter_name?}}`. Writes happen at `round_end`, `shop_enter` and `run_end`, never per frame.
- `runjournal.stats(filter?)` → `{runs, wins, win_rate, by_deck = {...}, by_stake = {...}, by_joker = {[key] = {runs, wins}}}`. "Build archetype" in 0.2.0 means the joker set at the run's end, grouped by any user-selected joker key.
- `runjournal.export(fmt)` with `fmt = 'csv'|'json'` writes `<profile>/runjournal/export-<os.time>.<fmt>` and returns the path. CSV has one row per run.
- UI (T-125): a "Run Journal" button in Options/pause, and an overlay with the stats summary, per-deck/stake tables, a joker lookup, the list of recent runs, and Export buttons.

### RunJournal 0.4.0: run flags (T-370, added 2026-09-28)

Additive record and index fields, so stats can leave runs out (T-371) without reading every record. The index version stays 1. A record or an index entry without the new fields counts as a normal run: nothing rewrites an old record or index on load; an entry gains the fields when its run is next written, and a rebuilt index derives them from the records.
- Record fields:
  - `seeded` (boolean): `G.GAME.seeded == true` as the run is actually played. The Finder's Play and Save Slots' Import Play clear `seeded` *after* `start_run` returns, but bh-core's `run_start` fires inside `start_run`, where it is still true. So the recorder sets it on every write of the live record (`round_end`, `shop_enter`, `run_end`), never at `run_start`; until the first write the live record has none. A loaded run's `seeded` comes back with its save, so its record keeps its value.
  - `challenge` (string or nil): `G.GAME.challenge`, the challenge id. Set at `run_start` and refreshed on every write.
  - `endless` (boolean): false until a round ends after the run was won, then true for good. The winning round itself is not endless: `run_end` (won) and its `round_end` can fire in either order, so the recorder compares round numbers. A run loaded with `G.GAME.won` already true counts from its next round. `won` stays true through endless, as before.
  - `origin` grows: `recorder.set_origin(o)` keeps `filter_name` (any string), `kind` (`'finder'` | `'daily'` | `'import'`), `date` (`'YYYY-MM-DD'`) and `mode` (`'blind'` | `'routed'`). Any other key, a non-string value and a value outside those sets is dropped. The Finder's Play keeps calling `set_origin{filter_name = ...}`; an origin with a `filter_name` counts as `kind = 'finder'`.
- Index entries carry `seeded` (boolean), `challenge` (id or nil), `endless` (boolean), `finder` (boolean: `origin.filter_name`, or `origin.kind == 'finder'`) and `daily` (boolean: `origin.kind == 'daily'`). Entries still carry no `origin` table. `recorder.save(record)` derives them from the record it is given, so a synthetic record without them is a normal run.
- Proofs: `tests/test_runjournal_flags.lua` and the `runjournal_flags` scenario.

### RunJournal 0.4.0: stats filters and the Jokers tab (T-371, added 2026-09-28)

Research pick [21]. By default the Journal's screen counts normal runs only; toggles bring the others back. Additive: a bare `runjournal.stats()` and the 0.3 table filters count every run as before.
- **Kinds.** `stats.kind_of(run)` gives a run one kind, the first that applies of `'daily'`, `'finder'`, `'challenge'`, `'seeded'`, else nil (normal). It reads an index entry's T-370 flags, or derives them from a record the way the recorder derives an entry's. A daily run is seeded too, and still only the Daily toggle shows it. An entry without flags (recorded before 0.4.0) is normal, and so is an endless run.
- **The filter.** `stats.compute(filter)`'s table filter gains `include = {seeded, finder, challenge, daily}` (booleans), beside `deck` and `stake`. With `include` present, a kind whose field is missing or false is left out. Without `include`, nothing is left out. `stats.DEFAULT_FILTER = {include = {seeded = false, finder = false, challenge = false, daily = false}}`; `stats.KINDS` lists the fields.
- **The endless reload.** Reloading a won endless run starts a new record whose `won` is nil (T-370's known gap). An entry with `endless = true` and `won` not true counts in `unfinished`, never as a loss, in every call.
- **`stats.jokers(filter?, runs?, read?)`** gives one row per joker key seen in a counted run (finished and passing the filter), at its end or at any shop: `{key, runs, wins, win_rate, held, lifespan}`. `runs`, `wins` and `win_rate` are counted as `by_joker` counts them (the run's end set). `held` counts the runs where a `jokers_seen` snapshot has the joker. `lifespan` is the mean number of shops it was held, over those runs (nil when `held` is 0). Every key is listed, not a top N. `runs` defaults to `recorder.list()`, and an entry's record is read through `read` (default `recorder.read`; the UI passes a per-open cache). `stats.sort_jokers(rows, by, name_of?)` sorts by `'runs'`, `'win_rate'` or `'lifespan'`, highest first, ties by name.
- **`stats.by_filter`** (Hunts) takes no filter: hunts are Finder runs by definition.
- **UI.**
  - A filter bar tops Overview, Decks/Stakes and a new **Jokers** tab (after Decks/Stakes). It holds toggles Seeded, Finder, Challenge and Daily (off: hidden), a deck cycle (All, then each deck in the index) and a stake cycle (All, then 1-8).
  - The bar keeps one state for the session, starting from `DEFAULT_FILTER`. A change recomputes the numbers, and the Overview's joker lookup follows it.
  - The Jokers tab is a paged table (name, runs, wins, win rate, held, lifespan) with a Runs / Win rate / Lifespan sort.
  - Six tabs fit the width of the old five: their buttons are narrowed, and ids and labels are unchanged. The overlay keeps one outer size (15.74 x 9.45 in the rig's 20 x 11.5 room) on every tab and in every filter state.
- Proofs: `tests/test_runjournal_filters.lua` and the `runjournal_filters` scenario.

### RunJournal 0.4.0: the daily list and the pick rate (T-378b, added 2026-09-28)

Closes research picks [25] (the daily seed's runs in the Journal) and T-372 (pick rate when offered). Additive: `stats.compute()` returns what it returned before, with or without a filter.
- **`stats.dailies(runs?, read?)`** lists the daily seed's runs, newest first (`started_at`, then `run_id`). A run is daily when it is a record whose `origin.kind == 'daily'`, or an index entry with `daily = true` (T-370). Several runs of one date are each listed; nothing is collapsed. Each row is `{run_id, date, mode, seed, deck, stake, won, final_ante, started_at, ended_at}`:
  - `date` is `origin.date` (the UTC day the seed was picked for), else the UTC date of `started_at`;
  - `mode` is `origin.mode` (`'blind'` | `'routed'`), else nil;
  - `won` is true (won), false (finished without a win) or nil (unfinished; the endless reload counts as unfinished, as in `compute`).

  Entries carry no origin, so a daily entry's record is read through `read` (default `recorder.read`); only daily entries are read. An unreadable record keeps its row, with the date from `started_at` and no mode. It takes no filter.
- **`stats.jokers`** rows gain `offered`, `picked` and `pick_rate`:
  - `offered` counts the runs whose record's `offered` (T-372a) has the joker;
  - `picked` counts those where it was also held at some shop (a `jokers_seen` snapshot has it, as `held` counts);
  - `pick_rate = picked / offered`, nil when `offered` is 0.

  They count only runs whose record has an `offered` table (0.4.0 or later). An older run still counts in `runs`, `wins` and `held`, never in the pick rate. A joker only offered, never held or kept, now gets a row too (`runs = 0`). `stats.sort_jokers` also sorts by `'pick_rate'`; a nil sorts last, and ties go by name.
- **UI.**
  - A seventh tab, **Daily**, after Hunts: date, Blind / Routed, seed, deck and result (`Won`, `Ante N` for a run lost at ante N, `Unfinished`), 7 per page with a page cycle (`runjournal_dpage_cycle`). It reads "No daily runs yet" when there are none. The list is not filtered: the bar's Daily toggle only decides whether daily runs count in the other tabs' numbers.
  - The Jokers table gains a **Pick** column: a percentage, or `-` when no counted run has offered data for the joker. The sort cycle gains **Pick rate**.
  - The tab row stays 14.75 wide, as with six tabs. Instead of one narrowed width, each tab button is fitted to its label: the narrow ones share one width and the wide ones hug their label. Every label keeps vanilla's tab text scale (0.5). With six equal buttons, 'Decks/Stakes' had been drawn at about 0.7 of it. Tab ids and labels are unchanged (`tab_but_<label>`).
  - The overlay keeps its outer size (15.74 x 9.45 in the rig's 20 x 11.5 room) on all seven tabs.
- Proofs: `tests/test_runjournal_daily.lua` and the `runjournal_daily` scenario.

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
- **Filter names (T-360, added 2026-09-28):** a filter may carry `named = true` (additive; `filter.validate` ignores it), meaning the player typed `name`, and the generated name no longer overwrites it. A blank name clears `named` and brings the generated name back. The filter panel gains **Rename** (`seedfinder_rename`: an input with `bh_digits`, max 30 chars, with Save `seedfinder_name_save` / Cancel `seedfinder_name_cancel`; Return saves) and **Save as** (`seedfinder_save_as`: a deep copy of the current filter inserted after it and made current, with the name editor open). Hunts, share codes and RunJournal's per-filter stats use `f.name` as before, so a typed name shows up there as it is.
