-- finder_search: a Seed Finder search runs to completion on its worker threads and
-- reports no error. Loader-agnostic on purpose (no vanilla profile setup), so it also
-- runs under the real-lovely rig next to Steamodded (rig/lovely-rig.sh --smods), where
-- 0.3.0's workers died on Steamodded-patched game code ("attempt to index global 'SMODS'").
local engine = require('seedfinder.engine')
local SEARCHES = {
  {f = {name = 'Charm', clauses = {{kind = 'tag', ante = 1, blind = 'any', key = 'tag_charm'}}}, seeds = 4000},
  -- Card clauses: which legendary the first Soul makes, and the Soul in a tag pack.
  {f = {name = 'Triboulet', clauses = {{kind = 'legendary', index = 1, key = 'j_triboulet'}}}, seeds = 4000},
  {f = {name = 'Charm Soul', clauses = {{kind = 'tag', ante = 1, blind = 'any', key = 'tag_charm'},
    {kind = 'soul_in_pack', ante = 1, pack = 'arcana', from_tag = true}}}, seeds = 20000},
}
local S = {}
local steps = {
  {name = 'environment', run = function(ctx)
    BHCore._env = nil
    local e = BHCore.env()
    ctx.log(('env: smods=%s content={%s} notice=%s'):format(tostring(e.smods), table.concat(e.content, ','),
      tostring((BHCore.env_notice()))))
    ctx.assert(#e.content == 0, 'content mods detected: '..table.concat(e.content, ','))
    return true
  end},
}
for _, sr in ipairs(SEARCHES) do
  steps[#steps + 1] = {name = 'start '..sr.f.name, run = function(ctx)
    local ok, h = pcall(engine.start, sr.f, {workers = 2, max_seeds = sr.seeds, start = 0})
    ctx.assert(ok, 'engine.start raised: '..tostring(h))
    S.h = h
    return true
  end}
  steps[#steps + 1] = {name = sr.f.name..' completes', timeout = 180, run = function(ctx)
    local p = engine.poll(S.h)
    ctx.assert(not p.error, 'search failed: '..tostring(p.error))
    if not p.done then return false end
    ctx.assert(p.scanned >= sr.seeds, 'scanned only '..tostring(p.scanned))
    -- The workers run vanilla's code; the main-thread re-check runs the live game's
    -- (Steamodded-patched, under --smods). Zero rejections means both agree.
    ctx.log(('%s: scanned %d seeds, %d verified hits, %d rejected by the re-check')
      :format(sr.f.name, p.scanned, #p.found, p.rejected or 0))
    ctx.assert(#p.found > 0, 'no '..sr.f.name..' hits in '..sr.seeds..' seeds')
    ctx.assert((p.rejected or 0) == 0, (p.rejected or 0)..' worker hits failed the main-thread re-check')
    return true
  end}
end
return steps
