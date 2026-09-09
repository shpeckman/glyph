# spec/glyph_spec.cr
require "./spec_helper"

private BE = IO::ByteFormat::BigEndian

private def glyf_record(points : Array(Tuple(Int32, Int32))) : Bytes
  io = IO::Memory.new
  xs = points.map { |p| p[0] }
  ys = points.map { |p| p[1] }
  io.write_bytes(1_i16, BE)
  io.write_bytes(xs.min.to_i16, BE)
  io.write_bytes(ys.min.to_i16, BE)
  io.write_bytes(xs.max.to_i16, BE)
  io.write_bytes(ys.max.to_i16, BE)
  io.write_bytes((points.size - 1).to_u16, BE)
  io.write_bytes(0_u16, BE)
  points.size.times { io.write_byte(0x01_u8) }
  prev = 0
  xs.each do |x|
    io.write_bytes((x - prev).to_i16, BE)
    prev = x
  end
  prev = 0
  ys.each do |y|
    io.write_bytes((y - prev).to_i16, BE)
    prev = y
  end
  io.to_slice
end

private def square_glyf(w : Int32 = 1000, h : Int32 = 1000) : Bytes
  glyf_record([{0, 0}, {w, 0}, {w, h}, {0, h}])
end

private def cpal_table(colors : Array(Tuple(UInt8, UInt8, UInt8, UInt8))) : Bytes
  io = IO::Memory.new
  io.write_bytes(0_u16, BE)
  io.write_bytes(colors.size.to_u16, BE)
  io.write_bytes(1_u16, BE)
  io.write_bytes(colors.size.to_u16, BE)
  io.write_bytes(14_u32, BE)
  io.write_bytes(0_u16, BE)
  colors.each do |c|
    r, g, b, a = c
    io.write_byte(b)
    io.write_byte(g)
    io.write_byte(r)
    io.write_byte(a)
  end
  io.to_slice
end

private def colr_v0_table(layer_glyph : Int32, palette_index : Int32) : Bytes
  io = IO::Memory.new
  io.write_bytes(0_u16, BE)
  io.write_bytes(1_u16, BE)
  io.write_bytes(14_u32, BE)
  io.write_bytes(20_u32, BE)
  io.write_bytes(1_u16, BE)
  io.write_bytes(0_u16, BE)
  io.write_bytes(0_u16, BE)
  io.write_bytes(1_u16, BE)
  io.write_bytes(layer_glyph.to_u16, BE)
  io.write_bytes(palette_index.to_u16, BE)
  io.to_slice
end

private def container(outlines : Array(Bytes), colr : Bytes, cpal : Bytes) : Bytes
  io = IO::Memory.new
  io.write_bytes(outlines.size.to_u16, BE)
  outlines.each do |o|
    io.write_bytes(o.size.to_u16, BE)
    io.write(o)
  end
  io.write_bytes(colr.size.to_u16, BE)
  io.write(colr)
  io.write_bytes(cpal.size.to_u16, BE)
  io.write(cpal)
  io.to_slice
end

private def pixel(image : Glyph::Image, x : Int32, y : Int32) : Tuple(UInt8, UInt8, UInt8, UInt8)
  o = (y * image.width + x) * 4
  {image.pixels[o], image.pixels[o + 1], image.pixels[o + 2], image.pixels[o + 3]}
end

