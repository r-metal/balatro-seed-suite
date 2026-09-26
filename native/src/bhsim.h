/* bhsim: a native port of Balatro's seed streams: stable (T-341 spike) and
 * shops, shop packs, pack contents (T-342).
 *
 * Written from vanilla 1.0.1o (build/game) and LuaJIT 2.1's math library; see
 * bhsim.c for the lines each function mirrors. No game data lives here: every
 * pool (ordered keys, availability, boss rules) is handed in by the caller,
 * which reads it from the running game (rig/scenarios/native_diff.lua,
 * native_diff_shop.lua).
 *
 * This header is also the FFI cdef: keep it plain C declarations only (no
 * preprocessor lines inside the BHSIM_CDEF block), native_diff.lua reads it
 * between the markers.
 */
#ifndef BHSIM_H
#define BHSIM_H
#include <stddef.h>
#include <stdint.h>

/* BHSIM_CDEF_BEGIN */
typedef struct bh_prng { uint64_t u[4]; } bh_prng;
typedef struct bh_ctx bh_ctx;

/* Primitives, exposed for the tests. */
double bh_pseudohash(const char *s, size_t len);
double bh_round13(double x);
/* %.13f half-way cases: 1 = away from zero (default), 0 = to even. */
void bh_set_round_ties(int away);
void bh_randomseed(bh_prng *rs, double d);
double bh_random(bh_prng *rs);

/* Context: the pools of one deck/stake/profile, built once. */
bh_ctx *bh_new(void);
void bh_free(bh_ctx *c);
int bh_set_run(bh_ctx *c, int win_ante, double edition_rate);
int bh_set_tags(bh_ctx *c, int n, int antes, const uint8_t *ok);
int bh_set_vouchers(bh_ctx *c, int n, const uint8_t *ok);
int bh_set_bosses(bh_ctx *c, int n, const int *min_ante, const uint8_t *showdown,
                  const uint8_t *ok, const int *used);
int bh_set_legendaries(bh_ctx *c, int n, const uint8_t *ok);

/* The stable walk for n seeds, antes 1..antes, in the game's order. Writes
 * BH_FIELDS int16 per (seed, ante): small tag, big tag, boss, voucher (pool
 * indices, 0-based; -1 = the pool's empty fallback), the legendary a Soul used
 * in that ante makes (the Souls of earlier antes held) and its edition
 * (0 none, 1 foil, 2 holo, 3 polychrome, 4 negative). Returns 0, or a negative
 * error code (see bhsim.c). */
int bh_stable_batch(bh_ctx *c, const char *const *seeds, int n, int antes, int16_t *out);

/* Conditional streams (T-342): shops, shop packs, pack contents. Every list
 * below comes from the running game (native/lua/bhsim.lua, bhsim.shop).
 * Centers: every center a shop or pack can make, indexed 0..n-1. group = the
 * center's name class (used_jokers is written and cleared by name), set =
 * BH_SET_*, eternal/perishable_compat, banned, used0 = in used_jokers at the
 * start of each walk. */
int bh_set_centers(bh_ctx *c, int n, const int *group, const uint8_t *set,
                   const uint8_t *eternal_compat, const uint8_t *perishable_compat,
                   const uint8_t *banned, const uint8_t *used0);
/* One create_card pool (BH_POOL_*): its full ordered list as center indices,
 * the static cull as a 0/1 mask (used_jokers left out), the center of
 * vanilla's empty-pool fallback, and whether used_jokers culls it. */
int bh_set_pool(bh_ctx *c, int which, int n, const int *center, const uint8_t *ok,
                int fallback, int cull_used);
/* c_soul, c_black_hole, c_base as center indices (-1 = not in the game). */
int bh_set_specials(bh_ctx *c, int soul, int black_hole, int base);
/* The Booster pool in order: weight, ok (not banned), kind (BH_KIND_*), size
 * (config.extra). buffoon = index of the run's forced first Buffoon (-1 when
 * banned), first_done = G.GAME.first_shop_buffoon. */
int bh_set_boosters(bh_ctx *c, int n, const double *weight, const uint8_t *ok,
                    const uint8_t *kind, const uint8_t *size, int buffoon, int first_done);
/* rates = joker, tarot, planet, playing_card, spectral (that order); flags =
 * BH_F_*; telescope = the Celestial pack's forced first planet (center) or -1;
 * fronts = #G.P_CARDS (drawn by sorted key). */
int bh_set_shop(bh_ctx *c, const double *rates, int joker_max, int flags,
                int telescope, int fronts);
/* Per tag index: the booster a skip of that tag opens at once, or -1. */
int bh_set_tag_packs(bh_ctx *c, int n, const int *booster);
/* int16 per ante written by bh_shop_batch for `rerolls` (layout: bhsim.c). */
int bh_shop_stride(bh_ctx *c, int rerolls);
/* predict.ante_walk for antes 1..antes, every ante under one policy: skip
 * bit 0 = Small, bit 1 = Big; `rerolls` per shop; every pack opened and
 * closed with nothing taken. Returns 0 or a negative error code. */
int bh_shop_batch(bh_ctx *c, const char *const *seeds, int n, int antes, int skip,
                  int rerolls, int16_t *out);
/* BHSIM_CDEF_END */

#define BH_FIELDS 6

/* bh_set_centers set codes, pools, booster kinds, bh_set_shop flags. The FFI
 * glue keeps its own copy of these numbers (bhsim.lua). */
enum { BH_SET_OTHER, BH_SET_JOKER, BH_SET_TAROT, BH_SET_PLANET, BH_SET_SPECTRAL,
       BH_SET_ENHANCED, BH_SET_DEFAULT };
enum { BH_POOL_JOKER1, BH_POOL_JOKER2, BH_POOL_JOKER3, BH_POOL_TAROT, BH_POOL_PLANET,
       BH_POOL_SPECTRAL, BH_POOL_ENHANCED, BH_POOLS };
enum { BH_KIND_NONE, BH_KIND_ARCANA, BH_KIND_CELESTIAL, BH_KIND_SPECTRAL,
       BH_KIND_STANDARD, BH_KIND_BUFFOON };
#define BH_F_ILLUSION 1
#define BH_F_OMEN_GLOBE 2
#define BH_F_TELESCOPE 4
#define BH_F_ALL_ETERNAL 8
#define BH_F_ETERNALS 16
#define BH_F_PERISHABLES 32
#define BH_F_RENTALS 64

#endif
