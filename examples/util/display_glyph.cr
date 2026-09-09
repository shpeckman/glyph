# examples/util/display_glyph.cr
require "base64"
require "../../src/glyph"

module DisplayGlyph
  def self.show(image : Glyph::Image) : Nil
    b64        = Base64.strict_encode(image.pixels)
    chunk_size = 4096
    offset     = 0

    while offset < b64.size
      chunk = b64.byte_slice(offset, chunk_size)
      offset += chunk_size
      m = offset < b64.size ? 1 : 0

      if offset == chunk_size
        print "\e_Ga=T,f=32,s=#{image.width},v=#{image.height},m=#{m};#{chunk}\e\\"
      else
        print "\e_Gm=#{m};#{chunk}\e\\"
      end
    end
    puts
  end
end
