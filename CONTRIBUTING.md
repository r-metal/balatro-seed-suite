# Contributing

Thanks for looking. This covers building, testing and releasing the suite. What the mods do is in the
[README](README.md).

## Requirements

- Balatro (Steam) with [lovely](https://github.com/ethangreen-dev/lovely-injector). No Steamodded.
- `luajit`, `make`, `python3` (3.11+), a C compiler for `native/`, and `unzip`.
- For the smoke rig: Linux, and a `headless-run` wrapper on `PATH` that runs a program on a private headless display
  (see [rig/README.md](rig/README.md)). The rig downloads LÖVE 11.5 into `tools/` the first time it runs.

## Layout

| Path | What |
|---|---|
| `mods/<Mod>/` | One lovely mod each: `lovely.toml` + `src/`. `bh-core` is the shared library, and every other mod requires it. A release bundles all of them into one `BalatroSeedSuite/` folder, with each `lovely.toml` as `lovely/<Mod>.toml` |
| `tests/` | Unit tests (`luajit tests/run.lua`) against the real game source |
| `rig/` | The smoke rig: the real game on native LÖVE, headless, driven by scripted scenarios in `rig/scenarios/` |
| `native/` | A C port of the seed streams, checked against the Lua simulator (not shipped yet) |
| `docs/` | The simulator and mod contracts |
| `journal/` | Technical findings: what surprised us about vanilla, LÖVE and lovely |
| `scripts/release.py` | Release zips and version checks |

## The game source

Tests and the rig run the real Balatro code. `make game-src` extracts it from **your own** `Balatro.exe`, which is a
zip, into `build/game/`. `build/` is gitignored: game code is never committed. The Makefile finds the game in any Steam
library. Otherwise pass `GAME_EXE=/path/to/Balatro.exe`.

## Make targets

```sh
make check        # the barrier: lint + unit tests + native tests + every smoke scenario (4 in parallel)
make smoke S=boot # one smoke scenario (build/smoke/<name>/ has its log and screenshots)
make install      # copy mods/* into the Proton prefix's Mods/, one folder per mod (MODS_DIR=... to override)
make install-zip  # install exactly what users download: the zip into Mods/ (LAYOUT=folder unzips it)
make uninstall    # remove every installed layout (saves and journals are kept)
make dist         # dist/<version>/: BalatroSeedSuite.zip, SHA256SUMS
make smoke-dist   # boot the rig from the extracted release bundle instead of mods/
make lovely-check # the real lovely (Linux build) with the release zip, Steamodded and Pokermon
```

`make smoke` emulates lovely, so it only proves the suite against the unmodded game. `make lovely-check`
runs the real game under the real lovely injector, in a throwaway Mods folder, next to other mods. For that it
needs a Steamodded copy in `tools/smods-<version>/` and, for the content-mod case, Pokermon in `tools/pokermon/`.
Scenarios named `lovely_*` only run there.

`make check` runs at low CPU priority (`nice -n 15`), so a game you are playing keeps its frame rate. It must pass
before any change is merged.

## Rules of thumb

- **Drive the real game.** Scenarios don't fake `G` or skip the game to get a pass.
- **Predictions need a real-game proof.** Anything new that the simulator predicts gets a golden scenario that plays
  real seeded runs and compares.
- **Lockstep versions.** Every mod's `VERSION` (in `src/init.lua`) is the suite version, and the dependent mods'
  `boot.lua` `NEEDS` is its major.minor. `scripts/release.py version` checks both.
- **Found something surprising** about vanilla, LÖVE or lovely? Add a short note to `journal/`.

## Releasing

1. Update the versions and write the `## X.Y.Z — date` section of `CHANGELOG.md`.
2. `make check`, `make smoke-dist` and `make lovely-check`.
3. Install with `make install-zip`, then play the real game once with each mod.
4. Tag `vX.Y.Z`, then publish `dist/X.Y.Z/*` as the GitHub Release, with `make notes` as the body. The asset name
   stays `BalatroSeedSuite.zip`, so `releases/latest/download/BalatroSeedSuite.zip` always points at the newest release.
