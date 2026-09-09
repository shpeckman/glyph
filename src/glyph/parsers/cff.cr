# src/glyph/parsers/cff.cr
module Glyph
  module Cff
    def self.parse(bytes : Bytes) : Outline
      r      = Reader.new(bytes)
      points = [] of Point
      ends   = [] of Int32
      stack  = [] of Float64
      x      = 0.0
      y      = 0.0

      while r.pos < r.size
        b0 = r.u8
        if b0 <= 27 || (b0 >= 29 && b0 <= 31)
          op = b0 == 12 ? ((12 << 8) | r.u8) : b0

          case op
          when 21
            ends << (points.size - 1) if points.size > 0 && (ends.empty? || ends.last != points.size - 1)
            dy = stack.pop
            dx = stack.pop
            x += dx; y += dy
            points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
            stack.clear
          when 4
            ends << (points.size - 1) if points.size > 0 && (ends.empty? || ends.last != points.size - 1)
            y += stack.pop
            points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
            stack.clear
          when 22
            ends << (points.size - 1) if points.size > 0 && (ends.empty? || ends.last != points.size - 1)
            x += stack.pop
            points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
            stack.clear
          when 5
            i = 0
            while i < stack.size
              x += stack[i]; y += stack[i + 1]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
              i += 2
            end
            stack.clear
          when 6
            i = 0
            while i < stack.size
              if i % 2 == 0
                x += stack[i]
              else
                y += stack[i]
              end
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
              i += 1
            end
            stack.clear
          when 7
            i = 0
            while i < stack.size
              if i % 2 == 0
                y += stack[i]
              else
                x += stack[i]
              end
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
              i += 1
            end
            stack.clear
          when 8
            i = 0
            while i < stack.size
              x += stack[i]; y += stack[i + 1]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
              x += stack[i + 2]; y += stack[i + 3]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
              x += stack[i + 4]; y += stack[i + 5]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
              i += 6
            end
            stack.clear
          when 24
            i = 0
            while i < stack.size - 2
              x += stack[i]; y += stack[i + 1]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
              x += stack[i + 2]; y += stack[i + 3]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
              x += stack[i + 4]; y += stack[i + 5]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
              i += 6
            end
            if i < stack.size
              x += stack[i]; y += stack[i + 1]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
            end
            stack.clear
          when 25
            i = 0
            while i < stack.size - 6
              x += stack[i]; y += stack[i + 1]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
              i += 2
            end
            if i < stack.size
              x += stack[i]; y += stack[i + 1]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
              x += stack[i + 2]; y += stack[i + 3]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
              x += stack[i + 4]; y += stack[i + 5]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
            end
            stack.clear
          when 26
            i = 0
            if stack.size % 4 == 1
              x += stack[i]
              i += 1
            end
            while i < stack.size
              x += 0.0; y += stack[i]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
              x += stack[i + 1]; y += stack[i + 2]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
              x += 0.0; y += stack[i + 3]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
              i += 4
            end
            stack.clear
          when 27
            i = 0
            if stack.size % 4 == 1
              y += stack[i]
              i += 1
            end
            while i < stack.size
              x += stack[i]; y += 0.0
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
              x += stack[i + 1]; y += stack[i + 2]
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
              x += stack[i + 3]; y += 0.0
              points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
              i += 4
            end
            stack.clear
          when 30
            i = 0
            while i < stack.size
              if ((i / 4) % 2) == 0
                x += 0.0; y += stack[i]
                points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
                x += stack[i + 1]; y += stack[i + 2]
                points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
                x += stack[i + 3]; y += (i + 4 == stack.size && stack.size % 4 == 1 ? stack[i + 4] : 0.0)
                points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
              else
                x += stack[i]; y += 0.0
                points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
                x += stack[i + 1]; y += stack[i + 2]
                points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
                y += stack[i + 3]; x += (i + 4 == stack.size && stack.size % 4 == 1 ? stack[i + 4] : 0.0)
                points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
              end
              i += (i + 4 == stack.size && stack.size % 4 == 1 ? 5 : 4)
            end
            stack.clear
          when 31
            i = 0
            while i < stack.size
              if ((i / 4) % 2) == 0
                x += stack[i]; y += 0.0
                points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
                x += stack[i + 1]; y += stack[i + 2]
                points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
                y += stack[i + 3]; x += (i + 4 == stack.size && stack.size % 4 == 1 ? stack[i + 4] : 0.0)
                points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
              else
                x += 0.0; y += stack[i]
                points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
                x += stack[i + 1]; y += stack[i + 2]
                points << Point.new(x.round.to_i32, y.round.to_i32, PointType::Cubic)
                x += stack[i + 3]; y += (i + 4 == stack.size && stack.size % 4 == 1 ? stack[i + 4] : 0.0)
                points << Point.new(x.round.to_i32, y.round.to_i32, PointType::OnCurve)
              end
              i += (i + 4 == stack.size && stack.size % 4 == 1 ? 5 : 4)
            end
            stack.clear
          when 14
            ends << (points.size - 1) if points.size > 0 && (ends.empty? || ends.last != points.size - 1)
            break
          else
            stack.clear
          end
        else
          if b0 == 28
            b1 = r.u8.to_i16
            b2 = r.u8.to_i16
            v  = (b1 << 8) | b2
            v  = v >= 0x8000 ? v - 0x10000 : v
            stack << v.to_f
          elsif b0 >= 32 && b0 <= 246
            stack << (b0.to_i32 - 139).to_f
          elsif b0 >= 247 && b0 <= 250
            stack << ((b0.to_i32 - 247) * 256 + r.u8.to_i32 + 108).to_f
          elsif b0 >= 251 && b0 <= 254
            stack << (-(b0.to_i32 - 251) * 256 - r.u8.to_i32 - 108).to_f
          elsif b0 == 255
            b1 = r.u8.to_i32
            b2 = r.u8.to_i32
            b3 = r.u8.to_i32
            b4 = r.u8.to_i32
            v  = (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
            stack << (v / 65536.0)
          end
        end
      end

      x_min = 0; y_min = 0; x_max = 0; y_max = 0
      if points.size > 0
        x_min = points.min_of(&.x)
        y_min = points.min_of(&.y)
        x_max = points.max_of(&.x)
        y_max = points.max_of(&.y)
      end

      s_points = Slice(Point).new(points.size) { |idx| points.unsafe_fetch(idx) }
      s_ends   = Slice(Int32).new(ends.size) { |idx| ends.unsafe_fetch(idx) }
      Outline.new(s_points, s_ends, x_min, y_min, x_max, y_max)
    end
  end
end
