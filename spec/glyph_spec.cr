# spec/glyph_spec.cr
# # spec/glyph_spec.cr
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
      Glyph::Reason::MalformedPayload.code.should eq("malformed_payload")
      Glyph::Reason::PayloadTooLarge.code.should eq("payload_too_large")
    end
  end

  describe "format names" do
    it "round-trips the four format names" do
      Glyph::Format.from_code?("glyf").should eq(Glyph::Format::Glyf)
      Glyph::Format.from_code?("colrv1").should eq(Glyph::Format::Colrv1)
      Glyph::Format.from_code?("cff").should eq(Glyph::Format::Cff)
      Glyph::Format.from_code?("sixel").should be_nil
      Glyph::Format::Colrv0.code.should eq("colrv0")
    end
  end

  describe "Outline.from_points" do
    it "derives bounds correctly from a populated point slice" do
      default_point = Glyph::Point.new(0, 0, Glyph::PointType::OnCurve)
      points        = Slice(Glyph::Point).new(3, default_point)
      points[0] = Glyph::Point.new(10, 20, Glyph::PointType::OnCurve)
      points[1] = Glyph::Point.new(100, 5, Glyph::PointType::Quad)
      points[2] = Glyph::Point.new(-50, 200, Glyph::PointType::Cubic)
      ends = Slice(Int32).new(1, 2)

      outline = Glyph::Outline.from_points(points, ends)

      outline.x_min.should eq(-50)
      outline.x_max.should eq(100)
      outline.y_min.should eq(5)
      outline.y_max.should eq(200)
      outline.point_count.should eq(3)
      outline.empty?.should be_false
    end

    it "handles empty outlines without crashing on min/max derivation" do
      outline = Glyph::Outline.from_points(Slice(Glyph::Point).empty, Slice(Int32).empty)

      outline.x_min.should eq(0)
      outline.x_max.should eq(0)
      outline.y_min.should eq(0)
      outline.y_max.should eq(0)
      outline.empty?.should be_true
    end
  end
end
