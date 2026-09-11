# spec/glyph/render/renderer_spec.cr
# # spec/glyph/render/renderer_spec.cr
require "../../spec_helper"

# Expose internal cache size exclusively for specs
class Glyph::Renderer
  def cache_size
    @cache.size
  end
end

describe Glyph::Renderer do
  it "fills the span with the foreground colour" do
    g     = Glyph::Glossary.new
    reg   = g.register(0x100000, square_glyf, size: Glyph::SizeMode::Stretch)
    image = Glyph::Renderer.new(8, 16, 16).render(reg, 0x3366ff_u32)
    DisplayGlyph.show(image)
    image.width.should eq(8)
    image.height.should eq(16)
    pixel(image, 4, 8).should eq({0x33_u8, 0x66_u8, 0xff_u8, 0xff_u8})
  end

  it "leaves uncovered pixels transparent" do
    g     = Glyph::Glossary.new
    reg   = g.register(0x100000, square_glyf(500, 1000), size: Glyph::SizeMode::Stretch)
    image = Glyph::Renderer.new(8, 16, 16).render(reg, 0xffffff_u32)
    DisplayGlyph.show(image)
    pixel(image, 1, 8)[3].should eq(255_u8)
    pixel(image, 6, 8)[3].should eq(0_u8)
  end

  it "widens the bitmap for a width=2 glyph" do
    g     = Glyph::Glossary.new
    reg   = g.register(0x100000, square_glyf, span: 2)
    image = Glyph::Renderer.new(8, 16, 16).render(reg, 0xffffff_u32)
    DisplayGlyph.show(image)
    image.width.should eq(16)
  end

  it "produces a fresh bitmap after a metrics change" do
    g        = Glyph::Glossary.new
    reg      = g.register(0x100000, square_glyf, size: Glyph::SizeMode::Stretch)
    renderer = Glyph::Renderer.new(8, 16, 16)
    image1   = renderer.render(reg, 0xffffff_u32)
    DisplayGlyph.show(image1)
    image1.width.should eq(8)
    renderer.resize(12, 24, 24)
    image2 = renderer.render(reg, 0xffffff_u32)
    DisplayGlyph.show(image2)
    image2.width.should eq(12)
  end

  it "serves a repeated render from the cache" do
    g        = Glyph::Glossary.new
    reg      = g.register(0x100000, square_glyf, size: Glyph::SizeMode::Stretch)
    renderer = Glyph::Renderer.new(8, 16, 16)
    renderer.render(reg, 0x112233_u32).pixels.should eq(renderer.render(reg, 0x112233_u32).pixels)
  end

  it "evicts the oldest renders when the cache exceeds MAX_CACHE" do
    g        = Glyph::Glossary.new
    reg      = g.register(0x100000, square_glyf, size: Glyph::SizeMode::Stretch)
    renderer = Glyph::Renderer.new(8, 16, 16)

    (Glyph::Renderer::MAX_CACHE + 1).times do |i|
      renderer.render(reg, i.to_u32)
    end

    renderer.cache_size.should eq(Glyph::Renderer::MAX_CACHE)
  end

  it "returns a blank image when a corrupted payload raises mid-render" do
    # Intentionally malformed COLR payload (OOB layer offset)
    io = IO::Memory.new
    io.write_bytes(0_u16, BE)    # version
    io.write_bytes(1_u16, BE)    # num_base
    io.write_bytes(14_u32, BE)   # base_offset
    io.write_bytes(9999_u32, BE) # layer_offset OUT OF BOUNDS!
    io.write_bytes(1_u16, BE)    # num_layers

    # base layer record
    io.write_bytes(0_u16, BE)
    io.write_bytes(0_u16, BE)
    io.write_bytes(1_u16, BE)

    colr = io.to_slice
    cpal = cpal_table([{255_u8, 0_u8, 0_u8, 255_u8}])

    g   = Glyph::Glossary.new
    reg = g.register(0x100000, container([square_glyf], colr, cpal), format: Glyph::Format::Colr)

    renderer = Glyph::Renderer.new(8, 16, 16)
    image    = renderer.render(reg, 0xffffff_u32)

    # Rendering should degrade gracefully via rescue block, returning 0/transparent instead of crashing
    image.pixels.all?(0_u8).should be_true
  end

  it "keys the cache on foreground colour and rendering modes" do
    g        = Glyph::Glossary.new
    reg      = g.register(0x100000, square_glyf, size: Glyph::SizeMode::Stretch)
    renderer = Glyph::Renderer.new(8, 16, 16)

    a = renderer.render(reg, 0xff0000_u32)
    b = renderer.render(reg, 0x00ff00_u32)
    DisplayGlyph.show(a)
    DisplayGlyph.show(b)
    pixel(a, 4, 8).should eq({0xff_u8, 0x00_u8, 0x00_u8, 0xff_u8})
    pixel(b, 4, 8).should eq({0x00_u8, 0xff_u8, 0x00_u8, 0xff_u8})

    # Use a fractional width so edges fall mid-pixel. We render it white (0xffffff)
    # to trigger visible subpixel color fringing.
    reg_frac = g.register(0x100001, square_glyf(333, 1000), size: Glyph::SizeMode::Stretch)
    renderer.subpixel = false
    c = renderer.render(reg_frac, 0xffffff_u32)

    renderer.subpixel = true
    d = renderer.render(reg_frac, 0xffffff_u32)

    c.pixels.should_not eq(d.pixels)
  end

  it "visually compares standard, subpixel, and gamma-correct rendering modes" do
    g = Glyph::Glossary.new

    # Fractional horizontal coverage to clearly show RGB subpixel fringing
    reg_subpx = g.register(0x100000, square_glyf(333, 1000), size: Glyph::SizeMode::Stretch)

    # Overlapping COLR layers to clearly show Gamma-Correct alpha blending
    # (Semi-transparent Green over Solid Red)
    io = IO::Memory.new
    io.write_bytes(0_u16, BE)
    io.write_bytes(1_u16, BE)
    io.write_bytes(14_u32, BE)
    io.write_bytes(20_u32, BE)
    io.write_bytes(2_u16, BE)
    io.write_bytes(0_u16, BE)
    io.write_bytes(0_u16, BE)
    io.write_bytes(2_u16, BE)
    io.write_bytes(0_u16, BE) # Layer 0: GID 0
    io.write_bytes(0_u16, BE) # Layer 0: Palette 0
    io.write_bytes(0_u16, BE) # Layer 1: GID 0
    io.write_bytes(1_u16, BE) # Layer 1: Palette 1
    colr      = io.to_slice
    cpal      = cpal_table([{255_u8, 0_u8, 0_u8, 255_u8}, {0_u8, 255_u8, 0_u8, 128_u8}])
    reg_gamma = g.register(0x100001, container([square_glyf(1000, 1000)], colr, cpal), format: Glyph::Format::Colr)

    renderer = Glyph::Renderer.new(16, 32, 32)

    puts "\n--- Visual comparison (reference: glyph-spec.txt) ---"

    renderer.subpixel = false
    renderer.gamma_correct = false
    img_standard_subpx = renderer.render(reg_subpx, 0xffffff_u32)
    img_standard_gamma = renderer.render(reg_gamma, 0xffffff_u32)
    puts "Standard Mode (Subpixel candidate):"
    DisplayGlyph.show(img_standard_subpx)
    puts "Standard Mode (Gamma candidate):"
    DisplayGlyph.show(img_standard_gamma)

    renderer.subpixel = true
    renderer.gamma_correct = false
    img_subpixel = renderer.render(reg_subpx, 0xffffff_u32)
    puts "Subpixel Anti-Aliasing Mode:"
    DisplayGlyph.show(img_subpixel)

    renderer.subpixel = false
    renderer.gamma_correct = true
    img_gamma = renderer.render(reg_gamma, 0xffffff_u32)
    puts "Gamma-Correct Blending Mode:"
    DisplayGlyph.show(img_gamma)

    renderer.subpixel = true
    renderer.gamma_correct = true
    img_both = renderer.render(reg_gamma, 0xffffff_u32)
    puts "Subpixel + Gamma-Correct Mode:"
    DisplayGlyph.show(img_both)

    img_standard_subpx.pixels.should_not eq(img_subpixel.pixels)
    img_standard_gamma.pixels.should_not eq(img_gamma.pixels)
  end

  it "defaults the baseline to four fifths of the cell" do
    Glyph::Renderer.new(10, 20).baseline.should eq(16)
  end

  it "rejects non-positive cell metrics" do
    expect_raises(ArgumentError) { Glyph::Renderer.new(0, 20) }
    expect_raises(ArgumentError) { Glyph::Renderer.new(10, -1) }
  end
end
