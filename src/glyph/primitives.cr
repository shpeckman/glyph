# src/glyph/primitives.cr
# # src/glyph/primitives.cr

module Glyph
  enum Mode
    Icon
    Font
  end

  enum Format
    Glyf
    Colrv0
    Colrv1
    Cff

    def code : String
      case self
      in .glyf?   then "glyf"
      in .colrv0? then "colrv0"
      in .colrv1? then "colrv1"
      in .cff?    then "cff"
      end
    end

    def self.from_code?(name : String) : Format?
      case name
      when "glyf"   then Glyf
      when "colrv0" then Colrv0
      when "colrv1" then Colrv1
      when "cff"    then Cff
      end
    end
  end

  enum SizeMode
    Height
    Advance
    Contain
    Cover
    Stretch
  end

  enum HAlign
    Start
    Center
    End
  end

  enum VAlign
    Start
    Center
    End
    Baseline
  end

  enum Extend
    Pad
    Repeat
    Reflect
  end

  @[Flags]
  enum Coverage
    System
    Glossary

    def code : String
      names = [] of String
      names << "system" if system?
      names << "glossary" if glossary?
      names.join(',')
    end
  end

  struct Pad
    getter top    : Float64
    getter right  : Float64
    getter bottom : Float64
    getter left   : Float64

    def initialize(@top : Float64 = 0.0, @right : Float64 = 0.0,
                   @bottom : Float64 = 0.0, @left : Float64 = 0.0)
    end

    def self.none : Pad
      Pad.new
    end

    def degenerate? : Bool
      return true if @top < 0 || @right < 0 || @bottom < 0 || @left < 0
      @left + @right >= 1.0 || @top + @bottom >= 1.0
    end
  end

  struct Metrics
    getter upm : Int32
    getter aw  : Int32
    getter lh  : Int32

    def initialize(upm : Int32 = DEFAULT_UPM, aw : Int32? = nil, lh : Int32? = nil)
      @upm = upm > 0 ? upm : DEFAULT_UPM
      @aw  = aw || @upm
      @lh  = lh || @upm
    end
  end

  enum PointType : UInt8
    OnCurve = 0
    Quad    = 1
    Cubic   = 2

    def on_curve?
      self == OnCurve
    end

    def quad?
      self == Quad
    end

    def cubic?
      self == Cubic
    end
  end

  struct Point
    getter x    : Int32
    getter y    : Int32
    getter type : PointType

    def initialize(@x : Int32, @y : Int32, @type : PointType)
    end

    def on_curve? : Bool
      @type.on_curve?
    end
  end

  struct Outline
    getter points : Slice(Point)
    getter ends   : Slice(Int32)
    getter x_min  : Int32
    getter y_min  : Int32
    getter x_max  : Int32
    getter y_max  : Int32

    def initialize(@points : Slice(Point), @ends : Slice(Int32),
                   @x_min : Int32, @y_min : Int32, @x_max : Int32, @y_max : Int32)
    end

    def self.blank(x_min = 0, y_min = 0, x_max = 0, y_max = 0) : Outline
      new(Slice(Point).empty, Slice(Int32).empty, x_min, y_min, x_max, y_max)
    end

    def self.from_points(points : Slice(Point), ends : Slice(Int32)) : Outline
      x_min = 0
      y_min = 0
      x_max = 0
      y_max = 0
      if points.size > 0
        x_min = points.min_of(&.x)
        y_min = points.min_of(&.y)
        x_max = points.max_of(&.x)
        y_max = points.max_of(&.y)
      end
      new(points, ends, x_min, y_min, x_max, y_max)
    end

    def empty? : Bool
      @ends.empty?
    end

    def point_count : Int32
      @points.size
    end
  end

  struct Registration
    getter cp       : Int32
    getter format   : Format
    getter metrics  : Metrics
    getter span     : Int32
    getter size     : SizeMode
    getter halign   : HAlign
    getter valign   : VAlign
    getter pad      : Pad
    getter outlines : Array(Outline)
    getter colr     : Bytes
    getter palette  : Array(UInt32)
    getter tag      : UInt64
    getter slot     : Int32
    getter text     : String

    def initialize(@cp : Int32, @format : Format, @metrics : Metrics, @span : Int32,
                   @size : SizeMode, @halign : HAlign, @valign : VAlign, @pad : Pad,
                   @outlines : Array(Outline), @colr : Bytes, @palette : Array(UInt32),
                   @tag : UInt64, @slot : Int32)
      @text = @span > 1 ? "#{@cp.chr} " : @cp.chr.to_s
    end
  end
end
