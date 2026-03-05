# frozen_string_literal: true

require "rails"

module MonkeyMcp
  class Engine < ::Rails::Engine
    # Reset registry on each code reload to avoid duplicate registrations
    config.to_prepare do
      MonkeyMcp::Registry.reset!
    end

    # Append POST /mcp route to the host application after initialization
    config.after_initialize do |app|
      app.routes.append do
        post "/mcp", to: "monkey_mcp/mcp#handle"
      end
    end
  end
end
