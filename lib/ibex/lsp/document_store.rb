# frozen_string_literal: true

module Ibex
  module LSP
    # Owns open buffers, parsed snapshots, include closures, and reverse dependencies.
    class DocumentStore
      include DocumentStoreValidation
      include DocumentStoreDiagnostics

      # @rbs!
      #   type snapshot = {
      #     uri: String,
      #     path: String,
      #     version: Integer?,
      #     source: String,
      #     open: bool,
      #     document: Frontend::SourceDocument?
      #   }
      #   type publication = {
      #     uri: String,
      #     ?version: Integer,
      #     diagnostics: Array[WorkspaceAnalyzer::lsp_diagnostic]
      #   }

      attr_reader :loader #: Frontend::SourceLoader
      attr_reader :workspace #: Workspace

      # @rbs (Workspace workspace, Frontend::SourceLoader loader) -> void
      def initialize(workspace, loader)
        @workspace = workspace
        @loader = loader
        @analyzer = WorkspaceAnalyzer.new(workspace, loader)
        @snapshots = {} #: Hash[String, snapshot]
        @roots = {} #: Hash[String, bool]
        @closures = {} #: Hash[String, Array[String]]
        @reverse_dependencies = {} #: Hash[String, Array[String]]
        @resolutions = {} #: Hash[String, Frontend::Resolution]
        @document_diagnostics = {} #: Hash[String, Array[WorkspaceAnalyzer::lsp_diagnostic]]
        @root_diagnostics = {} #: Hash[String, Hash[String, Array[WorkspaceAnalyzer::lsp_diagnostic]]]
      end

      # @rbs (String uri, Integer version, String source) -> Array[publication]
      def open(uri, version, source)
        path = workspace.path(uri)
        raise ProtocolError.new("document is already open: #{uri}", code: -32_602) if @snapshots.dig(path, :open)

        validate_version(version)
        validate_source(source)
        loader.set_overlay(path, source)
        @snapshots[path] = snapshot(uri, path, version, source, true, nil)
        refresh(path)
      end

      # @rbs (String uri, Integer version, String source) -> Array[publication]
      def change(uri, version, source)
        path = workspace.path(uri)
        current = open_snapshot(path, uri)
        validate_version(version)
        unless current.fetch(:version) && version > current.fetch(:version)
          raise ProtocolError.new("document version must increase monotonically", code: -32_602)
        end

        validate_source(source)
        loader.set_overlay(path, source)
        @snapshots[path] = snapshot(uri, path, version, source, true, nil)
        refresh(path)
      end

      # @rbs (String uri, ?source: String?) -> Array[publication]
      def save(uri, source: nil)
        path = workspace.path(uri)
        current = open_snapshot(path, uri)
        if source
          validate_source(source)
          loader.set_overlay(path, source)
          current = snapshot(uri, path, current.fetch(:version), source, true, nil)
          @snapshots[path] = current
        end
        refresh(path)
      end

      # Clear the open version first, then replace it with a disk snapshot if one exists.
      # @rbs (String uri) -> Array[publication]
      def close(uri)
        path = workspace.path(uri)
        open_snapshot(path, uri)
        clear = { uri: uri, diagnostics: [] } #: publication
        old_files = files_for(path)
        was_root = @roots[path]
        disk_path = disk_path_for_close(path, uri)
        disk_source = loader.disk_source(disk_path) if disk_path && loader.disk_file?(disk_path)
        loader.delete_overlay(path)
        if disk_source
          @snapshots[path] = snapshot(uri, path, nil, disk_source, false, nil)
          if was_root
            analyzed = @analyzer.analyze(path)
            update_snapshot(path, analyzed)
            remove_root_state(path)
            [clear] + publish_paths((old_files + [path]).uniq)
          else
            [clear] + refresh(path)
          end
        else
          remove_path(path)
          [clear] + refresh_dependents(path)
        end
      end

      # @rbs (String path) -> snapshot?
      def snapshot_for(path)
        @snapshots[path]
      end

      # Preserve the URI spelling used to open a document; closed files use their canonical URI.
      # @rbs (String path) -> String
      def uri_for(path)
        entry = @snapshots[path]
        return entry.fetch(:uri) if entry&.fetch(:open)

        workspace.uri(path)
      end

      # @rbs (String path) -> Array[String]
      def files_for(path)
        roots = affected_roots(path)
        files = roots.flat_map { |root| @closures.fetch(root, [root]) }
        (files + [path]).uniq
      end

      # @rbs (String path) -> Array[Frontend::Resolution]
      def resolutions_for(path)
        affected_roots(path).filter_map { |root| @resolutions[root] }
      end

      # @rbs (String path) -> Array[String]
      def roots_for(path)
        affected_roots(path)
      end

      private

      # @rbs (String path) -> Array[publication]
      def refresh(path)
        old_files = files_for(path)
        previous_roots = affected_roots(path)
        was_root = @roots[path]
        analyzed = @analyzer.analyze(path)
        update_snapshot(path, analyzed)
        update_root_membership(path, analyzed.fetch(:document))
        remove_root_state(path) if was_root && !@roots[path]
        roots = (previous_roots + affected_roots(path)).uniq
        roots.delete(path) unless @roots[path]
        roots.each { |root| refresh_root(root) }
        publish_paths((old_files + files_for(path) + [path]).uniq)
      end

      # @rbs (String path) -> Array[publication]
      def refresh_dependents(path)
        roots = affected_roots(path)
        roots.each { |root| refresh_root(root) }
        publish_paths(roots.flat_map { |root| @closures.fetch(root, [root]) }.uniq)
      end

      # @rbs (String root) -> void
      def refresh_root(root)
        files, analyzed = @analyzer.closure(root)
        @closures[root] = files
        rebuild_reverse_dependencies
        analyzed.each { |path, result| update_snapshot(path, result, own_diagnostics: false) }
        parse_failed = analyzed.any? do |path, result|
          !result.fetch(:diagnostics).empty? && loader.file?(path)
        end
        resolution, errors = parse_failed ? [nil, []] : @analyzer.resolve(root)
        resolution ? @resolutions[root] = resolution : @resolutions.delete(root)
        replace_root_diagnostics(root, files, analyzed, errors)
      end

      # @rbs () -> void
      def rebuild_reverse_dependencies
        reverse = Hash.new { |hash, key| hash[key] = [] } #: Hash[String, Array[String]]
        @closures.each { |root, files| files.each { |file| reverse[file] << root } }
        @reverse_dependencies = reverse
      end

      # @rbs (String path) -> Array[String]
      def affected_roots(path)
        roots = @reverse_dependencies.fetch(path, empty_paths).dup
        roots << path if @roots[path]
        roots.uniq
      end

      # @rbs (String path, WorkspaceAnalyzer::analyzed_document analyzed, ?own_diagnostics: bool) -> void
      def update_snapshot(path, analyzed, own_diagnostics: true)
        current = @snapshots[path]
        uri = current&.fetch(:uri) || workspace.uri(path)
        version = current&.fetch(:version)
        open = current&.fetch(:open) || false
        source = open ? current.fetch(:source) : analyzed.fetch(:source)
        document = analyzed.fetch(:document)
        @snapshots[path] = snapshot(uri, path, version, source, open, document)
        @document_diagnostics[path] = analyzed.fetch(:diagnostics) if own_diagnostics
      end

      # @rbs (String path, Frontend::SourceDocument? document) -> void
      def update_root_membership(path, document)
        if document&.ast.is_a?(Frontend::AST::Root)
          @roots[path] = true
        else
          @roots.delete(path)
        end
      end

      # @rbs (Array[String] paths) -> Array[publication]
      def publish_paths(paths)
        paths.filter_map do |path|
          entry = @snapshots[path]
          next unless entry

          publication = {
            uri: entry.fetch(:uri),
            diagnostics: aggregated_diagnostics(path)
          } #: publication
          publication[:version] = entry.fetch(:version) if entry.fetch(:open) && entry.fetch(:version)
          publication
        end
      end

      # @rbs (String uri, String path, Integer? version, String source, bool open,
      #   Frontend::SourceDocument? document) -> snapshot
      def snapshot(uri, path, version, source, open, document)
        { uri: uri, path: path, version: version, source: source, open: open, document: document }
      end

      # @rbs (String path, String uri) -> snapshot
      def open_snapshot(path, uri)
        entry = @snapshots[path]
        return entry if entry&.fetch(:open) && entry.fetch(:uri) == uri

        raise ProtocolError.new("document is not open: #{uri}", code: -32_602)
      end

      # @rbs () -> Array[String]
      def empty_paths
        [] #: Array[String]
      end

      # @rbs (String path) -> void
      def remove_path(path)
        @snapshots.delete(path)
        @document_diagnostics.delete(path)
        remove_root_state(path)
      end

      # @rbs (String path) -> void
      def remove_root_state(path)
        @roots.delete(path)
        @closures.delete(path)
        @resolutions.delete(path)
        @root_diagnostics.delete(path)
        rebuild_reverse_dependencies
      end
    end
  end
end
