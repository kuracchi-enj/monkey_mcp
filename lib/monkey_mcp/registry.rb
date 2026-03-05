# frozen_string_literal: true

module MonkeyMcp
  # Thread-safe registry that holds all registered MCP tool definitions.
  #
  # Both input_schema and route_check can be a Proc (evaluated lazily on first access).
  # Tools whose route_check returns false are silently excluded from all/find.
  class Registry
    @tools = {}
    @mutex = Mutex.new

    class << self
      def register(name:, description:, input_schema:, route_check:, controller:, action:)
        @mutex.synchronize do
          @tools[name] = {
            name:        name,
            description: description,
            input_schema: input_schema,
            route_check: route_check,
            controller:  controller,
            action:      action
          }
        end
      end

      def all
        @mutex.synchronize { @tools.values.filter_map { |t| resolve(t) } }
      end

      def find(name)
        @mutex.synchronize { (t = @tools[name]) ? resolve(t) : nil }
      end

      # Called by Engine on each Rails reload to avoid duplicate registrations
      def reset!
        @mutex.synchronize { @tools.clear }
      end

      private

      # Resolve a tool entry: evaluate lazy Procs, return nil if route doesn't exist
      def resolve(tool)
        route_check = tool[:route_check]
        return nil if route_check.respond_to?(:call) && !route_check.call

        schema = tool[:input_schema]
        schema = schema.call if schema.respond_to?(:call)

        tool.merge(input_schema: schema)
      end
    end
  end
end
