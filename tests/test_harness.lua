-- Sanity checks for the harness itself.
local H = ...
H.test('string_packer round-trips a run table', function()
  local run = H.fake_run()
  local back = STR_UNPACK(STR_PACK(run))
  H.eq(back.GAME.round_resets.ante, 2)
  H.eq(back.cardAreas.jokers.cards[1].save_fields.center, 'j_joker')
end)
H.test('compress_and_save / get_compressed round-trip through the fake fs', function()
  love.filesystem.createDirectory('1')
  compress_and_save('1/x.jkr', H.fake_run{ante = 7})
  H.eq(STR_UNPACK(get_compressed('1/x.jkr')).GAME.round_resets.ante, 7)
end)
