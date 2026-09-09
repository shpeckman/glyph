# src/glyph.cr
module Glyph
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}

  MAX_SLOTS      =  1024
  DECODED_BUDGET = 65536
  POINT_COST     =    12
  MAX_POINTS     = DECODED_BUDGET // POINT_COST
  MAX_PAYLOAD    =      65536
  MAX_CONTAINER  =       1024
  MAX_DEPTH      =         64
  DEFAULT_UPM    =       1000
  FOREGROUND     = 0xFFFF_u16

  PUA_RANGES = { {0xE000, 0xF8FF}, {0xF0000, 0xFFFFD}, {0x100000, 0x10FFFD} }

  def self.pua?(cp : Int32) : Bool
    PUA_RANGES.each do |range|
      lo, hi = range
      return true if cp >= lo && cp <= hi
    end
    false
  end

  enum Reason
    OutOfNamespace
    CompositeUnsupported
    HintingUnsupported
    MalformedPayload
    PayloadTooLarge
    OutlineTooLarge

    def code : String
      case self
      in .out_of_namespace?      then "out_of_namespace"
      in .composite_unsupported? then "composite_unsupported"
      in .hinting_unsupported?   then "hinting_unsupported"
      in .malformed_payload?     then "malformed_payload"
      in .payload_too_large?     then "payload_too_large"
      in .outline_too_large?     then "outline_too_large"
      end
    end
  end

  class Error < Exception
    getter reason : Reason

    def initialize(@reason : Reason)
      super(@reason.code)
    end
  end

  enum Format
    Glyf
    Colrv0
    Colrv1

    def code : String
      case self
      in .glyf?   then "glyf"
      in .colrv0? then "colrv0"
      in .colrv1? then "colrv1"
      end
    end

    def self.from_code?(name : String) : Format?
      case name
      when "glyf"   then Glyf
      when "colrv0" then Colrv0
      when "colrv1" then Colrv1
      end
    end
  end

  enum SizeMode
    Height
    Advance
    Contain
    Cover
    Stretch
  end

  enum HAlign
    Start
    Center
    End
  end

  enum VAlign
    Start
    Center
    End
    Baseline
  end

  enum Extend
    Pad
    Repeat
    Reflect
  end

  @[Flags]
  enum Coverage
    System
    Glossary

    def code : String
      names = [] of String
      names << "system" if system?
      names << "glossary" if glossary?
      names.join(',')
    end
  end

  struct Pad
    getter top    : Float64
    getter right  : Float64
    getter bottom : Float64
    getter left   : Float64

    def initialize(@top : Float64 = 0.0, @right : Float64 = 0.0,
                   @bottom : Float64 = 0.0, @left : Float64 = 0.0)
    end

    def self.none : Pad
      Pad.new
    end

    def degenerate? : Bool
      return true if @top < 0 || @right < 0 || @bottom < 0 || @left < 0
      @left + @right >= 1.0 || @top + @bottom >= 1.0
    end
  end

  struct Metrics
    getter upm : Int32
    getter aw  : Int32
    getter lh  : Int32

    def initialize(upm : Int32 = DEFAULT_UPM, aw : Int32? = nil, lh : Int32? = nil)
      @upm = upm > 0 ? upm : DEFAULT_UPM
      @aw  = aw || @upm
      @lh  = lh || @upm
    end
  end

  struct Point
    getter x         : Int32
    getter y         : Int32
    getter? on_curve : Bool

    def initialize(@x : Int32, @y : Int32, @on_curve : Bool)
    end
  end

  struct Outline
    getter points : Slice(Point)
    getter ends   : Slice(Int32)
    getter x_min  : Int32
    getter y_min  : Int32
    getter x_max  : Int32
    getter y_max  : Int32

    def initialize(@points : Slice(Point), @ends : Slice(Int32),
                   @x_min : Int32, @y_min : Int32, @x_max : Int32, @y_max : Int32)
    end

    def self.blank(x_min = 0, y_min = 0, x_max = 0, y_max = 0) : Outline
      new(Slice(Point).empty, Slice(Int32).empty, x_min, y_min, x_max, y_max)
    end

    def empty? : Bool
      @ends.empty?
    end

    def point_count : Int32
      @points.size
    end
  end

  struct Transform
    getter a : Float64
    getter b : Float64
    getter c : Float64
    getter d : Float64
    getter e : Float64
    getter f : Float64

    def initialize(@a : Float64, @b : Float64, @c : Float64,
                   @d : Float64, @e : Float64, @f : Float64)
    end

    def self.identity : Transform
      new(1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
    end

    def self.translate(dx : Float64, dy : Float64) : Transform
      new(1.0, 0.0, 0.0, 1.0, dx, dy)
    end

    def self.scale(sx : Float64, sy : Float64) : Transform
      new(sx, 0.0, 0.0, sy, 0.0, 0.0)
    end

    def self.rotate(radians : Float64) : Transform
      cs = Math.cos(radians)
      sn = Math.sin(radians)
      new(cs, sn, -sn, cs, 0.0, 0.0)
    end

    def self.skew(x_radians : Float64, y_radians : Float64) : Transform
      new(1.0, Math.tan(y_radians), -Math.tan(x_radians), 1.0, 0.0, 0.0)
    end

    def apply_x(x : Float64, y : Float64) : Float64
      @a * x + @c * y + @e
    end

    def apply_y(x : Float64, y : Float64) : Float64
      @b * x + @d * y + @f
    end

    def concat(inner : Transform) : Transform
      Transform.new(
        @a * inner.a + @c * inner.b,
        @b * inner.a + @d * inner.b,
        @a * inner.c + @c * inner.d,
        @b * inner.c + @d * inner.d,
        @a * inner.e + @c * inner.f + @e,
        @b * inner.e + @d * inner.f + @f)
    end

    def around(cx : Float64, cy : Float64) : Transform
      Transform.translate(cx, cy).concat(self).concat(Transform.translate(-cx, -cy))
    end

    def magnitude : Float64
      Math.sqrt((@a * @d - @b * @c).abs)
    end

    def invert : Transform?
      det = @a * @d - @b * @c
      return nil if det.abs < 1e-12
      ia = @d / det
      ib = -@b / det
      ic = -@c / det
      id = @a / det
      Transform.new(ia, ib, ic, id, -(ia * @e + ic * @f), -(ib * @e + id * @f))
    end
  end

  class Reader
    getter pos : Int32

    def initialize(@bytes : Bytes)
      @pos = 0
    end

    def size : Int32
      @bytes.size
    end

    def seek(pos : Int32) : Nil
      raise Error.new(Reason::MalformedPayload) if pos < 0 || pos > @bytes.size
      @pos = pos
    end

    def remaining : Int32
      @bytes.size - @pos
    end

    def u8 : UInt8
      need(1)
      v = @bytes.unsafe_fetch(@pos)
      @pos += 1
      v
    end

    def u16 : UInt16
      need(2)
      v = (@bytes.unsafe_fetch(@pos).to_u16 << 8) | @bytes.unsafe_fetch(@pos + 1).to_u16
      @pos += 2
      v
    end

    def i16 : Int32
      v = u16.to_i32
      v >= 0x8000 ? v - 0x10000 : v
    end

    def u24 : Int32
      need(3)
      v = (@bytes.unsafe_fetch(@pos).to_i32 << 16) |
          (@bytes.unsafe_fetch(@pos + 1).to_i32 << 8) |
          @bytes.unsafe_fetch(@pos + 2).to_i32
      @pos += 3
      v
    end

    def u32 : UInt32
      need(4)
      v = (@bytes.unsafe_fetch(@pos).to_u32 << 24) |
          (@bytes.unsafe_fetch(@pos + 1).to_u32 << 16) |
          (@bytes.unsafe_fetch(@pos + 2).to_u32 << 8) |
          @bytes.unsafe_fetch(@pos + 3).to_u32
      @pos += 4
      v
    end

    def f2dot14 : Float64
      i16 / 16384.0
    end

    def fixed : Float64
      v = u32.to_i64
      v -= 0x100000000_i64 if v >= 0x80000000_i64
      v / 65536.0
    end

    def slice(len : Int32) : Bytes
      raise Error.new(Reason::MalformedPayload) if len < 0
      need(len)
      v = @bytes[@pos, len]
      @pos += len
      v
    end

    private def need(n : Int32) : Nil
      raise Error.new(Reason::MalformedPayload) if @pos + n > @bytes.size
    end
  end

  module Glyf
    ON_CURVE = 0x01_u8
    X_SHORT  = 0x02_u8
    Y_SHORT  = 0x04_u8
    REPEAT   = 0x08_u8
    X_SAME   = 0x10_u8
    Y_SAME   = 0x20_u8

    def self.parse(bytes : Bytes) : Outline
      raise Error.new(Reason::PayloadTooLarge) if bytes.size > MAX_PAYLOAD
      parse(Reader.new(bytes))
    end

    def self.parse(r : Reader) : Outline
      n_contours = r.i16
      raise Error.new(Reason::CompositeUnsupported) if n_contours < 0
      x_min = r.i16
      y_min = r.i16
      x_max = r.i16
      y_max = r.i16
      return Outline.blank(x_min, y_min, x_max, y_max) if n_contours == 0

      ends = Slice(Int32).new(n_contours)
      prev = -1
      i    = 0
      while i < n_contours
        e = r.u16.to_i32
        raise Error.new(Reason::MalformedPayload) if e <= prev
        ends[i] = e
        prev = e
        i += 1
      end

      n_points = prev + 1
      raise Error.new(Reason::OutlineTooLarge) if n_points > MAX_POINTS
      raise Error.new(Reason::HintingUnsupported) if r.u16 != 0

      flags = Bytes.new(n_points)
      i     = 0
      while i < n_points
        flag = r.u8
        flags[i] = flag
        i += 1
        next if (flag & REPEAT) == 0
        rep = r.u8.to_i32
        raise Error.new(Reason::MalformedPayload) if i + rep > n_points
        k = 0
        while k < rep
          flags[i] = flag
          i += 1
          k += 1
        end
      end

      points = Slice(Point).new(n_points, Point.new(0, 0, false))
      v      = 0
      i      = 0
      while i < n_points
        flag = flags.unsafe_fetch(i)
        if (flag & X_SHORT) != 0
          d = r.u8.to_i32
          v += (flag & X_SAME) != 0 ? d : -d
        elsif (flag & X_SAME) == 0
          v += r.i16
        end
        points[i] = Point.new(v, 0, (flag & ON_CURVE) != 0)
        i += 1
      end

      v = 0
      i = 0
      while i < n_points
        flag = flags.unsafe_fetch(i)
        if (flag & Y_SHORT) != 0
          d = r.u8.to_i32
          v += (flag & Y_SAME) != 0 ? d : -d
        elsif (flag & Y_SAME) == 0
          v += r.i16
        end
        p = points.unsafe_fetch(i)
        points[i] = Point.new(p.x, v, p.on_curve?)
        i += 1
      end

      Outline.new(points, ends, x_min, y_min, x_max, y_max)
    end
  end

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

  module Fill
    SUBSAMPLES = 4

    private struct Edge
      getter x0    : Float64
      getter y0    : Float64
      getter y1    : Float64
      getter slope : Float64
      getter dir   : Int32

      def initialize(@x0 : Float64, @y0 : Float64, @y1 : Float64,
                     @slope : Float64, @dir : Int32)
      end
    end

    def self.coverage(contours : Array(Array(Float64)), width : Int32, height : Int32) : Slice(Float32)
      cov   = Slice(Float32).new(width * height, 0.0_f32)
      edges = [] of Edge
      contours.each do |poly|
        n = poly.size // 2
        next if n < 3
        i = 0
        while i < n
          j  = (i + 1) % n
          ax = poly.unsafe_fetch(i * 2)
          ay = poly.unsafe_fetch(i * 2 + 1)
          bx = poly.unsafe_fetch(j * 2)
          by = poly.unsafe_fetch(j * 2 + 1)
          if ay < by
            edges << Edge.new(ax, ay, by, (bx - ax) / (by - ay), 1)
          elsif by < ay
            edges << Edge.new(bx, by, ay, (ax - bx) / (ay - by), -1)
          end
          i += 1
        end
      end
      return cov if edges.empty?

      amount    = (1.0 / SUBSAMPLES).to_f32
      crossings = [] of Tuple(Float64, Int32)
      y         = 0
      while y < height
        row = y * width
        s   = 0
        while s < SUBSAMPLES
          sy = y + (s + 0.5) / SUBSAMPLES
          crossings.clear
          edges.each do |ed|
            crossings << {ed.x0 + (sy - ed.y0) * ed.slope, ed.dir} if ed.y0 <= sy && sy < ed.y1
          end
          if crossings.size > 1
            crossings.sort! { |l, r| l[0] <=> r[0] }
            wind  = 0
            k     = 0
            limit = crossings.size - 1
            while k < limit
              wind += crossings.unsafe_fetch(k)[1]
              if wind != 0
                add_span(cov, row, width,
                  crossings.unsafe_fetch(k)[0], crossings.unsafe_fetch(k + 1)[0], amount)
              end
              k += 1
            end
          end
          s += 1
        end
        y += 1
      end

      i = 0
      n = cov.size
      while i < n
        cov[i] = 1.0_f32 if cov.unsafe_fetch(i) > 1.0_f32
        i += 1
      end
      cov
    end

    def self.intersect(a : Slice(Float32), b : Slice(Float32)) : Slice(Float32)
      merged = Slice(Float32).new(a.size, 0.0_f32)
      i      = 0
      while i < a.size
        merged[i] = a.unsafe_fetch(i) * b.unsafe_fetch(i)
        i += 1
      end
      merged
    end

    private def self.add_span(cov : Slice(Float32), row : Int32, width : Int32,
                              x0 : Float64, x1 : Float64, amount : Float32) : Nil
      x0 = 0.0 if x0 < 0.0
      x1 = width.to_f if x1 > width
      return if x1 <= x0
      i0 = x0.floor.to_i
      i1 = x1.ceil.to_i - 1
      return if i0 >= width || i1 < 0
      i0 = 0 if i0 < 0
      i1 = width - 1 if i1 >= width
      if i0 == i1
        cov[row + i0] += (amount * (x1 - x0)).to_f32
        return
      end
      cov[row + i0] += (amount * ((i0 + 1) - x0)).to_f32
      k = i0 + 1
      while k < i1
        cov[row + k] += amount
        k += 1
      end
      cov[row + i1] += (amount * (x1 - i1)).to_f32
    end
  end

  struct ColorStop
    getter offset : Float64
    getter rgba   : UInt32

    def initialize(@offset : Float64, @rgba : UInt32)
    end
  end

  struct ColorLine
    getter stops       : Array(ColorStop)
    getter extend_mode : Extend

    def initialize(@stops : Array(ColorStop), @extend_mode : Extend)
    end

    def sample(t : Float64) : UInt32
      return 0_u32 if @stops.empty?
      return @stops.first.rgba if @stops.size == 1
      lo   = @stops.first.offset
      hi   = @stops.last.offset
      span = hi - lo
      if span > 1e-9
        case @extend_mode
        in .pad?
          t = lo if t < lo
          t = hi if t > hi
        in .repeat?
          t = lo + ((t - lo) % span + span) % span
        in .reflect?
          period = span * 2.0
          u      = ((t - lo) % period + period) % period
          t      = lo + (u <= span ? u : period - u)
        end
      end
      i     = 0
      limit = @stops.size - 1
      while i < limit
        a = @stops.unsafe_fetch(i)
        b = @stops.unsafe_fetch(i + 1)
        if t <= b.offset || i == limit - 1
          d = b.offset - a.offset
          f = d.abs < 1e-9 ? 0.0 : (t - a.offset) / d
          f = 0.0 if f < 0.0
          f = 1.0 if f > 1.0
          return mix(a.rgba, b.rgba, f)
        end
        i += 1
      end
      @stops.last.rgba
    end

    private def mix(a : UInt32, b : UInt32, f : Float64) : UInt32
      packed = 0_u32
      shift  = 0
      while shift < 32
        ca = ((a >> shift) & 0xff).to_f
        cb = ((b >> shift) & 0xff).to_f
        v  = (ca + (cb - ca) * f).round.to_u32
        v  = 255_u32 if v > 255
        packed |= v << shift
        shift += 8
      end
      packed
    end
  end

  abstract class Paint
    abstract def sample(x : Float64, y : Float64) : UInt32
  end

  class SolidPaint < Paint
    getter rgba : UInt32

    def initialize(@rgba : UInt32)
    end

    def sample(x : Float64, y : Float64) : UInt32
      @rgba
    end
  end

  class LinearPaint < Paint
    def initialize(@line : ColorLine, @inverse : Transform, @x0 : Float64, @y0 : Float64,
                   @dx : Float64, @dy : Float64, @len2 : Float64)
    end

    def sample(x : Float64, y : Float64) : UInt32
      gx = @inverse.apply_x(x, y) - @x0
      gy = @inverse.apply_y(x, y) - @y0
      @line.sample((gx * @dx + gy * @dy) / @len2)
    end
  end

  class RadialPaint < Paint
    def initialize(@line : ColorLine, @inverse : Transform,
                   @cx0 : Float64, @cy0 : Float64, @r0 : Float64,
                   @cx1 : Float64, @cy1 : Float64, @r1 : Float64)
    end

    def sample(x : Float64, y : Float64) : UInt32
      px  = @inverse.apply_x(x, y) - @cx0
      py  = @inverse.apply_y(x, y) - @cy0
      cdx = @cx1 - @cx0
      cdy = @cy1 - @cy0
      dr  = @r1 - @r0
      a   = cdx * cdx + cdy * cdy - dr * dr
      b   = px * cdx + py * cdy + @r0 * dr
      c   = px * px + py * py - @r0 * @r0
      if a.abs < 1e-9
        return @line.sample(0.0) if b.abs < 1e-9
        return @line.sample(c / (2.0 * b))
      end
      disc = b * b - a * c
      return @line.sample(0.0) if disc < 0.0
      sq = Math.sqrt(disc)
      s  = (b + sq) / a
      s  = (b - sq) / a if @r0 + s * dr < 0.0
      @line.sample(s)
    end
  end

  class Bitmap
    getter width  : Int32
    getter height : Int32
    getter data   : Slice(Float32)

    def initialize(@width : Int32, @height : Int32)
      @data = Slice(Float32).new(@width * @height * 4, 0.0_f32)
    end

    def blend(clip : Slice(Float32)?, paint : Paint) : Nil
      y = 0
      while y < @height
        x = 0
        while x < @width
          i   = y * @width + x
          cov = clip ? clip.unsafe_fetch(i).to_f64 : 1.0
          if cov > 0.0
            rgba = paint.sample(x + 0.5, y + 0.5)
            sa   = ((rgba >> 24) & 0xff) / 255.0 * cov
            if sa > 0.0
              sr  = ((rgba >> 16) & 0xff) / 255.0 * sa
              sg  = ((rgba >> 8) & 0xff) / 255.0 * sa
              sb  = (rgba & 0xff) / 255.0 * sa
              o   = i * 4
              inv = 1.0 - sa
              @data[o] = (sr + @data.unsafe_fetch(o) * inv).to_f32
              @data[o + 1] = (sg + @data.unsafe_fetch(o + 1) * inv).to_f32
              @data[o + 2] = (sb + @data.unsafe_fetch(o + 2) * inv).to_f32
              @data[o + 3] = (sa + @data.unsafe_fetch(o + 3) * inv).to_f32
            end
          end
          x += 1
        end
        y += 1
      end
    end

    def to_rgba8 : Bytes
      pixels = Bytes.new(@width * @height * 4)
      i      = 0
      n      = @width * @height
      while i < n
        o = i * 4
        a = @data.unsafe_fetch(o + 3).to_f64
        if a > 0.0
          pixels[o] = channel(@data.unsafe_fetch(o).to_f64 / a)
          pixels[o + 1] = channel(@data.unsafe_fetch(o + 1).to_f64 / a)
          pixels[o + 2] = channel(@data.unsafe_fetch(o + 2).to_f64 / a)
          pixels[o + 3] = channel(a)
        end
        i += 1
      end
      pixels
    end

    private def channel(v : Float64) : UInt8
      v = 0.0 if v < 0.0
      v = 1.0 if v > 1.0
      (v * 255.0).round.to_u8
    end
  end

  module Cpal
    def self.parse(bytes : Bytes) : Array(UInt32)
      return [] of UInt32 if bytes.empty?
      r = Reader.new(bytes)
      r.u16
      entries  = r.u16.to_i32
      palettes = r.u16.to_i32
      records  = r.u16.to_i32
      first    = r.u32.to_i32
      return [] of UInt32 if palettes < 1 || entries < 1 || records < 1
      index  = r.u16.to_i32
      colors = Array(UInt32).new(entries)
      i      = 0
      while i < entries
        slot = index + i
        if slot >= records
          colors << 0xff000000_u32
        else
          r.seek(first + slot * 4)
          b   = r.u8.to_u32
          g   = r.u8.to_u32
          red = r.u8.to_u32
          a   = r.u8.to_u32
          colors << ((a << 24) | (red << 16) | (g << 8) | b)
        end
        i += 1
      end
      colors
    end
  end

  struct Container
    getter outlines : Array(Outline)
    getter colr     : Bytes
    getter cpal     : Bytes

    def initialize(@outlines : Array(Outline), @colr : Bytes, @cpal : Bytes)
    end

    def self.parse(bytes : Bytes) : Container
      raise Error.new(Reason::PayloadTooLarge) if bytes.size > MAX_PAYLOAD
      r     = Reader.new(bytes)
      count = r.u16.to_i32
      raise Error.new(Reason::MalformedPayload) if count < 1 || count > MAX_CONTAINER
      outlines = Array(Outline).new(count)
      budget   = 0
      i        = 0
      while i < count
        len     = r.u16.to_i32
        outline = Glyf.parse(r.slice(len))
        budget += outline.point_count * POINT_COST
        raise Error.new(Reason::OutlineTooLarge) if budget > DECODED_BUDGET
        outlines << outline
        i += 1
      end
      colr_len = r.u16.to_i32
      raise Error.new(Reason::MalformedPayload) if colr_len <= 0
      colr     = r.slice(colr_len)
      cpal_len = r.u16.to_i32
      cpal     = cpal_len > 0 ? r.slice(cpal_len) : Bytes.empty
      Container.new(outlines, colr, cpal)
    end
  end

  class ColrRenderer
    def initialize(@outlines : Array(Outline), @colr : Bytes,
                   @palette : Array(UInt32), @fg : UInt32,
                   @width : Int32, @height : Int32)
      @base_glyph_list = 0
      @layer_list      = 0
    end

    def render(target : Bitmap, root : Transform) : Nil
      r            = Reader.new(@colr)
      version      = r.u16.to_i32
      num_base     = r.u16.to_i32
      base_offset  = r.u32.to_i32
      layer_offset = r.u32.to_i32
      num_layers   = r.u16.to_i32

      if version >= 1
        @base_glyph_list = r.u32.to_i32
        @layer_list      = r.u32.to_i32
        return if @base_glyph_list > 0 && paint_v1(target, root)
      end

      render_v0(target, root, r, num_base, base_offset, layer_offset, num_layers)
    end

    private def paint_v1(target : Bitmap, root : Transform) : Bool
      offset = base_paint_offset(0)
      return false unless offset
      paint(target, offset, root, nil, 0)
      true
    end

    private def base_paint_offset(glyph_id : Int32) : Int32?
      r = Reader.new(@colr)
      r.seek(@base_glyph_list)
      count = r.u32.to_i32
      i     = 0
      while i < count
        gid = r.u16.to_i32
        off = r.u32.to_i32
        return @base_glyph_list + off if gid == glyph_id
        i += 1
      end
      nil
    end

    private def render_v0(target : Bitmap, root : Transform, r : Reader,
                          num_base : Int32, base_offset : Int32,
                          layer_offset : Int32, num_layers : Int32) : Nil
      return if base_offset <= 0 || layer_offset <= 0
      first = -1
      count = 0
      i     = 0
      while i < num_base
        r.seek(base_offset + i * 6)
        gid = r.u16.to_i32
        fl  = r.u16.to_i32
        nl  = r.u16.to_i32
        if gid == 0
          first = fl
          count = nl
          break
        end
        i += 1
      end
      return if first < 0
      i = 0
      while i < count
        idx = first + i
        break if idx >= num_layers
        r.seek(layer_offset + idx * 4)
        gid  = r.u16.to_i32
        pal  = r.u16
        mask = glyph_mask(gid, root)
        target.blend(mask, SolidPaint.new(color_for(pal, 1.0))) if mask
        i += 1
      end
    end

    private def paint(target : Bitmap, offset : Int32, tf : Transform,
                      clip : Slice(Float32)?, depth : Int32) : Nil
      return if depth > MAX_DEPTH
      r = Reader.new(@colr)
      r.seek(offset)
      format = r.u8.to_i32

      case format
      when 1
        n     = r.u8.to_i32
        first = r.u32.to_i32
        return if @layer_list <= 0
        lr = Reader.new(@colr)
        lr.seek(@layer_list)
        total = lr.u32.to_i32
        i     = 0
        while i < n
          idx = first + i
          break if idx >= total
          lr.seek(@layer_list + 4 + idx * 4)
          paint(target, @layer_list + lr.u32.to_i32, tf, clip, depth + 1)
          i += 1
        end
      when 2, 3
        pal   = r.u16
        alpha = r.f2dot14
        target.blend(clip, SolidPaint.new(color_for(pal, alpha)))
      when 4, 5
        line = color_line(offset + r.u24, format == 5)
        x0   = r.i16.to_f
        y0   = r.i16.to_f
        x1   = r.i16.to_f
        y1   = r.i16.to_f
        x2   = r.i16.to_f
        y2   = r.i16.to_f
        target.blend(clip, linear_paint(line, tf, x0, y0, x1, y1, x2, y2))
      when 6, 7
        line    = color_line(offset + r.u24, format == 7)
        x0      = r.i16.to_f
        y0      = r.i16.to_f
        r0      = r.u16.to_f
        x1      = r.i16.to_f
        y1      = r.i16.to_f
        r1      = r.u16.to_f
        inverse = tf.invert
        if inverse
          target.blend(clip, RadialPaint.new(line, inverse, x0, y0, r0, x1, y1, r1))
        else
          target.blend(clip, SolidPaint.new(line.sample(0.0)))
        end
      when 8, 9
        line = color_line(offset + r.u24, format == 9)
        target.blend(clip, SolidPaint.new(line.sample(0.0)))
      when 10
        child = offset + r.u24
        gid   = r.u16.to_i32
        mask  = glyph_mask(gid, tf)
        return unless mask
        merged = clip ? Fill.intersect(clip, mask) : mask
        paint(target, child, tf, merged, depth + 1)
      when 11
        gid   = r.u16.to_i32
        child = base_paint_offset(gid)
        paint(target, child, tf, clip, depth + 1) if child
      when 12, 13
        child = offset + r.u24
        toff  = offset + r.u24
        tr    = Reader.new(@colr)
        tr.seek(toff)
        m = Transform.new(tr.fixed, tr.fixed, tr.fixed, tr.fixed, tr.fixed, tr.fixed)
        paint(target, child, tf.concat(m), clip, depth + 1)
      when 14, 15
        child = offset + r.u24
        dx    = r.i16.to_f
        dy    = r.i16.to_f
        paint(target, child, tf.concat(Transform.translate(dx, dy)), clip, depth + 1)
      when 16, 17, 18, 19, 20, 21, 22, 23
        child = offset + r.u24
        if format < 20
          sx = r.f2dot14
          sy = r.f2dot14
        else
          sx = r.f2dot14
          sy = sx
        end
        m = Transform.scale(sx, sy)
        m = m.around(r.i16.to_f, r.i16.to_f) if format == 18 || format == 19 || format == 22 || format == 23
        paint(target, child, tf.concat(m), clip, depth + 1)
      when 24, 25, 26, 27
        child = offset + r.u24
        m     = Transform.rotate(r.f2dot14 * Math::PI)
        m     = m.around(r.i16.to_f, r.i16.to_f) if format == 26 || format == 27
        paint(target, child, tf.concat(m), clip, depth + 1)
      when 28, 29, 30, 31
        child = offset + r.u24
        m     = Transform.skew(r.f2dot14 * Math::PI, r.f2dot14 * Math::PI)
        m     = m.around(r.i16.to_f, r.i16.to_f) if format == 30 || format == 31
        paint(target, child, tf.concat(m), clip, depth + 1)
      when 32
        source = offset + r.u24
        r.u8
        backdrop = offset + r.u24
        paint(target, backdrop, tf, clip, depth + 1)
        paint(target, source, tf, clip, depth + 1)
      end
    end

    private def linear_paint(line : ColorLine, tf : Transform,
                             x0 : Float64, y0 : Float64, x1 : Float64,
                             y1 : Float64, x2 : Float64, y2 : Float64) : Paint
      inverse = tf.invert
      return SolidPaint.new(line.sample(0.0)) unless inverse
      nx = -(y2 - y0)
      ny = x2 - x0
      nn = nx * nx + ny * ny
      if nn > 1e-9
        k  = ((x1 - x0) * nx + (y1 - y0) * ny) / nn
        px = x0 + k * nx
        py = y0 + k * ny
      else
        px = x1
        py = y1
      end
      dx   = px - x0
      dy   = py - y0
      len2 = dx * dx + dy * dy
      return SolidPaint.new(line.sample(0.0)) if len2 < 1e-9
      LinearPaint.new(line, inverse, x0, y0, dx, dy, len2)
    end

    private def color_line(offset : Int32, variable : Bool) : ColorLine
      r = Reader.new(@colr)
      r.seek(offset)
      mode = case r.u8
             when 1 then Extend::Repeat
             when 2 then Extend::Reflect
             else        Extend::Pad
             end
      count = r.u16.to_i32
      stops = Array(ColorStop).new(count)
      i     = 0
      while i < count
        at    = r.f2dot14
        pal   = r.u16
        alpha = r.f2dot14
        r.u32 if variable
        stops << ColorStop.new(at, color_for(pal, alpha))
        i += 1
      end
      stops.sort! { |l, r2| l.offset <=> r2.offset }
      ColorLine.new(stops, mode)
    end

    private def glyph_mask(glyph_id : Int32, tf : Transform) : Slice(Float32)?
      return nil if glyph_id < 0 || glyph_id >= @outlines.size
      Fill.coverage(Path.flatten(@outlines[glyph_id], tf), @width, @height)
    end

    private def color_for(index : UInt16, alpha : Float64) : UInt32
      rgba = if index == FOREGROUND || index >= @palette.size
               0xff000000_u32 | (@fg & 0x00ffffff_u32)
             else
               @palette[index.to_i32]
             end
      alpha = 0.0 if alpha < 0.0
      alpha = 1.0 if alpha > 1.0
      a     = (((rgba >> 24) & 0xff).to_f * alpha).round.to_u32
      (rgba & 0x00ffffff_u32) | (a << 24)
    end
  end

  struct Registration
    getter cp       : Int32
    getter format   : Format
    getter metrics  : Metrics
    getter span     : Int32
    getter size     : SizeMode
    getter halign   : HAlign
    getter valign   : VAlign
    getter pad      : Pad
    getter outlines : Array(Outline)
    getter colr     : Bytes
    getter palette  : Array(UInt32)
    getter tag      : UInt64
    getter slot     : Int32
    getter text     : String

    def initialize(@cp : Int32, @format : Format, @metrics : Metrics, @span : Int32,
                   @size : SizeMode, @halign : HAlign, @valign : VAlign, @pad : Pad,
                   @outlines : Array(Outline), @colr : Bytes, @palette : Array(UInt32),
                   @tag : UInt64, @slot : Int32)
      @text = @span > 1 ? "#{@cp.chr} " : @cp.chr.to_s
    end
  end

  module Layout
    def self.resolve(reg : Registration, cell_width : Int32, cell_height : Int32,
                     baseline : Int32) : Transform
      w   = (reg.span * cell_width).to_f
      h   = cell_height.to_f
      pad = reg.pad.degenerate? ? Pad.none : reg.pad
      pl  = w * pad.left
      pr  = w * pad.right
      pt  = h * pad.top
      pb  = h * pad.bottom
      ew  = w - pl - pr
      eh  = h - pt - pb
      aw  = reg.metrics.aw.to_f
      lh  = reg.metrics.lh.to_f
      aw  = 1.0 if aw <= 0.0
      lh  = 1.0 if lh <= 0.0

      sx = 0.0
      sy = 0.0
      case reg.size
      in .height?
        sx = eh / lh
        sy = sx
      in .advance?
        sx = ew / aw
        sy = sx
      in .contain?
        sx = Math.min(ew / aw, eh / lh)
        sy = sx
      in .cover?
        sx = Math.max(ew / aw, eh / lh)
        sy = sx
      in .stretch?
        sx = ew / aw
        sy = eh / lh
      end

      asc      = baseline.to_f
      desc     = (cell_height - baseline).to_f
      total    = asc + desc
      total    = 1.0 if total <= 0.0
      y_max    = lh * (asc / total)
      y_min    = y_max - lh
      scaled_w = aw * sx

      ox = case reg.halign
           in .start?  then pl
           in .center? then pl + (ew - scaled_w) * 0.5
           in .end?    then w - pr - scaled_w
           end

      oy = case reg.valign
           in .start?    then (h - pb) + y_min * sy
           in .center?   then (pt + eh * 0.5) + ((y_min + y_max) * 0.5) * sy
           in .end?      then pt + y_max * sy
           in .baseline? then baseline.to_f
           end

      Transform.new(sx, 0.0, 0.0, -sy, ox, oy)
    end
  end

  class Glossary
    getter size : Int32

    def initialize
      @entries   = {} of Int32 => Registration
      @order     = Deque(Int32).new
      @free      = Deque(Int32).new
      @next_slot = 0
      @next_tag  = 1_u64
      @size      = 0
    end

    def []?(cp : Int32) : Registration?
      @entries[cp]?
    end

    def register(cp : Int32, payload : Bytes, format : Format = Format::Glyf,
                 upm : Int32 = DEFAULT_UPM, aw : Int32? = nil, lh : Int32? = nil,
                 span : Int32 = 1, size : SizeMode = SizeMode::Height,
                 halign : HAlign = HAlign::Center, valign : VAlign = VAlign::Center,
                 pad : Pad = Pad.none) : Registration
      raise Error.new(Reason::OutOfNamespace) unless Glyph.pua?(cp)
      raise Error.new(Reason::PayloadTooLarge) if payload.size > MAX_PAYLOAD
      span = 1 if span != 2

      outlines = [] of Outline
      colr     = Bytes.empty
      palette  = [] of UInt32

      case format
      when .glyf?
        outline = Glyf.parse(payload)
        raise Error.new(Reason::OutlineTooLarge) if outline.point_count * POINT_COST > DECODED_BUDGET
        outlines << outline
      else
        container = Container.parse(payload)
        outlines  = container.outlines
        colr      = container.colr
        palette   = Cpal.parse(container.cpal)
      end

      existing = @entries[cp]?
      slot     = existing ? existing.slot : acquire_slot
      reg = Registration.new(cp, format, Metrics.new(upm, aw, lh), span, size,
        halign, valign, pad, outlines, colr, palette, next_tag, slot)

      unless existing
        @order.push(cp)
        @size += 1
      end
      @entries[cp] = reg
      reg
    end

    def query(cp : Int32, system : Bool = false) : Coverage
      cov = Coverage::None
      cov |= Coverage::System if system
      cov |= Coverage::Glossary if Glyph.pua?(cp) && @entries.has_key?(cp)
      cov
    end

    def clear(cp : Int32) : Bool
      raise Error.new(Reason::OutOfNamespace) unless Glyph.pua?(cp)
      reg = @entries.delete(cp)
      return true unless reg
      @order.delete(cp)
      @free.push(reg.slot)
      @size -= 1
      true
    end

    def clear_all : Nil
      @entries.each_value { |reg| @free.push(reg.slot) }
      @entries.clear
      @order.clear
      @size = 0
    end

    def each(& : Registration ->) : Nil
      @order.each do |cp|
        reg = @entries[cp]?
        yield reg if reg
      end
    end

    private def acquire_slot : Int32
      while @size >= MAX_SLOTS
        evict
      end
      return @free.shift unless @free.empty?
      slot = @next_slot
      @next_slot += 1
      slot
    end

    private def evict : Nil
      victim = @order.shift?
      return unless victim
      reg = @entries.delete(victim)
      return unless reg
      @free.push(reg.slot)
      @size -= 1
    end

    private def next_tag : UInt64
      tag = @next_tag
      @next_tag += 1
      tag
    end
  end

  struct Image
    getter width  : Int32
    getter height : Int32
    getter pixels : Bytes

    def initialize(@width : Int32, @height : Int32, @pixels : Bytes)
    end
  end

  class Renderer
    getter cell_width  : Int32
    getter cell_height : Int32
    getter baseline    : Int32

    def initialize(cell_width : Int32, cell_height : Int32, baseline : Int32? = nil)
      raise ArgumentError.new("cell metrics must be positive") if cell_width <= 0 || cell_height <= 0
      @cell_width  = cell_width
      @cell_height = cell_height
      @baseline    = baseline || (cell_height * 4) // 5
      @cache       = {} of Tuple(Int32, UInt64, UInt32) => Image
    end

    def resize(cell_width : Int32, cell_height : Int32, baseline : Int32? = nil) : Nil
      raise ArgumentError.new("cell metrics must be positive") if cell_width <= 0 || cell_height <= 0
      @cell_width  = cell_width
      @cell_height = cell_height
      @baseline    = baseline || (cell_height * 4) // 5
      @cache.clear
    end

    def render(reg : Registration, fg_rgb : UInt32) : Image
      key    = {reg.cp, reg.tag, fg_rgb}
      cached = @cache[key]?
      return cached if cached

      width  = reg.span * @cell_width
      height = @cell_height
      bitmap = Bitmap.new(width, height)
      tf     = Layout.resolve(reg, @cell_width, @cell_height, @baseline)

      case reg.format
      when .glyf?
        outline = reg.outlines.first?
        if outline
          mask = Fill.coverage(Path.flatten(outline, tf), width, height)
          bitmap.blend(mask, SolidPaint.new(0xff000000_u32 | (fg_rgb & 0x00ffffff_u32)))
        end
      else
        ColrRenderer.new(reg.outlines, reg.colr, reg.palette, fg_rgb, width, height)
          .render(bitmap, tf)
      end

      image = Image.new(width, height, bitmap.to_rgba8)
      @cache[key] = image
      image
    end
  end
end
