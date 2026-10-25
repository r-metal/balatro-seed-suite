-- seedfinder.filter: the Seed Finder's filter model. A filter is plain data
-- (no floats, so it round-trips through STR_PACK); eval reads what a seed
-- generates through bhcore.sim.predict only, never by re-deriving the RNG.
-- Contract: docs/contracts-0.2.md § SeedFinder "Filter model".
--
-- Shape
--   {name = string, stake = 1..8 (1), deck = 'b_...' ('b_red'),
--    all_unlocked = bool (false), antes = N (the highest clause ante),
--    mode = 'all'|'any' ('all'), clauses = {clause, ...}}
--   Clause kinds (ante is 1..antes):
--     {kind = 'tag', ante, blind = 'Small'|'Big'|'any' ('any'), key = 'tag_...',
--      by = bool (false)}
--     {kind = 'boss', ante, key = 'bl_...', by = bool (false)}
--     {kind = 'voucher', ante, key = 'v_...', by = bool (false)}
--       by (T-313a, boss T-375; additive: without it a clause means exactly
--       its ante): "by ante N", N = ante. A voucher: the shop Voucher of some
--       ante 1..N, each as the plain clause predicts it (the walk's purchases:
--       Policies, voucher clauses). A tag:
--       key is on the clause's blind (Small, Big or any) in some ante 1..N. A
--       boss: key is the Boss of some ante 1..N, each as the plain clause
--       predicts it (no boss rerolls). Only these three kinds take by (a joker
--       clause is "by ante N" already).
--     {kind = 'legendary', index = 1|2, key = 'j_...' or nil (any),
--      edition = <edition> or nil (any)}
--     {kind = 'soul_in_pack', ante, pack = 'arcana'|'spectral', from_tag = bool}
--     {kind = 'shop_joker', ante, key = <center key>, rerolls = 0.. (0),
--      edition = <edition> or nil (any), sticker = 'none' or nil (any)}
--     {kind = 'pack', ante, key_prefix = 'p_...'}
--     {kind = 'joker', ante, key = 'j_...', rerolls = 0.. (0),
--      from = 'shop'|'buffoon'|'both' ('both'), edition = <edition> or nil,
--      sticker = 'none' or nil (any)}
--       "by ante N": the joker shows up in any shop of antes 1..ante (with R
--       rerolls per shop) and/or any shop Buffoon pack of those antes. Not a
--       legendary (no shop or Buffoon pack makes one: the Soul does).
--   <edition> is 'foil'|'holo'|'polychrome'|'negative'|'any' ('any' = some
--   edition, not a base card), compared with predict's edition name (cards
--   carry edition = <name> or nil; legendaries {key, edition}). A legendary
--   clause with an edition and no key: the Soul makes a legendary of that
--   edition. A shop_joker's key stays required.
--   sticker (T-375, additive; shop_joker and joker only): 'none' = the card
--   that counts carries no eternal, perishable or rental sticker (predict's
--   cards carry stickers = {eternal, perishable, rental}, shop rows and pack
--   cards alike). A stickered copy of the key is not a hit: the search goes on
--   to the next candidate within the clause's budget (the next slot, reroll,
--   shop, pack or ante), exactly as for a copy of the wrong edition. Stickers
--   only exist from Black Stake up (the stake's enable_*_in_shop modifiers,
--   sim/card.lua), so on a lower stake the clause reads as without sticker.
--   exclude (T-375, additive: must-not): any plain clause at the top level of
--   a mode-'all' filter may carry exclude = bool (false). exclude = true holds
--   when the same clause without exclude fails: "no Plant by ante 3" is
--   {kind = 'boss', ante = 3, key = 'bl_plant', by = true, exclude = true}.
--   exclude (either value) is refused on a group member and in mode 'any' (a
--   must-not is never one option among several); exclude = false is the
--   plain clause.
--   Any-of groups (one level, a locked decision): a top-level entry of
--   f.clauses may be {kind = 'group', clauses = {clause, ...}}, 2..MAX_GROUP
--   plain clauses (never a group), which holds when any member holds; f.mode
--   still combines the top-level entries. Everything said of "every clause"
--   below (antes, needs, chaining) counts each member as a clause of f.
--   validate names a member's problem by its path: "clause 2, member 3 ...".
--
-- API
--   filter.validate(f)        -> true, or nil, err (the first problem found).
--   filter.eval(S, f)         -> bool, details. S is state.fresh(seed, ...) for
--                                f's stake/deck/all_unlocked and is consumed
--                                (its streams advance). Raises on an invalid f.
--   filter.fresh(f, seed)     -> state.fresh(seed, {stake, deck, all_unlocked})
--                                with f's defaults applied.
--   filter.eval_seed(f, seed) -> filter.eval(filter.fresh(f, seed), f).
--   filter.serialize(f)       -> STR_PACK string, or nil, err (invalid f).
--   filter.deserialize(s)     -> f, or nil, err. The string is loaded in an
--                                empty environment and the result validated.
--   filter.plain_clauses(f)   -> every plain clause of f in written order, a
--                                group's members in the group's place (the
--                                clauses the walk's needs are made of). With
--                                no group it is f.clauses itself: read only.
--   filter.prerequisites(key) -> the vouchers `key` requires, and what those
--                                require (a list, any order).
--   filter.purchase_rules(f)  -> the walk's purchase rules (Policies: voucher
--                                clauses), one per voucher a positive voucher
--                                clause buys (members included):
--                                {clause, key, lo, hi, own}. key is bought at
--                                the first ante lo..hi whose shop offers it;
--                                own: the clause's own voucher, else one it
--                                requires. None for Hieroglyph or Petroglyph.
--   filter.voucher_findable(key) -> true, or false and the voucher key needs
--                                that the walk never buys (Policies: voucher
--                                clauses; Petroglyph's Hieroglyph). validate
--                                refuses a voucher clause on such a key.
--   details = {checked = <clauses evaluated>, results = {[i] = {ok, ...}},
--              tag_packs = {[a] = <packs>} or nil,
--              skips = {[a] = {Small = tag, Big = tag}} or nil,
--              bought = {[a] = voucher key} or nil,
--              walked = <the highest ante the walk passed, 0 if none>}
--   results is indexed by the clause's position in f.clauses. Unevaluated
--   clauses (the short-circuit) have no entry. checked counts top-level
--   entries. tag_packs holds the tag packs (soul_in_pack from_tag's packs
--   shape) the walk opened: every chained ante it walked, whether or not a
--   from_tag clause there was evaluated (a group member may not be), and any
--   other walked ante where a taken pack tag opened one. skips holds the
--   blinds the walk skipped, per walked ante (taken tags, a chained ante's
--   pack tags), and ante 1's when it was not walked but both its blinds are
--   skipped (Policies: the forced Buffoon). bought holds the vouchers the
--   walk bought (Policies: voucher clauses), at every ante the eval drew a
--   voucher it could buy at. route.lua replays all three. What each
--   result carries:
--     group: hit = the index (in the group's clauses) of the member that
--       held, nil on a miss; results = {[m] = member details}, the members
--       evaluated, each with its own ok and its kind's fields below;
--     tag: small, big; boss/voucher: key; legendary: key, edition;
--     tag / boss / voucher with by: on a hit, ante (the first ante 1..N that
--       holds) and that ante's plain details (tag: small, big; boss and
--       voucher: key), plus a tag's blind ('Small' or 'Big': where the tag
--       is, Small first); a miss carries nothing;
--     soul_in_pack from_tag: packs = {{blind, tag, pack, cards, soul}...} and,
--       on a hit, blind/tag/pack/index (the blind to skip, the Soul's slot);
--     soul_in_pack (shop): shop, slot, pack, index, after (the blind the shop
--       follows: 'Boss' of the previous ante, 'Small' or 'Big');
--     shop_joker: shop, reroll (0 = the row on entering), slot;
--     pack: shop, slot, pack;
--     joker: ante, shop, after, and either reroll (the row, 0 = on entering)
--       and index (its slot in the row), or pack_slot (the Buffoon pack's
--       shop slot), pack (its key) and index (the joker's place in the pack).
--     A clause with sticker = 'none' reports the first clean copy it found,
--       in the same fields.
--     An excluded clause: ok is its own result (true when the positive form
--       failed). When ok is true it carries nothing else; when the positive
--       form held, it carries that form's details as listed above (what the
--       Finder's "why not" line names: the ante, shop, slot... it was seen).
--
-- Evaluation order: cheapest first (contract): tags, boss, voucher,
-- legendary, tag packs, shop packs, shop pack contents, shop cards, jokers
-- by ante N (they walk every ante up to N); ties by ante, then by position. 'all' stops at the first false clause, 'any' at the
-- first true one. A tag, boss or voucher clause with by stays in its kind's
-- class (it reads the same streams), with N as its ante for ties. An
-- excluded clause keeps its kind's class and ante too: it draws exactly what
-- its positive form draws, and only its result is negated (so in 'all' it
-- ends the eval when its positive form holds). A group
-- sorts as its cheapest member (that member's class, then its ante); its
-- members run cheapest first by the same rule, and the first one that holds
-- ends the group. Each stream is drawn once per S and shared by the clauses,
-- group members included:
--   * tags(S, a) and voucher(S, a) once per ante (per-ante streams, order-free;
--     a by clause reads antes 1, 2, ... N through the same memo and stops at
--     the first that holds, so no ante is drawn twice for it either). Ante
--     a's voucher pool leaves out what the walk bought below a (Policies:
--     voucher clauses), so every lower ante the walk may buy at is drawn
--     first, in ascending order; the walk draws those too, to know what it
--     buys where (still once each, through the memo);
--     boss(S, 1..a) in ascending order (the 'boss' stream is global), each
--     ante once: a boss clause with by reads bosses 1, 2, ... N through the
--     same memo and stops at the first that holds, and a later boss clause
--     (plain or by) continues from the last ante drawn. The shop walk draws
--     none of them, so a member read after a walk sees the same keys.
--   * legendaries on a copy of S when a later step (clause or member, in
--     evaluation order) may still read S's shop or pack streams (plan does
--     the same: no Soul is used under the policy, so 'Joker4' stays put).
--     Only legendaries draw 'Joker4' and 'edisou', so the one input another
--     step can move is the ante A the Soul's edition reads ('edisou'..A).
--     A is fixed by f: the ante S stands at once every tag, boss and voucher
--     step of f (members included) is drawn in class order, i.e. the highest
--     voucher ante, else the highest boss ante, else the highest tag ante,
--     else S's own (1 on a fresh S). A by clause counts as its N (the ante it
--     draws up to when it misses), wherever it stopped. In a plain filter all
--     of those precede the legendary steps, so A is where S stands then (as
--     since T-310), unless a by clause stopped below its N: the legendaries
--     are then drawn on a copy of S set to A. A group can end before a tag,
--     boss or voucher member is drawn, or walk S
--     first (shops, or tag packs drawn on S itself): the legendaries are then
--     drawn on a copy of S set to A (before the first such walk, if any). So a
--     legendary step reads what a plain clause in its place reads, whichever
--     members ran. (Alone, a legendary reads S's own ante: beside a tag, boss
--     or voucher step above ante 1 its edition can differ from its alone
--     result, in a plain filter as in a group.)
--
-- Policies (what a hit promises; predict.lua's header has the stream map)
--   tag clauses are taken: the player takes a tag by skipping its blind, so
--     wherever a positive tag clause (top level or group member; not an
--     excluded one) holds, the walk skips that blind: its shop never happens.
--     A plain clause takes its blind at its ante (Small first for blind
--     'any'), a by clause the first ante and blind it holds at (as its details
--     say). A skipped blind whose tag gives a pack opens it at the skip
--     (predict.ALL_TAG_PACKS: Charm, Meteor, Ethereal, Standard, Buffoon),
--     closed with nothing taken. Tags that act on a later shop or the jokers
--     (Uncommon, Rare, edition tags, Top-up, Voucher, Boss, Double...) are not
--     modelled: a walk that takes one is conditional on it. 0.4.0 played such
--     a blind instead, so a hit could rest on a shop the tag's skip removes.
--     The forced first Buffoon lands in the run's first shop: ante 1's, or ante
--     2's Boss shop when both ante-1 blinds are skipped (taken tags; chained
--     pack tags; or, when ante 1 is not walked, a separate from_tag branch
--     there, which skips its pack-tag blinds).
--   voucher clauses are bought: wherever a positive voucher clause (top level
--     or group member; not an excluded one) holds, the player buys that
--     voucher, a plain clause at its ante and a by clause at the first ante it
--     holds at. A tier-2 voucher's clause also buys what it `requires` (and
--     what that requires): at the first ante below the clause's ante (N for
--     by) whose shop offers it. Each voucher is bought once, at the first ante
--     a rule buys it, so a later clause on it never sees it again. Ante a's
--     voucher is drawn with every purchase below a redeemed (predict.voucher's
--     used): the pool leaves those out and admits their tier-2 vouchers. 0.4.0
--     bought nothing, so no tier-2 voucher ever showed, and a hit beside a
--     voucher clause could rest on that voucher left unbought.
--     The purchase is made in the ante's first shop right after entering (the
--     shop after the previous Boss; at ante 1 the first blind played), and
--     what it changes for generation holds for the rest of the walk
--     (state.redeem: used_vouchers, the rates, Overstock's slot, filled at
--     once in that shop). A purchase at an ante the walk does not walk is
--     applied to S there all the same; a separate tag branch's packs see the
--     vouchers bought by their skips (Omen Globe), the only effect they read.
--     Ante 1 offers no voucher when both its blinds are skipped (taken tags,
--     or the pack tags a from_tag clause there skips): a voucher clause does
--     not hold at ante 1 then. Hieroglyph and Petroglyph are never bought
--     (state.REWINDS: the -1 ante replays an ante, which the walk does not
--     model), so a Hieroglyph clause holds where it is offered, and a
--     Petroglyph clause, which could only hold after a Hieroglyph purchase,
--     is refused by validate. Discounts (Clearance Sale, Liquidation, Reroll
--     Surplus/Glut) change no draw.
--   soul_in_pack from_tag: at ante A, every Small/Big blind whose tag is a
--     Charm Tag (Mega Arcana, 5 cards) or an Ethereal Tag (Spectral Pack, 2
--     cards) is skipped, Small first. Vanilla opens that pack at the skip
--     (tag.lua:206-250, G.FUNCS.use_card -> Card:open, ante-A streams), so the
--     packs are predict.ante_walk's tag packs for ante A with both blinds
--     skipped (predict.TAG_PACKS; A > 1 draws the Boss shop's pack keys
--     first, which no pack's contents read). Nothing is
--     taken. Shops before the skip open no packs (their cards draw other
--     streams and are released on leaving), and no held tag opens a pack
--     first (skip_blind applies only the first new_blind_choice tag). The
--     Charm pack's _1/_2 art variant is unseeded math.random with the same
--     config; p_arcana_mega_1 stands for both. Ethereal has min_ante 2.
--   The walk: every walked ante is one predict.ante_walk(S, A, policy) call
--   (docs/bh-core.md § sim.predict), in ascending ante order; the policies
--   below are the skip / rerolls / open / cards it is given.
--   shop clauses: no skips but taken tags, no purchases but bought vouchers, the plan policy per shop (enter,
--     2 packs, R rerolls, open every pack in slot order when a clause needs
--     contents, leave), where R is the most rerolls a shop_joker clause asks
--     for at that ante. R is made in every shop of the ante: rerolls continue
--     the ante's 'cdt'/'...sho' streams, so they move the next shop's row too
--     (a rerolls = 0 clause beside a rerolls = 2 one at the same ante reads
--     the entering rows of that R = 2 walk). The shops of ante A are the ones
--     drawing ante-A streams: the one after the Boss of A-1 (none for A = 1), then after
--     the Small and Big of A. A shop index s is exact for any skips, since
--     the streams count shops, not blinds. Antes no clause needs are not
--     walked (every shop stream is keyed by ante); the run's forced first
--     Buffoon pack is still spent in ante 1 (predict.packs(S, 1, 1)).
--   joker clauses: every ante 1..N is a shop-clause ante under the same plan
--     policy, merged with the other shop clauses there (R is the most any
--     shop_joker or joker clause at that ante asks for; a joker clause with
--     from 'buffoon' or 'both' opens every pack). Within the walk the first
--     hit in play order counts: ante, shop, then the rows (entering, reroll
--     1..R), then the shop's Buffoon packs in slot order (they are opened
--     after the R rerolls). The ante of a hit is chained when that ante has a
--     from_tag clause, as for any shop clause.
--   Chained antes: at an ante with both a from_tag clause and a shop clause,
--   the two policies are one playthrough. The pack-tag blinds (and taken
--   tags' blinds) are skipped, so the shop after a skipped blind never
--   happens, and everything is drawn on S in the game's order: (A > 1) the
--   shop after the previous Boss, then per blind, Small first, its tag pack
--   at the skip or its shop when it is played: ante_walk with skip set on the
--   blinds whose tag gives a pack or is taken.
--   The order matters: a tag pack and a shop pack of the same kind
--   share the ante's streams (Tarot'ar1'A and 'soul_Tarot'A for Arcana), so
--   each changes what the other holds. Nothing is taken from a tag pack; a
--   player who takes its Soul must use it before opening a shop pack, since
--   no Soul rolls while one exists (common_events.lua:2090). Checked against
--   the real game by rig/scenarios/finder_chain.lua.
--   Elsewhere tag packs and shop packs are separate branches: the tag packs
--   are drawn on a copy of S taken before the first shop walk, so each
--   clause holds under its own policy. A fresh S applies the deck's queued
--   events that generation reads (docs/bh-core.md § sim.state).
--   Groups: every member's needs join the walk (R, open, the antes a joker
--   member walks) and a from_tag member makes its ante chained, whether or
--   not the member is reached, so the walk is fixed by f alone and no ante is
--   walked twice. A member therefore reads the same walk a plain clause in
--   its place would, and a hit's route replays that walk (route.lua). The
--   one input a walk could still move, the ante of the Soul's edition, is
--   fixed by f too (Evaluation order: legendaries).
--   Excluded clauses: their needs join the walk exactly as their positive
--   form's would (R, open, the antes a joker clause walks, a from_tag clause
--   chaining its ante). So a must-not is judged on the same shops and packs
--   the other clauses are, and the route (which gives an excluded clause no
--   step of its own) replays that walk.
local state = require('bhcore.sim.state')
local predict = require('bhcore.sim.predict')

