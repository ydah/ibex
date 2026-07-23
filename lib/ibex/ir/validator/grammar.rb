# frozen_string_literal: true

module Ibex
  module IR
    module Validator
      # Structural and referential validation for a Grammar IR v1 JSON object.
      # rubocop:disable Metrics/ClassLength -- inline type contracts accompany one cohesive document validator.
      class GrammarDocument < Base
        ROOT_REQUIRED = %w[
          ibex_ir schema_version class_name superclass start expect options symbols productions user_code
          conversions warnings
        ].freeze #: Array[String]
        ROOT_OPTIONAL = %w[user_code_chunks].freeze #: Array[String]
        SYMBOL_REQUIRED = %w[id name kind reserved prec loc].freeze #: Array[String]
        SYMBOL_OPTIONAL = %w[display_name semantic_type].freeze #: Array[String]
        PRODUCTION_REQUIRED = %w[id lhs rhs action prec_override origin].freeze #: Array[String]
        ORIGIN_KINDS = %w[
          optional_expansion star_expansion plus_expansion separated_list_expansion group_expansion
        ].freeze #: Array[String]

        attr_reader :symbols_by_id #: Hash[Integer, Hash[String, untyped]]
        attr_reader :symbols_by_name #: Hash[String, Hash[String, untyped]]
        attr_reader :productions_by_id #: Hash[Integer, Hash[String, untyped]]

        # @rbs @data: Hash[String, untyped]
        # @rbs @path: String

        # @rbs (Hash[String, untyped] data, ?path: String) -> void
        def initialize(data, path: "$")
          super()
          @data = data
          @path = path
          @symbols_by_id = {}
          @symbols_by_name = {}
          @productions_by_id = {}
        end

        # @rbs () -> self
        def validate
          record(@data, @path, ROOT_REQUIRED, ROOT_OPTIONAL)
          validate_envelope
          validate_header
          validate_options
          validate_symbols
          validate_reserved_symbols
          validate_start
          validate_productions
          validate_string_map(@data["user_code"], "#{@path}.user_code")
          validate_string_map(@data["conversions"], "#{@path}.conversions")
          validate_warnings
          validate_user_code_chunks if @data.key?("user_code_chunks")
          self
        end

        private

        # @rbs () -> void
        def validate_envelope
          literal(@data["ibex_ir"], "#{@path}.ibex_ir", "grammar")
          literal(@data["schema_version"], "#{@path}.schema_version", SCHEMA_VERSION)
        end

        # @rbs () -> void
        def validate_header
          nonempty_string(@data["class_name"], "#{@path}.class_name")
          nullable_string(@data["superclass"], "#{@path}.superclass")
          nonempty_string(@data["start"], "#{@path}.start")
          nonnegative_integer(@data["expect"], "#{@path}.expect")
        end

        # @rbs () -> void
        def validate_options
          path = "#{@path}.options"
          options = record(@data["options"], path, %w[result_var omit_action_call])
          boolean(options["result_var"], "#{path}.result_var")
          boolean(options["omit_action_call"], "#{path}.omit_action_call")
        end

        # @rbs () -> void
        def validate_symbols
          array(@data["symbols"], "#{@path}.symbols").each_with_index do |value, index|
            validate_symbol(value, index)
          end
        end

        # @rbs (untyped value, Integer index) -> void
        def validate_symbol(value, index)
          path = "#{@path}.symbols[#{index}]"
          symbol = record(value, path, SYMBOL_REQUIRED, SYMBOL_OPTIONAL)
          id = nonnegative_integer(symbol["id"], "#{path}.id")
          invalid("#{path}.id", "must equal its array index #{index}") unless id == index
          name = nonempty_string(symbol["name"], "#{path}.name")
          invalid("#{path}.name", "duplicates symbol #{name.inspect}") if @symbols_by_name.key?(name)
          @symbols_by_id[id] = symbol
          @symbols_by_name[name] = symbol
          enum(symbol["kind"], "#{path}.kind", %w[terminal nonterminal])
          boolean(symbol["reserved"], "#{path}.reserved")
          validate_precedence(symbol["prec"], "#{path}.prec")
          location(symbol["loc"], "#{path}.loc")
          SYMBOL_OPTIONAL.each { |key| metadata(symbol[key], "#{path}.#{key}") if symbol.key?(key) }
        end

        # @rbs (untyped value, String path) -> void
        def validate_precedence(value, path)
          return if value.nil?

          precedence = record(value, path, %w[associativity level])
          enum(precedence["associativity"], "#{path}.associativity", %w[left right nonassoc])
          positive_integer(precedence["level"], "#{path}.level")
        end

        # @rbs () -> void
        def validate_reserved_symbols
          validate_reserved_symbol(0, "$eof")
          validate_reserved_symbol(1, "error")
        end

        # @rbs (Integer id, String name) -> void
        def validate_reserved_symbol(id, name)
          symbol = @symbols_by_id[id]
          invalid("#{@path}.symbols", "must contain reserved symbol #{name.inspect} at id #{id}") unless symbol
          invalid("#{@path}.symbols[#{id}]", "must be reserved terminal #{name.inspect}") unless
            symbol["name"] == name && symbol["kind"] == "terminal" && symbol["reserved"]
        end

        # @rbs () -> void
        def validate_start
          start = @data["start"]
          symbol = @symbols_by_name[start]
          invalid("#{@path}.start", "references missing symbol #{start.inspect}") unless symbol
          invalid("#{@path}.start", "must reference a nonterminal") unless symbol["kind"] == "nonterminal"
        end

        # @rbs () -> void
        def validate_productions
          array(@data["productions"], "#{@path}.productions").each_with_index do |value, index|
            validate_production(value, index)
          end
        end

        # @rbs (untyped value, Integer index) -> void
        def validate_production(value, index)
          path = "#{@path}.productions[#{index}]"
          production = record(value, path, PRODUCTION_REQUIRED)
          id = nonnegative_integer(production["id"], "#{path}.id")
          invalid("#{path}.id", "must equal its array index #{index}") unless id == index
          @productions_by_id[id] = production
          validate_lhs(production["lhs"], "#{path}.lhs")
          validate_rhs(production["rhs"], "#{path}.rhs")
          validate_action(production["action"], "#{path}.action", rhs_length: production["rhs"].length)
          validate_precedence_override(production["prec_override"], "#{path}.prec_override")
          validate_origin(production["origin"], "#{path}.origin")
        end

        # @rbs (untyped value, String path) -> void
        def validate_lhs(value, path)
          id = nonnegative_integer(value, path)
          symbol = @symbols_by_id[id]
          invalid(path, "references missing symbol id #{id}") unless symbol
          invalid(path, "must reference a nonterminal") unless symbol["kind"] == "nonterminal"
        end

        # @rbs (untyped value, String path) -> void
        def validate_rhs(value, path)
          array(value, path).each_with_index do |id, index|
            id = nonnegative_integer(id, "#{path}[#{index}]")
            invalid("#{path}[#{index}]", "references missing symbol id #{id}") unless @symbols_by_id.key?(id)
          end
        end

        # @rbs (untyped value, String path, rhs_length: Integer) -> void
        def validate_action(value, path, rhs_length:)
          return if value.nil?

          action = record(value, path, %w[code loc named_refs context_length])
          string(action["code"], "#{path}.code")
          location(action["loc"], "#{path}.loc", nullable: false)
          context_length = nonnegative_integer(action["context_length"], "#{path}.context_length")
          validate_named_refs(action["named_refs"], "#{path}.named_refs", limit: [rhs_length, context_length].max)
        end

        # @rbs (untyped value, String path, limit: Integer) -> void
        def validate_named_refs(value, path, limit:)
          names = {} #: Hash[String, bool]
          array(value, path).each_with_index do |entry, index|
            entry_path = "#{path}[#{index}]"
            reference = record(entry, entry_path, %w[name index])
            name = nonempty_string(reference["name"], "#{entry_path}.name")
            invalid("#{entry_path}.name", "duplicates named reference #{name.inspect}") if names.key?(name)
            names[name] = true
            reference_index = nonnegative_integer(reference["index"], "#{entry_path}.index")
            if reference_index >= limit
              invalid("#{entry_path}.index", "must be less than the action context length #{limit}")
            end
          end
        end

        # @rbs (untyped value, String path) -> void
        def validate_precedence_override(value, path)
          return if value.nil?

          id = nonnegative_integer(value, path)
          symbol = @symbols_by_id[id]
          invalid(path, "references missing symbol id #{id}") unless symbol
          invalid(path, "must reference a terminal") unless symbol["kind"] == "terminal"
        end

        # @rbs (untyped value, String path) -> void
        def validate_origin(value, path)
          origin = object(value, path)
          kind = string(field(origin, "kind", path), "#{path}.kind")
          optional = ORIGIN_KINDS.include?(kind) ? %w[expression] : [] # @type var optional: Array[String]
          record(origin, path, %w[kind loc], optional)
          enum(kind, "#{path}.kind", %w[user inline_action] + ORIGIN_KINDS)
          string(origin["expression"], "#{path}.expression") if origin.key?("expression")
          location(origin["loc"], "#{path}.loc", nullable: false)
        end

        # @rbs (untyped value, String path) -> void
        def validate_string_map(value, path)
          object(value, path).each do |key, item|
            string(key, path)
            string(item, child_path(path, key))
          end
        end

        # @rbs () -> void
        def validate_warnings
          array(@data["warnings"], "#{@path}.warnings").each_with_index do |value, index|
            validate_warning(value, "#{@path}.warnings[#{index}]")
          end
        end

        # @rbs (untyped value, String path) -> void
        def validate_warning(value, path)
          warning = record(value, path, %w[type loc], %w[symbol production original])
          nonempty_string(warning["type"], "#{path}.type")
          location(warning["loc"], "#{path}.loc")
          validate_warning_symbol(warning, path) if warning.key?("symbol")
          validate_warning_production(warning, "production", path) if warning.key?("production")
          validate_warning_production(warning, "original", path) if warning.key?("original")
        end

        # @rbs (Hash[String, untyped] warning, String path) -> void
        def validate_warning_symbol(warning, path)
          name = nonempty_string(warning["symbol"], "#{path}.symbol")
          invalid("#{path}.symbol", "references missing symbol #{name.inspect}") unless @symbols_by_name.key?(name)
        end

        # @rbs (Hash[String, untyped] warning, String field_name, String path) -> void
        def validate_warning_production(warning, field_name, path)
          id = nonnegative_integer(warning[field_name], "#{path}.#{field_name}")
          invalid("#{path}.#{field_name}", "references missing production id #{id}") unless @productions_by_id.key?(id)
        end

        # @rbs () -> void
        def validate_user_code_chunks
          path = "#{@path}.user_code_chunks"
          object(@data["user_code_chunks"], path).each do |key, chunks|
            string(key, path)
            array(chunks, child_path(path, key)).each_with_index do |chunk, index|
              chunk_path = "#{child_path(path, key)}[#{index}]"
              chunk = record(chunk, chunk_path, %w[code loc])
              string(chunk["code"], "#{chunk_path}.code")
              location(chunk["loc"], "#{chunk_path}.loc", nullable: false)
            end
          end
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
