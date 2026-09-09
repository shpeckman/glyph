# examples/subpixel_lcd.cr
require "../src/glyph"
require "./util/extractor"
require "./util/display_glyph"

format, payload, upm = Extractor.extract("examples/fonts/Inter-Variable.ttf", 'O'.ord)
glossary = Glyph::Glossary.new(mode: Glyph::Mode::Font)
reg      = glossary.register('O'.ord, payload, format: format, upm: upm)

renderer = Glyph::Renderer.new(80, 160)
renderer.subpixel = true
image = renderer.render(reg, 0xFFFFFF_u32)

puts "Subpixel LCD Coverage ('O'):"
DisplayGlyph.show(image)
