# frozen_string_literal: true

module Ibex
  module Codegen
    # Serializes immutable example-keyed error records into generated Ruby.
    module RubyErrorMessages
      private

      # @rbs () -> String
      def error_messages_literal
        # @type self: Ruby
        return "{}" if @error_messages.empty?

        entries = @error_messages.map { |state, message| "#{state} => #{error_message_literal(message)}" }
        "{ #{entries.join(', ')} }"
      end

      # @rbs (String | { id: String, message: String } message) -> String
      def error_message_literal(message)
        return message.inspect unless message.is_a?(Hash)

        error_id = message.fetch(:id)
        text = message.fetch(:message)
        "{ id: #{error_id.inspect}, message: #{text.inspect} }.freeze"
      end
    end
  end
end
