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
  end

  it "permits an absent palette table" do
    payload = container([square_glyf], colr_v0_table(0, 0), Bytes.empty)
    Glyph::Container.parse(payload).cpal.empty?.should be_true
  end

  it "rejects an empty outline array" do
    io = IO::Memory.new
    io.write_bytes(0_u16, BE)
    error = expect_raises(Glyph::Error) { Glyph::Container.parse(io.to_slice) }
    error.reason.should eq(Glyph::Reason::MalformedPayload)
  end

  it "rejects a container with no COLR table" do
    io = IO::Memory.new
    io.write_bytes(1_u16, BE)
    outline = square_glyf
    io.write_bytes(outline.size.to_u16, BE)
    io.write(outline)
    io.write_bytes(0_u16, BE)
    error = expect_raises(Glyph::Error) { Glyph::Container.parse(io.to_slice) }
    error.reason.should eq(Glyph::Reason::MalformedPayload)
  end
end
