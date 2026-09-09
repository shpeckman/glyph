# spec/glyph/glossary_spec.cr
require "../spec_helper"

describe Glyph::Glossary do
  it "registers a glyph in the private use area" do
    g   = Glyph::Glossary.new
    reg = g.register(0x100000, square_glyf)
    reg.cp.should eq(0x100000)
    reg.format.should eq(Glyph::Format::Glyf)
    reg.span.should eq(1)
    g.size.should eq(1)
    g[0x100000]?.should_not be_nil
  end

  it "rejects a non-PUA codepoint in Icon mode" do
    g     = Glyph::Glossary.new
    error = expect_raises(Glyph::Error) { g.register('a'.ord, square_glyf) }
    error.reason.should eq(Glyph::Reason::OutOfNamespace)
    g.size.should eq(0)
  end

  it "accepts a non-PUA codepoint in Font mode" do
    g   = Glyph::Glossary.new(mode: Glyph::Mode::Font)
    reg = g.register('a'.ord, square_glyf)
    reg.cp.should eq('a'.ord)
    g.size.should eq(1)
    g['a'.ord]?.should_not be_nil
  end

  it "overwrites without consuming a second slot" do
    g      = Glyph::Glossary.new
    first  = g.register(0x100000, square_glyf)
    second = g.register(0x100000, square_glyf(500, 500))
    g.size.should eq(1)
    second.slot.should eq(first.slot)
    second.tag.should_not eq(first.tag)
  end

  it "normalizes an invalid span to one cell" do
    g = Glyph::Glossary.new
    g.register(0x100000, square_glyf, span: 5).span.should eq(1)
    g.register(0x100001, square_glyf, span: 2).span.should eq(2)
  end

  it "appends a blank cell to a width=2 glyph's text" do
    g = Glyph::Glossary.new
    g.register(0x100000, square_glyf, span: 1).text.should eq(0x100000.chr.to_s)
    g.register(0x100001, square_glyf, span: 2).text.should eq(0x100001.chr.to_s + " ")
  end

  it "evicts the oldest registration in FIFO order when full" do
    g       = Glyph::Glossary.new
    payload = square_glyf
    i       = 0
    while i < Glyph::MAX_SLOTS
      g.register(0x100000 + i, payload)
      i += 1
    end
    g.size.should eq(Glyph::MAX_SLOTS)
    g.register(0x100000 + Glyph::MAX_SLOTS, payload)
    g.size.should eq(Glyph::MAX_SLOTS)
    g[0x100000]?.should be_nil
    g[0x100001]?.should_not be_nil
    g[0x100000 + Glyph::MAX_SLOTS]?.should_not be_nil
  end

  it "reuses a freed slot after a clear" do
    g    = Glyph::Glossary.new
    slot = g.register(0x100000, square_glyf).slot
    g.clear(0x100000).should be_true
    g.size.should eq(0)
    g.register(0x100001, square_glyf).slot.should eq(slot)
  end

  it "treats clearing an empty slot as success" do
    g = Glyph::Glossary.new
    g.clear(0x100000).should be_true
  end

  it "rejects clearing a non-PUA codepoint in Icon mode" do
    g     = Glyph::Glossary.new
    error = expect_raises(Glyph::Error) { g.clear('z'.ord) }
    error.reason.should eq(Glyph::Reason::OutOfNamespace)
  end

  it "clears a non-PUA codepoint in Font mode" do
    g = Glyph::Glossary.new(mode: Glyph::Mode::Font)
    g.register('z'.ord, square_glyf)
    g.clear('z'.ord).should be_true
    g.size.should eq(0)
  end

  it "clears every slot" do
    g = Glyph::Glossary.new
    g.register(0x100000, square_glyf)
    g.register(0x100001, square_glyf)
    g.clear_all
    g.size.should eq(0)
    g[0x100000]?.should be_nil
  end

  it "reports coverage as a set" do
    g = Glyph::Glossary.new
    g.query(0x100000).should eq(Glyph::Coverage::None)
    g.query(0x100000, system: true).code.should eq("system")
    g.register(0x100000, square_glyf)
    g.query(0x100000).code.should eq("glossary")
    g.query(0x100000, system: true).code.should eq("system,glossary")
    g.query('a'.ord, system: true).code.should eq("system")
  end

  it "hides non-PUA coverage when dynamically switched to Icon mode" do
    g = Glyph::Glossary.new(mode: Glyph::Mode::Font)
    g.register('a'.ord, square_glyf)
    g.query('a'.ord).code.should eq("glossary")
    g.mode = Glyph::Mode::Icon
    g.query('a'.ord).should eq(Glyph::Coverage::None)
  end

  it "iterates in registration order" do
    g = Glyph::Glossary.new
    g.register(0x100002, square_glyf)
    g.register(0x100000, square_glyf)
    seen = [] of Int32
    g.each { |reg| seen << reg.cp }
    seen.should eq([0x100002, 0x100000])
  end
end
