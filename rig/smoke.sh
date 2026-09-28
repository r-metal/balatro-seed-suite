#!/usr/bin/env bash
# Smoke rig: runs rig/scenarios/<name>.lua inside the real game (build/game) on
# native LÖVE 11.5, headless, with every mods/* loaded as lovely would load them.
# Usage: rig/smoke.sh <name|all>     (normally via `make smoke S=<name>`)
# Output: one `SMOKE PASS <name>` / `SMOKE FAIL <name>: <reason>` line per scenario;
# on failure the last 30 log lines come first. Full log: build/smoke/<name>/log.txt.
# Contract: docs/SPEC.md § Smoke rig contract. Docs: rig/README.md.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOVE_VER=11.5
APPIMAGE="$ROOT/tools/love-$LOVE_VER-x86_64.AppImage"
LOVE_DIR="$ROOT/tools/love-$LOVE_VER"
LOVE_URL="https://github.com/love2d/love/releases/download/$LOVE_VER/love-$LOVE_VER-x86_64.AppImage"
WALL_TIMEOUT="${SMOKE_TIMEOUT:-120}"

die() { echo "SMOKE FAIL ${1}: ${2}"; exit 1; }

# LÖVE: fetched once into tools/ (gitignored), extracted because FUSE may be absent.
ensure_love() {
  [ -x "$LOVE_DIR/AppRun" ] && return 0
  mkdir -p "$ROOT/tools"
  if [ ! -s "$APPIMAGE" ]; then
    curl -fsSL -o "$APPIMAGE.part" "$LOVE_URL" && mv "$APPIMAGE.part" "$APPIMAGE" || return 1
  fi
  chmod +x "$APPIMAGE"
  local tmp; tmp="$(mktemp -d "$ROOT/tools/extract.XXXXXX")"
  (cd "$tmp" && "$APPIMAGE" --appimage-extract >/dev/null) && mv "$tmp/squashfs-root" "$LOVE_DIR"
  local rc=$?; rm -rf "$tmp"; return $rc
}

run_one() {
  local name="$1"
  local scen="$ROOT/rig/scenarios/$name.lua"
  local out="$ROOT/build/smoke/$name"
  case "$name" in *[!A-Za-z0-9_-]*|'') echo "SMOKE FAIL $name: bad scenario name"; return 1 ;; esac
  if [ ! -f "$scen" ]; then echo "SMOKE FAIL $name: no scenario rig/scenarios/$name.lua"; return 1; fi

  # One run per scenario at a time: concurrent runs of the same scenario would share
  # $out (and its save dir), leaking slots between games. The lock is released when
  # this function's fd closes; different scenarios still run in parallel.
  mkdir -p "$ROOT/build/smoke"
  local lockfd
  exec {lockfd}>"$ROOT/build/smoke/.$name.lock"
  flock "$lockfd"
  run_locked "$name" "$scen" "$out"
  local rc=$?
  exec {lockfd}>&-
  return $rc
}

run_locked() {
  local name="$1" scen="$2" out="$3"
  rm -rf "$out" && mkdir -p "$out/home"
  # Hard-link copy: fast, and PhysFS refuses symlinks by default. build.lua
  # removes main.lua before writing, so nothing writes through into build/game.
  if ! cp -al "$ROOT/build/game" "$out/game" 2>"$out/log.txt"; then
    tail -n 30 "$out/log.txt"; echo "SMOKE FAIL $name: could not stage build/game"; return 1
  fi
  rm -f "$out/game/.stamp"
  if ! luajit "$ROOT/rig/build.lua" "$ROOT" "$name" "$out" >>"$out/log.txt" 2>&1; then
    tail -n 30 "$out/log.txt"; echo "SMOKE FAIL $name: rig build failed (lovely.toml?)"; return 1
  fi

  # XDG_DATA_HOME isolates the save dir (love/<identity> under it); ALSOFT_DRIVERS
  # keeps audio off the real sound server; the SDL hint hides every game controller
  # (SDL reads /dev/input itself, so a pad in use on this machine drove rig games:
  # journal/2026-09-28-rig-host-gamepad.md). The game's own stdout/stderr go to log.txt.
  local status=0
  nice -n "${SMOKE_NICE:-15}" timeout -k 5 "$WALL_TIMEOUT" headless-run --res 1280x720 -- \
    env XDG_DATA_HOME="$out/home" ALSOFT_DRIVERS=null SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT=0x0000/0x0000 \
    bash -c 'exec "$0" "$1" >>"$2" 2>&1' "$LOVE_DIR/AppRun" "$out/game" "$out/log.txt" \
    >"$out/headless.txt" 2>&1 || status=$?

  local result=""
  [ -f "$out/result.txt" ] && result="$(head -n 1 "$out/result.txt")"
  if [ "$result" = "PASS" ] && [ "$status" = 0 ]; then
    echo "SMOKE PASS $name"; return 0
  fi
  local reason
  if [ -n "$result" ] && [ "$result" != "PASS" ]; then reason="${result#FAIL: }"
  elif [ "$status" = 124 ] || [ "$status" = 137 ]; then reason="wall-clock timeout (${WALL_TIMEOUT}s), game killed"
  elif [ "$result" = "PASS" ]; then reason="scenario passed but the game exited with status $status"
  else reason="game exited (status $status) without a result"
  fi
  tail -n 30 "$out/log.txt"
  echo "SMOKE FAIL $name: $reason"
  return 1
}

[ $# -eq 1 ] || die usage "rig/smoke.sh <name|all>"
command -v headless-run >/dev/null || die "$1" "headless-run not found"
command -v luajit >/dev/null || die "$1" "luajit not found"
[ -f "$ROOT/build/game/main.lua" ] || die "$1" "build/game missing (make game-src)"
ensure_love || die "$1" "could not fetch/extract LÖVE $LOVE_VER into tools/"

if [ "$1" != all ]; then
  run_one "$1"; exit $?
fi

names=()
for f in "$ROOT"/rig/scenarios/*.lua; do
  [ -e "$f" ] || continue
  n="$(basename "$f" .lua)"
  case "$n" in selftest_*|lovely_*) continue ;; esac  # lovely_*: rig/lovely-rig.sh only
  names+=("$n")
done
[ ${#names[@]} -gt 0 ] || die all "no scenarios in rig/scenarios"

# Scenarios run SMOKE_JOBS at a time (default 4): each has its own output dir, save
# dir, headless session and lock, and golden suites are CPU-light (frame-bound).
# Output is buffered per scenario and printed in name order, so logs never interleave.
jobs_max="${SMOKE_JOBS:-4}"
outdir="$ROOT/build/smoke/.all"; rm -rf "$outdir"; mkdir -p "$outdir"
for n in "${names[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$jobs_max" ]; do wait -n || true; done
  ( run_one "$n" >"$outdir/$n.out" 2>&1; echo $? >"$outdir/$n.rc" ) &
done
wait
failed=()
for n in "${names[@]}"; do
  cat "$outdir/$n.out"
  [ "$(cat "$outdir/$n.rc" 2>/dev/null)" = 0 ] || failed+=("$n")
done
# All green: the last line is the last scenario's PASS line. Any red: a summary FAIL.
[ ${#failed[@]} -eq 0 ] || die all "${#failed[@]} of ${#names[@]} failed: ${failed[*]}"
