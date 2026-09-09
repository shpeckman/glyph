# examples/util/extractor.cr
require "../../src/glyph"

module Extractor
  def self.extract(path : String, codepoint : Int32) : Tuple(Glyph::Format, Bytes, Int32)
    bytes = File.read(path).to_slice
    r     = Glyph::Reader.new(bytes)

    tag = String.new(r.slice(4))
    if tag == "ttcf"
      r.u32 # version
      num_fonts         = r.u32.to_i32!
      first_font_offset = r.u32.to_i32!
      r.seek(first_font_offset)
      tag = String.new(r.slice(4))
    end

    num_tables = r.u16.to_i32!
    r.seek(r.pos + 6) # skip searchRange, entrySelector, rangeShift

    tables = {} of String => Tuple(Int32, Int32)
    num_tables.times do
      table_tag = String.new(r.slice(4))
      r.u32 # checksum
      offset = r.u32.to_i32!
      length = r.u32.to_i32!
      tables[table_tag] = {offset, length}
    end

    upm = 1000
    if head = tables["head"]?
      r.seek(head[0] + 18)
      upm = r.u16.to_i32!
    end

    glyph_id = 0
    if cmap = tables["cmap"]?
      r.seek(cmap[0])
      r.u16 # version
      num_subtables = r.u16.to_i32!
      sub_offset    = 0
      num_subtables.times do
        pid = r.u16.to_i32!
        eid = r.u16.to_i32!
        off = r.u32.to_i32!
        if pid == 3 && (eid == 1 || eid == 10)
          sub_offset = cmap[0] + off
        end
      end

      if sub_offset > 0
        r.seek(sub_offset)
        format = r.u16.to_i32!
        if format == 4
          r.u16 # length
          r.u16 # language
          seg_count = r.u16.to_i32! // 2
          r.seek(r.pos + 6)

          end_codes = [] of Int32
          seg_count.times { end_codes << r.u16.to_i32! }
          r.u16 # reservedPad
          start_codes = [] of Int32
          seg_count.times { start_codes << r.u16.to_i32! }
          id_deltas = [] of Int32
          seg_count.times { id_deltas << r.i16 }

          id_range_offsets_pos = r.pos
          id_range_offsets     = [] of Int32
          seg_count.times { id_range_offsets << r.u16.to_i32! }

          seg_count.times do |i|
            if codepoint <= end_codes[i] && codepoint >= start_codes[i]
              if id_range_offsets[i] == 0
                glyph_id = (codepoint + id_deltas[i]) & 0xFFFF
              else
                ro_pos  = id_range_offsets_pos + i * 2
                idx_pos = ro_pos + id_range_offsets[i] + (codepoint - start_codes[i]) * 2
                r.seek(idx_pos)
                g        = r.u16.to_i32!
                glyph_id = (g + id_deltas[i]) & 0xFFFF if g != 0
              end
              break
            end
          end
        elsif format == 12
          r.u16 # reserved
          r.u32 # length
          r.u32 # language
          num_groups = r.u32.to_i32!
          num_groups.times do
            sc  = r.u32.to_i32!
            ec  = r.u32.to_i32!
            scd = r.u32.to_i32!
            if codepoint >= sc && codepoint <= ec
              glyph_id = scd + (codepoint - sc)
              break
            end
          end
        end
      end
    end

    glyf_bytes = Bytes.empty
    if tables.has_key?("head") && tables.has_key?("loca") && tables.has_key?("glyf")
      r.seek(tables["head"][0] + 50)
      loc_fmt = r.i16

      r.seek(tables["loca"][0] + (loc_fmt == 0 ? glyph_id * 2 : glyph_id * 4))
      if loc_fmt == 0
        o1 = r.u16.to_i32! * 2
        o2 = r.u16.to_i32! * 2
      else
        o1 = r.u32.to_i32!
        o2 = r.u32.to_i32!
      end

      if o2 > o1
        r.seek(tables["glyf"][0] + o1)
        glyf_bytes = r.slice(o2 - o1)
      end
    end

    if glyf_bytes.empty?
      io = IO::Memory.new
      io.write_bytes(0_i16, IO::ByteFormat::BigEndian)
      4.times { io.write_bytes(0_i16, IO::ByteFormat::BigEndian) }
      glyf_bytes = io.to_slice
    end

    fvar_bytes = tables.has_key?("fvar") ? bytes[tables["fvar"][0], tables["fvar"][1]] : Bytes.empty
    gvar_bytes = tables.has_key?("gvar") ? bytes[tables["gvar"][0], tables["gvar"][1]] : Bytes.empty

    if fvar_bytes.size > 0 || gvar_bytes.size > 0
      io = IO::Memory.new
      io.write_bytes(1_u16, IO::ByteFormat::BigEndian)
      io.write_bytes(glyf_bytes.size.to_u16, IO::ByteFormat::BigEndian)
      io.write(glyf_bytes)
      io.write_bytes(0_u16, IO::ByteFormat::BigEndian) # colr size
      io.write_bytes(0_u16, IO::ByteFormat::BigEndian) # cpal size
      io.write_bytes(fvar_bytes.size.to_u16, IO::ByteFormat::BigEndian)
      io.write(fvar_bytes)
      io.write_bytes(gvar_bytes.size.to_u16, IO::ByteFormat::BigEndian)
      io.write(gvar_bytes)
      return {Glyph::Format::Colrv0, io.to_slice, upm}
    end

    {Glyph::Format::Glyf, glyf_bytes, upm}
  end
end
