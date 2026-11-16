package com.sonicphysics

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView

/** SurfaceView + fixed 60 Hz game thread. The game renders into a 424x240 bitmap that is scaled up. */
class GameView(ctx: Context) : SurfaceView(ctx), SurfaceHolder.Callback {
    private val game = Game(ctx)
    private val vbmp = Bitmap.createBitmap(VW, VH, Bitmap.Config.ARGB_8888)
    private val vcanvas = Canvas(vbmp)
    private val blit = Paint().apply { isFilterBitmap = false; isAntiAlias = false }
    private var thread: Thread? = null
    @Volatile private var running = false
    private var surfaceReady = false
    private var scale = 1f
    private var offX = 0f
    private var offY = 0f

    init { holder.addCallback(this) }

    override fun surfaceCreated(h: SurfaceHolder) { surfaceReady = true; startLoop() }
    override fun surfaceChanged(h: SurfaceHolder, f: Int, w: Int, hh: Int) {}
    override fun surfaceDestroyed(h: SurfaceHolder) { surfaceReady = false; stopLoop() }

    fun startLoop() {
        if (running || !surfaceReady) return
        running = true
        thread = Thread {
            val step = 1_000_000_000L / 60
            var last = System.nanoTime()
            var acc = 0L
            while (running) {
                val now = System.nanoTime()
                acc += minOf(now - last, 100_000_000L)
                last = now
                while (acc >= step) { acc -= step; game.tick() }
                val c = holder.lockCanvas()
                if (c == null) { try { Thread.sleep(10) } catch (_: InterruptedException) {}; continue }
                try {
                    game.draw(vcanvas)
                    val w = c.width.toFloat(); val h = c.height.toFloat()
                    scale = minOf(w / VW, h / VH)
                    offX = (w - VW * scale) / 2f; offY = (h - VH * scale) / 2f
                    c.drawColor(Color.BLACK)
                    c.drawBitmap(vbmp, null, RectF(offX, offY, offX + VW * scale, offY + VH * scale), blit)
                } finally { holder.unlockCanvasAndPost(c) }
                try { Thread.sleep(4) } catch (_: InterruptedException) {}
            }
        }.also { it.start() }
    }

    fun stopLoop() {
        running = false
        thread?.join(500)
        thread = null
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        val act = e.actionMasked
        when (act) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = e.actionIndex
                game.touchDown(e.getPointerId(i), (e.getX(i) - offX) / scale, (e.getY(i) - offY) / scale)
            }
            MotionEvent.ACTION_MOVE -> for (i in 0 until e.pointerCount)
                game.touchMove(e.getPointerId(i), (e.getX(i) - offX) / scale, (e.getY(i) - offY) / scale)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> game.touchUp(e.getPointerId(e.actionIndex))
            MotionEvent.ACTION_CANCEL -> game.touchesClear()
        }
        return true
    }
}
