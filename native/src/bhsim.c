/* bhsim: Balatro's seed streams in C: the stable ones (T-341 spike) and the
 * conditional shop / pack streams (T-342, second half of this file). API:
 * bhsim.h.
 *
 * Mirrors, written from the call order (bodies are not copied):
 *   vanilla 1.0.1o, build/game/functions/misc_functions.lua
 *     pseudohash            :279-296  (the live `if true` branch only)
 *     pseudoseed            :298-313  (no predict_seed; 'seed' key unused here)
 *     pseudorandom          :315-320
 *     pseudorandom_element  :253-268  (array pools sort by index; the boss
 *                                      table sorts by key, byte order)
 *   build/game/functions/common_events.lua
 *     get_next_voucher_key  :1901-1911
 *     get_next_tag_key      :1914-1925  (G.FORCE_TAG nil)
 *     get_current_pool      :1963-2053  (culling is done by the caller, per
 *                                        ante for tags; only the key and the
 *                                        empty-pool fallback are here)
 *     poll_edition          :2055-2080  (non-guaranteed branch, _mod 1)
 *     create_card           :2082-2154  (the Soul: 'Joker', legendary, 'sou';
 *                                        card.lua:1418)
 *     get_new_boss          :2338-2383  (no perscribed_bosses, no FORCE_BOSS)
 *   LuaJIT 2.1 (lib_math.c random_seed / math_random, lj_prng.c
 *     lj_prng_u64d): the TW223 generator math.random/math.randomseed use.
 *
 * Exactness: pseudohash and pseudoseed feed math.randomseed bit for bit, so
 * every double operation here is kept in Lua's evaluation order, and the
 * build uses -ffp-contract=off and no fast-math (an FMA changes the bits).
 * Lua's a % 1 is a - floor(a / 1) * 1 = a - floor(a).
 * tonumber(string.format('%.13f', x)) is bh_round13: the exact decimal
 * rounding, then one correctly rounded division, which is what strtod /
 * lj_strscan return for that decimal. Half-way cases (x = j/2^14, j odd) are
 * where LuaJIT builds disagree: LÖVE 11.5's LuaJIT 2.1.1700008891 rounds them
 * away from zero, a 2026 LuaJIT 2.1 (and glibc) to even. So the tie rule is a
 * setting, bh_set_round_ties, which the FFI glue sets from the running
 * LuaJIT's own string.format (native/lua/bhsim.lua).
 *
 * Not modelled (no observable output here): the Soul's 'rarity'..ante..'sou'
 * draw (get_current_pool draws it even for legendaries; its stream feeds
 * nothing this walk reads), card side effects other than used_jokers.
 */
#include "bhsim.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define MAX_ANTES 64
#define MAX_POOL 512
#define KEY_MAX 64
#define SEED_MAX 64
#define MAP_SLOTS 1024 /* power of two, > streams one seed touches (the shop
                        * walk's resample keys are each a stream) */

/* ------------------------------------------------------------------------ */
/* LuaJIT's TW223 PRNG. */

#define TW223_GEN(i, k, q, s)                                                   \
  z = rs->u[i];                                                                \
  z = (((z << q) ^ z) >> (k - s)) ^ ((z & ((uint64_t)(int64_t)-1 << (64 - k))) << s); \
  r ^= z;                                                                      \
  rs->u[i] = z;

static uint64_t tw223_step(bh_prng *rs)
{
  uint64_t z, r = 0;
  TW223_GEN(0, 63, 31, 18)
  TW223_GEN(1, 58, 19, 28)
  TW223_GEN(2, 55, 24, 7)
  TW223_GEN(3, 47, 21, 8)
  return r;
}

typedef union { double d; uint64_t u; } u64d;

void bh_randomseed(bh_prng *rs, double d)
{
  uint32_t r = 0x11090601; /* 64 - k[i], four 8-bit constants */
  int i;
  for (i = 0; i < 4; i++) {
    u64d u;
    uint32_t m = 1u << (r & 255);
    r >>= 8;
    u.d = d = d * 3.14159265358979323846 + 2.7182818284590452354;
    if (u.u < m) u.u += m;
    rs->u[i] = u.u;
  }
  for (i = 0; i < 10; i++) (void)tw223_step(rs);
}

/* math.random() with no arguments: [0, 1). */
double bh_random(bh_prng *rs)
{
  u64d u;
  u.u = (tw223_step(rs) & 0x000fffffffffffffULL) | 0x3ff0000000000000ULL;
  return u.d - 1.0;
}

/* math.random(n) after math.randomseed(seed): an integer in [1, n]. */
static int random_int(double seed, int n)
{
  bh_prng rs;
  bh_randomseed(&rs, seed);
  return (int)(floor(bh_random(&rs) * (double)n) + 1.0);
}

static double random_real(double seed)
{
  bh_prng rs;
  bh_randomseed(&rs, seed);
  return bh_random(&rs);
}

/* ------------------------------------------------------------------------ */
/* pseudohash / %.13f / pseudoseed */

double bh_pseudohash(const char *s, size_t len)
{
  double num = 1.0;
  size_t i;
  for (i = len; i >= 1; i--) {
    double a = (1.1239285023 / num) * (double)(unsigned char)s[i - 1] * M_PI + M_PI * (double)i;
    num = a - floor(a);
  }
  return num;
}

static int ties_away = 1; /* LÖVE 11.5's rule; see the header comment */

void bh_set_round_ties(int away) { ties_away = away != 0; }

