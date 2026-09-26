-- seedfinder.odds: per-clause pass rates from a seed sample, and the expected
-- number of seeds a Finder run scans per hit. Pure functions over counts, plus
-- a thin sampler over filter.eval_seed (each eval builds its own fresh S, so
-- the live G.GAME is never read or written). This module runs where it is
-- called: seedfinder.engine.sample ships it to the Finder's workers, which
-- tally their seed ranges with odds.counter and send the counts back.
--
-- API
--   odds.sample(f, seeds, eval_clause) -> counts. For every seed, each clause
--     is evaluated on its own (a one-clause 'all' filter with f's name, stake,
--     deck, all_unlocked and antes) and the full filter once more, since the
--     full filter is not the conjunction of its clauses: chained antes play
--     the pack-tag and shop policies as one walk. eval_clause(f1, seed) -> bool
--     (default filter.eval_seed) lets a caller or test supply the evaluator.
--     Raises on an invalid f or an empty seed list.
--   odds.counter(f, eval_clause) -> add, counts. add(seed) evaluates one seed
--     exactly as sample does and folds it into counts (fresh, all zeros). The
--     workers tally with it, so a worker's chunk and sample agree by
--     construction. f is not validated here (the caller has).
--   odds.estimate(counts) -> est, or nil, err (a malformed counts table).
--
-- counts (plain data, so worker tallies sum field by field)
--   {n = seeds sampled, mode = 'all'|'any', clauses = {[i] = passes of clause
--    i alone}, full = passes of the whole filter}
--
-- est
--   per_clause     = {[i] = passes / n}
--   independent    = the full-filter rate if the clauses were independent:
--                    the product of per_clause ('all') or 1 - prod(1 - r) ('any')
--   joint          = full / n, or nil when the full filter never passed
--   expected_seeds = 1 / (joint or independent); math.huge when that is 0
--   bottleneck     = index of the lowest-rate clause (the first one on a tie)
--   never          = {i, ...}: clauses that never passed in the sample (an
--                    impossible or locked clause, or rarer than 1/n)
--   reason         = English naming the first never-passing clause when
--                    expected_seeds is math.huge, else nil
--   confidence     = 'measured' when joint rests on at least MIN_JOINT
--                    passes, else 'extrapolated' (joint is thin or absent and
--                    the figure leans on the independence product)
--   n, full        = copied from counts
local filter = require('seedfinder.filter')

local M = {}

-- Fewer full-filter passes than this and the joint rate is not a measurement.
M.MIN_JOINT = 5

-- The filter one clause makes on its own, under f's run settings.
local function single(f, c)
  return {name = f.name, stake = f.stake, deck = f.deck, all_unlocked = f.all_unlocked,
    antes = f.antes, mode = 'all', clauses = {c}}
end

function M.counter(f, eval_clause)
  eval_clause = eval_clause or filter.eval_seed
  local singles, passes = {}, {}
  for i, c in ipairs(f.clauses) do
    singles[i] = single(f, c)
    passes[i] = 0
  end
  local counts = {n = 0, mode = f.mode or 'all', clauses = passes, full = 0}
  local function add(seed)
    for i = 1, #singles do
      if eval_clause(singles[i], seed) then passes[i] = passes[i] + 1 end
    end
    if eval_clause(f, seed) then counts.full = counts.full + 1 end
    counts.n = counts.n + 1
  end
  return add, counts
end

function M.sample(f, seeds, eval_clause)
  local ok, err = filter.validate(f)
  if not ok then error(err, 2) end
  if type(seeds) ~= 'table' or #seeds == 0 then error('odds.sample: seeds must be a non-empty list', 2) end
  local add, counts = M.counter(f, eval_clause)
  for _, seed in ipairs(seeds) do add(seed) end
  return counts
end

local function count_ok(v, n)
  return type(v) == 'number' and v % 1 == 0 and v >= 0 and v <= n
end

function M.estimate(counts)
  if type(counts) ~= 'table' then return nil, 'odds: counts must be a table' end
  local n = counts.n
  if type(n) ~= 'number' or n % 1 ~= 0 or n < 1 then return nil, 'odds: counts.n must be a positive integer' end
  if counts.mode ~= 'all' and counts.mode ~= 'any' then return nil, 'odds: counts.mode must be all or any' end
  if type(counts.clauses) ~= 'table' or #counts.clauses == 0 then return nil, 'odds: counts.clauses must be a non-empty list' end
  if not count_ok(counts.full, n) then return nil, 'odds: counts.full must be an integer 0..n' end
  local any = counts.mode == 'any'
  local per, never = {}, {}
  local prod, miss = 1, 1
  local bottleneck
  for i, k in ipairs(counts.clauses) do
    if not count_ok(k, n) then return nil, 'odds: clause '..i..' count must be an integer 0..n' end
    local r = k / n
    per[i] = r
    prod = prod * r
    miss = miss * (1 - r)
    if k == 0 then never[#never + 1] = i end
    if not bottleneck or r < per[bottleneck] then bottleneck = i end
  end
  local independent = any and 1 - miss or prod
  local joint = counts.full > 0 and counts.full / n or nil
  local rate = joint or independent
  local est = {
    per_clause = per, independent = independent, joint = joint,
    expected_seeds = rate > 0 and 1 / rate or math.huge,
    bottleneck = bottleneck, never = never,
    confidence = counts.full >= M.MIN_JOINT and 'measured' or 'extrapolated',
    n = n, full = counts.full,
  }
  if rate == 0 then
    local i = never[1] or bottleneck
    est.reason = 'clause '..i..' never passed in '..n..' seeds (impossible or locked)'
  end
  return est
end

return M
