# spec/glyph/render/colr_spec.cr
# # spec/glyph/render/colr_spec.cr
require "../../spec_helper"

describe "colrv0 rendering" do
  it "paints a layer with its palette colour" do
    payload = container([square_glyf, square_glyf(500, 1000)],
      colr_v0_table(1, 0), cpal_table([{255_u8, 0_u8, 0_u8, 255_u8}]))
    g = Glyph::Glossary.new
    reg = g.register(0x100000, payload, format: Glyph::Format::Colr,
      size: Glyph::SizeMode::Stretch)
    image = Glyph::Renderer.new(8, 16, 16).render(reg, 0x00ff00_u32)
    DisplayGlyph.show(image)
    pixel(image, 1, 8).should eq({0xff_u8, 0x00_u8, 0x00_u8, 0xff_u8})
    pixel(image, 6, 8)[3].should eq(0_u8)
  end

  it "resolves palette index 0xFFFF to the foreground" do
    payload = container([square_glyf, square_glyf(500, 1000)],
      colr_v0_table(1, 0xFFFF), cpal_table([{255_u8, 0_u8, 0_u8, 255_u8}]))
    g = Glyph::Glossary.new
    reg = g.register(0x100000, payload, format: Glyph::Format::Colr,
      size: Glyph::SizeMode::Stretch)
    image = Glyph::Renderer.new(8, 16, 16).render(reg, 0x00ff00_u32)
    DisplayGlyph.show(image)
    pixel(image, 1, 8).should eq({0x00_u8, 0xff_u8, 0x00_u8, 0xff_u8})
  end
end