double bh_round13(double x)
{
  u64d u;
  uint64_t m;
  int e, neg;
  unsigned __int128 p, q, rem, half;
  u.d = x;
  neg = (int)(u.u >> 63);
  e = (int)((u.u >> 52) & 0x7ff);
  m = u.u & 0x000fffffffffffffULL;
  if (e == 0x7ff) return x;
  if (e == 0) e = 1; else m |= 1ULL << 52;
  e -= 1075; /* x = m * 2^e */
  if (m == 0) return x;
  if (e >= 0 || e < -127) {
    /* |x| >= 2^52 has no fraction to round; |x| < 2^-74 rounds to 0. */
    if (e >= 0) return x;
    return neg ? -0.0 : 0.0;
  }
  p = (unsigned __int128)m * 10000000000000ULL; /* < 2^97 */
  q = p >> (-e);
  rem = p - (q << (-e));
  half = (unsigned __int128)1 << (-e - 1);
  if (rem > half || (rem == half && (ties_away || (q & 1)))) q++;
  {
    /* Exact while q < 2^53, i.e. |x| < ~900; the streams only pass [0, 1). */
    double r = (double)q / 1e13;
    return neg ? -r : r;
  }
}

/* One seed's G.GAME.pseudorandom: stream key -> state, plus hashed_seed. */
typedef struct {
  char seed[SEED_MAX];
  size_t seed_len;
  double hashed;
  uint32_t gen;
  struct { uint32_t gen; uint32_t len; char key[KEY_MAX]; double v; } slot[MAP_SLOTS];
} streams;

static uint32_t fnv(const char *k, size_t n)
{
  uint32_t h = 2166136261u;
  size_t i;
  for (i = 0; i < n; i++) h = (h ^ (unsigned char)k[i]) * 16777619u;
  return h;
}

/* pseudoseed(key): advance the stream (created as pseudohash(key..seed)) and
 * return (state + hashed_seed) / 2. Returns NAN when the map is full. */
static double pseudoseed(streams *st, const char *key, size_t n)
{
  uint32_t h = fnv(key, n) & (MAP_SLOTS - 1);
  int probes;
  for (probes = 0; probes < MAP_SLOTS; probes++, h = (h + 1) & (MAP_SLOTS - 1)) {
    if (st->slot[h].gen != st->gen) {
      char buf[KEY_MAX + SEED_MAX];
      memcpy(buf, key, n);
      memcpy(buf + n, st->seed, st->seed_len);
      st->slot[h].gen = st->gen;
      st->slot[h].len = (uint32_t)n;
      memcpy(st->slot[h].key, key, n);
      st->slot[h].v = bh_pseudohash(buf, n + st->seed_len);
      break;
    }
    if (st->slot[h].len == n && memcmp(st->slot[h].key, key, n) == 0) break;
  }
  if (probes == MAP_SLOTS) return NAN;
  {
    double a = 2.134453429141 + st->slot[h].v * 1.72431234;
    double v = fabs(bh_round13(a - floor(a)));
    st->slot[h].v = v;
    return (v + st->hashed) / 2;
  }
}

/* key = base..int (e.g. 'Tag'..3), or base..int..'_resample'..it when it > 1. */
static size_t make_key(char *out, const char *base, int num, int it)
{
  size_t n = strlen(base);
  char digits[16];
  int d = 0;
  memcpy(out, base, n);
  if (num >= 0) {
    do { digits[d++] = (char)('0' + num % 10); num /= 10; } while (num);
    while (d) out[n++] = digits[--d];
  }
  if (it > 1) {
    memcpy(out + n, "_resample", 9);
    n += 9;
    do { digits[d++] = (char)('0' + it % 10); it /= 10; } while (it);
    while (d) out[n++] = digits[--d];
  }
  out[n] = 0;
  return n;
}

/* ------------------------------------------------------------------------ */
/* Context */

struct bh_ctx {
  int win_ante;
  double edition_rate;
  int n_tags, tag_antes;
  uint8_t *tag_ok; /* [ante-1][i] */
  int n_vouchers;
  uint8_t *voucher_ok;
  int n_bosses;
  int *boss_min, *boss_used0;
  uint8_t *boss_showdown, *boss_ok;
  int n_legend;
  uint8_t *legend_ok;
  /* T-342: shops, packs, pack contents (see the shop section below). */
  int n_centers, n_groups;
  int *center_group;
  uint8_t *center_set, *center_eternal, *center_perishable, *center_banned, *group_used0;
  struct { int n, fallback, cull_used; int *center; uint8_t *ok; } pool[BH_POOLS];
  int soul, black_hole, base;
  int n_boosters, buffoon, first_done;
  double *booster_weight;
  uint8_t *booster_ok, *booster_kind, *booster_size;
  int max_pack;
  double rates[5];
  int joker_max, flags, telescope, fronts;
  int n_tag_packs;
  int *tag_pack;
  streams st;
};

bh_ctx *bh_new(void)
{
  bh_ctx *c = calloc(1, sizeof *c);
  if (c) {
    c->win_ante = 8, c->edition_rate = 1.0;
    c->soul = c->black_hole = c->base = c->buffoon = c->telescope = -1;
  }
  return c;
}

void bh_free(bh_ctx *c)
{
  if (!c) return;
  free(c->tag_ok); free(c->voucher_ok); free(c->legend_ok);
  free(c->boss_min); free(c->boss_used0); free(c->boss_showdown); free(c->boss_ok);
  free(c->center_group); free(c->center_set); free(c->center_eternal);
  free(c->center_perishable); free(c->center_banned); free(c->group_used0);
  {
    int i;
    for (i = 0; i < BH_POOLS; i++) { free(c->pool[i].center); free(c->pool[i].ok); }
  }
  free(c->booster_weight); free(c->booster_ok); free(c->booster_kind); free(c->booster_size);
  free(c->tag_pack);
  free(c);
}

static uint8_t *dup8(const uint8_t *src, size_t n)
{
  uint8_t *p = malloc(n ? n : 1);
  if (p && n) memcpy(p, src, n);
  return p;
}

static int *dupi(const int *src, size_t n)
{
  int *p = malloc((n ? n : 1) * sizeof *p);
  if (p && n) memcpy(p, src, n * sizeof *p);
  return p;
}

