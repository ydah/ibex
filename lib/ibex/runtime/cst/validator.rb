# frozen_string_literal: true
# rbs_inline: enabled

require "json"

module Ibex
  module Runtime
    module CST
      # Structured failure raised for an invalid or incompatible CST document.
      class ValidationError < StandardError
        attr_reader :code #: Symbol
        attr_reader :path #: String
        attr_reader :expected #: untyped
        attr_reader :actual #: untyped

        # @rbs (code: Symbol, path: String, message: String, ?expected: untyped, ?actual: untyped) -> void
        def initialize(code:, path:, message:, expected: nil, actual: nil)
          @code = code
          @path = path.dup.freeze
          @expected = expected
          @actual = actual
          super("(cst):#{path}: #{message}")
        end
      end

      # Validates schema-v1 CST documents while rebuilding all derived Green data.
      module Validator # rubocop:disable Metrics/ModuleLength -- closed schema checks remain auditable in one boundary.
        TOP_KEYS = %w[
          ibex_ir schema_version grammar_digest table_format state_count production_count trivia_policy kinds root memo
        ].freeze #: Array[String]
        KIND_KEYS = %w[
          names terminal_range nonterminal_range named named_nonterminals trivia synthetic
        ].freeze #: Array[String]
        KNOWN_FLAGS = (
          Flags::CONTAINS_ERROR | Flags::CONTAINS_MISSING | Flags::CONTAINS_SKIPPED |
          Flags::HAS_ANNOTATION | Flags::SYNTHETIC | Flags::INCOMPLETE_INPUT
        ) #: Integer

        # @rbs (String source, ?grammar_digest: String?) -> SerializedTree
        def validate(source, grammar_digest: nil) # rubocop:disable Metrics/MethodLength
          document = JSON.parse(source)
          object!(document, "$")
          exact_keys!(document, TOP_KEYS, "$")
          value!(document, "ibex_ir", "cst", "$.ibex_ir")
          value!(document, "schema_version", 1, "$.schema_version")
          digest = string!(document.fetch("grammar_digest"), "$.grammar_digest")
          unless digest.match?(/\Asha256:[0-9a-f]{64}\z/)
            fail_validation(:invalid_digest, "$.grammar_digest", "expected a SHA-256 digest", actual: digest)
          end
          if grammar_digest && digest != grammar_digest
            fail_validation(
              :grammar_digest_mismatch, "$.grammar_digest",
              "grammar digest does not match", expected: grammar_digest, actual: digest
            )
          end

          kinds = load_kinds(document.fetch("kinds"))
          root = load_element(document.fetch("root"), kinds, "$.root")
          fail_validation(:invalid_root, "$.root", "root must be a node") unless root.is_a?(GreenNode)
          validate_derived!(root, "$.root")
          memo = document.fetch("memo")
          fail_validation(:unsupported_memo, "$.memo", "memo must be null in schema v1") unless memo.nil?

          SerializedTree.new(
            grammar_digest: digest,
            table_format: positive_integer!(document.fetch("table_format"), "$.table_format"),
            state_count: nonnegative_integer!(document.fetch("state_count"), "$.state_count"),
            production_count: nonnegative_integer!(document.fetch("production_count"), "$.production_count"),
            trivia_policy: trivia_policy!(document.fetch("trivia_policy"), "$.trivia_policy"),
            kinds: kinds, green_root: root
          )
        rescue JSON::ParserError => e
          fail_validation(:invalid_json, "$", e.message)
        rescue KeyError => e
          fail_validation(:missing_field, "$", e.message)
        end
        module_function :validate

        # @rbs (untyped value) -> Kind
        def load_kinds(value)
          object!(value, "$.kinds")
          exact_keys!(value, KIND_KEYS, "$.kinds")
          names = array!(value.fetch("names"), "$.kinds.names").map.with_index do |name, index|
            string!(name, "$.kinds.names[#{index}]")
          end
          metadata = {
            names: names,
            terminal_range: integer_pair!(value.fetch("terminal_range"), "$.kinds.terminal_range"),
            nonterminal_range: integer_pair!(value.fetch("nonterminal_range"), "$.kinds.nonterminal_range"),
            named: string_integer_map!(value.fetch("named"), "$.kinds.named"),
            named_nonterminals: integer_integer_map!(
              value.fetch("named_nonterminals"), "$.kinds.named_nonterminals"
            ),
            trivia: string_integer_map!(value.fetch("trivia"), "$.kinds.trivia"),
            synthetic: string_integer_map!(value.fetch("synthetic"), "$.kinds.synthetic")
          } #: Kind::metadata
          validate_kind_metadata!(metadata)
          Kind.new(metadata)
        end
        module_function :load_kinds
        private_class_method :load_kinds

        # @rbs (untyped value, Kind kinds, String path) -> (GreenNode | GreenToken)
        def load_element(value, kinds, path)
          object!(value, path)
          kind = nonnegative_integer!(value.fetch("k"), "#{path}.k")
          validate_kind!(kind, kinds, "#{path}.k")
          flags = flags!(value.fetch("f"), "#{path}.f")
          if value.key?("c")
            exact_keys!(value, %w[k f c], path)
            children = array!(value.fetch("c"), "#{path}.c").map.with_index do |child, index|
              load_element(child, kinds, "#{path}.c[#{index}]")
            end
            return GreenNode.new(kind: kind, children: children, flags: flags)
          end

          exact_keys!(value, %w[k f e t l r], path)
          expected = value.fetch("e")
          expected_kind = expected.nil? ? nil : nonnegative_integer!(expected, "#{path}.e")
          validate_kind!(expected_kind, kinds, "#{path}.e") if expected_kind
          GreenToken.new(
            kind: kind, flags: flags, expected_kind: expected_kind,
            text: decode_text(value.fetch("t"), "#{path}.t"),
            leading: load_trivia(value.fetch("l"), kinds, "#{path}.l"),
            trailing: load_trivia(value.fetch("r"), kinds, "#{path}.r")
          )
        end
        module_function :load_element
        private_class_method :load_element

        # @rbs (untyped value, Kind kinds, String path) -> Array[GreenTrivia]
        def load_trivia(value, kinds, path)
          array!(value, path).map.with_index do |item, index|
            pair = array!(item, "#{path}[#{index}]")
            unless pair.length == 2
              fail_validation(:invalid_trivia, "#{path}[#{index}]", "trivia must contain two items")
            end

            kind = nonnegative_integer!(pair.fetch(0), "#{path}[#{index}][0]")
            validate_kind!(kind, kinds, "#{path}[#{index}][0]")
            unless kinds.trivia?(kind)
              fail_validation(:invalid_trivia_kind, "#{path}[#{index}][0]", "kind is not trivia", actual: kind)
            end
            GreenTrivia.new(kind: kind, text: decode_text(pair.fetch(1), "#{path}[#{index}][1]"))
          end
        end
        module_function :load_trivia
        private_class_method :load_trivia

        # @rbs (untyped value, String path) -> String
        def decode_text(value, path)
          return value.b if value.is_a?(String)

          object!(value, path)
          exact_keys!(value, ["b64"], path)
          encoded = string!(value.fetch("b64"), "#{path}.b64")
          decoded = encoded.unpack1("m0")
          fail_validation(:invalid_base64, path, "invalid Base64 text") unless decoded.is_a?(String)
          decoded = decoded.b
          fail_validation(:invalid_base64, path, "invalid Base64 text") unless [decoded].pack("m0") == encoded

          decoded
        rescue ArgumentError
          fail_validation(:invalid_base64, path, "invalid Base64 text")
        end
        module_function :decode_text
        private_class_method :decode_text

        # @rbs (GreenNode | GreenToken element, String path) -> void
        def validate_derived!(element, path)
          unless element.to_source.bytesize == element.full_width
            fail_validation(:invalid_width, path, "derived full width does not match source bytes")
          end
          if element.leading_width + element.trailing_width > element.full_width
            fail_validation(:invalid_trim_width, path, "derived trim widths exceed full width")
          end
          return unless element.is_a?(GreenNode)

          expected = 1 + element.children.sum(&:descendant_count)
          fail_validation(:invalid_descendant_count, path, "derived descendant count is invalid") unless
            element.descendant_count == expected
          element.children.each_with_index do |child, index|
            validate_derived!(child, "#{path}.c[#{index}]")
          end
        end
        module_function :validate_derived!
        private_class_method :validate_derived!

        # @rbs (Integer kind, Kind kinds, String path) -> void
        def validate_kind!(kind, kinds, path)
          kinds.name(kind)
        rescue IndexError
          fail_validation(:invalid_kind, path, "kind id is outside the kind table", actual: kind)
        end
        module_function :validate_kind!
        private_class_method :validate_kind!

        # @rbs (untyped value, String path) -> Hash[String, untyped]
        def object!(value, path)
          return value if value.is_a?(Hash)

          fail_validation(:invalid_type, path, "expected object", actual: value.class.name)
        end
        module_function :object!
        private_class_method :object!

        # @rbs (untyped value, String path) -> Array[untyped]
        def array!(value, path)
          return value if value.is_a?(Array)

          fail_validation(:invalid_type, path, "expected array", actual: value.class.name)
        end
        module_function :array!
        private_class_method :array!

        # @rbs (untyped value, String path) -> String
        def string!(value, path)
          return value if value.is_a?(String)

          fail_validation(:invalid_type, path, "expected string", actual: value.class.name)
        end
        module_function :string!
        private_class_method :string!

        # @rbs (untyped value, String path) -> Integer
        def nonnegative_integer!(value, path)
          return value if value.is_a?(Integer) && !value.negative?

          fail_validation(:invalid_type, path, "expected non-negative integer", actual: value)
        end
        module_function :nonnegative_integer!
        private_class_method :nonnegative_integer!

        # @rbs (untyped value, String path) -> Integer
        def positive_integer!(value, path)
          integer = nonnegative_integer!(value, path)
          return integer if integer.positive?

          fail_validation(:invalid_type, path, "expected positive integer", actual: value)
        end
        module_function :positive_integer!
        private_class_method :positive_integer!

        # @rbs (untyped value, String path) -> Symbol
        def trivia_policy!(value, path)
          policy = string!(value, path).to_sym
          return policy if %i[leading balanced drop].include?(policy)

          fail_validation(:invalid_value, path, "unknown trivia policy", actual: value)
        end
        module_function :trivia_policy!
        private_class_method :trivia_policy!

        # @rbs (untyped value, String path) -> Integer
        def flags!(value, path)
          flags = nonnegative_integer!(value, path)
          fail_validation(:invalid_flags, path, "flags contain unknown bits", actual: flags) unless
            flags.nobits?(~KNOWN_FLAGS)
          fail_validation(:invalid_flags, path, "serialized annotations are unsupported") if
            flags.anybits?(Flags::HAS_ANNOTATION)
          flags
        end
        module_function :flags!
        private_class_method :flags!

        # @rbs (untyped value, String path) -> Array[Integer]
        def integer_pair!(value, path)
          pair = array!(value, path)
          fail_validation(:invalid_type, path, "expected two integers") unless pair.length == 2
          pair.map.with_index { |item, index| nonnegative_integer!(item, "#{path}[#{index}]") }
        end
        module_function :integer_pair!
        private_class_method :integer_pair!

        # @rbs (untyped value, String path) -> Hash[String, Integer]
        def string_integer_map!(value, path)
          object!(value, path).to_h do |key, item|
            [
              string!(key, "#{path}.<key>"),
              nonnegative_integer!(item, "#{path}.#{key}")
            ]
          end
        end
        module_function :string_integer_map!
        private_class_method :string_integer_map!

        # @rbs (untyped value, String path) -> Hash[Integer, Integer]
        def integer_integer_map!(value, path)
          object!(value, path).to_h do |key, item|
            integer_key = Integer(string!(key, "#{path}.<key>"), 10)
            [integer_key, nonnegative_integer!(item, "#{path}.#{key}")]
          end
        rescue ArgumentError
          fail_validation(:invalid_type, path, "expected integer object keys")
        end
        module_function :integer_integer_map!
        private_class_method :integer_integer_map!

        # @rbs (Kind::metadata metadata) -> void
        def validate_kind_metadata!(metadata)
          names = metadata.fetch(:names)
          limit = names.length
          validate_kind_range!(metadata.fetch(:terminal_range), limit, "$.kinds.terminal_range")
          validate_kind_range!(metadata.fetch(:nonterminal_range), limit, "$.kinds.nonterminal_range")
          ids = [] #: Array[Integer]
          ids.concat(metadata.fetch(:named).values)
          ids.concat(metadata.fetch(:named_nonterminals).keys)
          ids.concat(metadata.fetch(:named_nonterminals).values)
          ids.concat(metadata.fetch(:trivia).values)
          ids.concat(metadata.fetch(:synthetic).values)
          invalid = ids.find { |id| id >= limit }
          fail_validation(:invalid_kind, "$.kinds", "kind map exceeds names", actual: invalid) if invalid
        end
        module_function :validate_kind_metadata!
        private_class_method :validate_kind_metadata!

        # @rbs (Array[Integer] range, Integer limit, String path) -> void
        def validate_kind_range!(range, limit, path)
          return if range.fetch(1).between?(range.fetch(0), limit)

          fail_validation(:invalid_kind_range, path, "kind range exceeds names")
        end
        module_function :validate_kind_range!
        private_class_method :validate_kind_range!

        # @rbs (Hash[String, untyped] value, Array[String] expected, String path) -> void
        def exact_keys!(value, expected, path)
          actual = value.keys.sort
          return if actual == expected.sort

          fail_validation(:invalid_keys, path, "object keys do not match schema", expected: expected, actual: actual)
        end
        module_function :exact_keys!
        private_class_method :exact_keys!

        # @rbs (Hash[String, untyped] value, String key, untyped expected, String path) -> void
        def value!(value, key, expected, path)
          actual = value.fetch(key)
          return if actual == expected

          fail_validation(:invalid_value, path, "unexpected value", expected: expected, actual: actual)
        end
        module_function :value!
        private_class_method :value!

        # @rbs (Symbol code, String path, String message, ?expected: untyped, ?actual: untyped) -> bot
        def fail_validation(code, path, message, expected: nil, actual: nil)
          raise ValidationError.new(
            code: code, path: path, message: message, expected: expected, actual: actual
          )
        end
        module_function :fail_validation
        private_class_method :fail_validation
      end
    end
  end
end
