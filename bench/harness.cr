# bench/harness.cr
require "../src/glyph"

module Bench
  LABEL_WIDTH  = 46
  COLUMN_WIDTH = 12
  ROUNDS       = 15
  ALLOC_ROUNDS =  3
  MAX_BATCH    = 1 << 22
  WARMUP       = 20.milliseconds

  TARGET_ROUND_NS = 5_000_000.0

  RELEASE = {{ flag?(:release) }}
  GC_NAME = {{ flag?(:gc_none) ? "none" : "boehm" }}

  struct Result
    getter label        : String
    getter ops          : Int64
    getter min_ns       : Float64
    getter p50_ns       : Float64
    getter max_ns       : Float64
    getter bytes_per_op : Float64

    def initialize(@label : String, @ops : Int64, @min_ns : Float64,
                   @p50_ns : Float64, @max_ns : Float64, @bytes_per_op : Float64)
    end
  end

  class_property sink = 0_u64

  @@overhead_ns = 0.0
  @@calibrated  = false

  def self.consume(value : Int) : Nil
    @@sink &+= value.to_u64!
  end

  def self.consume(value : Float) : Nil
    @@sink &+= value.to_f64.unsafe_as(UInt64)
  end

  def self.consume(value : String) : Nil
    @@sink &+= value.bytesize.to_u64
  end

  def self.consume(value : Bytes) : Nil
    @@sink &+= value.size.to_u64
  end

  def self.consume(value : Bool) : Nil
    @@sink &+= (value ? 1_u64 : 0_u64)
  end

  def self.banner(title : String) : Nil
    puts "\e[1m#{title}\e[0m  term-compositor #{Glyph::VERSION}"
    puts "  crystal #{Crystal::VERSION}   release=#{RELEASE}   gc=#{GC_NAME}"
    puts "  \e[33mnot a --release build: timings are meaningless\e[0m" unless RELEASE
    puts "  min/p50/max over #{ROUNDS} rounds, alloc from GC::Stats#total_bytes"
  end

  def self.header(title : String) : Nil
    puts
    puts "\e[1m#{title}\e[0m"
    puts "  #{"benchmark".ljust(LABEL_WIDTH)}" \
         "#{"min".rjust(COLUMN_WIDTH)}#{"p50".rjust(COLUMN_WIDTH)}" \
         "#{"max".rjust(COLUMN_WIDTH)}#{"alloc".rjust(COLUMN_WIDTH)}"
  end

  def self.footer : Nil
    settle
    stats = GC.stats
    puts
    puts "  peak rss #{fmt_bytes(peak_rss.to_f)}   " \
         "live heap #{fmt_bytes(live_bytes.to_f)}   " \
         "heap #{fmt_bytes(stats.heap_size.to_f)}"
  end

  def self.note(label : String, value : String) : Nil
    puts "  #{label.ljust(LABEL_WIDTH)}#{value.rjust(COLUMN_WIDTH)}"
  end

  def self.skip(label : String, why : String) : Nil
    puts "  #{label.ljust(LABEL_WIDTH)}#{"skipped".rjust(COLUMN_WIDTH)}   #{why}"
  end

  def self.run(label : String, setup : Proc(Nil)? = nil, &block : ->) : Result
    warmup(setup, block)
    batch   = calibrate(setup, block)
    samples = Array(Float64).new(ROUNDS)
    r       = 0
    while r < ROUNDS
      samples << time_round(setup, block, batch)
      r += 1
    end
    samples.sort!
    result = Result.new(label, batch.to_i64 * ROUNDS,
      net(samples.first), net(percentile(samples, 0.5)), net(samples.last),
      alloc_per_op(setup, block, batch))
    emit(result)
    result
  end

  def self.retained(label : String, &block : ->) : Nil
    settle
    before_live  = live_bytes
    before_total = GC.stats.total_bytes
    block.call
    settle
    after_live  = live_bytes
    after_total = GC.stats.total_bytes
    held        = after_live > before_live ? (after_live - before_live).to_f : 0.0
    total       = (after_total - before_total).to_f
    puts "  #{label.ljust(LABEL_WIDTH)}" \
         "allocated #{fmt_bytes(total)}, retained #{fmt_bytes(held)}"
  end

  def self.live_bytes : UInt64
    stats = GC.stats
    stats.heap_size > stats.free_bytes ? stats.heap_size - stats.free_bytes : 0_u64
  end

  def self.peak_rss : Int64
    File.each_line("/proc/self/status") do |line|
      next unless line.starts_with?("VmHWM:")
      field = line.split[1]?
      return field ? field.to_i64 * 1024 : 0_i64
    end
    0_i64
  rescue
    0_i64
  end

  def self.fmt_time(ns : Float64) : String
    return "#{(ns / 1_000_000.0).round(2)} ms" if ns >= 1_000_000.0
    return "#{(ns / 1_000.0).round(2)} µs" if ns >= 1_000.0
    "#{ns.round(1)} ns"
  end

  def self.fmt_bytes(bytes : Float64) : String
    return "#{(bytes / 1_048_576.0).round(2)} MiB" if bytes >= 1_048_576.0
    return "#{(bytes / 1024.0).round(2)} KiB" if bytes >= 1024.0
    return "0 B" if bytes < 0.5
    "#{bytes.round(1)} B"
  end

  private def self.settle : Nil
    GC.collect
    GC.collect
  end

  private def self.emit(result : Result) : Nil
    puts "  #{result.label.ljust(LABEL_WIDTH)}" \
         "#{fmt_time(result.min_ns).rjust(COLUMN_WIDTH)}" \
         "#{fmt_time(result.p50_ns).rjust(COLUMN_WIDTH)}" \
         "#{fmt_time(result.max_ns).rjust(COLUMN_WIDTH)}" \
         "#{fmt_bytes(result.bytes_per_op).rjust(COLUMN_WIDTH)}"
  end

  private def self.net(ns : Float64) : Float64
    v = ns - overhead
    v < 0.0 ? 0.0 : v
  end

  private def self.overhead : Float64
    return @@overhead_ns if @@calibrated
    @@calibrated = true
    noop         = -> { }
    batch        = 1 << 16
    best         = Float64::MAX
    r            = 0
    while r < 5
      started = Time.instant
      i       = 0
      while i < batch
        noop.call
        i += 1
      end
      per  = (Time.instant - started).total_nanoseconds / batch
      best = per if per < best
      r += 1
    end
    @@overhead_ns = best
  end

  private def self.warmup(setup : Proc(Nil)?, block : Proc(Nil)) : Nil
    deadline = Time.instant + WARMUP
    loop do
      setup.try &.call
      block.call
      break if Time.instant >= deadline
    end
  end

  private def self.calibrate(setup : Proc(Nil)?, block : Proc(Nil)) : Int32
    batch = 1
    loop do
      started = Time.instant
      i       = 0
      while i < batch
        setup.try &.call
        block.call
        i += 1
      end
      ns = (Time.instant - started).total_nanoseconds
      return batch if ns >= TARGET_ROUND_NS || batch >= MAX_BATCH
      grow  = (TARGET_ROUND_NS / Math.max(ns, 1.0)).ceil.to_i
      grow  = 2 if grow < 2
      grow  = 512 if grow > 512
      batch = batch >= MAX_BATCH // grow ? MAX_BATCH : batch * grow
    end
  end

  private def self.time_round(setup : Proc(Nil)?, block : Proc(Nil), batch : Int32) : Float64
    if setup
      s     = setup
      total = 0.0
      i     = 0
      while i < batch
        s.call
        started = Time.instant
        block.call
        total += (Time.instant - started).total_nanoseconds
        i += 1
      end
      total / batch
    else
      started = Time.instant
      i       = 0
      while i < batch
        block.call
        i += 1
      end
      (Time.instant - started).total_nanoseconds / batch
    end
  end

  private def self.alloc_per_op(setup : Proc(Nil)?, block : Proc(Nil), batch : Int32) : Float64
    ops      = (batch.to_i64 * ALLOC_ROUNDS).to_f
    combined = sweep(setup, block, batch)
    return combined / ops unless setup
    solo = sweep(nil, setup, batch)
    net  = combined - solo
    net < 0.0 ? 0.0 : net / ops
  end

  private def self.sweep(setup : Proc(Nil)?, block : Proc(Nil), batch : Int32) : Float64
    GC.collect
    before = GC.stats.total_bytes
    r      = 0
    while r < ALLOC_ROUNDS
      i = 0
      while i < batch
        setup.try &.call
        block.call
        i += 1
      end
      r += 1
    end
    (GC.stats.total_bytes - before).to_f
  end

  private def self.percentile(sorted : Array(Float64), q : Float64) : Float64
    return 0.0 if sorted.empty?
    idx = ((sorted.size - 1) * q).round.to_i
    sorted.unsafe_fetch(idx.clamp(0, sorted.size - 1))
  end
end
