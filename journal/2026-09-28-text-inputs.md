# Text inputs: vanilla's quirks, and what Steamodded and HandyBalatro change

0.3.4 added five text boxes to Save Slots and the Finder, and a fix so a typed `0` stays
`0`. Four things about vanilla's `create_text_input` / `text_input_key` bit along the way.

- **Vanilla types `o` for `0` in every input** (`button_callbacks.lua:970`, `if args.key ==
  '0' then args.key = 'o' end`: seeds have no zero). That's why saves were called `max_o`.
  `BHCore.install_digits` wraps `text_input_key` for inputs flagged `bh_digits`: it lets
  vanilla type its `o`, then writes `0` into that letter and calls
  `TRANSPOSE_TEXT_INPUT(0)` so vanilla rebuilds the text itself.
  - Where the letter went is **not** `text.current_position`. Vanilla computes it from the
    text *before* the rebuild, so it lags one key. It's the cursor child's index - 1
    (capped at the text's length), plus 1.
  - A letter diff can't find it either: typing before an `o` makes the first changed
    letter the old `o`.
  - A full input types nothing. Without a length check the wrap turned an old `o` at the
    cursor into `0`. `text_digits` covers all three.

- **Steamodded prefixes the input's child ids, and HandyBalatro copies that patch**
  (Handy's `lovely/ui_fixes.toml` says "All fixes here taken from SMODS"). `create_text_input`
  gets `args.id = args.id or "text_input"`, and its children become `<id>_letter_<i>`,
  `<id>_prompt` and `<id>_position`. `select_text_input` records `G.CONTROLLER.text_input_id`,
  and `TRANSPOSE_TEXT_INPUT` / `GET_TEXT_FROM_INPUT` look for the prefixed ids.
  - The first `install_digits` looked for `id == 'position'`, so under Steamodded or Handy
    it silently did nothing. Caught by running `text_digits` in the real-lovely rig after
    the vanilla barrier was green.
  - The fix matches the `_position` suffix too.
  - `make lovely-check` now runs `text_digits`, `finder_names` and `saveslots_folders` under
    Steamodded, and `text_digits` under Handy alone.
  - Lesson: any code that walks an input's children must accept both id styles. So must
    anything that sets `G.CONTROLLER.text_input_hook` without going through
    `select_text_input`: under Steamodded, `text_input_id` would then be stale.

- **One element per `draw_layer` per UIBox.** `UIElement:set_values` does
  `draw_layers[layer] = self`, and a vanilla text input sits on draw_layer 2. So a second
  input in the same UIBox made the first one vanish. The Save Slots search box lives in
  its own UIBox for that reason. Steamodded's copy of `create_text_input` drops the
  `draw_layer`s, so the bug only shows in vanilla.

- **`G.FUNCS.flash` blinks the cursor of every input whenever any input is hooked**, and
  changes the cursor's width, which lays that input's box out again. With two inputs on
  screen, both showed a cursor, and a nested box's prompt ended up misplaced. Save Slots'
  name and search inputs use their own cursor func (`saveslots_cursor`): it keeps one
  width and blinks only when its own input is the hook. Steamodded's patch of `flash`
  compares `text_input_id` instead.

- Also seen (T-360): in an extended-corpus input, `text_input_key` maps shifted keys with
  `string.find(lower_ext, key)`, which treats the key as a pattern. Shift + `.` types `!`,
  and a raw `(` key would raise a pattern error. Scenarios avoid both.
