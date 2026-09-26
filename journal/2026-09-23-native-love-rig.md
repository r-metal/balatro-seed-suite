# Running Balatro on native LÖVE, headless, for tests

`Balatro.exe` is a fused LÖVE 11.5 build: a PE stub plus a zip (`unzip` warns about ~394 KB of leading bytes but extracts fine). Game logic is plain Lua, and on Linux vanilla `main.lua` only requires `luasteam` on Windows/OS X. So the real game runs on the Linux LÖVE 11.5 AppImage with no stubs at all.

Gotchas the rig hit:
- **PhysFS refuses symlinks** in the game dir. Stage it as a hard-link copy, and `os.remove` `main.lua` before writing the generated one, or you write through the hard link into the pristine extract.
- There's no FUSE here, so extract the AppImage (`--appimage-extract`).
- `XDG_DATA_HOME` per scenario isolates the save dir (`<home>/love/game/…`). The real Proton prefix is never involved.
- `ALSOFT_DRIVERS=null` avoids audio device trouble. `[ALSOFT] (WW) No capture backend` is expected noise.
- A crash during `main.lua` load happens before any driver hook exists. Put `love.errorhandler` in the generated prelude, or it sits on the crash screen until the wall-clock timeout (now 0.7 s instead of 120 s).
- Screenshots are taken at the end of the frame, so close UI in a *later* step than the shot. The virtual cursor sits at the screen centre and triggers tooltips, so move it to a corner before shots.
- To emulate lovely, parse `lovely.toml`: `[patches.module]` becomes `package.preload`, and `[patches.copy]` append/prepend becomes text concatenation around vanilla `main.lua`.
- Parallel agents running the **same** scenario shared `build/smoke/<name>` (and its save dir), so slots leaked between two games. The fix is a per-scenario `flock` in `smoke.sh` (`exec {fd}>lockfile; flock $fd`). Different scenarios still run in parallel.
