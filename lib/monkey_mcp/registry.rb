# frozen_string_literal: true

module MonkeyMcp
  # Thread-safe registry that holds all registered MCP tool definitions.
  class Registry
    @tools = {}
    @mutex = Mutex.new

    class << self
      def register(name:, description:, input_schema:, controller:, action:)
        @mutex.synchronize do
          @tools[name] = {
            name: name,
            description: description,
            input_schema: input_schema,
            controller: controller,
            action: action
          }
        end
      end

      def all
        @mutex.synchronize { @tools.values.dup }
      end

      def find(name)
        @mutex.synchronize { @tools[name] }
      end

      # Called on Rails reloader to avoid duplicate registrations
      def reset!
        @mutex.synchronize { @tools.clear }
      end
    end
  end
end
