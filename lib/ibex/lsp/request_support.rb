# frozen_string_literal: true

module Ibex
  module LSP
    # Shared publication, state, and parameter validation for request handlers.
    module RequestSupport
      private

      # @rbs (Array[DocumentStore::publication] publications) -> void
      def publish(publications)
        publications.each do |publication|
          version = publication[:version]
          next if version && stale_publication?(publication.fetch(:uri), version)

          params = {
            "uri" => publication.fetch(:uri),
            "diagnostics" => publication.fetch(:diagnostics)
          } #: lsp_object
          params["version"] = version if version
          @transport.write_message(
            "jsonrpc" => "2.0", "method" => "textDocument/publishDiagnostics", "params" => params
          )
        end
      end

      # @rbs (String uri, Integer version) -> bool
      def stale_publication?(uri, version)
        path = workspace.path(uri)
        store.snapshot_for(path)&.fetch(:version) != version
      end

      # @rbs (lsp_value? value) -> lsp_object
      def params_hash(value)
        return {} if value.nil?

        if value.is_a?(Hash)
          result = value #: lsp_object
          return result
        end

        raise ProtocolError.new("params must be an object", code: -32_602)
      end

      # @rbs (lsp_object value, String name) -> lsp_object
      def hash_member(value, name)
        member = value[name]
        if member.is_a?(Hash)
          result = member #: lsp_object
          return result
        end

        raise ProtocolError.new("#{name} must be an object", code: -32_602)
      end

      # @rbs (lsp_object value, String name) -> String
      def string_member(value, name)
        member = value[name]
        return member if member.is_a?(String)

        raise ProtocolError.new("#{name} must be a string", code: -32_602)
      end

      # @rbs (lsp_object value, String name) -> Integer
      def integer_member(value, name)
        member = value[name]
        return member if member.is_a?(Integer)

        raise ProtocolError.new("#{name} must be an integer", code: -32_602)
      end

      # @rbs (Symbol state) -> void
      def require_state!(state)
        return if @state == state

        raise ProtocolError.new("request requires #{state} server state", code: -32_600)
      end

      # @rbs () -> void
      def require_running!
        require_state!(:running)
      end

      # @rbs () -> DocumentStore
      def store
        @store || raise(ProtocolError.new("server is not initialized", code: -32_002))
      end

      # @rbs () -> Workspace
      def workspace
        @workspace || raise(ProtocolError.new("server is not initialized", code: -32_002))
      end
    end
  end
end
