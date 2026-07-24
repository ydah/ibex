# frozen_string_literal: true

module BenchmarkSupport
  # Observes the current process's resident set without imposing a threshold.
  module PeakRSS
    POLL_SECONDS = 0.01

    module_function

    def observe
      running = true
      peak = current_rss
      sampler = Thread.new do
        while running
          sample = current_rss
          peak = [peak, sample].compact.max
          sleep(POLL_SECONDS)
        end
      end
      begin
        yield
      ensure
        running = false
        sampler.join
      end
      [peak, current_rss, linux_high_water_mark].compact.max
    end

    def current_rss
      linux_status("VmRSS") || ps_rss
    end

    def linux_high_water_mark
      linux_status("VmHWM")
    end

    def linux_status(label)
      path = "/proc/#{Process.pid}/status"
      return nil unless File.readable?(path)

      match = File.read(path).match(/^#{label}:\s+(\d+)\s+kB$/)
      match && (Integer(match[1], 10) * 1024)
    rescue SystemCallError
      nil
    end

    def ps_rss
      output = IO.popen(["ps", "-o", "rss=", "-p", Process.pid.to_s], &:read)
      value = output.strip
      value.empty? ? nil : Integer(value, 10) * 1024
    rescue ArgumentError, SystemCallError
      nil
    end
  end
end
