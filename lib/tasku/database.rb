# frozen_string_literal: true

require "sequel"
require "fileutils"

module Tasku
  module Database
    DB_DIR = File.join(Dir.home, ".tasku")
    DB_PATH = File.join(DB_DIR, "tasks.db")

    def self.connect
      FileUtils.mkdir_p(DB_DIR)
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
    end
  end
end
