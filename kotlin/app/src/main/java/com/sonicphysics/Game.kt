package com.sonicphysics

import android.content.Context
import android.graphics.*
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.*

const val VW = 424
const val VH = 240
private const val LANG_NAME = "KOTLIN / ANDROID"

// ---- physics constants (px / frame @60Hz, Sonic Mania / Genesis values)
private const val ACC = 0.046875
private const val DEC = 0.5
private const val FRC = 0.046875
private const val TOP = 6.0
private const val SLP = 0.125
private const val SLP_ROLL_UP = 0.078125
private const val SLP_ROLL_DOWN = 0.3125
private const val ROLL_FRC = 0.0234375
private const val ROLL_DEC = 0.125
private const val AIR_ACC = 0.09375
private const val GRV = 0.21875
private const val JMP = 6.5
private const val WALLR = 10

private const val LW = 6900
private const val WH = 800
private const val PIT = 5000.0
private const val DEATH_Y = 900.0

private fun sign(v: Double) = if (v > 0) 1.0 else if (v < 0) -1.0 else 0.0
private fun clamp(v: Double, a: Double, b: Double) = if (v < a) a else if (v > b) b else v
private fun trunc(v: Double) = if (v >= 0) floor(v) else -floor(-v)

class Inp(
    var left: Boolean = false, var right: Boolean = false, var up: Boolean = false, var down: Boolean = false,
    var jumpHeld: Boolean = false, var jumpPressed: Boolean = false
)

class Loop(val cx: Double, val gy: Double, val R: Double = 88.0, val T: Double = 24.0)
class Ring(val x: Double, val y: Double, var got: Boolean = false)
class Spike(val x: Double, val y: Double)
class Spring(val x: Double, val y: Double, val power: Double, val red: Boolean, var t: Int = 0)
class Check(val x: Double, val y: Double, var on: Boolean = false)

class Game(private val ctx: Context) {
    // ------------------------------------------------------------ level
    private val H = DoubleArray(LW)
    private val loops = ArrayList<Loop>()
    private val rings = ArrayList<Ring>()
    private val spikes = ArrayList<Spike>()
    private val springs = ArrayList<Spring>()
    private val checks = ArrayList<Check>()
    private val goalX = 6780.0

    private fun hAt(x: Double): Double {
        var i = floor(x).toInt()
        if (i < 0) i = 0 else if (i > LW - 1) i = LW - 1
        return H[i]
    }

    private fun angleAt(x: Double): Double {
        val h1 = hAt(x - 6); val h2 = hAt(x + 6)
        if (h1 >= PIT || h2 >= PIT) return 0.0
        if (abs(h2 - h1) > 14) return 0.0
        return atan2(h2 - h1, 12.0)
    }

    private fun buildLevel() {
        loops.clear(); rings.clear(); spikes.clear(); springs.clear(); checks.clear()
        var x = 0
        var cur = 400.0
        fun flat(len: Int) { for (i in 0 until len) H[x + i] = cur; x += len }
        fun ramp(len: Int, dy: Double) {
            val y0 = cur
            for (i in 0 until len) H[x + i] = y0 + dy * (1 - cos(PI * i / len)) / 2
            cur = y0 + dy; x += len
        }
        fun pit(len: Int) { for (i in 0 until len) H[x + i] = PIT; x += len }
        fun loop(len: Int) { loops.add(Loop(x + len / 2.0, cur)); flat(len) }
        flat(500); ramp(360, -80.0); flat(160); ramp(520, 160.0); flat(300); loop(640); flat(240)
        ramp(300, -190.0); flat(120); ramp(300, 190.0); flat(320); pit(150); flat(500)
        ramp(420, -200.0); flat(80); ramp(560, 260.0); flat(160); loop(700); flat(570)

        fun block(x0: Int, w: Int, h: Int) {
            val top = H[x0] - h
            for (i in x0 until x0 + w) H[i] = top
        }
        block(4150, 64, 24); block(4270, 64, 48)

        fun addRings(x0: Int, n: Int, gap: Int, lift: Int) {
            for (i in 0 until n) {
                val rx = (x0 + i * gap).toDouble()
                rings.add(Ring(rx, hAt(rx) - lift))
            }
        }
        addRings(300, 6, 24, 26); addRings(900, 6, 24, 34); addRings(1300, 8, 24, 26)
        addRings(2700, 5, 24, 26); addRings(3770, 4, 30, 90); addRings(4600, 6, 24, 40)
        addRings(5200, 6, 24, 30); addRings(6400, 8, 24, 26)
        for (L in loops) for (k in 0 until 12) {
            val t = k * PI / 6
            rings.add(Ring(L.cx + (L.R - 22) * sin(t), L.gy - L.R + (L.R - 22) * cos(t)))
        }
        for (sx in intArrayOf(3560, 3592, 3624)) spikes.add(Spike(sx.toDouble(), hAt(sx + 16.0)))
        springs.add(Spring(2600.0, hAt(2616.0), 10.0, false))
        springs.add(Spring(3940.0, hAt(3956.0), 16.0, true))
        for (cx in intArrayOf(1700, 4040, 5500)) checks.add(Check(cx.toDouble(), hAt(cx.toDouble())))
    }