int bh_set_run(bh_ctx *c, int win_ante, double edition_rate)
{
  if (!c || win_ante < 1) return -1;
  c->win_ante = win_ante;
  c->edition_rate = edition_rate;
  return 0;
}

int bh_set_tags(bh_ctx *c, int n, int antes, const uint8_t *ok)
{
  if (!c || n < 0 || n > MAX_POOL || antes < 1 || antes > MAX_ANTES) return -1;
  free(c->tag_ok);
  c->tag_ok = dup8(ok, (size_t)n * antes);
  c->n_tags = n, c->tag_antes = antes;
  return c->tag_ok ? 0 : -2;
}

int bh_set_vouchers(bh_ctx *c, int n, const uint8_t *ok)
{
  if (!c || n < 0 || n > MAX_POOL) return -1;
  free(c->voucher_ok);
  c->voucher_ok = dup8(ok, (size_t)n);
  c->n_vouchers = n;
  return c->voucher_ok ? 0 : -2;
}

int bh_set_bosses(bh_ctx *c, int n, const int *min_ante, const uint8_t *showdown,
                  const uint8_t *ok, const int *used)
{
  if (!c || n < 0 || n > MAX_POOL) return -1;
  free(c->boss_min); free(c->boss_used0); free(c->boss_showdown); free(c->boss_ok);
  c->boss_min = dupi(min_ante, (size_t)n);
  c->boss_used0 = dupi(used, (size_t)n);
  c->boss_showdown = dup8(showdown, (size_t)n);
  c->boss_ok = dup8(ok, (size_t)n);
  c->n_bosses = n;
  return (c->boss_min && c->boss_used0 && c->boss_showdown && c->boss_ok) ? 0 : -2;
}

int bh_set_legendaries(bh_ctx *c, int n, const uint8_t *ok)
{
  if (!c || n < 0 || n > MAX_POOL) return -1;
  free(c->legend_ok);
  c->legend_ok = dup8(ok, (size_t)n);
  c->n_legend = n;
  return c->legend_ok ? 0 : -2;
}

/* ------------------------------------------------------------------------ */
/* The draws */

#define E_MAP -10 /* stream map overflow */
#define E_BOSS -11 /* no eligible boss (vanilla would error) */
#define E_ARGS -12

/* A culled pool draw with resamples (create_card :2112-2118, and the same
 * loop in get_next_tag_key / get_next_voucher_key). avail[i] = the entry is
 * not 'UNAVAILABLE'. Returns the 0-based index, -1 for the empty-pool
 * fallback (one draw from a 1-entry pool), or E_MAP. */
static int pool_draw(streams *st, const char *base, int num, int n, const uint8_t *avail,
                     const uint8_t *used)
{
  char key[KEY_MAX];
  size_t kn;
  int i, size = 0, it = 1, idx;
  double s;
  for (i = 0; i < n; i++) size += avail[i] && !(used && used[i]);
  kn = make_key(key, base, num, 1);
  s = pseudoseed(st, key, kn);
  if (s != s) return E_MAP;
  if (size == 0) return -1;
  idx = random_int(s, n) - 1;
  while (!avail[idx] || (used && used[idx])) {
    it++;
    kn = make_key(key, base, num, it);
    s = pseudoseed(st, key, kn);
    if (s != s) return E_MAP;
    idx = random_int(s, n) - 1;
  }
  return idx;
}

static int draw_boss(bh_ctx *c, int ante, int *used)
{
  int elig[MAX_POOL];
  int i, n = 0, min_use = 100, a1 = ante > 1 ? ante : 1;
  double s;
  for (i = 0; i < c->n_bosses; i++) {
    int e;
    if (!c->boss_ok[i]) continue;
    if (!c->boss_showdown[i])
      e = c->boss_min[i] <= a1 && (a1 % c->win_ante != 0 || ante < 2);
    else
      e = ante % c->win_ante == 0 && ante >= 2;
    if (e) {
      elig[n++] = i;
      if (used[i] <= min_use) min_use = used[i];
    }
  }
  {
    int k = 0;
    for (i = 0; i < n; i++) if (used[elig[i]] <= min_use) elig[k++] = elig[i];
    n = k;
  }
  s = pseudoseed(&c->st, "boss", 4);
  if (s != s) return E_MAP;
  if (n == 0) return E_BOSS;
  /* bosses arrive sorted by key: the survivors are the sorted key list. */
  i = elig[random_int(s, n) - 1];
  used[i]++;
  return i;
}

static int poll_edition(bh_ctx *c, const char *base, int ante)
{
  char key[KEY_MAX];
  size_t kn = make_key(key, base, ante, 1);
  double s = pseudoseed(&c->st, key, kn), poll, r = c->edition_rate;
  if (s != s) return E_MAP;
  poll = random_real(s);
  if (poll > 1 - 0.003 * 1) return 4;
  if (poll > 1 - 0.006 * r * 1) return 3;
  if (poll > 1 - 0.02 * r * 1) return 2;
  if (poll > 1 - 0.04 * r * 1) return 1;
  return 0;
}

