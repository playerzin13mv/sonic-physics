-- Sonic Mania-style physics test  |  Lua + LOVE2D (mobile)
-- Fixed 60 Hz timestep, virtual screen 424x240, all units in pixels / frame.
local lg = love.graphics
local floor, abs, sin, cos, pi = math.floor, math.abs, math.sin, math.cos, math.pi
local min, max, ceil = math.min, math.max, math.ceil
local atan2 = math.atan2 or math.atan

local VW, VH = 424, 240
local function sign(v) return v > 0 and 1 or (v < 0 and -1 or 0) end
local function trunc(v) return v >= 0 and floor(v) or -floor(-v) end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

---------------------------------------------------------------- constants
local ACC, DEC, FRC, TOP = 0.046875, 0.5, 0.046875, 6
local SLP, SLP_ROLL_UP, SLP_ROLL_DOWN = 0.125, 0.078125, 0.3125
local ROLL_FRC, ROLL_DEC = 0.0234375, 0.125
local AIR_ACC, GRV, JMP = 0.09375, 0.21875, 6.5
local WALLR = 10
local LANG_NAME = "LUA / LOVE2D"

---------------------------------------------------------------- level
local LW, WH, PIT, DEATH_Y = 6900, 800, 5000, 900
local H = {}
local loops, rings, spikes, springs, checks = {}, {}, {}, {}, {}
local goalX = 6780

local function hAt(x)
  local i = floor(x)
  if i < 0 then i = 0 elseif i > LW - 1 then i = LW - 1 end
  return H[i + 1]
end

local function angleAt(x)
  local h1, h2 = hAt(x - 6), hAt(x + 6)
  if h1 >= PIT or h2 >= PIT then return 0 end
  if abs(h2 - h1) > 14 then return 0 end
  return atan2(h2 - h1, 12)
end

