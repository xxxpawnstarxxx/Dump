"use client"

/**
 * ParticleBackground — a single-file, engine-grade particle web system.
 *
 * Optimizations (CPU-bound Canvas 2D, tuned to near-optimal):
 *   - True Struct-of-Arrays: separate flat Float32Arrays remove all `i*STRIDE` math
 *   - Spatial-hash grid via head/next Int32Array linked lists → O(n) connections
 *   - Per-particle cell cached during physics, reused in the connection pass
 *     (no empty-cell sweeping, no grid-coordinate re-derivation)
 *   - Zero Math.sqrt in line connections (alpha from squared-distance ratio)
 *   - Pre-computed inverse constants → multiplies instead of divides in hot loops
 *   - Branchless alpha-bucket indexing + batched line strokes (one stroke/bucket)
 *   - Pre-rendered radial-glow sprite drawn via drawImage (no per-particle arcs)
 *   - Mouse/touch repulsion + reactive cursor lines, DPR-aware, resize-preserving
 *   - IntersectionObserver + visibility halt the RAF loop entirely when offscreen
 *
 * Drop it anywhere as a fixed/absolute background layer.
 */

import { useEffect, useRef } from "react"

// ==================== TUNABLE CONSTANTS ====================
const MAX_PARTICLES = 2500
const DENSITY_DIVISOR = 10000 // 1 particle per N screen pixels
const MIN_PARTICLES = 50

const CONNECT_DIST = 130
const CONNECT_DIST_SQ = CONNECT_DIST * CONNECT_DIST
const INV_CONNECT_DIST_SQ = 1 / CONNECT_DIST_SQ

const REPEL_DIST = 180
const REPEL_DIST_SQ = REPEL_DIST * REPEL_DIST
const INV_REPEL_DIST = 1 / REPEL_DIST
const REPEL_STRENGTH = 1.5

const RETURN_EASE = 0.02 // how strongly particles drift back to base velocity
const MAX_SPEED = 3
const MAX_SPEED_SQ = MAX_SPEED * MAX_SPEED

const GRID_SIZE = CONNECT_DIST
const INV_GRID_SIZE = 1 / GRID_SIZE
const MAX_GRID_CELLS = 40000

const BATCH_COUNT = 10 // number of alpha buckets for line batching
const BATCH_MAX_IDX = BATCH_COUNT - 1
const MAX_BATCH_FLOATS = 60000 // floats per bucket (4 per line segment)

type Props = {
  /** Optional className for the canvas element. */
  className?: string
}

