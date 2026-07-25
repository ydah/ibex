# frozen_string_literal: true

module Ibex
  module Frontend
    class Lexer
      # Recover lexical failures while retaining every source byte.
      # @rbs (?max_diagnostics: Integer) -> [SourceDocument, Array[Diagnostic]]
      def tokenize_document_recovering(max_diagnostics: 20)
        unless max_diagnostics.is_a?(Integer) && max_diagnostics.positive?
          raise ArgumentError, "max_diagnostics must be a positive integer"
        end

        diagnostics = [] #: Array[Diagnostic]
        until @eof_token
          begin
            next_token
          rescue Ibex::Error => e
            diagnostic = recover_lexical_error(e, capture: diagnostics.length < max_diagnostics)
            diagnostics << diagnostic if diagnostic
          end
        end
        cst = CST::Document.new(@segments)
        document = SourceDocument.new(source: @cursor.source, file: @cursor.file,
                                      tokens: @emitted_tokens, cst: cst)
        [document, diagnostics.freeze]
      end

      private

      # @rbs (Exception error, capture: bool) -> Diagnostic?
      def recover_lexical_error(error, capture:)
        start = @active_token_start || @cursor.position
        advance_after_lexical_error(error, start)
        emit_invalid_segment(start)
        return unless capture

        location, message = lexical_error_details(error, start)
        Diagnostic.new(code: "frontend.lexical_error", phase: :lexical,
                       message: message, location: location,
                       span: @cursor.span_from(start), rendered: error.message)
      ensure
        @active_token_start = nil
      end

      # @rbs (Exception error, SourcePosition fallback) -> [Location, String]
      def lexical_error_details(error, fallback)
        pattern = /\A#{Regexp.escape(@cursor.file)}:(\d+):(\d+): (.*)\z/m
        match = error.message.match(pattern)
        if match
          return [
            Location.new(file: @cursor.file, line: Integer(match[1]), column: Integer(match[2])),
            match[3] || ""
          ]
        end

        location = Location.new(file: @cursor.file, line: fallback.line, column: fallback.column)
        [location, error.message.delete_prefix("#{location}: ")]
      end

      # @rbs (SourcePosition start) -> void
      def emit_invalid_segment(start)
        span = @cursor.span_from(start)
        previous = @segments.last
        unless previous&.kind == :invalid && previous.span.end_byte == span.start_byte
          emit_segment(:invalid, start)
          return
        end

        combined_span = SourceSpan.new(file: @cursor.file, start: previous.span.start, finish: span.finish)
        text = @cursor.source.byteslice(combined_span.start_byte, combined_span.length) || ""
        @segments[-1] = Segment.new(kind: :invalid, span: combined_span, text: text)
      end

      # @rbs (Exception error, SourcePosition start) -> void
      def advance_after_lexical_error(error, start)
        return unless @cursor.position.byte_offset == start.byte_offset

        remaining = @cursor.source.length - @cursor.index
        count = error.message.include?("unterminated block comment") ? remaining : 1
        @cursor.advance(count)
      end
    end
  end
end
