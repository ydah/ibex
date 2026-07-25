# frozen_string_literal: true

module Ibex
  module Frontend
    # An immutable lexical unit or trivia slice in a concrete syntax tree.
    class Segment
      TRIVIA_KINDS = %i[whitespace newline line_comment block_comment].freeze #: Array[Symbol]
      OPAQUE_KINDS = %i[action user_code_body].freeze #: Array[Symbol]

      attr_reader :kind #: Symbol
      attr_reader :span #: SourceSpan
      attr_reader :text #: String
      attr_reader :token_type #: Symbol?
      attr_reader :token_index #: Integer?

      # @rbs (kind: Symbol, span: SourceSpan, text: String, ?token_type: Symbol?,
      #   ?token_index: Integer?) -> void
      def initialize(kind:, span:, text:, token_type: nil, token_index: nil)
        raise ArgumentError, "segment text does not match its span" unless text.bytesize == span.length

        @kind = kind
        @span = span
        @text = text.dup.freeze
        @token_type = token_type
        @token_index = token_index
        freeze
      end

      # @rbs () -> bool
      def trivia?
        TRIVIA_KINDS.include?(kind)
      end

      # @rbs () -> bool
      def opaque?
        OPAQUE_KINDS.include?(kind)
      end

      # @rbs () -> bool
      def token?
        !token_index.nil?
      end

      # @rbs () -> String
      def render
        text
      end
    end

    module CST
      # The immutable lexical root of a grammar source document.
      class Document
        # @rbs! include Enumerable[Segment]
        # @rbs skip
        include Enumerable

        attr_reader :segments #: Array[Segment]

        # @rbs (Array[Segment] segments) -> void
        def initialize(segments)
          validate_contiguous(segments)
          @segments = segments.dup.freeze
          freeze
        end

        # @rbs!
        #   def each: () -> Enumerator[Segment, Document]
        #           | () { (Segment) -> void } -> Document
        # @rbs skip
        def each(&block)
          return enum_for(:each) unless block

          segments.each(&block)
          self
        end

        # @rbs () -> String
        def render
          segments.map(&:render).join
        end

        private

        # @rbs (Array[Segment] segments) -> void
        def validate_contiguous(segments)
          segments.each_cons(2) do |left, right|
            next unless left && right
            next if left.span.end_byte == right.span.start_byte

            raise ArgumentError, "concrete syntax tree segments must be contiguous"
          end
        end
      end
    end

    # Lossless grammar source plus its semantic parse and lexical concrete syntax tree.
    class SourceDocument
      attr_reader :source #: String
      attr_reader :file #: String
      attr_reader :tokens #: Array[Token]
      attr_reader :cst #: CST::Document
      attr_reader :ast #: AST::Root?

      # @rbs (source: String, file: String, tokens: Array[Token], cst: CST::Document,
      #   ?ast: AST::Root?) -> void
      def initialize(source:, file:, tokens:, cst:, ast: nil)
        @source = SourceEncoding.validated_utf8(source, file)
        @file = file.dup.freeze
        @tokens = tokens.dup.freeze
        @cst = cst
        @ast = ast
        @line_starts = build_line_starts.freeze #: Array[Integer]
        validate_render
        freeze
      end

      # @rbs () -> String
      def render
        cst.render
      end

      # @rbs (SourceSpan span) -> String
      def slice(span)
        validate_span(span)
        source.byteslice(span.start_byte, span.length) || ""
      end

      # @rbs (Integer byte_offset) -> SourcePosition
      def position_at(byte_offset)
        validate_byte_offset(byte_offset)
        prefix = source.byteslice(0, byte_offset) || ""
        raise ArgumentError, "byte offset must be on a UTF-8 character boundary" unless prefix.valid_encoding?

        line_index = (@line_starts.bsearch_index { |start| start > byte_offset } || @line_starts.length) - 1
        line_start = @line_starts.fetch(line_index)
        line_prefix = source.byteslice(line_start, byte_offset - line_start) || ""
        SourcePosition.new(byte_offset: byte_offset, line: line_index + 1, column: line_prefix.length + 1)
      end

      # @rbs (Integer line, Integer column) -> Integer
      def byte_offset_at(line, column)
        raise ArgumentError, "line and column must be positive" unless line.positive? && column.positive?

        line_start = @line_starts[line - 1]
        raise ArgumentError, "line is outside the source" unless line_start

        line_end = @line_starts[line] || source.bytesize
        line_text = source.byteslice(line_start, line_end - line_start) || ""
        line_text = line_text.delete_suffix("\n")
        character_count = column - 1
        raise ArgumentError, "column is outside the source line" if character_count > line_text.length

        line_start + line_text.each_char.take(character_count).join.bytesize
      end

      # @rbs (Integer start_byte, Integer end_byte) -> SourceSpan
      def span(start_byte, end_byte)
        SourceSpan.new(file: file, start: position_at(start_byte), finish: position_at(end_byte))
      end

      # @rbs (Segment segment) -> Token?
      def token_for(segment)
        index = segment.token_index
        index && tokens[index]
      end

      # @rbs (AST::Root ast) -> SourceDocument
      def with_ast(ast)
        self.class.new(source: source, file: file, tokens: tokens, cst: cst, ast: ast)
      end

      private

      # @rbs () -> Array[Integer]
      def build_line_starts
        starts = [0]
        offset = 0
        source.each_char do |character|
          offset += character.bytesize
          starts << offset if character == "\n"
        end
        starts
      end

      # @rbs () -> void
      def validate_render
        return if full_source_coverage? && segment_slices_match? && render == source

        raise ArgumentError, "concrete syntax tree does not reproduce its source"
      end

      # @rbs () -> bool
      def full_source_coverage?
        segments = cst.segments
        return source.empty? if segments.empty?

        first = segments.first
        last = segments.last
        return false unless first && last

        first.span.start_byte.zero? && last.span.end_byte == source.bytesize
      end

      # @rbs () -> bool
      def segment_slices_match?
        cst.segments.all? do |segment|
          segment.span.file == file &&
            source.byteslice(segment.span.start_byte, segment.span.length) == segment.text
        end
      end

      # @rbs (Integer byte_offset) -> void
      def validate_byte_offset(byte_offset)
        return if byte_offset.between?(0, source.bytesize)

        raise ArgumentError, "byte offset is outside the source"
      end

      # @rbs (SourceSpan span) -> void
      def validate_span(span)
        raise ArgumentError, "span belongs to another source" unless span.file == file

        validate_byte_offset(span.start_byte)
        validate_byte_offset(span.end_byte)
      end
    end
  end
end
