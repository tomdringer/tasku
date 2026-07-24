# frozen_string_literal: true

require_relative "database"

module Tasku
  class Project < Sequel::Model(:projects)
    unrestrict_primary_key

    def self.colour_map
      all.each_with_object({}) { |p, h| h[p.name] = p.colour }
    end
  end
end
