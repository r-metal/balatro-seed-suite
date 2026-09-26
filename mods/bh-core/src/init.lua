-- bh-core: shared library for the suite. Contracts: docs/bh-core.md.
if BHCore then return BHCore end

BHCore = {VERSION = '0.3.0'}

-- True when this bh-core serves a mod built for major.minor `want` ('0.3'). Before 1.0
-- a minor release may change the contracts, so both parts must match.
function BHCore.compat(want)
  return BHCore.VERSION:match('^%d+%.%d+') == want
end
BHCore.events = require('bhcore.events')
BHCore.events.install()

return BHCore