static int walk(bh_ctx *c, const char *seed, int antes, int16_t *out)
{
  streams *st = &c->st;
  int used_boss[MAX_POOL];
  uint8_t used_legend[MAX_POOL];
  int a;
  size_t len = strlen(seed);
  if (len >= SEED_MAX) return E_ARGS;
  memcpy(st->seed, seed, len);
  st->seed_len = len;
  st->hashed = bh_pseudohash(seed, len);
  if (++st->gen == 0) { memset(st->slot, 0, sizeof st->slot); st->gen = 1; }
  memcpy(used_boss, c->boss_used0, sizeof(int) * c->n_bosses);
  memset(used_legend, 0, (size_t)c->n_legend);

  for (a = 1; a <= antes; a++) {
    int16_t *o = out + (size_t)(a - 1) * BH_FIELDS;
    const uint8_t *tok = c->tag_ok + (size_t)(a - 1) * c->n_tags;
    int boss = 0, v, t1, t2, leg, ed;
    /* start_run (game.lua:2177-2180): boss, voucher, tags; later antes
     * (state_events.lua:263, button_callbacks.lua:2951-2954): voucher, tags, boss. */
    if (a == 1 && (boss = draw_boss(c, a, used_boss)) < 0) return boss;
    if ((v = pool_draw(st, "Voucher", a, c->n_vouchers, c->voucher_ok, NULL)) < -1) return v;
    if ((t1 = pool_draw(st, "Tag", a, c->n_tags, tok, NULL)) < -1) return t1;
    if ((t2 = pool_draw(st, "Tag", a, c->n_tags, tok, NULL)) < -1) return t2;
    if (a > 1 && (boss = draw_boss(c, a, used_boss)) < 0) return boss;
    /* The Soul: 'Joker4' (no ante in a legendary pool key), used_jokers kept. */
    if ((leg = pool_draw(st, "Joker4", -1, c->n_legend, c->legend_ok, used_legend)) < -1) return leg;
    if (leg >= 0) used_legend[leg] = 1;
    if ((ed = poll_edition(c, "edisou", a)) < 0) return ed;
    o[0] = (int16_t)t1; o[1] = (int16_t)t2; o[2] = (int16_t)boss;
    o[3] = (int16_t)v; o[4] = (int16_t)leg; o[5] = (int16_t)ed;
  }
  return 0;
}

int bh_stable_batch(bh_ctx *c, const char *const *seeds, int n, int antes, int16_t *out)
{
  int i;
  if (!c || !seeds || !out || n < 0 || antes < 1 || antes > c->tag_antes || !c->tag_ok ||
      !c->voucher_ok || !c->boss_ok || !c->legend_ok || c->n_bosses > MAX_POOL)
    return E_ARGS;
  for (i = 0; i < n; i++) {
    int rc = walk(c, seeds[i], antes, out + (size_t)i * antes * BH_FIELDS);
    if (rc < 0) return rc;
  }
  return 0;
}

/* ======================================================================== */
/* T-342: the conditional streams, in the order bhcore.sim.predict documents
 * (predict.lua header: "Inside one shop", "Ante walk"). Mirrors, written from
 * the call order (bodies are not copied):
 *   build/game/functions/common_events.lua
 *     get_pack              :1944-1961  ('shop_pack'..ante; the run's first
 *                                        call is the forced Buffoon, no draw)
 *     get_current_pool      :1963-2053  (the static cull is the caller's mask;
 *                                        here: used_jokers, the fallback, the
 *                                        'rarity'..ante..append roll and the
 *                                        key, Joker..rarity..append..ante)
 *     poll_edition          :2055-2080  (non-guaranteed branch, any _mod)
 *     create_card           :2082-2154  (soul / black hole gates, forced key,
 *                                        pool draw + resamples, 'front', the
 *                                        Joker stickers and 'edi' edition)
 *   build/game/functions/UI_definitions.lua
 *     create_card_for_shop  :742-799    ('cdt', 'illusion'; no tags held, no
 *                                        tutorial forced_shop)
 *   build/game/card.lua
 *     Card:set_ability      :349-354    (used_jokers by name: a group here)
 *     Card:set_eternal/_perishable/_rental :506-523
 *     Card:open             :1715-1768  (Arcana, Celestial + Telescope,
 *                                        Spectral, Standard, Buffoon)
 *     Card:remove           :4742-4748  (clears the name's used_jokers; with
 *                                        no jokers held that is always)
 *   build/game/functions/button_callbacks.lua reroll_shop :2855-2891
 *   build/game/tag.lua apply_to_run 'new_blind_choice' :206-250 (the pack a
 *     skipped Charm / Ethereal tag opens; the map comes from predict.TAG_PACKS)
 * Not modelled (no output reads them): To Do List's 'to_do' draw in
 * set_ability, Showman (no jokers are held in the walk), store_joker tags.
 *
 * Output layout, int16, per (seed, ante), stride bh_shop_stride(rerolls):
 *   [0] small tag, [1] big tag (tag pool indices, -1 = fallback)
 *   3 shop slots, each: [after: -1 absent, 0 Boss, 1 Small, 2 Big], then
 *     joker_max * (1 + rerolls) cards (the row, then each reroll's row),
 *     then 2 packs, each [booster, forced] + max_pack cards
 *   2 tag-pack slots, each: [blind: -1 absent, 0 Small, 1 Big, tag, booster]
 *     + max_pack cards
 *   card = BH_CARD int16: center (-1 = none), edition (0 none, 1 foil, 2 holo,
 *     3 polychrome, 4 negative), stickers (1 eternal, 2 perishable, 4 rental),
 *     seal (0 none, 1 Red, 2 Blue, 3 Gold, 4 Purple), front (sorted P_CARDS
 *     index, -1 none). */

#define BH_CARD 5
#define MAX_CENTERS 1024
#define MAX_ROW 16
#define MAX_PACK 16
#define E_KEY -13  /* a stream key longer than KEY_MAX */
#define E_PACK -14 /* get_pack found no booster (vanilla returns nil) */

static int set_ok(int s) { return s >= BH_SET_OTHER && s <= BH_SET_DEFAULT; }

