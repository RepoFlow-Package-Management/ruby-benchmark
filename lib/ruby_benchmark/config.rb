module RubyBenchmark
  SCENARIOS = %w[
    appsim
    micro_json_parse
    micro_json_generate
    micro_sha256
    micro_base64
    micro_regex
    micro_sort_int
    micro_hash_churn
    micro_marshal
    micro_zlib
  ].freeze

  PROFILES = {
    "light" => { payload_bytes: 1024, payload_pool: 1024, alloc_bytes: 256 },
    "heavy" => { payload_bytes: 8192, payload_pool: 1024, alloc_bytes: 4096 }
  }.freeze

  class Config
    attr_accessor :scenario, :threads, :warmup, :measure, :sample_interval,
                  :payload_bytes, :payload_pool, :alloc_bytes, :cache_size,
                  :seed, :profile, :timeseries, :output_path

    def initialize
      @scenario = "appsim"
      @threads = 10
      @warmup = 20.0
      @measure = 600.0
      @sample_interval = 1.0
      @payload_bytes = 1024
      @payload_pool = 1024
      @alloc_bytes = 256
      @cache_size = 50_000
      @seed = 1
      @profile = "light"
      @timeseries = true
      @output_path = nil
    end

    def apply_profile(name)
      settings = PROFILES.fetch(name)
      @profile = name
      settings.each { |key, value| public_send("#{key}=", value) }
    end

    def validate!
      raise ArgumentError, "unsupported scenario #{@scenario}" unless SCENARIOS.include?(@scenario)
      raise ArgumentError, "threads must be positive" unless @threads.positive?
      raise ArgumentError, "invalid duration" if @warmup.negative? || !@measure.positive?
      raise ArgumentError, "sample interval must be positive" unless @sample_interval.positive?
      raise ArgumentError, "invalid payload settings" if @payload_bytes < 256 || @payload_pool < 1
      raise ArgumentError, "cache size must be positive" unless @cache_size.positive?
    end

    def to_h
      {
        threads: @threads,
        warmup_s: @warmup,
        measure_s: @measure,
        sample_interval_s: @sample_interval,
        payload_bytes: @payload_bytes,
        payload_pool: @payload_pool,
        alloc_bytes: @alloc_bytes,
        cache_size: @cache_size,
        seed: @seed
      }
    end
  end
end
