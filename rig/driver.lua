-- Smoke-rig driver. Runs inside the real game, appended to main.lua by rig/build.lua.
-- Prepares a clean profile (tutorial done, splash skipped, muted), waits for the
-- main menu, then runs the scenario's steps one frame at a time after G:update.
-- The verdict goes to <out>/result.txt; smoke.sh turns it into the SMOKE line.
local cfg = ...
local BOOT_TIMEOUT = 60   -- seconds for the main menu to come up
local MENU_SETTLE = 1.0   -- seconds to let the title animation land before step 1

local rig = {phase = 'boot', step = 0, pending_shots = 0, frames = 0}
local now = function() return love.timer.getTime() end
rig.t0 = now()

local function say(msg) print('[smoke] '..msg); io.stdout:flush() end

local function finish(ok, reason)
  if rig.phase == 'done' then return end
  rig.phase = 'done'
  local line = ok and 'PASS' or ('FAIL: '..tostring(reason):gsub('\n', ' '))
  local f = io.open(cfg.out..'/result.txt', 'wb')
  if f then f:write(line, '\n'); f:close() end
  say('result '..line)
  love.event.quit(ok and 0 or 1)
end

-- A game error ends the scenario instead of sitting on the crash screen until the
-- wall-clock timeout. Replaces the vanilla handler (which could also phone home).
function love.errorhandler(msg)
  msg = tostring(msg)
  io.stderr:write('[smoke] game error: ', msg, '\n', debug.traceback('', 2), '\n')
  if rig.phase ~= 'done' then
    rig.phase = 'done'
    local f = io.open(cfg.out..'/result.txt', 'wb')
    if f then f:write('FAIL: game error: ', (msg:gsub('\n', ' ')), '\n'); f:close() end
  end
end

-- Clean-profile setup, applied after settings load and before the splash starts.
local splash_screen = Game.splash_screen
function Game:splash_screen(...)
  G.F_SKIP_TUTORIAL = true
  G.F_MUTE = true
  G.F_CRASH_REPORTS = false
  G.SETTINGS.tutorial_complete = true
  G.SETTINGS.tutorial_progress = nil
  G.SETTINGS.skip_splash = 'Yes'
  G.SETTINGS.crashreports = false
  if G.SETTINGS.SOUND then G.SETTINGS.SOUND.volume = 0 end
  return splash_screen(self, ...)
end

-- ctx: the scenario's view of the rig. Contract: docs/SPEC.md § Smoke rig contract.
local ctx = {name = cfg.name, out = cfg.out}

function ctx.log(msg) say(tostring(msg)) end

function ctx.assert(cond, msg)
  if not cond then error(msg or 'assertion failed', 2) end
  return cond
end

