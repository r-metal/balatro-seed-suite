# SaveSlots — spec and roadmap (plan of record)

Last updated: 2026-09-23 (v0.1.0 released; T-009 real-game check waits for the maintainer)

## Status overview

### Phase 0 — scaffold and test rigs
- [x] Repo initialized, spec + README written
- [x] Skeleton: `lovely.toml`, `init.lua`, module stubs, `Makefile`, unit-test runner (orchestrator)
- [x] T-001 Smoke rig (the adversarial verifier passed; 7 kinds of planted failure caught): the game running on native LÖVE 11.5, headless, with the mod loaded and a scripted scenario → PASS line + screenshot (guard task)

### Phase 1 — core modules
- [x] T-002 `store.lua` (after 2 refutations and a re-plan into T-002a/b/c; the final verifier passed 785 fuzzed crash runs): named saves on disk, index, summaries, Brainstorm import, with unit tests
- [x] T-003 `checkpoint.lua`: tracks the last safe snapshot, loads a run (also writes `save.jkr`), with unit tests
- [x] T-004 Brainstorm: loading an empty `x+N` slot no longer wipes the run (edit to the installed mod, outside this repo)

### Phase 2 — UI
- [x] T-005 `preview.lua`: preview panel (deck sprite, stats, jokers/consumables/vouchers drawn as cards)
- [x] T-006 `ui.lua`: Save Slots overlay (paged list, name input, save/overwrite/rename/delete-with-confirm/load)
- [x] T-007 `entry.lua`: "Save Slots" button in Options/pause menu + "Saves" tab on the Play screen

### Phase 3 — ship
- [x] `make install` copies the mod into the Proton prefix's `Mods/SaveSlots`
- [x] Full smoke run green: save → list → preview → load round-trip
- [x] Release v0.1.0: `CHANGELOG.md`, `make dist` → `dist/SaveSlots-0.1.0.zip`, tag `v0.1.0`
- [ ] **Real-game check under Proton + lovely — needs the maintainer to restart Balatro** (a second instance would share the same prefix and saves)

## Goal

Keep many named Balatro runs and pick any of them to resume. Browse them in a
list with a preview rich enough to recognise a run at a glance: deck, stake,
ante/round, money, seed, the point the run was saved at, and the jokers,
consumables and vouchers drawn as real cards.

## Locked decisions (kickoff 2026-09-23)

| # | Decision |
|---|---|
| D1 | A standalone lovely mod (`Mods/SaveSlots`), not a Brainstorm patch, so Brainstorm updates don't overwrite it. |
| D2 | Entry points: a **"Save Slots"** button in the Options overlay (the same function builds the main-menu Options and the in-run pause menu), and a **"Saves"** tab on the Play (run setup) screen, shown only on the main menu. The tab lists the 3 most recent saves as quick-load buttons plus an "Open Save Slots" button. |
| D3 | **Loading a slot also writes it to `save.jkr`**, so main-menu Continue matches the run you last loaded. |
| D4 | **Brainstorm's `saveState1-5.jkr` are imported once** per profile as "Brainstorm slot N". The originals are copied, never moved or deleted. |
| D5 | Brainstorm's z/x hotkeys stay. The empty-slot load bug gets fixed (T-004). |
| D6 | **What gets saved** is the last safe snapshot the game itself produced (`save_run()` output), never a mid-animation state. Where no snapshot exists yet this run, saving is refused with an on-screen message. It never falls back to `save.jkr` or a stale `G.ARGS.save_run` (see Traps). |
| D7 | Storage: `<profile>/saveslots/<id>.jkr` (the same compressed format as `save.jkr`, so a slot file can be dropped in as `save.jkr` by hand) plus `<profile>/saveslots/index.jkr` (names, timestamps, summaries), all through `love.filesystem`. |
| D8 | Lua 5.1 / LuaJIT only. No dependency on Steamodded. Lovely `module` patches let the files `require` each other; no nativefs. |
| D9 | Commit after each wave; verification posture **standard**. |

## Architecture

```
SaveSlots/
  lovely.toml          registers modules, appends `require('saveslots.init')` to main.lua
  src/init.lua         SaveSlots global; requires modules; installs hooks once
  src/store.lua        disk: list/read/save/rename/delete, summaries, Brainstorm import
  src/checkpoint.lua   hooks save_run + Game:start_run; get(); load_run()
  src/preview.lua      build(run, summary) -> UIBox definition for the right-hand panel
  src/ui.lua           the overlay: G.FUNCS.saveslots_open and every button callback
  src/entry.lua        hooks create_UIBox_options + G.UIDEF.run_setup
tests/                 unit tests (plain LuaJIT, stubbed love/G), `make unit`
rig/                   smoke rig: native LÖVE 11.5 running the real game source + the mod, headless
```

### Module contracts (locked, and every implementer codes against them)

