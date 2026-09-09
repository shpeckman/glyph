# spec/glyph/transform_spec.cr
require "../spec_helper"

describe Glyph::Transform do
  it "applies scale and translation" do
    t = Glyph::Transform.new(2.0, 0.0, 0.0, 3.0, 5.0, 7.0)
    t.apply_x(1.0, 1.0).should eq(7.0)
    t.apply_y(1.0, 1.0).should eq(10.0)
  end

  it "composes inner before outer" do
    outer = Glyph::Transform.translate(10.0, 0.0)
    inner = Glyph::Transform.scale(2.0, 2.0)
    c     = outer.concat(inner)
    c.apply_x(3.0, 0.0).should eq(16.0)
  end

  it "inverts an affine transform" do
    t   = Glyph::Transform.new(2.0, 0.0, 0.0, -4.0, 5.0, 9.0)
    inv = t.invert.not_nil!
    inv.apply_x(t.apply_x(3.0, 2.0), t.apply_y(3.0, 2.0)).should be_close(3.0, 1e-9)
    inv.apply_y(t.apply_x(3.0, 2.0), t.apply_y(3.0, 2.0)).should be_close(2.0, 1e-9)
  end

  it "returns nil for a degenerate transform" do
    Glyph::Transform.new(0.0, 0.0, 0.0, 0.0, 0.0, 0.0).invert.should be_nil
  end

  it "rotates around a center point" do
    t = Glyph::Transform.rotate(Math::PI).around(10.0, 10.0)
    t.apply_x(10.0, 10.0).should be_close(10.0, 1e-9)
    t.apply_x(11.0, 10.0).should be_close(9.0, 1e-9)
  end
end
