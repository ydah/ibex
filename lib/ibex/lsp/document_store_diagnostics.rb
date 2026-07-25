# frozen_string_literal: true

module Ibex
  module LSP
    # Owns per-document and per-root diagnostic aggregation for DocumentStore.
    module DocumentStoreDiagnostics
      private

      # @rbs (String root, Array[String] files, Hash[String, WorkspaceAnalyzer::analyzed_document] analyzed,
      #   Array[WorkspaceAnalyzer::lsp_diagnostic] errors) -> void
      def replace_root_diagnostics(root, files, analyzed, errors)
        # @type self: DocumentStore
        owned = {} #: Hash[String, Array[WorkspaceAnalyzer::lsp_diagnostic]]
        files.each { |path| owned[path] = analyzed.dig(path, :diagnostics) || [] }
        errors.each do |diagnostic|
          file = diagnostic.dig("data", "file")
          next unless file

          existing = owned[file] || []
          duplicate = existing.any? do |entry|
            entry["range"] == diagnostic["range"] && entry["message"] == diagnostic["message"]
          end
          owned[file] = existing + [diagnostic] unless duplicate
        end
        @root_diagnostics[root] = owned
      end

      # @rbs (String path) -> Array[WorkspaceAnalyzer::lsp_diagnostic]
      def aggregated_diagnostics(path)
        # @type self: DocumentStore
        diagnostics = @document_diagnostics.fetch(path, empty_diagnostics).dup
        @root_diagnostics.each_value do |owned|
          diagnostics.concat(owned.fetch(path, empty_diagnostics))
        end
        diagnostics.uniq
      end

      # @rbs () -> Array[WorkspaceAnalyzer::lsp_diagnostic]
      def empty_diagnostics
        [] #: Array[WorkspaceAnalyzer::lsp_diagnostic]
      end
    end
  end
end
