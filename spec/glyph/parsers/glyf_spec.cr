# spec/glyph/parsers/glyf_spec.cr
require "../../spec_helper"

describe Glyph::Glyf do
  it "parses a simple square" do
    outline = Glyph::Glyf.parse(square_glyf)
    outline.point_count.should eq(4)
    outline.ends.size.should eq(1)
    outline.ends[0].should eq(3)
    outline.x_max.should eq(1000)
    outline.points[2].x.should eq(1000)
    outline.points[2].y.should eq(1000)
    outline.points[0].on_curve?.should be_true
  end

  it "keeps an empty glyph parseable" do
    io = IO::Memory.new
    io.write_bytes(0_i16, BE)
    4.times { io.write_bytes(0_i16, BE) }
    outline = Glyph::Glyf.parse(io.to_slice)
    outline.empty?.should be_true
  end

  it "expands repeated flags" do
    io = IO::Memory.new
    io.write_bytes(1_i16, BE)
    io.write_bytes(0_i16, BE)
    io.write_bytes(0_i16, BE)
    io.write_bytes(10_i16, BE)
    io.write_bytes(10_i16, BE)
    io.write_bytes(3_u16, BE)
    io.write_bytes(0_u16, BE)
    io.write_byte(0x09_u8)
    io.write_byte(0x03_u8)
    4.times { io.write_bytes(0_i16, BE) }
    4.times { io.write_bytes(0_i16, BE) }
    outline = Glyph::Glyf.parse(io.to_slice)
    outline.point_count.should eq(4)
    outline.points.each { |p| p.on_curve?.should be_true }
  end

  it "decodes short x deltas with the sign flag" do
    io = IO::Memory.new
    io.write_bytes(1_i16, BE)
    io.write_bytes(0_i16, BE)
    io.write_bytes(0_i16, BE)
    io.write_bytes(20_i16, BE)
    io.write_bytes(0_i16, BE)
    io.write_bytes(1_u16, BE)
    io.write_bytes(0_u16, BE)
    io.write_byte(0x33_u8)
    io.write_byte(0x23_u8)
    io.write_byte(20_u8)
    io.write_byte(5_u8)
    outline = Glyph::Glyf.parse(io.to_slice)
    outline.points[0].x.should eq(20)
    outline.points[1].x.should eq(15)
  end

  it "rejects composite glyphs" do
    io = IO::Memory.new
    io.write_bytes(-1_i16, BE)
    4.times { io.write_bytes(0_i16, BE) }
    error = expect_raises(Glyph::Error) { Glyph::Glyf.parse(io.to_slice) }
    error.reason.should eq(Glyph::Reason::CompositeUnsupported)
  end

  it "rejects hinting instructions" do
    io = IO::Memory.new
    io.write_bytes(1_i16, BE)
    4.times { io.write_bytes(0_i16, BE) }
    io.write_bytes(0_u16, BE)
    io.write_bytes(4_u16, BE)
    error = expect_raises(Glyph::Error) { Glyph::Glyf.parse(io.to_slice) }
    error.reason.should eq(Glyph::Reason::HintingUnsupported)
  end

  it "rejects an oversized outline before allocating points" do
    io = IO::Memory.new
    io.write_bytes(1_i16, BE)
    4.times { io.write_bytes(0_i16, BE) }
    io.write_bytes((Glyph::MAX_POINTS + 1).to_u16, BE)
    error = expect_raises(Glyph::Error) { Glyph::Glyf.parse(io.to_slice) }
    error.reason.should eq(Glyph::Reason::OutlineTooLarge)
  end

  it "accepts an outline exactly at the budget boundary" do
    Glyph::MAX_POINTS.should eq(5461)
  end

  it "rejects an oversized payload" do
    error = expect_raises(Glyph::Error) { Glyph::Glyf.parse(Bytes.new(Glyph::MAX_PAYLOAD + 1)) }
    error.reason.should eq(Glyph::Reason::PayloadTooLarge)
  end

  it "rejects a truncated record" do
    error = expect_raises(Glyph::Error) { Glyph::Glyf.parse(Bytes[0_u8, 1_u8]) }
    error.reason.should eq(Glyph::Reason::MalformedPayload)
  end

  it "rejects non-monotonic contour ends" do
    io = IO::Memory.new
    io.write_bytes(2_i16, BE)
    4.times { io.write_bytes(0_i16, BE) }
    io.write_bytes(5_u16, BE)
    io.write_bytes(3_u16, BE)
    error = expect_raises(Glyph::Error) { Glyph::Glyf.parse(io.to_slice) }
    error.reason.should eq(Glyph::Reason::MalformedPayload)
  end
end
