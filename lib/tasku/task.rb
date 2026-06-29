# frozen_string_literal: true

require_relative "database"

module Tasku
  class Task < Sequel::Model(:tasks)
    plugin :timestamps, update_on_create: true

    VALID_PRIORITIES = %w[none low medium high urgent].freeze
    VALID_STATUSES = %w[backlog todo in_progress done cancelled archived].freeze

    def before_validation
      super
      self.code = code.to_s.upcase[0, 3] if code
    end

    def validate
      super
      errors.add(:name, "cannot be empty") if name.nil? || name.strip.empty?
      if priority && !VALID_PRIORITIES.include?(priority)
        errors.add(:priority, "must be one of: #{VALID_PRIORITIES.join(', ')}")
      end
      if status && !VALID_STATUSES.include?(status)
        errors.add(:status, "must be one of: #{VALID_STATUSES.join(', ')}")
      end
    end

    def tag_list
      (tags || "").split(",").map(&:strip).reject(&:empty?)
    end

    def overdue?
      return false unless due_day
      due_day < Date.today && !%w[done cancelled].include?(status)
    end
  end

end
