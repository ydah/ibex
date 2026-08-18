# frozen_string_literal: true
# rbs_inline: enabled

module Ibex
  # One fully rendered file in a parser generation.
  class Artifact
    attr_reader :kind #: Symbol
    attr_reader :path #: String
    attr_reader :content #: String
    attr_reader :mode #: Integer?

    # @rbs (kind: Symbol, path: String, content: String, ?mode: Integer?) -> void
    def initialize(kind:, path:, content:, mode: nil)
      raise ArgumentError, "artifact path must not be empty" if path.empty?

      @kind = kind
      @path = path.dup.freeze
      @content = content.dup.freeze
      @mode = mode
      freeze
    end
  end

  # A generation's rendered outputs before any target is changed.
  class ArtifactSet < Array
    # @rbs (kind: Symbol, path: String, content: String, ?mode: Integer?) -> Artifact
    def add(kind:, path:, content:, mode: nil)
      artifact = Artifact.new(kind: kind, path: path, content: content, mode: mode)
      self << artifact
      artifact
    end
  end
end
