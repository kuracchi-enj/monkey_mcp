# frozen_string_literal: true

module MonkeyMcp
  # Thread-safe registry that holds all registered MCP tool definitions.
  #
  # Both input_schema and route_check can be a Proc (evaluated lazily on first access).
  # Route check results are cached to avoid repeated evaluation and log spam.
  # Tools whose route_check returns false are excluded and a warning is logged once.
  class Registry
    @tools             = {}
    @route_check_cache = {}
    @mutex             = Mutex.new

    class << self
      def register(name:, description:, input_schema:, route_check:, controller:, action:)
        @mutex.synchronize do
          @tools[name] = {
            name:         name,
            description:  description,
            input_schema: input_schema,
            route_check:  route_check,
            controller:   controller,
            action:       action
          }
        end
      end

      def all
        @mutex.synchronize { @tools.values.filter_map { |t| resolve(t) } }
      end

      def find(name)
        @mutex.synchronize { (t = @tools[name]) ? resolve(t) : nil }
      end

      # Clear all tools and route-check cache (called on each Rails reload)
      def reset!
        @mutex.synchronize do
          @tools.clear
          @route_check_cache.clear
        end
      end

      private

      # Resolve a tool entry: evaluate lazy Procs, return nil if route doesn't exist.
      # Route check results are cached per tool name to avoid duplicate log warnings.
      def resolve(tool)
        route_check = tool[:route_check]
        if route_check.respond_to?(:call)
          route_ok = @route_check_cache.fetch(tool[:name]) do
            result = route_check.call
            unless result
              warn_missing_route(tool)
            end
            @route_check_cache[tool[:name]] = result
          end
          return nil unless route_ok
        end

        schema = tool[:input_schema]
        schema = schema.call if schema.respond_to?(:call)

        tool.merge(input_schema: schema)
      end

      def warn_missing_route(tool)
        logger = defined?(Rails) ? Rails.logger : nil
        msg = "[MonkeyMcp] Tool '#{tool[:name]}' excluded: " \
              "no route matches #{tool[:controller]}##{tool[:action]}. " \
              "Add a route or set it in configuration.excluded_tool_methods."
        logger ? logger.warn(msg) : warn(msg)
      end
    end
  end
end
