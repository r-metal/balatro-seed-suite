#!/usr/bin/env bash
# Real-lovely rig: runs rig/scenarios/<name>.lua in the real game (build/game) on native
# LÖVE 11.5 with the real lovely injector (Linux build, LD_PRELOAD), headless, in a
# throwaway Mods dir holding the release zip, optionally Steamodded, and the scenario
# driver packaged as a lovely mod. It checks what the emulating rig (smoke.sh) can't:
# the zip loaded by lovely itself, and the suite next to other mods' patches.
# Usage: rig/lovely-rig.sh <scenario> [--smods] [--suite <zip or folder>] [--mod <dir>]... [--profile <dir>]
#   --profile: a profile folder whose meta.jkr and profile.jkr (unlocks, discoveries) the
#   game loads as profile 1; copied into the throwaway save dir, never written back.
#   (normally via `make lovely-smoke S=<name> [SMODS=1]`)
# Output: `LOVELY PASS <name>` / `LOVELY FAIL <name>: <reason>`. Log: build/lovely-rig/<name>/.
# Needs: tools/lovely-0.9.0/liblovely.so (fetched on first use), tools/love-11.5 (from
# smoke.sh), and for --smods a Steamodded copy in tools/smods-<version>/ (SMODS_DIR=...).
# Never points at the real Mods dir.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOVELY_VER=0.9.0
LOVELY="$ROOT/tools/lovely-$LOVELY_VER/liblovely.so"
LOVE_DIR="$ROOT/tools/love-11.5"
SMODS_DIR="${SMODS_DIR:-$(ls -d "$ROOT"/tools/smods-* 2>/dev/null | tail -1)}"
WALL_TIMEOUT="${SMOKE_TIMEOUT:-180}"

name="${1:-}"; shift || true
smods=0; suite=""; extra=(); profile=""
while [ $# -gt 0 ]; do
  case "$1" in
    --smods) smods=1 ;;
    --suite) suite="$2"; shift ;;
    --mod) extra+=("$2"); shift ;;
    --profile) profile="$2"; shift ;;
    *) echo "LOVELY FAIL $name: unknown option $1"; exit 1 ;;
  esac
  shift
done
die() { echo "LOVELY FAIL $name: $1"; exit 1; }
case "$name" in *[!A-Za-z0-9_-]*|'') die "bad scenario name" ;; esac
[ -f "$ROOT/rig/scenarios/$name.lua" ] || die "no scenario rig/scenarios/$name.lua"
[ -f "$ROOT/build/game/main.lua" ] || die "build/game missing (make game-src)"
[ -x "$LOVE_DIR/bin/love" ] || die "tools/love-11.5 missing (run make smoke once)"
if [ ! -f "$LOVELY" ]; then
  mkdir -p "$(dirname "$LOVELY")"
  curl -fsSL "https://github.com/ethangreen-dev/lovely-injector/releases/download/v$LOVELY_VER/lovely-x86_64-unknown-linux-gnu.tar.gz" \
    | tar xz -C "$(dirname "$LOVELY")" || die "could not fetch lovely $LOVELY_VER"
fi
if [ -z "$suite" ]; then
  v=$(python3 "$ROOT/scripts/release.py" version) || die "no suite version"
  suite="$ROOT/dist/$v/BalatroSeedSuite.zip"
fi
[ -e "$suite" ] || die "no suite at $suite (make dist)"
[ $smods = 0 ] || [ -d "$SMODS_DIR/lovely" ] || die "no Steamodded copy in tools/smods-*"

out="$ROOT/build/lovely-rig/$name"
rm -rf "$out" && mkdir -p "$out/home" "$out/Mods/zz-rig-driver"
cp -r "$suite" "$out/Mods/"
[ $smods = 0 ] || cp -r "$SMODS_DIR" "$out/Mods/smods"
for m in "${extra[@]}"; do cp -r "$m" "$out/Mods/"; done
if [ -n "$profile" ]; then
  mkdir -p "$out/home/love/game/1"
  for f in meta.jkr profile.jkr; do [ -f "$profile/$f" ] && cp "$profile/$f" "$out/home/love/game/1/"; done
fi

# The driver as a lovely mod: fail fast on load errors, then run the scenario at the
# end of main.lua, exactly where the emulating rig appends it.
drv="$out/Mods/zz-rig-driver"
cat >"$drv/prelude.lua" <<EOF
function love.errorhandler(msg)
  msg = tostring(msg)
  io.stderr:write('[smoke] load error: ', msg, '\n', debug.traceback('', 2), '\n')
  local f = io.open('$out/result.txt', 'wb')
  if f then f:write('FAIL: load error: ', (msg:gsub('\n', ' ')), '\n'); f:close() end
end
EOF
cat >"$drv/driver.lua" <<EOF
assert(loadfile('$ROOT/rig/driver.lua'))({root = '$ROOT', name = '$name', out = '$out',
  scenario = '$ROOT/rig/scenarios/$name.lua'})
EOF
cat >"$drv/lovely.toml" <<'EOF'
[manifest]
version = "1.0.0"
priority = 100

[[patches]]
[patches.copy]
target = "main.lua"
position = "prepend"
sources = ["prelude.lua"]

[[patches]]
[patches.copy]
target = "main.lua"
position = "append"
sources = ["driver.lua"]
EOF

status=0
nice -n "${SMOKE_NICE:-15}" timeout -k 5 "$WALL_TIMEOUT" headless-run --res 1280x720 -- \
  env XDG_DATA_HOME="$out/home" LOVELY_MOD_DIR="$out/Mods" ALSOFT_DRIVERS=null \
  LD_LIBRARY_PATH="$LOVE_DIR/lib" \
  bash -c 'LD_PRELOAD="$3" exec "$0" "$1" >>"$2" 2>&1' "$LOVE_DIR/bin/love" "$ROOT/build/game" "$out/log.txt" "$LOVELY" \
  >"$out/headless.txt" 2>&1 || status=$?

result=""
[ -f "$out/result.txt" ] && result="$(head -n 1 "$out/result.txt")"
if [ "$result" = "PASS" ] && [ "$status" = 0 ]; then echo "LOVELY PASS $name"; exit 0; fi
if [ -n "$result" ] && [ "$result" != "PASS" ]; then reason="${result#FAIL: }"
elif [ "$status" = 124 ] || [ "$status" = 137 ]; then reason="wall-clock timeout (${WALL_TIMEOUT}s)"
else reason="game exited (status $status) without a result"; fi
tail -n 30 "$out/log.txt"
echo "LOVELY FAIL $name: $reason"
exit 1
