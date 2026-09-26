# Vanilla UI widget traps (from the Finder UI)

- **`create_option_cycle` returns a `G.UIT.R`**, so several cycles in one row stack vertically unless each is wrapped in a `G.UIT.C`.
- **A DynaText's `maxw` only applies in `DynaText:init`.** When a cycle changes, the label updates without refitting (non_recalc), so a long option either widens the row at build time or overflows later. Scale the DynaText to the cycle's width after building it, and rebuild the panel when labels vary a lot.
- **A single-option cycle draws disabled arrows with no button**, so the ids you gave its arrows are gone unless you put them on the arrow C-nodes yourself.
- **`unlock_card` queues an "Unlocked!" overlay** through `save_notify` → `unlock_notify.jkr`. It pops at the next run start, holding `locks.load` and `G.OVERLAY_MENU`. A scenario that unlocks decks should set the `unlocked`/`discovered` flags directly.
- **Vanilla's first Continue on a profile** shows a "Joker Unlocked!" card (Throwback) that has to be dismissed before the run is interactive. On a fresh profile Challenges are locked (`challenges_unlocked`).
