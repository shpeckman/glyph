# src/glyph/layout.cr
module Glyph
  module Layout
    def self.resolve(reg : Registration, cell_width : Int32, cell_height : Int32,
                     baseline : Int32) : Transform
      w   = (reg.span * cell_width).to_f
      h   = cell_height.to_f
      pad = reg.pad.degenerate? ? Pad.none : reg.pad
      pl  = w * pad.left
      pr  = w * pad.right
      pt  = h * pad.top
      pb  = h * pad.bottom
      ew  = w - pl - pr
      eh  = h - pt - pb
      aw  = reg.metrics.aw.to_f
      lh  = reg.metrics.lh.to_f
      aw  = 1.0 if aw <= 0.0
      lh  = 1.0 if lh <= 0.0

      sx = 0.0
      sy = 0.0
      case reg.size
      in .height?
        sx = eh / lh
        sy = sx
      in .advance?
        sx = ew / aw
        sy = sx
      in .contain?
        sx = Math.min(ew / aw, eh / lh)
        sy = sx
      in .cover?
        sx = Math.max(ew / aw, eh / lh)
        sy = sx
      in .stretch?
        sx = ew / aw
        sy = eh / lh
      end

      asc      = baseline.to_f
      desc     = (cell_height - baseline).to_f
      total    = asc + desc
      total    = 1.0 if total <= 0.0
      y_max    = lh * (asc / total)
      y_min    = y_max - lh
      scaled_w = aw * sx

      ox = case reg.halign
           in .start?  then pl
           in .center? then pl + (ew - scaled_w) * 0.5
           in .end?    then w - pr - scaled_w
           end

      oy = case reg.valign
           in .start?    then (h - pb) + y_min * sy
           in .center?   then (pt + eh * 0.5) + ((y_min + y_max) * 0.5) * sy
           in .end?      then pt + y_max * sy
           in .baseline? then pt + baseline.to_f
           end

      Transform.new(sx, 0.0, 0.0, -sy, ox, oy)
    end
  end
end
