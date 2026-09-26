-- Self-test: a step that asserts false must make the rig report SMOKE FAIL.
-- Excluded from `smoke.sh all`.
return {
  {name = 'deliberate failure', run = function(ctx)
    ctx.assert(false, 'selftest: this step always fails')
    return true
  end},
}
