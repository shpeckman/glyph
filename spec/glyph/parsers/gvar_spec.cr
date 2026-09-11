# spec/glyph/parsers/gvar_spec.cr
require "../../spec_helper"

describe Glyph::Gvar do
  it "applies coordinate deltas to a matched outline" do
    base = Glyph::Glyf.parse(square_glyf(1000, 1000))
    gvar = simple_gvar_table(10_i8, 20_i8)

    # Apply deltas at peak coordinate (+1.0)
    mutated = Glyph::Gvar.apply([base], gvar, [1.0])

    outline = mutated.first
    outline.point_count.should eq(4)

    # All points shifted by +10 in X and +20 in Y
    outline.points[0].x.should eq(10)
    outline.points[0].y.should eq(20)

    outline.points[2].x.should eq(1010)
    outline.points[2].y.should eq(1020)

    # Extents should be updated
    outline.x_min.should eq(10)
    outline.x_max.should eq(1010)
    outline.y_min.should eq(20)
    outline.y_max.should eq(1020)
  end

  it "scales deltas based on normalized coordinates" do
    base = Glyph::Glyf.parse(square_glyf(1000, 1000))
    gvar = simple_gvar_table(10_i8, 20_i8)

    # Apply at 50% coordinate
    mutated = Glyph::Gvar.apply([base], gvar, [0.5])

    outline = mutated.first
    outline.points[0].x.should eq(5)
    outline.points[0].y.should eq(10)
  end

  it "ignores tuples outside the coordinate influence" do
    base = Glyph::Glyf.parse(square_glyf(1000, 1000))
    gvar = simple_gvar_table(10_i8, 20_i8)

    # Our mock tuple peaks at 1.0 (positive range only).
    # Requesting -1.0 should result in 0 influence.
    mutated = Glyph::Gvar.apply([base], gvar, [-1.0])

    outline = mutated.first
    outline.points[0].x.should eq(0)
    outline.points[0].y.should eq(0)
  end

  it "properly advances past shared points before reading tuple deltas" do
    base = Glyph::Glyf.parse(square_glyf(1000, 1000))
    gvar = shared_points_gvar_table(10_i8, 20_i8)

    mutated = Glyph::Gvar.apply([base], gvar, [1.0])
    outline = mutated.first

    # Prior to the fix, the parser read shared points bytes as tuple deltas
    # (causing completely offset logic) and misaligned the reader.
    outline.points[0].x.should eq(10)
    outline.points[0].y.should eq(20)
    outline.points[2].x.should eq(1010)
    outline.points[2].y.should eq(1020)
  end
end
