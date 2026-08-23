require "json"
require "socket"
require "time"

module RubyBenchmark
  class Runner
    def initialize(config)
      @config = config
      @workload = Workload.new(config)
    end

    def run
      @config.validate!
      warmup = @config.warmup.positive? ? phase(@config.warmup, false) : empty_phase
      measured = phase(@config.measure, true)
      {
        "schema_version" => 1,
        "run_id" => "#{Time.now.utc.strftime('%Y%m%dT%H%M%S.%N')}Z-#{Socket.gethostname}",
        "timestamp_utc" => Time.now.utc.iso8601(9),
        "scenario" => @config.scenario,
        "profile" => @config.profile,
        "runtime" => {
          "name" => RUBY_ENGINE,
          "version" => RUBY_VERSION,
          "description" => RUBY_DESCRIPTION
        },
        "config" => @config.to_h,
        "payload_fingerprint" => @workload.fingerprint,
        "warmup_results" => warmup,
        "results" => measured
      }
    end

    private

    def phase(duration, capture_samples)
      start = monotonic
      deadline = start + duration
      workers = Array.new(@config.threads) do |index|
        Thread.new do
          state = @workload.state(index)
          histogram = Histogram.new
          operations = 0
          sink = 0
          request_id = index * 1_000_000
          while monotonic < deadline
            operation_start = monotonic
            sink ^= state.call(request_id).to_i
            histogram.record(((monotonic - operation_start) * 1_000_000).ceil)
            operations += 1
            request_id += 1
          end
          { operations: operations, histogram: histogram, counters: state.counters, sink: sink }
        end
      end
      sampler = capture_samples ? Sampler.new(@config.sample_interval) : nil
      sample_until(deadline, sampler)
      results = workers.map(&:value)
      elapsed = monotonic - start
      histogram = Histogram.new
      counters = Hash.new(0)
      operations = 0
      results.each do |result|
        operations += result[:operations]
        histogram.merge(result[:histogram])
        result[:counters].each { |key, value| counters[key] += value }
      end
      output = {
        "duration_s" => elapsed,
        "ops" => operations,
        "throughput_ops_s" => operations / elapsed,
        "latency" => histogram.to_h,
        "work" => counters.transform_keys(&:to_s)
      }
      output.merge!(sampler.result(@config.timeseries)) if sampler
      output
    end

    def sample_until(deadline, sampler)
      return sleep_until(deadline) unless sampler
      while (remaining = deadline - monotonic).positive?
        sleep([sampler.interval, remaining].min)
        sampler.capture
      end
    end

    def sleep_until(deadline)
      remaining = deadline - monotonic
      sleep(remaining) if remaining.positive?
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def empty_phase
      {
        "duration_s" => 0.0,
        "ops" => 0,
        "throughput_ops_s" => 0.0,
        "latency" => Histogram.new.to_h,
        "work" => {}
      }
    end
  end
end
