# frozen_string_literal: true

module Ibex
  module LSP
    # Answers source navigation and guarded workspace rename operations.
    class SymbolIndex
      IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/ #: Regexp
      RESERVED = %w[
        class fragment include token prechigh preclow left right nonassoc options expect start
        convert display type pragma extended rule end separated_list separated_nonempty_list
      ].freeze #: Array[String]

      # @rbs (DocumentStore store, String path) -> void
      def initialize(store, path)
        @store = store
        @path = path
        files = store.files_for(path)
        @occurrences, @documents = SymbolIndexBuilder.new(store, files).build
        @snapshot_state = files.to_h do |file|
          snapshot = store.snapshot_for(file)
          [file, snapshot && [snapshot.fetch(:version), snapshot.fetch(:source)]]
        end #: Hash[String, Array[untyped]?]
      end

      # @rbs (String path, Hash[String, untyped] position) -> Array[Hash[String, untyped]]
      def definition(path, position)
        occurrence = occurrence_at(path, position)
        return [] unless occurrence
        return [include_target_location(occurrence)] if occurrence.kind == :include

        matching(occurrence.key, role: :definition).map { |entry| location(entry) }
      end

      # @rbs (String path, Hash[String, untyped] position, ?include_declaration: bool) ->
      #   Array[Hash[String, untyped]]
      def references(path, position, include_declaration: false)
        occurrence = occurrence_at(path, position)
        return [] unless occurrence

        entries = matching(occurrence.key)
        entries = entries.reject { |entry| entry.role == :definition } unless include_declaration
        entries.map { |entry| location(entry) }
      end

      # @rbs (String path, Hash[String, untyped] position) -> Hash[String, untyped]?
      def prepare_rename(path, position)
        occurrence = renameable_occurrence(path, position)
        { "range" => range(occurrence), "placeholder" => occurrence.name }
      end

      # @rbs (String path, Hash[String, untyped] position, String new_name) -> Hash[String, untyped]
      def rename(path, position, new_name)
        ensure_fresh!
        occurrence = renameable_occurrence(path, position)
        validate_new_name(occurrence, new_name)
        entries = matching(occurrence.key)
        validate_unshared(entries)
        validate_nonoverlapping(entries)
        changes = entries.group_by(&:path).transform_values do |path_entries|
          path_entries.sort_by { |entry| entry.span.start_byte }.map do |entry|
            { "range" => range(entry), "newText" => new_name }
          end
        end
        replacements = changed_sources(entries, new_name)
        unless @store.valid_replacements?(replacements)
          raise ProtocolError.new("rename would make the affected grammar closure invalid", code: -32_602)
        end

        document_changes = changes.sort.map do |changed_path, edits|
          snapshot = @store.snapshot_for(changed_path)
          version = snapshot&.fetch(:open) ? snapshot.fetch(:version) : nil
          {
            "textDocument" => { "uri" => @store.uri_for(changed_path), "version" => version },
            "edits" => edits
          }
        end
        { "documentChanges" => document_changes }
      end

      # @rbs (String path, Hash[String, untyped] position) -> Hash[String, untyped]?
      def hover(path, position)
        occurrence = occurrence_at(path, position)
        return unless occurrence

        value = hover_value(occurrence)
        return unless value

        {
          "contents" => { "kind" => "markdown", "value" => value },
          "range" => range(occurrence)
        }
      end

      private

      # @rbs (String path, Hash[String, untyped] position) -> SymbolOccurrence?
      def occurrence_at(path, position)
        document = @documents[path]
        return unless document

        offset = PositionCodec.new(document.source).byte_offset(position)
        candidates = @occurrences.select do |entry|
          entry.path == path && entry.span.start_byte <= offset && offset < entry.span.end_byte
        end
        candidates.min_by { |entry| entry.span.length }
      end

      # @rbs (Array[untyped] key, ?role: Symbol?) -> Array[SymbolOccurrence]
      def matching(key, role: nil)
        @occurrences.select { |entry| entry.key == key && (!role || entry.role == role) }
      end

      # @rbs (SymbolOccurrence occurrence) -> Hash[String, untyped]
      def location(occurrence)
        { "uri" => @store.uri_for(occurrence.path), "range" => range(occurrence) }
      end

      # @rbs (SymbolOccurrence occurrence) -> Hash[String, untyped]
      def include_target_location(occurrence)
        target = occurrence.data.fetch(:target)
        point = { "line" => 0, "character" => 0 }
        { "uri" => @store.uri_for(target), "range" => { "start" => point, "end" => point.dup } }
      end

      # @rbs (SymbolOccurrence occurrence) -> Hash[String, Hash[String, Integer]]
      def range(occurrence)
        document = @documents.fetch(occurrence.path)
        PositionCodec.new(document.source).range(occurrence.span)
      end

      # @rbs (String path, Hash[String, untyped] position) -> SymbolOccurrence
      def renameable_occurrence(path, position)
        occurrence = occurrence_at(path, position)
        unless occurrence && %i[rule terminal parameter].include?(occurrence.kind) &&
               occurrence.name.match?(IDENTIFIER) && !RESERVED.include?(occurrence.name)
          raise ProtocolError.new("symbol at position cannot be renamed", code: -32_602)
        end
        unless matching(occurrence.key, role: :definition).any?
          raise ProtocolError.new("unresolved symbol cannot be renamed", code: -32_602)
        end

        occurrence
      end

      # @rbs (SymbolOccurrence occurrence, String new_name) -> void
      def validate_new_name(occurrence, new_name)
        unless new_name.is_a?(String) && new_name.match?(IDENTIFIER) && !RESERVED.include?(new_name)
          raise ProtocolError.new("new name must be a non-reserved grammar identifier", code: -32_602)
        end

        collision = @occurrences.any? do |entry|
          entry.role == :definition && entry.name == new_name && entry.key != occurrence.key &&
            collision_scope?(entry, occurrence)
        end
        raise ProtocolError.new("rename collides with existing symbol #{new_name}", code: -32_602) if collision
      end

      # @rbs (SymbolOccurrence candidate, SymbolOccurrence occurrence) -> bool
      def collision_scope?(candidate, occurrence)
        return candidate.key.take(3) == occurrence.key.take(3) if occurrence.kind == :parameter

        candidate.kind != :parameter
      end

      # @rbs (Array[SymbolOccurrence] entries) -> void
      def validate_nonoverlapping(entries)
        entries.group_by(&:path).each_value do |path_entries|
          ordered = path_entries.sort_by { |entry| [entry.span.start_byte, entry.span.end_byte] }
          overlap = (1...ordered.length).any? do |index|
            ordered.fetch(index - 1).span.end_byte > ordered.fetch(index).span.start_byte
          end
          raise ProtocolError.new("rename contains overlapping source edits", code: -32_603) if overlap
        end
      end

      # @rbs (Array[SymbolOccurrence] entries) -> void
      def validate_unshared(entries)
        return unless entries.any? { |entry| @store.roots_for(entry.path).length > 1 }

        raise ProtocolError.new("rename affecting a fragment shared by multiple roots is ambiguous", code: -32_602)
      end

      # @rbs () -> void
      def ensure_fresh!
        stale = @snapshot_state.any? do |path, expected|
          snapshot = @store.snapshot_for(path)
          actual = snapshot && [snapshot.fetch(:version), snapshot.fetch(:source)]
          actual != expected
        end
        raise ProtocolError.new("symbol snapshot is stale; retry the request", code: -32_602) if stale
      end

      # @rbs (Array[SymbolOccurrence] entries, String new_name) -> Hash[String, String]
      def changed_sources(entries, new_name)
        entries.group_by(&:path).to_h do |path, path_entries|
          document = @documents.fetch(path)
          source = document.source.dup
          path_entries.sort_by { |entry| -entry.span.start_byte }.each do |entry|
            prefix = source.byteslice(0, entry.span.start_byte) || ""
            suffix = source.byteslice(entry.span.end_byte, source.bytesize - entry.span.end_byte) || ""
            source = prefix + new_name + suffix
          end
          [path, source]
        end
      end

      # @rbs (SymbolOccurrence occurrence) -> String?
      def hover_value(occurrence)
        case occurrence.kind
        when :rule then rule_hover(occurrence)
        when :terminal then terminal_hover(occurrence)
        when :parameter then "`#{occurrence.name}` — formal parameter of `#{occurrence.data[:rule]}`"
        when :include then "Includes `#{occurrence.data[:target]}`"
        end
      end

      # @rbs (SymbolOccurrence occurrence) -> String
      def rule_hover(occurrence)
        definition = matching(occurrence.key, role: :definition).first
        data = definition&.data || occurrence.data
        lines = ["```ibex", data[:signature] || occurrence.name, "```"]
        lines << data[:documentation] if data[:documentation]
        lines.join("\n")
      end

      # @rbs (SymbolOccurrence occurrence) -> String
      def terminal_hover(occurrence)
        definition = matching(occurrence.key, role: :definition).first
        data = definition&.data || occurrence.data
        lines = ["`#{occurrence.name}` — terminal"]
        lines << "Display: #{data[:display]}" if data[:display]
        lines << "Type: `#{data[:type]}`" if data[:type]
        if (precedence = data[:precedence])
          lines << "Precedence: #{precedence[:associativity]} level #{precedence[:level]}"
        end
        lines.join("\n\n")
      end
    end
  end
end
