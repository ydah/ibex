# frozen_string_literal: true

require_relative "../error"
require_relative "../tables"
require_relative "source_cursor"
require_relative "action_scanner"
require_relative "lexer"
require_relative "ast"
require_relative "parser/declarations"
require_relative "parser/rules"
require_relative "bootstrap_parser"
require_relative "../ir"
require_relative "../normalize"
require_relative "../analysis"
require_relative "../lalr"
require_relative "../codegen/ruby"

module Ibex
  module Frontend
    # Builds the committed frontend parser from its canonical Ibex grammar.
    module Regenerator
      GRAMMAR_PATH = File.expand_path("grammar.y", File.dirname(__FILE__))

      module_function

      def generate
        source = File.read(GRAMMAR_PATH)
        ast = BootstrapParser.new(source, file: relative_grammar_path).parse
        grammar = Normalizer.new(ast).normalize
        automaton = LALR::Builder.new(grammar).build
        Codegen::Ruby.new(automaton, table: :compact, line_convert: false).generate
      end

      def relative_grammar_path
        "lib/ibex/frontend/grammar.y"
      end
    end
  end
end
