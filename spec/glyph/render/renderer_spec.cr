# spec/glyph/render/renderer_spec.cr
require "../../spec_helper"

describe Glyph::Renderer do
  it "fills the span with the foreground colour" do
    g     = Glyph::Glossary.new
    reg   = g.register(0x100000, square_glyf, size: Glyph::SizeMode::Stretch)
    image = Glyph::Renderer.new(8, 16, 16).render(reg, 0x3366ff_u32)
    image.width.should eq(8)
    image.height.should eq(16)
    pixel(image, 4, 8).should eq({0x33_u8, 0x66_u8, 0xff_u8, 0xff_u8})
  end

  it "leaves uncovered pixels transparent" do
    g     = Glyph::Glossary.new
    reg   = g.register(0x100000, square_glyf(500, 1000), size: Glyph::SizeMode::Stretch)
    image = Glyph::Renderer.new(8, 16, 16).render(reg, 0xffffff_u32)
    pixel(image, 1, 8)[3].should eq(255_u8)
    pixel(image, 6, 8)[3].should eq(0_u8)
  end

  it "widens the bitmap for a width=2 glyph" do
    g     = Glyph::Glossary.new
    reg   = g.register(0x100000, square_glyf, span: 2)
    image = Glyph::Renderer.new(8, 16, 16).render(reg, 0xffffff_u32)
    image.width.should eq(16)
  end

  it "produces a fresh bitmap after a metrics change" do
    g        = Glyph::Glossary.new
    reg      = g.register(0x100000, square_glyf, size: Glyph::SizeMode::Stretch)
    renderer = Glyph::Renderer.new(8, 16, 16)
    renderer.render(reg, 0xffffff_u32).width.should eq(8)
    renderer.resize(12, 24, 24)
    renderer.render(reg, 0xffffff_u32).width.should eq(12)
  end

  it "serves a repeated render from the cache" do
    g        = Glyph::Glossary.new
    reg      = g.register(0x100000, square_glyf, size: Glyph::SizeMode::Stretch)
    renderer = Glyph::Renderer.new(8, 16, 16)
    renderer.render(reg, 0x112233_u32).pixels.should eq(renderer.render(reg, 0x112233_u32).pixels)
  end

  it "keys the cache on foreground colour" do
    g        = Glyph::Glossary.new
    reg      = g.register(0x100000, square_glyf, size: Glyph::SizeMode::Stretch)
    renderer = Glyph::Renderer.new(8, 16, 16)
    a        = renderer.render(reg, 0xff0000_u32)
    b        = renderer.render(reg, 0x00ff00_u32)
    pixel(a, 4, 8).should eq({0xff_u8, 0x00_u8, 0x00_u8, 0xff_u8})
    pixel(b, 4, 8).should eq({0x00_u8, 0xff_u8, 0x00_u8, 0xff_u8})
  end

  it "defaults the baseline to four fifths of the cell" do
    Glyph::Renderer.new(10, 20).baseline.should eq(16)
  end

  it "rejects non-positive cell metrics" do
    expect_raises(ArgumentError) { Glyph::Renderer.new(0, 20) }
    expect_raises(ArgumentError) { Glyph::Renderer.new(10, -1) }
  end
end
