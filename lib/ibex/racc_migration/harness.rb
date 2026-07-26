# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module RaccMigration
    # Emits, but never executes, a subprocess-separated differential harness.
    class Harness
      CLASS_NAME = /\A[A-Z]\w*(?:::[A-Z]\w*)*\z/ #: Regexp

      # @rbs (String class_name) -> String
      def self.generate(class_name)
        raise ArgumentError, "invalid parser class name #{class_name.inspect}" unless class_name.match?(CLASS_NAME)

        template.sub("__PARSER_CLASS_NAME__", class_name.dump)
      end

      # @rbs () -> String
      def self.template
        <<~'RUBY'
          #!/usr/bin/env ruby
          # frozen_string_literal: true

          # Generated migration differential harness.
          # Running this file executes both generated parsers and all grammar
          # user code in child Ruby processes. Review the grammar and CASES,
          # then run this only in an isolation boundary you trust.

          require "rbconfig"
          require "tempfile"
          require "tmpdir"

          PARSER_CLASS = __PARSER_CLASS_NAME__
          TIMEOUT_SECONDS = 15
          MAX_OUTPUT_BYTES = 1_048_576
          CASES = [
            # { name: "example", tokens: [[:TOKEN, "value"], ["+", nil]] }
          ].freeze

          CHILD_RUNNER = <<~'CHILD'
            begin
              load ARGV.fetch(0)
              parser_class = ARGV.fetch(1).split("::").inject(Object) { |scope, name| scope.const_get(name, false) }
              tokens = Marshal.load(ARGV.fetch(2).unpack1("m0"))
              parser = parser_class.new
              parser.define_singleton_method(:next_token) { tokens.shift }
              result = parser.do_parse
              puts "IBEX_HARNESS_RESULT=#{[Marshal.dump([:ok, result])].pack("m0")}"
            rescue StandardError => error
              payload = [:error, error.class.name, error.message]
              puts "IBEX_HARNESS_RESULT=#{[Marshal.dump(payload)].pack("m0")}"
            end
          CHILD

          def terminate(pid)
            Process.kill("TERM", pid)
          rescue Errno::ESRCH
            nil
          ensure
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.5
            while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
              waited = Process.waitpid2(pid, Process::WNOHANG)
              return waited.last if waited

              sleep 0.01
            end
            Process.kill("KILL", pid)
            Process.waitpid2(pid).last
          end

          def run_command(*command)
            Tempfile.create("migration-stdout") do |stdout|
              Tempfile.create("migration-stderr") do |stderr|
                pid = Process.spawn(*command, out: stdout, err: stderr)
                deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT_SECONDS
                status = nil
                until status
                  waited = Process.waitpid2(pid, Process::WNOHANG)
                  status = waited.last if waited
                  break if status
                  if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
                    status = terminate(pid)
                    stdout.rewind
                    stderr.rewind
                    return [
                      stdout.read(MAX_OUTPUT_BYTES) || "", stderr.read(MAX_OUTPUT_BYTES) || "", status, true, false
                    ]
                  end
                  if stdout.size > MAX_OUTPUT_BYTES || stderr.size > MAX_OUTPUT_BYTES
                    status = terminate(pid)
                    stdout.rewind
                    stderr.rewind
                    return [
                      stdout.read(MAX_OUTPUT_BYTES) || "", stderr.read(MAX_OUTPUT_BYTES) || "", status, false, true
                    ]
                  end
                  sleep 0.01
                end
                stdout.rewind
                stderr.rewind
                [
                  stdout.read(MAX_OUTPUT_BYTES) || "", stderr.read(MAX_OUTPUT_BYTES) || "", status, false, false
                ]
              end
            end
          end

          def compile!(label, *command)
            stdout, stderr, status, timed_out, output_limited = run_command(*command)
            abort "#{label} generation timed out" if timed_out
            abort "#{label} generation exceeded #{MAX_OUTPUT_BYTES} output bytes" if output_limited
            return if status.success?

            abort "#{label} generation failed\n#{stdout}#{stderr}"
          end

          def observe(parser_path, tokens)
            payload = [Marshal.dump(tokens)].pack("m0")
            stdout, stderr, status, timed_out, output_limited = run_command(
              RbConfig.ruby, "-e", CHILD_RUNNER, parser_path, PARSER_CLASS, payload
            )
            return { timeout: true } if timed_out
            return { output_limit: MAX_OUTPUT_BYTES } if output_limited

            lines = stdout.lines
            marker = lines.reverse.find { |line| line.start_with?("IBEX_HARNESS_RESULT=") }
            unless status.success? && marker
              return {
                infrastructure_error: File.basename(parser_path),
                status: status.exitstatus,
                stdout: stdout,
                stderr: stderr
              }
            end
            outcome = marker && Marshal.load(marker.split("=", 2).last.strip.unpack1("m0"))
            {
              status: status.exitstatus,
              outcome: outcome,
              stdout: lines.reject { |line| line.equal?(marker) }.join,
              stderr: stderr
            }
          end

          abort "add at least one reviewed entry to CASES before running the harness" if CASES.empty?
          grammar = File.expand_path(ARGV.fetch(0))
          abort "grammar file does not exist: #{grammar}" unless File.file?(grammar)
          racc = ENV.fetch("RACC", "racc")
          ibex = ENV.fetch("IBEX", "ibex")

          failures = 0
          Dir.mktmpdir("ibex-migration-harness-") do |directory|
            racc_parser = File.join(directory, "racc_parser.rb")
            ibex_parser = File.join(directory, "ibex_parser.rb")
            compile!("racc", racc, "-o", racc_parser, grammar)
            compile!("ibex", ibex, "-E", "-o", ibex_parser, grammar)

            CASES.each do |test_case|
              name = test_case.fetch(:name)
              tokens = test_case.fetch(:tokens)
              expected = observe(racc_parser, tokens)
              actual = observe(ibex_parser, tokens)
              if expected == actual
                puts "ok #{name}"
              else
                failures += 1
                warn "difference #{name}"
                warn "  racc: #{expected.inspect}"
                warn "  ibex: #{actual.inspect}"
              end
            end
          end
          exit(failures.zero? ? 0 : 1)
        RUBY
      end
      private_class_method :template
    end
  end
end
