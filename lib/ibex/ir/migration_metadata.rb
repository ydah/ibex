# frozen_string_literal: true

require_relative "../error"

module Ibex
  module IR
    # Closed migration provenance shared by factories and serialized-document validation.
    module MigrationMetadata
      UNAVAILABLE_V2_CONFIGURATION = %w[
        effective_parser_algorithm
        effective_parser_entries
        effective_cst_trivia
      ].freeze #: Array[String]

      class << self
        # @rbs (Integer schema_version, migration_metadata? migration) -> void
        def validate!(schema_version, migration)
          raise Ibex::Error, "(ir):1:1: $.migration requires schema_version 3" if schema_version < 3 && migration
          return unless migration

          path = "$.migration"
          migration = validate_record(migration, path)
          from = migration.fetch(:from_schema_version)
          validate_source_version(schema_version, from, path)
          validate_inventory(migration.fetch(:unavailable), UNAVAILABLE_V2_CONFIGURATION, path)
        end

        private

        # @rbs (Object? migration, String path) -> migration_metadata
        def validate_record(migration, path)
          raise Ibex::Error, "(ir):1:1: #{path} must be an object" unless migration.is_a?(Hash)

          required = %i[from_schema_version unavailable]
          missing = required.reject { |key| migration.key?(key) }
          unless missing.empty?
            raise Ibex::Error, "(ir):1:1: #{path} is missing required field #{missing.first.inspect}"
          end

          unknown = migration.keys - required
          raise Ibex::Error, "(ir):1:1: #{path} has unsupported field #{unknown.first.inspect}" unless unknown.empty?

          migration #: migration_metadata
        end

        # @rbs (Integer schema_version, Integer from, String path) -> void
        def validate_source_version(schema_version, from, path)
          return if schema_version >= 3 && from == 2

          raise Ibex::Error, "(ir):1:1: #{path}.from_schema_version must be 2"
        end

        # @rbs (Object? unavailable, Array[String] expected, String path) -> void
        def validate_inventory(unavailable, expected, path)
          raise Ibex::Error, "(ir):1:1: #{path}.unavailable must be an array" unless unavailable.is_a?(Array)
          raise Ibex::Error, "(ir):1:1: #{path}.unavailable must not be empty" if unavailable.empty?

          unavailable.each_with_index do |name, index|
            item_path = "#{path}.unavailable[#{index}]"
            raise Ibex::Error, "(ir):1:1: #{item_path} must be a string" unless name.is_a?(String)
            next if expected.include?(name)

            raise Ibex::Error, "(ir):1:1: #{item_path} must be one of #{expected.join(', ')}"
          end
          unless unavailable.uniq.length == unavailable.length
            raise Ibex::Error, "(ir):1:1: #{path}.unavailable must contain unique names"
          end
          return if unavailable == expected

          raise Ibex::Error, "(ir):1:1: #{path}.unavailable must equal the deterministic migration loss inventory"
        end
      end
    end
    private_constant :MigrationMetadata
  end
end
