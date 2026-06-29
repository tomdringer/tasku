# frozen_string_literal: true

require "thor"
require "pastel"
require "tty-prompt"

require_relative "tasku/version"
require_relative "tasku/database"
Tasku::Database.connect
require_relative "tasku/task"
require_relative "tasku/output/terminal"
require_relative "tasku/cli"
require_relative "tasku/tui/app"
