-- RunJournal: records every run locally, with stats and CSV/JSON export. Contracts: docs/contracts-0.2.md.
if RunJournal then return RunJournal end

require('bhcore.init')

RunJournal = {VERSION = '0.3.2'}
RunJournal.recorder = require('runjournal.recorder')
RunJournal.stats = require('runjournal.stats')
RunJournal.ui = require('runjournal.ui')

RunJournal.recorder.install()
RunJournal.ui.install()

return RunJournal
