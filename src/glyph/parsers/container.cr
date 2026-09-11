# src/glyph/parsers/container.cr

module Glyph
  struct Container
    getter outlines : Array(Outline)
    getter colr     : Bytes
    getter cpal     : Bytes
    getter fvar     : Bytes
    getter gvar     : Bytes

    def initialize(@outlines : Array(Outline), @colr : Bytes, @cpal : Bytes, @fvar : Bytes = Bytes.empty, @gvar : Bytes = Bytes.empty)
    end

    def self.parse(bytes : Bytes) : Container
      raise Error.new(Error::Reason::PayloadTooLarge) if bytes.size > MAX_PAYLOAD
      r     = Reader.new(bytes)
      count = r.u16.to_i32
      raise Error.new(Error::Reason::MalformedPayload) if count < 1 || count > MAX_CONTAINER

      outlines = Array(Outline).new(count)
      budget   = 0
      i        = 0

      while i < count
        len     = r.u16.to_i32
        outline = Glyf.parse(r.slice(len), outlines)
        budget += outline.point_count * POINT_COST
        raise Error.new(Error::Reason::OutlineTooLarge) if budget > DECODED_BUDGET
        outlines << outline
        i += 1
      end

      colr_len = r.u16.to_i32
      colr     = colr_len > 0 ? r.slice(colr_len) : Bytes.empty

      cpal_len = r.remaining >= 2 ? r.u16.to_i32 : 0
      cpal     = cpal_len > 0 ? r.slice(cpal_len) : Bytes.empty

      fvar_len = r.remaining >= 2 ? r.u16.to_i32 : 0
      fvar     = fvar_len > 0 ? r.slice(fvar_len) : Bytes.empty

      gvar_len = r.remaining >= 2 ? r.u16.to_i32 : 0
      gvar     = gvar_len > 0 ? r.slice(gvar_len) : Bytes.empty

      Container.new(outlines, colr, cpal, fvar, gvar)
    rescue IndexError
      raise Error.new(Error::Reason::MalformedPayload)
    end
  end
end
