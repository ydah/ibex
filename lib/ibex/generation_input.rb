# frozen_string_literal: true
# rbs_inline: enabled

require "digest"

module Ibex
  # Digest and identity of source bytes actually consumed by one generation.
  class GenerationInput
    attr_reader :path #: String
    attr_reader :sha256 #: String
    attr_reader :bytesize #: Integer
    attr_reader :dev #: Integer
    attr_reader :ino #: Integer
    attr_reader :access_paths #: Array[String]

    # @rbs (String path, String source, ?access_path: String) -> void
    def initialize(path, source, access_path: path)
      @path = File.realpath(path).freeze
      stat = File.stat(@path)
      @sha256 = Digest::SHA256.hexdigest(source).freeze
      @bytesize = source.bytesize
      @dev = stat.dev
      @ino = stat.ino
      @access_paths = [File.expand_path(access_path)] #: Array[String]
    end

    # Record another lexical path that supplied these canonical bytes.
    # @rbs (String path) -> void
    def add_access_path(path)
      expanded = File.expand_path(path)
      @access_paths << expanded unless @access_paths.include?(expanded)
    end

    # @rbs () -> Hash[String, untyped]
    def to_h
      { "path" => @path, "sha256" => @sha256, "bytesize" => @bytesize }
    end

    # Detect content changes even when size and timestamps are preserved.
    # @rbs () -> bool
    def current?
      source = File.binread(@path)
      stat = File.stat(@path)
      lexical_paths_current? && stat.dev == @dev && stat.ino == @ino &&
        source.bytesize == @bytesize && Digest::SHA256.hexdigest(source) == @sha256
    rescue SystemCallError
      false
    end

    private

    # @rbs () -> bool
    def lexical_paths_current?
      @access_paths.all? { |path| File.realpath(path) == @path }
    end
  end
end
