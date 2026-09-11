# src/glyph/parsers/fvar.cr
# # src/glyph/parsers/fvar.cr
module Glyph
  module Fvar
    struct Axis
      getter tag : String
      getter min : Float64
      getter def : Float64
      getter max : Float64

      def initialize(@tag : String, @min : Float64, @def : Float64, @max : Float64)
      end
    end

    def self.parse(bytes : Bytes) : Array(Axis)
      return [] of Axis if bytes.empty?
      r = Reader.new(bytes)
      r.u32 # version
      offset = r.u16.to_i32
      r.u16 # countSizePairs
      axis_count = r.u16.to_i32

      r.seek(offset)
      axes = [] of Axis
      axis_count.times do
        tag_val = r.u32
        tag     = String.new(Bytes[(tag_val >> 24) & 0xFF, (tag_val >> 16) & 0xFF, (tag_val >> 8) & 0xFF, tag_val & 0xFF])
        min     = r.fixed
        df      = r.fixed
        max     = r.fixed
        r.u16
        r.u16
        axes << Axis.new(tag, min, df, max)
      end
      axes
    rescue IndexError
      raise Error.new(Reason::MalformedPayload)
    end

    def self.normalize(axes : Array(Axis), coords : Hash(String, Float64)) : Array(Float64)
      axes.map do |axis|
        val = coords[axis.tag]? || axis.def
        val = val.clamp(axis.min, axis.max)

        if val < axis.def
          axis.def == axis.min ? 0.0 : (val - axis.def) / (axis.def - axis.min)
        elsif val > axis.def
          axis.max == axis.def ? 0.0 : (val - axis.def) / (axis.max - axis.def)
        else
          0.0
        end
      end
    end
  end
end
