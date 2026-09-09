# spec/spec_helper.cr
require "spec"
require "../src/glyph"
require "../tools/display_glyph"

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

def cpal_table(colors : Array(Tuple(UInt8, UInt8, UInt8, UInt8))) : Bytes
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

def colr_v0_table(layer_glyph : Int32, palette_index : Int32) : Bytes
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

def container(outlines : Array(Bytes), colr : Bytes, cpal : Bytes) : Bytes
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

def pixel(image : Glyph::Image, x : Int32, y : Int32) : Tuple(UInt8, UInt8, UInt8, UInt8)
  o = (y * image.width + x) * 4
  {image.pixels[o], image.pixels[o + 1], image.pixels[o + 2], image.pixels[o + 3]}
end
