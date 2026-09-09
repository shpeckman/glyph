# spec/glyph/parsers/cff_spec.cr
require "../../spec_helper"

describe Glyph::Cff do
  it "parses a simple charstring" do
    io = IO::Memory.new

    # rmoveto (21)
    io.write_byte(239_u8) # dx: 100
    io.write_byte(239_u8) # dy: 100
    io.write_byte(21_u8)

    # rlineto (5)
    io.write_byte(189_u8) # dx: 50
    io.write_byte(139_u8) # dy: 0
    io.write_byte(139_u8) # dx: 0
    io.write_byte(189_u8) # dy: 50
    io.write_byte(5_u8)

    # endchar (14)
    io.write_byte(14_u8)

    outline = Glyph::Cff.parse(io.to_slice)

    outline.point_count.should eq(3)

    # initial point after rmoveto
    outline.points[0].x.should eq(100)
    outline.points[0].y.should eq(100)
    outline.points[0].on_curve?.should be_true

    # step 1 via rlineto
    outline.points[1].x.should eq(150)
    outline.points[1].y.should eq(100)

    # step 2 via rlineto
    outline.points[2].x.should eq(150)
    outline.points[2].y.should eq(150)
  end
end
