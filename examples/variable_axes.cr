# examples/variable_axes.cr
require "../src/glyph"
require "./util/extractor"
require "./util/display_glyph"

format, payload, upm = Extractor.extract("examples/fonts/Inter-Variable.ttf", 'A'.ord)
glossary = Glyph::Glossary.new(mode: Glyph::Mode::Font)

reg_light = glossary.register('A'.ord, payload, format: format, upm: upm, axes: {"wght" => 100.0})
reg_bold  = glossary.register(0xE000, payload, format: format, upm: upm, axes: {"wght" => 900.0})

renderer  = Glyph::Renderer.new(80, 160)
img_light = renderer.render(reg_light, 0xFFFFFF_u32)
img_bold  = renderer.render(reg_bold, 0xFFFFFF_u32)

puts "Light (wght=100):"
DisplayGlyph.show(img_light)

puts "\nBold (wght=900):"
DisplayGlyph.show(img_bold)
