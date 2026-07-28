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
    trace = call_tracepoint do |point|
      name = classes[point.defined_class]
      counts[name] += 1 if name && point.method_id == :initialize
    end
    return unavailable_counts unless trace

    trace.enable do
      CSTBenchmark.parse_once(parser_class, input)
    end
    counts.merge(node_and_token_constructions: counts.fetch(:nodes) + counts.fetch(:tokens))
  end

  def call_tracepoint(&block)
    TracePoint.new(:call, &block)
  rescue ArgumentError
    nil
  end

  def unavailable_counts
    { nodes: nil, tokens: nil, node_and_token_constructions: nil }
  end
end
