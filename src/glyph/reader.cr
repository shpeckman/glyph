# src/glyph/reader.cr
module Glyph
  class Reader
    getter pos : Int32

    def initialize(@bytes : Bytes)
      @pos = 0
    end

    def size : Int32
      @bytes.size
    end

    def seek(pos : Int32) : Nil
      raise Error.new(Error::Reason::MalformedPayload) if pos < 0 || pos > @bytes.size
      @pos = pos
    end

    def remaining : Int32
      @bytes.size - @pos
    end

    def u8 : UInt8
      need(1)
      v = @bytes.unsafe_fetch(@pos)
      @pos += 1
      v
    end

    def i8 : Int32
      v = u8.to_i32
      v >= 0x80 ? v - 0x100 : v
    end

    def u16 : UInt16
      need(2)
      v = (@bytes.unsafe_fetch(@pos).to_u16 << 8) | @bytes.unsafe_fetch(@pos + 1).to_u16
      @pos += 2
      v
    end

    def i16 : Int32
      v = u16.to_i32
      v >= 0x8000 ? v - 0x10000 : v
    end

    def u24 : Int32
      need(3)
      v = (@bytes.unsafe_fetch(@pos).to_i32 << 16) |
          (@bytes.unsafe_fetch(@pos + 1).to_i32 << 8) |
          @bytes.unsafe_fetch(@pos + 2).to_i32
      @pos += 3
      v
    end

    def u32 : UInt32
      need(4)
      v = (@bytes.unsafe_fetch(@pos).to_u32 << 24) |
          (@bytes.unsafe_fetch(@pos + 1).to_u32 << 16) |
          (@bytes.unsafe_fetch(@pos + 2).to_u32 << 8) |
          @bytes.unsafe_fetch(@pos + 3).to_u32
      @pos += 4
      v
    end

    def f2dot14 : Float64
      i16 / 16384.0
    end

    def fixed : Float64
      v = u32.to_i64
      v -= 0x100000000_i64 if v >= 0x80000000_i64
      v / 65536.0
    end

    def slice(len : Int32) : Bytes
      raise Error.new(Error::Reason::MalformedPayload) if len < 0
      need(len)
      v = @bytes[@pos, len]
      @pos += len
      v
    end

    private def need(n : Int32) : Nil
      raise Error.new(Error::Reason::MalformedPayload) if @pos + n > @bytes.size
    end
  end
end