    // ------------------------------------------------------------ assets
    private fun load(name: String): Bitmap {
        val o = BitmapFactory.Options().apply { inScaled = false }
        return ctx.assets.open(name).use { BitmapFactory.decodeStream(it, null, o)!! }
    }
    private val atlas = load("sonic.png")
    private val sdash = load("spindash.png")
    private val dpadImg = Array(5) { load("dpad_$it.png") }
    private val btnImg = arrayOf(load("btn_0.png"), load("btn_1.png"))
    private val pauseImg = load("pause.png")

    private fun range(r: Int, a: Int, b: Int) = (a..b).map { intArrayOf(r, it) }
    private val ANIM: Map<String, List<IntArray>> = mapOf(
        "idle" to range(0, 0, 10), "bored" to range(7, 0, 5),
        "walk" to range(1, 0, 11), "jog" to range(1, 12, 23),
        "run" to range(2, 0, 9), "max" to range(2, 10, 17),
        "roll" to listOf(intArrayOf(3, 0), intArrayOf(3, 2), intArrayOf(3, 1), intArrayOf(3, 3)),
        "drop" to listOf(intArrayOf(3, 4), intArrayOf(3, 5)),
        "hurt" to range(5, 10, 14), "die" to listOf(intArrayOf(5, 15)),
        "lookup" to range(8, 0, 5), "crouch" to range(8, 6, 10), "balance" to range(6, 0, 5),
        "spring" to listOf(intArrayOf(4, 0), intArrayOf(4, 1))
    )
    private val HOLD_LAST = setOf("hurt", "lookup", "crouch")
    private val ANIM_SPEED = mapOf("idle" to 0.08, "bored" to 0.1, "hurt" to 0.2, "crouch" to 0.3, "lookup" to 0.25,
        "balance" to 0.12, "spring" to 0.2, "drop" to 0.3, "spin" to 0.5, "die" to 0.1)

    // ------------------------------------------------------------ state
    private var mode = 0 // 0 = menu, 1 = play
    private var tickN = 0
    private val touches = ConcurrentHashMap<Int, FloatArray>()
    private var prevJump = false
    private var spawnX = 96.0
    private var spawnY = 0.0
    private var camX = 0.0
    private var camY = 0.0
    private var camLook = 0.0

    // Sonic
    private var x = 0.0; private var y = 0.0; private var xsp = 0.0; private var ysp = 0.0; private var gsp = 0.0
    private var ang = 0.0; private var drawA = 0.0; private var facing = 1
    private var grounded = true
    private var rolling = false; private var jumping = false; private var spin = false; private var spinCharge = 0.0
    private var crouch = false; private var lookUp = false; private var balance = false
    private var dropActive = false; private var dropT = 0; private var dropReady = false
    private var loop: Loop? = null; private var theta = 0.0; private var loopDir = 1.0; private var loopCool = 0
    private var lock = 0; private var inv = 0; private var hurt = false; private var dead = false; private var deadT = 0
    private var springT = 0; private var af = 0.0; private var animKey = "idle"; private var idleT = 0
    private var ringCount = 0; private var goalT = 0

    private fun hgt() = if (rolling || jumping || spin) 14.0 else 19.0

    private fun resetSonic(px: Double, py: Double) {
        x = px; y = py; xsp = 0.0; ysp = 0.0; gsp = 0.0; ang = 0.0; drawA = 0.0; facing = 1
        grounded = true; rolling = false; jumping = false; spin = false; spinCharge = 0.0
        crouch = false; lookUp = false; balance = false
        dropActive = false; dropT = 0; dropReady = false
        loop = null; theta = 0.0; loopDir = 1.0; loopCool = 0
        lock = 0; inv = 0; hurt = false; dead = false; deadT = 0
        springT = 0; af = 0.0; animKey = "idle"; idleT = 0; goalT = 0
    }