export default function ParticleBackground({ className }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    const ctx = canvas.getContext("2d", {
      alpha: false,
      desynchronized: true,
      willReadFrequently: false,
    })
    if (!ctx) return

    // ---- Mutable per-instance state (kept out of React to avoid re-renders) ----
    const mouse = { x: -9999, y: -9999 }
    let width = window.innerWidth
    let height = window.innerHeight
    let activeCount = 0
    let cols = 0
    let rows = 0
    let animId = 0
    let running = true
    let onScreen = true

    // ---- True Struct-of-Arrays storage (allocated once) ----
    const pX = new Float32Array(MAX_PARTICLES)
    const pY = new Float32Array(MAX_PARTICLES)
    const pVX = new Float32Array(MAX_PARTICLES)
    const pVY = new Float32Array(MAX_PARTICLES)
    const pBVX = new Float32Array(MAX_PARTICLES)
    const pBVY = new Float32Array(MAX_PARTICLES)
    const pCX = new Int32Array(MAX_PARTICLES) // cached grid column
    const pCY = new Int32Array(MAX_PARTICLES) // cached grid row

    // ---- Spatial-hash linked lists ----
    const next = new Int32Array(MAX_PARTICLES)
    const head = new Int32Array(MAX_GRID_CELLS)

    // ---- Batched line render buffers ----
    const batchData: Float32Array[] = Array.from(
      { length: BATCH_COUNT },
      () => new Float32Array(MAX_BATCH_FLOATS),
    )
    const batchCounts = new Int32Array(BATCH_COUNT)

    // ---- Pre-rendered glow sprite ----
    const sprite = document.createElement("canvas")
    sprite.width = 8
    sprite.height = 8
    const sCtx = sprite.getContext("2d")
    if (sCtx) {
      const glow = sCtx.createRadialGradient(4, 4, 0, 4, 4, 4)
      glow.addColorStop(0, "rgba(255, 255, 255, 1)")
      glow.addColorStop(0.3, "rgba(140, 160, 255, 0.8)")
      glow.addColorStop(1, "rgba(140, 160, 255, 0)")
      sCtx.fillStyle = glow
      sCtx.fillRect(0, 0, 8, 8)
    }

    // ---- Background gradient (recreated on resize) ----
    let bgGradient = ctx.createLinearGradient(0, 0, width, height)
    const buildGradient = () => {
      bgGradient = ctx.createLinearGradient(0, 0, width, height)
      bgGradient.addColorStop(0, "#0a0a1a")
      bgGradient.addColorStop(0.5, "#0d1b2a")
      bgGradient.addColorStop(1, "#0a0a1a")
    }

    const targetCount = (w: number, h: number) => {
      const c = Math.floor((w * h) / DENSITY_DIVISOR)
      return Math.min(Math.max(c, MIN_PARTICLES), MAX_PARTICLES)
    }

    const initParticles = (w: number, h: number, preserve = false) => {
      const count = targetCount(w, h)
      const start = preserve ? activeCount : 0
      for (let i = start; i < count; i++) {
        pX[i] = Math.random() * w
        pY[i] = Math.random() * h
        const bvx = (Math.random() - 0.5) * 1.5
        const bvy = (Math.random() - 0.5) * 1.5
        pVX[i] = bvx
        pVY[i] = bvy
        pBVX[i] = bvx
        pBVY[i] = bvy
      }
      return count
    }

    const applySize = (preserve: boolean) => {
      width = window.innerWidth
      height = window.innerHeight
      const dpr = Math.min(window.devicePixelRatio || 1, 2)

      // Backing store scaled by DPR; CSS size stays in logical pixels.
      canvas.width = Math.floor(width * dpr)
      canvas.height = Math.floor(height * dpr)
      canvas.style.width = width + "px"
      canvas.style.height = height + "px"
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)

      cols = Math.ceil(width * INV_GRID_SIZE)
      rows = Math.ceil(height * INV_GRID_SIZE)
      // Guard against pathological grid sizes blowing past the head buffer.
      if (cols * rows > MAX_GRID_CELLS) {
        cols = Math.floor(Math.sqrt(MAX_GRID_CELLS * (width / height)))
        rows = Math.floor(MAX_GRID_CELLS / cols)
      }

      activeCount = initParticles(width, height, preserve)
      buildGradient()
    }

    applySize(false)

    // ---- Helper: test a candidate against (x1,y1) and bucket the line (no sqrt) ----
    const tryConnect = (x1: number, y1: number, p2: number) => {
      const dx = x1 - pX[p2]
      const dy = y1 - pY[p2]
      const distSq = dx * dx + dy * dy
      if (distSq < CONNECT_DIST_SQ && distSq > 1) {
        // Fade derived from squared distance — avoids Math.sqrt entirely.
        const alpha = 1 - distSq * INV_CONNECT_DIST_SQ
        const b = (alpha * BATCH_MAX_IDX) | 0 // branchless, always in range
        const bc = batchCounts[b]
        if (bc < MAX_BATCH_FLOATS - 4) {
          const bd = batchData[b]
          bd[bc] = x1
          bd[bc + 1] = y1
          bd[bc + 2] = pX[p2]
          bd[bc + 3] = pY[p2]
          batchCounts[b] = bc + 4
        }
      }
    }

    // ---- Helper: walk a neighboring cell's linked list ----
    const connectCell = (x1: number, y1: number, nx: number, ny: number) => {
      if (nx < 0 || nx >= cols || ny >= rows) return
      let p2 = head[ny * cols + nx]
      while (p2 !== -1) {
        tryConnect(x1, y1, p2)
        p2 = next[p2]
      }
    }

    // ==================== RENDER FRAME ====================
    const draw = () => {
      ctx.fillStyle = bgGradient
      ctx.fillRect(0, 0, width, height)

      batchCounts.fill(0)
      head.fill(-1, 0, cols * rows)

      const mx = mouse.x
      const my = mouse.y

      // ---- 1. Physics + spatial-grid insertion (cell cached per particle) ----
      for (let i = 0; i < activeCount; i++) {
        let x = pX[i]
        let y = pY[i]
        let vx = pVX[i]
        let vy = pVY[i]

        const dx = x - mx
        const dy = y - my
        const distSq = dx * dx + dy * dy

        if (distSq < REPEL_DIST_SQ && distSq > 0) {
          const dist = Math.sqrt(distSq)
          const invDist = 1 / dist
          // Fused repel force: (1/dist - 1/REPEL_DIST) * strength.
          const f = (invDist - INV_REPEL_DIST) * REPEL_STRENGTH
          vx += dx * f
          vy += dy * f

          // Reactive line from particle to cursor, bucketed by intensity.
          const alpha = 1 - dist * INV_REPEL_DIST
          const b = (alpha * BATCH_MAX_IDX) | 0
          const bc = batchCounts[b]
          if (bc < MAX_BATCH_FLOATS - 4) {
            const bd = batchData[b]
            bd[bc] = x
            bd[bc + 1] = y
            bd[bc + 2] = mx
            bd[bc + 3] = my
            batchCounts[b] = bc + 4
          }
        }

        // Ease back toward base velocity, clamp speed.
        vx += (pBVX[i] - vx) * RETURN_EASE
        vy += (pBVY[i] - vy) * RETURN_EASE
        const speedSq = vx * vx + vy * vy
        if (speedSq > MAX_SPEED_SQ) {
          const s = MAX_SPEED / Math.sqrt(speedSq)
          vx *= s
          vy *= s
        }

        x += vx
        y += vy

        // Wrap around edges.
        if (x < 0) x += width
        else if (x > width) x -= width
        if (y < 0) y += height
        else if (y > height) y -= height

        pX[i] = x
        pY[i] = y
        pVX[i] = vx
        pVY[i] = vy

        // Cache grid cell, then insert into the per-cell linked list.
        let cx = (x * INV_GRID_SIZE) | 0
        let cy = (y * INV_GRID_SIZE) | 0
        if (cx < 0) cx = 0
        else if (cx >= cols) cx = cols - 1
        if (cy < 0) cy = 0
        else if (cy >= rows) cy = rows - 1
        pCX[i] = cx
        pCY[i] = cy
        const cell = cy * cols + cx
        next[i] = head[cell]
        head[cell] = i
      }

      // ---- 2. Connections: own cell (forward) + 4 forward neighbors ----
      // Iterating particles (not cells) skips empty cells; cached cx/cy avoids
      // re-deriving grid coordinates. Each pair is visited exactly once.
      for (let i = 0; i < activeCount; i++) {
        const x1 = pX[i]
        const y1 = pY[i]
        const cx = pCX[i]
        const cy = pCY[i]

        // Same cell — only nodes later in the linked list (forward-only).
        let p2 = next[i]
        while (p2 !== -1) {
          tryConnect(x1, y1, p2)
          p2 = next[p2]
        }

        // Forward neighbor cells (covers each neighbor pair once).
        connectCell(x1, y1, cx + 1, cy)
        connectCell(x1, y1, cx - 1, cy + 1)
        connectCell(x1, y1, cx, cy + 1)
        connectCell(x1, y1, cx + 1, cy + 1)
      }

      // ---- 3. Render batched connection lines ----
      ctx.strokeStyle = "rgb(120, 140, 255)"
      ctx.lineWidth = 1
      for (let b = 0; b < BATCH_COUNT; b++) {
        const count = batchCounts[b]
        if (count === 0) continue
        const bd = batchData[b]
        ctx.beginPath()
        for (let k = 0; k < count; k += 4) {
          ctx.moveTo(bd[k], bd[k + 1])
          ctx.lineTo(bd[k + 2], bd[k + 3])
        }
        ctx.globalAlpha = (b + 1) / BATCH_COUNT
        ctx.stroke()
      }

      // ---- 4. Render particle glows ----
      ctx.globalAlpha = 1
      for (let i = 0; i < activeCount; i++) {
        ctx.drawImage(sprite, (pX[i] - 4) | 0, (pY[i] - 4) | 0)
      }
    }

    // ==================== LOOP CONTROL ====================
    const loop = () => {
      draw()
      animId = requestAnimationFrame(loop)
    }
    const start = () => {
      if (running && onScreen && !animId) animId = requestAnimationFrame(loop)
    }
    const stop = () => {
      if (animId) {
        cancelAnimationFrame(animId)
        animId = 0
      }
    }

    // ==================== EVENT HANDLERS ====================
    const onMove = (e: MouseEvent) => {
      mouse.x = e.clientX
      mouse.y = e.clientY
    }
    const onTouch = (e: TouchEvent) => {
      const t = e.touches[0]
      if (t) {
        mouse.x = t.clientX
        mouse.y = t.clientY
      }
    }
    const onLeave = () => {
      mouse.x = -9999
      mouse.y = -9999
    }
    const onResize = () => applySize(true)
    const onVisibility = () => {
      running = document.visibilityState === "visible"
      running ? start() : stop()
    }

    window.addEventListener("resize", onResize)
    window.addEventListener("mousemove", onMove, { passive: true })
    window.addEventListener("mouseout", onLeave, { passive: true })
    window.addEventListener("touchmove", onTouch, { passive: true })
    window.addEventListener("touchend", onLeave, { passive: true })
    document.addEventListener("visibilitychange", onVisibility)

    // Halt the RAF loop entirely when scrolled offscreen (0% CPU/GPU).
    const observer = new IntersectionObserver(
      ([entry]) => {
        onScreen = entry.isIntersecting
        onScreen ? start() : stop()
      },
      { threshold: 0.01 },
    )
    observer.observe(canvas)

    start()

    return () => {
      stop()
      observer.disconnect()
      window.removeEventListener("resize", onResize)
      window.removeEventListener("mousemove", onMove)
      window.removeEventListener("mouseout", onLeave)
      window.removeEventListener("touchmove", onTouch)
      window.removeEventListener("touchend", onLeave)
      document.removeEventListener("visibilitychange", onVisibility)
    }
  }, [])

  return (
    <canvas
      ref={canvasRef}
      aria-hidden="true"
      className={className ?? "block h-full w-full"}
    />
  )
}
