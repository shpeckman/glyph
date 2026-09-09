# spec/glyph/paint_spec.cr
require "../spec_helper"

describe Glyph::ColorLine do
  it "interpolates between two stops" do
    line = Glyph::ColorLine.new([
      Glyph::ColorStop.new(0.0, 0xff000000_u32),
      Glyph::ColorStop.new(1.0, 0xffffffff_u32),
    ], Glyph::Extend::Pad)
    ((line.sample(0.5) >> 16) & 0xff).should be_close(128, 2)
  end

  it "pads outside the stop range" do
    line = Glyph::ColorLine.new([
      Glyph::ColorStop.new(0.0, 0xff102030_u32),
      Glyph::ColorStop.new(1.0, 0xff405060_u32),
    ], Glyph::Extend::Pad)
    line.sample(-3.0).should eq(0xff102030_u32)
    line.sample(9.0).should eq(0xff405060_u32)
  end

  it "repeats across the stop range" do
    line = Glyph::ColorLine.new([
      Glyph::ColorStop.new(0.0, 0xff000000_u32),
      Glyph::ColorStop.new(1.0, 0xffffffff_u32),
    ], Glyph::Extend::Repeat)
    line.sample(2.25).should eq(line.sample(0.25))
  end

  it "reflects across the stop range" do
    line = Glyph::ColorLine.new([
      Glyph::ColorStop.new(0.0, 0xff000000_u32),
      Glyph::ColorStop.new(1.0, 0xffffffff_u32),
    ], Glyph::Extend::Reflect)
    line.sample(1.25).should eq(line.sample(0.75))
  end
end
