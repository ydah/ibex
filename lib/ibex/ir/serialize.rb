# frozen_string_literal: true

require "json"

module Ibex
  module IR
    # Stable JSON serialization for versioned pipeline IR.
    module Serialize
      module_function

      def dump(value)
        "#{JSON.pretty_generate(value.to_h)}\n"
      end

      def load(source)
        data = JSON.parse(source)
        type = data.fetch("ibex_ir") { raise Ibex::Error, "(ir):1:1: missing ibex_ir discriminator" }
        validate_version(data)
        return load_grammar(data) if type == "grammar"

        raise Ibex::Error, "(ir):1:1: unsupported IR type #{type.inspect}"
      rescue JSON::ParserError => e
        raise Ibex::Error, "(ir):1:1: invalid JSON: #{e.message}"
      end

      def validate_version(data)
        version = data["schema_version"]
        return if version == SCHEMA_VERSION

        raise Ibex::Error, "(ir):1:1: unsupported schema_version #{version.inspect}; expected #{SCHEMA_VERSION}"
      end
      private_class_method :validate_version

      def load_grammar(data)
        symbols = data.fetch("symbols").map do |symbol|
          GrammarSymbol.new(id: symbol.fetch("id"), name: symbol.fetch("name"), kind: symbol.fetch("kind"),
                            reserved: symbol.fetch("reserved"), precedence: symbolize(symbol["prec"]),
                            location: symbolize(symbol["loc"]))
        end
        productions = data.fetch("productions").map { |production| load_production(production) }
        Grammar.new(class_name: data.fetch("class_name"), superclass: data["superclass"], start: data.fetch("start"),
                    expect: data.fetch("expect"), options: symbolize(data.fetch("options")), symbols: symbols,
                    productions: productions, user_code: data.fetch("user_code"),
                    conversions: data.fetch("conversions"), warnings: symbolize(data.fetch("warnings")))
      end
      private_class_method :load_grammar

      def load_production(production)
        action_data = production["action"]
        action = if action_data
                   Action.new(code: action_data.fetch("code"), location: symbolize(action_data["loc"]),
                              named_refs: symbolize(action_data.fetch("named_refs")),
                              context_length: action_data.fetch("context_length"))
                 end
        Production.new(id: production.fetch("id"), lhs: production.fetch("lhs"), rhs: production.fetch("rhs"),
                       action: action, precedence_override: production["prec_override"],
                       origin: symbolize(production.fetch("origin")))
      end
      private_class_method :load_production

      def symbolize(value)
        case value
        when Array then value.map { |item| symbolize(item) }
        when Hash then value.to_h { |key, item| [key.to_sym, symbolize(item)] }
        else value
        end
      end
      private_class_method :symbolize
    end
  end
end
