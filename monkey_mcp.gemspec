# frozen_string_literal: true

require_relative "lib/monkey_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "monkey_mcp"
  spec.version = MonkeyMcp::VERSION
  spec.authors = ["kensuke"]
  spec.email = ["kurapontoonakama0225@gmail.com"]

  spec.summary = "MCP (Model Context Protocol) server for Rails applications"
  spec.description = "Automatically exposes Rails controller actions as MCP tools via JSON-RPC 2.0."
  spec.homepage = "https://github.com/kuracchi-enj/monkey_mcp"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 7.0"
  spec.add_dependency "actionpack", ">= 7.0"
  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "rack", ">= 2.0"
end