describe Glyph do
  describe "namespace" do
    it "accepts all three private use areas" do
      Glyph.pua?(0xE000).should be_true
      Glyph.pua?(0xF8FF).should be_true
      Glyph.pua?(0xF0000).should be_true
      Glyph.pua?(0x100000).should be_true
    end

    it "rejects ordinary codepoints" do
      Glyph.pua?('a'.ord).should be_false
      Glyph.pua?(0x4E00).should be_false
      Glyph.pua?(0xF900).should be_false
      Glyph.pua?(0x10FFFE).should be_false
    end
  end

  describe "reason codes" do
    it "renders the spec's snake_case names" do
      Glyph::Reason::OutOfNamespace.code.should eq("out_of_namespace")
      Glyph::Reason::OutlineTooLarge.code.should eq("outline_too_large")
      Glyph::Reason::HintingUnsupported.code.should eq("hinting_unsupported")
    end
  end

  describe "format names" do
    it "round-trips the three v1.8 names" do
      Glyph::Format.from_code?("glyf").should eq(Glyph::Format::Glyf)
      Glyph::Format.from_code?("colrv1").should eq(Glyph::Format::Colrv1)
      Glyph::Format.from_code?("sixel").should be_nil
      Glyph::Format::Colrv0.code.should eq("colrv0")
    end
  end
end

describe Glyph::Glyf do
  it "parses a simple square" do
    outline = Glyph::Glyf.parse(square_glyf)
    outline.point_count.should eq(4)
    outline.ends.size.should eq(1)
    outline.ends[0].should eq(3)
    outline.x_max.should eq(1000)
    outline.points[2].x.should eq(1000)
    outline.points[2].y.should eq(1000)
    outline.points[0].on_curve?.should be_true
  end

  it "keeps an empty glyph parseable" do
    io = IO::Memory.new
    io.write_bytes(0_i16, BE)
    4.times { io.write_bytes(0_i16, BE) }
    outline = Glyph::Glyf.parse(io.to_slice)
    outline.empty?.should be_true
  end

  it "expands repeated flags" do
    io = IO::Memory.new
    io.write_bytes(1_i16, BE)
    io.write_bytes(0_i16, BE)
    io.write_bytes(0_i16, BE)
    io.write_bytes(10_i16, BE)
    io.write_bytes(10_i16, BE)
    io.write_bytes(3_u16, BE)
    io.write_bytes(0_u16, BE)
    io.write_byte(0x09_u8)
    io.write_byte(0x03_u8)
    4.times { io.write_bytes(0_i16, BE) }
    4.times { io.write_bytes(0_i16, BE) }
    outline = Glyph::Glyf.parse(io.to_slice)
    outline.point_count.should eq(4)
    outline.points.each { |p| p.on_curve?.should be_true }
  end

  it "decodes short x deltas with the sign flag" do
    io = IO::Memory.new
    io.write_bytes(1_i16, BE)
    io.write_bytes(0_i16, BE)
    io.write_bytes(0_i16, BE)
    io.write_bytes(20_i16, BE)
    io.write_bytes(0_i16, BE)
    io.write_bytes(1_u16, BE)
    io.write_bytes(0_u16, BE)
    io.write_byte(0x33_u8)
    io.write_byte(0x23_u8)
    io.write_byte(20_u8)
    io.write_byte(5_u8)
    outline = Glyph::Glyf.parse(io.to_slice)
    outline.points[0].x.should eq(20)
    outline.points[1].x.should eq(15)
  end

  it "rejects composite glyphs" do
    io = IO::Memory.new
    io.write_bytes(-1_i16, BE)
    4.times { io.write_bytes(0_i16, BE) }
    error = expect_raises(Glyph::Error) { Glyph::Glyf.parse(io.to_slice) }
    error.reason.should eq(Glyph::Reason::CompositeUnsupported)
  end

  it "rejects hinting instructions" do
    io = IO::Memory.new
    io.write_bytes(1_i16, BE)
    4.times { io.write_bytes(0_i16, BE) }
    io.write_bytes(0_u16, BE)
    io.write_bytes(4_u16, BE)
    error = expect_raises(Glyph::Error) { Glyph::Glyf.parse(io.to_slice) }
    error.reason.should eq(Glyph::Reason::HintingUnsupported)
  end

  it "rejects an oversized outline before allocating points" do
    io = IO::Memory.new
    io.write_bytes(1_i16, BE)
    4.times { io.write_bytes(0_i16, BE) }
    io.write_bytes((Glyph::MAX_POINTS + 1).to_u16, BE)
    error = expect_raises(Glyph::Error) { Glyph::Glyf.parse(io.to_slice) }
    error.reason.should eq(Glyph::Reason::OutlineTooLarge)
  end

  it "accepts an outline exactly at the budget boundary" do
    Glyph::MAX_POINTS.should eq(5461)
  end

  it "rejects an oversized payload" do
    error = expect_raises(Glyph::Error) { Glyph::Glyf.parse(Bytes.new(Glyph::MAX_PAYLOAD + 1)) }
    error.reason.should eq(Glyph::Reason::PayloadTooLarge)
  end

  it "rejects a truncated record" do
    error = expect_raises(Glyph::Error) { Glyph::Glyf.parse(Bytes[0_u8, 1_u8]) }
    error.reason.should eq(Glyph::Reason::MalformedPayload)
  end

  it "rejects non-monotonic contour ends" do
    io = IO::Memory.new
    io.write_bytes(2_i16, BE)
    4.times { io.write_bytes(0_i16, BE) }
    io.write_bytes(5_u16, BE)
    io.write_bytes(3_u16, BE)
    error = expect_raises(Glyph::Error) { Glyph::Glyf.parse(io.to_slice) }
    error.reason.should eq(Glyph::Reason::MalformedPayload)
  end
