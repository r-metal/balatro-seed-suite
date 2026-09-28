# Smoke rig

Runs the real Balatro source with SaveSlots loaded, on native LÖVE 11.5, headless,
and drives it through a scripted scenario. The contract lives in
[docs/SPEC.md § Smoke rig contract](../docs/SPEC.md); this file covers how to use it
and how it works.

```sh
make smoke S=boot          # one scenario
make smoke                 # every scenario except selftest_*
rig/smoke.sh boot          # the same thing without make (needs `make game-src` first)
SMOKE_TIMEOUT=60 rig/smoke.sh boot   # override the 120 s wall-clock limit
```

Output is one line per scenario, `SMOKE PASS <name>` or
`SMOKE FAIL <name>: <reason>`. On a failure the last 30 lines of the game log come
first. The exit status matches. With `all`, a failure also ends with a summary line
`SMOKE FAIL all: N of M failed: ...`.

## Per-scenario output: `build/smoke/<name>/`

| Path | What |
|---|---|
| `log.txt` | the game's stdout/stderr plus `[smoke]` lines from the driver (steps, shots, errors with tracebacks) |
| `<label>.png` | screenshots from `ctx.shot(label)` |
| `result.txt` | the driver's verdict: `PASS` or `FAIL: <reason>` |
| `home/` | the scenario's isolated save dir (`XDG_DATA_HOME`; the game writes under `home/love/game/`) |
| `game/` | the staged game: hard links to `build/game` plus the generated `main.lua` |
| `headless.txt` | `headless-run`'s own output (session id, display) |

The directory is wiped at the start of each run.

## Writing a scenario

`rig/scenarios/<name>.lua` returns an array of steps. Steps start once the main menu
is up and has had a second to settle. Each step's `run(ctx)` is called once per frame,
after `G:update`:

- truthy return: the step is done, move on to the next one
- falsy return: try again next frame, until `timeout` seconds (default 10) pass, then FAIL
- an error (including `ctx.assert`): FAIL with the message

```lua
return {
  {name = 'open overlay', run = function(ctx)
    return ctx.click('saveslots_open')          -- false until the button exists
  end},
  {name = 'overlay up', timeout = 5, run = function(ctx)
    if not G.OVERLAY_MENU or ctx.step_time() < 1 then return false end
    ctx.shot('overlay')
    return true
  end},
}
```

`ctx`:

| Call | Does |
|---|---|
| `ctx.shot(label)` | writes `build/smoke/<name>/<label>.png` at the end of this frame. Labels are `[A-Za-z0-9_-]`. The rig waits for pending shots before it passes. |
| `ctx.log(msg)` | a `[smoke]` line in `log.txt` |
| `ctx.assert(cond, msg)` | errors with `msg` when `cond` is falsy |
| `ctx.find_button(button[, id])` | first live UIElement with `config.button == button` (and `config.id == id` if given), searching every UIBox in `G.I`, `G.OVERLAY_MENU`, `G.MAIN_MENU_UI` and boxes nested as `config.object`; `nil` if none |
| `ctx.click(button[, id])` | `G.FUNCS[button](elem)` on that element; `true` if found, `false` if not |
| `ctx.start_run(args)` | closes any overlay, then `G.FUNCS.start_run(nil, args or {})` |
| `ctx.step_time()` | seconds since the current step started, to let an animation land (rig extension, not in the locked contract) |
| `ctx.name`, `ctx.out` | scenario name and its output directory |

Name a scenario `selftest_*` to keep it out of `make smoke` / `make check`.
Current scenarios: `boot` (menu → new run → blind select), `selftest_fail`
(must FAIL, proves failures are reported), `selftest_ctx` (exercises
`find_button`/`click` against the real main menu and Options overlay).

Scenarios drive the real game. Don't fake `G` or skip the game to make one pass.

## How it works

1. **LÖVE.** `smoke.sh` downloads `love-11.5-x86_64.AppImage` into `tools/`
   (gitignored) on first use and extracts it to `tools/love-11.5/`, because FUSE may
   not be available. No sudo or system packages.