int bh_set_centers(bh_ctx *c, int n, const int *group, const uint8_t *set,
                   const uint8_t *eternal_compat, const uint8_t *perishable_compat,
                   const uint8_t *banned, const uint8_t *used0)
{
  int i, g = 0;
  if (!c || n < 1 || n > MAX_CENTERS) return -1;
  for (i = 0; i < n; i++) {
    if (group[i] < 0 || group[i] >= n || !set_ok(set[i])) return -1;
    if (group[i] + 1 > g) g = group[i] + 1;
  }
  free(c->center_group); free(c->center_set); free(c->center_eternal);
  free(c->center_perishable); free(c->center_banned); free(c->group_used0);
  c->center_group = dupi(group, (size_t)n);
  c->center_set = dup8(set, (size_t)n);
  c->center_eternal = dup8(eternal_compat, (size_t)n);
  c->center_perishable = dup8(perishable_compat, (size_t)n);
  c->center_banned = dup8(banned, (size_t)n);
  c->group_used0 = calloc((size_t)g, 1);
  c->n_centers = n, c->n_groups = g;
  if (!c->center_group || !c->center_set || !c->center_eternal || !c->center_perishable ||
      !c->center_banned || !c->group_used0)
    return -2;
  for (i = 0; i < n; i++) if (used0[i]) c->group_used0[group[i]] = 1;
  return 0;
}

int bh_set_pool(bh_ctx *c, int which, int n, const int *center, const uint8_t *ok,
                int fallback, int cull_used)
{
  int i;
  if (!c || which < 0 || which >= BH_POOLS || n < 0 || n > MAX_POOL || fallback < 0 ||
      fallback >= c->n_centers)
    return -1;
  for (i = 0; i < n; i++) if (center[i] < 0 || center[i] >= c->n_centers) return -1;
  free(c->pool[which].center); free(c->pool[which].ok);
  c->pool[which].center = dupi(center, (size_t)n);
  c->pool[which].ok = dup8(ok, (size_t)n);
  c->pool[which].n = n;
  c->pool[which].fallback = fallback;
  c->pool[which].cull_used = cull_used != 0;
  return (c->pool[which].center && c->pool[which].ok) ? 0 : -2;
}

int bh_set_specials(bh_ctx *c, int soul, int black_hole, int base)
{
  if (!c || soul < 0 || black_hole < 0 || base < 0 || soul >= c->n_centers ||
      black_hole >= c->n_centers || base >= c->n_centers)
    return -1;
  c->soul = soul, c->black_hole = black_hole, c->base = base;
  return 0;
}

int bh_set_boosters(bh_ctx *c, int n, const double *weight, const uint8_t *ok,
                    const uint8_t *kind, const uint8_t *size, int buffoon, int first_done)
{
  int i, maxs = 0;
  if (!c || n < 1 || n > MAX_POOL || buffoon >= n) return -1;
  for (i = 0; i < n; i++) {
    if (size[i] > MAX_PACK || kind[i] > BH_KIND_BUFFOON) return -1;
    if (size[i] > maxs) maxs = size[i];
  }
  free(c->booster_weight); free(c->booster_ok); free(c->booster_kind); free(c->booster_size);
  c->booster_weight = malloc(sizeof(double) * (size_t)n);
  if (c->booster_weight) memcpy(c->booster_weight, weight, sizeof(double) * (size_t)n);
  c->booster_ok = dup8(ok, (size_t)n);
  c->booster_kind = dup8(kind, (size_t)n);
  c->booster_size = dup8(size, (size_t)n);
  c->n_boosters = n, c->buffoon = buffoon < 0 ? -1 : buffoon, c->first_done = first_done != 0;
  c->max_pack = maxs;
  return (c->booster_weight && c->booster_ok && c->booster_kind && c->booster_size) ? 0 : -2;
}

int bh_set_shop(bh_ctx *c, const double *rates, int joker_max, int flags,
                int telescope, int fronts)
{
  if (!c || joker_max < 0 || joker_max > MAX_ROW || fronts < 1 || telescope >= c->n_centers)
    return -1;
  memcpy(c->rates, rates, sizeof c->rates);
  c->joker_max = joker_max, c->flags = flags, c->telescope = telescope, c->fronts = fronts;
  return 0;
}

int bh_set_tag_packs(bh_ctx *c, int n, const int *booster)
{
  int i;
  if (!c || n < 0 || n > MAX_POOL) return -1;
  for (i = 0; i < n; i++) if (booster[i] >= c->n_boosters) return -1;
  free(c->tag_pack);
  c->tag_pack = dupi(booster, (size_t)n);
  c->n_tag_packs = n;
  return c->tag_pack ? 0 : -2;
}

static int pack_stride(const bh_ctx *c) { return 2 + c->max_pack * BH_CARD; }
static int tagpack_stride(const bh_ctx *c) { return 3 + c->max_pack * BH_CARD; }
static int shop_stride(const bh_ctx *c, int rerolls)
{
  return 1 + c->joker_max * (1 + rerolls) * BH_CARD + 2 * pack_stride(c);
}

int bh_shop_stride(bh_ctx *c, int rerolls)
{
  if (!c || rerolls < 0 || rerolls > 64) return -1;
  return 2 + 3 * shop_stride(c, rerolls) + 2 * tagpack_stride(c);
}

/* Stream keys: base..append..ante and friends, built piecewise. */
typedef struct { char s[KEY_MAX]; size_t n; int bad; } kbuf;

static void kb_s(kbuf *k, const char *s)
{
  size_t l = strlen(s);
  if (k->n + l >= KEY_MAX) { k->bad = 1; return; }
  memcpy(k->s + k->n, s, l);
  k->n += l;
}

static void kb_i(kbuf *k, int v)
{
  char d[16];
  int m = 0;
  do { d[m++] = (char)('0' + v % 10); v /= 10; } while (v);
  if (k->n + (size_t)m >= KEY_MAX) { k->bad = 1; return; }
  while (m) k->s[k->n++] = d[--m];
}

static void kb_init(kbuf *k, const char *a, const char *b, int ante)
{
  k->n = 0, k->bad = 0;
  kb_s(k, a);
  if (b) kb_s(k, b);
  if (ante >= 0) kb_i(k, ante);
}

/* pseudoseed(key); NAN on a bad key or a full stream map. */
static double kseed(streams *st, const kbuf *k)
{
  if (k->bad) return NAN;
  return pseudoseed(st, k->s, k->n);
}

