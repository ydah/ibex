# frozen_string_literal: true

module Ibex
  module LSP
    # Builds source occurrences and hover metadata from lossless frontend documents.
    class SymbolIndexBuilder
      include SymbolIndexSourceQueries
      include SymbolIndexPrecedenceReferences

      # @rbs (DocumentStore store, Array[String] files) -> void
      def initialize(store, files)
        @store = store
        @files = files
        @occurrences = [] #: Array[SymbolOccurrence]
        @documents = {} #: Hash[String, Frontend::SourceDocument]
        @global_kinds = {} #: Hash[String, Symbol]
        @rule_data = {} #: Hash[String, symbol_data]
        @terminal_data = Hash.new { |hash, key| hash[key] = {} } #: Hash[String, symbol_data]
      end

      # @rbs () -> [Array[SymbolOccurrence], Hash[String, Frontend::SourceDocument]]
      def build
        collect_documents
        # Definitions from every closure file must exist before references are classified.
        # rubocop:disable Style/CombinableLoops
        @documents.each { |path, document| collect_definitions(path, document) }
        @documents.each { |path, document| collect_references(path, document) }
        # rubocop:enable Style/CombinableLoops
        [@occurrences.freeze, @documents.freeze]
      end

      private

      # @rbs () -> void
      def collect_documents
        @files.each do |path|
          snapshot = @store.snapshot_for(path)
          document = snapshot&.fetch(:document)
          @documents[path] = document if document
        end
      end

      # @rbs (String path, Frontend::SourceDocument document) -> void
      def collect_definitions(path, document)
        ast = document.ast
        return unless ast

        declarations = ast.declarations
        declarations.each_with_index do |declaration, index|
          following = declarations[index + 1]&.loc || ast.rules.first&.loc
          collect_declaration(path, document, declaration, following)
        end
        ast.rules.each { |rule| collect_rule_definition(path, document, rule) }
      end

      # @rbs (String path, Frontend::SourceDocument document, Frontend::AST::declaration declaration,
      #   Frontend::Location? following) -> void
      def collect_declaration(path, document, declaration, following)
        tokens = tokens_between(document, declaration.loc, following)
        case declaration
        when Frontend::AST::Tokens
          add_named_tokens(path, tokens.drop(1), declaration.names, :terminal, :definition)
        when Frontend::AST::DisplayName
          @terminal_data[declaration.name][:display] = declaration.value
        when Frontend::AST::SemanticType
          @terminal_data[declaration.name][:type] = declaration.value
        when Frontend::AST::Precedence
          collect_precedence(declaration)
        when Frontend::AST::Include
          collect_include(path, tokens, declaration)
        end
      end

      # @rbs (Frontend::AST::Precedence declaration) -> void
      def collect_precedence(declaration)
        declaration.levels.each_with_index do |level, index|
          level.symbols.each do |name|
            @terminal_data[name][:precedence] = {
              direction: declaration.direction, associativity: level.associativity, level: index
            }
          end
        end
      end

      # @rbs (String path, Array[Frontend::Token] tokens, Frontend::AST::Include declaration) -> void
      def collect_include(path, tokens, declaration)
        token = tokens.find { |candidate| candidate.type == :literal }
        span = token&.span
        return unless span

        target = canonical_include_target(declaration)
        return unless target

        add_occurrence(
          name: declaration.path, kind: :include, role: :reference, key: [:include, target],
          path: path, span: span, data: { target: target }
        )
      end

      # @rbs (String path, Frontend::SourceDocument document, Frontend::AST::Rule rule) -> void
      def collect_rule_definition(path, document, rule)
        token = token_at(document, rule.loc, rule.lhs)
        span = token&.span
        return unless span

        lhs_token = token #: Frontend::Token

        @global_kinds[rule.lhs] ||= :rule
        signature = "#{rule.lhs}#{parameter_signature(rule.parameters)}"
        signature = "%inline #{signature}" if rule.inline
        data = {
          signature: signature,
          documentation: rule.documentation,
          inline: rule.inline,
          parameters: rule.parameters
        }
        @rule_data[rule.lhs] ||= data
        add_occurrence(
          name: rule.lhs, kind: :rule, role: :definition, key: global_key(rule.lhs),
          path: path, span: span, data: data
        )
        collect_parameters(path, document, rule, lhs_token)
      end

      # @rbs (String path, Frontend::SourceDocument document, Frontend::AST::Rule rule,
      #   Frontend::Token lhs_token) -> void
      def collect_parameters(path, document, rule, lhs_token)
        return if rule.parameters.empty?

        rule_id = lhs_token.span&.start_byte || 0
        rule.parameters.zip(parameter_tokens(document, lhs_token)).each do |parameter, token|
          span = token&.span
          next unless span

          add_occurrence(
            name: parameter, kind: :parameter, role: :definition,
            key: parameter_key(path, rule_id, parameter), path: path, span: span,
            data: { rule: rule.lhs }
          )
        end
      end

      # @rbs (String path, Frontend::SourceDocument document) -> void
      def collect_references(path, document)
        ast = document.ast
        return unless ast

        ast.declarations.each_with_index do |declaration, index|
          following = ast.declarations[index + 1]&.loc || ast.rules.first&.loc
          collect_declaration_references(path, document, declaration, following)
        end
        ast.rules.each_with_index do |rule, index|
          collect_rule_references(path, document, rule, ast.rules[index + 1]&.loc)
        end
      end

      # @rbs (String path, Frontend::SourceDocument document, Frontend::AST::declaration declaration,
      #   Frontend::Location? following) -> void
      def collect_declaration_references(path, document, declaration, following)
        names = declaration_reference_names(declaration)
        return if names.empty?

        remaining = tokens_between(document, declaration.loc, following).drop(1)
        names.each do |name|
          index = remaining.index { |token| token.value == name }
          token = index && remaining.delete_at(index)
          add_global_reference(path, token, name) if token
        end
      end

      # @rbs (String path, Frontend::SourceDocument document, Frontend::AST::Rule rule,
      #   Frontend::Location? following_rule) -> void
      def collect_rule_references(path, document, rule, following_rule)
        definition = token_at(document, rule.loc, rule.lhs)
        rule_id = definition&.span&.start_byte || 0
        rule.alternatives.each_with_index do |alternative, index|
          alternative.items.each { |item| collect_item(path, document, item, rule, rule_id) }
          following = rule.alternatives[index + 1]&.loc || following_rule
          collect_alternative_precedence(path, document, alternative, following, rule, rule_id)
        end
      end

      # @rbs (String path, Frontend::SourceDocument document, Frontend::AST::item item,
      #   Frontend::AST::Rule rule, Integer rule_id) -> void
      def collect_item(path, document, item, rule, rule_id)
        case item
        when Frontend::AST::SymbolReference, Frontend::AST::ParameterizedReference
          collect_named_item(path, document, item, rule, rule_id)
          item.arguments.each { |child| collect_item(path, document, child, rule, rule_id) } if
            item.is_a?(Frontend::AST::ParameterizedReference)
        when Frontend::AST::Optional, Frontend::AST::Star, Frontend::AST::Plus
          collect_item(path, document, item.item, rule, rule_id)
        when Frontend::AST::Group
          item.alternatives.flatten.each { |child| collect_item(path, document, child, rule, rule_id) }
        when Frontend::AST::SeparatedList
          collect_item(path, document, item.item, rule, rule_id)
          collect_item(path, document, item.separator, rule, rule_id)
        end
      end

      # @rbs (String path, Frontend::SourceDocument document,
      #   Frontend::AST::SymbolReference | Frontend::AST::ParameterizedReference item,
      #   Frontend::AST::Rule rule, Integer rule_id) -> void
      def collect_named_item(path, document, item, rule, rule_id)
        token = token_at(document, item.loc, item.name)
        return unless token&.span

        add_rule_reference(path, token, item.name, rule, rule_id)
      end

      # @rbs (String path, Frontend::Token token, String name) -> void
      def add_global_reference(path, token, name)
        span = token.span
        return unless span

        kind = @global_kinds[name] || :terminal
        data = symbol_data(kind, name)
        add_occurrence(name: name, kind: kind, role: :reference, key: global_key(name),
                       path: path, span: span, data: data)
      end

      # @rbs (Symbol kind, String name) -> symbol_data
      def symbol_data(kind, name)
        data = kind == :rule ? @rule_data[name] : @terminal_data[name]
        empty = {} #: symbol_data
        data || empty
      end

      # @rbs (String path, Array[Frontend::Token] tokens, Array[String] names, Symbol kind, Symbol role) -> void
      def add_named_tokens(path, tokens, names, kind, role)
        remaining = tokens.dup
        names.each do |name|
          index = remaining.index { |token| token.value == name }
          token = index && remaining.delete_at(index)
          span = token&.span
          next unless span

          @global_kinds[name] ||= kind
          add_occurrence(name: name, kind: kind, role: role, key: global_key(name),
                         path: path, span: span, data: @terminal_data[name])
        end
      end

      # @rbs (name: String, kind: Symbol, role: Symbol, key: symbol_key, path: String,
      #   span: Frontend::SourceSpan, data: symbol_data) -> void
      def add_occurrence(name:, kind:, role:, key:, path:, span:, data:)
        @occurrences << SymbolOccurrence.new(
          name: name, kind: kind, role: role, key: key, path: path, span: span, data: data
        )
      end

      # @rbs (String name) -> symbol_key
      def global_key(name)
        [:symbol, name]
      end

      # @rbs (String path, Integer rule_id, String name) -> symbol_key
      def parameter_key(path, rule_id, name)
        [:parameter, path, rule_id, name]
      end

      # @rbs (Array[String] parameters) -> String
      def parameter_signature(parameters)
        parameters.empty? ? "" : "(#{parameters.join(', ')})"
      end

      # @rbs (Frontend::AST::Include declaration) -> String?
      def canonical_include_target(declaration)
        candidate = File.expand_path(declaration.path, File.dirname(declaration.loc.file))
        target = @store.loader.canonical_path(candidate, allow_missing: true)
        @store.workspace.root_for(target) && target
      rescue SystemCallError
        nil
      end
    end
  end
end
