# src/glyph/transform.cr
struct Glyph::Transform
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
