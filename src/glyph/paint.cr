# src/glyph/paint.cr
module Glyph
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
end
