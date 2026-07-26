# frozen_string_literal: true

module Ibex
  module IR
    module Validator
      # Structural validation for the independently versioned Lexer IR.
      class LexerDocument < Base
        ROOT_REQUIRED = %w[
          ibex_ir schema_version initial_state states rules warnings source_provenance
        ].freeze #: Array[String]
        RULE_REQUIRED = %w[
          id state kind token pattern pattern_kind options action loc
        ].freeze #: Array[String]

        # @rbs (Hash[String, untyped] data, ?path: String) -> void
        def initialize(data, path: "$")
          super()
          @data = data
          @path = path
        end

        # @rbs () -> self
        def validate
          record(@data, @path, ROOT_REQUIRED)
          literal(@data["ibex_ir"], "#{@path}.ibex_ir", "lexer")
          literal(@data["schema_version"], "#{@path}.schema_version", LEXER_SCHEMA_VERSION)
          literal(@data["initial_state"], "#{@path}.initial_state", "INITIAL")
          validate_states
          validate_rules
          validate_warnings
          validate_source_provenance
          self
        end

        private

        # @rbs () -> void
        def validate_states
          seen = {} #: Hash[String, bool]
          values = array(@data["states"], "#{@path}.states")
          invalid("#{@path}.states", "must start with INITIAL") unless values.first == "INITIAL"
          values.each_with_index do |value, index|
            name = nonempty_string(value, "#{@path}.states[#{index}]")
            invalid("#{@path}.states[#{index}]", "duplicates state #{name.inspect}") if seen[name]
            seen[name] = true
          end
          @states = seen
        end

        # @rbs () -> void
        def validate_rules # rubocop:disable Metrics/AbcSize
          array(@data["rules"], "#{@path}.rules").each_with_index do |value, index|
            path = "#{@path}.rules[#{index}]"
            rule = record(value, path, RULE_REQUIRED)
            literal(rule["id"], "#{path}.id", index)
            state = nonempty_string(rule["state"], "#{path}.state")
            invalid("#{path}.state", "references missing state #{state.inspect}") unless @states[state]
            kind = enum(rule["kind"], "#{path}.kind", %w[token skip on])
            nullable_string(rule["token"], "#{path}.token")
            invalid("#{path}.token", "is required for token rules") if kind == "token" && rule["token"].nil?
            invalid("#{path}.token", "must be null for #{kind} rules") if kind != "token" && rule["token"]
            nonempty_string(rule["pattern"], "#{path}.pattern")
            enum(rule["pattern_kind"], "#{path}.pattern_kind", %w[regexp literal])
            options = string(rule["options"], "#{path}.options")
            invalid("#{path}.options", "may contain only i, m, and x") unless options.match?(/\A[imx]*\z/)
            validate_pattern(rule, path, options)
            nullable_string(rule["action"], "#{path}.action")
            invalid("#{path}.action", "is required for on rules") if kind == "on" && rule["action"].nil?
            location(rule["loc"], "#{path}.loc", nullable: false)
          end
        end

        # @rbs (Hash[String, untyped] rule, String path, String options) -> void
        def validate_pattern(rule, path, options)
          flags = 0
          flags |= Regexp::IGNORECASE if options.include?("i")
          flags |= Regexp::MULTILINE if options.include?("m")
          flags |= Regexp::EXTENDED if options.include?("x")
          regexp = Regexp.new("\\A(?:#{rule.fetch('pattern')})", flags)
          invalid("#{path}.pattern", "must not match an empty string") if regexp.match?("")
        rescue RegexpError => e
          invalid("#{path}.pattern", "is not a valid regular expression: #{e.message}")
        end

        # @rbs () -> void
        def validate_warnings
          array(@data["warnings"], "#{@path}.warnings").each_with_index do |value, index|
            path = "#{@path}.warnings[#{index}]"
            warning = record(value, path, %w[type rule loc])
            literal(warning["type"], "#{path}.type", "redos")
            nonnegative_integer(warning["rule"], "#{path}.rule")
            location(warning["loc"], "#{path}.loc", nullable: false)
          end
        end

        # @rbs () -> void
        def validate_source_provenance
          value = @data["source_provenance"]
          return if value.nil?

          record(value, "#{@path}.source_provenance", %w[file root byte_span])
          nullable_string(value["file"], "#{@path}.source_provenance.file")
          nullable_string(value["root"], "#{@path}.source_provenance.root")
          return if value["byte_span"].nil?

          span = record(value["byte_span"], "#{@path}.source_provenance.byte_span", %w[start end])
          nonnegative_integer(span["start"], "#{@path}.source_provenance.byte_span.start")
          nonnegative_integer(span["end"], "#{@path}.source_provenance.byte_span.end")
        end
      end
    end
  end
end
