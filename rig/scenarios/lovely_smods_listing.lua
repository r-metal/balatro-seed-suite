-- lovely_smods_listing: for the real-lovely rig next to Steamodded
-- (rig/lovely-rig.sh lovely_smods_listing --smods). Steamodded lists the suite from its
-- metadata.json (not as a "lovely-compat" stub), can load it, and the suite runs.
return {
  {name = 'listed', run = function(ctx)
    ctx.assert(SMODS and SMODS.Mods, 'Steamodded not loaded (run with --smods)')
    local m = SMODS.Mods.BalatroSeedSuite
    ctx.assert(m, 'not in SMODS.Mods; ids: '..(function()
      local t = {} for k in pairs(SMODS.Mods) do t[#t + 1] = k end return table.concat(t, ',') end)())
    ctx.assert(m.name == 'Balatro Seed Suite' and m.author[1] == 'r-metal', 'wrong metadata: '..tostring(m.name))
    ctx.assert(m.can_load ~= false and not m.disabled, 'Steamodded will not load it')
    for k in pairs(SMODS.Mods) do ctx.assert(not k:find('lovely%-compat%-BalatroSeedSuite'), 'stub listing '..k) end
    ctx.log(('SMODS lists %s %s by %s'):format(m.id, tostring(m.version), m.author[1]))
    return true
  end},
  {name = 'suite running', run = function(ctx)
    ctx.assert(BHCore and SaveSlots and SeedOracle and SeedFinder and RunJournal, 'a suite mod is missing')
    ctx.assert(SeedFinder.VERSION == BHCore.VERSION, 'versions differ')
    return true
  end},
}
