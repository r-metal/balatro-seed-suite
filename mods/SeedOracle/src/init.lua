-- SeedOracle: predicts tags, bosses, vouchers, shops and packs for the current seed. Contracts: docs/contracts-0.2.md.
if SeedOracle then return SeedOracle end

require('bhcore.init')

SeedOracle = {VERSION = '0.4.0'}
SeedOracle.oracle = require('seedoracle.oracle')
SeedOracle.ui = require('seedoracle.ui')

SeedOracle.oracle.install()
SeedOracle.ui.install()

return SeedOracle
