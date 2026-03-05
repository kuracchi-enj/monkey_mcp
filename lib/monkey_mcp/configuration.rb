# frozen_string_literal: true

module MonkeyMcp
  class Configuration
    # Token used to authenticate internal MCP subrequests
    attr_accessor :internal_token

    # Attribute columns excluded from auto-generated input_schema
    attr_accessor :excluded_columns

    def initialize
      @internal_token = ENV.fetch("MCP_INTERNAL_TOKEN", SecureRandom.hex(32))
      @excluded_columns = %w[created_at updated_at]
    end
  end
end
