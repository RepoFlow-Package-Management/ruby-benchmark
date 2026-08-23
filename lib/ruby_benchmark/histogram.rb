module RubyBenchmark
  class Histogram
    BUCKETS = 512

    attr_reader :count, :sum, :maximum

    def initialize
      @counts = Array.new(BUCKETS, 0)
      @count = 0
      @sum = 0
      @maximum = 0
    end

    def record(microseconds)
      value = microseconds.to_i
      @counts[index(value)] += 1
      @count += 1
      @sum += value
      @maximum = value if value > @maximum
    end

    def merge(other)
      @count += other.count
      @sum += other.sum
      @maximum = other.maximum if other.maximum > @maximum
      @counts.each_index { |index| @counts[index] += other.counts[index] }
    end

    def percentile(value)
      return 0 if @count.zero?
      rank = (@count * value / 100.0).ceil
      seen = 0
      @counts.each_with_index do |amount, index|
        seen += amount
        next if seen < rank
        return [bucket_upper(index), @maximum].min
      end
      @maximum
    end

    def to_h
      {
        mean_us: @count.zero? ? 0.0 : @sum.to_f / @count,
        p50_us: percentile(50),
        p90_us: percentile(90),
        p95_us: percentile(95),
        p99_us: percentile(99),
        max_us: @maximum
      }
    end

    protected

    attr_reader :counts

    private

    def index(value)
      return 0 if value <= 0
      exponent = Math.log2(value).floor
      exponent = 62 if exponent > 62
      base = 1 << exponent
      width = base / 8
      sub = width.positive? ? (value - base) / width : 0
      1 + exponent * 8 + [sub, 7].min
    end

    def bucket_upper(index)
      return 0 if index.zero?
      raw = index - 1
      exponent = raw / 8
      sub = raw % 8
      base = 1 << exponent
      width = base / 8
      width.positive? ? base + (sub + 1) * width - 1 : base * 2 - 1
    end
  end
end
