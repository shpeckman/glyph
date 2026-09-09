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
      cx = sx
      cy = sy

      q1  = false
      q1x = 0.0
      q1y = 0.0
      q2  = false
      q2x = 0.0
      q2y = 0.0

      k = 0
      while k < n
        idx = (begin_at + k) % n
        p   = points.unsafe_fetch(start + idx)
        px  = tf.apply_x(p.x.to_f, p.y.to_f)
        py  = tf.apply_y(p.x.to_f, p.y.to_f)

        case p.type
        when .on_curve?
          if q1
            if q2
              cubic(sink, cx, cy, q1x, q1y, q2x, q2y, px, py, tolerance)
              q2 = false
            else
              quad(sink, cx, cy, q1x, q1y, px, py, tolerance)
            end
            q1 = false
          else
            sink << px << py
          end
          cx = px
          cy = py
        when .quad?
          if q1
            mx = (q1x + px) * 0.5
            my = (q1y + py) * 0.5
            quad(sink, cx, cy, q1x, q1y, mx, my, tolerance)
            cx = mx
            cy = my
          end
          q1x = px
          q1y = py
          q1  = true
          q2  = false
        when .cubic?
          if q1
            q2x = px
            q2y = py
            q2  = true
          else
            q1x = px
            q1y = py
            q1  = true
            q2  = false
          end
        end
        k += 1
      end

      if q1
        if q2
          cubic(sink, cx, cy, q1x, q1y, q2x, q2y, sx, sy, tolerance)
        else
          quad(sink, cx, cy, q1x, q1y, sx, sy, tolerance)
        end
      end
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

    private def self.cubic(sink : Array(Float64), x0 : Float64, y0 : Float64,
                           cx1 : Float64, cy1 : Float64, cx2 : Float64, cy2 : Float64,
                           x1 : Float64, y1 : Float64, tolerance : Float64) : Nil
      split_cubic(sink, x0, y0, cx1, cy1, cx2, cy2, x1, y1, tolerance, 0)
    end

    private def self.split_cubic(sink : Array(Float64), x0 : Float64, y0 : Float64,
                                 cx1 : Float64, cy1 : Float64, cx2 : Float64, cy2 : Float64,
                                 x1 : Float64, y1 : Float64, tolerance : Float64, depth : Int32) : Nil
      if depth >= MAX_SEGMENTS
        sink << x1 << y1
        return
      end

      dx   = x1 - x0
      dy   = y1 - y0
      len2 = dx * dx + dy * dy

      dev1 = 0.0
      dev2 = 0.0
      if len2 > 1e-9
        dev1 = ((cx1 - x0) * dy - (cy1 - y0) * dx).abs / Math.sqrt(len2)
        dev2 = ((cx2 - x0) * dy - (cy2 - y0) * dx).abs / Math.sqrt(len2)
      else
        dev1 = Math.sqrt((cx1 - x0)**2 + (cy1 - y0)**2)
        dev2 = Math.sqrt((cx2 - x0)**2 + (cy2 - y0)**2)
      end

      if dev1 <= tolerance && dev2 <= tolerance
        sink << x1 << y1
        return
      end

      mx0 = (x0 + cx1) * 0.5
      my0 = (y0 + cy1) * 0.5
      mx1 = (cx1 + cx2) * 0.5
      my1 = (cy1 + cy2) * 0.5
      mx2 = (cx2 + x1) * 0.5
      my2 = (cy2 + y1) * 0.5

      qx0 = (mx0 + mx1) * 0.5
      qy0 = (my0 + my1) * 0.5
      qx1 = (mx1 + mx2) * 0.5
      qy1 = (my1 + my2) * 0.5

      bx = (qx0 + qx1) * 0.5
      by = (qy0 + qy1) * 0.5

      split_cubic(sink, x0, y0, mx0, my0, qx0, qy0, bx, by, tolerance, depth + 1)
      split_cubic(sink, bx, by, qx1, qy1, mx2, my2, x1, y1, tolerance, depth + 1)
    end
  end
end
