# frozen_string_literal: true

module Ibex
  module Frontend
    # Deterministically formats grammar trivia and rejects any semantic change.
    # rubocop:disable Metrics/ClassLength -- token layout policy stays together so adjacency rules remain auditable.
    class Formatter
      DECLARATION_STARTS = %i[
        PRAGMA INCLUDE TOKEN PRECHIGH PRECLOW OPTIONS EXPECT START CONVERT DISPLAY TYPE RULE
      ].freeze #: Array[Symbol]
      ASSOCIATIONS = %i[LEFT RIGHT NONASSOC].freeze #: Array[Symbol]
      CALLABLES = %i[LHS PARAMETERIZED_REFERENCE SEPARATED_LIST SEPARATED_NONEMPTY_LIST].freeze #: Array[Symbol]
      SUFFIXES = %w[? * +].freeze #: Array[String]
      CLOSERS = %w[) , ;].freeze #: Array[String]
      ADJACENT_AFTER = ["::", "("].freeze #: Array[String]

      # @rbs!
      #   type formatter_element = {
      #     segment: Segment,
      #     external: external_token?,
      #     role: Symbol?,
      #     gap: Array[Segment]
      #   }

      # @rbs (String source, ?file: String, ?mode: Symbol) -> String
      def self.format(source, file: "(grammar)", mode: :racc)
        new(mode: mode).format(source, file: file)
      end

      # @rbs (?mode: Symbol) -> void
      def initialize(mode: :racc)
        raise ArgumentError, "mode must be :racc or :extended" unless %i[racc extended].include?(mode)

        @mode = mode
      end

      # @rbs (String source, ?file: String) -> String
      def format(source, file: "(grammar)")
        document = Parser.new(source, file: file, mode: @mode).parse_source_document
        formatted = render(document)
        reparsed = Parser.new(formatted, file: file, mode: @mode).parse_source_document
        unless same_semantic_projection?(document.ast, reparsed.ast)
          raise Ibex::Error, "#{file}: formatting would change grammar semantics"
        end

        formatted
      rescue Ibex::Error
        raise
      rescue StandardError => e
        raise Ibex::Error, "#{file}: formatting failed: #{e.message}"
      end

      private

      # @rbs (SourceDocument document) -> String
      def render(document)
        @default_newline = document.source.match(/\r\n|\n/)&.[](0) || "\n"
        elements = build_elements(document)
        output = +""
        previous = nil #: formatter_element?
        elements.each do |current|
          output << separator(previous, current)
          output << current.fetch(:segment).text
          previous = current
        end
        output
      end

      # @rbs (SourceDocument document) -> Array[formatter_element]
      def build_elements(document)
        external_types = external_types(document.tokens)
        pending = [] #: Array[Segment]
        elements = document.cst.each_with_object([]) do |segment, result|
          if %i[whitespace newline].include?(segment.kind)
            pending << segment
            next
          end

          result << {
            segment: segment,
            external: segment.token_index && external_types[segment.token_index],
            role: nil,
            gap: pending
          }
          pending = []
        end
        annotate_roles(elements)
        elements
      end

      # @rbs (Array[Token] tokens) -> Hash[Integer, external_token]
      def external_types(tokens)
        adapter = TokenAdapter.new(tokens, extended: @mode == :extended)
        types = {} #: Hash[Integer, external_token]
        index = 0
        while (classified = adapter.next_token)
          types[index] = classified.fetch(0)
          index += 1
        end
        types
      end

      # @rbs (Array[formatter_element] elements) -> void
      def annotate_roles(elements)
        state = {
          section: :declarations, precedence_closer: nil, conversion: false,
          conversion_name: true, depth: 0, rule_colon: false
        } #: Hash[Symbol, untyped]
        elements.each do |element|
          external = element.fetch(:external)
          next unless external

          element[:role] = token_role(external, state)
          advance_role_state(external, element.fetch(:role), state)
        end
        annotate_comment_indentation(elements)
      end

      # @rbs (Array[formatter_element] elements) -> void
      def annotate_comment_indentation(elements)
        following_role = nil #: Symbol?
        elements.reverse_each do |element|
          segment = element.fetch(:segment)
          if comment?(segment)
            element[:role] = :rule_comment if following_role == :rule_start
            element[:role] = :alternative_comment if following_role == :alternative
          elsif element.fetch(:external)
            following_role = element.fetch(:role)
          end
        end
      end

      # @rbs (external_token external, Hash[Symbol, untyped] state) -> Symbol?
      def token_role(external, state)
        document_role = document_token_role(external, state)
        return document_role if document_role

        rule_token_role(external, state)
      end

      # @rbs (external_token external, Hash[Symbol, untyped] state) -> Symbol?
      def document_token_role(external, state)
        return :user_code if external == :USER_CODE
        return precedence_role(external, state) if %i[PRECHIGH PRECLOW].include?(external)
        return :precedence_level if ASSOCIATIONS.include?(external) && state[:precedence_closer]
        return section_end_role(state) if external == :END
        return :conversion_entry if state.fetch(:conversion) && state.fetch(:conversion_name)
        return :rule_keyword if external == :RULE
        return :declaration if DECLARATION_STARTS.include?(external)

        nil
      end

      # @rbs (Hash[Symbol, untyped] state) -> Symbol?
      def section_end_role(state)
        return :conversion_end if state.fetch(:conversion)
        return :grammar_end if state.fetch(:section) == :rules

        nil
      end

      # @rbs (external_token external, Hash[Symbol, untyped] state) -> Symbol?
      def rule_token_role(external, state)
        return :rule_start if external == :INLINE && state.fetch(:section) == :rules
        return :rule_start if external == :LHS
        return :alternative if external == "|" && state.fetch(:section) == :rules && state.fetch(:depth).zero?

        if external == ":"
          return :rule_colon if state.fetch(:rule_colon) && state.fetch(:depth).zero?

          return :named_reference
        end

        nil
      end

      # @rbs (external_token external, Hash[Symbol, untyped] state) -> Symbol
      def precedence_role(external, state)
        return :precedence_end if state[:precedence_closer] == external

        :declaration
      end

      # @rbs (external_token external, Symbol? role, Hash[Symbol, untyped] state) -> void
      def advance_role_state(external, role, state)
        advance_precedence_state(external, role, state)
        advance_conversion_state(external, role, state)
        advance_rule_state(external, role, state)
      end

      # @rbs (external_token external, Symbol? role, Hash[Symbol, untyped] state) -> void
      def advance_precedence_state(external, role, state)
        if role == :declaration && %i[PRECHIGH PRECLOW].include?(external)
          state[:precedence_closer] = external == :PRECHIGH ? :PRECLOW : :PRECHIGH
        elsif role == :precedence_end
          state[:precedence_closer] = nil
        end
      end

      # @rbs (external_token external, Symbol? role, Hash[Symbol, untyped] state) -> void
      def advance_conversion_state(external, role, state)
        if external == :CONVERT
          state[:conversion] = true
          state[:conversion_name] = true
        elsif role == :conversion_end
          state[:conversion] = false
        elsif state.fetch(:conversion) && role == :conversion_entry
          state[:conversion_name] = false
        elsif state.fetch(:conversion) && !state.fetch(:conversion_name)
          state[:conversion_name] = true
        end
      end

      # @rbs (external_token external, Symbol? role, Hash[Symbol, untyped] state) -> void
      def advance_rule_state(external, role, state)
        state[:section] = :rules if external == :RULE
        state[:rule_colon] = true if external == :LHS
        state[:rule_colon] = false if role == :rule_colon
        state[:depth] += 1 if external == "("
        state[:depth] -= 1 if external == ")"
      end

      # @rbs (formatter_element? previous, formatter_element current) -> String
      def separator(previous, current)
        gap = current.fetch(:gap)
        return leading_separator(current, gap) unless previous

        previous_segment = previous.fetch(:segment)
        current_segment = current.fetch(:segment)
        return "" if direct_opaque_pair?(previous_segment, current_segment)
        return trailing_separator(previous, gap) if current_segment.kind == :eof
        return comment_separator(previous, current, gap) if comment?(previous_segment) || comment?(current_segment)

        kind = separator_kind(previous, current)
        render_separator(kind, gap, indentation(current))
      end

      # @rbs (formatter_element current, Array[Segment] gap) -> String
      def leading_separator(current, gap)
        return "" unless newline_in?(gap)

        render_separator(:line, gap, indentation(current))
      end

      # @rbs (formatter_element previous, Array[Segment] gap) -> String
      def trailing_separator(previous, gap)
        segment = previous.fetch(:segment)
        return "" if segment.kind == :user_code_body
        return render_separator(:line, gap, 0) if previous.fetch(:role) == :grammar_end

        render_separator(gap.any? { |item| item.kind == :newline } ? :line : :none, gap, 0)
      end

      # @rbs (Segment previous, Segment current) -> bool
      def direct_opaque_pair?(previous, current)
        (previous.kind == :user_code_marker && current.kind == :user_code_body) ||
          (previous.kind == :user_code_body && current.kind == :user_code_marker)
      end

      # @rbs (Segment segment) -> bool
      def comment?(segment)
        %i[line_comment block_comment].include?(segment.kind)
      end

      # @rbs (formatter_element previous, formatter_element current, Array[Segment] gap) -> String
      def comment_separator(previous, current, gap)
        previous_segment = previous.fetch(:segment)
        current_segment = current.fetch(:segment)
        if text_ends_with_newline?(previous_segment.text)
          newlines = gap.select { |segment| segment.kind == :newline }.map(&:text)
          return newlines.join + (" " * indentation(current))
        end
        if previous_segment.kind == :line_comment || newline_in?(gap)
          return render_separator(:line, gap, indentation(current))
        end
        return " " if current_segment.kind == :line_comment || previous_segment.kind == :block_comment ||
                      current_segment.kind == :block_comment

        render_separator(:space, gap, indentation(current))
      end

      # @rbs (formatter_element previous, formatter_element current) -> Symbol
      def separator_kind(previous, current)
        previous_external = previous.fetch(:external)
        current_external = current.fetch(:external)
        previous_role = previous.fetch(:role)
        current_role = current.fetch(:role)

        return :line if line_boundary?(previous_role, current_role, previous, current)
        return :none if adjacent_tokens?(previous_external, current_external, previous_role, current_role)

        :space
      end

      # @rbs (external_token? previous_external, external_token? current_external,
      #   Symbol? previous_role, Symbol? current_role) -> bool
      def adjacent_tokens?(previous_external, current_external, previous_role, current_role)
        return true if current_role == :named_reference || previous_role == :named_reference
        return true if current_external == "::"
        return true if CLOSERS.include?(current_external) || SUFFIXES.include?(current_external)
        return true if ADJACENT_AFTER.include?(previous_external)

        current_external == "(" && CALLABLES.include?(previous_external)
      end

      # @rbs (Symbol? previous_role, Symbol? current_role, formatter_element previous,
      #   formatter_element current) -> bool
      def line_boundary?(previous_role, current_role, previous, current)
        return false if current_role == :rule_start && previous.fetch(:external) == :INLINE

        return true if %i[declaration rule_keyword precedence_level precedence_end conversion_entry
                          conversion_end rule_start alternative grammar_end user_code].include?(current_role)
        return true if previous_role == :rule_keyword
        return false unless current.fetch(:segment).kind == :user_code_marker

        previous.fetch(:segment).kind != :user_code_body
      end

      # @rbs (formatter_element element) -> Integer
      def indentation(element)
        case element.fetch(:role)
        when :rule_start, :precedence_level, :conversion_entry, :rule_comment then 2
        when :alternative, :alternative_comment then 4
        else 0
        end
      end

      # @rbs (Symbol kind, Array[Segment] gap, Integer indentation) -> String
      def render_separator(kind, gap, indentation)
        return "" if kind == :none
        return " " if kind == :space

        newlines = gap.select { |segment| segment.kind == :newline }.map(&:text)
        newlines = [@default_newline] if newlines.empty?
        newlines.join + (" " * indentation)
      end

      # @rbs (Array[Segment] gap) -> bool
      def newline_in?(gap)
        gap.any? { |segment| segment.kind == :newline }
      end

      # @rbs (String text) -> bool
      def text_ends_with_newline?(text)
        text.end_with?("\n")
      end

      # @rbs (untyped left, untyped right) -> bool
      def same_semantic_projection?(left, right)
        pending = [[left, right]] #: Array[[untyped, untyped]]
        until pending.empty?
          pair = pending.pop
          next unless pair

          left_value, right_value = pair
          next if left_value.equal?(right_value)
          return false unless comparable_semantic_values?(left_value, right_value)

          append_semantic_children(pending, left_value, right_value)
        end
        true
      end

      # @rbs (untyped left, untyped right) -> bool
      def comparable_semantic_values?(left, right)
        return left.instance_of?(right.class) && left.members == right.members if left.is_a?(Struct)
        return right.is_a?(Array) && left.length == right.length if left.is_a?(Array)
        return comparable_semantic_hashes?(left, right) if left.is_a?(Hash)

        left == right
      end

      # @rbs (Hash[untyped, untyped] left, untyped right) -> bool
      def comparable_semantic_hashes?(left, right)
        return false unless right.is_a?(Hash)

        left_keys = semantic_keys(left)
        right_keys = semantic_keys(right)
        left_keys.length == right_keys.length && left_keys.all? { |key| right_keys.include?(key) }
      end

      # @rbs (Array[[untyped, untyped]] pending, untyped left, untyped right) -> void
      def append_semantic_children(pending, left, right)
        case left
        when Struct
          semantic_members(left).reverse_each { |member| pending << [left[member], right[member]] }
        when Array
          left.each_index.reverse_each { |index| pending << [left[index], right[index]] }
        when Hash
          semantic_keys(left).reverse_each { |key| pending << [left[key], right[key]] }
        end
      end

      # @rbs (Struct[untyped] value) -> Array[Symbol]
      def semantic_members(value)
        value.members.reject { |member| %i[loc span].include?(member) }
      end

      # @rbs (Hash[untyped, untyped] value) -> Array[untyped]
      def semantic_keys(value)
        value.keys.reject { |key| %i[loc span].include?(key) }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
