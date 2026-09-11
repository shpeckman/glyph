# src/glyph/render/bitmap.cr
class Glyph::Bitmap
  getter width         : Int32
  getter height        : Int32
  getter data          : Slice(Float32)
  getter subpixel      : Bool
  getter gamma_correct : Bool

  def initialize(@width : Int32, @height : Int32, @subpixel : Bool = false, @gamma_correct : Bool = false)
    @data = Slice(Float32).new(@width * @height * 4, 0.0_f32)
  end

  def blend(clip : Slice(Float32)?, paint : Paint) : Nil
    y = 0
    while y < @height
      x = 0
      while x < @width
        if @subpixel
          mask_i = y * (@width * 3) + x * 3
          cov_r  = clip ? clip.unsafe_fetch(mask_i).to_f64 : 1.0
          cov_g  = clip ? clip.unsafe_fetch(mask_i + 1).to_f64 : 1.0
          cov_b  = clip ? clip.unsafe_fetch(mask_i + 2).to_f64 : 1.0
        else
          i     = y * @width + x
          cov_r = clip ? clip.unsafe_fetch(i).to_f64 : 1.0
          cov_g = cov_b = cov_r
        end

        cov_a = (cov_r + cov_g + cov_b) / 3.0

        if cov_a > 0.0 || cov_r > 0.0 || cov_g > 0.0 || cov_b > 0.0
          rgba = paint.sample(x + 0.5, y + 0.5)
          a    = ((rgba >> 24) & 0xff) / 255.0

          if a > 0.0
            r = ((rgba >> 16) & 0xff) / 255.0
            g = ((rgba >> 8) & 0xff) / 255.0
            b = (rgba & 0xff) / 255.0

            if @gamma_correct
              r = srgb_to_linear(r)
              g = srgb_to_linear(g)
              b = srgb_to_linear(b)
            end

            sa_r = a * cov_r
            sa_g = a * cov_g
            sa_b = a * cov_b
            sa_a = a * cov_a

            if sa_a > 0.0 || sa_r > 0.0 || sa_g > 0.0 || sa_b > 0.0
              sr = r * sa_r
              sg = g * sa_g
              sb = b * sa_b
              o  = (y * @width + x) * 4

              inv_r = 1.0 - sa_r
              inv_g = 1.0 - sa_g
              inv_b = 1.0 - sa_b
              inv_a = 1.0 - sa_a

              @data[o] = (sr + @data.unsafe_fetch(o) * inv_r).to_f32
              @data[o + 1] = (sg + @data.unsafe_fetch(o + 1) * inv_g).to_f32
              @data[o + 2] = (sb + @data.unsafe_fetch(o + 2) * inv_b).to_f32
              @data[o + 3] = (sa_a + @data.unsafe_fetch(o + 3) * inv_a).to_f32
            end
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
        r = @data.unsafe_fetch(o).to_f64 / a
        g = @data.unsafe_fetch(o + 1).to_f64 / a
        b = @data.unsafe_fetch(o + 2).to_f64 / a

        if @gamma_correct
          r = linear_to_srgb(r)
          g = linear_to_srgb(g)
          b = linear_to_srgb(b)
        end

        pixels[o] = channel(r)
        pixels[o + 1] = channel(g)
        pixels[o + 2] = channel(b)
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

  private def srgb_to_linear(c : Float64) : Float64
    c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  end

  private def linear_to_srgb(c : Float64) : Float64
    c <= 0.0031308 ? c * 12.92 : 1.055 * (c ** (1.0 / 2.4)) - 0.055
  end
end
