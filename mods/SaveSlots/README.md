# SaveSlots — named save slots for Balatro

A lovely mod: keep as many named runs as you like and resume any of them from a
list with a card-level preview (deck, stake, ante, money, seed, jokers,
consumables, vouchers).

> 0.2.0 adds auto-checkpoints (one per ante, the last 8 per run), practice
> scenarios (**New practice…**), seed-hunt entries from the Seed Finder, target/notes per
> slot, and a kind filter (All / Saves / Checkpoints / Practice / Hunts).
>
> Since 0.2.0: favorite a slot from the details column to pin it at the top of the list;
> auto-checkpoint pruning never deletes a favorite, and
> a Favorites filter lists only them.

## Using it

- **In a run:** pause (Esc) → **Save Slots**. Type a name, then **Save**.
  The save is the game's last autosave point (blind select, shop, after a hand),
  the same point Continue would resume from, not the exact frame you pressed it.
- **From the main menu:** **Play → Saves** tab (3 most recent + "Open Save
  Slots"), or **Options → Save Slots**.
- In the list: pick a save to preview it, then **Load**, **Overwrite** (in a
  run only), **Rename** (uses the name box), or **Delete** (press twice).
- **Folders:** give a save a folder from its details column (**Edit** next to Folder):
  type a new name or pick one you already use. The folder cycle next to the kind
  cycle lists one folder at a time, or the saves in no folder (**Unfiled**).
  Auto-checkpoint pruning never deletes a checkpoint you filed.
- **Search:** the box under the name matches a save's name, seed, deck, notes,
  target or folder as you type.
- Loading a save also makes it the main-menu **Continue** run.
- Brainstorm's `z/x + 1-5` slots are imported once as "Brainstorm slot N".
  The originals are left in place.

## Where saves live

In Balatro's save folder, next to your profile's own saves:

```
<Balatro save folder>/<profile>/saveslots/
  <id>.jkr     one run each, same format as save.jkr
  index.jkr    names, timestamps, preview summaries
```

The save folder is `%AppData%\Balatro` on Windows,
`~/Library/Application Support/Balatro` on macOS, and
`<Steam library>/steamapps/compatdata/2379780/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro`
under Proton.

## Install

Part of Balatro Seed Suite. It needs **bh-core** since 0.2. See the [top-level README](../../README.md).

## Known limitations

- A save is the last autosave point, not the exact frame you pressed Save.
- A few jokers compute tooltip numbers from the *current* run while shown in a preview (cosmetic).
- Loading a save taken in the shop logs `Card area 'shop_*' not instantiated before load`. That also happens in vanilla and is harmless.
