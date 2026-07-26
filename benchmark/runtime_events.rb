#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require_relative "../lib/ibex/runtime"

module RuntimeEventConstructionCounts
  TABLES = {
    format_version: Ibex::Runtime::PARSER_TABLE_FORMAT_VERSION,
    tokens: { ITEM: 2 },
    token_names: { 0 => "$eof", 1 => "error", 2 => "ITEM" },
    actions: [{ 2 => [:shift, 1] }, { 0 => [:reduce, 0] }, { 0 => [:accept] }],
    gotos: [{ 3 => 2 }, {}, {}],
    productions: [{ lhs: 3, length: 1 }]
  }.freeze

  @counts = { "event" => 0, "value_summary" => 0, "location_summary" => 0 }

  class Parser < Ibex::Runtime::Parser
    def self.parser_tables = TABLES

    def initialize
      super
      @tokens = [[:ITEM, "value", { file: "benchmark", line: 1, column: 1 }]]
    end

    def next_token = @tokens.shift
  end

  EVENT_COUNTER = Module.new do
    define_method(:new) do |**arguments|
      RuntimeEventConstructionCounts.increment("event")
      super(**arguments)
    end
  end

  SANITIZER_COUNTER = Module.new do
    define_method(:value) do |input|
      RuntimeEventConstructionCounts.increment("value_summary")
      super(input)
    end

    define_method(:location) do |input|
      RuntimeEventConstructionCounts.increment("location_summary")
      super(input)
    end
  end

  module_function

  def increment(name)
    @counts[name] += 1
  end

  def snapshot
    @counts.transform_values(&:itself)
  end

  def reset
    @counts.transform_values! { 0 }
  end
end

Ibex::Runtime::Event.singleton_class.prepend(RuntimeEventConstructionCounts::EVENT_COUNTER)
Ibex::Runtime::EventSanitizer.singleton_class.prepend(RuntimeEventConstructionCounts::SANITIZER_COUNTER)

RuntimeEventConstructionCounts::Parser.new.do_parse
without_observer = RuntimeEventConstructionCounts.snapshot
RuntimeEventConstructionCounts.reset

parser = RuntimeEventConstructionCounts::Parser.new
parser.observe { |_event| nil }
parser.do_parse
with_observer = RuntimeEventConstructionCounts.snapshot

puts JSON.pretty_generate(
  "benchmark" => "runtime_event_construction_counts",
  "without_observer" => without_observer,
  "with_observer" => with_observer
)
