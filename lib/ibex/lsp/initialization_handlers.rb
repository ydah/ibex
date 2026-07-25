# frozen_string_literal: true

module Ibex
  module LSP
    # Handles initialize/initialized/shutdown/exit lifecycle transitions.
    module InitializationHandlers
      include RequestSupport

      private

      # @rbs (untyped raw_params) -> Hash[String, untyped]
      def initialize_workspace(raw_params)
        raise ProtocolError.new("server is already initialized", code: -32_600) unless @state == :uninitialized

        params = params_hash(raw_params)
        loader = Frontend::SourceLoader.new
        @workspace = Workspace.new(initialization_roots(params), loader)
        @store = DocumentStore.new(@workspace, loader)
        @state = :initialized
        {
          "capabilities" => capabilities,
          "serverInfo" => { "name" => "ibex", "version" => Ibex::VERSION }
        }
      end

      # @rbs (untyped params) -> nil
      def initialized_notification(_params)
        require_state!(:initialized)
        @state = :running
        nil
      end

      # @rbs (untyped params) -> nil
      def shutdown_request(_params)
        require_state!(:running)
        @state = :shutdown
        nil
      end

      # @rbs (untyped params) -> nil
      def exit_notification(_params)
        @exit_status = @state == :shutdown ? 0 : 1
        @exit_requested = true
        nil
      end

      # @rbs () -> Hash[String, untyped]
      def capabilities
        {
          "positionEncoding" => "utf-16",
          "textDocumentSync" => { "openClose" => true, "change" => 1, "save" => { "includeText" => true } },
          "definitionProvider" => true,
          "referencesProvider" => true,
          "renameProvider" => { "prepareProvider" => true },
          "hoverProvider" => true,
          "workspace" => { "workspaceFolders" => { "supported" => true, "changeNotifications" => false } }
        }
      end

      # @rbs (Hash[String, untyped] params) -> Array[String]
      def initialization_roots(params)
        folders = params["workspaceFolders"]
        if folders.is_a?(Array) && !folders.empty?
          return folders.map do |folder|
            raise ProtocolError.new("workspaceFolders entries must be objects", code: -32_602) unless folder.is_a?(Hash)

            string_member(folder, "uri")
          end
        end

        root = params["rootUri"]
        return [root] if root.is_a?(String)

        raise ProtocolError.new("initialize requires rootUri or workspaceFolders", code: -32_602)
      end
    end
  end
end
