-- bh-core is a folder of its own in Mods/. Without it, or with one from another
-- release, RunJournal stays off and the main menu says why, instead of the game failing
-- to boot. NEEDS is this release's major.minor (scripts/release.py checks it).
local NEEDS = '0.4'
local core = package.preload['bhcore.init'] and require('bhcore.init')
if type(core) == 'table' and core.compat and core.compat(NEEDS) then
  require('runjournal.init')
else
  local found = type(core) == 'table' and tostring(core.VERSION) or 'not installed'
  print('[RunJournal] disabled: needs bh-core '..NEEDS..'.x, found '..found)
  if not BHSuiteNotice then
    BHSuiteNotice = {mods = {}, needs = NEEDS, found = found}
    local draw, font = love.draw
    function love.draw(...)
      if draw then draw(...) end
      if not (G and G.STAGES and G.STAGE == G.STAGES.MAIN_MENU) then return end
      local n = BHSuiteNotice
      local text = 'Balatro Seed Suite: '..table.concat(n.mods, ', ')..' disabled - needs bh-core '
        ..n.needs..'.x ('..n.found..'). Install the whole BalatroSeedSuite.zip into Mods/.'
      local w, h = love.graphics.getDimensions()
      font = font or love.graphics.newFont(math.max(12, math.floor(h / 45)))
      local pad, lh = 8, font:getHeight()
      love.graphics.push('all')
      love.graphics.origin()
      love.graphics.setFont(font)
      love.graphics.setColor(0, 0, 0, 0.75)
      love.graphics.rectangle('fill', 0, h - lh - 2 * pad, w, lh + 2 * pad)
      love.graphics.setColor(1, 0.45, 0.4, 1)
      love.graphics.printf(text, pad, h - lh - pad, w - 2 * pad, 'left')
      love.graphics.pop()
    end
  end
  BHSuiteNotice.mods[#BHSuiteNotice.mods + 1] = 'RunJournal'
end
