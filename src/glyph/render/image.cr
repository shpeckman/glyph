# src/glyph/render/image.cr
struct Glyph::Image
  getter width  : Int32
  getter height : Int32
  getter pixels : Bytes

  def initialize(@width : Int32, @height : Int32, @pixels : Bytes)
  end
end
