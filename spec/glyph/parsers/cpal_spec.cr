# spec/glyph/parsers/cpal_spec.cr
require "../../spec_helper"

describe Glyph::Cpal do
  it "reads colour records as BGRA" do
    palette = Glyph::Cpal.parse(cpal_table([{0x11_u8, 0x22_u8, 0x33_u8, 0xff_u8}]))
    palette.size.should eq(1)
    palette[0].should eq(0xff112233_u32)
  end

  it "returns an empty palette for empty bytes" do
    Glyph::Cpal.parse(Bytes.empty).empty?.should be_true
  end
end
