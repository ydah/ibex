# frozen_string_literal: true

module Ibex
  module TableArtifact
    # Canonical JSON ordering and digest primitives shared by writer and loader.
    module Serializer
      class << self
        # @rbs (untyped value) -> untyped
        def canonical(value)
          case value
          when Hash
            value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
          when Array
            value.map { |item| canonical(item) }
          else
            value
          end
        end

        # @rbs (untyped value) -> String
        def compact(value)
          JSON.generate(canonical(value))
        end

        # @rbs (untyped value) -> String
        def dump(value)
          "#{JSON.pretty_generate(canonical(value))}\n"
        end

        # @rbs (untyped value) -> String
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
