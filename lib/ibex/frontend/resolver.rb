# frozen_string_literal: true

module Ibex
  module Frontend
    # An actual filesystem read failure while resolving a grammar closure.
    class ResolutionIOError < Ibex::Error; end

    # Loads an explicit root grammar and resolves its extended-mode fragment graph.
    class Resolver
      GLOB_CHARACTERS = /[*?\[\]{}]/ #: Regexp
      WINDOWS_ABSOLUTE = %r{\A(?:[A-Za-z]:[\\/]|\\\\)} #: Regexp

      # @rbs @input_path: String
      # @rbs @mode: Symbol
      # @rbs @loader: SourceLoader
      # @rbs @root_path: String
      # @rbs @root_directory: String
      # @rbs @files: Array[String]
      # @rbs @visiting: Array[String]
      # @rbs @loaded: Hash[String, bool]
      # @rbs @include_chains: Hash[AST::Rule, Array[IR::source_provenance]]
      # @rbs @attempted_paths: Array[String]

      attr_reader :attempted_paths #: Array[String]

      # @rbs (String path, ?mode: Symbol, ?loader: SourceLoader) -> void
      def initialize(path, mode: :default, loader: SourceLoader.new)
        raise ArgumentError, "mode must be :default or :extended" unless %i[default extended].include?(mode)

        @input_path = path
        @mode = mode
        @loader = loader
        @attempted_paths = [File.expand_path(path)]
      end

      # @rbs () -> Resolution
      def resolve
        cached = @resolution
        return cached if cached

        prepare_resolution
        parsed_root = parse_root(@root_path)
        declarations, rules = expand_node(parsed_root, [])
        root = AST::Root.new(
          class_name: parsed_root.class_name, superclass: parsed_root.superclass,
          declarations: declarations, rules: rules, user_code: parsed_root.user_code, loc: parsed_root.loc,
          extended: parsed_root.extended, cst: parsed_root.cst, extended_loc: parsed_root.extended_loc
        )
        @loaded[@root_path] = true
        @visiting.pop
        @resolution = Resolution.new(
          root: root, root_path: @root_path, root_directory: @root_directory,
          files: @files, include_chains: @include_chains
        )
      end

      # @rbs () -> Array[String]
      def dependencies
        resolve.files
      end

      # Source bytes actually consumed by the parser, in resolution order.
      # @rbs () -> Array[GenerationInput]
      def source_records
        @loader.read_records
      end

      private

      # @rbs () -> void
      def prepare_resolution
        @root_path = canonical_root
        @root_directory = File.dirname(@root_path)
        @files = [@root_path] #: Array[String]
        @visiting = [@root_path] #: Array[String]
        @loaded = {} #: Hash[String, bool]
        chains = {} #: Hash[AST::Rule, Array[IR::source_provenance]]
        @include_chains = chains.compare_by_identity
        @attempted_paths = [File.expand_path(@input_path)]
      end

      # @rbs () -> String
      def canonical_root
        path = @loader.canonical_path(@input_path)
        raise Ibex::Error, "#{@input_path}:1:1: root grammar must be a file" unless @loader.file?(path)

        @loader.record_access(path, @input_path)
        path
      rescue SystemCallError => e
        raise ResolutionIOError, "#{@input_path}:1:1: cannot read root grammar: #{e.message}"
      end

      # @rbs (String path) -> AST::Root
      def parse_root(path)
        Parser.new(@loader.read(path), file: path, mode: @mode).parse
      rescue SystemCallError => e
        raise ResolutionIOError, "#{path}:1:1: cannot read grammar: #{e.message}"
      end

      # @rbs (String path) -> AST::Fragment
      def parse_fragment(path)
        Parser.new(@loader.read(path), file: path, mode: :extended).parse_fragment
      rescue SystemCallError => e
        raise ResolutionIOError, "#{path}:1:1: cannot read fragment: #{e.message}"
      end

      # @rbs (AST::Root | AST::Fragment node, Array[IR::source_provenance] chain) ->
      #   [Array[AST::declaration], Array[AST::Rule]]
      def expand_node(node, chain)
        declarations = [] #: Array[AST::declaration]
        rules = [] #: Array[AST::Rule]
        node.declarations.each do |declaration|
          if declaration.is_a?(AST::Include)
            included_declarations, included_rules = expand_include(declaration, chain)
            declarations.concat(included_declarations)
            rules.concat(included_rules)
          else
            declarations << declaration
          end
        end
        node.rules.each do |rule|
          @include_chains[rule] = chain
          rules << rule
        end
        [declarations, rules]
      end

      # @rbs (AST::Include include_node, Array[IR::source_provenance] chain) ->
      #   [Array[AST::declaration], Array[AST::Rule]]
      def expand_include(include_node, chain)
        target = canonical_include(include_node)
        reject_cycle(include_node, target)
        return [[], []] if @loaded[target]

        @files << target
        @visiting << target
        fragment = parse_fragment(target)
        next_chain = chain + [source_provenance(target)]
        declarations, rules = expand_node(fragment, next_chain)
        @visiting.pop
        @loaded[target] = true
        [declarations, rules]
      end

      # @rbs (AST::Include include_node) -> String
      def canonical_include(include_node)
        validate_include_path(include_node)
        candidate = File.expand_path(include_node.path, File.dirname(include_node.loc.file))
        @attempted_paths << candidate unless @attempted_paths.include?(candidate)
        canonical = @loader.canonical_path(candidate)
        unless @loader.file?(canonical)
          fail_include(include_node, "include path is not a file: #{include_node.path.inspect}")
        end

        unless inside_root?(canonical)
          message = "include resolves outside the root grammar directory: #{include_node.path.inspect}"
          fail_include(include_node, message)
        end
        @loader.record_access(canonical, candidate)
        canonical
      rescue Errno::ENOENT, Errno::ENOTDIR
        fail_include(include_node, "include file does not exist: #{include_node.path.inspect}")
      rescue SystemCallError => e
        message = "#{include_node.loc}: cannot read include #{include_node.path.inspect}: #{e.message}"
        raise ResolutionIOError, message
      end

      # @rbs (AST::Include include_node) -> void
      def validate_include_path(include_node)
        path = include_node.path
        fail_include(include_node, "include path must not be empty") if path.empty?
        fail_include(include_node, "include path must not contain NUL") if path.include?("\0")
        if path.start_with?("/") || path.match?(WINDOWS_ABSOLUTE)
          fail_include(include_node, "include path must be relative")
        end
        if path.split(%r{[\\/]}).include?("..")
          fail_include(include_node, "include path must not contain parent traversal")
        end
        return unless path.match?(GLOB_CHARACTERS)

        fail_include(include_node, "include path must not contain glob metacharacters")
      end

      # @rbs (String path) -> bool
      def inside_root?(path)
        directory = File.dirname(path)
        loop do
          return true if directory == @root_directory

          parent = File.dirname(directory)
          return false if parent == directory

          directory = parent
        end
      end

      # @rbs (AST::Include include_node, String target) -> void
      def reject_cycle(include_node, target)
        start = @visiting.index(target)
        return unless start

        cycle = @visiting.drop(start) + [target]
        fail_include(include_node, "include cycle: #{cycle.join(' -> ')}")
      end

      # @rbs (String file) -> IR::source_provenance
      def source_provenance(file)
        { file: file, root: @root_directory, byte_span: nil }
      end

      # @rbs (AST::Include include_node, String message) -> bot
      def fail_include(include_node, message)
        raise Ibex::Error, "#{include_node.loc}: #{message}"
      end
    end
  end
end
