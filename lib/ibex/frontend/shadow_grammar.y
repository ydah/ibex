class Ibex::Frontend::ShadowGeneratedParser < Ibex::Frontend::GeneratedParserBase
pragma extended
token CLASS FRAGMENT INCLUDE IMPORT TOKEN PRECHIGH PRECLOW OPTIONS EXPECT EXPECT_RR START RECOVER ON_ERROR_REDUCE TEST LEXER
token CONVERT DISPLAY TYPE PARAM PRINTER PRAGMA RULE END
token LEFT RIGHT NONASSOC PRECEDENCE IDENTIFIER LITERAL INTEGER ACTION USER_CODE INLINE EMPTY LHS
token PARAMETERIZED_REFERENCE TOKEN_ALIAS NODE
token SEPARATED_LIST SEPARATED_NONEMPTY_LIST STATE DO SKIP ON REGEXP
rule
  document
    : grammar                            { result = val[0] }
    | fragment                           { result = val[0] }

  grammar
    : CLASS constant_path superclass pragmas declarations RULE rules END user_code
      { result = build_root(val[0], val[1], val[2], val[4], val[6], val[8]) }

  fragment
    : FRAGMENT declarations RULE fragment_rules END user_code
      { result = build_fragment(val[0], val[1], val[3], val[5]) }

  fragment_rules
    :                                    { result = Array.new(0) }
    | rules                              { result = val[0] }

  constant_path
    : IDENTIFIER                         { result = [val[0].value] }
    | constant_path '::' IDENTIFIER      { result = val[0] + [val[2].value] }

  superclass
    :                                    { result = nil }
    | '<' constant_path                  { result = val[1] }

  pragmas
    :
    | pragmas PRAGMA IDENTIFIER

  sequence(X)
    :                                    { result = Array.new(0) }
    | sequence(X) X                      { result = val[0] + [val[1]] }

  declarations
    : sequence(declaration)              { result = val[0] }

  declaration
    : include_declaration                { result = val[0] }
    | token_declaration                  { result = val[0] }
    | precedence_declaration             { result = val[0] }
    | options_declaration                { result = val[0] }
    | expect_declaration                 { result = val[0] }
    | expect_rr_declaration              { result = val[0] }
    | start_declaration                  { result = val[0] }
    | recovery_declaration               { result = val[0] }
    | on_error_reduce_declaration        { result = val[0] }
    | test_declaration                   { result = val[0] }
    | lexer_declaration                  { result = val[0] }
    | convert_declaration                { result = val[0] }
    | display_declaration                { result = val[0] }
    | type_declaration                   { result = val[0] }
    | param_declaration                  { result = val[0] }
    | printer_declaration                { result = val[0] }

  %inline literal_value
    : LITERAL                            { result = val[0] }

  include_declaration
    : INCLUDE literal_value              { result = build_include(val[0], val[1]) }
    | IMPORT literal_value               { result = build_include(val[0], val[1]) }

  token_declaration
    : TOKEN token_entries                { result = build_tokens(val[0], val[1]) }

  token_entries
    : sequence(token_entry)              { result = val[0] }

  token_entry
    : grammar_symbol                     { result = build_token_entry(val[0]) }
    | IDENTIFIER TOKEN_ALIAS             { result = build_token_alias(val[0], val[1]) }

  precedence_declaration
    : PRECHIGH precedence_levels PRECLOW { result = build_precedence(val[0], :high_to_low, val[1]) }
    | PRECLOW precedence_levels PRECHIGH { result = build_precedence(val[0], :low_to_high, val[1]) }

  precedence_levels
    : sequence(precedence_level)         { result = val[0] }

  precedence_level
    : association symbols                { result = build_precedence_level(val[0], val[1]) }

  association
    : LEFT                               { result = val[0] }
    | RIGHT                              { result = val[0] }
    | NONASSOC                           { result = val[0] }
    | PRECEDENCE                         { result = val[0] }

  options_declaration
    : OPTIONS identifiers                { result = build_options(val[0], val[1]) }

  expect_declaration
    : EXPECT INTEGER                     { result = build_expect(val[0], val[1]) }

  expect_rr_declaration
    : EXPECT_RR INTEGER                  { result = build_expect_rr(val[0], val[1]) }

  start_declaration
    : START grammar_symbol symbols       { result = build_start(val[0], [val[1].value] + val[2]) }

  recovery_declaration
    : RECOVER IDENTIFIER ':' grammar_symbol symbols
      { result = build_recovery(val[0], val[1], [val[3].value] + val[4]) }

  on_error_reduce_declaration
    : ON_ERROR_REDUCE grammar_symbol symbols
      { result = build_on_error_reduce(val[0], [val[1].value] + val[2]) }

  test_declaration
    : TEST IDENTIFIER LITERAL            { result = build_grammar_test(val[0], val[1], val[2]) }

  lexer_declaration
    : LEXER lexer_entries END            { result = build_lexer(val[0], val[1]) }

  lexer_entries
    : sequence(lexer_entry)              { result = val[0] }

  lexer_entry
    : lexer_rule                         { result = val[0] }
    | lexer_state                        { result = val[0] }

  lexer_rule
    : SKIP lexer_pattern lexer_action    { result = build_lexer_rule(:skip, nil, val[1], val[2], val[0]) }
    | IDENTIFIER lexer_pattern lexer_action
                                         { result = build_lexer_rule(:token, val[0], val[1], val[2], val[0]) }
    | ON lexer_pattern ACTION            { result = build_lexer_rule(:on, nil, val[1], val[2], val[0]) }

  lexer_pattern
    : REGEXP                             { result = val[0] }
    | LITERAL                            { result = val[0] }

  lexer_action
    :                                    { result = nil }
    | ACTION                             { result = val[0] }

  lexer_state
    : STATE IDENTIFIER DO lexer_entries END
      { result = build_lexer_state(val[0], val[1], val[3]) }

  convert_declaration
    : CONVERT conversions END            { result = build_convert(val[0], val[1]) }

  conversions
    : sequence(conversion)               { result = val[0] }

  conversion
    : grammar_symbol LITERAL             { result = build_conversion(val[0], val[1]) }

  display_declaration
    : DISPLAY grammar_symbol LITERAL     { result = build_display_name(val[0], val[1], val[2]) }

  type_declaration
    : TYPE grammar_symbol LITERAL        { result = build_semantic_type(val[0], val[1], val[2]) }

  param_declaration
    : PARAM IDENTIFIER param_type        { result = build_parameter(val[0], val[1], val[2]) }

  param_type
    :                                    { result = nil }
    | LITERAL                            { result = val[0] }

  printer_declaration
    : PRINTER grammar_symbol ACTION      { result = build_printer(val[0], val[1], val[2]) }

  identifiers
    :                                    { result = Array.new(0) }
    | identifiers IDENTIFIER             { result = val[0] + [val[1].value] }

  symbols
    :                                    { result = Array.new(0) }
    | symbols grammar_symbol             { result = val[0] + [val[1].value] }

  grammar_symbol
    : IDENTIFIER                         { result = val[0] }
    | LITERAL                            { result = val[0] }

  rules
    : rule_definition                    { result = [val[0]] }
    | rules rule_definition              { result = val[0] + [val[1]] }

  rule_definition
    : inline_marker LHS rule_parameters ':' alternatives semicolon
      { result = build_rule(val[0], val[1], val[2], val[4]) }

  inline_marker
    :                                    { result = nil }
    | INLINE                             { result = val[0] }

  rule_parameters
    :                                    { result = nil }
    | '(' formal_parameters ')'          { result = build_rule_parameters(val[0], val[1]) }

  formal_parameters
    : IDENTIFIER                         { result = [val[0]] }
    | formal_parameters ',' IDENTIFIER   { result = val[0] + [val[2]] }

  semicolon
    :
    | ';'

  alternatives
    : alternative                        { result = [val[0]] }
    | alternatives '|' alternative       { result = val[0] + [val[2]] }

  alternative
    : items precedence_override node_annotation
                                         { result = build_alternative(val[0], val[1], val[2]) }

  node_annotation
    :                                    { result = nil }
    | NODE IDENTIFIER '(' node_fields ')'
                                         { result = build_node_annotation(val[0], val[1], val[3]) }

  node_fields
    :                                    { result = Array.new(0) }
    | formal_parameters                  { result = val[0] }

  precedence_override
    :                                    { result = nil }
    | '=' grammar_symbol                 { result = val[1] }

  items
    : sequence(item)                     { result = val[0] }

  item
    : symbol_item                        { result = val[0] }
    | parameterized_item                 { result = val[0] }
    | ACTION                             { result = build_action(val[0]) }
    | EMPTY                              { result = build_empty(val[0]) }
    | group_item                         { result = val[0] }
    | separated_item                     { result = val[0] }

  symbol_item
    : grammar_symbol named_reference suffixes
      { result = build_symbol_reference(val[0], val[1], val[2]) }

  parameterized_item
    : PARAMETERIZED_REFERENCE '(' parameter_arguments ')' named_reference suffixes
      { result = build_parameterized_reference(val[0], val[1], val[2], val[4], val[5]) }

  parameter_arguments
    :                                    { result = Array.new(0) }
    | parameter_argument_list            { result = val[0] }

  parameter_argument_list
    : parameter_argument                 { result = [val[0]] }
    | parameter_argument_list ',' parameter_argument
      { result = val[0] + [val[2]] }

  parameter_argument
    : symbol_item                        { result = val[0] }
    | parameterized_item                 { result = val[0] }
    | group_item                         { result = val[0] }
    | separated_item                     { result = val[0] }

  named_reference
    :                                    { result = nil }
    | ':' IDENTIFIER                     { result = [val[0], val[1]] }

  suffixes
    :                                    { result = Array.new(0) }
    | suffixes '?'                       { result = val[0] + [val[1]] }
    | suffixes '*'                       { result = val[0] + [val[1]] }
    | suffixes '+'                       { result = val[0] + [val[1]] }

  group_item
    : '(' group_alternatives ')' suffixes
      { result = build_group(val[0], val[1], val[3]) }

  group_alternatives
    : group_items                        { result = [val[0]] }
    | group_alternatives '|' group_items { result = val[0] + [val[2]] }

  group_items
    : sequence(group_item_element)       { result = val[0] }

  group_item_element
    : symbol_item                        { result = val[0] }
    | parameterized_item                 { result = val[0] }
    | group_item                         { result = val[0] }
    | separated_item                     { result = val[0] }

  separated_item
    : SEPARATED_LIST '(' item ',' item ')'
      { result = build_separated_list(val[0], val[2], val[4]) }
    | SEPARATED_NONEMPTY_LIST '(' item ',' item ')'
      { result = build_separated_list(val[0], val[2], val[4]) }

  user_code
    :                                    { result = empty_user_code }
    | user_code USER_CODE                { result = append_user_code(val[0], val[1]) }
end
