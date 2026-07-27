# frozen_string_literal: true
# rbs_inline: enabled

require_relative "source_text" unless defined?(Ibex::Runtime::CST::SourceText)
require_relative "syntax_token" unless defined?(Ibex::Runtime::CST::SyntaxToken)

module Ibex
  module Runtime
    module CST
      # Lazy Red navigation facade for one Green node occurrence.
      class SyntaxNode # rubocop:disable Metrics/ClassLength -- navigation and compatibility form one facade.
        # @rbs! type element = SyntaxNode | SyntaxToken
        # @rbs! include Enumerable[element]
        # @rbs skip
        include Enumerable

        attr_reader :green #: GreenNode
        attr_reader :parent #: SyntaxNode?
        attr_reader :index #: Integer
        attr_reader :offset #: Integer
        attr_reader :kinds #: Kind
        attr_reader :trivia_policy #: Symbol
        attr_reader :source_text #: SourceText

        # @rbs (green: GreenNode, kinds: Kind, ?parent: SyntaxNode?, ?index: Integer, ?offset: Integer,
        #   ?trivia_policy: Symbol, ?source_text: SourceText?) -> void
        def initialize(green:, kinds:, parent: nil, index: 0, offset: 0, trivia_policy: :leading, source_text: nil)
          @green = green
          @kinds = kinds
          @parent = parent
          @index = index
          @offset = offset
          @trivia_policy = trivia_policy
          @source_text = source_text || SourceText.new(root_source)
          @children = Array.new(@green.children.length) #: Array[element?]
        end

        # @rbs () -> Integer
        def kind = @green.kind

        # @rbs () -> String
        def kind_name = @kinds.name(kind)

        # Compatibility name for the physical grammar symbol.
        # @rbs () -> String
        def symbol = @kinds.name(@kinds.nonterminal_of(kind))

        # Green kinds replace occurrence-local production ids. Keep the legacy
        # key and reader with the historical synthetic sentinel.
        # @rbs () -> Integer
        def production_id = -1

        # @rbs () -> Array[element]
        def children
          @green.children.each_index.map { |child_index| child_at(child_index) }.freeze
        end

        # @rbs!
        #   def each: () -> Enumerator[element, self]
        #           | () { (element) -> void } -> self
        # @rbs skip
        def each(&block)
          return enum_for(:each) unless block

          children.each(&block)
          self
        end

        # @rbs (Integer child_index) -> element
        def child_at(child_index)
          cached = @children.fetch(child_index)
          return cached if cached

          green_child = @green.children.fetch(child_index)
          child_offset = offset_for(child_index)
          value = if green_child.is_a?(GreenNode)
                    self.class.new(
                      green: green_child, kinds: @kinds, parent: self, index: child_index,
                      offset: child_offset, trivia_policy: @trivia_policy, source_text: @source_text
                    )
                  else
                    SyntaxToken.new(green: green_child, parent: self, index: child_index, offset: child_offset)
                  end
          @children[child_index] = value
        end

        # @rbs () -> Array[SyntaxNode]
        def child_nodes
          nodes = [] #: Array[SyntaxNode]
          children.each { |child| nodes << child if child.is_a?(SyntaxNode) }
          nodes.freeze
        end

        # @rbs () -> Array[SyntaxToken]
        def tokens
          values = [] #: Array[SyntaxToken]
          descendants.each { |element| values << element if element.is_a?(SyntaxToken) }
          values.freeze
        end

        # @rbs () -> SyntaxToken?
        def first_token = tokens.first

        # @rbs () -> SyntaxToken?
        def last_token = tokens.last

        # @rbs () -> element?
        def next_sibling
          parent = @parent
          return unless parent

          parent.children[@index + 1]
        end

        # @rbs () -> element?
        def prev_sibling
          parent = @parent
          return unless parent
          return if @index.zero?

          parent.children[@index - 1]
        end

        # @rbs () -> Enumerator[SyntaxNode, void]
        def ancestors
          Enumerator.new do |yielder|
            ancestor = @parent
            while ancestor
              yielder << ancestor
              ancestor = ancestor.parent
            end
          end
        end

        # @rbs () -> Enumerator[element, void]
        def descendants
          Enumerator.new do |yielder|
            visit = lambda do |node|
              node.children.each do |child|
                yielder << child
                visit.call(child) if child.is_a?(SyntaxNode)
              end
            end
            visit.call(self)
          end
        end

        # @rbs () -> SyntaxNode
        def root
          parent = @parent
          parent ? parent.root : self
        end

        # @rbs () -> Range[Integer]
        def full_span
          ensure_coordinates!
          @offset...(@offset + @green.full_width)
        end

        # @rbs () -> Range[Integer]
        def span
          ensure_coordinates!
          (@offset + @green.leading_width)...(@offset + @green.full_width - @green.trailing_width)
        end

        # @rbs () -> Ibex::Location
        def location = @source_text.location(span)

        # @rbs () -> String
        def full_text = @green.to_source
        alias to_source full_text

        # @rbs () -> String
        def text
          start_offset = @green.leading_width
          width = @green.full_width - @green.leading_width - @green.trailing_width
          full_text.byteslice(start_offset, width) || "".b
        end

        # Compatibility view of file-tail trivia. The Red/Green layout owns it
        # on EOF rather than on the start node.
        # @rbs () -> Array[GreenTrivia]
        def trailing_trivia
          eof = compatibility_eof
          return (eof.green.leading + eof.green.trailing).freeze if eof

          token = last_token
          token ? token.green.trailing : []
        end

        # @rbs () -> bool
        def error? = @kinds.error?(kind)

        # @rbs () -> bool
        def missing? = false

        # @rbs () -> bool
        def contains_error? = @green.flags.anybits?(Flags::CONTAINS_ERROR)

        # @rbs () -> bool
        def incomplete_input? = @green.flags.anybits?(Flags::INCOMPLETE_INPUT)

        # @rbs (GreenNode | GreenToken | SyntaxNode | SyntaxToken replacement) -> SyntaxNode
        def replace_with(replacement) = Editing.replace(self, replacement)

        # @rbs (Integer child_index, GreenNode | GreenToken | SyntaxNode | SyntaxToken child) -> SyntaxNode
        def with_child(child_index, child)
          children = @green.children.dup
          children.fetch(child_index)
          children[child_index] = Editing.green_element(child)
          replace_with(
            GreenNode.new(
              kind: @green.kind, children: children,
              flags: @green.intrinsic_flags, annotations: @green.annotations
            )
          )
        end

        # @rbs (Integer child_index, GreenNode | GreenToken | SyntaxNode | SyntaxToken child) -> SyntaxNode
        def insert_child(child_index, child)
          raise IndexError, "child index #{child_index} is outside 0..#{@green.children.length}" unless
            child_index.between?(0, @green.children.length)

          children = @green.children.dup
          children.insert(child_index, Editing.green_element(child))
          replace_with(
            GreenNode.new(
              kind: @green.kind, children: children,
              flags: @green.intrinsic_flags, annotations: @green.annotations
            )
          )
        end

        # @rbs (Integer child_index) -> SyntaxNode
        def remove_child(child_index)
          children = @green.children.dup
          children.fetch(child_index)
          children.delete_at(child_index)
          replace_with(
            GreenNode.new(
              kind: @green.kind, children: children,
              flags: @green.intrinsic_flags, annotations: @green.annotations
            )
          )
        end

        # @rbs (SyntaxAnnotation annotation) -> SyntaxNode
        def annotate(annotation)
          raise TypeError, "annotation must be a SyntaxAnnotation" unless annotation.is_a?(SyntaxAnnotation)
          return root if @green.annotations.include?(annotation)

          replace_with(
            GreenNode.new(
              kind: @green.kind, children: @green.children,
              flags: @green.intrinsic_flags, annotations: @green.annotations + [annotation]
            )
          )
        end

        # @rbs (SyntaxAnnotation annotation) -> Enumerator[SyntaxNode, void]
        def annotated(annotation)
          Enumerator.new do |yielder|
            visit = lambda do |node|
              yielder << node if node.green.annotations.include?(annotation)
              node.child_nodes.each { |child| visit.call(child) }
            end
            visit.call(self)
          end
        end

        # Find the full-span-owning token for a byte offset.
        # @rbs (Integer source_offset) -> SyntaxToken?
        def token_at(source_offset)
          ensure_coordinates!
          return unless source_offset >= @offset && source_offset < @offset + @green.full_width

          node = self
          loop do
            child = node.child_covering_offset(source_offset)
            return unless child
            return child if child.is_a?(SyntaxToken)

            node = child
          end
        end

        # Return the smallest syntax element whose full span covers a range.
        # @rbs (Range[Integer] range) -> element?
        def covering(range)
          ensure_coordinates!
          start_offset, end_offset = normalize_range(range)
          return unless covers_offsets?(start_offset, end_offset)

          node = self
          loop do
            child = node.children.find do |candidate|
              candidate_start = candidate.offset
              candidate_end = candidate.offset + candidate.green.full_width
              candidate_start <= start_offset && candidate_end >= end_offset
            end
            return node unless child
            return child if child.is_a?(SyntaxToken)

            node = child
          end
        end

        # @rbs (kind: Integer | String | Symbol) -> Enumerator[element, void]
        def find(kind:)
          expected = kind.is_a?(Integer) ? kind : @kinds.fetch(kind)
          Enumerator.new do |yielder|
            descendants.each { |element| yielder << element if element.kind == expected }
          end
        end

        # @rbs () -> Enumerator[element, void]
        # @rbs () { (element) -> void } -> self
        def each_error(&block)
          errors = Enumerator.new do |yielder|
            descendants.each do |element|
              yielder << element if element.error? || element.missing?
            end
          end #: Enumerator[element, void]
          return errors unless block

          errors.each(&block)
          self
        end

        # @rbs () { (Symbol, element) -> void } -> self
        def walk(&block)
          raise ArgumentError, "walk requires a block" unless block

          visit = lambda do |element|
            block.call(:enter, element)
            element.children.each { |child| visit.call(child) } if element.is_a?(SyntaxNode)
            block.call(:leave, element)
          end
          visit.call(self)
          self
        end

        # @rbs () -> Cursor
        def cursor = Cursor.new(self)

        # @rbs (SyntaxNode other) -> bool
        def same_node?(other)
          root.equal?(other.root) && @green.equal?(other.green) && @offset == other.offset
        end

        # @rbs (untyped other) -> bool
        def ==(other)
          other.is_a?(SyntaxNode) && @green == other.green
        end

        # @rbs () -> Array[element]
        def deconstruct = children

        # @rbs (Array[Symbol]?) -> Hash[Symbol, untyped]
        def deconstruct_keys(_keys)
          values = {
            kind: :node, symbol: symbol, production_id: production_id, children: children,
            location: location, trailing_trivia: trailing_trivia
          } #: Hash[Symbol, untyped]
          @kinds.fields(kind).each do |name, slot|
            index = slot.is_a?(Hash) ? slot.fetch(:index) : slot
            values[name.to_sym] = child_at(index)
          end
          values.freeze
        end

        # @rbs () -> Hash[Symbol, untyped]
        def to_h = deconstruct_keys(nil)

        protected

        # @rbs (Integer source_offset) -> element?
        def child_covering_offset(source_offset)
          children.find do |child|
            source_offset >= child.offset && source_offset < child.offset + child.green.full_width
          end
        end

        private

        # @rbs () -> SyntaxToken?
        def compatibility_eof
          if kind_name == "source_file"
            token = last_token
            return token if token&.kind_name == "$eof"
          end
          container = @parent
          return unless container
          return unless container.kind_name == "source_file"
          return unless @index.zero?

          token = container.last_token
          token if token&.kind_name == "$eof"
        end

        # @rbs () -> String
        def root_source
          parent = @parent
          parent ? parent.source_text.text : @green.to_source
        end

        # @rbs (Integer child_index) -> Integer
        def offset_for(child_index)
          @offset + @green.children.first(child_index).sum(&:full_width)
        end

        # @rbs () -> void
        def ensure_coordinates!
          return unless @trivia_policy == :drop

          raise TriviaDroppedError, "source coordinates are unavailable when CST trivia is dropped"
        end

        # @rbs (Range[Integer] range) -> [Integer, Integer]
        def normalize_range(range)
          value = [range.begin, range.end + (range.exclude_end? ? 0 : 1)] #: [Integer, Integer]
          value.freeze
        end

        # @rbs (Integer start_offset, Integer end_offset) -> bool
        def covers_offsets?(start_offset, end_offset)
          start_offset >= @offset && end_offset <= @offset + @green.full_width && end_offset >= start_offset
        end
      end
    end
  end
end