`require('saveslots.store')` returns `store`:
- `store.list()` → array of `{id, name, saved_at, summary}` sorted by `saved_at` descending. Empty array when there are none.
- `store.read(id)` → the run table (as passed to `G:start_run{savetext=...}`), or `nil, err`.
- `store.save(run, name, id?)` → id. With no `id` it creates a new slot. With an `id` it overwrites that slot's run and summary and refreshes `saved_at`, keeping the name unless `name` is non-empty.
- `store.rename(id, name)` → true, or `nil, err`. `store.delete(id)` → true, or `nil, err`.
- `store.summarize(run)` → `{deck, stake, ante, round, dollars, seed, state, hands, discards, version, jokers}`. `deck` is the back's name, `state` is the `G.STATES` key name (e.g. `SHOP`), and `jokers` is the count.
- `store.import_brainstorm()` → the number imported. It is idempotent via a flag in the index.
- The id is a string derived from `os.time()`, made unique within the index.

`require('saveslots.checkpoint')` returns `checkpoint`:
- `checkpoint.install()` runs once. It wraps the global `save_run` (after the original returns, the latest snapshot is `G.culled_table`) and `Game.start_run` (clears the snapshot; when `args.savetext` is present, stores a **deep copy** of it before the original runs).
- `checkpoint.get()` → the snapshot table or `nil`.
- `checkpoint.load_run(run)` writes `run` to `<profile>/save.jkr` (D3), closes any overlay, and calls `G.FUNCS.start_run(nil, {savetext = run})`.

`require('saveslots.preview')` returns `preview`:
- `preview.build(run, summary)` → a `G.UIT.ROOT` definition. Cards are rebuilt from `run.cardAreas.jokers.cards`, `run.cardAreas.consumeables.cards` and `run.GAME.used_vouchers`. Centers missing from `G.P_CENTERS` (e.g. from a removed mod) are skipped, never an error.

`require('saveslots.ui')` returns `ui`:
- `ui.install()` registers `G.FUNCS.saveslots_*`. `G.FUNCS.saveslots_open(e)` opens the overlay; `e` may be nil.

`require('saveslots.entry')` returns `entry`:
- `entry.install()` wraps `create_UIBox_options` and `G.UIDEF.run_setup`.

### Smoke rig contract (locked; T-001 builds it, later tasks write scenarios)

- `rig/smoke.sh <name|all>` runs `rig/scenarios/<name>.lua` inside the real game
  (sources from `build/game`, native LÖVE 11.5 from `tools/`, headless via
  `headless-run`). It loads the mod **the way lovely does**, by parsing
  `SaveSlots/lovely.toml`: module patches become `package.preload` entries and
  the `main.lua` append runs at the end of `main.lua`.
- Isolation: every scenario gets a fresh save directory under
  `build/smoke/<name>/home` (via `XDG_DATA_HOME`). The rig marks the tutorial
  complete. It never reads or writes the Proton prefix.
- A scenario returns an array of steps `{name=, run=function(ctx) ... end, timeout=10}`.
  Steps start once the main menu is up. `run` returning truthy completes the step;
  falsy retries next frame until `timeout` seconds pass, which FAILs; an error FAILs.
- `ctx` provides: `ctx.shot(label)` (writes `build/smoke/<name>/<label>.png`),
  `ctx.log(msg)`, `ctx.assert(cond, msg)`, `ctx.find_button(button_name[, id])`
  (the first UIElement whose `config.button == button_name` in any live UIBox,
  optionally matching `config.id`), `ctx.click(button_name[, id])` (calls
  `G.FUNCS[button](elem)`, returns true if found), and `ctx.start_run(args)`
  (a new run from the menu).
- The last line of output is exactly `SMOKE PASS <name>` or
  `SMOKE FAIL <name>: <reason>`, and the exit status matches. `all` runs every
  scenario except `selftest_*` and fails if any one fails. A hard wall-clock
  timeout (120 s per scenario) kills the game and FAILs.

## Traps (why the decisions above look the way they do)

- **`G.ARGS.save_run` is never cleared.** It survives quitting to the menu and starting another run. Saving from it before the new run's first autosave would store the *previous* run. That is why D6 tracks the snapshot itself and resets it in `start_run`.
- **`start_run` keeps the table it loads from.** `G.GAME = saveTable.GAME` by reference, so the loaded table mutates as you play. Anything kept from `args.savetext` must be deep-copied first (`STR_UNPACK(STR_PACK(t))`).
- **Brainstorm's save crash.** `compress_and_save(path, nil)` crashes in `love.data.compress`. Guard every write.
- **Loading from the shop** logs `Card area 'shop_*' not instantiated before load`. That also happens in vanilla and is harmless.
- **Save format is versioned.** Vanilla refuses saves with `VERSION < '0.9.2'`. Show `version` in the preview, and don't block loading on it.
- **Preview cards are live `Card` objects.** A few jokers recompute tooltip numbers from the *current* run's `G.playing_cards` while displayed. That is cosmetic and accepted.
- **Game source is not ours.** The rig extracts `Balatro.exe` into `build/` (gitignored) at run time. No game code is ever committed.
