-- lovely_oracle_smods: for the real-lovely rig next to Steamodded alone
-- (rig/lovely-rig.sh lovely_oracle_smods --smods). The Oracle opens in a run and predicts
-- tags, Vouchers, The Soul, shops and packs without errors, with no editions (Steamodded
-- rolls them its own way) and later bosses marked unverified. Screenshot: oracle.png.
return {
  {name = 'steamodded present', run = function(ctx)
    BHCore._env = nil
    ctx.assert(BHCore.env().smods, 'Steamodded not detected (run with --smods)')
    ctx.assert(#BHCore.env().content == 0, 'content mods detected')
    return true
  end},
  {name = 'start run', run = function(ctx) ctx.start_run{}; return true end},
  {name = 'blind select', timeout = 30, run = function(ctx)
    return G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil
  end},
  {name = 'model', timeout = 10, run = function(ctx)
    local m = SeedOracle.oracle.get()
    if not m then return false end
    ctx.assert(not m.error, 'prediction failed: '..tostring(m.error))
    ctx.assert(not m.off, 'Oracle is off: '..tostring(m.off))
    local r = m.antes[1]
    ctx.assert(r.tags.small.key and r.boss.key and r.voucher.key, 'tags, boss or voucher missing')
    ctx.assert(r.soul and r.soul.key, 'The Soul not predicted')
    ctx.assert(r.shop and r.shop.cards and #r.shop.cards > 0, 'the shop not predicted')
    local function no_editions(t, seen)
      if type(t) ~= 'table' or seen[t] then return end
      seen[t] = true
      ctx.assert(not (t.key and t.edition), 'an edition is shown: '..tostring(t.key)..'/'..tostring(t.edition))
      for _, v in pairs(t) do no_editions(v, seen) end
    end
    no_editions(m, {})
    ctx.assert(m.antes[2].boss.badge == 'unverified', 'ante 2 boss badge is '..tostring(m.antes[2].boss.badge))
    ctx.log(('ante 1: %s / %s, boss %s, voucher %s, soul %s, shop %s'):format(r.tags.small.key, r.tags.big.key,
      r.boss.key, r.voucher.key, r.soul.key, r.shop.cards[1].key))
    return true
  end},
  {name = 'oracle opens', timeout = 20, run = function(ctx)
    if ctx.step_time() < 1 then return false end
    if not G.OVERLAY_MENU then G.FUNCS.seedoracle_open(); return false end
    if ctx.step_time() < 3 then return false end
    ctx.shot('oracle')
    return true
  end},
}
