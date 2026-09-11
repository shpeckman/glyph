# src/glyph.cr

require "./glyph/primitives"
require "./glyph/transform"
require "./glyph/reader"
require "./glyph/parsers/*"
require "./glyph/geometry/*"
require "./glyph/paint"
require "./glyph/render/*"
require "./glyph/layout"
require "./glyph/glossary"

module Glyph
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}

  MAX_SLOTS      =  1024
  DECODED_BUDGET = 65536
  POINT_COST     =    12
  MAX_POINTS     = DECODED_BUDGET // POINT_COST
  MAX_PAYLOAD    =      65536
  MAX_CONTAINER  =       1024
  MAX_DEPTH      =         64
  DEFAULT_UPM    =       1000
  FOREGROUND     = 0xFFFF_u16

  PUA_RANGES = { {0xE000, 0xF8FF}, {0xF0000, 0xFFFFD}, {0x100000, 0x10FFFD} }

  def self.pua?(cp : Int32) : Bool
    PUA_RANGES.each do |range|
      lo, hi = range
      return true if cp >= lo && cp <= hi
    end
    false
  end

  class Error < Exception
    enum Reason
      OutOfNamespace
      MalformedPayload
      PayloadTooLarge
      OutlineTooLarge

      def code : String
        case self
        in .out_of_namespace?  then "out_of_namespace"
        in .malformed_payload? then "malformed_payload"
        in .payload_too_large? then "payload_too_large"
        in .outline_too_large? then "outline_too_large"
        end
      end
    end

    getter reason : Reason

    def initialize(@reason : Reason)
      super(@reason.code)
    end
  end
end
