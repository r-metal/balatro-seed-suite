-- SeedFinder: searches seeds against multi-clause filters on worker threads. Contracts: docs/contracts-0.2.md.
if SeedFinder then return SeedFinder end

require('bhcore.init')

SeedFinder = {VERSION = '0.3.2'}
SeedFinder.filter = require('seedfinder.filter')
SeedFinder.engine = require('seedfinder.engine')
SeedFinder.worker = require('seedfinder.worker')
SeedFinder.ui = require('seedfinder.ui')

SeedFinder.ui.install()

return SeedFinder
