# examples/color_compositor.cr
require "../src/glyph"
require "./util/display_glyph"

BE = IO::ByteFormat::BigEndian

def glyf_record(points : Array(Tuple(Int32, Int32))) : Bytes
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

def square_glyf(w : Int32 = 1000, h : Int32 = 1000) : Bytes
  glyf_record([{0, 0}, {w, 0}, {w, h}, {0, h}])
end

io = IO::Memory.new
io.write_bytes(2_u16, BE)

sq1 = square_glyf(1000, 1000)
io.write_bytes(sq1.size.to_u16, BE)
io.write(sq1)

sq2 = square_glyf(500, 500)
io.write_bytes(sq2.size.to_u16, BE)
io.write(sq2)

colr = IO::Memory.new
colr.write_bytes(0_u16, BE)
colr.write_bytes(1_u16, BE)
colr.write_bytes(14_u32, BE)
colr.write_bytes(20_u32, BE)
colr.write_bytes(2_u16, BE)
colr.write_bytes(0_u16, BE)
colr.write_bytes(0_u16, BE)
colr.write_bytes(2_u16, BE)
colr.write_bytes(0_u16, BE)
colr.write_bytes(0_u16, BE)
colr.write_bytes(1_u16, BE)
colr.write_bytes(1_u16, BE)
colr_bytes = colr.to_slice

io.write_bytes(colr_bytes.size.to_u16, BE)
io.write(colr_bytes)

cpal = IO::Memory.new
cpal.write_bytes(0_u16, BE)
cpal.write_bytes(2_u16, BE)
cpal.write_bytes(1_u16, BE)
cpal.write_bytes(2_u16, BE)
cpal.write_bytes(14_u32, BE)
cpal.write_bytes(0_u16, BE)
cpal.write_byte(0_u8)
cpal.write_byte(0_u8)
cpal.write_byte(255_u8)
cpal.write_byte(255_u8)
cpal.write_byte(0_u8)
cpal.write_byte(255_u8)
cpal.write_byte(0_u8)
cpal.write_byte(128_u8)
cpal_bytes = cpal.to_slice

io.write_bytes(cpal_bytes.size.to_u16, BE)
io.write(cpal_bytes)

payload = io.to_slice

glossary = Glyph::Glossary.new
reg      = glossary.register(0xE000, payload, format: Glyph::Format::Colrv0, size: Glyph::SizeMode::Stretch)

renderer = Glyph::Renderer.new(64, 64)
renderer.gamma_correct = true
image = renderer.render(reg, 0xFFFFFF_u32)

puts "Gamma-Correct Alpha Compositing (COLRv0):"
DisplayGlyph.show(image)
