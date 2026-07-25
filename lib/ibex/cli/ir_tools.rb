# frozen_string_literal: true

require "tempfile"

module Ibex
  # @rbs!
  #   type migrate_ir_options = {
  #     paths: Array[String],
  #     ?to: Integer,
  #     ?output: String
  #   }

  # CLI validation and structural comparison for versioned IR documents.
  module CLIIRTools
    # @rbs!
    #   private def same_file_target?: (String left, String right) -> bool

    private

    # @rbs (Array[String] arguments) -> Integer
    def run_validate_ir_command(arguments)
      path = single_ir_path(arguments, "validate-ir")
      value = IR::Validator.validate(File.read(path))
      kind = value.is_a?(IR::Grammar) ? "grammar" : "automaton"
      @stdout.puts("valid #{kind} IR v#{value.schema_version}")
      0
    end

    # @rbs (Array[String] arguments) -> Integer
    def run_compare_command(arguments)
      raise Ibex::Error, "(cli):1:1: compare requires exactly two IR files" unless arguments.length == 2

      before = IR::Validator.validate(File.read(arguments.fetch(0)))
      after = IR::Validator.validate(File.read(arguments.fetch(1)))
      compatible = (before.is_a?(IR::Grammar) && after.is_a?(IR::Grammar)) ||
                   (before.is_a?(IR::Automaton) && after.is_a?(IR::Automaton))
      raise Ibex::Error, "(cli):1:1: cannot compare grammar IR with automaton IR" unless compatible

      @stdout.puts(JSON.pretty_generate(compare_ir(before, after)))
      0
    end

    # @rbs (Array[String] arguments) -> Integer
    def run_migrate_ir_command(arguments)
      settings = migrate_ir_options(arguments)
      input = single_ir_path(settings.fetch(:paths), "migrate-ir")
      output = settings[:output]
      if output && same_file_target?(input, output)
        raise Ibex::Error, "(cli):1:1: migrate-ir input and output paths must be distinct"
      end

      value = IR::Validator.validate(File.read(input))
      target = settings[:to] || raise(Ibex::Error, "(cli):1:1: migrate-ir requires --to=VERSION")
      unless IR::SUPPORTED_SCHEMA_VERSIONS.include?(target)
        raise Ibex::Error, "(cli):1:1: unsupported migration target schema_version #{target}"
      end
      if target < value.schema_version
        raise Ibex::Error,
              "(cli):1:1: downgrading schema_version #{value.schema_version} to #{target} is not supported"
      end

      source = IR::Serialize.dump(IR::Migration.to_version(value, to: target))
      output ? atomic_write_ir(output, source) : @stdout.write(source)
      0
    end

    # @rbs (Array[String] arguments) -> migrate_ir_options
    def migrate_ir_options(arguments)
      settings = { paths: [] } #: migrate_ir_options
      parser = OptionParser.new do |options|
        options.banner = "Usage: ibex migrate-ir INPUT --to=VERSION [-o FILE]"
        options.on("--to=VERSION", Integer, "target schema version") { |value| settings[:to] = value }
        options.on("-o FILE", "--output=FILE", "write atomically to FILE") { |value| settings[:output] = value }
      end
      settings[:paths] = parser.parse(arguments)
      settings
    end

    # @rbs (String path, String source) -> void
    def atomic_write_ir(path, source)
      target_path = File.symlink?(path) ? File.realpath(path) : path
      directory = File.dirname(File.expand_path(target_path))
      basename = File.basename(target_path)
      Tempfile.create([".#{basename}.", ".tmp"], directory) do |temporary|
        temporary.binmode
        temporary.write(source)
        temporary.flush
        temporary.fsync
        temporary.chmod(ir_file_mode(target_path))
        temporary.close
        File.rename(temporary.path, target_path)
      end
    end

    # @rbs (String path) -> Integer
    def ir_file_mode(path)
      return File.stat(path).mode & 0o777 if File.exist?(path)

      0o666 & ~File.umask
    end

    # @rbs (Array[String] arguments, String command) -> String
    def single_ir_path(arguments, command)
      return arguments.first if arguments.length == 1

      raise Ibex::Error, "(cli):1:1: #{command} requires exactly one IR file"
    end

    # @rbs (IR::Grammar | IR::Automaton before, IR::Grammar | IR::Automaton after) -> Hash[Symbol, untyped]
    def compare_ir(before, after)
      return compare_grammars(before, after) if before.is_a?(IR::Grammar) && after.is_a?(IR::Grammar)
      if before.is_a?(IR::Automaton) && after.is_a?(IR::Automaton)
        return {
          kind: "automaton",
          algorithm: { before: before.algorithm, after: after.algorithm },
          states: numeric_change(before.states.length, after.states.length),
          transitions: numeric_change(transition_count(before), transition_count(after)),
          conflicts: %i[sr resolved_sr rr].to_h do |kind|
            [kind, numeric_change(summary_count(before, kind), summary_count(after, kind))]
          end,
          grammar: compare_grammars(before.grammar, after.grammar)
        }
      end

      raise Ibex::Error, "(cli):1:1: unsupported IR comparison"
    end

    # @rbs (IR::Grammar before, IR::Grammar after) -> Hash[Symbol, untyped]
    def compare_grammars(before, after)
      before_symbols = before.symbols.map(&:name)
      after_symbols = after.symbols.map(&:name)
      before_productions = production_shapes(before)
      after_productions = production_shapes(after)
      {
        kind: "grammar",
        symbols: { added: (after_symbols - before_symbols).sort, removed: (before_symbols - after_symbols).sort },
        productions: {
          added: (after_productions - before_productions).sort,
          removed: (before_productions - after_productions).sort,
          count: numeric_change(before.productions.length, after.productions.length)
        },
        warnings: numeric_change(before.warnings.length, after.warnings.length)
      }
    end

    # @rbs (IR::Grammar grammar) -> Array[String]
    def production_shapes(grammar)
      grammar.productions.map do |production|
        lhs = grammar.symbol_by_id(production.lhs)&.name || production.lhs.to_s
        rhs = production.rhs.map { |id| grammar.symbol_by_id(id)&.name || id.to_s }
        "#{lhs} -> #{rhs.join(' ')}"
      end
    end

    # @rbs (IR::Automaton automaton) -> Integer
    def transition_count(automaton)
      automaton.states.sum { |state| state.transitions.length }
    end

    # @rbs (IR::Automaton automaton, Symbol kind) -> Integer
    def summary_count(automaton, kind)
      value = automaton.conflict_summary.fetch(kind)
      return value if value.is_a?(Integer)

      raise Ibex::Error, "(ir):1:1: conflict count #{kind} must be an integer"
    end

    # @rbs (Integer before, Integer after) -> Hash[Symbol, Integer]
    def numeric_change(before, after)
      { before: before, after: after, delta: after - before }
    end
  end
end
