# frozen_string_literal: true
# rbs_inline: enabled

require_relative "cst/kind" unless defined?(Ibex::Runtime::CST::Kind)
require_relative "cst/annotation" unless defined?(Ibex::Runtime::CST::SyntaxAnnotation)
require_relative "cst/green/trivia" unless defined?(Ibex::Runtime::CST::GreenTrivia)
require_relative "cst/green/token" unless defined?(Ibex::Runtime::CST::GreenToken)
require_relative "cst/green/node" unless defined?(Ibex::Runtime::CST::GreenNode)
require_relative "cst/green/cache" unless defined?(Ibex::Runtime::CST::NodeCache)
require_relative "cst/green/builder" unless defined?(Ibex::Runtime::CST::GreenBuilder)
require_relative "cst/source_text" unless defined?(Ibex::Runtime::CST::SourceText)
require_relative "cst/syntax_token" unless defined?(Ibex::Runtime::CST::SyntaxToken)
require_relative "cst/syntax_node" unless defined?(Ibex::Runtime::CST::SyntaxNode)
require_relative "cst/cursor" unless defined?(Ibex::Runtime::CST::Cursor)
require_relative "cst/typed_node" unless defined?(Ibex::Runtime::CST::TypedNode)
require_relative "cst/parse_result" unless defined?(Ibex::Runtime::CST::ParseResult)
require_relative "cst/editing" unless defined?(Ibex::Runtime::CST::Editing)
require_relative "cst/text_edit" unless defined?(Ibex::Runtime::CST::TextEdit)
require_relative "cst/rewriter" unless defined?(Ibex::Runtime::CST::SyntaxRewriter)
require_relative "cst/editor" unless defined?(Ibex::Runtime::CST::SyntaxEditor)
require_relative "cst/diff" unless defined?(Ibex::Runtime::CST::Diff)
require_relative "cst/serialized_tree" unless defined?(Ibex::Runtime::CST::SerializedTree)
require_relative "cst/validator" unless defined?(Ibex::Runtime::CST::Validator)
require_relative "cst/serialize" unless defined?(Ibex::Runtime::CST::Serialize)
require_relative "cst/incremental/token_memo" unless defined?(Ibex::Runtime::CST::TokenMemo)
require_relative "cst/incremental/relexer" unless defined?(Ibex::Runtime::CST::Relexer)
require_relative "cst/incremental/parse_memo" unless defined?(Ibex::Runtime::CST::ParseMemo)
require_relative "cst/incremental/lexed_syntax" unless defined?(Ibex::Runtime::CST::LexedSyntax)
require_relative "cst/incremental/blender" unless defined?(Ibex::Runtime::CST::Blender)
require_relative "cst/incremental/session" unless defined?(Ibex::Runtime::CST::IncrementalParseSession)

module Ibex
  module Runtime
    # Current Red/Green concrete-syntax APIs.
    module CST
    end
  end
end
