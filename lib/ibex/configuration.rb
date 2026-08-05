# frozen_string_literal: true
# rbs_inline: enabled

require "json"
require_relative "error"
require_relative "location"

module Ibex
  # Typed, provenance-preserving effective configuration.
  module Configuration
    OWNER_NAMES = {
      grammar_contract: "grammar-contract",
      grammar_minimum: "grammar-minimum",
      project_build: "project-build",
      invocation: "invocation"
    }.freeze #: Hash[Symbol, String]
    POLICIES = %i[fixed minimum build invocation].freeze #: Array[Symbol]
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
      attr_reader :default #: untyped
      attr_reader :owner #: Symbol
      attr_reader :policy #: Symbol
      attr_reader :allowed_values #: Array[untyped]?
      attr_reader :cli_option #: Symbol?

      # @rbs (String name, type: Symbol, default: untyped, owner: Symbol, policy: Symbol,
      #   ?allowed_values: Array[untyped]?, ?cli_option: Symbol?) -> void
      def initialize(name, type:, default:, owner:, policy:, allowed_values: nil, cli_option: nil)
        validate_identity!(name, owner, policy)
        validate_shape!(type, policy, cli_option)

        @name = name.dup.freeze
        @type = type
        @owner = owner
        @policy = policy
        @allowed_values = allowed_values&.map { |value| immutable(value) }&.freeze
        @cli_option = cli_option
        @default = validate(default)
        freeze
      end

      # Validate and defensively freeze a value from an adapter or declaration.
      # @rbs (untyped value) -> untyped
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

      private

      # @rbs (String name, Symbol owner, Symbol policy) -> void
      def validate_identity!(name, owner, policy)
        valid_name = name.is_a?(String) && name.match?(/\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/)
        raise ArgumentError, "invalid canonical configuration key: #{name.inspect}" unless valid_name
        raise ArgumentError, "unknown configuration owner: #{owner.inspect}" unless OWNER_NAMES.key?(owner)
        raise ArgumentError, "unknown configuration policy: #{policy.inspect}" unless POLICIES.include?(policy)
        return if OWNER_POLICIES.fetch(owner) == policy

        raise ArgumentError, "#{owner} configuration must use #{OWNER_POLICIES.fetch(owner)} policy"
      end

      # @rbs (Symbol type, Symbol policy, Symbol? cli_option) -> void
      def validate_shape!(type, policy, cli_option)
        raise ArgumentError, "cli_option must be a Symbol or nil" unless cli_option.nil? || cli_option.is_a?(Symbol)
        return unless policy == :minimum && type != :integer

        raise ArgumentError, "minimum configuration keys must have Integer values"
      end

      # @rbs (untyped value) -> untyped
      def immutable(value)
        value.is_a?(String) ? value.dup.freeze : value
      end

      # @rbs (untyped value) -> bool
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

      # @rbs () -> Hash[String, untyped]
      def to_h
        result = { "kind" => @kind.to_s } #: Hash[String, untyped]
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

      # @rbs (Location location) -> Hash[String, untyped]
      def stringify_location(location)
        location.to_h.transform_keys(&:to_s)
      end
    end

    # A typed effective value plus the evidence needed to explain it.
    class Value
      attr_reader :key #: Key
      attr_reader :value #: untyped
      attr_reader :origin #: Origin
      attr_reader :explicit #: bool
      attr_reader :canonical #: bool
      attr_reader :declared_value #: untyped

      # @rbs (Key key, untyped value, origin: Origin, explicit: bool, canonical: bool,
      #   ?declared_value: untyped) -> void
      def initialize(key, value, origin:, explicit:, canonical:, declared_value: DECLARED_VALUE_UNSET)
        raise ArgumentError, "configuration value key must be a Configuration::Key" unless key.is_a?(Key)
        raise ArgumentError, "configuration value origin must be a Configuration::Origin" unless origin.is_a?(Origin)
        raise ArgumentError, "explicit must be boolean" unless BOOLEAN_VALUES.include?(explicit)
        raise ArgumentError, "canonical must be boolean" unless BOOLEAN_VALUES.include?(canonical)

        validate_provenance!(key, origin, explicit, canonical, declared_value)

        @key = key
        @value = key.validate(value)
        @origin = origin
        @explicit = explicit
        @canonical = canonical
        @declared_value = declared_value.equal?(DECLARED_VALUE_UNSET) ? nil : key.validate(declared_value)

        freeze
      end

      # @rbs () -> Hash[String, untyped]
      def to_h
        result = {
          "key" => @key.name,
          "value" => json_value(@value),
          "owner" => @key.owner_name,
          "policy" => @key.policy.to_s,
          "origin" => @origin.to_h,
          "explicit" => @explicit,
          "canonical" => @canonical
        } #: Hash[String, untyped]
        unless @canonical
          result["analysis"] = {
            "declared" => json_value(@declared_value),
            "selected" => json_value(@value),
            "override" => true,
            "canonical_generation" => false
          }
        end
        result
      end

      private

      # @rbs (Key key, Origin origin, bool explicit, bool canonical, untyped declared_value) -> void
      def validate_provenance!(key, origin, explicit, canonical, declared_value)
        validate_canonical_origin!(key, origin, canonical)
        validate_owner_source!(key, origin)
        validate_explicitness!(origin, explicit)
        validate_declared_evidence!(canonical, declared_value)
      end

      # @rbs (Key key, Origin origin, bool canonical) -> void
      def validate_canonical_origin!(key, origin, canonical)
        analysis_override = origin.kind == :analysis_override
        unless analysis_override == !canonical
          raise ArgumentError, "analysis_override origin must identify a noncanonical selection"
        end
        return if canonical || key.policy == :fixed

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

      # @rbs (Origin origin, bool explicit) -> void
      def validate_explicitness!(origin, explicit)
        raise ArgumentError, "builtin configuration cannot be explicit" if origin.kind == :builtin && explicit
        raise ArgumentError, "non-builtin configuration must be explicit" if origin.kind != :builtin && !explicit
      end

      # @rbs (bool canonical, untyped declared_value) -> void
      def validate_declared_evidence!(canonical, declared_value)
        declared = !declared_value.equal?(DECLARED_VALUE_UNSET)
        raise ArgumentError, "canonical selections cannot carry declared evidence" if canonical && declared
        return if canonical || declared

        raise ArgumentError, "noncanonical selections require declared evidence"
      end

      # @rbs (untyped value) -> untyped
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
        Key.new("grammar.mode", type: :symbol, default: :default, owner: :grammar_contract, policy: :fixed,
                                allowed_values: %i[default extended], cli_option: :mode),
        Key.new("parser.algorithm", type: :symbol, default: :lalr, owner: :grammar_contract, policy: :fixed,
                                    allowed_values: %i[slr lalr ielr lr1], cli_option: :algorithm),
        Key.new("parser.entries", type: :symbol, default: :shared, owner: :grammar_contract, policy: :fixed,
                                  allowed_values: %i[shared isolated], cli_option: :entry_isolation),
        Key.new("cst.trivia", type: :symbol, default: :leading, owner: :grammar_contract, policy: :fixed,
                              allowed_values: %i[leading balanced drop], cli_option: :cst_trivia),
        Key.new("parser.superclass", type: :optional_string, default: nil, owner: :grammar_contract, policy: :fixed,
                                     cli_option: :superclass),
        Key.new("actions.omit_calls", type: :optional_boolean, default: nil, owner: :grammar_contract,
                                      policy: :fixed, cli_option: :omit_actions),
        Key.new("table.representation", type: :symbol, default: :compact, owner: :project_build, policy: :build,
                                        allowed_values: %i[plain compact], cli_option: :table),
        Key.new("runtime.embedded", type: :boolean, default: false, owner: :project_build, policy: :build,
                                    cli_option: :embedded),
        Key.new("build.debug", type: :boolean, default: false, owner: :project_build, policy: :build,
                               cli_option: :debug),
        Key.new("source.line_mapping", type: :symbol, default: :actions, owner: :project_build, policy: :build,
                                       allowed_values: %i[actions all none], cli_option: :line_convert),
        Key.new("build.frozen_strings", type: :boolean, default: false, owner: :project_build, policy: :build,
                                        cli_option: :frozen),
        Key.new("build.executable", type: :optional_string, default: nil, owner: :project_build, policy: :build,
                                    cli_option: :executable)
      ].freeze #: Array[Key]
      BY_NAME = DEFINITIONS.to_h { |key| [key.name, key] }.freeze #: Hash[String, Key]

      class << self
        # @rbs (String name) -> Key
        def fetch(name)
          BY_NAME.fetch(name) { raise ArgumentError, "unknown configuration key: #{name.inspect}" }
        end

        # @rbs () -> Array[Key]
        def keys
          DEFINITIONS
        end
      end
    end

    # Applies fixed/minimum override algebra and exposes deterministic evidence.
    class Resolver
      attr_reader :values #: Array[Value]

      # @rbs (?keys: Array[Key], ?grammar: Hash[String, untyped], ?project: Hash[String, untyped],
      #   ?cli: Hash[String, untyped], ?analysis_overrides: Hash[String, untyped],
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

      # @rbs (String name) -> untyped
      def value(name)
        fetch(name).value
      end

      # @rbs () -> Hash[String, Array[Hash[String, untyped]]]
      def to_h
        { "configuration" => @values.map(&:to_h) }
      end

      # Deterministic JSON independent of caller hash insertion order.
      # @rbs () -> String
      def dump
        "#{JSON.generate(to_h)}\n"
      end

      private

      # @rbs (Symbol kind, Hash[String, untyped] entries) -> void
      def validate_source!(kind, entries)
        entries.each_key do |name|
          raise ArgumentError, "unknown #{kind} configuration key: #{name.inspect}" unless @key_index.key?(name)
        end
      end

      # @rbs (Hash[Symbol, Hash[String, Location]] locations,
      #   Hash[Symbol, Hash[String, untyped]] sources) -> void
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

      # @rbs (Key key, Hash[Symbol, Hash[String, untyped]] sources,
      #   Hash[Symbol, Hash[String, Location]] locations) -> Value
      def resolve_key(key, sources, locations)
        builtin = value_from(key, key.default, :builtin, locations, explicit: false)
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
        Value.new(
          key, override.fetch(key.name), origin: selected_origin,
                                         explicit: true, canonical: false, declared_value: selected.value
        )
      end

      # @rbs (Key key, Value builtin, Hash[Symbol, Hash[String, untyped]] sources,
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

      # @rbs (Key key, Value builtin, Hash[Symbol, Hash[String, untyped]] sources,
      #   Hash[Symbol, Hash[String, Location]] locations) -> Value
      def resolve_minimum(key, builtin, sources, locations)
        grammar = source_value(key, :grammar, sources, locations)
        floor = grammar || builtin
        selected = floor
        %i[project cli].each do |kind|
          request = source_value(key, kind, sources, locations)
          next unless request
          raise Conflict.new(key, floor, request) if request.value < floor.value

          selected = request if request.value > selected.value
        end
        selected
      end

      # @rbs (Key key, Value builtin, Hash[Symbol, Hash[String, untyped]] sources,
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

      # @rbs (Key key, Symbol kind, Hash[Symbol, Hash[String, untyped]] sources,
      #   Hash[Symbol, Hash[String, Location]] locations) -> Value?
      def source_value(key, kind, sources, locations)
        entries = sources.fetch(kind)
        return unless entries.key?(key.name)

        value_from(key, entries.fetch(key.name), kind, locations, explicit: true)
      end

      # @rbs (Key key, untyped raw, Symbol kind, Hash[Symbol, Hash[String, Location]] locations,
      #   explicit: bool) -> Value
      def value_from(key, raw, kind, locations, explicit:)
        Value.new(
          key, raw, origin: origin(kind, key.name, locations), explicit: explicit, canonical: true
        )
      end

      # @rbs (Symbol kind, String name, Hash[Symbol, Hash[String, Location]] locations) -> Origin
      def origin(kind, name, locations)
        Origin.new(kind, location: locations.dig(kind, name))
      end
    end

    # Converts the existing internal CLI option hash into canonical concepts.
    class CLIAdapter
      # @rbs (Hash[Symbol, untyped] options, ?explicit_keys: Array[Symbol]) -> void
      def initialize(options, explicit_keys: options.keys)
        @options = options.to_h do |name, value|
          [name, value.is_a?(String) ? value.dup.freeze : value]
        end.freeze
        @explicit_keys = explicit_keys.dup.freeze
      end

      # @rbs (?grammar: Hash[String, untyped], ?locations: Hash[String, Location]) -> Resolver
      def resolve(grammar: {}, locations: {})
        source_locations = {} #: Hash[Symbol, Hash[String, Location]]
        source_locations[:grammar] = locations unless locations.empty?
        Resolver.new(grammar: grammar, cli: canonical_options, locations: source_locations)
      end

      private

      # @rbs () -> Hash[String, untyped]
      def canonical_options
        options = {} #: Hash[String, untyped]
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

      # @rbs (Symbol name, untyped value) -> untyped
      def convert(name, value)
        case name
        when :entry_isolation then convert_entry_isolation(value)
        when :cst_trivia then value == :attach ? :leading : value
        else value
        end
      end

      # @rbs (untyped value) -> untyped
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
