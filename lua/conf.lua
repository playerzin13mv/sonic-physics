function love.conf(t)
  t.identity = "sonic_physics_lua"
  t.window.title = "Sonic Physics - Lua / LOVE2D"
  t.window.width = 848
  t.window.height = 480
  t.window.resizable = true
  t.window.vsync = 1
  t.modules.physics = false
  t.modules.audio = false
  t.modules.sound = false
  t.modules.video = false
end
