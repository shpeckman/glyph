# spec/glyph/layout_spec.cr
# # spec/glyph/layout_spec.cr
require "../spec_helper"

describe Glyph::Layout do
  glossary = Glyph::Glossary.new

  it "stretches the authored extent onto the full span" do
    reg = glossary.register(0x100000, square_glyf, size: Glyph::SizeMode::Stretch)
    t   = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.apply_x(0.0, 0.0).should be_close(0.0, 1e-9)
    t.apply_x(1000.0, 0.0).should be_close(8.0, 1e-9)
    t.apply_y(0.0, 0.0).should be_close(16.0, 1e-9)
    t.apply_y(0.0, 1000.0).should be_close(0.0, 1e-9)
  end

  it "widens the span for a width=2 glyph" do
    reg = glossary.register(0x100001, square_glyf, span: 2, size: Glyph::SizeMode::Stretch)
    t   = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.apply_x(1000.0, 0.0).should be_close(16.0, 1e-9)
  end

  it "preserves aspect ratio for contain" do
    reg = glossary.register(0x100002, square_glyf, size: Glyph::SizeMode::Contain)
    t   = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.a.should be_close(0.008, 1e-9)
    t.d.should be_close(-0.008, 1e-9)
  end

  it "fills both axes for cover" do
    reg = glossary.register(0x100003, square_glyf, size: Glyph::SizeMode::Cover)
    t   = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.a.should be_close(0.016, 1e-9)
  end

  it "drives from line height by default" do
    reg = glossary.register(0x100004, square_glyf)
    reg.size.should eq(Glyph::SizeMode::Height)
    t = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.a.should be_close(0.016, 1e-9)
  end

  it "puts the glyph origin on the baseline" do
    reg = glossary.register(0x100005, square_glyf, valign: Glyph::VAlign::Baseline)
    t   = Glyph::Layout.resolve(reg, 8, 16, 12)
    t.apply_y(0.0, 0.0).should be_close(12.0, 1e-9)
  end

  it "honours top padding in baseline alignment" do
    reg = glossary.register(0x100010, square_glyf, valign: Glyph::VAlign::Baseline, pad: Glyph::Pad.new(top: 0.25))
    t   = Glyph::Layout.resolve(reg, 8, 16, 12)
    # h = 16, pt = 16 * 0.25 = 4
    # oy = pt + baseline = 4 + 12 = 16
    t.apply_y(0.0, 0.0).should be_close(16.0, 1e-9)
  end

  it "shrinks the span with padding" do
    reg = glossary.register(0x100006, square_glyf, size: Glyph::SizeMode::Stretch,
      pad: Glyph::Pad.new(0.25, 0.0, 0.25, 0.0))
    t = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.apply_y(0.0, 1000.0).should be_close(4.0, 1e-9)
    t.apply_y(0.0, 0.0).should be_close(12.0, 1e-9)
  end

  it "ignores degenerate padding" do
    reg = glossary.register(0x100007, square_glyf, size: Glyph::SizeMode::Stretch,
      pad: Glyph::Pad.new(0.6, 0.0, 0.6, 0.0))
    t = Glyph::Layout.resolve(reg, 8, 16, 16)
    t.apply_y(0.0, 1000.0).should be_close(0.0, 1e-9)
  end

  it "anchors horizontally with align start and end" do
    a = glossary.register(0x100008, square_glyf, size: Glyph::SizeMode::Height,
      halign: Glyph::HAlign::Start)
    b = glossary.register(0x100009, square_glyf, size: Glyph::SizeMode::Height,
      halign: Glyph::HAlign::End)
    Glyph::Layout.resolve(a, 8, 16, 16).apply_x(0.0, 0.0).should be_close(0.0, 1e-9)
    Glyph::Layout.resolve(b, 8, 16, 16).apply_x(1000.0, 0.0).should be_close(8.0, 1e-9)
  end
end
