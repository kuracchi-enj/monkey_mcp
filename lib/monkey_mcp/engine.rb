# frozen_string_literal: true

require "rails"

module MonkeyMcp
  class Engine < ::Rails::Engine
    # Reset registry on each code reload to avoid duplicate registrations
    config.to_prepare do
      MonkeyMcp::Registry.reset!
    end

    # Conditionally append the MCP route based on auto_append_route config.
    # Uses mount_path from configuration. Guard prevents duplicate registration on reload.
    config.after_initialize do |app|
      next unless MonkeyMcp.configuration.auto_append_route

      mount_path = MonkeyMcp.configuration.mount_path
      next if app.routes.routes.any? { |r| r.defaults[:controller] == "monkey_mcp/mcp" }

      app.routes.append do
        post mount_path, to: "monkey_mcp/mcp#handle"
      end
    end
  end
end
