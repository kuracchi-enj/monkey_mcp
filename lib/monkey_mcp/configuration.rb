# frozen_string_literal: true

module MonkeyMcp
  class Configuration
    # Token used to authenticate internal MCP subrequests
    attr_accessor :internal_token

    # AR column names excluded from auto-generated input_schema
    attr_accessor :excluded_columns

    # URL path where the MCP endpoint is mounted (default: "/mcp")
    attr_accessor :mount_path

    # Whether the Engine automatically appends the /mcp route (default: true)
    # Set to false to manage the route manually in config/routes.rb
    attr_accessor :auto_append_route

    # Public method names that should never be registered as MCP tools,
    # even if they have a matching route (e.g. utility/helper actions)
    attr_accessor :excluded_tool_methods

    # Controls how tools/list responds.
    # :full    - return all registered tools (default, backward-compatible)
    # :dynamic - return only tool_search and call_proxy meta-tools
    def tool_listing_mode=(value)
      unless %i[full dynamic].include?(value)
        raise ArgumentError, "tool_listing_mode must be :full or :dynamic, got: #{value.inspect}"
      end

      @tool_listing_mode = value
    end

    def tool_listing_mode
      @tool_listing_mode
    end

    # Default maximum number of results returned by tool_search (default: 10)
    def max_search_results=(value)
      unless value.is_a?(Integer) && value > 0
        raise ArgumentError, "max_search_results must be a positive integer, got: #{value.inspect}"
      end

      @max_search_results = value
    end

    def max_search_results
      @max_search_results
    end

    # Hard upper limit on tool_search results, regardless of what the caller requests (default: 100)
    def max_tool_search_results=(value)
      unless value.is_a?(Integer) && value > 0
        raise ArgumentError, "max_tool_search_results must be a positive integer, got: #{value.inspect}"
      end

      @max_tool_search_results = value
    end

    def max_tool_search_results
      @max_tool_search_results
    end

    # Target response-time threshold for tool_search in milliseconds (default: 1000)
    def search_timeout_ms=(value)
      unless value.is_a?(Integer) && value > 0
        raise ArgumentError, "search_timeout_ms must be a positive integer, got: #{value.inspect}"
      end

      @search_timeout_ms = value
    end

    def search_timeout_ms
      @search_timeout_ms
    end

    def initialize
      @internal_token           = ENV.fetch("MCP_INTERNAL_TOKEN", SecureRandom.hex(32))
      @excluded_columns         = %w[created_at updated_at]
      @mount_path               = "/mcp"
      @auto_append_route        = true
      @excluded_tool_methods    = []
      @tool_listing_mode        = :full
      @max_search_results       = 10
      @max_tool_search_results  = 100
      @search_timeout_ms        = 1000
    end
  end
end
