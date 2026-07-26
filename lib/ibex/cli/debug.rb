# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  # Safe parser-table simulation subcommand.
  module CLIDebug
    # @rbs!
    #   type debug_options = {
    #     paths: Array[String],
    #     format: String,
    #     max_steps: Integer,
    #     max_stack: Integer
    #   }

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_debug_command(arguments)
      settings = debug_options(arguments)
      operands = settings.fetch(:paths)
      raise Ibex::Error, "(cli):1:1: debug requires an Automaton IR file" if operands.empty?

      path = operands.first
      value = IR::Validator.validate(File.read(path))
      raise Ibex::Error, "#{path}:1:1: debug requires Automaton IR" unless value.is_a?(IR::Automaton)

      simulator = TableSimulation::Simulator.new(
        value,
        max_steps: settings.fetch(:max_steps),
        max_stack: settings.fetch(:max_stack)
      )
      tokens = operands.drop(1)
      interactive = tokens.empty?
      format = settings.fetch(:format)
      result = interactive ? simulate_debug_input(simulator, format) : simulator.simulate(tokens)
      write_debug_result(result, format, steps_written: interactive && format == "text")
      result.status == :accepted ? 0 : 1
    rescue ArgumentError => e
      raise Ibex::Error, "(debug):1:1: #{e.message}"
    end

    # @rbs (Array[String] arguments) -> debug_options
    def debug_options(arguments)
      settings = {
        paths: [],
        format: "text",
        max_steps: TableSimulation::Simulator::DEFAULT_MAX_STEPS,
        max_stack: TableSimulation::Simulator::DEFAULT_MAX_STACK
      } #: debug_options
      parser = OptionParser.new do |options|
        options.banner = "Usage: ibex debug AUTOMATON.json [TOKEN...]"
        options.on("--format=FORMAT", %w[text json], "text or json") { |value| settings[:format] = value }
        options.on("--max-steps=N", Integer, "maximum simulated actions") do |value|
          settings[:max_steps] = positive_debug_budget(value, "max-steps")
        end
        options.on("--max-stack=N", Integer, "maximum simulated state stack depth") do |value|
          settings[:max_stack] = positive_debug_budget(value, "max-stack")
        end
      end
      settings[:paths] = parser.parse(arguments)
      settings
    end

    # @rbs (Integer value, String name) -> Integer
    def positive_debug_budget(value, name)
      return value if value.positive?

      raise OptionParser::InvalidArgument, "--#{name} must be positive"
    end

    # @rbs (TableSimulation::Simulator simulator, String format) -> TableSimulation::Result
    def simulate_debug_input(simulator, format)
      session = simulator.start
      while (line = @stdin.gets)
        spelling = line.strip
        break if spelling.empty?

        steps = session.push(spelling)
        write_debug_steps(steps) if format == "text"
        break if session.status
      end
      written = session.steps.length
      result = session.finish
      write_debug_steps(result.steps.drop(written)) if format == "text"
      result
    end

    # @rbs (TableSimulation::Result result, String format, steps_written: bool) -> void
    def write_debug_result(result, format, steps_written:)
      if format == "json"
        @stdout.write(result.to_json)
      else
        write_debug_steps(result.steps) unless steps_written
        @stdout.puts("status=#{result.status}")
      end
    end

    # @rbs (Array[TableSimulation::Step] steps) -> void
    def write_debug_steps(steps)
      steps.each { |step| @stdout.puts(TableSimulation::Text.render_step(step)) }
    end
  end
end
