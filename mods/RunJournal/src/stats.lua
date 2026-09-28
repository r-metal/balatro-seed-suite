-- runjournal.stats: aggregates over the recorded runs, and CSV/JSON export. Contract:
-- docs/contracts-0.2.md § RunJournal.
--
-- API
--   stats(filter?) / stats.compute(filter?)
--     -> {runs, wins, win_rate, unfinished, by_deck = {[deck] = {runs, wins,
--        win_rate}}, by_stake = {[stake] = {...}}, by_joker = {[key] = {...}}}
--     The module table is callable, so `RunJournal.stats(filter)` is the contract's
--     `runjournal.stats(filter?)`. Only finished runs (the index entry has ended_at)
--     count in runs/wins; `unfinished` counts the rest (in progress or abandoned) that
--     pass the filter. win_rate is wins / runs, 0 with no runs.
--     An endless reload is unfinished too, never a loss: reloading a won endless run
--     starts a new record whose `won` is nil (T-370's known gap), so an entry with
--     endless = true and won not true is counted in `unfinished` even once it ended.
--     by_joker is the "build archetype" of 0.2.0: each key in the run's joker set at
--     its end (jokers_final, else the last shop's jokers) counts that run once.
--     filter: a function(entry) -> bool over index entries, or a table whose fields
--     must all match: {deck, stake, seed, won = bool, joker = key (in the end set),
--     include = {seeded, finder, challenge, daily}}.
--     include (T-371): which kinds of run count besides normal ones (see kind_of).
--     A kind whose field is missing or false is left out. No `include` at all leaves
--     nothing out, so a bare stats() and the 0.3 table filters count every run as
--     before; the Journal's screen starts from DEFAULT_FILTER instead.
--   stats.DEFAULT_FILTER = {include = {seeded = false, finder = false, challenge =
--     false, daily = false}}: normal runs only (the locked research answer). Shared:
--     copy it before changing it.
--   stats.KINDS = {'seeded', 'finder', 'challenge', 'daily'}, the include fields.
--   stats.kind_of(run) -> 'daily' | 'finder' | 'challenge' | 'seeded' | nil (normal).
--     run: an index entry (T-370's flags) or a record (flags derived from its seeded,
--     challenge and origin as the recorder derives an entry's). The first that
--     applies wins, in that order: a daily run is seeded too, a Finder run may be.
--     An entry without flags (recorded before 0.4.0) is normal; so is an endless run.
--   stats.jokers(filter?, runs?, read?) -> {row, ...}: one row per joker key seen in
--     a counted run (finished and passing `filter`, as compute counts runs), at its
--     end, at any shop, or (T-378b) offered in any shop. row = {key, runs, wins,
--     win_rate, held, lifespan, offered, picked, pick_rate}:
--       runs/wins/win_rate  as by_joker: runs whose end set held it, and their wins;
--       held      runs where it was held at a shop (a jokers_seen snapshot has it);
--       lifespan  the mean number of shops it was held, over those `held` runs (nil
--                 when held is 0: bought in the last shop, say).
--       offered   (T-378b) runs whose record's `offered` (T-372a) has it: a shop's
--                 card row showed it at least once, rerolls included;
--       picked    of those runs, the ones where it was also held at some shop (as
--                 `held` counts: a jokers_seen snapshot has it);
--       pick_rate picked / offered, nil when offered is 0.
--     offered/picked/pick_rate count only runs whose record has an `offered` table,
--     i.e. recorded by 0.4.0 or later: an older run still counts in runs/wins/held
--     but never in the pick rate, and a joker with no offered data has pick_rate nil.
--     A joker bought in the run's last shop is in no later jokers_seen snapshot, so
--     it is offered but not picked there (the `held` rule, kept on purpose).
--     Every key, not a top N. Rows come sorted by runs, then key (sort_jokers).
--     runs: index entries or records, default recorder.list(). An entry's jokers_seen
--     and offered come from its record, through read(run_id) (default recorder.read;
--     the UI passes a per-open cache, as the Hunts tab does). An unreadable record
--     still counts in runs/wins from the entry, and adds nothing to held/lifespan or
--     the pick rate. Reads only.
--   stats.sort_jokers(rows, by, name_of?) -> rows, sorted in place, highest first by
--     `by` ('runs' | 'win_rate' | 'lifespan' | 'pick_rate'; a nil lifespan or
--     pick_rate sorts last), ties by name ascending: row.name, else name_of(row.key),
--     else the key.
--   stats.dailies(runs?, read?) -> {row, ...}: (T-378b) the daily seed's runs, newest
--     first (started_at, then run_id), every run of a date listed on its own: nothing
--     is collapsed. A run is daily when it is a record whose origin.kind is 'daily'
--     (recorder.set_origin, which seedfinder.daily's play calls) or an index entry
--     with daily = true (T-370's flag). row = {run_id, date, mode, seed, deck, stake,
--     won, final_ante, started_at, ended_at}:
--       date   origin.date ('YYYY-MM-DD', the UTC day the seed was picked for), else
--              the UTC date of started_at;
--       mode   origin.mode, 'blind' | 'routed', or nil when unknown;
--       won    true (won), false (finished without a win), nil (unfinished, the
--              endless reload included: `finished` below, as compute counts it).
--     An entry carries no origin, so a daily entry's record is read through
--     read(run_id) (default recorder.read; the UI passes its per-open cache); only
--     daily entries are read, and an unreadable one keeps its row with the date from
--     started_at and no mode. It takes no filter: the Daily tab lists every daily run
--     (the include toggles hide them from the other numbers only). Reads only.
--   stats.export(fmt) -> path | nil, err. fmt = 'csv' | 'json'. Writes every recorded
--     run (finished or not) to '<profile>/runjournal/export-<os.time>.<fmt>', plain text
--     through love.filesystem, and verifies it by reading it back.
--     CSV: a header row, then one row per run, oldest first (see CSV_COLUMNS).
--     JSON: {"version": 1, "runs": [record, ...]}, each record as the recorder stores
--     it, except that `antes` is an object keyed by the ante as a string.
--   stats.csv_row(record), stats.json(value): the encoders, for tests and the UI.
--   stats.by_seed(runs?) -> {{seed, runs = {entry, ...}}, ...}: the seeds played more
--     than once. runs: index entries (or records) in any order, default recorder.list().
--     Each group's runs are oldest first; groups are newest first (by their newest
--     run's started_at, then seed). Finished or not, every run counts.
--   stats.compare(a, b) -> {rows = {row, ...}, diverge = ante | nil} | nil, err.
--     a, b: records, or run_ids read through recorder.read. One row per ante either
--     run has blinds in, ascending: {ante, dollars_a, dollars_b, best_hand_a,
--     best_hand_b, best_score_a, best_score_b, outcome_a, outcome_b}. dollars is the
--     ante's dollars_end (nil before its first round ended); best_hand is the
--     highest-scoring hand played in the ante. outcome: 'won' (its Boss won), 'lost'
--     (a blind lost), 'open' (played, neither yet), nil (not reached). diverge is the
--     first ante whose outcomes differ, nil when they never do.
--   stats.by_filter(runs?) -> {{filter_name, runs, wins, win_rate, unfinished,
--     best_ante, avg_ante, newest}, ...}: the Finder's hunts, one group per
--     origin.filter_name (recorder.set_origin, which SeedFinder's Play calls). runs:
--     records or index entries in any order, default recorder.list(); an index entry
--     carries no origin, so its record is read through recorder.read (an unreadable
--     one is skipped). A run without a filter name is not a hunt. As in compute,
--     runs/wins/win_rate count finished runs and `unfinished` the rest; avg_ante is
--     the mean final_ante of the finished runs (nil with none); best_ante is the
--     highest final_ante of any run and newest the latest started_at, both over every
--     run. Groups: best win rate first, then more runs, newest, name. Reads only.
--     It takes no filter: hunts are Finder runs by definition, so the include toggles
--     (and deck/stake) never apply to it.
local recorder = require('runjournal.recorder')

local stats = {}

stats.CSV_COLUMNS = {'run_id', 'seed', 'deck', 'stake', 'started_at', 'ended_at', 'won',
  'final_ante', 'final_round', 'blinds_played', 'blinds_skipped', 'hands_played',
  'best_hand', 'best_score', 'jokers'}

stats.KINDS = {'seeded', 'finder', 'challenge', 'daily'}
stats.DEFAULT_FILTER = {include = {seeded = false, finder = false, challenge = false, daily = false}}

-- A record (it has antes or jokers_seen), not an index entry.
local function is_record(x)
  return x.antes ~= nil or x.jokers_seen ~= nil
end

-- The run's joker set at its end: an entry's `jokers`, a record's jokers_final or its
-- last shop's jokers.
local function end_set(x)
  if x.jokers ~= nil then return x.jokers end
  if x.jokers_final ~= nil then return x.jokers_final end
  local seen = x.jokers_seen
  return type(seen) == 'table' and seen[#seen] or {}
end

function stats.kind_of(e)
  if type(e) ~= 'table' then return nil end
  local finder, daily = e.finder == true, e.daily == true
  if is_record(e) and type(e.origin) == 'table' then
    local o = e.origin
    finder = (o.filter_name ~= nil and o.filter_name ~= false) or o.kind == 'finder'
    daily = o.kind == 'daily'
  end
  if daily then return 'daily' end
  if finder then return 'finder' end
  if type(e.challenge) == 'string' then return 'challenge' end
  if e.seeded == true then return 'seeded' end
  return nil
end

-- Finished for the stats: it ended, and is not an endless reload (see the header).
local function finished(e)
  if not e.ended_at then return false end
  return not (e.endless == true and e.won ~= true)
end

local function matches(e, f)
  if f == nil then return true end
  if type(f) == 'function' then return f(e) and true or false end
  if type(f) ~= 'table' then return true end
  if f.deck ~= nil and e.deck ~= f.deck then return false end
  if f.stake ~= nil and e.stake ~= f.stake then return false end
  if f.seed ~= nil and e.seed ~= f.seed then return false end
  if f.won ~= nil and (e.won == true) ~= f.won then return false end
  if f.joker ~= nil then
    local found = false
    for _, k in ipairs(end_set(e) or {}) do if k == f.joker then found = true end end
    if not found then return false end
  end
  if type(f.include) == 'table' then
    local kind = stats.kind_of(e)
    if kind ~= nil and f.include[kind] ~= true then return false end
  end
  return true
end

local function bump(bucket, key, won)
  if key == nil then key = '?' end
  local b = bucket[key]
  if not b then b = {runs = 0, wins = 0, win_rate = 0}; bucket[key] = b end
  b.runs = b.runs + 1
  if won then b.wins = b.wins + 1 end
  b.win_rate = b.wins / b.runs
end

function stats.compute(filter)
  local out = {runs = 0, wins = 0, win_rate = 0, unfinished = 0,
    by_deck = {}, by_stake = {}, by_joker = {}}
  for _, e in ipairs(recorder.list()) do
    if matches(e, filter) then
      if finished(e) then
        local won = e.won == true
        out.runs = out.runs + 1
        if won then out.wins = out.wins + 1 end
        bump(out.by_deck, e.deck, won)
        bump(out.by_stake, e.stake, won)
        local seen = {}
        for _, k in ipairs(e.jokers or {}) do
          if not seen[k] then seen[k] = true; bump(out.by_joker, k, won) end
        end
      else
        out.unfinished = out.unfinished + 1
      end
    end
  end
  out.win_rate = out.runs > 0 and out.wins / out.runs or 0
  return out
end

-- Jokers -----------------------------------------------------------------------------

function stats.jokers(filter, runs, read)
  if runs == nil then runs = recorder.list() end
  read = read or recorder.read
  local rows, out = {}, {}
  local function row(key)
    local r = rows[key]
    if not r then
      r = {key = key, runs = 0, wins = 0, win_rate = 0, held = 0, shops = 0, offered = 0, picked = 0}
      rows[key] = r
      out[#out + 1] = r
    end
    return r
  end
  for _, e in ipairs(runs or {}) do
    if type(e) == 'table' and finished(e) and matches(e, filter) then
      local won = e.won == true
      local once = {}
      for _, k in ipairs(end_set(e) or {}) do
        if not once[k] then
          once[k] = true
          local r = row(k)
          r.runs = r.runs + 1
          if won then r.wins = r.wins + 1 end
        end
      end
      local rec = e
      if not is_record(e) then
        local ok, got = pcall(read, e.run_id)
        rec = ok and type(got) == 'table' and got or nil
      end
      local shops = {}   -- key -> the shops of this run that held it
      for _, snap in ipairs(rec and type(rec.jokers_seen) == 'table' and rec.jokers_seen or {}) do
        local here = {}
        for _, k in ipairs(type(snap) == 'table' and snap or {}) do
          if not here[k] then here[k] = true; shops[k] = (shops[k] or 0) + 1 end
        end
      end
      for k, n in pairs(shops) do
        local r = row(k)
        r.held = r.held + 1
        r.shops = r.shops + n
      end
      -- The pick rate: only a record that has `offered` (0.4.0 on) says what its
      -- shops showed; a run without it adds nothing here.
      local offered = rec and type(rec.offered) == 'table' and rec.offered or nil
      for k, n in pairs(offered or {}) do
        if type(k) == 'string' and type(n) == 'number' and n > 0 then
          local r = row(k)
          r.offered = r.offered + 1
          if shops[k] then r.picked = r.picked + 1 end
        end
      end
    end
  end
  for _, r in ipairs(out) do
    r.win_rate = r.runs > 0 and r.wins / r.runs or 0
    r.lifespan = r.held > 0 and r.shops / r.held or nil
    r.pick_rate = r.offered > 0 and r.picked / r.offered or nil
    r.shops = nil
  end
  return stats.sort_jokers(out, 'runs')
end

function stats.sort_jokers(rows, by, name_of)
  local function name(r)
    if r.name ~= nil then return tostring(r.name) end
    if name_of then return tostring(name_of(r.key)) end
    return tostring(r.key)
  end
  local function value(r)
    local v = r[by or 'runs']
    return type(v) == 'number' and v or -1
  end
  table.sort(rows, function(a, b)
    local x, y = value(a), value(b)
    if x ~= y then return x > y end
    local na, nb = name(a), name(b)
    if na ~= nb then return na < nb end
    return tostring(a.key) < tostring(b.key)
  end)
  return rows
end

-- JSON ---------------------------------------------------------------------------

local ESC = {['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}

local function json_string(s)
  return '"'..s:gsub('[%c"\\]', function(c)
    return ESC[c] or string.format('\\u%04x', c:byte())
  end)..'"'
end

local function json_number(n)
  if n ~= n or n == math.huge or n == -math.huge then return 'null' end
  if n == math.floor(n) and math.abs(n) < 2^53 then return string.format('%d', n) end
  return string.format('%.17g', n)
end

-- An array when the keys are exactly 1..n (an empty table is []), else an object
-- with the keys as strings, sorted so the output is stable.
local function encode(v, out)
  local t = type(v)
  if t == 'string' then out[#out + 1] = json_string(v)
  elseif t == 'number' then out[#out + 1] = json_number(v)
  elseif t == 'boolean' then out[#out + 1] = tostring(v)
  elseif t == 'table' then
    local n, count = #v, 0
    for _ in pairs(v) do count = count + 1 end
    if count == n then
      out[#out + 1] = '['
      for i = 1, n do
        if i > 1 then out[#out + 1] = ',' end
        encode(v[i], out)
      end
      out[#out + 1] = ']'
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b)
        if type(a) == type(b) and type(a) ~= 'boolean' then return a < b end
        return type(a) < type(b)
      end)
      out[#out + 1] = '{'
      for i, k in ipairs(keys) do
        if i > 1 then out[#out + 1] = ',' end
        out[#out + 1] = json_string(tostring(k))
        out[#out + 1] = ':'
        encode(v[k], out)
      end
      out[#out + 1] = '}'
    end
  else
    out[#out + 1] = 'null'
  end
end

function stats.json(v)
  local out = {}
  encode(v, out)
  return table.concat(out)
end

-- CSV ----------------------------------------------------------------------------

local function csv_field(v)
  if v == nil then return '' end
  local s = tostring(v)
  if s:find('[,"\r\n]') then s = '"'..s:gsub('"', '""')..'"' end
  return s
end

function stats.csv_row(r)
  local played, skipped, hands, best, best_hand = 0, 0, 0, nil, nil
  for _, a in pairs(r.antes or {}) do
    for _, b in ipairs(a.blinds or {}) do
      if b.skipped then skipped = skipped + 1 else played = played + 1 end
      for _, h in ipairs(b.hands or {}) do
        hands = hands + 1
        if type(h.score) == 'number' and (not best or h.score > best) then
          best, best_hand = h.score, h.hand
        end
      end
    end
  end
  local jokers = r.jokers_final or (r.jokers_seen and r.jokers_seen[#r.jokers_seen]) or {}
  local won = r.won == true and 'true' or (r.ended_at and 'false' or nil)
  local row = {r.run_id, r.seed, r.deck, r.stake, r.started_at, r.ended_at, won,
    r.final_ante, r.final_round, played, skipped, hands, best_hand, best,
    table.concat(jokers, ';')}
  local out = {}
  for i = 1, #stats.CSV_COLUMNS do out[i] = csv_field(row[i]) end
  return table.concat(out, ',')
end

-- Same seed ------------------------------------------------------------------------

function stats.by_seed(runs)
  if runs == nil then runs = recorder.list() end
  local groups, order = {}, {}
  for _, e in ipairs(runs or {}) do
    if type(e) == 'table' and e.seed ~= nil then
      local g = groups[e.seed]
      if not g then g = {seed = e.seed, runs = {}}; groups[e.seed] = g; order[#order + 1] = g end
      g.runs[#g.runs + 1] = e
    end
  end
  local out = {}
  local function older(x, y)
    if (x.started_at or 0) ~= (y.started_at or 0) then return (x.started_at or 0) < (y.started_at or 0) end
    return tostring(x.run_id) < tostring(y.run_id)
  end
  for _, g in ipairs(order) do
    if #g.runs >= 2 then
      table.sort(g.runs, older)
      out[#out + 1] = g
    end
  end
  table.sort(out, function(x, y)
    local nx, ny = x.runs[#x.runs].started_at or 0, y.runs[#y.runs].started_at or 0
    if nx ~= ny then return nx > ny end
    return tostring(x.seed) < tostring(y.seed)
  end)
  return out
end

-- The ante's outcome, best hand and score, from its blinds.
local function ante_summary(a)
  if type(a) ~= 'table' or type(a.blinds) ~= 'table' or #a.blinds == 0 then return nil end
  local outcome, best, best_hand = 'open', nil, nil
  for _, b in ipairs(a.blinds) do
    if not b.skipped and b.won == false then outcome = 'lost' end
    if outcome ~= 'lost' and b.kind == 'Boss' and b.won == true then outcome = 'won' end
    for _, h in ipairs(b.hands or {}) do
      if type(h.score) == 'number' and (not best or h.score > best) then best, best_hand = h.score, h.hand end
    end
  end
  return outcome, best_hand, best
end

local function record_of(x)
  if type(x) == 'table' then return x end
  return recorder.read(x)
end

function stats.compare(a, b)
  local ra, err = record_of(a)
  if not ra then return nil, 'run a: '..tostring(err) end
  local rb, err2 = record_of(b)
  if not rb then return nil, 'run b: '..tostring(err2) end
  local last = 0
  for _, r in ipairs({ra, rb}) do
    for k, v in pairs(r.antes or {}) do
      if type(k) == 'number' and k > last and type(v) == 'table' and #(v.blinds or {}) > 0 then last = k end
    end
  end
  local out = {rows = {}, diverge = nil}
  for n = 1, last do
    local ea, eb = (ra.antes or {})[n], (rb.antes or {})[n]
    local oa, ha, sa = ante_summary(ea)
    local ob, hb, sb = ante_summary(eb)
    if oa or ob then
      out.rows[#out.rows + 1] = {ante = n,
        dollars_a = oa and ea.dollars_end or nil, dollars_b = ob and eb.dollars_end or nil,
        best_hand_a = ha, best_hand_b = hb, best_score_a = sa, best_score_b = sb,
        outcome_a = oa, outcome_b = ob}
      if out.diverge == nil and oa ~= ob then out.diverge = n end
    end
  end
  return out
end

-- Hunts ----------------------------------------------------------------------------

-- The run's Finder filter name, reading the record when `e` is an index entry.
local function filter_name_of(e)
  if type(e) ~= 'table' then return nil end
  local origin = e.origin
  if origin == nil and e.antes == nil and type(e.run_id) == 'string' then
    local r = recorder.read(e.run_id)
    origin = r and r.origin
  end
  local name = type(origin) == 'table' and origin.filter_name or nil
  if type(name) ~= 'string' or name == '' then return nil end
  return name
end

function stats.by_filter(runs)
  if runs == nil then runs = recorder.list() end
  local groups, out = {}, {}
  for _, e in ipairs(runs or {}) do
    local name = filter_name_of(e)
    if name then
      local g = groups[name]
      if not g then
        g = {filter_name = name, runs = 0, wins = 0, win_rate = 0, unfinished = 0, ante_sum = 0}
        groups[name] = g
        out[#out + 1] = g
      end
      local ante = tonumber(e.final_ante)
      if e.ended_at then
        g.runs = g.runs + 1
        if e.won == true then g.wins = g.wins + 1 end
        g.ante_sum = g.ante_sum + (ante or 0)
      else
        g.unfinished = g.unfinished + 1
      end
      if ante and (not g.best_ante or ante > g.best_ante) then g.best_ante = ante end
      if type(e.started_at) == 'number' and (not g.newest or e.started_at > g.newest) then
        g.newest = e.started_at
      end
    end
  end
  for _, g in ipairs(out) do
    g.win_rate = g.runs > 0 and g.wins / g.runs or 0
    g.avg_ante = g.runs > 0 and g.ante_sum / g.runs or nil
    g.ante_sum = nil
  end
  table.sort(out, function(x, y)
    if x.win_rate ~= y.win_rate then return x.win_rate > y.win_rate end
    if x.runs ~= y.runs then return x.runs > y.runs end
    if (x.newest or 0) ~= (y.newest or 0) then return (x.newest or 0) > (y.newest or 0) end
    return x.filter_name < y.filter_name
  end)
  return out
end

-- Daily seeds ------------------------------------------------------------------------

local function is_daily(e)
  if is_record(e) then return type(e.origin) == 'table' and e.origin.kind == 'daily' end
  return e.daily == true
end

function stats.dailies(runs, read)
  if runs == nil then runs = recorder.list() end
  read = read or recorder.read
  local out = {}
  for _, e in ipairs(runs or {}) do
    if type(e) == 'table' and is_daily(e) then
      local origin = e.origin
      if not is_record(e) then
        local ok, r = pcall(read, e.run_id)
        origin = ok and type(r) == 'table' and r.origin or nil
      end
      if type(origin) ~= 'table' then origin = {} end
      local date = type(origin.date) == 'string' and origin.date or nil
      if not date and type(e.started_at) == 'number' then date = os.date('!%Y-%m-%d', e.started_at) end
      local mode = (origin.mode == 'blind' or origin.mode == 'routed') and origin.mode or nil
      local won = nil
      if e.won == true then won = true elseif finished(e) then won = false end
      out[#out + 1] = {run_id = e.run_id, date = date, mode = mode, seed = e.seed, deck = e.deck,
        stake = e.stake, won = won, final_ante = e.final_ante, started_at = e.started_at,
        ended_at = e.ended_at}
    end
  end
  table.sort(out, function(x, y)
    local tx, ty = tonumber(x.started_at) or 0, tonumber(y.started_at) or 0
    if tx ~= ty then return tx > ty end
    return tostring(x.run_id) > tostring(y.run_id)
  end)
  return out
end

-- Export -------------------------------------------------------------------------

-- Every recorded run's record, oldest first. An unreadable record is skipped.
local function records()
  local list = recorder.list()
  local out = {}
  for i = #list, 1, -1 do
    local r = recorder.read(list[i].run_id)
    if r then out[#out + 1] = r end
  end
  return out
end

local function for_json(r)
  local copy = {}
  for k, v in pairs(r) do copy[k] = v end
  local antes = {}
  for a, v in pairs(r.antes or {}) do antes[tostring(a)] = v end
  copy.antes = antes
  return copy
end

function stats.export(fmt)
  if fmt ~= 'csv' and fmt ~= 'json' then return nil, 'unknown format' end
  local runs = records()
  local text
  if fmt == 'csv' then
    local lines = {table.concat(stats.CSV_COLUMNS, ',')}
    for _, r in ipairs(runs) do lines[#lines + 1] = stats.csv_row(r) end
    text = table.concat(lines, '\n')..'\n'
  else
    local list = {}
    for i, r in ipairs(runs) do list[i] = for_json(r) end
    text = '{"version":1,"runs":'..(#list == 0 and '[]' or stats.json(list))..'}\n'
  end
  local dir = recorder.dir()
  love.filesystem.createDirectory(dir)
  local path = dir..'/export-'..tostring(os.time())..'.'..fmt
  local ok, res, err = pcall(love.filesystem.write, path, text)
  if not ok then return nil, tostring(res) end
  if not res then return nil, tostring(err or 'write failed') end
  local rok, back = pcall(love.filesystem.read, path)
  if not rok or back ~= text then return nil, 'read-back mismatch' end
  return path
end

setmetatable(stats, {__call = function(_, filter) return stats.compute(filter) end})

return stats
