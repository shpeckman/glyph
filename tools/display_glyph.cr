# tools/display_glyph.cr
require "base64"
require "../src/glyph"

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

# if PROGRAM_NAME == __FILE__
#   if ARGV.empty?
#     STDERR.puts "Usage: display_glyph <path/to/glyph/payload>"
#     exit 1
#   end
#
#   cell_width = 10
#   cell_height = 20
#
#   channel = Channel(String).new
#   spawn do
#     responses = ""
#     STDIN.raw do |io|
#       print "\e[14t\e[16t\e[18t"
#       STDOUT.flush
#       3.times do
#         loop do
#           char = io.read_char
#           break unless char
#           responses += char
#           break if char == 't'
#         end
#       end
#     end
#     channel.send(responses)
#   end
#
#   select
#   when res = channel.receive
#     if match = res.match(/\e\[6;(\d+);(\d+)t/)
#       cell_height = match[1].to_i
#       cell_width = match[2].to_i
#     end
#   when timeout(1.second)
#     STDERR.puts "Terminal did not respond to sizing queries in time. Using default 10x20 cell size."
#   end
#
#   payload = File.read(ARGV[0]).to_slice
#   glossary = Glyph::Glossary.new
#   reg = glossary.register(0xE000, payload)
#
#   renderer = Glyph::Renderer.new(cell_width, cell_height)
#   image = renderer.render(reg, 0xFFFFFFFF_u32)
#
#   DisplayGlyph.show(image)
# end
