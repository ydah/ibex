# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  module Coverage
    # Dependency-free structural validation for runtime-event schema version 1.
    module RuntimeEventValidator
      # @rbs!
      #   type json_value = String | Integer | Float | bool | nil | Array[json_value] | Hash[String, json_value]

      TOKEN_KEYS = %w[location state token token_id value].freeze #: Array[String]
      LOCATION_KEYS = %w[column end_column end_line file line].freeze #: Array[String]
      VALIDATORS = {
        "start" => :valid_start?,
        "shift" => :valid_shift?,
        "reduce" => :valid_reduce?,
        "error" => :valid_error?,
        "recover" => :valid_recover?,
        "discard" => :valid_discard?,
        "accept" => :valid_accept?,
        "reject" => :valid_reject?
      }.freeze #: Hash[String, Symbol]

      class << self
        # @rbs (Hash[String, json_value] document) -> bool
        def valid?(document)
          data = document["data"]
          return false unless data.is_a?(Hash) && data.keys.all?(String)
          data = data #: Hash[String, json_value]

          event = document["event"]
          return false unless event.is_a?(String)

          validator = VALIDATORS[event]
          validator ? send(validator, data) : false
        end

        private

        # @rbs (Hash[String, json_value] data) -> bool
        def valid_start?(data)
          return false unless exact_keys?(
            data,
            %w[driver grammar_digest initial_state production_count state_count table_format_version]
          )

          integer_fields = %w[initial_state table_format_version]
          optional_integer_fields = %w[state_count production_count]
          %w[pull push].include?(data["driver"]) &&
            integer_fields.all? { |key| integer?(data[key]) } &&
            optional_integer_fields.all? { |key| optional_integer?(data[key]) } &&
            optional_string?(data["grammar_digest"])
        end

        # @rbs (Hash[String, json_value] data) -> bool
        def valid_shift?(data)
          exact_keys?(data, TOKEN_KEYS + %w[from_state]) &&
            valid_token_fields?(data) &&
            integer?(data["from_state"])
        end

        # @rbs (Hash[String, json_value] data) -> bool
        def valid_reduce?(data)
          keys = %w[goto_state lhs location post_state pre_state production_id result rhs_length]
          rhs_length = data["rhs_length"]
          exact_keys?(data, keys) &&
            %w[goto_state lhs post_state pre_state production_id].all? { |key| integer?(data[key]) } &&
            rhs_length.is_a?(Integer) && rhs_length >= 0 &&
            summary?(data["result"]) && location?(data["location"])
        end

        # @rbs (Hash[String, json_value] data, reasons: Array[String]) -> bool
        def valid_token_event?(data, reasons:)
          exact_keys?(data, TOKEN_KEYS + %w[reason]) &&
            valid_token_fields?(data) &&
            reasons.include?(data["reason"])
        end

        # @rbs (Hash[String, json_value] data) -> bool
        def valid_error?(data)
          valid_token_event?(data, reasons: %w[syntax semantic])
        end

        # @rbs (Hash[String, json_value] data) -> bool
        def valid_discard?(data)
          valid_token_event?(data, reasons: %w[recovery])
        end

        # @rbs (Hash[String, json_value] data) -> bool
        def valid_reject?(data)
          valid_token_event?(data, reasons: %w[eof_during_recovery no_recovery_state])
        end

        # @rbs (Hash[String, json_value] data) -> bool
        def valid_recover?(data)
          exact_keys?(data, TOKEN_KEYS + %w[from_state reason]) &&
            valid_token_fields?(data) &&
            integer?(data["from_state"]) &&
            %w[syntax semantic].include?(data["reason"])
        end

        # @rbs (Hash[String, json_value] data) -> bool
        def valid_accept?(data)
          exact_keys?(data, %w[reason result state]) &&
            integer?(data["state"]) &&
            summary?(data["result"]) &&
            %w[table semantic].include?(data["reason"])
        end

        # @rbs (Hash[String, json_value] data) -> bool
        def valid_token_fields?(data)
          integer?(data["state"]) &&
            optional_integer?(data["token_id"]) &&
            summary?(data["token"]) &&
            summary?(data["value"]) &&
            location?(data["location"])
        end

        # @rbs (json_value value) -> bool
        def summary?(value)
          case value
          when nil, true, false, Integer then true
          when Float then value.finite?
          when String then value.length <= 256
          else composite_summary?(value)
          end
        end

        # @rbs (json_value value) -> bool
        def composite_summary?(value)
          return value.length <= 17 && value.all? { |entry| summary?(entry) } if value.is_a?(Array)
          return false unless value.is_a?(Hash)

          value.keys.all?(String) && value.length <= 17 && value.values.all? { |entry| summary?(entry) }
        end

        # @rbs (json_value value) -> bool
        def location?(value)
          return true if value.nil?
          return false unless value.is_a?(Hash) && value.keys.all?(String)
          return value["unavailable"].is_a?(String) if value.keys == ["unavailable"]

          (value.keys - LOCATION_KEYS).empty? && value.values.all? { |entry| summary?(entry) }
        end

        # @rbs (Hash[String, json_value] data, Array[String] keys) -> bool
        def exact_keys?(data, keys)
          data.keys.sort == keys.sort
        end

        # @rbs (json_value value) -> bool
        def integer?(value)
          value.is_a?(Integer)
        end

        # @rbs (json_value value) -> bool
        def optional_integer?(value)
          value.nil? || integer?(value)
        end

        # @rbs (json_value value) -> bool
        def optional_string?(value)
          value.nil? || value.is_a?(String)
        end
      end
    end
  end
end
