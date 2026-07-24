# frozen_string_literal: true

require "json"
require "fileutils"

module Tasku
  class Config
    CONFIG_PATH = File.join(Dir.home, ".tasku", "config.json")

    VALID_KEYS = {
      "list_spacing" => {
        values: %w[compact spacious],
        default: "compact",
        description: "Row spacing in task list"
      },
      "bar_project" => {
        values: %w[on off],
        default: "on",
        description: "Show project colour segment in row bar"
      },
      "bar_priority" => {
        values: %w[on off],
        default: "on",
        description: "Show priority colour segment in row bar"
      },
      "bar_status" => {
        values: %w[on off],
        default: "on",
        description: "Show status colour segment in row bar"
      }
    }.freeze

    def self.get(key)
      all[key] || VALID_KEYS.dig(key, :default)
    end

    def self.set(key, value)
      current = all
      current[key] = value
      FileUtils.mkdir_p(File.dirname(CONFIG_PATH))
      File.write(CONFIG_PATH, JSON.pretty_generate(current))
    end

    def self.all
      return {} unless File.exist?(CONFIG_PATH)

      JSON.parse(File.read(CONFIG_PATH))
    rescue JSON::ParserError
      {}
    end
  end
end
