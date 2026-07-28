# frozen_string_literal: true

module CSTConstructionProbe
  module_function

  def measure(cst_parser, input)
    { red_green_cst: construction_counts(cst_parser, input) }
  end

  def construction_counts(parser_class, input)
    classes = {
      Ibex::Runtime::CST::GreenNode => :nodes,
      Ibex::Runtime::CST::GreenToken => :tokens
    }
    counts = { nodes: 0, tokens: 0 }
    trace = TracePoint.new(:call) do |point|
      name = classes[point.defined_class]
      counts[name] += 1 if name && point.method_id == :initialize
    end
    trace.enable do
      CSTBenchmark.parse_once(parser_class, input)
    end
    counts.merge(node_and_token_constructions: counts.fetch(:nodes) + counts.fetch(:tokens))
  end
end
