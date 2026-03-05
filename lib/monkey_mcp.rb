# frozen_string_literal: true

require "securerandom"
require "active_support"
require "active_support/core_ext/string/inflections"
require "active_support/concern"
require "active_support/security_utils"

require_relative "monkey_mcp/version"
require_relative "monkey_mcp/configuration"
require_relative "monkey_mcp/registry"
require_relative "monkey_mcp/schema_builder"
require_relative "monkey_mcp/toolable"
require_relative "monkey_mcp/mcp_controller"
require_relative "monkey_mcp/engine"

module MonkeyMcp
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end
  end
end
