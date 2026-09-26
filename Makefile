# Balatro Seed Suite (mods/*). `make check` is the barrier.
SHELL := /bin/bash
# The game and its Proton prefix can be in any Steam library; override either if needed.
STEAM ?= $(HOME)/.local/share/Steam
STEAM_LIBS := $(STEAM) $(shell sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"/\1/p' $(STEAM)/steamapps/libraryfolders.vdf 2>/dev/null)
GAME_EXE ?= $(firstword $(wildcard $(addsuffix /steamapps/common/Balatro/Balatro.exe,$(STEAM_LIBS))))
PREFIX_APPDATA ?= $(firstword $(wildcard $(addsuffix /steamapps/compatdata/2379780/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro,$(STEAM_LIBS))))
MODS_DIR ?= $(PREFIX_APPDATA)/Mods
VERSION = $(shell python3 scripts/release.py version)
MODS := $(notdir $(patsubst %/lovely.toml,%,$(wildcard mods/*/lovely.toml)))
LUA_SRC := $(wildcard mods/*/src/*.lua mods/*/src/*/*.lua) $(wildcard tests/*.lua) $(wildcard rig/*.lua rig/scenarios/*.lua)

.PHONY: check lint unit native smoke smoke-dist game-src clear-installed install install-zip uninstall dist notes export clean

# Tests run at low CPU priority so a game being played keeps its frame rate.
NICE ?= nice -n 15

check: lint unit native smoke

# Game source (never committed): extracted from the fused Balatro.exe.
game-src: build/game/.stamp
build/game/.stamp: $(GAME_EXE)
	@test -n "$(GAME_EXE)" || { echo "game-src: Balatro.exe not found in any Steam library; pass GAME_EXE=..."; exit 1; }
	@mkdir -p build/game
	@unzip -qo "$(GAME_EXE)" -d build/game 2>/dev/null; test -f build/game/main.lua
	@touch $@

lint:
	@fail=0; for f in $(LUA_SRC); do luajit -bl "$$f" >/dev/null || fail=1; done; \
	  [ $$fail = 0 ] && echo "lint: $(words $(LUA_SRC)) files ok"; exit $$fail

unit: game-src
	@BRAINSTORM_KEYHANDLER="$${BRAINSTORM_KEYHANDLER:-$(MODS_DIR)/Brainstorm/Brainstorm_keyhandler.lua}" \
	  $(NICE) luajit tests/run.lua $(T)

# Native search backend (native/): build + its own C-vs-reference tests.
native:
	@$(NICE) $(MAKE) -s -C native test

smoke: game-src
	@test -x rig/smoke.sh || { echo "smoke: rig/smoke.sh missing"; exit 1; }
	@rig/smoke.sh $(or $(S),all)

# The release bundle as users get it: the rig boots from the extracted zip, not mods/.
SMOKE_DIST ?= boot oracle finder_ui runjournal_ui ui_flow
smoke-dist: dist game-src
	@rm -rf build/dist-check && mkdir -p build/dist-check
	@unzip -q dist/$(VERSION)/BalatroSeedSuite.zip -d build/dist-check
	@for s in $(SMOKE_DIST); do MODS_ROOT=$(CURDIR)/build/dist-check rig/smoke.sh $$s || exit 1; done

# Every layout the suite can be installed in: the dev copies (one folder per mod) and
# the release bundle (folder or zip). Each install target clears all of them first,
# so no module is ever loaded twice.
INSTALLED := $(MODS) BalatroSeedSuite BalatroSeedSuite.zip
clear-installed:
	@test -d "$(MODS_DIR)" || { echo "no Mods folder at '$(MODS_DIR)'; pass MODS_DIR=..."; exit 1; }
	@for m in $(INSTALLED); do rm -rf "$(MODS_DIR)/$$m"; done

install: clear-installed
	@for m in $(MODS); do \
	  mkdir -p "$(MODS_DIR)/$$m" && cp -r mods/$$m/lovely.toml mods/$$m/src "$(MODS_DIR)/$$m/" && echo "installed $$m"; \
	done; echo "into $(MODS_DIR) — restart Balatro"

# What users download. By default the zip itself goes into Mods/, as the README says
# (lovely 0.9+ loads zipped mods); LAYOUT=folder extracts it instead.
install-zip: dist clear-installed
	@if [ "$(LAYOUT)" = folder ]; then unzip -qo dist/$(VERSION)/BalatroSeedSuite.zip -d "$(MODS_DIR)"; \
	  else cp dist/$(VERSION)/BalatroSeedSuite.zip "$(MODS_DIR)/"; fi
	@echo "installed BalatroSeedSuite $(VERSION) as a $(or $(LAYOUT),zip) into $(MODS_DIR) — restart Balatro"

uninstall: clear-installed
	@echo "removed the suite from $(MODS_DIR) (saves and journals kept)"

# Release: dist/<version>/{BalatroSeedSuite.zip, SHA256SUMS}, one lovely mod folder
# built from tracked files. Versions are lockstep (scripts/release.py version checks them).
dist:
	@python3 scripts/release.py dist

notes:
	@python3 scripts/release.py notes $(VERSION)

# The public repo: allowlisted files at REF (default: the tag of this version).
# PUBLIC is a separate checkout; everything in it but .git is replaced.
export:
	@test -n "$(PUBLIC)" || { echo "export: pass PUBLIC=<path to the public checkout>"; exit 1; }
	@python3 scripts/release.py export "$(PUBLIC)" $(or $(REF),v$(VERSION))

clean:
	rm -rf build
