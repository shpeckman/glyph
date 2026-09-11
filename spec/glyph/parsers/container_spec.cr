# spec/glyph/parsers/container_spec.cr
require "../../spec_helper"

describe Glyph::Container do
  it "parses a colour container" do
    payload = container([square_glyf, square_glyf(500, 1000)],
      colr_v0_table(1, 0), cpal_table([{255_u8, 0_u8, 0_u8, 255_u8}]))
    parsed = Glyph::Container.parse(payload)
    parsed.outlines.size.should eq(2)
    parsed.colr.empty?.should be_false
    parsed.cpal.empty?.should be_false
    parsed.fvar.empty?.should be_true
    parsed.gvar.empty?.should be_true
  end

  it "parses a container with variation tables" do
    fvar    = fvar_table([{"wght", 100.0, 400.0, 900.0}])
    gvar    = simple_gvar_table(10, 10)
    payload = container([square_glyf], colr_v0_table(1, 0), cpal_table([{255_u8, 0_u8, 0_u8, 255_u8}]), fvar, gvar)

    parsed = Glyph::Container.parse(payload)
    parsed.outlines.size.should eq(1)
    parsed.fvar.empty?.should be_false
    parsed.gvar.empty?.should be_false
  end

  it "permits an empty COLR table for monochrome variable fonts" do
    io = IO::Memory.new
    io.write_bytes(1_u16, BE)
    outline = square_glyf
    io.write_bytes(outline.size.to_u16, BE)
    io.write(outline)
    io.write_bytes(0_u16, BE) # colr size
    io.write_bytes(0_u16, BE) # cpal size
    parsed = Glyph::Container.parse(io.to_slice)
    parsed.colr.empty?.should be_true
    parsed.outlines.size.should eq(1)
  end

  it "rejects an empty outline array" do
    io = IO::Memory.new
    io.write_bytes(0_u16, BE)
    error = expect_raises(Glyph::Error) { Glyph::Container.parse(io.to_slice) }
    error.reason.should eq(Glyph::Error::Reason::MalformedPayload)
  end
end