2. **Staging.** `build/game` (from `make game-src`) is copied into
   `build/smoke/<name>/game` with hard links. Symlinks won't work because PhysFS refuses
   them by default. `main.lua` is removed first and then regenerated, so nothing is
   written through a link into `build/game`.
3. **Loading the mod like lovely does.** `rig/build.lua` parses `mods/*/lovely.toml`
   with `rig/toml.lua` and writes `main.lua` as:
   - `package.preload[name]` for every `[patches.module]`, pointing at the source in `mods/<Mod>/`
   - `[patches.copy]` sources with `position = "prepend"`
   - the vanilla `main.lua`, verbatim
   - `[patches.copy]` sources with `position = "append"`, pasted as text the way lovely does
   - a `loadfile` of `rig/driver.lua` with the scenario's config

   The rig only emulates `module` patches and `copy` patches that target `main.lua`.
   Any other patch kind makes the build fail loudly. Skipping it quietly would make a
   PASS meaningless. Real lovely under Proton is only checked by hand (T-009).
4. **Driver** (`rig/driver.lua`, runs inside the game):
   - wraps `Game:splash_screen` to set up a clean profile: tutorial complete
     (`F_SKIP_TUTORIAL`, `tutorial_complete`, `tutorial_progress = nil`), splash
     skipped, muted, crash reports off
   - replaces `love.errorhandler`, so a game error writes `FAIL: game error: ...`
     and exits instead of waiting on the crash screen
   - wraps `love.update` to run the steps after the original, then writes `result.txt`
     and quits with status 0 or 1
   - FAILs if the main menu doesn't come up within 60 s
5. **Isolation.** The game runs under `headless-run --res 1280x720`, so nothing appears
   on the real display. `XDG_DATA_HOME=build/smoke/<name>/home` keeps saves away from
   `~/.local/share/love` and from the Proton prefix. `ALSOFT_DRIVERS=null` keeps it off
   the sound server. A `timeout 120` around `headless-run` kills the game and its sway
   session if it hangs. The rig never touches the Proton prefix or the Steam install.
6. **Verdict.** `smoke.sh` prints `SMOKE PASS` only when `result.txt` says `PASS` and
   the game exited with status 0. Otherwise it prints the recorded reason, the timeout,
   or the exit status.

## Troubleshooting

- `build/game missing`: run `make game-src`. It extracts `Balatro.exe` and needs the
  Steam install.
- Hanging or leftover sessions: `headless-run --list`, then `headless-run --stop <id>`.
- `[ALSOFT] (WW) ...` lines in `log.txt` are expected, because audio is on the null backend.
- `LONG DT @ ...` lines come from vanilla's frame timer and are harmless.

## The real-lovely rig (compatibility)

`rig/lovely-rig.sh <scenario> [--smods] [--mod <dir>]...` (or `make lovely-smoke S=<name> [SMODS=1]`)
runs the same scenario driver in the real game. The difference from `smoke.sh` is that it uses
the **real lovely injector**: its Linux build `liblovely.so`, loaded with `LD_PRELOAD` into native
LÖVE 11.5. It runs headless, like `smoke.sh`, with a throwaway Mods folder in
`build/lovely-rig/<name>/Mods` that holds:

- the release zip, as users install it (`--suite` to pick another);
- Steamodded with `--smods` (a copy in `tools/smods-*/`), and any `--mod` folders (Pokermon for the
  content-mod case);
- the scenario driver, packaged as a lovely mod (`zz-rig-driver`) that appends the driver to
  `main.lua`, exactly where `smoke.sh` puts it.

`make lovely-check` runs the compatibility matrix:
- plain lovely;
- Steamodded (Finder search, Oracle on every deck, Mods-menu listing, Save Slots preview of a
  pre-Steamodded save, the paused-game RNG, the golden suites);
- Steamodded with Pokermon.

Most scenarios assume the unmodded game's profile and flow, so the Steamodded ones are written
for it and named `lovely_*`. `smoke.sh all` skips them. It never touches a real Mods folder.

