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
require "./glyph/error"

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
end

# Limitations
# ===========
# 
# - CFF (Type 2 CharStrings): 
#   The CFF parser currently handles simple, fully-inlined, unhinted charstrings only. 
#   Complex features such as subroutines (`callsubr`, `callgsubr`), hintmasks (`hintmask`, `cntrmask`), and the flex family of operators are not supported. 
#   Feeding real-world CFF fonts into the parser may result in missing features or silent corruption.
# 
# - COLR Base Glyph: 
#   When rendering COLR payloads, the library hardcodes the base glyph to ID 0. 
#   This requires that custom container payloads map the desired glyph to the 0th index. 
#   Multi-glyph COLR payloads are not fully supported for per-codepoint selection.
# 
# - COLRv1 Gradients & Composites: 
#   Sweep gradient paints (formats 8/9) are currently stubbed to a solid flat fill utilizing the first color stop. 
#   PaintComposite (32) only supports Source-Over mode (mode 0) and ignores the blend mode parameter.
# 
# - GLYF Composites: 
#   Composite glyphs only support `ARGS_ARE_XY_VALUES`. 
#   Point-matching composites are currently unsupported and will misplace the component geometry.