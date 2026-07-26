# frozen_string_literal: true

module Ibex
  module IR
    module Validator
      # Structural and referential validation for a versioned Grammar IR JSON object.
      # rubocop:disable Metrics/ClassLength -- inline type contracts accompany one cohesive document validator.
      class GrammarDocument < Base
        ROOT_REQUIRED = %w[
          ibex_ir schema_version class_name superclass start expect options symbols productions user_code
          conversions warnings
        ].freeze #: Array[String]
        ROOT_OPTIONAL = %w[user_code_chunks expect_rr].freeze #: Array[String]
        V2_ROOT_REQUIRED = %w[source_provenance migration].freeze #: Array[String]
        V2_ROOT_OPTIONAL = %w[params printers recovery mode starts].freeze #: Array[String]
        SYMBOL_REQUIRED = %w[id name kind reserved prec loc].freeze #: Array[String]
        SYMBOL_OPTIONAL = %w[display_name semantic_type].freeze #: Array[String]
        V2_SYMBOL_REQUIRED = %w[doc].freeze #: Array[String]
        PRODUCTION_REQUIRED = %w[id lhs rhs action prec_override origin].freeze #: Array[String]
        V2_PRODUCTION_REQUIRED = %w[doc expansion].freeze #: Array[String]
        V2_ACTION_REQUIRED = %w[composition].freeze #: Array[String]
        ORIGIN_KINDS = %w[
          optional_expansion star_expansion plus_expansion separated_list_expansion group_expansion
        ].freeze #: Array[String]
        RUBY_KEYWORDS = %w[
          __ENCODING__ __FILE__ __LINE__ alias and begin break case class def defined do else elsif end ensure false for
          if in module next nil not or redo rescue retry return self super then true undef unless until when while yield
        ].freeze #: Array[String]

        attr_reader :symbols_by_id #: Hash[Integer, Hash[String, untyped]]
        attr_reader :symbols_by_name #: Hash[String, Hash[String, untyped]]
        attr_reader :productions_by_id #: Hash[Integer, Hash[String, untyped]]

        # @rbs @data: Hash[String, untyped]
        # @rbs @path: String
        # @rbs @version: Integer

        # @rbs (Hash[String, untyped] data, ?path: String, ?version: Integer) -> void
        def initialize(data, path: "$", version: data.fetch("schema_version"))
          super()
          @data = data
          @path = path
          @version = version
          @symbols_by_id = {}
          @symbols_by_name = {}
          @productions_by_id = {}
        end

        # @rbs () -> self
        def validate
          required = ROOT_REQUIRED + (@version >= 2 ? V2_ROOT_REQUIRED : [])
          optional = ROOT_OPTIONAL + (@version >= 2 ? V2_ROOT_OPTIONAL : [])
          record(@data, @path, required, optional)
          validate_envelope
          validate_header
          validate_options
          validate_parser_parameters if @data.key?("params")
          validate_symbols
          validate_value_printers if @data.key?("printers")
          validate_reserved_symbols
          validate_start
          validate_recovery if @data.key?("recovery")
          validate_productions
          validate_string_map(@data["user_code"], "#{@path}.user_code")
          validate_string_map(@data["conversions"], "#{@path}.conversions")
          validate_warnings
          validate_user_code_chunks if @data.key?("user_code_chunks")
          if @version >= 2
            validate_source_provenance(@data["source_provenance"], "#{@path}.source_provenance")
            validate_migration
          end
          self
        end

        private

        # @rbs () -> void
        def validate_envelope
          literal(@data["ibex_ir"], "#{@path}.ibex_ir", "grammar")
          literal(@data["schema_version"], "#{@path}.schema_version", @version)
        end

        # @rbs () -> void
        def validate_header
          nonempty_string(@data["class_name"], "#{@path}.class_name")
          nullable_string(@data["superclass"], "#{@path}.superclass")
          nonempty_string(@data["start"], "#{@path}.start")
          enum(@data["mode"], "#{@path}.mode", %w[racc extended]) if @data.key?("mode")
          nonnegative_integer(@data["expect"], "#{@path}.expect")
          nonnegative_integer(@data["expect_rr"], "#{@path}.expect_rr") if @data.key?("expect_rr")
        end

        # @rbs () -> void
        def validate_options
          path = "#{@path}.options"
          options = record(@data["options"], path, %w[result_var omit_action_call])
          boolean(options["result_var"], "#{path}.result_var")
          boolean(options["omit_action_call"], "#{path}.omit_action_call")
        end

        # @rbs () -> void
        def validate_parser_parameters
          names = {} #: Hash[String, bool]
          array(@data["params"], "#{@path}.params").each_with_index do |value, index|
            path = "#{@path}.params[#{index}]"
            parameter = record(value, path, %w[name semantic_type])
            name = nonempty_string(parameter["name"], "#{path}.name")
            invalid("#{path}.name", "must be a Ruby local identifier") unless name.match?(/\A[a-z_][a-zA-Z0-9_]*\z/)
            invalid("#{path}.name", "must not be a Ruby keyword") if RUBY_KEYWORDS.include?(name)
            invalid("#{path}.name", "duplicates parameter #{name.inspect}") if names.key?(name)
            names[name] = true
            metadata(parameter["semantic_type"], "#{path}.semantic_type")
          end
        end

        # @rbs () -> void
        def validate_value_printers
          names = {} #: Hash[String, bool]
          array(@data["printers"], "#{@path}.printers").each_with_index do |value, index|
            path = "#{@path}.printers[#{index}]"
            printer = record(value, path, %w[symbol code loc])
            name = nonempty_string(printer["symbol"], "#{path}.symbol")
            invalid("#{path}.symbol", "references missing symbol #{name.inspect}") unless @symbols_by_name.key?(name)
            invalid("#{path}.symbol", "duplicates printer for #{name.inspect}") if names.key?(name)
            names[name] = true
            string(printer["code"], "#{path}.code")
            location(printer["loc"], "#{path}.loc", nullable: false)
          end
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
          required = SYMBOL_REQUIRED + (@version >= 2 ? V2_SYMBOL_REQUIRED : [])
          symbol = record(value, path, required, SYMBOL_OPTIONAL)
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
          nullable_string(symbol["doc"], "#{path}.doc") if @version >= 2
        end

        # @rbs (untyped value, String path) -> void
        def validate_precedence(value, path)
          return if value.nil?

          precedence = record(value, path, %w[associativity level])
          enum(precedence["associativity"], "#{path}.associativity", %w[left right nonassoc precedence])
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
          return unless @data.key?("starts")

          validate_multiple_starts(start)
        end

        # @rbs (String start) -> void
        def validate_multiple_starts(start)
          starts = array(@data["starts"], "#{@path}.starts")
          invalid("#{@path}.starts", "must not be empty") if starts.empty?
          invalid("#{@path}.starts[0]", "must equal start #{start.inspect}") unless starts.first == start
          invalid("#{@path}.mode", "must be extended for multiple start symbols") unless @data["mode"] == "extended"
          seen = {} #: Hash[String, bool]
          starts.each_with_index do |name, index|
            name = nonempty_string(name, "#{@path}.starts[#{index}]")
            invalid("#{@path}.starts[#{index}]", "duplicates start symbol #{name.inspect}") if seen[name]
            seen[name] = true
            definition = @symbols_by_name[name]
            invalid("#{@path}.starts[#{index}]", "references missing symbol #{name.inspect}") unless definition
            invalid("#{@path}.starts[#{index}]", "must reference a nonterminal") unless
              definition["kind"] == "nonterminal"
          end
        end

        # @rbs () -> void
        def validate_recovery
          path = "#{@path}.recovery"
          recovery = record(@data["recovery"], path, %w[sync_tokens on_error_reduce])
          invalid("#{@path}.mode", "must be extended for recovery declarations") unless @data["mode"] == "extended"
          validate_recovery_symbols(recovery["sync_tokens"], "#{path}.sync_tokens", kind: "terminal")
          groups = array(recovery["on_error_reduce"], "#{path}.on_error_reduce")
          seen = {} #: Hash[String, bool]
          groups.each_with_index do |group, index|
            group_path = "#{path}.on_error_reduce[#{index}]"
            names = array(group, group_path)
            invalid(group_path, "must not be empty") if names.empty?
            names.each_with_index do |name, name_index|
              validate_recovery_symbol(
                name, "#{group_path}[#{name_index}]", kind: "nonterminal", seen: seen
              )
            end
          end
          return unless array(recovery["sync_tokens"], "#{path}.sync_tokens").empty? && groups.empty?

          invalid(path, "must declare at least one recovery policy")
        end

        # @rbs (untyped values, String path, kind: String) -> void
        def validate_recovery_symbols(values, path, kind:)
          seen = {} #: Hash[String, bool]
          array(values, path).each_with_index do |name, index|
            validate_recovery_symbol(name, "#{path}[#{index}]", kind: kind, seen: seen)
          end
        end

        # @rbs (untyped value, String path, kind: String, seen: Hash[String, bool]) -> void
        def validate_recovery_symbol(value, path, kind:, seen:)
          name = nonempty_string(value, path)
          invalid(path, "duplicates symbol #{name.inspect}") if seen[name]
          seen[name] = true
          symbol = @symbols_by_name[name]
          invalid(path, "references missing symbol #{name.inspect}") unless symbol
          invalid(path, "must reference a #{kind}") unless symbol["kind"] == kind
          invalid(path, "must not reference the synthetic error token") if name == "error"
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
          required = PRODUCTION_REQUIRED + (@version >= 2 ? V2_PRODUCTION_REQUIRED : [])
          production = record(value, path, required)
          id = nonnegative_integer(production["id"], "#{path}.id")
          invalid("#{path}.id", "must equal its array index #{index}") unless id == index
          @productions_by_id[id] = production
          validate_lhs(production["lhs"], "#{path}.lhs")
          validate_rhs(production["rhs"], "#{path}.rhs")
          validate_action(production["action"], "#{path}.action", rhs_length: production["rhs"].length)
          validate_precedence_override(production["prec_override"], "#{path}.prec_override")
          validate_origin(production["origin"], "#{path}.origin")
          return unless @version >= 2

          nullable_string(production["doc"], "#{path}.doc")
          validate_expansion(production["expansion"], "#{path}.expansion")
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

          required = %w[code loc named_refs context_length] + (@version >= 2 ? V2_ACTION_REQUIRED : [])
          action = record(value, path, required)
          string(action["code"], "#{path}.code")
          location(action["loc"], "#{path}.loc", nullable: false)
          context_length = nonnegative_integer(action["context_length"], "#{path}.context_length")
          validate_named_refs(action["named_refs"], "#{path}.named_refs", limit: [rhs_length, context_length].max)
          return unless @version >= 2

          validate_action_composition(
            action["composition"], "#{path}.composition", rhs_length: rhs_length
          )
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

        # @rbs (untyped value, String path, ?nullable: bool) -> void
        def validate_source_provenance(value, path, nullable: true)
          return if nullable && value.nil?

          source = record(value, path, %w[file root byte_span])
          nullable_string(source["file"], "#{path}.file")
          nullable_string(source["root"], "#{path}.root")
          validate_byte_span(source["byte_span"], "#{path}.byte_span")
        end

        # @rbs (untyped value, String path) -> void
        def validate_byte_span(value, path)
          return if value.nil?

          span = record(value, path, %w[start end])
          start_byte = nonnegative_integer(span["start"], "#{path}.start")
          end_byte = nonnegative_integer(span["end"], "#{path}.end")
          invalid("#{path}.end", "must be greater than or equal to start") if end_byte < start_byte
        end

        # @rbs () -> void
        def validate_migration
          path = "#{@path}.migration"
          value = @data["migration"]
          return if value.nil?

          migration = record(value, path, %w[from_schema_version unavailable])
          literal(migration["from_schema_version"], "#{path}.from_schema_version", 1)
          values = array(migration["unavailable"], "#{path}.unavailable")
          invalid("#{path}.unavailable", "must not be empty") if values.empty?
          values.each_with_index do |name, index|
            enum(name, "#{path}.unavailable[#{index}]", Migration::UNAVAILABLE_V1_METADATA)
          end
          invalid("#{path}.unavailable", "must contain unique names") unless values.uniq.length == values.length
        end

        # @rbs (untyped value, String path) -> void
        def validate_expansion(value, path)
          return if value.nil?

          expansion = record(value, path, %w[parameter inline include_chain])
          validate_parameter_expansion(expansion["parameter"], "#{path}.parameter")
          validate_inline_expansion(expansion["inline"], "#{path}.inline")
          array(expansion["include_chain"], "#{path}.include_chain").each_with_index do |source, index|
            validate_source_provenance(source, "#{path}.include_chain[#{index}]", nullable: false)
          end
        end

        # @rbs (untyped value, String path) -> void
        def validate_parameter_expansion(value, path)
          return if value.nil?

          parameter = record(value, path, %w[rule arguments])
          nonempty_string(parameter["rule"], "#{path}.rule")
          array(parameter["arguments"], "#{path}.arguments").each_with_index do |argument, index|
            nonempty_string(argument, "#{path}.arguments[#{index}]")
          end
        end

        # @rbs (untyped value, String path) -> void
        def validate_inline_expansion(value, path)
          return if value.nil?

          inline = record(value, path, %w[rule])
          nonempty_string(inline["rule"], "#{path}.rule")
        end

        # @rbs (untyped value, String path, rhs_length: Integer) -> void
        def validate_action_composition(value, path, rhs_length:)
          return if value.nil?

          composition = record(value, path, %w[strategy fragments], %w[plan])
          literal(composition["strategy"], "#{path}.strategy", "sequence")
          fragments = array(composition["fragments"], "#{path}.fragments")
          invalid("#{path}.fragments", "must not be empty") if fragments.empty?
          fragments.each_with_index do |value, index|
            fragment_path = "#{path}.fragments[#{index}]"
            fragment = record(value, fragment_path, %w[kind source])
            enum(fragment["kind"], "#{fragment_path}.kind", %w[rule inline])
            validate_source_provenance(fragment["source"], "#{fragment_path}.source")
          end
          validate_action_composition_plan(composition["plan"], "#{path}.plan", rhs_length, fragments) if
            composition.key?("plan")
        end

        # @rbs (untyped value, String path, Integer rhs_length, Array[untyped] fragments) -> void
        def validate_action_composition_plan(value, path, rhs_length, fragments)
          plan = record(value, path, %w[version physical steps])
          literal(plan["version"], "#{path}.version", 1)
          physical = nonnegative_integer(plan["physical"], "#{path}.physical")
          invalid("#{path}.physical", "must equal production RHS length #{rhs_length}") unless physical == rhs_length
          steps = array(plan["steps"], "#{path}.steps")
          invalid("#{path}.steps", "must not be empty") if steps.empty?
          invalid("#{path}.steps", "must align one-to-one with fragments") unless steps.length == fragments.length
          steps.each_with_index do |step, index|
            validate_action_composition_step(step, "#{path}.steps[#{index}]", physical, index)
            next if step["kind"] == fragments.fetch(index)["kind"]

            invalid("#{path}.steps[#{index}].kind", "must match the corresponding fragment")
          end
        end

        # @rbs (untyped value, String path, Integer physical, Integer step_index) -> void
        def validate_action_composition_step(value, path, physical, step_index)
          step = record(
            value, path,
            %w[kind rule code loc named_refs context_length inputs stack_inputs lookahead result_var],
            %w[result_type]
          )
          kind = enum(step["kind"], "#{path}.kind", %w[rule inline])
          rule = nullable_string(step["rule"], "#{path}.rule")
          invalid("#{path}.rule", "must name an inline rule") if kind == "inline" && (!rule || rule.empty?)
          nullable_string(step["code"], "#{path}.code")
          location(step["loc"], "#{path}.loc", nullable: false)
          context = nonnegative_integer(step["context_length"], "#{path}.context_length")
          inputs = array(step["inputs"], "#{path}.inputs")
          limit = physical + step_index
          validate_action_slots(inputs, "#{path}.inputs", limit)
          stack_inputs = array(step["stack_inputs"], "#{path}.stack_inputs")
          validate_action_slots(stack_inputs, "#{path}.stack_inputs", limit)
          validate_named_refs(step["named_refs"], "#{path}.named_refs", limit: [inputs.length, context].max)
          validate_action_lookahead(step["lookahead"], "#{path}.lookahead", physical)
          boolean(step["result_var"], "#{path}.result_var")
          nullable_string(step["result_type"], "#{path}.result_type")
        end

        # @rbs (Array[untyped] inputs, String path, Integer limit) -> void
        def validate_action_slots(inputs, path, limit)
          inputs.each_with_index do |input, index|
            slot_path = "#{path}[#{index}]"
            slot = nonnegative_integer(input, slot_path)
            invalid(slot_path, "must reference an available slot below #{limit}") if slot >= limit
          end
        end

        # @rbs (untyped value, String path, Integer physical) -> void
        def validate_action_lookahead(value, path, physical)
          return if value.nil?

          boundary = nonnegative_integer(value, path)
          invalid(path, "must reference a physical slot below #{physical}") if boundary >= physical
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