    private fun newGame() {
        buildLevel()
        spawnX = 96.0; spawnY = hAt(96.0) - 19
        resetSonic(spawnX, spawnY)
        ringCount = 0
        camX = clamp(x - VW / 2, 0.0, (LW - VW).toDouble()); camY = clamp(y - VH / 2 - 20, 0.0, (WH - VH).toDouble())
    }

    init { newGame() }

    // ------------------------------------------------------------ helpers
    private var hitWall = false
    private fun wallClip(x0: Double, x1: Double, feet: Double): Double {
        hitWall = false
        if (x1 == x0) return x1
        val dir = if (x1 > x0) 1 else -1
        var xs = x0
        while (xs != x1) {
            var nxt = xs + dir
            if ((dir > 0 && nxt > x1) || (dir < 0 && nxt < x1)) nxt = x1
            val p = floor(nxt + dir * WALLR)
            val c = hAt(p); val t = hAt(p + dir)
            if (t < feet - 6 && (c - t > 6)) { hitWall = true; return xs }
            xs = nxt
        }
        return x1
    }

    private fun setAir(vx: Double, vy: Double) { grounded = false; xsp = vx; ysp = vy; loop = null }

    private fun unball() {
        if (rolling || jumping || spin) y -= 5
        rolling = false; jumping = false; spin = false
        dropActive = false; dropReady = false; dropT = 0
    }

    private fun die() {
        if (dead) return
        dead = true; deadT = 0; grounded = false; loop = null
        xsp = 0.0; ysp = -7.0
        rolling = false; jumping = false; spin = false
    }

    private fun hurtPlayer(srcx: Double) {
        if (inv > 0 || hurt || dead) return
        if (ringCount <= 0) { die(); return }
        ringCount = 0
        val dir = if (x >= srcx) 1.0 else -1.0
        unball()
        hurt = true; inv = 120; lock = 0
        setAir(2 * dir, -4.0)
    }

    private fun land(inp: Inp) {
        val gy = hAt(x)
        val a = angleAt(x)
        val sa = sin(a)
        gsp = if (abs(a) < 0.4) xsp
        else if (abs(a) < 0.78) { if (abs(xsp) > ysp) xsp else ysp * 0.5 * sign(sa) }
        else { if (abs(xsp) > ysp) xsp else ysp * sign(sa) }
        grounded = true; ang = a; springT = 0
        val wasHurt = hurt
        if (wasHurt) gsp = 0.0
        hurt = false; jumping = false; rolling = false
        if (dropReady && inp.jumpHeld && !wasHurt) {
            val f = facing.toDouble()
            val g = if (sign(xsp) == f || xsp == 0.0) gsp / 4 + 8 * f
            else if (abs(a) < 0.1) 8 * f
            else gsp / 2 + 8 * f
            gsp = clamp(g, -12.0, 12.0); rolling = true
        }
        dropActive = false; dropReady = false; dropT = 0
        y = gy - hgt()
    }

