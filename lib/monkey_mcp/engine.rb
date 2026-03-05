# frozen_string_literal: true

require "rails"

module MonkeyMcp
  class Engine < ::Rails::Engine
    # Reset registry on each code reload to avoid duplicate registrations
    config.to_prepare do
      MonkeyMcp::Registry.reset!
    end

    # Append POST /mcp route once — guard against duplicate appends on reload
    config.after_initialize do |app|
      next if app.routes.routes.any? { |r| r.defaults[:controller] == "monkey_mcp/mcp" }

      app.routes.append do
        post "/mcp", to: "monkey_mcp/mcp#handle"
      end
    end
  end
end
