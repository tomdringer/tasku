# frozen_string_literal: true

require "thor"
require "pastel"
require "tty-prompt"

require_relative "tasku/version"
require_relative "tasku/database"
Tasku::Database.connect
require_relative "tasku/task"
require_relative "tasku/project"
require_relative "tasku/config"
require_relative "tasku/output/terminal"
require_relative "tasku/cli"
begin
  require_relative "tasku/tui/app"
rescue LoadError
  # TUI not available in this build
end