    // ------------------------------------------------------------ ground
    private fun groundStep(inp: Inp) {
        val a = ang
        val sa = sin(a); val ca = cos(a)

        if (spin) {
            gsp = 0.0
            if (inp.jumpPressed) spinCharge = min(spinCharge + 2, 8.0)
            spinCharge -= trunc(spinCharge / 0.125) / 256
            if (!inp.down) { gsp = facing * (8 + floor(spinCharge) / 2); spin = false; rolling = true }
            y = hAt(x) - hgt()
            return
        }

        if (lock > 0) lock--

        crouch = inp.down && abs(gsp) < 0.5 && abs(a) < 0.4 && !rolling && lock == 0
        lookUp = inp.up && gsp == 0.0 && !crouch && !rolling
        if (crouch) {
            gsp = 0.0
            if (inp.jumpPressed) {
                spin = true; spinCharge = 2.0; crouch = false
                y = hAt(x) - hgt()
                return
            }
        }

        if (inp.jumpPressed && !crouch) {
            val vx = gsp * ca + JMP * sa
            val vy = gsp * sa - JMP * ca
            if (!(rolling || jumping)) y += 5
            rolling = false; jumping = true
            setAir(vx, vy)
            return
        }

        if (rolling) {
            val f = if (sign(gsp) == sign(sa)) SLP_ROLL_DOWN else SLP_ROLL_UP
            gsp += f * sa
        } else gsp += SLP * sa

        if (rolling) {
            if (inp.left && gsp > 0) gsp -= ROLL_DEC
            else if (inp.right && gsp < 0) gsp += ROLL_DEC
            gsp -= min(abs(gsp), ROLL_FRC) * sign(gsp)
            if (abs(gsp) < 0.5) rolling = false
        } else if (lock == 0 && !crouch) {
            if (inp.left && !inp.right) {
                if (gsp > 0) { gsp -= DEC; if (gsp <= 0) gsp = -DEC }
                else if (gsp > -TOP) { gsp -= ACC; if (gsp <= -TOP) gsp = -TOP }
                facing = -1
            } else if (inp.right && !inp.left) {
                if (gsp < 0) { gsp += DEC; if (gsp >= 0) gsp = DEC }
                else if (gsp < TOP) { gsp += ACC; if (gsp >= TOP) gsp = TOP }
                facing = 1
            } else gsp -= min(abs(gsp), FRC) * sign(gsp)
            if (inp.down && abs(gsp) >= 1) rolling = true
        }
        gsp = clamp(gsp, -16.0, 16.0)

        if (!rolling && abs(gsp) < 2.5 && abs(a) > 0.61 && lock == 0) lock = 30

        val ox = x
        val xs = gsp * ca
        val feet = y + hgt()
        x = wallClip(x, x + xs, feet)
        if (hitWall) gsp = 0.0
        val gy = hAt(x)
        val d = gy - feet
        val tol = min(abs(xs) + 4, 14.0)
        if (d > tol) { setAir(gsp * ca, gsp * sa); return }
        y = gy - hgt()
        ang = angleAt(x)

        if (loopCool > 0) loopCool--
        else if (abs(gsp) >= 4.2 && abs(ang) < 0.2) {
            for (L in loops) {
                if ((ox < L.cx && x >= L.cx && gsp > 0) || (ox > L.cx && x <= L.cx && gsp < 0)) {
                    if (abs(hAt(L.cx) - L.gy) < 1) { loop = L; theta = 0.0; loopDir = sign(gsp) }
                }
            }
        }
    }

    // ------------------------------------------------------------ loop
    private fun loopStep(inp: Inp) {
        val L = loop ?: return
        val sa = sin(-theta)
        if (rolling) {
            val f = if (sign(gsp) == sign(sa)) SLP_ROLL_DOWN else SLP_ROLL_UP
            gsp += f * sa
        } else gsp += SLP * sa
        gsp = clamp(gsp, -16.0, 16.0)
        val rho = L.R - hgt()
        theta += gsp / rho
        val th = theta
        ang = -th
        x = L.cx + rho * sin(th)
        y = (L.gy - L.R) + rho * cos(th)

        if (inp.jumpPressed) {
            val a = -th
            val vx = gsp * cos(a) + JMP * sin(a)
            val vy = gsp * sin(a) - JMP * cos(a)
            if (!(rolling || jumping)) y += 5
            rolling = false; jumping = true
            setAir(vx, vy); return
        }
        var exit = false
        if (abs(th) >= 2 * PI) { exit = true; loopCool = 30 }
        else if (th * loopDir < 0) { exit = true; loopCool = 30 }
        if (exit) { loop = null; x = L.cx; ang = 0.0; y = L.gy - hgt(); return }
        val m = abs(th)
        if (abs(gsp) < 2.5 && m > PI / 3 && m < 5 * PI / 3) {
            val a = -th
            setAir(gsp * cos(a), gsp * sin(a)); lock = 30
        }
    }

    // ------------------------------------------------------------ air
    private fun airStep(inp: Inp) {
        if (jumping && !hurt && !inp.jumpHeld && ysp < -4) ysp = -4.0
        if (!hurt) {
            if (inp.left && !inp.right) {
                if (xsp > -TOP) { xsp -= AIR_ACC; if (xsp <= -TOP) xsp = -TOP }
                facing = -1
            } else if (inp.right && !inp.left) {
                if (xsp < TOP) { xsp += AIR_ACC; if (xsp >= TOP) xsp = TOP }
                facing = 1
            }
        }
        if (ysp < 0 && ysp > -4) xsp -= trunc(xsp / 0.125) / 256

        // Drop Dash: press jump again in the air and keep holding
        if (jumping && !hurt) {
            if (inp.jumpPressed && !dropActive) { dropActive = true; dropT = 0 }
            if (dropActive) {
                if (inp.jumpHeld) { dropT++; if (dropT >= 20) dropReady = true }
                else { dropActive = false; dropT = 0; dropReady = false }
            }
        }

        x = wallClip(x, x + xsp, y + hgt())
        if (hitWall) xsp = 0.0
        y += ysp
        ysp = min(ysp + (if (hurt) 0.1875 else GRV), 16.0)
        if (springT > 0 && ysp > 0) springT = 0

        val gy = hAt(x)
        if (gy < PIT && y + hgt() >= gy) land(inp)
    }

