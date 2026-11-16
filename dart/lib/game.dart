// Sonic Mania-style physics test | Dart + Flutter (mobile)
// Fixed 60 Hz timestep, virtual screen 424x240, units are pixels / frame.
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';

const int VW = 424;
const int VH = 240;
const String langName = 'DART / FLUTTER';

// ---- physics constants (Sonic Mania / Genesis values)
const double ACC = 0.046875, DEC = 0.5, FRC = 0.046875, TOP = 6.0;
const double SLP = 0.125, SLP_ROLL_UP = 0.078125, SLP_ROLL_DOWN = 0.3125;
const double ROLL_FRC = 0.0234375, ROLL_DEC = 0.125;
const double AIR_ACC = 0.09375, GRV = 0.21875, JMP = 6.5;
const int WALLR = 10;

const int LW = 6900, WH = 800;
const double PIT = 5000.0, DEATH_Y = 900.0;

double sign(double v) => v > 0 ? 1.0 : (v < 0 ? -1.0 : 0.0);
double clampD(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double trunc(double v) => v.truncateToDouble();

class Images {
  final ui.Image atlas, sdash, pause;
  final List<ui.Image> dpad, btn;
  Images({required this.atlas, required this.sdash, required this.dpad, required this.btn, required this.pause});
}

class Inp {
  bool left = false, right = false, up = false, down = false, jumpHeld = false, jumpPressed = false;
}

class Loop {
  final double cx, gy;
  final double R = 88, T = 24;
  Loop(this.cx, this.gy);
}

class Ring {
  final double x, y;
  bool got = false;
  Ring(this.x, this.y);
}

class Spike {
  final double x, y;
  Spike(this.x, this.y);
}

class Spring {
  final double x, y, power;
  final bool red;
  int t = 0;
  Spring(this.x, this.y, this.power, this.red);
}

class Check {
  final double x, y;
  bool on = false;
  Check(this.x, this.y);
}

List<List<int>> _range(int r, int a, int b) => [for (var i = a; i <= b; i++) [r, i]];

class Game {
  final Images img;
  Game(this.img) {
    newGame();
  }

  // ------------------------------------------------------------ level
  final Float64List H = Float64List(LW);
  final List<Loop> loops = [];
  final List<Ring> rings = [];
  final List<Spike> spikes = [];
  final List<Spring> springs = [];
  final List<Check> checks = [];
  final double goalX = 6780;

  double hAt(double x) {
    var i = x.floor();
    if (i < 0) {
      i = 0;
    } else if (i > LW - 1) {
      i = LW - 1;
    }
    return H[i];
  }

  double angleAt(double x) {
    final h1 = hAt(x - 6), h2 = hAt(x + 6);
    if (h1 >= PIT || h2 >= PIT) return 0;
    if ((h2 - h1).abs() > 14) return 0;
    return atan2(h2 - h1, 12);
  }

  void buildLevel() {
    loops.clear();
    rings.clear();
    spikes.clear();
    springs.clear();
    checks.clear();
    int x = 0;
    double cur = 400;
    void flat(int len) {
      for (var i = 0; i < len; i++) {
        H[x + i] = cur;
      }
      x += len;
    }

    void ramp(int len, double dy) {
      final y0 = cur;
      for (var i = 0; i < len; i++) {
        H[x + i] = y0 + dy * (1 - cos(pi * i / len)) / 2;
      }
      cur = y0 + dy;
      x += len;
    }

    void pit(int len) {
      for (var i = 0; i < len; i++) {
        H[x + i] = PIT;
      }
      x += len;
    }

    void loop(int len) {
      loops.add(Loop(x + len / 2, cur));
      flat(len);
    }

    flat(500); ramp(360, -80); flat(160); ramp(520, 160); flat(300); loop(640); flat(240);
    ramp(300, -190); flat(120); ramp(300, 190); flat(320); pit(150); flat(500);
    ramp(420, -200); flat(80); ramp(560, 260); flat(160); loop(700); flat(570);

    void block(int x0, int w, int h) {
      final top = H[x0] - h;
      for (var i = x0; i < x0 + w; i++) {
        H[i] = top;
      }
    }

    block(4150, 64, 24);
    block(4270, 64, 48);

    void addRings(int x0, int n, int gap, int lift) {
      for (var i = 0; i < n; i++) {
        final rx = (x0 + i * gap).toDouble();
        rings.add(Ring(rx, hAt(rx) - lift));
      }
    }

    addRings(300, 6, 24, 26); addRings(900, 6, 24, 34); addRings(1300, 8, 24, 26);
    addRings(2700, 5, 24, 26); addRings(3770, 4, 30, 90); addRings(4600, 6, 24, 40);
    addRings(5200, 6, 24, 30); addRings(6400, 8, 24, 26);
    for (final L in loops) {
      for (var k = 0; k < 12; k++) {
        final t = k * pi / 6;
        rings.add(Ring(L.cx + (L.R - 22) * sin(t), L.gy - L.R + (L.R - 22) * cos(t)));
      }
    }
    for (final sx in [3560, 3592, 3624]) {
      spikes.add(Spike(sx.toDouble(), hAt(sx + 16.0)));
    }
    springs.add(Spring(2600, hAt(2616), 10, false));
    springs.add(Spring(3940, hAt(3956), 16, true));
    for (final cx in [1700, 4040, 5500]) {
      checks.add(Check(cx.toDouble(), hAt(cx.toDouble())));
    }
  }

  // ------------------------------------------------------------ animation tables
  final Map<String, List<List<int>>> anim = {
    'idle': _range(0, 0, 10), 'bored': _range(7, 0, 5),
    'walk': _range(1, 0, 11), 'jog': _range(1, 12, 23),
    'run': _range(2, 0, 9), 'max': _range(2, 10, 17),
    'roll': [[3, 0], [3, 2], [3, 1], [3, 3]], 'drop': [[3, 4], [3, 5]],
    'hurt': _range(5, 10, 14), 'die': [[5, 15]],
    'lookup': _range(8, 0, 5), 'crouch': _range(8, 6, 10), 'balance': _range(6, 0, 5),
    'spring': [[4, 0], [4, 1]],
  };
  final Set<String> holdLast = {'hurt', 'lookup', 'crouch'};
  final Map<String, double> animSpeed = {
    'idle': 0.08, 'bored': 0.1, 'hurt': 0.2, 'crouch': 0.3, 'lookup': 0.25,
    'balance': 0.12, 'spring': 0.2, 'drop': 0.3, 'spin': 0.5, 'die': 0.1,
  };

  // ------------------------------------------------------------ state
  int mode = 0; // 0 menu, 1 play
  int tickN = 0;
  double acc = 0;
  final Map<int, Offset> touches = {}; // virtual coords
  bool prevJump = false;
  double spawnX = 96, spawnY = 0;
  double camX = 0, camY = 0, camLook = 0;

  double x = 0, y = 0, xsp = 0, ysp = 0, gsp = 0;
  double ang = 0, drawA = 0;
  int facing = 1;
  bool grounded = true, rolling = false, jumping = false, spin = false;
  double spinCharge = 0;
  bool crouch = false, lookUp = false, balance = false;
  bool dropActive = false, dropReady = false;
  int dropT = 0;
  Loop? loop;
  double theta = 0, loopDir = 1;
  int loopCool = 0, lock = 0, inv = 0, deadT = 0, springT = 0, idleT = 0, ringCount = 0, goalT = 0;
  bool hurt = false, dead = false;
  double af = 0;
  String animKey = 'idle';

  double hgt() => (rolling || jumping || spin) ? 14.0 : 19.0;

  void resetSonic(double px, double py) {
    x = px; y = py; xsp = 0; ysp = 0; gsp = 0; ang = 0; drawA = 0; facing = 1;
    grounded = true; rolling = false; jumping = false; spin = false; spinCharge = 0;
    crouch = false; lookUp = false; balance = false;
    dropActive = false; dropT = 0; dropReady = false;
    loop = null; theta = 0; loopDir = 1; loopCool = 0;
    lock = 0; inv = 0; hurt = false; dead = false; deadT = 0;
    springT = 0; af = 0; animKey = 'idle'; idleT = 0; goalT = 0;
  }

  void newGame() {
    buildLevel();
    spawnX = 96;
    spawnY = hAt(96) - 19;
    resetSonic(spawnX, spawnY);
    ringCount = 0;
    camX = clampD(x - VW / 2, 0, (LW - VW).toDouble());
    camY = clampD(y - VH / 2 - 20, 0, (WH - VH).toDouble());
  }

  // ------------------------------------------------------------ helpers
  bool hitWall = false;
  double wallClip(double x0, double x1, double feet) {
    hitWall = false;
    if (x1 == x0) return x1;
    final dir = x1 > x0 ? 1 : -1;
    var xs = x0;
    while (xs != x1) {
      var nxt = xs + dir;
      if ((dir > 0 && nxt > x1) || (dir < 0 && nxt < x1)) nxt = x1;
      final p = (nxt + dir * WALLR).floorToDouble();
      final c = hAt(p), t = hAt(p + dir);
      if (t < feet - 6 && (c - t > 6)) {
        hitWall = true;
        return xs;
      }
      xs = nxt;
    }
    return x1;
  }

  void setAir(double vx, double vy) {
    grounded = false; xsp = vx; ysp = vy; loop = null;
  }

  void unball() {
    if (rolling || jumping || spin) y -= 5;
    rolling = false; jumping = false; spin = false;
    dropActive = false; dropReady = false; dropT = 0;
  }

  void die() {
    if (dead) return;
    dead = true; deadT = 0; grounded = false; loop = null;
    xsp = 0; ysp = -7;
    rolling = false; jumping = false; spin = false;
  }

  void hurtPlayer(double srcx) {
    if (inv > 0 || hurt || dead) return;
    if (ringCount <= 0) {
      die();
      return;
    }
    ringCount = 0;
    final dir = x >= srcx ? 1.0 : -1.0;
    unball();
    hurt = true; inv = 120; lock = 0;
    setAir(2 * dir, -4);
  }

  void land(Inp inp) {
    final gy = hAt(x);
    final a = angleAt(x);
    final sa = sin(a);
    if (a.abs() < 0.4) {
      gsp = xsp;
    } else if (a.abs() < 0.78) {
      gsp = xsp.abs() > ysp ? xsp : ysp * 0.5 * sign(sa);
    } else {
      gsp = xsp.abs() > ysp ? xsp : ysp * sign(sa);
    }
    grounded = true; ang = a; springT = 0;
    final wasHurt = hurt;
    if (wasHurt) gsp = 0;
    hurt = false; jumping = false; rolling = false;
    if (dropReady && inp.jumpHeld && !wasHurt) {
      final f = facing.toDouble();
      double g;
      if (sign(xsp) == f || xsp == 0) {
        g = gsp / 4 + 8 * f;
      } else if (a.abs() < 0.1) {
        g = 8 * f;
      } else {
        g = gsp / 2 + 8 * f;
      }
      gsp = clampD(g, -12, 12);
      rolling = true;
    }
    dropActive = false; dropReady = false; dropT = 0;
    y = gy - hgt();
  }

  // ------------------------------------------------------------ ground
  void groundStep(Inp inp) {
    final a = ang;
    final sa = sin(a), ca = cos(a);

    if (spin) {
      gsp = 0;
      if (inp.jumpPressed) spinCharge = min(spinCharge + 2, 8.0);
      spinCharge -= trunc(spinCharge / 0.125) / 256;
      if (!inp.down) {
        gsp = facing * (8 + spinCharge.floorToDouble() / 2);
        spin = false;
        rolling = true;
      }
      y = hAt(x) - hgt();
      return;
    }

    if (lock > 0) lock--;

    crouch = inp.down && gsp.abs() < 0.5 && a.abs() < 0.4 && !rolling && lock == 0;
    lookUp = inp.up && gsp == 0 && !crouch && !rolling;
    if (crouch) {
      gsp = 0;
      if (inp.jumpPressed) {
        spin = true; spinCharge = 2; crouch = false;
        y = hAt(x) - hgt();
        return;
      }
    }

    if (inp.jumpPressed && !crouch) {
      final vx = gsp * ca + JMP * sa;
      final vy = gsp * sa - JMP * ca;
      if (!(rolling || jumping)) y += 5;
      rolling = false; jumping = true;
      setAir(vx, vy);
      return;
    }

    if (rolling) {
      final f = sign(gsp) == sign(sa) ? SLP_ROLL_DOWN : SLP_ROLL_UP;
      gsp += f * sa;
    } else {
      gsp += SLP * sa;
    }

    if (rolling) {
      if (inp.left && gsp > 0) {
        gsp -= ROLL_DEC;
      } else if (inp.right && gsp < 0) {
        gsp += ROLL_DEC;
      }
      gsp -= min(gsp.abs(), ROLL_FRC) * sign(gsp);
      if (gsp.abs() < 0.5) rolling = false;
    } else if (lock == 0 && !crouch) {
      if (inp.left && !inp.right) {
        if (gsp > 0) {
          gsp -= DEC;
          if (gsp <= 0) gsp = -DEC;
        } else if (gsp > -TOP) {
          gsp -= ACC;
          if (gsp <= -TOP) gsp = -TOP;
        }
        facing = -1;
      } else if (inp.right && !inp.left) {
        if (gsp < 0) {
          gsp += DEC;
          if (gsp >= 0) gsp = DEC;
        } else if (gsp < TOP) {
          gsp += ACC;
          if (gsp >= TOP) gsp = TOP;
        }
        facing = 1;
      } else {
        gsp -= min(gsp.abs(), FRC) * sign(gsp);
      }
      if (inp.down && gsp.abs() >= 1) rolling = true;
    }
    gsp = clampD(gsp, -16, 16);

    if (!rolling && gsp.abs() < 2.5 && a.abs() > 0.61 && lock == 0) lock = 30;

    final ox = x;
    final xs = gsp * ca;
    final feet = y + hgt();
    x = wallClip(x, x + xs, feet);
    if (hitWall) gsp = 0;
    final gy = hAt(x);
    final d = gy - feet;
    final tol = min(xs.abs() + 4, 14.0);
    if (d > tol) {
      setAir(gsp * ca, gsp * sa);
      return;
    }
    y = gy - hgt();
    ang = angleAt(x);

    if (loopCool > 0) {
      loopCool--;
    } else if (gsp.abs() >= 4.2 && ang.abs() < 0.2) {
      for (final L in loops) {
        if ((ox < L.cx && x >= L.cx && gsp > 0) || (ox > L.cx && x <= L.cx && gsp < 0)) {
          if ((hAt(L.cx) - L.gy).abs() < 1) {
            loop = L; theta = 0; loopDir = sign(gsp);
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ loop
  void loopStep(Inp inp) {
    final L = loop;
    if (L == null) return;
    final sa = sin(-theta);
    if (rolling) {
      final f = sign(gsp) == sign(sa) ? SLP_ROLL_DOWN : SLP_ROLL_UP;
      gsp += f * sa;
    } else {
      gsp += SLP * sa;
    }
    gsp = clampD(gsp, -16, 16);
    final rho = L.R - hgt();
    theta += gsp / rho;
    final th = theta;
    ang = -th;
    x = L.cx + rho * sin(th);
    y = (L.gy - L.R) + rho * cos(th);

    if (inp.jumpPressed) {
      final a = -th;
      final vx = gsp * cos(a) + JMP * sin(a);
      final vy = gsp * sin(a) - JMP * cos(a);
      if (!(rolling || jumping)) y += 5;
      rolling = false; jumping = true;
      setAir(vx, vy);
      return;
    }
    var exit = false;
    if (th.abs() >= 2 * pi) {
      exit = true; loopCool = 30;
    } else if (th * loopDir < 0) {
      exit = true; loopCool = 30;
    }
    if (exit) {
      loop = null; x = L.cx; ang = 0; y = L.gy - hgt();
      return;
    }
    final m = th.abs();
    if (gsp.abs() < 2.5 && m > pi / 3 && m < 5 * pi / 3) {
      final a = -th;
      setAir(gsp * cos(a), gsp * sin(a));
      lock = 30;
    }
  }

  // ------------------------------------------------------------ air
  void airStep(Inp inp) {
    if (jumping && !hurt && !inp.jumpHeld && ysp < -4) ysp = -4;
    if (!hurt) {
      if (inp.left && !inp.right) {
        if (xsp > -TOP) {
          xsp -= AIR_ACC;
          if (xsp <= -TOP) xsp = -TOP;
        }
        facing = -1;
      } else if (inp.right && !inp.left) {
        if (xsp < TOP) {
          xsp += AIR_ACC;
          if (xsp >= TOP) xsp = TOP;
        }
        facing = 1;
      }
    }
    if (ysp < 0 && ysp > -4) xsp -= trunc(xsp / 0.125) / 256;

    // Drop Dash: press jump again in the air and keep holding
    if (jumping && !hurt) {
      if (inp.jumpPressed && !dropActive) {
        dropActive = true; dropT = 0;
      }
      if (dropActive) {
        if (inp.jumpHeld) {
          dropT++;
          if (dropT >= 20) dropReady = true;
        } else {
          dropActive = false; dropT = 0; dropReady = false;
        }
      }
    }

    x = wallClip(x, x + xsp, y + hgt());
    if (hitWall) xsp = 0;
    y += ysp;
    ysp = min(ysp + (hurt ? 0.1875 : GRV), 16.0);
    if (springT > 0 && ysp > 0) springT = 0;

    final gy = hAt(x);
    if (gy < PIT && y + hgt() >= gy) land(inp);
  }

  // ------------------------------------------------------------ entities
  void overlaps() {
    final px = x, py = y, h = hgt();
    for (final r in rings) {
      if (!r.got && (px - r.x).abs() < 14 && (py - r.y).abs() < h + 6) {
        r.got = true;
        ringCount++;
      }
    }
    for (final s in spikes) {
      if ((px - (s.x + 16)).abs() < 22 && py + h > s.y - 12 && py - h < s.y) hurtPlayer(s.x + 16);
    }
    for (final sp in springs) {
      if (sp.t > 0) sp.t--;
      final feet = py + h;
      if ((px - (sp.x + 16)).abs() < 18 && feet > sp.y - 14 && feet < sp.y + 8 && (grounded || ysp >= 0) && !hurt) {
        if (grounded) xsp = gsp * cos(ang);
        unball();
        y = sp.y - 14 - 19;
        setAir(xsp, -sp.power);
        springT = 1;
        sp.t = 12;
      }
    }
    for (final c in checks) {
      if (!c.on && (px - c.x).abs() < 22 && (py - c.y).abs() < 70) {
        c.on = true; spawnX = c.x; spawnY = hAt(c.x) - 19;
      }
    }
    if (goalT == 0 && px > goalX) goalT = 240;
  }

  // ------------------------------------------------------------ update
  Inp readInput() {
    final i = Inp();
    for (final t in touches.values) {
      if (t.dx < VW * 0.5) {
        final dx = t.dx - 52, dy = t.dy - 188;
        if (dx * dx + dy * dy < 100 * 100) {
          if (dx > 12) {
            i.right = true;
          } else if (dx < -12) {
            i.left = true;
          }
          if (dy > 14) {
            i.down = true;
          } else if (dy < -14) {
            i.up = true;
          }
        }
      } else if (t.dy > 40) {
        i.jumpHeld = true;
      }
    }
    i.jumpPressed = i.jumpHeld && !prevJump;
    prevJump = i.jumpHeld;
    return i;
  }

  String animState() {
    if (dead) return 'die';
    if (hurt) return 'hurt';
    if (spin) return 'spin';
    if (dropReady) return 'drop';
    if (rolling || jumping) return 'roll';
    if (springT > 0) return 'spring';
    if (grounded || loop != null) {
      if (crouch) return 'crouch';
      if (lookUp) return 'lookup';
      final s = gsp.abs();
      if (s < 0.1) {
        if (balance) return 'balance';
        if (idleT > 300) return 'bored';
        return 'idle';
      }
      return s < 3.5 ? 'walk' : (s < 6 ? 'jog' : (s < 9.8 ? 'run' : 'max'));
    }
    final s = xsp.abs();
    return s < 3.5 ? 'walk' : (s < 6 ? 'jog' : 'run');
  }

  void stepSonic(Inp input) {
    var inp = input;
    if (goalT > 0) inp = Inp();
    if (dead) {
      y += ysp; ysp += GRV; deadT++;
      if (deadT > 100) {
        resetSonic(spawnX, spawnY);
        ringCount = 0;
      }
      return;
    }
    if (inv > 0) inv--;
    if (loop != null) {
      loopStep(inp);
    } else if (grounded) {
      groundStep(inp);
    } else {
      airStep(inp);
    }

    balance = false;
    if (grounded && loop == null && gsp == 0 && !crouch && !spin) {
      if (hAt(x - 12) - hAt(x) > 24 || hAt(x + 12) - hAt(x) > 24) balance = true;
    }
    if (grounded && gsp == 0 && !inp.left && !inp.right && !inp.up && !inp.down) {
      idleT++;
    } else {
      idleT = 0;
    }

    if (!dead) overlaps();
    if (y > DEATH_Y) die();
    if (goalT > 0) {
      goalT--;
      if (goalT == 0) newGame();
    }

    final target = (grounded || loop != null) ? ang : 0.0;
    drawA = loop != null ? target : drawA + clampD(target - drawA, -0.3, 0.3);

    final key = animState();
    if (key != animKey) {
      animKey = key;
      af = 0;
    }
    final s = (grounded ? gsp : xsp).abs();
    final spd = animSpeed[key] ?? (key == 'roll' ? 0.2 + gsp.abs() * 0.03 : 0.12 + s * 0.035);
    af += spd;

    final dx = x - camX - VW / 2;
    if (dx > 16) {
      camX += min(dx - 16, 16.0);
    } else if (dx < -16) {
      camX += max(dx + 16, -16.0);
    }
    if (lookUp && idleT > 60) {
      camLook = max(camLook - 2, -64.0);
    } else if (crouch && idleT > 60) {
      camLook = min(camLook + 2, 64.0);
    } else {
      camLook -= sign(camLook) * min(camLook.abs(), 4.0);
    }
    final ty = y - VH / 2 - 10 + camLook;
    final dy = ty - camY;
    if (grounded || loop != null) {
      final sp = gsp.abs() < 8 ? 6.0 : 16.0;
      camY += clampD(dy, -sp, sp);
    } else {
      if (dy > 32) {
        camY += min(dy - 32, 16.0);
      } else if (dy < -32) {
        camY += max(dy + 32, -16.0);
      }
    }
    camX = clampD(camX, 0, (LW - VW).toDouble());
    camY = clampD(camY, 0, (WH - VH).toDouble());
  }

  void update(double dt) {
    acc += min(dt, 0.1);
    while (acc >= 1 / 60) {
      acc -= 1 / 60;
      tickN++;
      if (mode == 1) stepSonic(readInput());
    }
  }

  // ------------------------------------------------------------ input events
  double _scale = 1, _offX = 0, _offY = 0;
  Offset _toV(double lx, double ly) => Offset((lx - _offX) / _scale, (ly - _offY) / _scale);

  void touchDown(int id, double lx, double ly) {
    final v = _toV(lx, ly);
    if (mode == 0) {
      mode = 1; touches.clear(); newGame(); prevJump = true;
      return;
    }
    if (v.dx > VW - 40 && v.dy < 44) {
      mode = 0; touches.clear();
      return;
    }
    touches[id] = v;
  }

  void touchMove(int id, double lx, double ly) {
    if (touches.containsKey(id)) touches[id] = _toV(lx, ly);
  }

  void touchUp(int id) => touches.remove(id);

  // ------------------------------------------------------------ drawing
  static const Color CA = Color(0xFFDB6D00), CB = Color(0xFF924900);
  static const Color G1 = Color(0xFF50D228), G2 = Color(0xFF00821E);
  final Paint _p = Paint()..isAntiAlias = false;
  final Paint _img = Paint()..isAntiAlias = false..filterQuality = FilterQuality.none;
  final Path _path = Path();
  late Canvas c;

  void rect(double x, double y, double w, double h, Color col) {
    _p.style = PaintingStyle.fill;
    _p.color = col;
    c.drawRect(Rect.fromLTWH(x, y, w, h), _p);
  }

  void text(String s, double x, double baseY, double size, Color col, {bool shadow = false}) {
    void d(double ox, double oy, Color cc) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: cc, fontSize: size, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(x + ox, baseY + oy - size * 0.85));
    }

    if (shadow) d(1, 1, const Color(0x96000000));
    d(0, 0, col);
  }

  void sprite(ui.Image im, int sx, int sy, int sw, int sh, double px, double py, double rot, double fx, double fy,
      double ox, double oy) {
    c.save();
    c.translate(px, py);
    c.rotate(rot);
    c.scale(fx, fy);
    c.drawImageRect(im, Rect.fromLTWH(sx.toDouble(), sy.toDouble(), sw.toDouble(), sh.toDouble()),
        Rect.fromLTWH(-ox, -oy, sw.toDouble(), sh.toDouble()), _img);
    c.restore();
  }

  void quad(List<double> v) {
    _path.reset();
    _path.moveTo(v[0], v[1]);
    for (var i = 2; i < v.length; i += 2) {
      _path.lineTo(v[i], v[i + 1]);
    }
    _path.close();
    c.drawPath(_path, _p);
  }

  void drawBackground() {
    const bands = [Color(0xFF2878E6), Color(0xFF3C8CF0), Color(0xFF5AA5FA), Color(0xFF82C3FF), Color(0xFFAADCFF)];
    for (var i = 0; i < bands.length; i++) {
      rect(0, i * 48.0, VW.toDouble(), 48, bands[i]);
    }
    for (var sx = 0; sx <= VW; sx += 4) {
      final hy = 170 + 22 * sin((camX * 0.25 + sx) / 50) - camY * 0.15;
      rect(sx.toDouble(), hy, 4, VH - hy, const Color(0xFF28965A));
    }
    for (var sx = 0; sx <= VW; sx += 4) {
      final hy = 195 + 14 * sin((camX * 0.45 + sx) / 34 + 2) - camY * 0.3;
      rect(sx.toDouble(), hy, 4, VH - hy, const Color(0xFF14783C));
    }
  }

  void drawTerrain() {
    final cx = camX.floor(), cy = camY.floor();
    final x0 = (cx / 4).floor() * 4;
    for (var wx = x0; wx <= x0 + VW + 4; wx += 4) {
      if (wx < 0 || wx >= LW) continue;
      final top = hAt(wx + 2.0);
      if (top >= PIT) continue;
      final gx = (wx - cx).toDouble();
      final ytop = top.floor();
      final colx = (wx / 16).floor();
      var row = (ytop / 16).floor();
      var yy = ytop;
      final bottom = cy + VH;
      while (yy < bottom) {
        final ny = (row + 1) * 16;
        rect(gx, (yy - cy).toDouble(), 4, (ny - yy).toDouble(), ((colx + row) % 2 == 0) ? CA : CB);
        yy = ny;
        row++;
      }
      rect(gx, (ytop - cy).toDouble(), 4, 4, G1);
      rect(gx, (ytop + 4 - cy).toDouble(), 4, 3, G2);
    }
  }

  void drawLoops() {
    for (final L in loops) {
      final cx = L.cx - camX, cy = L.gy - L.R - camY;
      if (cx > -L.R - 40 && cx < VW + L.R + 40) {
        for (var k = 0; k < 60; k++) {
          final a0 = k * pi / 30, a1 = (k + 1) * pi / 30;
          final r0 = L.R, r1 = L.R + L.T;
          _p.style = PaintingStyle.fill;
          _p.color = k % 2 == 0 ? CA : CB;
          quad([
            cx + r0 * sin(a0), cy + r0 * cos(a0), cx + r1 * sin(a0), cy + r1 * cos(a0),
            cx + r1 * sin(a1), cy + r1 * cos(a1), cx + r0 * sin(a1), cy + r0 * cos(a1),
          ]);
        }
        _p.style = PaintingStyle.stroke;
        _p.strokeWidth = 1;
        _p.color = const Color(0xFF6D2400);
        c.drawCircle(Offset(cx, cy), L.R, _p);
        _p.style = PaintingStyle.fill;
      }
    }
  }

  void drawObjects() {
    for (final r in rings) {
      if (r.got) continue;
      final sx = r.x - camX, sy = r.y - camY;
      if (sx > -10 && sx < VW + 10) {
        final w = max(1.5, cos(tickN / 10 + r.x * 0.05).abs() * 6);
        _p.style = PaintingStyle.stroke;
        _p.strokeWidth = 2;
        _p.color = const Color(0xFFFFD700);
        c.drawOval(Rect.fromLTRB(sx - w, sy - 7, sx + w, sy + 7), _p);
        _p.style = PaintingStyle.fill;
      }
    }
    for (final s in spikes) {
      final sx = s.x - camX, sy = s.y - camY;
      _p.style = PaintingStyle.fill;
      _p.color = const Color(0xFFC8C8D2);
      for (var k = 0; k < 4; k++) {
        quad([sx + k * 8, sy, sx + k * 8 + 4, sy - 16, sx + k * 8 + 8, sy]);
      }
      rect(sx, sy - 2, 32, 2, const Color(0xFF5A5A64));
    }
    for (final s in springs) {
      final sx = s.x - camX, sy = s.y - camY;
      final comp = s.t > 0 ? 8.0 : 0.0;
      rect(sx + 4, sy - 6, 24, 6, const Color(0xFF9696A0));
      rect(sx + 2, sy - 16 + comp, 28, 6, s.red ? const Color(0xFFE62828) : const Color(0xFFFFD200));
      rect(sx + 12, sy - 10 + comp / 2, 8, 4, const Color(0xFFC8C8D2));
    }
    for (final ck in checks) {
      final sx = ck.x - camX, sy = ck.y - camY;
      rect(sx - 2, sy - 40, 4, 40, const Color(0xFFAAAAB4));
      _p.style = PaintingStyle.fill;
      _p.color = ck.on ? const Color(0xFFFF2828) : const Color(0xFF286EFF);
      c.drawCircle(Offset(sx, sy - 44), 6, _p);
    }
    final gx = goalX - camX, gy = hAt(goalX) - camY;
    rect(gx - 2, gy - 56, 4, 56, const Color(0xFFAAAAB4));
    rect(gx - 16, gy - 70, 32, 18, const Color(0xFFE63C3C));
    text('GOAL', gx - 13, gy - 57, 11, const Color(0xFFFFFFFF));
  }

  void drawSonic() {
    if (inv > 0 && (inv ~/ 3) % 2 == 0) return;
    final px = x.floorToDouble() - camX.floorToDouble();
    final py = y.floorToDouble() - camY.floorToDouble();
    final key = animKey;
    if (key == 'spin') {
      final f = af.floor() % 6;
      sprite(img.sdash, f * 32, 0, 32, 32, px, py, 0, facing.toDouble(), 1, 16, 16);
      return;
    }
    final list = anim[key]!;
    final n = list.length;
    final idx = holdLast.contains(key) ? min(af.floor(), n - 1) : af.floor() % n;
    final fr = list[idx];
    final sx = fr[1] * 48, sy = fr[0] * 48;
    if (key == 'roll' || key == 'drop') {
      sprite(img.atlas, sx, sy, 48, 48, px, py, 0, facing.toDouble(), 1, 24, 28);
    } else if (key == 'hurt' || key == 'die') {
      sprite(img.atlas, sx, sy, 48, 48, px, py + 19, 0, facing.toDouble(), 1, 24, 48);
    } else {
      var fx = px, fy = py + 19;
      if (loop != null) {
        fx = px + 19 * sin(theta);
        fy = py + 19 * cos(theta);
      }
      sprite(img.atlas, sx, sy, 48, 48, fx, fy, drawA, facing.toDouble(), 1, 24, 48);
    }
  }

  void drawHUD() {
    final spd = (grounded ? gsp : xsp).abs();
    text('RINGS $ringCount', 8, 18, 11, const Color(0xFFFFE632), shadow: true);
    text('SPEED ${spd.toStringAsFixed(2)}', 8, 32, 11, const Color(0xFFFFFFFF), shadow: true);
    text(langName, VW - 130.0, 18, 10, const Color(0xBEFFFFFF), shadow: true);
    if (goalT > 0) text('GOAL!', VW / 2 - 20, 90, 14, const Color(0xFFFFFFFF), shadow: true);
    if (dropReady) text('DROP DASH READY', VW / 2 - 60, 50, 11, const Color(0xFFFFFF50), shadow: true);
    var dx = 0.0, dy = 0.0;
    for (final t in touches.values) {
      if (t.dx < VW * 0.5) {
        dx = t.dx - 52;
        dy = t.dy - 188;
      }
    }
    var dirIdx = 0;
    if (dx * dx + dy * dy < 100 * 100 && (dx.abs() > 12 || dy.abs() > 14)) {
      dirIdx = dx.abs() >= dy.abs() ? (dx < 0 ? 1 : 3) : (dy > 0 ? 2 : 4);
    }
    final a = Paint()..filterQuality = FilterQuality.none..color = const Color(0xD9FFFFFF);
    c.drawImage(img.dpad[dirIdx], const Offset(20, 156), a);
    var jumpDown = false;
    for (final t in touches.values) {
      if (t.dx >= VW * 0.5 && t.dy > 40) jumpDown = true;
    }
    c.drawImage(img.btn[jumpDown ? 1 : 0], const Offset(340, 164), a);
    c.drawImage(img.pause, Offset(VW - 22.0, 26), _img);
  }

  void drawMenu() {
    drawBackground();
    rect(0, 190, VW.toDouble(), 50, CA);
    rect(0, 190, VW.toDouble(), 4, G1);
    text('SONIC MANIA', 100, 60, 32, const Color(0xFFFFFFFF), shadow: true);
    text('PHYSICS TEST', 112, 88, 22, const Color(0xFF50C8FF), shadow: true);
    final list = anim['max']!;
    final fr = list[(tickN ~/ 3) % list.length];
    sprite(img.atlas, fr[1] * 48, fr[0] * 48, 48, 48, VW / 2, 190, 0, 1.6, 1.6, 24, 48);
    text(langName, VW / 2 - 56, 115, 14, const Color(0xFFFFFFFF), shadow: true);
    if ((tickN ~/ 30) % 2 == 0) text('TAP TO START', VW / 2 - 66, 138, 16, const Color(0xFFFFFFFF), shadow: true);
    text('D-PAD: MOVE  A: JUMP  DOWN+A: SPIN DASH  JUMP + HOLD A: DROP DASH', 14, 230, 8, const Color(0xFFFFFFFF),
        shadow: true);
  }

  void draw(Canvas canvas, Size size) {
    c = canvas;
    _scale = min(size.width / VW, size.height / VH);
    _offX = (size.width - VW * _scale) / 2;
    _offY = (size.height - VH * _scale) / 2;
    c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000000));
    c.save();
    c.translate(_offX, _offY);
    c.scale(_scale, _scale);
    c.clipRect(Rect.fromLTWH(0, 0, VW.toDouble(), VH.toDouble()));
    if (mode == 0) {
      drawMenu();
    } else {
      drawBackground();
      drawTerrain();
      drawLoops();
      drawObjects();
      drawSonic();
      drawHUD();
    }
    c.restore();
  }
}
