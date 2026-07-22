# frozen_string_literal: true

require_relative "error"
require_relative "tables"
require_relative "runtime"
require_relative "frontend/source_cursor"
require_relative "frontend/action_scanner"
require_relative "frontend/lexer"
require_relative "frontend/ast"
require_relative "frontend/token_adapter/declaration_state"
require_relative "frontend/token_adapter/delimiter_tracker"
require_relative "frontend/token_adapter/rule_state"
require_relative "frontend/token_adapter"
require_relative "frontend/generated_parser_base"
require_relative "frontend/generated_parser"
require_relative "frontend/parser"
require_relative "frontend/dsl"

module Ibex
  module Frontend
    # @rbs!
    #   type user_code_token = { name: String, code: String }
    #   type token_value = String | Integer | user_code_token | nil
    #   type external_token = Symbol | String
    #   type parser_section = :declarations | :rules | :user_code
    #   type delimiter_kind = :group | :separated
  end
end