/* pseudorandom(key): pseudoseed, then math.random(). */
static double kreal(streams *st, const kbuf *k)
{
  double s = kseed(st, k);
  return s != s ? s : random_real(s);
}

/* One walk's mutable state besides the streams: used_jokers (by group), the
 * run's first-Buffoon flag and the shop row (centers, for Card:remove). */
typedef struct {
  uint8_t used[MAX_CENTERS];
  int first_done;
  int row[MAX_ROW];
  int n_row;
} shopwalk;

#define USED(w, c, i) ((w)->used[(c)->center_group[i]])

/* A create_card pool draw (get_current_pool + pseudorandom_element and its
 * resamples). Returns a center index, E_MAP or E_KEY. */
static int pool_pick(bh_ctx *c, shopwalk *w, int which, const kbuf *key)
{
  streams *st = &c->st;
  const int *ctr = c->pool[which].center;
  const uint8_t *ok = c->pool[which].ok;
  int n = c->pool[which].n, cull = c->pool[which].cull_used;
  int i, size = 0, it = 1, idx;
  double s;
#define AVAIL(j) (ok[j] && !(cull && USED(w, c, ctr[j])))
  for (i = 0; i < n; i++) size += AVAIL(i);
  s = kseed(st, key);
  if (s != s) return key->bad ? E_KEY : E_MAP;
  if (size == 0) return c->pool[which].fallback;
  idx = random_int(s, n) - 1;
  while (!AVAIL(idx)) {
    kbuf k2 = *key;
    it++;
    kb_s(&k2, "_resample");
    kb_i(&k2, it);
    s = kseed(st, &k2);
    if (s != s) return k2.bad ? E_KEY : E_MAP;
    idx = random_int(s, n) - 1;
  }
#undef AVAIL
  return ctr[idx];
}

/* poll_edition(key, mod, no_neg), non-guaranteed. -> 0..4, or E_MAP. */
static int edition_of(bh_ctx *c, const kbuf *k, double mod, int no_neg)
{
  double poll = kreal(&c->st, k), r = c->edition_rate;
  if (poll != poll) return E_MAP;
  if (poll > 1 - 0.003 * mod && !no_neg) return 4;
  if (poll > 1 - 0.006 * r * mod) return 3;
  if (poll > 1 - 0.02 * r * mod) return 2;
  if (poll > 1 - 0.04 * r * mod) return 1;
  return 0;
}

static const char *const TYPE_NAME[] = {"", "Joker", "Tarot", "Planet", "Spectral", "Enhanced", "Base"};
#define T_BASE BH_SET_DEFAULT /* the type 'Base' makes c_base, set 'Default' */

/* create_card(t, area, nil, nil, _, soulable, forced, app) for the shop row
 * (pack = 0) or a pack (pack = 1). Writes one card at o. Returns 0 or an
 * error code. */
static int create(bh_ctx *c, shopwalk *w, int t, int pack, int soulable, int forced,
                  const char *app, int ante, int16_t *o)
{
  streams *st = &c->st;
  int center, e;
  kbuf k;
  double p;
  if (forced < 0 && soulable && !c->center_banned[c->soul]) {
    if ((t == BH_SET_TAROT || t == BH_SET_SPECTRAL) && !USED(w, c, c->soul)) {
      kb_init(&k, "soul_", TYPE_NAME[t], ante);
      if (isnan(p = kreal(st, &k))) return E_MAP;
      if (p > 0.997) forced = c->soul;
    }
    if ((t == BH_SET_PLANET || t == BH_SET_SPECTRAL) && !USED(w, c, c->black_hole)) {
      kb_init(&k, "soul_", TYPE_NAME[t], ante);
      if (isnan(p = kreal(st, &k))) return E_MAP;
      if (p > 0.997) forced = c->black_hole;
    }
  }
  if (t == T_BASE) forced = c->base;
  if (forced >= 0 && !c->center_banned[forced]) {
    center = forced;
    if (c->center_set[center] != BH_SET_DEFAULT) t = c->center_set[center];
  } else {
    int which;
    if (t == BH_SET_JOKER) {
      int rarity;
      kb_init(&k, "rarity", NULL, ante);
      kb_s(&k, app);
      if (isnan(p = kreal(st, &k))) return k.bad ? E_KEY : E_MAP;
      rarity = p > 0.95 ? 3 : p > 0.7 ? 2 : 1;
      kb_init(&k, "Joker", NULL, rarity);
      kb_s(&k, app);
      kb_i(&k, ante);
      which = BH_POOL_JOKER1 + rarity - 1;
    } else {
      switch (t) {
      case BH_SET_TAROT: which = BH_POOL_TAROT; break;
      case BH_SET_PLANET: which = BH_POOL_PLANET; break;
      case BH_SET_SPECTRAL: which = BH_POOL_SPECTRAL; break;
      case BH_SET_ENHANCED: which = BH_POOL_ENHANCED; break;
      default: return E_ARGS; /* a banned c_base: no 'Base' pool here */
      }
      kb_init(&k, TYPE_NAME[t], app, ante);
    }
    if ((center = pool_pick(c, w, which, &k)) < 0) return center;
  }
  o[0] = (int16_t)center, o[1] = 0, o[2] = 0, o[3] = 0, o[4] = -1;
  if (t == T_BASE || t == BH_SET_ENHANCED) {
    double s;
    kb_init(&k, "front", app, ante);
    if (isnan(s = kseed(st, &k))) return E_MAP;
    o[4] = (int16_t)(random_int(s, c->fronts) - 1);
  }
  USED(w, c, center) = 1;
  if (t == BH_SET_JOKER) {
    int eternal = 0, perishable = 0, rental = 0;
    int ecompat = c->center_eternal[center], pcompat = c->center_perishable[center];
    if (c->flags & BH_F_ALL_ETERNAL) eternal = ecompat && !perishable;
    kb_init(&k, pack ? "packetper" : "etperpoll", NULL, ante);
    if (isnan(p = kreal(st, &k))) return E_MAP;
    if ((c->flags & BH_F_ETERNALS) && p > 0.7)
      eternal = ecompat && !perishable;
    else if ((c->flags & BH_F_PERISHABLES) && p > 0.4 && p <= 0.7)
      perishable = pcompat && !eternal;
    if (c->flags & BH_F_RENTALS) {
      kb_init(&k, pack ? "packssjr" : "ssjr", NULL, ante);
      if (isnan(p = kreal(st, &k))) return E_MAP;
      if (p > 0.7) rental = 1;
    }
    kb_init(&k, "edi", app, ante);
    if ((e = edition_of(c, &k, 1.0, 0)) < 0) return e;
    o[1] = (int16_t)e;
    o[2] = (int16_t)(eternal | perishable << 1 | rental << 2);
  }
  return 0;
}

