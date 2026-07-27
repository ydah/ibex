# frozen_string_literal: true

module CSTIncrementalPropertyHarness
  Definition = Struct.new(:parser_class, :separator, keyword_init: true)

  class Document
    def self.random(separator, random)
      count = random.rand(2..8)
      numbers = Array.new(count) { random.rand(10).to_s }
      gaps = Array.new(count - 1) { valid_gap(separator, random) }
      new(separator, numbers, gaps)
    end

    def self.valid_gap(separator, random)
      whitespace = ["", " ", "\t"]
      "#{whitespace.fetch(random.rand(3))}#{separator}#{whitespace.fetch(random.rand(3))}"
    end

    attr_reader :source

    def initialize(separator, numbers, gaps)
      @separator = separator
      @numbers = numbers
      @gaps = gaps
      @source = render
    end

    def edit(random)
      before = @source
      mutate(random)
      @source = render
      minimal_edit(before, @source)
    end

    private

    def mutate(random)
      case random.rand(6)
      when 0 then replace_number(random)
      when 1 then replace_gap(random)
      when 2 then append_number(random)
      when 3 then prepend_number(random)
      when 4 then remove_last(random)
      when 5 then remove_first(random)
      end
    end

    def replace_number(random)
      replacement = random.rand(10).zero? ? "?" : random.rand(10).to_s
      @numbers[random.rand(@numbers.length)] = replacement
    end

    def replace_gap(random)
      index = random.rand(@gaps.length)
      @gaps[index] = if random.rand(8).zero?
                       " ? "
                     else
                       self.class.valid_gap(@separator, random)
                     end
    end

    def append_number(random)
      return replace_number(random) if @numbers.length >= 10

      @gaps << self.class.valid_gap(@separator, random)
      @numbers << random.rand(10).to_s
    end

    def prepend_number(random)
      return replace_number(random) if @numbers.length >= 10

      @numbers.unshift(random.rand(10).to_s)
      @gaps.unshift(self.class.valid_gap(@separator, random))
    end

    def remove_last(random)
      return replace_number(random) if @numbers.length <= 2

      @numbers.pop
      @gaps.pop
    end

    def remove_first(random)
      return replace_number(random) if @numbers.length <= 2

      @numbers.shift
      @gaps.shift
    end

    def render
      @numbers.each_with_index.with_object(+"") do |(number, index), text|
        text << @gaps.fetch(index - 1) if index.positive?
        text << number
      end
    end

    def minimal_edit(before, after)
      prefix = 0
      prefix += 1 while prefix < before.bytesize && prefix < after.bytesize &&
                        before.getbyte(prefix) == after.getbyte(prefix)
      suffix = 0
      suffix += 1 while suffix < before.bytesize - prefix && suffix < after.bytesize - prefix &&
                        before.getbyte(before.bytesize - suffix - 1) == after.getbyte(after.bytesize - suffix - 1)
      Ibex::Runtime::CST::TextEdit.new(
        start: prefix,
        delete_length: before.bytesize - prefix - suffix,
        insert_text: after.byteslice(prefix, after.bytesize - prefix - suffix) || ""
      )
    end
  end

  module_function

  def build(index:, random:)
    separator = ["+", ",", ";"].fetch(random.rand(3))
    source = grammar_source(index, separator, random)
    ast = Ibex::Frontend::Parser.new(source, file: "cst-incremental-property-#{index}.y").parse
    grammar = Ibex::Normalizer.new(ast).normalize
    automaton = Ibex::LALR::Builder.new(grammar).build
    namespace = Module.new
    namespace.module_eval(Ibex::Codegen::Ruby.new(automaton).generate, "cst_incremental_property.rb")
    Definition.new(parser_class: namespace.const_get(grammar.class_name), separator: separator)
  end

  def grammar_source(index, separator, random)
    recursion = random.rand(2).zero? ? "terms SEP term" : "term SEP terms"
    depth = random.rand(4)
    entry = depth.zero? ? "terms" : "layer_0"
    wrappers = Array.new(depth) do |layer|
      child = layer == depth - 1 ? "terms" : "layer_#{layer + 1}"
      "layer_#{layer}: #{child} { raise \"parser action executed\" }"
    end
    <<~GRAMMAR
      class CSTIncrementalPropertyParser#{index}
      pragma cst
      token NUM SEP
      lexer
        skip /[[:space:]]+/
        NUM /[0-9]/
        SEP '#{separator}'
      end
      rule
      start: #{entry} { raise "parser action executed" }
      #{wrappers.join("\n")}
      terms: #{recursion} { raise "parser action executed" }
           | term { raise "parser action executed" }
      term: NUM { raise "parser action executed" }
      end
    GRAMMAR
  end
end
