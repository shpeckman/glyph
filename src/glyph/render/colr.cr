# src/glyph/render/colr.cr
module Glyph
  class ColrRenderer
    def initialize(@outlines : Array(Outline), @colr : Bytes,
                   @palette : Array(UInt32), @fg : UInt32,
                   @width : Int32, @height : Int32, @subpixel : Bool = false)
      @base_glyph_list = 0
      @layer_list      = 0
    end

    def render(target : Bitmap, root : Transform) : Nil
      r            = Reader.new(@colr)
      version      = r.u16.to_i32
      num_base     = r.u16.to_i32
      base_offset  = r.u32.to_i32
      layer_offset = r.u32.to_i32
      num_layers   = r.u16.to_i32

      if version >= 1
        @base_glyph_list = r.u32.to_i32
        @layer_list      = r.u32.to_i32
        return if @base_glyph_list > 0 && paint_v1(target, root)
      end

      render_v0(target, root, r, num_base, base_offset, layer_offset, num_layers)
    end

    private def paint_v1(target : Bitmap, root : Transform) : Bool
      offset = base_paint_offset(0)
      return false unless offset
      paint(target, offset, root, nil, 0)
      true
    end

    private def base_paint_offset(glyph_id : Int32) : Int32?
      r = Reader.new(@colr)
      r.seek(@base_glyph_list)
      count = r.u32.to_i32
      i     = 0
      while i < count
        gid = r.u16.to_i32
        off = r.u32.to_i32
        return @base_glyph_list + off if gid == glyph_id
        i += 1
      end
      nil
    end

    private def render_v0(target : Bitmap, root : Transform, r : Reader,
                          num_base : Int32, base_offset : Int32,
                          layer_offset : Int32, num_layers : Int32) : Nil
      return if base_offset <= 0 || layer_offset <= 0
      first = -1
      count = 0
      i     = 0
      while i < num_base
        r.seek(base_offset + i * 6)
        gid = r.u16.to_i32
        fl  = r.u16.to_i32
        nl  = r.u16.to_i32
        if gid == 0
          first = fl
          count = nl
          break
        end
        i += 1
      end
      return if first < 0
      i = 0
      while i < count
        idx = first + i
        break if idx >= num_layers
        r.seek(layer_offset + idx * 4)
        gid  = r.u16.to_i32
        pal  = r.u16
        mask = glyph_mask(gid, root)
        target.blend(mask, SolidPaint.new(color_for(pal, 1.0))) if mask
        i += 1
      end
    end

    private def paint(target : Bitmap, offset : Int32, tf : Transform,
                      clip : Slice(Float32)?, depth : Int32) : Nil
      return if depth > MAX_DEPTH
      r = Reader.new(@colr)
      r.seek(offset)
      format = r.u8.to_i32

      case format
      when 1
        n     = r.u8.to_i32
        first = r.u32.to_i32
        return if @layer_list <= 0
        lr = Reader.new(@colr)
        lr.seek(@layer_list)
        total = lr.u32.to_i32
        i     = 0
        while i < n
          idx = first + i
          break if idx >= total
          lr.seek(@layer_list + 4 + idx * 4)
          paint(target, @layer_list + lr.u32.to_i32, tf, clip, depth + 1)
          i += 1
        end
      when 2, 3
        pal   = r.u16
        alpha = r.f2dot14
        target.blend(clip, SolidPaint.new(color_for(pal, alpha)))
      when 4, 5
        line = color_line(offset + r.u24, format == 5)
        x0   = r.i16.to_f
        y0   = r.i16.to_f
        x1   = r.i16.to_f
        y1   = r.i16.to_f
        x2   = r.i16.to_f
        y2   = r.i16.to_f
        target.blend(clip, linear_paint(line, tf, x0, y0, x1, y1, x2, y2))
      when 6, 7
        line    = color_line(offset + r.u24, format == 7)
        x0      = r.i16.to_f
        y0      = r.i16.to_f
        r0      = r.u16.to_f
        x1      = r.i16.to_f
        y1      = r.i16.to_f
        r1      = r.u16.to_f
        inverse = tf.invert
        if inverse
          target.blend(clip, RadialPaint.new(line, inverse, x0, y0, r0, x1, y1, r1))
        else
          target.blend(clip, SolidPaint.new(line.sample(0.0)))
        end
      when 8, 9
        line = color_line(offset + r.u24, format == 9)
        target.blend(clip, SolidPaint.new(line.sample(0.0)))
      when 10
        child = offset + r.u24
        gid   = r.u16.to_i32
        mask  = glyph_mask(gid, tf)
        return unless mask
        merged = clip ? Fill.intersect(clip, mask) : mask
        paint(target, child, tf, merged, depth + 1)
      when 11
        gid   = r.u16.to_i32
        child = base_paint_offset(gid)
        paint(target, child, tf, clip, depth + 1) if child
      when 12, 13
        child = offset + r.u24
        toff  = offset + r.u24
        tr    = Reader.new(@colr)
        tr.seek(toff)
        m = Transform.new(tr.fixed, tr.fixed, tr.fixed, tr.fixed, tr.fixed, tr.fixed)
        paint(target, child, tf.concat(m), clip, depth + 1)
      when 14, 15
        child = offset + r.u24
        dx    = r.i16.to_f
        dy    = r.i16.to_f
        paint(target, child, tf.concat(Transform.translate(dx, dy)), clip, depth + 1)
      when 16, 17, 18, 19, 20, 21, 22, 23
        child = offset + r.u24
        if format < 20
          sx = r.f2dot14
          sy = r.f2dot14
        else
          sx = r.f2dot14
          sy = sx
        end
        m = Transform.scale(sx, sy)
        m = m.around(r.i16.to_f, r.i16.to_f) if format == 18 || format == 19 || format == 22 || format == 23
        paint(target, child, tf.concat(m), clip, depth + 1)
      when 24, 25, 26, 27
        child = offset + r.u24
        m     = Transform.rotate(r.f2dot14 * Math::PI)
        m     = m.around(r.i16.to_f, r.i16.to_f) if format == 26 || format == 27
        paint(target, child, tf.concat(m), clip, depth + 1)
      when 28, 29, 30, 31
        child = offset + r.u24
        m     = Transform.skew(r.f2dot14 * Math::PI, r.f2dot14 * Math::PI)
        m     = m.around(r.i16.to_f, r.i16.to_f) if format == 30 || format == 31
        paint(target, child, tf.concat(m), clip, depth + 1)
      when 32
        source = offset + r.u24
        r.u8
        backdrop = offset + r.u24
        paint(target, backdrop, tf, clip, depth + 1)
        paint(target, source, tf, clip, depth + 1)
      end
    end

    private def linear_paint(line : ColorLine, tf : Transform,
                             x0 : Float64, y0 : Float64, x1 : Float64,
                             y1 : Float64, x2 : Float64, y2 : Float64) : Paint
      inverse = tf.invert
      return SolidPaint.new(line.sample(0.0)) unless inverse
      nx = -(y2 - y0)
      ny = x2 - x0
      nn = nx * nx + ny * ny
      if nn > 1e-9
        k  = ((x1 - x0) * nx + (y1 - y0) * ny) / nn
        px = x0 + k * nx
        py = y0 + k * ny
      else
        px = x1
        py = y1
      end
      dx   = px - x0
      dy   = py - y0
      len2 = dx * dx + dy * dy
      return SolidPaint.new(line.sample(0.0)) if len2 < 1e-9
      LinearPaint.new(line, inverse, x0, y0, dx, dy, len2)
    end

    private def color_line(offset : Int32, variable : Bool) : ColorLine
      r = Reader.new(@colr)
      r.seek(offset)
      mode = case r.u8
             when 1 then Extend::Repeat
             when 2 then Extend::Reflect
             else        Extend::Pad
             end
      count = r.u16.to_i32
      stops = Array(ColorStop).new(count)
      i     = 0
      while i < count
        at    = r.f2dot14
        pal   = r.u16
        alpha = r.f2dot14
        r.u32 if variable
        stops << ColorStop.new(at, color_for(pal, alpha))
        i += 1
      end
      stops.sort! { |l, r2| l.offset <=> r2.offset }
      ColorLine.new(stops, mode)
    end

    private def glyph_mask(glyph_id : Int32, tf : Transform) : Slice(Float32)?
      return nil if glyph_id < 0 || glyph_id >= @outlines.size
      mask_w  = @subpixel ? @width * 3 : @width
      tf_mask = @subpixel ? Transform.scale(3.0, 1.0).concat(tf) : tf
      Fill.coverage(Path.flatten(@outlines[glyph_id], tf_mask), mask_w, @height)
    end

    private def color_for(index : UInt16, alpha : Float64) : UInt32
      rgba = if index == FOREGROUND || index >= @palette.size
               0xff000000_u32 | (@fg & 0x00ffffff_u32)
             else
               @palette[index.to_i32]
             end
      alpha = 0.0 if alpha < 0.0
      alpha = 1.0 if alpha > 1.0
      a     = (((rgba >> 24) & 0xff).to_f * alpha).round.to_u32
      (rgba & 0x00ffffff_u32) | (a << 24)
    end
  end
end
