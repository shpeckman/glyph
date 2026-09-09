# src/glyph/geometry/fill.cr
module Glyph
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
end
