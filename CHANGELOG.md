# Changelog

## 0.3.4 — 2026-09-28

Organise your filters and saves.

- **Seed Finder: name your filters.** **Rename** sets a name that sticks when you change the clauses; clear the name to get the generated one back. **Save as** makes a copy of the current filter to tweak, leaving the original as it was. Hunts and the Run Journal show the name you gave.
- **Save Slots: folders.** Give a save a folder from its details (type a new one or pick one you use). The folder cycle next to the kind cycle lists one folder at a time, or the saves in no folder. Auto-checkpoint pruning keeps a checkpoint you filed.
- **Save Slots: search.** A search box matches a save's name, seed, deck, notes, target or folder as you type.
- **Fix: typing `0` in the suite's text boxes gave `o`.** The game's text box is built for seeds, which have no zero. Save names, notes, folders, search and filter names now keep the digit.
- Save Slots: "Save current run" is now a **Save** button beside the name box, which makes room for the folder cycle and the search box.
- Under the hood: `make lovely-check` types into the new boxes under Steamodded and next to HandyBalatro, which both change how the game's text boxes are built.

## 0.3.3 — 2026-09-28

Two fixes for games with Steamodded.

- **Fix: under Steamodded, the Oracle failed on the Zodiac, Painted, Anaglyph, Plasma and Erratic decks** with "attempt to concatenate local 'v' (a function value)". Steamodded adds a function to these five decks that the simulator could not copy. The Finder's check of a hit on these decks failed the same way.
- **Fix: under Steamodded, Save Slots could not preview a save made before Steamodded was installed** if one of its cards had an edition ("attempt to perform arithmetic on field 'card_limit'").
- Under the hood: `make lovely-check` plans every deck under Steamodded and previews a pre-Steamodded save (`lovely_preview_smods`).

## 0.3.2 — 2026-09-26

The Seed Finder and Oracle do much more under Steamodded, now that their predictions were checked against the real Steamodded game.

- **Fix: under Steamodded, every prediction made while the Oracle or Seed Finder was open was random.** Steamodded makes the game's seeded RNG return random numbers while the game is paused, and both windows pause it. So the Oracle showed wrong tags, bosses and Vouchers, and the Finder rejected every correct hit ("14 of 14 found hits failed the check"). The predictions now run unpaused.

- **Under Steamodded, the Finder searches card clauses** (shop Jokers, packs, the Soul in a pack, which legendary the Soul makes), not only tags and Vouchers. Boss clauses and edition requirements are still left out.
- **Under Steamodded, the Oracle previews shops, packs and The Soul again.** Editions are left out and later bosses are marked unverified, because Steamodded rolls editions and picks bosses its own way.
- Fix: under Steamodded, Finder searches that involve packs failed with "not a pack". The search threads lost the booster packs, because Steamodded turns them into objects of its own classes.
- The Finder says how many found hits failed its check, and each search leaves a summary line in the lovely log.
- Under the hood: 255 predictions checked against the real Steamodded game (20 Soul legendaries, 83 pack contents, 68 shop rows and rerolls, plus tags and Vouchers) all matched on which card appears. `make lovely-check` now runs these golden suites under Steamodded.

## 0.3.1 — 2026-09-26

Works alongside other mods.

### Fixes
- **The Seed Finder could not search whenever Steamodded was installed.** It failed with "Search failed: … attempt to index global 'SMODS'". The search threads now run the game's own code, not another mod's patched copy of it.
- Search and Odds failures show a short, readable message. The full error goes to the lovely log.
- Save Slots practice scenarios set the round's Voucher the way Steamodded's shop expects.

### With other mods
- **Steamodded** lists the suite in its Mods menu as "Balatro Seed Suite" by r-metal.
- **Under Steamodded**, the Oracle shows tags, bosses and Vouchers. Bosses are marked unverified, because Steamodded picks them its own way. Shops, packs and The Soul aren't previewed, and the Finder searches tag, boss and Voucher clauses only. A note in both says so.
- **With content mods**, meaning mods that add cards to the pools such as Pokermon, the Oracle and Finder switch off and say why, instead of showing predictions that don't apply.