    // ------------------------------------------------------------ entities
    private fun overlaps() {
        val px = x; val py = y; val h = hgt()
        for (r in rings) if (!r.got && abs(px - r.x) < 14 && abs(py - r.y) < h + 6) { r.got = true; ringCount++ }
        for (s in spikes) if (abs(px - (s.x + 16)) < 22 && py + h > s.y - 12 && py - h < s.y) hurtPlayer(s.x + 16)
        for (sp in springs) {
            if (sp.t > 0) sp.t--
            val feet = py + h
            if (abs(px - (sp.x + 16)) < 18 && feet > sp.y - 14 && feet < sp.y + 8 && (grounded || ysp >= 0) && !hurt) {
                if (grounded) xsp = gsp * cos(ang)
                unball()
                y = sp.y - 14 - 19
                setAir(xsp, -sp.power); springT = 1; sp.t = 12
            }
        }
        for (c in checks) if (!c.on && abs(px - c.x) < 22 && abs(py - c.y) < 70) {
            c.on = true; spawnX = c.x; spawnY = hAt(c.x) - 19
        }
        if (goalT == 0 && px > goalX) goalT = 240
    }

    // ------------------------------------------------------------ update
    private fun readInput(): Inp {
        val i = Inp()
        for (t in touches.values) {
            if (t[0] < VW * 0.5) {
                val dx = t[0] - 52; val dy = t[1] - 188
                if (dx * dx + dy * dy < 100 * 100) {
                    if (dx > 12) i.right = true else if (dx < -12) i.left = true
                    if (dy > 14) i.down = true else if (dy < -14) i.up = true
                }
            } else if (t[1] > 40) i.jumpHeld = true
        }
        i.jumpPressed = i.jumpHeld && !prevJump
        prevJump = i.jumpHeld
        return i
    }

    private fun animState(): String {
        if (dead) return "die"
        if (hurt) return "hurt"
        if (spin) return "spin"
        if (dropReady) return "drop"
        if (rolling || jumping) return "roll"
        if (springT > 0) return "spring"
        if (grounded || loop != null) {
            if (crouch) return "crouch"
            if (lookUp) return "lookup"
            val s = abs(gsp)
            if (s < 0.1) {
                if (balance) return "balance"
                if (idleT > 300) return "bored"
                return "idle"
            }
            return if (s < 3.5) "walk" else if (s < 6) "jog" else if (s < 9.8) "run" else "max"
        }
        val s = abs(xsp)
        return if (s < 3.5) "walk" else if (s < 6) "jog" else "run"
    }

    private fun stepSonic(input: Inp) {
        var inp = input
        if (goalT > 0) inp = Inp()
        if (dead) {
            y += ysp; ysp += GRV; deadT++
            if (deadT > 100) { resetSonic(spawnX, spawnY); ringCount = 0 }
            return
        }
        if (inv > 0) inv--
        if (loop != null) loopStep(inp) else if (grounded) groundStep(inp) else airStep(inp)

        balance = false
        if (grounded && loop == null && gsp == 0.0 && !crouch && !spin) {
            if (hAt(x - 12) - hAt(x) > 24 || hAt(x + 12) - hAt(x) > 24) balance = true
        }
        if (grounded && gsp == 0.0 && !inp.left && !inp.right && !inp.up && !inp.down) idleT++ else idleT = 0

        if (!dead) overlaps()
        if (y > DEATH_Y) die()
        if (goalT > 0) { goalT--; if (goalT == 0) newGame() }

        val target = if (grounded || loop != null) ang else 0.0
        drawA = if (loop != null) target else drawA + clamp(target - drawA, -0.3, 0.3)

        val key = animState()
        if (key != animKey) { animKey = key; af = 0.0 }
        val s = abs(if (grounded) gsp else xsp)
        val spd = ANIM_SPEED[key] ?: if (key == "roll") 0.2 + abs(gsp) * 0.03 else 0.12 + s * 0.035
        af += spd

        val dx = x - camX - VW / 2
        if (dx > 16) camX += min(dx - 16, 16.0) else if (dx < -16) camX += max(dx + 16, -16.0)
        if (lookUp && idleT > 60) camLook = max(camLook - 2, -64.0)
        else if (crouch && idleT > 60) camLook = min(camLook + 2, 64.0)
        else camLook -= sign(camLook) * min(abs(camLook), 4.0)
        val ty = y - VH / 2 - 10 + camLook
        val dy = ty - camY
        if (grounded || loop != null) {
            val sp = if (abs(gsp) < 8) 6.0 else 16.0
            camY += clamp(dy, -sp, sp)
        } else {
            if (dy > 32) camY += min(dy - 32, 16.0) else if (dy < -32) camY += max(dy + 32, -16.0)
        }
        camX = clamp(camX, 0.0, (LW - VW).toDouble()); camY = clamp(camY, 0.0, (WH - VH).toDouble())
    }

