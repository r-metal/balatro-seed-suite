# The rig was playable by the real controller

On 2026-09-28 a DualSense Edge was plugged into the dev machine at 17:20, and the developer
played Balatro with it while wave 7 ran. Every headless rig game read it. SDL opens
`/dev/input` itself (the user is in the `input` group), and a headless sway session with
no input devices doesn't change that. So its presses arrived in the rig games as
`love.gamepadpressed`. The d-pad moved the controller focus, and A clicked whatever was
focused. Scenarios failed at random:
- the Journal switched tabs mid-step;
- the Oracle showed a different ante's tab ("expected tag_charm, got tag_economy");
- shop steps timed out.

All four implementers traced it independently. A LÖVE probe under `headless-run` saw
"DualSense Edge Wireless Controller gamepad=true".

**Fix:** `rig/smoke.sh` and `rig/lovely-rig.sh` start the game with
`SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT=0x0000/0x0000`, which hides every game controller.
The probe then sees 0 joysticks. `rig/driver.lua` fails a scenario at the main menu when
any joystick is visible ("a host game controller reaches the rig"), so a missing hint is a
loud failure rather than a flake. With the pad connected, removing the hint turned `boot`
red, and putting it back turned it green.

**Lesson:** the rig was isolated from the display, the audio and the save directory, but
not from input devices. A barrier run while he plays with a pad isn't evidence until the
guard passes. Before this, runs while he played with a keyboard and mouse were
unaffected: those events go to his own display, not to headless sway.

## Also: never point a worktree's `build/game` at the real one

To compare throughput at an older commit, I made a git worktree and symlinked its
`build/game` to the main checkout's. The rig stages every game as *hard links* into
`build/game` and then writes the generated `main.lua` in place. So the worktree's run
overwrote the real `build/game/main.lua` with its own loader, which pointed at the
worktree's mods. The next main-checkout run then failed with "cannot open .../wt054/mods/...".
Fix: `rm build/game/.stamp && make game-src`. It re-extracts the game read-only from
Balatro.exe. A worktree gets its own `make game-src`.

The native scans' step budgets went from 100 s to 240 s the same day. The worker
throughput was unchanged: the Lua workers ran at 1,422 seeds/s per thread at 054bbb3 and
1,498 after wave 7, under the same load. But a full barrier while another game ran pushed
the 1M-seed scan past 100 s.
