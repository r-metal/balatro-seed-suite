# `G.ARGS.save_run` is never cleared

`save_run()` (`functions/misc_functions.lua:1452`) sets `G.ARGS.save_run = G.culled_table`, and nothing ever resets it: not quitting to the menu, not `start_run`. Code that reads it as "the current run" (Brainstorm's save-state hotkey) will:

- crash with `bad argument #3 to 'compress'` (`engine/string_packer.lua:70`) before the first autosave of the session, because `compress_and_save(path, nil)`;
- silently save the **previous** run if you start a new run and press save before its first autosave.

Also, `Game:start_run` does `self.GAME = saveTable.GAME`, **by reference**. The table you load from mutates as you play, so anything you keep must be deep-copied first (`STR_UNPACK(STR_PACK(t))`).

SaveSlots tracks its own snapshot instead: it wraps `save_run` (take `G.culled_table` after the original) and `Game.start_run` (reset the snapshot, or deep-copy `args.savetext`).
