# frozen_string_literal: true

require "sequel"
require "fileutils"
require "securerandom"

module Tasku
  module Database
    DB_DIR = File.join(Dir.home, ".tasku")
    DB_PATH = File.join(DB_DIR, "tasks.db")

    def self.connect
      FileUtils.mkdir_p(DB_DIR)
      # Treat all stored datetime strings as UTC so comparisons with
      # cloud timestamps (which are always UTC) stay consistent.
      Sequel.database_timezone = :utc
      @db = Sequel.sqlite(DB_PATH)
      Sequel::Model.db = @db
      migrate
      @db
    end

    def self.db
      @db || connect
    end

    def self.migrate
      db.create_table? :tasks do
        primary_key :id
        String :name, null: false
        File :description
        String :project
        String :category
        Date :start_day
        Date :due_day
        String :model_name
        String :code
        String :priority, default: "none"
        String :status, default: "todo"
        String :tags
        Float :estimated_hours
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
      end

      if db.table_exists?(:tasks) && !db.schema(:tasks).map(&:first).include?(:code)
        db.alter_table(:tasks) { add_column :code, String }
      end

      if db.table_exists?(:tasks) && !db.schema(:tasks).map(&:first).include?(:uuid)
        db.alter_table(:tasks) { add_column :uuid, String }
        # Backfill existing tasks with UUIDs
        db[:tasks].where(uuid: nil).each do |row|
          db[:tasks].where(id: row[:id]).update(uuid: SecureRandom.uuid)
        end
      end

      db.create_table? :projects do
        String :name, primary_key: true
        String :colour
      end
    end
  end
end