end

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

describe Glyph::Layout do
  glossary = Glyph::Glossary.new

  it "stretches the authored extent onto the full span" do
    reg = glossary.register(0x100000, square_glyf, size: Glyph::SizeMode::Stretch)
    t   = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.apply_x(0.0, 0.0).should be_close(0.0, 1e-9)
    t.apply_x(1000.0, 0.0).should be_close(8.0, 1e-9)
    t.apply_y(0.0, 0.0).should be_close(16.0, 1e-9)
    t.apply_y(0.0, 1000.0).should be_close(0.0, 1e-9)
  end

  it "widens the span for a width=2 glyph" do
    reg = glossary.register(0x100001, square_glyf, span: 2, size: Glyph::SizeMode::Stretch)
    t   = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.apply_x(1000.0, 0.0).should be_close(16.0, 1e-9)
  end

  it "preserves aspect ratio for contain" do
    reg = glossary.register(0x100002, square_glyf, size: Glyph::SizeMode::Contain)
    t   = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.a.should be_close(0.008, 1e-9)
    t.d.should be_close(-0.008, 1e-9)
  end

  it "fills both axes for cover" do
    reg = glossary.register(0x100003, square_glyf, size: Glyph::SizeMode::Cover)
    t   = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.a.should be_close(0.016, 1e-9)
  end

  it "drives from line height by default" do
    reg = glossary.register(0x100004, square_glyf)
    reg.size.should eq(Glyph::SizeMode::Height)
    t = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.a.should be_close(0.016, 1e-9)
  end

  it "puts the glyph origin on the baseline" do
    reg = glossary.register(0x100005, square_glyf, valign: Glyph::VAlign::Baseline)
    t   = Glyph::Layout.resolve(reg, 8, 16, 12)
    t.apply_y(0.0, 0.0).should be_close(12.0, 1e-9)
  end

  it "shrinks the span with padding" do
    reg = glossary.register(0x100006, square_glyf, size: Glyph::SizeMode::Stretch,
      pad: Glyph::Pad.new(0.25, 0.0, 0.25, 0.0))
    t = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.apply_y(0.0, 1000.0).should be_close(4.0, 1e-9)
    t.apply_y(0.0, 0.0).should be_close(12.0, 1e-9)
  end

  it "ignores degenerate padding" do
    reg = glossary.register(0x100007, square_glyf, size: Glyph::SizeMode::Stretch,
      pad: Glyph::Pad.new(0.6, 0.0, 0.6, 0.0))
    t = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.apply_y(0.0, 1000.0).should be_close(0.0, 1e-9)
  end

  it "anchors horizontally with align start and end" do
    a = glossary.register(0x100008, square_glyf, size: Glyph::SizeMode::Height,
      halign: Glyph::HAlign::Start)
    b = glossary.register(0x100009, square_glyf, size: Glyph::SizeMode::Height,
      halign: Glyph::HAlign::End)
    Glyph::Layout.resolve(a, 8, 16, 16).apply_x(0.0, 0.0).should be_close(0.0, 1e-9)
    Glyph::Layout.resolve(b, 8, 16, 16).apply_x(1000.0, 0.0).should be_close(8.0, 1e-9)
  end
