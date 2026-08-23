require "etc"

module RubyBenchmark
  class Sampler
    attr_reader :samples

    def initialize(interval)
      @interval = interval
      @processors = Etc.nprocessors
      @samples = []
      @start_wall = monotonic
      @previous_wall = @start_wall
      @previous_cpu = cpu_time
      @gc_start = GC.stat
      GC::Profiler.enable
      @gc_time_start = GC::Profiler.total_time
    end

    def capture
      now = monotonic
      cpu = cpu_time
      wall_delta = now - @previous_wall
      cpu_percent = wall_delta.positive? ? (cpu - @previous_cpu) / wall_delta * 100.0 / @processors : 0.0
      stats = GC.stat
      @samples << {
        "t_s" => now - @start_wall,
        "process_pct_all" => cpu_percent,
        "process_rss_bytes" => rss_bytes,
        "heap_live_slots" => stats[:heap_live_slots] || 0,
        "total_allocated_objects" => stats[:total_allocated_objects] || 0
      }
      @previous_wall = now
      @previous_cpu = cpu
    end

    def gc_result
      current = GC.stat
      {
        "collections" => (current[:count] || 0) - (@gc_start[:count] || 0),
        "pause_total_ms" => (GC::Profiler.total_time - @gc_time_start) * 1000.0,
        "allocated_objects" => (current[:total_allocated_objects] || 0) - (@gc_start[:total_allocated_objects] || 0)
      }
    end

    def result(timeseries)
      cpu_values = @samples.map { |sample| sample["process_pct_all"] }
      rss_values = @samples.map { |sample| sample["process_rss_bytes"] }.reject(&:zero?)
      heap_values = @samples.map { |sample| sample["heap_live_slots"] }
      {
        "gc" => gc_result,
        "cpu" => { "process_pct_all_cores" => stats(cpu_values), "sample_count" => @samples.length },
        "memory" => {
          "process_rss_bytes" => stats(rss_values),
          "heap_live_slots" => stats(heap_values),
          "sample_count" => @samples.length
        },
        "timeseries" => timeseries ? @samples : []
      }
    end

    def interval
      @interval
    end

    private

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def cpu_time
      Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
    end

    def rss_bytes
      line = File.foreach("/proc/self/status").find { |entry| entry.start_with?("VmRSS:") }
      line ? line.split[1].to_i * 1024 : 0
    rescue Errno::ENOENT
      0
    end

    def stats(values)
      return {} if values.empty?
      sorted = values.sort
      {
        "mean" => values.sum.to_f / values.length,
        "p50" => percentile(sorted, 50),
        "p95" => percentile(sorted, 95),
        "max" => sorted.last
      }
    end

    def percentile(sorted, value)
      sorted[[(sorted.length * value / 100.0).ceil - 1, 0].max]
    end
  end
end
