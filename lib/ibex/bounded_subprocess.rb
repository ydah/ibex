# frozen_string_literal: true
# rbs_inline: enabled

require "tempfile"

module Ibex
  # Captures one shell-free child process under wall-clock and output budgets.
  class BoundedSubprocess
    DEFAULT_TIMEOUT_SECONDS = 10 #: Integer
    DEFAULT_MAX_OUTPUT_BYTES = 1_048_576 #: Integer
    TERMINATION_GRACE_SECONDS = 0.25 #: Float
    POLL_SECONDS = 0.01 #: Float

    # Immutable observation of one bounded child-process execution.
    class Result
      attr_reader :stdout #: String
      attr_reader :stderr #: String
      attr_reader :status #: Process::Status
      attr_reader :timed_out #: bool
      attr_reader :output_limited #: bool

      # @rbs (stdout: String, stderr: String, status: Process::Status,
      #   timed_out: bool, output_limited: bool) -> void
      def initialize(stdout:, stderr:, status:, timed_out:, output_limited:)
        @stdout = stdout.freeze
        @stderr = stderr.freeze
        @status = status
        @timed_out = timed_out
        @output_limited = output_limited
        freeze
      end
    end

    # @rbs (timeout_seconds: Integer, max_output_bytes: Integer) -> void
    def initialize(timeout_seconds: DEFAULT_TIMEOUT_SECONDS,
                   max_output_bytes: DEFAULT_MAX_OUTPUT_BYTES)
      raise ArgumentError, "timeout_seconds must be positive" unless timeout_seconds.positive?
      raise ArgumentError, "max_output_bytes must be positive" unless max_output_bytes.positive?

      @timeout_seconds = timeout_seconds
      @max_output_bytes = max_output_bytes
    end

    # @rbs (Array[String] command, input: String) -> Result
    def run(command, input:)
      raise ArgumentError, "command must not be empty" if command.empty?

      Tempfile.create("ibex-subprocess-input") do |stdin|
        Tempfile.create("ibex-subprocess-stdout") do |stdout|
          Tempfile.create("ibex-subprocess-stderr") do |stderr|
            run_with_files(command, input, stdin, stdout, stderr)
          end
        end
      end
    end

    private

    # @rbs (Array[String] command, String input, File stdin, File stdout, File stderr) -> Result
    def run_with_files(command, input, stdin, stdout, stderr)
      stdin.binmode
      stdin.write(input)
      stdin.flush
      stdin.rewind
      pid = spawn_child(command, stdin, stdout, stderr)
      status, timed_out, output_limited = wait(pid, stdout.path, stderr.path)
      terminate_descendants(pid)
      Result.new(
        stdout: read_bounded(stdout.path), stderr: read_bounded(stderr.path),
        status: status, timed_out: timed_out, output_limited: output_limited
      ).freeze
    ensure
      terminate(pid) if pid && !status
    end

    # @rbs (Array[String] command, File stdin, File stdout, File stderr) -> Integer
    def spawn_child(command, stdin, stdout, stderr)
      options = { in: stdin, out: stdout, err: stderr } #: Hash[Symbol, untyped]
      options[:pgroup] = true if process_groups?
      spawn(*command, **options)
    end

    # @rbs (Integer pid, String stdout_path, String stderr_path) ->
    #   [Process::Status, bool, bool]
    def wait(pid, stdout_path, stderr_path)
      deadline = monotonic_time + @timeout_seconds
      loop do
        waited = Process.waitpid2(pid, Process::WNOHANG)
        return [waited.last, false, false] if waited

        return [terminate(pid), false, true] if output_exceeded?(stdout_path, stderr_path)
        return [terminate(pid), true, false] if monotonic_time >= deadline

        sleep(POLL_SECONDS)
      end
    end

    # @rbs (Integer pid) -> Process::Status
    def terminate(pid)
      signal_process_tree("TERM", pid)
      deadline = monotonic_time + TERMINATION_GRACE_SECONDS
      loop do
        waited = Process.waitpid2(pid, Process::WNOHANG)
        return waited.last if waited
        break if monotonic_time >= deadline

        sleep(POLL_SECONDS)
      end
      signal_process_tree("KILL", pid)
      Process.waitpid2(pid).last
    rescue Errno::ESRCH, Errno::ECHILD
      process_status(pid)
    end

    # @rbs (Integer pid) -> void
    def terminate_descendants(pid)
      return unless process_groups?
      return unless process_group_alive?(pid)

      deadline = monotonic_time + TERMINATION_GRACE_SECONDS
      Process.kill("TERM", -pid)
      sleep(POLL_SECONDS) while process_group_alive?(pid) && monotonic_time < deadline
      Process.kill("KILL", -pid) if process_group_alive?(pid)
    rescue Errno::ESRCH
      nil
    end

    # @rbs (String signal, Integer pid) -> void
    def signal_process_tree(signal, pid)
      Process.kill(signal, process_groups? ? -pid : pid)
    end

    # @rbs (Integer pid) -> bool
    def process_group_alive?(pid)
      Process.kill(0, -pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    # @rbs () -> bool
    def process_groups?
      !RUBY_PLATFORM.match?(/mswin|mingw|cygwin/)
    end

    # @rbs (Integer pid) -> Process::Status
    def process_status(pid)
      waited = Process.waitpid2(pid, Process::WNOHANG)
      return waited.last if waited

      raise Ibex::Error, "(subprocess):1:1: child #{pid} exited without a wait status"
    end

    # @rbs (String stdout_path, String stderr_path) -> bool
    def output_exceeded?(stdout_path, stderr_path)
      File.size(stdout_path) > @max_output_bytes || File.size(stderr_path) > @max_output_bytes
    end

    # @rbs (String path) -> String
    def read_bounded(path)
      File.binread(path, @max_output_bytes)
    end

    # @rbs () -> Float
    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