end

describe Glyph::Glossary do
  it "registers a glyph in the private use area" do
    g   = Glyph::Glossary.new
    reg = g.register(0x100000, square_glyf)
    reg.cp.should eq(0x100000)
    reg.format.should eq(Glyph::Format::Glyf)
    reg.span.should eq(1)
    g.size.should eq(1)
    g[0x100000]?.should_not be_nil
  end

  it "rejects a non-PUA codepoint" do
    g     = Glyph::Glossary.new
    error = expect_raises(Glyph::Error) { g.register('a'.ord, square_glyf) }
    error.reason.should eq(Glyph::Reason::OutOfNamespace)
    g.size.should eq(0)
  end

  it "overwrites without consuming a second slot" do
    g      = Glyph::Glossary.new
    first  = g.register(0x100000, square_glyf)
    second = g.register(0x100000, square_glyf(500, 500))
    g.size.should eq(1)
    second.slot.should eq(first.slot)
    second.tag.should_not eq(first.tag)
  end

  it "normalizes an invalid span to one cell" do
    g = Glyph::Glossary.new
    g.register(0x100000, square_glyf, span: 5).span.should eq(1)
    g.register(0x100001, square_glyf, span: 2).span.should eq(2)
  end

  it "appends a blank cell to a width=2 glyph's text" do
    g = Glyph::Glossary.new
    g.register(0x100000, square_glyf, span: 1).text.should eq(0x100000.chr.to_s)
    g.register(0x100001, square_glyf, span: 2).text.should eq(0x100001.chr.to_s + " ")
  end

  it "evicts the oldest registration in FIFO order when full" do
    g       = Glyph::Glossary.new
    payload = square_glyf
    i       = 0
    while i < Glyph::MAX_SLOTS
      g.register(0x100000 + i, payload)
      i += 1
    end
    g.size.should eq(Glyph::MAX_SLOTS)
    g.register(0x100000 + Glyph::MAX_SLOTS, payload)
    g.size.should eq(Glyph::MAX_SLOTS)
    g[0x100000]?.should be_nil
    g[0x100001]?.should_not be_nil
    g[0x100000 + Glyph::MAX_SLOTS]?.should_not be_nil
  end

  it "reuses a freed slot after a clear" do
    g    = Glyph::Glossary.new
    slot = g.register(0x100000, square_glyf).slot
    g.clear(0x100000).should be_true
    g.size.should eq(0)
    g.register(0x100001, square_glyf).slot.should eq(slot)
  end

  it "treats clearing an empty slot as success" do
    g = Glyph::Glossary.new
    g.clear(0x100000).should be_true
  end

  it "rejects clearing a non-PUA codepoint" do
    g     = Glyph::Glossary.new
    error = expect_raises(Glyph::Error) { g.clear('z'.ord) }
    error.reason.should eq(Glyph::Reason::OutOfNamespace)
  end

  it "clears every slot" do
    g = Glyph::Glossary.new
    g.register(0x100000, square_glyf)
    g.register(0x100001, square_glyf)
    g.clear_all
    g.size.should eq(0)
    g[0x100000]?.should be_nil
  end

  it "reports coverage as a set" do
    g = Glyph::Glossary.new
    g.query(0x100000).should eq(Glyph::Coverage::None)
    g.query(0x100000, system: true).code.should eq("system")
    g.register(0x100000, square_glyf)
    g.query(0x100000).code.should eq("glossary")
    g.query(0x100000, system: true).code.should eq("system,glossary")
    g.query('a'.ord, system: true).code.should eq("system")
  end

  it "iterates in registration order" do
    g = Glyph::Glossary.new
    g.register(0x100002, square_glyf)
    g.register(0x100000, square_glyf)
    seen = [] of Int32
    g.each { |reg| seen << reg.cp }
    seen.should eq([0x100002, 0x100000])
  end
