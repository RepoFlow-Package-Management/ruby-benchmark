require "digest"

module RubyBenchmark
  class Payloads
    attr_reader :items, :fingerprint

    def initialize(count, size, seed)
      random = Random.new(seed ^ 0x2d01a8cdb02a9c33)
      @items = Array.new(count) do |index|
        prefix = format(
          '{"id":%d,"ts":%d,"user":"user%d","flag":%s,"msg":"',
          index,
          1_700_000_000 + index * 13,
          index % 10_000,
          index.even? ? "true" : "false"
        )
        body_size = [size - prefix.bytesize - 2, 0].max
        prefix + Array.new(body_size) { (97 + random.rand(26)).chr }.join + '"}'
      end
      @fingerprint = Digest::SHA256.hexdigest(@items.join)[0, 16]
    end
  end
end