local M = {}

M.MAX_ANTE = 16
M.MAX_REROLLS = 20
M.MAX_GROUP = 6
-- The plain clause kinds (a group is not one: see the header).
M.KINDS = {'tag', 'boss', 'voucher', 'legendary', 'soul_in_pack', 'shop_joker', 'pack', 'joker'}
M.FROM = {'shop', 'buffoon', 'both'}

-- Cost classes, cheapest first.
local TAG, BOSS, VOUCHER, LEGEND, TAG_PACK, PACK, SHOP_PACK, SHOP_CARD, BY_ANTE = 1, 2, 3, 4, 5, 6, 7, 8, 9

local PACK_KIND = {arcana = 'Arcana', spectral = 'Spectral'}
M.EDITIONS = {'foil', 'holo', 'polychrome', 'negative', 'any'}
local EDITION = {}
for _, e in ipairs(M.EDITIONS) do EDITION[e] = true end
local FROM = {}
for _, v in ipairs(M.FROM) do FROM[v] = true end
local SOUL = 'c_soul'

------------------------------------------------------------------------------
-- Validation

local function is_int(v, lo, hi)
  return type(v) == 'number' and v % 1 == 0 and v >= lo and v <= hi
end

-- Checks a key against a prototype table when the game's are loaded.
local function known(tbl, key, pred)
  if type(tbl) ~= 'table' then return true end
  local v = tbl[key]
  return v ~= nil and (not pred or pred(v))
