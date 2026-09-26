-- SaveSlots: named save slots with a card-level preview.
-- Runs once, at the end of main.lua (see lovely.toml). Contracts: docs/SPEC.md.
if SaveSlots then return SaveSlots end

require('bhcore.init') -- 0.2: events (auto-checkpoints) and fs come from bh-core

SaveSlots = {VERSION = '0.3.0'}
SaveSlots.store = require('saveslots.store')
SaveSlots.checkpoint = require('saveslots.checkpoint')
SaveSlots.preview = require('saveslots.preview')
SaveSlots.ui = require('saveslots.ui')
SaveSlots.entry = require('saveslots.entry')
SaveSlots.practice = require('saveslots.practice')

SaveSlots.checkpoint.install()
SaveSlots.ui.install()
SaveSlots.entry.install()
SaveSlots.practice.install()

return SaveSlots
