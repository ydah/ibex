# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require_relative "error"
require_relative "location"

module Ibex
  # Typed, provenance-preserving effective configuration.
  module Configuration
    autoload :AnalysisGrammar, File.join(__dir__, "configuration/analysis_grammar")

    # @rbs!
    #   type config_value = Symbol | String | Integer | bool | nil
    #   type json_value = String | Integer | bool | nil | Array[json_value] | Hash[String, json_value]

    OWNER_NAMES = {
      grammar_contract: "grammar-contract",
      grammar_minimum: "grammar-minimum",
      project_build: "project-build",
      invocation: "invocation"
    }.freeze #: Hash[Symbol, String]
    ORIGIN_KINDS = %i[builtin grammar project cli analysis_override].freeze #: Array[Symbol]
    BOOLEAN_VALUES = [true, false].freeze #: Array[bool]
    DECLARED_VALUE_UNSET = Object.new.freeze #: Object
    OWNER_POLICIES = {
      grammar_contract: :fixed, grammar_minimum: :minimum,
      project_build: :build, invocation: :invocation
    }.freeze #: Hash[Symbol, Symbol]

    # One closed definition of a configuration concept and its value domain.
    class Key
      attr_reader :name #: String
      attr_reader :type #: Symbol
      attr_reader :default #: config_value
      attr_reader :owner #: Symbol
      attr_reader :allowed_values #: Array[config_value]?
      attr_reader :cli_option #: Symbol?
      attr_reader :parser_setting #: Symbol?
      attr_reader :cli_aliases #: Array[String]

      # @rbs (String name, type: Symbol, default: config_value, owner: Symbol,
      #   ?allowed_values: Array[config_value]?, ?cli_option: Symbol?, ?parser_setting: Symbol?,
      #   ?cli_aliases: Array[String]) -> void
      def initialize(name, type:, default:, owner:, allowed_values: nil, cli_option: nil, parser_setting: nil,
                     cli_aliases: [])
        validate_identity!(name, owner)

        @name = name.dup.freeze
        @type = type
        @owner = owner
        validate_shape!(type, cli_option)
        @allowed_values = allowed_values&.map { |value| immutable(value) }&.freeze
        @cli_option = cli_option
        @parser_setting = parser_setting&.to_sym
        @cli_aliases = cli_aliases.map(&:to_s).freeze
        @default = validate(default)
        freeze
      end

      # Validate and defensively freeze a value from an adapter or declaration.
      # @rbs (config_value value) -> config_value
      def validate(value)
        raise ArgumentError, "#{@name} expects #{@type}, got #{value.inspect}" unless valid_type?(value)

        allowed_values = @allowed_values
        if allowed_values && !allowed_values.include?(value)
          raise ArgumentError, "#{@name} must be one of #{allowed_values.map(&:inspect).join(', ')}"
        end

        immutable(value)
      end

      # @rbs () -> String
      def owner_name
        OWNER_NAMES.fetch(@owner)
      end

      # @rbs () -> Symbol
      def policy
        OWNER_POLICIES.fetch(@owner)
      end

      private

      # @rbs (String name, Symbol owner) -> void
      def validate_identity!(name, owner)
        valid_name = name.is_a?(String) && name.match?(/\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/)
        raise ArgumentError, "invalid canonical configuration key: #{name.inspect}" unless valid_name
        raise ArgumentError, "unknown configuration owner: #{owner.inspect}" unless OWNER_NAMES.key?(owner)
      end

      # @rbs (Symbol type, Symbol? cli_option) -> void
      def validate_shape!(type, cli_option)
        raise ArgumentError, "cli_option must be a Symbol or nil" unless cli_option.nil? || cli_option.is_a?(Symbol)
        return unless policy == :minimum && type != :integer

        raise ArgumentError, "minimum configuration keys must have Integer values"
      end

      # @rbs (config_value value) -> config_value
      def immutable(value)
        value.is_a?(String) ? value.dup.freeze : value
      end

      # @rbs (config_value value) -> bool
      def valid_type?(value)
        case @type
        when :symbol then value.is_a?(Symbol)
        when :boolean then BOOLEAN_VALUES.include?(value)
        when :integer then value.is_a?(Integer)
        when :optional_boolean then value.nil? || BOOLEAN_VALUES.include?(value)
        when :optional_string then value.nil? || value.is_a?(String)
        else raise ArgumentError, "unknown configuration value type: #{@type.inspect}"
        end
      end
    end

    # Where a selected configuration value came from.
    class Origin
      attr_reader :kind #: Symbol
      attr_reader :location #: Location?

      # @rbs (Symbol kind, ?location: Location?) -> void
      def initialize(kind, location: nil)
        raise ArgumentError, "unknown configuration origin: #{kind.inspect}" unless ORIGIN_KINDS.include?(kind)
        unless location.nil? || location.is_a?(Location)
          raise ArgumentError, "configuration location must be an Ibex::Location"
        end
        if location && !%i[grammar project].include?(kind)
          raise ArgumentError, "#{kind} configuration cannot have a source location"
        end

        @kind = kind
        @location = location
        freeze
      end

      # @rbs () -> Hash[String, json_value]
      def to_h
        result = { "kind" => @kind.to_s } #: Hash[String, json_value]
        location = @location
        result["location"] = stringify_location(location) if location
        result
      end

      # @rbs () -> String
      def label
        location = @location
        return @kind.to_s unless location

        file = location.file || "(source)"
        "#{@kind} #{file}:#{location.line}:#{location.column}"
      end

      private

      # @rbs (Location location) -> Hash[String, json_value]
      def stringify_location(location)
        location.to_h.transform_keys(&:to_s)
      end
    end

    # A typed effective value plus the evidence needed to explain it.
    class Value
      attr_reader :key #: Key
      attr_reader :value #: config_value
      attr_reader :origin #: Origin
      attr_reader :declared_value #: config_value

      # @rbs (Key key, config_value value, origin: Origin,
      #   ?declared_value: config_value | Object) -> void
      def initialize(key, value, origin:, declared_value: DECLARED_VALUE_UNSET)
        raise ArgumentError, "configuration value key must be a Configuration::Key" unless key.is_a?(Key)
        raise ArgumentError, "configuration value origin must be a Configuration::Origin" unless origin.is_a?(Origin)

        validate_provenance!(key, origin, declared_value)

        @key = key
        @value = key.validate(value)
        @origin = origin
        declared = declared_value #: config_value
        @declared_value = declared.equal?(DECLARED_VALUE_UNSET) ? nil : key.validate(declared)

        freeze
      end

      # @rbs () -> Hash[String, json_value]
      def to_h
        result = {
          "key" => @key.name,
          "value" => json_value(@value),
          "owner" => @key.owner_name,
          "policy" => @key.policy.to_s,
          "origin" => @origin.to_h,
          "explicit" => explicit,
          "canonical" => canonical
        } #: Hash[String, json_value]
        unless canonical
          result["analysis"] = {
            "declared" => json_value(@declared_value),
            "selected" => json_value(@value),
            "override" => true,
            "canonical_generation" => false
          }
        end
        result
      end

      # @rbs () -> bool
      # rubocop:disable Naming/PredicateMethod -- public JSON fields are named explicit/canonical.
      def explicit
        @origin.kind != :builtin
      end

      # @rbs () -> bool
      def canonical
        @origin.kind != :analysis_override
      end
      # rubocop:enable Naming/PredicateMethod

      private

      # @rbs (Key key, Origin origin, config_value | Object declared_value) -> void
      def validate_provenance!(key, origin, declared_value)
        validate_canonical_origin!(key, origin)
        validate_owner_source!(key, origin)
        validate_declared_evidence!(origin, declared_value)
      end

      # @rbs (Key key, Origin origin) -> void
      def validate_canonical_origin!(key, origin)
        return unless origin.kind == :analysis_override && key.policy != :fixed

        raise ArgumentError, "noncanonical selections are only valid for fixed configuration"
      end

      # @rbs (Key key, Origin origin) -> void
      def validate_owner_source!(key, origin)
        if origin.kind == :grammar && !%i[fixed minimum].include?(key.policy)
          raise ArgumentError, "#{key.name} is #{key.policy} configuration and cannot be grammar-owned"
        end
        return unless origin.kind == :project && key.policy == :invocation

        raise ArgumentError, "#{key.name} is invocation configuration and cannot be project-owned"
      end

      # @rbs (Origin origin, config_value | Object declared_value) -> void
      def validate_declared_evidence!(origin, declared_value)
        canonical = origin.kind != :analysis_override
        declared = !declared_value.equal?(DECLARED_VALUE_UNSET)
        raise ArgumentError, "canonical selections cannot carry declared evidence" if canonical && declared
        return if canonical || declared

        raise ArgumentError, "noncanonical selections require declared evidence"
      end

      # @rbs (config_value value) -> (String | Integer | bool | nil)
      def json_value(value)
        value.is_a?(Symbol) ? value.to_s : value
      end
    end

    # A fixed/minimum request that contradicts the declared contract.
    class Conflict < Ibex::Error
      attr_reader :key #: Key
      attr_reader :declared #: Value
      attr_reader :requested #: Value

      # @rbs (Key key, Value declared, Value requested) -> void
      def initialize(key, declared, requested)
        @key = key
        @declared = declared
        @requested = requested
        super(
          "configuration conflict for #{key.name}: " \
          "#{declared.origin.label} selected #{declared.value.inspect}, " \
          "#{requested.origin.label} requested #{requested.value.inspect}"
        )
      end
    end

    # Closed definitions shared by generation, grammar tests, and analyses.
    module Registry
      DEFINITIONS = [
        Key.new("grammar.mode", type: :symbol, default: :default, owner: :grammar_contract,
                                allowed_values: %i[default extended], cli_option: :mode),
        Key.new("parser.algorithm", type: :symbol, default: :lalr, owner: :grammar_contract,
                                    allowed_values: %i[slr lalr ielr lr1], cli_option: :algorithm,
                                    parser_setting: :algorithm),
        Key.new("parser.entries", type: :symbol, default: :shared, owner: :grammar_contract,
                                  allowed_values: %i[shared isolated], cli_option: :entry_isolation,
                                  parser_setting: :entries),
        Key.new("cst.trivia", type: :symbol, default: :leading, owner: :grammar_contract,
                              allowed_values: %i[leading balanced drop], cli_option: :cst_trivia,
                              parser_setting: :cst_trivia, cli_aliases: ["attach"]),
        Key.new("parser.superclass", type: :optional_string, default: nil, owner: :grammar_contract,
                                     cli_option: :superclass),
        Key.new("actions.omit_calls", type: :optional_boolean, default: nil, owner: :grammar_contract,
                                      cli_option: :omit_actions),
        Key.new("table.representation", type: :symbol, default: :compact, owner: :project_build,
                                        allowed_values: %i[plain compact], cli_option: :table),
        Key.new("runtime.embedded", type: :boolean, default: false, owner: :project_build,
                                    cli_option: :embedded),
        Key.new("build.debug", type: :boolean, default: false, owner: :project_build,
                               cli_option: :debug),
        Key.new("source.line_mapping", type: :symbol, default: :actions, owner: :project_build,
                                       allowed_values: %i[actions all none], cli_option: :line_convert),
        Key.new("build.frozen_strings", type: :boolean, default: false, owner: :project_build,
                                        cli_option: :frozen),
        Key.new("build.executable", type: :optional_string, default: nil, owner: :project_build,
                                    cli_option: :executable)
      ].freeze #: Array[Key]
      BY_NAME = DEFINITIONS.to_h { |key| [key.name, key] }.freeze #: Hash[String, Key]
      CLI_ALGORITHM_VALUES = BY_NAME.fetch("parser.algorithm").allowed_values.map(&:to_s).freeze
      CLI_CST_TRIVIA_VALUES = (
        BY_NAME.fetch("cst.trivia").allowed_values.map(&:to_s) + BY_NAME.fetch("cst.trivia").cli_aliases
      ).freeze

      class << self
        # @rbs (String name) -> Key
        def fetch(name)
          BY_NAME.fetch(name) { raise ArgumentError, "unknown configuration key: #{name.inspect}" }
        end

        # @rbs () -> Array[Key]
        def keys
          DEFINITIONS
        end

        # @rbs () -> Hash[Symbol, Hash[Symbol, untyped]]
        def parser_setting_definitions
          @parser_setting_definitions ||= DEFINITIONS.each_with_object({}) do |key, definitions|
            next unless key.parser_setting

            definitions[key.parser_setting] = {
              configuration: key.name,
              values: key.allowed_values.map(&:to_sym).freeze
            }.freeze
          end.freeze
        end

        # @rbs (Symbol setting) -> Array[Symbol]
        def parser_setting_values(setting)
          parser_setting_definitions.fetch(setting).fetch(:values)
        end

        # @rbs (Symbol setting) -> Key
        def parser_setting_key(setting)
          fetch(parser_setting_definitions.fetch(setting).fetch(:configuration))
        end
      end
    end

    # Applies fixed/minimum override algebra and exposes deterministic evidence.
    class Resolver
      attr_reader :values #: Array[Value]

      # @rbs (?keys: Array[Key], ?grammar: Hash[String, config_value], ?project: Hash[String, config_value],
      #   ?cli: Hash[String, config_value], ?analysis_overrides: Hash[String, config_value],
      #   ?locations: Hash[Symbol, Hash[String, Location]]) -> void
      def initialize(keys: Registry.keys, grammar: {}, project: {}, cli: {}, analysis_overrides: {}, locations: {})
        @keys = keys.sort_by(&:name).freeze
        @key_index = @keys.to_h { |key| [key.name, key] }.freeze
        raise ArgumentError, "duplicate configuration key definition" unless @key_index.length == @keys.length

        sources = { grammar: grammar, project: project, cli: cli, analysis_override: analysis_overrides }
        sources.each { |kind, entries| validate_source!(kind, entries) }
        validate_locations!(locations, sources)
        @values = @keys.map do |key|
          resolve_key(key, sources, locations)
        end.freeze
        @value_index = @values.to_h { |entry| [entry.key.name, entry] }.freeze
        freeze
      end

      # @rbs (String name) -> Value
      def fetch(name)
        @value_index.fetch(name) { raise ArgumentError, "unknown configuration key: #{name.inspect}" }
      end

      # @rbs (String name) -> config_value
      def value(name)
        fetch(name).value
      end

      # @rbs () -> Hash[String, Array[Hash[String, json_value]]]
      def to_h
        { "configuration" => @values.map(&:to_h) }
      end

      # Deterministic JSON independent of caller hash insertion order.
      # @rbs () -> String
      def dump
        "#{JSON.generate(to_h)}\n"
      end

      private

      # @rbs (Symbol kind, Hash[String, config_value] entries) -> void
      def validate_source!(kind, entries)
        entries.each_key do |name|
          raise ArgumentError, "unknown #{kind} configuration key: #{name.inspect}" unless @key_index.key?(name)
        end
      end

      # @rbs (Hash[Symbol, Hash[String, Location]] locations,
      #   Hash[Symbol, Hash[String, config_value]] sources) -> void
      def validate_locations!(locations, sources)
        locations.each do |kind, entries|
          unless %i[grammar project].include?(kind)
            raise ArgumentError, "#{kind} configuration cannot have source locations"
          end

          entries.each do |name, location|
            raise ArgumentError, "unknown #{kind} configuration location: #{name.inspect}" unless @key_index.key?(name)
            raise ArgumentError, "configuration location must be an Ibex::Location" unless location.is_a?(Location)
            next if sources.fetch(kind).key?(name)

            raise ArgumentError, "configuration location for #{name} has no #{kind} value"
          end
        end
      end

      # @rbs (Key key, Hash[Symbol, Hash[String, config_value]] sources,
      #   Hash[Symbol, Hash[String, Location]] locations) -> Value
      def resolve_key(key, sources, locations)
        builtin = value_from(key, key.default, :builtin, locations)
        selected = case key.policy
                   when :fixed then resolve_fixed(key, builtin, sources, locations)
                   when :minimum then resolve_minimum(key, builtin, sources, locations)
                   when :build, :invocation then resolve_override(key, builtin, sources, locations)
                   else raise ArgumentError, "unsupported configuration policy: #{key.policy.inspect}"
                   end
        override = sources.fetch(:analysis_override)
        return selected unless override.key?(key.name)
        raise ArgumentError, "analysis overrides are only valid for fixed configuration" unless key.policy == :fixed
        if key.validate(override.fetch(key.name)) == selected.value
          raise ArgumentError, "analysis override for #{key.name} must differ from the canonical value"
        end

        selected_origin = origin(:analysis_override, key.name, locations)
        Value.new(key, override.fetch(key.name), origin: selected_origin, declared_value: selected.value)
      end

      # @rbs (Key key, Value builtin, Hash[Symbol, Hash[String, config_value]] sources,
      #   Hash[Symbol, Hash[String, Location]] locations) -> Value
      def resolve_fixed(key, builtin, sources, locations)
        grammar = source_value(key, :grammar, sources, locations)
        declared = grammar || builtin
        requested = %i[project cli].filter_map { |kind| source_value(key, kind, sources, locations) }
        reject_fixed_conflicts!(key, grammar, declared, requested)

        grammar || requested.last || builtin
      end

      # @rbs (Key key, Value? grammar, Value declared, Array[Value] requested) -> void
      def reject_fixed_conflicts!(key, grammar, declared, requested)
        if grammar
          conflict = requested.find { |selection| selection.value != declared.value }
          raise Conflict.new(key, declared, conflict) if conflict
        elsif requested.map(&:value).uniq.length > 1
          raise Conflict.new(key, requested.fetch(0), requested.fetch(1))
        end
      end

      # @rbs (Key key, Value builtin, Hash[Symbol, Hash[String, config_value]] sources,
      #   Hash[Symbol, Hash[String, Location]] locations) -> Value
      def resolve_minimum(key, builtin, sources, locations)
        grammar = source_value(key, :grammar, sources, locations)
        floor = grammar || builtin
        selected = floor
        %i[project cli].each do |kind|
          request = source_value(key, kind, sources, locations)
          next unless request

          request_value = request.value #: Integer
          floor_value = floor.value #: Integer
          raise Conflict.new(key, floor, request) if request_value < floor_value

          selected_value = selected.value #: Integer
          selected = request if request_value > selected_value
        end
        selected
      end

      # @rbs (Key key, Value builtin, Hash[Symbol, Hash[String, config_value]] sources,
      #   Hash[Symbol, Hash[String, Location]] locations) -> Value
      def resolve_override(key, builtin, sources, locations)
        if sources.fetch(:grammar).key?(key.name)
          raise ArgumentError, "#{key.name} is #{key.policy} configuration and cannot be grammar-owned"
        end
        if key.policy == :invocation && sources.fetch(:project).key?(key.name)
          raise ArgumentError, "#{key.name} is invocation configuration and cannot be project-owned"
        end

        source_value(key, :cli, sources, locations) ||
          source_value(key, :project, sources, locations) || builtin
      end

      # @rbs (Key key, Symbol kind, Hash[Symbol, Hash[String, config_value]] sources,
      #   Hash[Symbol, Hash[String, Location]] locations) -> Value?
      def source_value(key, kind, sources, locations)
        entries = sources.fetch(kind)
        return unless entries.key?(key.name)

        value_from(key, entries.fetch(key.name), kind, locations)
      end

      # @rbs (Key key, config_value raw, Symbol kind, Hash[Symbol, Hash[String, Location]] locations) -> Value
      def value_from(key, raw, kind, locations)
        Value.new(key, raw, origin: origin(kind, key.name, locations))
      end

      # @rbs (Symbol kind, String name, Hash[Symbol, Hash[String, Location]] locations) -> Origin
      def origin(kind, name, locations)
        Origin.new(kind, location: locations.dig(kind, name))
      end
    end

    # Converts the existing internal CLI option hash into canonical concepts.
    class CLIAdapter
      # The adapter receives the legacy CLI option map, which also contains
      # operation flags and list values outside the closed configuration domain.
      # It validates and converts only declared configuration options.
      # @rbs (Hash[Symbol, untyped] options, ?explicit_keys: Array[Symbol]) -> void
      def initialize(options, explicit_keys: options.keys)
        @options = options.to_h do |name, value|
          [name, value.is_a?(String) ? value.dup.freeze : value]
        end.freeze
        @explicit_keys = explicit_keys.dup.freeze
      end

      # @rbs (?grammar: Hash[String, config_value], ?locations: Hash[String, Location]) -> Resolver
      def resolve(grammar: {}, locations: {})
        source_locations = {} #: Hash[Symbol, Hash[String, Location]]
        source_locations[:grammar] = locations unless locations.empty?
        Resolver.new(grammar: grammar, cli: configuration_values, locations: source_locations)
      end

      # Canonical configuration values selected by explicit legacy CLI options.
      # Raw option spellings stop at this adapter boundary.
      # @rbs () -> Hash[String, config_value]
      def configuration_values
        options = {} #: Hash[String, config_value]
        Registry::DEFINITIONS.each do |key|
          raw_name = key.cli_option
          next unless raw_name && @explicit_keys.include?(raw_name) && @options.key?(raw_name)

          options[key.name] = if raw_name == :line_convert
                                convert_line_mapping
                              else
                                convert(raw_name, @options.fetch(raw_name))
                              end
        end
        line_mapping = Registry.fetch("source.line_mapping")
        if !options.key?(line_mapping.name) && @explicit_keys.include?(:line_convert_all) &&
           @options.key?(:line_convert_all)
          options[line_mapping.name] = convert_line_mapping
        end
        options
      end

      private

      # @rbs (Symbol name, untyped value) -> config_value
      def convert(name, value)
        case name
        when :entry_isolation then convert_entry_isolation(value)
        when :cst_trivia then value == :attach ? :leading : value
        else value
        end
      end

      # @rbs (untyped value) -> config_value
      def convert_entry_isolation(value)
        return :isolated if value == true
        return :shared if value == false

        value
      end

      # @rbs () -> Symbol
      def convert_line_mapping
        line_convert = @options.fetch(:line_convert, true)
        line_convert_all = @options.fetch(:line_convert_all, false)
        unless BOOLEAN_VALUES.include?(line_convert)
          raise ArgumentError, "line_convert expects boolean, got #{line_convert.inspect}"
        end
        unless BOOLEAN_VALUES.include?(line_convert_all)
          raise ArgumentError, "line_convert_all expects boolean, got #{line_convert_all.inspect}"
        end
        if line_convert_all && !line_convert
          raise ArgumentError, "line_convert_all=true conflicts with line_convert=false"
        end
        return :all if line_convert_all
        return :none unless line_convert

        :actions
      end
    end
  end
end

require_relative "configuration/explanation"