### Under the hood
- A second test rig runs the real lovely (its Linux build) with Steamodded and Pokermon: `make lovely-check`.

## 0.3.0 — 2026-09-26

The first public release. The suite installs as a single lovely mod: put `BalatroSeedSuite.zip` into `Mods/` (no unzipping), or unzip it there as one `BalatroSeedSuite/` folder.

### Seed Finder
- **Route panel.** Each hit has a Route button listing the exact plays that deliver it, ante by ante: which blind to skip or play, which pack to open, when to use a Soul, and how many rerolls. A test plays a real hit by following only its route.
- Hits are ranked by what they cost to deliver (antes, rerolls, money), with a compact cost on each row; edition filters in the filter engine (Negative / Polychrome / Holographic / Foil / any) for shop jokers and the Soul's legendary (the editor UI is coming).
- **Odds.** An Odds button samples 20,000 seeds on the workers and says roughly how rare a hit is and how long a search should take, which clause is the bottleneck, and when a clause never passes (impossible or locked). A live "hits per million" stat while searching. The overlay no longer widens when hits appear.
- **"Joker by ante N" filter** (shops with a reroll budget and/or Buffoon packs), proven in the real game; the editor UI is coming.
- **Play starts an unseeded run** on the hit's seed, the way Brainstorm's reroll does, so it counts for unlocks, stats and high scores. It was a seeded run before.
- **Tag-skip Soul + shop Soul in one ante now means one playthrough.** A filter asking for both (say, a Charm Tag Soul and a shop Arcana Soul in ante 1) used to check each on its own copy of the seed, so many hits could not deliver both: the tag pack and a shop pack of the same kind share the ante's random streams, and the shop after a skipped blind never happens. Such antes are now walked in play order (skip the Charm/Ethereal blinds, open tag packs at the skip, shops in between). Checked against the real game by a new rig scenario. Take the first Soul by using it before opening the shop pack: no Soul rolls while one exists.
- The joker lists (shop joker, legendary) are in alphabetical order.
- Fix: a filter whose ante 1 skips both blinds put the run's forced first Buffoon in the wrong shop.

### Seed Oracle
- **What-if toggles.** Per ante: Skip Small, Skip Big and rerolls 0-5. The tab re-predicts the shops, packs and tag packs as they would happen, without touching the run.
- **Divergence banner.** When the live shop stops matching the prediction, the Oracle says where, what it expected, what it saw and the likely cause (a purchase, a used card...), then re-predicts from the run as it is.
- A later ante's tab follows the skips chosen in earlier antes.
- Pack contents follow the order packs are opened, not their slot: each pack now reads "1st opened holds" / "2nd opened holds" instead of "Holds".

### Save Slots
- **Share codes.** Share copies a code (seed, deck, stake, notes, filter); Import code shows it and plays it as an unseeded run.
- **Favorites.** A Favorite / Unfavorite toggle in the details column pins a slot: favorites list first (gold dot), a new Favorites filter shows only them, and auto-checkpoint pruning never deletes a favorite. Stored as additive `meta.favorite`, so older builds read the index unchanged.
- **Blind HUD after a load.** Resuming a run mid-blind on a blind that pays $0 (Small Blind at Red stake and up) left the blind panel off screen, with no blind name, score target or reward. This is a vanilla bug that the Continue button hits too, but slot loads and checkpoints made it common. Any load now brings the panel back.

### Run Journal
- **Same seed tab.** Runs of one seed side by side, ante by ante, with where they diverged.
- **Hunts tab.** How each Finder filter's runs went: runs, wins, best ante.

### bh-core and the suite
- **A missing bh-core no longer stops the game from booting.** A mod installed without bh-core, or next to one from another release, stays off, and the main menu says what is missing.
- A native (C) seed simulator, 68x faster per thread than the Lua one and matching it exactly on 1,000,000 seeds (not wired into the Finder yet); odds sampling on the Finder's workers; share-code encoding.
- The test rig runs at low CPU priority, so a game being played keeps its frame rate.

## 0.2.0 — 2026-09-23

The suite grows from one mod to five. Everything is Lovely-only, and every new mod needs **bh-core**.

