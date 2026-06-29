# frozen_string_literal: true

require_relative "lib/tasku/version"

Gem::Specification.new do |spec|
  spec.name        = "tasku"
  spec.version     = Tasku::VERSION
  spec.authors     = ["Tom Dringer"]
  spec.summary     = "タスクリスト — a beautiful terminal task manager"
  spec.description = "Tasku is a terminal-based task manager with colour-coded priorities, status tracking, SQLite persistence, and a beautiful CLI interface."
  spec.homepage    = "https://github.com/tomdringer/tasku"
  spec.metadata    = {
    "homepage_uri" => "https://github.com/tomdringer/tasku",
    "source_code_uri" => "https://github.com/tomdringer/tasku",
    "changelog_uri" => "https://github.com/tomdringer/tasku/releases"
  }
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.bindir = "exe"
  spec.executables = ["tasku"]
  spec.require_paths = ["lib"]

  spec.files = Dir["lib/**/*", "exe/*"].reject { |f| f.start_with?("lib/tasku/tui") }

  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "sequel", "~> 5.0"
  spec.add_dependency "sqlite3", "~> 1.6"
end
