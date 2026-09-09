# bench/glyph_bench.cr
require "./harness"

module GlyphBench
  BE = IO::ByteFormat::BigEndian

  CELL_W   = 10
  CELL_H   = 20
  BASELINE = 16

  def self.glyf(contours : Array(Array(Tuple(Int32, Int32)))) : Bytes
    io     = IO::Memory.new
    points = contours.flatten
    xs     = points.map { |p| p[0] }
    ys     = points.map { |p| p[1] }
    io.write_bytes(contours.size.to_i16, BE)
    io.write_bytes(xs.min.to_i16, BE)
    io.write_bytes(ys.min.to_i16, BE)
    io.write_bytes(xs.max.to_i16, BE)
    io.write_bytes(ys.max.to_i16, BE)
    total = 0
    contours.each do |c|
      total += c.size
      io.write_bytes((total - 1).to_u16, BE)
    end
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

  def self.square : Bytes
    glyf([[{0, 0}, {1000, 0}, {1000, 1000}, {0, 1000}]])
  end

  def self.half : Bytes
    glyf([[{0, 0}, {500, 0}, {500, 1000}, {0, 1000}]])
  end

  def self.ring : Bytes
    glyf([
      [{120, 120}, {880, 120}, {880, 880}, {120, 880}],
      [{300, 700}, {700, 700}, {700, 300}, {300, 300}],
    ])
  end

  def self.cpal(colors : Array(Tuple(UInt8, UInt8, UInt8, UInt8))) : Bytes
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

  def self.colr_v0(layer_glyph : Int32, palette_index : Int32) : Bytes
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

  def self.fvar(axes : Array(Tuple(String, Float64, Float64, Float64))) : Bytes
    io = IO::Memory.new
    io.write_bytes(0x00010000_u32, BE)
    io.write_bytes(16_u16, BE)
    io.write_bytes(2_u16, BE)
    io.write_bytes(axes.size.to_u16, BE)
    io.write_bytes(20_u16, BE)
    io.write_bytes(0_u16, BE)
    io.write_bytes(0_u16, BE)
    axes.each do |ax|
      tag, min, df, max = ax
      tag.each_byte { |b| io.write_byte(b) }
      io.write_bytes((min * 65536).to_i32, BE)
      io.write_bytes((df * 65536).to_i32, BE)
      io.write_bytes((max * 65536).to_i32, BE)
      io.write_bytes(0_u16, BE)
      io.write_bytes(0_u16, BE)
    end
    io.to_slice
  end

  def self.gvar(dx : Int8, dy : Int8) : Bytes
    io = IO::Memory.new
    io.write_bytes(0x00010000_u32, BE)
    io.write_bytes(1_u16, BE)
    io.write_bytes(0_u16, BE)
    io.write_bytes(0_u32, BE)
    io.write_bytes(1_u16, BE)
    io.write_bytes(0_u16, BE)
    io.write_bytes(24_u32, BE)
    io.write_bytes(0_u16, BE)
    io.write_bytes(14_u16, BE)
    io.write_bytes(1_u16, BE)
    io.write_bytes(10_u16, BE)
    io.write_bytes(18_u16, BE)
    io.write_bytes(0x8000_u16, BE)
    io.write_bytes(0x4000_u16, BE)
    io.write_byte(0x07_u8)
    8.times { io.write_byte(dx.to_u8) }
    io.write_byte(0x07_u8)
    8.times { io.write_byte(dy.to_u8) }
    io.to_slice
  end

  def self.container(outlines : Array(Bytes), colr : Bytes, palette : Bytes, fvar : Bytes = Bytes.empty, gvar : Bytes = Bytes.empty) : Bytes
    io = IO::Memory.new
    io.write_bytes(outlines.size.to_u16, BE)
    outlines.each do |o|
      io.write_bytes(o.size.to_u16, BE)
      io.write(o)
    end
    io.write_bytes(colr.size.to_u16, BE)
    io.write(colr)
    io.write_bytes(palette.size.to_u16, BE)
    io.write(palette)
    if fvar.size > 0 || gvar.size > 0
      io.write_bytes(fvar.size.to_u16, BE)
      io.write(fvar)
      io.write_bytes(gvar.size.to_u16, BE)
      io.write(gvar)
    end
    io.to_slice
  end

  class_property held_renderer : Glyph::Renderer? = nil

  def self.run : Nil
    Bench.banner("term-compositor  glyph bench")
    run_parse
    run_geometry
    run_raster
    Bench.footer
  end

  private def self.run_parse : Nil
    Bench.header("parsing and registration")

    square_bytes = square
    ring_bytes   = ring
    fvar_bytes   = fvar([{"wght", 100.0, 400.0, 900.0}])
    gvar_bytes   = gvar(10_i8, 10_i8)

    Bench.run("Glyf.parse   square, 4 points") do
      Bench.consume(Glyph::Glyf.parse(square_bytes).point_count)
    end

    Bench.run("Glyf.parse   ring, 8 points 2 contours") do
      Bench.consume(Glyph::Glyf.parse(ring_bytes).point_count)
    end

    payload = container([square_bytes, half], colr_v0(1, 0),
      cpal([{255_u8, 0_u8, 0_u8, 255_u8}]))

    Bench.run("Container.parse  2 outlines + COLR/CPAL") do
      Bench.consume(Glyph::Container.parse(payload).outlines.size)
    end

    var_payload = container([square_bytes], colr_v0(0, 0), Bytes.empty, fvar_bytes, gvar_bytes)

    glossary = Glyph::Glossary.new(mode: Glyph::Mode::Font)
    cp       = 0x100000
    Bench.run("Glossary#register  ring") do
      cp = cp >= 0x1000FF ? 0x100001 : cp + 1
      Bench.consume(glossary.register(cp, ring_bytes).span)
    end

    Bench.run("Glossary#register  variable font apply") do
      cp = cp >= 0x1000FF ? 0x100001 : cp + 1
      Bench.consume(glossary.register(cp, var_payload, format: Glyph::Format::Colrv0, axes: {"wght" => 700.0}).span)
    end
  end

  private def self.run_geometry : Nil
    Bench.header("geometry  cell #{CELL_W}x#{CELL_H}")

    glossary = Glyph::Glossary.new
    reg      = glossary.register(0x100000, ring, size: Glyph::SizeMode::Contain)
    outline  = Glyph::Glyf.parse(ring)

    Bench.run("Layout.resolve") do
      Bench.consume(Glyph::Layout.resolve(reg, CELL_W, CELL_H, BASELINE).a)
    end

    tf = Glyph::Layout.resolve(reg, CELL_W, CELL_H, BASELINE)

    Bench.run("Path.flatten     ring") do
      Bench.consume(Glyph::Path.flatten(outline, tf).size)
    end

    contours = Glyph::Path.flatten(outline, tf)

    Bench.run("Fill.coverage    #{CELL_W}x#{CELL_H}") do
      Bench.consume(Glyph::Fill.coverage(contours, CELL_W, CELL_H).size)
    end

    Bench.run("Fill.coverage    #{CELL_W * 2}x#{CELL_H * 2}") do
      Bench.consume(Glyph::Fill.coverage(contours, CELL_W * 2, CELL_H * 2).size)
    end

    Bench.run("Transform#concat") do
      Bench.consume(tf.concat(Glyph::Transform.scale(1.5, 1.5)).a)
    end
  end

  private def self.run_raster : Nil
    Bench.header("Glyph::Renderer  cell #{CELL_W}x#{CELL_H}")

    glossary = Glyph::Glossary.new
    reg      = glossary.register(0x100000, ring, size: Glyph::SizeMode::Contain)
    payload = container([square, half], colr_v0(1, 0),
      cpal([{255_u8, 0_u8, 0_u8, 255_u8}]))
    colr = glossary.register(0x100001, payload, format: Glyph::Format::Colrv0,
      size: Glyph::SizeMode::Stretch)

    renderer = Glyph::Renderer.new(CELL_W, CELL_H)
    renderer.render(reg, 0xffffff_u32)
    renderer.render(colr, 0xffffff_u32)

    Bench.run("render  glyf   warm (cache hit)") do
      Bench.consume(renderer.render(reg, 0xffffff_u32).width)
    end

    Bench.run("render  glyf   cold (fresh cache)",
      setup: -> { renderer = Glyph::Renderer.new(CELL_W, CELL_H) }) do
      Bench.consume(renderer.render(reg, 0xffffff_u32).width)
    end

    Bench.run("render  colrv0 cold (fresh cache)",
      setup: -> { renderer = Glyph::Renderer.new(CELL_W, CELL_H) }) do
      Bench.consume(renderer.render(colr, 0xffffff_u32).width)
    end

    Bench.run("render  glyf   cold (subpx + gamma)",
      setup: -> {
        renderer = Glyph::Renderer.new(CELL_W, CELL_H)
        renderer.subpixel = true
        renderer.gamma_correct = true
      }) do
      Bench.consume(renderer.render(reg, 0xffffff_u32).width)
    end

    Bench.retained("512 colours in one Renderer cache") do
      cache           = Glyph::Renderer.new(CELL_W, CELL_H)
      @@held_renderer = cache
      i               = 0
      while i < 512
        cache.render(reg, (0x100000 + i).to_u32)
        i += 1
      end
    end

    image = renderer.render(reg, 0xffffff_u32)
    Bench.note("one cached bitmap", Bench.fmt_bytes(image.pixels.size.to_f))
  end
end

GlyphBench.run
