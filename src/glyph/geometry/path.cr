# src/glyph/geometry/path.cr
module Glyph
  module Path
    MAX_SEGMENTS = 32

    def self.flatten(outline : Outline, tf : Transform) : Array(Array(Float64))
      contours = [] of Array(Float64)
      return contours if outline.empty?
      tolerance = 0.2 / Math.max(tf.magnitude, 1e-9)
      start     = 0
      outline.ends.each do |last|
        n = last - start + 1
        if n >= 2
          poly = [] of Float64
          walk(outline.points, start, n, tf, tolerance, poly)
          contours << poly if poly.size >= 6
        end
        start = last + 1
      end
      contours
    end

    private def self.walk(points : Slice(Point), start : Int32, n : Int32,
                          tf : Transform, tolerance : Float64, sink : Array(Float64)) : Nil
      first_on = -1
      i        = 0
      while i < n
        if points.unsafe_fetch(start + i).on_curve?
          first_on = i
          break
        end
        i += 1
      end

      if first_on >= 0
        p        = points.unsafe_fetch(start + first_on)
        sx       = tf.apply_x(p.x.to_f, p.y.to_f)
        sy       = tf.apply_y(p.x.to_f, p.y.to_f)
        begin_at = first_on + 1
      else
        a        = points.unsafe_fetch(start + n - 1)
        b        = points.unsafe_fetch(start)
        mx       = (a.x + b.x) * 0.5
        my       = (a.y + b.y) * 0.5
        sx       = tf.apply_x(mx, my)
        sy       = tf.apply_y(mx, my)
        begin_at = 0
      end

      sink << sx << sy
      cx        = sx
      cy        = sy
      have_ctrl = false
      qx        = 0.0
      qy        = 0.0

      k = 0
      while k < n
        idx = (begin_at + k) % n
        p   = points.unsafe_fetch(start + idx)
        px  = tf.apply_x(p.x.to_f, p.y.to_f)
        py  = tf.apply_y(p.x.to_f, p.y.to_f)
        if p.on_curve?
          if have_ctrl
            quad(sink, cx, cy, qx, qy, px, py, tolerance)
            have_ctrl = false
          else
            sink << px << py
          end
          cx = px
          cy = py
        else
          if have_ctrl
            mx = (qx + px) * 0.5
            my = (qy + py) * 0.5
            quad(sink, cx, cy, qx, qy, mx, my, tolerance)
            cx = mx
            cy = my
          end
          qx        = px
          qy        = py
          have_ctrl = true
        end
        k += 1
      end

      quad(sink, cx, cy, qx, qy, sx, sy, tolerance) if have_ctrl
    end

    private def self.quad(sink : Array(Float64), x0 : Float64, y0 : Float64,
                          cx : Float64, cy : Float64, x1 : Float64, y1 : Float64,
                          tolerance : Float64) : Nil
      dx   = cx - (x0 + x1) * 0.5
      dy   = cy - (y0 + y1) * 0.5
      dev  = Math.sqrt(dx * dx + dy * dy)
      segs = dev <= tolerance ? 1 : (Math.sqrt(dev / tolerance) * 2.0).ceil.to_i
      segs = 1 if segs < 1
      segs = MAX_SEGMENTS if segs > MAX_SEGMENTS
      i    = 1
      while i <= segs
        t  = i.to_f / segs
        mt = 1.0 - t
        wa = mt * mt
        wb = 2.0 * mt * t
        wc = t * t
        sink << x0 * wa + cx * wb + x1 * wc
        sink << y0 * wa + cy * wb + y1 * wc
        i += 1
      end
    end
  end
end