local function buildLevel()
  loops, rings, spikes, springs, checks = {}, {}, {}, {}, {}
  local x, cur = 0, 400
  local function flat(len) for i = 0, len - 1 do H[x + i + 1] = cur end x = x + len end
  local function ramp(len, dy)
    local y0 = cur
    for i = 0, len - 1 do H[x + i + 1] = y0 + dy * (1 - cos(pi * i / len)) / 2 end
    cur = y0 + dy; x = x + len
  end
  local function pit(len) for i = 0, len - 1 do H[x + i + 1] = PIT end x = x + len end
  local function loop(len) loops[#loops + 1] = { cx = x + len / 2, gy = cur, R = 88, T = 24 }; flat(len) end
  flat(500); ramp(360, -80); flat(160); ramp(520, 160); flat(300); loop(640); flat(240)
  ramp(300, -190); flat(120); ramp(300, 190); flat(320); pit(150); flat(500)
  ramp(420, -200); flat(80); ramp(560, 260); flat(160); loop(700); flat(570)

  local function block(x0, w, h)
    local top = H[x0 + 1] - h
    for i = x0, x0 + w - 1 do H[i + 1] = top end
  end
  block(4150, 64, 24); block(4270, 64, 48)

  local function addRings(x0, n, gap, lift)
    for i = 0, n - 1 do
      local rx = x0 + i * gap
      rings[#rings + 1] = { x = rx, y = hAt(rx) - lift, got = false }
    end
  end
  addRings(300, 6, 24, 26); addRings(900, 6, 24, 34); addRings(1300, 8, 24, 26)
  addRings(2700, 5, 24, 26); addRings(3770, 4, 30, 90); addRings(4600, 6, 24, 40)
  addRings(5200, 6, 24, 30); addRings(6400, 8, 24, 26)
  for _, L in ipairs(loops) do
    for k = 0, 11 do
      local t = k * pi / 6
      rings[#rings + 1] = { x = L.cx + (L.R - 22) * sin(t), y = L.gy - L.R + (L.R - 22) * cos(t), got = false }
    end
  end

  for _, sx in ipairs({ 3560, 3592, 3624 }) do spikes[#spikes + 1] = { x = sx, y = hAt(sx + 16) } end
  springs[1] = { x = 2600, y = hAt(2616), power = 10, t = 0, red = false }
  springs[2] = { x = 3940, y = hAt(3956), power = 16, t = 0, red = true }
  for _, cx in ipairs({ 1700, 4040, 5500 }) do checks[#checks + 1] = { x = cx, y = hAt(cx), on = false } end
end

---------------------------------------------------------------- assets
local atlas, sdash, dpadImg, btnImg, pauseImg
local quads = {}
local function Q(r, i)
  local k = r * 100 + i
  if not quads[k] then quads[k] = lg.newQuad(i * 48, r * 48, 48, 48, atlas:getDimensions()) end
  return quads[k]
end

local function range(r, a, b) local t = {} for i = a, b do t[#t + 1] = { r, i } end return t end
local ANIM = {
  idle = range(0, 0, 10), bored = range(7, 0, 5),
  walk = range(1, 0, 11), jog = range(1, 12, 23),
  run = range(2, 0, 9), max = range(2, 10, 17),
  roll = { { 3, 0 }, { 3, 2 }, { 3, 1 }, { 3, 3 } }, drop = { { 3, 4 }, { 3, 5 } },
  hurt = range(5, 10, 14), die = { { 5, 15 } },
  lookup = range(8, 0, 5), crouch = range(8, 6, 10), balance = range(6, 0, 5),
  spring = { { 4, 0 }, { 4, 1 } },
}
local HOLD_LAST = { hurt = true, lookup = true, crouch = true, spring = false }

---------------------------------------------------------------- state
local P, cam = {}, { x = 0, y = 0, look = 0 }
local spawn = { x = 96, y = 0 }
local mode = "menu"
local tick = 0
local touches = {}
local prevJump = false

local function hgt() return (P.rolling or P.jumping or P.spin) and 14 or 19 end

local function resetSonic(x, y)
  for k in pairs(P) do P[k] = nil end
  P.x, P.y, P.xsp, P.ysp, P.gsp = x, y, 0, 0, 0
  P.ang, P.drawA, P.facing = 0, 0, 1
  P.grounded = true
  P.rolling, P.jumping, P.spin, P.spinCharge = false, false, false, 0
  P.crouch, P.lookUp, P.balance = false, false, false
  P.dropActive, P.dropT, P.dropReady = false, 0, false
  P.loop, P.theta, P.loopDir, P.loopCool = nil, 0, 1, 0
  P.lock, P.inv, P.hurt, P.dead, P.deadT = 0, 0, false, false, 0
  P.springT, P.af, P.animKey, P.idleT = 0, 0, "idle", 0
  P.rings = P.rings or 0
  P.goalT = 0
end

local function newGame()
  buildLevel()
  spawn.x = 96; spawn.y = hAt(96) - 19
  resetSonic(spawn.x, spawn.y)
  P.rings = 0
  cam.x = clamp(P.x - VW / 2, 0, LW - VW); cam.y = clamp(P.y - VH / 2 - 20, 0, WH - VH)
end

---------------------------------------------------------------- helpers
local function wallClip(x0, x1, feet)
  if x1 == x0 then return x1, false end
  local dir = x1 > x0 and 1 or -1
  local xs = x0
  while xs ~= x1 do
    local nxt = xs + dir
    if (dir > 0 and nxt > x1) or (dir < 0 and nxt < x1) then nxt = x1 end
    local p = floor(nxt + dir * WALLR)
    local c, t = hAt(p), hAt(p + dir)
    if t < feet - 6 and (c - t > 6) then return xs, true end
    xs = nxt
  end
  return x1, false
end

local function setAir(xsp, ysp)
  P.grounded = false; P.xsp = xsp; P.ysp = ysp; P.loop = nil
end

local function unball()
  if P.rolling or P.jumping or P.spin then P.y = P.y - 5 end
  P.rolling, P.jumping, P.spin = false, false, false
  P.dropActive, P.dropReady, P.dropT = false, false, 0
end

local function die()
  if P.dead then return end
  P.dead = true; P.deadT = 0; P.grounded = false; P.loop = nil
  P.xsp = 0; P.ysp = -7
  P.rolling, P.jumping, P.spin = false, false, false
end

local function hurtPlayer(srcx)
  if P.inv > 0 or P.hurt or P.dead then return end
  if P.rings <= 0 then die(); return end
  P.rings = 0
  local dir = (P.x >= srcx) and 1 or -1
  unball()
  P.hurt = true; P.inv = 120; P.lock = 0
  setAir(2 * dir, -4)
end

local function land(inp)
  local gy = hAt(P.x)
  local a = angleAt(P.x)
  local sa = sin(a)
  if abs(a) < 0.4 then P.gsp = P.xsp
  elseif abs(a) < 0.78 then
    if abs(P.xsp) > P.ysp then P.gsp = P.xsp else P.gsp = P.ysp * 0.5 * sign(sa) end
  else
    if abs(P.xsp) > P.ysp then P.gsp = P.xsp else P.gsp = P.ysp * sign(sa) end
  end
  P.grounded = true; P.ang = a; P.springT = 0
  local wasHurt = P.hurt
  if wasHurt then P.gsp = 0 end
  P.hurt = false
  P.jumping = false; P.rolling = false
  if P.dropReady and inp.jumpHeld and not wasHurt then
    local f = P.facing
    local g
    if sign(P.xsp) == f or P.xsp == 0 then g = P.gsp / 4 + 8 * f
    elseif abs(a) < 0.1 then g = 8 * f
    else g = P.gsp / 2 + 8 * f end
    P.gsp = clamp(g, -12, 12); P.rolling = true
  end
  P.dropActive, P.dropReady, P.dropT = false, false, 0
  P.y = gy - hgt()
end

---------------------------------------------------------------- ground
local function groundStep(inp)
  local a = P.ang
  local sa, ca = sin(a), cos(a)

  -- spin dash charging
  if P.spin then
    P.gsp = 0
    if inp.jumpPressed then P.spinCharge = min(P.spinCharge + 2, 8) end
    P.spinCharge = P.spinCharge - trunc(P.spinCharge / 0.125) / 256
    if not inp.down then
      P.gsp = P.facing * (8 + floor(P.spinCharge) / 2)
      P.spin = false; P.rolling = true
    end
    P.y = hAt(P.x) - hgt()
    return
  end

  if P.lock > 0 then P.lock = P.lock - 1 end

  -- crouch / look up
  P.crouch = inp.down and abs(P.gsp) < 0.5 and abs(a) < 0.4 and not P.rolling and P.lock == 0
  P.lookUp = inp.up and P.gsp == 0 and not P.crouch and not P.rolling
  if P.crouch then
    P.gsp = 0
    if inp.jumpPressed then
      P.spin = true; P.spinCharge = 2; P.crouch = false
      P.y = hAt(P.x) - hgt()
      return
    end
  end

  -- jump
  if inp.jumpPressed and not P.crouch then
    local xs = P.gsp * ca + JMP * sa
    local ys = P.gsp * sa - JMP * ca
    if not (P.rolling or P.jumping) then P.y = P.y + 5 end
    P.rolling = false; P.jumping = true
    setAir(xs, ys)
    return
  end

  -- slope factor
  if P.rolling then
    local f = (sign(P.gsp) == sign(sa)) and SLP_ROLL_DOWN or SLP_ROLL_UP
    P.gsp = P.gsp + f * sa
  else
    P.gsp = P.gsp + SLP * sa
  end

  -- input
  if P.rolling then
    if inp.left and P.gsp > 0 then P.gsp = P.gsp - ROLL_DEC
    elseif inp.right and P.gsp < 0 then P.gsp = P.gsp + ROLL_DEC end
    P.gsp = P.gsp - min(abs(P.gsp), ROLL_FRC) * sign(P.gsp)
    if abs(P.gsp) < 0.5 then P.rolling = false end
  elseif P.lock == 0 and not P.crouch then
    if inp.left and not inp.right then
      if P.gsp > 0 then P.gsp = P.gsp - DEC; if P.gsp <= 0 then P.gsp = -DEC end
      elseif P.gsp > -TOP then P.gsp = P.gsp - ACC; if P.gsp <= -TOP then P.gsp = -TOP end end
      P.facing = -1
    elseif inp.right and not inp.left then
      if P.gsp < 0 then P.gsp = P.gsp + DEC; if P.gsp >= 0 then P.gsp = DEC end
      elseif P.gsp < TOP then P.gsp = P.gsp + ACC; if P.gsp >= TOP then P.gsp = TOP end end
      P.facing = 1
    else
      P.gsp = P.gsp - min(abs(P.gsp), FRC) * sign(P.gsp)
    end
    if inp.down and abs(P.gsp) >= 1 then P.rolling = true end
  end
  P.gsp = clamp(P.gsp, -16, 16)

  -- slip on steep slopes
  if not P.rolling and abs(P.gsp) < 2.5 and abs(a) > 0.61 and P.lock == 0 then P.lock = 30 end

  -- move
  local ox = P.x
  local xsp = P.gsp * ca
  local feet = P.y + hgt()
  local nx, hit = wallClip(P.x, P.x + xsp, feet)
  if hit then P.gsp = 0 end
  P.x = nx
  local gy = hAt(P.x)
  local d = gy - feet
  local tol = min(abs(xsp) + 4, 14)
  if d > tol then
    setAir(P.gsp * ca, P.gsp * sa)
    return
  end
  P.y = gy - hgt()
  P.ang = angleAt(P.x)

  -- loop entry
  if P.loopCool > 0 then P.loopCool = P.loopCool - 1
  elseif abs(P.gsp) >= 4.2 and abs(P.ang) < 0.2 then
    for _, L in ipairs(loops) do
      if (ox < L.cx and P.x >= L.cx and P.gsp > 0) or (ox > L.cx and P.x <= L.cx and P.gsp < 0) then
        if abs(hAt(L.cx) - L.gy) < 1 then
          P.loop = L; P.theta = 0; P.loopDir = sign(P.gsp)
        end
      end
    end
  end
end

---------------------------------------------------------------- loop
local function loopStep(inp)
  local L = P.loop
  local sa = sin(-P.theta)
  if P.rolling then
    local f = (sign(P.gsp) == sign(sa)) and SLP_ROLL_DOWN or SLP_ROLL_UP
    P.gsp = P.gsp + f * sa
  else
    P.gsp = P.gsp + SLP * sa
  end
  P.gsp = clamp(P.gsp, -16, 16)
  local rho = L.R - hgt()
  P.theta = P.theta + P.gsp / rho
  local th = P.theta
  P.ang = -th
  P.x = L.cx + rho * sin(th)
  P.y = (L.gy - L.R) + rho * cos(th)

  if inp.jumpPressed then
    local a = -th
    local xs = P.gsp * cos(a) + JMP * sin(a)
    local ys = P.gsp * sin(a) - JMP * cos(a)
    if not (P.rolling or P.jumping) then P.y = P.y + 5 end
    P.rolling = false; P.jumping = true
    setAir(xs, ys); return
  end
  local exit = false
  if abs(th) >= 2 * pi then exit = true; P.loopCool = 30
  elseif th * P.loopDir < 0 then exit = true; P.loopCool = 30 end
  if exit then
    P.loop = nil; P.x = L.cx; P.ang = 0; P.y = L.gy - hgt(); return
  end
  local m = abs(th)
  if abs(P.gsp) < 2.5 and m > pi / 3 and m < 5 * pi / 3 then
    local a = -th
    setAir(P.gsp * cos(a), P.gsp * sin(a)); P.lock = 30
  end
end

---------------------------------------------------------------- air
local function airStep(inp)
  if P.jumping and not P.hurt and not inp.jumpHeld and P.ysp < -4 then P.ysp = -4 end
  if not P.hurt then
    if inp.left and not inp.right then
      if P.xsp > -TOP then P.xsp = P.xsp - AIR_ACC; if P.xsp <= -TOP then P.xsp = -TOP end end
      P.facing = -1
    elseif inp.right and not inp.left then
      if P.xsp < TOP then P.xsp = P.xsp + AIR_ACC; if P.xsp >= TOP then P.xsp = TOP end end
      P.facing = 1
    end
  end
  if P.ysp < 0 and P.ysp > -4 then P.xsp = P.xsp - trunc(P.xsp / 0.125) / 256 end

  -- Drop Dash (Sonic Mania): press jump again in the air and keep holding
  if P.jumping and not P.hurt then
    if inp.jumpPressed and not P.dropActive then P.dropActive = true; P.dropT = 0 end
    if P.dropActive then
      if inp.jumpHeld then
        P.dropT = P.dropT + 1
        if P.dropT >= 20 then P.dropReady = true end
      else P.dropActive, P.dropT, P.dropReady = false, 0, false end
    end
  end

  local nx, hit = wallClip(P.x, P.x + P.xsp, P.y + hgt())
  if hit then P.xsp = 0 end
  P.x = nx
  P.y = P.y + P.ysp
  P.ysp = min(P.ysp + (P.hurt and 0.1875 or GRV), 16)
  if P.springT > 0 and P.ysp > 0 then P.springT = 0 end

  local gy = hAt(P.x)
  if gy < PIT and P.y + hgt() >= gy then land(inp) end
end

---------------------------------------------------------------- entities
local function overlaps()
  local px, py, h = P.x, P.y, hgt()
  for _, r in ipairs(rings) do
    if not r.got and abs(px - r.x) < 14 and abs(py - r.y) < h + 6 then r.got = true; P.rings = P.rings + 1 end
  end
  for _, s in ipairs(spikes) do
    if abs(px - (s.x + 16)) < 22 and py + h > s.y - 12 and py - h < s.y then hurtPlayer(s.x + 16) end
  end
  for _, sp in ipairs(springs) do
    if sp.t > 0 then sp.t = sp.t - 1 end
    local feet = py + h
    if abs(px - (sp.x + 16)) < 18 and feet > sp.y - 14 and feet < sp.y + 8 and (P.grounded or P.ysp >= 0) and not P.hurt then
      if P.grounded then P.xsp = P.gsp * cos(P.ang) end
      unball()
      P.y = sp.y - 14 - 19
      setAir(P.xsp, -sp.power); P.springT = 1; sp.t = 12
    end
  end
  for _, c in ipairs(checks) do
    if not c.on and abs(px - c.x) < 22 and abs(py - c.y) < 70 then
      c.on = true; spawn.x = c.x; spawn.y = hAt(c.x) - 19
    end
  end
  if P.goalT == 0 and px > goalX then P.goalT = 240 end
end

---------------------------------------------------------------- update
local function readInput()
  local kb = love.keyboard.isDown
  local i = { left = kb("left", "a"), right = kb("right", "d"), up = kb("up", "w"), down = kb("down", "s"),
    jumpHeld = kb("z", "x", "space", "k") }
  for _, t in pairs(touches) do
    if t.x < VW * 0.5 then
      local dx, dy = t.x - 52, t.y - 188
      if dx * dx + dy * dy < 100 * 100 then
        if dx > 12 then i.right = true elseif dx < -12 then i.left = true end
        if dy > 14 then i.down = true elseif dy < -14 then i.up = true end
      end
    elseif t.y > 40 then i.jumpHeld = true end
  end
  i.jumpPressed = i.jumpHeld and not prevJump
  prevJump = i.jumpHeld
  return i
end

local function animState()
  if P.dead then return "die" end
  if P.hurt then return "hurt" end
  if P.spin then return "spin" end
  if P.dropReady then return "drop" end
  if P.rolling or P.jumping then return "roll" end
  if P.springT > 0 then return "spring" end
  if P.grounded or P.loop then
    if P.crouch then return "crouch" end
    if P.lookUp then return "lookup" end
    local s = abs(P.gsp)
    if s < 0.1 then
      if P.balance then return "balance" end
      if P.idleT > 300 then return "bored" end
      return "idle"
    end
    if s < 3.5 then return "walk" elseif s < 6 then return "jog" elseif s < 9.8 then return "run" end
    return "max"
  end
  local s = abs(P.xsp)
  if s < 3.5 then return "walk" elseif s < 6 then return "jog" end
  return "run"
end

local ANIM_SPEED = { idle = 0.08, bored = 0.1, hurt = 0.2, crouch = 0.3, lookup = 0.25, balance = 0.12,
  spring = 0.2, drop = 0.3, spin = 0.5, die = 0.1 }

local function stepSonic(inp)
  if P.goalT > 0 then
    inp = { left = false, right = false, up = false, down = false, jumpHeld = false, jumpPressed = false }
  end
  if P.dead then
    P.y = P.y + P.ysp; P.ysp = P.ysp + GRV; P.deadT = P.deadT + 1
    if P.deadT > 100 then local r = P.rings; resetSonic(spawn.x, spawn.y); P.rings = 0 end
    return
  end
  if P.inv > 0 then P.inv = P.inv - 1 end
  if P.loop then loopStep(inp)
  elseif P.grounded then groundStep(inp)
  else airStep(inp) end

  -- ledge balance / idle timer
  P.balance = false
  if P.grounded and not P.loop and P.gsp == 0 and not P.crouch and not P.spin then
    if hAt(P.x - 12) - hAt(P.x) > 24 or hAt(P.x + 12) - hAt(P.x) > 24 then P.balance = true end
  end
  if P.grounded and P.gsp == 0 and not inp.left and not inp.right and not inp.up and not inp.down then
    P.idleT = P.idleT + 1
  else P.idleT = 0 end

  if not P.dead then overlaps() end
  if P.y > DEATH_Y then die() end
  if P.goalT > 0 then
    P.goalT = P.goalT - 1
    if P.goalT == 0 then newGame() end
  end

  -- sprite rotation follows the ground
  local target = (P.grounded or P.loop) and P.ang or 0
  if P.loop then P.drawA = target else P.drawA = P.drawA + clamp(target - P.drawA, -0.3, 0.3) end

  -- animation
  local key = animState()
  if key ~= P.animKey then P.animKey = key; P.af = 0 end
  local s = abs(P.grounded and P.gsp or P.xsp)
  local spd = ANIM_SPEED[key]
  if not spd then
    if key == "roll" then spd = 0.2 + abs(P.gsp) * 0.03 else spd = 0.12 + s * 0.035 end
  end
  P.af = P.af + spd

  -- camera
  local dx = P.x - cam.x - VW / 2
  if dx > 16 then cam.x = cam.x + min(dx - 16, 16) elseif dx < -16 then cam.x = cam.x + max(dx + 16, -16) end
  if P.lookUp and P.idleT > 60 then cam.look = max(cam.look - 2, -64)
  elseif P.crouch and P.idleT > 60 then cam.look = min(cam.look + 2, 64)
  else cam.look = cam.look - sign(cam.look) * min(abs(cam.look), 4) end
  local ty = P.y - VH / 2 - 10 + cam.look
  local dy = ty - cam.y
  if P.grounded or P.loop then
    local sp = abs(P.gsp) < 8 and 6 or 16
    cam.y = cam.y + clamp(dy, -sp, sp)
  else
    if dy > 32 then cam.y = cam.y + min(dy - 32, 16) elseif dy < -32 then cam.y = cam.y + max(dy + 32, -16) end
  end
  cam.x = clamp(cam.x, 0, LW - VW); cam.y = clamp(cam.y, 0, WH - VH)
end

---------------------------------------------------------------- drawing
local CA, CB = { 219, 109, 0 }, { 146, 73, 0 }
local G1, G2 = { 80, 210, 40 }, { 0, 130, 30 }
local function setc(c, a) lg.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end

local function drawBackground()
  local bands = { { 40, 120, 230 }, { 60, 140, 240 }, { 90, 165, 250 }, { 130, 195, 255 }, { 170, 220, 255 } }
  for i, c in ipairs(bands) do setc(c); lg.rectangle("fill", 0, (i - 1) * 48, VW, 48) end
  setc({ 40, 150, 90 })
  for sx = 0, VW, 4 do
    local hy = 170 + 22 * sin((cam.x * 0.25 + sx) / 50) - cam.y * 0.15
    lg.rectangle("fill", sx, hy, 4, VH - hy)
  end
  setc({ 20, 120, 60 })
  for sx = 0, VW, 4 do
    local hy = 195 + 14 * sin((cam.x * 0.45 + sx) / 34 + 2) - cam.y * 0.3
    lg.rectangle("fill", sx, hy, 4, VH - hy)
  end
end

local function drawTerrain()
  local cx, cy = floor(cam.x), floor(cam.y)
  local x0 = floor(cx / 4) * 4
  for wx = x0, x0 + VW + 4, 4 do
    if wx >= 0 and wx < LW then
      local top = hAt(wx + 2)
      if top < PIT then
        local gx = wx - cx
        local ytop = floor(top)
        local colx = floor(wx / 16)
        local row = floor(ytop / 16)
        local y, bottom = ytop, cy + VH
        while y < bottom do
          local ny = (row + 1) * 16
          setc(((colx + row) % 2 == 0) and CA or CB)
          lg.rectangle("fill", gx, y - cy, 4, ny - y)
          y = ny; row = row + 1
        end
        setc(G1); lg.rectangle("fill", gx, ytop - cy, 4, 4)
        setc(G2); lg.rectangle("fill", gx, ytop + 4 - cy, 4, 3)
      end
    end
  end
end

local function drawLoops()
  for _, L in ipairs(loops) do
    local cx, cy = L.cx - cam.x, L.gy - L.R - cam.y
    if cx > -L.R - 40 and cx < VW + L.R + 40 then
      for k = 0, 59 do
        local a0, a1 = k * pi / 30, (k + 1) * pi / 30
        local r0, r1 = L.R, L.R + L.T
        setc(k % 2 == 0 and CA or CB)
        lg.polygon("fill", cx + r0 * sin(a0), cy + r0 * cos(a0), cx + r1 * sin(a0), cy + r1 * cos(a0),
          cx + r1 * sin(a1), cy + r1 * cos(a1), cx + r0 * sin(a1), cy + r0 * cos(a1))
      end
      setc({ 109, 36, 0 }); lg.setLineWidth(1); lg.circle("line", cx, cy, L.R)
    end
  end
end

local function drawObjects()
  local t = tick
  for _, r in ipairs(rings) do
    if not r.got then
      local sx, sy = r.x - cam.x, r.y - cam.y
      if sx > -10 and sx < VW + 10 then
        local w = max(1.5, abs(cos(t / 10 + r.x * 0.05)) * 6)
        setc({ 255, 215, 0 }); lg.setLineWidth(2); lg.ellipse("line", sx, sy, w, 7)
      end
    end
  end
  for _, s in ipairs(spikes) do
    local sx, sy = s.x - cam.x, s.y - cam.y
    for k = 0, 3 do
      setc({ 200, 200, 210 }); lg.polygon("fill", sx + k * 8, sy, sx + k * 8 + 4, sy - 16, sx + k * 8 + 8, sy)
    end
    setc({ 90, 90, 100 }); lg.rectangle("fill", sx, sy - 2, 32, 2)
  end
  for _, sp in ipairs(springs) do
    local sx, sy = sp.x - cam.x, sp.y - cam.y
    local comp = sp.t > 0 and 8 or 0
    setc({ 150, 150, 160 }); lg.rectangle("fill", sx + 4, sy - 6, 24, 6)
    setc(sp.red and { 230, 40, 40 } or { 255, 210, 0 }); lg.rectangle("fill", sx + 2, sy - 16 + comp, 28, 6)
    setc({ 200, 200, 210 }); lg.rectangle("fill", sx + 12, sy - 10 + comp / 2, 8, 4)
  end
  for _, c in ipairs(checks) do
    local sx, sy = c.x - cam.x, c.y - cam.y
    setc({ 170, 170, 180 }); lg.rectangle("fill", sx - 2, sy - 40, 4, 40)
    setc(c.on and { 255, 40, 40 } or { 40, 110, 255 }); lg.circle("fill", sx, sy - 44, 6)
  end
  local gx, gy = goalX - cam.x, hAt(goalX) - cam.y
  setc({ 170, 170, 180 }); lg.rectangle("fill", gx - 2, gy - 56, 4, 56)
  setc({ 230, 60, 60 }); lg.rectangle("fill", gx - 16, gy - 70, 32, 18)
  setc({ 255, 255, 255 }); lg.print("GOAL", gx - 12, gy - 68)
end

local function drawSonic()
  if P.inv > 0 and floor(P.inv / 3) % 2 == 0 then return end
  local key = P.animKey
  local px, py = floor(P.x) - floor(cam.x), floor(P.y) - floor(cam.y)
  lg.setColor(1, 1, 1, 1)
  if key == "spin" then
    local f = floor(P.af) % 6
    lg.draw(sdash, lg.newQuad(f * 32, 0, 32, 32, sdash:getDimensions()), px, py, 0, P.facing, 1, 16, 16)
    return
  end
  local list = ANIM[key]
  local n = #list
  local idx = HOLD_LAST[key] and min(floor(P.af), n - 1) or (floor(P.af) % n)
  local fr = list[idx + 1]
  local q = Q(fr[1], fr[2])
  if key == "roll" or key == "drop" then
    lg.draw(atlas, q, px, py, 0, P.facing, 1, 24, 28)
  elseif key == "hurt" or key == "die" then
    lg.draw(atlas, q, px, py + 19, 0, P.facing, 1, 24, 48)
  else
    local fx, fy = px, py + 19
    local rot = P.drawA
    if P.loop then
      local th = P.theta
      fx = px + 19 * sin(th); fy = py + 19 * cos(th)
    end
    lg.draw(atlas, q, fx, fy, rot, P.facing, 1, 24, 48)
  end
end

local function drawHUD()
  lg.setColor(0, 0, 0, 0.6); lg.print("RINGS " .. P.rings, 9, 9); lg.print(string.format("SPEED %.2f", abs(P.grounded and P.gsp or P.xsp)), 9, 23)
  lg.setColor(1, 0.9, 0.2, 1); lg.print("RINGS " .. P.rings, 8, 8)
  lg.setColor(1, 1, 1, 1); lg.print(string.format("SPEED %.2f", abs(P.grounded and P.gsp or P.xsp)), 8, 22)
  lg.setColor(1, 1, 1, 0.7); lg.print(LANG_NAME, VW - 92, 8)
  if P.goalT > 0 then lg.setColor(1, 1, 1, 1); lg.print("GOAL!", VW / 2 - 14, 80) end
  if P.dropReady then lg.setColor(1, 1, 0.3, 1); lg.print("DROP DASH READY", VW / 2 - 44, 40) end
  lg.setColor(1, 1, 1, 1)
  local dirIdx = 0
  local dx, dy = 0, 0
  for _, t in pairs(touches) do
    if t.x < VW * 0.5 then dx, dy = t.x - 52, t.y - 188 end
  end
  if dx * dx + dy * dy < 100 * 100 and (abs(dx) > 12 or abs(dy) > 14) then
    if abs(dx) >= abs(dy) then dirIdx = dx < 0 and 1 or 3 else dirIdx = dy > 0 and 2 or 4 end
  end
  lg.setColor(1, 1, 1, 0.85)
  lg.draw(dpadImg[dirIdx], 20, 156)
  local jumping = false
  for _, t in pairs(touches) do if t.x >= VW * 0.5 and t.y > 40 then jumping = true end end
  lg.draw(btnImg[(jumping or love.keyboard.isDown("z", "x", "space", "k")) and 1 or 0], 340, 164)
  lg.draw(pauseImg, VW - 22, 26)
  lg.setColor(1, 1, 1, 1)
end

local function drawMenu()
  drawBackground()
  local t = tick
  setc({ 219, 109, 0 }); lg.rectangle("fill", 0, 190, VW, 50)
  setc(G1); lg.rectangle("fill", 0, 190, VW, 4)
  lg.setColor(0, 0, 0, 0.5); lg.print("SONIC MANIA", 121, 31, 0, 3, 3); lg.print("PHYSICS TEST", 133, 61, 0, 2.4, 2.4)
  lg.setColor(1, 1, 1, 1); lg.print("SONIC MANIA", 120, 30, 0, 3, 3)
  lg.setColor(0.3, 0.8, 1, 1); lg.print("PHYSICS TEST", 132, 60, 0, 2.4, 2.4)
  lg.setColor(1, 1, 1, 1)
  local fr = ANIM.max[floor(t / 3) % #ANIM.max + 1]
  lg.draw(atlas, Q(fr[1], fr[2]), VW / 2, 190, 0, 1.6, 1.6, 24, 48)
  lg.print(LANG_NAME, VW / 2 - 40, 104, 0, 1.3, 1.3)
  if floor(t / 30) % 2 == 0 then lg.print("TAP TO START", VW / 2 - 52, 125, 0, 1.5, 1.5) end
  lg.print("D-PAD: MOVE   A: JUMP   DOWN+A: SPIN DASH   JUMP + HOLD A: DROP DASH", 18, 220)
end

---------------------------------------------------------------- love callbacks
local canvas, scale, ox, oy
function love.load()
  lg.setDefaultFilter("nearest", "nearest")
  canvas = lg.newCanvas(VW, VH)
  atlas = lg.newImage("assets/sonic.png")
  sdash = lg.newImage("assets/spindash.png")
  dpadImg = {}
  for i = 0, 4 do dpadImg[i] = lg.newImage("assets/dpad_" .. i .. ".png") end
  btnImg = { [0] = lg.newImage("assets/btn_0.png"), [1] = lg.newImage("assets/btn_1.png") }
  pauseImg = lg.newImage("assets/pause.png")
  newGame()
end

local acc = 0
function love.update(dt)
  acc = acc + min(dt, 0.1)
  while acc >= 1 / 60 do
    acc = acc - 1 / 60
    tick = tick + 1
    if mode == "play" then stepSonic(readInput()) end
  end
end

function love.draw()
  local w, h = lg.getDimensions()
  scale = min(w / VW, h / VH)
  ox, oy = (w - VW * scale) / 2, (h - VH * scale) / 2
  lg.setCanvas(canvas)
  lg.clear(0, 0, 0, 1)
  if mode == "menu" then drawMenu()
  else
    drawBackground(); drawTerrain(); drawLoops(); drawObjects(); drawSonic(); drawHUD()
  end
  lg.setCanvas()
  lg.setColor(1, 1, 1, 1)
  lg.clear(0, 0, 0, 1)
  lg.draw(canvas, ox, oy, 0, scale, scale)
end

local function toV(x, y) return (x - ox) / scale, (y - oy) / scale end

local function press(id, x, y)
  local vx, vy = toV(x, y)
  if mode == "menu" then
    mode = "play"; touches = {}; newGame(); prevJump = true
    return
  end
  if vx > VW - 40 and vy < 44 then mode = "menu"; touches = {}; return end
  touches[id] = { x = vx, y = vy }
end

function love.touchpressed(id, x, y) press(id, x, y) end
function love.touchmoved(id, x, y) if touches[id] then touches[id].x, touches[id].y = toV(x, y) end end
function love.touchreleased(id) touches[id] = nil end
function love.mousepressed(x, y, b, istouch) if not istouch then press("m", x, y) end end
function love.mousemoved(x, y, dx, dy, istouch) if not istouch and touches["m"] then touches["m"].x, touches["m"].y = toV(x, y) end end
function love.mousereleased(x, y, b, istouch) if not istouch then touches["m"] = nil end end
function love.keypressed(k)
  if mode == "menu" and (k == "return" or k == "space" or k == "z") then mode = "play"; newGame(); prevJump = true
  elseif k == "escape" then mode = "menu" end
end