/* Card:remove on every card of the row (reroll, leaving the shop). */
static void release_row(bh_ctx *c, shopwalk *w)
{
  while (w->n_row > 0) {
    w->n_row--;
    USED(w, c, w->row[w->n_row]) = 0;
  }
}

/* create_card_for_shop(G.shop_jokers) with no tags held. */
static int shop_card(bh_ctx *c, shopwalk *w, int ante, int16_t *o)
{
  streams *st = &c->st;
  const double *r = c->rates;
  int types[5], i, rc, t = -1;
  double total = r[0] + r[1] + r[2] + r[3] + r[4], polled, check = 0, p;
  kbuf k;
  kb_init(&k, "cdt", NULL, ante);
  if (isnan(polled = kreal(st, &k))) return E_MAP;
  polled = polled * total;
  types[0] = BH_SET_JOKER, types[1] = BH_SET_TAROT, types[2] = BH_SET_PLANET;
  types[3] = T_BASE, types[4] = BH_SET_SPECTRAL;
  /* The playing-card entry's type is decided while the list is built. */
  if (c->flags & BH_F_ILLUSION) {
    kb_init(&k, "illusion", NULL, -1);
    if (isnan(p = kreal(st, &k))) return E_MAP;
    if (p > 0.6) types[3] = BH_SET_ENHANCED;
  }
  for (i = 0; i < 5; i++) {
    if (polled > check && polled <= check + r[i]) { t = types[i]; break; }
    check = check + r[i];
  }
  if (t < 0) { o[0] = -1; return 0; }
  if ((rc = create(c, w, t, 0, 0, -1, "sho", ante, o)) < 0) return rc;
  if ((t == T_BASE || t == BH_SET_ENHANCED) && (c->flags & BH_F_ILLUSION)) {
    kb_init(&k, "illusion", NULL, -1);
    if (isnan(p = kreal(st, &k))) return E_MAP;
    if (p > 0.8) {
      if (isnan(p = kreal(st, &k))) return E_MAP;
      o[1] = p > 1 - 0.15 ? 3 : p > 0.5 ? 2 : 1;
    }
  }
  w->row[w->n_row++] = o[0];
  return 0;
}

/* get_pack('shop_pack'): the booster index; *forced = the run's first Buffoon. */
static int get_pack(bh_ctx *c, shopwalk *w, int ante, int *forced)
{
  double cume = 0, it = 0, poll;
  int i;
  kbuf k;
  *forced = 0;
  if (!w->first_done && c->buffoon >= 0) {
    w->first_done = 1;
    *forced = 1;
    return c->buffoon;
  }
  for (i = 0; i < c->n_boosters; i++) if (c->booster_ok[i]) cume = cume + c->booster_weight[i];
  kb_init(&k, "shop_pack", NULL, ante);
  if (isnan(poll = kreal(&c->st, &k))) return E_MAP;
  poll = poll * cume;
  for (i = 0; i < c->n_boosters; i++) {
    if (!c->booster_ok[i]) continue;
    it = it + c->booster_weight[i];
    if (it >= poll && it - c->booster_weight[i] <= poll) return i;
  }
  return E_PACK;
}

/* Card:open's cards for booster b, then the pack closed with nothing taken
 * (each card removed). Writes booster_size cards at o. */
static int open_pack(bh_ctx *c, shopwalk *w, int b, int ante, int16_t *o)
{
  streams *st = &c->st;
  int i, rc, size = c->booster_size[b], kind = c->booster_kind[b];
  kbuf k;
  double p;
  for (i = 1; i <= size; i++) {
    int16_t *co = o + (i - 1) * BH_CARD;
    switch (kind) {
    case BH_KIND_ARCANA: {
      int spectral = 0;
      if (c->flags & BH_F_OMEN_GLOBE) {
        kb_init(&k, "omen_globe", NULL, -1);
        if (isnan(p = kreal(st, &k))) return E_MAP;
        spectral = p > 0.8;
      }
      rc = spectral ? create(c, w, BH_SET_SPECTRAL, 1, 1, -1, "ar2", ante, co)
                    : create(c, w, BH_SET_TAROT, 1, 1, -1, "ar1", ante, co);
      break;
    }
    case BH_KIND_CELESTIAL:
      rc = create(c, w, BH_SET_PLANET, 1, 1,
                  (c->flags & BH_F_TELESCOPE) && i == 1 ? c->telescope : -1, "pl1", ante, co);
      break;
    case BH_KIND_SPECTRAL:
      rc = create(c, w, BH_SET_SPECTRAL, 1, 1, -1, "spe", ante, co);
      break;
    case BH_KIND_STANDARD: {
      int t, e;
      kb_init(&k, "stdset", NULL, ante);
      if (isnan(p = kreal(st, &k))) return E_MAP;
      t = p > 0.6 ? BH_SET_ENHANCED : T_BASE;
      if ((rc = create(c, w, t, 1, 1, -1, "sta", ante, co)) < 0) return rc;
      kb_init(&k, "standard_edition", NULL, ante);
      if ((e = edition_of(c, &k, 2.0, 1)) < 0) return e;
      co[1] = (int16_t)e;
      kb_init(&k, "stdseal", NULL, ante);
      if (isnan(p = kreal(st, &k))) return E_MAP;
      if (p > 1 - 0.02 * 10) {
        kb_init(&k, "stdsealtype", NULL, ante);
        if (isnan(p = kreal(st, &k))) return E_MAP;
        co[3] = p > 0.75 ? 1 : p > 0.5 ? 2 : p > 0.25 ? 3 : 4;
      }
      break;
    }
    case BH_KIND_BUFFOON:
      rc = create(c, w, BH_SET_JOKER, 1, 1, -1, "buf", ante, co);
      break;
    default:
      return E_ARGS;
    }
    if (rc < 0) return rc;
  }
  for (i = size; i >= 1; i--) USED(w, c, o[(i - 1) * BH_CARD]) = 0;
  return 0;
}

