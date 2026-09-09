# src/glyph/parsers/glyf.cr
module Glyph
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
end
