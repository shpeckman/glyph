# src/glyph/glossary.cr

module Glyph
  class Glossary
    getter size : Int32

    def initialize
      @entries   = {} of Int32 => Registration
      @order     = Deque(Int32).new
      @free      = Deque(Int32).new
      @next_slot = 0
      @next_tag  = 1_u64
      @size      = 0
    end

    def []?(cp : Int32) : Registration?
      @entries[cp]?
    end

    def register(cp : Int32, payload : Bytes, format : Format = Format::Glyf,
                 upm : Int32 = DEFAULT_UPM, aw : Int32? = nil, lh : Int32? = nil,
                 span : Int32 = 1, size : SizeMode = SizeMode::Height,
                 halign : HAlign = HAlign::Center, valign : VAlign = VAlign::Center,
                 pad : Pad = Pad.none) : Registration
      raise Error.new(Reason::OutOfNamespace) unless Glyph.pua?(cp)
      raise Error.new(Reason::PayloadTooLarge) if payload.size > MAX_PAYLOAD
      span = 1 if span != 2

      outlines = [] of Outline
      colr     = Bytes.empty
      palette  = [] of UInt32

      case format
      when .glyf?
        outline = Glyf.parse(payload)
        raise Error.new(Reason::OutlineTooLarge) if outline.point_count * POINT_COST > DECODED_BUDGET
        outlines << outline
      when .cff?
        outline = Cff.parse(payload)
        raise Error.new(Reason::OutlineTooLarge) if outline.point_count * POINT_COST > DECODED_BUDGET
        outlines << outline
      else
        container = Container.parse(payload)
        outlines  = container.outlines
        colr      = container.colr
        palette   = Cpal.parse(container.cpal)
      end

      existing = @entries[cp]?
      slot     = existing ? existing.slot : acquire_slot
      reg = Registration.new(cp, format, Metrics.new(upm, aw, lh), span, size,
        halign, valign, pad, outlines, colr, palette, next_tag, slot)

      unless existing
        @order.push(cp)
        @size += 1
      end
      @entries[cp] = reg
      reg
    end

    def query(cp : Int32, system : Bool = false) : Coverage
      cov = Coverage::None
      cov |= Coverage::System if system
      cov |= Coverage::Glossary if Glyph.pua?(cp) && @entries.has_key?(cp)
      cov
    end

    def clear(cp : Int32) : Bool
      raise Error.new(Reason::OutOfNamespace) unless Glyph.pua?(cp)
      reg = @entries.delete(cp)
      return true unless reg
      @order.delete(cp)
      @free.push(reg.slot)
      @size -= 1
      true
    end

    def clear_all : Nil
      @entries.each_value { |reg| @free.push(reg.slot) }
      @entries.clear
      @order.clear
      @size = 0
    end

    def each(& : Registration ->) : Nil
      @order.each do |cp|
        reg = @entries[cp]?
        yield reg if reg
      end
    end

    private def acquire_slot : Int32
      while @size >= MAX_SLOTS
        evict
      end
      return @free.shift unless @free.empty?
      slot = @next_slot
      @next_slot += 1
      slot
    end

    private def evict : Nil
      victim = @order.shift?
      return unless victim
      reg = @entries.delete(victim)
      return unless reg
      @free.push(reg.slot)
      @size -= 1
    end

    private def next_tag : UInt64
      tag = @next_tag
      @next_tag += 1
      tag
    end
  end
end
