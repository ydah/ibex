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
  class ArtifactSet
    # @rbs! include Enumerable[Artifact]
    # @rbs skip
    include Enumerable

    # @rbs () -> void
    def initialize
      @artifacts = [] #: Array[Artifact]
    end

    # @rbs (kind: Symbol, path: String, content: String, ?mode: Integer?) -> Artifact
    def add(kind:, path:, content:, mode: nil)
      artifact = Artifact.new(kind: kind, path: path, content: content, mode: mode)
      @artifacts << artifact
      artifact
    end

    # @rbs!
    #   def each: () -> Enumerator[Artifact, ArtifactSet]
    #           | () { (Artifact) -> void } -> ArtifactSet
    # @rbs skip
    def each(&block)
      return enum_for(:each) unless block

      @artifacts.each(&block)
      self
    end

    # @rbs () -> Array[Artifact]
    def to_a
      @artifacts.dup
    end

    # @rbs () -> bool
    def empty?
      @artifacts.empty?
    end
  end
end
