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

    def initialize
      @internal_token        = ENV.fetch("MCP_INTERNAL_TOKEN", SecureRandom.hex(32))
      @excluded_columns      = %w[created_at updated_at]
      @mount_path            = "/mcp"
      @auto_append_route     = true
      @excluded_tool_methods = []
    end
  end
end