/* One shop (predict.ante_walk's walk_shop, cards and open on). */
static int shop_visit(bh_ctx *c, shopwalk *w, int ante, int after, int rerolls, int16_t *o)
{
  int jm = c->joker_max, j, r, p, rc;
  int16_t *cards = o + 1, *packs = o + 1 + jm * (1 + rerolls) * BH_CARD;
  o[0] = (int16_t)after;
  release_row(c, w);
  for (j = 0; j < jm; j++)
    if ((rc = shop_card(c, w, ante, cards + j * BH_CARD)) < 0) return rc;
  for (p = 0; p < 2; p++) {
    int forced, b = get_pack(c, w, ante, &forced);
    if (b < 0) return b;
    packs[p * pack_stride(c)] = (int16_t)b;
    packs[p * pack_stride(c) + 1] = (int16_t)forced;
  }
  for (r = 1; r <= rerolls; r++) {
    release_row(c, w);
    for (j = 0; j < jm; j++)
      if ((rc = shop_card(c, w, ante, cards + (r * jm + j) * BH_CARD)) < 0) return rc;
  }
  for (p = 0; p < 2; p++) {
    int16_t *po = packs + p * pack_stride(c);
    if ((rc = open_pack(c, w, po[0], ante, po + 2)) < 0) return rc;
  }
  release_row(c, w);
  return 0;
}

static void begin_seed(streams *st, const char *seed, size_t len)
{
  memcpy(st->seed, seed, len);
  st->seed_len = len;
  st->hashed = bh_pseudohash(seed, len);
  if (++st->gen == 0) { memset(st->slot, 0, sizeof st->slot); st->gen = 1; }
}

static int shop_walk(bh_ctx *c, const char *seed, int antes, int skip, int rerolls,
                     int stride, int16_t *out)
{
  streams *st = &c->st;
  shopwalk w;
  int a, i;
  size_t len = strlen(seed);
  if (len >= SEED_MAX) return E_ARGS;
  begin_seed(st, seed, len);
  memcpy(w.used, c->group_used0, (size_t)c->n_groups);
  w.first_done = c->first_done;
  w.n_row = 0;
  for (i = 0; i < antes * stride; i++) out[i] = -1;

  for (a = 1; a <= antes; a++) {
    int16_t *o = out + (size_t)(a - 1) * stride;
    int16_t *shops = o + 2, *tps = o + 2 + 3 * shop_stride(c, rerolls);
    const uint8_t *tok = c->tag_ok + (size_t)(a - 1) * c->n_tags;
    int tags[2], blind, si = 0, ti = 0, rc;
    /* predict.ante_walk draws the ante's tags itself ('Tag'..a, a per-ante
     * stream: its place among the shop draws is free). */
    if ((tags[0] = pool_draw(st, "Tag", a, c->n_tags, tok, NULL)) < -1) return tags[0];
    if ((tags[1] = pool_draw(st, "Tag", a, c->n_tags, tok, NULL)) < -1) return tags[1];
    o[0] = (int16_t)tags[0], o[1] = (int16_t)tags[1];
    /* The shop after the Boss of ante a-1 comes after ease_ante. */
    if (a > 1 && (rc = shop_visit(c, &w, a, 0, rerolls, shops + si++ * shop_stride(c, rerolls))) < 0)
      return rc;
    for (blind = 0; blind < 2; blind++) {
      if (skip & (1 << blind)) {
        int tag = tags[blind], b = tag >= 0 && tag < c->n_tag_packs ? c->tag_pack[tag] : -1;
        if (b >= 0) {
          int16_t *tp = tps + ti++ * tagpack_stride(c);
          tp[0] = (int16_t)blind, tp[1] = (int16_t)tag, tp[2] = (int16_t)b;
          if ((rc = open_pack(c, &w, b, a, tp + 3)) < 0) return rc;
        }
      } else if ((rc = shop_visit(c, &w, a, blind + 1, rerolls,
                                  shops + si++ * shop_stride(c, rerolls))) < 0) {
        return rc;
      }
    }
  }
  return 0;
}

int bh_shop_batch(bh_ctx *c, const char *const *seeds, int n, int antes, int skip,
                  int rerolls, int16_t *out)
{
  int i, stride = bh_shop_stride(c, rerolls);
  if (!c || !seeds || !out || n < 0 || antes < 1 || antes > c->tag_antes || !c->tag_ok ||
      stride < 0 || c->n_centers < 1 || c->soul < 0 || !c->booster_ok || !c->tag_pack ||
      c->n_tag_packs != c->n_tags || c->fronts < 1)
    return E_ARGS;
  for (i = 0; i < BH_POOLS; i++) if (!c->pool[i].ok) return E_ARGS;
  for (i = 0; i < n; i++) {
    int rc = shop_walk(c, seeds[i], antes, skip, rerolls, stride, out + (size_t)i * antes * stride);
    if (rc < 0) return rc;
  }
  return 0;
}
