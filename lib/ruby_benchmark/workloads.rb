require "base64"
require "digest"
require "json"
require "zlib"

module RubyBenchmark
  class Workload
    attr_reader :fingerprint

    def initialize(config)
      @config = config
      payloads = Payloads.new(config.payload_pool, config.payload_bytes, config.seed)
      @payloads = payloads.items
      @fingerprint = payloads.fingerprint
      @cache = {}
      @cache_locks = Array.new(64) { Mutex.new }
    end

    def state(thread_index)
      WorkState.new(self, @config, @payloads, thread_index)
    end

    def cache_fetch(key)
      lock = @cache_locks[key % @cache_locks.length]
      lock.synchronize { @cache[key] }
    end

    def cache_store(key, value)
      lock = @cache_locks[key % @cache_locks.length]
      lock.synchronize do
        @cache.shift if @cache.length >= @config.cache_size && !@cache.key?(key)
        @cache[key] = value
      end
    end
  end

  class WorkState
    attr_reader :counters

    def initialize(workload, config, payloads, thread_index)
      @workload = workload
      @config = config
      @payloads = payloads
      @random = Random.new(config.seed ^ ((thread_index + 1) * 0x9e3779b9))
      @counters = Hash.new(0)
      @hash = {}
      @json_object = {
        "id" => 42,
        "ts" => 1_700_000_000,
        "user" => "user42",
        "flag" => true,
        "msg" => payloads.first.byteslice(0, 128)
      }
    end

    def call(request_id)
      return app(request_id) if @config.scenario == "appsim"
      micro(request_id)
    end

    private

    def app(request_id)
      payload = @payloads[request_id % @payloads.length]
      parsed = JSON.parse(payload)
      key = (parsed["id"] ^ parsed["ts"] ^ stable_hash(parsed["user"])) % @config.cache_size
      digest = @random.rand < 0.8 ? @workload.cache_fetch(key) : nil
      if digest
        @counters[:cache_hits] += 1
      else
        @counters[:cache_misses] += 1
        digest = Digest::SHA256.digest(payload)
        @workload.cache_store(key, digest)
      end
      encoded = Base64.strict_encode64(digest)
      response = JSON.generate("id" => parsed["id"], "ts" => parsed["ts"], "ok" => true, "hash" => encoded)
      if @config.alloc_bytes.positive?
        allocation = "x" * @config.alloc_bytes
        @counters[:allocated_bytes] += allocation.bytesize
        response.bytesize ^ allocation.getbyte(0)
      else
        response.bytesize
      end
    end

    def micro(request_id)
      payload = @payloads[request_id % @payloads.length]
      case @config.scenario
      when "micro_json_parse"
        object = JSON.parse(payload)
        object["id"] ^ object["ts"] ^ object["user"].bytesize
      when "micro_json_generate"
        JSON.generate(@json_object).bytesize
      when "micro_sha256"
        Digest::SHA256.digest(payload).unpack1("Q")
      when "micro_base64"
        Base64.strict_decode64(Base64.strict_encode64(payload)).bytesize
      when "micro_regex"
        match = /"user":"(user\d+)"/.match(payload)
        match ? match[1].bytesize : 0
      when "micro_sort_int"
        values = payload.unpack("l<*")[0, 256]
        sorted = values.sort
        sorted.first ^ sorted.last
      when "micro_hash_churn"
        key = @random.rand(4096)
        @hash[key] = (@hash[key] || 0) * 33 + request_id
        @hash.delete(@random.rand(4096)) if @hash.length > 2048
        @hash[key]
      when "micro_marshal"
        Marshal.load(Marshal.dump(@json_object))["id"]
      when "micro_zlib"
        Zlib::Inflate.inflate(Zlib::Deflate.deflate(payload, 1)).bytesize
      else
        raise "unsupported scenario #{@config.scenario}"
      end
    end

    def stable_hash(value)
      value.each_byte.reduce(1_469_598_103_934_665_603) do |hash, byte|
        (hash ^ byte) * 1_099_511_628_211 & 0xffffffffffffffff
      end
    end
  end
end
