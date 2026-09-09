# src/glyph/parsers/container.cr

module Glyph
  struct Container
    getter outlines : Array(Outline)
    getter colr     : Bytes
    getter cpal     : Bytes

    def initialize(@outlines : Array(Outline), @colr : Bytes, @cpal : Bytes)
    end

    def self.parse(bytes : Bytes) : Container
      raise Error.new(Reason::PayloadTooLarge) if bytes.size > MAX_PAYLOAD
      r     = Reader.new(bytes)
      count = r.u16.to_i32
      raise Error.new(Reason::MalformedPayload) if count < 1 || count > MAX_CONTAINER
      outlines = Array(Outline).new(count)
      budget   = 0
      i        = 0
      while i < count
        len     = r.u16.to_i32
        outline = Glyf.parse(r.slice(len), outlines)
        budget += outline.point_count * POINT_COST
        raise Error.new(Reason::OutlineTooLarge) if budget > DECODED_BUDGET
        outlines << outline
        i += 1
      end
      colr_len = r.u16.to_i32
      raise Error.new(Reason::MalformedPayload) if colr_len <= 0
      colr     = r.slice(colr_len)
      cpal_len = r.u16.to_i32
      cpal     = cpal_len > 0 ? r.slice(cpal_len) : Bytes.empty
      Container.new(outlines, colr, cpal)
    end
  end
end
