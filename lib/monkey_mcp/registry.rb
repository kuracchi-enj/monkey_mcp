# frozen_string_literal: true

module MonkeyMcp
  # Thread-safe registry that holds all registered MCP tool definitions.
  # input_schema can be a Hash or a Proc (evaluated lazily on first access).
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
        @mutex.synchronize { @tools.values.map { |t| resolve(t) } }
      end

      def find(name)
        @mutex.synchronize { (t = @tools[name]) ? resolve(t) : nil }
      end

      # Called by Engine on each Rails reload to avoid duplicate registrations
      def reset!
        @mutex.synchronize { @tools.clear }
      end

      private

      # Evaluate a lazily-defined input_schema Proc, or return a Hash as-is
      def resolve(tool)
        schema = tool[:input_schema]
        schema = schema.call if schema.respond_to?(:call)
        tool.merge(input_schema: schema)
      end
    end
  end
end