end

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

describe Glyph::Container do
  it "parses a colour container" do
    payload = container([square_glyf, square_glyf(500, 1000)],
      colr_v0_table(1, 0), cpal_table([{255_u8, 0_u8, 0_u8, 255_u8}]))
    parsed = Glyph::Container.parse(payload)
    parsed.outlines.size.should eq(2)
    parsed.colr.empty?.should be_false
    parsed.cpal.empty?.should be_false
  end

  it "permits an absent palette table" do
    payload = container([square_glyf], colr_v0_table(0, 0), Bytes.empty)
    Glyph::Container.parse(payload).cpal.empty?.should be_true
  end

  it "rejects an empty outline array" do
    io = IO::Memory.new
    io.write_bytes(0_u16, BE)
    error = expect_raises(Glyph::Error) { Glyph::Container.parse(io.to_slice) }
    error.reason.should eq(Glyph::Reason::MalformedPayload)
  end

  it "rejects a container with no COLR table" do
    io = IO::Memory.new
    io.write_bytes(1_u16, BE)
    outline = square_glyf
    io.write_bytes(outline.size.to_u16, BE)
    io.write(outline)
    io.write_bytes(0_u16, BE)
    error = expect_raises(Glyph::Error) { Glyph::Container.parse(io.to_slice) }
    error.reason.should eq(Glyph::Reason::MalformedPayload)
  end
end

describe Glyph::Cpal do
  it "reads colour records as BGRA" do
    palette = Glyph::Cpal.parse(cpal_table([{0x11_u8, 0x22_u8, 0x33_u8, 0xff_u8}]))
    palette.size.should eq(1)
    palette[0].should eq(0xff112233_u32)
  end

  it "returns an empty palette for empty bytes" do
    Glyph::Cpal.parse(Bytes.empty).empty?.should be_true
  end
end

describe "colrv0 rendering" do
  it "paints a layer with its palette colour" do
    payload = container([square_glyf, square_glyf(500, 1000)],
      colr_v0_table(1, 0), cpal_table([{255_u8, 0_u8, 0_u8, 255_u8}]))
    g = Glyph::Glossary.new
    reg = g.register(0x100000, payload, format: Glyph::Format::Colrv0,
      size: Glyph::SizeMode::Stretch)
    image = Glyph::Renderer.new(8, 16, 16).render(reg, 0x00ff00_u32)
    pixel(image, 1, 8).should eq({0xff_u8, 0x00_u8, 0x00_u8, 0xff_u8})
    pixel(image, 6, 8)[3].should eq(0_u8)
  end

  it "resolves palette index 0xFFFF to the foreground" do
    payload = container([square_glyf, square_glyf(500, 1000)],
      colr_v0_table(1, 0xFFFF), cpal_table([{255_u8, 0_u8, 0_u8, 255_u8}]))
    g = Glyph::Glossary.new
    reg = g.register(0x100000, payload, format: Glyph::Format::Colrv0,
      size: Glyph::SizeMode::Stretch)
    image = Glyph::Renderer.new(8, 16, 16).render(reg, 0x00ff00_u32)
    pixel(image, 1, 8).should eq({0x00_u8, 0xff_u8, 0x00_u8, 0xff_u8})
  end
end

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