function ctx.shot(label)
  label = tostring(label)
  if not label:match('^[%w_%-]+$') then error('shot label must be [A-Za-z0-9_-]: '..label, 2) end
  local path = cfg.out..'/'..label..'.png'
  rig.pending_shots = rig.pending_shots + 1
  love.graphics.captureScreenshot(function(img)
    local data = img:encode('png'):getString()
    local f = io.open(path, 'wb')
    if f then f:write(data); f:close() end
    rig.pending_shots = rig.pending_shots - 1
    say('shot '..label..' -> '..path..' ('..#data..' bytes)')
  end)
end

-- Every UIBox reachable from G.I (all instance lists), the overlay and the main
-- menu, including UIBoxes nested as config.object inside another box.
local function each_uibox(fn)
  local seen = {}
  local function visit_box(box)
    if type(box) ~= 'table' or seen[box] or box.REMOVED or not box.UIRoot then return end
    seen[box] = true
    local function walk(node)
      if type(node) ~= 'table' or node.REMOVED then return end
      if fn(node) then return true end
      local obj = node.config and node.config.object
      if type(obj) == 'table' and obj.UIRoot then visit_box(obj) end
      for _, child in pairs(node.children or {}) do
        if walk(child) then return true end
      end
    end
    return walk(box.UIRoot)
  end
  for _, list in pairs(G.I or {}) do
    for _, box in ipairs(list) do
      if visit_box(box) then return end
    end
  end
  if visit_box(G.OVERLAY_MENU) then return end
  visit_box(G.MAIN_MENU_UI)
end

function ctx.find_button(button, id)
  local found
  each_uibox(function(node)
    local c = node.config
    if c and c.button == button and (id == nil or c.id == id) then found = node; return true end
  end)
  return found
end

function ctx.click(button, id)
  local e = ctx.find_button(button, id)
  if not e then return false end
  local fn = G.FUNCS[button]
  if not fn then error('G.FUNCS.'..tostring(button)..' does not exist', 2) end
  fn(e)
  return true
end

function ctx.start_run(args)
  if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() end
  G.FUNCS.start_run(nil, args or {})
end

-- Rig extension (not in the locked contract, additive): seconds since the
-- current step started, for steps that must let an animation settle.
function ctx.step_time() return now() - (rig.step_started or now()) end

-- Load the scenario.
local steps
do
  local chunk, err = loadfile(cfg.scenario)
  if not chunk then
    rig.load_error = 'cannot load scenario: '..tostring(err)
  else
    local ok, res = pcall(chunk)
    if not ok then rig.load_error = 'scenario raised: '..tostring(res)
    elseif type(res) ~= 'table' or #res == 0 then rig.load_error = 'scenario must return a non-empty array of steps'
    else
      for i, s in ipairs(res) do
        if type(s) ~= 'table' or type(s.run) ~= 'function' then
          rig.load_error = 'step #'..i..' needs a run function'; break
        end
      end
      steps = res
    end
  end
end

local function menu_ready()
  return G and G.STAGES and G.STAGE == G.STAGES.MAIN_MENU and G.STATE == G.STATES.MENU
    and G.MAIN_MENU_UI and G.MAIN_MENU_UI.states and G.MAIN_MENU_UI.states.visible
end

local function tick()
  rig.frames = rig.frames + 1
  if rig.phase == 'boot' then
    if rig.load_error then return finish(false, rig.load_error) end
    if menu_ready() then
      rig.menu_at = rig.menu_at or now()
      if now() - rig.menu_at >= MENU_SETTLE then
        say(string.format('main menu up after %.1fs', now() - rig.t0))
        -- A game controller in use on this machine would drive the rig game too (SDL reads
        -- /dev/input itself); smoke.sh and lovely-rig.sh hide them with an SDL hint.
        if love.joystick and love.joystick.getJoystickCount() > 0 then
          return finish(false, 'a host game controller reaches the rig (is the SDL hint in smoke.sh / lovely-rig.sh?)')
        end
        rig.phase, rig.step, rig.step_started = 'steps', 1, now()
      end
    elseif now() - rig.t0 > BOOT_TIMEOUT then
      return finish(false, 'main menu not reached within '..BOOT_TIMEOUT..'s')
    end
  elseif rig.phase == 'steps' then
    local s = steps[rig.step]
    local label = 'step '..rig.step..' ('..tostring(s.name or '?')..')'
    local ok, res = xpcall(s.run, debug.traceback, ctx)
    if not ok then
      io.stderr:write('[smoke] ', label, ' error: ', tostring(res), '\n')
      return finish(false, label..': '..tostring(res):match('^[^\n]*'))
    end
    if res then
      say(label..' ok')
      rig.step, rig.step_started = rig.step + 1, now()
      if rig.step > #steps then rig.phase, rig.flush_at = 'flush', now() end
    elseif now() - rig.step_started > (s.timeout or 10) then
      return finish(false, label..': timed out after '..(s.timeout or 10)..'s')
    end
  elseif rig.phase == 'flush' then
    -- Screenshots are captured at the end of a frame; wait for their callbacks.
    if rig.pending_shots == 0 and now() - rig.flush_at > 0.1 then return finish(true) end
    if now() - rig.flush_at > 5 then return finish(false, 'screenshots never completed') end
  end
end

local update = love.update
function love.update(dt)
  update(dt)
  if rig.phase ~= 'done' then tick() end
end

return rig
