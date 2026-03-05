# frozen_string_literal: true

module MonkeyMcp
  # Include in ApplicationController to get MCP internal request protection.
  #
  # Usage:
  #   class ApplicationController < ActionController::Base
  #     include MonkeyMcp::ControllerHelpers
  #
  #     before_action :require_login
  #     protect_with_internal_token! :require_login
  #   end
  #
  # This calls `skip_before_action :require_login, if: :mcp_internal_request?`
  # so the auth callback is bypassed for internal MCP subrequests.
  module ControllerHelpers
    extend ActiveSupport::Concern

    class_methods do
      # Skip the given before_action callbacks for internal MCP subrequests.
      # Must be called after the before_action declarations.
      def protect_with_internal_token!(*callback_names)
        callback_names.each do |name|
          skip_before_action name, if: :mcp_internal_request?
        end
      end
    end

    private

    # Returns true when the request carries a valid MCP internal token.
    # Memoized per request to avoid repeated string comparison.
    def mcp_internal_request?
      @_mcp_internal_request ||= begin
        token = request.headers["X-Mcp-Internal-Token"].to_s
        token.present? && ActiveSupport::SecurityUtils.secure_compare(
          token, MonkeyMcp.configuration.internal_token
        )
      end
    end
  end
end
