# examples/basic_raster.cr
require "../src/glyph"
require "./util/extractor"
require "./util/display_glyph"

format, payload, upm = Extractor.extract("examples/fonts/Inter-Variable.ttf", 'A'.ord)
glossary = Glyph::Glossary.new(mode: Glyph::Mode::Font)
reg      = glossary.register('A'.ord, payload, format: format, upm: upm)

renderer = Glyph::Renderer.new(80, 160)
image    = renderer.render(reg, 0xFFFFFF_u32)

puts "Basic Font Rasterization ('A'):"
DisplayGlyph.show(image)
