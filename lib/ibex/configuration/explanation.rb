# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Configuration
    # One observed configuration source and how it participated in selection.
    class Evidence
      STATUSES = %i[accepted ignored duplicate conflicting].freeze #: Array[Symbol]
      SOURCES = %i[grammar project cli].freeze #: Array[Symbol]

      attr_reader :key #: Key
      attr_reader :source #: Symbol
      attr_reader :value #: config_value
      attr_reader :status #: Symbol
      attr_reader :location #: Location?
      attr_reader :reason #: String

      # @rbs (Key key, source: Symbol, value: config_value, status: Symbol, reason: String,
      #   ?location: Location?) -> void
      def initialize(key, source:, value:, status:, reason:, location: nil)
        raise ArgumentError, "configuration evidence key must be a Configuration::Key" unless key.is_a?(Key)
        raise ArgumentError, "unknown configuration evidence source: #{source.inspect}" unless SOURCES.include?(source)
        raise ArgumentError, "unknown configuration evidence status: #{status.inspect}" unless STATUSES.include?(status)
        unless location.nil? || location.is_a?(Location)
          raise ArgumentError, "configuration evidence location must be an Ibex::Location"
        end
        raise ArgumentError, "configuration evidence reason must not be empty" if reason.empty?

        @key = key
        @source = source
        @value = key.validate(value)
        @status = status
        @location = location
        @reason = reason.dup.freeze
        freeze
      end

      # @rbs () -> Hash[String, json_value]
      def to_h
        result = {
          "source" => @source.to_s,
          "value" => json_value(@value),
          "status" => @status.to_s,
          "reason" => @reason
        } #: Hash[String, json_value]
        location = @location
        result["location"] = location.to_h.transform_keys(&:to_s) if location
        result
      end

      private

      # @rbs (config_value value) -> (String | Integer | bool | nil)
      def json_value(value)
        value.is_a?(Symbol) ? value.to_s : value
      end
    end

    # Whether an input can prove the historical source of a selected setting.
    class Recording
      STATES = %i[source recorded unspecified unavailable not_applicable].freeze #: Array[Symbol]

      attr_reader :state #: Symbol
      attr_reader :reason #: String

      # @rbs (Symbol state, String reason) -> void
      def initialize(state, reason)
        raise ArgumentError, "unknown configuration recording state: #{state.inspect}" unless STATES.include?(state)
        raise ArgumentError, "configuration recording reason must not be empty" if reason.empty?

        @state = state
        @reason = reason.dup.freeze
        freeze
      end

      # @rbs () -> Hash[String, String]
      def to_h
        { "state" => @state.to_s.tr("_", "-"), "reason" => @reason }
      end
    end

    # Canonical, static input facts used to build a configuration report.
    class Input
      KINDS = %i[grammar_source grammar_ir].freeze #: Array[Symbol]

      attr_reader :kind #: Symbol
      attr_reader :path #: String
      attr_reader :files #: Array[String]
      attr_reader :schema_version #: Integer?
      attr_reader :grammar_values #: Hash[String, config_value]
      attr_reader :grammar_locations #: Hash[String, Location]
      attr_reader :evidence #: Hash[String, Array[Evidence]]
      attr_reader :recordings #: Hash[String, Recording]

      # @rbs (kind: Symbol, path: String, ?files: Array[String], ?schema_version: Integer?,
      #   ?grammar_values: Hash[String, config_value], ?grammar_locations: Hash[String, Location],
      #   ?evidence: Hash[String, Array[Evidence]], ?recordings: Hash[String, Recording]) -> void
      def initialize(kind:, path:, files: [path], schema_version: nil, grammar_values: {}, grammar_locations: {},
                     evidence: {}, recordings: {})
        raise ArgumentError, "unknown configuration input kind: #{kind.inspect}" unless KINDS.include?(kind)
        unless path.is_a?(String) && !path.empty?
          raise ArgumentError, "configuration input path must be a non-empty String"
        end

        validate_files!(files, path)
        validate_schema_version!(kind, schema_version)
        validate_entries!(grammar_values, grammar_locations, evidence, recordings)
        assign_input(
          kind, path, files, schema_version, grammar_values, grammar_locations, evidence, recordings
        )
        freeze
      end

      # @rbs () -> Hash[String, json_value]
      def to_h
        result = {
          "kind" => @kind.to_s.tr("_", "-"),
          "path" => @path,
          "files" => @files
        } #: Hash[String, json_value]
        result["schema_version"] = @schema_version if @schema_version
        result
      end

      private

      # @rbs (Symbol kind, String path, Array[String] files, Integer? schema_version,
      #   Hash[String, config_value] grammar_values, Hash[String, Location] grammar_locations,
      #   Hash[String, Array[Evidence]] evidence, Hash[String, Recording] recordings) -> void
      def assign_input(kind, path, files, schema_version, grammar_values, grammar_locations, evidence, recordings)
        @kind = kind
        @path = path.dup.freeze
        @files = files.map { |file| file.dup.freeze }.freeze
        @schema_version = schema_version
        @grammar_values = immutable_values(grammar_values)
        @grammar_locations = grammar_locations.to_h { |key, location| [key.dup.freeze, location] }.freeze
        @evidence = evidence.to_h { |key, entries| [key.dup.freeze, entries.dup.freeze] }.freeze
        @recordings = recordings.to_h { |key, recording| [key.dup.freeze, recording] }.freeze
      end

      # @rbs (Array[String] files, String path) -> void
      def validate_files!(files, path)
        unless files.is_a?(Array) && !files.empty? && files.all? { |file| file.is_a?(String) && !file.empty? }
          raise ArgumentError, "configuration input files must be non-empty Strings"
        end
        raise ArgumentError, "configuration input files must be unique" unless files.uniq.length == files.length
        raise ArgumentError, "configuration input path must be the first file" unless files.first == path
      end

      # @rbs (Symbol kind, Integer? schema_version) -> void
      def validate_schema_version!(kind, schema_version)
        if kind == :grammar_source
          raise ArgumentError, "grammar source input cannot have a schema version" unless schema_version.nil?
        elsif !schema_version.is_a?(Integer) || !schema_version.positive?
          raise ArgumentError, "Grammar IR input requires a positive schema version"
        end
      end

      # @rbs (Hash[String, config_value] values, Hash[String, Location] locations,
      #   Hash[String, Array[Evidence]] evidence, Hash[String, Recording] recordings) -> void
      def validate_entries!(values, locations, evidence, recordings)
        validate_fact_hashes!(values, locations, evidence, recordings)
        names = values.keys | locations.keys | evidence.keys | recordings.keys
        names.each do |name|
          raise ArgumentError, "configuration input keys must be Strings" unless name.is_a?(String)

          Registry.fetch(name)
        end
        validate_locations!(values, locations)
        validate_evidence!(evidence)
        validate_recordings!(recordings)
      end

      # @rbs (*Hash[Object?, Object?] values) -> void
      def validate_fact_hashes!(*values)
        return if values.all?(Hash)

        raise ArgumentError, "configuration input facts must be Hash values"
      end

      # @rbs (Hash[String, config_value] values, Hash[String, Location] locations) -> void
      def validate_locations!(values, locations)
        locations.each do |name, location|
          raise ArgumentError, "configuration location for #{name} has no grammar value" unless values.key?(name)
          raise ArgumentError, "configuration location must be an Ibex::Location" unless location.is_a?(Location)
        end
      end

      # @rbs (Hash[String, Array[Evidence]] evidence) -> void
      def validate_evidence!(evidence)
        evidence.each do |name, entries|
          key = Registry.fetch(name)
          unless entries.is_a?(Array) && entries.all? { |entry| entry.is_a?(Evidence) && entry.key.equal?(key) }
            raise ArgumentError, "configuration evidence for #{name} has the wrong key"
          end
        end
      end

      # @rbs (Hash[String, Recording] recordings) -> void
      def validate_recordings!(recordings)
        recordings.each do |name, recording|
          next if recording.is_a?(Recording)

          raise ArgumentError, "configuration recording for #{name} must be a Recording"
        end
      end

      # @rbs (Hash[String, config_value] values) -> Hash[String, config_value]
      def immutable_values(values)
        values.to_h do |name, value|
          [name.dup.freeze, Registry.fetch(name).validate(value)]
        end.freeze
      end
    end

    # A fixed-contract mismatch retained as structured report data.
    class ConflictRecord
      attr_reader :key #: Key
      attr_reader :declared #: Value
      attr_reader :requested #: Value

      # @rbs (Conflict conflict) -> void
      def initialize(conflict)
        raise ArgumentError, "conflict record requires a Configuration::Conflict" unless conflict.is_a?(Conflict)

        @key = conflict.key
        @declared = conflict.declared
        @requested = conflict.requested
        freeze
      end

      # @rbs () -> Hash[String, json_value]
      def to_h
        {
          "key" => @key.name,
          "policy" => @key.policy.to_s,
          "declared" => selection(@declared),
          "requested" => selection(@requested)
        }
      end

      # @rbs () -> String
      def message
        location = @declared.origin.location
        prefix = location ? "#{location.file || '(source)'}:#{location.line}:#{location.column}: " : "(config):1:1: "
        "#{prefix}configuration conflict for #{@key.name}: " \
          "#{@declared.origin.label} selected #{@declared.value.inspect}, " \
          "#{@requested.origin.label} requested #{@requested.value.inspect}"
      end

      private

      # @rbs (Value value) -> Hash[String, json_value]
      def selection(value)
        serialized = value.to_h
        { "value" => serialized.fetch("value"), "origin" => serialized.fetch("origin") }
      end
    end

    # The effective value and all accepted or rejected evidence for one key.
    class Explanation
      attr_reader :value #: Value
      attr_reader :evidence #: Array[Evidence]
      attr_reader :recording #: Recording

      # @rbs (Value value, evidence: Array[Evidence], recording: Recording) -> void
      def initialize(value, evidence:, recording:)
        raise ArgumentError, "explanation value must be a Configuration::Value" unless value.is_a?(Value)
        unless recording.is_a?(Recording)
          raise ArgumentError,
                "explanation recording must be a Configuration::Recording"
        end
        unless evidence.all? { |entry| entry.is_a?(Evidence) && entry.key.equal?(value.key) }
          raise ArgumentError, "explanation evidence has the wrong key"
        end

        @value = value
        @evidence = evidence.dup.freeze
        @recording = recording
        freeze
      end

      # @rbs () -> Hash[String, json_value]
      def to_h
        @value.to_h.merge(
          "selection" => @value.explicit ? "explicit" : "implicit",
          "conformance" => @value.canonical ? "canonical" : "noncanonical",
          "recording" => @recording.to_h,
          "evidence" => @evidence.map(&:to_h)
        )
      end
    end

    # Deterministic, static-no-user-code explanation of every registered setting.
    class Report
      attr_reader :input #: Input
      attr_reader :explanations #: Array[Explanation]
      attr_reader :conflicts #: Array[ConflictRecord]

      # @rbs (Input input, ?cli: Hash[String, config_value]) -> void
      def initialize(input, cli: {})
        raise ArgumentError, "configuration report input must be a Configuration::Input" unless input.is_a?(Input)

        cli.each_key { |name| Registry.fetch(name) }

        @input = input
        conflicts = [] #: Array[ConflictRecord]
        @explanations = Registry.keys.sort_by(&:name).map do |key|
          value = resolve_key(key, cli)
          explanation(value, cli)
        rescue Conflict => e
          record = ConflictRecord.new(e)
          conflicts << record
          explanation(e.declared, cli, conflict: record)
        end.freeze
        @conflicts = conflicts.freeze
        freeze
      end

      # @rbs () -> bool
      def success?
        @conflicts.empty?
      end

      # @rbs () -> Hash[String, json_value]
      def to_h
        {
          "ibex_report" => "configuration",
          "schema_version" => 1,
          "trust" => "static-no-user-code",
          "status" => success? ? "ok" : "conflict",
          "input" => @input.to_h,
          "configuration" => @explanations.map(&:to_h),
          "conflicts" => @conflicts.map(&:to_h)
        }
      end

      # Deterministic JSON independent of caller hash insertion order.
      # @rbs () -> String
      def dump
        "#{JSON.generate(to_h)}\n"
      end

      # @rbs () -> String
      def render_text
        lines = ["configuration status=#{success? ? 'ok' : 'conflict'} (static-no-user-code): #{@input.path}"]
        @explanations.each { |entry| lines.concat(render_explanation(entry)) }
        @conflicts.each { |conflict| lines << "conflict: #{conflict.message}" }
        "#{lines.join("\n")}\n"
      end

      private

      # @rbs (Key key, Hash[String, config_value] cli) -> Value
      def resolve_key(key, cli)
        name = key.name
        grammar = {} #: Hash[String, config_value]
        grammar[name] = @input.grammar_values.fetch(name) if @input.grammar_values.key?(name)
        request = {} #: Hash[String, config_value]
        request[name] = cli.fetch(name) if cli.key?(name)
        locations = {} #: Hash[Symbol, Hash[String, Location]]
        locations[:grammar] = { name => @input.grammar_locations.fetch(name) } \
          if @input.grammar_locations.key?(name)
        Resolver.new(keys: [key], grammar: grammar, cli: request, locations: locations).values.fetch(0)
      end

      # @rbs (Value value, Hash[String, config_value] cli, ?conflict: ConflictRecord?) -> Explanation
      def explanation(value, cli, conflict: nil)
        key = value.key
        evidence = @input.evidence.fetch(key.name, []).dup
        evidence << cli_evidence(key, cli.fetch(key.name), conflicting: !conflict.nil?) if cli.key?(key.name)
        recording = @input.recordings.fetch(
          key.name,
          Recording.new(:not_applicable, "this setting has no historical source contract in this input")
        )
        Explanation.new(value, evidence: evidence, recording: recording)
      end

      # @rbs (Key key, config_value raw, conflicting: bool) -> Evidence
      def cli_evidence(key, raw, conflicting:)
        value = key.validate(raw)
        grammar = @input.grammar_values
        status = conflicting ? :conflicting : :accepted
        reason = if conflicting
                   "conflicts with the fixed grammar contract and was not selected"
                 elsif grammar.key?(key.name) && grammar.fetch(key.name) == value
                   "matches the fixed grammar contract"
                 else
                   "selected canonical command-line request"
                 end
        Evidence.new(key, source: :cli, value: value, status: status, reason: reason)
      end

      # @rbs (config_value value) -> String
      def display(value)
        value.nil? ? "null" : value.to_s
      end

      # @rbs (Location location) -> String
      def location_label(location)
        "#{location.file || '(source)'}:#{location.line}:#{location.column}"
      end

      # @rbs (Explanation entry) -> Array[String]
      def render_explanation(entry)
        value = entry.value
        lines = [
          "#{value.key.name}=#{display(value.value)} owner=#{value.key.owner_name} " \
          "origin=#{value.origin.label} policy=#{value.key.policy} " \
          "#{value.explicit ? 'explicit' : 'implicit'} #{value.canonical ? 'canonical' : 'noncanonical'}",
          "  recording=#{entry.recording.state}: #{entry.recording.reason}"
        ]
        entry.evidence.each do |evidence|
          location = evidence.location ? " at #{location_label(evidence.location)}" : ""
          lines << "  #{evidence.status} #{evidence.source}=#{display(evidence.value)}#{location}: #{evidence.reason}"
        end
        lines
      end
    end
  end
end
