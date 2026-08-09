# frozen_string_literal: true

module Ibex
  module TableArtifact
    # Canonical JSON ordering and digest primitives shared by writer and loader.
    module Serializer
      # @rbs!
      #   type json_value = String | Integer | Float | bool | nil | Array[json_value] | Hash[json_value, json_value]

      class << self
        # @rbs (json_value value) -> json_value
        def canonical(value)
          case value
          when Hash
            value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
          when Array
            value.map { |item| canonical(item) }
          when String
            normalized = value.dup.force_encoding(Encoding::UTF_8)
            normalized.valid_encoding? ? normalized : value
          else
            value
          end
        end

        # @rbs (json_value value) -> String
        def compact(value)
          JSON.generate(canonical(value))
        end

        # @rbs (json_value value) -> String
        def dump(value)
          "#{JSON.pretty_generate(canonical(value))}\n"
        end

        # @rbs (json_value value) -> String
        def digest(value)
          "sha256:#{Digest::SHA256.hexdigest(compact(value))}"
        end

        # @rbs (untyped value) -> untyped
        def deep_freeze(value)
          case value
          when Hash
            value.each do |key, item|
              deep_freeze(key)
              deep_freeze(item)
            end
          when Array
            value.each { |item| deep_freeze(item) }
          end
          value.freeze
        end
      end
    end
  end
end
