# frozen_string_literal: true

module Ibex
  module LSP
    # Applies full-text LSP document notifications to the overlay-backed store.
    module DocumentHandlers
      include RequestSupport

      private

      # @rbs (untyped raw_params) -> nil
      def did_open(raw_params)
        require_running!
        params = params_hash(raw_params)
        document = hash_member(params, "textDocument")
        publications = store.open(
          string_member(document, "uri"), integer_member(document, "version"), string_member(document, "text")
        )
        publish(publications)
        nil
      end

      # @rbs (untyped raw_params) -> nil
      def did_change(raw_params)
        require_running!
        params = params_hash(raw_params)
        document = hash_member(params, "textDocument")
        changes = params["contentChanges"]
        unless changes.is_a?(Array) && changes.one? && changes.first.is_a?(Hash) &&
               !changes.first.key?("range") && !changes.first.key?("rangeLength")
          raise ProtocolError.new("full sync requires exactly one range-free content change", code: -32_602)
        end

        source = string_member(changes.fetch(0), "text")
        publications = store.change(
          string_member(document, "uri"), integer_member(document, "version"), source
        )
        publish(publications)
        nil
      end

      # @rbs (untyped raw_params) -> nil
      def did_save(raw_params)
        require_running!
        params = params_hash(raw_params)
        document = hash_member(params, "textDocument")
        source = params["text"]
        unless source.nil? || source.is_a?(String)
          raise ProtocolError.new("saved document text must be a string", code: -32_602)
        end

        publish(store.save(string_member(document, "uri"), source: source))
        nil
      end

      # @rbs (untyped raw_params) -> nil
      def did_close(raw_params)
        require_running!
        params = params_hash(raw_params)
        document = hash_member(params, "textDocument")
        publish(store.close(string_member(document, "uri")))
        nil
      end
    end
  end
end
