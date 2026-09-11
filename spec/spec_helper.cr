# spec/spec_helper.cr
# # spec/spec_helper.cr
require "spec"
require "base64"
require "../src/glyph"

module DisplayGlyph
  def self.show(image : Glyph::Image) : Nil
    b64        = Base64.strict_encode(image.pixels)
    chunk_size = 4096
    offset     = 0

    while offset < b64.size
      chunk = b64.byte_slice(offset, chunk_size)
      offset += chunk_size
      m = offset < b64.size ? 1 : 0

      if offset == chunk_size
        print "\e_Ga=T,f=32,s=#{image.width},v=#{image.height},m=#{m};#{chunk}\e\\"
      else
        print "\e_Gm=#{m};#{chunk}\e\\"
      end
    end
    puts
  end
end

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

def fvar_table(axes : Array(Tuple(String, Float64, Float64, Float64))) : Bytes
  io = IO::Memory.new
  io.write_bytes(0x00010000_u32, BE) # version
  io.write_bytes(16_u16, BE)         # offset
  io.write_bytes(2_u16, BE)          # countSizePairs
  io.write_bytes(axes.size.to_u16, BE)
  io.write_bytes(20_u16, BE) # axisSize
  io.write_bytes(0_u16, BE)  # instanceCount
  io.write_bytes(0_u16, BE)  # instanceSize
  axes.each do |ax|
    tag, min, df, max = ax
    tag.each_byte { |b| io.write_byte(b) }
    io.write_bytes((min * 65536).to_i32, BE)
    io.write_bytes((df * 65536).to_i32, BE)
    io.write_bytes((max * 65536).to_i32, BE)
    io.write_bytes(0_u16, BE) # flags
    io.write_bytes(0_u16, BE) # nameID
  end
  io.to_slice
end

def simple_gvar_table(dx : Int8, dy : Int8) : Bytes
  io = IO::Memory.new
  io.write_bytes(0x00010000_u32, BE) # version
  io.write_bytes(1_u16, BE)          # axis_count
  io.write_bytes(0_u16, BE)          # shared_tuple_count
  io.write_bytes(0_u32, BE)          # shared_tuples_offset
  io.write_bytes(1_u16, BE)          # glyph_count
  io.write_bytes(0_u16, BE)          # flags (short offsets)
  io.write_bytes(24_u32, BE)         # data_offset (20 header + 4 offsets)

  # Offsets
  io.write_bytes(0_u16, BE) # glyph 0 start
  # Tuple data length = 4 (header) + 6 (tuple header) + 18 (deltas) = 28 bytes / 2 = 14
  io.write_bytes(14_u16, BE) # glyph 0 end

  # Glyph 0 Data
  io.write_bytes(1_u16, BE)  # tuple_count_flags (1 tuple)
  io.write_bytes(10_u16, BE) # tuple_data_offset (4 + 6 = 10)

  # Tuple header
  io.write_bytes(18_u16, BE)     # size of delta data
  io.write_bytes(0x8000_u16, BE) # idx (embedded peak)
  io.write_bytes(0x4000_u16, BE) # peak (1.0 in f2dot14)

  # Packed deltas X (8 points: 4 outline + 4 phantom)
  io.write_byte(0x07_u8) # control = 8 items, 8-bit
  8.times { io.write_byte(dx.to_u8) }

  # Packed deltas Y (8 points)
  io.write_byte(0x07_u8) # control = 8 items, 8-bit
  8.times { io.write_byte(dy.to_u8) }

  io.to_slice
end

def shared_points_gvar_table(dx : Int8, dy : Int8) : Bytes
  io = IO::Memory.new
  io.write_bytes(0x00010000_u32, BE) # version
  io.write_bytes(1_u16, BE)          # axis_count
  io.write_bytes(0_u16, BE)          # shared_tuple_count
  io.write_bytes(0_u32, BE)          # shared_tuples_offset
  io.write_bytes(1_u16, BE)          # glyph_count
  io.write_bytes(0_u16, BE)          # flags (short offsets)
  io.write_bytes(24_u32, BE)         # data_offset

  # Offsets
  io.write_bytes(0_u16, BE)  # glyph 0 start
  io.write_bytes(13_u16, BE) # glyph 0 end (13 * 2 = 26 bytes data)

  # Glyph 0 Data (Start: 0)
  io.write_bytes(0x8001_u16, BE) # tuple_count_flags (1 tuple + SHARED POINTS)
  io.write_bytes(10_u16, BE)     # tuple_data_offset (4 base header + 6 tuple header)

  # Tuple header (Start: 4)
  io.write_bytes(10_u16, BE)     # size of delta data (10 bytes: 5 for X, 5 for Y)
  io.write_bytes(0x8000_u16, BE) # idx (embedded peak)
  io.write_bytes(0x4000_u16, BE) # peak (1.0 in f2dot14)

  # Shared points (Start: 10, positioned exactly at tuple_data_offset)
  io.write_byte(0x04_u8) # count = 4
  io.write_byte(0x03_u8) # control = 4 items
  io.write_byte(0x00_u8) # pt 0 = 0
  io.write_byte(0x01_u8) # pt 1 = +1
  io.write_byte(0x01_u8) # pt 2 = +1
  io.write_byte(0x01_u8) # pt 3 = +1

  # Packed deltas X (Start: 16)
  io.write_byte(0x03_u8) # control = 4 items, 8-bit
  4.times { io.write_byte(dx.to_u8) }

  # Packed deltas Y (Start: 21)
  io.write_byte(0x03_u8) # control = 4 items, 8-bit
  4.times { io.write_byte(dy.to_u8) }

  io.to_slice
end

def container(outlines : Array(Bytes), colr : Bytes, cpal : Bytes, fvar : Bytes = Bytes.empty, gvar : Bytes = Bytes.empty) : Bytes
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
  if fvar.size > 0 || gvar.size > 0
    io.write_bytes(fvar.size.to_u16, BE)
    io.write(fvar)
    io.write_bytes(gvar.size.to_u16, BE)
    io.write(gvar)
  end
  io.to_slice
end

def pixel(image : Glyph::Image, x : Int32, y : Int32) : Tuple(UInt8, UInt8, UInt8, UInt8)
  o = (y * image.width + x) * 4
  {image.pixels[o], image.pixels[o + 1], image.pixels[o + 2], image.pixels[o + 3]}
end
