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
      },
      "col_project" => {
        values: %w[on off],
        default: "off",
        description: "Show project column in task list"
      },
      "col_priority" => {
        values: %w[on off],
        default: "on",
        description: "Show priority column in task list"
      },
      "col_status" => {
        values: %w[on off],
        default: "on",
        description: "Show status column in task list"
      },
      "col_due" => {
        values: %w[on off],
        default: "on",
        description: "Show due date column in task list"
      },
      "col_name_min" => {
        range: 10..200,
        default: "20",
        description: "Minimum width (chars) of the name column"
      },
      "col_priority_min" => {
        range: 4..40,
        default: "10",
        description: "Minimum width (chars) of the priority column"
      },
      "col_status_min" => {
        range: 4..40,
        default: "11",
        description: "Minimum width (chars) of the status column"
      },
      "col_due_min" => {
        range: 4..40,
        default: "19",
        description: "Minimum width (chars) of the due date column"
      }
    }.freeze

    # ── Cloud sync settings ────────────────────────────────────────────────
    CLOUD_URL_DEFAULT = "https://tasku.cloud".freeze

    def self.cloud_token
      cloud["token"]
    end

    def self.cloud_token=(value)
      save_cloud("token", value)
    end

    def self.cloud_url
      cloud["url"] || CLOUD_URL_DEFAULT
    end

    def self.cloud_url=(value)
      save_cloud("url", value)
    end

    def self.last_synced_at
      raw = cloud["last_synced_at"]
      raw ? Time.parse(raw).utc : nil
    rescue ArgumentError, TypeError
      nil
    end

    def self.last_synced_at=(time)
      save_cloud("last_synced_at", time&.utc&.iso8601)
    end

    def self.cloud_configured?
      !cloud_token.nil?
    end

    def self.get(key)
      all[key] || VALID_KEYS.dig(key, :default)
    end

    def self.get_int(key)
      get(key).to_i
    end

    def self.set(key, value)
      pastel = Pastel.new rescue nil
      meta = VALID_KEYS[key]
      raise ArgumentError, "Unknown key '#{key}'" unless meta

      if meta[:range]
        int = Integer(value) rescue nil
        raise ArgumentError, "Value must be an integer between #{meta[:range].min} and #{meta[:range].max}" unless int && meta[:range].include?(int)
        value = int.to_s
      elsif meta[:values]
        raise ArgumentError, "Invalid value '#{value}'. Valid: #{meta[:values].join(', ')}" unless meta[:values].include?(value)
      end

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

    def self.cloud
      all["cloud"] || {}
    end

    def self.save_cloud(key, value)
      current = all
      current["cloud"] ||= {}
      current["cloud"][key] = value
      FileUtils.mkdir_p(File.dirname(CONFIG_PATH))
      File.write(CONFIG_PATH, JSON.pretty_generate(current))
    end
    private_class_method :cloud, :save_cloud
  end
end
