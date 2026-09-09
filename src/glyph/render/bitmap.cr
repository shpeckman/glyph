# src/glyph/render/bitmap.cr
module Glyph
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
end
