# bhsim: the native port of the seed streams, stable (T-341) and shops / packs /
# pack contents (T-342). Built as a Linux .so for the rig; the Windows DLL is T-343.
#   make -C native        build/libbhsim.so
#   make -C native test   primitives + synthetic-pool walks against vanilla's
#                         own Lua and bhcore.sim.predict under the system luajit
#                         (needs build/game)
# Exact double arithmetic is the whole point: no fast-math, no FMA contraction.
CC ?= cc
CFLAGS ?= -O2
CFLAGS += -std=gnu11 -fPIC -Wall -Wextra -ffp-contract=off -fno-fast-math
LDFLAGS += -shared
LIBS := -lm

.PHONY: all test clean
all: build/libbhsim.so

build/libbhsim.so: src/bhsim.c src/bhsim.h | build
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ src/bhsim.c $(LIBS)

build:
	@mkdir -p build

test: build/libbhsim.so
	@luajit test/test_native.lua $(abspath $(CURDIR)/..)

clean:
	rm -rf build