    @Volatile private var cmd = 0 // 1 = start game, 2 = back to menu (set on UI thread, handled on game thread)

    fun tick() {
        tickN++
        if (cmd == 1) { mode = 1; touches.clear(); newGame(); prevJump = true; cmd = 0 }
        else if (cmd == 2) { mode = 0; touches.clear(); cmd = 0 }
        if (mode == 1) stepSonic(readInput())
    }

    // ------------------------------------------------------------ input events (UI thread)
    fun touchDown(id: Int, vx: Float, vy: Float) {
        if (mode == 0) { cmd = 1; return }
        if (vx > VW - 40 && vy < 44) { cmd = 2; return }
        touches[id] = floatArrayOf(vx, vy)
    }
    fun touchMove(id: Int, vx: Float, vy: Float) { touches[id]?.let { it[0] = vx; it[1] = vy } }
    fun touchUp(id: Int) { touches.remove(id) }
    fun touchesClear() { touches.clear() }

    // ------------------------------------------------------------ drawing
    private val CA = Color.rgb(219, 109, 0)
    private val CB = Color.rgb(146, 73, 0)
    private val G1 = Color.rgb(80, 210, 40)
    private val G2 = Color.rgb(0, 130, 30)
    private val p = Paint().apply { isAntiAlias = false; style = Paint.Style.FILL }
    private val sp = Paint().apply { isAntiAlias = false; isFilterBitmap = false }
    private val tp = Paint().apply { isAntiAlias = false; typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD) }
    private val path = Path()
    private lateinit var c: Canvas

    private fun rect(x: Double, y: Double, w: Double, h: Double, col: Int) {
        p.style = Paint.Style.FILL; p.color = col
        c.drawRect(x.toFloat(), y.toFloat(), (x + w).toFloat(), (y + h).toFloat(), p)
    }
    private fun text(s: String, x: Float, y: Float, size: Float, col: Int, shadow: Boolean = false) {
        tp.textSize = size
        if (shadow) { tp.color = Color.argb(150, 0, 0, 0); c.drawText(s, x + 1, y + 1, tp) }
        tp.color = col; c.drawText(s, x, y, tp)
    }
    private fun sprite(bmp: Bitmap, sx: Int, sy: Int, sw: Int, sh: Int, px: Double, py: Double, rot: Double,
                       fx: Double, fy: Double, ox: Float, oy: Float) {
        c.save()
        c.translate(px.toFloat(), py.toFloat())
        c.rotate(Math.toDegrees(rot).toFloat())
        c.scale(fx.toFloat(), fy.toFloat())
        c.drawBitmap(bmp, Rect(sx, sy, sx + sw, sy + sh), RectF(-ox, -oy, -ox + sw, -oy + sh), sp)
        c.restore()
    }

    private fun drawBackground() {
        val bands = intArrayOf(Color.rgb(40, 120, 230), Color.rgb(60, 140, 240), Color.rgb(90, 165, 250),
            Color.rgb(130, 195, 255), Color.rgb(170, 220, 255))
        for (i in bands.indices) rect(0.0, i * 48.0, VW.toDouble(), 48.0, bands[i])
        var sx = 0
        while (sx <= VW) {
            val hy = 170 + 22 * sin((camX * 0.25 + sx) / 50) - camY * 0.15
            rect(sx.toDouble(), hy, 4.0, VH - hy, Color.rgb(40, 150, 90)); sx += 4
        }
        sx = 0
        while (sx <= VW) {
            val hy = 195 + 14 * sin((camX * 0.45 + sx) / 34 + 2) - camY * 0.3
            rect(sx.toDouble(), hy, 4.0, VH - hy, Color.rgb(20, 120, 60)); sx += 4
        }
    }

    private fun drawTerrain() {
        val cx = floor(camX).toInt(); val cy = floor(camY).toInt()
        val x0 = floor(cx / 4.0).toInt() * 4
        var wx = x0
        while (wx <= x0 + VW + 4) {
            if (wx in 0 until LW) {
                val top = hAt(wx + 2.0)
                if (top < PIT) {
                    val gx = (wx - cx).toDouble()
                    val ytop = floor(top).toInt()
                    val colx = floor(wx / 16.0).toInt()
                    var row = floor(ytop / 16.0).toInt()
                    var yy = ytop
                    val bottom = cy + VH
                    while (yy < bottom) {
                        val ny = (row + 1) * 16
                        rect(gx, (yy - cy).toDouble(), 4.0, (ny - yy).toDouble(), if ((colx + row) % 2 == 0) CA else CB)
                        yy = ny; row++
                    }
                    rect(gx, (ytop - cy).toDouble(), 4.0, 4.0, G1)
                    rect(gx, (ytop + 4 - cy).toDouble(), 4.0, 3.0, G2)
                }
            }
            wx += 4
        }
    }

    private fun quad(px: DoubleArray) {
        path.reset(); path.moveTo(px[0].toFloat(), px[1].toFloat())
        var i = 2
        while (i < px.size) { path.lineTo(px[i].toFloat(), px[i + 1].toFloat()); i += 2 }
        path.close(); c.drawPath(path, p)
    }

    private fun drawLoops() {
        for (L in loops) {
            val cx = L.cx - camX; val cy = L.gy - L.R - camY
            if (cx > -L.R - 40 && cx < VW + L.R + 40) {
                for (k in 0 until 60) {
                    val a0 = k * PI / 30; val a1 = (k + 1) * PI / 30
                    val r0 = L.R; val r1 = L.R + L.T
                    p.style = Paint.Style.FILL; p.color = if (k % 2 == 0) CA else CB
                    quad(doubleArrayOf(cx + r0 * sin(a0), cy + r0 * cos(a0), cx + r1 * sin(a0), cy + r1 * cos(a0),
                        cx + r1 * sin(a1), cy + r1 * cos(a1), cx + r0 * sin(a1), cy + r0 * cos(a1)))
                }
                p.style = Paint.Style.STROKE; p.strokeWidth = 1f; p.color = Color.rgb(109, 36, 0)
                c.drawCircle(cx.toFloat(), cy.toFloat(), L.R.toFloat(), p)
                p.style = Paint.Style.FILL
            }
        }
    }

    private fun drawObjects() {
        val t = tickN
        for (r in rings) if (!r.got) {
            val sx = r.x - camX; val sy = r.y - camY
            if (sx > -10 && sx < VW + 10) {
                val w = max(1.5, abs(cos(t / 10.0 + r.x * 0.05)) * 6)
                p.style = Paint.Style.STROKE; p.strokeWidth = 2f; p.color = Color.rgb(255, 215, 0)
                c.drawOval(RectF((sx - w).toFloat(), (sy - 7).toFloat(), (sx + w).toFloat(), (sy + 7).toFloat()), p)
                p.style = Paint.Style.FILL
            }
        }
        for (s in spikes) {
            val sx = s.x - camX; val sy = s.y - camY
            p.style = Paint.Style.FILL; p.color = Color.rgb(200, 200, 210)
            for (k in 0 until 4) quad(doubleArrayOf(sx + k * 8, sy, sx + k * 8 + 4, sy - 16, sx + k * 8 + 8, sy))
            rect(sx, sy - 2, 32.0, 2.0, Color.rgb(90, 90, 100))
        }
        for (s in springs) {
            val sx = s.x - camX; val sy = s.y - camY
            val comp = if (s.t > 0) 8.0 else 0.0
            rect(sx + 4, sy - 6, 24.0, 6.0, Color.rgb(150, 150, 160))
            rect(sx + 2, sy - 16 + comp, 28.0, 6.0, if (s.red) Color.rgb(230, 40, 40) else Color.rgb(255, 210, 0))
            rect(sx + 12, sy - 10 + comp / 2, 8.0, 4.0, Color.rgb(200, 200, 210))
        }
        for (ck in checks) {
            val sx = ck.x - camX; val sy = ck.y - camY
            rect(sx - 2, sy - 40, 4.0, 40.0, Color.rgb(170, 170, 180))
            p.style = Paint.Style.FILL; p.color = if (ck.on) Color.rgb(255, 40, 40) else Color.rgb(40, 110, 255)
            c.drawCircle(sx.toFloat(), (sy - 44).toFloat(), 6f, p)
        }
        val gx = goalX - camX; val gy = hAt(goalX) - camY
        rect(gx - 2, gy - 56, 4.0, 56.0, Color.rgb(170, 170, 180))
        rect(gx - 16, gy - 70, 32.0, 18.0, Color.rgb(230, 60, 60))
        text("GOAL", (gx - 13).toFloat(), (gy - 57).toFloat(), 11f, Color.WHITE)
    }

    private fun drawSonic() {
        if (inv > 0 && (inv / 3) % 2 == 0) return
        val px = floor(x) - floor(camX); val py = floor(y) - floor(camY)
        val key = animKey
        if (key == "spin") {
            val f = floor(af).toInt() % 6
            sprite(sdash, f * 32, 0, 32, 32, px, py, 0.0, facing.toDouble(), 1.0, 16f, 16f)
            return
        }
        val list = ANIM[key]!!
        val n = list.size
        val idx = if (key in HOLD_LAST) min(floor(af).toInt(), n - 1) else floor(af).toInt() % n
        val fr = list[idx]
        val sx = fr[1] * 48; val sy = fr[0] * 48
        when (key) {
            "roll", "drop" -> sprite(atlas, sx, sy, 48, 48, px, py, 0.0, facing.toDouble(), 1.0, 24f, 28f)
            "hurt", "die" -> sprite(atlas, sx, sy, 48, 48, px, py + 19, 0.0, facing.toDouble(), 1.0, 24f, 48f)
            else -> {
                var fx = px; var fy = py + 19
                if (loop != null) { fx = px + 19 * sin(theta); fy = py + 19 * cos(theta) }
                sprite(atlas, sx, sy, 48, 48, fx, fy, drawA, facing.toDouble(), 1.0, 24f, 48f)
            }
        }
    }

    private fun drawHUD() {
        val spd = abs(if (grounded) gsp else xsp)
        text("RINGS $ringCount", 8f, 18f, 11f, Color.rgb(255, 230, 50), true)
        text("SPEED " + "%.2f".format(spd), 8f, 32f, 11f, Color.WHITE, true)
        text(LANG_NAME, VW - 130f, 18f, 10f, Color.argb(190, 255, 255, 255), true)
        if (goalT > 0) text("GOAL!", VW / 2f - 20f, 90f, 14f, Color.WHITE, true)
        if (dropReady) text("DROP DASH READY", VW / 2f - 60f, 50f, 11f, Color.rgb(255, 255, 80), true)
        var dx = 0f; var dy = 0f
        for (t in touches.values) if (t[0] < VW * 0.5) { dx = t[0] - 52; dy = t[1] - 188 }
        var dirIdx = 0
        if (dx * dx + dy * dy < 100 * 100 && (abs(dx) > 12 || abs(dy) > 14)) {
            dirIdx = if (abs(dx) >= abs(dy)) (if (dx < 0) 1 else 3) else (if (dy > 0) 2 else 4)
        }
        sp.alpha = 217
        c.drawBitmap(dpadImg[dirIdx], 20f, 156f, sp)
        var jumpDown = false
        for (t in touches.values) if (t[0] >= VW * 0.5 && t[1] > 40) jumpDown = true
        c.drawBitmap(btnImg[if (jumpDown) 1 else 0], 340f, 164f, sp)
        sp.alpha = 255
        c.drawBitmap(pauseImg, (VW - 22).toFloat(), 26f, sp)
    }

    private fun drawMenu() {
        drawBackground()
        rect(0.0, 190.0, VW.toDouble(), 50.0, CA)
        rect(0.0, 190.0, VW.toDouble(), 4.0, G1)
        text("SONIC MANIA", 100f, 60f, 32f, Color.WHITE, true)
        text("PHYSICS TEST", 112f, 88f, 22f, Color.rgb(80, 200, 255), true)
        val list = ANIM["max"]!!
        val fr = list[(tickN / 3) % list.size]
        sprite(atlas, fr[1] * 48, fr[0] * 48, 48, 48, VW / 2.0, 190.0, 0.0, 1.6, 1.6, 24f, 48f)
        text(LANG_NAME, VW / 2f - 56f, 115f, 14f, Color.WHITE, true)
        if ((tickN / 30) % 2 == 0) text("TAP TO START", VW / 2f - 66f, 138f, 16f, Color.WHITE, true)
        text("D-PAD: MOVE  A: JUMP  DOWN+A: SPIN DASH  JUMP + HOLD A: DROP DASH", 14f, 230f, 8f, Color.WHITE, true)
    }

    fun draw(canvas: Canvas) {
        c = canvas
        c.drawColor(Color.BLACK)
        if (mode == 0) drawMenu()
        else { drawBackground(); drawTerrain(); drawLoops(); drawObjects(); drawSonic(); drawHUD() }
    }
}