### bh-core (new)
- **Seed simulator.** It predicts what vanilla will generate for a seed: skip tags, bosses, vouchers, the Soul's legendaries, shop cards per reroll, packs and pack contents (Soul/Black Hole included), and stake stickers, editions and seals. It calls the game's own Card-free generation functions inside a sandbox that never touches the live run, plus a Card-free twin of `create_card` that makes the same draws in the same order.
- **Proven against the real game:** golden suites play 10 real seeded runs each (stable streams: 30 antes + 10 Souls; shops: 60 shops, 120 rerolls, 120 opened packs, 3 seeds at Gold stake) and a 1,500-draw differential of `create_card`. Everything matches exactly, including the RNG state afterwards.
- Game event hooks (run start, blind selected/skipped, hand scored, round end, shop, ante change, run end), and verified crash-safe storage (moved out of SaveSlots).

### SeedOracle (new)
- In-run overlay (Options/pause, `ctrl+o`): the current ante and the next two, with tags, boss, voucher, Soul legendary, and the next shop's cards, rerolls, packs and pack contents drawn as real cards. Each item is badged **stable** or **if…**.

### SeedFinder (new)
- A filter builder (tags per blind, boss, voucher, legendary, Soul in a Charm/Ethereal pack, shop jokers, packs; all/any). The search runs on worker threads: **~53,000 seeds/s** for Charm Tag + Soul on 4 workers. Every hit is re-checked before it's shown. Play a hit, or save it as a SaveSlots hunt. Filters persist.

### RunJournal (new)
- A local log of every run (antes, blinds, skips, hands and scores, jokers seen, outcome). Stats by deck, stake and joker; CSV/JSON export.

### SaveSlots 0.2
- Auto-checkpoints: one per ante, the last 8 per run, 3 runs kept.
- Practice scenarios: compose deck, stake, ante, money, jokers, consumables and hand levels into a real run.
- Seed-hunt entries, target/notes per slot, and a kind filter. 0.1.0 slots load unchanged.

### Development
- The repo is now a multi-mod suite (`mods/`). The smoke rig loads every mod the way lovely does, and runs scenarios 4 in parallel.
- `make check`: lint (76 files), 249 unit tests, and 21 smoke scenarios against the real game code, including the golden suites and a suite-coexistence scenario (every Options button exactly once, tabs intact, no leaks).

## 0.1.0 — 2026-09-23

First release of **SaveSlots**, a Lovely-only Balatro mod for named save slots.

### Added
- **Save Slots screen**, reachable from the pause menu, from Options on the main menu, and from a new **Saves** tab on the Play screen (the 3 most recent saves plus "Open Save Slots").
- Save the current run under a name. The save is the game's last autosave point, the same point Continue would resume from. Overwrite, rename, and delete (press twice), with a paged list of 8 per page, newest first.
- **Preview panel**: deck back, stake, ante/round/money/hands/discards, seed, where the run was saved (shop, blind select…), game version, and the run's jokers, consumables and vouchers drawn as real cards with their editions, stickers and tooltips.
- **Load** resumes the saved run and also makes it the main-menu Continue run.
- Brainstorm's `saveState1-5.jkr` are imported once as "Brainstorm slot N". The originals are never touched.

### Robustness
- Crash- and disk-full-safe storage in `<profile>/saveslots/`. Every write is staged and verified by reading it back; a torn file falls back to its verified `.tmp`; the index rebuilds itself from slot files if it's lost; a failed save or overwrite leaves the list and the saves exactly as they were. The verifier checked this with 785 fuzzed crash runs.
- Saving is refused (with a message) until the current run has a real autosave point. It never falls back to a stale snapshot from a previous run.
- Previews never touch the live run: RNG state, `used_jokers`, and joker/consumable slot limits are all protected.

### Fixed (in the installed Brainstorm mod, outside this repo)
- Saving a state before the first autosave no longer crashes (`string_packer.lua:70`).
- Loading an empty `x+N` slot no longer wipes the current run.

### Development
- `make check`: lint, 109 unit tests (including independent adversarial suites), and 5 smoke scenarios that run the real game code headless on native LÖVE 11.5 with an isolated save dir.
- `make install`, `make dist`.
