# src/glyph/parsers/glyf.cr
# # src/glyph/parsers/glyf.cr

module Glyph
  module Glyf
    ON_CURVE = 0x01_u8
    X_SHORT  = 0x02_u8
    Y_SHORT  = 0x04_u8
    REPEAT   = 0x08_u8
    X_SAME   = 0x10_u8
    Y_SAME   = 0x20_u8

    ARG_1_AND_2_ARE_WORDS    = 0x0001
    ARGS_ARE_XY_VALUES       = 0x0002
    WE_HAVE_A_SCALE          = 0x0008
    MORE_COMPONENTS          = 0x0020
    WE_HAVE_AN_X_AND_Y_SCALE = 0x0040
    WE_HAVE_A_TWO_BY_TWO     = 0x0080

    def self.parse(bytes : Bytes, outlines : Array(Outline)? = nil) : Outline
      raise Error.new(Reason::PayloadTooLarge) if bytes.size > MAX_PAYLOAD
      parse(Reader.new(bytes), outlines)
    end

    def self.parse(r : Reader, outlines : Array(Outline)? = nil) : Outline
      n_contours = r.i16
      x_min      = r.i16
      y_min      = r.i16
      x_max      = r.i16
      y_max      = r.i16

      if n_contours < 0
        return parse_composite(r, outlines, x_min, y_min, x_max, y_max)
      end

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

      instruction_length = r.u16.to_i32
      r.seek(r.pos + instruction_length)

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

      points = Slice(Point).new(n_points, Point.new(0, 0, PointType::OnCurve))
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
        points[i] = Point.new(v, 0, (flag & ON_CURVE) != 0 ? PointType::OnCurve : PointType::Quad)
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
        points[i] = Point.new(p.x, v, p.type)
        i += 1
      end

      Outline.new(points, ends, x_min, y_min, x_max, y_max)
    rescue IndexError
      raise Error.new(Reason::MalformedPayload)
    end

    private def self.parse_composite(r : Reader, outlines : Array(Outline)?, x_min : Int32, y_min : Int32, x_max : Int32, y_max : Int32) : Outline
      raise Error.new(Reason::MalformedPayload) unless outlines

      all_points = [] of Point
      all_ends   = [] of Int32

      flags = MORE_COMPONENTS
      while (flags & MORE_COMPONENTS) != 0
        flags       = r.u16
        glyph_index = r.u16.to_i32

        if (flags & ARG_1_AND_2_ARE_WORDS) != 0
          arg1 = r.i16.to_i32
          arg2 = r.i16.to_i32
        else
          arg1 = r.u8.to_i32
          arg1 -= 256 if arg1 >= 128
          arg2 = r.u8.to_i32
          arg2 -= 256 if arg2 >= 128
        end

        a = 1.0; b = 0.0; c = 0.0; d = 1.0; e = 0.0; f = 0.0
        if (flags & ARGS_ARE_XY_VALUES) != 0
          e = arg1.to_f
          f = arg2.to_f
        end

        if (flags & WE_HAVE_A_SCALE) != 0
          scale = r.i16 / 16384.0
          a     = scale; d = scale
        elsif (flags & WE_HAVE_AN_X_AND_Y_SCALE) != 0
          a = r.i16 / 16384.0
          d = r.i16 / 16384.0
        elsif (flags & WE_HAVE_A_TWO_BY_TWO) != 0
          a = r.i16 / 16384.0
          b = r.i16 / 16384.0
          c = r.i16 / 16384.0
          d = r.i16 / 16384.0
        end

        if glyph_index >= 0 && glyph_index < outlines.size
          ref          = outlines.unsafe_fetch(glyph_index)
          point_offset = all_points.size

          ref.points.each do |p|
            nx = (a * p.x + c * p.y + e).round.to_i32
            ny = (b * p.x + d * p.y + f).round.to_i32
            all_points << Point.new(nx, ny, p.type)
          end

          ref.ends.each do |ed|
            all_ends << ed + point_offset
          end
        end
      end

      s_points = Slice(Point).new(all_points.size) { |idx| all_points.unsafe_fetch(idx) }
      s_ends   = Slice(Int32).new(all_ends.size) { |idx| all_ends.unsafe_fetch(idx) }
      Outline.new(s_points, s_ends, x_min, y_min, x_max, y_max)
    end
  end
end
