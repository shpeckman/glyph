# spec/glyph/parsers/fvar_spec.cr
require "../../spec_helper"

describe Glyph::Fvar do
  it "parses axes from a variation table" do
    table = fvar_table([
      {"wght", 100.0, 400.0, 900.0},
      {"wdth", 50.0,  100.0, 200.0},
    ])

    axes = Glyph::Fvar.parse(table)
    axes.size.should eq(2)

    axes[0].tag.should eq("wght")
    axes[0].min.should eq(100.0)
    axes[0].def.should eq(400.0)
    axes[0].max.should eq(900.0)

    axes[1].tag.should eq("wdth")
    axes[1].def.should eq(100.0)
  end

  it "normalizes user coordinates correctly" do
    axes = [
      Glyph::Fvar::Axis.new("wght", 100.0, 400.0, 900.0),
      Glyph::Fvar::Axis.new("opsz", 8.0, 14.0, 72.0),
    ]

    coords = Glyph::Fvar.normalize(axes, {"wght" => 700.0, "opsz" => 8.0})

    # 700 is 300 above the 400 default, out of a 500 max range -> 0.6
    coords[0].should be_close(0.6, 1e-9)

    # 8.0 is the minimum, which is -1.0 normalized
    coords[1].should be_close(-1.0, 1e-9)
  end

  it "falls back to default for omitted axes" do
    axes   = [Glyph::Fvar::Axis.new("wght", 100.0, 400.0, 900.0)]
    coords = Glyph::Fvar.normalize(axes, {} of String => Float64)
    coords[0].should eq(0.0)
  end

  it "clamps coordinates outside the valid range" do
    axes = [Glyph::Fvar::Axis.new("wght", 100.0, 400.0, 900.0)]

    low = Glyph::Fvar.normalize(axes, {"wght" => 0.0})
    low[0].should eq(-1.0)

    high = Glyph::Fvar.normalize(axes, {"wght" => 1500.0})
    high[0].should eq(1.0)
  end
end
