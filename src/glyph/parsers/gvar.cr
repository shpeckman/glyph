# src/glyph/parsers/gvar.cr
module Glyph::Gvar
  private struct TupleHeader
    getter size               : Int32
    getter peak               : Array(Float64)
    getter inter_start        : Array(Float64)?
    getter inter_end          : Array(Float64)?
    getter has_private_points : Bool

    def initialize(@size : Int32, @peak : Array(Float64), @inter_start : Array(Float64)?, @inter_end : Array(Float64)?, @has_private_points : Bool)
    end
  end

  def self.apply(outlines : Array(Outline), gvar : Bytes, coords : Array(Float64)) : Array(Outline)
    return outlines if gvar.empty? || coords.all?(0.0)

    r = Reader.new(gvar)
    r.u32 # version
    axis_count           = r.u16.to_i32
    shared_tuple_count   = r.u16.to_i32
    shared_tuples_offset = r.u32.to_i32
    glyph_count          = r.u16.to_i32
    flags                = r.u16.to_i32
    data_offset          = r.u32.to_i32

    offsets = Array(Int32).new(glyph_count + 1)
    (glyph_count + 1).times do
      offsets << ((flags & 1) != 0 ? r.u32.to_i32 : r.u16.to_i32 * 2)
    end

    shared_tuples = Array(Array(Float64)).new(shared_tuple_count)
    if shared_tuple_count > 0
      r.seek(shared_tuples_offset)
      shared_tuple_count.times do
        t = [] of Float64
        axis_count.times { t << r.f2dot14 }
        shared_tuples << t
      end
    end

    mutated = [] of Outline
    outlines.each_with_index do |outline, gid|
      if gid >= glyph_count || offsets[gid] == offsets[gid + 1]
        mutated << outline
        next
      end

      r.seek(data_offset + offsets[gid])
      tuple_count_flags = r.u16.to_i32
      tuple_count       = tuple_count_flags & 0x0FFF
      tuple_data_offset = r.u16.to_i32 + data_offset + offsets[gid]

      headers = [] of TupleHeader
      tuple_count.times do
        size = r.u16.to_i32
        idx  = r.u16.to_i32

        peak = nil
        if (idx & 0x8000) != 0
          peak = [] of Float64
          axis_count.times { peak << r.f2dot14 }
        else
          idx_masked = idx & 0x0FFF
          raise Error.new(Error::Reason::MalformedPayload) if idx_masked >= shared_tuples.size
          peak = shared_tuples.unsafe_fetch(idx_masked)
        end

        inter_start = nil
        inter_end   = nil
        if (idx & 0x4000) != 0
          inter_start = [] of Float64
          axis_count.times { inter_start << r.f2dot14 }
          inter_end = [] of Float64
          axis_count.times { inter_end << r.f2dot14 }
        end

        has_private_points = (idx & 0x2000) != 0
        headers << TupleHeader.new(size, peak, inter_start, inter_end, has_private_points)
      end

      scalars = headers.map { |h| calculate_scalar(coords, h.peak, h.inter_start, h.inter_end) }

      r.seek(tuple_data_offset)

      shared_points = nil
      if (tuple_count_flags & 0x8000) != 0
        shared_points = read_packed_points(r)
      end

      num_points = outline.point_count + 4
      total_dx   = Array(Float64).new(num_points, 0.0)
      total_dy   = Array(Float64).new(num_points, 0.0)

      headers.each_with_index do |h, i|
        scalar   = scalars[i]
        next_pos = r.pos + h.size

        if scalar == 0.0
          r.seek(next_pos)
          next
        end

        pts         = h.has_private_points ? read_packed_points(r) : shared_points
        point_count = pts ? pts.size : num_points

        dxs = read_packed_deltas(r, point_count)
        dys = read_packed_deltas(r, point_count)

        tuple_dx  = Array(Float64).new(num_points, 0.0)
        tuple_dy  = Array(Float64).new(num_points, 0.0)
        has_delta = Array(Bool).new(num_points, false)

        if pts
          pts.each_with_index do |pt_idx, j|
            if pt_idx < num_points
              tuple_dx[pt_idx] = dxs[j]
              tuple_dy[pt_idx] = dys[j]
              has_delta[pt_idx] = true
            end
          end
          iup(outline, tuple_dx, tuple_dy, has_delta)
        else
          0.upto(num_points - 1) do |j|
            tuple_dx[j] = dxs[j]
            tuple_dy[j] = dys[j]
          end
        end

        0.upto(num_points - 1) do |j|
          total_dx[j] += tuple_dx[j] * scalar
          total_dy[j] += tuple_dy[j] * scalar
        end

        r.seek(next_pos)
      end

      new_points = Slice(Point).new(outline.point_count) do |i|
        p = outline.points.unsafe_fetch(i)
        Point.new(
          (p.x + total_dx[i]).round.to_i32,
          (p.y + total_dy[i]).round.to_i32,
          p.type
        )
      end

      mutated << Outline.from_points(new_points, outline.ends)
    end

    mutated
  rescue IndexError
    raise Error.new(Error::Reason::MalformedPayload)
  end

  private def self.calculate_scalar(coords : Array(Float64), peak : Array(Float64), start_coords : Array(Float64)?, end_coords : Array(Float64)?) : Float64
    scalar = 1.0
    coords.each_with_index do |v, i|
      p = peak[i]
      next if p == 0.0

      s = start_coords ? start_coords[i] : (p > 0.0 ? 0.0 : p)
      e = end_coords ? end_coords[i] : (p > 0.0 ? p : 0.0)

      if v == p
        scalar *= 1.0
      elsif v <= s || v >= e
        return 0.0
      elsif v < p
        scalar *= (v - s) / (p - s)
      else
        scalar *= (e - v) / (e - p)
      end
    end
    scalar
  end

  private def self.read_packed_points(r : Reader) : Array(Int32)?
    count_byte = r.u8
    return nil if count_byte == 0

    count = 0
    if (count_byte & 0x80) != 0
      count = ((count_byte & 0x7F).to_i32 << 8) | r.u8
    else
      count = count_byte.to_i32
    end

    points = [] of Int32
    while points.size < count
      control = r.u8
      num     = (control & 0x7F).to_i32 + 1
      if (control & 0x80) != 0
        num.times { points << r.u16.to_i32 }
      else
        num.times { points << r.u8.to_i32 }
      end
    end

    current = 0
    points.map! do |v|
      current += v
      current
    end
    points
  end

  private def self.read_packed_deltas(r : Reader, count : Int32) : Array(Float64)
    deltas = [] of Float64
    while deltas.size < count
      control = r.u8
      num     = (control & 0x3F).to_i32 + 1
      if (control & 0x80) != 0
        num.times { deltas << 0.0 }
      elsif (control & 0x40) != 0
        num.times { deltas << r.i16.to_f64 }
      else
        num.times { deltas << r.i8.to_f64 }
      end
    end
    deltas
  end

  private def self.iup(base : Outline, dx : Array(Float64), dy : Array(Float64), has_delta : Array(Bool))
    start = 0
    base.ends.each do |end_idx|
      iup_contour(base.points, dx, dy, has_delta, start, end_idx)
      start = end_idx + 1
    end
  end

  private def self.iup_contour(points : Slice(Point), dx : Array(Float64), dy : Array(Float64), has_delta : Array(Bool), start : Int32, end_idx : Int32)
    first_idx = -1
    start.upto(end_idx) do |i|
      if has_delta[i]
        first_idx = i
        break
      end
    end

    return if first_idx == -1

    touched = [] of Int32
    start.upto(end_idx) { |i| touched << i if has_delta[i] }

    if touched.size == 1
      d_x = dx[first_idx]
      d_y = dy[first_idx]
      start.upto(end_idx) do |i|
        dx[i] = d_x
        dy[i] = d_y
      end
      return
    end

    touched.each_with_index do |t1, i|
      t2 = touched[(i + 1) % touched.size]

      idx = (t1 + 1) > end_idx ? start : t1 + 1
      while idx != t2
        dx[idx] = interpolate(points[idx].x, points[t1].x, points[t2].x, dx[t1], dx[t2])
        dy[idx] = interpolate(points[idx].y, points[t1].y, points[t2].y, dy[t1], dy[t2])
        idx = (idx + 1) > end_idx ? start : idx + 1
      end
    end
  end

  private def self.interpolate(v : Int32, v1 : Int32, v2 : Int32, d1 : Float64, d2 : Float64) : Float64
    if v1 == v2
      return d1 == d2 ? d1 : 0.0
    end
    if v1 > v2
      v1, v2 = v2, v1
      d1, d2 = d2, d1
    end
    if v <= v1
      return d1
    elsif v >= v2
      return d2
    else
      ratio = (v - v1).to_f / (v2 - v1)
      return d1 + ratio * (d2 - d1)
    end
  end
end
