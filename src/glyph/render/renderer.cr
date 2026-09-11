# src/glyph/render/renderer.cr
class Glyph::Renderer
  MAX_CACHE = 1024

  getter cell_width  : Int32
  getter cell_height : Int32
  getter baseline    : Int32

  property subpixel      : Bool = false
  property gamma_correct : Bool = false

  def initialize(cell_width : Int32, cell_height : Int32, baseline : Int32? = nil)
    raise ArgumentError.new("cell metrics must be positive") if cell_width <= 0 || cell_height <= 0
    @cell_width  = cell_width
    @cell_height = cell_height
    @baseline    = baseline || (cell_height * 4) // 5
    @cache       = {} of Tuple(Int32, UInt64, UInt32, Bool, Bool) => Image
    @cache_order = Deque(Tuple(Int32, UInt64, UInt32, Bool, Bool)).new
  end

  def resize(cell_width : Int32, cell_height : Int32, baseline : Int32? = nil) : Nil
    raise ArgumentError.new("cell metrics must be positive") if cell_width <= 0 || cell_height <= 0
    @cell_width  = cell_width
    @cell_height = cell_height
    @baseline    = baseline || (cell_height * 4) // 5
    @cache.clear
    @cache_order.clear
  end

  def render(reg : Registration, fg_rgb : UInt32) : Image
    key = {reg.cp, reg.tag, fg_rgb, @subpixel, @gamma_correct}
    if cached = @cache[key]?
      @cache_order.delete(key)
      @cache_order.push(key)
      return cached
    end

    width  = reg.span * @cell_width
    height = @cell_height
    bitmap = Bitmap.new(width, height, @subpixel, @gamma_correct)
    tf     = Layout.resolve(reg, @cell_width, @cell_height, @baseline)

    begin
      if reg.format.glyf? || reg.format.cff? || reg.colr.empty?
        outline = reg.outlines.first?
        if outline
          mask_w  = @subpixel ? width * 3 : width
          tf_mask = @subpixel ? Transform.scale(3.0, 1.0).concat(tf) : tf
          mask    = Fill.coverage(Path.flatten(outline, tf_mask), mask_w, height)
          bitmap.blend(mask, SolidPaint.new(0xff000000_u32 | (fg_rgb & 0x00ffffff_u32)))
        end
      else
        ColrRenderer.new(reg.outlines, reg.colr, reg.palette, fg_rgb, width, height, @subpixel)
          .render(bitmap, tf)
      end
    rescue IndexError | Glyph::Error
      # Render-time rescue: bad glyph gracefully degrades to a blank image
      # rather than crashing the compositor's render loop.
    end

    image = Image.new(width, height, bitmap.to_rgba8)

    if @cache.size >= MAX_CACHE
      evict_key = @cache_order.shift
      @cache.delete(evict_key)
    end

    @cache[key] = image
    @cache_order.push(key)
    image
  end
end