end

local function P(name) return G and G[name] end

-- What voucher `key` requires, and what that requires (any order).
local function prerequisites(key)
  local out, seen = {}, {[key] = true}
  local function add(k)
    local v = P('P_CENTERS') and G.P_CENTERS[k]
    local req = type(v) == 'table' and type(v.requires) == 'table' and v.requires or {}
    for _, r in pairs(req) do
      if not seen[r] then seen[r] = true; out[#out + 1] = r; add(r) end
    end
  end
  add(key)
  return out
end
M.prerequisites = prerequisites

-- A voucher the walk never buys (Policies: voucher clauses).
local function rewinds(key)
  local v = P('P_CENTERS') and G.P_CENTERS[key]
  return type(v) == 'table' and state.REWINDS[v.name] == true
end

local function center_name(key)
  local v = P('P_CENTERS') and G.P_CENTERS[key]
  return type(v) == 'table' and v.name or tostring(key)
end

-- A voucher the walk can make show: not one that needs a voucher it never buys.
function M.voucher_findable(key)
  for _, r in ipairs(prerequisites(key)) do
    if rewinds(r) then return false, r end
  end
  return true
end

local FIELDS = {
  tag = {kind = true, ante = true, blind = true, key = true, by = true},
  boss = {kind = true, ante = true, key = true, by = true},
  voucher = {kind = true, ante = true, key = true, by = true},
  legendary = {kind = true, index = true, key = true, edition = true},
  soul_in_pack = {kind = true, ante = true, pack = true, from_tag = true},
  shop_joker = {kind = true, ante = true, key = true, rerolls = true, edition = true, sticker = true},
  pack = {kind = true, ante = true, key_prefix = true},
  joker = {kind = true, ante = true, key = true, rerolls = true, from = true, edition = true, sticker = true},
}
-- Every plain kind takes exclude (validate limits where: top level, mode 'all').
for _, fields in pairs(FIELDS) do fields.exclude = true end

local function prefixed(v, p)
  return type(v) == 'string' and #v > #p and v:sub(1, #p) == p
end

-- Whether t is a list (1..n, no holes, no other keys); its length.
local function list_len(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do
    if t[i] == nil then return nil end
  end
  return n
end

local check_group

-- where: 'clause i' or, for a group member, 'clause i, member m'. top: a
-- top-level entry; any: f's mode is 'any'.
local function check_clause(c, where, antes, top, any)
  if type(c) ~= 'table' then return where..': not a table' end
  if c.kind == 'group' then
    if not top then return where..': a group cannot hold a group (groups nest one level)' end
    return check_group(c, where, antes)
  end
  local fields = FIELDS[c.kind]
  if not fields then return where..': unknown kind '..tostring(c.kind) end
  where = where..' ('..c.kind..')'
  if c.by ~= nil and not fields.by then
    local why = c.kind == 'joker' and ' (a joker clause is by ante N already)' or ''
    return where..': by is for voucher, tag and boss clauses only'..why
  end
  if c.sticker ~= nil and not fields.sticker then
    return where..': sticker is for shop_joker and joker clauses only'
  end
  for k in pairs(c) do
    if not fields[k] then return where..': unknown field '..tostring(k) end
  end
  if c.by ~= nil and type(c.by) ~= 'boolean' then return where..': by must be a boolean' end
  if c.exclude ~= nil then
    if not top then return where..': exclude cannot be on a group member (a must-not stands alone)' end
    if any then return where..': exclude needs mode all (a must-not is never one option of several)' end
    if type(c.exclude) ~= 'boolean' then return where..': exclude must be a boolean' end
  end
  if c.sticker ~= nil and c.sticker ~= 'none' then
    return where..': sticker must be none (no eternal, perishable or rental sticker)'
  end
  if c.kind ~= 'legendary' and not is_int(c.ante, 1, antes) then
    return where..': ante must be an integer 1..'..antes
  end
  if c.edition ~= nil and not EDITION[c.edition] then
    return where..': unknown edition '..tostring(c.edition)..' (foil, holo, polychrome, negative or any)'
  end
  if c.kind == 'tag' then
    if c.blind ~= nil and c.blind ~= 'Small' and c.blind ~= 'Big' and c.blind ~= 'any' then
      return where..': blind must be Small, Big or any'
    end
    if not prefixed(c.key, 'tag_') or not known(P('P_TAGS'), c.key) then
      return where..': unknown tag '..tostring(c.key)
    end
  elseif c.kind == 'boss' then
    if not prefixed(c.key, 'bl_') or not known(P('P_BLINDS'), c.key, function(b) return b.boss end) then
      return where..': unknown boss '..tostring(c.key)
    end
  elseif c.kind == 'voucher' then
    if not prefixed(c.key, 'v_') or not known(P('P_CENTERS'), c.key, function(v) return v.set == 'Voucher' end) then
      return where..': unknown voucher '..tostring(c.key)
    end
    local findable, needs = M.voucher_findable(c.key)
    if not findable then
      return where..': '..center_name(c.key)..' needs '..center_name(needs)..' bought first, and the Finder never buys '
        ..center_name(needs)..' (its -1 ante is not modelled)'
    end
  elseif c.kind == 'legendary' then
    if c.index ~= 1 and c.index ~= 2 then return where..': index must be 1 or 2' end
    if c.key ~= nil and (not prefixed(c.key, 'j_')
      or not known(P('P_CENTERS'), c.key, function(j) return j.rarity == 4 end)) then
      return where..': not a legendary joker '..tostring(c.key)
    end
  elseif c.kind == 'soul_in_pack' then
    if not PACK_KIND[c.pack] then return where..': pack must be arcana or spectral' end
    if c.from_tag ~= nil and type(c.from_tag) ~= 'boolean' then return where..': from_tag must be a boolean' end
  elseif c.kind == 'shop_joker' then
    if type(c.key) ~= 'string' or c.key == '' or not known(P('P_CENTERS'), c.key) then
      return where..': unknown card '..tostring(c.key)
    end
    if c.rerolls ~= nil and not is_int(c.rerolls, 0, M.MAX_REROLLS) then
      return where..': rerolls must be an integer 0..'..M.MAX_REROLLS
    end
  elseif c.kind == 'joker' then
    if not prefixed(c.key, 'j_') or not known(P('P_CENTERS'), c.key, function(j) return j.set == 'Joker' end) then
      return where..': unknown joker '..tostring(c.key)
    end
    if not known(P('P_CENTERS'), c.key, function(j) return j.rarity ~= 4 end) then
      return where..': '..c.key..' is a legendary (only the Soul makes one: use a legendary clause)'
    end
    if c.rerolls ~= nil and not is_int(c.rerolls, 0, M.MAX_REROLLS) then
      return where..': rerolls must be an integer 0..'..M.MAX_REROLLS
    end
    if c.from ~= nil and not FROM[c.from] then return where..': from must be shop, buffoon or both' end
  elseif c.kind == 'pack' then
    if not (prefixed(c.key_prefix, 'p_') or c.key_prefix == 'p_') then
      return where..': key_prefix must start with p_'
    end
  end
end

check_group = function(g, where, antes)
  local at = where..' (group)'
  for k in pairs(g) do
    if k ~= 'kind' and k ~= 'clauses' then return at..': unknown field '..tostring(k) end
  end
  local n = type(g.clauses) == 'table' and list_len(g.clauses)
  if not n then return at..': clauses must be a list' end
  if n < 2 or n > M.MAX_GROUP then
    return at..': needs 2..'..M.MAX_GROUP..' members, has '..n
  end
  for m, c in ipairs(g.clauses) do
    local err = check_clause(c, where..', member '..m, antes, false)
    if err then return err end
  end
end

function M.plain_clauses(f)
  local grouped = false
  for _, c in ipairs(f.clauses) do
    if type(c) == 'table' and c.kind == 'group' then grouped = true; break end
  end
  if not grouped then return f.clauses end
  local out = {}
  for _, c in ipairs(f.clauses) do
    if type(c) == 'table' and c.kind == 'group' and type(c.clauses) == 'table' then
      for _, m in ipairs(c.clauses) do out[#out + 1] = m end
    else
      out[#out + 1] = c
    end
  end
  return out
end

local function max_ante(f)
  local m = 1
  for _, c in ipairs(M.plain_clauses(f)) do
    if type(c) == 'table' and type(c.ante) == 'number' and c.ante > m then m = c.ante end
  end
  return m
end

function M.validate(f)
  if type(f) ~= 'table' then return nil, 'filter: not a table' end
  if type(f.name) ~= 'string' then return nil, 'filter: name must be a string' end
  if f.stake ~= nil and not is_int(f.stake, 1, 8) then return nil, 'filter: stake must be an integer 1..8' end
  if f.deck ~= nil and (not prefixed(f.deck, 'b_')
    or not known(P('P_CENTERS'), f.deck, function(d) return d.set == 'Back' end)) then
    return nil, 'filter: unknown deck '..tostring(f.deck)
  end
  if f.all_unlocked ~= nil and type(f.all_unlocked) ~= 'boolean' then
    return nil, 'filter: all_unlocked must be a boolean'
  end
  if f.mode ~= nil and f.mode ~= 'all' and f.mode ~= 'any' then return nil, 'filter: mode must be all or any' end
  if type(f.clauses) ~= 'table' or #f.clauses == 0 then return nil, 'filter: needs at least one clause' end
  if not list_len(f.clauses) then return nil, 'filter: clauses must be a list' end
  if f.antes ~= nil and not is_int(f.antes, 1, M.MAX_ANTE) then
    return nil, 'filter: antes must be an integer 1..'..M.MAX_ANTE
  end
  local antes = f.antes or math.min(max_ante(f), M.MAX_ANTE)
  for i, c in ipairs(f.clauses) do
    local err = check_clause(c, 'clause '..i, antes, true, f.mode == 'any')
    if err then return nil, 'filter: '..err end
  end
  return true
end

------------------------------------------------------------------------------
-- Evaluation

local function class_of(c)
  if c.kind == 'tag' then return TAG
  elseif c.kind == 'boss' then return BOSS
  elseif c.kind == 'voucher' then return VOUCHER
  elseif c.kind == 'legendary' then return LEGEND
  elseif c.kind == 'soul_in_pack' then return c.from_tag and TAG_PACK or SHOP_PACK
  elseif c.kind == 'pack' then return PACK
  elseif c.kind == 'joker' then return BY_ANTE
  end
  return SHOP_CARD
end

-- Sorts idx by class, then ante, then index.
local function sort_by(idx, cls, ante)
  table.sort(idx, function(a, b)
    if cls[a] ~= cls[b] then return cls[a] < cls[b] end
    if ante[a] ~= ante[b] then return ante[a] < ante[b] end
    return a < b
  end)
end

-- Evaluation order: order = clause indices; members[i] = group i's member
-- indices; steps = the class of every evaluation step (a plain clause or one
-- member) in order, so step k of a group at position pos is first[pos] + j - 1
-- for its j-th member.
local function order_of(f)
  local idx, cls, ante, members, mcls = {}, {}, {}, {}, {}
  for i, c in ipairs(f.clauses) do
    idx[i] = i
    if c.kind == 'group' then
      local m, mc, ma = {}, {}, {}
      for j, x in ipairs(c.clauses) do m[j], mc[j], ma[j] = j, class_of(x), x.ante or 0 end
      sort_by(m, mc, ma)
      members[i], mcls[i] = m, mc
      cls[i], ante[i] = mc[m[1]], ma[m[1]]
    else
      cls[i], ante[i] = class_of(c), c.ante or 0
    end
  end
  sort_by(idx, cls, ante)
  local steps, first = {}, {}
  for pos, i in ipairs(idx) do
    first[pos] = #steps + 1
    if members[i] then
      for _, j in ipairs(members[i]) do steps[#steps + 1] = mcls[i][j] end
    else
      steps[#steps + 1] = cls[i]
    end
  end
  return idx, members, steps, first
end

-- What the shop walk must produce per ante: rows (shop cards), rerolls,
-- open (pack contents). Pack keys are always drawn for a walked ante. A joker
-- clause needs every ante 1..N. Group members count as clauses.
local function shop_needs(f)
  local needs, any_open = {}, false
  local function need(a)
    local n = needs[a] or {rows = false, rerolls = 0, open = false}
    needs[a] = n
    return n
  end
  for _, c in ipairs(M.plain_clauses(f)) do
    local cls = class_of(c)
    if cls == BY_ANTE then
      local open = (c.from or 'both') ~= 'shop'
      for a = 1, c.ante do
        local n = need(a)
        n.rows = true
        n.rerolls = math.max(n.rerolls, c.rerolls or 0)
        if open then n.open, any_open = true, true end
      end
    elseif cls == PACK or cls == SHOP_PACK or cls == SHOP_CARD then
      local n = need(c.ante)
      if cls == SHOP_CARD then
        n.rows = true
        n.rerolls = math.max(n.rerolls, c.rerolls or 0)
      elseif cls == SHOP_PACK then
        n.rows, n.open, any_open = true, true, true
      end
    end
  end
  return needs, any_open
end

local function keys_of(cards)
  local out = {}
  for i, c in ipairs(cards) do out[i] = c.key end
  return out
end

local function soul_at(cards)
  for i, c in ipairs(cards) do
    if c.key == SOUL then return i end
  end
end

-- The blind a tag clause holds on in the ante whose tags are t (Small
-- first), or nil.
local function tag_blind(c, t)
  local blind = c.blind or 'any'
  if (blind == 'Small' or blind == 'any') and t.small == c.key then return 'Small' end
  if (blind == 'Big' or blind == 'any') and t.big == c.key then return 'Big' end
end

-- Per-eval memo: every stream is drawn once and shared by the clauses.
local Ctx = {}
Ctx.__index = Ctx

-- Antes whose tag packs and shops are one playthrough (header: Chained
-- antes), and whether any from_tag clause is on a separate branch.
local function chained_antes(f, needs)
  local out, branch = {}, false
  for _, c in ipairs(M.plain_clauses(f)) do
    if c.kind == 'soul_in_pack' and c.from_tag then
      if needs[c.ante] then out[c.ante] = true else branch = true end
    end
  end
  return out, branch
end

-- The ante the Soul's edition reads (header: legendaries), and whether f has
-- a legendary step at all.
local function soul_ante(f, S)
  local top, legend = {}, false
  for _, c in ipairs(M.plain_clauses(f)) do
    local cls = class_of(c)
    if cls == LEGEND then
      legend = true
    elseif cls <= VOUCHER and c.ante > (top[cls] or 0) then
      top[cls] = c.ante
    end
  end
  return top[VOUCHER] or top[BOSS] or top[TAG] or S.game.round_resets.ante, legend
end

-- The positive tag clauses (members included): the tags the player takes.
local function taker_clauses(f)
  local out = {}
  for _, c in ipairs(M.plain_clauses(f)) do
    if c.kind == 'tag' and not c.exclude then out[#out + 1] = c end
  end
  return out
end

-- Whether f has a positive from_tag clause (members included) at ante a.
local function has_from_tag(f, a)
  for _, c in ipairs(M.plain_clauses(f)) do
    if c.kind == 'soul_in_pack' and c.from_tag and c.ante == a and not c.exclude then return true end
  end
  return false
end

function M.purchase_rules(f)
  local out = {}
  for _, c in ipairs(M.plain_clauses(f)) do
    if c.kind == 'voucher' and not c.exclude then
      if not rewinds(c.key) then
        out[#out + 1] = {clause = c, key = c.key, lo = c.by and 1 or c.ante, hi = c.ante, own = true}
      end
      for _, r in ipairs(prerequisites(c.key)) do
        if not rewinds(r) and c.ante > 1 then out[#out + 1] = {clause = c, key = r, lo = 1, hi = c.ante - 1} end
      end
    end
  end
  return out
end

-- Where the walk may buy: buy[key][a] = true when key is bought at ante a if
-- a's shop offers it; at[a] = true when some key is.
local function purchases_of(f)
  local buy, at = {}, {}
  for _, r in ipairs(M.purchase_rules(f)) do
    buy[r.key] = buy[r.key] or {}
    for a = r.lo, r.hi do buy[r.key][a], at[a] = true, true end
  end
  return buy, at
end

local function copy_set(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function new_ctx(S, f, steps)
  local needs, any_open = shop_needs(f)
  local chained, branch = chained_antes(f, needs)
  local ante, legend = soul_ante(f, S)
  local buy, buy_at = purchases_of(f)
  return setmetatable({S = S, f = f, tags = {}, vouchers = {}, bosses = {}, boss_upto = 0,
    tag_packs = {}, needs = needs, any_open = any_open, walked = 0, shops = {},
    chained = chained, tag_branch = branch, steps = steps,
    soul_ante = ante, has_legend = legend,
    takers = taker_clauses(f), taken_at = {}, skips = {}, walk_packs = {},
    branch1 = branch and chained[1] == nil and has_from_tag(f, 1),
    -- v_base: the run's own redeemed vouchers (the deck's), before the walk
    -- buys any; nil when f buys nothing, and S's own then never changes.
    buy = buy, buy_at = buy_at, bought = {},
    v_base = next(buy_at) and copy_set(S.game.used_vouchers or {}) or nil}, Ctx)
end

function Ctx:tag(a)
  if not self.tags[a] then self.tags[a] = predict.tags(self.S, a) end
  return self.tags[a]
end

function Ctx:boss(a)
  for x = self.boss_upto + 1, a do
    self.bosses[x] = predict.boss(self.S, x)
    self.boss_upto = x
  end
  return self.bosses[a]
end

-- Ante x's voucher, drawn once, and whether the walk buys it (header:
-- Policies, voucher clauses). Its pool leaves out the purchases below x, so
-- redeemed draws every lower ante the walk may buy at first.
function Ctx:voucher(x)
  local v = self.vouchers[x]
  if v then return v end
  v = predict.voucher(self.S, x, self:redeemed(x - 1))
  self.vouchers[x] = v
  if self.buy[v] and self.buy[v][x] and self:offered(x) then self.bought[x] = v end
  return v
end

-- The vouchers redeemed once ante x's purchase is made: the run's own and the
-- walk's at antes 1..x. nil when f buys nothing (S's own used_vouchers).
function Ctx:redeemed(x)
  local used = self.v_base
  if not used then return nil end
  for y = 1, x do
    if self.buy_at[y] then
      self:voucher(y)
      local key = self.bought[y]
      if key then
        if used == self.v_base then used = copy_set(used) end
        used[key] = true
      end
    end
  end
  return used
end

-- The voucher the walk buys at ante x, or nil.
function Ctx:bought_at(x)
  if self.buy_at[x] then self:voucher(x) end
  return self.bought[x]
end

-- Whether ante x's shops offer its voucher. Every ante's do (the shop after
-- the previous Boss) but ante 1's when both its blinds are skipped: its taken
-- tags, and the pack tags a from_tag clause there skips (chained, or a
-- separate branch), as walk_to and first_shop_ante skip them.
function Ctx:offered(x)
  if x > 1 then return true end
  if self.offered1 == nil then
    local t = self:taken(1) or {}
    local small, big = t.Small ~= nil, t.Big ~= nil
    if self.chained[1] or self.branch1 then
      local tags = self:tag(1)
      small = small or predict.TAG_PACKS[tags.small] ~= nil
      big = big or predict.TAG_PACKS[tags.big] ~= nil
    end
    self.offered1 = not (small and big)
  end
  return self.offered1
end

-- The blinds of ante x a positive tag clause takes (header: Policies, tag
-- clauses): {Small = key, Big = key}, or false. A plain clause takes its
-- blind at its ante when it holds there (Small first for blind 'any'); a by
-- clause takes the first ante and blind that holds, as its eval reports.
-- 'Tag'..a is a per-ante stream, so drawing a tag here moves nothing else.
function Ctx:taken(x)
  if self.taken_at[x] ~= nil then return self.taken_at[x] end
  local out = false
  for _, c in ipairs(self.takers) do
    local at, b
    if c.by then
      for y = 1, math.min(x, c.ante) do
        b = tag_blind(c, self:tag(y))
        if b then at = y; break end
      end
    elseif c.ante == x then
      at, b = x, tag_blind(c, self:tag(x))
    end
    if at == x and b then
      out = out or {}
      out[b] = c.key
    end
  end
  self.taken_at[x] = out
  return out
end

-- The ante of the run's first shop, which gets the forced first Buffoon: ante
-- 1 unless both its blinds are skipped, then ante 2 (the shop after its Boss).
-- A walked ante 1 says so by its shops. An unwalked one skips its taken tags
-- and, with a from_tag clause there (a separate branch), its pack-tag blinds;
-- when that is both, details.skips[1] records it for the route to replay.
function Ctx:first_shop_ante()
  if self.shops[1] then return #self.shops[1] == 0 and 2 or 1 end
  local t, tags = self:taken(1) or {}, self:tag(1)
  local function skipped(blind, tag)
    return t[blind] or (self.branch1 and predict.TAG_PACKS[tag] and tag) or nil
  end
  local sk = {Small = skipped('Small', tags.small), Big = skipped('Big', tags.big)}
  if sk.Small and sk.Big then
    self.skips[1] = sk
    return 2
  end
  return 1
end

-- Whether any step after step k (a clause or group member, in eval order)
-- still reads S's shop or pack streams.
function Ctx:later_needs_S(k)
  for p = k + 1, #self.steps do
    if self.steps[p] >= TAG_PACK then return true end
  end
  return false
end

-- The legendaries on a copy of S set to the Soul's ante.
function Ctx:draw_legend()
  local L = state.copy(self.S)
  L.game.round_resets.ante = self.soul_ante
  self.legend = predict.legendaries(L, 2)
end

function Ctx:legendaries(k)
  if not self.legend then
    if self.S.game.round_resets.ante ~= self.soul_ante then
      -- Only in a group filter, or after a by clause that stopped below its
      -- N: a step that would have moved S there was never drawn (a plain
      -- filter draws every tag, boss and voucher first).
      self:draw_legend()
    else
      local L = self.S
      if self:later_needs_S(k) then L = state.copy(self.S) end
      self.legend = predict.legendaries(L, 2)
    end
  end
  return self.legend
end

-- S is about to walk (a shop walk, or tag packs drawn on S itself), which
-- moves its ante: a legendary step not reached yet is drawn first. Never in
-- a plain filter, whose legendary steps all precede every walk.
function Ctx:before_walk()
  if self.has_legend and not self.legend then self:draw_legend() end
end

-- A walk's tag packs in the details shape: kind is the clause pack name
-- ('arcana' / 'spectral'), cards the keys, soul the Soul's slot.
local function tag_packs_of(walk)
  local out = {}
  for i, p in ipairs(walk.tag_packs) do
    out[i] = {blind = p.blind, tag = p.tag, pack = p.pack, kind = p.pack:match('^p_(%l+)_'),
      cards = keys_of(p.cards), soul = soul_at(p.cards)}
  end
  return out
end

-- The packs Charm/Ethereal tags open at ante a, Small then Big.
function Ctx:tag_packs_at(a)
  if self.tag_packs[a] then return self.tag_packs[a] end
  -- The separate branch is copied before any shop walk touches S.
  if not self.tag_S then
    self.tag_S = next(self.needs) and state.copy(self.S) or self.S
  end
  if self.chained[a] then
    self:walk_to(a)
    return self.tag_packs[a]
  end
  -- Both blinds skipped: a pack tag's pack opens at its skip, other tags give
  -- none. For a > 1 the walk draws the Boss's shop first (pack keys only on
  -- 'shop_pack'A, which no pack's contents read), so the packs are unchanged.
  if self.tag_S == self.S then self:before_walk() end
  -- What a purchase changes that these packs read is used_vouchers (Omen
  -- Globe): the vouchers bought below a, and a's own, bought in the Boss's
  -- shop before the skips.
  local used = self:redeemed(a > 1 and a or 0)
  if used then self.tag_S.game.used_vouchers = copy_set(used) end
  local walk = predict.ante_walk(self.tag_S, a, {skip = {Small = true, Big = true},
    cards = false, open = false, tags = self:tag(a)})
  self.tag_packs[a] = tag_packs_of(walk)
  return self.tag_packs[a]
end

-- Walks the shops of every needed ante up to a, in ascending order, one
-- predict.ante_walk per ante under the plan policy (needs n). Every ante
-- skips its taken tags' blinds; a chained ante also the blinds whose tag
-- gives a pack. An ante's voucher purchase is made in its first shop, or
-- applied to S when the ante is not walked. Each shop gets rows = {the row
-- on entering (after a purchase there), the row after reroll 1, ...}.
function Ctx:walk_to(a)
  local S = self.S
  if a > self.walked then
    -- A separate tag branch not drawn yet (a group member after a walk) still
    -- starts from S as it was before any shop; so do the legendaries.
    if self.tag_branch and not self.tag_S then self.tag_S = state.copy(S) end
    self:before_walk()
  end
  for x = self.walked + 1, a do
    local n = self.needs[x]
    local bought = self:bought_at(x)
    if not n and bought then
      -- An ante no clause needs still has its shops: the purchase holds on.
      state.redeem(S, bought)
    end
    if n then
      -- The run's forced first Buffoon (it draws nothing, so only which shop it
      -- lands in matters) belongs to the run's first shop: ante 1's, or ante
      -- 2's Boss shop when both ante-1 blinds are skipped. A walked ante places
      -- it itself (ante_walk); one no clause needs is spent here, since an
      -- unwalked ante still has its shops (only taken tags skip there).
      local first = self:first_shop_ante()
      if x > first and not S.game.first_shop_buffoon and self.shops[first] == nil then predict.packs(S, 1, 1) end
      local tags = self:tag(x)
      local taken = self:taken(x) or {}
      local skip = {Small = taken.Small ~= nil, Big = taken.Big ~= nil}
      if self.chained[x] then
        skip.Small = skip.Small or predict.TAG_PACKS[tags.small] ~= nil
        skip.Big = skip.Big or predict.TAG_PACKS[tags.big] ~= nil
      end
      -- Every pack a skipped blind's tag gives opens at the skip, whatever
      -- the reason for the skip (Meteor, Standard and Buffoon included).
      local walk = predict.ante_walk(S, x, {skip = skip, rerolls = n.rerolls, open = n.open,
        cards = n.rows, tags = tags, pack_tags = predict.ALL_TAG_PACKS, voucher = bought})
      for _, shop in ipairs(walk.shops) do
        shop.rows = {shop.cards}
        for r, row in ipairs(shop.rerolls) do shop.rows[r + 1] = row.cards end
      end
      if skip.Small or skip.Big then
        self.skips[x] = {Small = skip.Small and tags.small or nil, Big = skip.Big and tags.big or nil}
      end
      self.walk_packs[x] = tag_packs_of(walk)
      if self.chained[x] then self.tag_packs[x] = self.walk_packs[x] end
      self.shops[x] = walk.shops
    end
    self.walked = x
  end
  return self.shops[a]
end

-- A clause's edition against a predicted card's (nil = base card).
local function edition_ok(want, got)
  if want == nil then return true end
  if want == 'any' then return got ~= nil end
  return got == want
end

-- A clause's sticker against a predicted card's stickers: 'none' = no
-- eternal, perishable or rental (nil = any card).
local function sticker_ok(want, s)
  if want == nil or s == nil then return true end
  return not (s.eternal or s.perishable or s.rental)
end

-- Whether a predicted card is the one a shop_joker / joker clause asks for.
local function matches(c, card)
  return card.key == c.key and edition_ok(c.edition, card.edition) and sticker_ok(c.sticker, card.stickers)
end

local EVAL = {}

function EVAL.tag(ctx, c)
  if c.by then
    for a = 1, c.ante do
      local t = ctx:tag(a)
      local b = tag_blind(c, t)
      if b then return true, {ante = a, small = t.small, big = t.big, blind = b} end
    end
    return false, {}
  end
  local t = ctx:tag(c.ante)
  return tag_blind(c, t) ~= nil, {small = t.small, big = t.big}
end

function EVAL.boss(ctx, c)
  if c.by then
    for a = 1, c.ante do
      local b = ctx:boss(a)
      if b == c.key then return true, {ante = a, key = b} end
    end
    return false, {}
  end
  local b = ctx:boss(c.ante)
  return b == c.key, {key = b}
end

function EVAL.voucher(ctx, c)
  if c.by then
    for a = 1, c.ante do
      local v = ctx:voucher(a)
      if v == c.key and ctx:offered(a) then return true, {ante = a, key = v} end
    end
    return false, {}
  end
  local v = ctx:voucher(c.ante)
  return v == c.key and ctx:offered(c.ante), {key = v}
end

function EVAL.legendary(ctx, c, k)
  local l = ctx:legendaries(k)[c.index]
  return (c.key == nil or l.key == c.key) and edition_ok(c.edition, l.edition),
    {key = l.key, edition = l.edition}
end

function EVAL.soul_in_pack(ctx, c)
  if c.from_tag then
    local packs = ctx:tag_packs_at(c.ante)
    for _, p in ipairs(packs) do
      if p.kind == c.pack and p.soul then
        return true, {packs = packs, blind = p.blind, tag = p.tag, pack = p.pack, index = p.soul}
      end
    end
    return false, {packs = packs}
  end
  local kind = PACK_KIND[c.pack]
  for s, shop in ipairs(ctx:walk_to(c.ante)) do
    for j, p in ipairs(shop.packs) do
      local i = p.kind == kind and soul_at(shop.contents[j])
      if i then return true, {shop = s, slot = j, pack = p.key, index = i, after = shop.after} end
    end
  end
  return false, {}
end

function EVAL.shop_joker(ctx, c)
  for s, shop in ipairs(ctx:walk_to(c.ante)) do
    for r = 0, c.rerolls or 0 do
      for slot, card in ipairs(shop.rows[r + 1]) do
        if matches(c, card) then
          return true, {shop = s, reroll = r, slot = slot}
        end
      end
    end
  end
  return false, {}
end

function EVAL.pack(ctx, c)
  local pre = c.key_prefix
  for s, shop in ipairs(ctx:walk_to(c.ante)) do
    for j, p in ipairs(shop.packs) do
      if p.key:sub(1, #pre) == pre then return true, {shop = s, slot = j, pack = p.key} end
    end
  end
  return false, {}
end

function EVAL.joker(ctx, c)
  local from = c.from or 'both'
  local rows, packs = from ~= 'buffoon', from ~= 'shop'
  for a = 1, c.ante do
    for s, shop in ipairs(ctx:walk_to(a)) do
      if rows then
        for r = 0, c.rerolls or 0 do
          for slot, card in ipairs(shop.rows[r + 1]) do
            if matches(c, card) then
              return true, {ante = a, shop = s, after = shop.after, reroll = r, index = slot}
            end
          end
        end
      end
      if packs then
        for j, p in ipairs(shop.packs) do
          if p.kind == 'Buffoon' then
            for k, card in ipairs(shop.contents[j]) do
              if matches(c, card) then
                return true, {ante = a, shop = s, after = shop.after, pack_slot = j, pack = p.key, index = k}
              end
            end
          end
        end
      end
    end
  end
  return false, {}
end

-- A group: its members in order (steps k, k+1, ...) until one holds.
local function eval_group(ctx, g, members, k)
  local info = {results = {}}
  for j, m in ipairs(members) do
    local c = g.clauses[m]
    local hit, mi = EVAL[c.kind](ctx, c, k + j - 1)
    mi.ok = hit and true or false
    info.results[m] = mi
    if hit then
      info.hit = m
      return true, info
    end
  end
  return false, info
end

function M.eval(S, f)
  local ok, err = M.validate(f)
  if not ok then error(err, 2) end
  assert(type(S) == 'table' and type(S.game) == 'table', 'filter.eval: not a sim state')
  local any = f.mode == 'any'
  local order, members, steps, first = order_of(f)
  local ctx = new_ctx(S, f, steps)
  local details = {checked = 0, results = {}}
  local result = not any
  for pos, i in ipairs(order) do
    local c = f.clauses[i]
    local hit, info
    if members[i] then
      hit, info = eval_group(ctx, c, members[i], first[pos])
    else
      hit, info = EVAL[c.kind](ctx, c, first[pos])
      -- A must-not: the positive form's draws, its result negated; its
      -- details only when the positive form held (the "why not").
      if c.exclude then
        hit = not hit
        if hit then info = {} end
      end
    end
    info.ok = hit and true or false
    details.results[i] = info
    details.checked = pos
    if any and hit then result = true; break end
    if not any and not hit then result = false; break end
  end
  for a, packs in pairs(ctx.walk_packs) do
    if ctx.chained[a] or #packs > 0 then
      details.tag_packs = details.tag_packs or {}
      details.tag_packs[a] = packs
    end
  end
  if next(ctx.skips) then details.skips = ctx.skips end
  if next(ctx.bought) then details.bought = ctx.bought end
  details.walked = ctx.walked
  return result, details
end

function M.fresh(f, seed)
  return state.fresh(seed, {stake = f.stake or 1, deck = f.deck or 'b_red', all_unlocked = f.all_unlocked or false})
end

function M.eval_seed(f, seed)
  return M.eval(M.fresh(f, seed), f)
end

------------------------------------------------------------------------------
-- Serialization

function M.serialize(f)
  local ok, err = M.validate(f)
  if not ok then return nil, err end
  return STR_PACK(f)
end

function M.deserialize(s)
  if type(s) ~= 'string' or s:sub(1, 6) ~= 'return' then return nil, 'filter: not a packed filter' end
  local chunk, err = loadstring(s, '=filter')
  if not chunk then return nil, 'filter: '..tostring(err) end
  setfenv(chunk, {})
  local ok, f = pcall(chunk)
  if not ok then return nil, 'filter: '..tostring(f) end
  local valid, verr = M.validate(f)
  if not valid then return nil, verr end
  return f
end

return M
