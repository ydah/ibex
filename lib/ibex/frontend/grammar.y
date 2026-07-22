class Ibex::Frontend::GeneratedParser < Ibex::Frontend::GeneratedParserBase
token CLASS TOKEN PRECHIGH PRECLOW OPTIONS EXPECT START CONVERT PRAGMA RULE END
token LEFT RIGHT NONASSOC IDENTIFIER LITERAL INTEGER ACTION USER_CODE LHS
token SEPARATED_LIST SEPARATED_NONEMPTY_LIST
rule
  grammar
    : CLASS constant_path superclass pragmas declarations RULE rules END user_code
      { result = build_root(val[0], val[1], val[2], val[4], val[6], val[8]) }

  constant_path
    : IDENTIFIER                         { result = [val[0].value] }
    | constant_path '::' IDENTIFIER      { result = val[0] + [val[2].value] }

  superclass
    :                                    { result = nil }
    | '<' constant_path                  { result = val[1] }

  pragmas
    :
    | pragmas PRAGMA IDENTIFIER

  declarations
    :                                    { result = Array.new(0) }
    | declarations declaration           { result = val[0] + [val[1]] }

  declaration
    : token_declaration                  { result = val[0] }
    | precedence_declaration             { result = val[0] }
    | options_declaration                { result = val[0] }
    | expect_declaration                 { result = val[0] }
    | start_declaration                  { result = val[0] }
    | convert_declaration                { result = val[0] }

  token_declaration
    : TOKEN symbols                      { result = build_tokens(val[0], val[1]) }

  precedence_declaration
    : PRECHIGH precedence_levels PRECLOW { result = build_precedence(val[0], :high_to_low, val[1]) }
    | PRECLOW precedence_levels PRECHIGH { result = build_precedence(val[0], :low_to_high, val[1]) }

  precedence_levels
    :                                    { result = Array.new(0) }
    | precedence_levels precedence_level { result = val[0] + [val[1]] }

  precedence_level
    : association symbols                { result = build_precedence_level(val[0], val[1]) }

  association
    : LEFT                               { result = val[0] }
    | RIGHT                              { result = val[0] }
    | NONASSOC                           { result = val[0] }

  options_declaration
    : OPTIONS identifiers                { result = build_options(val[0], val[1]) }

  expect_declaration
    : EXPECT INTEGER                     { result = build_expect(val[0], val[1]) }

  start_declaration
    : START grammar_symbol               { result = build_start(val[0], val[1].value) }

  convert_declaration
    : CONVERT conversions END            { result = build_convert(val[0], val[1]) }

  conversions
    :                                    { result = Array.new(0) }
    | conversions conversion             { result = val[0] + [val[1]] }

  conversion
    : grammar_symbol LITERAL              { result = build_conversion(val[0], val[1]) }

  identifiers
    :                                    { result = Array.new(0) }
    | identifiers IDENTIFIER              { result = val[0] + [val[1].value] }

  symbols
    :                                    { result = Array.new(0) }
    | symbols grammar_symbol              { result = val[0] + [val[1].value] }

  grammar_symbol
    : IDENTIFIER                         { result = val[0] }
    | LITERAL                            { result = val[0] }

  rules
    : rule_definition                    { result = [val[0]] }
    | rules rule_definition              { result = val[0] + [val[1]] }

  rule_definition
    : LHS ':' alternatives semicolon     { result = build_rule(val[0], val[2]) }

  semicolon
    :
    | ';'

  alternatives
    : alternative                        { result = [val[0]] }
    | alternatives '|' alternative       { result = val[0] + [val[2]] }

  alternative
    : items precedence_override          { result = build_alternative(val[0], val[1]) }

  precedence_override
    :                                    { result = nil }
    | '=' grammar_symbol                 { result = val[1] }

  items
    :                                    { result = Array.new(0) }
    | items item                         { result = val[0] + [val[1]] }

  item
    : symbol_item                        { result = val[0] }
    | ACTION                             { result = build_action(val[0]) }
    | group_item                         { result = val[0] }
    | separated_item                     { result = val[0] }

  symbol_item
    : grammar_symbol named_reference suffixes
      { result = build_symbol_reference(val[0], val[1], val[2]) }

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
    :                                    { result = Array.new(0) }
    | group_items group_item_element      { result = val[0] + [val[1]] }

  group_item_element
    : symbol_item                        { result = val[0] }
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
