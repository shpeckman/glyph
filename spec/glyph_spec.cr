# spec/glyph_spec.cr
require "./spec_helper"

describe Glyph do
  describe "namespace" do
    it "accepts all three private use areas" do
      Glyph.pua?(0xE000).should be_true
      Glyph.pua?(0xF8FF).should be_true
      Glyph.pua?(0xF0000).should be_true
      Glyph.pua?(0x100000).should be_true
    end

    it "rejects ordinary codepoints" do
      Glyph.pua?('a'.ord).should be_false
      Glyph.pua?(0x4E00).should be_false
      Glyph.pua?(0xF900).should be_false
      Glyph.pua?(0x10FFFE).should be_false
    end
  end

  describe "reason codes" do
    it "renders the spec's snake_case names" do
      Glyph::Reason::OutOfNamespace.code.should eq("out_of_namespace")
      Glyph::Reason::OutlineTooLarge.code.should eq("outline_too_large")
      Glyph::Reason::HintingUnsupported.code.should eq("hinting_unsupported")
    end
  end

  describe "format names" do
    it "round-trips the three v1.8 names" do
      Glyph::Format.from_code?("glyf").should eq(Glyph::Format::Glyf)
      Glyph::Format.from_code?("colrv1").should eq(Glyph::Format::Colrv1)
      Glyph::Format.from_code?("sixel").should be_nil
      Glyph::Format::Colrv0.code.should eq("colrv0")
    end
  end
end
