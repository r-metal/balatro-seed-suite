-- finder_search: a Seed Finder search runs to completion on its worker threads and
-- reports no error. Loader-agnostic on purpose (no vanilla profile setup), so it also
-- runs under the real-lovely rig next to Steamodded (rig/lovely-rig.sh --smods), where
-- 0.3.0's workers died on Steamodded-patched game code ("attempt to index global 'SMODS'").
local engine = require('seedfinder.engine')
local CHARM = {name = 'Charm', clauses = {{kind = 'tag', ante = 1, blind = 'any', key = 'tag_charm'}}}
local S = {}
return {
  {name = 'start search', run = function(ctx)
    BHCore._env = nil
    local e = BHCore.env()
    ctx.log(('env: smods=%s content={%s} notice=%s'):format(tostring(e.smods), table.concat(e.content, ','),
      tostring((BHCore.env_notice()))))
    ctx.assert(#e.content == 0, 'content mods detected: '..table.concat(e.content, ','))
    local ok, h = pcall(engine.start, CHARM, {workers = 2, max_seeds = 4000, start = 0})
    ctx.assert(ok, 'engine.start raised: '..tostring(h))
    S.h = h
    return true
  end},
  {name = 'search completes', timeout = 90, run = function(ctx)
    local p = engine.poll(S.h)
    ctx.assert(not p.error, 'search failed: '..tostring(p.error))
    if not p.done then return false end
    ctx.assert(p.scanned >= 4000, 'scanned only '..tostring(p.scanned))
    -- The workers run vanilla's code; the main-thread re-check runs the live game's
    -- (Steamodded-patched, under --smods). Zero rejections means both agree.
    ctx.log(('scanned %d seeds, %d verified Charm hits, %d rejected by the re-check')
      :format(p.scanned, #p.found, p.rejected or 0))
    ctx.assert(#p.found > 0, 'no Charm Tag hits in 4000 seeds')
    ctx.assert((p.rejected or 0) == 0, (p.rejected or 0)..' worker hits failed the main-thread re-check')
    return true
  end},
}
