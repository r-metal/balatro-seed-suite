-- Tracks the last safe run snapshot and loads runs. Contract: docs/SPEC.md.
--
-- What this module is for
--   Saving a slot must store a state the game itself considered safe to resume
--   from (D6): the table vanilla `save_run()` builds at its autosave points
--   (blind select, shop, after a hand). Never a mid-animation state, never
--   `save.jkr` on disk, never `G.ARGS.save_run` (see "Traps" below).
--
-- API
--   checkpoint.install()   Wraps the global `save_run` and `Game.start_run`.
--                          Safe to call more than once: later calls are no-ops.
--   checkpoint.get()       The latest snapshot of the current run, or nil when
--                          this run has not produced one yet (callers refuse to
--                          save and say so on screen).
--   checkpoint.run_id()    The current run's auto-checkpoint run id, `<seed>:<start
--                          os.time>`, or nil before the first run_start.
--   checkpoint.auto_save(run)
--                          The auto-checkpoint save path: stores `run` (a save_run()
--                          table) as `kind = 'checkpoint'`, named "Auto A<ante>", under
--                          the current run id, then prunes (store.prune_checkpoints:
--                          newest AUTO_KEEP_PER_RUN per run id, AUTO_KEEP_RUNS run ids).
--                          Returns the slot id, or nil, err ('disabled', 'in sim', 'no
--                          run', or a store error). It never calls save_run().
--   checkpoint.load_run(run)
--                          Resumes `run` (a table shaped like `save_run()`
--                          output, e.g. from `store.read`): writes it to
--                          `<profile>/save.jkr` so main-menu Continue matches
--                          (D3), closes any overlay, then starts it through
--                          `G.FUNCS.start_run`. Returns true, or nil, err
--                          ('no run' for a non-table, or the write error).
--
-- Hooks (all call the original; none replaces vanilla behaviour)
--   save_run         After the original returns, `G.culled_table` is the fresh
--                    snapshot (vanilla rebuilds it on every call, so keeping the
--                    reference is safe). Skipped when saving is disabled
--                    (`G.F_NO_SAVING == true`, where vanilla returns early).
--   Game:start_run   Before the original runs, resets the snapshot: a deep copy
--                    of `args.savetext` when resuming a saved run, else nil.
--   Blind:load       After the original, brings the blind HUD on screen for a run
--                    resumed mid-blind. Vanilla (blind.lua:746-749) does that only
--                    when the blind pays dollars, so a $0 blind (Small Blind at Red
--                    stake and up) left the HUD at start_run's offset.y = -10: no
--                    blind name, score target or reward for the whole round.
--
-- Auto-checkpoints (docs/contracts-0.2.md § SaveSlots 0.2, T-121)
--   bh-core events arm them: `run_start` of a new run (ante 1) and every
--   `ante_change`. The first snapshot taken while armed whose STATE is
--   BLIND_SELECT (vanilla's autosave in Game:update_blind_select, game.lua:3265)
--   goes through auto_save, and disarms. Nothing is saved while
--   `SaveSlots.settings.auto_checkpoints == false` (default on) or inside a sim
--   (`BHCore.sim_depth > 0`).
--   run id: a new run gets `<seed>:<os.time()>` at run_start. A loaded run (Continue,
--   a slot, a rewind to "Auto A2") continues the newest checkpoint run id with its
--   seed, or starts a new one when there is none; it is not armed, so loading never
--   makes a checkpoint by itself. Two playthroughs of one seed loaded later therefore
--   share the newest one's run id.
--   Pruning only ever deletes kind 'checkpoint' entries that carry a run_id: player
--   saves, practice and hunt slots are never evicted.
--
-- Traps (docs/SPEC.md "Traps")
--   * `G.ARGS.save_run` is never cleared, so after quitting to the menu and
--     starting a new run it still holds the previous run. Resetting in
--     start_run is what keeps `get()` from returning that stale run.
--   * start_run keeps the table it loads by reference (`G.GAME =
--     saveTable.GAME`), so it mutates as you play. The snapshot is taken with
--     `STR_UNPACK(STR_PACK(t))` before the original sees it.
--   * `compress_and_save(path, nil)` crashes inside love.data.compress, so
--     load_run refuses anything that isn't a table before writing.
--   * Don't call `save_run()` from here to force a fresh snapshot: outside the
--     game's own call sites it can capture a state mid-animation.
local store = require('saveslots.store')

local checkpoint = {}

checkpoint.AUTO_KEEP_PER_RUN = 8
checkpoint.AUTO_KEEP_RUNS = 3

local snapshot = nil
local installed = false
local run_id = nil   -- auto-checkpoint run id of the current run
local armed = false  -- the next BLIND_SELECT snapshot becomes a checkpoint

local function deep_copy(t)
  return STR_UNPACK(STR_PACK(t))
end

local function in_sim()
  return type(BHCore) == 'table' and (BHCore.sim_depth or 0) > 0
end

local function enabled()
  local s = type(SaveSlots) == 'table' and SaveSlots.settings
  return not (type(s) == 'table' and s.auto_checkpoints == false)
end

-- The newest checkpoint run id for `seed`, or nil. store.list is newest first.
local function latest_run_id(seed)
  local prefix = tostring(seed)..':'
  for _, e in ipairs(store.list({kind = 'checkpoint'})) do
    local rid = e.meta.run_id
    if type(rid) == 'string' and rid:sub(1, #prefix) == prefix then return rid end
  end
end

local function on_run_start(p)
  armed = not p.loaded
  run_id = p.loaded and latest_run_id(p.seed) or nil
  run_id = run_id or (tostring(p.seed)..':'..tostring(os.time()))
end

local function on_ante_change(p)
  if p.from ~= p.to then armed = true end
end

function checkpoint.run_id()
  return run_id
end

function checkpoint.auto_save(run)
  if not enabled() then return nil, 'disabled' end
  if in_sim() then return nil, 'in sim' end
  if type(run) ~= 'table' or not run_id then return nil, 'no run' end
  local ante = store.summarize(run).ante
  local id, err = store.save(run, 'Auto A'..tostring(ante or '?'), nil,
    {kind = 'checkpoint', run_id = run_id})
  if not id then return nil, err end
  local _, perr = store.prune_checkpoints(checkpoint.AUTO_KEEP_PER_RUN, checkpoint.AUTO_KEEP_RUNS)
  if perr then print('[SaveSlots] auto-checkpoint prune: '..tostring(perr)) end
  return id
end

-- Called with every fresh snapshot: saves it when armed and at blind select.
local function maybe_auto(run)
  if not armed or in_sim() or run.STATE ~= G.STATES.BLIND_SELECT then return end
  armed = false
  if not enabled() then return end
  local ok, id, err = pcall(checkpoint.auto_save, run)
  if not ok or not id then
    print('[SaveSlots] auto-checkpoint failed: '..tostring(ok and err or id))
  end
end

function checkpoint.install()
  if installed then return end
  installed = true

  if type(SaveSlots) == 'table' then
    SaveSlots.settings = SaveSlots.settings or {}
    if SaveSlots.settings.auto_checkpoints == nil then SaveSlots.settings.auto_checkpoints = true end
  end
  local events = require('bhcore.events')
  events.on('run_start', on_run_start)
  events.on('ante_change', on_ante_change)

  local orig_save_run = save_run
  local function record(...)
    if G.F_NO_SAVING ~= true and type(G.culled_table) == 'table' then
      snapshot = G.culled_table
      maybe_auto(snapshot)
    end
    return ...
  end
  save_run = function(...)
    return record(orig_save_run(...))
  end

  local orig_start_run = Game.start_run
  Game.start_run = function(self, args, ...)
    if args and args.savetext then
      snapshot = deep_copy(args.savetext)
    else
      snapshot = nil
    end
    return orig_start_run(self, args, ...)
  end

  if type(Blind) == 'table' and type(Blind.load) == 'function' then
    local orig_blind_load = Blind.load
    Blind.load = function(self, ...)
      local ret = orig_blind_load(self, ...)
      if self.blind_set and G.HUD_blind then G.HUD_blind.alignment.offset.y = 0 end
      return ret
    end
  end
end

function checkpoint.get()
  return snapshot
end

function checkpoint.load_run(run)
  if type(run) ~= 'table' then return nil, 'no run' end

  local ok, err = pcall(compress_and_save, G.SETTINGS.profile..'/save.jkr', run)
  if not ok then return nil, 'could not write save.jkr: '..tostring(err) end
  G.SAVED_GAME = nil

  if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() end
  G.FUNCS.start_run(nil, {savetext = run})
  return true
end

return checkpoint
