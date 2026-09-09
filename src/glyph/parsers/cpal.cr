# src/glyph/parsers/cpal.cr
module Glyph
  module Cpal
    def self.parse(bytes : Bytes) : Array(UInt32)
      return [] of UInt32 if bytes.empty?
      r = Reader.new(bytes)
      r.u16
      entries  = r.u16.to_i32
      palettes = r.u16.to_i32
      records  = r.u16.to_i32
      first    = r.u32.to_i32
      return [] of UInt32 if palettes < 1 || entries < 1 || records < 1
      index  = r.u16.to_i32
      colors = Array(UInt32).new(entries)
      i      = 0
      while i < entries
        slot = index + i
        if slot >= records
          colors << 0xff000000_u32
        else
          r.seek(first + slot * 4)
          b   = r.u8.to_u32
          g   = r.u8.to_u32
          red = r.u8.to_u32
          a   = r.u8.to_u32
          colors << ((a << 24) | (red << 16) | (g << 8) | b)
        end
        i += 1
      end
      colors
    end
  end
end
