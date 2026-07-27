# frozen_string_literal: true
# rbs_inline: enabled

require "json"

module Ibex
  module Runtime
    module CST
      class SerializationError < StandardError; end

      # Stable JSON serialization for `ibex_cst` schema version 1.
      module Serialize
        SCHEMA_VERSION = 1 #: Integer

        # @rbs (SyntaxNode | SerializedTree value, ?grammar_digest: String?, ?table_format: Integer?,
        #   ?state_count: Integer?, ?production_count: Integer?, ?memo: ParseMemo?) -> String
        def dump(value, grammar_digest: nil, table_format: nil, state_count: nil, production_count: nil, memo: nil)
          tree = serialization_tree(
            value, grammar_digest: grammar_digest, table_format: table_format,
                   state_count: state_count, production_count: production_count, memo: memo
          )
          document = {
            "ibex_ir" => "cst",
            "schema_version" => SCHEMA_VERSION,
            "grammar_digest" => tree.grammar_digest,
            "table_format" => tree.table_format,
            "state_count" => tree.state_count,
            "production_count" => tree.production_count,
            "trivia_policy" => tree.trivia_policy.to_s,
            "kinds" => kinds_document(tree.kinds),
            "root" => element_document(tree.green_root),
            "memo" => tree.memo&.to_h
          }
          "#{JSON.pretty_generate(document)}\n"
        end
        module_function :dump

        # @rbs (String source, ?grammar_digest: String?, ?state_count: Integer?,
        #   ?production_count: Integer?) -> SerializedTree
        def load(source, grammar_digest: nil, state_count: nil, production_count: nil)
          Validator.validate(
            source,
            grammar_digest: grammar_digest,
            state_count: state_count,
            production_count: production_count
          )
        end
        module_function :load

        # @rbs (SyntaxNode | SerializedTree value, grammar_digest: String?, table_format: Integer?,
        #   state_count: Integer?, production_count: Integer?, memo: ParseMemo?) -> SerializedTree
        def serialization_tree(value, grammar_digest:, table_format:, state_count:, production_count:, memo:)
          return value if value.is_a?(SerializedTree)

          missing = {
            grammar_digest: grammar_digest, table_format: table_format,
            state_count: state_count, production_count: production_count
          }.select { |_name, item| item.nil? }.keys
          raise ArgumentError, "missing CST serialization metadata: #{missing.join(', ')}" unless missing.empty?

          SerializedTree.new(
            grammar_digest: grammar_digest || "", table_format: table_format || 0,
            state_count: state_count || 0, production_count: production_count || 0,
            trivia_policy: value.trivia_policy, kinds: value.kinds, green_root: value.green, memo: memo
          )
        end
        module_function :serialization_tree
        private_class_method :serialization_tree

        # @rbs (Kind kinds) -> Hash[String, untyped]
        def kinds_document(kinds)
          metadata = kinds.to_h
          {
            "names" => metadata.fetch(:names),
            "terminal_range" => metadata.fetch(:terminal_range),
            "nonterminal_range" => metadata.fetch(:nonterminal_range),
            "named" => metadata.fetch(:named),
            "named_nonterminals" => metadata.fetch(:named_nonterminals).to_h { |key, value| [key.to_s, value] },
            "trivia" => metadata.fetch(:trivia),
            "synthetic" => metadata.fetch(:synthetic)
          }
        end
        module_function :kinds_document
        private_class_method :kinds_document

        # @rbs (GreenNode | GreenToken element) -> Hash[String, untyped]
        def element_document(element)
          if element.is_a?(GreenNode)
            raise SerializationError, "annotated Green nodes cannot be serialized" unless element.annotations.empty?

            return {
              "k" => element.kind,
              "f" => element.intrinsic_flags,
              "c" => element.children.map { |child| element_document(child) }
            }
          end

          {
            "k" => element.kind,
            "f" => element.flags,
            "e" => element.expected_kind,
            "t" => encode_text(element.text),
            "l" => element.leading.map { |trivia| trivia_document(trivia) },
            "r" => element.trailing.map { |trivia| trivia_document(trivia) }
          }
        end
        module_function :element_document
        private_class_method :element_document

        # @rbs (GreenTrivia trivia) -> Array[untyped]
        def trivia_document(trivia) = [trivia.kind, encode_text(trivia.text)]
        module_function :trivia_document
        private_class_method :trivia_document

        # @rbs (String text) -> (String | Hash[String, String])
        def encode_text(text)
          utf8 = text.dup.force_encoding(Encoding::UTF_8)
          return utf8 if utf8.valid_encoding?

          { "b64" => [text.b].pack("m0") }
        end
        module_function :encode_text
        private_class_method :encode_text
      end
    end
  end
end
